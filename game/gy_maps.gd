extends RefCounted

## Карты «Кладбища»: десять погостов, у каждого своё небо, свет, туман, земля, украшения, погода,
## опасные лужи, набор врагов и босс. Всё описано словарями: gy_world.gd строит мир по описанию,
## gy_game.gd берёт отсюда длину раунда, частоту волн и список врагов. Поля, которых нет у карты,
## берутся из DEFAULT (это обычный «Старый погост»), поэтому карту можно описать парой строк.
##
## Цвета — строки «#rrggbb». Половина стороны арены — arena (x и z), по краю ограда.
## hazards: лужи, на которых существа замедляются: ice — лёд (твари скользят и буксуют, герой
## чуть скользит), mud — грязь (вязнут все, кроме болотников и призраков).

const DEFAULT := {
	"id": "old",
	"title": "Старый погост",
	"subtitle": "Ночь, туман, фонари. Здесь всё началось.",
	"round": 180.0,
	"arena": [34.0, 34.0],
	"rate": 1.0,  # множитель частоты появления врагов
	"tough": 1.0,  # множитель здоровья врагов
	"xp_mult": 1.0,
	"pumpkin_chance": 0.07,  # шанс тыквы (лечение) с обычного врага
	"boss": "vampire",
	"sky": {"top": "#0b1230", "horizon": "#2a3a66", "ground": "#141c30", "moon": "#f4f0e0", "moon_dir": [0.45, 0.55, -0.35],
		"moon_size": 0.035, "stars": 1.0, "haze": "#2a3a66"},
	"env": {"bg": "#1c2740", "ambient": "#8088a8", "ambient_energy": 1.25, "fog": "#3b4a6e", "fog_density": 0.012,
		"moon": "#dde2ff", "moon_energy": 1.35, "moon_angle": [-55.0, 35.0], "exposure": 1.2, "saturation": 1.05,
		"volumetric": 0.0, "glow": 0.8},
	"ground": {"grass_dark": "#24401f", "grass_light": "#42662b", "dirt": "#4d3a29", "path": "#785f40", "path_width": 1.2,
		"snow": 0.0, "wet": 0.0, "cobble": 0.0, "flowers": 0.975, "paths": 1},
	"decor": {"graves": 72, "grave_props": 22, "pines": 18, "rocks": 16, "furniture": 8, "pumpkins": 16,
		"crypts": 4, "houses": 0, "cars": 0, "obelisks": 0, "outer_pines": 40},
	"lights": {"fires": 6, "lanterns": 6, "posts": 4, "range": 11.0, "energy": 1.0, "hero_lantern": false},
	"weather": {"kind": "leaves", "fireflies": true, "wisps": false},
	"hazards": {"ice": 0, "mud": 0},
	"enemies": {
		"zombie": {"weight": 3.0, "from": 0.0},
		"skeleton": {"weight": 2.0, "from": 30.0},
		"ghost": {"weight": 2.0, "from": 60.0},
		"ghoul": {"weight": 0.7, "from": 45.0},
		"knight": {"weight": 0.7, "from": 75.0},
		"wraith": {"weight": 0.45, "from": 100.0},
	},
}

## Форпост между боями (gy_base.gd ставит на нём здания, стражников и нападающих): тёплый свет, деревянный
## забор с воротами на севере, места под здания заняты заранее (reserved: x, z, радиус).
const BASE := {
	"id": "base",
	"title": "Форпост",
	"subtitle": "Дом сторожа между ночами.",
	"round": 0.0,
	"arena": [16.0, 11.0],
	"sky": {"top": "#0a1028", "horizon": "#2c3454", "ground": "#141a2c", "moon": "#f8f0d8", "moon_size": 0.04, "stars": 1.1, "haze": "#2c3454"},
	"env": {"bg": "#1a2238", "ambient": "#8c8aa0", "ambient_energy": 1.1, "fog": "#343e5c", "fog_density": 0.012,
		"moon": "#e4e0ff", "moon_energy": 1.1, "exposure": 1.15, "saturation": 1.08},
	"ground": {"grass_dark": "#2a4420", "grass_light": "#466a2c", "dirt": "#4d3a29", "path": "#7a6040", "path_width": 1.1, "paths": 1},
	"decor": {"graves": 4, "grave_props": 2, "pines": 0, "rocks": 3, "furniture": 4, "pumpkins": 10, "crypts": 0, "obelisks": 0,
		"outer_pines": 90, "outer_rocks": 12, "fence": "fence", "gate": true,
		"reserved": [[-9.0, -2.0, 4.5], [9.0, -2.5, 4.5], [0.0, 2.5, 3.0], [0.0, 7.5, 4.5], [0.0, -9.5, 4.0], [-5.0, -9.0, 2.5], [5.0, -9.0, 2.5]]},
	"lights": {"fires": 0, "lanterns": 5, "posts": 0, "range": 11.0, "energy": 1.0, "hero_lantern": false},
	"weather": {"kind": "leaves", "fireflies": true, "wisps": false},
	"hazards": {"ice": 0, "mud": 0},
	"enemies": {},
}

