extends CharacterBody3D

## «Симулятор жизни»: герой от первого лица в младенчестве.
## Режимы (mode): "lie" — лежит в кроватке, только крутит головой; "crawl" — ползёт (камера низко, медленно);
## "walk" — ходит на ножках: камера выше, быстрее, но есть равновесие (balance): оно тратится при ходьбе
## тем быстрее, чем слабее навык «Ноги», и при нуле малыш падает (режим "fallen" на секунду, потом снова
## ползёт). Каждое падение и каждый шаг прокачивают «Ноги» (через game.add_skill).
## Управление: W A S D / стрелки / левый стик — движение; мышь / правый стик — обзор; E / кнопка A — взять
## или поговорить; Пробел / X — встать и сесть; H / Y — лампочка; Esc / Start — пауза. Чувствительность,
## инверсия и покачивание головы берутся из настроек (set_settings). Движение только в _physics_process:
## разгон и торможение плавные, голова покачивается в такт шагам, шаги звучат (game.play_step).
## Перед глазами видны ручки малыша (качаются при ползании и ходьбе, держат поднятый предмет);
## предмет, на который смотришь и до которого дотянешься, подсвечивается жёлтым.
## Для самопроверки у героя есть goto(point) — автопилот идёт к точке, и interact_nearest().

const CRAWL_SPEED := 1.2
const WALK_SPEED := 2.1
const ACCEL := 9.0            # как быстро набирает скорость (1/с)
const DECEL := 13.0           # как быстро останавливается
const CRAWL_EYE := 0.45       # высота глаз над полом, когда ползёт
const WALK_EYE := 0.85        # высота глаз на ножках (малыш ростом около метра)
const LIE_EYE := 0.75         # глаза, когда лежит в кроватке (матрас приподнят)
const FALL_EYE := 0.28
const EYE_SPEED := 6.0
const MOUSE_BASE := 0.0022    # радиан на пиксель при чувствительности 1.0
const STICK_SPEED := 2.4      # радиан в секунду на полном отклонении правого стика
const GRAVITY := 14.0
const FALL_SECONDS := 1.4
const INTERACT_CRAWL := 1.1
const INTERACT_WALK := 1.5
const GOTO_TOLERANCE := 0.3
const Actions := preload("res://game/actions.gd")  # клавиши W A S D, E, Пробел, Esc — если в project.godot их нет

var game: Node = null  # корень сцены (ls_game.gd)
var mode := "lie"
var can_walk := false      # открыл ли малыш ходьбу (квест «Встань на ножки»)
var balance := 1.0         # 0..1, равновесие при ходьбе
var legs := 0.0            # копия навыка «Ноги» 0..100 (обновляет game)
var inventory: Array[String] = []
var held_model: Node3D = null  # поднятый предмет виден перед глазами
var steps_walked := 0.0
var falls := 0
var settings := {"sensitivity": 1.0, "invert_y": false, "head_bob": true}
var _fall_time := 0.0
var _wobble_time := 0.0
var _bob := 0.0            # фаза покачивания головы
var _bob_amp := 0.0
var _goto_target := Vector3.ZERO
var _goto_active := false
var _stuck_time := 0.0
var _detour_time := 0.0
var _detour_dir := Vector3.ZERO
var _hint: Label
var _target: Node3D = null         # подсвеченный предмет
var _highlight: StandardMaterial3D
var _hands: Node3D
var _hand_left: Node3D
var _hand_right: Node3D
var _hand_swing := 0.0

@onready var camera: Camera3D = $Camera
@onready var shape_node: CollisionShape3D = $Shape


func _ready() -> void:
	Actions.ensure()
	_ensure_gamepad()
	add_to_group("player")
	if not DisplayServer.is_touchscreen_available() and not _is_batch():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera.position.y = LIE_EYE
	camera.fov = 80.0
	_highlight = StandardMaterial3D.new()
	_highlight.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight.albedo_color = Color(1.0, 0.9, 0.3, 0.28)
	_highlight.emission_enabled = true
	_highlight.emission = Color(1.0, 0.85, 0.2)
	_highlight.emission_energy_multiplier = 0.6
	_highlight.cull_mode = BaseMaterial3D.CULL_DISABLED
	_build_hands()


