extends RigidBody

# Tank specifications
export var max_speed = 25.0  # km/h
export var reverse_speed = 10.0  # km/h
export var rotation_speed = 30.0  # degrees per second
export var acceleration = 5.0
export var brake_force = 10.0
export var track_friction = 0.8

# Turret control
export var turret_rotation_speed = 45.0  # degrees per second
export var barrel_elevation_speed = 20.0  # degrees per second
export var min_barrel_angle = -10.0
export var max_barrel_angle = 30.0

# Combat
export var shell_velocity = 500.0
export var reload_time = 4.0
export var ammo_types = ["AP", "HE", "HEAT"]
export var current_ammo_type = 0
export var max_ammo = {"AP": 30, "HE": 20, "HEAT": 10}
var current_ammo = {"AP": 30, "HE": 20, "HEAT": 10}

# Physics
export var center_of_mass_offset = Vector3(0, -0.5, 0)
export var suspension_stiffness = 50.0
export var suspension_damping = 5.0
export var track_width = 3.0

# State
var left_track_speed = 0.0
var right_track_speed = 0.0
var turret_rotation = 0.0
var barrel_elevation = 0.0
var is_reloading = false
var reload_timer = 0.0
var engine_rpm = 0.0

# Input
var throttle_input = 0.0
var steering_input = 0.0
var turret_input = Vector2.ZERO
var is_aiming = false

# Components
onready var hull = $Hull
onready var turret = $Hull/Turret
onready var barrel = $Hull/Turret/Barrel
onready var muzzle = $Hull/Turret/Barrel/Muzzle
onready var left_track_visual = $Hull/LeftTrack
onready var right_track_visual = $Hull/RightTrack
onready var engine_audio = $EngineAudio
onready var turret_audio = $TurretAudio
onready var track_audio = $TrackAudio
onready var fire_audio = $FireAudio
onready var reload_audio = $ReloadAudio
onready var suspension_wheels = []

signal fired(shell_type, position, direction)
signal reloaded()
signal ammo_changed(type)
signal hit_received(damage, location)

func _ready():
	set_center_of_mass(center_of_mass_offset)
	_setup_suspension()
	_initialize_tracks()

func _setup_suspension():
	# Create suspension wheels
	var wheel_positions = [
		Vector3(-1.2, -0.5, 2), Vector3(1.2, -0.5, 2),
		Vector3(-1.2, -0.5, 0), Vector3(1.2, -0.5, 0),
		Vector3(-1.2, -0.5, -2), Vector3(1.2, -0.5, -2)
	]
	
	for pos in wheel_positions:
		var wheel = RigidBody.new()
		wheel.mass = 50
		wheel.translation = pos
		hull.add_child(wheel)
		
		var joint = Generic6DOFJoint.new()
		joint.set_param_y(Generic6DOFJoint.PARAM_LINEAR_LOWER_LIMIT, -0.2)
		joint.set_param_y(Generic6DOFJoint.PARAM_LINEAR_UPPER_LIMIT, 0.2)
		hull.add_child(joint)
		
		suspension_wheels.append({"wheel": wheel, "joint": joint})

func _initialize_tracks():
	# Setup track materials for scrolling texture effect
	if left_track_visual and left_track_visual.material_override:
		left_track_visual.material_override.set_shader_param("scroll_speed", 0.0)
	if right_track_visual and right_track_visual.material_override:
		right_track_visual.material_override.set_shader_param("scroll_speed", 0.0)

func _physics_process(delta):
	_handle_input()
	_update_movement(delta)
	_update_turret(delta)
	_update_reload(delta)
	_update_audio(delta)
	_update_visual_effects(delta)

func _handle_input():
	# Tank movement
	throttle_input = Input.get_action_strength("move_forward") - Input.get_action_strength("move_backward")
	steering_input = Input.get_action_strength("turn_left") - Input.get_action_strength("turn_right")
	
	# Turret control
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		turret_input = Vector2.ZERO
		is_aiming = true
	else:
		turret_input.x = Input.get_action_strength("turret_right") - Input.get_action_strength("turret_left")
		turret_input.y = Input.get_action_strength("turret_up") - Input.get_action_strength("turret_down")
	
	# Combat actions
	if Input.is_action_just_pressed("fire") and not is_reloading:
		fire()
	
	if Input.is_action_just_pressed("change_ammo"):
		cycle_ammo_type()
	
	# Zoom/aim mode
	is_aiming = Input.is_action_pressed("aim")

func _input(event):
	if event is InputEventMouseMotion and is_aiming:
		turret_input.x += event.relative.x * 0.001
		turret_input.y += event.relative.y * 0.001

func _update_movement(delta):
	# Calculate track speeds for differential steering
	var forward_speed = throttle_input * max_speed
	if throttle_input < 0:
		forward_speed = throttle_input * reverse_speed
	
	var turn_rate = steering_input * rotation_speed
	
	# Differential drive calculation
	left_track_speed = forward_speed - (turn_rate * track_width / 2)
	right_track_speed = forward_speed + (turn_rate * track_width / 2)
	
	# Convert to m/s
	left_track_speed /= 3.6
	right_track_speed /= 3.6
	
	# Apply forces at track positions
	var left_force = -transform.basis.z * left_track_speed * mass * acceleration
	var right_force = -transform.basis.z * right_track_speed * mass * acceleration
	
	add_force(left_force * 0.5, Vector3(-track_width/2, 0, 0))
	add_force(right_force * 0.5, Vector3(track_width/2, 0, 0))
	
	# Brake/friction
	if abs(throttle_input) < 0.1:
		linear_velocity *= (1.0 - brake_force * delta)
		angular_velocity.y *= (1.0 - brake_force * delta)
	
	# Track friction for realistic movement
	var lateral_velocity = linear_velocity.dot(transform.basis.x) * transform.basis.x
	add_central_force(-lateral_velocity * track_friction * mass)
	
	# Update engine RPM for audio
	engine_rpm = (abs(left_track_speed) + abs(right_track_speed)) / 2.0 * 100

