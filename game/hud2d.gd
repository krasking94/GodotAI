extends CanvasLayer

## Надписи поверх игры (2D-пример): счётчик монет слева сверху и большое сообщение посередине экрана
## (его показывает солнце-цель через show_message). Надписи создаются кодом, без сцены.

const Coin := preload("res://game/coin2d.gd")
const COIN_ICON := "res://assets/kenney/platformer/hudCoin.png"  # если картинки нет, остаётся только текст

var _coins_label: Label
var _message: Label


func _ready() -> void:
	_coins_label = Label.new()
	_coins_label.position = Vector2(16.0, 10.0)
	if ResourceLoader.exists(COIN_ICON):
		var icon := TextureRect.new()
		icon.texture = load(COIN_ICON)
		icon.position = Vector2(12.0, 8.0)
		icon.scale = Vector2(0.3, 0.3)
		add_child(icon)
		_coins_label.position.x = 54.0
	_coins_label.add_theme_font_size_override("font_size", 28)
	_coins_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_coins_label.add_theme_constant_override("outline_size", 6)
	add_child(_coins_label)
	_message = Label.new()
	_message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # на весь экран, текст по центру
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message.add_theme_font_size_override("font_size", 56)
	_message.add_theme_color_override("font_outline_color", Color("#7a4a00"))
	_message.add_theme_constant_override("outline_size", 10)
	_message.visible = false
	add_child(_message)


func _process(_delta: float) -> void:
	_coins_label.text = "Монеты: %d / %d" % [Coin.collected, Coin.total]


func show_message(text: String) -> void:
	_message.text = text
	_message.visible = true
	print("Надпись на экране: %s" % text)
