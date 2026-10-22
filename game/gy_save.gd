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
	"abilities": [],  # id открытых способностей
	"slots": [],  # id способностей в четырёх слотах
	"fence": 0,
	"unlocked": ["old"],  # id открытых карт
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


static func skin() -> String:
	return str(load_data()["skin"])


static func set_skin(value: String) -> void:
	load_data()["skin"] = value
	store()
