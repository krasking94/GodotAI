@tool
extends EditorPlugin
## «Ухо и рука»: слушает локальный порт и выполняет команды от enginectl.
## Протокол: одна строка JSON на запрос и одна строка JSON на ответ.
## Запрос: {"token": "...", "command": "doctor", "args": {}}
## Ответ:  {"status": "ok"|"error", "result": {...}, "errors": [], "warnings": [], "files": []}

const PLUGIN_VERSION := "0.10.1"
## Флаги, при которых Godot запускает редактор лишь на время разовой задачи (сборка, импорт, проверка).
const BATCH_FLAGS := ["--export-debug", "--export-release", "--export-pack", "--export-patch", "--import",
	"--quit", "--quit-after", "--doctool", "--check-only", "--convert-3to4", "--validate-conversion-3to4"]
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
	# Godot поднимает редактор (и плагины) и для разовых задач: --export-*, --import, --quit-after…
	# Такой процесс живёт секунды; если он откроет порт и перепишет connection.json, файл настоящего
	# редактора будет затёрт, а потом удалён, и enginectl потеряет связь. Поэтому в пакетном режиме молчим.
	for arg in OS.get_cmdline_args():
		for batch_flag in BATCH_FLAGS:
			if arg == batch_flag or arg.begins_with(batch_flag + "="):
				print("AI Bridge %s: пакетный режим (%s), сервер не запускаю" % [PLUGIN_VERSION, arg])
				return
	var other_pid := _connection_file_pid()
	if other_pid > 0 and other_pid != OS.get_process_id() and OS.is_process_running(other_pid):
		print("AI Bridge %s: проект уже открыт другим редактором (pid %d), этот сервер не запускаю" % [PLUGIN_VERSION, other_pid])
		return
	_token = _make_token()
	for i in PORT_TRIES:
		if _server.listen(DEFAULT_PORT + i, HOST) == OK:
			_port = DEFAULT_PORT + i
			break
	if _port == 0:
		push_error("AI Bridge: не удалось открыть порт %d..%d" % [DEFAULT_PORT, DEFAULT_PORT + PORT_TRIES - 1])
		return
	_write_connection_file()
	_journal_load()
	_build_dock()
	print("AI Bridge %s: слушаю %s:%d" % [PLUGIN_VERSION, HOST, _port])
	if SELFTEST_FLAG in OS.get_cmdline_user_args():
		_selftest.stage = 1


func _exit_tree() -> void:
	for c in _clients:
		c.peer.disconnect_from_host()
	_clients.clear()
	_server.stop()
	if _dock_panel != null:
		remove_dock(_dock_panel)
		_dock_panel.queue_free()
		_dock_panel = null
		_dock = null
	# Удаляем только свой файл подключения: чужой (другого редактора) не трогаем.
	if _port != 0 and _connection_file_pid() == OS.get_process_id():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(STATE_DIR + "/connection.json"))


## pid из существующего connection.json или 0, если файла нет или он не читается.
func _connection_file_pid() -> int:
	var path := ProjectSettings.globalize_path(STATE_DIR + "/connection.json")
	if not FileAccess.file_exists(path):
		return 0
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return int(parsed.get("pid", 0)) if parsed is Dictionary else 0


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
	var command := str(request.get("command", ""))
	var before := _before_command(command, args)  # что было до команды, чтобы задача могла её отменить
	var response := _dispatch(command, args)
	_record(command, args, response, before)
	return response


func _dispatch(command: String, args: Dictionary) -> Dictionary:
	match command:
		"doctor":
			return _ok(_doctor())
		"task.begin":
			return _task_begin(args)
		"task.end":
			return _task_end(args)
		"task.list":
			return _task_list(args)
		"task.undo":
			return _task_undo(args)
		"journal.get":
			return _journal_get(args)
		"journal.clear":
			return _journal_clear()
		"journal.add":
			return _journal_add(args)
		"editor.screenshot":
			return _editor_screenshot(args)
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
		"project.refresh":
			return _project_refresh(args)
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
#   {"op": "instance", "parent": ".", "name": "Car", "scene": "res://scenes/car.tscn", "props": {...}} — готовая сцена как узел
# Значения свойств: числа, строки, bool, массивы из 2/3/4 чисел (Vector2/Vector3/Color),
# "res://..." для ресурсов, для mesh — {"primitive": "box"|"plane"|"sphere"|"cylinder"|"capsule", ...},
# для material — {"color": [r, g, b]} или {"color": "#rrggbb"}.
# Сначала проверяются все операции; если хоть одна неверна, не применяется ничего.
# ---------------------------------------------------------------------------

const UNDO_LABEL := "AI Bridge: scene apply"
const BACKUP_KEEP := 20  # сколько резервных копий сцен хранить в .godot/ai_bridge/backup
var _build_target_path := ""  # путь сцены, которую сейчас собирает scene.build (чтобы не вложить её в саму себя)


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
			"instance":
				_plan_instance(i, op, root, created, deleted, plan, steps, errors)
			_:
				errors.append("Операция %d: неизвестный тип «%s» (ожидается create, set, delete или instance)" % [i, kind])
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
	# Номер записи журнала в имени действия: так task.undo отличает это действие от других таких же.
	ur.create_action("%s (%d) #%d" % [UNDO_LABEL, steps.size(), _next_id], UndoRedo.MERGE_DISABLE, root)
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


