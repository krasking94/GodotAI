extends CanvasLayer

## Экран «Симулятора жизни»: возраст и текущее задание (слева сверху), навыки и отношения с родителями
## (справа сверху), лампочка-подсказка (кнопка справа: что делать, куда идти, какие клавиши),
## подсказка у предмета (внизу), реплики родителей (внизу по центру), предисловие, мини-игры с буквами
## и сном (по центру, выбор клавишами 1 2 3), итог этапа, главное меню (новая игра, продолжить, настройки,
## выход), пауза (Esc), настройки (чувствительность, инверсия, покачивание, громкость музыки и звуков,
## полный экран), всплывающие «+5 Ноги», баннер выполненного задания, шкала равновесия при ходьбе,
## строка клавиш справа внизу. Меню управляются и мышью, и клавишами (стрелки + Enter), и геймпадом.
## Игра (ls_game.gd) зовёт методы set_age, set_quest, set_skills, set_relations, say, show_intro,
## start_letters, start_dream, show_end, show_main_menu, show_pause, skill_popup, quest_banner…
## Любое открытое окно ставит ui_open = true: герой тогда не ходит и не крутит головой.
## Звуки интерфейса HUD не играет сам, а просит игру сигналом sound_requested.

signal minigame_finished(result: Dictionary)
signal intro_closed
signal lamp_toggled(open: bool)
signal menu_action(id: String)          # new_game, continue, resume, main_menu, exit
signal settings_changed(settings: Dictionary)
signal sound_requested(id: String)

const SKILL_TITLES := {"legs": "Ноги", "hands": "Руки", "speech": "Речь", "mind": "Ум", "heart": "Сердце"}
const SKILL_COLORS := {"legs": Color("#6ad17a"), "hands": Color("#f0a860"), "speech": Color("#6fb8ff"),
	"mind": Color("#c89bff"), "heart": Color("#ff7a9a")}
const GOLD := Color("#ffe08a")
const PANEL_BG := Color(0.08, 0.1, 0.16, 0.72)

var ui_open := false
var auto_pick := false  # самопроверка: в мини-играх отвечать правильно само

var _age: Label
var _quest_title: Label
var _quest_text: Label
var _quest_progress: Label
var _hint: Label
var _controls: Label
var _speech_panel: PanelContainer
var _speech_name: Label
var _speech_text: Label
var _speech_timer := 0.0
var _skill_rows := {}      # id -> ProgressBar
var _relation_rows := {}   # id -> ProgressBar
var _skill_panel: PanelContainer
var _lamp_button: Button
var _lamp_panel: PanelContainer
var _lamp_text: RichTextLabel
var _intro: PanelContainer
var _game_panel: PanelContainer
var _game_question: Label
var _game_options: Array[Button] = []
var _game_note: Label
var _end_panel: PanelContainer
var _end_text: RichTextLabel
var _toast: Label
var _toast_timer := 0.0
var _banner: Label
var _flash: ColorRect
var _dim: ColorRect
var _menu: PanelContainer
var _menu_continue: Button
var _menu_first: Button
var _version: Label
var _pause: PanelContainer
var _pause_first: Button
var _settings: PanelContainer
var _settings_back: Button
var _settings_widgets := {}
var _settings_from := "menu"   # куда возвращаться из настроек: menu или pause
var _balance_box: Control
var _balance_bar: ProgressBar
var _rounds: Array = []
var _round := 0
var _correct := 0
var _wrong := 0
var _game_kind := ""
var _dream_blink := -1
var _dream_timer := 0.0
var _auto_timer := 0.0
var _quiet := false  # пока строим настройки, не слать settings_changed


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS  # меню и пауза работают, когда игра стоит
	_build_dim()
	_build_top_left()
	_build_top_right()
	_build_bottom()
	_build_lamp()
	_build_speech()
	_build_minigame()
	_build_intro()
	_build_end()
	_build_toast()
	_build_banner()
	_build_flash()
	_build_main_menu()
	_build_pause()
	_build_settings()


func hint_label() -> Label:
	return _hint


# --- Сборка: общие кирпичики ---------------------------------------------------------------------

