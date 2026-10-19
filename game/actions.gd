## Карта действий игры: одно место, где записано, какая клавиша что делает.
## Скрипты читают действия (Input.is_action_pressed("move_forward")), а не клавиши, поэтому
## экранные кнопки на телефоне, геймпад и клавиатура работают одинаково: все они «нажимают действие».
## Та же таблица записана в project.godot (раздел [input], см. tools/write_input_map.gd), чтобы её было
## видно в редакторе: Проект → Настройки проекта → Карта действий. ensure() добавляет действия на лету,
## если в настройках их ещё нет (например, проект не перезагружен после обновления).

const TABLE := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"run": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"brake": [KEY_SPACE],
	"interact": [KEY_E],
	"flip": [KEY_R],
	"pause": [KEY_ESCAPE],
	"save": [KEY_F5],
	"load": [KEY_F9],
}


static func ensure() -> void:
	for action in TABLE:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for key in TABLE[action]:
			var event := InputEventKey.new()
			event.device = -1  # любая клавиатура (ALL_DEVICES)
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
