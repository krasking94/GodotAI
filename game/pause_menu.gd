extends CanvasLayer

## Меню паузы: Esc открывает и закрывает. Кнопки: Продолжить, Сохранить (F5), Загрузить (F9), Выйти.
## Пока меню открыто, игра стоит (get_tree().paused = true) и мышь свободна; «Продолжить» снова
## захватывает мышь. Сохранение и загрузка идут через узел группы save_manager (game/save_manager.gd).
## Меню строится кодом, в сцене нужен только этот узел CanvasLayer со скриптом.
## Самопроверка: game run --test menu=open:0.5,save:0.3,load:0.3,close:0.5 (фазы open, close, save, load, quit).

var _status: Label
var _phases: Array = []
var _phase_index := 0
var _phase_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # меню работает, пока всё остальное стоит на паузе
	layer = 10
	visible = false
	_build_ui()
	var prefix := "--test-menu="
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			for part in arg.trim_prefix(prefix).split(",", false):
				var pair := part.strip_edges().split(":")
				var seconds := float(pair[1]) if pair.size() >= 2 and pair[1].is_valid_float() else 0.0
				_phases.append({"name": pair[0].strip_edges(), "seconds": seconds})


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Пауза"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for item in [["Продолжить (Esc)", resume], ["Сохранить (F5)", _on_save],
			["Загрузить (F9)", _on_load], ["Выйти из игры", _on_quit]]:
		var button := Button.new()
		button.text = item[0]
		button.add_theme_font_size_override("font_size", 22)
		button.pressed.connect(item[1])
		box.add_child(button)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 18)
	box.add_child(_status)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		toggle()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _phase_index >= _phases.size():
		return
	var phase: Dictionary = _phases[_phase_index]
	if _phase_time == 0.0:
		match phase["name"]:
			"open":
				pause()
			"close":
				resume()
			"save":
				_on_save()
			"load":
				_on_load()
			"quit":
				_on_quit()
	_phase_time += delta
	if _phase_time >= phase["seconds"]:
		_phase_index += 1
		_phase_time = 0.0


func toggle() -> void:
	if visible:
		resume()
	else:
		pause()


func pause() -> void:
	visible = true
	get_tree().paused = true
	_status.text = ""
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	print("Меню: пауза, игра остановлена")


func resume() -> void:
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	print("Меню: игра продолжается")


func _manager() -> Node:
	var manager := get_tree().get_first_node_in_group("save_manager")
	if manager == null:
		_status.text = "В сцене нет узла сохранений (SaveManager)"
		print("Меню: в сцене нет узла группы save_manager")
	return manager


func _on_save() -> void:
	var manager := _manager()
	if manager != null:
		_status.text = "Сохранено" if manager.save_game() else "Не удалось сохранить, см. вывод"


func _on_load() -> void:
	var manager := _manager()
	if manager != null:
		_status.text = "Загружено" if manager.load_game() else "Не удалось загрузить, см. вывод"


func _on_quit() -> void:
	print("Меню: выход из игры")
	get_tree().quit()
