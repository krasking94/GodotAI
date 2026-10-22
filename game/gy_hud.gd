extends CanvasLayer

## Табло «Кладбища»: полоса здоровья, таймер, уровень, убитые, рекорд, полоса опыта внизу, красная вспышка
## при ударе, большие надписи (победа, поражение), окно прокачки (1, 2, 3 или кнопки) и стартовое меню
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
var _levelup_buttons: Array = []
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


func _build_levelup() -> void:
	_levelup_panel = _panel()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_levelup_title = _make_label(30)
	_levelup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_levelup_title)
	for i in 3:
		var button := Button.new()
		button.add_theme_font_size_override("font_size", 22)
		button.custom_minimum_size = Vector2(420, 64)
		button.pressed.connect(func(): if game != null: game.choose_upgrade(i))
		column.add_child(button)
		_levelup_buttons.append(button)
	_levelup_panel.add_child(column)
	add_child(_levelup_panel)


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
	if game != null and str(game.get("state")) == "levelup" and bool(game.get("auto")):
		_auto_timer += delta
		if _auto_timer >= 0.3:
			_auto_timer = 0.0
			game.choose_upgrade(randi_range(0, 2))


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


func show_levelup(options: Array, level: int) -> void:
	_levelup_title.text = "Уровень %d! Выбери прокачку" % level
	for i in _levelup_buttons.size():
		var button: Button = _levelup_buttons[i]
		if i < options.size():
			var option: Dictionary = options[i]
			button.text = "%d. %s — %s" % [i + 1, str(option["title"]), str(option["text"])]
			button.visible = true
		else:
			button.visible = false
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
