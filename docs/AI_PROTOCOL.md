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
| `scene build` | проверена 19.10.2026 headless (`scene.build`, args: `path`, `root_type`, `root_name`, `ops` — только `create` и `set`, `overwrite`=false, `open`=true, `main_scene`=false). Собирает новую сцену в памяти и сохраняет одним шагом; при любой ошибке файл не создаётся. Ответ: `node_count`, `reread_node_count` (файл прочитан обратно с диска), `plan`, `opened`, `main_scene`, в `files` путь сцены (и `res://project.godot`, если назначена главной). В enginectl: `scene build --file описание.json` (поля `scene {path, root_type, root_name}` и `ops`; `--path`, `--root-type`, `--root-name` важнее полей файла), `--ops '[...]'` + `--path`, флаги `--overwrite`, `--main`, `--no-open` |
| `script set` | проверена (`script.set`, args: `path`, `content`, `node` необязательно): записывает .gd, обновляет его в редакторе, при `node` вешает на узел через Undo/Redo. Если скрипт не компилируется, в ответе `parse_error` и предупреждение |
| `game run / stop / status` | проверены. Реализованы в enginectl, не в плагине: игра запускается отдельным процессом Godot (путь берётся из connection.json открытого редактора, из `--godot` или `GODOT_EXE`; на Windows автоматически берётся `_console.exe`), вывод пишется в `.godot/ai_bridge/last_run.log`. `run` ждёт `--seconds` (по умолчанию 8) и останавливает игру, либо `--background`; `--scene` выбирает сцену, иначе главная; `--headless` без окна |
| `log get` | проверена: разбирает лог последнего запуска на `errors` (SCRIPT ERROR / ERROR / USER ERROR с подробностями `at:`), `warnings` и `output` |
| `screenshot` | не реализована |
| `project main-scene` | проверена (`project.main_scene`, args: `path`): назначает главную сцену, сохраняет project.godot |

## Значения свойств в `scene apply`

- Числа, строки, `true`/`false` — как есть.
- Список из 3 чисел → Vector3 (`position`, `rotation_degrees`, `scale`), из 2 чисел → Vector2.
- Цвет: `"#rrggbb"` или список из 3–4 чисел от 0 до 1.
- `"res://путь"` → загружается ресурс (меш, материал, сцена).
- `mesh`: `{"primitive": "box"|"plane"|"sphere"|"cylinder"|"capsule", "size": [...], "radius": r, "height": h, "color": ...}`.
- `material_override`: `{"color": ...}` → StandardMaterial3D.

В `plan` для мешей показываются тип, размер и цвет (`{"mesh": "BoxMesh", "size": [...], "color": [...]}`).

Примеры описаний: `tools/enginectl/examples/yard.json` (двор: пол, две стены, свет), `room.json` (комната: пол 8×8, четыре стены, лампа, камера, скрипт). В каждом записана фраза человека (`phrase`), блок `scene` и `ops`; `scene apply` берёт из файла только `ops`, `scene build` — всё.

Папка `tools/` помечена файлом `.gdignore`: редактор её не сканирует и не компилирует, поэтому учебный сломанный скрипт лежит там как `examples/yard_broken.gd.txt`.
