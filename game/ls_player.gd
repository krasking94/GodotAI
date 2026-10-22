extends CharacterBody3D

## «Симулятор жизни»: герой от первого лица в младенчестве.
## Режимы (mode): "lie" — лежит в кроватке, только крутит головой мышью; "crawl" — ползёт (камера низко,
## медленно); "walk" — ходит на ножках: камера выше, быстрее, но есть равновесие (balance): оно тратится
## при ходьбе тем быстрее, чем слабее навык «Ноги», и при нуле малыш падает (режим "fallen" на секунду,
## потом снова ползёт). Каждое падение и каждый шаг прокачивают «Ноги» (через game.add_skill).
## Клавиши: W A S D — движение, мышь — обзор, Пробел — встать/сесть (когда ходьба уже открыта),
## E — взаимодействие с ближайшим предметом из группы "ls_interact" (prompt()/interact(player)),
## Esc — отпустить мышь, щелчок — захватить снова. Движение только в _physics_process.
## Для самопроверки у героя есть goto(point) — автопилот идёт к точке, и auto_interact().

const CRAWL_SPEED := 1.1
const WALK_SPEED := 2.0
const CRAWL_EYE := 0.45   # высота глаз над полом, когда ползёт
const WALK_EYE := 0.85    # высота глаз на ножках (малыш ростом около метра)
const LIE_EYE := 0.75     # глаза, когда лежит в кроватке (матрас приподнят)
const EYE_SPEED := 6.0
const MOUSE_SENSITIVITY := 0.0025
const GRAVITY := 14.0
const FALL_SECONDS := 1.4
const INTERACT_CRAWL := 1.1
const INTERACT_WALK := 1.5
const GOTO_TOLERANCE := 0.3

var game: Node = null  # корень сцены (ls_game.gd)
var mode := "lie"
var can_walk := false      # открыл ли малыш ходьбу (квест «Встань на ножки»)
var balance := 1.0         # 0..1, равновесие при ходьбе
var legs := 0.0            # копия навыка «Ноги» 0..100 (обновляет game)
var inventory: Array[String] = []
var held_model: Node3D = null  # поднятый предмет виден перед глазами
var steps_walked := 0.0
var falls := 0
var _fall_time := 0.0
var _wobble_time := 0.0
var _goto_target := Vector3.ZERO
var _goto_active := false
var _stuck_time := 0.0
var _detour_time := 0.0
var _detour_dir := Vector3.ZERO
var _hint: Label
var _step_sound: AudioStreamPlayer

@onready var camera: Camera3D = $Camera
@onready var shape_node: CollisionShape3D = $Shape


func _ready() -> void:
	add_to_group("player")
	if not DisplayServer.is_touchscreen_available() and not _is_batch():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera.position.y = LIE_EYE
	camera.fov = 80.0


static func _is_batch() -> bool:
	return DisplayServer.get_name() == "headless"


func set_mode(new_mode: String) -> void:
	if mode == new_mode:
		return
	mode = new_mode
	balance = 1.0
	if mode == "walk":
		print("Малыш встал на ножки")
	elif mode == "crawl":
		print("Малыш ползёт")
	elif mode == "fallen":
		falls += 1
		_fall_time = FALL_SECONDS
		print("Малыш упал (падение №%d)" % falls)
		if game != null and game.has_method("on_fall"):
			game.on_fall()


func set_hint(label: Label) -> void:
	_hint = label


