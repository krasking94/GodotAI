extends Node3D

## «Кладбище»: 3D-выживание против орды нежити на моделях Kenney (Graveyard Kit, Blocky Characters, CC0).
## Десять карт (gy_maps.gd): у каждой своё небо, свет, погода, земля, лужи (лёд, грязь), враги и босс;
## мир по описанию карты строит gy_world.gd. Из тумана идут зомби, скелеты и призраки, на 80 % раунда
## выходит босс. Герой стреляет сам в ближайшего врага, игрок только бегает (стрелки или WASD) и на каждом
## новом уровне выбирает прокачку (1, 2, 3). Души убитых дают опыт, тыквы лечат. Продержался round_seconds — победа.
## Между ночами — форпост (gy_base.gd): по нему ходишь, у зданий нажимаешь E: Алтарь душ (постоянная
## прокачка за души), Костёр (смена героя), Дом сторожа (летопись), Башня (укрепления: щит в начале ночи),
## Ворота (выбор карты: открываются за души). Души — валюта, их приносит каждая ночь (убитые, уровни, победа).
## После конца ночи R — та же карта заново, Enter — в форпост. Всё хранит gy_save.gd.
## Этот узел — корень сцены и ведущий; Player (gy_hero.gd) и Hud (gy_hud.gd) — его дети из сцены,
## камера, мир, враги, снаряды и души создаются кодом.
##
## Самопроверка для ИИ: --test-graveyard=seconds:30,auto:1,move:circle,seed:1,report:5,map:winter,quit:1
## pick:N — в открытом окне выбрать строку N (вместе с shop); at:x:z — поставить героя в форпосте в точку;
## slots:nova.dash.frost.meteor — какие способности в слотах на эту ночь; cast:id:сек — включить способность
## id на этой секунде (можно несколько через «;»); abilities:all — открыть все способности.
## seconds — длина раунда; auto — без меню и с автоматическим выбором прокачки; move — автопилот героя
## (circle кружит вокруг центра, away убегает от ближайшего врага, relic бежит к реликвии, none стоит);
## boss:секунда — когда выходит босс; rate — множитель частоты появления врагов; skin — имя скина;
## seed — сид карты; zoom — множитель расстояния камеры; map — id карты (old, swamp, winter, village, forest,
## bloodmoon, pumpkin, road, quarry, lair); quit — выйти из игры после конца раунда (код 0);
## fx:0 — без частиц; base — сразу в форпост; shop:id — через секунду открыть окно здания (altar, gate, camp,
## home, fence) для снимка; souls:N — выдать N душ; unlock:all — открыть все карты.
## Каждые report секунд печатает «Кладбище [t с]: …», в конце «Кладбище: итог …».

const MODELS := "res://assets/kenney/graveyard/models/"
const SOUNDS := "res://assets/kenney/graveyard/sounds/"
const SOUND_NAMES := ["bolt", "hit", "die", "hurt", "pickup", "levelup", "win", "over", "boss", "click", "swing",
	"die_zombie", "die_skeleton", "die_ghost", "die_elite", "punch", "windup", "soul", "heal", "relic", "alert", "elite",
	"hover", "select", "step0", "step1", "step2", "step3"]
const SOUND_VOLUME := {"bolt": -14.0, "hit": -8.0, "die": -6.0, "swing": -8.0, "pickup": -6.0, "die_zombie": -6.0,
	"die_skeleton": -8.0, "die_ghost": -8.0, "die_elite": -2.0, "punch": -5.0, "windup": -12.0, "soul": -12.0, "heal": -4.0,
	"alert": -2.0, "elite": -4.0, "hover": -14.0, "select": -6.0, "step0": -18.0, "step1": -18.0, "step2": -18.0, "step3": -18.0}
const SKINS := ["adventurer", "man", "woman", "soldier", "robot", "orc", "manAlternative", "womanAlternative"]
const SKIN_TITLES := {"adventurer": "Путешественник", "man": "Горожанин", "woman": "Горожанка", "soldier": "Солдат",
	"robot": "Робот", "orc": "Орк", "manAlternative": "Учёный", "womanAlternative": "Байкерша"}
