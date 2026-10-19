extends CanvasLayer

## Экранное управление для телефона: слева плавающий джойстик (палец кладётся где угодно на левой
## половине экрана), справа кнопки E, Прыжок/Тормоз, R, Бег и пауза; обзор — пальцем по правой половине
## (это делает player.gd по InputEventScreenDrag). Джойстик и кнопки «нажимают действия» из game/actions.gd
## через Input.parse_input_event(InputEventAction), поэтому персонаж и машина не отличают их от клавиатуры:
## так нажатие видят и опрос (Input.is_action_pressed), и обработчики событий (event.is_action_pressed),
## в отличие от Input.action_press, который только меняет состояние и событий не рассылает.
## Показывается на устройствах с сенсорным экраном, а также при запуске с аргументом --touch
## или с --test touch=… (для снимков и проверок без телефона). На телефоне (OS.has_feature("mobile"))
## весь 2D-слой увеличивается по плотности экрана (content_scale_factor), чтобы кнопки были под палец.
## Самопроверка: game run --test touch=joy:1.5:0;-1,button:0.3:interact,show:1
## (joy:сек:x;y держит джойстик, button:сек:действие держит кнопку, show показывает панель, wait ждёт);
## после каждой фазы в выводе «Экранное управление [фаза]: персонаж …, машина …».

const Actions := preload("res://game/actions.gd")
const JOY_RADIUS := 90.0
const BUTTONS := [["E", "interact"], ["Прыжок\nТормоз", "jump brake"], ["R", "flip"], ["Бег", "run"]]

var _joy_base := Vector2.ZERO
var _joy_vector := Vector2.ZERO
var _joy_index := -1
var _pad: Control
var _phases: Array = []
var _phase_index := 0
var _phase_time := 0.0
var _held_actions: Array[String] = []


func _ready() -> void:
	Actions.ensure()
	process_mode = Node.PROCESS_MODE_ALWAYS  # кнопка паузы и самопроверка работают и при остановленной игре
	layer = 5
	var program := ""
	var forced := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--touch":
			forced = true
		elif arg.begins_with("--test-touch="):
			forced = true
			program = arg.trim_prefix("--test-touch=")
	visible = forced or DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	if OS.has_feature("mobile"):
		# На телефоне точек на дюйм в 2–3 раза больше, чем на мониторе: без этого джойстик и кнопки
		# были бы размером с ноготь. Множитель увеличивает весь 2D-слой (панель, подсказку, спидометр),
		# 3D-картинка остаётся в полном разрешении.
		var scale_factor := clampf(DisplayServer.screen_get_dpi() / 200.0, 1.0, 2.0)
		get_window().content_scale_factor = scale_factor
		print("Экранное управление: %d точек на дюйм, масштаб панели %.2f" % [DisplayServer.screen_get_dpi(), scale_factor])
	_build_ui()
	for part in program.split(",", false):
		var fields := part.strip_edges().split(":")
		var seconds := float(fields[1]) if fields.size() >= 2 and fields[1].is_valid_float() else 0.0
		_phases.append({"name": fields[0].strip_edges(), "seconds": seconds,
			"args": fields[2].strip_edges() if fields.size() >= 3 else ""})
	if visible:
		print("Экранное управление: включено")


func _build_ui() -> void:
	_pad = Control.new()
	_pad.name = "Joystick"
	_pad.anchor_right = 0.5
	_pad.anchor_bottom = 1.0
	_pad.mouse_filter = Control.MOUSE_FILTER_STOP
	_pad.gui_input.connect(_on_pad_input)
	_pad.draw.connect(_draw_pad)
	add_child(_pad)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	column.position = Vector2(-150, -330)
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	for item in BUTTONS:
		var button := Button.new()
		button.text = item[0]
		button.custom_minimum_size = Vector2(120, 64)
		button.add_theme_font_size_override("font_size", 22)
		button.focus_mode = Control.FOCUS_NONE
		var actions: PackedStringArray = str(item[1]).split(" ")
		if item[1] == "run":
			button.toggle_mode = true
			button.toggled.connect(func(on: bool) -> void: _send("run", on))
		else:
			button.button_down.connect(func() -> void:
				for a in actions: _send(a, true))
			button.button_up.connect(func() -> void:
				for a in actions: _send(a, false))
		column.add_child(button)
	var pause := Button.new()
	pause.text = "II"
	pause.custom_minimum_size = Vector2(64, 64)
	pause.add_theme_font_size_override("font_size", 26)
	pause.focus_mode = Control.FOCUS_NONE
	pause.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause.position = Vector2(-84, 20)
	pause.pressed.connect(func() -> void:
		_send("pause", true)
		_send("pause", false))
	add_child(pause)