func _panel_style(color: Color, border: Color = Color(1, 1, 1, 0.25)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(14)
	box.set_content_margin_all(16)
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 8
	return box


func _label(size: int, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Кнопка меню: большая, с подсветкой при наведении и при выборе клавишами (focus).
func _menu_button(text: String, id: String, color := Color("#243a6a")) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(360, 56)
	button.add_theme_font_size_override("font_size", 26)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.focus_mode = Control.FOCUS_ALL
	var normal := _panel_style(color, Color(1, 1, 1, 0.2))
	normal.set_content_margin_all(8)
	var lit := _panel_style(color.lightened(0.25), GOLD)
	lit.set_content_margin_all(8)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", lit)
	button.add_theme_stylebox_override("focus", lit)
	button.add_theme_stylebox_override("pressed", lit)
	button.add_theme_stylebox_override("hover_pressed", lit)
	button.mouse_entered.connect(func() -> void: sound_requested.emit("hover"))
	button.focus_entered.connect(func() -> void: sound_requested.emit("hover"))
	button.pressed.connect(func() -> void:
		sound_requested.emit("click")
		_on_menu_button(id))
	return button


## Окно по центру экрана заданного размера.
func _center_panel(width: float, height: float, bg: Color, border: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(bg, border))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5
	panel.offset_top = -height * 0.5
	panel.offset_bottom = height * 0.5
	panel.visible = false
	add_child(panel)
	return panel


func _build_dim() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.03, 0.08, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.visible = false
	add_child(_dim)


func _build_top_left() -> void:
	var panel := PanelContainer.new()
	panel.name = "QuestPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(PANEL_BG))
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(420, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	_age = _label(22, GOLD)
	_age.text = "Возраст: 0 мес."
	_age.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_age)
	_quest_progress = _label(18, Color("#b8c8e8"))
	_quest_progress.text = ""
	_quest_progress.autowrap_mode = TextServer.AUTOWRAP_OFF
	_quest_progress.custom_minimum_size = Vector2(60, 0)
	_quest_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_quest_progress)
	_quest_title = _label(26)
	_quest_title.text = "Задание"
	box.add_child(_quest_title)
	_quest_text = _label(20, Color("#d8e4ff"))
	_quest_text.custom_minimum_size = Vector2(380, 0)
	box.add_child(_quest_text)


func _build_top_right() -> void:
	var panel := PanelContainer.new()
	_skill_panel = panel
	panel.name = "SkillPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(PANEL_BG))
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -300
	panel.offset_right = -84
	panel.offset_top = 20
	add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var title := _label(20, GOLD)
	title.text = "Навыки"
	box.add_child(title)
	for id in SKILL_TITLES:
		_skill_rows[id] = _bar_row(box, SKILL_TITLES[id], SKILL_COLORS[id])
	var title2 := _label(20, GOLD)
	title2.text = "Родители"
	box.add_child(title2)
	_relation_rows["mom"] = _bar_row(box, "Мама", Color("#ff9ac0"))
	_relation_rows["dad"] = _bar_row(box, "Папа", Color("#8ac0ff"))


func _bar_row(parent: Control, title: String, color: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var label := _label(17)
	label.text = title
	label.custom_minimum_size = Vector2(72, 0)
	row.add_child(label)
	var bar := ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(110, 16)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.12)
	back.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	row.add_child(bar)
	return bar


func _build_bottom() -> void:
	_hint = _label(26, Color("#ffffff"))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = 24
	_hint.offset_top = -64
	_hint.offset_right = 700
	add_child(_hint)
	# Строка клавиш справа внизу — всегда видно, что можно нажать.
	_controls = _label(16, Color(1, 1, 1, 0.75))
	_controls.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_controls.anchor_left = 1.0
	_controls.anchor_right = 1.0
	_controls.anchor_top = 1.0
	_controls.anchor_bottom = 1.0
	_controls.offset_left = -1000
	_controls.offset_right = -16
	_controls.offset_top = -36
	_controls.offset_bottom = -12
	_controls.autowrap_mode = TextServer.AUTOWRAP_OFF
	_controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_controls.text = "W A S D — двигаться · мышь — смотреть · E — взять · Пробел — встать · H — подсказка · Esc — пауза"
	add_child(_controls)
	# Шкала равновесия (видна, когда малыш идёт на ножках).
	_balance_box = VBoxContainer.new()
	_balance_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_balance_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_balance_box.anchor_left = 0.5
	_balance_box.anchor_right = 0.5
	_balance_box.anchor_top = 1.0
	_balance_box.anchor_bottom = 1.0
	_balance_box.offset_left = -110
	_balance_box.offset_right = 110
	_balance_box.offset_top = -84
	_balance_box.offset_bottom = -44
	_balance_box.visible = false
	add_child(_balance_box)
	var caption := _label(15, Color("#d8e4ff"))
	caption.text = "Равновесие"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_balance_box.add_child(caption)
	_balance_bar = ProgressBar.new()
	_balance_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_balance_bar.min_value = 0.0
	_balance_bar.max_value = 1.0
	_balance_bar.value = 1.0
	_balance_bar.show_percentage = false
	_balance_bar.custom_minimum_size = Vector2(220, 12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#6ad17a")
	fill.set_corner_radius_all(6)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.45)
	back.set_corner_radius_all(6)
	_balance_bar.add_theme_stylebox_override("fill", fill)
	_balance_bar.add_theme_stylebox_override("background", back)
	_balance_box.add_child(_balance_bar)
	# Прицел: точка в центре, чтобы было понятно, куда смотришь.
	var dot := ColorRect.new()
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE  # прицел не должен перехватывать мышь
	dot.color = Color(1, 1, 1, 0.7)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.offset_left = -3
	dot.offset_top = -3
	dot.offset_right = 3
	dot.offset_bottom = 3
	add_child(dot)


func _build_lamp() -> void:
	_lamp_button = Button.new()
	_lamp_button.text = "💡"
	_lamp_button.tooltip_text = "Подсказка: что делать (клавиша H)"
	_lamp_button.add_theme_font_size_override("font_size", 30)
	_lamp_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_lamp_button.anchor_left = 1.0
	_lamp_button.anchor_right = 1.0
	_lamp_button.offset_left = -72
	_lamp_button.offset_right = -16
	_lamp_button.offset_top = 20
	_lamp_button.offset_bottom = 76
	_lamp_button.focus_mode = Control.FOCUS_NONE
	var style := _panel_style(Color("#ffd24a"), Color("#fff2b0"))
	style.set_content_margin_all(4)
	_lamp_button.add_theme_stylebox_override("normal", style)
	var hover := _panel_style(Color("#ffe27a"), Color("#ffffff"))
	hover.set_content_margin_all(4)
	_lamp_button.add_theme_stylebox_override("hover", hover)
	_lamp_button.add_theme_stylebox_override("pressed", hover)
	_lamp_button.pressed.connect(func() -> void:
		sound_requested.emit("click")
		toggle_lamp())
	add_child(_lamp_button)
	var under := _label(14, GOLD)
	under.text = "H"
	under.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	under.anchor_left = 1.0
	under.anchor_right = 1.0
	under.offset_left = -72
	under.offset_right = -16
	under.offset_top = 78
	under.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(under)

	_lamp_panel = PanelContainer.new()
	_lamp_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lamp_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.12, 0.1, 0.04, 0.92), Color("#ffd24a")))
	_lamp_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_lamp_panel.anchor_left = 1.0
	_lamp_panel.anchor_right = 1.0
	_lamp_panel.offset_left = -560
	_lamp_panel.offset_right = -84
	_lamp_panel.offset_top = 20
	_lamp_panel.visible = false
	add_child(_lamp_panel)
	_lamp_text = RichTextLabel.new()
	_lamp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lamp_text.bbcode_enabled = true
	_lamp_text.fit_content = true
	_lamp_text.custom_minimum_size = Vector2(470, 0)
	_lamp_text.add_theme_font_size_override("normal_font_size", 18)
	_lamp_text.add_theme_font_size_override("bold_font_size", 20)
	_lamp_panel.add_child(_lamp_text)


