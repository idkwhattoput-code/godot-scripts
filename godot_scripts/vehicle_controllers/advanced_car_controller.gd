extends RigidBody

# Engine settings
export var max_engine_power = 400.0
export var max_brake_force = 50.0
export var max_steering_angle = 0.35
export var steering_speed = 2.0
export var downforce_coefficient = 5.0

# Transmission
export var gear_ratios = [3.5, 2.5, 1.8, 1.3, 1.0, 0.8]
export var final_drive_ratio = 3.42
export var automatic_transmission = true
export var shift_time = 0.2

# Physics
export var center_of_mass_offset = Vector3(0, -0.5, 0)
export var tire_grip = 1.0
export var tire_drag = 0.99
export var rolling_resistance = 0.1
export var air_resistance = 0.3

# Suspension (per wheel)
export var suspension_travel = 0.2
export var suspension_stiffness = 20.0
export var suspension_damping = 2.0

# Drift and traction
export var drift_friction = 0.8
export var traction_control = true
export var stability_control = true
export var abs_enabled = true

# State variables
var current_gear = 0
var engine_rpm = 0.0
var clutch_engagement = 1.0
var is_shifting = false
var shift_timer = 0.0

var steering_input = 0.0
var throttle_input = 0.0
var brake_input = 0.0
var handbrake_input = 0.0
var clutch_input = 0.0

var wheel_speeds = [0.0, 0.0, 0.0, 0.0]
var wheel_slip = [0.0, 0.0, 0.0, 0.0]
var is_drifting = false
var drift_angle = 0.0

# Damage system
export var enable_damage = true
export var max_health = 100.0
var current_health = 100.0
var engine_damage = 0.0
var tire_wear = [0.0, 0.0, 0.0, 0.0]

# Visual effects
var skid_marks = []
var smoke_emitters = []

# Audio
var engine_audio_players = []
var current_engine_pitch = 1.0

# Components
onready var wheels = [
	$WheelFL,
	$WheelFR,
	$WheelRL,
	$WheelRR
]
onready var wheel_meshes = [
	$Body/WheelMeshFL,
	$Body/WheelMeshFR,
	$Body/WheelMeshRL,
	$Body/WheelMeshRR
]
onready var engine_sound = $EngineSound
onready var tire_sound = $TireSound
onready var crash_sound = $CrashSound
onready var gear_shift_sound = $GearShiftSound

signal gear_changed(gear)
signal damage_taken(amount)
signal car_destroyed()
signal drift_started()
signal drift_ended(score)

func _ready():
	set_center_of_mass(center_of_mass_offset)
	current_health = max_health
	_setup_audio()
	_setup_visual_effects()

func _setup_audio():
	# Create multiple audio players for realistic engine sound
	for i in range(3):
		var player = AudioStreamPlayer3D.new()
		player.bus = "Engine"
		add_child(player)
		engine_audio_players.append(player)

func _setup_visual_effects():
	# Setup skid marks and smoke for each wheel
	for i in range(4):
		var skid = SkidMark.new()
		add_child(skid)
		skid_marks.append(skid)
		
		var smoke = CPUParticles.new()
		smoke.emitting = false
		smoke.amount = 50
		smoke.lifetime = 2.0
		smoke.initial_velocity = 5.0
		wheels[i].add_child(smoke)
		smoke_emitters.append(smoke)

func _physics_process(delta):
	_handle_input()
	_update_transmission(delta)
	_apply_forces(delta)
	_update_wheels(delta)
	_update_audio(delta)
	_update_visual_effects()
	_check_damage()

func _handle_input():
	steering_input = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	throttle_input = Input.get_action_strength("accelerate")
	brake_input = Input.get_action_strength("brake")
	handbrake_input = Input.get_action_strength("handbrake")
	clutch_input = Input.get_action_strength("clutch")
	
	# Manual transmission
	if not automatic_transmission:
		if Input.is_action_just_pressed("gear_up"):
			shift_gear(1)
		elif Input.is_action_just_pressed("gear_down"):
			shift_gear(-1)

func _update_transmission(delta):
	if is_shifting:
		shift_timer -= delta
		clutch_engagement = 0.0
		if shift_timer <= 0:
			is_shifting = false
			clutch_engagement = 1.0
	else:
		clutch_engagement = 1.0 - clutch_input
	
	# Calculate engine RPM
	var wheel_rpm = _get_average_wheel_rpm()
	var gear_ratio = _get_current_gear_ratio()
	var target_rpm = wheel_rpm * gear_ratio * final_drive_ratio
	
	# Engine inertia and rev limiter
	engine_rpm = lerp(engine_rpm, target_rpm * clutch_engagement + throttle_input * 1000, 10 * delta)
	engine_rpm = clamp(engine_rpm, 800, 7000)
	
	# Automatic transmission
	if automatic_transmission and not is_shifting:
		if engine_rpm > 6000 and current_gear < gear_ratios.size() - 1:
			shift_gear(1)
		elif engine_rpm < 2000 and current_gear > 0 and throttle_input < 0.1:
			shift_gear(-1)