const ENEMY_KINDS := {
	# model — файл модели (character — блочный человечек Kenney со скином skins), tint — подкраска, xp — опыт,
	# weight — как часто выпадает (карта задаёт своё), elite — редкий сильный враг (объявляется на табло),
	# immune — лужи, которые врагу не страшны (ice, mud), light — свой свет, boss — босс карты.
	"zombie": {"model": "zombie", "title": "Зомби", "hp": 30.0, "speed": 1.7, "damage": 10.0, "xp": 1, "scale": 1.8},
	"skeleton": {"model": "skeleton", "title": "Скелет", "hp": 14.0, "speed": 3.0, "damage": 6.0, "xp": 2, "scale": 1.7},
	"ghost": {"model": "ghost", "title": "Призрак", "hp": 22.0, "speed": 2.3, "damage": 8.0, "xp": 3, "scale": 1.6, "ghost": true},
	"ghoul": {"model": "zombie", "title": "Гуль", "tint": "#6f9a4a", "hp": 90.0, "speed": 1.3, "damage": 18.0, "xp": 10, "scale": 2.4, "elite": true},
	"knight": {"model": "skeleton", "title": "Рыцарь-скелет", "tint": "#a9bddb", "hp": 60.0, "speed": 2.4, "damage": 12.0, "xp": 8, "scale": 2.0, "elite": true},
	"wraith": {"model": "ghost", "title": "Жнец", "tint": "#c070ff", "hp": 45.0, "speed": 3.4, "damage": 10.0, "xp": 15, "scale": 2.0, "ghost": true, "elite": true, "light": "#b060ff"},
	"frost": {"model": "zombie", "title": "Мерзляк", "tint": "#9ad8ff", "hp": 45.0, "speed": 1.4, "damage": 12.0, "xp": 3, "scale": 1.9, "immune": ["ice"]},
	"bog": {"model": "zombie", "title": "Болотник", "tint": "#5a7a3a", "hp": 55.0, "speed": 1.5, "damage": 12.0, "xp": 3, "scale": 2.0, "immune": ["mud"]},
	"villager": {"model": "character", "skins": ["man", "woman", "manAlternative", "womanAlternative"], "tint": "#8a9098", "title": "Одержимый", "hp": 18.0, "speed": 3.3, "damage": 7.0, "xp": 2, "scale": 1.7, "model_scale": 0.105},
	"burning": {"model": "zombie", "title": "Горящий", "tint": "#ff8a2a", "hp": 35.0, "speed": 2.6, "damage": 12.0, "xp": 4, "scale": 1.8, "light": "#ff6a1a"},
	"guard": {"model": "skeleton", "title": "Сторож", "tint": "#ff6a4a", "hp": 40.0, "speed": 5.5, "damage": 0.0, "xp": 12, "scale": 1.7, "guard": true, "light": "#ff4a2a"},
	# Боссы: по одному на карту, выходят на 80 % раунда.
	"vampire": {"model": "vampire", "title": "Вампир", "hp": 700.0, "speed": 2.4, "damage": 25.0, "xp": 60, "scale": 3.2, "boss": true, "light": "#ff3a3a"},
	"bog_king": {"model": "zombie", "title": "Болотный царь", "tint": "#4a7a2a", "hp": 900.0, "speed": 1.9, "damage": 28.0, "xp": 70, "scale": 3.4, "boss": true, "light": "#7aff3a", "immune": ["mud"]},
	"frost_giant": {"model": "zombie", "title": "Ледяной великан", "tint": "#bfe8ff", "hp": 1000.0, "speed": 2.0, "damage": 30.0, "xp": 70, "scale": 3.6, "boss": true, "light": "#a0e0ff", "immune": ["ice"]},
	"elder": {"model": "character", "skins": ["orc"], "title": "Староста", "hp": 900.0, "speed": 3.0, "damage": 25.0, "xp": 70, "scale": 3.0, "model_scale": 0.19, "boss": true, "light": "#ffb060"},
	"ghost_lord": {"model": "ghost", "title": "Владыка призраков", "tint": "#c0a0ff", "hp": 1000.0, "speed": 2.8, "damage": 25.0, "xp": 80, "scale": 3.4, "ghost": true, "boss": true, "light": "#b080ff"},
	"pumpkin_king": {"model": "vampire", "title": "Тыквенный король", "tint": "#ff9a30", "hp": 1100.0, "speed": 2.4, "damage": 28.0, "xp": 80, "scale": 3.3, "boss": true, "light": "#ff8a20"},
	"butcher": {"model": "zombie", "title": "Мясник", "tint": "#8a2a2a", "hp": 1300.0, "speed": 2.6, "damage": 35.0, "xp": 90, "scale": 3.6, "boss": true, "light": "#ff3030"},
	"lich": {"model": "skeleton", "title": "Король-лич", "tint": "#d8f0ff", "hp": 1300.0, "speed": 2.4, "damage": 30.0, "xp": 100, "scale": 3.4, "boss": true, "light": "#80d0ff"},
	"prince": {"model": "vampire", "title": "Князь вампиров", "hp": 2500.0, "speed": 2.6, "damage": 35.0, "xp": 200, "scale": 3.6, "boss": true, "light": "#ff2a4a"},
}
const UPGRADES := [
	{"id": "damage", "title": "Сила удара", "text": "Урон снарядов +30%"},
	{"id": "rate", "title": "Скорострельность", "text": "Стреляешь на 25% чаще"},
	{"id": "multishot", "title": "Ещё снаряд", "text": "+1 снаряд за выстрел"},
	{"id": "speed", "title": "Быстрые ноги", "text": "Скорость бега +15%"},
	{"id": "health", "title": "Крепкое сердце", "text": "Макс. здоровье +25 и лечение"},
	{"id": "magnet", "title": "Магнит душ", "text": "Души притягиваются на 60% дальше"},
	{"id": "pierce", "title": "Пробивание", "text": "Снаряд пробивает ещё одного врага"},
	{"id": "regen", "title": "Восстановление", "text": "+1 здоровья в секунду"},
]
## Постоянная прокачка на Алтаре душ: level растёт за души, cost — цена первого уровня (дальше × (уровень+1)).
const PERMANENT := [
	{"id": "body", "title": "Крепкое тело", "text": "+10 к здоровью за уровень", "max": 5, "cost": 30},
	{"id": "arrows", "title": "Острые стрелы", "text": "+8% к урону за уровень", "max": 5, "cost": 40},
	{"id": "legs", "title": "Лёгкие ноги", "text": "+5% к скорости бега за уровень", "max": 5, "cost": 35},
	{"id": "hands", "title": "Быстрые руки", "text": "+6% к скорострельности за уровень", "max": 5, "cost": 45},
	{"id": "greed", "title": "Жадные руки", "text": "Магнит душ +20% за уровень", "max": 5, "cost": 25},
	{"id": "luck", "title": "Везение", "text": "Тыквы чаще, реликвия раньше", "max": 3, "cost": 50},
	{"id": "harvest", "title": "Жатва", "text": "+10% душ за ночь за уровень", "max": 5, "cost": 60},
]
const FENCE_COST := [80, 160, 320]
const FENCE_SHIELD := 30.0  # щит за каждый уровень укреплений
const RELIC_FIRST := 25.0  # первая реликвия на этой секунде (--test graveyard=relic:сек меняет)
const RELIC_EVERY := 40.0  # пауза до следующей после того, как взяли или исчезла
const RELIC_LIFETIME := 30.0  # сколько лежит, последние 5 с мигает
const RELIC_COLOR := Color("#c070ff")
const SPAWN_MIN := 17.0
const SPAWN_MAX := 22.0
const MAX_ENEMIES := 90
const SOUL_LIFETIME := 40.0
const Enemy := preload("res://game/gy_enemy.gd")
const Maps := preload("res://game/gy_maps.gd")
const World := preload("res://game/gy_world.gd")
const Save := preload("res://game/gy_save.gd")
const Fx := preload("res://game/gy_fx.gd")
const Base := preload("res://game/gy_base.gd")
const Abilities := preload("res://game/gy_abilities.gd")
const MAX_SLOTS := 4
## Цвет искр, которыми рассыпается погибший враг (по модели; подкрашенные — по своей подкраске).
const DEATH_COLORS := {"zombie": "#7cff5a", "skeleton": "#ffffff", "ghost": "#8ad8ff", "vampire": "#ff3a3a", "character": "#ffd0a0"}

## Что открыть после перезапуска сцены (статические поля переживают reload_current_scene):
## next_state — "play" (ночь на карте next_map), "base" (форпост) или "" (меню).
static var next_map := ""
static var next_state := ""

@export var round_seconds := 180.0
@export var decor_seed := 0  # 0 = каждый раз новая карта