## Сколько душ стоит открыть карту (по порядку); первая открыта всегда.
const UNLOCK_COST := [0, 60, 120, 200, 300, 420, 560, 720, 900, 1200]

const MAPS := [
	{"id": "old"},
	{
		"id": "swamp",
		"title": "Туманные болота",
		"subtitle": "Дождь, густой туман и грязь, в которой вязнут все. Болотники грязи не боятся.",
		"round": 200.0,
		"arena": [32.0, 32.0],
		"rate": 1.1,
		"tough": 1.1,
		"boss": "bog_king",
		"sky": {"top": "#071410", "horizon": "#1c3a30", "ground": "#0a1a14", "moon": "#c8e8c0", "stars": 0.4, "haze": "#1c3a30"},
		"env": {"bg": "#15261f", "ambient": "#6f9a84", "ambient_energy": 1.0, "fog": "#2f5445", "fog_density": 0.03,
			"moon": "#b8d8c0", "moon_energy": 0.9, "exposure": 1.1, "saturation": 0.95, "volumetric": 0.04},
		"ground": {"grass_dark": "#1a2e18", "grass_light": "#2f4a22", "dirt": "#2d2a1c", "path": "#4a4630", "wet": 0.7, "flowers": 1.0},
		"decor": {"graves": 30, "grave_props": 14, "pines": 22, "rocks": 30, "furniture": 4, "pumpkins": 4, "crypts": 2, "outer_pines": 50},
		"lights": {"fires": 3, "lanterns": 8, "posts": 2, "range": 10.0, "energy": 1.1},
		"weather": {"kind": "rain", "fireflies": true, "wisps": true},
		"hazards": {"ice": 0, "mud": 16},
		"enemies": {
			"zombie": {"weight": 2.5, "from": 0.0},
			"bog": {"weight": 2.0, "from": 15.0},
			"ghost": {"weight": 2.0, "from": 40.0},
			"ghoul": {"weight": 0.8, "from": 50.0},
			"wraith": {"weight": 0.4, "from": 110.0},
		},
	},
	{
		"id": "winter",
		"title": "Зимний погост",
		"subtitle": "Снег и ледяные лужи: твари на льду скользят и буксуют. Мерзляки льда не замечают.",
		"round": 210.0,
		"rate": 1.15,
		"tough": 1.15,
		"boss": "frost_giant",
		"sky": {"top": "#101a3a", "horizon": "#5a6f9a", "ground": "#2a3350", "moon": "#ffffff", "moon_size": 0.04, "stars": 1.3, "haze": "#6a7fae"},
		"env": {"bg": "#1c2742", "ambient": "#7a8ab4", "ambient_energy": 0.45, "fog": "#3e4c70", "fog_density": 0.014,
			"moon": "#d4def8", "moon_energy": 0.7, "exposure": 1.0, "saturation": 0.9},
		"ground": {"grass_dark": "#3e4a5c", "grass_light": "#56647a", "dirt": "#3a424e", "path": "#5c6878", "snow": 1.0, "flowers": 1.0},
		"decor": {"graves": 60, "grave_props": 14, "pines": 34, "rocks": 12, "furniture": 6, "pumpkins": 0, "crypts": 4, "outer_pines": 60},
		"lights": {"fires": 6, "lanterns": 8, "posts": 4, "range": 11.0, "energy": 1.1},
		"weather": {"kind": "snow", "fireflies": false, "wisps": false},
		"hazards": {"ice": 16, "mud": 0},
		"enemies": {
			"frost": {"weight": 2.5, "from": 0.0},
			"skeleton": {"weight": 2.0, "from": 20.0},
			"ghost": {"weight": 1.5, "from": 50.0},
			"knight": {"weight": 0.8, "from": 60.0},
			"wraith": {"weight": 0.4, "from": 120.0},
		},
	},
	{
		"id": "village",
		"title": "Заброшенная деревня",
		"subtitle": "Пустые дома и узкие улочки. Жители не ушли: они одержимы и очень быстры.",
		"round": 210.0,
		"arena": [36.0, 36.0],
		"rate": 1.2,
		"tough": 1.2,
		"boss": "elder",
		"sky": {"top": "#0d1226", "horizon": "#3c3a52", "ground": "#1a1a26", "moon": "#f0e2c0", "stars": 0.9, "haze": "#3c3a52"},
		"env": {"bg": "#232033", "ambient": "#8c8498", "ambient_energy": 1.15, "fog": "#3e3a52", "fog_density": 0.014,
			"moon": "#e6dcc8", "moon_energy": 1.2, "exposure": 1.15, "saturation": 1.0},
		"ground": {"grass_dark": "#26321e", "grass_light": "#3e4e26", "dirt": "#3e3424", "path": "#5a544a", "cobble": 1.0, "path_width": 1.6, "paths": 2},
		"decor": {"graves": 10, "grave_props": 8, "pines": 8, "rocks": 10, "furniture": 14, "pumpkins": 10, "crypts": 1, "houses": 14, "cars": 2, "outer_pines": 36, "fence": "fence"},
		"lights": {"fires": 4, "lanterns": 6, "posts": 8, "range": 12.0, "energy": 1.2},
		"weather": {"kind": "leaves", "fireflies": false, "wisps": true},
		"enemies": {
			"villager": {"weight": 3.0, "from": 0.0},
			"zombie": {"weight": 2.0, "from": 20.0},
			"skeleton": {"weight": 1.5, "from": 45.0},
			"ghost": {"weight": 1.2, "from": 70.0},
			"knight": {"weight": 0.7, "from": 90.0},
		},
	},
	{
		"id": "forest",
		"title": "Чёрный лес",
		"subtitle": "Кромешная тьма. У фонарей светло, вдали ничего не видно. Фонарь в руке героя.",
		"round": 220.0,
		"arena": [34.0, 34.0],
		"rate": 1.25,
		"tough": 1.25,
		"boss": "ghost_lord",
		"sky": {"top": "#020409", "horizon": "#0c1220", "ground": "#05070c", "moon": "#9ab0d0", "moon_size": 0.025, "stars": 1.5, "haze": "#0c1220"},
		"env": {"bg": "#070b14", "ambient": "#3a4a6a", "ambient_energy": 0.4, "fog": "#0a1020", "fog_density": 0.03,
			"moon": "#8aa0c8", "moon_energy": 0.35, "exposure": 1.1, "saturation": 0.95, "volumetric": 0.05, "glow": 1.1},
		"ground": {"grass_dark": "#1a2a18", "grass_light": "#2b4222", "dirt": "#3a2d20", "path": "#5c4a34", "flowers": 0.99},
		"decor": {"graves": 36, "grave_props": 12, "pines": 60, "rocks": 24, "furniture": 4, "pumpkins": 6, "crypts": 2, "outer_pines": 90},
		"lights": {"fires": 7, "lanterns": 10, "posts": 6, "range": 13.0, "energy": 2.2, "hero_lantern": true},
		"weather": {"kind": "leaves", "fireflies": true, "wisps": true},
		"enemies": {
			"ghost": {"weight": 3.0, "from": 0.0},
			"zombie": {"weight": 2.0, "from": 0.0},
			"skeleton": {"weight": 1.5, "from": 40.0},
			"wraith": {"weight": 0.8, "from": 60.0},
			"ghoul": {"weight": 0.6, "from": 90.0},
		},
	},
	{
		"id": "bloodmoon",
		"title": "Кровавая луна",
		"subtitle": "Красное небо, нечисти вдвое больше, но и опыт за каждого двойной.",
		"round": 220.0,
		"rate": 1.6,
		"tough": 1.2,
		"xp_mult": 2.0,
		"boss": "vampire",
		"sky": {"top": "#1a0408", "horizon": "#5a1420", "ground": "#1a0a0c", "moon": "#ff5a4a", "moon_size": 0.05, "stars": 0.5, "haze": "#5a1420"},
		"env": {"bg": "#2a0c12", "ambient": "#6a5058", "ambient_energy": 0.8, "fog": "#4a141c", "fog_density": 0.016,
			"moon": "#e09080", "moon_energy": 0.8, "exposure": 1.05, "saturation": 0.95, "glow": 1.0},
		"ground": {"grass_dark": "#201618", "grass_light": "#36262a", "dirt": "#281a16", "path": "#4e3a34", "flowers": 0.985},
		"decor": {"graves": 80, "grave_props": 24, "pines": 14, "rocks": 14, "furniture": 8, "pumpkins": 10, "crypts": 4, "obelisks": 8, "outer_pines": 40},
		"lights": {"fires": 8, "lanterns": 6, "posts": 4, "range": 11.0, "energy": 1.2},
		"weather": {"kind": "ash", "fireflies": false, "wisps": true},
		"enemies": {
			"zombie": {"weight": 3.0, "from": 0.0},
			"skeleton": {"weight": 2.5, "from": 15.0},
			"ghost": {"weight": 2.0, "from": 40.0},
			"ghoul": {"weight": 1.0, "from": 30.0},
			"knight": {"weight": 1.0, "from": 60.0},
			"wraith": {"weight": 0.6, "from": 90.0},
		},
	},
	{
		"id": "pumpkin",
		"title": "Тыквенное поле",
		"subtitle": "Тыквы повсюду и лечат втрое чаще. Зато здесь бродят горящие мертвецы.",
		"round": 220.0,
		"arena": [36.0, 30.0],
		"rate": 1.3,
		"tough": 1.3,
		"pumpkin_chance": 0.2,
		"boss": "pumpkin_king",
		"sky": {"top": "#120c22", "horizon": "#5a3a1a", "ground": "#1c1410", "moon": "#ffd080", "moon_size": 0.045, "stars": 0.9, "haze": "#5a3a1a"},
		"env": {"bg": "#22180f", "ambient": "#8c8070", "ambient_energy": 1.0, "fog": "#3e2c1c", "fog_density": 0.013,
			"moon": "#ffd8a0", "moon_energy": 1.0, "exposure": 1.1, "saturation": 1.1},
		"ground": {"grass_dark": "#2c3418", "grass_light": "#4e5a22", "dirt": "#4a3220", "path": "#6a5236", "flowers": 0.97},
		"decor": {"graves": 20, "grave_props": 10, "pines": 10, "rocks": 8, "furniture": 6, "pumpkins": 90, "crypts": 1, "scarecrows": 10, "outer_pines": 30},
		"lights": {"fires": 8, "lanterns": 8, "posts": 2, "range": 11.0, "energy": 1.1},
		"weather": {"kind": "leaves", "fireflies": true, "wisps": false},
		"enemies": {
			"zombie": {"weight": 2.0, "from": 0.0},
			"skeleton": {"weight": 2.0, "from": 20.0},
			"burning": {"weight": 1.6, "from": 30.0},
			"ghost": {"weight": 1.2, "from": 60.0},
			"ghoul": {"weight": 0.8, "from": 70.0},
		},
	},
	{
		"id": "road",
		"title": "Дорога мёртвых",
		"subtitle": "Длинное шоссе, разбитые машины и пепел с неба. Орда идёт с обеих сторон.",
		"round": 240.0,
		"arena": [54.0, 18.0],
		"rate": 1.4,
		"tough": 1.4,
		"boss": "butcher",
		"sky": {"top": "#0c0c10", "horizon": "#3a3634", "ground": "#141212", "moon": "#d8d0c0", "stars": 0.6, "haze": "#3a3634"},
		"env": {"bg": "#2a2624", "ambient": "#8a8480", "ambient_energy": 1.1, "fog": "#3a3432", "fog_density": 0.016,
			"moon": "#d0c8c0", "moon_energy": 1.1, "exposure": 1.15, "saturation": 0.8},
		"ground": {"grass_dark": "#2c2e24", "grass_light": "#484a34", "dirt": "#3c3630", "path": "#2e2e30", "path_width": 2.6, "flowers": 1.0, "paths": 3},
		"decor": {"graves": 10, "grave_props": 10, "pines": 12, "rocks": 20, "furniture": 6, "pumpkins": 4, "crypts": 0, "cars": 12, "outer_pines": 40},
		"lights": {"fires": 8, "lanterns": 4, "posts": 10, "range": 12.0, "energy": 1.2},
		"weather": {"kind": "ash", "fireflies": false, "wisps": true},
		"enemies": {
			"zombie": {"weight": 3.5, "from": 0.0},
			"skeleton": {"weight": 1.5, "from": 30.0},
			"ghoul": {"weight": 1.2, "from": 25.0},
			"knight": {"weight": 1.0, "from": 70.0},
			"ghost": {"weight": 1.0, "from": 90.0},
		},
	},
	{
		"id": "quarry",
		"title": "Костяной карьер",
		"subtitle": "Бледный камень и скалы-лабиринт. Царство скелетов и их рыцарей.",
		"round": 240.0,
		"arena": [36.0, 36.0],
		"rate": 1.5,
		"tough": 1.5,
		"boss": "lich",
		"sky": {"top": "#0a0e1a", "horizon": "#4a4a52", "ground": "#1c1c22", "moon": "#f0f0f0", "stars": 1.1, "haze": "#4a4a52"},
		"env": {"bg": "#202026", "ambient": "#8a8a94", "ambient_energy": 0.7, "fog": "#3a3a44", "fog_density": 0.013,
			"moon": "#e8e8f0", "moon_energy": 1.0, "exposure": 1.05, "saturation": 0.75},
		"ground": {"grass_dark": "#3c3830", "grass_light": "#524c42", "dirt": "#34302a", "path": "#625c50", "flowers": 1.0, "paths": 2},
		"decor": {"graves": 30, "grave_props": 20, "pines": 4, "rocks": 90, "furniture": 4, "pumpkins": 0, "crypts": 2, "obelisks": 12, "outer_pines": 10, "outer_rocks": 50},
		"lights": {"fires": 8, "lanterns": 6, "posts": 4, "range": 11.0, "energy": 1.1},
		"weather": {"kind": "none", "fireflies": false, "wisps": true},
		"enemies": {
			"skeleton": {"weight": 3.5, "from": 0.0},
			"knight": {"weight": 1.5, "from": 20.0},
			"zombie": {"weight": 1.5, "from": 0.0},
			"ghost": {"weight": 1.0, "from": 60.0},
			"wraith": {"weight": 0.6, "from": 100.0},
		},
	},
	{
		"id": "lair",
		"title": "Логово Князя",
		"subtitle": "Склепы, свечи и лиловая мгла. Здесь ждёт Князь вампиров со своей свитой.",
		"round": 300.0,
		"arena": [34.0, 34.0],
		"rate": 1.7,
		"tough": 1.7,
		"xp_mult": 1.5,
		"boss": "prince",
		"sky": {"top": "#0a0414", "horizon": "#3a1c4a", "ground": "#140a1c", "moon": "#d8a0ff", "moon_size": 0.045, "stars": 1.2, "haze": "#3a1c4a"},
		"env": {"bg": "#1a0e2a", "ambient": "#7a62a0", "ambient_energy": 0.75, "fog": "#2a1840", "fog_density": 0.02,
			"moon": "#c8a0f0", "moon_energy": 0.9, "exposure": 1.15, "saturation": 1.05, "volumetric": 0.035, "glow": 1.1},
		"ground": {"grass_dark": "#2a2034", "grass_light": "#3c2e4a", "dirt": "#2c2230", "path": "#5a4a66", "flowers": 0.99, "paths": 2},
		"decor": {"graves": 60, "grave_props": 20, "pines": 12, "rocks": 14, "furniture": 10, "pumpkins": 6, "crypts": 8, "obelisks": 10, "outer_pines": 40},
		"lights": {"fires": 8, "lanterns": 14, "posts": 4, "range": 11.0, "energy": 1.3, "hero_lantern": true},
		"weather": {"kind": "ash", "fireflies": true, "wisps": true},
		"enemies": {
			"zombie": {"weight": 2.0, "from": 0.0},
			"skeleton": {"weight": 2.0, "from": 0.0},
			"ghost": {"weight": 2.0, "from": 20.0},
			"ghoul": {"weight": 1.0, "from": 30.0},
			"knight": {"weight": 1.0, "from": 45.0},
			"wraith": {"weight": 0.8, "from": 60.0},
			"burning": {"weight": 0.8, "from": 80.0},
		},
	},
]


## Полное описание карты: поля карты поверх DEFAULT (вложенные словари тоже сливаются).
static func get_map(id: String) -> Dictionary:
	var result: Dictionary = _merge(DEFAULT, {})
	if id == "base":
		return _merge(DEFAULT, BASE)
	for entry in MAPS:
		if str(entry["id"]) == id:
			result = _merge(DEFAULT, entry)
			break
	return result


static func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var result := {}
	for key in base:
		var value = base[key]
		if value is Dictionary and over.has(key) and over[key] is Dictionary and key != "enemies":
			result[key] = _merge(value, over[key])
		elif over.has(key):
			result[key] = over[key]
		else:
			result[key] = value.duplicate(true) if (value is Dictionary or value is Array) else value
	for key in over:
		if not result.has(key):
			result[key] = over[key]
	return result


static func ids() -> Array:
	var result: Array = []
	for entry in MAPS:
		result.append(str(entry["id"]))
	return result


static func index_of(id: String) -> int:
	return ids().find(id)


static func title_of(id: String) -> String:
	return str(get_map(id)["title"])


static func unlock_cost(id: String) -> int:
	var index := index_of(id)
	return int(UNLOCK_COST[index]) if index >= 0 and index < UNLOCK_COST.size() else 0
