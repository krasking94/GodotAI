extends CanvasLayer

## Экран «Симулятора жизни»: возраст и текущее задание (слева сверху), навыки и отношения с родителями
## (справа сверху), лампочка-подсказка (кнопка справа: что делать, куда идти, какие клавиши),
## подсказка у предмета (внизу), реплики родителей (внизу по центру), предисловие в начале,
## мини-игры с буквами и сном (по центру, выбор клавишами 1 2 3), итог этапа.
## Все окна управляются клавишами, мышь нужна только для обзора. Игра (ls_game.gd) зовёт методы
## set_age, set_quest, set_skills, set_relations, say, show_intro, start_letters, start_dream, show_end.
## Любое открытое окно ставит ui_open = true: герой тогда не ходит и не крутит головой.

signal minigame_finished(result: Dictionary)
signal intro_closed
signal lamp_toggled(open: bool)

const SKILL_TITLES := {"legs": "Ноги", "hands": "Руки", "speech": "Речь", "mind": "Ум", "heart": "Сердце"}
const SKILL_COLORS := {"legs": Color("#6ad17a"), "hands": Color("#f0a860"), "speech": Color("#6fb8ff"),
	"mind": Color("#c89bff"), "heart": Color("#ff7a9a")}

var ui_open := false
var auto_pick := false  # самопроверка: в мини-играх отвечать правильно само

var _age: Label
var _quest_title: Label
var _quest_text: Label
var _hint: Label
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
var _rounds: Array = []
var _round := 0
var _correct := 0
var _wrong := 0
var _game_kind := ""
var _dream_blink := -1
var _dream_timer := 0.0
var _auto_timer := 0.0


func _ready() -> void:
	layer = 10
	_build_top_left()
	_build_top_right()
	_build_bottom()
	_build_lamp()
	_build_speech()
	_build_minigame()
	_build_intro()
	_build_end()
	_build_toast()


func hint_label() -> Label:
	return _hint


# --- Сборка ---------------------------------------------------------------------------

func _panel_style(color: Color, border: Color = Color(1, 1, 1, 0.25)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(14)
	box.set_content_margin_all(16)
	return box


func _label(size: int, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _build_top_left() -> void:
	var panel := PanelContainer.new()
	panel.name = "QuestPanel"
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.1, 0.16, 0.72)))
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(420, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_age = _label(22, Color("#ffe08a"))
	_age.text = "Возраст: 0 мес."
	box.add_child(_age)
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
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.1, 0.16, 0.72)))
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -300
	panel.offset_right = -84
	panel.offset_top = 20
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := _label(20, Color("#ffe08a"))
	title.text = "Навыки"
	box.add_child(title)
	for id in SKILL_TITLES:
		_skill_rows[id] = _bar_row(box, SKILL_TITLES[id], SKILL_COLORS[id])
	var title2 := _label(20, Color("#ffe08a"))
	title2.text = "Родители"
	box.add_child(title2)
	_relation_rows["mom"] = _bar_row(box, "Мама", Color("#ff9ac0"))
	_relation_rows["dad"] = _bar_row(box, "Папа", Color("#8ac0ff"))


func _bar_row(parent: Control, title: String, color: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(17)
	label.text = title
	label.custom_minimum_size = Vector2(72, 0)
	row.add_child(label)
	var bar := ProgressBar.new()
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
	# Прицел: точка в центре, чтобы было понятно, куда смотришь.
	var dot := ColorRect.new()
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
	_lamp_button.pressed.connect(toggle_lamp)
	add_child(_lamp_button)
	var under := _label(14, Color("#ffe08a"))
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
	_lamp_text.bbcode_enabled = true
	_lamp_text.fit_content = true
	_lamp_text.custom_minimum_size = Vector2(470, 0)
	_lamp_text.add_theme_font_size_override("normal_font_size", 18)
	_lamp_text.add_theme_font_size_override("bold_font_size", 20)
	_lamp_panel.add_child(_lamp_text)


func _build_speech() -> void:
	_speech_panel = PanelContainer.new()
	_speech_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.1, 0.08, 0.12, 0.9), Color("#ffb0d0")))
	_speech_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_speech_panel.anchor_left = 0.5
	_speech_panel.anchor_right = 0.5
	_speech_panel.anchor_top = 1.0
	_speech_panel.anchor_bottom = 1.0
	_speech_panel.offset_left = -330
	_speech_panel.offset_right = 330
	_speech_panel.offset_top = -190
	_speech_panel.offset_bottom = -90
	_speech_panel.visible = false
	add_child(_speech_panel)
	var box := VBoxContainer.new()
	_speech_panel.add_child(box)
	_speech_name = _label(20, Color("#ffb0d0"))
	box.add_child(_speech_name)
	_speech_text = _label(22)
	_speech_text.custom_minimum_size = Vector2(620, 0)
	box.add_child(_speech_text)