var state := "menu"  # menu, base, shop, playing, levelup, won, over
var map_id := "old"
var map: Dictionary = {}
var arena := Vector2(34, 34)  # половина сторон арены, по краю ограда
var elapsed := 0.0
var kills := 0
var level := 1
var xp := 0
var xp_needed := 5
var boss_time := 0.0
var boss_spawned := false
var skin_index := 0
var best_score := 0
var auto := false
var enemies: Array = []  # живые враги (gy_enemy.gd)
var souls: Array = []  # души и тыквы: Node3D с meta value/kind/age
var test_options := {}
var player: CharacterBody3D
var hud: CanvasLayer
var world: Node3D
var base: Node3D = null  # форпост (только в состоянии base/shop)
var abilities: Node3D = null  # активные способности (только ночью)
var bolts_root: Node3D
var souls_earned := 0  # души за эту ночь
var boss_killed := false
var shop_id := ""
var shop_rows: Array = []

var _spawn_budget := 0.0
var _report_every := 0.0
var _forced_levelup := 0.0
var _report_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _camera: Camera3D
var _menu_light: OmniLight3D
var _enemies_root: Node3D
var _souls_root: Node3D
var _sounds := {}
var _levelup_options: Array = []
var recommended_index := 0  # какую из трёх прокачек игра советует (подсказка «Рекомендуется»)
var hold_levelup := false  # окно прокачки не закрывать автоматически (снимок окна по --test graveyard=levelup:сек)
var _soul_material: StandardMaterial3D
var _seen_kinds := {}  # какие виды врагов уже объявлялись на табло
var relic: Node3D = null  # реликвия на земле (пол-шкалы опыта), её сторожит быстрый скелет
var _relic_timer := RELIC_FIRST
var _relic_age := 0.0
var _relic_orb: MeshInstance3D
var _relic_light: OmniLight3D
var _guard: Node3D = null
var _fx_root: Node3D
var _quit_on_end := false
var _end_timer := 0.0
var _shop_timer := 0.0
var _shake := 0.0
var _casts: Array = []  # самопроверка: [id, секунда] — включить способность на этой секунде


func _ready() -> void:
	_parse_test_args()
	_rng.seed = decor_seed if decor_seed != 0 else randi()
	Save.load_data()
	if test_options.has("souls"):
		Save.data["souls"] = int(test_options["souls"])
	if test_options.has("unlock"):
		for id in Maps.ids():
			Save.unlock(id)
	if test_options.has("abilities"):
		for id in Abilities.ORDER:
			Save.unlock_ability(id)
	var mode := next_state
	if mode == "":
		if test_options.has("base"):
			mode = "base"
		elif test_options.has("map") or test_options.has("auto") or test_options.has("move"):
			mode = "play"
	map_id = str(test_options.get("map", next_map if next_map != "" else "old"))
	if Maps.index_of(map_id) < 0:
		push_warning("Кладбище: нет карты «%s», открываю старый погост" % map_id)
		map_id = "old"
	if mode == "base":
		_setup_base()
		return
	map = Maps.get_map(map_id)
	player = get_node_or_null("Player")
	hud = get_node_or_null("Hud")
	_enemies_root = _make_root("Enemies")
	_souls_root = _make_root("Souls")
	bolts_root = _make_root("Bolts")
	_fx_root = _make_root("Effects")
	_setup_camera()
	_setup_sounds()
	world = World.new()
	world.name = "World"
	add_child(world)
	world.build(map, _rng, str(test_options.get("fx", "1")) != "0")
	arena = world.arena
	abilities = Abilities.new()
	abilities.name = "Abilities"
	abilities.game = self
	add_child(abilities)
	abilities.slots = Save.slots().duplicate()
	if test_options.has("slots"):
		abilities.slots = Array(str(test_options["slots"]).split(".", false))
	for item in str(test_options.get("cast", "")).split(";", false):
		var pair: PackedStringArray = str(item).split(":")
		if pair.size() >= 2:
			_casts.append([pair[0], float(pair[1])])
	round_seconds = float(map["round"])
	if test_options.has("seconds"):
		round_seconds = float(test_options["seconds"])
	boss_time = float(test_options["boss"]) if test_options.has("boss") else round_seconds * 0.8
	_report_every = float(test_options.get("report", 0.0))
	_forced_levelup = float(test_options.get("levelup", 0.0))  # на этой секунде открыть окно прокачки (для снимков)
	_relic_timer = float(test_options.get("relic", maxf(RELIC_FIRST - 4.0 * Save.upgrade_level("luck"), 8.0)))
	hold_levelup = _forced_levelup > 0.0
	_quit_on_end = test_options.has("quit")
	auto = test_options.has("auto") or test_options.has("move")
	best_score = Save.record(map_id)
	skin_index = maxi(SKINS.find(Save.skin()), 0)
	if test_options.has("skin"):
		skin_index = maxi(SKINS.find(str(test_options["skin"])), 0)
	if player != null:
		player.game = self
		player.autopilot = str(test_options.get("move", ""))
		player.set_skin(SKINS[skin_index])
		player.set_lantern(bool(map["lights"]["hero_lantern"]))
	if hud != null:
		hud.game = self
	print("Кладбище готово: карта %s «%s», раунд %d с, босс %s на %d с, скин %s, сид %d" % [map_id, str(map["title"]), int(round_seconds), str(map["boss"]), int(boss_time), SKINS[skin_index], _rng.seed])
	var start_now := auto or mode == "play"
	next_map = ""
	next_state = ""
	if start_now:
		start_game()
	else:
		_enter_menu()


## Форпост: мир по карте «base», здания и стражники из gy_base.gd, герой ходит, табло показывает души и подсказку.
func _setup_base() -> void:
	next_map = ""
	next_state = ""
	map_id = "base"
	map = Maps.get_map("base")
	player = get_node_or_null("Player")
	hud = get_node_or_null("Hud")
	_enemies_root = _make_root("Enemies")
	_souls_root = _make_root("Souls")
	bolts_root = _make_root("Bolts")
	_fx_root = _make_root("Effects")
	_setup_camera()
	_setup_sounds()
	world = World.new()
	world.name = "World"
	add_child(world)
	world.build(map, _rng, str(test_options.get("fx", "1")) != "0")
	arena = world.arena
	base = Base.new()
	base.name = "Base"
	add_child(base)
	base.build(self, world, Save.fence_level())
	skin_index = maxi(SKINS.find(Save.skin()), 0)
	if player != null:
		player.game = self
		player.autopilot = str(test_options.get("move", ""))
		player.set_skin(SKINS[skin_index])
		player.set_lantern(false)
		player.global_position = Vector3(0, 0.95, -2.0)
		if test_options.has("at"):
			var at: PackedStringArray = str(test_options["at"]).split(":")
			if at.size() >= 2:
				player.global_position = Vector3(float(at[0]), 0.95, float(at[1]))
	if hud != null:
		hud.game = self
		hud.show_base(Save.souls())
	_menu_light.visible = false
	state = "base"
	_quit_on_end = test_options.has("quit")
	_shop_timer = 1.0 if test_options.has("shop") else 0.0
	print("Форпост готов: душ %d, укрепления %d, открыто карт %d" % [Save.souls(), Save.fence_level(), Save.data["unlocked"].size()])


