extends RigidBody

# Bike settings
export var max_engine_power = 300.0
export var max_brake_force = 100.0
export var max_lean_angle = 45.0
export var lean_speed = 2.0
export var wheelie_torque = 500.0
export var stoppie_torque = 400.0

# Physics
export var center_of_mass_offset = Vector3(0, -0.3, 0)
export var wheel_base = 1.4
export var front_wheel_grip = 0.9
export var rear_wheel_grip = 1.0
export var aerodynamic_drag = 0.4

# Stability assist
export var gyroscopic_stability = 10.0
export var speed_stability_multiplier = 0.1
export var auto_balance = true
export var auto_balance_strength = 5.0

# Transmission
export var gear_ratios = [2.8, 2.0, 1.5, 1.2, 1.0, 0.9]
export var automatic = true
export var clutch_speed = 3.0

# State variables
var current_gear = 0
var engine_rpm = 0.0
var current_lean = 0.0
var is_wheelie = false
var is_stoppie = false
var is_grounded = true
var air_time = 0.0
var trick_score = 0

# Input
var throttle = 0.0
var brake_front = 0.0
var brake_rear = 0.0
var steering = 0.0
var lean_input = 0.0
var clutch = 1.0

# Wheel data
var front_wheel_speed = 0.0
var rear_wheel_speed = 0.0
var front_slip = 0.0
var rear_slip = 0.0

# Components
onready var body_mesh = $BodyMesh
onready var front_wheel = $FrontWheel
onready var rear_wheel = $RearWheel
onready var front_wheel_mesh = $FrontWheel/WheelMesh
onready var rear_wheel_mesh = $RearWheel/WheelMesh
onready var front_suspension = $FrontSuspension
onready var rear_suspension = $RearSuspension
onready var engine_audio = $EngineAudio
onready var tire_audio = $TireAudio
onready var wind_audio = $WindAudio

signal wheelie_started()
signal wheelie_ended(duration)
signal stoppie_started()
signal stoppie_ended(duration)
signal airborne()
signal landed(air_time)
signal crashed()

func _ready():
	set_center_of_mass(center_of_mass_offset)
	_setup_suspension()

func _setup_suspension():
	# Create suspension joints if not already present
	if not front_suspension:
		front_suspension = Generic6DOFJoint.new()
		add_child(front_suspension)
	if not rear_suspension:
		rear_suspension = Generic6DOFJoint.new()
		add_child(rear_suspension)

func _physics_process(delta):
	_handle_input()
	_update_wheels(delta)
	_apply_engine_force(delta)
	_apply_brakes(delta)
	_handle_lean(delta)
	_handle_stability(delta)
	_check_tricks(delta)
	_update_audio(delta)
	_check_crash()

func _handle_input():
	throttle = Input.get_action_strength("accelerate")
	brake_front = Input.get_action_strength("brake") * 0.7
	brake_rear = Input.get_action_strength("brake") * 0.3
	
	# Separate front/rear brake inputs if available
	if Input.is_action_pressed("brake_front"):
		brake_front = 1.0
	if Input.is_action_pressed("brake_rear"):
		brake_rear = 1.0
	
	steering = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	lean_input = Input.get_action_strength("lean_left") - Input.get_action_strength("lean_right")
	
	# Manual clutch
	clutch = 1.0 - Input.get_action_strength("clutch")
	
	# Gear shifting
	if not automatic:
		if Input.is_action_just_pressed("gear_up") and current_gear < gear_ratios.size() - 1:
			current_gear += 1
		elif Input.is_action_just_pressed("gear_down") and current_gear > 0:
			current_gear -= 1

