extends Node3D

## Мир «Симулятора жизни»: свет и небо, дом с окнами и дверными проёмами, двор за окнами, полы на шейдере
## (доски, плитка, ковёр, трава — game/ls_floor.gdshader), люстры, картины, плинтусы. Строится кодом из
## коробок и моделей Kenney (Furniture Kit, Nature Kit, CC0). Здесь же общие помощники для игры:
## place() ставит модель ногами на пол, box() — коробка со столкновением, material() — матовый цвет.
## Солнце светит в окна и даёт тени (DirectionalLight3D с тенями), в каждой комнате люстра с тёплым светом.

const FURNITURE := "res://assets/kenney/furniture/"
const NATURE := "res://assets/kenney/nature/"
const FLOOR_SHADER := preload("res://game/ls_floor.gdshader")
const WALL_H := 2.7
const WALL_T := 0.16
const WINDOW_W := 1.3
const WINDOW_SILL := 0.9
const WINDOW_TOP := 2.1
const DOOR_W := 1.0
const DOOR_H := 2.1

## Комнаты: прямоугольник в плане (x, z, ширина, глубина), пол (mode шейдера и два цвета), цвет стен.
const ROOMS := {
	"nursery": {"title": "детская", "rect": Rect2(0, 0, 4, 4.5), "floor": [2, "#f2c9a8", "#e7b48d"], "wall": "#fbe9d4"},
	"living": {"title": "гостиная", "rect": Rect2(4, 0, 4.5, 9), "floor": [0, "#d7a46a", "#b8824a"], "wall": "#f6ead8"},
	"kitchen": {"title": "кухня", "rect": Rect2(8.5, 0, 3.5, 4.5), "floor": [1, "#e8eef2", "#b9d3df"], "wall": "#e4f0f4"},
	"bath": {"title": "ванная", "rect": Rect2(0, 4.5, 4, 4.5), "floor": [1, "#f0f4f6", "#cfe0ea"], "wall": "#e6f1f5"},
	"bedroom": {"title": "спальня", "rect": Rect2(8.5, 4.5, 3.5, 4.5), "floor": [2, "#d9bfd2", "#c3a3ba"], "wall": "#f3e4ee"},
}
## Дверные проёмы (центр) и центры комнат — для маршрутов и подсказок.
const DOORS := {"nursery": Vector3(4.0, 0, 2.4), "kitchen": Vector3(8.5, 0, 2.4), "bath": Vector3(4.0, 0, 6.8), "bedroom": Vector3(8.5, 0, 6.8)}
const ROOM_CENTER := {"nursery": Vector3(2.0, 0, 2.25), "kitchen": Vector3(10.25, 0, 2.25), "bath": Vector3(2.0, 0, 6.75),
	"bedroom": Vector3(10.25, 0, 6.75), "living": Vector3(6.25, 0, 4.5)}

var sun: DirectionalLight3D
var environment: Environment
var _models := {}
var _materials := {}
var _glass: StandardMaterial3D


func build() -> void:
	name = "World"
	_build_environment()
	_build_house()
	_build_outdoors()


# --- Помощники --------------------------------------------------------------------------------

## Матовый материал одного цвета (кэшируется по цвету).
func material(color: Color, rough := 0.9) -> StandardMaterial3D:
	var key := "%s:%.2f" % [color.to_html(), rough]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = rough
		_materials[key] = m
	return _materials[key]


## Коробка (BoxMesh) в точке pos; solid — со столкновением.
func box(parent: Node, size: Vector3, pos: Vector3, color: Color, solid := true, rough := 0.9) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape_mesh := BoxMesh.new()
	shape_mesh.size = size
	mesh.mesh = shape_mesh
	mesh.material_override = material(color, rough)
	mesh.position = pos
	parent.add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
		mesh.add_child(body)
	return mesh


