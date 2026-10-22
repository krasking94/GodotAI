extends CharacterBody3D

## Герой «Кладбища»: блочный человечек Kenney (basicCharacter.gltf, скин — картинка из skins/).
## Бегает по стрелкам или WASD относительно экрана, сам стреляет светящимися снарядами (gy_bolt.gd)
## в ближайшего врага. Руки и ноги качаются кодом: у каждой конечности свой шарнир-узел в плече или бедре.
## Урон от врага: короткая неуязвимость 0,4 с и красная вспышка; при нуле здоровья зовёт game.game_over().
## Параметры (урон, скорострельность, число снарядов, скорость, магнит душ, восстановление) меняет
## прокачка в gy_game.gd. На ледяной луже герой чуть скользит (разгон и торможение медленнее), в грязи вязнет
## (game.world.speed_factor). На тёмных картах в руке фонарь (set_lantern). autopilot для самопроверки: circle, away, relic, none.

const MODEL := "res://assets/kenney/characters/basicCharacter.gltf"
const SKIN_DIR := "res://assets/kenney/characters/skins/"
const MODEL_SCALE := 0.1  # модель высотой 16 единиц → 1,6 м
const GRAVITY := 20.0
const SHOOT_RANGE := 16.0
const Bolt := preload("res://game/gy_bolt.gd")

var game: Node = null
var max_hp := 100.0
var hp := 100.0
var speed := 5.0
var damage := 12.0
var fire_interval := 0.7
var projectiles := 1
var pierce := 1
var magnet := 3.0
var regen := 0.0
var bolt_speed := 15.0
var shield := 0.0  # щит от укреплений форпоста: принимает урон первым
var autopilot := ""
var alive := true
var _dash_timer := 0.0
var _dash_dir := Vector3.ZERO

var _model: Node3D
var _limbs := {}
var _material: StandardMaterial3D
var _fire_timer := 0.5
var _step_timer := 0.0
var _hurt_timer := 0.0
var _flash := 0.0
var _anim := 0.0
var _facing := 0.0
var _lantern: OmniLight3D
var _lantern_phase := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	_build_model()
	set_skin("adventurer")


func _build_model() -> void:
	var packed := load(MODEL) as PackedScene
	if packed == null:
		push_warning("Герой: модель %s не найдена" % MODEL)
		_model = Node3D.new()
		add_child(_model)
		return
	_model = packed.instantiate()
	_model.scale = Vector3.ONE * MODEL_SCALE
	_model.position = Vector3(0, -0.9, 0)  # центр капсулы на 0,9 м, ноги на земле
	add_child(_model)
	# Шарниры: плечи на высоте 12, бёдра на 6 (в единицах модели).
	for limb in [["ArmLeft1", Vector3(3, 12, 0)], ["ArmRight1", Vector3(-3, 12, 0)], ["LegLeft1", Vector3(1, 6, 0)], ["LegRight1", Vector3(-1, 6, 0)]]:
		var limb_name := str(limb[0])
		var joint: Vector3 = limb[1]
		var mesh := _model.find_child(limb_name, true, false)
		if mesh == null:
			continue
		var pivot := Node3D.new()
		pivot.name = limb_name + "Pivot"
		pivot.position = joint
		mesh.get_parent().add_child(pivot)
		mesh.reparent(pivot, false)
		mesh.position = -joint
		_limbs[limb_name] = pivot


func set_skin(skin: String) -> void:
	var path := SKIN_DIR + "skin_" + skin + ".png"
	if not ResourceLoader.exists(path):
		push_warning("Герой: нет скина %s" % path)
		return
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_material.roughness = 1.0
	_material.albedo_texture = load(path)
	for mesh in _model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = _material


## Фонарь в руке: тёплый свет вокруг героя, чуть дрожит (для тёмных карт).
func set_lantern(enabled: bool) -> void:
	if not enabled:
		if _lantern != null:
			_lantern.visible = false
		return
	if _lantern == null:
		_lantern = OmniLight3D.new()
		_lantern.name = "Lantern"
		_lantern.light_color = Color("#ffc890")
		_lantern.light_energy = 1.6
		_lantern.omni_range = 9.0
		_lantern.omni_attenuation = 1.3
		_lantern.position = Vector3(0.5, 0.9, 0.3)
		add_child(_lantern)
	_lantern.visible = true


