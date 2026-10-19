extends Node2D

## Человечек для 2D-примера, нарисованный кодом (без картинок): голова с волосами и лицом, футболка,
## штаны, руки и ноги. Смотрит в сторону движения, ноги шагают при ходьбе, в прыжке поднимает руки,
## в приседе фигура ниже. Размеры совпадают с капсулой персонажа: стоя 48 px (от −24 до 24),
## в приседе 28 px (от −4 до 24). Цвета меняются в константах ниже.

const SKIN := Color("#f1c27d")
const SHIRT := Color("#e0453c")
const PANTS := Color("#2f4f8f")
const HAIR := Color("#4a2e1a")
const SHOES := Color("#222222")

var _facing := 1.0
var _walk := 0.0


func _process(delta: float) -> void:
	var body := get_parent() as CharacterBody2D
	if body != null:
		if absf(body.velocity.x) > 1.0:
			_facing = signf(body.velocity.x)
			if body.is_on_floor():
				_walk += delta * 12.0
		else:
			_walk = 0.0
	queue_redraw()


func _draw() -> void:
	var body := get_parent() as CharacterBody2D
	var crouched: bool = body != null and body.get("is_crouched") == true
	var in_air: bool = body != null and not body.is_on_floor()
	var top := -4.0 if crouched else -24.0  # верх фигуры; ноги всегда стоят на 24
	var head_r := 7.0
	var head := Vector2(0.0, top + head_r)
	var torso_top := top + 2.0 * head_r
	var legs_top := 16.0 if crouched else 6.0
	var swing := 3.0 if in_air else sin(_walk) * 5.0
	draw_rect(Rect2(-7.0 + swing, legs_top, 6.0, 24.0 - legs_top), PANTS)
	draw_rect(Rect2(1.0 - swing, legs_top, 6.0, 24.0 - legs_top), PANTS)
	draw_rect(Rect2(-8.0 + swing, 21.0, 8.0, 3.0), SHOES)
	draw_rect(Rect2(0.0 - swing, 21.0, 8.0, 3.0), SHOES)
	draw_rect(Rect2(-8.0, torso_top, 16.0, legs_top - torso_top), SHIRT)
	var arm_y := torso_top - 8.0 if in_air else torso_top + 2.0
	draw_rect(Rect2(-12.0, arm_y, 4.0, 10.0), SKIN)
	draw_rect(Rect2(8.0, arm_y, 4.0, 10.0), SKIN)
	draw_circle(head, head_r, SKIN)
	draw_rect(Rect2(-head_r, top, 2.0 * head_r, 3.5), HAIR)
	draw_circle(head + Vector2(3.0 * _facing, -1.0), 1.5, Color.BLACK)
	draw_arc(head + Vector2(1.5 * _facing, 2.0), 3.0, 0.3, PI - 0.3, 8, Color.BLACK, 1.0)