## Модель Kenney: матовая (у наборов metallic = 1, без отражений они чёрные), один экземпляр из кэша сцены.
func instance_model(path: String) -> Node3D:
	if not _models.has(path):
		var packed := load(path) as PackedScene
		if packed == null:
			return null
		_models[path] = packed
	var node: Node3D = (_models[path] as PackedScene).instantiate()
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mesh as MeshInstance3D).mesh
		if m == null:
			continue
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).metallic > 0.0:
				(mat as BaseMaterial3D).metallic = 0.0
				(mat as BaseMaterial3D).roughness = 0.85
	return node


static func model_aabb(model: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mesh.global_transform * mesh.get_aabb()
		result = b if first else result.merge(b)
		first = false
	return result


## Ставит модель ногами на пол в точку pos (центр по x и z), поворот yaw в градусах, при solid — коробка
## столкновений по габаритам. wrapper — готовый узел-обёртка (например предмет Item), иначе создаётся Node3D.
func place(parent: Node, path: String, model_scale: float, pos: Vector3, yaw_deg: float, solid := true, item_name := "", wrapper: Node3D = null) -> Node3D:
	if wrapper == null:
		wrapper = Node3D.new()
	if item_name != "":
		wrapper.name = item_name
	parent.add_child(wrapper)
	var model := instance_model(path)
	if model == null:
		push_warning("Нет модели %s" % path)
		wrapper.set_meta("size", Vector3(0.3, 0.3, 0.3))
		return wrapper
	wrapper.add_child(model)
	model.scale = Vector3.ONE * model_scale
	var aabb := model_aabb(model)
	var center := aabb.get_center()
	model.position = Vector3(-center.x, -aabb.position.y, -center.z)
	wrapper.position = pos
	wrapper.rotation_degrees.y = yaw_deg
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(maxf(aabb.size.x, 0.1), maxf(aabb.size.y, 0.1), maxf(aabb.size.z, 0.1))
		shape.shape = box_shape
		shape.position = Vector3(0, aabb.size.y * 0.5, 0)
		body.add_child(shape)
		wrapper.add_child(body)
	wrapper.set_meta("size", aabb.size)
	return wrapper


## Перекрасить поверхность модели по имени материала (копия, остальные модели не трогаются).
static func tint_surface(node: Node3D, material_name: String, color: Color) -> void:
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mesh as MeshInstance3D).mesh
		if m == null:
			continue
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			if mat is BaseMaterial3D and mat.resource_name == material_name:
				var copy: BaseMaterial3D = mat.duplicate()
				copy.albedo_color = color
				(mesh as MeshInstance3D).set_surface_override_material(i, copy)


func floor_material(mode: int, a: Color, b: Color, cell := 0.6) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FLOOR_SHADER
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("color_a", a)
	m.set_shader_parameter("color_b", b)
	m.set_shader_parameter("cell", cell)
	return m


func room_of(point: Vector3) -> String:
	for id in ROOMS:
		if (ROOMS[id]["rect"] as Rect2).has_point(Vector2(point.x, point.z)):
			return id
	return "living"


func room_title(id: String) -> String:
	return str(ROOMS[id]["title"]) if ROOMS.has(id) else "дом"


# --- Свет и небо --------------------------------------------------------------------------------

func _build_environment() -> void:
	environment = Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#5aa6f0")
	sky_material.sky_horizon_color = Color("#cfe6ff")
	sky_material.ground_bottom_color = Color("#7fb35a")
	sky_material.ground_horizon_color = Color("#bfe0a8")
	sky_material.sun_angle_max = 20.0
	sky_material.sun_curve = 0.1
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#ffe9d2")
	environment.ambient_light_energy = 0.42
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 6.0
	environment.ssao_enabled = true  # мягкие тени в углах (только Forward+/Mobile, в режиме совместимости не рисуется)
	environment.ssao_radius = 0.8
	environment.ssao_intensity = 1.6
	environment.glow_enabled = true
	environment.glow_intensity = 0.35
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.1
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.1
	environment.adjustment_contrast = 1.03
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.light_color = Color("#fff2dc")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 2.5  # без этого на перемычках дверей полосы (shadow acne)
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 40.0
	sun.rotation_degrees = Vector3(-48, -35, 0)  # светит с юга-востока: в окна детской, гостиной и кухни
	add_child(sun)


