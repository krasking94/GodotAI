extends Node3D

func _ready() -> void:
	print("Комната готова: %d объектов" % get_child_count())
