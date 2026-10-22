extends Node3D

## «Кладбище»: 3D-выживание против орды нежити на моделях Kenney (Graveyard Kit, Blocky Characters, CC0).
## Ночь, туман, фонари. Из тумана идут зомби, скелеты и призраки, под конец выходит вампир. Герой стреляет
## сам в ближайшего врага, игрок только бегает (стрелки или WASD) и на каждом новом уровне выбирает
## прокачку (1, 2, 3). Души убитых дают опыт, тыквы лечат. Продержался round_seconds — победа.
## Перед игрой меню: ← → выбирают скин героя (8 скинов Kenney), Enter начинает; после конца R — заново.
## Кладбище каждый раз новое: надгробия, склепы, сосны, фонари и ограда расставляются кодом по сиду.
## Этот узел — корень сцены и ведущий раунда; Player (gy_hero.gd) и Hud (gy_hud.gd) — его дети из сцены,
## камера, свет, туман, земля, украшения, враги, снаряды и души создаются кодом.
##
## Самопроверка для ИИ: --test-graveyard=seconds:30,auto:1,move:circle,seed:1,report:5
## seconds — длина раунда; auto — без меню и с автоматическим выбором прокачки; move — автопилот героя
## (circle кружит вокруг центра, away убегает от ближайшего врага, none стоит); boss:секунда — когда
## выходит вампир; rate — множитель частоты появления врагов; skin — имя скина (none = без скина);
## seed — сид кладбища; zoom — множитель расстояния камеры (0.4 — крупный план для проверки моделей).
## Каждые report секунд печатает «Кладбище [t с]: …», в конце «Кладбище: итог …».

const MODELS := "res://assets/kenney/graveyard/models/"
const SOUNDS := "res://assets/kenney/graveyard/sounds/"
const SOUND_NAMES := ["bolt", "hit", "die", "hurt", "pickup", "levelup", "win", "over", "boss", "click", "swing"]
const SOUND_VOLUME := {"bolt": -14.0, "hit": -8.0, "die": -6.0, "swing": -8.0, "pickup": -6.0}
const SKINS := ["adventurer", "man", "woman", "soldier", "robot", "orc", "manAlternative", "womanAlternative"]
const SKIN_TITLES := {"adventurer": "Путешественник", "man": "Горожанин", "woman": "Горожанка", "soldier": "Солдат",
	"robot": "Робот", "orc": "Орк", "manAlternative": "Учёный", "womanAlternative": "Байкерша"}
const ENEMY_KINDS := {
	# scale — множитель модели: фигурки Graveyard Kit ростом около 0,8 м, зомби делаем 1,4 м, вампира 2,6 м.
	"zombie": {"hp": 30.0, "speed": 1.7, "damage": 10.0, "xp": 2, "scale": 1.8, "from": 0.0, "weight": 3.0},
	"skeleton": {"hp": 14.0, "speed": 3.0, "damage": 6.0, "xp": 2, "scale": 1.7, "from": 30.0, "weight": 2.0},
	"ghost": {"hp": 22.0, "speed": 2.3, "damage": 8.0, "xp": 3, "scale": 1.6, "from": 60.0, "weight": 2.0, "ghost": true},
	"vampire": {"hp": 700.0, "speed": 2.4, "damage": 25.0, "xp": 60, "scale": 3.2, "from": 0.0, "weight": 0.0, "boss": true},
}
const UPGRADES := [
	{"id": "damage", "title": "Сила удара", "text": "Урон снарядов +30%"},
	{"id": "rate", "title": "Скорострельность", "text": "Стреляешь на 25% чаще"},
	{"id": "multishot", "title": "Ещё снаряд", "text": "+1 снаряд за выстрел"},
	{"id": "speed", "title": "Быстрые ноги", "text": "Скорость бега +15%"},
	{"id": "health", "title": "Крепкое сердце", "text": "Макс. здоровье +25 и лечение"},
	{"id": "magnet", "title": "Магнит душ", "text": "Души притягиваются на 60% дальше"},
	{"id": "pierce", "title": "Пробивание", "text": "Снаряд пробивает ещё одного врага"},
	{"id": "regen", "title": "Восстановление", "text": "+1 здоровья в секунду"},
]
const ARENA := 34.0  # половина стороны кладбища, по краю ограда
const SPAWN_MIN := 17.0
const SPAWN_MAX := 22.0
const MAX_ENEMIES := 90
const SOUL_LIFETIME := 40.0
const BEST_FILE := "user://graveyard_best.txt"
const Enemy := preload("res://game/gy_enemy.gd")

