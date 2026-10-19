extends Node2D

## Облако для 2D-примера, нарисованное кодом: ряд белых кругов с лёгкой тенью снизу.
## Размер задаётся в width и height. Как платформа лежит внутри StaticBody2D с прямоугольной формой
## того же размера (верх облака совпадает с верхом формы); без тела это просто украшение неба.

@export var width := 200.0
@export var height := 32.0
@export var tint := Color("#ffffff")


func _draw() -> void:
	var shadow := Color(0.76, 0.83, 0.93)
	var half := width * 0.5
	var r := height * 0.65
	var n := int(width / 40.0) + 1
	for layer_index in [1, 0]:  # сначала тень со сдвигом вниз, потом белое
		var color := shadow if layer_index == 1 else tint
		var dy := 5.0 if layer_index == 1 else 0.0
		for i in range(n):
			var t := float(i) / float(maxi(n - 1, 1))
			var x := lerpf(-half + r * 0.6, half - r * 0.6, t)
			var radius := r * (0.75 + 0.25 * sin(t * PI))
			draw_circle(Vector2(x, dy + height * 0.1), radius, color)
		draw_rect(Rect2(-half + r * 0.3, dy - height * 0.1, width - r * 0.6, height * 0.6), color)
