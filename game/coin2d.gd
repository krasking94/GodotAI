extends Area2D

## Монетка для 2D-примера: рисуется кодом (золотой кружок с ободком и бликом), слегка покачивается,
## исчезает, когда персонаж её касается, и пишет в журнал, сколько собрано. Счёт показывает hud2d.gd.

static var collected := 0
static var total := 0

var _time := 0.0


func _ready() -> void:
	total += 1
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var bob := Vector2(0.0, sin(_time * 3.0) * 3.0)
	draw_circle(bob, 12.0, Color("#c98a00"))
	draw_circle(bob, 9.0, Color("#ffd23c"))
	draw_circle(bob + Vector2(-3.0, -3.0), 2.5, Color("#fff2a8"))


func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		collected += 1
		print("Монетка собрана! Всего: %d из %d" % [collected, total])
		queue_free()
