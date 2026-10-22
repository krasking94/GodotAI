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
var special := ""  # приём босса: charge (разбег и таран), summon (зовёт слуг minion), stomp (удар по земле)
var minion := ""
var is_bomb := false  # смертник: взрывается у героя
var is_heavy := false  # громила: почти не отбрасывается
var game: Node = null

static var _eye_materials := {}

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
var _special_timer := 4.0
var _charge := 0.0  # секунды тарана
var _charge_dir := Vector3.ZERO
var _charge_hit := false
var _dmg_accum := 0.0  # урон, накопленный для одной цифры над головой
var _dmg_timer := 0.0
var _eyes := ""


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
	special = str(stats.get("special", ""))
	minion = str(stats.get("minion", ""))
	is_bomb = bool(stats.get("bomb", false))
	is_heavy = bool(stats.get("heavy", false))
	_eyes = str(stats.get("eyes", ""))
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
	_add_eyes(box)


## Светящиеся глаза: две точки на уровне головы, цвет по виду (eyes в описании, иначе по модели).
func _add_eyes(box: AABB) -> void:
	var color := _eyes
	if color == "":
		if is_boss and _light_color != "":
			color = _light_color
		else:
			color = {"zombie": "#c8ff40", "skeleton": "#8ad8ff", "ghost": "#ffffff", "vampire": "#ff3030", "character": "#ff9a40"}.get(_model_name, "#ffffff")
	if not _eye_materials.has(color):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(color)
		material.emission_enabled = true
		material.emission = Color(color)
		material.emission_energy_multiplier = 2.5
		_eye_materials[color] = material
	var mesh := SphereMesh.new()
	mesh.radius = 0.045 * _size
	mesh.height = 0.09 * _size
	mesh.radial_segments = 6
	mesh.rings = 3
	var eye_y := (box.end.y - box.size.y * 0.14) if box.size != Vector3.ZERO else 0.8 * _size
	var eye_z := (box.size.z * 0.42) if box.size != Vector3.ZERO else 0.2 * _size
	var eye_x := (box.size.x * 0.16) if box.size != Vector3.ZERO else 0.08 * _size
	for sign in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = mesh
		eye.material_override = _eye_materials[color]
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.position = Vector3(sign * eye_x, eye_y, eye_z)
		add_child(eye)


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
	if base_target == Vector3.INF:
		factor *= float(game.get("enemy_speed"))
	_slowed = lerpf(_slowed, 1.0 - factor, 1.0 - exp(-6.0 * delta))
	velocity.x = dir.x * speed * factor
	velocity.z = dir.z * speed * factor
	if _windup > 0.0 or _lunge > 0.0:
		velocity.x = 0.0  # во время замаха и выпада стоит на месте
		velocity.z = 0.0
	if _dmg_timer > 0.0:
		_dmg_timer -= delta
		if _dmg_timer <= 0.0:
			_flush_damage()
	if is_boss and special != "" and base_target == Vector3.INF and frozen <= 0.0 and _charge <= 0.0:
		_special_timer -= delta
		if _special_timer <= 0.0:
			_use_special(player, dist, dir)
	if _charge > 0.0:
		# Таран: несётся по прямой вчетверо быстрее, бьёт героя с полуторным уроном один раз.
		_charge -= delta
		velocity.x = _charge_dir.x * speed * 4.0
		velocity.z = _charge_dir.z * speed * 4.0
		if not _charge_hit and dist < reach_distance() * 1.4:
			_charge_hit = true
			_strike(player, 1.5)
		if fmod(_charge, 0.06) < delta:
			game.spawn_burst(global_position + Vector3(0, 0.4, 0), Color(_light_color if _light_color != "" else "#ffffff"), 0.6)
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
	var reach := reach_distance()
	if _windup > 0.0:
		_windup -= delta
		if _windup <= 0.0:
			_lunge = 0.3
			if dist < reach * 1.25:
				_strike(player)
	elif chasing and dist < reach and _attack_cooldown <= 0.0 and frozen <= 0.0 and _charge <= 0.0:
		_attack_cooldown = 1.2
		_windup = 0.28 if not is_bomb else 0.45
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


func reach_distance() -> float:
	return 0.55 + 0.35 * _size


## Приём босса: charge — разбег к герою, summon — слуги вокруг, stomp — удар по земле (если герой не дальше 7 м).
func _use_special(player: Node3D, dist: float, dir: Vector3) -> void:
	match special:
		"charge":
			if dist > 3.0:
				_charge = 0.9
				_charge_dir = dir
				_charge_hit = false
				_special_timer = 6.0
				game.play_sound("alert")
				print("%s идёт на таран" % title)
			else:
				_special_timer = 1.0
		"summon":
			game.boss_summon(self, minion, 4)
			_special_timer = 9.0
		"stomp":
			if dist <= 7.0:
				game.boss_stomp(self, 4.5, damage * 1.2)
				_lunge = 0.3
				_special_timer = 7.0
			else:
				_special_timer = 1.0
		_:
			_special_timer = 5.0
	if player == null:
		pass


## Удар по герою: урон, искры и звук; герой 0,4 с неуязвим, поэтому толпа не бьёт десять раз за кадр.
## Нападающий на форпост бьёт по забору: только искры, без урона. Смертник взрывается: урон всем в 2,5 м и сам гибнет.
func _strike(player: Node3D, mult: float = 1.0) -> void:
	if base_target != Vector3.INF:
		game.spawn_burst(global_position + Vector3(0, 0.7, 0) + (base_target - global_position).normalized() * 0.5, Color("#c8b08a"), 0.4)
		return
	if is_bomb:
		if player.global_position.distance_to(global_position) <= 2.5:
			player.take_damage(damage)
		game.spawn_burst(global_position + Vector3(0, 0.6, 0), Color("#c050ff"), 2.5)
		game.play_sound("die_elite")
		game.shake(0.35)
		hp = 0.0
		game.on_enemy_died(self)
		queue_free()
		return
	if is_guard:
		player.take_damage(float(player.get("max_hp")) * 0.5)
		game.spawn_burst(player.global_position + Vector3(0, 0.9, 0), Color("#ff3a3a"), 1.5)
	else:
		player.take_damage(damage * mult)
		game.spawn_burst(player.global_position + Vector3(0, 0.9, 0), Color("#ff6a3a"), 0.5 * mult)
	game.play_sound("punch")


## Показать накопленный урон одной цифрой над головой.
func _flush_damage() -> void:
	if _dmg_accum > 0.0:
		game.show_damage(global_position + Vector3(0, 0.9 * _size + 0.3, 0), _dmg_accum, is_boss)
	_dmg_accum = 0.0
	_dmg_timer = 0.0


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	_hit = 0.12
	_dmg_accum += amount
	if _dmg_timer <= 0.0:
		_dmg_timer = 0.15
	game.play_sound("hit")
	if hp <= 0.0:
		_flush_damage()
		game.on_enemy_died(self)
		queue_free()


## Отбросить: толчок в метрах в секунду, гаснет сам. Боссов отбрасывает втрое слабее.
func knockback(push: Vector3) -> void:
	_knock += push * (0.3 if is_boss or is_heavy else 1.0)


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