## Вставка готовой сцены как узла: {"op": "instance", "parent": ".", "name": "Car", "scene": "res://scenes/car.tscn", "props": {...}}.
## Свойства задаются корню экземпляра (позиция, поворот, @export-поля его скрипта); внутренние узлы живут в своей сцене.
func _plan_instance(i: int, op: Dictionary, root: Node, created: Dictionary, deleted: Dictionary,
		plan: Array, steps: Array, errors: Array) -> void:
	var scene_path := str(op.get("scene", ""))
	var name := str(op.get("name", scene_path.get_file().get_basename().to_pascal_case()))
	var parent_path := str(op.get("parent", "."))
	if name == "" or name.validate_node_name() != name:
		errors.append("Операция %d: имя узла «%s» пустое или содержит недопустимые символы" % [i, name])
		return
	if not scene_path.begins_with("res://") or not FileAccess.file_exists(scene_path):
		errors.append("Операция %d: сцена «%s» не найдена (ожидается путь res://…tscn)" % [i, scene_path])
		return
	if scene_path == root.scene_file_path or scene_path == _build_target_path:
		errors.append("Операция %d: сцена не может содержать саму себя (%s)" % [i, scene_path])
		return
	var parent := _resolve(root, parent_path, created, deleted)
	if parent == null:
		errors.append("Операция %d: родитель «%s» не найден" % [i, parent_path])
		return
	var new_path := _join_path(root, parent, name, created)
	if parent.has_node(name) or created.has(new_path):
		errors.append("Операция %d: у «%s» уже есть дочерний узел «%s»" % [i, parent_path, name])
		return
	# Читаем с диска, а не из кэша: файл мог быть только что пересобран.
	var packed := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if packed == null or not packed.can_instantiate():
		errors.append("Операция %d: «%s» не сцена или не читается" % [i, scene_path])
		return
	var node := packed.instantiate()
	node.name = name
	created[new_path] = node
	steps.append({"kind": "create", "parent": parent, "node": node})
	var entry := {"op": "instance", "path": new_path, "scene": scene_path, "type": node.get_class(), "props": {}}
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
		# Свежий узел (создан в этом же наборе или корень собираемой сцены) ещё не в дереве редактора:
		# меняем напрямую. Так «script» вступает в силу сразу, и следующие свойства того же set
		# (например @export-поля скрипта) проходят проверку «есть ли такое свойство».
		if created.values().has(node) or (node == root and _build_target_path != ""):
			node.set(str(prop), converted["value"])
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
	if prop == "shape" and typeof(value) == TYPE_DICTIONARY:
		return _make_shape_2d(value) if node is CollisionShape2D else _make_shape(value)
	if prop == "environment" and typeof(value) == TYPE_DICTIONARY:
		return _make_environment(value)
	if prop == "material_override" or prop == "material":
		if typeof(value) == TYPE_DICTIONARY:
			return _make_material(value)
	if typeof(value) == TYPE_STRING and str(value).begins_with("res://"):
		var res := _load_fresh(str(value))
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


## Загружает ресурс по пути. Для скрипта сверяет текст с диском: редактор без фокуса не замечает
## правок, сделанных снаружи (ИИ правит файл), и load() отдаёт из кэша старый текст без новых свойств.
func _load_fresh(path: String) -> Resource:
	var res := load(path)
	if res is Script:
		_refresh_script(res)
	return res


## Если текст скрипта на диске отличается от загруженного, подтягивает его и перекомпилирует. true = обновлён.
func _refresh_script(script: Script) -> bool:
	var path := script.resource_path
	if not path.begins_with("res://"):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	if text == script.source_code:
		return false
	script.source_code = text
	script.reload(true)
	return true


func _all_nodes(node: Node) -> Array:
	var result: Array = [node]
	for child in node.get_children():
		result.append_array(_all_nodes(child))
	return result


## Пути открытых сцен с несохранёнными изменениями. Публичного API у редактора нет, поэтому читаем
## заголовки вкладок сцен: несохранённая помечена «(*)». Если вкладки не нашлись, возвращаем [].
func _unsaved_open_scenes() -> Array:
	var open: Array = EditorInterface.get_open_scenes()
	var by_title := {}
	for scene_path in open:
		by_title[str(scene_path).get_file().get_basename()] = scene_path
	for bar in EditorInterface.get_base_control().find_children("*", "TabBar", true, false):
		if bar.tab_count == 0:
			continue
		var looks_like_scene_tabs := true
		for t in bar.tab_count:
			var title: String = bar.get_tab_title(t).trim_suffix("(*)")
			if not by_title.has(title) and not title.begins_with("["):
				looks_like_scene_tabs = false
				break
		if not looks_like_scene_tabs:
			continue
		var result: Array = []
		for t in bar.tab_count:
			var raw: String = bar.get_tab_title(t)
			if raw.ends_with("(*)") and by_title.has(raw.trim_suffix("(*)")):
				result.append(by_title[raw.trim_suffix("(*)")])
		return result
	return []


## Сохраняет текущее состояние открытой сцены (как она сейчас в редакторе, с несохранёнными правками)
## в .godot/ai_bridge/backup/, чтобы перезапись файла ничего не потеряла. Возвращает путь копии или "".
func _backup_open_scene(path: String) -> String:
	for scene_root in EditorInterface.get_open_scene_roots():
		if scene_root == null or scene_root.scene_file_path != path:
			continue
		var packed := PackedScene.new()
		if packed.pack(scene_root) != OK:
			return ""
		var dir := "res://.godot/ai_bridge/backup"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var stamp := Time.get_datetime_string_from_system().replace(":", "-")
		var backup := "%s/%s_%s.tscn" % [dir, path.get_file().get_basename(), stamp]
		if ResourceSaver.save(packed, backup) == OK:
			_prune_backups(dir, BACKUP_KEEP)
			return backup
		return ""
	return ""


## Оставляет в папке резервных копий только BACKUP_KEEP самых новых файлов (имена содержат дату, сортировка по имени).
func _prune_backups(dir: String, keep: int) -> void:
	var names: Array = []
	for name in DirAccess.get_files_at(dir):
		if name.ends_with(".tscn"):
			names.append(name)
	names.sort()
	while names.size() > keep:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(names.pop_front())))


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
	if spec.has("shader"):
		var shader_material := _make_shader_material(spec)
		if shader_material.has("error"):
			return shader_material
		mesh.material = shader_material["value"]
	elif spec.has("color"):
		var color := _to_color(spec["color"])
		if color.has("error"):
			return color
		var material := StandardMaterial3D.new()
		material.albedo_color = color["value"]
		mesh.material = material
	return {"value": mesh}


