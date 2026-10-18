"""enginectl: отправляет команды плагину AI Bridge в открытом редакторе Godot
и запускает игру отдельным процессом с записью вывода в лог.

Пример:  python tools/enginectl/enginectl.py doctor
Ответ всегда печатается как JSON. Код выхода 0, если status == "ok", иначе 1.
"""

import argparse
import json
import os
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
    if options.test:
        # Всё после «--» Godot отдаёт скриптам как пользовательские аргументы (OS.get_cmdline_user_args).
        cmd.append("--")
        for item in options.test:
            who, sep, program = item.partition("=")
            if not sep or not who.strip() or not program.strip():
                return fail(f"--test ждёт вид КТО=ПРОГРАММА, например player=forward:1.5,enter:0.5 (получено: {item!r})")
            cmd.append(f"--test-{who.strip()}={program.strip()}")
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


def parse_log(project: Path) -> dict:
    """Разбирает лог последнего запуска на ошибки, предупреждения и обычный вывод."""
    log_path = project / RUN_LOG
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
    game_sub.add_parser("stop", help="остановить запущенную игру")
    game_sub.add_parser("status", help="запущена ли игра и что было в последнем запуске")

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
            args = {"path": path, "ops": spec.get("ops"), "overwrite": options.overwrite,
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
        return send(project, "project.main_scene", {"path": options.path})
    if options.command == "game":
        if options.game_command == "run":
            return game_run(project, options)
        if options.game_command == "stop":
            return game_stop(project)
        return game_status(project)
    if options.command == "log":
        return log_get(project, options)
    return fail(f"Неизвестная команда {options.command}")


def print_response(response: dict) -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    print(json.dumps(response, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    sys.exit(main())
