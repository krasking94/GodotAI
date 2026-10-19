extends Area2D

## Монетка для 2D-примера: исчезает, когда персонаж её касается, и пишет в журнал, сколько собрано.

static var collected := 0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		collected += 1
		print("Монетка собрана! Всего: %d" % collected)
		queue_free()
