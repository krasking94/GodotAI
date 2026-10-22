extends CanvasLayer

## Табло «Кладбища»: полоса здоровья, таймер, уровень, убитые, рекорд, полоса опыта внизу, красная вспышка
## при ударе, большие надписи (победа, поражение), окно прокачки (три карточки с рисованными значками и пометкой
## «Рекомендуется»: клавиши 1 2 3, стрелки и Enter или мышь), стартовое меню (Enter — в форпост),
## табло форпоста (души, подсказка «E — …» у зданий) и окна зданий (список строк: ↑ ↓, Enter, Esc или мышь).
## Под полосой здоровья — название карты, справа сверху — души. Над полосой опыта — четыре слота способностей
## (клавиши 1–4 или мышь): значок, название, затемнение перезарядки и секунды до готовности. Работает и на паузе (process_mode ALWAYS): окно прокачки показывается,
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
var _relic_arrow: RelicArrow
var _relic_label: Label
var _menu_panel: PanelContainer
var _menu_souls: Label
var _menu_hint: Label
var _map_label: Label
var _souls_label: Label
var _prompt_label: Label
var _shop_panel: PanelContainer
var _shop_title: Label
var _shop_hint: Label
var _shop_rows_box: VBoxContainer
var _shop_rows: Array = []  # [PanelContainer, Label слева, Label справа]
var _shop_focus := 0
var _shop_count := 0
var _auto_timer := 0.0
var _combo_label: Label
var _slots_box: HBoxContainer
var _slots: Array = []  # [PanelContainer, AbilityIcon, Label название, Label секунды, id]


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
	_map_label = _make_label(17)
	_map_label.position = Vector2(18, 44)
	_map_label.modulate = Color(1, 1, 1, 0.8)
	add_child(_map_label)
	_combo_label = _make_label(24)
	_combo_label.position = Vector2(18, 70)
	_combo_label.modulate = Color("#ffe08a")
	_combo_label.visible = false
	add_child(_combo_label)
	_souls_label = _make_label(22)
	_souls_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_souls_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_souls_label.offset_right = -16
	_souls_label.offset_top = 104
	_souls_label.add_theme_color_override("font_color", Color("#9fe8ff"))
	add_child(_souls_label)
	_prompt_label = _make_label(26)
	_prompt_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt_label.offset_bottom = -60
	_prompt_label.add_theme_color_override("font_color", Color("#ffe0a0"))
	_prompt_label.visible = false
	add_child(_prompt_label)
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
	_build_slots()
	_banner = _make_label(34)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = 128  # ниже стрелки и подписи реликвии
	_banner.add_theme_color_override("font_color", Color("#ffb347"))
	_banner.visible = false
	add_child(_banner)
	_message = _make_label(52)
	_message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message.visible = false
	add_child(_message)
	_relic_arrow = RelicArrow.new()
	_relic_arrow.custom_minimum_size = Vector2(36, 36)
	_relic_arrow.size = Vector2(36, 36)
	_relic_arrow.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_relic_arrow.offset_left = -18
	_relic_arrow.offset_right = 18
	_relic_arrow.offset_top = 60
	_relic_arrow.offset_bottom = 96
	_relic_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_relic_arrow.visible = false
	add_child(_relic_arrow)
	_relic_label = _make_label(16)
	_relic_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_relic_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_relic_label.offset_top = 96
	_relic_label.add_theme_color_override("font_color", Color("#d9a6ff"))
	_relic_label.visible = false
	add_child(_relic_label)
	_build_levelup()
	_build_menu()
	_build_shop()


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


