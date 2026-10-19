extends VehicleBody3D

## Машина на упрощённой физике Godot (VehicleBody3D: кузов + четыре VehicleWheel3D).
## Управление, пока active: W/S (или стрелки) — газ и задний ход, A/D — руль,
## пробел — тормоз, R — поставить на колёса, если перевернулась (одно нажатие, только когда лежит). Пока active выключен
## (водителя нет), машина стоит на ручнике; персонаж включает active, садясь в неё (клавиша E).
## S на ходу сначала тормозит, и только когда машина почти остановилась, включает задний ход.
## Руль на скорости становится мягче, а выше MAX_SPEED мотор не разгоняет: так машина не переворачивается.
##
## Самопроверка для ИИ: test_program = "gas:2,left:2,brake:1" (фазы через запятую, секунды после двоеточия;
## фазы: gas, reverse, left, right, gasleft, gasright, brake, coast, flip). После каждой фазы печатается строка
## «Машина [фаза]: скорость, путь, поворот курса, крен», по ней ИИ видит в логе, как машина себя ведёт.
## test_drive > 0 — то же, что test_program = "gas:<секунды>".

const ENGINE_FORCE := 2400.0
const BRAKE_FORCE := 110.0
const MAX_SPEED := 14.0       # м/с, около 50 км/ч
const MAX_STEER := 0.55       # радианы на месте
const MIN_STEER := 0.18       # радианы на максимальной скорости
const STEER_SPEED := 2.5
const REVERSE_SWITCH_SPEED := 0.8

@export var active := true
@export var test_drive := 0.0
@export var test_program := ""

var _phases: Array = []        # [{"name": "gas", "seconds": 2.0}, ...]
var _phase_index := 0
var _phase_time := 0.0
var _phase_start_pos := Vector3.ZERO
var _phase_start_yaw := 0.0
var _speed_label: Label  # спидометр в углу экрана, виден пока active
var _r_was_down := false  # чтобы R срабатывала по нажатию, а не пока зажата


func _ready() -> void:
	add_to_group("cars")  # по этой группе персонаж находит, куда сесть (E)
	_speed_label = Label.new()
	_speed_label.add_theme_font_size_override("font_size", 32)
	_speed_label.position = Vector2(24, 16)
	var layer := CanvasLayer.new()
	layer.name = "Speedometer"
	layer.add_child(_speed_label)
	add_child(layer)
	if test_program == "" and test_drive > 0.0:
		test_program = "gas:%s" % test_drive
	# enginectl game run --test car=gas:2,brake:1 передаёт аргумент --test-car=…, он важнее сцены.
	var prefix := "--test-car="
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			test_program = arg.trim_prefix(prefix)
	for part in test_program.split(",", false):
		var pair := part.strip_edges().split(":")
		if pair.size() == 2 and pair[1].is_valid_float():
			_phases.append({"name": pair[0].strip_edges(), "seconds": float(pair[1])})
	_begin_phase()


func _physics_process(delta: float) -> void:
	var gas := 0.0
	var steer_input := 0.0
	var braking := false
	var speed := linear_velocity.length()
	var forward_speed := global_transform.basis.z.dot(linear_velocity)  # у VehicleBody3D вперёд = +Z (проверено заездом)

	if _phase_index < _phases.size():
		match _phases[_phase_index]["name"]:
			"gas":
				gas = 1.0
			"reverse":
				gas = -1.0
			"left":
				gas = 0.6
				steer_input = 1.0
			"right":
				gas = 0.6
				steer_input = -1.0
			"gasleft":  # газ в пол и руль до упора: проверка на переворот
				gas = 1.0
				steer_input = 1.0
			"gasright":
				gas = 1.0
				steer_input = -1.0
			"brake":
				braking = true
			"flip":  # проверка клавиши R: положить на бок и поставить обратно
				if _phase_time == 0.0:
					global_transform.basis = Basis(Vector3.BACK, PI * 0.6)
				elif _phase_time > 0.5 and is_flipped():
					flip_upright()
		_phase_time += delta
		if _phase_time >= _phases[_phase_index]["seconds"]:
			_report_phase(speed)
			_phase_index += 1
			_begin_phase()
	elif active:
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			gas += 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			if forward_speed > REVERSE_SWITCH_SPEED:
				braking = true  # на ходу S — это тормоз
			else:
				gas -= 1.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			steer_input += 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			steer_input -= 1.0
		if Input.is_physical_key_pressed(KEY_SPACE):
			braking = true
		# R срабатывает один раз за нажатие (а не каждый кадр, пока зажата) и только если машина
		# действительно лежит на боку или на крыше: иначе каждый кадр подбрасывал бы её на полметра.
		var r_down := Input.is_physical_key_pressed(KEY_R)
		if r_down and not _r_was_down:
			if is_flipped():
				flip_upright()
			else:
				print("Машина и так на колёсах, R не нужна")
		_r_was_down = r_down
	else:
		braking = true  # без водителя машина стоит на ручнике

	# Выше MAX_SPEED мотор не толкает вперёд (назад — вполовину медленнее).
	if gas > 0.0 and forward_speed > MAX_SPEED:
		gas = 0.0
	elif gas < 0.0 and -forward_speed > MAX_SPEED * 0.5:
		gas = 0.0
	engine_force = gas * ENGINE_FORCE
	var steer_limit := lerpf(MAX_STEER, MIN_STEER, clampf(speed / MAX_SPEED, 0.0, 1.0))
	steering = move_toward(steering, steer_input * steer_limit, STEER_SPEED * delta)
	brake = BRAKE_FORCE if braking else 0.0
	_speed_label.visible = active
	if active:
		_speed_label.text = "%d км/ч" % roundi(absf(forward_speed) * 3.6)


## Лежит ли машина на боку или на крыше (верх кузова отклонён от вертикали больше ~45°).
func is_flipped() -> bool:
	return global_transform.basis.y.dot(Vector3.UP) < 0.7


## Ставит машину на колёса на том же месте (после переворота).
func flip_upright() -> void:
	var yaw := global_transform.basis.get_euler().y
	global_transform.basis = Basis(Vector3.UP, yaw)
	global_position += Vector3.UP * 0.5
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _begin_phase() -> void:
	_phase_time = 0.0
	_phase_start_pos = global_position
	_phase_start_yaw = global_transform.basis.get_euler().y


func _report_phase(speed: float) -> void:
	var phase: Dictionary = _phases[_phase_index]
	var distance := global_position.distance_to(_phase_start_pos)
	var yaw_change := rad_to_deg(wrapf(global_transform.basis.get_euler().y - _phase_start_yaw, -PI, PI))
	var tilt := rad_to_deg(acos(clampf(global_transform.basis.y.dot(Vector3.UP), -1.0, 1.0)))
	var turn := "прямо"
	if yaw_change > 5.0:
		turn = "влево на %.0f°" % yaw_change
	elif yaw_change < -5.0:
		turn = "вправо на %.0f°" % -yaw_change
	var forward_speed := global_transform.basis.z.dot(linear_velocity)
	var heading := "вперёд" if forward_speed >= 0.0 else "назад"
	print("Машина [%s %.1f с]: скорость %.1f м/с (%s), путь %.1f м, курс %s, крен %.0f°%s" % [
		phase["name"], phase["seconds"], speed, heading, distance, turn, tilt, " (ПЕРЕВЕРНУЛАСЬ)" if tilt > 90.0 else ""])
