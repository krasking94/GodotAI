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
    options = parser.parse_args()

    project = options.project or find_project_root(Path.cwd()) or find_project_root(Path(__file__).resolve().parent)
    if project is None:
        response = fail("Не найден project.godot. Укажите папку проекта через --project")
    else:
        response = send(project.resolve(), options.command, {})

    sys.stdout.reconfigure(encoding="utf-8")
    print(json.dumps(response, ensure_ascii=False, indent=2))
    return 0 if response.get("status") == "ok" else 1


if __name__ == "__main__":
    sys.exit(main())
