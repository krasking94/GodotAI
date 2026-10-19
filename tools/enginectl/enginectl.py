"""enginectl: отправляет команды плагину AI Bridge в открытом редакторе Godot,
запускает игру отдельным процессом с записью вывода в лог и собирает игру
в отдельный файл (project export).

Пример:  python tools/enginectl/enginectl.py doctor
Ответ всегда печатается как JSON. Код выхода 0, если status == "ok", иначе 1.
"""

import argparse
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

STATE_DIR = Path(".godot") / "ai_bridge"
CONNECTION_FILE = STATE_DIR / "connection.json"
RUN_LOG = STATE_DIR / "last_run.log"
RUN_INFO = STATE_DIR / "last_run.json"
SCREENSHOT_PNG = STATE_DIR / "screenshot.png"
SCREENSHOT_LOG = STATE_DIR / "screenshot.log"
TIMEOUT_SECONDS = 10
ERROR_PREFIXES = ("SCRIPT ERROR:", "ERROR:", "USER ERROR:")
WARNING_PREFIXES = ("WARNING:", "USER WARNING:", "SCRIPT WARNING:")


def find_project_root(start: Path) -> Path | None:
    for folder in [start, *start.parents]:
        if (folder / "project.godot").is_file():
            return folder
    return None


def fail(message: str) -> dict:
    return {"status": "error", "result": {}, "errors": [message], "warnings": [], "files": []}


def ok(result: dict, files: list | None = None, warnings: list | None = None) -> dict:
    return {"status": "ok", "result": result, "errors": [], "warnings": warnings or [], "files": files or []}


def read_connection(project: Path) -> dict | None:
    conn_path = project / CONNECTION_FILE
    if not conn_path.is_file():
        return None
    return json.loads(conn_path.read_text(encoding="utf-8"))


def send(project: Path, command: str, args: dict) -> dict:
    conn = read_connection(project)
    if conn is None:
        return fail(
            "Godot не на связи: не найден файл подключения. "
            "Откройте проект в редакторе и включите плагин AI Bridge "
            "(Проект → Настройки проекта → Плагины)."
        )
    request = json.dumps({"token": conn["token"], "command": command, "args": args}) + "\n"
    try:
        with socket.create_connection((conn["host"], conn["port"]), timeout=TIMEOUT_SECONDS) as sock:
            sock.sendall(request.encode("utf-8"))
            data = b""
            while not data.endswith(b"\n"):
                chunk = sock.recv(65536)
                if not chunk:
                    break
                data += chunk
    except OSError as exc:
        if not process_alive(conn.get("pid", 0)):
            return fail("Godot не на связи: файл подключения остался от уже закрытого редактора. "
                        "Откройте проект в Godot и повторите команду.")
        return fail(f"Godot не отвечает на {conn['host']}:{conn['port']} ({exc}). Редактор закрыт или плагин выключен?")
    if not data:
        return fail("Godot закрыл соединение без ответа")
    return json.loads(data.decode("utf-8"))


# ---------------------------------------------------------------------------
# Запуск игры отдельным процессом Godot
# ---------------------------------------------------------------------------

def looks_like_godot(path: Path) -> bool:
    """Файл Godot рядом с проектом: Godot_v4.7.2-stable_win64.exe, Godot_v4.7.2-stable_linux.x86_64 и т.п."""
    return (path.is_file() and path.name.lower().startswith("godot")
            and path.suffix.lower() in ("", ".exe", ".x86_64", ".arm64", ".x86_32"))


def find_godot(project: Path, explicit: str | None) -> Path | None:
    """Путь к Godot: --godot, переменная GODOT_EXE, файл подключения открытого редактора,
    `godot` в PATH, либо файл Godot* в папке проекта или на уровень выше."""
    candidates = [explicit, os.environ.get("GODOT_EXE")]
    conn = read_connection(project)
    if conn and conn.get("godot_exe"):
        candidates.append(conn["godot_exe"])
    candidates += [shutil.which("godot"), shutil.which("godot4")]
    for folder in (project, project.parent):
        candidates += sorted(str(p) for p in folder.glob("[Gg]odot*") if looks_like_godot(p))
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            exe = Path(candidate)
            # На Windows вывод игры печатает только console-версия, лежащая рядом.
            if exe.suffix.lower() == ".exe" and not exe.stem.endswith("_console"):
                console = exe.with_name(exe.stem + "_console.exe")
                if console.is_file():
                    return console
            return exe
    return None


def game_run(project: Path, options) -> dict:
    godot = find_godot(project, options.godot)
    if godot is None:
        conn = read_connection(project)
        hint = ("Редактор открыт, но файл подключения записан старой версией плагина: "
                "в Godot выберите «Проект → Перезагрузить текущий проект». Либо "
                if conn and not conn.get("godot_exe") else "")
        return fail(f"Не найден исполняемый файл Godot. {hint}откройте проект в редакторе, положите Godot в папку "
                    "проекта или на уровень выше, задайте переменную GODOT_EXE или укажите --godot <путь>")
    info = read_run_info(project)
    if info and info.get("running") and process_alive(info.get("pid", 0)):
        return fail(f"Игра уже запущена (pid {info['pid']}). Остановите её: enginectl game stop")

    cmd = [str(godot), "--path", str(project)]
    if options.headless:
        cmd.append("--headless")
    if options.scene:
        cmd.append(options.scene)
    test_args = test_arguments(options.test)
    if isinstance(test_args, dict):
        return test_args
    if test_args:
        # Всё после «--» Godot отдаёт скриптам как пользовательские аргументы (OS.get_cmdline_user_args).
        cmd.append("--")
        cmd.extend(test_args)
    (project / STATE_DIR).mkdir(parents=True, exist_ok=True)
    log_path = project / RUN_LOG
    started = time.time()
    with open(log_path, "w", encoding="utf-8") as log:
        log.write(f"# enginectl game run {datetime.now():%Y-%m-%d %H:%M:%S}\n# {' '.join(cmd)}\n")
        log.flush()
        creation = {"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP} if os.name == "nt" else {}
        try:
            proc = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, cwd=project, **creation)
        except OSError as exc:
            return fail(f"Не удалось запустить Godot: {exc}")
        write_run_info(project, {"pid": proc.pid, "command": cmd, "scene": options.scene or "<главная сцена>",
                                 "started": started, "running": True, "exit_code": None, "duration": None})
        if options.background:
            return ok({"pid": proc.pid, "running": True, "log_path": str(log_path),
                       "hint": "Остановить: enginectl game stop; ошибки: enginectl log get"})
        exit_code, stopped_by_us = wait_or_stop(proc, options.seconds)
    duration = round(time.time() - started, 2)
    write_run_info(project, {"pid": proc.pid, "command": cmd, "scene": options.scene or "<главная сцена>",
                             "started": started, "running": False, "exit_code": exit_code,
                             "duration": duration, "stopped_by_timeout": stopped_by_us})
    summary = parse_log(project)
    summary.update({"exit_code": exit_code, "duration": duration, "stopped_by_timeout": stopped_by_us,
                    "log_path": str(log_path)})
    warnings = []
    if exit_code not in (0, None) and not stopped_by_us:
        warnings.append(f"Игра завершилась с кодом {exit_code}")
    return ok(summary, warnings=warnings)