## Значок способности (gy_abilities.gd), нарисованный кодом: лучи, шевроны рывка, снежинка, метеор, костёр, часы.
## charge — доля перезарядки 0…1: сверху вниз слот затемнён на (1 - charge).
class AbilityIcon extends Control:
	var kind := ""
	var color := Color.WHITE
	var charge := 1.0

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var one := PackedColorArray([color])
		draw_circle(c, r, Color(color, 0.14))
		match kind:
			"nova":
				for i in 8:
					var a := TAU * i / 8.0
					draw_line(c + Vector2.from_angle(a) * r * 0.3, c + Vector2.from_angle(a) * r * 0.75, color, 3.0, true)
				draw_circle(c, r * 0.2, color)
			"dash":
				for i in 2:
					var x := c.x - r * 0.45 + i * r * 0.45
					draw_polyline(PackedVector2Array([Vector2(x, c.y - r * 0.45), Vector2(x + r * 0.4, c.y), Vector2(x, c.y + r * 0.45)]), color, 4.0, true)
			"frost":
				for i in 6:
					var a := TAU * i / 6.0
					var tip := c + Vector2.from_angle(a) * r * 0.72
					draw_line(c, tip, color, 3.0, true)
					var mid := c + Vector2.from_angle(a) * r * 0.45
					draw_line(mid, mid + Vector2.from_angle(a + 0.6) * r * 0.22, color, 2.5, true)
					draw_line(mid, mid + Vector2.from_angle(a - 0.6) * r * 0.22, color, 2.5, true)
			"meteor":
				draw_circle(c + Vector2(r * 0.2, r * 0.2), r * 0.32, color)
				for i in 3:
					var off := Vector2(-r * 0.1, (i - 1) * r * 0.22)
					draw_line(c + off + Vector2(0, r * 0.1), c + off + Vector2(-r * 0.65, -r * 0.45), Color(color, 0.8 - 0.2 * i), 3.0, true)
			"fire":
				draw_polygon(PackedVector2Array([c + Vector2(-r * 0.4, r * 0.5), c + Vector2(r * 0.4, r * 0.5), c + Vector2(r * 0.3, r * 0.05),
					c + Vector2(r * 0.05, -r * 0.6), c + Vector2(-r * 0.15, -r * 0.1), c + Vector2(-r * 0.35, r * 0.05)]), one)
				draw_line(c + Vector2(-r * 0.6, r * 0.6), c + Vector2(r * 0.6, r * 0.6), color, 4.0, true)
			"time":
				draw_arc(c, r * 0.62, 0.0, TAU, 32, color, 3.0, true)
				draw_line(c, c + Vector2(0, -r * 0.42), color, 3.0, true)
				draw_line(c, c + Vector2(r * 0.3, r * 0.15), color, 3.0, true)
			_:
				draw_circle(c, r * 0.3, color)
		draw_arc(c, r - 1.5, 0.0, TAU, 48, color, 2.0, true)
		if charge < 1.0:
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, size.y * (1.0 - charge))), Color(0, 0, 0, 0.62))


## Стрелка к реликвии под таймером: лиловый треугольник, повёрнутый в сторону реликвии.
class RelicArrow extends Control:
	var angle := 0.0

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var points := PackedVector2Array()
		for p in [Vector2(r, 0), Vector2(-r * 0.7, r * 0.6), Vector2(-r * 0.3, 0), Vector2(-r * 0.7, -r * 0.6)]:
			points.append(c + p.rotated(angle))
		draw_polygon(points, PackedColorArray([Color("#c070ff")]))


func _card_style(color: Color, focused: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.10, 0.11, 0.17, 0.98) if focused else Color(0.06, 0.07, 0.11, 0.96)
	box.border_color = color if focused else Color(color, 0.45)
	box.set_border_width_all(4 if focused else 2)
	box.set_corner_radius_all(12)
	box.set_content_margin_all(14)
	return box


func _slot_style(color: Color, ready: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.06, 0.1, 0.9)
	box.border_color = color if ready else Color(color, 0.35)
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(6)
	return box


