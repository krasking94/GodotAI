extends Node3D

## «Симулятор жизни», этап 1 — младенчество (0–3 года). Вид от первого лица, мультяшный стиль:
## дом из пяти комнат (детская, гостиная, кухня, ванная, спальня) строится кодом из цветных стен
## и мебели Kenney Furniture Kit; еда — Kenney Food Kit; мама и папа — человечки Kenney Blocky Characters.
## Малыш (ls_player.gd) сначала лежит в кроватке, потом ползёт, встаёт на ножки и ходит.
## Квесты (QUESTS) идут цепочкой: посмотреть на маму, дотянуться до погремушки, доползти до мишки,
## к маме в гостиную, принести мяч, встать на ножки, дойти до папы, первое слово (мини-игра с буквами),
## яблоко папе, игрушки в коробку, буквы у полки, сон (мини-игра) — и этап окончен (3 года).
## Навыки: legs (Ноги), hands (Руки), speech (Речь), mind (Ум), heart (Сердце), 0..100. Ходьба
## открывается, когда Ноги ≥ LEGS_TO_STAND: чем больше ползаешь, тем раньше встанешь. Отношения с мамой
## и папой (relations) растут за выполненные просьбы и влияют на прибавку Речи и Сердца.
## Лампочка (H) показывает, что делать, куда идти (комната и направление) и клавиши. Предисловие — в начале.
## Прогресс пишется в user://lifesim_save.json после каждого задания («Продолжить» в главном меню),
## настройки — в user://lifesim_settings.json. Экран, меню, пауза и настройки — ls_hud.gd.
## Звук: шаги и шорохи ползания, предметы, награды, клики меню (Kenney, CC0), колыбельная, двор за окном,
## лепет и смех малыша (сделаны кодом, assets/lifesim/audio). Музыка — шина Music, остальное — SFX.
##
## Самопроверка для ИИ: --test-lifesim=auto:1,seconds:120,report:5,quit:1
## auto — автопилот: закрывает предисловие, ходит к целям, нажимает E, в мини-играх отвечает верно;
## quest:N — начать сразу с задания N (0..); seconds — сколько секунд идёт проверка; report — как часто
## печатать «Жизнь [t с]: …»; quit — выйти после конца этапа или по истечении seconds; intro:0 — без предисловия;
## lamp:1 — открыть лампочку (для снимка); look:x:z — повернуть малыша к точке; spin:1 — крутить мышью (проверка обзора).

const FURNITURE := "res://assets/kenney/furniture/"
const FOOD := "res://assets/kenney/food/"
const CHARACTER := "res://assets/kenney/characters/basicCharacter.gltf"
const SKIN_DIR := "res://assets/kenney/characters/skins/"
const SOUNDS := "res://assets/kenney/graveyard/sounds/"
const AUDIO := "res://assets/lifesim/audio/"
const VERSION := "0.2 — младенчество"
const SETTINGS_PATH := "user://lifesim_settings.json"
const FURNITURE_SCALE := 2.0   # мебель Kenney: холодильник 0,92 → 1,84 м
const FOOD_SCALE := 0.45       # еда Kenney: яблоко 0,2 → 0,09 м
const World := preload("res://game/ls_world.gd")
const LEGS_TO_STAND := 18.0    # навык «Ноги», с которого малыш может встать
const MONTH_SECONDS := 25.0    # пассивный ход времени: месяц за столько секунд
const STAGE_END_MONTHS := 36
const SAVE_PATH := "user://lifesim_save.json"

## Цепочка заданий. type: look (смотреть на цель), interact (нажать E у цели), reach (подойти к цели),
## stand (встать на ножки), fetch (взять предмет и отдать получателю), collect (несколько предметов в коробку),
## letters/word/dream (мини-игры, начинаются у цели по E). who — кто просит (mom/dad), months — прибавка возраста,
## rewards — прибавки навыков.
const QUESTS := [
	{"id": "look_mom", "title": "Посмотри на маму", "text": "Покрути головой мышкой и найди маму. Она рядом с кроваткой.",
		"type": "look", "target": "Mom", "who": "mom", "months": 2, "rewards": {"heart": 6, "mind": 2},
		"say": "Привет, малыш! Это я, мама."},
	{"id": "rattle", "title": "Дотянись до погремушки", "text": "Погремушка лежит в кроватке у ног. Посмотри на неё и нажми E.",
		"type": "interact", "target": "Rattle", "who": "mom", "months": 3, "rewards": {"hands": 8, "mind": 3},
		"say": "Какой ты ловкий! Держи погремушку."},
	{"id": "bear", "title": "Доползи до мишки", "text": "Мама вынула тебя из кроватки. Ползи (W A S D) к плюшевому мишке в углу детской и нажми E.",
		"type": "interact", "target": "Bear", "who": "mom", "months": 3, "rewards": {"legs": 8, "heart": 3},
		"say": "Ползи к мишке, он тебя ждёт!"},
	{"id": "mom_living", "title": "Доползи до мамы в гостиную", "text": "Мама ушла в гостиную. Выползи из детской через дверь и подползи к маме.",
		"type": "reach", "target": "Mom", "who": "mom", "months": 3, "rewards": {"legs": 8, "heart": 4},
		"say": "Я в гостиной! Ползи ко мне, малыш."},
	{"id": "ball", "title": "Принеси мячик маме", "text": "Мячик укатился под стол на кухне. Доползи, возьми его (E) и принеси маме в гостиную (E).",
		"type": "fetch", "target": "Ball", "receiver": "Mom", "who": "mom", "months": 4, "rewards": {"legs": 8, "hands": 6, "heart": 4},
		"say": "Где же мячик? Кажется, укатился на кухню."},
	{"id": "stand", "title": "Встань на ножки", "text": "Нажми Пробел, чтобы встать. Если ножки ещё слабые, поползай ещё — навык «Ноги» растёт от ползания.",
		"type": "stand", "who": "mom", "months": 3, "rewards": {"legs": 6, "heart": 3},
		"say": "Попробуй встать! Держись, я рядом."},
	{"id": "dad_kitchen", "title": "Дойди до папы на кухне", "text": "Иди на ножках к папе на кухню. Падать не страшно: каждое падение делает ноги крепче. Пробел — снова встать.",
		"type": "reach", "target": "Dad", "who": "dad", "months": 3, "rewards": {"legs": 10, "heart": 4},
		"say": "Иди ко мне, сынок! Шаг, ещё шаг!"},
	{"id": "word", "title": "Скажи первое слово", "text": "Подойди к маме и нажми E. Собери слово МАМА из букв: выбирай нужную букву клавишами 1, 2, 3.",
		"type": "word", "target": "Mom", "who": "mom", "months": 3, "rewards": {"speech": 14, "mind": 4},
		"say": "Скажи: ма-ма. Ма-ма!"},
	{"id": "apple", "title": "Угости папу яблоком", "text": "Возьми яблоко со стола на кухне (E) и отдай папе (E). Он в гостиной на диване.",
		"type": "fetch", "target": "Apple", "receiver": "Dad", "who": "dad", "months": 3, "rewards": {"hands": 8, "heart": 6},
		"say": "Принесёшь мне яблочко со стола?"},
	{"id": "toys", "title": "Собери игрушки в коробку", "text": "В детской разбросаны игрушки: кубик, книжка и машинка. Бери по одной (E) и клади в коробку (E).",
		"type": "collect", "targets": ["Cube", "Book", "Car"], "box": "ToyBox", "who": "mom", "months": 3, "rewards": {"hands": 8, "mind": 6, "heart": 6},
		"say": "Давай уберём игрушки в коробку. Я помогу!"},
	{"id": "letters", "title": "Выучи буквы", "text": "Подойди к книжной полке в детской и нажми E. Мама покажет буквы А, Б, В — находи нужную клавишами 1, 2, 3.",
		"type": "letters", "target": "Bookcase", "who": "mom", "months": 3, "rewards": {"mind": 12, "speech": 8},
		"say": "Пойдём учить буквы у книжной полки."},
	{"id": "sleep", "title": "Ложись спать", "text": "Подойди к своей кроватке в детской и нажми E. Тебе приснится сон — лови звёздочки.",
		"type": "dream", "target": "Crib", "who": "mom", "months": 3, "rewards": {"mind": 6, "heart": 4},
		"say": "Пора спать, малыш. Сладких снов!"},
]

const DICTIONARY := {"word": "МАМА", "letters": ["А", "Б", "В", "Г", "Д", "М", "О", "П"]}