@export var round_seconds := 180.0
@export var decor_seed := 0  # 0 = каждый раз новое кладбище

var state := "menu"  # menu, playing, levelup, won, over
var elapsed := 0.0
var kills := 0
var level := 1
var xp := 0
var xp_needed := 5
var boss_time := 0.0
var boss_spawned := false
var skin_index := 0
var best_score := 0
var auto := false
var enemies: Array = []  # живые враги (gy_enemy.gd)
var souls: Array = []  # души и тыквы: Node3D с meta value/kind/age
var test_options := {}
var player: CharacterBody3D
var hud: CanvasLayer
var bolts_root: Node3D

const Fx := preload("res://game/gy_fx.gd")
## Цвет искр, которыми рассыпается погибший враг.
const DEATH_COLORS := {"zombie": "#7cff5a", "skeleton": "#ffffff", "ghost": "#8ad8ff", "vampire": "#ff3a3a"}

var _spawn_budget := 0.0
var _report_every := 0.0
var _forced_levelup := 0.0
var _report_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _camera: Camera3D
var _menu_light: OmniLight3D
var _enemies_root: Node3D
var _souls_root: Node3D
var _decor_root: Node3D
var _sounds := {}
var _levelup_options: Array = []
var recommended_index := 0  # какую из трёх прокачек игра советует (подсказка «Рекомендуется»)
var hold_levelup := false  # окно прокачки не закрывать автоматически (снимок окна по --test graveyard=levelup:сек)
var _fires: Array = []  # [OmniLight3D, фаза] для мерцания
var _soul_material: StandardMaterial3D
var _solid_spots: Array = []  # Vector2 занятых мест, чтобы украшения не лезли друг в друга
var _fx_root: Node3D
var _fireflies: CPUParticles3D
var _leaves: CPUParticles3D


func _ready() -> void:
	_parse_test_args()
	_rng.seed = decor_seed if decor_seed != 0 else randi()
	player = get_node_or_null("Player")
	hud = get_node_or_null("Hud")
	_enemies_root = _make_root("Enemies")
	_souls_root = _make_root("Souls")
	bolts_root = _make_root("Bolts")
	_decor_root = _make_root("Decor")
	_setup_environment()
	_setup_camera()
	_setup_sounds()
	_build_graveyard()
	_setup_effects()
	if test_options.has("seconds"):
		round_seconds = float(test_options["seconds"])
	boss_time = float(test_options["boss"]) if test_options.has("boss") else round_seconds * 0.8
	_report_every = float(test_options.get("report", 0.0))
	_forced_levelup = float(test_options.get("levelup", 0.0))  # на этой секунде открыть окно прокачки (для снимков)
	hold_levelup = _forced_levelup > 0.0
	auto = test_options.has("auto") or test_options.has("move")
	best_score = _load_best()
	if test_options.has("skin"):
		skin_index = maxi(SKINS.find(str(test_options["skin"])), 0)
	if player != null:
		player.game = self
		player.autopilot = str(test_options.get("move", ""))
		player.set_skin(SKINS[skin_index])
	if hud != null:
		hud.game = self
	print("Кладбище готово: раунд %d с, вампир на %d с, скин %s, сид %d" % [int(round_seconds), int(boss_time), SKINS[skin_index], _rng.seed])
	if auto:
		start_game()
	else:
		_enter_menu()