## Физическая форма для CollisionShape3D: {"primitive": "box"|"sphere"|"capsule"|"cylinder", "size": [x, y, z], "radius": r, "height": h}.
func _make_shape(spec: Dictionary) -> Dictionary:
	var primitive := str(spec.get("primitive", "box"))
	match primitive:
		"box":
			var box := BoxShape3D.new()
			if spec.has("size"):
				if not _is_number_array(spec["size"], 3):
					return {"error": "size для box: список из 3 чисел"}
				box.size = Vector3(spec["size"][0], spec["size"][1], spec["size"][2])
			return {"value": box}
		"sphere":
			var sphere := SphereShape3D.new()
			if spec.has("radius"):
				sphere.radius = float(spec["radius"])
			return {"value": sphere}
		"capsule":
			var capsule := CapsuleShape3D.new()
			if spec.has("radius"):
				capsule.radius = float(spec["radius"])
			if spec.has("height"):
				capsule.height = float(spec["height"])
			return {"value": capsule}
		"cylinder":
			var cylinder := CylinderShape3D.new()
			if spec.has("radius"):
				cylinder.radius = float(spec["radius"])
			if spec.has("height"):
				cylinder.height = float(spec["height"])
			return {"value": cylinder}
		_:
			return {"error": "неизвестная форма «%s» (box, sphere, capsule, cylinder)" % primitive}


## Физическая форма для CollisionShape2D: {"primitive": "rectangle"|"circle"|"capsule", "size": [w, h], "radius", "height"}.
func _make_shape_2d(spec: Dictionary) -> Dictionary:
	var primitive := str(spec.get("primitive", "rectangle"))
	match primitive:
		"rectangle", "box":
			var rect := RectangleShape2D.new()
			if spec.has("size"):
				if not _is_number_array(spec["size"], 2):
					return {"error": "size для rectangle: список из 2 чисел"}
				rect.size = Vector2(spec["size"][0], spec["size"][1])
			return {"value": rect}
		"circle", "sphere":
			var circle := CircleShape2D.new()
			if spec.has("radius"):
				circle.radius = float(spec["radius"])
			return {"value": circle}
		"capsule":
			var capsule := CapsuleShape2D.new()
			if spec.has("radius"):
				capsule.radius = float(spec["radius"])
			if spec.has("height"):
				capsule.height = float(spec["height"])
			return {"value": capsule}
		_:
			return {"error": "неизвестная 2D-форма «%s» (rectangle, circle, capsule)" % primitive}


## Окружение для WorldEnvironment: {"sky": true, "ambient_energy": 0.0..1.0, "sky_color": цвет, "horizon_color": цвет, "fog": true}.
## С небом теневые стороны объектов подсвечиваются рассеянным светом, а фон становится небом.
func _make_environment(spec: Dictionary) -> Dictionary:
	var env := Environment.new()
	if bool(spec.get("sky", true)):
		var material := ProceduralSkyMaterial.new()
		for key in ["sky_color", "horizon_color", "ground_color"]:
			if spec.has(key):
				var color := _to_color(spec[key])
				if color.has("error"):
					return {"error": "%s: %s" % [key, color["error"]]}
				if key == "sky_color":
					material.sky_top_color = color["value"]
				elif key == "horizon_color":
					material.sky_horizon_color = color["value"]
					material.ground_horizon_color = color["value"]
				else:
					material.ground_bottom_color = color["value"]
		var sky := Sky.new()
		sky.sky_material = material
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	if spec.has("ambient_energy"):
		env.ambient_light_energy = float(spec["ambient_energy"])
	if bool(spec.get("fog", false)):
		env.fog_enabled = true
	return {"value": env}


## Материал: {"color": цвет} — обычный, или {"shader": "res://….gdshader", "params": {…}} — с шейдером.
func _make_material(spec: Dictionary) -> Dictionary:
	if spec.has("shader"):
		return _make_shader_material(spec)
	var material := StandardMaterial3D.new()
	if spec.has("color"):
		var color := _to_color(spec["color"])
		if color.has("error"):
			return color
		material.albedo_color = color["value"]
	return {"value": material}


## Материал с шейдером из файла: {"shader": "res://game/grid.gdshader", "params": {"cell": 4, "line_color": "#ffffff"}}.
## Цвет в params задаётся как "#rrggbb", списки из 2–3 чисел становятся Vector2/Vector3.
func _make_shader_material(spec: Dictionary) -> Dictionary:
	var shader_path := str(spec["shader"])
	var shader = load(shader_path) if shader_path.begins_with("res://") else null
	if shader == null or not (shader is Shader):
		return {"error": "шейдер «%s» не найден (ожидается путь res://….gdshader)" % shader_path}
	var material := ShaderMaterial.new()
	material.shader = shader
	var params = spec.get("params", {})
	if typeof(params) != TYPE_DICTIONARY:
		return {"error": "params шейдера: ожидается объект {имя: значение}"}
	for key in params:
		var value = params[key]
		if typeof(value) == TYPE_STRING and str(value).begins_with("#"):
			var color := _to_color(value)
			if color.has("error"):
				return {"error": "%s: %s" % [key, color["error"]]}
			value = color["value"]
		elif _is_number_array(value, 3):
			value = Vector3(value[0], value[1], value[2])
		elif _is_number_array(value, 2):
			value = Vector2(value[0], value[1])
		material.set_shader_parameter(key, value)
	return {"value": material}


func _describe_material(material: Material) -> Variant:
	if material is StandardMaterial3D:
		return {"material": "StandardMaterial3D", "color": _to_json(material.albedo_color)}
	if material is ShaderMaterial:
		var shader: Shader = material.shader
		return {"material": "ShaderMaterial", "shader": shader.resource_path if shader != null else null}
	return material.get_class() if material != null else null


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
			if value is Shape3D or value is Shape2D:
				return _describe_shape(value)
			if value is Environment:
				return {"environment": "Environment", "sky": value.sky != null,
					"ambient_energy": value.ambient_light_energy, "fog": value.fog_enabled}
			if value is Material:
				return _describe_material(value)
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
		ur.create_action("AI Bridge: script set %s #%d" % [node.name, _next_id], UndoRedo.MERGE_DISABLE, root)
		ur.add_do_property(node, "script", script)
		ur.add_undo_property(node, "script", node.get_script())
		ur.commit_action()
		EditorInterface.mark_scene_as_unsaved()
		result["attached_to"] = node_path
		result["attached_name"] = node.name
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
	elif mesh.material is ShaderMaterial:
		info["material"] = _describe_material(mesh.material)
	return info


