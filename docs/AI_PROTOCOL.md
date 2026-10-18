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
| `scene inspect` | не реализована |
| `scene apply` | не реализована |
| `script set` | не реализована |
| `game run / stop` | не реализована |
| `log get` | не реализована |
| `screenshot` | не реализована |
