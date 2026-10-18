# AI_PROTOCOL — команды моста

Описание формата команд `enginectl` ↔ плагин `ai_bridge`.

## Подключение

- Плагин слушает только `127.0.0.1`, порт 47615 (если занят — следующие до 47624).
- При включении плагин создаёт случайный токен и пишет `{host, port, token, pid}` в `.godot/ai_bridge/connection.json` (папка `.godot` не попадает в Git).
- Обмен: одна строка JSON на запрос, одна строка JSON на ответ.
- Запрос: `{"token": "...", "command": "doctor", "args": {}}`.
- Неверный токен — ответ с `status: "error"`.

Запуск: `python tools/enginectl/enginectl.py doctor` из папки проекта (на Windows при необходимости `py -3`).

Самопроверка плагина без enginectl: `Godot --headless --path <проект> --editor -- --ai-bridge-selftest`. Плагин подключается к своему порту, шлёт `doctor` с верным и с неверным токеном, печатает оба ответа и `AI Bridge selftest: PASS`/`FAIL`, затем закрывает редактор с кодом 0/1.

Каждый ответ содержит: `status`, `result`, `errors`, `warnings`, `files`.

| Команда | Статус |
|---|---|
| `doctor` | проверена 19.10.2026: версия Godot и плагина, имя и путь проекта, открытая сцена |
| `scene inspect` | проверена 19.10.2026 (команда протокола `scene.inspect`, args: `path` — узел, с которого начать, по умолчанию корень; `depth` — глубина, -1 = все). Ответ: `scene_path`, `node_count`, `root` — дерево узлов, у каждого `name`, `type`, `path`, `children`, при наличии `script`, `instance`, для Node3D/Node2D `position`, `rotation_degrees`, `scale`, для Control `position`, `size` |
| `scene apply` | проверена 19.10.2026 в headless-редакторе (команда `scene.apply`, args: `ops` — список операций, `dry_run`). Операции: `create` (parent, name, type, props), `set` (path, props), `delete` (path). Сначала проверяются все операции, при любой ошибке не применяется ничего. Применение — одно действие Undo/Redo редактора (Ctrl+Z отменяет весь набор). Ответ: `plan` (что создано/изменено/удалено, для set — старое и новое значение), `applied`, `dry_run` |
| `scene save` | проверена (`scene.save`): сохраняет открытую сцену, путь в `files` |
| `scene open` | проверена (`scene.open`, args: `path`): открывает существующую сцену в редакторе |
| `scene undo` / `scene redo` | проверены (`scene.undo`, `scene.redo`): отмена/повтор последнего действия в истории открытой сцены, как Ctrl+Z / Ctrl+Y; в ответе имя действия |
| `scene new` | проверена (`scene.new`, args: `path`, `root_type`=Node3D, `root_name`): создаёт сцену с одним корнем, сохраняет и открывает в редакторе |
| `script set` | не реализована |
| `game run / stop` | не реализована |
| `log get` | не реализована |
| `screenshot` | не реализована |

## Значения свойств в `scene apply`

- Числа, строки, `true`/`false` — как есть.
- Список из 3 чисел → Vector3 (`position`, `rotation_degrees`, `scale`), из 2 чисел → Vector2.
- Цвет: `"#rrggbb"` или список из 3–4 чисел от 0 до 1.
- `"res://путь"` → загружается ресурс (меш, материал, сцена).
- `mesh`: `{"primitive": "box"|"plane"|"sphere"|"cylinder"|"capsule", "size": [...], "radius": r, "height": h, "color": ...}`.
- `material_override`: `{"color": ...}` → StandardMaterial3D.

Пример набора операций: `tools/enginectl/examples/yard.json` (пол, две стены, свет).
