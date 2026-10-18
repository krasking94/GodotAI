"""enginectl: отправляет команды плагину AI Bridge в открытом редакторе Godot.

Пример:  python tools/enginectl/enginectl.py doctor
Ответ всегда печатается как JSON. Код выхода 0, если status == "ok", иначе 1.
"""

import argparse
import json
import socket
import sys
from pathlib import Path

CONNECTION_FILE = Path(".godot") / "ai_bridge" / "connection.json"
TIMEOUT_SECONDS = 10


def find_project_root(start: Path) -> Path | None:
    for folder in [start, *start.parents]:
        if (folder / "project.godot").is_file():
            return folder
    return None


def fail(message: str) -> dict:
    return {"status": "error", "result": {}, "errors": [message], "warnings": [], "files": []}


def send(project: Path, command: str, args: dict) -> dict:
    conn_path = project / CONNECTION_FILE
    if not conn_path.is_file():
        return fail(
            "Godot не на связи: не найден файл подключения. "
            "Откройте проект в редакторе и включите плагин AI Bridge "
            "(Проект → Настройки проекта → Плагины)."
        )
    conn = json.loads(conn_path.read_text(encoding="utf-8"))
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
        return fail(f"Godot не отвечает на {conn['host']}:{conn['port']} ({exc}). Редактор закрыт или плагин выключен?")
    if not data:
        return fail("Godot закрыл соединение без ответа")
    return json.loads(data.decode("utf-8"))


def main() -> int:
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
    options = parser.parse_args()

    command, args = options.command, {}
    if options.command == "scene":
        command = f"scene.{options.scene_command}"
        if options.scene_command == "inspect":
            args = {"path": options.path, "depth": options.depth}
        elif options.scene_command == "apply":
            try:
                raw = json.loads(options.file.read_text(encoding="utf-8") if options.file else options.ops)
            except (OSError, json.JSONDecodeError) as exc:
                print_response(fail(f"Не удалось прочитать операции: {exc}"))
                return 1
            ops = raw.get("ops") if isinstance(raw, dict) else raw
            args = {"ops": ops, "dry_run": options.dry_run}
        elif options.scene_command == "open":
            args = {"path": options.path}
        elif options.scene_command == "new":
            args = {"path": options.path, "root_type": options.root_type}
            if options.root_name:
                args["root_name"] = options.root_name

    project = options.project or find_project_root(Path.cwd()) or find_project_root(Path(__file__).resolve().parent)
    if project is None:
        response = fail("Не найден project.godot. Укажите папку проекта через --project")
    else:
        response = send(project.resolve(), command, args)

    print_response(response)
    return 0 if response.get("status") == "ok" else 1


def print_response(response: dict) -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    print(json.dumps(response, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    sys.exit(main())