func _update_turret(delta):
	# Turret rotation
	turret_rotation += turret_input.x * turret_rotation_speed * delta
	turret_rotation = wrapf(turret_rotation, 0, 360)
	
	if turret:
		turret.rotation.y = deg2rad(turret_rotation)
		
		# Turret motor sound
		if abs(turret_input.x) > 0.1 and turret_audio:
			if not turret_audio.playing:
				turret_audio.play()
		elif turret_audio and turret_audio.playing:
			turret_audio.stop()
	
	# Barrel elevation
	barrel_elevation -= turret_input.y * barrel_elevation_speed * delta
	barrel_elevation = clamp(barrel_elevation, min_barrel_angle, max_barrel_angle)
	
	if barrel:
		barrel.rotation.x = deg2rad(barrel_elevation)

func _update_reload(delta):
	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0:
			is_reloading = false
			emit_signal("reloaded")

func fire():
	var ammo_type = ammo_types[current_ammo_type]
	
	if current_ammo[ammo_type] <= 0:
		# Click sound for empty
		return
	
	current_ammo[ammo_type] -= 1
	
	# Get muzzle position and direction
	var fire_position = muzzle.global_transform.origin
	var fire_direction = -barrel.global_transform.basis.z
	
	emit_signal("fired", ammo_type, fire_position, fire_direction)
	
	# Recoil
	var recoil_force = fire_direction * -2000
	add_force(recoil_force, barrel.translation)
	
	# Effects
	if fire_audio:
		fire_audio.play()
	
	_create_muzzle_flash()
	
	# Start reload
	is_reloading = true
	reload_timer = reload_time
	
	if reload_audio:
		reload_audio.play()

func cycle_ammo_type():
	current_ammo_type = (current_ammo_type + 1) % ammo_types.size()
	emit_signal("ammo_changed", ammo_types[current_ammo_type])

func _create_muzzle_flash():
	var flash = CPUParticles.new()
	flash.emitting = true
	flash.amount = 50
	flash.lifetime = 0.1
	flash.one_shot = true
	flash.initial_velocity = 20
	flash.angular_velocity = 45
	flash.scale = Vector3(2, 2, 2)
	
	muzzle.add_child(flash)
	flash.global_transform = muzzle.global_transform
	
	yield(get_tree().create_timer(1.0), "timeout")
	flash.queue_free()

func _update_audio(delta):
	# Engine sound
	if engine_audio:
		engine_audio.pitch_scale = 0.8 + engine_rpm / 200.0
		engine_audio.volume_db = linear2db(0.5 + abs(throttle_input) * 0.5)
		if not engine_audio.playing:
			engine_audio.play()
	
	# Track sound
	if track_audio:
		var movement_speed = linear_velocity.length()
		if movement_speed > 0.5:
			track_audio.volume_db = linear2db(movement_speed / 10.0)
			if not track_audio.playing:
				track_audio.play()
		else:
			track_audio.stop()

func _update_visual_effects(delta):
	# Update track scroll speed
	if left_track_visual and left_track_visual.material_override:
		left_track_visual.material_override.set_shader_param("scroll_speed", left_track_speed)
	if right_track_visual and right_track_visual.material_override:
		right_track_visual.material_override.set_shader_param("scroll_speed", right_track_speed)
	
	# Dust/dirt particles from tracks
	var movement_speed = linear_velocity.length()
	if movement_speed > 1.0:
		# Create dust particles
		pass

func take_damage(damage: float, impact_point: Vector3):
	# Simple damage model
	emit_signal("hit_received", damage, impact_point)
	
	# Apply impact force
	var impact_direction = (impact_point - global_transform.origin).normalized()
	apply_impulse(impact_point - global_transform.origin, impact_direction * damage * 10)

func get_ammo_count(type: String) -> int:
	return current_ammo.get(type, 0)

func reload_ammo(type: String, amount: int):
	if current_ammo.has(type):
		current_ammo[type] = min(current_ammo[type] + amount, max_ammo[type])

func get_turret_transform() -> Transform:
	if turret:
		return turret.global_transform
	return global_transform

func get_barrel_direction() -> Vector3:
	if barrel:
		return -barrel.global_transform.basis.z
	return -transform.basis.z

func stabilize_gun():
	# Gun stabilization system - keeps barrel pointed at target despite hull movement
	pass

func set_target_position(pos: Vector3):
	# Auto-aim turret at position
	if not turret or not barrel:
		return
	
	var turret_pos = turret.global_transform.origin
	var to_target = pos - turret_pos
	
	# Calculate turret rotation
	var flat_direction = Vector3(to_target.x, 0, to_target.z).normalized()
	var target_turret_rotation = atan2(flat_direction.x, flat_direction.z)
	
	# Calculate barrel elevation
	var distance = Vector2(to_target.x, to_target.z).length()
	var height_diff = to_target.y
	var target_elevation = atan2(height_diff, distance)
	
	# Set as input for smooth rotation
	turret_input.x = angle_difference(target_turret_rotation, deg2rad(turret_rotation))
	turret_input.y = angle_difference(target_elevation, deg2rad(barrel_elevation))

func angle_difference(a: float, b: float) -> float:
	var diff = a - b
	while diff > PI:
		diff -= TAU
	while diff < -PI:
		diff += TAU
	return diff