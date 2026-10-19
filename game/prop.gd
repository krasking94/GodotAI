extends Node3D

## Декорация из готовой модели (glTF), в которую нельзя пройти: при запуске каждому мешу модели
## добавляется точная форма столкновений по его геометрии (create_trimesh_collision), так что
## персонаж и машина упираются в фонтан, домик или дерево, а не проходят сквозь них.
## Вешается на корень экземпляра модели: {"op": "instance", "scene": "res://assets/kenney/city/pavement-fountain.glb",
## "props": {"script": "res://game/prop.gd"}}. solid = false оставляет модель «призраком» (декорация вдали).
## В выводе строка «Предмет «Fountain»: столкновения для N мешей», по ней ИИ видит, что формы созданы.

@export var solid := true


func _ready() -> void:
	if not solid:
		return
	var count := 0
	for mesh in find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).create_trimesh_collision()
		count += 1
	print("Предмет «%s»: столкновения для %d мешей" % [name, count])
