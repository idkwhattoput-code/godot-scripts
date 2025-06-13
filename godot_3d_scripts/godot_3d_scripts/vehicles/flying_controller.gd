extends RigidBody

export var thrust_power = 50.0
export var vertical_thrust_multiplier = 1.5
export var max_speed = 100.0
export var rotation_speed = 2.0
export var stabilization_force = 10.0
export var air_friction = 0.98

export var use_physics_flight = true
export var arcade_flight = false

var input_vector = Vector3.ZERO
var rotation_input = Vector3.ZERO
var is_grounded = false
var altitude = 0.0

export var auto_level = true
export var auto_hover = false
export var hover_height = 10.0
export var hover_force = 20.0

onready var ground_ray = $GroundRay
onready var collision_shape = $CollisionShape
onready var engine_particles = $EngineParticles
onready var engine_sound = $EngineSound

signal altitude_changed(altitude)
signal speed_changed(speed)
signal grounded()
signal airborne()

func _ready():
	set_gravity_scale(0.3)
	set_linear_damp(0.5)
	set_angular_damp(2.0)
	
	if ground_ray:
		ground_ray.enabled = true
		ground_ray.cast_to = Vector3(0, -hover_height * 2, 0)

func _physics_process(delta):
	_handle_input()
	_update_altitude()
	
	if use_physics_flight:
		_physics_based_flight(delta)
	else:
		_arcade_flight(delta)
	
	_apply_stabilization(delta)
	_check_ground_state()
	_update_effects()
	
	var speed = linear_velocity.length()
	emit_signal("speed_changed", speed)
	emit_signal("altitude_changed", altitude)

func _handle_input():
	input_vector = Vector3.ZERO
	rotation_input = Vector3.ZERO
	
	var forward = Input.get_action_strength("move_forward") - Input.get_action_strength("move_backward")
	var right = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var up = Input.get_action_strength("fly_up") - Input.get_action_strength("fly_down")
	
	input_vector = Vector3(right, up, forward)
	
	var pitch = Input.get_action_strength("pitch_down") - Input.get_action_strength("pitch_up")
	var yaw = Input.get_action_strength("yaw_left") - Input.get_action_strength("yaw_right")
	var roll = Input.get_action_strength("roll_left") - Input.get_action_strength("roll_right")
	
	rotation_input = Vector3(pitch, yaw, roll)
	
	if Input.is_action_pressed("boost"):
		input_vector *= 2.0

func _physics_based_flight(delta):
	var forward = -transform.basis.z
	var right = transform.basis.x
	var up = transform.basis.y
	
	var thrust = Vector3.ZERO
	thrust += forward * input_vector.z * thrust_power
	thrust += right * input_vector.x * thrust_power * 0.5
	thrust += up * input_vector.y * thrust_power * vertical_thrust_multiplier
	
	if auto_hover and input_vector.length() < 0.1:
		_apply_hover_force()
	
	add_central_force(thrust)
	
	var torque = Vector3.ZERO
	torque.x = rotation_input.x * rotation_speed
	torque.y = rotation_input.y * rotation_speed
	torque.z = rotation_input.z * rotation_speed * 0.7
	
	add_torque(torque * 100)
	
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed
	
	linear_velocity *= air_friction

func _arcade_flight(delta):
	var forward = -transform.basis.z
	var right = transform.basis.x
	var up = Vector3.UP
	
	var movement = Vector3.ZERO
	movement += forward * input_vector.z
	movement += right * input_vector.x
	movement.y = input_vector.y
	
	movement = movement.normalized() * thrust_power * delta
	
	translate(movement)
	
	rotate_x(rotation_input.x * rotation_speed * delta)
	rotate_y(rotation_input.y * rotation_speed * delta)
	rotate_z(rotation_input.z * rotation_speed * delta)

func _apply_hover_force():
	if not ground_ray:
		return
	
	ground_ray.force_raycast_update()
	
	if ground_ray.is_colliding():
		var distance = global_transform.origin.distance_to(ground_ray.get_collision_point())
		
		if distance < hover_height:
			var hover_power = (1.0 - distance / hover_height) * hover_force
			add_central_force(Vector3.UP * hover_power)

func _apply_stabilization(delta):
	if not auto_level or rotation_input.length() > 0.1:
		return
	
	var current_rotation = transform.basis.get_euler()
	var target_rotation = Vector3(0, current_rotation.y, 0)
	
	var stabilization_torque = (target_rotation - current_rotation) * stabilization_force
	stabilization_torque.y = 0
	
	add_torque(stabilization_torque)

func _update_altitude():
	if ground_ray:
		ground_ray.force_raycast_update()
		if ground_ray.is_colliding():
			altitude = global_transform.origin.distance_to(ground_ray.get_collision_point())
		else:
			altitude = global_transform.origin.y
	else:
		altitude = global_transform.origin.y

func _check_ground_state():
	var was_grounded = is_grounded
	
	if ground_ray:
		ground_ray.force_raycast_update()
		is_grounded = ground_ray.is_colliding() and altitude < 1.0
	
	if is_grounded and not was_grounded:
		emit_signal("grounded")
	elif not is_grounded and was_grounded:
		emit_signal("airborne")

func _update_effects():
	if engine_particles:
		engine_particles.emitting = input_vector.length() > 0.1
		engine_particles.amount = int(8 + input_vector.length() * 16)
	
	if engine_sound:
		var target_pitch = 0.8 + input_vector.length() * 0.6
		engine_sound.pitch_scale = lerp(engine_sound.pitch_scale, target_pitch, 0.1)
		
		if input_vector.length() > 0.1 and not engine_sound.playing:
			engine_sound.play()
		elif input_vector.length() < 0.1 and engine_sound.playing:
			engine_sound.stop()

func apply_impulse_force(force: Vector3):
	apply_central_impulse(force)

func stabilize_immediately():
	angular_velocity = Vector3.ZERO
	var current_rotation = transform.basis.get_euler()
	transform.basis = Basis(Vector3(0, current_rotation.y, 0))

func set_flight_mode(physics_based: bool):
	use_physics_flight = physics_based
	if physics_based:
		mode = MODE_RIGID
	else:
		mode = MODE_KINEMATIC

func emergency_landing():
	auto_hover = true
	input_vector = Vector3.ZERO
	
	while altitude > 2.0:
		yield(get_tree().create_timer(0.1), "timeout")
		add_central_force(Vector3.DOWN * 10)
	
	stabilize_immediately()

func boost(duration: float = 2.0, multiplier: float = 3.0):
	var original_thrust = thrust_power
	thrust_power *= multiplier
	
	yield(get_tree().create_timer(duration), "timeout")
	
	thrust_power = original_thrust