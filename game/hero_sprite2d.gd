extends AnimatedSprite2D

## Человечек из картинок Kenney (CC0) для 2D-примера: кадры stand / walk / jump / duck / cheer собираются
## в анимации кодом, без отдельного файла SpriteFrames. Смотрит в сторону движения, при ходьбе шагает,
## в прыжке и падении поза jump, в приседе duck; после победы cheer (вызывает sungoal2d.gd через cheer()).
## Ноги стоят на низу капсулы персонажа (24 px). Другой персонаж: поменяйте PREFIX, например "adventurer".

const DIR := "res://assets/kenney/platformer/"
const PREFIX := "player"
const FEET_Y := 24.0
const SPRITE_SCALE := 0.5

var _facing := 1.0
var _cheering := false


func _ready() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	_add(frames, "stand", ["stand"], 5.0)
	_add(frames, "walk", ["walk1", "walk2"], 8.0)
	_add(frames, "jump", ["jump"], 5.0)
	_add(frames, "duck", ["duck"], 5.0)
	_add(frames, "cheer", ["cheer1", "stand"], 4.0)
	sprite_frames = frames
	scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	var tex: Texture2D = frames.get_frame_texture("stand", 0)
	if tex != null:
		position = Vector2(0.0, FEET_Y - tex.get_height() * SPRITE_SCALE * 0.5)
	play("stand")


func _add(frames: SpriteFrames, anim: String, names: Array, fps: float) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, true)
	for n in names:
		var path := "%s%s_%s.png" % [DIR, PREFIX, n]
		if ResourceLoader.exists(path):
			frames.add_frame(anim, load(path))
		else:
			push_warning("hero_sprite2d: нет картинки %s" % path)


func _process(_delta: float) -> void:
	var body := get_parent() as CharacterBody2D
	if body == null:
		return
	if absf(body.velocity.x) > 1.0:
		_facing = signf(body.velocity.x)
	flip_h = _facing < 0.0
	var anim := "stand"
	if _cheering:
		anim = "cheer"
	elif body.get("is_crouched") == true:
		anim = "duck"
	elif not body.is_on_floor():
		anim = "jump"
	elif absf(body.velocity.x) > 1.0:
		anim = "walk"
	if animation != anim:
		play(anim)


func cheer() -> void:
	_cheering = true