func _update_wheels(delta):
	# Check ground contact
	var front_grounded = _check_wheel_ground(front_wheel)
	var rear_grounded = _check_wheel_ground(rear_wheel)
	is_grounded = front_grounded or rear_grounded
	
	if not is_grounded:
		air_time += delta
		if air_time == delta:  # Just became airborne
			emit_signal("airborne")
	else:
		if air_time > 0.1:
			emit_signal("landed", air_time)
		air_time = 0.0
	
	# Update wheel speeds
	var linear_vel = linear_velocity
	var angular_vel = angular_velocity
	
	if front_wheel:
		var front_vel = linear_vel + angular_vel.cross(front_wheel.translation - translation)
		front_wheel_speed = front_vel.dot(-transform.basis.z)
		
		# Rotate wheel mesh
		if front_wheel_mesh:
			front_wheel_mesh.rotate_x(front_wheel_speed * delta / 0.3)
	
	if rear_wheel:
		var rear_vel = linear_vel + angular_vel.cross(rear_wheel.translation - translation)
		rear_wheel_speed = rear_vel.dot(-transform.basis.z)
		
		if rear_wheel_mesh:
			rear_wheel_mesh.rotate_x(rear_wheel_speed * delta / 0.3)

func _apply_engine_force(delta):
	if not is_grounded:
		return
	
	# Calculate engine RPM
	var wheel_rpm = abs(rear_wheel_speed) * 60 / (2 * PI * 0.3)
	var gear_ratio = gear_ratios[current_gear] if current_gear < gear_ratios.size() else 1.0
	engine_rpm = wheel_rpm * gear_ratio * clutch
	engine_rpm = clamp(engine_rpm + throttle * 1000, 1000, 11000)
	
	# Auto-shifting
	if automatic:
		if engine_rpm > 9000 and current_gear < gear_ratios.size() - 1:
			current_gear += 1
		elif engine_rpm < 3000 and current_gear > 0:
			current_gear -= 1
	
	# Apply force
	var rpm_factor = engine_rpm / 11000.0
	var torque_curve = sin(rpm_factor * PI) * 0.7 + 0.3
	var engine_force = max_engine_power * torque_curve * gear_ratio * throttle * clutch
	
	if rear_wheel:
		var force_vector = -transform.basis.z * engine_force
		add_force(force_vector, rear_wheel.translation)
		
		# Calculate rear wheel slip
		rear_slip = abs(rear_wheel_speed - linear_velocity.length()) / max(linear_velocity.length(), 1.0)

func _apply_brakes(delta):
	var brake_deceleration = linear_velocity.normalized() * -1
	
	if brake_front > 0 and front_wheel:
		var front_brake = brake_deceleration * brake_front * max_brake_force * 0.7
		add_force(front_brake, front_wheel.translation)
		
		# Stoppie detection
		if linear_velocity.length() > 5 and brake_front > 0.8:
			apply_torque_impulse(transform.basis.x * stoppie_torque * delta)
	
	if brake_rear > 0 and rear_wheel:
		var rear_brake = brake_deceleration * brake_rear * max_brake_force * 0.3
		add_force(rear_brake, rear_wheel.translation)

func _handle_lean(delta):
	# Calculate target lean based on speed and steering
	var speed = linear_velocity.length()
	var speed_factor = clamp(speed / 30.0, 0, 1)
	
	# Automatic counter-steering lean
	var auto_lean = -steering * speed_factor * 0.7
	
	# Manual lean input
	var manual_lean = lean_input
	
	# Combine lean inputs
	var target_lean = (auto_lean + manual_lean) * deg2rad(max_lean_angle)
	target_lean = clamp(target_lean, -deg2rad(max_lean_angle), deg2rad(max_lean_angle))
	
	# Apply lean
	current_lean = lerp(current_lean, target_lean, lean_speed * delta)
	
	# Visual lean (rotate mesh)
	if body_mesh:
		body_mesh.rotation.z = current_lean
	
	# Physics lean (apply forces)
	if is_grounded and abs(current_lean) > 0.01:
		var lean_force = transform.basis.x * sin(current_lean) * mass * 10
		add_central_force(lean_force)
		
		# Steering from lean
		var lean_steering = current_lean * speed_factor * 0.5
		apply_torque_impulse(Vector3.UP * lean_steering * 10)

