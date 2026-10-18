@tool
extends EditorPlugin
## «Ухо и рука»: слушает локальный порт и выполняет команды от enginectl.
## Протокол: одна строка JSON на запрос и одна строка JSON на ответ.
## Запрос: {"token": "...", "command": "doctor", "args": {}}
## Ответ:  {"status": "ok"|"error", "result": {...}, "errors": [], "warnings": [], "files": []}

const PLUGIN_VERSION := "0.5.0"
const HOST := "127.0.0.1"
const DEFAULT_PORT := 47615
const PORT_TRIES := 10
const STATE_DIR := "res://.godot/ai_bridge"
const MAX_LINE_BYTES := 1024 * 1024

const SELFTEST_FLAG := "--ai-bridge-selftest"
const SELFTEST_TIMEOUT_FRAMES := 600

var _server := TCPServer.new()
var _clients: Array[Dictionary] = []
var _token := ""
var _port := 0
var _selftest := {"stage": 0, "peer": null, "buffer": PackedByteArray(), "results": [], "frames": 0}


func _enter_tree() -> void:
	_token = _make_token()
	for i in PORT_TRIES:
		if _server.listen(DEFAULT_PORT + i, HOST) == OK:
			_port = DEFAULT_PORT + i
			break
	if _port == 0:
		push_error("AI Bridge: не удалось открыть порт %d..%d" % [DEFAULT_PORT, DEFAULT_PORT + PORT_TRIES - 1])
		return
	_write_connection_file()
	print("AI Bridge %s: слушаю %s:%d" % [PLUGIN_VERSION, HOST, _port])
	if SELFTEST_FLAG in OS.get_cmdline_user_args():
		_selftest.stage = 1


func _exit_tree() -> void:
	for c in _clients:
		c.peer.disconnect_from_host()
	_clients.clear()
	_server.stop()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STATE_DIR + "/connection.json"))


func _process(_delta: float) -> void:
	while _server.is_listening() and _server.is_connection_available():
		_clients.append({"peer": _server.take_connection(), "buffer": PackedByteArray()})

	for c in _clients.duplicate():
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.erase(c)
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var got := peer.get_data(available)
			if got[0] == OK:
				c.buffer.append_array(got[1])
		if c.buffer.size() > MAX_LINE_BYTES:
			_send(peer, _error("Запрос слишком большой"))
			peer.disconnect_from_host()
			_clients.erase(c)
			continue
		var newline: int = c.buffer.find(10)
		while newline != -1:
			var line: String = c.buffer.slice(0, newline).get_string_from_utf8()
			c.buffer = c.buffer.slice(newline + 1)
			_send(peer, _handle_line(line))
			newline = c.buffer.find(10)

	if _selftest.stage > 0:
		_run_selftest()


## Самопроверка: плагин сам подключается к своему порту как обычный клиент и шлёт два
## запроса (верный и неверный токен), печатает ответы и закрывает редактор.
## Запуск: Godot --headless --path <проект> --editor -- --ai-bridge-selftest
func _run_selftest() -> void:
	_selftest.frames += 1
	if _selftest.frames > SELFTEST_TIMEOUT_FRAMES:
		_selftest_finish("ответ не пришёл за %d кадров" % SELFTEST_TIMEOUT_FRAMES)
		return
	match _selftest.stage:
		1:
			var peer := StreamPeerTCP.new()
			if peer.connect_to_host(HOST, _port) != OK:
				_selftest_finish("не удалось подключиться к %s:%d" % [HOST, _port])
				return
			_selftest.peer = peer
			_selftest.stage = 2
		2:
			var peer: StreamPeerTCP = _selftest.peer
			peer.poll()
			var status := peer.get_status()
			if status == StreamPeerTCP.STATUS_CONNECTED:
				for request in [
					{"token": _token, "command": "doctor", "args": {}},
					{"token": "wrong-token", "command": "doctor", "args": {}},
				]:
					peer.put_data((JSON.stringify(request) + "\n").to_utf8_buffer())
				_selftest.stage = 3
			elif status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
				_selftest_finish("соединение с %s:%d не установилось" % [HOST, _port])
		3:
			var peer: StreamPeerTCP = _selftest.peer
			peer.poll()
			var available := peer.get_available_bytes()
			if available > 0:
				var got := peer.get_data(available)
				if got[0] == OK:
					_selftest.buffer.append_array(got[1])
			var newline: int = _selftest.buffer.find(10)
			while newline != -1:
				_selftest.results.append(_selftest.buffer.slice(0, newline).get_string_from_utf8())
				_selftest.buffer = _selftest.buffer.slice(newline + 1)
				newline = _selftest.buffer.find(10)
			if _selftest.results.size() >= 2:
				_selftest_finish("")


