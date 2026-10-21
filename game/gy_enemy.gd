extends CharacterBody3D

## Враг «Кладбища»: зомби, скелет, призрак или вампир (модели Graveyard Kit). Идёт к герою по прямой,
## обходя препятствия скольжением; призрак проходит сквозь всё и парит. Рядом с героем бьёт раз в секунду
## (player.take_damage). От снаряда вздрагивает (сжимается), при нуле здоровья зовёт game.on_enemy_died()
## и исчезает. Создаётся кодом: gy_game.gd зовёт setup(kind, stats, game) до добавления в дерево.

const MODELS := "res://assets/kenney/graveyard/models/"
const GRAVITY := 20.0

var kind := "zombie"
var hp := 30.0
var max_hp := 30.0
var speed := 1.7
var damage := 10.0
var xp := 2
var is_ghost := false
var is_boss := false
var game: Node = null

var _model: Node3D
var _arms: Array = []
var _attack_cooldown := 0.0
var _anim := 0.0
var _hit := 0.0
var _size := 1.0


func setup(enemy_kind: String, stats: Dictionary, owner_game: Node) -> void:
	kind = enemy_kind
	game = owner_game
	max_hp = float(stats["hp"])
	hp = max_hp
	speed = float(stats["speed"]) * randf_range(0.9, 1.1)
	damage = float(stats["damage"])
	xp = int(stats["xp"])
	_size = float(stats["scale"])
	is_ghost = bool(stats.get("ghost", false))
	is_boss = bool(stats.get("boss", false))
	_anim = randf_range(0, TAU)


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 2 if is_ghost else (1 | 2 | 4)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.2 * _size
	capsule.height = 0.8 * _size
	shape.shape = capsule
	shape.position = Vector3(0, 0.4 * _size, 0)
	add_child(shape)
	var path := MODELS + kind + ".glb"
	if ResourceLoader.exists(path):
		_model = (load(path) as PackedScene).instantiate()
	else:
		push_warning("Враг: нет модели %s" % path)
		_model = Node3D.new()
	_model.scale = Vector3.ONE * _size
	add_child(_model)
	var box: AABB = game.model_aabb(_model)
	if box.size != Vector3.ZERO:
		_model.position.y -= box.position.y - global_position.y
	for arm_name in ["armLeft", "armRight"]:
		var arm := _model.find_child(arm_name, true, false)
		if arm != null:
			_arms.append(arm)
	if game.test_options.has("debug") and game.enemies.size() < 2:
		var names: Array = []
		for n in _model.find_children("*", "", true, false):
			names.append("%s(%s)" % [n.name, n.get_class()])
		print("Враг %s: узлы %s, коробка %s, поворот тела %s, модель %s" % [kind, ", ".join(names), box, rotation_degrees, _model.rotation_degrees])
	if is_boss:
		var light := OmniLight3D.new()
		light.light_color = Color("#ff3a3a")
		light.light_energy = 0.7
		light.omni_range = 4.5
		light.position = Vector3(0, 0.9 * _size, 0)
		add_child(light)


func _physics_process(delta: float) -> void:
	_anim += delta
	if game == null or str(game.get("state")) != "playing":
		return
	var player: Node3D = game.get("player")
	if player == null:
		return
	var to := player.global_position - global_position
	to.y = 0
	var dist := to.length()
	var dir := to / dist if dist > 0.001 else Vector3.ZERO
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if is_ghost:
		velocity.y = 0.0
		global_position.y = 0.3 + sin(_anim * 2.0) * 0.15
	elif is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if dir != Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-8.0 * delta))
	_attack_cooldown -= delta
	if dist < 0.55 + 0.35 * _size and _attack_cooldown <= 0.0:
		_attack_cooldown = 1.0
		player.take_damage(damage)
	var swing := sin(_anim * 6.0) * 0.35
	for i in _arms.size():
		_arms[i].rotation.x = -0.6 + swing * (1.0 if i == 0 else -1.0)
	if _hit > 0.0:
		_hit -= delta
		var squash := 1.0 - 0.25 * clampf(_hit / 0.12, 0.0, 1.0)
		_model.scale = Vector3(_size * (2.0 - squash), _size * squash, _size * (2.0 - squash))
	else:
		_model.scale = Vector3.ONE * _size


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	_hit = 0.12
	game.play_sound("hit")
	if hp <= 0.0:
		game.on_enemy_died(self)
		queue_free()