# --- Дом -------------------------------------------------------------------------------------------

func _build_house() -> void:
	var house := Node3D.new()
	house.name = "House"
	add_child(house)
	for id in ROOMS:
		var room: Dictionary = ROOMS[id]
		var rect: Rect2 = room["rect"]
		var center := rect.get_center()
		var floor_mesh := box(house, Vector3(rect.size.x, 0.1, rect.size.y), Vector3(center.x, -0.05, center.y), Color.WHITE)
		floor_mesh.name = "Floor_" + id
		var fl: Array = room["floor"]
		floor_mesh.material_override = floor_material(int(fl[0]), Color(str(fl[1])), Color(str(fl[2])), 0.6 if int(fl[0]) != 1 else 0.45)
		var ceiling := box(house, Vector3(rect.size.x, 0.1, rect.size.y), Vector3(center.x, WALL_H + 0.05, center.y), Color("#f7f3ec"), false)
		ceiling.name = "Ceiling_" + id
		_chandelier(house, Vector3(center.x, WALL_H, center.y), id)
		_skirting(house, rect, Color(str(room["wall"])).darkened(0.35))
	# Внешние стены с окнами, внутренние с дверями. Цвет стены — по комнате, у общей стены две стороны
	# красятся отдельно: тонкая «краска» с каждой стороны.
	_wall(house, Vector2(0, 0), Vector2(12, 0), [], [2.0, 6.2, 10.2], ["nursery", "living", "kitchen"], 1)
	_wall(house, Vector2(0, 9), Vector2(12, 9), [], [2.0, 6.2, 10.2], ["bath", "living", "bedroom"], -1)
	_wall(house, Vector2(0, 0), Vector2(0, 9), [], [2.2, 6.8], ["nursery", "bath"], 1)
	_wall(house, Vector2(12, 0), Vector2(12, 9), [], [2.2, 6.8], ["kitchen", "bedroom"], -1)
	_wall(house, Vector2(4, 0), Vector2(4, 9), [2.4, 6.8], [], ["living"], 0)
	_wall(house, Vector2(8.5, 0), Vector2(8.5, 9), [2.4, 6.8], [], ["living"], 0)
	_wall(house, Vector2(0, 4.5), Vector2(4, 4.5), [], [], ["nursery"], 0)
	_wall(house, Vector2(8.5, 4.5), Vector2(12, 4.5), [], [], ["kitchen"], 0)
	_paint_inner_walls(house)
	_pictures(house)
	_door_frames(house)


## Плинтус по периметру комнаты: тонкая полоска у пола, чтобы стык пола и стены читался.
func _skirting(parent: Node, rect: Rect2, color: Color) -> void:
	var t := WALL_T * 0.5 + 0.02
	var h := 0.1
	var cx := rect.get_center().x
	var cz := rect.get_center().y
	box(parent, Vector3(rect.size.x - WALL_T, h, 0.03), Vector3(cx, h * 0.5, rect.position.y + t), color, false)
	box(parent, Vector3(rect.size.x - WALL_T, h, 0.03), Vector3(cx, h * 0.5, rect.end.y - t), color, false)
	box(parent, Vector3(0.03, h, rect.size.y - WALL_T), Vector3(rect.position.x + t, h * 0.5, cz), color, false)
	box(parent, Vector3(0.03, h, rect.size.y - WALL_T), Vector3(rect.end.x - t, h * 0.5, cz), color, false)


