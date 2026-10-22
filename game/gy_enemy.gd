extends CharacterBody3D

## Враг «Кладбища»: зомби, скелет, призрак, вампир и их подкрашенные варианты (гуль, рыцарь-скелет, жнец,
## мерзляк, болотник, горящий, боссы карт) на моделях Graveyard Kit, а также одержимые жители и староста —
## блочные человечки Kenney со скином (model: character). Идёт к герою по прямой, обходя препятствия
## скольжением; призрак проходит сквозь всё и парит. На льду буксует, в грязи вязнет (game.world.speed_factor),
## если не immune к этой луже; призраки парят над лужами. Рядом с героем замахивается (руки вверх, 0,28 с), потом делает выпад и бьёт
## (player.take_damage, искры и звук удара). От снаряда вздрагивает (сжимается), при нуле здоровья зовёт game.on_enemy_died()
## и исчезает. Создаётся кодом: gy_game.gd зовёт setup(kind, stats, game) до добавления в дерево.

const MODELS := "res://assets/kenney/graveyard/models/"
const CHARACTER := "res://assets/kenney/characters/basicCharacter.gltf"
const SKIN_DIR := "res://assets/kenney/characters/skins/"
const GRAVITY := 20.0

var kind := "zombie"
var hp := 30.0
var max_hp := 30.0
var speed := 1.7
var damage := 10.0
var xp := 2
var is_ghost := false
var is_boss := false
var is_elite := false
var is_guard := false  # сторож реликвии: кружит вокруг неё, бьёт на полжизни
var guard_target: Node3D = null
var title := ""
var immune: Array = []  # лужи, которые не замедляют (ice, mud)
var base_target := Vector3.INF  # нападающий на форпост: идёт не к герою, а к этой точке у забора и бьёт забор
var frozen := 0.0  # секунды во льду (Ледяной взрыв): стоит, не бьёт
var game: Node = null

static var _ice_mesh: BoxMesh
static var _ice_material: StandardMaterial3D

static var _tinted := {}  # кэш подкрашенных материалов: ключ «вид:материал»
static var _skins := {}  # кэш материалов человечков: ключ «скин:подкраска»

var _model: Node3D
var _arms: Array = []
var _attack_cooldown := 0.0
var _anim := 0.0
var _hit := 0.0
var _size := 1.0
var _model_name := "zombie"
var _tint := ""
var _light_color := ""
var _windup := 0.0
var _lunge := 0.0
var _orbit := 0.0
var _model_scale := 1.0
var _skin := ""
var _slowed := 0.0
var _knock := Vector3.ZERO  # отбрасывание (Святая волна, Метеор), гаснет за полсекунды
var _ice: MeshInstance3D = null


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
	is_elite = bool(stats.get("elite", false))
	is_guard = bool(stats.get("guard", false))
	title = str(stats.get("title", enemy_kind))
	_model_name = str(stats.get("model", enemy_kind))
	_model_scale = float(stats.get("model_scale", _size))
	_tint = str(stats.get("tint", ""))
	_light_color = str(stats.get("light", ""))
	immune = stats.get("immune", [])
	if is_ghost:
		immune = ["ice", "mud"]
	if stats.has("skins"):
		var skins: Array = stats["skins"]
		_skin = str(skins[randi_range(0, skins.size() - 1)])
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
	var path := CHARACTER if _model_name == "character" else MODELS + _model_name + ".glb"
	if ResourceLoader.exists(path):
		_model = (load(path) as PackedScene).instantiate()
	else:
		push_warning("Враг: нет модели %s" % path)
		_model = Node3D.new()
	_model.scale = Vector3.ONE * _model_scale
	add_child(_model)
	var box: AABB = game.model_aabb(_model)
	if box.size != Vector3.ZERO:
		_model.position.y -= box.position.y - global_position.y
	if _model_name == "character":
		_apply_skin()
	elif _tint != "":
		_apply_tint(Color(_tint))
	for arm_name in ["armLeft", "armRight", "ArmLeft1", "ArmRight1"]:
		var arm := _model.find_child(arm_name, true, false)
		if arm != null:
			if _model_name == "character":
				# У человечка плечо не в начале координат руки: подвешиваем руку на шарнир в плече.
				var joint := Vector3(3, 12, 0) if arm_name == "ArmLeft1" else Vector3(-3, 12, 0)
				var pivot := Node3D.new()
				pivot.position = joint
				arm.get_parent().add_child(pivot)
				arm.reparent(pivot, false)
				arm.position = -joint
				arm = pivot
			_arms.append(arm)
	if game.test_options.has("debug") and game.enemies.size() < 2:
		var names: Array = []
		for n in _model.find_children("*", "", true, false):
			names.append("%s(%s)" % [n.name, n.get_class()])
		print("Враг %s: узлы %s, коробка %s, поворот тела %s, модель %s" % [kind, ", ".join(names), box, rotation_degrees, _model.rotation_degrees])
	if _light_color != "":
		var light := OmniLight3D.new()
		light.light_color = Color(_light_color)
		light.light_energy = 0.7
		light.omni_range = 4.5
		light.position = Vector3(0, 0.9 * _size, 0)
		add_child(light)