def test_arguments(items: list) -> list | dict:
    """--test кто=программа → ["--test-кто=программа", ...]; при ошибке возвращает ответ fail()."""
    result = []
    for item in items or []:
        who, sep, program = item.partition("=")
        if not sep or not who.strip() or not program.strip():
            return fail(f"--test ждёт вид КТО=ПРОГРАММА, например player=forward:1.5,enter:0.5 (получено: {item!r})")
        result.append(f"--test-{who.strip()}={program.strip()}")
    return result


def png_size(path: Path) -> tuple[int, int] | None:
    """Ширина и высота PNG из заголовка IHDR (без библиотек)."""
    try:
        with open(path, "rb") as f:
            head = f.read(24)
    except OSError:
        return None
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        return None
    return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")


def game_screenshot(project: Path, options) -> dict:
    """Запускает сцену отдельным процессом Godot со скриптом game/screenshot.gd и сохраняет кадр в PNG."""
    godot = find_godot(project, options.godot)
    if godot is None:
        return fail("Не найден исполняемый файл Godot: откройте проект в редакторе, положите Godot в папку проекта "
                    "или на уровень выше, задайте переменную GODOT_EXE или укажите --godot <путь>")
    if not (project / "game" / "screenshot.gd").is_file():
        return fail("В проекте нет game/screenshot.gd (скрипт, который делает снимок)")
    match = re.fullmatch(r"(\d{3,5})x(\d{3,5})", options.size or "")
    if not match:
        return fail(f"--size ждёт ШИРИНАxВЫСОТА, например 1280x720 (получено: {options.size!r})")
    width, height = int(match.group(1)), int(match.group(2))
    out = Path(options.out).expanduser() if options.out else project / SCREENSHOT_PNG
    if not out.is_absolute():
        out = Path.cwd() / out
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.unlink()
    test_args = test_arguments(options.test)
    if isinstance(test_args, dict):
        return test_args

    cmd = [str(godot), "--path", str(project), "--resolution", f"{width}x{height}", "--script", "res://game/screenshot.gd"]
    virtual_display = False
    if sys.platform.startswith("linux") and not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
        if shutil.which("xvfb-run") is None:
            return fail("Нет экрана (переменная DISPLAY пуста) и нет xvfb-run: окно для снимка открыть негде. "
                        "Установите пакет xvfb или запускайте там, где есть экран")
        # Виртуальный экран без видеокарты: программный OpenGL (llvmpipe) вместо Vulkan.
        cmd = ["xvfb-run", "-a", "-s", f"-screen 0 {width}x{height}x24"] + cmd + [
            "--rendering-driver", "opengl3", "--rendering-method", "gl_compatibility"]
        virtual_display = True
    user_args = [f"--shot-out={out}", f"--shot-after={options.after}"]
    if options.scene:
        user_args.append(f"--shot-scene={options.scene}")
    cmd += ["--"] + user_args + test_args

    (project / STATE_DIR).mkdir(parents=True, exist_ok=True)
    timeout = options.after + 90
    started = time.time()
    try:
        completed = subprocess.run(cmd, cwd=project, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    except subprocess.TimeoutExpired:
        return fail(f"Снимок не сделан: игра не завершилась за {timeout:.0f} с")
    except OSError as exc:
        return fail(f"Не удалось запустить Godot: {exc}")
    duration = round(time.time() - started, 2)
    log_path = project / SCREENSHOT_LOG
    log_path.write_text(f"# enginectl game screenshot {datetime.now():%Y-%m-%d %H:%M:%S}\n# {' '.join(cmd)}\n"
                        + completed.stdout.decode("utf-8", errors="replace"), encoding="utf-8")
    summary = parse_log(project, SCREENSHOT_LOG)
    # Шум виртуального экрана (нет звуковой карты, vsync) снимку не мешает.
    noise = ("ALSA", "vsync", "V-Sync", "snd_", "audio")

    def is_noise(entry: dict) -> bool:
        text = " ".join([entry["message"], *entry["details"]])
        return any(n in text for n in noise)

    summary["errors"] = [e for e in summary["errors"] if not is_noise(e)]
    summary["warnings"] = [w for w in summary["warnings"] if not is_noise(w)]
    summary["output"] = [line for line in summary["output"] if not line.startswith("ALSA lib")]
    size = png_size(out)
    if size is None:
        return {"status": "error", "result": {"exit_code": completed.returncode, "duration": duration,
                                              "log_path": str(log_path), "output": summary["output"][-20:]},
                "errors": [e["message"] for e in summary["errors"]] or [f"Файл {out} не появился (код выхода {completed.returncode})"],
                "warnings": [w["message"] for w in summary["warnings"]], "files": []}
    return ok({"path": str(out), "width": size[0], "height": size[1], "scene": options.scene or "<главная сцена>",
               "after": options.after, "virtual_display": virtual_display, "duration": duration,
               "exit_code": completed.returncode, "log_path": str(log_path), "output": summary["output"][-20:],
               "errors_in_game": summary["errors"], "hint": "Открой PNG и опиши, что видно; потом правь сцену"},
              files=[str(out)], warnings=[w["message"] for w in summary["warnings"]])


def wait_or_stop(proc: subprocess.Popen, seconds: float) -> tuple[int | None, bool]:
    try:
        return proc.wait(timeout=seconds), False
    except subprocess.TimeoutExpired:
        terminate(proc.pid)
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        return proc.returncode, True


def terminate(pid: int) -> None:
    if os.name == "nt":
        subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True)
    else:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass


