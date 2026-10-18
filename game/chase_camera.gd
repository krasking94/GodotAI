extends Camera3D

## Камера-преследователь: едет за целью (машиной) сзади и сверху, смотрит на неё
## и не наклоняется вместе с кузовом, поэтому горизонт остаётся ровным.

@export var target: NodePath
@export var distance := 7.0
@export var height := 3.0
@export var smoothing := 4.0

var _target: Node3D


func _ready() -> void:
	_target = get_node_or_null(target) as Node3D
	if _target != null:
		global_position = _desired_position()


func _physics_process(delta: float) -> void:
	if _target == null:
		return
	global_position = global_position.lerp(_desired_position(), clampf(smoothing * delta, 0.0, 1.0))
	look_at(_target.global_position + Vector3.UP * 0.5, Vector3.UP)


func _desired_position() -> Vector3:
	var forward := _target.global_transform.basis.z  # у VehicleBody3D вперёд = +Z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = Vector3.BACK
	return _target.global_position - forward.normalized() * distance + Vector3.UP * height