func _build_minigame() -> void:
	_game_panel = PanelContainer.new()
	_game_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.08, 0.18, 0.95), Color("#8ac0ff")))
	_game_panel.set_anchors_preset(Control.PRESET_CENTER)
	_game_panel.anchor_left = 0.5
	_game_panel.anchor_right = 0.5
	_game_panel.anchor_top = 0.5
	_game_panel.anchor_bottom = 0.5
	_game_panel.offset_left = -360
	_game_panel.offset_right = 360
	_game_panel.offset_top = -170
	_game_panel.offset_bottom = 170
	_game_panel.visible = false
	add_child(_game_panel)
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
	_intro = PanelContainer.new()
	_intro.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.06, 0.12, 0.96), Color("#ffe08a")))
	_intro.set_anchors_preset(Control.PRESET_CENTER)
	_intro.anchor_left = 0.5
	_intro.anchor_right = 0.5
	_intro.anchor_top = 0.5
	_intro.anchor_bottom = 0.5
	_intro.offset_left = -420
	_intro.offset_right = 420
	_intro.offset_top = -250
	_intro.offset_bottom = 250
	_intro.visible = false
	add_child(_intro)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_intro.add_child(box)
	var title := _label(34, Color("#ffe08a"))
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
		"Задание всегда написано слева сверху.\n\n" +
		"[b]Управление.[/b] Мышь — смотреть по сторонам. W A S D — двигаться. E — взять предмет или поговорить. " +
		"Пробел — встать на ножки (когда научишься). H или лампочка справа — подсказка, что делать.\n\n" +
		"[color=#ffe08a]Нажми Enter, чтобы начать.[/color]")
	box.add_child(text)


func _build_end() -> void:
	_end_panel = PanelContainer.new()
	_end_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.06, 0.12, 0.96), Color("#ffe08a")))
	_end_panel.set_anchors_preset(Control.PRESET_CENTER)
	_end_panel.anchor_left = 0.5
	_end_panel.anchor_right = 0.5
	_end_panel.anchor_top = 0.5
	_end_panel.anchor_bottom = 0.5
	_end_panel.offset_left = -380
	_end_panel.offset_right = 380
	_end_panel.offset_top = -220
	_end_panel.offset_bottom = 220
	_end_panel.visible = false
	add_child(_end_panel)
	_end_text = RichTextLabel.new()
	_end_text.bbcode_enabled = true
	_end_text.fit_content = true
	_end_text.custom_minimum_size = Vector2(720, 0)
	_end_text.add_theme_font_size_override("normal_font_size", 21)
	_end_text.add_theme_font_size_override("bold_font_size", 30)
	_end_panel.add_child(_end_text)


func _build_toast() -> void:
	_toast = _label(28, Color("#ffe08a"))
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_left = -400
	_toast.offset_right = 400
	_toast.offset_top = 110
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.visible = false
	add_child(_toast)


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


func set_quest(title: String, text: String) -> void:
	_quest_title.text = title
	_quest_text.text = text


func set_skills(skills: Dictionary) -> void:
	for id in _skill_rows:
		_skill_rows[id].value = float(skills.get(id, 0.0))


func set_relations(relations: Dictionary) -> void:
	for id in _relation_rows:
		_relation_rows[id].value = float(relations.get(id, 0.0))


## Реплика родителя внизу экрана на несколько секунд.
func say(who: String, text: String, seconds := 4.0) -> void:
	_speech_name.text = who
	_speech_text.text = text
	_speech_panel.visible = true
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


func show_intro() -> void:
	_intro.visible = true
	ui_open = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _close_intro() -> void:
	_intro.visible = false
	ui_open = false
	if not DisplayServer.is_touchscreen_available() and DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	intro_closed.emit()


## Мини-игра с буквами: rounds — массив {"question": "...", "options": ["А","Б","В"], "answer": 0}.
func start_letters(rounds: Array, kind := "letters") -> void:
	_rounds = rounds
	_round = 0
	_correct = 0
	_wrong = 0
	_game_kind = kind
	_game_panel.visible = true
	ui_open = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
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
		toast("Верно!", 1.2)
		_round += 1
		_show_round()
	else:
		_wrong += 1
		if _game_kind == "dream":
			toast("Мимо! Жди, когда загорится", 1.2)
		else:
			toast("Не та буква, попробуй ещё", 1.5)


func _finish_game() -> void:
	_game_panel.visible = false
	ui_open = false
	if not DisplayServer.is_touchscreen_available() and DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var result := {"kind": _game_kind, "correct": _correct, "wrong": _wrong, "rounds": _rounds.size()}
	print("Мини-игра «%s» окончена: верно %d, ошибок %d" % [_game_kind, _correct, _wrong])
	minigame_finished.emit(result)


func show_end(bbcode: String) -> void:
	_end_text.text = bbcode
	_end_panel.visible = true
	ui_open = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode
	if _intro.visible:
		if key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
			_close_intro()
		return
	if _game_panel.visible:
		if key == KEY_1 or key == KEY_KP_1:
			_pick(0)
		elif key == KEY_2 or key == KEY_KP_2:
			_pick(1)
		elif key == KEY_3 or key == KEY_KP_3:
			_pick(2)
		return
	if key == KEY_H:
		toggle_lamp()


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