func _parse_test_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if not str(arg).begins_with("--test-graveyard="):
			continue
		for item in str(arg).trim_prefix("--test-graveyard=").split(",", false):
			var pair: PackedStringArray = str(item).split(":", false, 1)
			test_options[pair[0].strip_edges()] = pair[1].strip_edges() if pair.size() > 1 else "1"
	if test_options.has("seed"):
		decor_seed = int(test_options["seed"])


func _make_root(root_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = root_name
	add_child(node)
	return node


# --- Камера, звуки ---

func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 50
	_camera.position = Vector3(0, 3, 6)
	add_child(_camera)
	_camera.current = true
	_menu_light = OmniLight3D.new()
	_menu_light.name = "MenuLight"
	_menu_light.light_color = Color("#ffd9a0")
	_menu_light.light_energy = 2.0
	_menu_light.omni_range = 7.0
	_menu_light.position = Vector3(1.8, 2.2, 2.6)
	add_child(_menu_light)


func _setup_sounds() -> void:
	for n in SOUND_NAMES:
		var path: String = SOUNDS + n + ".ogg"
		if not ResourceLoader.exists(path):
			continue
		var stream := AudioStreamPlayer.new()
		stream.stream = load(path)
		stream.max_polyphony = 3
		stream.volume_db = float(SOUND_VOLUME.get(n, 0.0))
		add_child(stream)
		_sounds[n] = stream


func play_sound(sound_name: String) -> void:
	if _sounds.has(sound_name):
		_sounds[sound_name].play()


## Один из нескольких похожих звуков (шаги): prefix0 … prefix(count-1).
func play_random(prefix: String, count: int) -> void:
	play_sound(prefix + str(_rng.randi_range(0, count - 1)))


## Общая коробка всех сеток модели (для gy_enemy.gd).
static func model_aabb(model: Node3D) -> AABB:
	return World.model_aabb(model)


# --- Искры ---

## Искры в точке попадания снаряда (зовёт gy_bolt.gd).
func spawn_sparks(pos: Vector3) -> void:
	if str(test_options.get("fx", "1")) == "0":
		return
	var sparks := Fx.sparks()
	_fx_root.add_child(sparks)
	sparks.global_position = pos + Vector3(0, 0.3, 0)
	if test_options.has("debug"):
		print("Искры: попадание в точке (%.1f, %.1f)" % [pos.x, pos.z])


## Взрыв искр цвета врага при его гибели; у босса втрое больше и крупнее.
func spawn_burst(pos: Vector3, color: Color, size: float) -> void:
	if str(test_options.get("fx", "1")) == "0":
		return
	var burst := Fx.sparks(color, int(14 * size), 1.0 + (size - 1.0) * 0.4)
	_fx_root.add_child(burst)
	burst.global_position = pos
	if test_options.has("debug"):
		print("Взрыв искр %s в точке (%.1f, %.1f)" % [color.to_html(false), pos.x, pos.z])


# --- Ход раунда ---

func _process(delta: float) -> void:
	world.tick(delta)
	if player != null:
		world.follow(player.global_position)
	if state == "menu":
		if player != null:
			player.rotation.y += delta * 0.7
		_update_camera(delta, true)
		return
	_update_camera(delta, false)
	if state == "base" or state == "shop":
		base.tick(delta)
		if _quit_on_end:
			# Самопроверка форпоста: выйти через seconds секунд.
			_end_timer += delta
			if _end_timer >= float(test_options.get("seconds", 5.0)):
				print("Форпост: стражников %d, нападающих %d, душ %d" % [base.guards.size(), base.attackers.size(), Save.souls()])
				get_tree().quit(0)
		if hud != null and state == "base":
			var spot: Dictionary = base.nearest_spot(player.global_position)
			hud.set_prompt("E — %s" % str(spot["title"]) if not spot.is_empty() else "")
		if _shop_timer > 0.0:
			_shop_timer -= delta
			if _shop_timer <= 0.0:
				if state == "base":
					open_shop(str(test_options["shop"]))
					if test_options.has("pick"):
						_shop_timer = 0.5  # самопроверка: через полсекунды выбрать строку pick
				else:
					shop_pick(int(test_options["pick"]))
		return
	if state == "won" or state == "over":
		if _quit_on_end:
			_end_timer += delta
			if _end_timer > 0.5:
				get_tree().quit(0)
		return
	if state != "playing":
		return
	elapsed += delta
	if _forced_levelup > 0.0 and elapsed >= _forced_levelup:
		_forced_levelup = 0.0
		_gain_xp(xp_needed - xp)
	abilities.tick(delta)
	for cast in _casts.duplicate():
		if elapsed >= float(cast[1]):
			_casts.erase(cast)
			abilities.cast(str(cast[0]))
	if hud != null:
		hud.set_cooldowns(abilities)
	_spawn(delta)
	_update_souls(delta)
	_update_relic(delta)
	if hud != null:
		hud.set_values(player.hp, player.max_hp, xp, xp_needed, level, maxf(round_seconds - elapsed, 0.0), kills, enemies.size(), best_score)
	if _report_every > 0.0:
		_report_timer += delta
		if _report_timer >= _report_every:
			_report_timer -= _report_every
			_report("[%d с]" % int(elapsed))
	if elapsed >= round_seconds:
		_win()


func _update_camera(delta: float, menu: bool) -> void:
	if player == null:
		return
	var target: Vector3
	var look: Vector3
	if menu:
		target = player.global_position + Vector3(0, 1.35, 4.3)
		look = player.global_position + Vector3(0, 0.55, 0)
	else:
		var zoom := float(test_options.get("zoom", 1.0)) * (1.3 if state == "base" or state == "shop" else 1.0)
		target = player.global_position + Vector3(0, 9.5, 6.0) * zoom
		look = player.global_position + Vector3(0, 0.5, 0)
	_camera.position = _camera.position.lerp(target, 1.0 - exp(-6.0 * delta))
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 2.0, 0.0)
		_camera.position += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake * 0.25
	_camera.look_at(look, Vector3.UP)


## Тряска камеры силой strength (0…1), гаснет за полсекунды.
func shake(strength: float) -> void:
	_shake = maxf(_shake, strength)