## Стена от a до b. doors — координаты проёмов вдоль стены (ширина DOOR_W, высота DOOR_H), windows — окна
## (ширина WINDOW_W, от WINDOW_SILL до WINDOW_TOP). rooms — комнаты вдоль стены (цвет берётся у первой),
## side — с какой стороны стены двор (1: окна смотрят в −z/−x, −1: в +z/+x, 0: внутренняя стена).
func _wall(parent: Node, a: Vector2, b: Vector2, doors: Array, windows: Array, rooms: Array, side: int) -> void:
	var along := b - a
	var length := along.length()
	var dir := along / length
	var horizontal := absf(dir.x) > absf(dir.y)
	var color := Color(str(ROOMS[rooms[0]]["wall"]))
	var cuts: Array = []
	for d in doors:
		cuts.append([float(d) - DOOR_W * 0.5, float(d) + DOOR_W * 0.5, 0.0, DOOR_H])
	for w in windows:
		cuts.append([float(w) - WINDOW_W * 0.5, float(w) + WINDOW_W * 0.5, WINDOW_SILL, WINDOW_TOP])
	cuts.sort_custom(func(p, q): return p[0] < q[0])
	var cursor := 0.0
	for cut in cuts:
		var from: float = cut[0]
		var to: float = cut[1]
		var y0: float = cut[2]
		var y1: float = cut[3]
		_wall_piece(parent, a, dir, cursor, from, 0.0, WALL_H, color, horizontal)
		if y0 > 0.0:
			_wall_piece(parent, a, dir, from, to, 0.0, y0, color, horizontal)  # под окном
		_wall_piece(parent, a, dir, from, to, y1, WALL_H, color, horizontal)  # над проёмом
		if y0 > 0.0:
			var mid := a + dir * ((from + to) * 0.5)
			_window(parent, Vector3(mid.x, 0, mid.y), horizontal, side)
		cursor = to
	_wall_piece(parent, a, dir, cursor, length, 0.0, WALL_H, color, horizontal)
	# Комнаты, у которых цвет стены другой, получают свой слой краски со своей стороны.
	for i in range(1, rooms.size()):
		pass


func _wall_piece(parent: Node, a: Vector2, dir: Vector2, from: float, to: float, y0: float, y1: float, color: Color, horizontal: bool) -> void:
	if to - from < 0.01 or y1 - y0 < 0.01:
		return
	var mid := a + dir * ((from + to) * 0.5)
	var size := Vector3(to - from, y1 - y0, WALL_T) if horizontal else Vector3(WALL_T, y1 - y0, to - from)
	box(parent, size, Vector3(mid.x, (y0 + y1) * 0.5, mid.y), color)


## Тонкие слои краски на внутренних стенах со стороны комнат другого цвета (кухня, ванная, спальня, детская).
func _paint_inner_walls(parent: Node) -> void:
	var layers := [
		# стена x=4: со стороны детской (z 0..4.5) и ванной (4.5..9)
		["nursery", Vector3(4 - WALL_T * 0.5 - 0.005, WALL_H * 0.5, 2.25), Vector3(0.01, WALL_H, 4.5), [2.4]],
		["bath", Vector3(4 - WALL_T * 0.5 - 0.005, WALL_H * 0.5, 6.75), Vector3(0.01, WALL_H, 4.5), [6.8]],
		# стена x=8.5: со стороны кухни и спальни
		["kitchen", Vector3(8.5 + WALL_T * 0.5 + 0.005, WALL_H * 0.5, 2.25), Vector3(0.01, WALL_H, 4.5), [2.4]],
		["bedroom", Vector3(8.5 + WALL_T * 0.5 + 0.005, WALL_H * 0.5, 6.75), Vector3(0.01, WALL_H, 4.5), [6.8]],
		# стена z=4.5 слева: со стороны ванной; справа: со стороны спальни
		["bath", Vector3(2.0, WALL_H * 0.5, 4.5 + WALL_T * 0.5 + 0.005), Vector3(4.0, WALL_H, 0.01), []],
		["bedroom", Vector3(10.25, WALL_H * 0.5, 4.5 + WALL_T * 0.5 + 0.005), Vector3(3.5, WALL_H, 0.01), []],
	]
	for layer in layers:
		var color := Color(str(ROOMS[layer[0]]["wall"]))
		var pos: Vector3 = layer[1]
		var size: Vector3 = layer[2]
		var door_list: Array = layer[3]
		if door_list.is_empty():
			box(parent, size, pos, color, false)
			continue
		# Слой с вырезом под дверь: три куска (слева, над дверью, справа) вдоль z.
		var door_z: float = door_list[0]
		var z0 := pos.z - size.z * 0.5
		var z1 := pos.z + size.z * 0.5
		var d0 := door_z - DOOR_W * 0.5
		var d1 := door_z + DOOR_W * 0.5
		box(parent, Vector3(size.x, WALL_H, d0 - z0), Vector3(pos.x, WALL_H * 0.5, (z0 + d0) * 0.5), color, false)
		box(parent, Vector3(size.x, WALL_H - DOOR_H, DOOR_W), Vector3(pos.x, (WALL_H + DOOR_H) * 0.5, door_z), color, false)
		box(parent, Vector3(size.x, WALL_H, z1 - d1), Vector3(pos.x, WALL_H * 0.5, (d1 + z1) * 0.5), color, false)