func _physics_process(delta: float) -> void:
	_anim += delta
	if _lantern != null and _lantern.visible:
		_lantern_phase += delta
		_lantern.light_energy = 1.6 + 0.15 * sin(_lantern_phase * 9.0) + 0.1 * sin(_lantern_phase * 23.0)
	var state := str(game.get("state")) if game != null else ""
	var in_base := state == "base"
	if game == null or not (state == "playing" or in_base) or not alive:
		_animate(0.0, delta)
		return
	var dir := _input_direction()
	var world: Node = game.get("world")
	var factor := 1.0
	var hazard := ""
	if world != null:
		hazard = world.hazard_at(global_position)
		factor = world.speed_factor(global_position, "hero")
	var wanted := Vector3(dir.x * speed * factor, 0, dir.z * speed * factor)
	if _dash_timer > 0.0:
		# Рывок: быстро вперёд сквозь врагов (столкновения с ними выключены), следом искры.
		_dash_timer -= delta
		wanted = _dash_dir * 32.0
		if game.has_method("spawn_burst") and fmod(_dash_timer, 0.05) < delta:
			game.spawn_burst(global_position + Vector3(0, 0.6, 0), Color("#8ad8ff"), 0.5)
		if _dash_timer <= 0.0:
			collision_mask = 1 | 4
	if hazard == "ice" and _dash_timer <= 0.0:
		# Лёд: скорость догоняет желаемую медленно, поэтому герой скользит.
		var k := 1.0 - exp(-2.2 * delta)
		velocity.x = lerpf(velocity.x, wanted.x, k)
		velocity.z = lerpf(velocity.z, wanted.z, k)
	else:
		velocity.x = wanted.x
		velocity.z = wanted.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	var arena: Vector2 = game.get("arena")
	global_position.x = clampf(global_position.x, -arena.x + 0.7, arena.x - 0.7)
	global_position.z = clampf(global_position.z, -arena.y + 0.7, arena.y - 0.7)
	if dir.length() > 0.1:
		_facing = atan2(dir.x, dir.z)
		_step_timer -= delta
		if _step_timer <= 0.0 and is_on_floor():
			_step_timer = 0.32
			game.play_random("step", 4)
	_model.rotation.y = lerp_angle(_model.rotation.y, _facing, 1.0 - exp(-12.0 * delta))
	_animate(dir.length(), delta)
	if regen > 0.0 and hp < max_hp:
		hp = minf(hp + regen * delta, max_hp)
	_hurt_timer -= delta
	if _flash > 0.0:
		_flash -= delta
		_material.albedo_color = Color(1, 0.45, 0.45) if _flash > 0.0 else Color.WHITE
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = fire_interval
		_shoot(dir.length() > 0.1, 9.0 if in_base else SHOOT_RANGE)


func _input_direction() -> Vector3:
	if autopilot != "":
		return _autopilot_direction()
	var v := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if v == Vector2.ZERO:
		var x := 0.0
		var y := 0.0
		if Input.is_physical_key_pressed(KEY_A):
			x -= 1.0
		if Input.is_physical_key_pressed(KEY_D):
			x += 1.0
		if Input.is_physical_key_pressed(KEY_W):
			y -= 1.0
		if Input.is_physical_key_pressed(KEY_S):
			y += 1.0
		v = Vector2(x, y).limit_length(1.0)
	return Vector3(v.x, 0, v.y)