func _apply_forces(delta):
	var forward = -transform.basis.z
	var right = transform.basis.x
	var up = transform.basis.y
	
	# Engine force
	var engine_force = _calculate_engine_force() * (1.0 - engine_damage)
	var drive_force = forward * engine_force * throttle_input
	
	# Only apply to rear wheels (RWD)
	if wheels[2] and wheels[3]:
		add_force(drive_force * 0.5, wheels[2].translation)
		add_force(drive_force * 0.5, wheels[3].translation)
	
	# Braking
	for i in range(4):
		if wheels[i]:
			var brake_force = Vector3.ZERO
			if brake_input > 0:
				brake_force = -linear_velocity.normalized() * brake_input * max_brake_force
			if handbrake_input > 0 and i >= 2:  # Rear wheels only
				brake_force = -linear_velocity.normalized() * handbrake_input * max_brake_force * 0.7
			
			if brake_force.length() > 0:
				add_force(brake_force, wheels[i].translation)
	
	# Downforce
	var speed = linear_velocity.length()
	add_central_force(Vector3.DOWN * downforce_coefficient * speed * speed * 0.01)
	
	# Air resistance
	add_central_force(-linear_velocity * air_resistance * speed * 0.01)
	
	# Rolling resistance
	if is_on_ground():
		add_central_force(-linear_velocity * rolling_resistance)

func _update_wheels(delta):
	for i in range(4):
		if not wheels[i] or not wheel_meshes[i]:
			continue
		
		var wheel = wheels[i]
		var mesh = wheel_meshes[i]
		
		# Raycast for ground contact
		var ray = RayCast.new()
		wheel.add_child(ray)
		ray.cast_to = Vector3.DOWN * (suspension_travel + 0.1)
		ray.force_raycast_update()
		
		if ray.is_colliding():
			# Suspension
			var hit_distance = wheel.global_transform.origin.distance_to(ray.get_collision_point())
			var suspension_force = (suspension_travel - hit_distance) * suspension_stiffness
			var damping_force = -linear_velocity.y * suspension_damping
			
			add_force(up * (suspension_force + damping_force), wheel.translation)
			
			# Steering (front wheels)
			if i < 2:
				var steer_angle = steering_input * max_steering_angle
				wheel.rotation.y = lerp(wheel.rotation.y, steer_angle, steering_speed * delta)
			
			# Calculate wheel slip
			var wheel_velocity = get_velocity_at_position(wheel.global_transform.origin)
			var wheel_forward = -wheel.global_transform.basis.z
			var forward_velocity = wheel_velocity.dot(wheel_forward)
			var lateral_velocity = wheel_velocity.dot(wheel.global_transform.basis.x)
			
			wheel_slip[i] = abs(lateral_velocity) / max(abs(forward_velocity), 1.0)
			
			# Traction control
			if traction_control and wheel_slip[i] > 0.2 and i >= 2:
				throttle_input *= 0.7
			
			# Calculate and apply tire forces
			var tire_force = _calculate_tire_force(i, forward_velocity, lateral_velocity)
			add_force(tire_force, wheel.translation)
			
			# Update wheel rotation
			wheel_speeds[i] = forward_velocity / (0.3 * TAU)  # Assuming 0.3m wheel radius
			mesh.rotate_x(wheel_speeds[i] * delta * TAU)
		
		ray.queue_free()

func _calculate_engine_force() -> float:
	var rpm_normalized = engine_rpm / 7000.0
	var torque_curve = sin(rpm_normalized * PI) * 0.8 + 0.2  # Simple torque curve
	var gear_ratio = _get_current_gear_ratio()
	
	return max_engine_power * torque_curve * gear_ratio * final_drive_ratio