def process_alive(pid: int) -> bool:
    if not pid:
        return False
    if os.name == "nt":
        out = subprocess.run(["tasklist", "/FI", f"PID eq {pid}"], capture_output=True, text=True).stdout
        return str(pid) in out
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def read_run_info(project: Path) -> dict | None:
    path = project / RUN_INFO
    if not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def write_run_info(project: Path, info: dict) -> None:
    (project / RUN_INFO).write_text(json.dumps(info, ensure_ascii=False, indent=2), encoding="utf-8")


# ---------------------------------------------------------------------------
# Сборка игры без редактора (экспорт)
# ---------------------------------------------------------------------------

EXPORT_PRESETS = Path("export_presets.cfg")
EXPORT_EXAMPLE = Path("tools") / "export_presets.example.cfg"
EXPORT_LOG = STATE_DIR / "export.log"
# Какой файл шаблона нужен каждой платформе; {mode} — debug или release.
TEMPLATE_FILES = {
    "Windows Desktop": "windows_{mode}_x86_64.exe",
    "Linux": "linux_{mode}.x86_64",
    "Android": "android_{mode}.apk",
}
TEMPLATES_HINT = ("шаблоны экспорта ставятся один раз: в Godot «Редактор → Управление шаблонами экспорта… → "
                  "Скачать и установить» (около 1,3 ГБ)")
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


def read_presets(project: Path) -> tuple[list, list]:
    """Пресеты из export_presets.cfg: [{name, platform, export_path, runnable, options}]. Если файла нет,
    он создаётся из tools/export_presets.example.cfg; об этом сообщает предупреждение (второй элемент)."""
    import configparser
    warnings = []
    cfg_path = project / EXPORT_PRESETS
    if not cfg_path.is_file():
        example = project / EXPORT_EXAMPLE
        if not example.is_file():
            return [], [f"Нет ни {EXPORT_PRESETS}, ни примера {EXPORT_EXAMPLE}"]
        # Имя файла сборки берётся из имени папки проекта (в примере стоит GodotAI), чтобы в другом
        # проекте игра не называлась GodotAI.exe; небуквенные имена заменяются на Game.
        game_name = project.resolve().name
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", game_name):
            game_name = "Game"
        cfg_path.write_text(example.read_text(encoding="utf-8").replace("/GodotAI.", f"/{game_name}."), encoding="utf-8")
        warnings.append(f"Файла {EXPORT_PRESETS} не было, создан из примера {EXPORT_EXAMPLE}, файл сборки «{game_name}» "
                        "(в репозиторий он не попадает; правится в «Проект → Экспорт»)")
    parser = configparser.ConfigParser(interpolation=None, strict=False, comment_prefixes=(";", "#"))
    parser.optionxform = str  # ключи вида binary_format/architecture не приводить к нижнему регистру
    try:
        parser.read(cfg_path, encoding="utf-8")
    except configparser.Error as exc:
        return [], [f"Не удалось разобрать {EXPORT_PRESETS}: {exc}"]

    def unquote(value: str) -> str:
        value = value.strip()
        return value[1:-1] if len(value) >= 2 and value[0] == value[-1] == '"' else value

    presets = []
    for section in parser.sections():
        match = re.fullmatch(r"preset\.(\d+)", section)
        if not match:
            continue
        options = {k: unquote(v) for k, v in parser.items(f"{section}.options")} if parser.has_section(f"{section}.options") else {}
        presets.append({"name": unquote(parser.get(section, "name", fallback="")),
                        "platform": unquote(parser.get(section, "platform", fallback="")),
                        "export_path": unquote(parser.get(section, "export_path", fallback="")),
                        "runnable": unquote(parser.get(section, "runnable", fallback="true")) == "true",
                        "options": options})
    return presets, warnings