func _autopilot_direction() -> Vector3:
	var p := Vector2(global_position.x, global_position.z)
	match autopilot:
		"circle":
			var r := p.length()
			var tangent := Vector2(-p.y, p.x).normalized() if r > 0.1 else Vector2(1, 0)
			var radial := (-p.normalized() if r > 0.1 else Vector2.ZERO) * clampf(r - 7.0, -1.0, 1.0)
			var d := (tangent + radial).normalized()
			return Vector3(d.x, 0, d.y)
		"relic":
			var relic: Node3D = game.get("relic")
			if relic == null:
				autopilot = "circle"
				var d := _autopilot_direction()
				autopilot = "relic"
				return d
			var to := Vector2(relic.global_position.x - global_position.x, relic.global_position.z - global_position.z)
			return Vector3(to.normalized().x, 0, to.normalized().y)
		"away":
			var enemy := _nearest_enemy()
			var d := Vector2.ZERO
			if enemy != null:
				var to := Vector2(global_position.x - enemy.global_position.x, global_position.z - enemy.global_position.z)
				d = to.normalized()
			var arena: Vector2 = game.get("arena")
			if absf(p.x) > arena.x - 6.0 or absf(p.y) > arena.y - 6.0:
				d = (d - p.normalized() * 1.5).normalized()
			return Vector3(d.x, 0, d.y)
	return Vector3.ZERO


func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for enemy in game.get("enemies"):
		if not is_instance_valid(enemy):
			continue
		var d: float = global_position.distance_squared_to(enemy.global_position)
		if d < best_dist:
			best_dist = d
			best = enemy
	return best


func _shoot(moving: bool, shoot_range: float) -> void:
	var target := _nearest_enemy()
	if target == null:
		return
	var to := target.global_position - global_position
	to.y = 0
	if to.length() > shoot_range or to.length() < 0.01:
		return
	var base := to.normalized()
	if not moving:
		_facing = atan2(base.x, base.z)
	var bolts_root: Node = game.get("bolts_root")
	for i in projectiles:
		var spread := 0.0 if projectiles == 1 else deg_to_rad(-9.0 * (projectiles - 1) * 0.5 + 9.0 * i)
		var bolt := Bolt.new()
		bolt.setup(base.rotated(Vector3.UP, spread), bolt_speed, damage, pierce)
		bolt.game = game
		bolts_root.add_child(bolt)
		bolt.global_position = global_position + Vector3(0, 0.1, 0) + base * 0.7
	game.play_sound("bolt")


func take_damage(amount: float) -> void:
	if not alive or _hurt_timer > 0.0:
		return
	if shield > 0.0:
		var absorbed := minf(shield, amount)
		shield -= absorbed
		amount -= absorbed
		if absorbed > 0.0:
			game.spawn_burst(global_position + Vector3(0, 1.0, 0), Color("#6ad0ff"), 0.8)
	hp -= amount
	_hurt_timer = 0.4
	_flash = 0.15
	game.play_sound("hurt")
	if game.hud != null and amount > 0.0:
		game.hud.flash()
	if hp <= 0.0:
		hp = 0.0
		alive = false
		print("Герой пал")
		game.game_over()


func heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)


## Призрачный рывок на distance метров в сторону движения (или взгляда): 0,6 с неуязвимости, сквозь врагов.
func dash(distance: float) -> void:
	var dir := _input_direction()
	if dir.length() < 0.1:
		dir = Vector3(sin(_facing), 0, cos(_facing))
	_dash_dir = dir.normalized()
	_dash_timer = distance / 32.0
	_hurt_timer = maxf(_hurt_timer, 0.6)
	collision_mask = 1  # сквозь врагов (слой 4), стены остаются


func _animate(move: float, delta: float) -> void:
	var swing := sin(_anim * 11.0) * 0.75 * move
	var idle := sin(_anim * 2.0) * 0.06 * (1.0 - move)
	_set_limb("LegLeft1", swing)
	_set_limb("LegRight1", -swing)
	_set_limb("ArmLeft1", -swing + idle)
	_set_limb("ArmRight1", swing - idle)
	if _model != null:
		_model.position.y = -0.9 + absf(sin(_anim * 11.0)) * 0.06 * move


func _set_limb(limb_name: String, angle: float) -> void:
	if _limbs.has(limb_name):
		_limbs[limb_name].rotation.x = angle