## Окно: рама, стекло (прозрачное), подоконник. Снаружи за ним двор.
func _window(parent: Node, pos: Vector3, horizontal: bool, side: int) -> void:
	var frame_color := Color("#ffffff")
	var h := WINDOW_TOP - WINDOW_SILL
	var cy := (WINDOW_TOP + WINDOW_SILL) * 0.5
	var t := WALL_T + 0.04
	var fw := 0.06
	if horizontal:
		box(parent, Vector3(WINDOW_W + fw * 2, fw, t), Vector3(pos.x, WINDOW_SILL - fw * 0.5, pos.z), frame_color, false)
		box(parent, Vector3(WINDOW_W + fw * 2, fw, t), Vector3(pos.x, WINDOW_TOP + fw * 0.5, pos.z), frame_color, false)
		box(parent, Vector3(fw, h, t), Vector3(pos.x - WINDOW_W * 0.5 - fw * 0.5, cy, pos.z), frame_color, false)
		box(parent, Vector3(fw, h, t), Vector3(pos.x + WINDOW_W * 0.5 + fw * 0.5, cy, pos.z), frame_color, false)
		box(parent, Vector3(0.04, h, t), Vector3(pos.x, cy, pos.z), frame_color, false)  # переплёт
		box(parent, Vector3(WINDOW_W + 0.3, 0.04, 0.3), Vector3(pos.x, WINDOW_SILL - fw, pos.z - side * 0.1), frame_color, false)  # подоконник
		_glass_pane(parent, Vector3(WINDOW_W, h, 0.02), Vector3(pos.x, cy, pos.z))
	else:
		box(parent, Vector3(t, fw, WINDOW_W + fw * 2), Vector3(pos.x, WINDOW_SILL - fw * 0.5, pos.z), frame_color, false)
		box(parent, Vector3(t, fw, WINDOW_W + fw * 2), Vector3(pos.x, WINDOW_TOP + fw * 0.5, pos.z), frame_color, false)
		box(parent, Vector3(t, h, fw), Vector3(pos.x, cy, pos.z - WINDOW_W * 0.5 - fw * 0.5), frame_color, false)
		box(parent, Vector3(t, h, fw), Vector3(pos.x, cy, pos.z + WINDOW_W * 0.5 + fw * 0.5), frame_color, false)
		box(parent, Vector3(t, h, 0.04), Vector3(pos.x, cy, pos.z), frame_color, false)
		box(parent, Vector3(0.3, 0.04, WINDOW_W + 0.3), Vector3(pos.x - side * 0.1, WINDOW_SILL - fw, pos.z), frame_color, false)
		_glass_pane(parent, Vector3(0.02, h, WINDOW_W), Vector3(pos.x, cy, pos.z))