static func _is_batch() -> bool:
	return DisplayServer.get_name() == "headless"


## Геймпад: левый стик — движение, правый — обзор, A — взять, X — встать, Y — лампочка, Start — пауза.
## Действия добавляются только в память игры (на карту клавиш проекта не влияют).
static func _ensure_gamepad() -> void:
	var extra := {
		"ls_look_left": [["axis", JOY_AXIS_RIGHT_X, -1.0]],
		"ls_look_right": [["axis", JOY_AXIS_RIGHT_X, 1.0]],
		"ls_look_up": [["axis", JOY_AXIS_RIGHT_Y, -1.0]],
		"ls_look_down": [["axis", JOY_AXIS_RIGHT_Y, 1.0]],
		"ls_lamp": [["key", KEY_H], ["button", JOY_BUTTON_Y]],
		"ls_fullscreen": [["key", KEY_F11]],
		"move_left": [["axis", JOY_AXIS_LEFT_X, -1.0]],
		"move_right": [["axis", JOY_AXIS_LEFT_X, 1.0]],
		"move_forward": [["axis", JOY_AXIS_LEFT_Y, -1.0]],
		"move_back": [["axis", JOY_AXIS_LEFT_Y, 1.0]],
		"interact": [["button", JOY_BUTTON_A]],
		"jump": [["button", JOY_BUTTON_X]],
		"pause": [["button", JOY_BUTTON_START]],
	}
	for action in extra:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		for spec in extra[action]:
			var event: InputEvent
			match str(spec[0]):
				"axis":
					var motion := InputEventJoypadMotion.new()
					motion.axis = int(spec[1])
					motion.axis_value = float(spec[2])
					event = motion
				"button":
					var button := InputEventJoypadButton.new()
					button.button_index = int(spec[1])
					event = button
				_:
					var key := InputEventKey.new()
					key.physical_keycode = int(spec[1])
					event = key
			event.device = -1
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)


func set_settings(new_settings: Dictionary) -> void:
	for key in new_settings:
		settings[key] = new_settings[key]


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
		camera.rotation.z = 0.45 * (1.0 if randf() < 0.5 else -1.0)
		print("Малыш упал (падение №%d)" % falls)
		if game != null and game.has_method("on_fall"):
			game.on_fall()


func set_hint(label: Label) -> void:
	_hint = label


## Куда смотрит (единичный вектор взгляда камеры в мире).
func look_dir() -> Vector3:
	return -camera.global_transform.basis.z


func _ui_open() -> bool:
	return game != null and game.has_method("ui_blocks_mouse") and game.ui_blocks_mouse()


## Обзор мышью читается в _input, а не в _unhandled_input: иначе движение мыши съедают панели экрана
## (захваченный курсор стоит в центре окна, прямо на прицеле), и голова не поворачивается.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if _ui_open():
			return
		var k: float = MOUSE_BASE * float(settings.get("sensitivity", 1.0))
		var invert: float = -1.0 if bool(settings.get("invert_y", false)) else 1.0
		_turn(-event.relative.x * k, -event.relative.y * k * invert)