var skills := {"legs": 0.0, "hands": 0.0, "speech": 0.0, "mind": 0.0, "heart": 0.0}
var relations := {"mom": 30.0, "dad": 30.0}
var months := 0
var quest_index := 0
var stage_done := false
var _month_time := 0.0
var _look_time := 0.0
var _collected := 0
var world: Node3D  # ls_world.gd: дом, двор, свет
var _player: CharacterBody3D
var _hud: CanvasLayer
var _props := {}          # имя -> узел (мебель, предметы, родители)
var _marker: MeshInstance3D
var _marker_time := 0.0
var _sounds := {}
var _models := {}
var _skins := {}
var _test := {}
var _test_time := 0.0
var _report_time := 0.0
var _auto_wait := 0.0
var _auto_path: Array = []
var _auto_goal := Vector3.ZERO
var _mom_mood_time := 0.0
var settings := {"sensitivity": 1.0, "music": 0.6, "sfx": 0.9, "invert_y": false, "head_bob": true, "fullscreen": false}
var _music: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _sfx_bus := 0
var _music_bus := 0
var _nothing_time := 0.0
var _started := false   # игра началась (меню закрыто)
var _from_save := false  # «Продолжить»: навыки уже загружены, награды заново не выдаём

@onready var _player_node: CharacterBody3D = $Player
@onready var _hud_node: CanvasLayer = $Hud


func _ready() -> void:
	randomize()
	_parse_test()
	_player = _player_node
	_hud = _hud_node
	_player.game = self
	_player.set_hint(_hud.hint_label())
	_hud.minigame_finished.connect(_on_minigame)
	_hud.intro_closed.connect(_on_intro_closed)
	_hud.lamp_toggled.connect(func(open: bool) -> void: if open: _update_lamp())
	_hud.menu_action.connect(_on_menu_action)
	_hud.settings_changed.connect(_on_settings_changed)
	_hud.sound_requested.connect(play_sound)
	_hud.set_version("версия %s" % VERSION)
	_setup_audio()
	_load_sounds()
	_load_settings()
	world = World.new()
	add_child(world)
	world.build()
	_build_furniture()
	_build_parents()
	_build_marker()
	_player.teleport(_props["Crib"].global_position + Vector3(0, 0.55, 0), PI)
	_player.set_mode("lie")
	_player.legs = skills["legs"]
	_hud.auto_pick = _test.get("auto", "0") == "1"
	_refresh_hud()
	print("Жизнь: дом построен, мебели %d, заданий %d, малыш в кроватке" % [_props.size(), QUESTS.size()])
	if _test.is_empty() or _test.get("menu", "0") == "1":
		_hud.show_main_menu(_has_progress())
		_play_music()
		return
	_begin_game(_test.get("intro", "1") == "1" and _test.get("auto", "0") != "1")


## Старт игры (новая или продолжение): задание, предисловие, реплика мамы.
func _begin_game(with_intro: bool) -> void:
	_started = true
	_hud.hide_main_menu()
	if _test.has("quest"):
		_jump_to_quest(int(_test["quest"]))
		_test.erase("quest")
	if _test.has("look"):
		var parts: PackedStringArray = str(_test["look"]).split(":")
		if parts.size() >= 2:
			var to := Vector3(float(parts[0]), 0.0, float(parts[1])) - _player.global_position
			_player.rotation.y = atan2(-to.x, -to.z)
	_start_quest()
	_play_music()
	if with_intro:
		_hud.show_intro()
	else:
		_on_intro_closed()
	if _test.get("lamp", "0") == "1":
		_hud.toggle_lamp()
	if _test.get("pause", "0") == "1":  # для снимков: окно паузы или настроек
		_set_paused(true)
	elif _test.get("settings", "0") == "1":
		_hud._show_settings("menu")


# --- Меню, пауза, настройки ------------------------------------------------------------------

func _on_menu_action(id: String) -> void:
	match id:
		"new_game":
			_reset_progress()
			_begin_game(true)
		"continue":
			if _load_progress():
				_begin_game(false)
			else:
				_reset_progress()
				_begin_game(true)
		"resume":
			_set_paused(false)
		"main_menu":
			_set_paused(false)
			if _started and not stage_done:
				_save_progress()
			_started = false
			_hud.show_main_menu(_has_progress())
		"exit":
			if _started and not stage_done:
				_save_progress()
			get_tree().quit(0)


## Esc: закрыть открытое окно или поставить игру на паузу.
func toggle_pause() -> void:
	if _hud.handle_escape():
		play_sound("click")
		return
	if _hud.main_menu_open() or not _started or _hud.ui_open:
		return
	play_sound("click")
	_set_paused(true)


func _set_paused(on: bool) -> void:
	get_tree().paused = on
	if on:
		_hud.show_pause()
	else:
		_hud.hide_pause()


func toggle_lamp() -> void:
	play_sound("click")
	_hud.toggle_lamp()


func toggle_fullscreen() -> void:
	settings["fullscreen"] = not bool(settings.get("fullscreen", false))
	_hud.apply_settings(settings)
	_apply_settings()
	_save_settings()


func _on_settings_changed(new_settings: Dictionary) -> void:
	for key in new_settings:
		settings[key] = new_settings[key]
	_apply_settings()
	_save_settings()


func _apply_settings() -> void:
	_player.set_settings(settings)
	AudioServer.set_bus_volume_db(_music_bus, linear_to_db(clampf(float(settings.get("music", 0.6)), 0.0, 1.0)))
	AudioServer.set_bus_volume_db(_sfx_bus, linear_to_db(clampf(float(settings.get("sfx", 0.9)), 0.0, 1.0)))
	AudioServer.set_bus_mute(_music_bus, float(settings.get("music", 0.6)) <= 0.001)
	AudioServer.set_bus_mute(_sfx_bus, float(settings.get("sfx", 0.9)) <= 0.001)
	if DisplayServer.get_name() != "headless":
		var want_full: bool = bool(settings.get("fullscreen", false))
		var is_full: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		if want_full != is_full:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_full else DisplayServer.WINDOW_MODE_WINDOWED)


func _load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if file != null:
			var data: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if data is Dictionary:
				for key in settings:
					if (data as Dictionary).has(key):
						settings[key] = data[key]
	_hud.apply_settings(settings)
	_apply_settings()


func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(settings, "  "))
		file.close()


func _parse_test() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-lifesim="):
			for part in arg.trim_prefix("--test-lifesim=").split(",", false):
				var kv: PackedStringArray = part.split(":", true, 1)
				_test[kv[0]] = kv[1] if kv.size() > 1 else "1"


func _on_intro_closed() -> void:
	_say_current()


func ui_blocks_mouse() -> bool:
	return _hud.ui_open


# --- Мир: строит ls_world.gd; здесь только обёртки, чтобы мебель и предметы собирались теми же помощниками.

func _material(color: Color) -> StandardMaterial3D:
	return world.material(color)


func _box(parent: Node, size: Vector3, pos: Vector3, color: Color, solid := true, name_hint := "") -> MeshInstance3D:
	var mesh: MeshInstance3D = world.box(parent, size, pos, color, solid)
	if name_hint != "":
		mesh.name = name_hint
	return mesh


# --- Мебель и предметы ------------------------------------------------------------------

func _place(parent: Node, path: String, model_scale: float, pos: Vector3, yaw_deg: float, solid := true, item_name := "", wrapper: Node3D = null) -> Node3D:
	return world.place(parent, path, model_scale, pos, yaw_deg, solid, item_name, wrapper)


func _tint_surface(node: Node3D, material_name: String, color: Color) -> void:
	World.tint_surface(node, material_name, color)


func _instance_model(path: String) -> Node3D:
	return world.instance_model(path)


