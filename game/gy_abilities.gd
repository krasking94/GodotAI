extends Node3D

## Активные способности «Кладбища»: лежат в четырёх слотах внизу экрана, включаются клавишами 1–4 (или мышью)
## и перезаряжаются по времени. Покупаются в Кузнице форпоста за души (gy_game.gd, окно forge), слоты
## хранит gy_save.gd. Узел создаёт gy_game.gd на время ночи: abilities.game = game, затем add_child;
## дальше cast(id) включает способность, tick(delta) ведёт перезарядку и действующие эффекты.
##
## nova — Святая волна: кольцо света, урон всем рядом и отбрасывание. dash — Призрачный рывок: герой
## проскакивает сквозь врагов и 0,6 с неуязвим. frost — Ледяной взрыв: враги рядом вмерзают в лёд на 4 с.
## meteor — Метеор: огненный камень падает на самую густую толпу. fire — Костёр жизни: костёр лечит
## стоящего рядом 8 с. time — Час душ: враги втрое медленнее 5 с, все души летят к герою.

const ABILITIES := {
	"nova": {"title": "Святая волна", "short": "Волна", "text": "урон 60 и отброс всем в 7 м", "cooldown": 18.0, "cost": 0, "color": "#ffe08a", "sound": "relic"},
	"dash": {"title": "Призрачный рывок", "short": "Рывок", "text": "7 м сквозь врагов, 0,6 с неуязвим", "cooldown": 7.0, "cost": 120, "color": "#8ad8ff", "sound": "swing"},
	"frost": {"title": "Ледяной взрыв", "short": "Лёд", "text": "враги в 8 м во льду 4 с", "cooldown": 22.0, "cost": 180, "color": "#a0f0ff", "sound": "soul"},
	"meteor": {"title": "Метеор", "short": "Метеор", "text": "урон 150 в 4 м по самой густой толпе", "cooldown": 28.0, "cost": 260, "color": "#ff7a3a", "sound": "boss"},
	"fire": {"title": "Костёр жизни", "short": "Костёр", "text": "костёр на 8 с, +6 здоровья в секунду", "cooldown": 35.0, "cost": 220, "color": "#7aff9a", "sound": "heal"},
	"time": {"title": "Час душ", "short": "Час душ", "text": "5 с враги втрое медленнее, души летят к тебе", "cooldown": 40.0, "cost": 320, "color": "#d0a0ff", "sound": "elite"},
}
const ORDER := ["nova", "dash", "frost", "meteor", "fire", "time"]
const MODELS := "res://assets/kenney/graveyard/models/"
const Fx := preload("res://game/gy_fx.gd")

var game: Node = null
var slots: Array = []  # id способностей по слотам (до 4)
var cooldowns := {}  # id → сколько секунд осталось
var enemy_slow := 1.0  # множитель скорости всех врагов (Час душ)
var pull_souls := false  # все души летят к герою (Час душ)

var _time_left := 0.0
var _fire_node: Node3D = null
var _fire_left := 0.0
var _fire_light: OmniLight3D
var _meteors: Array = []  # [MeshInstance3D, цель Vector3, осталось секунд]
var _rings: Array = []  # [MeshInstance3D, возраст]
static var _ring_material: StandardMaterial3D
static var _meteor_material: StandardMaterial3D


func cast(id: String) -> bool:
	if not ABILITIES.has(id) or float(cooldowns.get(id, 0.0)) > 0.0:
		return false
	var player: Node3D = game.get("player")
	if player == null:
		return false
	var stats: Dictionary = ABILITIES[id]
	match id:
		"nova":
			_ring(player.global_position, Color(str(stats["color"])), 7.0)
			var hits := 0
			for enemy in _enemies_within(player.global_position, 7.0):
				enemy.knockback((enemy.global_position - player.global_position).normalized() * 9.0)
				enemy.take_damage(60.0)
				hits += 1
			game.spawn_burst(player.global_position + Vector3(0, 1.0, 0), Color(str(stats["color"])), 2.0)
			print("Святая волна: задето %d" % hits)
		"dash":
			player.dash(7.0)
			print("Призрачный рывок")
		"frost":
			_ring(player.global_position, Color(str(stats["color"])), 8.0)
			var hits := 0
			for enemy in _enemies_within(player.global_position, 8.0):
				enemy.freeze(4.0)
				hits += 1
			print("Ледяной взрыв: заморожено %d" % hits)
		"meteor":
			var target := _densest_spot(player.global_position, 15.0)
			_launch_meteor(target)
			print("Метеор летит в (%.0f, %.0f)" % [target.x, target.z])
		"fire":
			_light_fire(player.global_position)
			print("Костёр жизни")
		"time":
			_time_left = 5.0
			enemy_slow = 0.33
			pull_souls = true
			_ring(player.global_position, Color(str(stats["color"])), 12.0)
			print("Час душ")
	cooldowns[id] = float(stats["cooldown"])
	game.play_sound(str(stats["sound"]))
	return true