## Нажимает или отпускает действие так, как это сделала бы клавиша.
func _send(action: String, pressed: bool, strength := 1.0) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = strength if pressed else 0.0
	Input.parse_input_event(event)


# --- Джойстик ----------------------------------------------------------------------

func _on_pad_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _joy_index == -1:
			_joy_index = event.index
			_joy_base = event.position
			_set_joystick(Vector2.ZERO)
		elif not event.pressed and event.index == _joy_index:
			_joy_index = -1
			_set_joystick(Vector2.ZERO)
		_pad.accept_event()
	elif event is InputEventScreenDrag and event.index == _joy_index:
		_set_joystick((event.position - _joy_base) / JOY_RADIUS)
		_pad.accept_event()


## Переводит отклонение джойстика (x вправо, y вниз, длина до 1) в силу четырёх действий ходьбы.
func _set_joystick(vector: Vector2) -> void:
	_joy_vector = vector.limit_length(1.0)
	_press_axis("move_left", "move_right", _joy_vector.x)
	_press_axis("move_forward", "move_back", _joy_vector.y)
	_pad.queue_redraw()


func _press_axis(negative: String, positive: String, value: float) -> void:
	if value < -0.05:
		_send(negative, true, -value)
		_send(positive, false)
	elif value > 0.05:
		_send(positive, true, value)
		_send(negative, false)
	else:
		_send(negative, false)
		_send(positive, false)


func _draw_pad() -> void:
	var base := _joy_base if _joy_index != -1 else Vector2(170, _pad.size.y - 170)
	_pad.draw_circle(base, JOY_RADIUS, Color(1, 1, 1, 0.15))
	_pad.draw_arc(base, JOY_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 3.0)
	_pad.draw_circle(base + _joy_vector * JOY_RADIUS, 36.0, Color(1, 1, 1, 0.6))


# --- Самопроверка ----------------------------------------------------------------

func _process(delta: float) -> void:
	if _phase_index >= _phases.size():
		return
	var phase: Dictionary = _phases[_phase_index]
	if _phase_time == 0.0:
		match phase["name"]:
			"show":
				visible = true
			"joy":
				var xy: PackedStringArray = str(phase["args"]).split(";")
				if xy.size() == 2 and xy[0].is_valid_float() and xy[1].is_valid_float():
					_set_joystick(Vector2(float(xy[0]), float(xy[1])))
			"button":
				for a in str(phase["args"]).split(" ", false):
					_send(a, true)
					_held_actions.append(a)
	_phase_time += delta
	if _phase_time >= phase["seconds"]:
		if phase["name"] == "joy":
			_set_joystick(Vector2.ZERO)
		for a in _held_actions:
			_send(a, false)
		_held_actions.clear()
		print("Экранное управление [%s%s %.1f с]: %s" % [phase["name"],
			(" " + str(phase["args"])) if str(phase["args"]) != "" else "", _phase_time, _report()])
		_phase_index += 1
		_phase_time = 0.0


func _report() -> String:
	var parts: Array[String] = []
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		parts.append("персонаж %s%s" % [player.global_position.snapped(Vector3(0.01, 0.01, 0.01)),
			", в машине" if "_car" in player and player._car != null else ""])
	var car := get_tree().get_first_node_in_group("cars") as Node3D
	if car != null:
		parts.append("машина %s, скорость %.1f м/с" % [car.global_position.snapped(Vector3(0.01, 0.01, 0.01)),
			car.linear_velocity.length() if car is RigidBody3D else 0.0])
	return ", ".join(parts) if not parts.is_empty() else "в сцене нет персонажа и машины"
