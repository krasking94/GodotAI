extends CanvasLayer

## Табло «Кладбища»: полоса здоровья, таймер, уровень, убитые, рекорд, полоса опыта внизу, красная вспышка
## при ударе, большие надписи (победа, поражение), окно прокачки (три карточки с рисованными значками и пометкой
## «Рекомендуется»: клавиши 1 2 3, стрелки и Enter или мышь) и стартовое меню
## (← → скин, Enter — начать). Работает и на паузе (process_mode ALWAYS): окно прокачки показывается,
## когда игра стоит. Все клавиши меню, прокачки и R обрабатываются здесь и передаются в gy_game.gd.

var game: Node = null

var _hp_bar: ProgressBar
var _hp_label: Label
var _xp_bar: ProgressBar
var _time_label: Label
var _level_label: Label
var _kills_label: Label
var _best_label: Label
var _message: Label
var _banner: Label
var _banner_timer := 0.0
var _flash_rect: ColorRect
var _levelup_panel: PanelContainer
var _levelup_title: Label
var _levelup_cards: Array = []  # [PanelContainer, UpgradeIcon, Label заголовок, Label описание, Label «Рекомендуется»]
var _levelup_focus := 0
var _levelup_count := 3
var _menu_panel: PanelContainer
var _menu_skin: Label
var _menu_best: Label
var _auto_timer := 0.0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1, 0, 0, 0)
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_rect)
	_hp_bar = _make_bar(Color("#c62828"), Color("#2a0d0d"))
	_hp_bar.position = Vector2(16, 14)
	_hp_bar.size = Vector2(280, 26)
	add_child(_hp_bar)
	_hp_label = _make_label(18)
	_hp_label.position = Vector2(26, 15)
	add_child(_hp_label)
	_time_label = _make_label(40)
	_time_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_time_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_time_label.offset_top = 8
	add_child(_time_label)
	_level_label = _make_label(24)
	_level_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_level_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_level_label.offset_right = -16
	_level_label.offset_top = 10
	add_child(_level_label)
	_kills_label = _make_label(22)
	_kills_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_kills_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_kills_label.offset_right = -16
	_kills_label.offset_top = 44
	add_child(_kills_label)
	_best_label = _make_label(18)
	_best_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_best_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_best_label.offset_right = -16
	_best_label.offset_top = 76
	add_child(_best_label)
	_xp_bar = _make_bar(Color("#4fd8ff"), Color("#0b1a24"))
	_xp_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_xp_bar.offset_left = 16
	_xp_bar.offset_right = -16
	_xp_bar.offset_top = -30
	_xp_bar.offset_bottom = -12
	add_child(_xp_bar)
	_banner = _make_label(34)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = 64
	_banner.add_theme_color_override("font_color", Color("#ffb347"))
	_banner.visible = false
	add_child(_banner)
	_message = _make_label(52)
	_message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message.visible = false
	add_child(_message)
	_build_levelup()
	_build_menu()


