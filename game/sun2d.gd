extends Node2D

## Солнце для 2D-примера: круг с мягким сиянием, нарисованный кодом (без картинок).
## Лежит в CanvasLayer вместе с небом, поэтому стоит на месте, когда камера едет за персонажем.

@export var radius := 48.0
@export var color := Color("#ffd93c")


func _draw() -> void:
	for i in range(4, 0, -1):
		draw_circle(Vector2.ZERO, radius + i * 14.0, Color(color, 0.08))
	draw_circle(Vector2.ZERO, radius, color)