func _build_furniture() -> void:
	var root := Node3D.new()
	root.name = "Furniture"
	add_child(root)
	var fs := FURNITURE_SCALE
	# Детская: кроватка с бортиками, мишка, полка, коробка для игрушек, коврик, лампа.
	var crib := _place(root, FURNITURE + "bedSingle.glb", 1.5, Vector3(1.0, 0, 1.4), 0, true, "Crib", Item.new())
	_crib_fence(crib)
	_props["Crib"] = _station(crib, "Crib", "кроватка", "E — лечь спать")
	_props["Bear"] = _item(root, FURNITURE + "bear.glb", 1.6, Vector3(3.3, 0, 3.9), "Bear", "мишка")
	_props["Bear"].rotation_degrees.y = -40
	_props["Bookcase"] = _station(_place(root, FURNITURE + "bookcaseOpen.glb", fs, Vector3(0.4, 0, 3.6), 90, true, "Bookcase", Item.new()), "Bookcase", "книжная полка", "E — учить буквы")
	_props["ToyBox"] = _station(_place(root, FURNITURE + "cardboardBoxOpen.glb", fs, Vector3(3.5, 0, 0.7), 0, true, "ToyBox", Item.new()), "ToyBox", "коробка для игрушек", "E — положить игрушку в коробку")
	_place(root, FURNITURE + "rugRound.glb", fs, Vector3(2.4, 0, 2.6), 0, false)
	_place(root, FURNITURE + "lampRoundFloor.glb", fs, Vector3(0.4, 0, 0.5), 0, true)
	_place(root, FURNITURE + "sideTable.glb", fs, Vector3(2.4, 0, 0.4), 0, true)
	_place(root, FURNITURE + "radio.glb", fs, Vector3(2.4, 0.76, 0.4), 0, false)
	_place(root, FURNITURE + "plantSmall2.glb", fs, Vector3(2.05, 0.76, 0.4), 0, false)
	_place(root, FURNITURE + "lampWall.glb", fs, Vector3(2.0, 1.75, 0.12), 0, false)
	# Гостиная: диван, столик, телевизор, растение, ковёр, лампа.
	_place(root, FURNITURE + "loungeSofa.glb", fs, Vector3(6.25, 0, 8.3), 180, true, "Sofa")
	_place(root, FURNITURE + "tableCoffee.glb", fs, Vector3(6.25, 0, 6.6), 0, true)
	_place(root, FURNITURE + "rugRectangle.glb", fs, Vector3(6.25, 0, 6.2), 0, false)
	_place(root, FURNITURE + "cabinetTelevision.glb", fs, Vector3(6.25, 0, 0.45), 0, true)
	_place(root, FURNITURE + "televisionModern.glb", fs, Vector3(6.25, 0.62, 0.45), 0, false)
	_place(root, FURNITURE + "pottedPlant.glb", fs, Vector3(4.5, 0, 0.5), 0, true)
	_place(root, FURNITURE + "lampRoundFloor.glb", fs, Vector3(8.1, 0, 8.5), 0, true)
	_place(root, FURNITURE + "loungeChair.glb", fs, Vector3(8.0, 0, 4.0), -90, true)
	_place(root, FURNITURE + "coatRackStanding.glb", fs, Vector3(4.4, 0, 8.5), 0, true)
	var bookcase := _place(root, FURNITURE + "bookcaseClosed.glb", fs, Vector3(4.45, 0, 4.6), 90, true)
	_tint_surface(bookcase, "wood", Color("#b98755"))  # под цвет паркета
	var sofa: Node3D = _props.get("Sofa", null)
	var sofa_h: float = ((sofa.get_meta("size") as Vector3).y * 0.55) if sofa != null else 0.4
	_place(root, FURNITURE + "pillowBlue.glb", fs * 0.8, Vector3(5.5, sofa_h, 8.35), 20, false)
	_place(root, FURNITURE + "pillowBlue.glb", fs * 0.8, Vector3(7.0, sofa_h, 8.35), -15, false)
	_place(root, FURNITURE + "loungeSofaOttoman.glb", fs, Vector3(7.6, 0, 6.6), 0, true)
	_place(root, FURNITURE + "plantSmall3.glb", fs, Vector3(6.25, 0.46, 6.6), 0, false)
	# Кухня: холодильник, плита, мойка, шкафы, стол со стульями, еда.
	_place(root, FURNITURE + "kitchenFridge.glb", fs, Vector3(11.5, 0, 0.5), 0, true)
	_place(root, FURNITURE + "kitchenStove.glb", fs, Vector3(10.6, 0, 0.55), 0, true)
	_place(root, FURNITURE + "kitchenSink.glb", fs, Vector3(9.7, 0, 0.55), 0, true)
	_place(root, FURNITURE + "kitchenCabinetUpper.glb", fs, Vector3(9.7, 1.5, 0.3), 0, false)
	_place(root, FURNITURE + "kitchenCabinetUpper.glb", fs, Vector3(10.6, 1.5, 0.3), 0, false)
	_place(root, FURNITURE + "kitchenMicrowave.glb", fs, Vector3(11.5, 1.9, 0.5), 0, false)
	var counter := _place(root, FURNITURE + "kitchenCabinet.glb", fs, Vector3(11.6, 0, 1.6), -90, true)
	var counter_top: float = (counter.get_meta("size") as Vector3).y
	_place(root, FURNITURE + "toaster.glb", fs, Vector3(11.6, counter_top, 1.35), -90, false)
	_place(root, FURNITURE + "kitchenCoffeeMachine.glb", fs, Vector3(11.6, counter_top, 1.85), -90, false)
	_place(root, FURNITURE + "trashcan.glb", fs, Vector3(11.7, 0, 4.15), 0, true)
	var table := _place(root, FURNITURE + "tableCloth.glb", fs, Vector3(10.2, 0, 3.0), 0, true, "Table")
	_place(root, FURNITURE + "chair.glb", fs, Vector3(9.3, 0, 3.0), 90, true)
	_place(root, FURNITURE + "chair.glb", fs, Vector3(11.1, 0, 3.0), -90, true)
	var table_top: float = (table.get_meta("size") as Vector3).y
	_props["Apple"] = _item(root, FOOD + "apple.glb", FOOD_SCALE * 1.3, Vector3(10.0, table_top, 2.9), "Apple", "яблоко")
	_tint_surface(_props["Apple"], "red", Color("#e8342e"))  # у Kenney яблоко бледно-розовое, на скатерти не видно
	_place(root, FOOD + "banana.glb", FOOD_SCALE, Vector3(10.5, table_top, 3.1), 30, false)
	_place(root, FOOD + "cup.glb", FOOD_SCALE, Vector3(10.3, table_top, 2.7), 0, false)
	_place(root, FOOD + "bread.glb", FOOD_SCALE, Vector3(9.8, table_top, 3.2), 0, false)
	_props["Ball"] = _ball(root, Vector3(10.2, 0, 3.6))
	# Ванная и спальня — для прогулок.
	_place(root, FURNITURE + "bathtub.glb", fs, Vector3(1.3, 0, 8.3), 0, true)
	_place(root, FURNITURE + "toilet.glb", fs, Vector3(3.5, 0, 8.2), -90, true)
	_place(root, FURNITURE + "washer.glb", fs, Vector3(3.4, 0, 5.2), 0, true)
	_place(root, FURNITURE + "bathroomSink.glb", fs, Vector3(0.45, 0.8, 6.3), 90, true)
	_place(root, FURNITURE + "rugRounded.glb", fs, Vector3(2.2, 0, 6.8), 0, false)
	var washer: Node3D = _place(root, FURNITURE + "plantSmall3.glb", fs, Vector3(3.4, 0.0, 5.2), 0, false)
	washer.position.y = 1.0  # на стиральной машине (её высота 0,5 × 2)
	_place(root, FURNITURE + "bedDouble.glb", fs, Vector3(10.3, 0, 7.6), 0, true)
	_place(root, FURNITURE + "sideTable.glb", fs, Vector3(9.0, 0, 8.5), 0, true)
	_place(root, FURNITURE + "lampRoundTable.glb", fs, Vector3(9.0, 0.76, 8.5), 0, false)
	_place(root, FURNITURE + "desk.glb", fs, Vector3(11.2, 0, 5.2), 180, true)
	_place(root, FURNITURE + "chairDesk.glb", fs, Vector3(11.2, 0, 6.0), 180, true)
	_place(root, FURNITURE + "cabinetBedDrawer.glb", fs, Vector3(11.6, 0, 8.4), -90, true)
	_place(root, FURNITURE + "lampWall.glb", fs, Vector3(11.88, 1.6, 5.2), -90, false)
	_place(root, FURNITURE + "plantSmall2.glb", fs, Vector3(10.6, 0.77, 5.1), 0, false)
	# Игрушки для квеста «Собери игрушки» (появляются, когда квест начнётся) и погремушка в кроватке.
	_props["Cube"] = _toy_cube(root, Vector3(1.6, 0, 3.6))
	_props["Book"] = _item(root, FURNITURE + "books.glb", fs, Vector3(3.0, 0, 2.2), "Book", "книжка")
	_props["Car"] = _toy_car(root, Vector3(2.2, 0, 4.0))
	for id in ["Cube", "Book", "Car"]:
		_props[id].visible = false
		_props[id].set_meta("available", false)
	for id in ["Crib", "Bookcase", "ToyBox", "Ball", "Apple"]:
		_props[id].set_meta("available", false)  # включаются, когда нужны по заданию
	_props["Rattle"] = _rattle(root, crib.global_position + Vector3(0.0, 0.57, 0.6))