func _glass_pane(parent: Node, size: Vector3, pos: Vector3) -> void:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass.albedo_color = Color(0.75, 0.9, 1.0, 0.18)
		_glass.roughness = 0.05
		_glass.specular = 0.8
		_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pane := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	pane.mesh = mesh
	pane.material_override = _glass
	pane.position = pos
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(pane)
	# Невидимая преграда, чтобы малыш не вылез в окно.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	pane.add_child(body)


## Люстра: модель Kenney под потолком и тёплый свет.
func _chandelier(parent: Node, pos: Vector3, room_id: String) -> void:
	var lamp := place(parent, FURNITURE + "lampSquareCeiling.glb", 2.0, pos, 0, false)
	var size: Vector3 = lamp.get_meta("size")
	lamp.position.y = pos.y - size.y  # модель растёт вверх от точки опоры: подвешиваем к потолку
	var light := OmniLight3D.new()
	light.position = Vector3(pos.x, pos.y - size.y - 0.15, pos.z)
	light.light_color = Color("#fff1d6")
	light.light_energy = 1.1 if room_id == "living" else 0.9
	light.omni_range = 7.0 if room_id == "living" else 5.5
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	parent.add_child(light)


## Картины на стенах: рамка и цветное «полотно» с простым рисунком из двух-трёх прямоугольников.
func _pictures(parent: Node) -> void:
	var pictures := [
		# позиция, поворот (0: смотрит в +z, 180: в −z, 90: в +x, −90: в −x), цвета
		[Vector3(2.0, 1.7, 4.5 - WALL_T * 0.5 - 0.02), 180, ["#ffd6e0", "#ff8fb0", "#ffe08a"]],   # детская, стена к ванной
		[Vector3(6.2, 1.8, 9 - WALL_T * 0.5 - 0.02), 180, ["#cfe8ff", "#6aa8ff", "#ffffff"]],       # гостиная, над диваном
		[Vector3(4 + WALL_T * 0.5 + 0.02, 1.7, 4.8), 90, ["#e8f4d8", "#8fc46a", "#5a8a3a"]],      # гостиная, стена к ванной
		[Vector3(10.25, 1.8, 4.5 + WALL_T * 0.5 + 0.02), 0, ["#f4dde8", "#c28ab0", "#7a4a6a"]],   # спальня
		[Vector3(10.6, 1.7, 9 - WALL_T * 0.5 - 0.02), 180, ["#ffeec8", "#ffb45a", "#d87a2a"]],     # спальня над кроватью
	]
	for p in pictures:
		var pos: Vector3 = p[0]
		var yaw: float = p[1]
		var colors: Array = p[2]
		var frame := box(parent, Vector3(0.8, 0.6, 0.03), pos, Color("#6b4a2a"), false, 0.6)
		frame.rotation_degrees.y = yaw
		var canvas := box(frame, Vector3(0.7, 0.5, 0.02), Vector3(0, 0, 0.01), Color(str(colors[0])), false)
		box(canvas, Vector3(0.3, 0.3, 0.01), Vector3(-0.12, -0.05, 0.012), Color(str(colors[1])), false)
		box(canvas, Vector3(0.18, 0.18, 0.01), Vector3(0.18, 0.1, 0.012), Color(str(colors[2])), false)


## Дверные косяки вокруг проёмов во внутренних стенах.
func _door_frames(parent: Node) -> void:
	var frame_color := Color("#8a6a4a")
	for door in [Vector3(4.0, 0, 2.4), Vector3(4.0, 0, 6.8), Vector3(8.5, 0, 2.4), Vector3(8.5, 0, 6.8)]:
		var t := WALL_T + 0.05
		box(parent, Vector3(t, DOOR_H + 0.05, 0.06), Vector3(door.x, (DOOR_H + 0.05) * 0.5, door.z - DOOR_W * 0.5 - 0.03), frame_color, false, 0.6)
		box(parent, Vector3(t, DOOR_H + 0.05, 0.06), Vector3(door.x, (DOOR_H + 0.05) * 0.5, door.z + DOOR_W * 0.5 + 0.03), frame_color, false, 0.6)
		box(parent, Vector3(t, 0.06, DOOR_W + 0.12), Vector3(door.x, DOOR_H + 0.03, door.z), frame_color, false, 0.6)


