extends Area3D

## Снаряд героя «Кладбища»: светящийся шарик, летит по прямой 1,4 с, бьёт врагов из группы enemies
## (take_damage), после pierce попаданий исчезает. Создаётся кодом из gy_hero.gd: setup(), затем add_child.

static var _material: StandardMaterial3D

var game: Node = null  # ведущий раунда (gy_game.gd), для искр при попадании

var _dir := Vector3.FORWARD
var _speed := 15.0
var _damage := 12.0
var _pierce := 1
var _life := 1.4
var _hit: Array = []


func setup(dir: Vector3, speed: float, damage: float, pierce: int) -> void:
	_dir = dir.normalized()
	_speed = speed
	_damage = damage
	_pierce = maxi(pierce, 1)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 4
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape.shape = sphere
	add_child(shape)
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_color = Color("#ffd080")
		_material.emission_enabled = true
		_material.emission = Color("#ff9a2a")
		_material.emission_energy_multiplier = 3.0
	var mesh := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.14
	ball.height = 0.28
	mesh.mesh = ball
	mesh.material_override = _material
	add_child(mesh)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += _dir * _speed * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("enemies") or _hit.has(body):
		return
	_hit.append(body)
	if game != null:
		game.spawn_sparks(global_position)
	body.take_damage(_damage)
	_pierce -= 1
	if _pierce <= 0:
		queue_free()