func _crib_fence(crib: Node3D) -> void:
	var size: Vector3 = crib.get_meta("size")
	var color := Color("#ffffff")
	var h := 0.45
	var y := size.y + h * 0.5
	for sign_x in [-1.0, 1.0]:
		var bar := _box(crib, Vector3(0.05, h, size.z), Vector3(sign_x * size.x * 0.5, y, 0), color)
		bar.rotation = Vector3.ZERO
	for sign_z in [-1.0, 1.0]:
		_box(crib, Vector3(size.x, h, 0.05), Vector3(0, y, sign_z * size.z * 0.5), color)
	# Вертикальные перекладины, чтобы было похоже на кроватку.
	for i in range(1, 6):
		var z := -size.z * 0.5 + size.z * i / 6.0
		for sign_x in [-1.0, 1.0]:
			_box(crib, Vector3(0.03, h, 0.03), Vector3(sign_x * size.x * 0.5, y, z), Color("#ffd9e6"), false)
	var pillow := _place(crib, FURNITURE + "pillow.glb", 1.3, Vector3(0, size.y, -size.z * 0.35), 0, false)
	pillow.position.y = size.y


## Предмет, который можно взять (E): модель Kenney, группа ls_interact.
func _item(parent: Node, path: String, model_scale: float, pos: Vector3, item_name: String, title: String) -> Node3D:
	var node := _place(parent, path, model_scale, pos, randf_range(-30, 30), false, item_name, Item.new())
	_make_pickup(node, item_name, title)
	return node


## Место, у которого нажимают E (кроватка, полка, коробка): не берётся в руки, подсказка своя.
func _station(node: Node3D, item_name: String, title: String, prompt_text: String) -> Node3D:
	_make_pickup(node, item_name, title)
	(node as Item).prompt_text = prompt_text
	return node


func _make_pickup(node: Node3D, item_name: String, title: String) -> void:
	var item := node as Item
	item.item_name = item_name
	item.title = title
	item.game = self
	node.set_meta("available", true)
	node.add_to_group("ls_interact")


func _ball(parent: Node, pos: Vector3) -> Node3D:
	var wrapper := Item.new()
	wrapper.name = "Ball"
	parent.add_child(wrapper)
	wrapper.position = pos
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	mesh.mesh = sphere
	mesh.material_override = _material(Color("#ff5a5a"))
	mesh.position.y = 0.12
	wrapper.add_child(mesh)
	var stripe := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.115
	torus.outer_radius = 0.13
	stripe.mesh = torus
	stripe.material_override = _material(Color("#ffffff"))
	stripe.position.y = 0.12
	wrapper.add_child(stripe)
	wrapper.set_meta("size", Vector3(0.24, 0.24, 0.24))
	_make_pickup(wrapper, "Ball", "мячик")
	return wrapper


func _toy_cube(parent: Node, pos: Vector3) -> Node3D:
	var wrapper := Item.new()
	wrapper.name = "Cube"
	parent.add_child(wrapper)
	wrapper.position = pos
	var mesh := _box(wrapper, Vector3(0.18, 0.18, 0.18), Vector3(0, 0.09, 0), Color("#4aa3ff"), false)
	mesh.rotation.y = 0.5
	var letter := Label3D.new()
	letter.text = "А"
	letter.font_size = 96
	letter.pixel_size = 0.0015
	letter.modulate = Color("#ffffff")
	letter.position = Vector3(0, 0.09, 0.092)
	letter.rotation.y = 0.5
	mesh.add_child(letter)
	wrapper.set_meta("size", Vector3(0.18, 0.18, 0.18))
	_make_pickup(wrapper, "Cube", "кубик")
	return wrapper


func _toy_car(parent: Node, pos: Vector3) -> Node3D:
	var wrapper := Item.new()
	wrapper.name = "Car"
	parent.add_child(wrapper)
	wrapper.position = pos
	_box(wrapper, Vector3(0.3, 0.1, 0.15), Vector3(0, 0.1, 0), Color("#ffb000"), false)
	_box(wrapper, Vector3(0.16, 0.09, 0.13), Vector3(-0.02, 0.19, 0), Color("#ffd060"), false)
	for x in [-0.09, 0.09]:
		for z in [-0.08, 0.08]:
			var wheel := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.045
			cyl.bottom_radius = 0.045
			cyl.height = 0.03
			wheel.mesh = cyl
			wheel.material_override = _material(Color("#333333"))
			wheel.rotation.x = PI / 2
			wheel.position = Vector3(x, 0.045, z)
			wrapper.add_child(wheel)
	wrapper.rotation.y = -0.6
	wrapper.set_meta("size", Vector3(0.3, 0.25, 0.15))
	_make_pickup(wrapper, "Car", "машинка")
	return wrapper


func _rattle(parent: Node, pos: Vector3) -> Node3D:
	var wrapper := Item.new()
	wrapper.name = "Rattle"
	parent.add_child(wrapper)
	wrapper.position = pos
	var handle := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.015
	cyl.bottom_radius = 0.02
	cyl.height = 0.16
	handle.mesh = cyl
	handle.material_override = _material(Color("#ffffff"))
	handle.rotation.z = PI / 2
	handle.position = Vector3(-0.08, 0.03, 0)
	wrapper.add_child(handle)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.055
	sphere.height = 0.11
	head.mesh = sphere
	head.material_override = _material(Color("#ff8ac8"))
	head.position = Vector3(0.03, 0.05, 0)
	wrapper.add_child(head)
	wrapper.set_meta("size", Vector3(0.22, 0.1, 0.1))
	_make_pickup(wrapper, "Rattle", "погремушка")
	return wrapper


# --- Родители ----------------------------------------------------------------------------

func _build_parents() -> void:
	_props["Mom"] = _parent("Mom", "Мама", "woman", Vector3(2.3, 0, 1.6), Vector3(1.0, 0.55, 1.4))
	_props["Dad"] = _parent("Dad", "Папа", "man", Vector3(9.4, 0, 3.6), Vector3(10.2, 0.6, 3.0))


func _parent(id: String, title: String, skin: String, pos: Vector3, look_at_point: Vector3) -> Node3D:
	var person := Parent.new()
	person.name = id
	person.title = title
	person.game = self
	person.player = _player
	add_child(person)
	var model := _instance_model(CHARACTER)
	if model != null:
		model.scale = Vector3.ONE * 0.1  # 16 единиц → 1,6 м
		person.add_child(model)
		var material := StandardMaterial3D.new()
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.roughness = 1.0
		var path := SKIN_DIR + "skin_" + skin + ".png"
		if ResourceLoader.exists(path):
			material.albedo_texture = load(path)
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = material
		person.model = model
		person.setup_limbs()
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	shape.shape = capsule
	shape.position.y = 0.8
	body.add_child(shape)
	person.add_child(body)
	var label := Label3D.new()
	label.text = title
	label.font_size = 64
	label.pixel_size = 0.0022
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 1.85
	label.outline_size = 12
	person.add_child(label)
	person.position = pos
	person.look_at_point = look_at_point
	person.add_to_group("ls_interact")
	return person


## Над целью крутится золотая звёздочка со свечением.
func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.12, 0.12, 0.12)
	_marker.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#ffd040")
	material.emission_enabled = true
	material.emission = Color("#ffb020")
	material.emission_energy_multiplier = 0.7
	_marker.material_override = material
	var star := Label3D.new()
	star.text = "★"
	star.font_size = 140
	star.pixel_size = 0.003
	star.modulate = Color("#ffe060")
	star.outline_modulate = Color("#b07a10")
	star.outline_size = 16
	star.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	star.no_depth_test = true
	star.position.y = 0.22
	_marker.add_child(star)
	var light := OmniLight3D.new()
	light.light_color = Color("#ffd040")
	light.light_energy = 0.6
	light.omni_range = 1.5
	_marker.add_child(light)
	_marker.visible = false
	add_child(_marker)


# --- Квесты -------------------------------------------------------------------------------

func current_quest() -> Dictionary:
	return QUESTS[quest_index] if quest_index < QUESTS.size() else {}