func _calculate_tire_force(wheel_index: int, forward_vel: float, lateral_vel: float) -> Vector3:
	var wheel = wheels[wheel_index]
	var forward = -wheel.global_transform.basis.z
	var right = wheel.global_transform.basis.x
	
	# Longitudinal force (acceleration/braking)
	var long_slip = 0.0
	if abs(forward_vel) > 0.1:
		long_slip = (wheel_speeds[wheel_index] * 0.3 - forward_vel) / abs(forward_vel)
	
	var long_force = forward * long_slip * tire_grip * mass * 2.0
	
	# Lateral force (cornering)
	var lat_slip = atan2(lateral_vel, abs(forward_vel))
	var lat_force = -right * sin(lat_slip) * tire_grip * mass * 4.0
	
	# Reduce grip when drifting
	if abs(lat_slip) > deg2rad(15):
		lat_force *= drift_friction
		if not is_drifting:
			is_drifting = true
			emit_signal("drift_started")
	elif is_drifting and abs(lat_slip) < deg2rad(5):
		is_drifting = false
		emit_signal("drift_ended", calculate_drift_score())
	
	# Apply tire wear
	if enable_damage:
		tire_wear[wheel_index] += (abs(long_slip) + abs(lat_slip)) * 0.0001
		var wear_factor = 1.0 - tire_wear[wheel_index]
		long_force *= wear_factor
		lat_force *= wear_factor
	
	return long_force + lat_force

func _get_average_wheel_rpm() -> float:
	var total = 0.0
	for speed in wheel_speeds:
		total += abs(speed)
	return total / 4.0 * 60.0  # Convert to RPM

func _get_current_gear_ratio() -> float:
	if current_gear < 0 or current_gear >= gear_ratios.size():
		return 1.0
	return gear_ratios[current_gear]

func shift_gear(direction: int):
	var new_gear = current_gear + direction
	if new_gear >= 0 and new_gear < gear_ratios.size() and not is_shifting:
		current_gear = new_gear
		is_shifting = true
		shift_timer = shift_time
		emit_signal("gear_changed", current_gear)
		if gear_shift_sound:
			gear_shift_sound.play()

func _update_audio(delta):
	# Engine sound with multiple layers
	var rpm_normalized = engine_rpm / 7000.0
	current_engine_pitch = lerp(current_engine_pitch, 0.5 + rpm_normalized * 1.5, 5 * delta)
	
	for i in range(engine_audio_players.size()):
		var player = engine_audio_players[i]
		player.pitch_scale = current_engine_pitch + i * 0.1
		player.volume_db = linear2db(throttle_input * 0.8 + 0.2)
		if not player.playing:
			player.play()
	
	# Tire screech
	var max_slip = 0.0
	for slip in wheel_slip:
		max_slip = max(max_slip, slip)
	
	if tire_sound:
		if max_slip > 0.3:
			tire_sound.volume_db = linear2db(min(max_slip, 1.0))
			if not tire_sound.playing:
				tire_sound.play()
		else:
			tire_sound.stop()

func _update_visual_effects():
	for i in range(4):
		if wheel_slip[i] > 0.5 and is_on_ground():
			# Tire smoke
			smoke_emitters[i].emitting = true
			
			# Skid marks
			if skid_marks[i]:
				skid_marks[i].add_point(wheels[i].global_transform.origin)
		else:
			smoke_emitters[i].emitting = false
			if skid_marks[i]:
				skid_marks[i].stop()

func _check_damage():
	if not enable_damage:
		return
	
	# Check for collisions
	for contact in get_colliding_bodies():
		if contact != self:
			var impact_force = linear_velocity.length()
			if impact_force > 10:
				take_damage(impact_force * 0.5)

func take_damage(amount: float):
	current_health -= amount
	engine_damage = 1.0 - (current_health / max_health)
	
	emit_signal("damage_taken", amount)
	
	if crash_sound and amount > 5:
		crash_sound.play()
	
	if current_health <= 0:
		emit_signal("car_destroyed")
		set_physics_process(false)

func repair():
	current_health = max_health
	engine_damage = 0.0
	tire_wear = [0.0, 0.0, 0.0, 0.0]

func is_on_ground() -> bool:
	for wheel in wheels:
		var ray = RayCast.new()
		wheel.add_child(ray)
		ray.cast_to = Vector3.DOWN * (suspension_travel + 0.1)
		ray.force_raycast_update()
		var on_ground = ray.is_colliding()
		ray.queue_free()
		if on_ground:
			return true
	return false

func get_speed_kmh() -> float:
	return linear_velocity.length() * 3.6

func get_velocity_at_position(pos: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(pos - global_transform.origin)

func calculate_drift_score() -> int:
	var speed = get_speed_kmh()
	var angle = rad2deg(drift_angle)
	return int(speed * angle * 0.1)

class SkidMark:
	var points = []
	var active = false
	
	func add_point(pos: Vector3):
		if not active:
			active = true
			points.clear()
		points.append(pos)
	
	func stop():
		active = false