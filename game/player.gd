extends CharacterBody3D

## Персонаж от первого лица.
## Управление: W A S D (или стрелки) — ходьба, Shift — бег, мышь — обзор, пробел — прыжок,
## E — взаимодействие с ближайшим предметом из группы "interactables" (машина: сесть; дверь: открыть;
## кнопка: нажать; предмет: подобрать) или выход из машины, Esc — отпустить мышь, щелчок — захватить снова.
## У каждого такого предмета есть prompt() (текст подсказки внизу экрана) и interact(player).
## Выход из машины возможен только туда, где есть свободное место и земля под ногами
## (проверяются левая дверь, правая, сзади, спереди); иначе персонаж остаётся в машине.
## Инвентарь: add_item/has_item (например «Ключ» для запертой двери). Состояние сохраняется (группа persist).
## Через секунду после старта печатает, стоит ли на полу: по этой строке ИИ проверяет в логе,
## что персонаж не провалился.
## Самопроверка: test_program = "goto:4:2.5;2,interact:0.3,forward:1,enter:0.5,wait:3,exit:0.5"
## (фаза = имя:секунды[:аргументы]; goto идёт к точке x;z не дольше заданных секунд, interact/enter
## нажимают E, exit выходит из машины, forward идёт вперёд, wait ждёт, save/load/corrupt зовут узел
## сохранений), после каждой фазы в логе «Персонаж [фаза]: …».

const SPEED := 4.0
const RUN_SPEED := 8.0  # с зажатым Shift
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.003
const FALL_LIMIT_Y := -10.0  # ниже этой высоты считаем, что упал за край двора
const REPORT_AFTER := 1.0
const INTERACT_DISTANCE := 3.0  # метры до предмета, с которых работает E
const GOTO_TOLERANCE := 0.35    # м: ближе этого точка goto считается достигнутой

@export var drive_camera: NodePath  # камера, которая включается за рулём (иначе остаётся своя)
@export var test_program := ""

@onready var camera: Camera3D = $Camera
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var inventory: Array[String] = []
var _start_position := Vector3.ZERO
var _time := 0.0
var _reported := false
var _car: Node3D = null  # машина, в которой сидим
var _hint: Label  # подсказка внизу экрана
var _phases: Array = []
var _phase_index := 0
var _phase_time := 0.0
var _test_world_dir := Vector3.ZERO  # направление ходьбы для фазы goto (в мировых осях)
var _collision_off_frames := 0  # после телепорта столкновения включаются обратно через пару кадров физики


