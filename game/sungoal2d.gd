extends Area2D

## Солнце как цель уровня (2D-пример): когда персонаж допрыгивает до солнца, в журнал и на экран
## (через hud2d.gd) выводится надпись о победе. Само солнце рисует дочерний узел со скриптом sun2d.gd.

var reached := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if reached or not body is CharacterBody2D:
		return
	reached = true
	print("Ты добрался до солнца! Победа")
	var look := body.get_node_or_null("Look")
	if look != null and look.has_method("cheer"):
		look.cheer()
	var hud := get_tree().root.find_child("Hud", true, false)  # ищем от корня: при запуске для снимка current_scene не задана
	if hud != null and hud.has_method("win"):
		hud.win()
	elif hud != null and hud.has_method("show_message"):
		hud.show_message("Ты добрался до солнца!")
