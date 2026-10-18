extends Node3D

func _ready() -> void:
	print("Двор готов: %d объектов" % get_child_count())
