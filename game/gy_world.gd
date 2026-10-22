extends Node3D

## Мир «Кладбища»: строится по описанию карты из gy_maps.gd. Небо (шейдер gy_sky.gdshader), луна,
## туман, земля плитками (gy_ground.gdshader), ограда с невидимыми стенами, склепы, могилы, сосны, камни,
## дома (Kenney City Kit), разбитые машины (Kenney Racing Kit), пугала, фонари и костры, опасные лужи
## (лёд и грязь, gy_ice.gdshader) и погода (снег, дождь, пепел, листья, клочья тумана, светлячки — gy_fx.gd).
## Снаружи ограды — кольцо сосен и камней, чтобы горизонт не был пустым.
## gy_game.gd создаёт узел, зовёт build(map, rng, fx) и дальше спрашивает speed_factor(pos) для луж,
## free_spot() для реликвии и tick()/follow() каждый кадр (мерцание костров, погода едет за героем).

const MODELS := "res://assets/kenney/graveyard/models/"
const CITY := "res://assets/kenney/city/"
const RACING := "res://assets/kenney/racing/"
const Fx := preload("res://game/gy_fx.gd")
## Насколько замедляет лужа: лёд — твари буксуют, герой лишь чуть скользит; грязь вязнет для всех.
const HAZARD_FACTOR := {"ice": {"enemy": 0.45, "hero": 0.8}, "mud": {"enemy": 0.55, "hero": 0.7}}

var map: Dictionary = {}
var arena := Vector2(34, 34)
var rng := RandomNumberGenerator.new()
var solid_spots: Array = []  # Vector2 занятых мест, чтобы украшения не лезли друг в друга
var hazards: Array = []  # [Vector2 центр, радиус, вид]
var fires: Array = []  # [OmniLight3D, фаза, энергия] для мерцания
var fx_enabled := true
var environment: Environment
var moon: DirectionalLight3D

var _decor_root: Node3D
var _hazard_root: Node3D
var _weather_root: Node3D
var _weather: Array = []  # [CPUParticles3D, высота над героем]
var _ice_material: ShaderMaterial
var _mud_material: ShaderMaterial
var _hazard_mesh: PlaneMesh


func build(map_def: Dictionary, seed_rng: RandomNumberGenerator, fx: bool) -> void:
	map = map_def
	rng = seed_rng
	fx_enabled = fx
	var a: Array = map["arena"]
	arena = Vector2(float(a[0]), float(a[1]))
	_decor_root = _make_root("Decor")
	_hazard_root = _make_root("Hazards")
	_weather_root = _make_root("Weather")
	_setup_environment()
	_setup_ground()
	_build_fence()
	_build_decor()
	_build_lights()
	_build_hazards()
	_setup_weather()
	print("Карта «%s» построена: %d украшений, %d луж, арена %dx%d" % [str(map["title"]), _decor_root.get_child_count(), hazards.size(), int(arena.x * 2), int(arena.y * 2)])