func _build_speech() -> void:
	_speech_panel = PanelContainer.new()
	_speech_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speech_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.1, 0.08, 0.12, 0.9), Color("#ffb0d0")))
	_speech_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_speech_panel.anchor_left = 0.5
	_speech_panel.anchor_right = 0.5
	_speech_panel.anchor_top = 1.0
	_speech_panel.anchor_bottom = 1.0
	_speech_panel.offset_left = -330
	_speech_panel.offset_right = 330
	_speech_panel.offset_top = -200
	_speech_panel.offset_bottom = -100
	_speech_panel.visible = false
	add_child(_speech_panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speech_panel.add_child(box)
	_speech_name = _label(20, Color("#ffb0d0"))
	box.add_child(_speech_name)
	_speech_text = _label(22)
	_speech_text.custom_minimum_size = Vector2(620, 0)
	box.add_child(_speech_text)


func _build_minigame() -> void:
	_game_panel = _center_panel(720, 340, Color(0.06, 0.08, 0.18, 0.95), Color("#8ac0ff"))
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	_game_panel.add_child(box)
	_game_question = _label(28)
	_game_question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_question.custom_minimum_size = Vector2(680, 0)
	box.add_child(_game_question)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	for i in 3:
		var button := Button.new()
		button.custom_minimum_size = Vector2(150, 120)
		button.add_theme_font_size_override("font_size", 54)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_stylebox_override("normal", _panel_style(Color("#243a6a"), Color("#8ac0ff")))
		button.add_theme_stylebox_override("hover", _panel_style(Color("#3a5aa0"), Color("#ffffff")))
		button.add_theme_stylebox_override("pressed", _panel_style(Color("#3a5aa0"), Color("#ffffff")))
		button.pressed.connect(_pick.bind(i))
		row.add_child(button)
		_game_options.append(button)
	_game_note = _label(18, Color("#b0c8ff"))
	_game_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_note.text = "Нажми 1, 2 или 3 на клавиатуре или щёлкни мышью"
	box.add_child(_game_note)


func _build_intro() -> void:
	_intro = _center_panel(840, 520, Color(0.05, 0.06, 0.12, 0.96), GOLD)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_intro.add_child(box)
	var title := _label(34, GOLD)
	title.text = "Симулятор жизни"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.custom_minimum_size = Vector2(800, 0)
	text.add_theme_font_size_override("normal_font_size", 20)
	text.add_theme_font_size_override("bold_font_size", 21)
	text.text = ("Ты только что родился. Впереди целая жизнь: сначала ты научишься ползать и ходить, скажешь первое слово, " +
		"выучишь буквы, потом будет садик, школа, учёба и работа. Кем ты станешь, решаешь ты сам.\n\n" +
		"[b]Как это работает.[/b] Всё, что ты делаешь, растит навыки: ползаешь — крепнут [color=#6ad17a]Ноги[/color], " +
		"берёшь вещи — [color=#f0a860]Руки[/color], говоришь и слушаешь маму — [color=#6fb8ff]Речь[/color], " +
		"решаешь задачки — [color=#c89bff]Ум[/color], помогаешь родителям — [color=#ff7a9a]Сердце[/color]. " +
		"От навыков зависит, что откроется дальше: новые задания, места, друзья и профессии.\n\n" +
		"[b]Родители.[/b] Мама и папа рядом. Слушайся их и помогай — отношения растут, а с ними и бонусы. " +
		"Задание всегда написано слева сверху, а над целью светится жёлтая звёздочка.\n\n" +
		"[b]Управление.[/b] Мышь — смотреть по сторонам. W A S D — двигаться. E — взять предмет или поговорить. " +
		"Пробел — встать на ножки (когда научишься). H или лампочка справа — подсказка. Esc — пауза и настройки. " +
		"Геймпад тоже работает: стики, A, X, Y, Start.\n\n" +
		"[color=#ffe08a]Нажми Enter, чтобы начать.[/color]")
	box.add_child(text)


func _build_end() -> void:
	_end_panel = _center_panel(760, 460, Color(0.05, 0.06, 0.12, 0.96), GOLD)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_end_panel.add_child(box)
	_end_text = RichTextLabel.new()
	_end_text.bbcode_enabled = true
	_end_text.fit_content = true
	_end_text.custom_minimum_size = Vector2(720, 0)
	_end_text.add_theme_font_size_override("normal_font_size", 21)
	_end_text.add_theme_font_size_override("bold_font_size", 30)
	box.add_child(_end_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var menu_button := _menu_button("В главное меню", "main_menu")
	menu_button.custom_minimum_size = Vector2(300, 52)
	row.add_child(menu_button)
	var exit_button := _menu_button("Выйти из игры", "exit", Color("#5a2a3a"))
	exit_button.custom_minimum_size = Vector2(300, 52)
	row.add_child(exit_button)


func _build_toast() -> void:
	_toast = _label(28, GOLD)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_left = -400
	_toast.offset_right = 400
	_toast.offset_top = 110
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.visible = false
	add_child(_toast)


## Баннер «Задание выполнено»: выезжает по центру, чуть увеличивается и тает.
func _build_banner() -> void:
	_banner = _label(40, GOLD)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.anchor_top = 0.5
	_banner.anchor_bottom = 0.5
	_banner.offset_left = -450
	_banner.offset_right = 450
	_banner.offset_top = -160
	_banner.offset_bottom = -60
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.pivot_offset = Vector2(450, 50)
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.visible = false
	add_child(_banner)


func _build_flash() -> void:
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)


func _build_main_menu() -> void:
	_menu = _center_panel(560, 520, Color(0.05, 0.06, 0.12, 0.94), GOLD)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	_menu.add_child(box)
	var title := _label(44, GOLD)
	title.text = "Симулятор жизни"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := _label(20, Color("#d8e4ff"))
	subtitle.text = "Этап 1: младенчество"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	box.add_child(spacer)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(column)
	_menu_first = _menu_button("Новая игра", "new_game")
	column.add_child(_menu_first)
	_menu_continue = _menu_button("Продолжить", "continue", Color("#2a5a3a"))
	column.add_child(_menu_continue)
	column.add_child(_menu_button("Настройки", "settings_menu"))
	column.add_child(_menu_button("Выйти", "exit", Color("#5a2a3a")))
	var tip := _label(15, Color(1, 1, 1, 0.6))
	tip.text = "Стрелки и Enter, мышь или геймпад"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tip)
	_version = _label(14, Color(1, 1, 1, 0.5))
	_version.text = "версия 0.2"
	_version.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_version.anchor_top = 1.0
	_version.anchor_bottom = 1.0
	_version.offset_left = 16
	_version.offset_top = -30
	_version.offset_right = 400
	_version.visible = false
	add_child(_version)