func _start_quest() -> void:
	if quest_index >= QUESTS.size():
		_finish_stage()
		return
	var quest := current_quest()
	_look_time = 0.0
	_collected = 0
	for item_name in _player.inventory.duplicate():  # новое задание — руки свободны (погремушку и мишку малыш отложил)
		_player.remove_item(item_name)
	_hud.set_quest("Задание %d: %s" % [quest_index + 1, quest["title"]], quest["text"], quest_index + 1, QUESTS.size())
	match str(quest["id"]):
		"bear":
			# Мама вынимает малыша из кроватки и ставит на пол.
			_player.teleport(Vector3(2.0, 0.3, 2.0), deg_to_rad(-120))
			_player.set_mode("crawl")
			_props["Mom"].walk_to(Vector3(2.0, 0, 0.9))
		"mom_living":
			_props["Mom"].walk_to(Vector3(6.2, 0, 4.3))
		"ball":
			_props["Ball"].set_meta("available", true)
		"dad_kitchen":
			_props["Dad"].walk_to(Vector3(9.3, 0, 3.6))
		"apple":
			_props["Apple"].set_meta("available", true)
			_props["Dad"].walk_to(Vector3(6.2, 0, 7.4))
		"toys":
			for id in ["Cube", "Book", "Car", "ToyBox"]:
				_props[id].visible = true
				_props[id].set_meta("available", true)
			_props["Mom"].walk_to(Vector3(2.6, 0, 1.4))
		"letters":
			_props["Bookcase"].set_meta("available", true)
			_props["Mom"].walk_to(Vector3(1.2, 0, 3.0))
		"sleep":
			_props["Crib"].set_meta("available", true)
			_props["Mom"].walk_to(Vector3(2.2, 0, 1.0))
	_update_marker()
	_update_lamp()
	print("Задание %d «%s» началось" % [quest_index + 1, quest["title"]])


func _say_current() -> void:
	var quest := current_quest()
	if quest.is_empty():
		return
	var who: String = "Мама" if quest["who"] == "mom" else "Папа"
	_hud.say(who, str(quest.get("say", "")), 5.0)
	var parent: Node3D = _props.get("Mom" if quest["who"] == "mom" else "Dad")
	if parent is Parent:
		(parent as Parent).wave()
	play_sound("say")


func _jump_to_quest(index: int) -> void:
	# Для снимков и проверок: выполнить все задания до index мгновенно.
	while quest_index < clampi(index, 0, QUESTS.size()) :
		var quest := current_quest()
		if not _from_save:
			_apply_rewards(quest)  # при продолжении навыки уже загружены из сохранения
		match str(quest["id"]):
			"bear":
				_player.teleport(Vector3(2.0, 0.3, 2.0), deg_to_rad(-120))
				_player.set_mode("crawl")
			"rattle":
				_props["Rattle"].visible = false
				_props["Rattle"].set_meta("available", false)
			"stand":
				_player.can_walk = true
				_player.set_mode("walk")
		quest_index += 1
	if quest_index > 2 and _player.mode == "lie":
		_player.teleport(Vector3(2.0, 0.3, 2.0), deg_to_rad(-120))
		_player.set_mode("crawl")
	if quest_index > 5:
		_player.can_walk = true
		_player.set_mode("walk")
	_from_save = false


func _apply_rewards(quest: Dictionary) -> void:
	var rewards: Dictionary = quest.get("rewards", {})
	for id in rewards:
		add_skill(id, float(rewards[id]))
	months += int(quest.get("months", 0))
	var who := str(quest.get("who", "mom"))
	relations[who] = minf(relations[who] + 7.0, 100.0)
	var other := "dad" if who == "mom" else "mom"
	relations[other] = minf(relations[other] + 2.0, 100.0)


func _complete_quest() -> void:
	var quest := current_quest()
	var target := _target_node()
	_apply_rewards(quest)
	play_sound("levelup")
	_hud.quest_banner("Задание выполнено!\n%s" % quest["title"])
	_hud.flash(Color(1.0, 0.9, 0.5, 0.25), 0.5)
	_sparkle((target.global_position + Vector3.UP * 0.8) if target != null else (_player.global_position + _player.look_dir() * 0.8 + Vector3.UP * 0.6))
	var who: String = "Мама" if quest["who"] == "mom" else "Папа"
	_hud.say(who, _praise(), 3.0)
	var parent: Node3D = _props.get("Mom" if quest["who"] == "mom" else "Dad")
	if parent is Parent:
		(parent as Parent).wave()
	if str(quest["id"]) in ["word"]:
		get_tree().create_timer(0.6).timeout.connect(func() -> void: play_sound("babble_mama"))
	elif str(quest["id"]) in ["rattle", "bear", "ball", "toys"]:
		get_tree().create_timer(0.5).timeout.connect(func() -> void: play_sound("giggle"))
	print("Задание %d «%s» выполнено; навыки %s; возраст %d мес." % [quest_index + 1, quest["title"], _skills_text(), months])
	quest_index += 1
	_refresh_hud()
	_auto_wait = 1.5
	if quest_index < QUESTS.size():
		_save_progress()
		_start_quest()
		get_tree().create_timer(3.2).timeout.connect(_say_current)
	else:
		_finish_stage()


## Золотые искры в точке (выполненное задание).
func _sparkle(pos: Vector3) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = true
	particles.amount = 40
	particles.lifetime = 1.1
	particles.explosiveness = 0.9
	particles.direction = Vector3.UP
	particles.spread = 70.0
	particles.initial_velocity_min = 1.2
	particles.initial_velocity_max = 2.4
	particles.gravity = Vector3(0, -3.0, 0)
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	particles.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#ffe060")
	material.emission_enabled = true
	material.emission = Color("#ffd040")
	material.emission_energy_multiplier = 2.5
	particles.material_override = material
	add_child(particles)
	particles.global_position = pos
	get_tree().create_timer(2.0).timeout.connect(particles.queue_free)


func _praise() -> String:
	var lines := ["Умница!", "Молодец, малыш!", "Вот это да!", "Ты растёшь на глазах!", "Какой ты у нас способный!"]
	return lines[randi() % lines.size()]


## Герой зовёт при каждом падении: ноги крепнут, папа подбадривает.
func on_fall() -> void:
	add_skill("legs", 2.5)
	play_sound("hurt")
	_hud.flash(Color(0.9, 0.3, 0.3, 0.3), 0.6)
	_hud.toast("Упал! Ничего страшного — Пробел, чтобы встать снова", 2.5)


## E в пустоту: подсказать, как брать предметы (не чаще раза в пару секунд).
func on_interact_nothing() -> void:
	if _nothing_time > 0.0:
		return
	_nothing_time = 2.5
	_hud.toast("Рядом нечего взять: подойди ближе и смотри прямо на предмет", 2.0)


## Пробел, когда ходьба ещё не открыта: проверяем, хватает ли навыка.
func on_try_stand() -> void:
	if skills["legs"] >= LEGS_TO_STAND:
		_player.can_walk = true
		_player.set_mode("walk")
		play_sound("stand")
		_hud.toast("Ты встал на ножки!", 3.0)
		if str(current_quest().get("id", "")) == "stand":
			_complete_quest()
	else:
		var need := int(ceil(LEGS_TO_STAND - skills["legs"]))
		_hud.say("Мама", "Ножки ещё слабые. Поползай ещё немного, навык «Ноги» вырастет на %d — и получится!" % need, 3.0)


func add_skill(id: String, amount: float) -> void:
	if not skills.has(id):
		return
	var bonus := 1.0
	if id == "speech" or id == "heart":
		bonus = 1.0 + (relations["mom"] + relations["dad"]) / 400.0  # послушные дети учатся говорить быстрее
	skills[id] = clampf(skills[id] + amount * bonus, 0.0, 100.0)
	_player.legs = skills["legs"]
	if amount >= 1.0:
		_refresh_hud()
		_hud.skill_popup(id, amount * bonus)


func _skills_text() -> String:
	var parts := []
	for id in skills:
		parts.append("%s %d" % [id, int(skills[id])])
	return ", ".join(parts)


func _refresh_hud() -> void:
	_hud.set_skills(skills)
	_hud.set_relations(relations)
	_hud.set_age(months)


## Предмет или родитель, к которому нажали E. Возвращает true, если взаимодействие обработано квестом.
func on_interact(node: Node3D, item_name: String) -> void:
	var quest := current_quest()
	if quest.is_empty():
		return
	var type := str(quest["type"])
	match type:
		"interact":
			if item_name == quest["target"]:
				_pickup_into_hands(node, item_name)
				_complete_quest()
		"fetch":
			if item_name == quest["target"] and not _player.has_item(item_name):
				_pickup_into_hands(node, item_name)
				_hud.toast("Теперь отнеси %s" % ("маме" if quest["receiver"] == "Mom" else "папе"), 2.5)
				_update_marker()
			elif item_name == quest["receiver"] and _player.has_item(str(quest["target"])):
				_player.remove_item(str(quest["target"]))
				play_sound("pickup")
				_complete_quest()
			elif item_name == "Mom" or item_name == "Dad":
				_say_current()
		"collect":
			var targets: Array = quest["targets"]
			if targets.has(item_name) and _player.inventory.is_empty():
				_pickup_into_hands(node, item_name)
				_hud.toast("Теперь положи в коробку", 2.0)
				_update_marker()
			elif item_name == quest["box"] and not _player.inventory.is_empty() and targets.has(_player.inventory[0]):
				_player.remove_item(_player.inventory[0])
				_collected += 1
				play_sound("pickup")
				add_skill("hands", 2.0)
				_hud.toast("Убрано %d из %d" % [_collected, targets.size()], 2.0)
				if _collected >= targets.size():
					_complete_quest()
				else:
					_update_marker()
			elif item_name == quest["box"]:
				_hud.toast("Сначала возьми игрушку", 2.0)
			elif item_name == "Mom" or item_name == "Dad":
				_say_current()
		"word", "letters", "dream":
			if item_name == quest["target"]:
				_start_minigame(type)
			elif item_name == "Mom" or item_name == "Dad":
				_say_current()
		_:
			if item_name == "Mom" or item_name == "Dad":
				_say_current()