func _selftest_finish(error: String) -> void:
	_selftest.stage = 0
	if _selftest.peer != null:
		_selftest.peer.disconnect_from_host()
	var passed := false
	if error != "":
		printerr("AI Bridge selftest: FAIL: %s" % error)
	else:
		print("AI Bridge selftest: ответ на верный токен: %s" % _selftest.results[0])
		print("AI Bridge selftest: ответ на неверный токен: %s" % _selftest.results[1])
		var first = JSON.parse_string(_selftest.results[0])
		var second = JSON.parse_string(_selftest.results[1])
		passed = (
			typeof(first) == TYPE_DICTIONARY and first.get("status") == "ok"
			and typeof(second) == TYPE_DICTIONARY and second.get("status") == "error"
		)
		print("AI Bridge selftest: %s" % ("PASS" if passed else "FAIL"))
	get_tree().quit(0 if passed else 1)


func _handle_line(line: String) -> Dictionary:
	var request = JSON.parse_string(line)
	if typeof(request) != TYPE_DICTIONARY:
		return _error("Запрос не является JSON-объектом")
	if str(request.get("token", "")) != _token:
		return _error("Неверный токен подключения")
	var args = request.get("args", {})
	if typeof(args) != TYPE_DICTIONARY:
		return _error("Поле args должно быть объектом")
	match str(request.get("command", "")):
		"doctor":
			return _ok(_doctor())
		"scene.inspect":
			return _scene_inspect(args)
		"scene.apply":
			return _scene_apply(args)
		"scene.save":
			return _scene_save()
		"scene.new":
			return _scene_new(args)
		"scene.build":
			return _scene_build(args)
		"scene.open":
			return _scene_open(args)
		"script.set":
			return _script_set(args)
		"project.main_scene":
			return _project_main_scene(args)
		"scene.undo":
			return _scene_undo(true)
		"scene.redo":
			return _scene_undo(false)
		var unknown:
			return _error("Неизвестная команда: %s" % unknown)


# ---------------------------------------------------------------------------
# scene.apply: набор изменений сцены через Undo/Redo редактора.
# args.ops — список операций, args.dry_run — только показать план.
# Операции:
#   {"op": "create", "parent": ".", "name": "Cube", "type": "MeshInstance3D", "props": {...}}
#   {"op": "set", "path": "Cube", "props": {"position": [1, 0.5, 0]}}
#   {"op": "delete", "path": "Cube"}
# Значения свойств: числа, строки, bool, массивы из 2/3/4 чисел (Vector2/Vector3/Color),
# "res://..." для ресурсов, для mesh — {"primitive": "box"|"plane"|"sphere"|"cylinder"|"capsule", ...},
# для material — {"color": [r, g, b]} или {"color": "#rrggbb"}.
# Сначала проверяются все операции; если хоть одна неверна, не применяется ничего.
# ---------------------------------------------------------------------------

const UNDO_LABEL := "AI Bridge: scene apply"


