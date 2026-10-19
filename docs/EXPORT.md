# Сборка игры без редактора

Готовая игра должна запускаться без Godot и без ИИ (правило из README). Для этого проект «экспортируется»:
Godot складывает движок и все файлы игры в один исполняемый файл. Команда `enginectl project export`
делает это одной строкой, настройки лежат в `export_presets.cfg`.

## Один раз: шаблоны экспорта

Шаблон экспорта — это заготовка движка для каждой платформы (Windows, Linux, Android…), около 1,3 ГБ на все.
В Godot: **Редактор → Управление шаблонами экспорта… → Скачать и установить**. Версия шаблонов должна совпадать
с версией редактора (4.7.2). Без шаблонов `project export` откажется и напишет, что именно не найдено.

## Пресеты

`export_presets.cfg` в репозиторий не попадает (он в `.gitignore`: в нём могут быть пути к ключам подписи).
При первом `project export` файл создаётся из `tools/export_presets.example.cfg`: пресеты **Windows**
(один файл `build/windows/GodotAI.exe`, данные игры внутри), **Linux** (`build/linux/GodotAI.x86_64`)
и **Android** (`build/android/GodotAI.apk`). Из сборки исключены документация, `tools/` и плагин ИИ
(`exclude_filter`). Пресеты видны и правятся в редакторе: **Проект → Экспорт**.

```text
python tools\enginectl\enginectl.py project export --list
python tools\enginectl\enginectl.py project export --preset Windows            # отладочная сборка
python tools\enginectl\enginectl.py project export --preset Windows --release  # релизная, без отладочных сообщений
python tools\enginectl\enginectl.py project export --preset Linux --out /tmp/игра/GodotAI.x86_64
```

Ответ: путь и размер файла, время, лог (`.godot/ai_bridge/export.log`), ошибки Godot, если были.
Сборка идёт отдельным процессом Godot (`--headless --export-debug/--export-release`), открытый редактор не мешает:
плагин AI Bridge 0.9.2 в таком «пакетном» процессе не запускает сервер и не трогает файл подключения.

Отладочная сборка (`debug`) показывает консоль и печатает ошибки, релизная (`--release`) чище и быстрее.
Значок у `.exe` пока стандартный, от Godot: смена значка требует программу `rcedit`, в пресете
`application/modify_resources=false`.

## Windows

1. Шаблоны установлены (см. выше).
2. `python tools\enginectl\enginectl.py project export --preset Windows --release`
3. Открыть `build\windows\GodotAI.exe` двойным щелчком. Windows может показать предупреждение SmartScreen
   (файл не подписан): «Подробнее → Выполнить в любом случае».

Проверено в облаке 19.10.2026: сборки Linux (`GodotAI.x86_64`, 70 МБ) и Windows (`GodotAI.exe`, 104 МБ отладочная,
плюс `GodotAI.console.exe` — запуск с консолью) собираются за 7 с; Linux-сборка запущена без редактора
(`--headless -- --test-player=goto:3:0;5`): двор загрузился, персонаж дошёл до точки. Windows-сборку запускает владелец.

## Android

Нужно один раз поставить на компьютер владельца (из облака эти сайты закрыты сетевой политикой, поэтому делает человек):

1. **OpenJDK 17** — https://adoptium.net/temurin/releases/?variant=openjdk17 (Windows x64, .msi). Godot 4.7 рекомендует
   именно 17; новее тоже работает.
2. **Android SDK** — проще всего через Android Studio (https://developer.android.com/studio): запустить один раз,
   в SDK Manager отметить Platform-Tools (35+), Build-Tools 35.0.1, Platform 35, Command-line Tools, NDK 28.1.13356709
   и CMake 3.10.2. Либо без Android Studio: командные инструменты (`sdkmanager`) и команда
   `sdkmanager --sdk_root=<папка SDK> "platform-tools" "build-tools;35.0.1" "platforms;android-35" "cmdline-tools;latest" "cmake;3.10.2.4988404" "ndk;28.1.13356709"`.
   Обычное место SDK на Windows: `%LOCALAPPDATA%\Android\Sdk` (внутри должна быть `platform-tools\adb.exe`).
3. В Godot: **Редактор → Настройки редактора → Экспорт → Android**: `Java SDK Path` — папка JDK, `Android SDK Path` — папка SDK.
   Отладочный ключ подписи (`debug.keystore`) Godot создаёт сам программой `keytool` из JDK; если жалуется на ключ,
   перезапустить редактор после указания путей.
4. На телефоне: **Настройки → О телефоне → семь раз нажать «Номер сборки»**, затем **Для разработчиков → Отладка по USB**.
5. `python tools\enginectl\enginectl.py project export --preset Android` → `build\android\GodotAI.apk`.
   Поставить на телефон: скопировать APK по кабелю и открыть его на телефоне (разрешить установку из этого источника),
   либо `adb install -r build\android\GodotAI.apk` из `platform-tools`.

Что проверить на телефоне (пункт 8 списка проверок из PLAN.md):
- джойстик ведёт персонажа, E сажает в машину, джойстик рулит, Прыжок/Тормоз тормозит, R ставит на колёса;
- мультитач: джойстик и кнопка одновременно (газ и руль, бег и ходьба);
- «II» → Сохранить, закрыть игру, открыть снова, «II» → Загрузить — персонаж и машина там же;
- свернуть игру (домой), вернуться — игра продолжается, ничего не сломалось;
- панель читаема: на телефоне 2D-слой увеличен по плотности экрана (`content_scale_factor` в `game/touch_controls.gd`),
  3D остаётся в полном разрешении.

Ключ подписи для магазина (release keystore) и его пароль — только у владельца, не в репозитории и не в
`export_presets.cfg`, который в репозиторий тоже не попадает. Для Google Play нужен формат AAB и Gradle-сборка
(`gradle_build/use_gradle_build=true`, «Проект → Установить шаблон сборки Android»); это не входит в первую версию.
