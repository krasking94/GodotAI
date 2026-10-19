extends StaticBody3D

## Кнопка: E переключает булево свойство у другого узла (по умолчанию visible у цели),
## например включает и выключает солнце. В выводе «Кнопка …: солнце выключено».
## Состояние сохраняется (группа persist).

@export var target: NodePath          # что переключаем, например ../Lamp
@export var property := "visible"     # булево свойство цели
@export var label := "солнце"         # как называть цель в подсказке и выводе

var _target: Node


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("persist")
	_target = get_node_or_null(target)
	if _target == null:
		push_warning("Кнопка «%s»: цель «%s» не найдена" % [name, target])


func is_on() -> bool:
	return _target != null and bool(_target.get(property))


func prompt() -> String:
	return "E — %s %s" % ["выключить" if is_on() else "включить", label]


func interact(_player: Node) -> void:
	if _target == null:
		print("Кнопка «%s»: цель не найдена, нажатие ничего не делает" % name)
		return
	_target.set(property, not is_on())
	print("Кнопка «%s»: %s %s" % [name, label, "включено" if is_on() else "выключено"])


func save_state() -> Dictionary:
	return {"on": is_on()}


func load_state(state: Dictionary) -> void:
	if _target != null and state.has("on"):
		_target.set(property, bool(state["on"]))