func _parse_test_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if not str(arg).begins_with("--test-graveyard="):
			continue
		for item in str(arg).trim_prefix("--test-graveyard=").split(",", false):
			var pair: PackedStringArray = str(item).split(":", false, 1)
			test_options[pair[0].strip_edges()] = pair[1].strip_edges() if pair.size() > 1 else "1"
	if test_options.has("seed"):
		decor_seed = int(test_options["seed"])


func _make_root(root_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = root_name
	add_child(node)
	return node


# --- Сцена: свет, туман, земля, камера, звуки ---

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#1c2740")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8088a8")
	env.ambient_light_energy = 1.25
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color("#3b4a6e")
	env.fog_light_energy = 1.0
	env.fog_density = 0.012
	# Мягкие тени в углах у камней и деревьев (работает в Forward+ и Mobile, в режиме совместимости просто не рисуется).
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 1.5
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	var world := WorldEnvironment.new()
	world.name = "Night"
	world.environment = env
	add_child(world)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.rotation_degrees = Vector3(-55, 35, 0)
	moon.light_color = Color("#dde2ff")
	moon.light_energy = 1.35
	moon.shadow_enabled = true
	add_child(moon)
	# Земля плитками по 10 м: в режиме совместимости на одну сетку действует не больше 8 источников света.
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	var tile := PlaneMesh.new()
	tile.size = Vector2(10, 10)
	tile.material = _ground_material()
	for ix in range(-4, 4):
		for iz in range(-4, 4):
			var mesh := MeshInstance3D.new()
			mesh.mesh = tile
			mesh.position = Vector3(ix * 10 + 5, 0, iz * 10 + 5)
			ground.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(90, 0.2, 90)
	shape.shape = box
	shape.position = Vector3(0, -0.1, 0)
	ground.add_child(shape)
	add_child(ground)


## Земля рисуется шейдером game/gy_ground.gdshader: трава с пятнами, проплешины, тропинки крест-накрест, цветочки.
## Узор считается по мировым координатам, поэтому плитки стыкуются без швов.
func _ground_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://game/gy_ground.gdshader")
	return material


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 50
	_camera.position = Vector3(0, 3, 6)
	add_child(_camera)
	_camera.current = true
	_menu_light = OmniLight3D.new()
	_menu_light.name = "MenuLight"
	_menu_light.light_color = Color("#ffd9a0")
	_menu_light.light_energy = 2.0
	_menu_light.omni_range = 7.0
	_menu_light.position = Vector3(1.8, 2.2, 2.6)
	add_child(_menu_light)


func _setup_sounds() -> void:
	for n in SOUND_NAMES:
		var path: String = SOUNDS + n + ".ogg"
		if not ResourceLoader.exists(path):
			continue
		var stream := AudioStreamPlayer.new()
		stream.stream = load(path)
		stream.max_polyphony = 3
		stream.volume_db = float(SOUND_VOLUME.get(n, 0.0))
		add_child(stream)
		_sounds[n] = stream


func play_sound(sound_name: String) -> void:
	if _sounds.has(sound_name):
		_sounds[sound_name].play()


# --- Кладбище: ограда, надгробия, склепы, сосны, фонари ---

## Светлячки и листья живут в коробке вокруг героя и едут за ним; искры рождаются при каждом попадании.
## Отключить для быстрых проверок: --test graveyard=fx:0.
func _setup_effects() -> void:
	_fx_root = _make_root("Effects")
	if str(test_options.get("fx", "1")) == "0":
		return
	_fireflies = Fx.fireflies()
	_fx_root.add_child(_fireflies)
	_leaves = Fx.leaves()
	_fx_root.add_child(_leaves)
	_follow_effects()


func _follow_effects() -> void:
	if player == null:
		return
	var pos := player.global_position
	if _fireflies != null:
		_fireflies.position = Vector3(pos.x, 1.4, pos.z)
	if _leaves != null:
		_leaves.position = Vector3(pos.x, 6.5, pos.z)


## Искры в точке попадания снаряда (зовёт gy_bolt.gd).
func spawn_sparks(pos: Vector3) -> void:
	if _fx_root == null or str(test_options.get("fx", "1")) == "0":
		return
	var sparks := Fx.sparks()
	_fx_root.add_child(sparks)
	sparks.global_position = pos + Vector3(0, 0.3, 0)
	if test_options.has("debug"):
		print("Искры: попадание в точке (%.1f, %.1f)" % [pos.x, pos.z])


## Взрыв искр цвета врага при его гибели; у вампира втрое больше и крупнее.
func spawn_burst(pos: Vector3, color: Color, size: float) -> void:
	if _fx_root == null or str(test_options.get("fx", "1")) == "0":
		return
	var burst := Fx.sparks(color, int(14 * size), 1.0 + (size - 1.0) * 0.4)
	_fx_root.add_child(burst)
	burst.global_position = pos
	if test_options.has("debug"):
		print("Взрыв искр %s в точке (%.1f, %.1f)" % [color.to_html(false), pos.x, pos.z])


func _build_graveyard() -> void:
	_solid_spots.clear()
	# Ограда по краю и невидимые стены, чтобы никто не ушёл в туман.
	for i in range(int(-ARENA), int(ARENA)):
		var p := float(i) + 0.5
		_place("ironFence", Vector3(p, 0, -ARENA), 0.0, 1.0, false)
		_place("ironFence", Vector3(p, 0, ARENA), PI, 1.0, false)
		_place("ironFence", Vector3(-ARENA, 0, p), PI * 0.5, 1.0, false)
		_place("ironFence", Vector3(ARENA, 0, p), -PI * 0.5, 1.0, false)
	for corner in [Vector3(-ARENA, 0, -ARENA), Vector3(ARENA, 0, -ARENA), Vector3(-ARENA, 0, ARENA), Vector3(ARENA, 0, ARENA)]:
		_place("ironFenceBorderColumn", corner, 0.0, 1.0, false)
	for wall in [[Vector3(0, 1, -ARENA), Vector3(ARENA * 2 + 1, 2, 0.4)], [Vector3(0, 1, ARENA), Vector3(ARENA * 2 + 1, 2, 0.4)],
			[Vector3(-ARENA, 1, 0), Vector3(0.4, 2, ARENA * 2 + 1)], [Vector3(ARENA, 1, 0), Vector3(0.4, 2, ARENA * 2 + 1)]]:
		_add_block(wall[0], wall[1])
	# Склепы с фонарями по четырём сторонам, вокруг них «кварталы» могил.
	for crypt_pos in [Vector3(-20, 0, -20), Vector3(21, 0, -18), Vector3(-19, 0, 22), Vector3(20, 0, 21)]:
		_place("crypt", crypt_pos, _rng.randf_range(0, TAU), 2.6, true)
		_place_light("lightpostSingle", crypt_pos + Vector3(2.6, 0, 1.2), 1.6, Color("#ffd27a"), 1.6, false)
	var graves := ["gravestoneBevel", "gravestoneBroken", "gravestoneCross", "gravestoneCrossLarge", "gravestoneDecorative",
		"gravestoneFlat", "gravestoneRound", "gravestoneWide", "gravestoneRoof", "cross", "crossWood", "pillarObelisk"]
	_scatter(graves, 72, 1.0, 1.25, true, 1.3)
	_scatter(["graveBorder", "grave", "coffin", "shovelDirt"], 22, 1.0, 1.2, false, 1.2)
	_scatter(["pine", "pineCrooked"], 18, 1.4, 2.0, true, 2.2)
	_scatter(["rocks", "rocksTall", "trunk", "trunkLong", "debris", "debrisWood"], 16, 1.0, 1.6, true, 1.4)
	_scatter(["bench", "benchDamaged", "urn", "altarStone"], 8, 1.0, 1.3, true, 1.2)
	_scatter(["pumpkin", "pumpkinCarved", "pumpkinTallCarved"], 16, 1.0, 1.4, false, 0.8)
	for i in 6:
		var pos := _free_spot(1.6)
		if pos != Vector3.INF:
			_place_light("fireBasket", pos, 2.2, Color("#ff9a3c"), 1.3, true)
	for i in 6:
		var pos := _free_spot(1.2)
		if pos != Vector3.INF:
			_place_light("lanternCandle", pos, 2.0, Color("#ffd27a"), 1.0, false)
	print("Кладбище построено: %d украшений" % _decor_root.get_child_count())


func _scatter(names: Array, count: int, scale_min: float, scale_max: float, solid: bool, spacing: float) -> void:
	for i in count:
		var pos := _free_spot(spacing)
		if pos == Vector3.INF:
			continue
		var model_name: String = names[_rng.randi_range(0, names.size() - 1)]
		_place(model_name, pos, _rng.randf_range(0, TAU), _rng.randf_range(scale_min, scale_max), solid)


## Случайное свободное место: не ближе 5 м к центру (старт героя), не ближе spacing к другим предметам.
func _free_spot(spacing: float) -> Vector3:
	for attempt in 40:
		var p := Vector2(_rng.randf_range(-ARENA + 2.5, ARENA - 2.5), _rng.randf_range(-ARENA + 2.5, ARENA - 2.5))
		if p.length() < 5.0:
			continue
		var ok := true
		for spot in _solid_spots:
			if p.distance_to(spot) < spacing:
				ok = false
				break
		if ok:
			_solid_spots.append(p)
			return Vector3(p.x, 0, p.y)
	return Vector3.INF


func _place(model_name: String, pos: Vector3, rot_y: float, scale_factor: float, solid: bool) -> Node3D:
	var path := MODELS + model_name + ".glb"
	var model: Node3D
	if ResourceLoader.exists(path):
		model = (load(path) as PackedScene).instantiate()
	else:
		push_warning("Кладбище: нет модели %s" % path)
		model = Node3D.new()
	model.name = model_name
	model.position = pos
	model.rotation.y = rot_y
	model.scale = Vector3.ONE * scale_factor
	_decor_root.add_child(model)
	var box := model_aabb(model)
	if box.size != Vector3.ZERO:
		model.position.y -= box.position.y  # ноги модели на землю
		box.position.y = 0.0
		if solid:
			_add_block(box.get_center(), Vector3(maxf(box.size.x * 0.8, 0.4), box.size.y, maxf(box.size.z * 0.8, 0.4)))
	return model


func _place_light(model_name: String, pos: Vector3, scale_factor: float, color: Color, energy: float, flicker: bool) -> void:
	var model := _place(model_name, pos, _rng.randf_range(0, TAU), scale_factor, true)
	var box := model_aabb(model)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 11.0
	light.omni_attenuation = 1.2
	light.position = Vector3(pos.x, maxf(box.size.y * 0.9, 0.6), pos.z)
	_decor_root.add_child(light)
	if flicker:
		_fires.append([light, _rng.randf_range(0, TAU), energy])


func _add_block(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_decor_root.add_child(body)


## Общая коробка всех сеток модели в мировых координатах (модель уже должна быть в дереве).
static func model_aabb(model: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


# --- Ход раунда ---

func _process(delta: float) -> void:
	for fire in _fires:
		var light: OmniLight3D = fire[0]
		light.light_energy = float(fire[2]) * (1.0 + 0.18 * sin(Time.get_ticks_msec() * 0.013 + float(fire[1])) + 0.08 * sin(Time.get_ticks_msec() * 0.031 + float(fire[1]) * 2.0))
	_follow_effects()
	if state == "menu":
		if player != null:
			player.rotation.y += delta * 0.7
		_update_camera(delta, true)
		return
	_update_camera(delta, false)
	if state != "playing":
		return
	elapsed += delta
	if _forced_levelup > 0.0 and elapsed >= _forced_levelup:
		_forced_levelup = 0.0
		_gain_xp(xp_needed - xp)
	_spawn(delta)
	_update_souls(delta)
	if hud != null:
		hud.set_values(player.hp, player.max_hp, xp, xp_needed, level, maxf(round_seconds - elapsed, 0.0), kills, enemies.size(), best_score)
	if _report_every > 0.0:
		_report_timer += delta
		if _report_timer >= _report_every:
			_report_timer -= _report_every
			_report("[%d с]" % int(elapsed))
	if elapsed >= round_seconds:
		_win()


func _update_camera(delta: float, menu: bool) -> void:
	if player == null:
		return
	var target: Vector3
	var look: Vector3
	if menu:
		target = player.global_position + Vector3(0, 1.6, 4.5)
		look = player.global_position + Vector3(0, -0.25, 0)
	else:
		target = player.global_position + Vector3(0, 9.5, 6.0) * float(test_options.get("zoom", 1.0))
		look = player.global_position + Vector3(0, 0.5, 0)
	_camera.position = _camera.position.lerp(target, 1.0 - exp(-6.0 * delta))
	_camera.look_at(look, Vector3.UP)


func _spawn(delta: float) -> void:
	var rate := (0.7 + elapsed / 35.0) * float(test_options.get("rate", 1.0))
	_spawn_budget += rate * delta
	while _spawn_budget >= 1.0:
		_spawn_budget -= 1.0
		if enemies.size() < MAX_ENEMIES:
			_spawn_enemy(_pick_kind())
	if not boss_spawned and elapsed >= boss_time:
		boss_spawned = true
		_spawn_enemy("vampire")
		play_sound("boss")
		if hud != null:
			hud.show_banner("Вампир вышел из склепа!")
		print("Вампир вышел из склепа на %d с" % int(elapsed))


func _pick_kind() -> String:
	var total := 0.0
	for kind in ENEMY_KINDS:
		var stats: Dictionary = ENEMY_KINDS[kind]
		if elapsed >= float(stats["from"]):
			total += float(stats["weight"])
	var roll := _rng.randf_range(0.0, total)
	for kind in ENEMY_KINDS:
		var stats: Dictionary = ENEMY_KINDS[kind]
		if elapsed < float(stats["from"]):
			continue
		roll -= float(stats["weight"])
		if roll <= 0.0:
			return kind
	return "zombie"


func _spawn_enemy(kind: String) -> void:
	var enemy := Enemy.new()
	var angle := _rng.randf_range(0, TAU)
	var radius := _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
	var pos := player.global_position + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
	pos.x = clampf(pos.x, -ARENA + 1.5, ARENA - 1.5)
	pos.z = clampf(pos.z, -ARENA + 1.5, ARENA - 1.5)
	pos.y = 0.05
	enemy.setup(kind, ENEMY_KINDS[kind], self)
	_enemies_root.add_child(enemy)
	enemy.global_position = pos
	enemies.append(enemy)


func on_enemy_died(enemy: Node3D) -> void:
	enemies.erase(enemy)
	kills += 1
	var pos := enemy.global_position
	spawn_burst(pos + Vector3(0, 0.6, 0), Color(DEATH_COLORS.get(enemy.kind, "#ffffff")), 3.0 if enemy.is_boss else 1.0)
	_spawn_soul(pos, enemy.xp, "soul")
	if enemy.is_boss:
		_spawn_soul(pos + Vector3(1, 0, 0), 0, "pumpkin")
		play_sound("boss")
		if hud != null:
			hud.show_banner("Вампир повержен!")
		print("Вампир повержен на %d с" % int(elapsed))
	elif _rng.randf() < 0.07:
		_spawn_soul(pos + Vector3(0.6, 0, 0), 0, "pumpkin")
	play_sound("die")


func _spawn_soul(pos: Vector3, value: int, kind: String) -> void:
	var soul := Node3D.new()
	if kind == "pumpkin" and ResourceLoader.exists(MODELS + "pumpkinCarved.glb"):
		var model: Node3D = (load(MODELS + "pumpkinCarved.glb") as PackedScene).instantiate()
		model.scale = Vector3.ONE * 1.3
		soul.add_child(model)
	else:
		if _soul_material == null:
			_soul_material = StandardMaterial3D.new()
			_soul_material.albedo_color = Color("#7ff6ff")
			_soul_material.emission_enabled = true
			_soul_material.emission = Color("#4fd8ff")
			_soul_material.emission_energy_multiplier = 2.5
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.16
		sphere.height = 0.32
		mesh.mesh = sphere
		mesh.material_override = _soul_material
		soul.add_child(mesh)
	soul.set_meta("value", value)
	soul.set_meta("kind", kind)
	soul.set_meta("age", 0.0)
	soul.position = Vector3(pos.x, 0.45, pos.z)
	_souls_root.add_child(soul)
	souls.append(soul)


func _update_souls(delta: float) -> void:
	var player_pos := player.global_position
	for soul in souls.duplicate():
		var age := float(soul.get_meta("age")) + delta
		soul.set_meta("age", age)
		var to: Vector3 = player_pos - soul.global_position
		to.y = 0
		var dist: float = to.length()
		var kind := str(soul.get_meta("kind"))
		var reach: float = player.magnet if kind == "soul" else 1.6
		if dist < reach and dist > 0.001:
			soul.global_position += to / dist * minf(9.0 * delta, dist)
		soul.position.y = 0.45 + sin(age * 4.0) * 0.1
		if dist < 0.8:
			_collect(soul)
		elif age > SOUL_LIFETIME:
			souls.erase(soul)
			soul.queue_free()


func _collect(soul: Node3D) -> void:
	souls.erase(soul)
	var kind := str(soul.get_meta("kind"))
	if kind == "pumpkin":
		player.heal(25.0)
		print("Тыква: лечение, здоровье %d" % int(player.hp))
	else:
		_gain_xp(int(soul.get_meta("value")))
	play_sound("pickup")
	soul.queue_free()


func _gain_xp(amount: int) -> void:
	xp += amount
	if xp >= xp_needed:
		xp -= xp_needed
		level += 1
		xp_needed = 5 + level * 3
		_level_up()


func _level_up() -> void:
	state = "levelup"
	var pool := UPGRADES.duplicate()
	pool.shuffle()
	_levelup_options = pool.slice(0, 3)
	recommended_index = _recommend(_levelup_options)
	get_tree().paused = true
	play_sound("levelup")
	if hud != null:
		hud.show_levelup(_levelup_options, level, recommended_index)
	print("Новый уровень %d: выбор из %s, рекомендуется %s" % [level, ", ".join(_levelup_options.map(func(u): return str(u["title"]))), str(_levelup_options[recommended_index]["title"])])


## Совет игроку: что из предложенного полезнее прямо сейчас. Мало здоровья — лечение и восстановление,
## мало снарядов — ещё снаряд, иначе урон и скорострельность; выбрать всё равно можно что угодно.
func _recommend(options: Array) -> int:
	var hp_part: float = player.hp / maxf(player.max_hp, 1.0)
	var best_index := 0
	var best_score := -1.0
	for i in options.size():
		var option: Dictionary = options[i]
		var score := 1.0
		match str(option["id"]):
			"health":
				score = 3.5 if hp_part < 0.5 else (1.6 if level >= 5 else 0.9)
			"regen":
				score = 2.6 if hp_part < 0.6 else 1.1
			"multishot":
				score = 2.4 if player.projectiles < 3 else 1.3
			"damage":
				score = 1.8 if level >= 3 else 1.4
			"rate":
				score = 1.7
			"pierce":
				score = 1.5 if player.projectiles >= 2 else 0.8
			"speed":
				score = 1.2 if player.speed < 6.5 else 0.6
			"magnet":
				score = 1.4 if souls.size() > 6 else 0.7
		if score > best_score:
			best_score = score
			best_index = i
	return best_index


func choose_upgrade(index: int) -> void:
	if state != "levelup" or index < 0 or index >= _levelup_options.size():
		return
	var upgrade: Dictionary = _levelup_options[index]
	match str(upgrade["id"]):
		"damage":
			player.damage *= 1.3
		"rate":
			player.fire_interval /= 1.25
		"multishot":
			player.projectiles += 1
		"speed":
			player.speed *= 1.15
		"health":
			player.max_hp += 25.0
			player.hp = player.max_hp
		"magnet":
			player.magnet *= 1.6
		"pierce":
			player.pierce += 1
		"regen":
			player.regen += 1.0
	print("Прокачка: %s" % str(upgrade["title"]))
	play_sound("click")
	if hud != null:
		hud.hide_levelup()
	get_tree().paused = false
	state = "playing"


func score() -> int:
	return kills * 10 + (level - 1) * 50 + int(elapsed)


func _win() -> void:
	state = "won"
	var s := score()
	if s > best_score:
		best_score = s
		_save_best(s)
	play_sound("win")
	if hud != null:
		hud.show_message("Ты выжил!\nСчёт %d, рекорд %d\nR: ещё раз" % [s, best_score])
	_report("итог (победа)")


func game_over() -> void:
	if state != "playing":
		return
	state = "over"
	var s := score()
	if s > best_score:
		best_score = s
		_save_best(s)
	play_sound("over")
	if hud != null:
		hud.show_message("Тебя одолели\nСчёт %d, рекорд %d\nR: ещё раз" % [s, best_score])
	_report("итог (поражение)")


func _report(label: String) -> void:
	print("Кладбище %s: здоровье %d/%d, уровень %d (опыт %d/%d), врагов %d, убито %d, душ на земле %d, счёт %d" % [label,
		int(player.hp), int(player.max_hp), level, xp, xp_needed, enemies.size(), kills, souls.size(), score()])


func restart() -> void:
	get_tree().paused = false
	print("Перезапуск кладбища")
	get_tree().reload_current_scene()


# --- Меню ---

func _enter_menu() -> void:
	state = "menu"
	if hud != null:
		hud.show_menu(str(SKIN_TITLES.get(SKINS[skin_index], SKINS[skin_index])), best_score)


func menu_skin(step: int) -> void:
	if state != "menu":
		return
	skin_index = posmod(skin_index + step, SKINS.size())
	player.set_skin(SKINS[skin_index])
	play_sound("click")
	if hud != null:
		hud.show_menu(str(SKIN_TITLES.get(SKINS[skin_index], SKINS[skin_index])), best_score)


func start_game() -> void:
	if state != "menu" and state != "playing":
		return
	state = "playing"
	player.rotation.y = 0.0
	if _menu_light != null:
		_menu_light.visible = false
	if hud != null:
		hud.hide_menu()
	play_sound("click")
	print("Кладбище: раунд начался, герой %s" % SKINS[skin_index])


func _load_best() -> int:
	if not FileAccess.file_exists(BEST_FILE):
		return 0
	var file := FileAccess.open(BEST_FILE, FileAccess.READ)
	return int(file.get_as_text().strip_edges()) if file != null else 0


func _save_best(value: int) -> void:
	var file := FileAccess.open(BEST_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string(str(value))