func _scene_apply(args: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _error("В редакторе не открыта ни одна сцена")
	var ops = args.get("ops", [])
	if typeof(ops) != TYPE_ARRAY or ops.is_empty():
		return _error("Поле ops должно быть непустым списком операций")
	var dry_run := bool(args.get("dry_run", false))

	# Этап 1: проверка и построение плана. created: путь -> ещё не добавленный узел.
	var plan: Array = []
	var errors: Array = []
	var steps: Array = []  # что именно делать при применении
	var created: Dictionary = {}
	var deleted: Dictionary = {}
	for i in ops.size():
		var op = ops[i]
		if typeof(op) != TYPE_DICTIONARY:
			errors.append("Операция %d: должна быть объектом" % i)
			continue
		var kind := str(op.get("op", ""))
		match kind:
			"create":
				_plan_create(i, op, root, created, deleted, plan, steps, errors)
			"set":
				_plan_set(i, op, root, created, deleted, plan, steps, errors)
			"delete":
				_plan_delete(i, op, root, created, deleted, plan, steps, errors)
			_:
				errors.append("Операция %d: неизвестный тип «%s» (ожидается create, set или delete)" % [i, kind])
	if not errors.is_empty():
		# Узлы, созданные для плана, но не добавленные в сцену, освобождаем.
		for node in created.values():
			node.free()
		var response := _error("План не применён: найдены ошибки")
		response["errors"] = errors
		response["result"] = {"plan": plan, "dry_run": dry_run, "applied": false}
		return response
	if dry_run:
		for node in created.values():
			node.free()
		return _ok({"plan": plan, "dry_run": true, "applied": false, "scene_path": root.scene_file_path})

	# Этап 2: применение одним действием Undo/Redo.
	var ur := get_undo_redo()
	ur.create_action("%s (%d)" % [UNDO_LABEL, steps.size()], UndoRedo.MERGE_DISABLE, root)
	for step in steps:
		match step["kind"]:
			"create":
				ur.add_do_method(step["parent"], "add_child", step["node"])
				ur.add_do_method(step["node"], "set_owner", root)
				ur.add_do_reference(step["node"])
				ur.add_undo_method(step["parent"], "remove_child", step["node"])
			"set":
				ur.add_do_property(step["node"], step["prop"], step["value"])
				ur.add_undo_property(step["node"], step["prop"], step["old"])
			"delete":
				ur.add_do_method(step["parent"], "remove_child", step["node"])
				ur.add_undo_method(step["parent"], "add_child", step["node"])
				ur.add_undo_method(step["parent"], "move_child", step["node"], step["index"])
				ur.add_undo_method(self, "_set_owner_many", step["owned"], root)
				ur.add_undo_reference(step["node"])
	ur.commit_action()
	EditorInterface.mark_scene_as_unsaved()
	return _ok({"plan": plan, "dry_run": false, "applied": true, "scene_path": root.scene_file_path,
		"undo_hint": "Отменить: Ctrl+Z в редакторе"})


func _plan_create(i: int, op: Dictionary, root: Node, created: Dictionary, deleted: Dictionary,
		plan: Array, steps: Array, errors: Array) -> void:
	var type := str(op.get("type", ""))
	var name := str(op.get("name", ""))
	var parent_path := str(op.get("parent", "."))
	if name == "" or name.validate_node_name() != name:
		errors.append("Операция %d: имя узла «%s» пустое или содержит недопустимые символы" % [i, name])
		return
	if not ClassDB.class_exists(type) or not ClassDB.can_instantiate(type) or not ClassDB.is_parent_class(type, "Node"):
		errors.append("Операция %d: тип «%s» не существует или это не узел" % [i, type])
		return
	var parent := _resolve(root, parent_path, created, deleted)
	if parent == null:
		errors.append("Операция %d: родитель «%s» не найден" % [i, parent_path])
		return
	var new_path := _join_path(root, parent, name, created)
	if parent.has_node(name) or created.has(new_path):
		errors.append("Операция %d: у «%s» уже есть дочерний узел «%s»" % [i, parent_path, name])
		return
	var node: Node = ClassDB.instantiate(type)
	node.name = name
	created[new_path] = node
	steps.append({"kind": "create", "parent": parent, "node": node})
	var entry := {"op": "create", "path": new_path, "type": type, "props": {}}
	var props = op.get("props", {})
	if typeof(props) != TYPE_DICTIONARY:
		errors.append("Операция %d: props должно быть объектом" % i)
		return
	for prop in props:
		var converted := _coerce(node, str(prop), props[prop])
		if converted.has("error"):
			errors.append("Операция %d: %s" % [i, converted["error"]])
			continue
		node.set(str(prop), converted["value"])
		entry["props"][str(prop)] = _to_json(converted["value"])
	plan.append(entry)


func _plan_set(i: int, op: Dictionary, root: Node, created: Dictionary, deleted: Dictionary,
		plan: Array, steps: Array, errors: Array) -> void:
	var path := str(op.get("path", ""))
	var node := _resolve(root, path, created, deleted)
	if node == null:
		errors.append("Операция %d: узел «%s» не найден" % [i, path])
		return
	var props = op.get("props", {})
	if typeof(props) != TYPE_DICTIONARY or props.is_empty():
		errors.append("Операция %d: props должно быть непустым объектом" % i)
		return
	var entry := {"op": "set", "path": path, "changes": {}}
	for prop in props:
		var converted := _coerce(node, str(prop), props[prop])
		if converted.has("error"):
			errors.append("Операция %d: %s" % [i, converted["error"]])
			continue
		var old = node.get(str(prop))
		if created.values().has(node):
			node.set(str(prop), converted["value"])  # узел ещё не в сцене, менять можно напрямую
		else:
			steps.append({"kind": "set", "node": node, "prop": str(prop), "value": converted["value"], "old": old})
		entry["changes"][str(prop)] = {"from": _to_json(old), "to": _to_json(converted["value"])}
	plan.append(entry)


func _plan_delete(i: int, op: Dictionary, root: Node, created: Dictionary, deleted: Dictionary,
		plan: Array, steps: Array, errors: Array) -> void:
	var path := str(op.get("path", ""))
	var node := _resolve(root, path, created, deleted)
	if node == null:
		errors.append("Операция %d: узел «%s» не найден" % [i, path])
		return
	if node == root:
		errors.append("Операция %d: корень сцены удалить нельзя" % i)
		return
	if created.values().has(node):
		errors.append("Операция %d: узел «%s» создаётся в этом же наборе, уберите его создание" % [i, path])
		return
	deleted[path] = true
	var owned := _collect_owned(node, root)
	steps.append({"kind": "delete", "parent": node.get_parent(), "node": node,
		"index": node.get_index(), "owned": owned})
	plan.append({"op": "delete", "path": path, "type": node.get_class(), "descendants": owned.size() - 1})


## Ищет узел по пути от корня: сначала в сцене, затем среди только что созданных.
func _resolve(root: Node, path: String, created: Dictionary, deleted: Dictionary) -> Node:
	if path == "" or path == ".":
		return root
	if deleted.has(path):
		return null
	if created.has(path):
		return created[path]
	return root.get_node_or_null(path)


func _join_path(root: Node, parent: Node, name: String, created: Dictionary) -> String:
	if parent == root:
		return name
	for key in created:
		if created[key] == parent:
			return key + "/" + name
	return str(root.get_path_to(parent)) + "/" + name


func _collect_owned(node: Node, root: Node) -> Array:
	var result: Array = [node]
	for child in node.get_children():
		if child.owner == root:
			result.append_array(_collect_owned(child, root))
	return result


func _set_owner_many(nodes: Array, root: Node) -> void:
	for node in nodes:
		node.owner = root


## Переводит значение из JSON в тип свойства узла. Возвращает {"value": ...} или {"error": "..."}.
func _coerce(node: Node, prop: String, value: Variant) -> Dictionary:
	if not _has_property(node, prop):
		return {"error": "у %s нет свойства «%s»" % [node.get_class(), prop]}
	if prop == "mesh" and typeof(value) == TYPE_DICTIONARY:
		return _make_mesh(value)
	if prop == "material_override" or prop == "material":
		if typeof(value) == TYPE_DICTIONARY:
			return _make_material(value)
	if typeof(value) == TYPE_STRING and str(value).begins_with("res://"):
		var res := load(str(value))
		if res == null:
			return {"error": "ресурс «%s» не найден" % value}
		return {"value": res}
	var current = node.get(prop)
	match typeof(current):
		TYPE_VECTOR3:
			if _is_number_array(value, 3):
				return {"value": Vector3(value[0], value[1], value[2])}
			return {"error": "«%s» ожидает список из 3 чисел" % prop}
		TYPE_VECTOR2:
			if _is_number_array(value, 2):
				return {"value": Vector2(value[0], value[1])}
			return {"error": "«%s» ожидает список из 2 чисел" % prop}
		TYPE_COLOR:
			var color := _to_color(value)
			if color.has("error"):
				return {"error": "«%s»: %s" % [prop, color["error"]]}
			return color
		TYPE_INT:
			if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
				return {"value": int(value)}
			return {"error": "«%s» ожидает число" % prop}
		TYPE_FLOAT:
			if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
				return {"value": float(value)}
			return {"error": "«%s» ожидает число" % prop}
		TYPE_BOOL:
			if typeof(value) == TYPE_BOOL:
				return {"value": value}
			return {"error": "«%s» ожидает true или false" % prop}
		TYPE_STRING, TYPE_STRING_NAME:
			return {"value": str(value)}
		TYPE_NODE_PATH:
			return {"value": NodePath(str(value))}
		_:
			return {"value": value}


func _has_property(node: Node, prop: String) -> bool:
	for p in node.get_property_list():
		if p.name == prop:
			return true
	return false


func _is_number_array(value: Variant, size: int) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != size:
		return false
	for v in value:
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			return false
	return true


func _to_color(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_STRING and Color.html_is_valid(str(value)):
		return {"value": Color.html(str(value))}
	if _is_number_array(value, 3):
		return {"value": Color(value[0], value[1], value[2])}
	if _is_number_array(value, 4):
		return {"value": Color(value[0], value[1], value[2], value[3])}
	return {"error": "цвет задаётся как \"#rrggbb\" или список из 3–4 чисел от 0 до 1"}


func _make_mesh(spec: Dictionary) -> Dictionary:
	var primitive := str(spec.get("primitive", "box"))
	var mesh: PrimitiveMesh
	match primitive:
		"box":
			var box := BoxMesh.new()
			if spec.has("size"):
				if not _is_number_array(spec["size"], 3):
					return {"error": "size для box: список из 3 чисел"}
				box.size = Vector3(spec["size"][0], spec["size"][1], spec["size"][2])
			mesh = box
		"plane":
			var plane := PlaneMesh.new()
			if spec.has("size"):
				if not _is_number_array(spec["size"], 2):
					return {"error": "size для plane: список из 2 чисел"}
				plane.size = Vector2(spec["size"][0], spec["size"][1])
			mesh = plane
		"sphere":
			var sphere := SphereMesh.new()
			if spec.has("radius"):
				sphere.radius = float(spec["radius"])
				sphere.height = float(spec.get("height", sphere.radius * 2.0))
			mesh = sphere
		"cylinder":
			var cylinder := CylinderMesh.new()
			if spec.has("radius"):
				cylinder.top_radius = float(spec["radius"])
				cylinder.bottom_radius = float(spec["radius"])
			if spec.has("height"):
				cylinder.height = float(spec["height"])
			mesh = cylinder
		"capsule":
			var capsule := CapsuleMesh.new()
			if spec.has("radius"):
				capsule.radius = float(spec["radius"])
			if spec.has("height"):
				capsule.height = float(spec["height"])
			mesh = capsule
		_:
			return {"error": "неизвестный примитив «%s» (box, plane, sphere, cylinder, capsule)" % primitive}
	if spec.has("color"):
		var color := _to_color(spec["color"])
		if color.has("error"):
			return color
		var material := StandardMaterial3D.new()
		material.albedo_color = color["value"]
		mesh.material = material
	return {"value": mesh}


func _make_material(spec: Dictionary) -> Dictionary:
	var material := StandardMaterial3D.new()
	if spec.has("color"):
		var color := _to_color(spec["color"])
		if color.has("error"):
			return color
		material.albedo_color = color["value"]
	return {"value": material}


## Значение свойства в виде, пригодном для JSON.
func _to_json(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR3:
			return _v3(value)
		TYPE_VECTOR2:
			return _v2(value)
		TYPE_COLOR:
			return [snappedf(value.r, 0.001), snappedf(value.g, 0.001), snappedf(value.b, 0.001), snappedf(value.a, 0.001)]
		TYPE_NODE_PATH, TYPE_STRING_NAME:
			return str(value)
		TYPE_OBJECT:
			if value == null:
				return null
			if value is Resource and value.resource_path != "":
				return value.resource_path
			if value is PrimitiveMesh:
				return _describe_mesh(value)
			if value is StandardMaterial3D:
				return {"material": "StandardMaterial3D", "color": _to_json(value.albedo_color)}
			return value.get_class()
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_ARRAY, TYPE_DICTIONARY:
			return value
		_:
			return str(value)


# ---------------------------------------------------------------------------
# scene.save и scene.new
# ---------------------------------------------------------------------------

func _scene_save() -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _error("В редакторе не открыта ни одна сцена")
	if root.scene_file_path == "":
		return _error("Сцена ещё не сохранялась и не имеет пути; создайте её через scene.new")
	var err := EditorInterface.save_scene()
	if err != OK:
		return _error("Не удалось сохранить сцену: %s" % error_string(err))
	var response := _ok({"scene_path": root.scene_file_path})
	response["files"] = [root.scene_file_path]
	return response


## Создаёт новую сцену с одним корневым узлом, сохраняет и открывает её в редакторе.
## args: path ("res://scenes/x.tscn"), root_type (по умолчанию Node3D), root_name (по умолчанию имя файла).
func _scene_new(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", ""))
	if not path.begins_with("res://") or not path.ends_with(".tscn") or path.contains(".."):
		return _error("path должен быть вида res://папка/имя.tscn")
	if FileAccess.file_exists(path):
		return _error("Файл «%s» уже существует" % path)
	var root_type := str(args.get("root_type", "Node3D"))
	if not ClassDB.class_exists(root_type) or not ClassDB.can_instantiate(root_type) or not ClassDB.is_parent_class(root_type, "Node"):
		return _error("root_type «%s» не существует или это не узел" % root_type)
	var root: Node = ClassDB.instantiate(root_type)
	root.name = str(args.get("root_name", path.get_file().get_basename().to_pascal_case()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	if err != OK:
		return _error("Не удалось собрать сцену: %s" % error_string(err))
	err = ResourceSaver.save(packed, path)
	if err != OK:
		return _error("Не удалось сохранить «%s»: %s" % [path, error_string(err)])
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.open_scene_from_path(path)
	var response := _ok({"scene_path": path, "root_type": root_type})
	response["files"] = [path]
	return response


## Дерево открытой в редакторе сцены. args: path (узел, с которого начать, по умолчанию корень),
## depth (сколько уровней вниз, -1 = все).
func _scene_inspect(args: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _error("В редакторе не открыта ни одна сцена")
	var start: Node = root
	var start_path := str(args.get("path", "."))
	if start_path != "" and start_path != ".":
		start = root.get_node_or_null(start_path)
		if start == null:
			return _error("Узел не найден: %s" % start_path)
	var max_depth := int(args.get("depth", -1))
	var counter := [0]
	var tree := _describe_node(start, root, max_depth, 0, counter)
	return _ok({
		"scene_path": root.scene_file_path,
		"root": tree,
		"node_count": counter[0],
	})


func _describe_node(node: Node, root: Node, max_depth: int, depth: int, counter: Array) -> Dictionary:
	counter[0] += 1
	var info := {
		"name": str(node.name),
		"type": node.get_class(),
		"path": str(root.get_path_to(node)),
	}
	var script = node.get_script()
	if script is Script:
		info["script"] = script.resource_path
	if node != root and node.scene_file_path != "":
		info["instance"] = node.scene_file_path
	if node is Node3D:
		info["position"] = _v3(node.position)
		info["rotation_degrees"] = _v3(node.rotation_degrees)
		info["scale"] = _v3(node.scale)
	elif node is Node2D:
		info["position"] = _v2(node.position)
		info["rotation_degrees"] = snappedf(node.rotation_degrees, 0.001)
		info["scale"] = _v2(node.scale)
	elif node is Control:
		info["position"] = _v2(node.position)
		info["size"] = _v2(node.size)
	var children := []
	if max_depth < 0 or depth < max_depth:
		for child in node.get_children():
			children.append(_describe_node(child, root, max_depth, depth + 1, counter))
	info["children"] = children
	return info


func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


func _v2(v: Vector2) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001)]


func _doctor() -> Dictionary:
	var info := Engine.get_version_info()
	return {
		"message": "Godot на связи",
		"godot_version": info.string,
		"plugin_version": PLUGIN_VERSION,
		"project_name": ProjectSettings.get_setting("application/config/name", ""),
		"project_path": ProjectSettings.globalize_path("res://"),
		"godot_executable": OS.get_executable_path(),
		"edited_scene": _edited_scene_path(),
		"main_scene": str(ProjectSettings.get_setting("application/run/main_scene", "")),
	}


func _edited_scene_path() -> String:
	var root := EditorInterface.get_edited_scene_root()
	return root.scene_file_path if root else ""


func _ok(result: Dictionary) -> Dictionary:
	return {"status": "ok", "result": result, "errors": [], "warnings": [], "files": []}


func _error(message: String) -> Dictionary:
	return {"status": "error", "result": {}, "errors": [message], "warnings": [], "files": []}


func _send(peer: StreamPeerTCP, response: Dictionary) -> void:
	peer.put_data((JSON.stringify(response) + "\n").to_utf8_buffer())


func _make_token() -> String:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(24).hex_encode()


## Файл подключения лежит в .godot/ (не попадает в Git), enginectl читает из него порт и токен.
func _write_connection_file() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STATE_DIR))
	var file := FileAccess.open(STATE_DIR + "/connection.json", FileAccess.WRITE)
	if file == null:
		push_error("AI Bridge: не удалось записать файл подключения")
		return
	file.store_string(JSON.stringify({"host": HOST, "port": _port, "token": _token, "pid": OS.get_process_id(),
		"godot_exe": OS.get_executable_path(), "project_path": ProjectSettings.globalize_path("res://")}, "\t"))


## Отмена или повтор последнего действия в истории открытой сцены (то же, что Ctrl+Z / Ctrl+Y).
func _scene_undo(undo: bool) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _error("В редакторе не открыта ни одна сцена")
	var ur := get_undo_redo()
	var history := ur.get_history_undo_redo(ur.get_object_history_id(root))
	if undo:
		if not history.has_undo():
			return _error("Нечего отменять")
		var action := history.get_current_action_name()
		history.undo()
		EditorInterface.mark_scene_as_unsaved()
		return _ok({"undone": action})
	if not history.has_redo():
		return _error("Нечего повторять")
	history.redo()
	EditorInterface.mark_scene_as_unsaved()
	return _ok({"redone": history.get_current_action_name()})


## Открывает существующую сцену в редакторе.
func _scene_open(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", ""))
	if not path.begins_with("res://") or path.contains(".."):
		return _error("path должен начинаться с res://")
	if not FileAccess.file_exists(path):
		return _error("Файл «%s» не найден" % path)
	EditorInterface.open_scene_from_path(path)
	return _ok({"scene_path": path})


# ---------------------------------------------------------------------------
# script.set: записать GDScript в файл и (по желанию) повесить его на узел открытой сцены.
# args: path ("res://game/hello.gd"), content (текст скрипта), node (путь узла, необязательно).
# Ответ: files = [path], parse_error — текст ошибки разбора, если скрипт не компилируется.
# ---------------------------------------------------------------------------

func _script_set(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", ""))
	if not path.begins_with("res://") or not path.ends_with(".gd") or path.contains(".."):
		return _error("path должен быть вида res://папка/имя.gd")
	if not args.has("content") or typeof(args.content) != TYPE_STRING:
		return _error("content должен быть строкой с текстом скрипта")
	var node: Node = null
	var root := EditorInterface.get_edited_scene_root()
	var node_path := str(args.get("node", ""))
	if node_path != "":
		if root == null:
			return _error("В редакторе не открыта ни одна сцена, некуда вешать скрипт")
		node = root if node_path == "." else root.get_node_or_null(node_path)
		if node == null:
			return _error("Узел «%s» не найден" % node_path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var existed := FileAccess.file_exists(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _error("Не удалось записать «%s»: %s" % [path, error_string(FileAccess.get_open_error())])
	file.store_string(args.content)
	file.close()
	var fs := EditorInterface.get_resource_filesystem()
	if existed:
		fs.update_file(path)
	else:
		fs.scan()
	var script: Script = load(path)
	if script == null:
		return _error("Файл записан, но Godot не смог загрузить его как скрипт: %s" % path)
	var result := {"path": path, "created": not existed}
	# load() отдаёт уже закэшированный скрипт со старым текстом, поэтому обновляем его явно.
	script.source_code = args.content
	var reload_err := script.reload(true)
	if reload_err != OK:
		result["parse_error"] = "скрипт не компилируется (%s), подробности в выводе редактора и в enginectl game run" % error_string(reload_err)
	if node != null:
		var ur := get_undo_redo()
		ur.create_action("AI Bridge: script set %s" % node.name, UndoRedo.MERGE_DISABLE, root)
		ur.add_do_property(node, "script", script)
		ur.add_undo_property(node, "script", node.get_script())
		ur.commit_action()
		EditorInterface.mark_scene_as_unsaved()
		result["attached_to"] = node_path
	var response := _ok(result)
	response["files"] = [path]
	if result.has("parse_error"):
		response["warnings"] = [result["parse_error"]]
	return response


## Назначает главную сцену проекта (её запускает кнопка «Запустить» и enginectl game run без --scene).
func _project_main_scene(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", ""))
	if not path.begins_with("res://") or not path.ends_with(".tscn") or path.contains(".."):
		return _error("path должен быть вида res://папка/имя.tscn")
	if not FileAccess.file_exists(path):
		return _error("Файл «%s» не найден" % path)
	ProjectSettings.set_setting("application/run/main_scene", path)
	var err := ProjectSettings.save()
	if err != OK:
		return _error("Не удалось сохранить настройки проекта: %s" % error_string(err))
	var response := _ok({"main_scene": path})
	response["files"] = ["res://project.godot"]
	return response


## Примитивный меш в виде, пригодном для плана: тип, размеры, цвет.
func _describe_mesh(mesh: PrimitiveMesh) -> Dictionary:
	var info := {"mesh": mesh.get_class()}
	if mesh is BoxMesh or mesh is PlaneMesh:
		info["size"] = _to_json(mesh.size)
	elif mesh is SphereMesh:
		info["radius"] = mesh.radius
		info["height"] = mesh.height
	elif mesh is CylinderMesh:
		info["radius"] = mesh.top_radius
		info["height"] = mesh.height
	elif mesh is CapsuleMesh:
		info["radius"] = mesh.radius
		info["height"] = mesh.height
	if mesh.material is StandardMaterial3D:
		info["color"] = _to_json(mesh.material.albedo_color)
	return info


# ---------------------------------------------------------------------------
# scene.build: новая сцена целиком за один шаг — «пол, две стены и свет одной фразой».
# args: path ("res://scenes/room.tscn"), root_type (Node3D), root_name (по умолчанию из имени файла),
#       ops — операции create/set как в scene.apply, overwrite (false), open (true), main_scene (false).
# Сцена собирается в памяти, поэтому файл появляется только если все операции верны.
# После сохранения файл читается обратно с диска (мимо кэша) и узлы пересчитываются:
# так проверяется, что сцена действительно сохранилась и откроется заново.
# ---------------------------------------------------------------------------

func _scene_build(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", ""))
	if not path.begins_with("res://") or not path.ends_with(".tscn") or path.contains(".."):
		return _error("path должен быть вида res://папка/имя.tscn")
	var overwrite := bool(args.get("overwrite", false))
	if FileAccess.file_exists(path) and not overwrite:
		return _error("Файл «%s» уже существует: укажите другой путь или overwrite" % path)
	var root_type := str(args.get("root_type", "Node3D"))
	if not ClassDB.class_exists(root_type) or not ClassDB.can_instantiate(root_type) or not ClassDB.is_parent_class(root_type, "Node"):
		return _error("root_type «%s» не существует или это не узел" % root_type)
	var root_name := str(args.get("root_name", path.get_file().get_basename().to_pascal_case()))
	if root_name == "" or root_name.validate_node_name() != root_name:
		return _error("root_name «%s» пустое или содержит недопустимые символы" % root_name)
	var ops = args.get("ops", [])
	if typeof(ops) != TYPE_ARRAY or ops.is_empty():
		return _error("Поле ops должно быть непустым списком операций")

	var root: Node = ClassDB.instantiate(root_type)
	root.name = root_name
	var plan: Array = []
	var errors: Array = []
	var steps: Array = []
	var created: Dictionary = {}
	var deleted: Dictionary = {}
	for i in ops.size():
		var op = ops[i]
		if typeof(op) != TYPE_DICTIONARY:
			errors.append("Операция %d: должна быть объектом" % i)
			continue
		var kind := str(op.get("op", ""))
		match kind:
			"create":
				_plan_create(i, op, root, created, deleted, plan, steps, errors)
			"set":
				_plan_set(i, op, root, created, deleted, plan, steps, errors)
			_:
				errors.append("Операция %d: в новой сцене допустимы только create и set, получено «%s»" % [i, kind])
	if not errors.is_empty():
		for node in created.values():
			node.free()
		root.free()
		var response := _error("Сцена не создана: найдены ошибки")
		response["errors"] = errors
		response["result"] = {"plan": plan, "scene_path": path, "built": false}
		return response

	# Узлы пока не в дереве: добавляем их по порядку и назначаем владельца, иначе они не попадут в файл.
	for step in steps:
		match step["kind"]:
			"create":
				step["parent"].add_child(step["node"])
				step["node"].owner = root
			"set":
				step["node"].set(step["prop"], step["value"])
	var node_count := _count_nodes(root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	if err != OK:
		return _error("Не удалось собрать сцену: %s" % error_string(err))
	err = ResourceSaver.save(packed, path)
	if err != OK:
		return _error("Не удалось сохранить «%s»: %s" % [path, error_string(err)])

	# Проверка: файл читается обратно с диска, число узлов должно совпасть.
	var warnings: Array = []
	var reread_count := -1
	var reloaded := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if reloaded != null:
		var copy := reloaded.instantiate()
		reread_count = _count_nodes(copy)
		copy.free()
	if reread_count != node_count:
		warnings.append("Файл сохранён, но при чтении обратно узлов %d вместо %d" % [reread_count, node_count])

	EditorInterface.get_resource_filesystem().scan()
	var opened := false
	if bool(args.get("open", true)):
		if overwrite and _edited_scene_path() == path:
			EditorInterface.reload_scene_from_path(path)
		else:
			EditorInterface.open_scene_from_path(path)
		opened = true
	var main_set := false
	if bool(args.get("main_scene", false)):
		ProjectSettings.set_setting("application/run/main_scene", path)
		if ProjectSettings.save() == OK:
			main_set = true
		else:
			warnings.append("Сцена создана, но назначить её главной не удалось (project.godot не сохранился)")

	var response := _ok({"scene_path": path, "root_type": root_type, "root_name": root_name,
		"node_count": node_count, "reread_node_count": reread_count, "built": true, "opened": opened,
		"main_scene": main_set, "plan": plan,
		"undo_hint": "Сцена новая, в истории Undo её нет; чтобы убрать, удалите файл %s" % path})
	response["warnings"] = warnings
	response["files"] = [path] if not main_set else [path, "res://project.godot"]
	return response


func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count
