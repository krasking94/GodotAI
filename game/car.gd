extends VehicleBody3D

## Машина на упрощённой физике Godot (VehicleBody3D: кузов + четыре VehicleWheel3D).
## Управление, пока active: W/S (или стрелки) — газ и задний ход, A/D — руль, пробел — тормоз.
## test_drive > 0: первые столько секунд машина сама едет вперёд, потом печатает,
## сколько проехала и с какой скоростью; по этой строке ИИ проверяет в логе, что машина едет.

const ENGINE_FORCE := 600.0
const BRAKE_FORCE := 40.0
const MAX_STEER := 0.5  # радианы, около 29 градусов
const STEER_SPEED := 3.0

@export var active := true
@export var test_drive := 0.0

var _time := 0.0
var _start := Vector3.ZERO
var _reported := false


func _ready() -> void:
	_start = global_position


func _physics_process(delta: float) -> void:
	_time += delta
	var gas := 0.0
	var steer_input := 0.0
	var braking := false
	if test_drive > 0.0 and _time < test_drive:
		gas = 1.0
	elif active:
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			gas += 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			gas -= 1.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			steer_input += 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			steer_input -= 1.0
		braking = Input.is_physical_key_pressed(KEY_SPACE)
	engine_force = gas * ENGINE_FORCE
	steering = move_toward(steering, steer_input * MAX_STEER, STEER_SPEED * delta)
	brake = BRAKE_FORCE if braking else 0.0

	if test_drive > 0.0 and not _reported and _time >= test_drive:
		_reported = true
		var distance := global_position.distance_to(_start)
		print("Машина: проехала %.1f м за %.1f с, скорость %.1f м/с" % [distance, test_drive, linear_velocity.length()])
