extends CanvasLayer

## Надписи поверх игры и правила раунда (2D-пример): счётчик монет со значком, сердечки-жизни, таймер,
## большое сообщение посередине (победа, конец игры), звуки из assets/kenney/platformer/sounds
## (jump, coin, hurt, stomp, win, over; если файла нет, звука просто не будет) и перезапуск по R
## (после победы или конца игры ещё и по Enter). Надписи создаются кодом, без сцены.
## Другие скрипты находят узел по имени «Hud»: coin2d.gd → add_coin(), персонаж → play_sound("jump")
## и lose_life() при ранении, sungoal2d.gd → win().

const Coin := preload("res://game/coin2d.gd")
const ASSETS := "res://assets/kenney/platformer/"
const SOUND_NAMES := ["jump", "coin", "hurt", "stomp", "win", "over"]

@export var max_lives := 3

var lives := 3
var elapsed := 0.0
var state := "playing"  # playing, won, over

var _coins_label: Label
var _lives_label: Label
var _time_label: Label
var _message: Label
var _hearts: Array = []
var _heart_full: Texture2D
var _heart_empty: Texture2D
var _sounds := {}


func _ready() -> void:
	lives = max_lives
	_coins_label = _make_label(28)
	_coins_label.position = Vector2(16.0, 10.0)
	if ResourceLoader.exists(ASSETS + "hudCoin.png"):
		var icon := TextureRect.new()
		icon.texture = load(ASSETS + "hudCoin.png")
		icon.position = Vector2(12.0, 8.0)
		icon.scale = Vector2(0.3, 0.3)
		add_child(icon)
		_coins_label.position.x = 54.0
	add_child(_coins_label)
	if ResourceLoader.exists(ASSETS + "hudHeart_full.png") and ResourceLoader.exists(ASSETS + "hudHeart_empty.png"):
		_heart_full = load(ASSETS + "hudHeart_full.png")
		_heart_empty = load(ASSETS + "hudHeart_empty.png")
		for i in max_lives:
			var heart := TextureRect.new()
			heart.position = Vector2(300.0 + i * 42.0, 6.0)
			heart.scale = Vector2(0.3, 0.3)
			add_child(heart)
			_hearts.append(heart)
	else:
		_lives_label = _make_label(28)
		_lives_label.position = Vector2(300.0, 10.0)
		add_child(_lives_label)
	_update_hearts()
	_time_label = _make_label(28)
	_time_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_time_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_time_label.offset_right = -16.0
	_time_label.offset_top = 10.0
	add_child(_time_label)
	_message = _make_label(56)
	_message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # на весь экран, текст по центру
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message.add_theme_color_override("font_outline_color", Color("#7a4a00"))
	_message.add_theme_constant_override("outline_size", 10)
	_message.visible = false
	add_child(_message)
	for n in SOUND_NAMES:
		var path: String = ASSETS + "sounds/" + n + ".ogg"
		if ResourceLoader.exists(path):
			var player := AudioStreamPlayer.new()
			player.stream = load(path)
			add_child(player)
			_sounds[n] = player


func _make_label(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	return label


func _process(delta: float) -> void:
	if state == "playing":
		elapsed += delta
	_coins_label.text = "Монеты: %d / %d" % [Coin.collected, Coin.total]
	_time_label.text = "Время: %d с" % int(elapsed)
	if state != "playing" and Input.is_action_just_pressed("ui_accept"):
		restart()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		restart()


func _update_hearts() -> void:
	for i in _hearts.size():
		_hearts[i].texture = _heart_full if i < lives else _heart_empty
	if _lives_label != null:
		_lives_label.text = "Жизни: %d" % lives


func play_sound(sound_name: String) -> void:
	if _sounds.has(sound_name):
		_sounds[sound_name].play()


func add_coin() -> void:
	play_sound("coin")


## Отнимает жизнь; возвращает true, если жизни кончились (конец игры).
func lose_life() -> bool:
	if state != "playing":
		return state == "over"
	lives = maxi(lives - 1, 0)
	_update_hearts()
	print("Жизни: %d" % lives)
	if lives == 0:
		state = "over"
		play_sound("over")
		show_message("Игра окончена\nEnter или R: заново")
		return true
	play_sound("hurt")
	return false


func win() -> void:
	if state != "playing":
		return
	state = "won"
	play_sound("win")
	show_message("Ты добрался до солнца за %d с!\nR: ещё раз" % int(elapsed))


func show_message(text: String) -> void:
	_message.text = text
	_message.visible = true
	print("Надпись на экране: %s" % text.replace("\n", " "))


func restart() -> void:
	Coin.collected = 0
	Coin.total = 0
	print("Перезапуск уровня")
	get_tree().reload_current_scene()