func _make_label(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_bar(fill: Color, back: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0
	bar.max_value = 1
	bar.value = 1
	var fill_box := StyleBoxFlat.new()
	fill_box.bg_color = fill
	fill_box.set_corner_radius_all(4)
	var back_box := StyleBoxFlat.new()
	back_box.bg_color = back
	back_box.set_corner_radius_all(4)
	back_box.border_color = Color(1, 1, 1, 0.35)
	back_box.set_border_width_all(1)
	bar.add_theme_stylebox_override("fill", fill_box)
	bar.add_theme_stylebox_override("background", back_box)
	return bar


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.03, 0.04, 0.08, 0.9)
	box.border_color = Color("#ffb347")
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", box)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.visible = false
	return panel


const UPGRADE_COLORS := {"damage": "#ff6b4a", "rate": "#ffd24a", "multishot": "#ffa84a", "speed": "#4ad0ff",
	"health": "#ff4a6e", "magnet": "#c07aff", "pierce": "#9fe34a", "regen": "#4aff9a"}


## Значок прокачки, нарисованный кодом (меч, молния, сердце и т. д.), чтобы не тащить картинки.
class UpgradeIcon extends Control:
	var kind := ""
	var color := Color.WHITE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color(color, 0.16))
		draw_arc(c, r - 1.5, 0.0, TAU, 48, color, 2.5, true)
		var one := PackedColorArray([color])
		match kind:
			"damage":
				draw_line(c + Vector2(-r * 0.4, r * 0.4), c + Vector2(r * 0.45, -r * 0.45), color, 6.0, true)
				draw_line(c + Vector2(-r * 0.5, r * 0.1), c + Vector2(-r * 0.1, r * 0.5), color, 5.0, true)
				draw_line(c + Vector2(-r * 0.4, r * 0.4), c + Vector2(-r * 0.62, r * 0.62), color, 8.0, true)
			"rate":
				draw_polyline(PackedVector2Array([c + Vector2(r * 0.15, -r * 0.62), c + Vector2(-r * 0.3, r * 0.05),
					c + Vector2(r * 0.08, r * 0.05), c + Vector2(-r * 0.15, r * 0.62)]), color, 5.0, true)
			"multishot":
				for i in 3:
					draw_circle(c + Vector2((i - 1) * r * 0.42, -absf(i - 1) * r * 0.18 + r * 0.05), r * 0.17, color)
			"speed":
				for i in 3:
					draw_line(c + Vector2(-r * 0.6, (i - 1) * r * 0.3), c + Vector2(r * (0.1 if i != 1 else 0.35), (i - 1) * r * 0.3), color, 5.0, true)
				draw_polygon(PackedVector2Array([c + Vector2(r * 0.35, -r * 0.28), c + Vector2(r * 0.7, 0.0), c + Vector2(r * 0.35, r * 0.28)]), one)
			"health":
				draw_circle(c + Vector2(-r * 0.26, -r * 0.18), r * 0.3, color)
				draw_circle(c + Vector2(r * 0.26, -r * 0.18), r * 0.3, color)
				draw_polygon(PackedVector2Array([c + Vector2(-r * 0.54, -r * 0.05), c + Vector2(r * 0.54, -r * 0.05), c + Vector2(0.0, r * 0.58)]), one)
			"magnet":
				draw_arc(c + Vector2(0.0, -r * 0.05), r * 0.4, PI, TAU, 24, color, 8.0, true)
				draw_line(c + Vector2(-r * 0.4, -r * 0.05), c + Vector2(-r * 0.4, r * 0.45), color, 8.0, true)
				draw_line(c + Vector2(r * 0.4, -r * 0.05), c + Vector2(r * 0.4, r * 0.45), color, 8.0, true)
			"pierce":
				draw_arc(c, r * 0.3, 0.0, TAU, 24, color, 3.0, true)
				draw_line(c + Vector2(-r * 0.68, 0.0), c + Vector2(r * 0.5, 0.0), color, 4.0, true)
				draw_polygon(PackedVector2Array([c + Vector2(r * 0.45, -r * 0.2), c + Vector2(r * 0.72, 0.0), c + Vector2(r * 0.45, r * 0.2)]), one)
			"regen":
				draw_rect(Rect2(c + Vector2(-r * 0.13, -r * 0.52), Vector2(r * 0.26, r * 1.04)), color)
				draw_rect(Rect2(c + Vector2(-r * 0.52, -r * 0.13), Vector2(r * 1.04, r * 0.26)), color)
			_:
				draw_circle(c, r * 0.3, color)


func _card_style(color: Color, focused: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.10, 0.11, 0.17, 0.98) if focused else Color(0.06, 0.07, 0.11, 0.96)
	box.border_color = color if focused else Color(color, 0.45)
	box.set_border_width_all(4 if focused else 2)
	box.set_corner_radius_all(12)
	box.set_content_margin_all(14)
	return box


func _build_levelup() -> void:
	_levelup_panel = _panel()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_levelup_title = _make_label(30)
	_levelup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_levelup_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	for i in 3:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(236, 300)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and game != null:
				game.choose_upgrade(i))
		card.mouse_entered.connect(func(): _set_levelup_focus(i))
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 8)
		var key := _make_label(18)
		key.text = "%d" % (i + 1)
		key.modulate = Color(1, 1, 1, 0.6)
		inner.add_child(key)
		var icon := UpgradeIcon.new()
		icon.custom_minimum_size = Vector2(84, 84)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(icon)
		var title := _make_label(24)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inner.add_child(title)
		var text := _make_label(17)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.modulate = Color(1, 1, 1, 0.85)
		text.size_flags_vertical = Control.SIZE_EXPAND_FILL
		inner.add_child(text)
		var badge := _make_label(16)
		badge.text = "★ Рекомендуется"
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_color_override("font_color", Color("#ffd24a"))
		inner.add_child(badge)
		card.add_child(inner)
		row.add_child(card)
		_levelup_cards.append([card, icon, title, text, badge])
	column.add_child(row)
	var hint := _make_label(16)
	hint.text = "1 2 3, стрелки и Enter или щелчок мышью"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.6)
	column.add_child(hint)
	_levelup_panel.add_child(column)
	add_child(_levelup_panel)


func _set_levelup_focus(index: int) -> void:
	if _levelup_count <= 0:
		return
	_levelup_focus = wrapi(index, 0, _levelup_count)
	for i in _levelup_cards.size():
		var card: PanelContainer = _levelup_cards[i][0]
		var icon: UpgradeIcon = _levelup_cards[i][1]
		card.add_theme_stylebox_override("panel", _card_style(icon.color, i == _levelup_focus))