func _pickup_into_hands(node: Node3D, item_name: String) -> void:
	var title := item_name
	if node is Item:
		title = (node as Item).title
	node.set_meta("available", false)
	# Модель уходит в руки малыша: копия без столкновений.
	var copy := Node3D.new()
	for child in node.get_children():
		if child is MeshInstance3D:
			copy.add_child((child as MeshInstance3D).duplicate())
		elif child is Node3D and not (child is StaticBody3D):
			copy.add_child((child as Node3D).duplicate())
	var size: Vector3 = node.get_meta("size", Vector3(0.2, 0.2, 0.2))
	var k := 0.25 / maxf(size.x, maxf(size.y, size.z))
	copy.scale = Vector3.ONE * minf(k, 1.0)
	node.visible = false
	_player.add_item(item_name, copy)
	add_skill("hands", 1.5)
	play_sound("pickup")
	_hud.toast("Ты взял: %s" % title, 1.5)


func _start_minigame(type: String) -> void:
	var rounds := []
	if type == "word":
		var word: String = DICTIONARY["word"]
		for i in word.length():
			var answer := word[i]
			rounds.append(_letter_round("Слово МАМА. Какая буква идёт %s?" % ["первой", "второй", "третьей", "четвёртой"][i], answer))
	elif type == "letters":
		for letter in ["А", "Б", "В"]:
			rounds.append(_letter_round("Это буква %s. Найди её среди трёх!" % letter, letter))
	if type == "dream":
		_hud.start_dream(4)
	else:
		_hud.start_letters(rounds, type)


func _letter_round(question: String, answer: String) -> Dictionary:
	var pool: Array = DICTIONARY["letters"].duplicate()
	pool.erase(answer)
	pool.shuffle()
	var options := [answer, pool[0], pool[1]]
	options.shuffle()
	return {"question": question, "options": options, "answer": options.find(answer)}


func _on_minigame(result: Dictionary) -> void:
	var quest := current_quest()
	if quest.is_empty():
		return
	var wrong := int(result["wrong"])
	if wrong == 0:
		_hud.toast("Без единой ошибки! Ум +3", 2.5)
		add_skill("mind", 3.0)
	if str(quest["type"]) == str(result["kind"]):
		_complete_quest()


func _finish_stage() -> void:
	if stage_done:
		return
	stage_done = true
	months = maxi(months, STAGE_END_MONTHS)
	_refresh_hud()
	_hud.set_quest("Этап пройден", "Тебе три года. Впереди садик!")
	_marker.visible = false
	_save_final()
	var text := "[b]Тебе исполнилось 3 года![/b]\n\nМладенчество пройдено. Вот каким ты вырос:\n"
	for id in skills:
		text += "• %s: %d\n" % [_hud.SKILL_TITLES[id], int(skills[id])]
	text += "• Отношения с мамой: %d, с папой: %d\n" % [int(relations["mom"]), int(relations["dad"])]
	text += "• Падений, пока учился ходить: %d\n\n" % _player.falls
	text += "Итог сохранён. Следующий этап — [b]садик[/b] — появится в следующей версии игры."
	_hud.show_end(text)
	play_sound("win")
	print("Жизнь: этап «младенчество» пройден; навыки %s; отношения мама %d папа %d; падений %d" % [_skills_text(), int(relations["mom"]), int(relations["dad"]), _player.falls])
	if _test.get("quit", "0") == "1":
		get_tree().create_timer(1.0).timeout.connect(func() -> void: get_tree().quit(0))


func _read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return data if data is Dictionary else {}


func _write_save(data: Dictionary) -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		print("Жизнь: не удалось сохранить (%s)" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data, "  "))
	file.close()


## Есть ли незаконченная жизнь, которую можно продолжить.
func _has_progress() -> bool:
	var data := _read_save()
	return data.has("progress") and int((data["progress"] as Dictionary).get("quest_index", 0)) < QUESTS.size()


## Прогресс пишется после каждого задания: с какого задания продолжать, навыки, отношения, возраст.
func _save_progress() -> void:
	var data := _read_save()
	data["progress"] = {"quest_index": quest_index, "skills": skills.duplicate(), "relations": relations.duplicate(),
		"months": months, "falls": _player.falls, "can_walk": _player.can_walk, "saved_at": Time.get_datetime_string_from_system()}
	_write_save(data)
	print("Жизнь: прогресс сохранён (задание %d)" % (quest_index + 1))


func _load_progress() -> bool:
	var data := _read_save()
	if not data.has("progress"):
		return false
	var p: Dictionary = data["progress"]
	var index := int(p.get("quest_index", 0))
	if index >= QUESTS.size():
		return false
	_reset_state()
	for id in skills:
		skills[id] = float((p.get("skills", {}) as Dictionary).get(id, 0.0))
	for id in relations:
		relations[id] = float((p.get("relations", {}) as Dictionary).get(id, 30.0))
	months = int(p.get("months", 0))
	_player.falls = int(p.get("falls", 0))
	_player.legs = skills["legs"]
	_test["quest"] = str(index)  # _begin_game перенесёт малыша к нужному заданию
	_from_save = true
	_refresh_hud()
	print("Жизнь: продолжаем с задания %d" % (index + 1))
	return true


## Итог этапа: хранится отдельно от прогресса (задел для «начать новую жизнь с садика»), прогресс стирается.
func _save_final() -> void:
	var data := _read_save()
	data["stage"] = "infancy"
	data["stage_done"] = true
	data["skills"] = skills.duplicate()
	data["relations"] = relations.duplicate()
	data["months"] = months
	data["falls"] = _player.falls
	data["saved_at"] = Time.get_datetime_string_from_system()
	data.erase("progress")
	_write_save(data)
	print("Жизнь: итог этапа сохранён в %s" % SAVE_PATH)


func _reset_progress() -> void:
	var data := _read_save()
	data.erase("progress")
	_write_save(data)
	_reset_state()


## Вернуть игру к началу: малыш в кроватке, навыки по нулям, предметы на местах.
func _reset_state() -> void:
	for id in skills:
		skills[id] = 0.0
	relations = {"mom": 30.0, "dad": 30.0}
	months = 0
	quest_index = 0
	stage_done = false
	_month_time = 0.0
	_collected = 0
	_auto_path.clear()
	for item_name in _player.inventory.duplicate():
		_player.remove_item(item_name)
	_player.falls = 0
	_player.can_walk = false
	_player.legs = 0.0
	_player.teleport(_props["Crib"].global_position + Vector3(0, 0.55, 0), PI)
	_player.set_mode("lie")
	for id in ["Bear", "Rattle", "Ball", "Apple", "Cube", "Book", "Car"]:
		_props[id].visible = id in ["Bear", "Rattle"]
		_props[id].set_meta("available", id in ["Bear", "Rattle"])
	for id in ["Crib", "Bookcase", "ToyBox"]:
		_props[id].set_meta("available", false)
	_props["ToyBox"].visible = true
	_props["Mom"].teleport_to(Vector3(2.3, 0, 1.6))
	_props["Dad"].teleport_to(Vector3(9.4, 0, 3.6))
	_refresh_hud()


# --- Цель на экране и лампочка ----------------------------------------------------------------

func _target_node() -> Node3D:
	var quest := current_quest()
	if quest.is_empty():
		return null
	var type := str(quest["type"])
	if type == "fetch":
		return _props.get(str(quest["receiver"])) if _player.has_item(str(quest["target"])) else _props.get(str(quest["target"]))
	if type == "collect":
		if not _player.inventory.is_empty():
			return _props.get(str(quest["box"]))
		for id in quest["targets"]:
			if _props[id].get_meta("available", false):
				return _props[id]
		return _props.get(str(quest["box"]))
	if type == "stand":
		return null
	return _props.get(str(quest.get("target", "")))


