# HANDOFF — где остановились

**Дата:** 19.10.2026

**Сделано:**
- Окружение владельца проверено: Godot 4.7.2 в `F:\Godot`, Python 3.12.10 (в cmd работает `python`, в PowerShell надёжнее `py -3`), Git.
- Проект лежит в `F:\Godot\GodotAI`, импортирован в Менеджер проектов Godot и открывается в редакторе без ошибок.
- Ветка `bridge-doctor`: плагин `addons/ai_bridge` (слушает 127.0.0.1:47615, токен в `.godot/ai_bridge/connection.json`) и `tools/enginectl/enginectl.py` с командой `doctor`.
- **Проверено вживую:** `doctor` (PR #1, слит в main) и `scene inspect` (ветка scene-inspect): на scenes/inspect_test.tscn вернул дерево из 5 узлов с позициями, совпадающими с редактором.

**Не проверено:** ответ плагина на неверный токен; самопроверка `--ai-bridge-selftest`.

**Замечено (исправлено в день 7):** если редактор закрыть принудительно, в `.godot/ai_bridge/connection.json` остаётся устаревший файл; теперь `enginectl` проверяет `pid` и пишет, что файл остался от закрытого редактора.

**Замечено также:** после обновления файлов плагина редактору нужен «Проект → Перезагрузить текущий проект», иначе он работает со старой версией.

**Дни 4–5 (ветка scene-apply):** `scene apply` (create/set/delete, dry_run, Undo/Redo одним действием), `scene new`, `scene open`, `scene save`, `scene undo`/`redo`. Проверено в headless-редакторе Godot 4.7.2 (Linux, в облачной среде Claude): полный цикл new → apply → inspect → set/delete → ошибки → undo → redo → save → open. В headless при save в логе `ERROR: Parameter "t" is null` из создания миниатюры (dummy-рендер), к плагину не относится.

**Как проверять без владельца:** скачать Godot Linux в среду, `Godot --headless --path <проект> --editor` в фоне, затем `python3 tools/enginectl/enginectl.py ...`. Проверка синтаксиса: `--headless --check-only --script res://addons/ai_bridge/plugin.gd`.

**День 6 (ветка game-run, PR #4):** `script set`, `project main-scene`, `game run/stop/status`, `log get`. Игра запускается не из редактора, а отдельным процессом Godot (так весь вывод попадает в лог; путь к Godot берётся из connection.json). Цикл «сломанный скрипт → game run → log get → исправление → чистый запуск» проверен headless. Создана сцена `scenes/yard.tscn` (двор: пол, две стены, лампа, камера, скрипт `game/yard.gd`), назначена главной.

**День 7 (ветка scene-build):** `scene build` собирает новую сцену целиком за один шаг: корень + операции create/set (как в apply) + сохранение; файл появляется только если все операции верны; после записи файл читается обратно с диска и число узлов сверяется (`reread_node_count`); сцена открывается в редакторе, по `--main` назначается главной, по `--overwrite` перезаписывается (открытая сцена перезагружается). «Одной фразой» устроено так: человек пишет фразу → ИИ переводит её в JSON-описание (поля `phrase`, `scene`, `ops`) → одна команда `scene build --file`. Примеры: `examples/yard.json` (двор), `examples/room.json` (комната 8×8, четыре стены, лампа, камера, скрипт `game/room.gd`). Проверено headless: build → inspect → перезапуск редактора → open → inspect (8 узлов) → `game run --scene res://scenes/room.tscn` («Комната готова: 7 объектов»). Заодно: `enginectl` ищет Godot сам (PATH, папка проекта, папка над проектом) и подсказывает перезагрузку проекта, если файл подключения записан старым плагином; `tools/` помечена `.gdignore`, чтобы редактор не компилировал учебный сломанный скрипт (`examples/yard_broken.gd.txt`); в плане `scene apply` для мешей показываются размер и цвет.

**Следующий шаг:** проверка `scene build` в GUI владельца, затем неделя 2: персонаж (дни 8–9: ходьба, обзор, столкновения).