## Клавиша 1–4 ночью: включить способность из слота.
func cast_slot(index: int) -> void:
	if state != "playing" or abilities == null or index < 0 or index >= abilities.slots.size():
		return
	var id := str(abilities.slots[index])
	if not abilities.cast(id):
		play_sound("hover")


func _spawn(delta: float) -> void:
	var rate := (0.7 + elapsed / 35.0) * float(map["rate"]) * float(test_options.get("rate", 1.0))
	_spawn_budget += rate * delta
	while _spawn_budget >= 1.0:
		_spawn_budget -= 1.0
		if enemies.size() < MAX_ENEMIES:
			_spawn_enemy(_pick_kind())
	if not boss_spawned and elapsed >= boss_time:
		boss_spawned = true
		var boss := _spawn_enemy(str(map["boss"]))
		play_sound("boss")
		if hud != null:
			hud.show_banner("%s вышел из тьмы!" % boss.title)
		print("Босс %s вышел на %d с" % [boss.title, int(elapsed)])


## Вид следующего врага: по весам карты среди тех, чьё время (from) уже пришло.
func _pick_kind() -> String:
	var roster: Dictionary = map["enemies"]
	var total := 0.0
	for kind in roster:
		if elapsed >= float(roster[kind]["from"]):
			total += float(roster[kind]["weight"])
	var roll := _rng.randf_range(0.0, total)
	for kind in roster:
		if elapsed < float(roster[kind]["from"]):
			continue
		roll -= float(roster[kind]["weight"])
		if roll <= 0.0:
			return kind
	return roster.keys()[0] if not roster.is_empty() else "zombie"


func _spawn_enemy(kind: String, at: Vector3 = Vector3.INF) -> Node3D:
	var enemy := Enemy.new()
	var angle := _rng.randf_range(0, TAU)
	var radius := _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
	var pos := player.global_position + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
	if at != Vector3.INF:
		pos = at
	pos.x = clampf(pos.x, -arena.x + 1.5, arena.x - 1.5)
	pos.z = clampf(pos.z, -arena.y + 1.5, arena.y - 1.5)
	pos.y = 0.05
	var stats: Dictionary = ENEMY_KINDS[kind].duplicate()
	if not bool(stats.get("guard", false)):
		stats["hp"] = float(stats["hp"]) * float(map["tough"])
	enemy.setup(kind, stats, self)
	_enemies_root.add_child(enemy)
	enemy.global_position = pos
	enemies.append(enemy)
	if bool(stats.get("elite", false)) and not _seen_kinds.has(kind):
		_seen_kinds[kind] = true
		play_sound("elite")
		if hud != null:
			hud.show_banner("Новый враг: %s (+%d опыта)" % [str(stats["title"]), int(stats["xp"])])
		print("Новый враг: %s на %d с" % [str(stats["title"]), int(elapsed)])
	return enemy


func on_enemy_died(enemy: Node3D) -> void:
	enemies.erase(enemy)
	var pos := enemy.global_position
	var stats: Dictionary = ENEMY_KINDS[enemy.kind]
	var color := Color(str(stats.get("tint", DEATH_COLORS.get(str(stats.get("model", "zombie")), "#ffffff"))))
	spawn_burst(pos + Vector3(0, 0.6, 0), color, 3.0 if enemy.is_boss else 1.0)
	if enemy.base_target != Vector3.INF:
		play_sound("die_" + str(stats.get("model", "zombie")))  # нападающий на форпост: без душ и счёта
		return
	kills += 1
	_spawn_soul(pos, ceili(float(enemy.xp) * float(map["xp_mult"])), "soul")
	if enemy.is_boss:
		boss_killed = true
		_spawn_soul(pos + Vector3(1, 0, 0), 0, "pumpkin")
		play_sound("boss")
		if hud != null:
			hud.show_banner("%s повержен!" % enemy.title)
		print("Босс %s повержен на %d с" % [enemy.title, int(elapsed)])
	elif _rng.randf() < float(map["pumpkin_chance"]) + 0.03 * Save.upgrade_level("luck"):
		_spawn_soul(pos + Vector3(0.6, 0, 0), 0, "pumpkin")
	if enemy.is_boss:
		pass
	elif enemy.is_elite or enemy.is_guard:
		play_sound("die_elite")
	else:
		var model := str(stats.get("model", "zombie"))
		play_sound("die_" + ("zombie" if model == "character" else model))


func _spawn_soul(pos: Vector3, value: int, kind: String) -> void:
	var soul := Node3D.new()
	if kind == "pumpkin" and ResourceLoader.exists(MODELS + "pumpkinCarved.glb"):
		var model: Node3D = (load(MODELS + "pumpkinCarved.glb") as PackedScene).instantiate()
		model.scale = Vector3.ONE * 1.3
		soul.add_child(model)
	else:
		if _soul_material == null:
			_soul_material = StandardMaterial3D.new()
			_soul_material.albedo_color = Color("#7ff6ff")
			_soul_material.emission_enabled = true
			_soul_material.emission = Color("#4fd8ff")
			_soul_material.emission_energy_multiplier = 2.5
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.16
		sphere.height = 0.32
		mesh.mesh = sphere
		mesh.material_override = _soul_material
		soul.add_child(mesh)
	soul.set_meta("value", value)
	soul.set_meta("kind", kind)
	soul.set_meta("age", 0.0)
	soul.position = Vector3(pos.x, 0.45, pos.z)
	_souls_root.add_child(soul)
	souls.append(soul)


func _update_souls(delta: float) -> void:
	var player_pos := player.global_position
	for soul in souls.duplicate():
		var age := float(soul.get_meta("age")) + delta
		soul.set_meta("age", age)
		var to: Vector3 = player_pos - soul.global_position
		to.y = 0
		var dist: float = to.length()
		var kind := str(soul.get_meta("kind"))
		var reach: float = player.magnet if kind == "soul" else 1.6
		if abilities != null and abilities.pull_souls and kind == "soul":
			reach = INF
		if dist < reach and dist > 0.001:
			soul.global_position += to / dist * minf(9.0 * delta, dist)
		soul.position.y = 0.45 + sin(age * 4.0) * 0.1
		if dist < 0.8:
			_collect(soul)
		elif age > SOUL_LIFETIME:
			souls.erase(soul)
			soul.queue_free()


func _collect(soul: Node3D) -> void:
	souls.erase(soul)
	var kind := str(soul.get_meta("kind"))
	if kind == "pumpkin":
		player.heal(25.0)
		play_sound("heal")
		print("Тыква: лечение, здоровье %d" % int(player.hp))
	else:
		_gain_xp(int(soul.get_meta("value")))
		play_sound("soul")
	soul.queue_free()


