@tool
extends EditorPlugin
## «Ухо и рука»: слушает локальный порт и выполняет команды от enginectl.
## Протокол: одна строка JSON на запрос и одна строка JSON на ответ.
## Запрос: {"token": "...", "command": "doctor", "args": {}}
## Ответ:  {"status": "ok"|"error", "result": {...}, "errors": [], "warnings": [], "files": []}

const PLUGIN_VERSION := "0.1.0"
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
		var unknown:
			return _error("Неизвестная команда: %s" % unknown)


func _doctor() -> Dictionary:
	var info := Engine.get_version_info()
	return {
		"message": "Godot на связи",
		"godot_version": info.string,
		"plugin_version": PLUGIN_VERSION,
		"project_name": ProjectSettings.get_setting("application/config/name", ""),
		"project_path": ProjectSettings.globalize_path("res://"),
		"edited_scene": _edited_scene_path(),
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
	file.store_string(JSON.stringify({"host": HOST, "port": _port, "token": _token, "pid": OS.get_process_id()}, "\t"))