## Человечек Kenney: одна картинка-скин на все части, подкраска затемняет (одержимые серые).
func _apply_skin() -> void:
	var key := "%s:%s" % [_skin, _tint]
	if not _skins.has(key):
		var material := StandardMaterial3D.new()
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.roughness = 1.0
		var path := SKIN_DIR + "skin_" + _skin + ".png"
		if ResourceLoader.exists(path):
			material.albedo_texture = load(path)
		if _tint != "":
			material.albedo_color = Color(_tint)
		_skins[key] = material
	for mesh in _model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = _skins[key]


## Подкраска модели: у каждой поверхности копия материала с albedo_color = tint (текстура остаётся).
func _apply_tint(tint: Color) -> void:
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node
		for i in mesh.get_surface_override_material_count():
			var material: Material = mesh.get_active_material(i)
			if material == null or not (material is BaseMaterial3D):
				continue
			var key := "%s:%d" % [kind, material.get_instance_id()]
			if not _tinted.has(key):
				var copy: BaseMaterial3D = material.duplicate()
				copy.albedo_color = tint
				_tinted[key] = copy
			mesh.set_surface_override_material(i, _tinted[key])


func _physics_process(delta: float) -> void:
	_anim += delta
	if game == null:
		return
	var state := str(game.get("state"))
	if base_target == Vector3.INF and state != "playing":
		return
	if base_target != Vector3.INF and state != "base" and state != "shop":
		return
	var player: Node3D = game.get("player")
	if player == null:
		return
	var target := player.global_position
	var chasing := true
	if base_target != Vector3.INF:
		target = base_target
	elif is_guard and guard_target != null and is_instance_valid(guard_target):
		var center: Vector3 = guard_target.global_position
		if player.global_position.distance_to(center) > 7.0:
			# Герой далеко: кружим вокруг реликвии.
			_orbit += delta * speed / 2.8
			target = center + Vector3(cos(_orbit) * 2.8, 0, sin(_orbit) * 2.8)
			chasing = false
	var to := target - global_position
	to.y = 0
	var dist := to.length()
	var dir := to / dist if dist > 0.001 else Vector3.ZERO
	if not chasing and dist < 0.3:
		dir = Vector3.ZERO
	var factor := 1.0
	var world: Node = game.get("world")
	if world != null:
		factor = world.speed_factor(global_position, "enemy", immune)
	var abilities: Node = game.get("abilities")
	if abilities != null:
		factor *= float(abilities.enemy_slow)
	_slowed = lerpf(_slowed, 1.0 - factor, 1.0 - exp(-6.0 * delta))
	velocity.x = dir.x * speed * factor
	velocity.z = dir.z * speed * factor
	if _windup > 0.0 or _lunge > 0.0:
		velocity.x = 0.0  # во время замаха и выпада стоит на месте
		velocity.z = 0.0
	if frozen > 0.0:
		frozen -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		_windup = 0.0
		_lunge = 0.0
		if frozen <= 0.0 and _ice != null:
			_ice.queue_free()
			_ice = null
	if _knock != Vector3.ZERO:
		velocity.x += _knock.x
		velocity.z += _knock.z
		_knock = _knock.lerp(Vector3.ZERO, 1.0 - exp(-7.0 * delta))
		if _knock.length() < 0.2:
			_knock = Vector3.ZERO
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
	var reach := 0.55 + 0.35 * _size
	if _windup > 0.0:
		_windup -= delta
		if _windup <= 0.0:
			_lunge = 0.3
			if dist < reach * 1.25:
				_strike(player)
	elif chasing and dist < reach and _attack_cooldown <= 0.0 and frozen <= 0.0:
		_attack_cooldown = 1.2
		_windup = 0.28
		game.play_sound("windup")
	var forward := 0.0
	if _windup > 0.0:
		# Замах: обе руки поднимаются вверх.
		for arm in _arms:
			arm.rotation.x = lerpf(arm.rotation.x, -2.6, 1.0 - exp(-18.0 * delta))
	elif _lunge > 0.0:
		# Выпад: руки резко вниз, тело подаётся вперёд и возвращается.
		_lunge -= delta
		var k := clampf(_lunge / 0.3, 0.0, 1.0)
		forward = sin((1.0 - k) * PI) * 0.35 * _size
		for arm in _arms:
			arm.rotation.x = lerpf(0.4, -2.6, k * k)
	else:
		var swing := sin(_anim * 6.0) * 0.35
		for i in _arms.size():
			_arms[i].rotation.x = -0.6 + swing * (1.0 if i == 0 else -1.0)
	_model.position.z = forward
	# На скользкой луже тварь буксует: покачивается из стороны в сторону.
	_model.rotation.z = sin(_anim * 9.0) * 0.22 * _slowed
	if _hit > 0.0:
		_hit -= delta
		var squash := 1.0 - 0.25 * clampf(_hit / 0.12, 0.0, 1.0)
		_model.scale = Vector3(_model_scale * (2.0 - squash), _model_scale * squash, _model_scale * (2.0 - squash))
	else:
		_model.scale = Vector3.ONE * _model_scale