func _handle_stability(delta):
	var speed = linear_velocity.length()
	
	# Gyroscopic effect (more stable at higher speeds)
	var gyro_force = gyroscopic_stability * speed * speed_stability_multiplier
	angular_velocity.x *= 1.0 - (gyro_force * delta)
	angular_velocity.z *= 1.0 - (gyro_force * delta)
	
	# Auto-balance at low speeds
	if auto_balance and speed < 5 and is_grounded:
		var balance_torque = -transform.basis.z.cross(Vector3.UP) * auto_balance_strength
		balance_torque *= (1.0 - speed / 5.0)  # Reduce effect as speed increases
		apply_torque_impulse(balance_torque * delta)
	
	# Prevent tipping over
	var up_dot = transform.basis.y.dot(Vector3.UP)
	if up_dot < 0.5 and is_grounded:
		var recovery_torque = transform.basis.z.cross(Vector3.UP) * 20
		apply_torque_impulse(recovery_torque * delta)

func _check_tricks(delta):
	# Wheelie detection
	var pitch = transform.basis.get_euler().x
	if pitch < -0.2 and is_grounded and throttle > 0.5:
		if not is_wheelie:
			is_wheelie = true
			emit_signal("wheelie_started")
	elif is_wheelie and (pitch > -0.05 or not is_grounded):
		is_wheelie = false
		emit_signal("wheelie_ended", 0)  # TODO: Track duration
	
	# Stoppie detection
	if pitch > 0.2 and is_grounded and brake_front > 0.5:
		if not is_stoppie:
			is_stoppie = true
			emit_signal("stoppie_started")
	elif is_stoppie and (pitch < 0.05 or not is_grounded):
		is_stoppie = false
		emit_signal("stoppie_ended", 0)  # TODO: Track duration
	
	# Wheelie/Stoppie control
	if Input.is_action_pressed("wheelie") and is_grounded and speed > 5:
		apply_torque_impulse(-transform.basis.x * wheelie_torque * delta)

func _update_audio(delta):
	# Engine sound
	if engine_audio:
		var rpm_normalized = engine_rpm / 11000.0
		engine_audio.pitch_scale = 0.5 + rpm_normalized * 1.5
		engine_audio.volume_db = linear2db(0.3 + throttle * 0.7)
		if not engine_audio.playing:
			engine_audio.play()
	
	# Tire screech
	if tire_audio:
		var max_slip = max(front_slip, rear_slip)
		if max_slip > 0.2 and is_grounded:
			tire_audio.volume_db = linear2db(min(max_slip * 2, 1.0))
			if not tire_audio.playing:
				tire_audio.play()
		else:
			tire_audio.stop()
	
	# Wind noise
	if wind_audio:
		var speed_normalized = linear_velocity.length() / 50.0
		wind_audio.volume_db = linear2db(speed_normalized * 0.5)
		if speed_normalized > 0.1 and not wind_audio.playing:
			wind_audio.play()
		elif speed_normalized < 0.1:
			wind_audio.stop()

func _check_crash():
	# Check if bike has tipped over
	var up_dot = transform.basis.y.dot(Vector3.UP)
	if up_dot < 0.1 and is_grounded:
		emit_signal("crashed")
		# Reduce control
		throttle = 0
		steering *= 0.1

func _check_wheel_ground(wheel: Spatial) -> bool:
	if not wheel:
		return false
	
	var space_state = get_world().direct_space_state
	var from = wheel.global_transform.origin
	var to = from + Vector3.DOWN * 0.4
	
	var result = space_state.intersect_ray(from, to, [self])
	return result.size() > 0

func reset_position():
	translation = Vector3(0, 2, 0)
	rotation = Vector3.ZERO
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	current_lean = 0
	is_wheelie = false
	is_stoppie = false

func get_speed_kmh() -> float:
	return linear_velocity.length() * 3.6

func apply_nitro(duration: float = 2.0):
	# Temporary speed boost
	var boost_force = -transform.basis.z * max_engine_power * 2
	for i in range(int(duration * 60)):  # Apply over multiple frames
		yield(get_tree(), "physics_frame")
		if is_grounded:
			add_central_force(boost_force)