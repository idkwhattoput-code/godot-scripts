extends RigidBody

export var max_engine_force = 1500.0
export var max_brake_force = 500.0
export var max_steer_angle = 0.4
export var steer_speed = 5.0

export var downforce = 100.0
export var max_speed = 200.0

var steer_target = 0.0
var steer_angle = 0.0

var engine_force_value = 0.0
var brake_force_value = 0.0

export var gear_ratios = [3.5, 2.5, 1.8, 1.3, 1.0, 0.8]
var current_gear = 0
var rpm = 0.0
var max_rpm = 6000.0
var min_rpm = 1000.0

var traction_control = true
var abs_enabled = true
var stability_control = true

onready var front_left_wheel = $FrontLeft
onready var front_right_wheel = $FrontRight
onready var rear_left_wheel = $RearLeft
onready var rear_right_wheel = $RearRight

onready var engine_sound = $EngineSound
onready var brake_sound = $BrakeSound
onready var skid_sound = $SkidSound

signal gear_changed(gear)
signal speed_changed(speed)
signal rpm_changed(rpm)

func _ready():
	set_use_custom_integrator(false)
	
	for wheel in [front_left_wheel, front_right_wheel, rear_left_wheel, rear_right_wheel]:
		if wheel:
			wheel.set_use_as_traction(true)
			wheel.set_use_as_steering(false)
	
	if front_left_wheel:
		front_left_wheel.set_use_as_steering(true)
	if front_right_wheel:
		front_right_wheel.set_use_as_steering(true)

func _physics_process(delta):
	_handle_input(delta)
	_update_gear()
	_update_rpm(delta)
	_apply_downforce()
	_update_sounds()
	_apply_traction_control()
	_apply_stability_control(delta)
	
	var speed = linear_velocity.length() * 3.6
	emit_signal("speed_changed", speed)
	emit_signal("rpm_changed", rpm)

func _handle_input(delta):
	var throttle = Input.get_action_strength("accelerate")
	var brake = Input.get_action_strength("brake")
	var steer = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	
	if Input.is_action_just_pressed("handbrake"):
		_apply_handbrake()
	
	if Input.is_action_just_pressed("gear_up"):
		_shift_gear(1)
	elif Input.is_action_just_pressed("gear_down"):
		_shift_gear(-1)
	
	var speed = linear_velocity.length()
	var speed_factor = clamp(speed / 50.0, 0.1, 1.0)
	steer_target = steer * max_steer_angle * (2.0 - speed_factor)
	
	steer_angle = lerp(steer_angle, steer_target, steer_speed * delta)
	
	if front_left_wheel:
		front_left_wheel.set_steering(steer_angle)
	if front_right_wheel:
		front_right_wheel.set_steering(steer_angle)
	
	var gear_ratio = gear_ratios[current_gear] if current_gear < gear_ratios.size() else 1.0
	engine_force_value = throttle * max_engine_force * gear_ratio
	
	if speed * 3.6 > max_speed:
		engine_force_value = 0
	
	brake_force_value = brake * max_brake_force
	
	if abs_enabled and brake > 0.8:
		_apply_abs()
	
	for wheel in [rear_left_wheel, rear_right_wheel]:
		if wheel:
			wheel.set_engine_force(engine_force_value)
			wheel.set_brake(brake_force_value)
	
	for wheel in [front_left_wheel, front_right_wheel]:
		if wheel:
			wheel.set_brake(brake_force_value)

func _update_gear():
	var speed = linear_velocity.length() * 3.6
	
	if current_gear < gear_ratios.size() - 1:
		if rpm > max_rpm * 0.9:
			_shift_gear(1)
	
	if current_gear > 0:
		if rpm < min_rpm * 1.2 and speed > 10:
			_shift_gear(-1)

func _shift_gear(direction: int):
	current_gear = clamp(current_gear + direction, 0, gear_ratios.size() - 1)
	emit_signal("gear_changed", current_gear + 1)

func _update_rpm(delta):
	var speed = linear_velocity.length() * 3.6
	var gear_ratio = gear_ratios[current_gear] if current_gear < gear_ratios.size() else 1.0
	
	var target_rpm = min_rpm + (speed / max_speed) * (max_rpm - min_rpm) * gear_ratio
	rpm = lerp(rpm, target_rpm, 10.0 * delta)
	rpm = clamp(rpm, min_rpm, max_rpm)

func _apply_downforce():
	var speed = linear_velocity.length()
	var down_force = downforce * speed * speed * 0.001
	add_central_force(Vector3.DOWN * down_force)

func _apply_handbrake():
	for wheel in [rear_left_wheel, rear_right_wheel]:
		if wheel:
			wheel.set_brake(max_brake_force * 2.0)

func _apply_abs():
	var wheels = [front_left_wheel, front_right_wheel, rear_left_wheel, rear_right_wheel]
	for wheel in wheels:
		if wheel and wheel.is_in_contact():
			if wheel.get_skidinfo() < 0.5:
				wheel.set_brake(brake_force_value * 0.6)
			else:
				wheel.set_brake(brake_force_value)

func _apply_traction_control():
	if not traction_control:
		return
	
	var wheels = [rear_left_wheel, rear_right_wheel]
	for wheel in wheels:
		if wheel and wheel.is_in_contact():
			if wheel.get_skidinfo() < 0.8:
				wheel.set_engine_force(engine_force_value * 0.7)

func _apply_stability_control(delta):
	if not stability_control:
		return
	
	var angular_vel = angular_velocity.y
	var linear_vel = linear_velocity
	var forward = -transform.basis.z
	var right = transform.basis.x
	
	var forward_speed = linear_vel.dot(forward)
	var right_speed = linear_vel.dot(right)
	
	if abs(right_speed) > forward_speed * 0.3 and forward_speed > 5:
		var correction_torque = -angular_vel * 1000 * delta
		add_torque(Vector3(0, correction_torque, 0))
		
		for wheel in [rear_left_wheel, rear_right_wheel]:
			if wheel:
				wheel.set_engine_force(engine_force_value * 0.5)

func _update_sounds():
	if engine_sound:
		engine_sound.pitch_scale = 0.5 + (rpm / max_rpm) * 1.5
		
		if not engine_sound.playing:
			engine_sound.play()
	
	if brake_sound and brake_force_value > 100:
		if not brake_sound.playing:
			brake_sound.play()
	elif brake_sound:
		brake_sound.stop()
	
	var is_skidding = false
	for wheel in [front_left_wheel, front_right_wheel, rear_left_wheel, rear_right_wheel]:
		if wheel and wheel.is_in_contact() and wheel.get_skidinfo() < 0.5:
			is_skidding = true
			break
	
	if skid_sound:
		if is_skidding and not skid_sound.playing:
			skid_sound.play()
		elif not is_skidding:
			skid_sound.stop()

func reset_position():
	translation = Vector3(0, 2, 0)
	rotation = Vector3.ZERO
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func get_speed_kmh() -> float:
	return linear_velocity.length() * 3.6

func set_traction_control(enabled: bool):
	traction_control = enabled

func set_abs(enabled: bool):
	abs_enabled = enabled

func set_stability_control(enabled: bool):
	stability_control = enabled