# --- Реликвия: редкий бонус на пол-шкалы опыта под охраной быстрого скелета ---

func _update_relic(delta: float) -> void:
	if relic == null:
		_relic_timer -= delta
		if _relic_timer <= 0.0:
			_spawn_relic()
		if hud != null:
			hud.set_relic(false, 0.0, 0.0)
		return
	_relic_age += delta
	_relic_orb.position.y = 1.25 + sin(_relic_age * 2.5) * 0.12
	_relic_orb.rotation.y += delta * 1.5
	_relic_light.light_energy = 1.3 + sin(_relic_age * 5.0) * 0.35
	if _relic_age > RELIC_LIFETIME - 5.0:
		_relic_orb.visible = fmod(_relic_age, 0.4) < 0.25
	var to := player.global_position - relic.global_position
	to.y = 0
	if hud != null:
		hud.set_relic(true, atan2(-to.z, -to.x), to.length())
	if to.length() < 1.3:
		_take_relic()
	elif _relic_age > RELIC_LIFETIME:
		print("Реликвия исчезла")
		_remove_relic()


## Реликвия ложится в 12–26 м от героя, не на украшения и не в лужу; рядом появляется Сторож и кружит вокруг неё.
func _spawn_relic() -> void:
	var player_p := Vector2(player.global_position.x, player.global_position.z)
	var spot := Vector2.INF
	for attempt in 60:
		var p := Vector2(_rng.randf_range(-arena.x + 4.0, arena.x - 4.0), _rng.randf_range(-arena.y + 4.0, arena.y - 4.0))
		var d := p.distance_to(player_p)
		if d < 12.0 or d > 26.0:
			continue
		if world.is_free(p, 2.2):
			spot = p
			break
	if spot == Vector2.INF:
		_relic_timer = 5.0
		return
	relic = Node3D.new()
	relic.name = "Relic"
	if ResourceLoader.exists(MODELS + "altarStone.glb"):
		var altar: Node3D = (load(MODELS + "altarStone.glb") as PackedScene).instantiate()
		altar.scale = Vector3.ONE * 1.2
		relic.add_child(altar)
	var orb_material := StandardMaterial3D.new()
	orb_material.albedo_color = RELIC_COLOR
	orb_material.emission_enabled = true
	orb_material.emission = RELIC_COLOR
	orb_material.emission_energy_multiplier = 3.0
	_relic_orb = MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.6, 0.8, 0.6)
	_relic_orb.mesh = prism
	_relic_orb.material_override = orb_material
	_relic_orb.position = Vector3(0, 1.25, 0)
	relic.add_child(_relic_orb)
	_relic_light = OmniLight3D.new()
	_relic_light.light_color = RELIC_COLOR
	_relic_light.light_energy = 1.3
	_relic_light.omni_range = 7.0
	_relic_light.position = Vector3(0, 1.6, 0)
	relic.add_child(_relic_light)
	_souls_root.add_child(relic)
	relic.global_position = Vector3(spot.x, 0, spot.y)
	_relic_age = 0.0
	var guard_pos := Vector3(spot.x, 0.05, spot.y) + Vector3(2.8, 0, 0)
	_guard = _spawn_enemy("guard", guard_pos)
	_guard.guard_target = relic
	play_sound("alert")
	if hud != null:
		hud.show_banner("Реликвия! Пол-шкалы опыта, но её сторожит Сторож: удар отнимает полжизни")
	print("Реликвия появилась в (%.0f, %.0f) на %d с, сторож рядом" % [spot.x, spot.y, int(elapsed)])


func _take_relic() -> void:
	var bonus := ceili(float(xp_needed) * 0.5)
	spawn_burst(relic.global_position + Vector3(0, 1.2, 0), RELIC_COLOR, 2.0)
	play_sound("relic")
	if hud != null:
		hud.show_banner("Реликвия взята: +%d опыта!" % bonus)
	print("Реликвия взята на %d с: +%d опыта" % [int(elapsed), bonus])
	_remove_relic()
	_gain_xp(bonus)


func _remove_relic() -> void:
	if _guard != null and is_instance_valid(_guard):
		_guard.guard_target = null  # сторож остаётся и гонится за героем, но уже медленнее героя
		_guard.speed = 4.2
		if hud != null:
			hud.show_banner("Сторож гонится за тобой: убегай или стреляй!")
	_guard = null
	relic.queue_free()
	relic = null
	_relic_timer = RELIC_EVERY
	if hud != null:
		hud.set_relic(false, 0.0, 0.0)


# --- Опыт и прокачка ---

func _gain_xp(amount: int) -> void:
	xp += amount
	if xp >= xp_needed:
		xp -= xp_needed
		level += 1
		xp_needed = 4 + level * 2
		_level_up()


func _level_up() -> void:
	state = "levelup"
	var pool := UPGRADES.duplicate()
	pool.shuffle()
	_levelup_options = pool.slice(0, 3)
	recommended_index = _recommend(_levelup_options)
	get_tree().paused = true
	play_sound("levelup")
	if hud != null:
		hud.show_levelup(_levelup_options, level, recommended_index)
	print("Новый уровень %d: выбор из %s, рекомендуется %s" % [level, ", ".join(_levelup_options.map(func(u): return str(u["title"]))), str(_levelup_options[recommended_index]["title"])])


## Совет игроку: что из предложенного полезнее прямо сейчас. Мало здоровья — лечение и восстановление,
## мало снарядов — ещё снаряд, иначе урон и скорострельность; выбрать всё равно можно что угодно.
func _recommend(options: Array) -> int:
	var hp_part: float = player.hp / maxf(player.max_hp, 1.0)
	var best_index := 0
	var best := -1.0
	for i in options.size():
		var option: Dictionary = options[i]
		var score_value := 1.0
		match str(option["id"]):
			"health":
				score_value = 3.5 if hp_part < 0.5 else (1.6 if level >= 5 else 0.9)
			"regen":
				score_value = 2.6 if hp_part < 0.6 else 1.1
			"multishot":
				score_value = 2.4 if player.projectiles < 3 else 1.3
			"damage":
				score_value = 1.8 if level >= 3 else 1.4
			"rate":
				score_value = 1.7
			"pierce":
				score_value = 1.5 if player.projectiles >= 2 else 0.8
			"speed":
				score_value = 1.2 if player.speed < 6.5 else 0.6
			"magnet":
				score_value = 1.4 if souls.size() > 6 else 0.7
		if score_value > best:
			best = score_value
			best_index = i
	return best_index


