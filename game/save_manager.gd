extends Node

## Сохранение и загрузка игры. F5 — сохранить, F9 — загрузить; то же делают кнопки меню паузы (Esc).
## Сохраняются узлы группы "persist": у каждого есть save_state() -> Dictionary и load_state(Dictionary)
## (персонаж, машина, дверь, кнопка, предмет); ключ записи — путь узла от корня сцены.
## Файл user://save.json (на Windows это %APPDATA%\Godot\app_userdata\GodotAI\save.json).
## Запись безопасная: сначала во временный файл, он читается обратно и проверяется, прежняя копия
## переименовывается в save.bak.json, и только потом временный файл становится save.json. Поэтому сбой
## на записи или повреждённый файл не уничтожают последнее рабочее сохранение, а повреждённый файл при
## загрузке даёт строку в выводе и игра продолжается (проверка №6 плана): берётся save.bak.json, если есть.
## Самопроверка: game run --test save=save:0.5,corrupt:0.3,load:0.5 (фазы save, load, corrupt, wait;
## число — секунды паузы после фазы). После каждой операции в выводе строка «Сохранено: …» / «Загружено: …».

const SAVE_PATH := "user://save.json"
const BACKUP_PATH := "user://save.bak.json"
const TEMP_PATH := "user://save.tmp.json"
const FORMAT := 1  # номер формата файла; файл с другим номером не загружается

var _phases: Array = []
var _phase_index := 0
var _phase_time := 0.0


func _ready() -> void:
	add_to_group("save_manager")
	var prefix := "--test-save="
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			for part in arg.trim_prefix(prefix).split(",", false):
				var pair := part.strip_edges().split(":")
				var seconds := float(pair[1]) if pair.size() >= 2 and pair[1].is_valid_float() else 0.0
				_phases.append({"name": pair[0].strip_edges(), "seconds": seconds})


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5:
			save_game()
		elif event.keycode == KEY_F9:
			load_game()


func _process(delta: float) -> void:
	if _phase_index >= _phases.size():
		return
	var phase: Dictionary = _phases[_phase_index]
	if _phase_time == 0.0:
		match phase["name"]:
			"save":
				save_game()
			"load":
				load_game()
			"corrupt":
				corrupt_save_for_test()
	_phase_time += delta
	if _phase_time >= phase["seconds"]:
		_phase_index += 1
		_phase_time = 0.0


## Записывает состояние всех узлов группы persist. Возвращает true, если файл на диске обновлён.
func save_game() -> bool:
	var root := get_tree().current_scene
	if root == null:
		print("Сохранение не удалось: нет текущей сцены")
		return false
	var nodes := {}
	for node in get_tree().get_nodes_in_group("persist"):
		if node.has_method("save_state"):
			nodes[str(root.get_path_to(node))] = node.save_state()
	var data := {"format": FORMAT, "scene": root.scene_file_path,
		"saved_at": Time.get_datetime_string_from_system(), "nodes": nodes}
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		print("Сохранение не удалось: не могу записать %s (%s)" % [TEMP_PATH, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	var check := _read_save(TEMP_PATH)  # прочитать обратно: на диск легло то, что читается
	if check.has("error"):
		print("Сохранение не удалось: записанный файл не читается (%s), старое сохранение не тронуто" % check["error"])
		DirAccess.remove_absolute(TEMP_PATH)
		return false
	var dir := DirAccess.open("user://")
	if dir.file_exists(SAVE_PATH):
		if dir.file_exists(BACKUP_PATH):
			dir.remove(BACKUP_PATH)
		dir.rename(SAVE_PATH, BACKUP_PATH)  # прежняя копия остаётся рядом
	var err := dir.rename(TEMP_PATH, SAVE_PATH)
	if err != OK:
		print("Сохранение не удалось: не могу заменить %s (%s)" % [SAVE_PATH, error_string(err)])
		return false
	print("Сохранено: %d объектов в %s" % [nodes.size(), ProjectSettings.globalize_path(SAVE_PATH)])
	return true


## Восстанавливает состояние из save.json; если он повреждён, из save.bak.json. Игра при этом не падает.
func load_game() -> bool:
	var source := SAVE_PATH
	var result := _read_save(SAVE_PATH)
	if result.has("error"):
		print("Загрузка: файл %s не годится (%s), игра продолжается" % [SAVE_PATH, result["error"]])
		if not FileAccess.file_exists(BACKUP_PATH):
			print("Загрузка: предыдущей копии %s нет, загружать нечего" % BACKUP_PATH)
			return false
		source = BACKUP_PATH
		result = _read_save(BACKUP_PATH)
		if result.has("error"):
			print("Загрузка: предыдущая копия %s тоже не годится (%s)" % [BACKUP_PATH, result["error"]])
			return false
		print("Загрузка: беру предыдущую копию %s" % BACKUP_PATH)
	var data: Dictionary = result["data"]
	var root := get_tree().current_scene
	var scene := str(data.get("scene", ""))
	if root == null or (scene != "" and scene != root.scene_file_path):
		print("Загрузка: сохранение сделано в другой сцене (%s), сюда не подходит" % scene)
		return false
	var nodes: Dictionary = data["nodes"]
	var restored := 0
	var without := 0
	for node in get_tree().get_nodes_in_group("persist"):
		var key := str(root.get_path_to(node))
		if node.has_method("load_state") and nodes.get(key) is Dictionary:
			node.load_state(nodes[key])
			restored += 1
		else:
			without += 1
	print("Загружено: %d объектов из %s%s" % [restored, source,
		(", без записи в файле: %d" % without) if without > 0 else ""])
	return true


## Только для самопроверки: портит файл сохранения, чтобы проверить, что игра это переживает.
func corrupt_save_for_test() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("{\"format\": 1, \"nodes\": [[[ обрыв файла")
		file.close()
	print("Проверка: файл сохранения испорчен нарочно")


## Читает и проверяет файл. Возвращает {"data": Dictionary} или {"error": "почему"}.
func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "файла нет"}
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges() == "":
		return {"error": "файл пуст или не читается"}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"error": "строка %d: %s" % [json.get_error_line(), json.get_error_message()]}
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("nodes")) != TYPE_DICTIONARY:
		return {"error": "неожиданная структура, нет списка nodes"}
	if int(data.get("format", 0)) != FORMAT:
		return {"error": "формат %s, а игра ждёт %d" % [data.get("format"), FORMAT]}
	return {"data": data}
