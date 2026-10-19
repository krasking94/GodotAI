extends CharacterBody2D

## Персонаж для 2D-примера (платформер): стрелки влево/вправо — ходьба, пробел или Enter — прыжок.
## Пример независим от 3D-демо: читает встроенные действия Godot ui_left / ui_right / ui_accept,
## поэтому работает в любом новом проекте без карты действий.
##
## Самопроверка для ИИ: --test-player2d=right:1,jump:0.5,left:1 (фазы right, left, jump, wait;
## секунды после двоеточия). После каждой фазы печатается «Персонаж 2D [фаза]: позиция, на полу, скорость».

const SPEED := 220.0
const JUMP_SPEED := -420.0
const FALL_LIMIT_Y := 2000.0  # ниже этой точки персонаж упал с уровня и возвращается на старт

@export var test_program := ""

var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
var _phases: Array = []
var _phase_index := 0
var _phase_time := 0.0
var _phase_start := Vector2.ZERO
var _phase_top_y := 0.0  # самая высокая точка за фазу (в 2D вверх — это меньший y)
var _start_position := Vector2.ZERO


func _ready() -> void:
	_start_position = global_position
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
	print("Персонаж 2D готов: позиция %s" % global_position.round())


func _physics_process(delta: float) -> void:
	var direction := 0.0
	var jump := false
	if _phase_index < _phases.size():
		var phase: Dictionary = _phases[_phase_index]
		match phase["name"]:
			"right":
				direction = 1.0
			"left":
				direction = -1.0
			"jump":
				jump = _phase_time == 0.0
		_phase_time += delta
		_phase_top_y = minf(_phase_top_y, global_position.y)
		if _phase_time >= phase["seconds"]:
			print("Персонаж 2D [%s %.1f с]: позиция %s, на полу=%s, скорость %s, путь %.0f, подъём %.0f" % [phase["name"],
				phase["seconds"], global_position.round(), is_on_floor(), velocity.round(),
				global_position.distance_to(_phase_start), _phase_start.y - _phase_top_y])
			_phase_index += 1
			_phase_time = 0.0
			_phase_start = global_position
			_phase_top_y = global_position.y
	else:
		direction = Input.get_axis("ui_left", "ui_right")
		jump = Input.is_action_just_pressed("ui_accept")

	if not is_on_floor():
		velocity.y += _gravity * delta
	elif jump:
		velocity.y = JUMP_SPEED
	velocity.x = direction * SPEED
	move_and_slide()
	if global_position.y > FALL_LIMIT_Y:
		print("Персонаж 2D упал с уровня, возвращаю на старт")
		global_position = _start_position
		velocity = Vector2.ZERO
