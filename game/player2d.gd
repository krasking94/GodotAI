extends CharacterBody2D

## Персонаж для 2D-примера (платформер), управление только стрелками: ← → ходьба, ↑ прыжок, ↓ присесть
## (пробел или Enter тоже прыгают). Пример независим от 3D-демо: читает встроенные действия Godot
## ui_left / ui_right / ui_up / ui_down / ui_accept, поэтому работает в любом новом проекте без карты действий.
##
## В приседе капсула 48 → 28 px (ноги остаются на месте), скорость ниже, прыгать нельзя; встать можно,
## только если над головой свободно (проверка формой в слое 1), иначе в журнал пишется «встать нельзя».
##
## Враг (enemy2d.gd) вызывает hurt(): жизнь отнимает hud2d.gd (lose_life), персонаж возвращается на старт
## и 2 секунды мигает (неуязвим); если жизни кончились, персонаж замирает (is_hurt), дальше R или Enter.
##
## Самопроверка для ИИ: --test-player2d=jumpright:1.1,jumpright:1.1,crawl:2,stand:0.5
## (фазы right, left, jump, jumpright, jumpleft, crouch, crawl, stand, wait; секунды после двоеточия).
## Прыжок в фазе «ждёт пола»: если в момент начала фазы персонаж ещё в воздухе, он прыгнет, как только
## приземлится. После каждой фазы печатается «Персонаж 2D [фаза]: позиция, на полу, скорость, поза».

const SPEED := 220.0
const CROUCH_SPEED := 110.0
const JUMP_SPEED := -650.0  # высота прыжка ≈ 215 px при стандартной гравитации 980; ступеньки уровня по 160 px
const STAND_HEIGHT := 48.0
const CROUCH_HEIGHT := 28.0
const FALL_LIMIT_Y := 2000.0  # ниже этой точки персонаж упал с уровня и возвращается на старт
const INVULNERABLE_TIME := 2.0

@export var test_program := ""

var is_crouched := false
var is_hurt := false

var _dead := false
var _invulnerable := 0.0
var _hud: Node = null

var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
var _phases: Array = []
var _phase_index := 0
var _phase_time := 0.0
var _phase_start := Vector2.ZERO
var _phase_top_y := 0.0  # самая высокая точка за фазу (в 2D вверх — это меньший y)
var _jump_pending := false
var _stand_blocked := false
var _start_position := Vector2.ZERO
var _shape_node: CollisionShape2D = null
var _look: ColorRect = null
var _stand_shape: CapsuleShape2D = null
var _crouch_shape: CapsuleShape2D = null


func _ready() -> void:
	_start_position = global_position
	for child in get_children():
		if child is CollisionShape2D and _shape_node == null:
			_shape_node = child
		elif child is ColorRect and _look == null:
			_look = child
	if _shape_node != null and _shape_node.shape is CapsuleShape2D:
		_stand_shape = _shape_node.shape
		_crouch_shape = _stand_shape.duplicate()
		_crouch_shape.height = CROUCH_HEIGHT
	var prefix := "--test-player2d="
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			test_program = arg.trim_prefix(prefix)
	for part in test_program.split(",", false):
		var pair := part.strip_edges().split(":")
		if pair.size() == 2 and pair[1].is_valid_float():
			_phases.append({"name": pair[0].strip_edges(), "seconds": float(pair[1])})
	_phase_start = global_position
	_phase_top_y = global_position.y
	_hud = get_tree().root.find_child("Hud", true, false)
	if not _phases.is_empty():
		_jump_pending = _phases[0]["name"].begins_with("jump")
	print("Персонаж 2D готов: позиция %s" % global_position.round())