func _describe_shape(shape: Resource) -> Dictionary:
	var info := {"shape": shape.get_class()}
	if shape is BoxShape3D or shape is RectangleShape2D:
		info["size"] = _to_json(shape.size)
	elif shape is SphereShape3D or shape is CircleShape2D:
		info["radius"] = shape.radius
	elif shape is CapsuleShape3D or shape is CylinderShape3D or shape is CapsuleShape2D:
		info["radius"] = shape.radius
		info["height"] = shape.height
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
	_build_target_path = path
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
			"instance":
				_plan_instance(i, op, root, created, deleted, plan, steps, errors)
			_:
				errors.append("Операция %d: в новой сцене допустимы только create, set и instance, получено «%s»" % [i, kind])
	_build_target_path = ""
	if not errors.is_empty():
		for node in created.values():
			node.free()
		root.free()
		var response := _error("Сцена не создана: найдены ошибки")
		response["errors"] = errors
		response["result"] = {"plan": plan, "scene_path": path, "built": false}
		return response

	# Перезапись открытой сцены: несохранённые ручные правки не должны пропасть.
	var backup_path := ""
	var was_open := path in EditorInterface.get_open_scenes()
	if overwrite and was_open:
		if path in _unsaved_open_scenes() and not bool(args.get("force", false)):
			for node in created.values():
				node.free()
			root.free()
			return _error("Сцена «%s» открыта в редакторе с несохранёнными изменениями: сохраните её (scene save) или закройте вкладку, либо повторите с force, тогда текущее состояние уйдёт в резервную копию" % path)
		backup_path = _backup_open_scene(path)

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
	# Если сцена уже открыта во вкладке (не обязательно текущей), её нужно перезагрузить с диска,
	# иначе редактор покажет старое содержимое из памяти и при сохранении затрёт новый файл.
	if overwrite and was_open:
		EditorInterface.reload_scene_from_path(path)
	if bool(args.get("open", true)):
		EditorInterface.open_scene_from_path(path)  # открыть или переключиться на вкладку
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
		"main_scene": main_set, "backup": backup_path, "plan": plan,
		"undo_hint": "Сцена новая, в истории Undo её нет; чтобы убрать, удалите файл %s" % path
			if backup_path == "" else "Прежнее состояние сцены сохранено в %s" % backup_path})
	response["warnings"] = warnings
	response["files"] = [path] if not main_set else [path, "res://project.godot"]
	return response


## project.refresh: подхватить правки файлов, сделанные снаружи (ИИ, git pull), пока окно редактора без фокуса.
## Сканирует файловую систему, перечитывает с диска скрипты узлов открытых сцен и файлы из args.files,
## перезагружает открытые сцены без несохранённых изменений (args.reload_scenes, по умолчанию true).
func _project_refresh(args: Dictionary) -> Dictionary:
	EditorInterface.get_resource_filesystem().scan()
	var reloaded_scripts: Array = []
	var checked := {}
	for scene_root in EditorInterface.get_open_scene_roots():
		if scene_root == null:
			continue
		for node in _all_nodes(scene_root):
			var script = node.get_script()
			if script is Script and not checked.has(script.resource_path):
				checked[script.resource_path] = true
				if _refresh_script(script):
					reloaded_scripts.append(script.resource_path)
	var reloaded_files: Array = []
	var files = args.get("files", [])
	if typeof(files) != TYPE_ARRAY:
		return _error("files должно быть списком путей res://…")
	for f in files:
		var file_path := str(f)
		if not file_path.begins_with("res://") or not FileAccess.file_exists(file_path):
			return _error("файл «%s» не найден" % file_path)
		if not ResourceLoader.has_cached(file_path):
			continue  # не загружен, редактор возьмёт его с диска при первом обращении
		var res := ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if res is Script:
			if _refresh_script(res):
				reloaded_scripts.append(file_path)
		elif res != null:
			reloaded_files.append(file_path)
	var reloaded_scenes: Array = []
	var skipped: Array = []
	if bool(args.get("reload_scenes", true)):
		var unsaved := _unsaved_open_scenes()
		for scene_path in EditorInterface.get_open_scenes():
			if scene_path in unsaved:
				skipped.append(scene_path)
			else:
				EditorInterface.reload_scene_from_path(scene_path)
				reloaded_scenes.append(scene_path)
	return _ok({"scanned": true, "reloaded_scripts": reloaded_scripts, "reloaded_files": reloaded_files,
		"reloaded_scenes": reloaded_scenes, "skipped_unsaved": skipped})


func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count


# ---------------------------------------------------------------------------
# Журнал и задачи ИИ: что делает агент, план, изменённые файлы, ошибки, отмена.
# Каждая команда от enginectl записывается в журнал (.godot/ai_bridge/journal.json);
# task.begin / task.end группируют команды в задачу с заголовком и планом;
# task.undo отменяет задачу по записям (история сцены, файлы, скрипты, настройка).
# Панель «Задачи ИИ» в редакторе показывает всё это и даёт кнопку отмены.
# ---------------------------------------------------------------------------

const JOURNAL_FILE := STATE_DIR + "/journal.json"
const TRASH_DIR := STATE_DIR + "/trash"
const JOURNAL_KEEP := 300   # записей в журнале (старые уходят)
const TASKS_KEEP := 50
## Команды, которые в журнал не пишутся: служебные и чтение журнала.
const SILENT_COMMANDS := ["doctor", "scene.inspect", "task.begin", "task.end", "task.list", "task.undo",
	"journal.get", "journal.clear", "journal.add", "editor.screenshot"]

var _journal: Array = []     # {id, time, command, status, summary, files, errors, task, undo, undone}
var _tasks: Array = []       # {id, title, plan, started, finished, status, note, entries}
var _next_id := 1
var _current_task := 0       # id идущей задачи или 0
var _dock: VBoxContainer = null
var _dock_panel: EditorDock = null  # обёртка панели в редакторе 4.7 (заголовок, место, ключ раскладки)
var _dock_status: Label
var _dock_task: Label
var _dock_plan: RichTextLabel
var _dock_tree: Tree
var _dock_details: RichTextLabel
var _dock_undo_button: Button


# --- Журнал ----------------------------------------------------------------

func _journal_load() -> void:
	_journal = []
	_tasks = []
	if not FileAccess.file_exists(JOURNAL_FILE):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(JOURNAL_FILE))
	if parsed is Dictionary:
		_journal = parsed.get("journal", []) if parsed.get("journal") is Array else []
		_tasks = parsed.get("tasks", []) if parsed.get("tasks") is Array else []
		_next_id = int(parsed.get("next_id", 1))
		_current_task = int(parsed.get("current_task", 0))