func _build_pause() -> void:
	_pause = _center_panel(460, 400, Color(0.05, 0.06, 0.12, 0.94), Color("#8ac0ff"))
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	_pause.add_child(box)
	var title := _label(34, Color("#8ac0ff"))
	title.text = "Пауза"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(column)
	_pause_first = _menu_button("Продолжить", "resume", Color("#2a5a3a"))
	column.add_child(_pause_first)
	column.add_child(_menu_button("Настройки", "settings_pause"))
	column.add_child(_menu_button("В главное меню", "main_menu"))
	column.add_child(_menu_button("Выйти из игры", "exit", Color("#5a2a3a")))


func _build_settings() -> void:
	_settings = _center_panel(620, 520, Color(0.05, 0.06, 0.12, 0.96), GOLD)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_settings.add_child(box)
	var title := _label(32, GOLD)
	title.text = "Настройки"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_settings_widgets["sensitivity"] = _slider_row(box, "Чувствительность мыши", 0.3, 3.0, 0.1, 1.0)
	_settings_widgets["music"] = _slider_row(box, "Громкость музыки", 0.0, 1.0, 0.05, 0.6)
	_settings_widgets["sfx"] = _slider_row(box, "Громкость звуков", 0.0, 1.0, 0.05, 0.9)
	_settings_widgets["invert_y"] = _check_row(box, "Инверсия мыши по вертикали", false)
	_settings_widgets["head_bob"] = _check_row(box, "Покачивание головы при ходьбе", true)
	_settings_widgets["fullscreen"] = _check_row(box, "Полный экран (F11)", false)
	var note := _label(15, Color(1, 1, 1, 0.6))
	note.text = "Всё сохраняется сразу. Esc или «Назад» — вернуться."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	_settings_back = _menu_button("Назад", "settings_back")
	_settings_back.custom_minimum_size = Vector2(240, 52)
	row.add_child(_settings_back)