func choose_upgrade(index: int) -> void:
	if state != "levelup" or index < 0 or index >= _levelup_options.size():
		return
	var upgrade: Dictionary = _levelup_options[index]
	match str(upgrade["id"]):
		"damage":
			player.damage *= 1.3
		"rate":
			player.fire_interval /= 1.25
		"multishot":
			player.projectiles += 1
		"speed":
			player.speed *= 1.15
		"health":
			player.max_hp += 25.0
			player.hp = player.max_hp
		"magnet":
			player.magnet *= 1.6
		"pierce":
			player.pierce += 1
		"regen":
			player.regen += 1.0
	print("Прокачка: %s" % str(upgrade["title"]))
	play_sound("select")
	if hud != null:
		hud.hide_levelup()
	get_tree().paused = false
	state = "playing"


# --- Конец раунда ---

func score() -> int:
	return kills * 10 + (level - 1) * 50 + int(elapsed)


## Души за ночь: по одной за убитого, по пять за уровень, 40 за босса, за победу 80 плюс 30 за номер карты;
## Жатва на алтаре добавляет по 10 % за уровень.
func souls_for_night(won: bool) -> int:
	var amount := kills + (level - 1) * 5 + (40 if boss_killed else 0)
	if won:
		amount += 80 + 30 * Maps.index_of(map_id)
	return ceili(float(amount) * (1.0 + 0.1 * Save.upgrade_level("harvest")))


func _finish_round(won: bool) -> void:
	state = "won" if won else "over"
	var s := score()
	var new_best := Save.set_record(map_id, s, won)
	best_score = Save.record(map_id)
	souls_earned = souls_for_night(won)
	Save.add_souls(souls_earned)
	Save.add_stat("nights", 1)
	Save.add_stat("kills", kills)
	if won:
		Save.add_stat("wins", 1)
	play_sound("win" if won else "over")
	if hud != null:
		var head := "Ты выжил! %s пройден%s" % [str(map["title"]), " — новый рекорд!" if new_best else ""] if won else "Тебя одолели%s" % (" — но это новый рекорд!" if new_best else "")
		hud.show_message("%s\nСчёт %d · рекорд %d\n✦ Души: +%d (всего %d)\nEnter — в форпост · R — ещё раз" % [head, s, best_score, souls_earned, Save.souls()])
	_report("итог (%s), душ +%d" % ["победа" if won else "поражение", souls_earned])


func _win() -> void:
	_finish_round(true)


func game_over() -> void:
	if state != "playing":
		return
	_finish_round(false)


func _report(label: String) -> void:
	print("Кладбище %s: карта %s, здоровье %d/%d, уровень %d (опыт %d/%d), врагов %d, убито %d, душ на земле %d, счёт %d" % [label,
		map_id, int(player.hp), int(player.max_hp), level, xp, xp_needed, enemies.size(), kills, souls.size(), score()])


## R после конца: та же карта заново, сразу в бой.
func restart() -> void:
	get_tree().paused = false
	next_map = map_id
	next_state = "play"
	print("Перезапуск карты %s" % map_id)
	get_tree().reload_current_scene()


## Enter после конца или в меню: в форпост.
func to_base() -> void:
	get_tree().paused = false
	next_map = ""
	next_state = "base"
	print("В форпост")
	get_tree().reload_current_scene()


## Из ворот форпоста: в ночь на выбранную карту.
func go_to_map(id: String) -> void:
	next_map = id
	next_state = "play"
	print("В путь: карта %s" % id)
	get_tree().reload_current_scene()


# --- Меню ---

func _enter_menu() -> void:
	state = "menu"
	if hud != null:
		hud.show_menu(Save.souls(), Save.stat("nights"))


func start_game() -> void:
	if state != "menu" and state != "playing":
		return
	state = "playing"
	player.rotation.y = 0.0
	_apply_permanent()
	if _menu_light != null:
		_menu_light.visible = false
	if hud != null:
		hud.hide_menu()
		hud.set_map_title(str(map["title"]))
		hud.set_souls(Save.souls())
		hud.show_slots(abilities.slots)
	play_sound("click")
	print("Кладбище: раунд начался, карта %s, герой %s, щит %d, слоты %s" % [map_id, SKINS[skin_index], int(player.shield), ", ".join(abilities.slots)])


## Постоянная прокачка с Алтаря душ и щит от укреплений действуют с начала каждой ночи.
func _apply_permanent() -> void:
	player.max_hp += 10.0 * Save.upgrade_level("body")
	player.hp = player.max_hp
	player.damage *= 1.0 + 0.08 * Save.upgrade_level("arrows")
	player.speed *= 1.0 + 0.05 * Save.upgrade_level("legs")
	player.fire_interval /= 1.0 + 0.06 * Save.upgrade_level("hands")
	player.magnet *= 1.0 + 0.2 * Save.upgrade_level("greed")
	player.shield = FENCE_SHIELD * Save.fence_level()


# --- Форпост: здания и их окна ---

## E у здания: открыть его окно (список строк, Enter выбирает).
func interact() -> void:
	if state != "base" or base == null:
		return
	var spot: Dictionary = base.nearest_spot(player.global_position)
	if spot.is_empty():
		return
	open_shop(str(spot["id"]))


func open_shop(id: String) -> void:
	shop_id = id
	state = "shop"
	play_sound("select")
	_refresh_shop(0)
	print("Открыто окно: %s" % id)


func _refresh_shop(selected: int) -> void:
	shop_rows = _shop_rows(shop_id)
	if hud != null:
		hud.set_souls(Save.souls())
		hud.show_shop(_shop_title(shop_id), shop_rows, _shop_hint(shop_id), selected)


func close_shop() -> void:
	if state != "shop":
		return
	state = "base"
	play_sound("click")
	if hud != null:
		hud.hide_shop()


func _shop_title(id: String) -> String:
	match id:
		"altar": return "Алтарь душ — постоянная прокачка"
		"gate": return "Ворота — куда идём этой ночью?"
		"camp": return "Костёр — кто пойдёт в ночь?"
		"home": return "Дом сторожа — летопись"
		"fence": return "Башня — укрепления форпоста"
		"forge": return "Кузница — способности (слотов: %d)" % MAX_SLOTS
	return id


func _shop_hint(id: String) -> String:
	match id:
		"gate": return "↑ ↓ выбрать · Enter — в путь или открыть за души · Esc — назад"
		"home": return "Esc — назад"
		"forge": return "↑ ↓ выбрать · Enter — купить, надеть или снять · Esc — назад · ночью клавиши 1–4"
	return "↑ ↓ выбрать · Enter — купить · Esc — назад"


