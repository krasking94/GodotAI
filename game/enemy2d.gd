extends Area2D

## Враг для 2D-примера на картинках Kenney (assets/kenney/platformer/enemies): слизень ходит по облаку
## туда-сюда, пчела летает и покачивается. Прыжок на врага сверху раздавливает его и подбрасывает
## персонажа; касание сбоку или снизу отнимает жизнь (вызывает hurt() у персонажа). Кадры <kind>.png и
## <kind>_move.png собираются в анимацию кодом, после смерти показывается <kind>_dead.png.
## Форму столкновения задаёт дочерний CollisionShape2D (слизень: прямоугольник 40×28 со сдвигом [0, 17],
## пчела: 36×36 со сдвигом [0, 1]); body_top — верх тела относительно узла: если центр персонажа выше него
## и персонаж падает, это прыжок сверху, иначе ранение.

const DIR := "res://assets/kenney/platformer/enemies/"
const SPRITE_SCALE := 0.5
const BOUNCE_SPEED := -380.0

@export var kind := "slimeGreen"
@export var speed := 60.0
@export var patrol := 90.0  # на сколько px уходит влево и вправо от начальной точки
@export var flying := false
@export var body_top := 1.0

var _start := Vector2.ZERO
var _dir := 1.0
var _dead := false
var _time := 0.0
var _sprite: AnimatedSprite2D


func _ready() -> void:
	_start = global_position
	body_entered.connect(_on_body_entered)
	_sprite = AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("move")
	frames.set_animation_speed("move", 4.0)
	for n in [kind, kind + "_move"]:
		if ResourceLoader.exists(DIR + n + ".png"):
			frames.add_frame("move", load(DIR + n + ".png"))
	frames.add_animation("dead")
	if ResourceLoader.exists(DIR + kind + "_dead.png"):
		frames.add_frame("dead", load(DIR + kind + "_dead.png"))
	if frames.get_frame_count("move") == 0:
		push_warning("enemy2d: нет картинок для «%s» в %s" % [kind, DIR])
	_sprite.sprite_frames = frames
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	add_child(_sprite)
	_sprite.play("move")


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_time += delta
	global_position.x += _dir * speed * delta
	if absf(global_position.x - _start.x) > patrol:
		_dir = -_dir
		global_position.x = _start.x + clampf(global_position.x - _start.x, -patrol, patrol)
	_sprite.flip_h = _dir > 0.0
	if flying:
		global_position.y = _start.y + sin(_time * 2.5) * 12.0


func _on_body_entered(body: Node2D) -> void:
	if _dead or not body is CharacterBody2D:
		return
	# Прыжок сверху: персонаж падает и его центр выше верха врага (так засчитывается и приземление на край).
	if body.velocity.y > 0.0 and body.global_position.y < global_position.y + body_top:
		_squash(body)
	elif body.has_method("hurt"):
		body.hurt()


func _squash(body: CharacterBody2D) -> void:
	_dead = true
	_sprite.play("dead")
	set_deferred("monitoring", false)
	body.velocity.y = BOUNCE_SPEED
	print("Враг %s раздавлен" % name)
	var hud := get_tree().root.find_child("Hud", true, false)
	if hud != null and hud.has_method("play_sound"):
		hud.play_sound("stomp")
	get_tree().create_timer(0.8).timeout.connect(queue_free)