def godot_version(godot: Path) -> str | None:
    """«4.7.2.stable» из вывода `Godot --version` (4.7.2.stable.official.ed1daf0bf); None, если не удалось."""
    try:
        out = subprocess.run([str(godot), "--version"], capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    match = re.search(r"(\d+\.\d+(?:\.\d+)?)\.([a-z0-9]+)", out)
    return f"{match.group(1)}.{match.group(2)}" if match else None


def templates_dir(version: str) -> Path:
    """Папка шаблонов экспорта Godot для этой версии (как в «Управление шаблонами экспорта»)."""
    if os.name == "nt":
        base = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming")) / "Godot"
    elif sys.platform == "darwin":
        base = Path.home() / "Library" / "Application Support" / "Godot"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")) / "godot"
    return base / "export_templates" / version


def check_template(godot: Path, platform: str, mode: str) -> tuple[str | None, dict]:
    """Проверяет, что для платформы установлен нужный шаблон. Возвращает (текст ошибки или None, сведения)."""
    version = godot_version(godot)
    info = {"godot_version": version, "templates_dir": None, "template_file": None}
    if version is None:
        return None, info  # версию не узнали — пусть проверяет сам Godot
    folder = templates_dir(version)
    info["templates_dir"] = str(folder)
    if not folder.is_dir():
        return f"Нет шаблонов экспорта для Godot {version} (ожидались в {folder}); {TEMPLATES_HINT}", info
    pattern = TEMPLATE_FILES.get(platform)
    if pattern is None:
        return None, info
    file = folder / pattern.format(mode=mode)
    info["template_file"] = str(file)
    if not file.is_file():
        return f"Нет шаблона {file.name} для платформы «{platform}» в {folder}; {TEMPLATES_HINT}", info
    return None, info


def project_export(project: Path, options) -> dict:
    presets, warnings = read_presets(project)
    if not presets and warnings:
        return fail(warnings[0])
    if options.list:
        return ok({"presets_file": str(project / EXPORT_PRESETS),
                   "presets": [{k: p[k] for k in ("name", "platform", "export_path", "runnable")} for p in presets],
                   "hint": "Собрать: enginectl project export --preset <имя> [--release] [--out путь]"}, warnings=warnings)
    if not options.preset:
        return fail("Укажите --preset <имя> (список: enginectl project export --list)")
    preset = next((p for p in presets if p["name"] == options.preset), None)
    if preset is None:
        names = ", ".join(p["name"] for p in presets) or "нет ни одного"
        return fail(f"Пресета «{options.preset}» нет в {EXPORT_PRESETS}. Есть: {names}")
    godot = find_godot(project, options.godot)
    if godot is None:
        return fail("Не найден исполняемый файл Godot: откройте проект в редакторе, положите Godot в папку проекта "
                    "или на уровень выше, задайте переменную GODOT_EXE или укажите --godot <путь>")
    mode = "release" if options.release else "debug"
    template_error, template_info = check_template(godot, preset["platform"], mode)
    if template_error:
        return fail(template_error)
    out_text = options.out or preset["export_path"]
    if not out_text:
        return fail(f"У пресета «{preset['name']}» не задан путь сборки: укажите --out <файл>")
    out = Path(out_text).expanduser()
    if not out.is_absolute():
        out = (Path.cwd() if options.out else project) / out
    out.parent.mkdir(parents=True, exist_ok=True)  # Godot требует, чтобы папка уже существовала

    cmd = [str(godot), "--headless", "--path", str(project), f"--export-{mode}", preset["name"], str(out)]
    (project / STATE_DIR).mkdir(parents=True, exist_ok=True)
    log_path = project / EXPORT_LOG
    started = time.time()
    try:
        completed = subprocess.run(cmd, cwd=project, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   timeout=options.timeout)
    except subprocess.TimeoutExpired:
        return fail(f"Сборка не завершилась за {options.timeout:.0f} с (см. {log_path})")
    except OSError as exc:
        return fail(f"Не удалось запустить Godot: {exc}")
    duration = round(time.time() - started, 2)
    text = ANSI_RE.sub("", completed.stdout.decode("utf-8", errors="replace"))
    log_path.write_text(f"# enginectl project export {datetime.now():%Y-%m-%d %H:%M:%S}\n# {' '.join(cmd)}\n" + text,
                        encoding="utf-8")
    summary = parse_log(project, EXPORT_LOG)
    # Строки прогресса ([ 96% ] savepack | Storing File: …) в ответе не нужны.
    output = [line for line in summary["output"] if not re.match(r"\s*\[\s*\d+%\s*\]|\[\s*DONE\s*\]", line)]
    if preset["platform"] != "Android":
        # Редактор при старте проверяет Android SDK и ворчит, если его нет; к сборке для Windows это не относится.
        output = [line for line in output if "Android" not in line]
    result = {"preset": preset["name"], "platform": preset["platform"], "mode": mode, "path": str(out),
              "duration": duration, "exit_code": completed.returncode, "log_path": str(log_path),
              "output": output[-15:], **template_info}
    errors = [e["message"] for e in summary["errors"]]
    if completed.returncode != 0 or not out.is_file():
        if not errors:
            errors = [f"Сборка не удалась (код выхода {completed.returncode}), файл {out.name} не появился"]
        if preset["platform"] == "Android" and any("SDK" in e or "keystore" in e.lower() or "Java" in e for e in errors):
            errors.append("Для Android нужны JDK 17 и Android SDK, пути задаются в «Редактор → Настройки редактора → "
                          "Экспорт → Android»; подробности в docs/EXPORT.md")
        return {"status": "error", "result": result, "errors": errors,
                "warnings": warnings + [w["message"] for w in summary["warnings"]], "files": []}
    result["size_mb"] = round(out.stat().st_size / (1024 * 1024), 1)
    extra = [str(p) for p in out.parent.iterdir() if p.is_file() and p != out and p.stat().st_mtime >= started - 1]
    result["also_written"] = extra
    result["hint"] = ("Запускается без редактора и без ИИ: откройте файл двойным щелчком"
                      if preset["platform"] != "Android" else "Скопируйте APK на телефон и установите (docs/EXPORT.md)")
    return ok(result, files=[str(out), *extra], warnings=warnings + [w["message"] for w in summary["warnings"]])


def game_stop(project: Path) -> dict:
    info = read_run_info(project)
    if not info or not info.get("running"):
        return fail("Нет запущенной игры (последний запуск уже завершён или его не было)")
    pid = info["pid"]
    alive = process_alive(pid)
    if alive:
        terminate(pid)
        for _ in range(50):
            if not process_alive(pid):
                break
            time.sleep(0.1)
    info.update({"running": False, "duration": round(time.time() - info["started"], 2), "stopped_by_user": True})
    write_run_info(project, info)
    return ok({"pid": pid, "was_running": alive, "stopped": not process_alive(pid)})


def game_status(project: Path) -> dict:
    info = read_run_info(project)
    if not info:
        return ok({"running": False, "last_run": None})
    running = bool(info.get("running")) and process_alive(info.get("pid", 0))
    if info.get("running") and not running:
        info["running"] = False
        write_run_info(project, info)
    return ok({"running": running, "last_run": info})


def parse_log(project: Path, log_file: Path = RUN_LOG) -> dict:
    """Разбирает лог запуска игры на ошибки, предупреждения и обычный вывод."""
    log_path = project / log_file
    if not log_path.is_file():
        return {"errors": [], "warnings": [], "output": [], "line_count": 0}
    errors, warnings, output = [], [], []
    current = None
    for raw in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.rstrip()
        if line.startswith("#"):
            continue
        if line.startswith(ERROR_PREFIXES):
            prefix = next(p for p in ERROR_PREFIXES if line.startswith(p))
            current = {"kind": prefix[:-1], "message": line[len(prefix):].strip(), "details": []}
            errors.append(current)
        elif line.startswith(WARNING_PREFIXES):
            prefix = next(p for p in WARNING_PREFIXES if line.startswith(p))
            current = {"kind": prefix[:-1], "message": line[len(prefix):].strip(), "details": []}
            warnings.append(current)
        elif line.startswith(" ") and current is not None:
            current["details"].append(line.strip())
        else:
            current = None
            if line:
                output.append(line)
    return {"errors": errors, "warnings": warnings, "output": output,
            "line_count": len(errors) + len(warnings) + len(output)}


def log_get(project: Path, options) -> dict:
    info = read_run_info(project)
    if not (project / RUN_LOG).is_file():
        return fail("Лога ещё нет: сначала enginectl game run")
    summary = parse_log(project)
    if not options.all:
        summary["output"] = summary["output"][-options.tail:]
    summary["last_run"] = info
    summary["log_path"] = str(project / RUN_LOG)
    return ok(summary)


# ---------------------------------------------------------------------------
# Разбор аргументов
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Установка моста в другой проект (новый или существующий)
# ---------------------------------------------------------------------------

SETUP_FILES = [  # что копируется: (откуда относительно этого репозитория, куда относительно цели)
    ("addons/ai_bridge/plugin.cfg", "addons/ai_bridge/plugin.cfg"),
    ("addons/ai_bridge/plugin.gd", "addons/ai_bridge/plugin.gd"),
    ("addons/ai_bridge/plugin.gd.uid", "addons/ai_bridge/plugin.gd.uid"),
    ("tools/enginectl/enginectl.py", "tools/enginectl/enginectl.py"),
    ("tools/export_presets.example.cfg", "tools/export_presets.example.cfg"),  # иначе project export в новом проекте не с чего начать
    ("tools/enginectl/examples/room.json", "tools/enginectl/examples/room.json"),
    ("tools/enginectl/examples/platformer2d.json", "tools/enginectl/examples/platformer2d.json"),
    ("game/room.gd", "game/room.gd"),
    ("game/player2d.gd", "game/player2d.gd"),
]
PLUGIN_ENTRY = 'res://addons/ai_bridge/plugin.cfg'
MIN_GITIGNORE = "# Служебные папки Godot\n.godot/\n.import/\nexport_presets.cfg\n\n# Сборки\nbuild/\n*.apk\n*.exe\n*.pck\n\n# Секреты\n.env\n*.keystore\n"


def setup_project(source: Path, options) -> dict:
    """Копирует плагин AI Bridge, enginectl и пример комнаты в другой проект Godot и включает плагин.
    Если в цели нет project.godot, создаётся новый пустой проект."""
    target = Path(options.target).expanduser()
    if not target.is_absolute():
        target = Path.cwd() / target
    target = target.resolve()
    if target == source.resolve():
        return fail("Это и есть исходный проект: укажите другую папку в --target")
    missing = [src for src, _ in SETUP_FILES if not (source / src).is_file()]
    if missing:
        return fail(f"В исходном проекте {source} нет файлов: {', '.join(missing)}")
    target.mkdir(parents=True, exist_ok=True)
    copied, updated, kept = [], [], []
    for src, dst in SETUP_FILES:
        src_path, dst_path = source / src, target / dst
        if dst_path.is_file():
            if dst_path.read_bytes() == src_path.read_bytes():
                kept.append(dst)
                continue
            if dst.startswith("game/") and not options.force:
                kept.append(dst)  # пример игры не затираем: его могли изменить
                continue
            updated.append(dst)
        else:
            copied.append(dst)
        dst_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src_path, dst_path)

    project_file = target / "project.godot"
    name = options.name or target.name
    created_project = False
    if project_file.is_file():
        text = project_file.read_text(encoding="utf-8")
        new_text = enable_plugin(text)
        if new_text != text:
            project_file.write_text(new_text, encoding="utf-8")
            plugin_state = "включён в существующем project.godot"
        else:
            plugin_state = "уже был включён"
    else:
        project_file.write_text(
            "; Engine configuration file.\n; It's best edited using the editor UI and not directly,\n"
            "; since the parameters that go here are not all obvious.\n;\n; Format:\n"
            ";   [section] ; section goes between []\n;   param=value ; assign values to parameters\n\n"
            "config_version=5\n\n[application]\n\n"
            f'config/name="{name}"\nconfig/features=PackedStringArray("4.7")\n\n'
            f'[editor_plugins]\n\nenabled=PackedStringArray("{PLUGIN_ENTRY}")\n', encoding="utf-8")
        created_project = True
        plugin_state = "включён в новом project.godot"
    gitignore = target / ".gitignore"
    if not gitignore.is_file():
        gitignore.write_text(MIN_GITIGNORE, encoding="utf-8")
        copied.append(".gitignore")
    return ok({"target": str(target), "project_created": created_project, "project_name": name if created_project else None,
               "plugin": plugin_state, "copied": copied, "updated": updated, "unchanged": kept,
               "next": [f"Откройте папку в Godot: Менеджер проектов → Импорт → {project_file}",
                        "В папке проекта: python tools/enginectl/enginectl.py doctor",
                        "Комната одной командой: python tools/enginectl/enginectl.py scene build --file tools/enginectl/examples/room.json",
                        "Запуск: python tools/enginectl/enginectl.py game run --scene res://scenes/room.tscn --seconds 5",
                        "2D-пример: scene build --file tools/enginectl/examples/platformer2d.json, затем game run --scene res://scenes/platformer2d.tscn"]},
              files=[str(target / f) for f in copied + updated])