func _journal_save() -> void:
	if _journal.size() > JOURNAL_KEEP:
		_journal = _journal.slice(_journal.size() - JOURNAL_KEEP)
	if _tasks.size() > TASKS_KEEP:
		_tasks = _tasks.slice(_tasks.size() - TASKS_KEEP)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STATE_DIR))
	var file := FileAccess.open(JOURNAL_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"journal": _journal, "tasks": _tasks, "next_id": _next_id,
			"current_task": _current_task}, "\t"))
	_dock_refresh()


## Снимок состояния до команды: нужен, чтобы task.undo вернул всё как было.
func _before_command(command: String, args: Dictionary) -> Dictionary:
	match command:
		"script.set":
			var path := str(args.get("path", ""))
			if path.begins_with("res://") and FileAccess.file_exists(path):
				return {"previous": FileAccess.get_file_as_string(path)}
			return {"previous": null}
		"project.main_scene":
			return {"previous": str(ProjectSettings.get_setting("application/run/main_scene", ""))}
	return {}


## Записывает выполненную команду в журнал (и в текущую задачу, если она идёт).
func _record(command: String, args: Dictionary, response: Dictionary, before: Dictionary) -> void:
	if command in SILENT_COMMANDS:
		return
	var result: Dictionary = response.get("result", {}) if response.get("result") is Dictionary else {}
	var entry := {"id": _next_id, "time": Time.get_datetime_string_from_system(false, true), "command": command,
		"status": str(response.get("status", "error")), "summary": _summarize(command, args, result, response),
		"files": response.get("files", []), "errors": response.get("errors", []), "task": _current_task,
		"undo": _undo_info(command, args, result, before), "undone": false}
	_next_id += 1
	_journal.append(entry)
	if _current_task != 0:
		var task := _find_task(_current_task)
		if not task.is_empty():
			task["entries"].append(entry["id"])
			if entry["status"] != "ok":
				task["errors"] = int(task.get("errors", 0)) + 1
	_journal_save()


## Одна строка о команде для панели: что сделано и где.
func _summarize(command: String, args: Dictionary, result: Dictionary, response: Dictionary) -> String:
	var where := str(args.get("path", args.get("scene", "")))
	var text := ""
	match command:
		"scene.apply":
			var count: int = result.get("plan", []).size() if result.get("plan") is Array else 0
			text = "%s: %d операций в %s" % ["план (dry run)" if result.get("dry_run", false) else "изменена сцена",
				count, str(result.get("scene_path", ""))]
		"scene.build":
			var count: int = result.get("plan", []).size() if result.get("plan") is Array else 0
			text = "собрана сцена %s: %d операций" % [str(result.get("scene_path", where)), count]
		"scene.new":
			text = "новая сцена %s" % str(result.get("scene_path", where))
		"scene.open":
			text = "открыта сцена %s" % where
		"scene.save":
			text = "сохранена сцена %s" % str(result.get("scene_path", ""))
		"scene.inspect":
			text = "прочитано дерево сцены (%d узлов)" % int(result.get("node_count", 0))
		"scene.undo":
			text = "отменено: %s" % str(result.get("undone", ""))
		"scene.redo":
			text = "повторено: %s" % str(result.get("redone", ""))
		"script.set":
			text = "%s скрипт %s" % ["создан" if result.get("created", false) else "обновлён", where]
			if result.has("attached_to"):
				text += ", повешен на %s" % str(result["attached_to"])
		"project.main_scene":
			text = "главная сцена: %s" % where
		"project.refresh":
			text = "проект перечитан с диска"
		_:
			text = command
	if response.get("status", "") != "ok":
		var errors: Array = response.get("errors", [])
		text = "ОШИБКА %s: %s" % [command, str(errors[0]) if errors.size() > 0 else "?"]
	return text


## Как отменить эту запись: {"kind": "history"|"script"|"file"|"setting", ...} или {} если нечего.
func _undo_info(command: String, args: Dictionary, result: Dictionary, before: Dictionary) -> Dictionary:
	match command:
		"scene.apply":
			if result.get("applied", false):
				var count: int = result.get("plan", []).size() if result.get("plan") is Array else 0
				return {"kind": "history", "scene": str(result.get("scene_path", "")),
					"action": "%s (%d) #%d" % [UNDO_LABEL, count, _next_id]}
		"script.set":
			if result.has("path"):
				var info := {"kind": "script", "path": str(result["path"]), "previous": before.get("previous")}
				if result.has("attached_to"):
					info["action"] = "AI Bridge: script set %s #%d" % [str(result.get("attached_name", "")), _next_id]
				return info
		"scene.build":
			if result.has("scene_path"):
				return {"kind": "file", "path": str(result["scene_path"]), "backup": str(result.get("backup", ""))}
		"scene.new":
			if result.has("scene_path"):
				return {"kind": "file", "path": str(result["scene_path"]), "backup": ""}
		"project.main_scene":
			if result.has("path") or result.has("main_scene"):
				return {"kind": "setting", "previous": str(before.get("previous", ""))}
	return {}


func _journal_get(args: Dictionary) -> Dictionary:
	var limit := int(args.get("limit", 50))
	var entries := _journal.slice(maxi(_journal.size() - limit, 0)) if limit > 0 else _journal.duplicate()
	return _ok({"entries": entries, "total": _journal.size(), "current_task": _current_task,
		"journal_path": JOURNAL_FILE})


func _journal_clear() -> Dictionary:
	var count := _journal.size()
	_journal = []
	_tasks = []
	_current_task = 0
	_journal_save()
	return _ok({"cleared": count})


## Запись от enginectl о команде, которую выполняет он сам (game run, screenshot, export).
func _journal_add(args: Dictionary) -> Dictionary:
	var command := str(args.get("command", ""))
	if command == "":
		return _error("Поле command пустое")
	var fake := {"status": str(args.get("status", "ok")), "result": {}, "errors": args.get("errors", []),
		"files": args.get("files", [])}
	var entry := {"id": _next_id, "time": Time.get_datetime_string_from_system(false, true), "command": command,
		"status": fake["status"], "summary": str(args.get("summary", command)), "files": fake["files"],
		"errors": fake["errors"], "task": _current_task, "undo": {}, "undone": false}
	_next_id += 1
	_journal.append(entry)
	if _current_task != 0:
		var task := _find_task(_current_task)
		if not task.is_empty():
			task["entries"].append(entry["id"])
			if entry["status"] != "ok":
				task["errors"] = int(task.get("errors", 0)) + 1
	_journal_save()
	return _ok({"id": entry["id"]})