## Строки окна: title, text, right (цена/уровень), locked (серым), action (что делает Enter).
func _shop_rows(id: String) -> Array:
	var rows: Array = []
	var souls := Save.souls()
	match id:
		"altar":
			for u in PERMANENT:
				var level := Save.upgrade_level(str(u["id"]))
				var maxed := level >= int(u["max"])
				var cost := int(u["cost"]) * (level + 1)
				rows.append({"id": u["id"], "title": "%s  %s" % [str(u["title"]), _dots(level, int(u["max"]))], "text": str(u["text"]),
					"right": "максимум" if maxed else "✦ %d" % cost, "locked": maxed or souls < cost, "action": "" if maxed else "buy"})
		"gate":
			for map_entry_id in Maps.ids():
				var m := Maps.get_map(map_entry_id)
				var unlocked := Save.is_unlocked(map_entry_id)
				var cost := Maps.unlock_cost(map_entry_id)
				var record := Save.record(map_entry_id)
				var right := ("✓ пройдена" if Save.is_won(map_entry_id) else "открыта") if unlocked else "открыть: ✦ %d" % cost
				var text := str(m["subtitle"]).split(".")[0] + ("  ·  рекорд %d" % record if record > 0 else "")
				rows.append({"id": map_entry_id, "title": "%d. %s" % [Maps.index_of(map_entry_id) + 1, str(m["title"])], "text": text,
					"right": right, "locked": not unlocked and souls < cost, "action": "play" if unlocked else "unlock"})
		"camp":
			for skin in SKINS:
				rows.append({"id": skin, "title": str(SKIN_TITLES.get(skin, skin)), "text": "", "right": "выбран" if skin == SKINS[skin_index] else "", "locked": false, "action": "skin"})
		"home":
			rows.append({"id": "", "title": "Ночей: %d · побед: %d · убито нечисти: %d · душ собрано: %d" % [Save.stat("nights"), Save.stat("wins"), Save.stat("kills"), Save.stat("souls_total")],
				"text": "", "right": "", "locked": false, "action": ""})
			for map_entry_id in Maps.ids():
				var record := Save.record(map_entry_id)
				rows.append({"id": map_entry_id, "title": "%d. %s" % [Maps.index_of(map_entry_id) + 1, Maps.title_of(map_entry_id)], "text": "",
					"right": ("рекорд %d" % record if record > 0 else "—") + ("  ✓" if Save.is_won(map_entry_id) else ""), "locked": false, "action": ""})
		"forge":
			var slots := Save.slots()
			for ability_id in Abilities.ORDER:
				var a: Dictionary = Abilities.ABILITIES[ability_id]
				var owned: bool = Save.abilities().has(ability_id)
				var slot := slots.find(ability_id)
				var right := ("в слоте %d" % (slot + 1)) if slot >= 0 else ("надеть" if owned else "✦ %d" % int(a["cost"]))
				rows.append({"id": ability_id, "title": str(a["title"]), "text": str(a["text"]),
					"right": "%d с · %s" % [int(a["cooldown"]), right], "locked": not owned and souls < int(a["cost"]), "action": "slot" if owned else "ability"})
		"fence":
			var level := Save.fence_level()
			var maxed := level >= FENCE_COST.size()
			var cost := 0 if maxed else int(FENCE_COST[level])
			rows.append({"id": "fence", "title": "Укрепления  %s" % _dots(level, FENCE_COST.size()), "text": "Щит %d здоровья в начале каждой ночи, стражников %d" % [int(FENCE_SHIELD * level), 4 + 2 * maxi(level - 1, 0)],
				"right": "максимум" if maxed else "✦ %d" % cost, "locked": maxed or souls < cost, "action": "" if maxed else "buy"})
	return rows


func _dots(level: int, max_level: int) -> String:
	var text := ""
	for i in max_level:
		text += "●" if i < level else "○"
	return text


## Enter в окне: купить, выбрать героя или пойти в ночь.
func shop_pick(index: int) -> void:
	if state != "shop" or index < 0 or index >= shop_rows.size():
		return
	var row: Dictionary = shop_rows[index]
	match str(row["action"]):
		"buy":
			if shop_id == "fence":
				var level := Save.fence_level()
				if Save.spend(int(FENCE_COST[level])):
					Save.set_fence_level(level + 1)
					play_sound("levelup")
					print("Куплено: укрепления %d" % (level + 1))
				else:
					play_sound("hover")
			else:
				for u in PERMANENT:
					if str(u["id"]) != str(row["id"]):
						continue
					var level := Save.upgrade_level(str(u["id"]))
					if Save.spend(int(u["cost"]) * (level + 1)):
						Save.set_upgrade_level(str(u["id"]), level + 1)
						play_sound("levelup")
						print("Куплено: %s %d" % [str(u["title"]), level + 1])
					else:
						play_sound("hover")
			_refresh_shop(index)
		"unlock":
			if Save.spend(Maps.unlock_cost(str(row["id"]))):
				Save.unlock(str(row["id"]))
				play_sound("relic")
				print("Открыта карта %s" % str(row["id"]))
				if hud != null:
					hud.show_banner("Открыт %s!" % Maps.title_of(str(row["id"])))
			else:
				play_sound("hover")
			_refresh_shop(index)
		"play":
			get_tree().paused = false
			go_to_map(str(row["id"]))
		"ability":
			var a: Dictionary = Abilities.ABILITIES[str(row["id"])]
			if Save.spend(int(a["cost"])):
				Save.unlock_ability(str(row["id"]))
				var slots := Save.slots()
				if slots.size() < MAX_SLOTS:
					slots.append(str(row["id"]))
					Save.set_slots(slots)
				play_sound("levelup")
				print("Куплена способность %s" % str(row["id"]))
			else:
				play_sound("hover")
			_refresh_shop(index)
		"slot":
			var slots := Save.slots()
			if slots.has(str(row["id"])):
				slots.erase(str(row["id"]))
				play_sound("click")
			elif slots.size() < MAX_SLOTS:
				slots.append(str(row["id"]))
				play_sound("select")
			else:
				play_sound("hover")
				if hud != null:
					hud.show_banner("Все %d слота заняты: сними что-нибудь" % MAX_SLOTS)
			Save.set_slots(slots)
			_refresh_shop(index)
		"skin":
			skin_index = maxi(SKINS.find(str(row["id"])), 0)
			player.set_skin(SKINS[skin_index])
			Save.set_skin(SKINS[skin_index])
			play_sound("click")
			_refresh_shop(index)
		_:
			play_sound("hover")
