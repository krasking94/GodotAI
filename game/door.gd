extends Node3D

## Дверь: створка Panel поворачивается вокруг петли (начало координат узла).
## E открывает и закрывает; если locked, сначала нужен предмет key_name у персонажа
## (в выводе «Дверь … заперта: нужен Ключ»). Состояние open/locked сохраняется (группа persist).

@export var open := false
@export var locked := false
@export var key_name := "Ключ"
@export var open_angle := 100.0  # градусов поворота створки в открытом состоянии
@export var swing_time := 0.6    # секунд на открывание

@onready var panel: Node3D = $Panel
var _tween: Tween


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("persist")
	panel.rotation_degrees.y = open_angle if open else 0.0


func prompt() -> String:
	if open:
		return "E — закрыть дверь"
	if locked:
		return "E — открыть дверь (заперта, нужен %s)" % key_name
	return "E — открыть дверь"


func interact(player: Node) -> void:
	if locked:
		if player != null and player.has_method("has_item") and player.has_item(key_name):
			locked = false
			print("Дверь «%s» отперта: у персонажа есть %s" % [name, key_name])
		else:
			print("Дверь «%s» заперта: нужен %s" % [name, key_name])
			return
	open = not open
	_animate()
	print("Дверь «%s» %s" % [name, "открыта" if open else "закрыта"])


func _animate() -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(panel, "rotation_degrees:y", open_angle if open else 0.0, swing_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func save_state() -> Dictionary:
	return {"open": open, "locked": locked}


func load_state(state: Dictionary) -> void:
	open = bool(state.get("open", open))
	locked = bool(state.get("locked", locked))
	if _tween != null:
		_tween.kill()
	panel.rotation_degrees.y = open_angle if open else 0.0