## Удар по герою: урон, искры и звук; герой 0,4 с неуязвим, поэтому толпа не бьёт десять раз за кадр.
## Нападающий на форпост бьёт по забору: только искры, без урона.
func _strike(player: Node3D) -> void:
	if base_target != Vector3.INF:
		game.spawn_burst(global_position + Vector3(0, 0.7, 0) + (base_target - global_position).normalized() * 0.5, Color("#c8b08a"), 0.4)
		return
	if is_guard:
		player.take_damage(float(player.get("max_hp")) * 0.5)
		game.spawn_burst(player.global_position + Vector3(0, 0.9, 0), Color("#ff3a3a"), 1.5)
	else:
		player.take_damage(damage)
		game.spawn_burst(player.global_position + Vector3(0, 0.9, 0), Color("#ff6a3a"), 0.5)
	game.play_sound("punch")


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	_hit = 0.12
	game.play_sound("hit")
	if hp <= 0.0:
		game.on_enemy_died(self)
		queue_free()


## Отбросить: толчок в метрах в секунду, гаснет сам. Боссов отбрасывает втрое слабее.
func knockback(push: Vector3) -> void:
	_knock += push * (0.3 if is_boss else 1.0)


## Вморозить в лёд на seconds: стоит на месте, не бьёт, вокруг полупрозрачный ледяной куб.
func freeze(seconds: float) -> void:
	if is_boss:
		seconds *= 0.4
	frozen = maxf(frozen, seconds)
	if _ice != null:
		return
	if _ice_mesh == null:
		_ice_mesh = BoxMesh.new()
		_ice_mesh.size = Vector3.ONE
		_ice_material = StandardMaterial3D.new()
		_ice_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ice_material.albedo_color = Color(0.6, 0.85, 1.0, 0.45)
		_ice_material.roughness = 0.1
		_ice_material.emission_enabled = true
		_ice_material.emission = Color(0.3, 0.6, 1.0)
		_ice_material.emission_energy_multiplier = 0.4
	_ice = MeshInstance3D.new()
	_ice.mesh = _ice_mesh
	_ice.material_override = _ice_material
	_ice.scale = Vector3(0.6 * _size, 0.8 * _size, 0.6 * _size)
	_ice.position = Vector3(0, 0.4 * _size, 0)
	_ice.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ice)