func _build_menu() -> void:
	_menu_panel = _panel()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	var title := _make_label(54)
	title.text = "КЛАДБИЩЕ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("#ffb347"))
	column.add_child(title)
	var subtitle := _make_label(20)
	subtitle.text = "Продержись три минуты против орды нежити"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)
	_menu_skin = _make_label(26)
	_menu_skin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_menu_skin)
	var hint := _make_label(18)
	hint.text = "Стрелки или WASD — бегать, герой стреляет сам\n1 2 3 — выбор прокачки на новом уровне\nEnter — начать"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	_menu_best = _make_label(18)
	_menu_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_menu_best)
	_menu_panel.add_child(column)
	_menu_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_menu_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_menu_panel.offset_bottom = -16
	add_child(_menu_panel)


func _process(delta: float) -> void:
	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0:
			_banner.visible = false
	if _flash_rect.color.a > 0.0:
		_flash_rect.color.a = maxf(_flash_rect.color.a - delta * 2.5, 0.0)
	if game != null and str(game.get("state")) == "levelup" and bool(game.get("auto")) and not bool(game.get("hold_levelup")):
		_auto_timer += delta
		if _auto_timer >= 0.3:
			_auto_timer = 0.0
			game.choose_upgrade(int(game.get("recommended_index")))


func _input(event: InputEvent) -> void:
	if game == null or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode
	var state := str(game.get("state"))
	match state:
		"levelup":
			if key == KEY_1 or key == KEY_KP_1:
				game.choose_upgrade(0)
			elif key == KEY_2 or key == KEY_KP_2:
				game.choose_upgrade(1)
			elif key == KEY_3 or key == KEY_KP_3:
				game.choose_upgrade(2)
			elif key == KEY_LEFT or key == KEY_A:
				_set_levelup_focus(_levelup_focus - 1)
			elif key == KEY_RIGHT or key == KEY_D:
				_set_levelup_focus(_levelup_focus + 1)
			elif key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
				game.choose_upgrade(_levelup_focus)
		"menu":
			if key == KEY_LEFT or key == KEY_A:
				game.menu_skin(-1)
			elif key == KEY_RIGHT or key == KEY_D:
				game.menu_skin(1)
			elif key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
				game.start_game()
		"won", "over":
			if key == KEY_R or key == KEY_ENTER or key == KEY_KP_ENTER:
				game.restart()


func set_values(hp: float, max_hp: float, xp: int, xp_needed: int, level: int, time_left: float, kills: int, enemies: int, best: int) -> void:
	_hp_bar.value = hp / maxf(max_hp, 1.0)
	_hp_label.text = "Здоровье %d / %d" % [int(ceil(hp)), int(max_hp)]
	_xp_bar.value = float(xp) / maxf(float(xp_needed), 1.0)
	_time_label.text = "%d:%02d" % [int(time_left) / 60, int(time_left) % 60]
	_level_label.text = "Уровень %d" % level
	_kills_label.text = "Убито %d · врагов %d" % [kills, enemies]
	_best_label.text = "Рекорд %d" % best if best > 0 else ""


func flash() -> void:
	_flash_rect.color.a = 0.22


func show_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = true
	_banner_timer = 3.0


func show_message(text: String) -> void:
	_message.text = text
	_message.visible = true
	print("Надпись на экране: %s" % text.replace("\n", " "))


func show_levelup(options: Array, level: int, recommended: int = 0) -> void:
	_levelup_title.text = "Уровень %d! Выбери прокачку" % level
	_levelup_count = mini(options.size(), _levelup_cards.size())
	for i in _levelup_cards.size():
		var card: PanelContainer = _levelup_cards[i][0]
		if i < options.size():
			var option: Dictionary = options[i]
			var icon: UpgradeIcon = _levelup_cards[i][1]
			icon.kind = str(option["id"])
			icon.color = Color(UPGRADE_COLORS.get(icon.kind, "#ffffff"))
			icon.queue_redraw()
			_levelup_cards[i][2].text = str(option["title"])
			_levelup_cards[i][3].text = str(option["text"])
			_levelup_cards[i][4].visible = (i == recommended)
			card.visible = true
		else:
			card.visible = false
	_set_levelup_focus(recommended)
	_auto_timer = 0.0
	_levelup_panel.visible = true


func hide_levelup() -> void:
	_levelup_panel.visible = false


func show_menu(skin_title: String, best: int) -> void:
	_menu_skin.text = "◀  Герой: %s  ▶" % skin_title
	_menu_best.text = "Рекорд: %d" % best if best > 0 else "Рекорда пока нет"
	_menu_panel.visible = true
	_hp_bar.visible = false
	_hp_label.visible = false
	_xp_bar.visible = false
	_time_label.visible = false
	_level_label.visible = false
	_kills_label.visible = false
	_best_label.visible = false


func hide_menu() -> void:
	_menu_panel.visible = false
	_hp_bar.visible = true
	_hp_label.visible = true
	_xp_bar.visible = true
	_time_label.visible = true
	_level_label.visible = true
	_kills_label.visible = true
	_best_label.visible = true
