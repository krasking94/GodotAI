extends Node2D

## Небо для 2D-примера: вертикальный градиент на весь экран, нарисованный кодом.
## Лежит в CanvasLayer, поэтому не двигается с камерой и перерисовывается при смене размера окна.

@export var top_color := Color("#4f9cf5")
@export var bottom_color := Color("#d0f4f7")  # как небо на фоне Kenney colored_grass.png


func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)


func _draw() -> void:
	var size := get_viewport_rect().size
	var points := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)])
	var colors := PackedColorArray([top_color, top_color, bottom_color, bottom_color])
	draw_polygon(points, colors)
