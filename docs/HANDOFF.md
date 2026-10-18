# HANDOFF — где остановились

**Дата:** 19.10.2026

**Сделано:**
- Окружение владельца проверено: Godot 4.7.2 в `F:\Godot`, Python 3.12.10 (в cmd работает `python`, в PowerShell надёжнее `py -3`), Git.
- Проект лежит в `F:\Godot\GodotAI`, импортирован в Менеджер проектов Godot и открывается в редакторе без ошибок.
- Ветка `bridge-doctor`: плагин `addons/ai_bridge` (слушает 127.0.0.1:47615, токен в `.godot/ai_bridge/connection.json`) и `tools/enginectl/enginectl.py` с командой `doctor`.
- **Проверено вживую:** `doctor` (PR #1, слит в main) и `scene inspect` (ветка scene-inspect): на scenes/inspect_test.tscn вернул дерево из 5 узлов с позициями, совпадающими с редактором.

**Не проверено:** ответ плагина на неверный токен; самопроверка `--ai-bridge-selftest`.

**Замечено:** если редактор закрыть принудительно, в `.godot/ai_bridge/connection.json` остаётся устаревший файл, и `enginectl` отвечает «Godot не отвечает» вместо «не найден файл подключения». Не критично; можно проверять `pid` из файла.

**Замечено также:** после обновления файлов плагина редактору нужен «Проект → Перезагрузить текущий проект», иначе он работает со старой версией.

**Дни 4–5 (ветка scene-apply):** `scene apply` (create/set/delete, dry_run, Undo/Redo одним действием), `scene new`, `scene open`, `scene save`, `scene undo`/`redo`. Проверено в headless-редакторе Godot 4.7.2 (Linux, в облачной среде Claude): полный цикл new → apply → inspect → set/delete → ошибки → undo → redo → save → open. В headless при save в логе `ERROR: Parameter "t" is null` из создания миниатюры (dummy-рендер), к плагину не относится.

**Как проверять без владельца:** скачать Godot Linux в среду, `Godot --headless --path <проект> --editor` в фоне, затем `python3 tools/enginectl/enginectl.py ...`. Проверка синтаксиса: `--headless --check-only --script res://addons/ai_bridge/plugin.gd`.

**Следующий шаг:** день 6 плана — `game run / stop` и `log get` (запуск игры из редактора и чтение ошибок).
