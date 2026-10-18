# GodotAI — движок с ИИ внутри

Игровой движок на базе **Godot 4**, построенный вокруг ИИ: человек описывает словами, что хочет, ИИ создаёт и правит игру прямо в редакторе, а движок сам сообщает ИИ, что получилось (сцена, ошибки, снимок экрана).

Главный документ проекта — [docs/PLAN.md](docs/PLAN.md). Его читает любой ИИ и человек перед началом работы.

## Что где лежит

| Папка | Что внутри |
|---|---|
| `addons/ai_bridge/` | Плагин «Ухо и рука» для Godot (GDScript): принимает команды от ИИ |
| `tools/enginectl/` | Программа `enginectl` на Python: через неё ИИ отправляет команды в редактор |
| `game/` | Игровые модули: персонаж, машина, взаимодействия, сохранения |
| `scenes/` | Сцены демо |
| `docs/` | План, состояние работ, решения, описание команд, реестр ресурсов |

## Что нужно на компьютере

- Godot 4.7.2 (stable)
- Python 3.12
- Git

## Первая проверка связи

1. Открыть проект в Godot (плагин AI Bridge уже включён в `project.godot`).
2. В терминале, из папки проекта: `python tools\enginectl\enginectl.py doctor`
   (если `python` открывает Microsoft Store, использовать `py -3`).
3. В ответе должно быть `"status": "ok"` и «Godot на связи».
4. Открыть в редакторе сцену `scenes/inspect_test.tscn` и выполнить `python tools\enginectl\enginectl.py scene inspect`: в ответе дерево узлов Root → Floor, Cube, Sun, Camera.
5. `python tools\enginectl\enginectl.py scene apply --file tools\enginectl\examples\yard.json --dry-run` покажет план, та же команда без `--dry-run` поставит в сцену пол, две стены и свет; Ctrl+Z в редакторе убирает всё разом.
6. `python tools\enginectl\enginectl.py game run --seconds 5` запускает главную сцену (двор) на 5 секунд и возвращает ошибки и вывод игры; `python tools\enginectl\enginectl.py log get` показывает лог последнего запуска.

Самопроверка без терминала: `Godot --headless --path <папка проекта> --editor -- --ai-bridge-selftest`
печатает ответы на верный и неверный токен и строку `AI Bridge selftest: PASS`.

## Правила

- Секреты (API-ключи, пароли) в репозиторий не кладём: он открытый.
- Готовая игра не должна требовать ИИ для запуска.