def enable_plugin(text: str) -> str:
    """Добавляет плагин в [editor_plugins] enabled=PackedStringArray(...) файла project.godot, не трогая остальное."""
    if PLUGIN_ENTRY in text:
        return text
    section = re.search(r"^\[editor_plugins\]\s*$", text, flags=re.M)
    if section is None:
        return text.rstrip("\n") + f'\n\n[editor_plugins]\n\nenabled=PackedStringArray("{PLUGIN_ENTRY}")\n'
    enabled = re.search(r"^enabled=PackedStringArray\((.*)\)\s*$", text[section.end():], flags=re.M)
    if enabled is None:
        return text[:section.end()] + f'\n\nenabled=PackedStringArray("{PLUGIN_ENTRY}")' + text[section.end():]
    inner = enabled.group(1).strip()
    new_inner = f'"{PLUGIN_ENTRY}"' if inner == "" else f'{inner}, "{PLUGIN_ENTRY}"'
    start = section.end() + enabled.start(1)
    end = section.end() + enabled.end(1)
    return text[:start] + new_inner + text[end:]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="enginectl", description="Управление редактором Godot для ИИ")
    parser.add_argument("--project", type=Path, help="папка проекта Godot (по умолчанию ищется от текущей папки)")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("doctor", help="проверить, что Godot запущен и плагин отвечает")

    scene = sub.add_parser("scene", help="работа с открытой в редакторе сценой")
    scene_sub = scene.add_subparsers(dest="scene_command", required=True)
    inspect = scene_sub.add_parser("inspect", help="прочитать дерево открытой сцены")
    inspect.add_argument("--path", default=".", help="узел, с которого начать (по умолчанию корень сцены)")
    inspect.add_argument("--depth", type=int, default=-1, help="сколько уровней вниз показать (-1 = все)")
    apply = scene_sub.add_parser("apply", help="применить набор изменений (create/set/delete) через Undo/Redo")
    source = apply.add_mutually_exclusive_group(required=True)
    source.add_argument("--file", type=Path, help="JSON-файл со списком операций (или объект с полем ops)")
    source.add_argument("--ops", help="список операций прямо в строке JSON")
    apply.add_argument("--dry-run", action="store_true", help="только показать план, ничего не менять")
    scene_sub.add_parser("save", help="сохранить открытую сцену")
    open_cmd = scene_sub.add_parser("open", help="открыть существующую сцену в редакторе")
    open_cmd.add_argument("--path", required=True, help="например res://scenes/inspect_test.tscn")
    scene_sub.add_parser("undo", help="отменить последнее действие в открытой сцене (как Ctrl+Z)")
    scene_sub.add_parser("redo", help="повторить отменённое действие (как Ctrl+Y)")
    new = scene_sub.add_parser("new", help="создать новую сцену и открыть её в редакторе")
    new.add_argument("--path", required=True, help="куда сохранить, например res://scenes/yard.tscn")
    new.add_argument("--root-type", default="Node3D", help="тип корневого узла (по умолчанию Node3D)")
    new.add_argument("--root-name", help="имя корневого узла (по умолчанию из имени файла)")
    build = scene_sub.add_parser("build", help="создать новую сцену целиком за один шаг: корень, объекты, сохранение")
    build_source = build.add_mutually_exclusive_group(required=True)
    build_source.add_argument("--file", type=Path, help="JSON с полями scene {path, root_type, root_name} и ops (как в apply)")
    build_source.add_argument("--ops", help="список операций прямо в строке JSON (тогда нужен --path)")
    build.add_argument("--path", help="куда сохранить, например res://scenes/room.tscn (важнее, чем scene.path в файле)")
    build.add_argument("--root-type", help="тип корневого узла (по умолчанию из файла или Node3D)")
    build.add_argument("--root-name", help="имя корневого узла (по умолчанию из файла или из имени сцены)")
    build.add_argument("--overwrite", action="store_true", help="перезаписать сцену, если файл уже есть")
    build.add_argument("--force", action="store_true",
                       help="перезаписать даже открытую сцену с несохранёнными правками (её текущее состояние уйдёт в .godot/ai_bridge/backup)")
    build.add_argument("--main", action="store_true", help="сразу назначить сцену главной (её запускает кнопка «Запустить»)")
    build.add_argument("--no-open", action="store_true", help="не открывать сцену в редакторе после создания")

    script = sub.add_parser("script", help="скрипты GDScript")
    script_sub = script.add_subparsers(dest="script_command", required=True)
    script_set = script_sub.add_parser("set", help="записать скрипт в файл и, если указано, повесить на узел")
    script_set.add_argument("--path", required=True, help="например res://game/hello.gd")
    content = script_set.add_mutually_exclusive_group(required=True)
    content.add_argument("--file", type=Path, help="взять текст скрипта из файла")
    content.add_argument("--content", help="текст скрипта прямо в строке")
    script_set.add_argument("--node", help="путь узла в открытой сцене, на который повесить скрипт (\".\" = корень)")

    project_cmd = sub.add_parser("project", help="настройки проекта")
    project_sub = project_cmd.add_subparsers(dest="project_command", required=True)
    main_scene = project_sub.add_parser("main-scene", help="назначить главную сцену (её запускает кнопка «Запустить»)")
    main_scene.add_argument("--path", required=True, help="например res://scenes/yard.tscn")
    refresh = project_sub.add_parser("refresh", help="подхватить правки файлов, сделанные снаружи (ИИ, git pull): скан, скрипты с диска, перезагрузка открытых сцен")
    refresh.add_argument("--file", action="append", default=[], metavar="res://…", help="перечитать этот файл из кэша редактора (можно несколько раз)")
    refresh.add_argument("--no-scenes", action="store_true", help="не перезагружать открытые сцены")
    export = project_sub.add_parser("export", help="собрать игру без редактора: Godot --export-debug/--export-release по пресету из export_presets.cfg")
    export.add_argument("--preset", help="имя пресета (Windows, Linux, Android — см. --list)")
    export.add_argument("--out", help="куда положить сборку; по умолчанию export_path пресета (относительно папки проекта)")
    export.add_argument("--release", action="store_true", help="релизная сборка (без отладочных сообщений); по умолчанию отладочная")
    export.add_argument("--list", action="store_true", help="показать пресеты из export_presets.cfg и ничего не собирать")
    export.add_argument("--timeout", type=float, default=600.0, help="сколько секунд ждать сборку (по умолчанию 600)")
    export.add_argument("--godot", help="путь к исполняемому файлу Godot, если редактор закрыт")

    game = sub.add_parser("game", help="запуск игры отдельным процессом Godot с записью лога")
    game_sub = game.add_subparsers(dest="game_command", required=True)
    run = game_sub.add_parser("run", help="запустить игру (главную сцену или --scene)")
    run.add_argument("--scene", help="какую сцену запустить, например res://scenes/yard.tscn")
    run.add_argument("--seconds", type=float, default=8, help="сколько секунд дать игре поработать, потом остановить (по умолчанию 8)")
    run.add_argument("--background", action="store_true", help="запустить и сразу вернуться, не останавливая игру")
    run.add_argument("--headless", action="store_true", help="без окна (для автоматических проверок)")
    run.add_argument("--test", action="append", default=[], metavar="КТО=ПРОГРАММА",
                     help="программа самопроверки для скрипта игры, например player=forward:1.5,enter:0.5,wait:2,exit:0.5 "
                          "или car=gas:2,brake:1 (можно указать несколько раз); скрипт печатает результат фаз в лог")
    run.add_argument("--godot", help="путь к исполняемому файлу Godot, если редактор закрыт")
    shot = game_sub.add_parser("screenshot", help="запустить сцену, подождать и сохранить кадр в PNG (нужно окно; без экрана на Linux берётся xvfb-run)")
    shot.add_argument("--scene", help="какую сцену снимать, например res://scenes/yard.tscn (иначе главная)")
    shot.add_argument("--out", help="куда сохранить PNG (по умолчанию .godot/ai_bridge/screenshot.png)")
    shot.add_argument("--after", type=float, default=2.0, help="сколько секунд дать игре поработать до снимка (по умолчанию 2)")
    shot.add_argument("--size", default="1280x720", help="размер окна и снимка, по умолчанию 1280x720")
    shot.add_argument("--test", action="append", default=[], metavar="КТО=ПРОГРАММА",
                      help="программы самопроверки, как у game run (например player=forward:1.5,enter:0.5)")
    shot.add_argument("--godot", help="путь к исполняемому файлу Godot, если редактор закрыт")
    game_sub.add_parser("stop", help="остановить запущенную игру")
    game_sub.add_parser("status", help="запущена ли игра и что было в последнем запуске")

    task = sub.add_parser("task", help="задачи ИИ для панели «Задачи ИИ» в редакторе: объявить, закончить, отменить")
    task_sub = task.add_subparsers(dest="task_command", required=True)
    begin = task_sub.add_parser("begin", help="объявить задачу: заголовок и план; дальнейшие команды попадают в неё")
    begin.add_argument("--title", required=True, help="что делает ИИ, например «Строю комнату»")
    begin.add_argument("--plan", action="append", default=[], metavar="ШАГ", help="шаг плана (можно несколько раз)")
    end = task_sub.add_parser("end", help="закончить текущую задачу")
    end.add_argument("--status", choices=["ok", "error"], help="итог; без него — по ошибкам в записях")
    end.add_argument("--note", default="", help="короткий итог для человека")
    undo = task_sub.add_parser("undo", help="отменить задачу: история сцены, файлы в .godot/ai_bridge/trash, прежний текст скриптов")
    undo.add_argument("--id", type=int, default=0, help="номер задачи (по умолчанию последняя)")
    task_list = task_sub.add_parser("list", help="задачи с их записями")
    task_list.add_argument("--limit", type=int, default=20)

    journal = sub.add_parser("journal", help="журнал команд ИИ (то, что видно в панели «Задачи ИИ»)")
    journal_sub = journal.add_subparsers(dest="journal_command", required=True)
    journal_get = journal_sub.add_parser("get", help="последние записи журнала")
    journal_get.add_argument("--limit", type=int, default=50)
    journal_sub.add_parser("clear", help="очистить журнал и список задач (файлы не трогает)")

    editor = sub.add_parser("editor", help="окно редактора")
    editor_sub = editor.add_subparsers(dest="editor_command", required=True)
    editor_shot = editor_sub.add_parser("screenshot", help="снимок окна редактора в PNG (редактор должен быть с экраном, не headless)")
    editor_shot.add_argument("--out", default=".godot/ai_bridge/editor.png", help="куда сохранить PNG")

    setup = sub.add_parser("setup", help="поставить мост (плагин AI Bridge, enginectl, пример комнаты) в другой проект Godot; без project.godot создаётся новый проект")
    setup.add_argument("--target", required=True, help="папка другого проекта (новая или существующая)")
    setup.add_argument("--name", help="имя нового проекта (по умолчанию имя папки)")
    setup.add_argument("--force", action="store_true", help="перезаписать и пример игры (game/room.gd), если он менялся")

    log = sub.add_parser("log", help="лог последнего запуска игры")
    log_sub = log.add_subparsers(dest="log_command", required=True)
    log_get_cmd = log_sub.add_parser("get", help="ошибки, предупреждения и вывод последнего запуска")
    log_get_cmd.add_argument("--all", action="store_true", help="весь обычный вывод, а не только хвост")
    log_get_cmd.add_argument("--tail", type=int, default=40, help="сколько последних строк вывода показать (по умолчанию 40)")
    return parser


