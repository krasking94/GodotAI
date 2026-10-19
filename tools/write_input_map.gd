extends SceneTree

## Записывает таблицу действий из game/actions.gd в project.godot (раздел [input]).
## Запуск: Godot --headless --path . --script res://tools/write_input_map.gd (редактор лучше закрыть).

func _init() -> void:
	var actions = load("res://game/actions.gd")
	for action in actions.TABLE:
		var events: Array = []
		for key in actions.TABLE[action]:
			var event := InputEventKey.new()
			event.device = -1  # любая клавиатура
			event.physical_keycode = key
			events.append(event)
		ProjectSettings.set_setting("input/%s" % action, {"deadzone": 0.2, "events": events})
	var err := ProjectSettings.save()
	print("Карта действий: %d действий записано в project.godot (%s)" % [actions.TABLE.size(), error_string(err)])
	quit()
