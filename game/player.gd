extends CharacterBody3D

## Персонаж от первого лица.
## Управление: W A S D (или стрелки) — ходьба, Shift — бег, мышь — обзор, пробел — прыжок,
## E — сесть в ближайшую машину (группа "cars") или выйти из неё, Esc — отпустить мышь,
## щелчок по окну игры — снова захватить.
## Выход из машины возможен только туда, где есть свободное место и земля под ногами
## (проверяются левая дверь, правая, сзади, спереди); иначе персонаж остаётся в машине.
## Через секунду после старта печатает, стоит ли на полу: по этой строке ИИ проверяет в логе,
## что персонаж не провалился. Самопроверка посадки: test_program = "forward:1.5,enter:0.5,wait:3,exit:0.5"
## (фазы forward, wait, enter, exit), после каждой фазы в логе строка «Персонаж [фаза]: …».

const SPEED := 4.0
const RUN_SPEED := 8.0  # с зажатым Shift
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.003
const FALL_LIMIT_Y := -10.0  # ниже этой высоты считаем, что упал за край двора
const REPORT_AFTER := 1.0
const ENTER_DISTANCE := 3.0  # метры до машины, с которых можно сесть

@export var drive_camera: NodePath  # камера, которая включается за рулём (иначе остаётся своя)
@export var test_program := ""

@onready var camera: Camera3D = $Camera
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _start_position := Vector3.ZERO
var _time := 0.0
var _reported := false
var _car: Node3D = null  # машина, в которой сидим
var _hint: Label  # подсказка внизу экрана: «E — сесть в машину» / «E — выйти»
var _phases: Array = []
var _phase_index := 0
var _phase_time := 0.0


func _ready() -> void:
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
		var pair := part.strip_edges().split(":")
		var seconds := float(pair[1]) if pair.size() == 2 and pair[1].is_valid_float() else 0.0
		_phases.append({"name": pair[0].strip_edges(), "seconds": seconds})


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and _car == null:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-80.0), deg_to_rad(80.0))
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		elif event.keycode == KEY_E:
			if _car == null:
				enter_nearest_car()
			else:
				exit_car()
	elif event is InputEventMouseButton and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	_time += delta
	var input := _test_input(delta)
	if _car != null:
		# Сидим в машине: едем вместе с ней, сами не двигаемся.
		global_position = _car.global_position + Vector3.UP * 1.0
		_hint.text = "E — выйти из машины"
		_report_floor()
		return
	_hint.text = "E — сесть в машину" if _nearest_car() != null else ""

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
	var direction := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := RUN_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()

	if position.y < FALL_LIMIT_Y:
		print("Персонаж упал за край двора, возвращаю на старт")
		position = _start_position
		velocity = Vector3.ZERO
	_report_floor()


func _report_floor() -> void:
	if not _reported and _time >= REPORT_AFTER:
		_reported = true
		if _car != null:
			print("Персонаж: в машине «%s», позиция=%s" % [_car.name, position.snapped(Vector3(0.01, 0.01, 0.01))])
		else:
			print("Персонаж: на полу=%s, позиция=%s" % [is_on_floor(), position.snapped(Vector3(0.01, 0.01, 0.01))])


# --- Посадка и выход ---------------------------------------------------------

## Ближайшая машина из группы "cars" не дальше ENTER_DISTANCE, иначе null.
func _nearest_car() -> Node3D:
	var nearest: Node3D = null
	var best := ENTER_DISTANCE
	for car in get_tree().get_nodes_in_group("cars"):
		if car is Node3D:
			var d: float = car.global_position.distance_to(global_position)
			if d < best:
				best = d
				nearest = car
	return nearest


## Садится в ближайшую машину, если она не дальше ENTER_DISTANCE.
func enter_nearest_car() -> bool:
	var nearest := _nearest_car()
	if nearest == null:
		print("Персонаж: рядом нет машины (ближе %.0f м)" % ENTER_DISTANCE)
		return false
	_car = nearest
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
	if "active" in _car:
		_car.active = false
	var car_name: String = _car.name
	_car = null
	global_position = spot["position"]
	rotation = Vector3(0.0, spot["yaw"], 0.0)
	camera.rotation.x = 0.0
	visible = true
	collision_layer = 1
	collision_mask = 1
	velocity = Vector3.ZERO
	camera.current = true
	print("Персонаж вышел из машины «%s» %s" % [car_name, spot["name"]])
	return true


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


# --- Самопроверка ----------------------------------------------------------------

## Программа самопроверки из командной строки: enginectl game run --test player=forward:1.5,enter:0.5
## передаёт игре аргумент --test-player=…, и он важнее значения, записанного в сцене.
static func test_program_from_cmdline(who: String, fallback: String) -> String:
	var prefix := "--test-%s=" % who
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback


## Возвращает направление ходьбы для текущей фазы test_program и печатает отчёт по её окончании.
func _test_input(delta: float) -> Vector2:
	if _phase_index >= _phases.size():
		return Vector2.ZERO
	var phase: Dictionary = _phases[_phase_index]
	var input := Vector2.ZERO
	if _phase_time == 0.0:
		match phase["name"]:
			"enter":
				enter_nearest_car()
			"exit":
				exit_car()
	if phase["name"] == "forward":
		input.y = -1.0
	_phase_time += delta
	if _phase_time >= phase["seconds"]:
		print("Персонаж [%s %.1f с]: %s, позиция=%s" % [phase["name"], phase["seconds"],
			"в машине" if _car != null else "на ногах, на полу=%s" % is_on_floor(),
			global_position.snapped(Vector3(0.01, 0.01, 0.01))])
		_phase_index += 1
		_phase_time = 0.0
	return input
