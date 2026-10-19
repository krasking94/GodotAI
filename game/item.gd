extends Node3D

## Предмет, который можно подобрать: E кладёт его в инвентарь персонажа (player.add_item),
## предмет исчезает с земли. Медленно вращается, чтобы его было видно. Состояние picked сохраняется.

@export var item_name := "Ключ"
@export var spin_speed := 1.5  # радиан в секунду

var picked := false


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("persist")


func _process(delta: float) -> void:
	if not picked:
		rotate_y(spin_speed * delta)


func prompt() -> String:
	return "E — подобрать %s" % item_name


func interact(player: Node) -> void:
	if picked:
		return
	if player != null and player.has_method("add_item"):
		player.add_item(item_name)
	_set_picked(true)
	print("Подобран предмет «%s»" % item_name)


func _set_picked(value: bool) -> void:
	picked = value
	visible = not value
	if value:
		remove_from_group("interactables")
	elif not is_in_group("interactables"):
		add_to_group("interactables")


func save_state() -> Dictionary:
	return {"picked": picked}


func load_state(state: Dictionary) -> void:
	_set_picked(bool(state.get("picked", picked)))