func _physics_process(delta: float) -> void:
	var direction := 0.0
	var jump := false
	var wants_crouch := false
	if _phase_index < _phases.size():
		var phase: Dictionary = _phases[_phase_index]
		match phase["name"]:
			"right":
				direction = 1.0
			"left":
				direction = -1.0
			"jumpright":
				direction = 1.0
			"jumpleft":
				direction = -1.0
			"crouch":
				wants_crouch = true
			"crawl":
				wants_crouch = true
				direction = 1.0
		jump = _jump_pending
		_phase_time += delta
		_phase_top_y = minf(_phase_top_y, global_position.y)
		if _phase_time >= phase["seconds"]:
			print("Персонаж 2D [%s %.1f с]: позиция %s, на полу=%s, скорость %s, путь %.0f, подъём %.0f, поза %s" % [
				phase["name"], phase["seconds"], global_position.round(), is_on_floor(), velocity.round(),
				global_position.distance_to(_phase_start), _phase_start.y - _phase_top_y,
				"присед" if is_crouched else "стоя"])
			_phase_index += 1
			_phase_time = 0.0
			_phase_start = global_position
			_phase_top_y = global_position.y
			_jump_pending = _phase_index < _phases.size() and _phases[_phase_index]["name"].begins_with("jump")
	else:
		direction = Input.get_axis("ui_left", "ui_right")
		jump = Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_accept")
		wants_crouch = Input.is_action_pressed("ui_down")
	if _dead:  # жизни кончились: стоим, ждём перезапуска
		direction = 0.0
		jump = false
		wants_crouch = false
	if _invulnerable > 0.0:
		_invulnerable -= delta
		is_hurt = _invulnerable > INVULNERABLE_TIME - 0.6
		var look := get_node_or_null("Look")
		if look != null:
			look.modulate.a = 1.0 if _invulnerable <= 0.0 or fmod(_invulnerable, 0.2) < 0.1 else 0.4

	_update_crouch(wants_crouch)
	if not is_on_floor():
		velocity.y += _gravity * delta
	elif jump and not is_crouched:
		velocity.y = JUMP_SPEED
		_jump_pending = false
		if _hud != null and _hud.has_method("play_sound"):
			_hud.play_sound("jump")
	velocity.x = direction * (CROUCH_SPEED if is_crouched else SPEED)
	move_and_slide()
	if global_position.y > FALL_LIMIT_Y:
		print("Персонаж 2D упал с уровня, возвращаю на старт")
		global_position = _start_position
		velocity = Vector2.ZERO


func _update_crouch(wants: bool) -> void:
	if _crouch_shape == null:
		return
	if wants and not is_crouched:
		_set_crouched(true)
	elif not wants and is_crouched:
		if _headroom_free():
			_set_crouched(false)
		elif not _stand_blocked:
			_stand_blocked = true
			print("Персонаж 2D: встать нельзя, сверху препятствие")


func _set_crouched(crouched: bool) -> void:
	is_crouched = crouched
	_stand_blocked = false
	var drop := (STAND_HEIGHT - CROUCH_HEIGHT) * 0.5  # капсула короче, но ноги должны остаться на полу
	_shape_node.shape = _crouch_shape if crouched else _stand_shape
	_shape_node.position.y = drop if crouched else 0.0
	if _look != null:
		_look.size.y = CROUCH_HEIGHT if crouched else STAND_HEIGHT
		_look.position.y = -STAND_HEIGHT * 0.5 + (STAND_HEIGHT - CROUCH_HEIGHT if crouched else 0.0)
	print("Персонаж 2D присел" if crouched else "Персонаж 2D встал")


## Свободно ли место для полной капсулы над ногами (слой 1, сам персонаж не считается).
func _headroom_free() -> bool:
	var probe := CapsuleShape2D.new()
	probe.radius = _stand_shape.radius
	probe.height = STAND_HEIGHT - 2.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = probe
	query.transform = Transform2D(0.0, global_position + Vector2(0.0, -1.0))
	query.exclude = [get_rid()]
	query.collision_mask = 1
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


## Ранение от врага: жизнь отнимает Hud; возвращаемся на старт и две секунды мигаем.
func hurt() -> void:
	if _dead or _invulnerable > 0.0:
		return
	var dead := false
	if _hud != null and _hud.has_method("lose_life"):
		dead = _hud.lose_life()
	if dead:
		_dead = true
		is_hurt = true
		velocity.x = 0.0
		print("Персонаж 2D: жизни кончились")
		return
	print("Персонаж 2D ранен, возвращаюсь на старт")
	_invulnerable = INVULNERABLE_TIME
	is_hurt = true
	if is_crouched:
		_set_crouched(false)
	global_position = _start_position
	velocity = Vector2.ZERO