func _slider_row(parent: Control, title: String, lo: float, hi: float, step: float, value: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var label := _label(20)
	label.text = title
	label.custom_minimum_size = Vector2(300, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(200, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_ALL
	var value_label := _label(18, GOLD)
	value_label.custom_minimum_size = Vector2(50, 0)
	value_label.text = "%.2f" % value if hi <= 3.0 and step < 1.0 and hi > 1.0 else "%d%%" % int(round(value * 100))
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = ("%.1f" % v) if hi > 1.0 else ("%d%%" % int(round(v * 100)))
		_emit_settings())
	row.add_child(slider)
	row.add_child(value_label)
	return slider


func _check_row(parent: Control, title: String, value: bool) -> CheckButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var label := _label(20)
	label.text = title
	label.custom_minimum_size = Vector2(300, 0)
	row.add_child(label)
	var check := CheckButton.new()
	check.button_pressed = value
	check.focus_mode = Control.FOCUS_ALL
	check.toggled.connect(func(_on: bool) -> void:
		sound_requested.emit("click")
		_emit_settings())
	row.add_child(check)
	return check


func _emit_settings() -> void:
	if _quiet:
		return
	settings_changed.emit(get_settings())


func get_settings() -> Dictionary:
	return {
		"sensitivity": (_settings_widgets["sensitivity"] as HSlider).value,
		"music": (_settings_widgets["music"] as HSlider).value,
		"sfx": (_settings_widgets["sfx"] as HSlider).value,
		"invert_y": (_settings_widgets["invert_y"] as CheckButton).button_pressed,
		"head_bob": (_settings_widgets["head_bob"] as CheckButton).button_pressed,
		"fullscreen": (_settings_widgets["fullscreen"] as CheckButton).button_pressed,
	}


func apply_settings(settings: Dictionary) -> void:
	_quiet = true
	for id in ["sensitivity", "music", "sfx"]:
		if settings.has(id):
			(_settings_widgets[id] as HSlider).value = float(settings[id])
	for id in ["invert_y", "head_bob", "fullscreen"]:
		if settings.has(id):
			(_settings_widgets[id] as CheckButton).button_pressed = bool(settings[id])
	_quiet = false


# --- Обновление ------------------------------------------------------------------------

func set_age(months: int) -> void:
	var years := months / 12
	var rest := months % 12
	var text := "Возраст: "
	if years > 0:
		text += "%d %s" % [years, _plural(years, "год", "года", "лет")]
		if rest > 0:
			text += " %d мес." % rest
	else:
		text += "%d мес." % rest
	_age.text = text


static func _plural(n: int, one: String, few: String, many: String) -> String:
	var tail := n % 10
	if n % 100 >= 11 and n % 100 <= 14:
		return many
	if tail == 1:
		return one
	if tail >= 2 and tail <= 4:
		return few
	return many


func set_quest(title: String, text: String, index := -1, total := 0) -> void:
	_quest_title.text = title
	_quest_text.text = text
	_quest_progress.text = ("%d / %d" % [index, total]) if index > 0 and total > 0 else ""


func set_skills(skills: Dictionary) -> void:
	for id in _skill_rows:
		_skill_rows[id].value = float(skills.get(id, 0.0))


func set_relations(relations: Dictionary) -> void:
	for id in _relation_rows:
		_relation_rows[id].value = float(relations.get(id, 0.0))


## Шкала равновесия: показывать только на ножках.
func set_balance(show: bool, value: float) -> void:
	_balance_box.visible = show
	_balance_bar.value = value
	var fill: StyleBoxFlat = _balance_bar.get_theme_stylebox("fill")
	fill.bg_color = Color("#6ad17a").lerp(Color("#ff5a5a"), 1.0 - clampf(value, 0.0, 1.0))


func set_controls_text(text: String) -> void:
	_controls.text = text


func set_version(text: String) -> void:
	_version.text = text


## Всплывающее «+5 Ноги» рядом со шкалой навыка: поднимается и тает.
func skill_popup(id: String, amount: float) -> void:
	if not _skill_rows.has(id) or not _skill_panel.visible:
		return
	var bar: ProgressBar = _skill_rows[id]
	var popup := _label(22, SKILL_COLORS.get(id, GOLD))
	popup.text = "+%d %s" % [int(round(amount)), SKILL_TITLES.get(id, id)]
	popup.add_theme_constant_override("outline_size", 8)
	add_child(popup)
	popup.global_position = bar.global_position + Vector2(-150, -8)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position:y", popup.position.y - 44, 1.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(popup, "modulate:a", 0.0, 1.3).set_ease(Tween.EASE_IN).set_delay(0.4)
	tween.chain().tween_callback(popup.queue_free)


## Баннер по центру: «Задание выполнено!» и название.
func quest_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = true
	_banner.modulate = Color(1, 1, 1, 0)
	_banner.scale = Vector2(0.6, 0.6)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_banner, "modulate:a", 1.0, 0.25)
	tween.tween_property(_banner, "scale", Vector2(1, 1), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.chain().tween_interval(1.6)
	tween.chain().tween_property(_banner, "modulate:a", 0.0, 0.5)
	tween.chain().tween_callback(func() -> void: _banner.visible = false)


## Короткая вспышка экрана (падение — красноватая, награда — золотая).
func flash(color: Color, seconds := 0.35) -> void:
	_flash.color = color
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 0.0, seconds)


## Реплика родителя внизу экрана на несколько секунд.
func say(who: String, text: String, seconds := 4.0) -> void:
	_speech_name.text = who
	_speech_text.text = text
	_speech_panel.visible = true
	_speech_panel.modulate = Color(1, 1, 1, 0)
	create_tween().tween_property(_speech_panel, "modulate:a", 1.0, 0.2)
	_speech_timer = seconds
	print("%s: %s" % [who, text])


func toast(text: String, seconds := 2.5) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_timer = seconds
	print("Сообщение: %s" % text)


func set_lamp_text(bbcode: String) -> void:
	_lamp_text.text = bbcode


func toggle_lamp() -> void:
	_lamp_panel.visible = not _lamp_panel.visible
	_skill_panel.visible = not _lamp_panel.visible  # подсказка занимает правый край, навыки на время прячутся
	lamp_toggled.emit(_lamp_panel.visible)


func lamp_open() -> bool:
	return _lamp_panel.visible


func _set_ui_open(open: bool) -> void:
	ui_open = open
	_dim.visible = open and (_menu.visible or _pause.visible or _settings.visible or _end_panel.visible)
	if open:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif not DisplayServer.is_touchscreen_available() and DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _hud_visible(on: bool) -> void:
	# В меню игровые панели прячутся, чтобы экран был чистым.
	for node in [_skill_panel, _lamp_button, _hint, _controls, _balance_box, _quest_title.get_parent().get_parent()]:
		(node as Control).visible = on
	if not on:
		_lamp_panel.visible = false


# --- Меню -----------------------------------------------------------------------------------

func show_main_menu(has_save: bool) -> void:
	_pause.visible = false
	_settings.visible = false
	_end_panel.visible = false
	_intro.visible = false
	_menu_continue.visible = has_save
	_menu.visible = true
	_version.visible = true
	_hud_visible(false)
	_set_ui_open(true)
	(_menu_continue if has_save else _menu_first).grab_focus()


func hide_main_menu() -> void:
	_menu.visible = false
	_version.visible = false
	_hud_visible(true)
	_set_ui_open(false)


func main_menu_open() -> bool:
	return _menu.visible


func show_pause() -> void:
	_pause.visible = true
	_set_ui_open(true)
	_pause_first.grab_focus()


func hide_pause() -> void:
	_pause.visible = false
	_settings.visible = false
	_set_ui_open(false)


func pause_open() -> bool:
	return _pause.visible or (_settings.visible and _settings_from == "pause")


func _show_settings(from: String) -> void:
	_settings_from = from
	_menu.visible = false
	_pause.visible = false
	_settings.visible = true
	_set_ui_open(true)
	(_settings_widgets["sensitivity"] as HSlider).grab_focus()


func _settings_back_pressed() -> void:
	_settings.visible = false
	if _settings_from == "pause":
		_pause.visible = true
		_pause_first.grab_focus()
	else:
		_menu.visible = true
		(_menu_continue if _menu_continue.visible else _menu_first).grab_focus()
	_set_ui_open(true)


## Esc: закрыть то, что открыто (настройки → назад, пауза → продолжить). true — нажатие обработано.
func handle_escape() -> bool:
	if _settings.visible:
		_settings_back_pressed()
		return true
	if _pause.visible:
		menu_action.emit("resume")
		return true
	if _lamp_panel.visible:
		toggle_lamp()
		return true
	return false


func _on_menu_button(id: String) -> void:
	match id:
		"settings_menu":
			_show_settings("menu")
		"settings_pause":
			_show_settings("pause")
		"settings_back":
			_settings_back_pressed()
		_:
			menu_action.emit(id)


func show_intro() -> void:
	_intro.visible = true
	_set_ui_open(true)


func _close_intro() -> void:
	_intro.visible = false
	_set_ui_open(false)
	intro_closed.emit()


## Мини-игра с буквами: rounds — массив {"question": "...", "options": ["А","Б","В"], "answer": 0}.
func start_letters(rounds: Array, kind := "letters") -> void:
	_rounds = rounds
	_round = 0
	_correct = 0
	_wrong = 0
	_game_kind = kind
	_game_panel.visible = true
	_set_ui_open(true)
	_show_round()


## Мини-игра «сон»: мигают три звёздочки, нужно нажать ту, что светится. rounds — сколько раз.
func start_dream(rounds: int) -> void:
	var list := []
	for i in rounds:
		list.append({"question": "Тебе снится сон. Поймай звёздочку, которая светится!", "options": ["☆", "☆", "☆"], "answer": randi() % 3})
	start_letters(list, "dream")


func _show_round() -> void:
	if _round >= _rounds.size():
		_finish_game()
		return
	var data: Dictionary = _rounds[_round]
	_game_question.text = str(data["question"])
	var options: Array = data["options"]
	for i in 3:
		_game_options[i].text = str(options[i]) if i < options.size() else ""
		_game_options[i].visible = i < options.size()
		_game_options[i].add_theme_color_override("font_color", Color.WHITE)
	_dream_blink = int(data["answer"]) if _game_kind == "dream" else -1
	_dream_timer = 0.0
	_auto_timer = 0.6
	if _game_kind == "dream":
		_game_note.text = "Раунд %d из %d. Нажми 1, 2 или 3, когда звёздочка загорится" % [_round + 1, _rounds.size()]
	else:
		_game_note.text = "Вопрос %d из %d. Нажми 1, 2 или 3 на клавиатуре или щёлкни мышью" % [_round + 1, _rounds.size()]


func _pick(index: int) -> void:
	if not _game_panel.visible or _round >= _rounds.size():
		return
	var data: Dictionary = _rounds[_round]
	if index == int(data["answer"]):
		_correct += 1
		sound_requested.emit("correct")
		toast("Верно!", 1.2)
		_round += 1
		_show_round()
	else:
		_wrong += 1
		sound_requested.emit("wrong")
		if _game_kind == "dream":
			toast("Мимо! Жди, когда загорится", 1.2)
		else:
			toast("Не та буква, попробуй ещё", 1.5)


func _finish_game() -> void:
	_game_panel.visible = false
	_set_ui_open(false)
	var result := {"kind": _game_kind, "correct": _correct, "wrong": _wrong, "rounds": _rounds.size()}
	print("Мини-игра «%s» окончена: верно %d, ошибок %d" % [_game_kind, _correct, _wrong])
	minigame_finished.emit(result)


func show_end(bbcode: String) -> void:
	_end_text.text = bbcode
	_end_panel.visible = true
	_set_ui_open(true)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode
	if _intro.visible:
		if key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
			sound_requested.emit("click")
			_close_intro()
		get_viewport().set_input_as_handled()
		return
	if _game_panel.visible:
		if key == KEY_1 or key == KEY_KP_1:
			_pick(0)
		elif key == KEY_2 or key == KEY_KP_2:
			_pick(1)
		elif key == KEY_3 or key == KEY_KP_3:
			_pick(2)
		get_viewport().set_input_as_handled()
		return


func _process(delta: float) -> void:
	if _speech_panel.visible:
		_speech_timer -= delta
		if _speech_timer <= 0.0:
			_speech_panel.visible = false
	if _toast.visible:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast.visible = false
	if _game_panel.visible:
		if _game_kind == "dream":
			_dream_timer += delta
			var lit := fmod(_dream_timer, 1.6) > 0.8
			for i in 3:
				var button := _game_options[i]
				if i == _dream_blink and lit:
					button.text = "★"
					button.add_theme_color_override("font_color", Color("#ffe060"))
				else:
					button.text = "☆"
					button.add_theme_color_override("font_color", Color("#8aa0d0"))
		if auto_pick:
			_auto_timer -= delta
			if _auto_timer <= 0.0 and _round < _rounds.size():
				if _game_kind != "dream" or fmod(_dream_timer, 1.6) > 0.8:
					_pick(int(_rounds[_round]["answer"]))
					_auto_timer = 0.6