# --- Задачи ----------------------------------------------------------------

func _find_task(id: int) -> Dictionary:
	for task in _tasks:
		if int(task.get("id", 0)) == id:
			return task
	return {}


func _find_entry(id: int) -> Dictionary:
	for entry in _journal:
		if int(entry.get("id", 0)) == id:
			return entry
	return {}


## task.begin: {"title": "Строю комнату", "plan": ["пол", "стены", "лампа"]}. Прежняя незаконченная задача закрывается.
func _task_begin(args: Dictionary) -> Dictionary:
	var title := str(args.get("title", "")).strip_edges()
	if title == "":
		return _error("Поле title пустое: скажите, что делает ИИ, например «Строю комнату»")
	var plan: Array = []
	if args.get("plan") is Array:
		for step in args["plan"]:
			plan.append(str(step))
	elif args.get("plan") is String and str(args["plan"]) != "":
		plan = [str(args["plan"])]
	if _current_task != 0:
		var old := _find_task(_current_task)
		if not old.is_empty() and old.get("finished", "") == "":
			old["finished"] = Time.get_datetime_string_from_system(false, true)
			old["status"] = "прервана"
			old["note"] = "началась новая задача «%s»" % title
	var task := {"id": _next_id, "title": title, "plan": plan, "started": Time.get_datetime_string_from_system(false, true),
		"finished": "", "status": "идёт", "note": "", "entries": [], "errors": 0}
	_next_id += 1
	_tasks.append(task)
	_current_task = task["id"]
	_journal_save()
	_dock_show()
	return _ok({"task_id": task["id"], "title": title, "plan": plan})


## task.end: {"status": "ok"|"error", "note": "..."}; без status берётся по ошибкам в записях.
func _task_end(args: Dictionary) -> Dictionary:
	if _current_task == 0:
		return _error("Сейчас нет идущей задачи (task.begin не вызывался)")
	var task := _find_task(_current_task)
	if task.is_empty():
		_current_task = 0
		_journal_save()
		return _error("Идущая задача не найдена в журнале")
	var status := str(args.get("status", ""))
	if status == "":
		status = "ошибка" if int(task.get("errors", 0)) > 0 else "готово"
	elif status == "ok":
		status = "готово"
	elif status == "error":
		status = "ошибка"
	task["status"] = status
	task["note"] = str(args.get("note", ""))
	task["finished"] = Time.get_datetime_string_from_system(false, true)
	_current_task = 0
	_journal_save()
	return _ok({"task_id": task["id"], "title": task["title"], "status": status, "entries": task["entries"].size(),
		"errors": int(task.get("errors", 0)), "files": _task_files(task)})


func _task_files(task: Dictionary) -> Array:
	var files: Array = []
	for id in task.get("entries", []):
		for f in _find_entry(int(id)).get("files", []):
			if not files.has(f):
				files.append(f)
	return files


func _task_list(args: Dictionary) -> Dictionary:
	var limit := int(args.get("limit", 20))
	var tasks := _tasks.slice(maxi(_tasks.size() - limit, 0)) if limit > 0 else _tasks.duplicate()
	var out: Array = []
	for task in tasks:
		var item: Dictionary = task.duplicate()
		item["files"] = _task_files(task)
		var entries: Array = []
		for id in task.get("entries", []):
			var entry := _find_entry(int(id))
			if not entry.is_empty():
				entries.append({"id": entry["id"], "time": entry["time"], "command": entry["command"],
					"status": entry["status"], "summary": entry["summary"], "undone": entry.get("undone", false)})
		item["entries"] = entries
		out.append(item)
	return _ok({"tasks": out, "current_task": _current_task})


## task.undo: {"id": N} — отменяет записи задачи в обратном порядке. Без id берётся последняя задача.
## История сцены отматывается только если сверху лежит именно действие ИИ (иначе ручные правки
## пострадали бы); файлы переезжают в .godot/ai_bridge/trash, скрипты получают прежний текст.
func _task_undo(args: Dictionary) -> Dictionary:
	var id := int(args.get("id", 0))
	var task: Dictionary
	if id == 0:
		if _tasks.is_empty():
			return _error("Задач ещё не было")
		task = _tasks[_tasks.size() - 1]
	else:
		task = _find_task(id)
		if task.is_empty():
			return _error("Задача %d не найдена" % id)
	var undone: Array = []
	var skipped: Array = []
	var ids: Array = task.get("entries", []).duplicate()
	ids.reverse()
	for entry_id in ids:
		var entry := _find_entry(int(entry_id))
		if entry.is_empty() or entry.get("undone", false):
			continue
		var info: Dictionary = entry.get("undo", {})
		if info.is_empty():
			continue
		var outcome := _undo_entry(info)
		if outcome == "":
			entry["undone"] = true
			undone.append(entry["summary"])
		else:
			skipped.append("%s — %s" % [entry["summary"], outcome])
	if undone.size() > 0:
		task["status"] = "отменена" if skipped.is_empty() else "отменена частично"
		if _current_task == int(task["id"]):
			_current_task = 0
			task["finished"] = Time.get_datetime_string_from_system(false, true)
	EditorInterface.get_resource_filesystem().scan()
	_journal_save()
	if undone.is_empty() and skipped.is_empty():
		return _error("В задаче «%s» нечего отменять" % task["title"])
	return _ok({"task_id": task["id"], "title": task["title"], "undone": undone, "skipped": skipped,
		"trash": TRASH_DIR if undone.size() > 0 else ""})