## Куда смотрит (единичный вектор взгляда камеры в мире).
func look_dir() -> Vector3:
	return -camera.global_transform.basis.z


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-80.0), deg_to_rad(80.0))
	elif event.is_action_pressed("interact"):
		interact_nearest()
	elif event.is_action_pressed("jump"):
		toggle_stand()
	elif event.is_action_pressed("pause"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseButton and event.pressed and not DisplayServer.is_touchscreen_available():
		if game == null or not game.has_method("ui_blocks_mouse") or not game.ui_blocks_mouse():
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Пробел: встать на ножки (если ходьба открыта) или снова сесть на пол.
func toggle_stand() -> void:
	if mode == "crawl" and can_walk:
		set_mode("walk")
	elif mode == "walk":
		set_mode("crawl")
	elif mode == "crawl" and not can_walk and game != null and game.has_method("on_try_stand"):
		game.on_try_stand()


func _physics_process(delta: float) -> void:
	var paused_ui: bool = game != null and game.has_method("ui_blocks_mouse") and game.ui_blocks_mouse()
	var eye := LIE_EYE
	var input := Vector2.ZERO
	if mode == "lie":
		velocity = Vector3.ZERO
	elif mode == "fallen":
		_fall_time -= delta
		eye = 0.3
		velocity.x = 0.0
		velocity.z = 0.0
		if _fall_time <= 0.0:
			set_mode("crawl")
	else:
		eye = WALK_EYE if mode == "walk" else CRAWL_EYE
		if _goto_active:
			var to := _goto_target - global_position
			to.y = 0.0
			if to.length() < GOTO_TOLERANCE:
				_goto_active = false
				print("Малыш дошёл до точки %s" % [_goto_target.snapped(Vector3(0.1, 0.1, 0.1))])
			else:
				var world_dir := to.normalized()
				if _detour_time > 0.0:
					_detour_time -= delta
					world_dir = _detour_dir  # обходим препятствие боком
				var local := global_transform.basis.inverse() * world_dir
				input = Vector2(local.x, local.z)
				# Поворачиваем тело к цели, чтобы и камера смотрела туда.
				var yaw := atan2(-to.x, -to.z)
				rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-6.0 * delta))
		elif not paused_ui:
			input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var direction := (transform.basis * Vector3(input.x, 0.0, input.y)).limit_length(1.0)
		var speed := WALK_SPEED if mode == "walk" else CRAWL_SPEED
		var real := get_real_velocity()
		var moving := direction.length() > 0.1 and Vector2(real.x, real.z).length() > 0.15  # упёрся в стену — не идёт
		if mode == "walk":
			speed *= 0.7 + 0.3 * balance
			if moving:
				var drain := 0.22 / (1.0 + legs / 20.0)
				balance = maxf(balance - drain * delta, 0.0)
				steps_walked += speed * delta
				if game != null and game.has_method("add_skill"):
					game.add_skill("legs", 0.6 * delta)
				_wobble_time += delta * 7.0
				var amp := 0.06 * (1.0 - clampf(legs / 100.0, 0.0, 0.9))
				camera.rotation.z = sin(_wobble_time) * amp
				if balance <= 0.0:
					set_mode("fallen")
			else:
				balance = minf(balance + 0.5 * delta, 1.0)
				camera.rotation.z = lerpf(camera.rotation.z, 0.0, 1.0 - exp(-5.0 * delta))
		elif moving and game != null and game.has_method("add_skill"):
			game.add_skill("legs", 0.25 * delta)
			camera.rotation.z = 0.0
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		if _goto_active and direction.length() > 0.1 and not moving and _detour_time <= 0.0:
			_stuck_time += delta
			if _stuck_time > 0.6:  # упёрлись (стул, стол): шаг вбок, потом снова к цели
				_stuck_time = 0.0
				_detour_time = 0.9
				var side := Vector3(-direction.z, 0.0, direction.x) * (1.0 if randf() < 0.5 else -1.0)
				_detour_dir = (side - direction * 0.3).normalized()
		elif moving:
			_stuck_time = 0.0
	if not is_on_floor() and mode != "lie":
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = minf(velocity.y, 0.0)
	if mode != "lie":
		move_and_slide()
	camera.position.y = lerpf(camera.position.y, eye, 1.0 - exp(-EYE_SPEED * delta))
	if _hint != null:
		var near := _nearest_interactable()
		_hint.text = str(near.prompt()) if near != null and near.has_method("prompt") else ""


func reach() -> float:
	return INTERACT_WALK if mode == "walk" else INTERACT_CRAWL


## Ближайший предмет в пределах досягаемости; из нескольких берётся тот, на который смотрит камера.
func _nearest_interactable() -> Node3D:
	var best: Node3D = null
	var best_score := -INF
	var look := look_dir()
	for node in get_tree().get_nodes_in_group("ls_interact"):
		if not (node is Node3D) or not node.has_method("interact"):
			continue
		if node.has_method("is_available") and not node.is_available(self):
			continue
		var target := (node as Node3D).global_position
		var size: Vector3 = node.get_meta("size", Vector3(0.3, 0.3, 0.3))
		target.y += minf(size.y * 0.5, 0.8)
		var d := global_position.distance_to(target)
		if d > reach() + 0.3:
			continue
		var aim := look.dot((target - camera.global_position).normalized())
		var score := aim * 4.0 - d  # главное — куда смотришь, потом расстояние
		if score > best_score:
			best_score = score
			best = node
	return best


func interact_nearest() -> void:
	if mode == "fallen":
		return
	var near := _nearest_interactable()
	if near != null:
		near.interact(self)


## Автопилот самопроверки: пойти к точке (вернёт true, когда дошёл).
func goto(point: Vector3) -> bool:
	if mode == "lie":
		return false
	var flat := point - global_position
	flat.y = 0.0
	if flat.length() < GOTO_TOLERANCE:
		_goto_active = false
		return true
	_goto_target = point
	_goto_active = true
	return false


func stop_goto() -> void:
	_goto_active = false


## Повернуть тело и камеру на точку (автопилот смотрит на предмет перед тем, как нажать E).
func aim_at(point: Vector3) -> void:
	var to := point - camera.global_position
	rotation.y = atan2(-to.x, -to.z)
	camera.rotation.x = clampf(atan2(to.y, Vector2(to.x, to.z).length()), deg_to_rad(-80.0), deg_to_rad(80.0))


## Переставить малыша (например, мама вынула из кроватки) и повернуть по оси Y (радианы).
func teleport(point: Vector3, yaw: float) -> void:
	global_position = point
	rotation.y = yaw
	camera.rotation.x = 0.0
	velocity = Vector3.ZERO
	_goto_active = false


# --- Инвентарь --------------------------------------------------------------------

func add_item(item_name: String, model: Node3D = null) -> void:
	inventory.append(item_name)
	if held_model != null:
		held_model.queue_free()
		held_model = null
	if model != null:
		held_model = model
		camera.add_child(model)
		model.position = Vector3(0.25, -0.2, -0.5)
		model.rotation = Vector3(0.2, -0.4, 0.0)
	print("Малыш взял: %s (всего предметов %d)" % [item_name, inventory.size()])


func has_item(item_name: String) -> bool:
	return inventory.has(item_name)


func remove_item(item_name: String) -> bool:
	var index := inventory.find(item_name)
	if index < 0:
		return false
	inventory.remove_at(index)
	if held_model != null:
		held_model.queue_free()
		held_model = null
	return true