## Четыре слота способностей над полосой опыта: значок, название, цифра клавиши и секунды перезарядки.
func _build_slots() -> void:
	_slots_box = HBoxContainer.new()
	_slots_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_slots_box.offset_left = -246
	_slots_box.offset_right = 246
	_slots_box.offset_top = -118
	_slots_box.offset_bottom = -40
	_slots_box.add_theme_constant_override("separation", 8)
	_slots_box.visible = false
	add_child(_slots_box)
	for i in 4:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(116, 78)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(_on_slot_input.bind(i))
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		panel.add_child(box)
		var icon := AbilityIcon.new()
		icon.custom_minimum_size = Vector2(44, 44)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(icon)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 0)
		box.add_child(column)
		var key := _make_label(13)
		key.text = str(i + 1)
		key.modulate = Color(1, 1, 1, 0.6)
		column.add_child(key)
		var title := _make_label(14)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		column.add_child(title)
		var seconds := _make_label(15)
		seconds.modulate = Color("#ffd27a")
		column.add_child(seconds)
		_slots_box.add_child(panel)
		_slots.append([panel, icon, title, seconds, ""])


func _on_slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and game != null:
		game.cast_slot(index)


## Показать слоты на ночь: ids — способности по порядку (до 4), пустые слоты скрыты.
func show_slots(ids: Array) -> void:
	var Abilities := load("res://game/gy_abilities.gd")
	for i in _slots.size():
		var slot: Array = _slots[i]
		var id := str(ids[i]) if i < ids.size() else ""
		slot[4] = id
		var panel: PanelContainer = slot[0]
		panel.visible = id != "" and Abilities.ABILITIES.has(id)
		if not panel.visible:
			continue
		var stats: Dictionary = Abilities.ABILITIES[id]
		var icon: AbilityIcon = slot[1]
		icon.kind = id
		icon.color = Color(str(stats["color"]))
		icon.charge = 1.0
		icon.queue_redraw()
		var title: Label = slot[2]
		title.text = str(stats.get("short", stats["title"]))
		var seconds: Label = slot[3]
		seconds.text = ""
		panel.add_theme_stylebox_override("panel", _slot_style(icon.color, true))
	_slots_box.visible = ids.size() > 0


## Обновить перезарядку слотов из узла способностей (каждый кадр ночью).
func set_cooldowns(abilities: Node) -> void:
	if not _slots_box.visible:
		return
	for slot in _slots:
		var id := str(slot[4])
		if id == "":
			continue
		var state: Array = abilities.cooldown_state(id)
		var icon: AbilityIcon = slot[1]
		var was_ready := icon.charge >= 1.0
		icon.charge = float(state[0])
		icon.queue_redraw()
		var seconds: Label = slot[3]
		seconds.text = ("%d с" % int(ceil(float(state[1])))) if float(state[1]) > 0.0 else ""
		if was_ready != (icon.charge >= 1.0):
			var panel: PanelContainer = slot[0]
			panel.add_theme_stylebox_override("panel", _slot_style(icon.color, icon.charge >= 1.0))


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
	var new_focus := wrapi(index, 0, _levelup_count)
	if _levelup_panel.visible and new_focus != _levelup_focus and game != null:
		game.play_sound("hover")
	_levelup_focus = new_focus
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
	var subtitle := _make_label(18)
	subtitle.text = "Последний сторож погоста. Десять ночей, десять погостов."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(1, 1, 1, 0.8)
	column.add_child(subtitle)
	_menu_souls = _make_label(22)
	_menu_souls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_souls.add_theme_color_override("font_color", Color("#9fe8ff"))
	column.add_child(_menu_souls)
	var start := _make_label(28)
	start.text = "Enter — в форпост"
	start.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start.add_theme_color_override("font_color", Color("#ffe0a0"))
	column.add_child(start)
	_menu_hint = _make_label(16)
	_menu_hint.text = "В форпосте: стрелки или WASD — ходить, E у здания — войти, ворота ведут в ночь\nНочью герой стреляет сам, 1 2 3 — прокачка на новом уровне"
	_menu_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_hint.modulate = Color(1, 1, 1, 0.65)
	column.add_child(_menu_hint)
	_menu_panel.add_child(column)
	_menu_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_menu_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_menu_panel.offset_bottom = -16
	add_child(_menu_panel)