## Отменяет одну запись. Возвращает "" при успехе или причину, почему нельзя.
func _undo_entry(info: Dictionary) -> String:
	match str(info.get("kind", "")):
		"history":
			return _undo_history(str(info.get("scene", "")), str(info.get("action", "")))
		"script":
			if info.has("action"):
				var err := _undo_history("", str(info["action"]))  # снять скрипт с узла, если это верхнее действие
				if err != "" and not err.begins_with("сверху"):
					return err
			var path := str(info.get("path", ""))
			if info.get("previous") == null:
				return _move_to_trash(path)
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file == null:
				return "не удалось записать %s" % path
			file.store_string(str(info["previous"]))
			file.close()
			var script: Script = load(path)
			if script != null:
				_refresh_script(script)
			return ""
		"file":
			var path := str(info.get("path", ""))
			var err := _move_to_trash(path)
			if err != "":
				return err
			var backup := str(info.get("backup", ""))
			if backup != "" and FileAccess.file_exists(backup):
				var copy_err := DirAccess.copy_absolute(ProjectSettings.globalize_path(backup), ProjectSettings.globalize_path(path))
				if copy_err != OK:
					return "файл убран, но прежняя копия %s не вернулась: %s" % [backup, error_string(copy_err)]
			return ""
		"setting":
			ProjectSettings.set_setting("application/run/main_scene", str(info.get("previous", "")))
			var err := ProjectSettings.save()
			return "" if err == OK else "не удалось сохранить project.godot: %s" % error_string(err)
	return "неизвестный вид отмены"


## Откатывает верхнее действие в истории сцены, если это ожидаемое действие ИИ.
func _undo_history(scene_path: String, action: String) -> String:
	var root: Node = null
	if scene_path == "":
		root = EditorInterface.get_edited_scene_root()
	else:
		for open_root in EditorInterface.get_open_scene_roots():
			if open_root.scene_file_path == scene_path:
				root = open_root
	if root == null:
		return "сцена %s не открыта в редакторе" % scene_path
	var ur := get_undo_redo()
	var history := ur.get_history_undo_redo(ur.get_object_history_id(root))
	if not history.has_undo():
		return "история сцены пуста"
	var top := history.get_current_action_name()
	if top != action:
		return "сверху в истории другое действие («%s»), отмените его сами через Ctrl+Z или оставьте" % top
	history.undo()
	EditorInterface.mark_scene_as_unsaved()
	return ""


## Переносит файл в .godot/ai_bridge/trash/<имя>.<время> (не удаляет насовсем).
func _move_to_trash(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "файла %s уже нет" % path
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TRASH_DIR))
	var stamp := int(Time.get_unix_time_from_system())
	var target := "%s/%s.%d" % [TRASH_DIR, path.get_file(), stamp]
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(target))
	if err != OK:
		return "не удалось убрать %s: %s" % [path, error_string(err)]
	# Редактор кладёт рядом со скриптом файл .uid (его номер в проекте); без скрипта он не нужен.
	if FileAccess.file_exists(path + ".uid"):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".uid"),
			ProjectSettings.globalize_path("%s/%s.uid.%d" % [TRASH_DIR, path.get_file(), stamp]))
	return ""


# --- Снимок окна редактора ---------------------------------------------------