# --- Двор ----------------------------------------------------------------------------------------

func _build_outdoors() -> void:
	var yard := Node3D.new()
	yard.name = "Yard"
	add_child(yard)
	var ground := box(yard, Vector3(70, 0.1, 70), Vector3(6, -0.06, 4.5), Color.WHITE)
	ground.material_override = floor_material(3, Color("#86c35a"), Color("#5f9e3c"), 1.0)
	# Дорожка от двери дома (условно у кухни) и забор по периметру участка.
	var path := box(yard, Vector3(1.2, 0.02, 6.0), Vector3(14.5, 0.0, 4.5), Color("#c9bda6"), false)
	path.material_override = floor_material(1, Color("#cfc4ae"), Color("#b9ad95"), 0.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var trees := ["tree_default", "tree_oak", "tree_detailed", "tree_pineDefaultA"]
	var spots := [Vector3(-3.5, 0, 1.5), Vector3(-4, 0, 7), Vector3(2, 0, -4), Vector3(6, 0, -4.5), Vector3(10.5, 0, -4),
		Vector3(15.5, 0, 1), Vector3(16, 0, 8), Vector3(3, 0, 13), Vector3(8, 0, 13.5), Vector3(13, 0, 12.5), Vector3(-3, 0, 12),
		Vector3(-7, 0, 4), Vector3(19, 0, 4.5), Vector3(6, 0, -8), Vector3(6, 0, 17)]
	for i in spots.size():
		var spot: Vector3 = spots[i]
		var tree: String = trees[i % trees.size()]
		place(yard, NATURE + tree + ".glb", rng.randf_range(3.2, 4.2), spot, rng.randf_range(0, 360), false)
	for i in 14:
		var bush := "plant_bush" if i % 2 == 0 else "plant_bushDetailed"
		var pos := Vector3(rng.randf_range(-6, 18), 0, -3.0 if i < 7 else 12.0) + Vector3(0, 0, rng.randf_range(-1.0, 1.0))
		place(yard, NATURE + bush + ".glb", rng.randf_range(2.0, 3.0), pos, rng.randf_range(0, 360), false)
	var flowers := ["flower_redA", "flower_yellowA", "flower_purpleA"]
	for i in 40:
		var pos := Vector3(rng.randf_range(-6, 18), 0, rng.randf_range(-3.5, 12.5))
		if pos.x > -0.6 and pos.x < 12.6 and pos.z > -0.6 and pos.z < 9.6:
			continue  # не внутри дома
		place(yard, NATURE + flowers[i % 3] + ".glb", 2.0, pos, rng.randf_range(0, 360), false)
	# Забор вокруг участка (модель 1 м шириной, масштаб 2 → 2 м).
	for x in range(-8, 22, 2):
		place(yard, NATURE + "fence_simple.glb", 2.0, Vector3(x + 1, 0, -6), 0, false)
		place(yard, NATURE + "fence_simple.glb", 2.0, Vector3(x + 1, 0, 15), 0, false)
	for z in range(-6, 15, 2):
		place(yard, NATURE + "fence_simple.glb", 2.0, Vector3(-8, 0, z + 1), 90, false)
		place(yard, NATURE + "fence_simple.glb", 2.0, Vector3(22, 0, z + 1), 90, false)
	# Крыша и внешние стены снаружи: простая плоская крыша с карнизом, чтобы из окон дом выглядел домом.
	box(yard, Vector3(12.8, 0.25, 9.8), Vector3(6, WALL_H + 0.25, 4.5), Color("#8a4a3a"), false, 0.8)
