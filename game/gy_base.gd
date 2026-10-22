extends Node3D

## Форпост «Кладбища» — база между боями. Мир (забор с воротами, земля, свет, погода) строит gy_world.gd
## по карте «base» из gy_maps.gd, а этот узел добавляет здания и жизнь вокруг:
## Алтарь душ (склеп) — постоянная прокачка за души; Кузница (гараж с горном) — способности (этап 3);
## Костёр — смена героя; Дом сторожа — летопись; Ворота — выбор карты и выход в ночь; Сторожевая башня —
## укрепления (щит в начале ночи и ещё один стражник). У каждого здания есть место взаимодействия
## (spots): подошёл — табло показывает «E — …», нажал E — gy_game.gd открывает окно.
## По бокам за забором бродят зомби, скелеты и призраки: идут к забору и бьют по нему, а стражники
## (gy_guard.gd) у забора их отстреливают. Герою в форпосте ничего не грозит.

const MODELS := "res://assets/kenney/graveyard/models/"
const CITY := "res://assets/kenney/city/"
const Enemy := preload("res://game/gy_enemy.gd")
const Guard := preload("res://game/gy_guard.gd")
const ATTACKER_KINDS := ["zombie", "zombie", "skeleton", "ghost"]
const MAX_ATTACKERS_PER_SIDE := 5

var game: Node = null
var world: Node3D = null
var spots: Array = []  # [Vector3 место, радиус, id, подпись]
var attackers: Array = []
var guards: Array = []

var _spawn_timer := 2.0
var _rng := RandomNumberGenerator.new()


func build(owner_game: Node, owner_world: Node3D, fence_level: int) -> void:
	game = owner_game
	world = owner_world
	_rng.seed = 7
	var arena: Vector2 = world.arena
	# Алтарь душ: склеп с фонарём у входа.
	world.place_model(MODELS + "crypt.glb", "Altar", Vector3(-9.5, 0, -2), PI * 0.5, 2.8, true)
	world.place_light("fireBasket", Vector3(-6.8, 0, 0.2), 2.0, Color("#ff9a3c"), 1.3, true)
	_spot(Vector3(-6.4, 0, -2), 2.8, "altar", "Алтарь душ")
	# Кузница: гараж и горн рядом.
	world.place_model(CITY + "building-garage.glb", "Forge", Vector3(9.8, 0, -2.5), -PI * 0.5, 5.0, true)
	world.place_light("fireBasket", Vector3(6.6, 0, -0.2), 2.4, Color("#ff7a2c"), 1.5, true)
	_spot(Vector3(6.6, 0, -2.5), 2.8, "forge", "Кузница")
	# Костёр посреди двора: брёвна вокруг.
	var fire: OmniLight3D = world.place_light("fireBasket", Vector3(0, 0, 2.5), 3.2, Color("#ffa050"), 2.0, true)
	fire.omni_range = 9.0
	world.place_model(MODELS + "trunkLong.glb", "Log", Vector3(-1.8, 0, 4.2), 0.3, 1.4, true)
	world.place_model(MODELS + "trunkLong.glb", "Log", Vector3(2.0, 0, 4.0), -0.4, 1.4, true)
	_spot(Vector3(0, 0, 2.5), 2.6, "camp", "Костёр: сменить героя")
	# Дом сторожа на юге.
	world.place_model(CITY + "building-small-b.glb", "Home", Vector3(0, 0, 8.0), PI, 5.0, true)
	world.place_light("lanternCandle", Vector3(2.4, 0, 5.0), 2.0, Color("#ffd27a"), 1.0, false)
	_spot(Vector3(0, 0, 5.2), 2.6, "home", "Дом сторожа: летопись")
	# Ворота на севере и сторожевая башня рядом.
	_spot(Vector3(0, 0, -arena.y + 2.2), 2.8, "gate", "Ворота: в путь")
	world.place_model(MODELS + "ironFenceBorderColumn.glb", "Tower", Vector3(-5, 0, -arena.y + 1.0), 0.0, 3.2, true)
	world.place_light("lanternGlass", Vector3(-5, 0, -arena.y + 2.2), 2.0, Color("#ffd27a"), 1.0, false)
	_spot(Vector3(-5, 0, -arena.y + 2.6), 2.4, "fence", "Башня: укрепления")
	# Угловые башенки.
	for corner in [Vector3(-arena.x, 0, arena.y), Vector3(arena.x, 0, arena.y), Vector3(arena.x, 0, -arena.y)]:
		world.place_model(MODELS + "ironFenceBorderColumn.glb", "Tower", corner, 0.0, 2.6, false)
	# Стражники вдоль западного и восточного забора; укрепления добавляют по одному с каждой стороны.
	var rows := [-4.0, 4.0]
	if fence_level >= 2:
		rows.append(0.0)
	if fence_level >= 3:
		rows.append(-8.0)
	for z in rows:
		_guard(Vector3(-arena.x + 1.6, 0, z), PI * 1.5)
		_guard(Vector3(arena.x - 1.6, 0, z), PI * 0.5)
	print("Форпост построен: %d мест, %d стражников, укрепления %d" % [spots.size(), guards.size(), fence_level])


func _spot(pos: Vector3, radius: float, id: String, title: String) -> void:
	spots.append([pos, radius, id, title])


func _guard(pos: Vector3, facing: float) -> void:
	var guard := Guard.new()
	guard.game = game
	add_child(guard)
	guard.global_position = pos
	guard.rotation.y = facing
	guards.append(guard)


## Ближайшее место взаимодействия, если герой в его радиусе; иначе пустой словарь.
func nearest_spot(pos: Vector3) -> Dictionary:
	var best := {}
	var best_dist := INF
	for spot in spots:
		var p: Vector3 = spot[0]
		var d := Vector2(pos.x - p.x, pos.z - p.z).length()
		if d < float(spot[1]) and d < best_dist:
			best_dist = d
			best = {"id": str(spot[2]), "title": str(spot[3])}
	return best


## Нападающие появляются за забором слева и справа и идут бить забор; погибших заменяют новые.
func tick(delta: float) -> void:
	for attacker in attackers.duplicate():
		if not is_instance_valid(attacker):
			attackers.erase(attacker)
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = _rng.randf_range(1.5, 3.0)
	var arena: Vector2 = world.arena
	for side in [-1.0, 1.0]:
		var count := 0
		for attacker in attackers:
			if signf(attacker.global_position.x) == side:
				count += 1
		if count >= MAX_ATTACKERS_PER_SIDE:
			continue
		var kind: String = ATTACKER_KINDS[_rng.randi_range(0, ATTACKER_KINDS.size() - 1)]
		var z := _rng.randf_range(-arena.y + 3.0, arena.y - 3.0)
		var enemy := Enemy.new()
		var stats: Dictionary = game.ENEMY_KINDS[kind].duplicate()
		stats["damage"] = 0.0
		enemy.setup(kind, stats, game)
		enemy.base_target = Vector3(side * (arena.x + 0.9), 0, z)
		add_child(enemy)
		enemy.global_position = Vector3(side * (arena.x + _rng.randf_range(7.0, 12.0)), 0.05, z + _rng.randf_range(-3.0, 3.0))
		attackers.append(enemy)
		game.enemies.append(enemy)
