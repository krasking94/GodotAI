extends SceneTree

## Снимок экрана игры без человека: загружает сцену, даёт ей поработать и сохраняет кадр в PNG.
## Запускается не как сцена, а как главный цикл: Godot --path <проект> --script res://game/screenshot.gd -- …
## Аргументы после «--»: --shot-scene=res://… (иначе главная сцена проекта), --shot-out=<файл.png>,
## --shot-after=<секунд> (сколько дать игре поработать, по умолчанию 2), а также --test-кто=программа
## для самопроверок объектов (их читают сами скрипты персонажа и машины).
## Удобнее вызывать через enginectl: game screenshot --scene … --out … --after … --test …

var _elapsed := 0.0
var _scene_path := ""
var _out := "screenshot.png"
var _after := 2.0
var _done := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-scene="):
			_scene_path = arg.trim_prefix("--shot-scene=")
		elif arg.begins_with("--shot-out="):
			_out = arg.trim_prefix("--shot-out=")
		elif arg.begins_with("--shot-after="):
			_after = float(arg.trim_prefix("--shot-after="))
	if _scene_path == "":
		_scene_path = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	var packed := load(_scene_path) as PackedScene
	if packed == null:
		push_error("Снимок: сцена «%s» не найдена или не сцена" % _scene_path)
		quit(2)
		return
	root.add_child(packed.instantiate())


func _process(delta: float) -> bool:
	if _done:
		return true
	_elapsed += delta
	if _elapsed < _after:
		return false
	_done = true
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Снимок: кадр пустой (нет окна или графика не инициализирована)")
		quit(3)
		return true
	var err := image.save_png(_out)
	if err != OK:
		push_error("Снимок: не удалось сохранить «%s»: %s" % [_out, error_string(err)])
		quit(4)
		return true
	print("Снимок сохранён: %s (%dx%d, через %.1f с)" % [_out, image.get_width(), image.get_height(), _elapsed])
	return true