func _row_style(focused: bool, locked: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.12, 0.13, 0.2, 0.98) if focused else Color(0.06, 0.07, 0.11, 0.9)
	box.border_color = Color("#ffe0a0") if focused else Color(1, 1, 1, 0.12)
	box.set_border_width_all(2 if focused else 1)
	box.set_corner_radius_all(8)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	if locked:
		box.bg_color = box.bg_color.darkened(0.3)
	return box


## Окно здания форпоста: заголовок, до 12 строк (слева название и описание, справа цена или состояние), подсказка.
func _build_shop() -> void:
	_shop_panel = _panel()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_shop_title = _make_label(28)
	_shop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_title.add_theme_color_override("font_color", Color("#ffe0a0"))
	column.add_child(_shop_title)
	_shop_rows_box = VBoxContainer.new()
	_shop_rows_box.add_theme_constant_override("separation", 4)
	for i in 12:
		var row := PanelContainer.new()
		row.custom_minimum_size = Vector2(760, 0)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and game != null:
				game.shop_pick(i))
		row.mouse_entered.connect(func(): _set_shop_focus(i))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		var left := _make_label(17)
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.add_child(left)
		var right := _make_label(17)
		right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.custom_minimum_size = Vector2(150, 0)
		right.add_theme_color_override("font_color", Color("#9fe8ff"))
		line.add_child(right)
		row.add_child(line)
		_shop_rows_box.add_child(row)
		_shop_rows.append([row, left, right])
	column.add_child(_shop_rows_box)
	_shop_hint = _make_label(15)
	_shop_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_hint.modulate = Color(1, 1, 1, 0.6)
	column.add_child(_shop_hint)
	_shop_panel.add_child(column)
	add_child(_shop_panel)


func _set_shop_focus(index: int) -> void:
	if _shop_count <= 0:
		return
	var new_focus := wrapi(index, 0, _shop_count)
	if _shop_panel.visible and new_focus != _shop_focus and game != null:
		game.play_sound("hover")
	_shop_focus = new_focus
	for i in _shop_rows.size():
		var row: PanelContainer = _shop_rows[i][0]
		row.add_theme_stylebox_override("panel", _row_style(i == _shop_focus, bool(row.get_meta("locked", false))))


func show_shop(title: String, rows: Array, hint: String, selected: int) -> void:
	_shop_title.text = title
	_shop_hint.text = hint
	_shop_count = mini(rows.size(), _shop_rows.size())
	for i in _shop_rows.size():
		var row: PanelContainer = _shop_rows[i][0]
		if i < rows.size():
			var data: Dictionary = rows[i]
			var left: Label = _shop_rows[i][1]
			var right: Label = _shop_rows[i][2]
			var text := str(data["title"])
			if str(data.get("text", "")) != "":
				text += "  —  " + str(data["text"])
			left.text = text
			right.text = str(data.get("right", ""))
			var locked := bool(data.get("locked", false))
			row.set_meta("locked", locked)
			left.modulate = Color(1, 1, 1, 0.55) if locked else Color.WHITE
			right.modulate = Color(1, 1, 1, 0.55) if locked else Color.WHITE
			row.visible = true
		else:
			row.visible = false
	_shop_panel.visible = true
	_prompt_label.visible = false
	_set_shop_focus(clampi(selected, 0, maxi(_shop_count - 1, 0)))


func hide_shop() -> void:
	_shop_panel.visible = false


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
		"playing":
			if key == KEY_1 or key == KEY_KP_1:
				game.cast_slot(0)
			elif key == KEY_2 or key == KEY_KP_2:
				game.cast_slot(1)
			elif key == KEY_3 or key == KEY_KP_3:
				game.cast_slot(2)
			elif key == KEY_4 or key == KEY_KP_4:
				game.cast_slot(3)
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
			if key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
				game.to_base()
		"base":
			if key == KEY_E or key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
				game.interact()
		"shop":
			if key == KEY_UP or key == KEY_W:
				_set_shop_focus(_shop_focus - 1)
			elif key == KEY_DOWN or key == KEY_S:
				_set_shop_focus(_shop_focus + 1)
			elif key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
				game.shop_pick(_shop_focus)
			elif key == KEY_ESCAPE or key == KEY_E or key == KEY_BACKSPACE:
				game.close_shop()
		"won", "over":
			if key == KEY_R:
				game.restart()
			elif key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
				game.to_base()