func _update_marker() -> void:
	var target := _target_node()
	_marker.visible = target != null and not stage_done
	if target != null:
		var size: Vector3 = target.get_meta("size", Vector3(0.3, 1.6, 0.3))
		_marker.global_position = target.global_position + Vector3(0, size.y + 0.35, 0)


func _room_of(point: Vector3) -> String:
	return world.room_title(world.room_of(point))


func _direction_word(target: Node3D) -> String:
	var to := target.global_position - _player.global_position
	to.y = 0.0
	if to.length() < 0.8:
		return "совсем рядом"
	var forward := -_player.global_transform.basis.z
	var angle := rad_to_deg(forward.signed_angle_to(to.normalized(), Vector3.UP))
	var dist := "%.0f м" % to.length()
	if absf(angle) < 30.0:
		return "прямо перед тобой, %s" % dist
	if absf(angle) > 150.0:
		return "сзади, %s — развернись" % dist
	return "%s, %s" % ["слева" if angle > 0.0 else "справа", dist]


func _update_lamp() -> void:
	var quest := current_quest()
	var text := ""
	if quest.is_empty():
		text = "[b]Этап пройден.[/b] Садик появится в следующей версии."
	else:
		text = "[b]Что делать сейчас[/b]\n%s\n\n" % quest["text"]
		var target := _target_node()
		if target != null:
			text += "[b]Куда идти[/b]\nЦель — %s. Она в комнате «%s»: %s. Над целью крутится золотая звёздочка.\n\n" % [_target_title(target), _room_of(target.global_position), _direction_word(target)]
		elif str(quest["type"]) == "stand":
			text += "[b]Куда идти[/b]\nНикуда: просто нажми Пробел. Навык «Ноги» сейчас %d, нужно %d.\n\n" % [int(skills["legs"]), int(LEGS_TO_STAND)]
	text += "[b]Что ты умеешь[/b]\n"
	match _player.mode:
		"lie":
			text += "• Лежать в кроватке и крутить головой (мышь)\n• E — дотянуться до того, на что смотришь\n"
		"crawl", "fallen":
			text += "• Ползать: W A S D, мышь — смотреть\n• E — взять предмет или поговорить\n"
			text += "• Пробел — встать на ножки%s\n" % ("" if _player.can_walk else " (когда «Ноги» дорастут до %d)" % int(LEGS_TO_STAND))
		"walk":
			text += "• Ходить: W A S D (устал — садись Пробелом и ползи)\n• E — взять предмет или поговорить\n• Пробел — сесть на пол\n"
	text += "• H или лампочка — закрыть эту подсказку\n\n[b]Навыки[/b] растут от дел: ползание и ходьба — Ноги, предметы — Руки, слова — Речь, задачки — Ум, помощь родителям — Сердце."
	_hud.set_lamp_text(text)


func _target_title(target: Node3D) -> String:
	if target is Item:
		return (target as Item).title
	if target is Parent:
		return (target as Parent).title.to_lower()
	return str(target.name).to_lower()


# --- Звук ---------------------------------------------------------------------------------------

## Две шины громкости: Music (колыбельная и двор) и SFX (всё остальное); их крутят ползунки настроек.
func _setup_audio() -> void:
	_music_bus = AudioServer.get_bus_index("Music")
	if _music_bus < 0:
		AudioServer.add_bus()
		_music_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_music_bus, "Music")
	_sfx_bus = AudioServer.get_bus_index("SFX")
	if _sfx_bus < 0:
		AudioServer.add_bus()
		_sfx_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_sfx_bus, "SFX")


## Звуки по именам событий. Для каждого — список файлов (варианты шагов) и громкость в дБ.
const SOUND_TABLE := {
	"hover": [["hover"], -14.0], "click": [["click"], -8.0], "pickup": [["pickup"], -6.0],
	"levelup": [["levelup"], -4.0], "hurt": [["hurt"], -6.0], "win": [["win"], -3.0], "say": [["select"], -12.0],
	"correct": [["heal"], -8.0], "wrong": [["hover"], -8.0], "stand": [["relic"], -8.0],
	"step": [["step0", "step1", "step2", "step3"], -14.0],
	"crawl": [["@crawl0", "@crawl1", "@crawl2"], -10.0],
	"giggle": [["@giggle"], -6.0], "babble_mama": [["@babble_mama"], -4.0], "babble_dada": [["@babble_dada"], -4.0],
}


func _load_sounds() -> void:
	for id in SOUND_TABLE:
		var spec: Array = SOUND_TABLE[id]
		var streams: Array = []
		for file_name in spec[0]:
			var name_str := str(file_name)
			var path: String = (AUDIO + name_str.trim_prefix("@") + ".wav") if name_str.begins_with("@") else (SOUNDS + name_str + ".ogg")
			if ResourceLoader.exists(path):
				streams.append(load(path))
		if streams.is_empty():
			continue
		var player := AudioStreamPlayer.new()
		player.name = "Sound_" + id
		player.volume_db = float(spec[1])
		player.bus = "SFX"
		player.max_polyphony = 3
		add_child(player)
		_sounds[id] = {"player": player, "streams": streams}


## Сыграть звук события; из нескольких вариантов берётся случайный, высота чуть плавает — так живее.
func play_sound(id: String) -> void:
	if not _sounds.has(id):
		return
	var entry: Dictionary = _sounds[id]
	var player: AudioStreamPlayer = entry["player"]
	var streams: Array = entry["streams"]
	player.stream = streams[randi() % streams.size()]
	player.pitch_scale = randf_range(0.94, 1.06)
	player.play()


## Шаг малыша: на ножках — шаги, ползком — шорох ладошек.
func play_step(mode: String) -> void:
	play_sound("step" if mode == "walk" else "crawl")


## Колыбельная и двор за окном — петлёй, тихо, на шине Music (играют и в меню, и на паузе).
func _play_music() -> void:
	if _music != null:
		return
	_music = _loop_player(AUDIO + "lullaby.wav", -10.0)
	_ambient = _loop_player(AUDIO + "ambient_day.wav", -16.0)


func _loop_player(path: String, volume_db: float) -> AudioStreamPlayer:
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path)
	if stream is AudioStreamWAV:
		stream = (stream as AudioStreamWAV).duplicate()
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_begin = 0
		(stream as AudioStreamWAV).loop_end = (stream as AudioStreamWAV).data.size() / 2  # 16 бит моно
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = "Music"
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	player.play()
	return player


# --- Ход времени и самопроверка ----------------------------------------------------------------

func _process(delta: float) -> void:
	if stage_done:
		return
	if not _hud.ui_open:
		_month_time += delta
		if _month_time >= MONTH_SECONDS:
			_month_time -= MONTH_SECONDS
			months += 1
			_hud.set_age(months)
			if months >= STAGE_END_MONTHS:
				_finish_stage()
				return
	_marker_time += delta
	if _marker.visible:
		_marker.position.y += sin(_marker_time * 4.0) * 0.0025
		_marker.rotation.y += delta * 2.0
	_nothing_time = maxf(_nothing_time - delta, 0.0)
	_hud.set_balance(_player.mode == "walk", _player.balance)
	var quest := current_quest()
	if not quest.is_empty() and str(quest["type"]) in ["look", "reach"]:
		var target: Node3D = _props.get(str(quest["target"]))
		if target != null:
			if str(quest["type"]) == "look":
				var to: Vector3 = (target.global_position + Vector3.UP * 1.2 - _player.camera.global_position).normalized()
				if _player.look_dir().dot(to) > 0.9:
					_look_time += delta
					if _look_time > 1.2:
						_complete_quest()
				else:
					_look_time = 0.0
			elif _player.global_position.distance_to(target.global_position) < 1.3 and not (target is Parent and (target as Parent).is_walking()):
				_complete_quest()
	if _hud.lamp_open() and fmod(_marker_time, 0.5) < delta:
		_update_lamp()
	_test_tick(delta)


