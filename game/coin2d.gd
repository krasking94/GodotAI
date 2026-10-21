extends Area2D

## Монетка для 2D-примера: слегка покачивается, исчезает, когда персонаж её касается, и пишет в журнал,
## сколько собрано (счёт показывает hud2d.gd). Если у узла есть дочерний Sprite2D (картинка Kenney),
## качается он; иначе монетка рисуется кодом (золотой кружок с ободком и бликом).

static var collected := 0
static var total := 0

var _time := 0.0
var _look: Sprite2D = null


func _ready() -> void:
	total += 1
	for child in get_children():
		if child is Sprite2D:
			_look = child
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	if _look != null:
		_look.position.y = sin(_time * 3.0) * 3.0
	else:
		queue_redraw()


func _draw() -> void:
	if _look != null:
		return
	var bob := Vector2(0.0, sin(_time * 3.0) * 3.0)
	draw_circle(bob, 12.0, Color("#c98a00"))
	draw_circle(bob, 9.0, Color("#ffd23c"))
	draw_circle(bob + Vector2(-3.0, -3.0), 2.5, Color("#fff2a8"))


func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		collected += 1
		print("Монетка собрана! Всего: %d из %d" % [collected, total])
		var hud := get_tree().root.find_child("Hud", true, false)
		if hud != null and hud.has_method("add_coin"):
			hud.add_coin()
		queue_free()