func set_values(hp: float, max_hp: float, xp: int, xp_needed: int, level: int, time_left: float, kills: int, enemies: int, best: int) -> void:
	_hp_bar.value = hp / maxf(max_hp, 1.0)
	var shield := float(game.player.shield) if game != null and game.player != null else 0.0
	_hp_label.text = "Здоровье %d / %d" % [int(ceil(hp)), int(max_hp)] + ("  · щит %d" % int(ceil(shield)) if shield > 0.0 else "")
	_xp_bar.value = float(xp) / maxf(float(xp_needed), 1.0)
	_time_label.text = "%d:%02d" % [int(time_left) / 60, int(time_left) % 60]
	_level_label.text = "Уровень %d" % level
	_kills_label.text = "Убито %d · врагов %d" % [kills, enemies]
	_best_label.text = "Рекорд %d" % best if best > 0 else ""


## Стрелка и расстояние до реликвии (angle в экранных осях: 0 — вправо, вниз — положительный).
func set_relic(shown: bool, angle: float, distance: float) -> void:
	_relic_arrow.visible = shown
	_relic_label.visible = shown
	if shown:
		_relic_arrow.angle = angle
		_relic_arrow.queue_redraw()
		_relic_label.text = "Реликвия: %d м" % int(distance)


func flash() -> void:
	_flash_rect.color.a = 0.22


func show_banner(text: String, color: String = "#ffb347") -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", Color(color))
	_banner.visible = true
	_banner_timer = 3.0


## Серия убийств слева под названием карты: видна от трёх подряд, растёт и ярчает.
func set_combo(count: int, _fraction: float) -> void:
	_combo_label.visible = count >= 3 and _xp_bar.visible
	if count >= 3:
		_combo_label.text = "Серия ×%d" % count
		_combo_label.add_theme_font_size_override("font_size", mini(24 + count / 2, 40))
		_combo_label.modulate = Color("#ff6a3a") if count >= 25 else (Color("#ffb347") if count >= 10 else Color("#ffe08a"))


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


func show_menu(souls: int, nights: int) -> void:
	_menu_souls.text = "✦ Души: %d" % souls + ("  ·  ночей позади: %d" % nights if nights > 0 else "")
	_menu_panel.visible = true
	_set_hud_visible(false)
	_souls_label.visible = false


func set_map_title(title: String) -> void:
	_map_label.text = title


func set_souls(souls: int) -> void:
	_souls_label.text = "✦ %d" % souls


func _set_hud_visible(shown: bool) -> void:
	_hp_bar.visible = shown
	_hp_label.visible = shown
	_map_label.visible = shown
	_xp_bar.visible = shown
	_time_label.visible = shown
	_level_label.visible = shown
	_kills_label.visible = shown
	_best_label.visible = shown
	_souls_label.visible = shown
	if not shown:
		_slots_box.visible = false
		_combo_label.visible = false


func hide_menu() -> void:
	_menu_panel.visible = false
	_set_hud_visible(true)


## Табло форпоста: только души и название, подсказка у зданий.
func show_base(souls: int) -> void:
	_menu_panel.visible = false
	_set_hud_visible(false)
	_map_label.visible = true
	_map_label.text = "Форпост"
	_souls_label.visible = true
	_souls_label.offset_top = 10
	set_souls(souls)


func set_prompt(text: String) -> void:
	_prompt_label.text = text
	_prompt_label.visible = text != "" and not _shop_panel.visible