func tick(delta: float) -> void:
	for id in cooldowns.keys():
		cooldowns[id] = maxf(float(cooldowns[id]) - delta, 0.0)
	if _time_left > 0.0:
		_time_left -= delta
		if _time_left <= 0.0:
			enemy_slow = 1.0
			pull_souls = false
	for ring in _rings.duplicate():
		var mesh: MeshInstance3D = ring[0]
		ring[1] += delta
		var k: float = ring[1] / 0.55
		if k >= 1.0:
			_rings.erase(ring)
			mesh.queue_free()
			continue
		var r: float = float(ring[2]) * (0.2 + 0.8 * k)
		mesh.scale = Vector3(r, 1.0, r)
		mesh.transparency = k
	for meteor in _meteors.duplicate():
		var mesh: MeshInstance3D = meteor[0]
		meteor[2] -= delta
		var target: Vector3 = meteor[1]
		var k := clampf(float(meteor[2]) / 0.9, 0.0, 1.0)
		mesh.global_position = target + Vector3(-6.0 * k, 16.0 * k, -4.0 * k)
		if meteor[2] <= 0.0:
			_meteors.erase(meteor)
			mesh.queue_free()
			_meteor_hit(target)
	if _fire_node != null:
		_fire_left -= delta
		_fire_light.light_energy = 2.2 + 0.4 * sin(Time.get_ticks_msec() * 0.02)
		var player: Node3D = game.get("player")
		if player != null and player.global_position.distance_to(_fire_node.global_position) < 4.0:
			player.heal(6.0 * delta)
		if _fire_left <= 0.0:
			_fire_node.queue_free()
			_fire_node = null


## Доля перезарядки 0…1 (1 — готово) и секунды до готовности, для табло.
func cooldown_state(id: String) -> Array:
	var left := float(cooldowns.get(id, 0.0))
	var total := float(ABILITIES[id]["cooldown"]) if ABILITIES.has(id) else 1.0
	return [1.0 - clampf(left / total, 0.0, 1.0), left]


func _enemies_within(center: Vector3, radius: float) -> Array:
	var result: Array = []
	for enemy in game.get("enemies"):
		if is_instance_valid(enemy) and enemy.global_position.distance_to(center) <= radius:
			result.append(enemy)
	return result


## Точка, где врагов больше всего в 4 м вокруг (среди врагов не дальше reach от героя); нет врагов — перед героем.
func _densest_spot(origin: Vector3, reach: float) -> Vector3:
	var best := origin + Vector3(0, 0, -4)
	var best_count := -1
	var candidates := _enemies_within(origin, reach)
	for enemy in candidates:
		var count := 0
		for other in candidates:
			if other.global_position.distance_to(enemy.global_position) <= 4.0:
				count += 1
		if count > best_count:
			best_count = count
			best = enemy.global_position
	return best


func _ring(center: Vector3, color: Color, radius: float) -> void:
	if _ring_material == null:
		_ring_material = StandardMaterial3D.new()
		_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_material.vertex_color_use_as_albedo = false
		_ring_material.albedo_color = Color.WHITE
		_ring_material.emission_enabled = true
		_ring_material.emission_energy_multiplier = 2.0
	var mesh := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.82
	torus.outer_radius = 1.0
	mesh.mesh = torus
	var material: StandardMaterial3D = _ring_material.duplicate()
	material.albedo_color = color
	material.emission = color
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	mesh.global_position = center + Vector3(0, 0.25, 0)
	mesh.scale = Vector3(0.2 * radius, 1.0, 0.2 * radius)
	_rings.append([mesh, 0.0, radius])


func _launch_meteor(target: Vector3) -> void:
	if _meteor_material == null:
		_meteor_material = StandardMaterial3D.new()
		_meteor_material.albedo_color = Color("#ff8a3a")
		_meteor_material.emission_enabled = true
		_meteor_material.emission = Color("#ff5a1a")
		_meteor_material.emission_energy_multiplier = 3.0
	var mesh := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.6
	ball.height = 1.2
	mesh.mesh = ball
	mesh.material_override = _meteor_material
	var light := OmniLight3D.new()
	light.light_color = Color("#ff7a2a")
	light.light_energy = 2.5
	light.omni_range = 9.0
	mesh.add_child(light)
	add_child(mesh)
	mesh.global_position = target + Vector3(-6, 16, -4)
	_meteors.append([mesh, target, 0.9])


func _meteor_hit(target: Vector3) -> void:
	var hits := 0
	for enemy in _enemies_within(target, 4.0):
		enemy.knockback((enemy.global_position - target).normalized() * 6.0)
		enemy.take_damage(150.0)
		hits += 1
	game.spawn_burst(target + Vector3(0, 0.5, 0), Color("#ff8a3a"), 3.0)
	_ring(target, Color("#ff9a4a"), 4.0)
	game.play_sound("die_elite")
	game.shake(0.6)
	print("Метеор упал: задето %d" % hits)


func _light_fire(center: Vector3) -> void:
	if _fire_node != null:
		_fire_node.queue_free()
	_fire_node = Node3D.new()
	if ResourceLoader.exists(MODELS + "fireBasket.glb"):
		var model: Node3D = (load(MODELS + "fireBasket.glb") as PackedScene).instantiate()
		model.scale = Vector3.ONE * 2.4
		_fire_node.add_child(model)
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color("#7aff9a")
	_fire_light.light_energy = 2.2
	_fire_light.omni_range = 7.0
	_fire_light.position = Vector3(0, 1.2, 0)
	_fire_node.add_child(_fire_light)
	add_child(_fire_node)
	_fire_node.global_position = center + Vector3(0, 0, 1.2)
	_fire_left = 8.0
	_ring(center, Color("#7aff9a"), 4.0)
