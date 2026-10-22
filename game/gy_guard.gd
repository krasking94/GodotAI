extends Node3D

## Стражник форпоста: блочный человечек Kenney в форме солдата стоит у забора и стреляет снарядами
## (gy_bolt.gd) в ближайшего нападающего в пределах range. Создаётся кодом из gy_base.gd:
## guard.game = game, затем add_child. Не ходит, только поворачивается к цели.

const CHARACTER := "res://assets/kenney/characters/basicCharacter.gltf"
const SKIN := "res://assets/kenney/characters/skins/skin_soldier.png"
const Bolt := preload("res://game/gy_bolt.gd")

static var _material: StandardMaterial3D

var game: Node = null
var shoot_range := 8.0
var damage := 11.0
var interval := 1.0

var _timer := 0.0
var _model: Node3D
var _facing := 0.0
var _arm_right: Node3D


func _ready() -> void:
	if ResourceLoader.exists(CHARACTER):
		_model = (load(CHARACTER) as PackedScene).instantiate()
	else:
		_model = Node3D.new()
	_model.scale = Vector3.ONE * 0.1
	add_child(_model)
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_material.roughness = 1.0
		if ResourceLoader.exists(SKIN):
			_material.albedo_texture = load(SKIN)
	for mesh in _model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = _material
	# Правая рука вытянута вперёд: шарнир в плече.
	var arm := _model.find_child("ArmRight1", true, false)
	if arm != null:
		var pivot := Node3D.new()
		pivot.position = Vector3(-3, 12, 0)
		arm.get_parent().add_child(pivot)
		arm.reparent(pivot, false)
		arm.position = Vector3(3, -12, 0)
		pivot.rotation.x = -1.4
		_arm_right = pivot
	_timer = randf_range(0.0, interval)
	_facing = rotation.y


func _physics_process(delta: float) -> void:
	if game == null:
		return
	var target: Node3D = null
	var best := shoot_range * shoot_range
	for enemy in game.get("enemies"):
		if not is_instance_valid(enemy):
			continue
		var d: float = global_position.distance_squared_to(enemy.global_position)
		if d < best:
			best = d
			target = enemy
	if target != null:
		var to := target.global_position - global_position
		to.y = 0
		if to.length() > 0.01:
			_facing = atan2(to.x, to.z)
	rotation.y = lerp_angle(rotation.y, _facing, 1.0 - exp(-10.0 * delta))
	if _arm_right != null:
		_arm_right.rotation.x = lerpf(_arm_right.rotation.x, -1.5 if target != null else -0.2, 1.0 - exp(-8.0 * delta))
	_timer -= delta
	if target == null or _timer > 0.0:
		return
	_timer = interval
	var dir := target.global_position - global_position
	dir.y = 0
	var bolt := Bolt.new()
	bolt.setup(dir.normalized(), 16.0, damage, 1)
	bolt.game = game
	var bolts_root: Node = game.get("bolts_root")
	bolts_root.add_child(bolt)
	bolt.global_position = global_position + Vector3(0, 1.1, 0) + dir.normalized() * 0.6