func _test_tick(delta: float) -> void:
	if _test.is_empty():
		return
	_test_time += delta
	var report := float(_test.get("report", "0"))
	if report > 0.0:
		_report_time += delta
		if _report_time >= report:
			_report_time -= report
			print("Жизнь [%d с]: задание %d (%s), режим %s, позиция %s, навыки %s, возраст %d мес." % [int(_test_time), quest_index + 1,
				str(current_quest().get("id", "конец")), _player.mode, _player.global_position.snapped(Vector3(0.1, 0.1, 0.1)), _skills_text(), months])
			if _test.get("spin", "0") == "1":
				print("  поворот головы: %.0f°, мышь захвачена=%s" % [rad_to_deg(_player.rotation.y), Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED])
			if _test.get("debug", "0") == "1":
				print("  автопилот: goto=%s путь=%s равновесие=%.2f скорость=%s ui=%s ждать=%.1f" % [_player._goto_active, _auto_path, _player.balance,
					_player.get_real_velocity().snapped(Vector3(0.01, 0.01, 0.01)), _hud.ui_open, _auto_wait])
	if _test.get("spin", "0") == "1":
		# Проверка обзора мышью: подаём движение мыши как настоящее событие, в отчёте печатается поворот.
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(12, 0)
		Input.parse_input_event(motion)
	if _test.has("seconds") and _test_time >= float(_test["seconds"]):
		print("Жизнь: проверка окончена по времени; задание %d, навыки %s" % [quest_index + 1, _skills_text()])
		if _test.get("quit", "0") == "1":
			get_tree().quit(0)
		_test.erase("seconds")
	if _test.get("auto", "0") == "1":
		_auto_step(delta)


## Автопилот: выполняет текущее задание сам.
func _auto_step(delta: float) -> void:
	if _auto_wait > 0.0:
		_auto_wait -= delta
		return
	var quest := current_quest()
	if quest.is_empty() or _hud.ui_open:
		return
	var type := str(quest["type"])
	if type == "look":
		var target: Node3D = _props[str(quest["target"])]
		var to: Vector3 = target.global_position + Vector3.UP * 1.2 - _player.camera.global_position
		_player.rotation.y = atan2(-to.x, -to.z)
		_player.camera.rotation.x = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -1.2, 1.2)
		return
	if type == "stand":
		if skills["legs"] < LEGS_TO_STAND:
			# Ползаем туда-сюда, чтобы ноги окрепли.
			var goal := Vector3(6.0, 0, 2.0) if fmod(_test_time, 6.0) < 3.0 else Vector3(6.0, 0, 7.5)
			if _room_id(_player.global_position) != "living":
				_auto_path = route(_player.global_position, goal)
				goal = _auto_path[0]
			_player.goto(goal)
		else:
			_player.stop_goto()
			_player.toggle_stand()
			_auto_wait = 1.0
		return
	var target := _target_node()
	if target == null:
		return
	if _player.mode == "crawl" and _player.can_walk:
		_player.toggle_stand()
	if _player.mode == "lie":
		_player.aim_at(target.global_position)
		_player.interact_nearest()
		_auto_wait = 0.5
		return
	var point := target.global_position
	if target is Parent:
		point += (_player.global_position - point).normalized() * 0.6
	var flat := target.global_position - _player.global_position
	flat.y = 0.0
	var near: float = 1.0 if type == "reach" else (_player.reach() + 0.1 if target is Parent else _player.reach() * 0.6)
	if flat.length() < near:
		_player.stop_goto()
		_auto_path.clear()
		if type == "reach":
			return
		var size: Vector3 = target.get_meta("size", Vector3(0.3, 0.3, 0.3))
		_player.aim_at(target.global_position + Vector3.UP * minf(size.y * 0.5, 0.8))
		_player.interact_nearest()
		_auto_wait = 0.8
		return
	# Идём по комнатам через двери: маршрут пересчитывается, когда меняется цель.
	if _auto_path.is_empty() or _auto_goal.distance_to(point) > 0.3:
		_auto_goal = point
		_auto_path = route(_player.global_position, point)
	if _player.goto(_auto_path[0]):
		_auto_path.remove_at(0)
		if _auto_path.is_empty():
			_auto_path = route(_player.global_position, point)


## Маршрут из точки a в точку b через дверные проёмы (все комнаты выходят в гостиную).
func route(a: Vector3, b: Vector3) -> Array:
	var from_room := _room_id(a)
	var to_room := _room_id(b)
	var path: Array = []
	if from_room != to_room:
		if from_room != "living" and World.DOORS.has(from_room):
			var door: Vector3 = World.DOORS[from_room]
			path.append(door + (door - World.ROOM_CENTER[from_room]).normalized() * -0.6)
			path.append(door + (door - World.ROOM_CENTER[from_room]).normalized() * 0.6)
		if to_room != "living" and World.DOORS.has(to_room):
			var door: Vector3 = World.DOORS[to_room]
			path.append(door + (door - World.ROOM_CENTER[to_room]).normalized() * 0.6)
			path.append(door + (door - World.ROOM_CENTER[to_room]).normalized() * -0.6)
	path.append(b)
	return path


func _room_id(point: Vector3) -> String:
	return world.room_of(point)


# --- Вложенные классы -----------------------------------------------------------------------

## Предмет, который можно взять (E): обёртка модели, группа ls_interact. Пока available = false, его не видно для E.
class Item extends Node3D:
	var item_name := ""
	var title := ""
	var prompt_text := ""
	var game: Node

	func prompt() -> String:
		return prompt_text if prompt_text != "" else "E — взять: %s" % title

	func is_available(_who: Node) -> bool:
		return visible and bool(get_meta("available", false))

	func interact(_who: Node) -> void:
		if game != null and game.has_method("on_interact"):
			game.on_interact(self, item_name)


## Мама или папа: стоит, чуть покачивается, поворачивается к малышу, умеет перейти в другую комнату (walk_to).
class Parent extends Node3D:
	var title := ""
	var game: Node
	var player: Node3D
	var model: Node3D
	var look_at_point := Vector3.ZERO
	var _goal := Vector3.ZERO
	var _walking := false
	var _time := 0.0
	var _anim := 0.0
	var _wave_time := 0.0
	var _limbs := {}

	func _ready() -> void:
		set_meta("size", Vector3(0.6, 1.6, 0.4))
		_goal = position

	## Шарниры рук и ног (как у героя «Кладбища»): плечи на высоте 12, бёдра на 6 в единицах модели.
	func setup_limbs() -> void:
		if model == null:
			return
		for limb in [["ArmLeft1", Vector3(3, 12, 0)], ["ArmRight1", Vector3(-3, 12, 0)], ["LegLeft1", Vector3(1, 6, 0)], ["LegRight1", Vector3(-1, 6, 0)]]:
			var limb_name := str(limb[0])
			var joint: Vector3 = limb[1]
			var mesh := model.find_child(limb_name, true, false)
			if mesh == null:
				continue
			var pivot := Node3D.new()
			pivot.name = limb_name + "Pivot"
			pivot.position = joint
			mesh.get_parent().add_child(pivot)
			mesh.reparent(pivot, false)
			mesh.position = -joint
			_limbs[limb_name] = pivot

	func _set_limb(limb_name: String, angle: float, roll := 0.0) -> void:
		if _limbs.has(limb_name):
			var pivot: Node3D = _limbs[limb_name]
			pivot.rotation.x = angle
			pivot.rotation.z = roll

	## Помахать рукой (когда говорит с малышом).
	func wave() -> void:
		_wave_time = 1.6

	func teleport_to(point: Vector3) -> void:
		position = point
		_goal = point
		_walking = false

	func prompt() -> String:
		return "E — поговорить с %s" % ("мамой" if title == "Мама" else "папой")

	func is_available(_who: Node) -> bool:
		return true

	func interact(_who: Node) -> void:
		if game != null and game.has_method("on_interact"):
			game.on_interact(self, name)

	func walk_to(point: Vector3) -> void:
		_goal = point
		_walking = true

	func is_walking() -> bool:
		return _walking

	func _physics_process(delta: float) -> void:
		_time += delta
		if _walking:
			var to := _goal - position
			to.y = 0.0
			if to.length() < 0.1:
				_walking = false
				position = _goal
			else:
				position += to.normalized() * minf(2.2 * delta, to.length())
				rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-8.0 * delta))
		elif player != null:
			var to := player.global_position - global_position
			to.y = 0.0
			if to.length() > 0.2:
				rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-3.0 * delta))
		if model != null:
			model.position.y = (absf(sin(_time * 9.0)) * 0.06) if _walking else (sin(_time * 1.5) * 0.015)
		# Руки и ноги: при ходьбе качаются в противофазе, стоя — лёгкое дыхание; машет правой рукой.
		var move := 1.0 if _walking else 0.0
		_anim += delta * (11.0 if _walking else 1.5)
		var swing := sin(_anim) * 0.75 * move
		var idle := sin(_time * 1.5) * 0.05
		_set_limb("LegLeft1", swing)
		_set_limb("LegRight1", -swing)
		_set_limb("ArmLeft1", -swing + idle)
		if _wave_time > 0.0:
			_wave_time -= delta
			_set_limb("ArmRight1", -2.6 + sin(_time * 14.0) * 0.25, -0.5)
		else:
			_set_limb("ArmRight1", swing + idle, 0.0)