func _make_root(root_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = root_name
	add_child(node)
	return node


# --- Небо, свет, туман ---

func _setup_environment() -> void:
	var e: Dictionary = map["env"]
	var s: Dictionary = map["sky"]
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load("res://game/gy_sky.gdshader")
	sky_material.set_shader_parameter("top_color", Color(str(s["top"])))
	sky_material.set_shader_parameter("horizon_color", Color(str(s["horizon"])))
	sky_material.set_shader_parameter("ground_color", Color(str(s["ground"])))
	sky_material.set_shader_parameter("haze_color", Color(str(s["haze"])))
	sky_material.set_shader_parameter("moon_color", Color(str(s["moon"])))
	var md: Array = s["moon_dir"]
	sky_material.set_shader_parameter("moon_dir", Vector3(float(md[0]), float(md[1]), float(md[2])))
	sky_material.set_shader_parameter("moon_size", float(s["moon_size"]))
	sky_material.set_shader_parameter("stars", float(s["stars"]))
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(str(e["ambient"]))
	environment.ambient_light_energy = float(e["ambient_energy"])
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = float(e["exposure"])
	environment.fog_enabled = true
	environment.fog_light_color = Color(str(e["fog"]))
	environment.fog_light_energy = 1.0
	environment.fog_density = float(e["fog_density"])
	environment.fog_sky_affect = 0.35
	# Мягкие тени в углах и свечение ярких предметов (работают в Forward+ и Mobile, в режиме совместимости не рисуются).
	environment.ssao_enabled = true
	environment.ssao_radius = 1.0
	environment.ssao_intensity = 1.5
	environment.glow_enabled = true
	environment.glow_intensity = float(e["glow"])
	environment.glow_bloom = 0.08
	environment.glow_hdr_threshold = 0.9
	environment.adjustment_enabled = true
	environment.adjustment_saturation = float(e["saturation"])
	# Объёмный туман только в Forward+ (как на ПК владельца): клочья тьмы между фонарями на тёмных картах.
	var volumetric := float(e["volumetric"])
	if volumetric > 0.0 and RenderingServer.get_current_rendering_method() == "forward_plus":
		environment.volumetric_fog_enabled = true
		environment.volumetric_fog_density = volumetric
		environment.volumetric_fog_albedo = Color(str(e["fog"])).lightened(0.3)
		environment.volumetric_fog_emission = Color(str(e["fog"]))
		environment.volumetric_fog_emission_energy = 0.15
		environment.volumetric_fog_length = 90.0
		environment.volumetric_fog_ambient_inject = 0.2
	var world_env := WorldEnvironment.new()
	world_env.name = "Night"
	world_env.environment = environment
	add_child(world_env)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	var angle: Array = e["moon_angle"]
	moon.rotation_degrees = Vector3(float(angle[0]), float(angle[1]), 0)
	moon.light_color = Color(str(e["moon"]))
	moon.light_energy = float(e["moon_energy"])
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 60.0
	add_child(moon)


# --- Земля ---

## Земля плитками по 10 м: в режиме совместимости на одну сетку действует не больше 8 источников света.
func _setup_ground() -> void:
	var g: Dictionary = map["ground"]
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	var tile := PlaneMesh.new()
	tile.size = Vector2(10, 10)
	var material := ShaderMaterial.new()
	material.shader = load("res://game/gy_ground.gdshader")
	material.set_shader_parameter("grass_dark", Color(str(g["grass_dark"])))
	material.set_shader_parameter("grass_light", Color(str(g["grass_light"])))
	material.set_shader_parameter("dirt_color", Color(str(g["dirt"])))
	material.set_shader_parameter("path_color", Color(str(g["path"])))
	material.set_shader_parameter("path_width", float(g["path_width"]))
	material.set_shader_parameter("flower_rarity", float(g["flowers"]))
	material.set_shader_parameter("snow", float(g["snow"]))
	material.set_shader_parameter("wet", float(g["wet"]))
	material.set_shader_parameter("cobble", float(g["cobble"]))
	material.set_shader_parameter("paths", int(g["paths"]))
	tile.material = material
	var nx := ceili((arena.x + 16.0) / 10.0)
	var nz := ceili((arena.y + 16.0) / 10.0)
	for ix in range(-nx, nx):
		for iz in range(-nz, nz):
			var mesh := MeshInstance3D.new()
			mesh.mesh = tile
			mesh.position = Vector3(ix * 10 + 5, 0, iz * 10 + 5)
			ground.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(nx * 20 + 2, 0.2, nz * 20 + 2)
	shape.shape = box
	shape.position = Vector3(0, -0.1, 0)
	ground.add_child(shape)
	add_child(ground)


# --- Ограда, склепы, могилы, дома, машины ---

func _build_fence() -> void:
	var fence_model := str(map["decor"].get("fence", "ironFence"))
	var step := 1.5 if fence_model == "fence" else 1.0
	var x := -arena.x + step * 0.5
	while x < arena.x:
		_place(fence_model, Vector3(x, 0, -arena.y), 0.0, 1.0, false)
		_place(fence_model, Vector3(x, 0, arena.y), PI, 1.0, false)
		x += step
	var z := -arena.y + step * 0.5
	while z < arena.y:
		_place(fence_model, Vector3(-arena.x, 0, z), PI * 0.5, 1.0, false)
		_place(fence_model, Vector3(arena.x, 0, z), -PI * 0.5, 1.0, false)
		z += step
	for corner in [Vector3(-arena.x, 0, -arena.y), Vector3(arena.x, 0, -arena.y), Vector3(-arena.x, 0, arena.y), Vector3(arena.x, 0, arena.y)]:
		_place("ironFenceBorderColumn", corner, 0.0, 1.0, false)
	for wall in [[Vector3(0, 1, -arena.y), Vector3(arena.x * 2 + 1, 2, 0.4)], [Vector3(0, 1, arena.y), Vector3(arena.x * 2 + 1, 2, 0.4)],
			[Vector3(-arena.x, 1, 0), Vector3(0.4, 2, arena.y * 2 + 1)], [Vector3(arena.x, 1, 0), Vector3(0.4, 2, arena.y * 2 + 1)]]:
		add_block(wall[0], wall[1])


func _build_decor() -> void:
	var d: Dictionary = map["decor"]
	var l: Dictionary = map["lights"]
	# Склепы с фонарями, вокруг них «кварталы» могил.
	for crypt_pos in _crypt_positions(int(d["crypts"])):
		_place("crypt", crypt_pos, rng.randf_range(0, TAU), 2.6, true)
		place_light("lightpostSingle", crypt_pos + Vector3(2.6, 0, 1.2), 1.6, Color("#ffd27a"), float(l["energy"]) * 1.6, false)
	# Дома заброшенной деревни: кварталами, с фонарём у крыльца.
	for i in int(d["houses"]):
		var pos := free_spot(7.0, 9.0)
		if pos == Vector3.INF:
			continue
		var house: String = ["building-small-a", "building-small-b", "building-small-c", "building-garage"][rng.randi_range(0, 3)]
		var rot := float(rng.randi_range(0, 3)) * PI * 0.5
		_place_from(CITY + house + ".glb", house, pos, rot, rng.randf_range(5.5, 6.5), true)
		if i % 2 == 0:
			place_light("lanternCandle", pos + Vector3(cos(rot) * 3.8, 0, -sin(rot) * 3.8), 2.0, Color("#ffd27a"), float(l["energy"]), false)
	# Разбитые машины на дороге мёртвых: вдоль шоссе, чуть вкривь.
	for i in int(d["cars"]):
		var car: String = ["vehicle-truck-red", "vehicle-truck-green", "vehicle-truck-yellow", "vehicle-truck-purple", "vehicle-motorcycle"][rng.randi_range(0, 4)]
		var pos: Vector3
		if int(map["ground"]["paths"]) == 3:
			pos = Vector3(rng.randf_range(-arena.x + 6.0, arena.x - 6.0), 0, rng.randf_range(-4.5, 4.5))
			if pos.length() < 7.0 or not _claim(Vector2(pos.x, pos.z), 4.0):
				continue
		else:
			pos = free_spot(4.0)
			if pos == Vector3.INF:
				continue
		_place_from(RACING + car + ".glb", car, pos, rng.randf_range(0, TAU), 1.8, true)
	var graves := ["gravestoneBevel", "gravestoneBroken", "gravestoneCross", "gravestoneCrossLarge", "gravestoneDecorative",
		"gravestoneFlat", "gravestoneRound", "gravestoneWide", "gravestoneRoof", "cross", "crossWood", "pillarObelisk"]
	_scatter(graves, int(d["graves"]), 1.0, 1.25, true, 1.3)
	_scatter(["graveBorder", "grave", "coffin", "shovelDirt"], int(d["grave_props"]), 1.0, 1.2, false, 1.2)
	_scatter(["pine", "pineCrooked"], int(d["pines"]), 1.4, 2.0, true, 2.2)
	_scatter(["rocks", "rocksTall", "trunk", "trunkLong", "debris", "debrisWood"], int(d["rocks"]), 1.0, 1.6, true, 1.4)
	_scatter(["bench", "benchDamaged", "urn", "altarStone"], int(d["furniture"]), 1.0, 1.3, true, 1.2)
	_scatter(["pumpkin", "pumpkinCarved", "pumpkinTallCarved"], int(d["pumpkins"]), 1.0, 1.4, false, 0.8)
	_scatter(["pillarObelisk"], int(d["obelisks"]), 2.2, 2.8, true, 1.6)
	# Пугала: деревянный крест с тыквой-головой.
	for i in int(d.get("scarecrows", 0)):
		var pos := free_spot(1.6)
		if pos == Vector3.INF:
			continue
		var cross := _place("crossWood", pos, rng.randf_range(0, TAU), 2.4, true)
		var head := _place("pumpkinCarved", pos, cross.rotation.y, 1.1, false)
		head.position.y = model_aabb(cross).size.y - 0.15
	# Кольцо снаружи ограды: сосны и камни, чтобы за забором был лес, а не пустота.
	_scatter_outside(["pine", "pineCrooked"], int(d["outer_pines"]), 1.6, 2.6)
	_scatter_outside(["rocks", "rocksTall"], int(d.get("outer_rocks", 0)), 1.4, 2.4)


func _crypt_positions(count: int) -> Array:
	var ax := arena.x * 0.6
	var az := arena.y * 0.6
	var corners := [Vector3(-ax, 0, -az), Vector3(ax, 0, -az * 0.9), Vector3(-ax * 0.95, 0, az), Vector3(ax, 0, az)]
	if count <= 4:
		return corners.slice(0, count)
	var result: Array = corners.duplicate()
	for i in count - 4:
		var angle := TAU * float(i) / float(count - 4) + PI * 0.25
		result.append(Vector3(cos(angle) * ax * 0.55, 0, sin(angle) * az * 0.55))
	return result


func _scatter(names: Array, count: int, scale_min: float, scale_max: float, solid: bool, spacing: float) -> void:
	for i in count:
		var pos := free_spot(spacing)
		if pos == Vector3.INF:
			continue
		var model_name: String = names[rng.randi_range(0, names.size() - 1)]
		_place(model_name, pos, rng.randf_range(0, TAU), rng.randf_range(scale_min, scale_max), solid)


## Украшения за оградой: без столкновений, в полосе 3–14 м от забора.
func _scatter_outside(names: Array, count: int, scale_min: float, scale_max: float) -> void:
	for i in count:
		var side := rng.randi_range(0, 3)
		var depth := rng.randf_range(3.0, 14.0)
		var pos: Vector3
		match side:
			0: pos = Vector3(rng.randf_range(-arena.x - 14.0, arena.x + 14.0), 0, -arena.y - depth)
			1: pos = Vector3(rng.randf_range(-arena.x - 14.0, arena.x + 14.0), 0, arena.y + depth)
			2: pos = Vector3(-arena.x - depth, 0, rng.randf_range(-arena.y - 14.0, arena.y + 14.0))
			_: pos = Vector3(arena.x + depth, 0, rng.randf_range(-arena.y - 14.0, arena.y + 14.0))
		var model_name: String = names[rng.randi_range(0, names.size() - 1)]
		_place(model_name, pos, rng.randf_range(0, TAU), rng.randf_range(scale_min, scale_max), false)


## Случайное свободное место: не ближе min_center к центру (старт героя), не ближе spacing к другим предметам.
func free_spot(spacing: float, min_center: float = 5.0) -> Vector3:
	for attempt in 40:
		var p := Vector2(rng.randf_range(-arena.x + 2.5, arena.x - 2.5), rng.randf_range(-arena.y + 2.5, arena.y - 2.5))
		if p.length() < min_center:
			continue
		if _claim(p, spacing):
			return Vector3(p.x, 0, p.y)
	return Vector3.INF


## Занять место, если рядом нет других предметов.
func _claim(p: Vector2, spacing: float) -> bool:
	for spot in solid_spots:
		if p.distance_to(spot) < spacing:
			return false
	solid_spots.append(p)
	return true


func is_free(p: Vector2, spacing: float) -> bool:
	for spot in solid_spots:
		if p.distance_to(spot) < spacing:
			return false
	for hazard in hazards:
		if p.distance_to(hazard[0]) < float(hazard[1]) + 0.5:
			return false
	return true


func _place(model_name: String, pos: Vector3, rot_y: float, scale_factor: float, solid: bool) -> Node3D:
	return _place_from(MODELS + model_name + ".glb", model_name, pos, rot_y, scale_factor, solid)


func _place_from(path: String, model_name: String, pos: Vector3, rot_y: float, scale_factor: float, solid: bool) -> Node3D:
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
			add_block(box.get_center(), Vector3(maxf(box.size.x * 0.8, 0.4), box.size.y, maxf(box.size.z * 0.8, 0.4)))
	return model


func place_light(model_name: String, pos: Vector3, scale_factor: float, color: Color, energy: float, flicker: bool) -> OmniLight3D:
	var model := _place(model_name, pos, rng.randf_range(0, TAU), scale_factor, true)
	var box := model_aabb(model)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = float(map["lights"]["range"])
	light.omni_attenuation = 1.2
	light.position = Vector3(pos.x, maxf(box.size.y * 0.9, 0.6), pos.z)
	_decor_root.add_child(light)
	if flicker:
		fires.append([light, rng.randf_range(0, TAU), energy])
	return light


func add_block(center: Vector3, size: Vector3) -> void:
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


# --- Фонари и костры ---

func _build_lights() -> void:
	var l: Dictionary = map["lights"]
	var energy := float(l["energy"])
	for i in int(l["fires"]):
		var pos := free_spot(1.6)
		if pos != Vector3.INF:
			place_light("fireBasket", pos, 2.2, Color("#ff9a3c"), energy * 1.3, true)
	for i in int(l["lanterns"]):
		var pos := free_spot(1.2)
		if pos != Vector3.INF:
			place_light("lanternCandle", pos, 2.0, Color("#ffd27a"), energy, false)
	for i in int(l["posts"]):
		var pos := free_spot(2.0, 8.0)
		if pos != Vector3.INF:
			place_light("lightpostSingle", pos, 1.6, Color("#ffe0a0"), energy * 1.5, false)


func tick(_delta: float) -> void:
	var t := Time.get_ticks_msec()
	for fire in fires:
		var light: OmniLight3D = fire[0]
		light.light_energy = float(fire[2]) * (1.0 + 0.18 * sin(t * 0.013 + float(fire[1])) + 0.08 * sin(t * 0.031 + float(fire[1]) * 2.0))


# --- Опасные лужи: лёд и грязь ---

func _build_hazards() -> void:
	var h: Dictionary = map["hazards"]
	for kind in ["ice", "mud"]:
		for i in int(h.get(kind, 0)):
			var radius := rng.randf_range(1.6, 3.4)
			var pos := Vector3.INF
			for attempt in 30:
				var p := Vector2(rng.randf_range(-arena.x + radius + 1.0, arena.x - radius - 1.0), rng.randf_range(-arena.y + radius + 1.0, arena.y - radius - 1.0))
				if p.length() < 4.0 + radius:
					continue
				if is_free(p, radius + 0.6):
					pos = Vector3(p.x, 0, p.y)
					break
			if pos == Vector3.INF:
				continue
			_add_puddle(pos, radius, kind)


func _add_puddle(pos: Vector3, radius: float, kind: String) -> void:
	if _hazard_mesh == null:
		_hazard_mesh = PlaneMesh.new()
		_hazard_mesh.size = Vector2(2, 2)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _hazard_mesh
	mesh.material_override = _ice_material_for(kind)
	mesh.scale = Vector3(radius, 1, radius)
	mesh.position = pos + Vector3(0, 0.03, 0)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hazard_root.add_child(mesh)
	hazards.append([Vector2(pos.x, pos.z), radius, kind])


func _ice_material_for(kind: String) -> ShaderMaterial:
	if kind == "mud":
		if _mud_material == null:
			_mud_material = ShaderMaterial.new()
			_mud_material.shader = load("res://game/gy_ice.gdshader")
			_mud_material.set_shader_parameter("base_color", Color("#2a2418"))
			_mud_material.set_shader_parameter("edge_color", Color("#3a3220"))
			_mud_material.set_shader_parameter("shine", 0.25)
			_mud_material.set_shader_parameter("cracks", 0.0)
			_mud_material.set_shader_parameter("alpha_max", 0.92)
		return _mud_material
	if _ice_material == null:
		_ice_material = ShaderMaterial.new()
		_ice_material.shader = load("res://game/gy_ice.gdshader")
	return _ice_material


## Множитель скорости существа в точке: 1, если лужи нет; who — "enemy" или "hero"; immune — виды луж, которые
## существу не страшны (мерзляк на льду, болотник в грязи, призраки парят над всем).
func speed_factor(pos: Vector3, who: String, immune: Array = []) -> float:
	var kind := hazard_at(pos)
	if kind == "" or immune.has(kind):
		return 1.0
	return float(HAZARD_FACTOR[kind][who])


func hazard_at(pos: Vector3) -> String:
	var p := Vector2(pos.x, pos.z)
	for hazard in hazards:
		if p.distance_to(hazard[0]) < float(hazard[1]) * 0.9:
			return str(hazard[2])
	return ""


# --- Погода ---

func _setup_weather() -> void:
	if not fx_enabled:
		return
	var w: Dictionary = map["weather"]
	if bool(w["fireflies"]):
		_add_weather(Fx.fireflies(), 1.4)
	match str(w["kind"]):
		"leaves": _add_weather(Fx.leaves(), 6.5)
		"snow": _add_weather(Fx.snow(), 7.0)
		"rain": _add_weather(Fx.rain(), 9.0)
		"ash": _add_weather(Fx.ash(), 5.0)
	if bool(w["wisps"]):
		_add_weather(Fx.wisps(), 0.9)


func _add_weather(particles: CPUParticles3D, height: float) -> void:
	_weather_root.add_child(particles)
	_weather.append([particles, height])


## Погода живёт в коробке вокруг героя и едет за ним.
func follow(pos: Vector3) -> void:
	for item in _weather:
		var particles: CPUParticles3D = item[0]
		particles.position = Vector3(pos.x, float(item[1]), pos.z)