func _turn(yaw: float, pitch: float) -> void:
	rotate_y(yaw)
	camera.rotate_x(pitch)
	camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-80.0), deg_to_rad(80.0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if game != null and game.has_method("toggle_pause"):
			game.toggle_pause()
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
	if event.is_action_pressed("ls_fullscreen"):
		if game != null and game.has_method("toggle_fullscreen"):
			game.toggle_fullscreen()
		return
	if _ui_open():
		return
	if event.is_action_pressed("interact"):
		interact_nearest()
	elif event.is_action_pressed("jump"):
		toggle_stand()
	elif event.is_action_pressed("ls_lamp"):
		if game != null and game.has_method("toggle_lamp"):
			game.toggle_lamp()
	elif event is InputEventMouseButton and event.pressed and not DisplayServer.is_touchscreen_available():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Пробел: встать на ножки (если ходьба открыта) или снова сесть на пол.
func toggle_stand() -> void:
	if mode == "crawl" and can_walk:
		set_mode("walk")
		if game != null and game.has_method("play_sound"):
			game.play_sound("stand")
	elif mode == "walk":
		set_mode("crawl")
	elif mode == "crawl" and not can_walk and game != null and game.has_method("on_try_stand"):
		game.on_try_stand()


func _physics_process(delta: float) -> void:
	var paused_ui := _ui_open()
	var eye := LIE_EYE
	var input := Vector2.ZERO
	var moving := false
	var speed := 0.0
	if mode == "lie":
		velocity = Vector3.ZERO
	elif mode == "fallen":
		_fall_time -= delta
		eye = FALL_EYE
		velocity.x = lerpf(velocity.x, 0.0, 1.0 - exp(-DECEL * delta))
		velocity.z = lerpf(velocity.z, 0.0, 1.0 - exp(-DECEL * delta))
		camera.rotation.z = lerpf(camera.rotation.z, 0.0, 1.0 - exp(-2.0 * delta))
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
			# Правый стик геймпада — обзор.
			var look := Input.get_vector("ls_look_left", "ls_look_right", "ls_look_up", "ls_look_down")
			if look.length() > 0.05:
				var invert: float = -1.0 if bool(settings.get("invert_y", false)) else 1.0
				var k: float = STICK_SPEED * float(settings.get("sensitivity", 1.0)) * delta
				_turn(-look.x * k, -look.y * k * invert)
		var direction := (transform.basis * Vector3(input.x, 0.0, input.y)).limit_length(1.0)
		speed = WALK_SPEED if mode == "walk" else CRAWL_SPEED
		if mode == "walk":
			speed *= 0.7 + 0.3 * balance
		# Плавный разгон и торможение.
		var wanted := direction * speed
		var rate := ACCEL if direction.length() > 0.1 else DECEL
		velocity.x = lerpf(velocity.x, wanted.x, 1.0 - exp(-rate * delta))
		velocity.z = lerpf(velocity.z, wanted.z, 1.0 - exp(-rate * delta))
		var real := get_real_velocity()
		var real_speed := Vector2(real.x, real.z).length()
		moving = direction.length() > 0.1 and real_speed > 0.15  # упёрся в стену — не идёт
		if mode == "walk":
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
			camera.rotation.z = lerpf(camera.rotation.z, 0.0, 1.0 - exp(-5.0 * delta))
		if _goto_active and direction.length() > 0.1 and not moving and _detour_time <= 0.0:
			_stuck_time += delta
			if _stuck_time > 0.6:  # упёрлись (стул, стол): шаг вбок, потом снова к цели
				_stuck_time = 0.0
				_detour_time = 0.9
				var side := Vector3(-direction.z, 0.0, direction.x) * (1.0 if randf() < 0.5 else -1.0)
				_detour_dir = (side - direction * 0.3).normalized()
		elif moving:
			_stuck_time = 0.0
		_update_bob(delta, moving, real_speed)
	if not is_on_floor() and mode != "lie":
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = minf(velocity.y, 0.0)
	if mode != "lie":
		move_and_slide()
	var bob_y := sin(_bob * 2.0) * _bob_amp if bool(settings.get("head_bob", true)) else 0.0
	var bob_x := sin(_bob) * _bob_amp * 0.6 if bool(settings.get("head_bob", true)) else 0.0
	camera.position.y = lerpf(camera.position.y, eye + bob_y, 1.0 - exp(-EYE_SPEED * delta))
	camera.position.x = lerpf(camera.position.x, bob_x, 1.0 - exp(-EYE_SPEED * delta))
	_update_hands(delta, moving)
	_update_target()


## Покачивание головы в такт шагам и звук шага в нижней точке.
func _update_bob(delta: float, moving: bool, real_speed: float) -> void:
	var target_amp := 0.0
	if moving:
		target_amp = 0.028 if mode == "walk" else 0.014
		var rate := (7.5 if mode == "walk" else 5.0) * clampf(real_speed / 1.5, 0.5, 1.4)
		var before := fmod(_bob, PI)
		_bob += delta * rate
		if fmod(_bob, PI) < before:  # прошли нижнюю точку — шаг
			if game != null and game.has_method("play_step"):
				game.play_step(mode)
	_bob_amp = lerpf(_bob_amp, target_amp, 1.0 - exp(-8.0 * delta))


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
		if aim < 0.2:
			continue  # за спиной не берём
		var score := aim * 4.0 - d  # главное — куда смотришь, потом расстояние
		if score > best_score:
			best_score = score
			best = node
	return best


## Подсветка цели и подсказка внизу экрана.
func _update_target() -> void:
	var near := _nearest_interactable() if mode != "fallen" else null
	if near != _target:
		_set_highlight(_target, false)
		_set_highlight(near, true)
		_target = near
	if _hint != null:
		_hint.text = str(near.prompt()) if near != null and near.has_method("prompt") else ""


func _set_highlight(node: Node3D, on: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_overlay = _highlight if on else null


func interact_nearest() -> void:
	if mode == "fallen":
		return
	var near := _nearest_interactable()
	if near != null:
		_hand_swing = 1.0  # ручка тянется к предмету
		near.interact(self)
	elif game != null and game.has_method("on_interact_nothing"):
		game.on_interact_nothing()


# --- Ручки малыша перед глазами -------------------------------------------------------------------

func _build_hands() -> void:
	_hands = Node3D.new()
	_hands.name = "Hands"
	camera.add_child(_hands)
	_hand_left = _hand(Vector3(-0.23, -0.31, -0.46))
	_hand_right = _hand(Vector3(0.23, -0.31, -0.46))
	_hands.visible = false


func _hand(pos: Vector3) -> Node3D:
	var hand := Node3D.new()
	hand.position = pos
	_hands.add_child(hand)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("#f7cdb0")
	skin.roughness = 0.9
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = Color("#9ad4ff")
	sleeve.roughness = 1.0
	var palm := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.034
	capsule.height = 0.12
	palm.mesh = capsule
	palm.material_override = skin
	palm.rotation.x = deg_to_rad(80.0)
	palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hand.add_child(palm)
	for i in 3:  # три пальчика
		var finger := MeshInstance3D.new()
		var fm := CapsuleMesh.new()
		fm.radius = 0.011
		fm.height = 0.055
		finger.mesh = fm
		finger.material_override = skin
		finger.rotation.x = deg_to_rad(80.0)
		finger.position = Vector3(-0.022 + 0.022 * i, 0.0, -0.075)
		finger.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hand.add_child(finger)
	var cuff := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.038
	cm.bottom_radius = 0.042
	cm.height = 0.07
	cuff.mesh = cm
	cuff.material_override = sleeve
	cuff.rotation.x = deg_to_rad(80.0)
	cuff.position = Vector3(0, 0.012, 0.085)
	cuff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hand.add_child(cuff)
	return hand


func _update_hands(delta: float, moving: bool) -> void:
	if _hands == null:
		return
	_hands.visible = mode != "lie"
	if not _hands.visible:
		return
	_hand_swing = maxf(_hand_swing - delta * 3.0, 0.0)
	var crawl := mode == "crawl" or mode == "fallen"
	var base_l := Vector3(-0.23, -0.33, -0.44) if crawl else Vector3(-0.23, -0.29, -0.46)
	var base_r := Vector3(0.23, -0.33, -0.44) if crawl else Vector3(0.23, -0.29, -0.46)
	if held_model != null:
		base_r = Vector3(0.24, -0.29, -0.5)
	var swing := sin(_bob) * (0.06 if moving else 0.0)
	var breathe := sin(Time.get_ticks_msec() * 0.002) * 0.004
	var reach_offset := Vector3(0, 0.04, -0.08) * _hand_swing
	var l := base_l + Vector3(0, swing * 0.5 + breathe, swing)
	var r := base_r + Vector3(0, -swing * 0.5 + breathe, -swing) + reach_offset
	_hand_left.position = _hand_left.position.lerp(l, 1.0 - exp(-10.0 * delta))
	_hand_right.position = _hand_right.position.lerp(r, 1.0 - exp(-10.0 * delta))
	# Ладошки чуть приподняты к глазам, чтобы были видны пальчики, а не только рукава.
	var tilt := -0.25 if crawl else -0.55
	_hand_left.rotation.x = lerpf(_hand_left.rotation.x, tilt + swing, 1.0 - exp(-8.0 * delta))
	_hand_right.rotation.x = lerpf(_hand_right.rotation.x, tilt - swing, 1.0 - exp(-8.0 * delta))


# --- Автопилот и перемещения --------------------------------------------------------------------

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
		model.position = Vector3(0.24, -0.2, -0.5)
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