def main() -> int:
    options = build_parser().parse_args()
    project = options.project or find_project_root(Path.cwd()) or find_project_root(Path(__file__).resolve().parent)
    if project is None:
        print_response(fail("Не найден project.godot. Укажите папку проекта через --project"))
        return 1
    project = project.resolve()

    try:
        response = dispatch(project, options)
    except (OSError, json.JSONDecodeError) as exc:
        response = fail(str(exc))
    print_response(response)
    return 0 if response.get("status") == "ok" else 1


def dispatch(project: Path, options) -> dict:
    if options.command == "doctor":
        return send(project, "doctor", {})
    if options.command == "scene":
        args: dict = {}
        if options.scene_command == "inspect":
            args = {"path": options.path, "depth": options.depth}
        elif options.scene_command == "apply":
            try:
                raw = json.loads(options.file.read_text(encoding="utf-8") if options.file else options.ops)
            except (OSError, json.JSONDecodeError) as exc:
                return fail(f"Не удалось прочитать операции: {exc}")
            args = {"ops": raw.get("ops") if isinstance(raw, dict) else raw, "dry_run": options.dry_run}
        elif options.scene_command == "open":
            args = {"path": options.path}
        elif options.scene_command == "new":
            args = {"path": options.path, "root_type": options.root_type}
            if options.root_name:
                args["root_name"] = options.root_name
        elif options.scene_command == "build":
            try:
                raw = json.loads(options.file.read_text(encoding="utf-8") if options.file else options.ops)
            except (OSError, json.JSONDecodeError) as exc:
                return fail(f"Не удалось прочитать описание сцены: {exc}")
            spec = raw if isinstance(raw, dict) else {"ops": raw}
            scene = spec.get("scene") if isinstance(spec.get("scene"), dict) else {}
            path = options.path or scene.get("path")
            if not path:
                return fail("Укажите, куда сохранить сцену: --path res://scenes/имя.tscn или поле scene.path в файле")
            args = {"path": path, "ops": spec.get("ops"), "overwrite": options.overwrite, "force": options.force,
                    "open": not options.no_open, "main_scene": options.main,
                    "root_type": options.root_type or scene.get("root_type", "Node3D")}
            root_name = options.root_name or scene.get("root_name")
            if root_name:
                args["root_name"] = root_name
        return send(project, f"scene.{options.scene_command}", args)
    if options.command == "script":
        content = options.file.read_text(encoding="utf-8") if options.file else options.content
        args = {"path": options.path, "content": content}
        if options.node:
            args["node"] = options.node
        return send(project, "script.set", args)
    if options.command == "project":
        if options.project_command == "refresh":
            return send(project, "project.refresh", {"files": options.file, "reload_scenes": not options.no_scenes})
        if options.project_command == "export":
            response = project_export(project, options)
            if not options.list:
                result = response.get("result", {})
                journal_notify(project, "project.export", response,
                               f"сборка {options.preset} ({result.get('mode', '?')}): {result.get('path', '?')}"
                               + (f", {result['size_mb']} МБ" if "size_mb" in result else ""))
            return response
        return send(project, "project.main_scene", {"path": options.path})
    if options.command == "game":
        if options.game_command == "run":
            response = game_run(project, options)
            result = response.get("result", {})
            scene = options.scene or "главная сцена"
            if result.get("running"):
                summary = f"игра запущена в фоне: {scene}"
            else:
                summary = f"игра запущена ({scene}): ошибок {len(result.get('errors', []))}, {result.get('duration', 0)} с"
            journal_notify(project, "game.run", response, summary)
            return response
        if options.game_command == "screenshot":
            response = game_screenshot(project, options)
            journal_notify(project, "game.screenshot", response,
                           f"снимок игры {options.scene or 'главной сцены'} → {response.get('result', {}).get('path', '?')}")
            return response
        if options.game_command == "stop":
            return game_stop(project)
        return game_status(project)
    if options.command == "log":
        return log_get(project, options)
    if options.command == "setup":
        return setup_project(project, options)
    if options.command == "task":
        if options.task_command == "begin":
            return send(project, "task.begin", {"title": options.title, "plan": options.plan})
        if options.task_command == "end":
            args = {"note": options.note}
            if options.status:
                args["status"] = options.status
            return send(project, "task.end", args)
        if options.task_command == "undo":
            return send(project, "task.undo", {"id": options.id})
        return send(project, "task.list", {"limit": options.limit})
    if options.command == "journal":
        if options.journal_command == "clear":
            return send(project, "journal.clear", {})
        return send(project, "journal.get", {"limit": options.limit})
    if options.command == "editor":
        out = Path(options.out).expanduser()
        if not out.is_absolute():
            out = Path.cwd() / out
        out.parent.mkdir(parents=True, exist_ok=True)
        return send(project, "editor.screenshot", {"path": str(out)})
    return fail(f"Неизвестная команда {options.command}")


def journal_notify(project: Path, command: str, response: dict, summary: str) -> None:
    """Сообщает плагину о команде, выполненной самим enginectl (game run, screenshot, export),
    чтобы она попала в панель «Задачи ИИ». Если редактор закрыт — молча пропускает."""
    if read_connection(project) is None:
        return
    try:
        send(project, "journal.add", {"command": command, "status": response.get("status", "error"), "summary": summary,
                                      "files": response.get("files", []), "errors": response.get("errors", [])})
    except (OSError, json.JSONDecodeError):
        pass


def print_response(response: dict) -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    print(json.dumps(response, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    sys.exit(main())
