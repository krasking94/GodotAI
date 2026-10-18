extends CharacterBody3D

## Персонаж от первого лица.
## Управление: W A S D (или стрелки) — ходьба, мышь — обзор, пробел — прыжок,
## Esc — отпустить мышь, щелчок по окну игры — снова захватить.
## Через секунду после старта печатает, стоит ли на полу: по этой строке ИИ
## проверяет в логе, что персонаж не провалился.

const SPEED := 4.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.003
const FALL_LIMIT_Y := -10.0  # ниже этой высоты считаем, что упал за край двора
const REPORT_AFTER := 1.0

@onready var camera: Camera3D = $Camera
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _start_position := Vector3.ZERO
var _time := 0.0
var _reported := false


func _ready() -> void:
	_start_position = position
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-80.0), deg_to_rad(80.0))
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseButton and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_physical_key_pressed(KEY_SPACE):
		velocity.y = JUMP_VELOCITY

	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input.x += 1.0
	var direction := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED
	move_and_slide()

	if position.y < FALL_LIMIT_Y:
		print("Персонаж упал за край двора, возвращаю на старт")
		position = _start_position
		velocity = Vector3.ZERO

	_time += delta
	if not _reported and _time >= REPORT_AFTER:
		_reported = true
		print("Персонаж: на полу=%s, позиция=%s" % [is_on_floor(), position.snapped(Vector3(0.01, 0.01, 0.01))])