## editor.screenshot: {"path": "/абсолютный/путь.png"} — кадр всего окна редактора (нужен экран, не headless).
func _editor_screenshot(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", ""))
	if path == "":
		return _error("Укажите path для PNG")
	if DisplayServer.get_name() == "headless":
		return _error("Редактор запущен без экрана (headless): снимок окна сделать негде")
	var image := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return _error("Не удалось получить изображение окна редактора")
	var err := image.save_png(path)
	if err != OK:
		return _error("Не удалось сохранить %s: %s" % [path, error_string(err)])
	var response := _ok({"path": path, "width": image.get_width(), "height": image.get_height()})
	response["files"] = [path]
	return response


# --- Панель «Задачи ИИ» ----------------------------------------------------------

func _build_dock() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "Задачи ИИ"
	_dock_status = Label.new()
	_dock_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dock.add_child(_dock_status)
	_dock_task = Label.new()
	_dock_task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dock.add_child(_dock_task)
	_dock_plan = RichTextLabel.new()
	_dock_plan.fit_content = true
	_dock_plan.bbcode_enabled = true
	_dock_plan.custom_minimum_size = Vector2(0, 24)
	_dock_plan.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_dock.add_child(_dock_plan)
	var buttons := HBoxContainer.new()
	_dock_undo_button = Button.new()
	_dock_undo_button.text = "Отменить задачу"
	_dock_undo_button.tooltip_text = "Откатить последнюю задачу ИИ: история сцены, файлы в .godot/ai_bridge/trash, прежний текст скриптов"
	_dock_undo_button.pressed.connect(_on_dock_undo)
	buttons.add_child(_dock_undo_button)
	var refresh := Button.new()
	refresh.text = "Обновить проект"
	refresh.tooltip_text = "Подхватить правки файлов снаружи (то же, что enginectl project refresh)"
	refresh.pressed.connect(func(): _project_refresh({}); _dock_refresh())
	buttons.add_child(refresh)
	var clear := Button.new()
	clear.text = "Очистить"
	clear.tooltip_text = "Очистить журнал (файлы и сцены не трогает)"
	clear.pressed.connect(func(): _journal_clear())
	buttons.add_child(clear)
	_dock.add_child(buttons)
	_dock_tree = Tree.new()
	_dock_tree.columns = 3
	_dock_tree.column_titles_visible = true
	_dock_tree.set_column_title(0, "Время")
	_dock_tree.set_column_title(1, "Команда")
	_dock_tree.set_column_title(2, "Итог")
	_dock_tree.set_column_expand(0, false)
	_dock_tree.set_column_custom_minimum_width(0, 84)
	_dock_tree.set_column_expand(1, false)
	_dock_tree.set_column_custom_minimum_width(1, 110)
	_dock_tree.hide_root = true
	_dock_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dock_tree.item_selected.connect(_on_dock_item_selected)
	_dock.add_child(_dock_tree)
	_dock_details = RichTextLabel.new()
	_dock_details.bbcode_enabled = true
	_dock_details.selection_enabled = true
	_dock_details.custom_minimum_size = Vector2(0, 120)
	_dock_details.text = "Выберите запись, чтобы увидеть файлы и ошибки."
	_dock.add_child(_dock_details)
	# Нижняя правая секция обычно пуста, поэтому панель видна сразу; рядом с Инспектором она пряталась
	# за стрелками прокрутки вкладок (на экране владельца вкладка не влезала). Новый ключ раскладки нужен,
	# потому что редактор запоминает место панели по ключу и иначе вернул бы её на старое место.
	_dock_panel = EditorDock.new()
	_dock_panel.title = "Задачи ИИ"
	_dock_panel.layout_key = "ai_bridge_tasks"
	_dock_panel.default_slot = EditorDock.DOCK_SLOT_RIGHT_BL
	_dock_panel.add_child(_dock)
	add_dock(_dock_panel)
	_dock_refresh()


## Выводит вкладку «Задачи ИИ» вперёд (панель живёт в TabContainer вместе с «Сцена» и «Импорт»).
func _dock_show() -> void:
	if _dock == null:
		return
	if _dock_panel != null:
		_dock_panel.make_visible()
	# Между панелью и TabContainer редактор может вставлять свои обёртки: ищем ближайшую вкладку.
	var node: Node = _dock
	while node != null and not (node.get_parent() is TabContainer):
		node = node.get_parent()
	if node == null:
		print("AI Bridge: не нашёл вкладку панели (родители: %s)" % _dock_ancestry())
		return
	var tabs := node.get_parent() as TabContainer
	var index := tabs.get_tab_idx_from_control(node as Control)
	if index >= 0:
		tabs.current_tab = index


func _dock_ancestry() -> String:
	var names: PackedStringArray = []
	var node: Node = _dock
	while node != null and names.size() < 6:
		names.append(node.get_class())
		node = node.get_parent()
	return " ← ".join(names)


func _dock_refresh() -> void:
	if _dock == null:
		return
	_dock_status.text = "ИИ на связи: порт %d · записей в журнале %d · задач %d" % [_port, _journal.size(), _tasks.size()]
	var task: Dictionary = {}
	if _current_task != 0:
		task = _find_task(_current_task)
	elif not _tasks.is_empty():
		task = _tasks[_tasks.size() - 1]
	if task.is_empty():
		_dock_task.text = "Задач ещё не было. ИИ объявляет задачу командой enginectl task begin."
		_dock_plan.text = ""
		_dock_undo_button.disabled = true
	else:
		_dock_task.text = "%s: %s (%s)" % ["Сейчас" if _current_task != 0 else "Последняя задача", task["title"], task["status"]]
		var lines: PackedStringArray = []
		var plan: Array = task.get("plan", [])
		for i in plan.size():
			lines.append("%d. %s" % [i + 1, str(plan[i])])
		if str(task.get("note", "")) != "":
			lines.append("[i]%s[/i]" % str(task["note"]))
		_dock_plan.text = "\n".join(lines)
		_dock_undo_button.disabled = task["status"] in ["отменена"] or task.get("entries", []).is_empty()
	_dock_tree.clear()
	var root := _dock_tree.create_item()
	var shown := 0
	var index := _tasks.size() - 1
	var loose: Array = []  # записи вне задач
	for entry in _journal:
		if int(entry.get("task", 0)) == 0:
			loose.append(entry)
	var groups: Array = []
	while index >= 0 and groups.size() < 15:
		groups.append(_tasks[index])
		index -= 1
	if not loose.is_empty():
		groups.append({"title": "Вне задач", "status": "", "entries": loose.map(func(e): return e["id"]), "loose": true})
	for group in groups:
		var item := _dock_tree.create_item(root)
		item.set_text(0, str(group.get("started", "")).substr(11, 5))
		item.set_text(1, "задача" if not group.get("loose", false) else "")
		item.set_text(2, "%s%s" % [group["title"], " — " + str(group["status"]) if str(group.get("status", "")) != "" else ""])
		item.set_metadata(0, {"task": group.get("id", 0)})
		item.collapsed = shown > 0
		var ids: Array = group.get("entries", []).duplicate()
		ids.reverse()
		for id in ids:
			var entry := _find_entry(int(id))
			if entry.is_empty():
				continue
			var child := _dock_tree.create_item(item)
			child.set_text(0, str(entry["time"]).substr(11, 5))
			child.set_text(1, str(entry["command"]))
			var mark := "✓ " if entry["status"] == "ok" else "✗ "
			if entry.get("undone", false):
				mark = "↶ "
			child.set_text(2, mark + str(entry["summary"]))
			child.set_metadata(0, {"entry": entry["id"]})
			if entry["status"] != "ok":
				child.set_custom_color(2, Color(1.0, 0.45, 0.4))
			elif entry.get("undone", false):
				child.set_custom_color(2, Color(0.6, 0.6, 0.6))
		shown += 1


func _on_dock_item_selected() -> void:
	var item := _dock_tree.get_selected()
	if item == null:
		return
	var meta = item.get_metadata(0)
	if not (meta is Dictionary):
		return
	if meta.has("entry"):
		var entry := _find_entry(int(meta["entry"]))
		if entry.is_empty():
			return
		var lines: PackedStringArray = ["[b]%s[/b] · %s · %s" % [entry["command"], entry["time"], entry["status"]], str(entry["summary"])]
		if not entry.get("files", []).is_empty():
			lines.append("Файлы: " + ", ".join(PackedStringArray(entry["files"].map(func(f): return str(f)))))
		for e in entry.get("errors", []):
			lines.append("[color=salmon]%s[/color]" % str(e))
		if entry.get("undone", false):
			lines.append("[i]отменено[/i]")
		elif not entry.get("undo", {}).is_empty():
			lines.append("[i]можно отменить кнопкой «Отменить задачу»[/i]")
		_dock_details.text = "\n".join(lines)
	elif meta.has("task"):
		var task := _find_task(int(meta["task"]))
		if task.is_empty():
			return
		var lines: PackedStringArray = ["[b]%s[/b] · %s → %s · %s" % [task["title"], task["started"], task["finished"], task["status"]]]
		var files := _task_files(task)
		if not files.is_empty():
			lines.append("Файлы: " + ", ".join(PackedStringArray(files.map(func(f): return str(f)))))
		if str(task.get("note", "")) != "":
			lines.append(str(task["note"]))
		_dock_details.text = "\n".join(lines)


func _on_dock_undo() -> void:
	var response := _task_undo({})
	var result: Dictionary = response.get("result", {})
	if response.get("status", "") != "ok":
		_dock_details.text = "[color=salmon]%s[/color]" % str(response.get("errors", [""])[0])
		return
	var lines: PackedStringArray = ["Отменено (%d):" % result["undone"].size()]
	for u in result["undone"]:
		lines.append("↶ " + str(u))
	for s in result["skipped"]:
		lines.append("[color=salmon]не отменено: %s[/color]" % str(s))
	if result["undone"].size() > 0:
		lines.append("[i]Убранные файлы лежат в %s[/i]" % TRASH_DIR)
	_dock_details.text = "\n".join(lines)