func _ready() -> void:
	add_to_group("persist")
	_start_position = position
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 26)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.position = Vector2(24, -56)
	var layer := CanvasLayer.new()
	layer.name = "Hint"
	layer.add_child(_hint)
	add_child(layer)
	test_program = test_program_from_cmdline("player", test_program)
	for part in test_program.split(",", false):
		var fields := part.strip_edges().split(":")
		var seconds := float(fields[1]) if fields.size() >= 2 and fields[1].is_valid_float() else 0.0
		_phases.append({"name": fields[0].strip_edges(), "seconds": seconds,
			"args": fields[2].strip_edges() if fields.size() >= 3 else ""})


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and _car == null:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-80.0), deg_to_rad(80.0))
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		elif event.keycode == KEY_E:
			interact_nearest()
	elif event is InputEventMouseButton and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	_time += delta
	if _collision_off_frames > 0:
		_collision_off_frames -= 1
		if _collision_off_frames == 0:
			collision_layer = 1
			collision_mask = 1
	var input := _test_input(delta)
	if _car != null:
		# Сидим в машине: едем вместе с ней, сами не двигаемся.
		global_position = _car.global_position + Vector3.UP * 1.0
		_hint.text = "E — выйти из машины"
		_report_floor()
		return
	var near := _nearest_interactable()
	_hint.text = str(near.prompt()) if near != null and near.has_method("prompt") else ""

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_physical_key_pressed(KEY_SPACE):
		velocity.y = JUMP_VELOCITY

	if _phases.is_empty():
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			input.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			input.y += 1.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			input.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			input.x += 1.0
	var direction := _test_world_dir if _test_world_dir != Vector3.ZERO \
		else (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := RUN_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()

	if position.y < FALL_LIMIT_Y:
		print("Персонаж упал за край двора, возвращаю на старт")
		_teleport(_start_position, rotation.y)
	_report_floor()


func _report_floor() -> void:
	if not _reported and _time >= REPORT_AFTER:
		_reported = true
		if _car != null:
			print("Персонаж: в машине «%s», позиция=%s" % [_car.name, position.snapped(Vector3(0.01, 0.01, 0.01))])
		else:
			print("Персонаж: на полу=%s, позиция=%s" % [is_on_floor(), position.snapped(Vector3(0.01, 0.01, 0.01))])


# --- Взаимодействие (E) и инвентарь ---------------------------------------------------

## Ближайший видимый узел из группы "interactables" не дальше INTERACT_DISTANCE, иначе null.
func _nearest_interactable() -> Node3D:
	var nearest: Node3D = null
	var best := INTERACT_DISTANCE
	for node in get_tree().get_nodes_in_group("interactables"):
		if node is Node3D and node.is_visible_in_tree() and node.has_method("interact"):
			var d: float = node.global_position.distance_to(global_position)
			if d < best:
				best = d
				nearest = node
	return nearest


## E: в машине — выйти, иначе подействовать на ближайший предмет (сесть, открыть, нажать, подобрать).
func interact_nearest() -> bool:
	if _car != null:
		return exit_car()
	var near := _nearest_interactable()
	if near == null:
		print("Персонаж: рядом ничего нет (ближе %.0f м)" % INTERACT_DISTANCE)
		return false
	near.interact(self)
	return true


func add_item(item_name: String) -> void:
	if not inventory.has(item_name):
		inventory.append(item_name)


func has_item(item_name: String) -> bool:
	return inventory.has(item_name)


# --- Посадка и выход ---------------------------------------------------------

## Садится в машину (вызывается из car.interact по E рядом с машиной).
func enter_car(car: Node3D) -> bool:
	if _car != null or car == null:
		return false
	_car = car
	visible = false
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	if "active" in _car:
		_car.active = true
	var cam := get_node_or_null(drive_camera) as Camera3D
	if cam != null:
		cam.current = true
	print("Персонаж сел в машину «%s»" % _car.name)
	return true


## Выходит из машины туда, где есть свободное место и земля. Если места нет, остаётся внутри.
func exit_car() -> bool:
	if _car == null:
		return false
	var spot := _find_exit_spot(_car)
	if spot.is_empty():
		print("Выйти нельзя: вокруг машины нет свободного места (проверены левая и правая двери, зад и перёд)")
		return false
	var car_name: String = _car.name
	_leave_car()
	_teleport(spot["position"], spot["yaw"])
	print("Персонаж вышел из машины «%s» %s" % [car_name, spot["name"]])
	return true


## Покидает машину без поиска места (положение задаёт вызывающий): общая часть выхода и загрузки.
func _leave_car() -> void:
	if "active" in _car:
		_car.active = false
	_car = null
	camera.rotation.x = 0.0
	visible = true
	camera.current = true


## Переносит персонажа в точку. Столкновения на два кадра физики выключены: иначе движок считает,
## что персонаж «пролетел» это расстояние за один кадр, и ударом отбрасывает машину, сквозь которую он прошёл.
func _teleport(target: Vector3, yaw: float) -> void:
	collision_layer = 0
	collision_mask = 0
	_collision_off_frames = 2
	global_position = target
	rotation = Vector3(0.0, yaw, 0.0)
	velocity = Vector3.ZERO


## Ищет место для выхода: у левой двери, у правой, сзади, спереди. Нужны земля под ногами и
## пустое пространство размером с персонажа. Возвращает {} если места нет.
func _find_exit_spot(car: Node3D) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var basis := car.global_transform.basis
	var yaw := basis.get_euler().y
	# У VehicleBody3D вперёд = +Z, поэтому левый борт — это +X, правый — -X.
	var candidates := [
		{"name": "у левой двери", "offset": Vector3(2.2, 0.0, 0.0)},
		{"name": "у правой двери", "offset": Vector3(-2.2, 0.0, 0.0)},
		{"name": "сзади", "offset": Vector3(0.0, 0.0, -3.5)},
		{"name": "спереди", "offset": Vector3(0.0, 0.0, 3.5)},
	]
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	var exclude: Array[RID] = [car.get_rid(), get_rid()]
	for c in candidates:
		var point: Vector3 = car.global_position + basis * c["offset"]
		# Земля: луч вниз от уровня крыши до 3 м под машиной.
		var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 1.5, point + Vector3.DOWN * 3.0)
		ray.exclude = exclude
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			continue
		var stand: Vector3 = hit["position"] + Vector3.UP * 0.95
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis(), stand)
		query.exclude = exclude
		if space.intersect_shape(query, 1).is_empty():
			# Спиной к машине: смотрим в сторону, куда вышли.
			var away := (point - car.global_position)
			away.y = 0.0
			var face_yaw := atan2(-away.x, -away.z) if away.length() > 0.01 else yaw
			return {"name": c["name"], "position": stand, "yaw": face_yaw}
	return {}


