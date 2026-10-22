extends RefCounted

## Сохранение «Кладбища»: один файл user://graveyard_save.json со всем, что должно пережить закрытие игры:
## рекорды и победы по картам, выбранный герой, души (валюта базы), купленные постоянные прокачки,
## открытые способности и их слоты, уровень забора. Старый файл graveyard_best.txt (рекорд одной карты)
## подхватывается как рекорд «Старого погоста». Всё статическое: Save.data читается один раз на процесс,
## после каждого изменения зовут Save.store().

const PATH := "user://graveyard_save.json"
const OLD_BEST := "user://graveyard_best.txt"
const DEFAULT := {
	"records": {},  # id карты → лучший счёт
	"won": {},  # id карты → true, если хоть раз выжил
	"skin": "adventurer",
	"souls": 0,
	"upgrades": {},  # id постоянной прокачки → уровень
	"abilities": ["nova"],  # id открытых способностей (Святая волна есть у всех с самого начала)
	"slots": ["nova"],  # id способностей в четырёх слотах
	"fence": 0,
	"unlocked": ["old"],  # id открытых карт
	"stats": {"nights": 0, "wins": 0, "kills": 0, "souls_total": 0},  # летопись
	"tutorial": {},  # пройденные шаги обучения: base, night, after → true
}

static var data: Dictionary = {}
static var _loaded := false


static func load_data() -> Dictionary:
	if _loaded:
		return data
	_loaded = true
	data = DEFAULT.duplicate(true)
	if FileAccess.file_exists(PATH):
		var file := FileAccess.open(PATH, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				for key in parsed:
					data[key] = parsed[key]
	elif FileAccess.file_exists(OLD_BEST):
		var file := FileAccess.open(OLD_BEST, FileAccess.READ)
		if file != null:
			var best := int(file.get_as_text().strip_edges())
			if best > 0:
				data["records"]["old"] = best
	return data


static func store() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))


static func record(map_id: String) -> int:
	return int(load_data()["records"].get(map_id, 0))


## Запоминает счёт, если он лучше прежнего; возвращает true при новом рекорде.
static func set_record(map_id: String, score: int, won: bool) -> bool:
	load_data()
	var best := false
	if score > record(map_id):
		data["records"][map_id] = score
		best = true
	if won:
		data["won"][map_id] = true
	store()
	return best


static func is_won(map_id: String) -> bool:
	return bool(load_data()["won"].get(map_id, false))


static func souls() -> int:
	return int(load_data()["souls"])


static func add_souls(amount: int) -> void:
	load_data()
	data["souls"] = int(data["souls"]) + amount
	if amount > 0:
		data["stats"]["souls_total"] = int(data["stats"].get("souls_total", 0)) + amount
	store()


## Списать души, если хватает; возвращает true при успехе.
static func spend(amount: int) -> bool:
	load_data()
	if int(data["souls"]) < amount:
		return false
	data["souls"] = int(data["souls"]) - amount
	store()
	return true


static func upgrade_level(id: String) -> int:
	return int(load_data()["upgrades"].get(id, 0))


static func set_upgrade_level(id: String, level: int) -> void:
	load_data()["upgrades"][id] = level
	store()


static func fence_level() -> int:
	return int(load_data()["fence"])


static func set_fence_level(level: int) -> void:
	load_data()["fence"] = level
	store()


static func is_unlocked(map_id: String) -> bool:
	return load_data()["unlocked"].has(map_id)


static func unlock(map_id: String) -> void:
	load_data()
	if not data["unlocked"].has(map_id):
		data["unlocked"].append(map_id)
	store()


static func abilities() -> Array:
	return load_data()["abilities"]


static func slots() -> Array:
	return load_data()["slots"]


static func unlock_ability(id: String) -> void:
	load_data()
	if not data["abilities"].has(id):
		data["abilities"].append(id)
	store()


static func set_slots(value: Array) -> void:
	load_data()["slots"] = value.duplicate()
	store()


static func add_stat(key: String, amount: int) -> void:
	load_data()
	data["stats"][key] = int(data["stats"].get(key, 0)) + amount
	store()


static func stat(key: String) -> int:
	return int(load_data()["stats"].get(key, 0))


static func tutorial_done(key: String) -> bool:
	return bool(load_data().get("tutorial", {}).get(key, false))


static func set_tutorial_done(key: String) -> void:
	load_data()
	if not data.has("tutorial"):
		data["tutorial"] = {}
	data["tutorial"][key] = true
	store()


static func skin() -> String:
	return str(load_data()["skin"])


static func set_skin(value: String) -> void:
	load_data()["skin"] = value
	store()