# --- Сохранение --------------------------------------------------------------------

func save_state() -> Dictionary:
	return {"position": [global_position.x, global_position.y, global_position.z],
		"yaw": rotation.y, "inventory": inventory.duplicate(), "car": _car.name if _car != null else ""}


func load_state(state: Dictionary) -> void:
	inventory.clear()
	for item in state.get("inventory", []):
		inventory.append(str(item))
	var car_name := str(state.get("car", ""))
	if _car != null:
		_leave_car()
	if car_name != "":
		for car in get_tree().get_nodes_in_group("cars"):
			if car.name == car_name:
				enter_car(car)
				return
	var p = state.get("position", null)
	var target := Vector3(p[0], p[1], p[2]) if p is Array and p.size() == 3 else global_position
	_teleport(target, float(state.get("yaw", rotation.y)))


# --- Самопроверка ----------------------------------------------------------------

## Программа самопроверки из командной строки: enginectl game run --test player=forward:1.5,enter:0.5
## передаёт игре аргумент --test-player=…, и он важнее значения, записанного в сцене.
static func test_program_from_cmdline(who: String, fallback: String) -> String:
	var prefix := "--test-%s=" % who
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback


## Возвращает направление ходьбы (в осях персонажа) для текущей фазы test_program, для goto задаёт
## _test_world_dir, и печатает отчёт по окончании фазы.
func _test_input(delta: float) -> Vector2:
	_test_world_dir = Vector3.ZERO
	if _phase_index >= _phases.size():
		return Vector2.ZERO
	var phase: Dictionary = _phases[_phase_index]
	var input := Vector2.ZERO
	var finished := false
	if _phase_time == 0.0:
		match phase["name"]:
			"enter", "interact":
				interact_nearest()
			"exit":
				exit_car()
			"save", "load", "corrupt":
				var manager := get_tree().get_first_node_in_group("save_manager")
				if manager == null:
					print("Персонаж: в сцене нет узла сохранений (SaveManager)")
				elif phase["name"] == "save":
					manager.save_game()
				elif phase["name"] == "load":
					manager.load_game()
				else:
					manager.corrupt_save_for_test()
	match phase["name"]:
		"forward":
			input.y = -1.0
		"goto":
			var xz: PackedStringArray = str(phase["args"]).split(";")
			if xz.size() == 2 and xz[0].is_valid_float() and xz[1].is_valid_float():
				var target := Vector3(float(xz[0]), global_position.y, float(xz[1]))
				var to_target := target - global_position
				to_target.y = 0.0
				if to_target.length() <= GOTO_TOLERANCE:
					finished = true
				else:
					_test_world_dir = to_target.normalized()
					rotation.y = atan2(-_test_world_dir.x, -_test_world_dir.z)  # смотреть, куда идём
	_phase_time += delta
	if _phase_time >= phase["seconds"] or finished:
		var note := ""
		if phase["name"] == "goto":
			note = " (дошёл)" if finished else " (НЕ ДОШЁЛ за %.1f с)" % phase["seconds"]
		print("Персонаж [%s%s %.1f с]: %s, позиция=%s%s" % [phase["name"],
			(" " + str(phase["args"])) if str(phase["args"]) != "" else "", _phase_time,
			"в машине" if _car != null else "на ногах, на полу=%s" % is_on_floor(),
			global_position.snapped(Vector3(0.01, 0.01, 0.01)), note])
		_phase_index += 1
		_phase_time = 0.0
		_test_world_dir = Vector3.ZERO
	return input
