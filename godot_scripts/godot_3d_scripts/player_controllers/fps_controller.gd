extends KinematicBody

# Movement settings
export var walk_speed = 7.0
export var sprint_speed = 12.0
export var crouch_speed = 3.0
export var acceleration = 10.0
export var friction = 12.0
export var air_friction = 2.0

# Jump and gravity
export var jump_force = 12.0
export var gravity = -24.0
export var max_fall_speed = -40.0
export var coyote_time = 0.1
export var jump_buffer_time = 0.1

# Camera settings
export var mouse_sensitivity = 0.3
export var gamepad_sensitivity = 2.0
export var max_look_angle = 90.0
export var head_bob_enabled = true
export var head_bob_frequency = 2.0
export var head_bob_amplitude = 0.08

# Stair stepping
export var step_height = 0.3
export var step_check_distance = 0.6

# States
var velocity = Vector3.ZERO
var snap_vector = Vector3.DOWN
var is_sprinting = false
var is_crouching = false
var is_aiming = false
var was_on_floor = false
var coyote_timer = 0.0
var jump_buffer_timer = 0.0

# Camera variables
var camera_rotation = Vector2.ZERO
var head_bob_time = 0.0
var target_fov = 75.0
var default_fov = 75.0

# Movement state
var move_state = "idle"
var footstep_timer = 0.0

# Components
onready var head = $Head
onready var camera = $Head/Camera
onready var standing_collision = $StandingCollision
onready var crouching_collision = $CrouchingCollision
onready var raycast_foot = $RayCastFoot
onready var raycast_head = $RayCastHead
onready var step_cast = $StepCast
onready var interaction_ray = $Head/Camera/InteractionRay
onready var footstep_audio = $FootstepAudio
onready var jump_audio = $JumpAudio
onready var land_audio = $LandAudio

signal footstep()
signal jumped()
signal landed(fall_height)
signal state_changed(new_state)

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera.fov = default_fov
	target_fov = default_fov
	
	standing_collision.disabled = false
	crouching_collision.disabled = true
	
	_setup_step_detection()

func _setup_step_detection():
	if step_cast:
		step_cast.cast_to = Vector3(0, -step_height, -step_check_distance)
		step_cast.enabled = true

func _input(event):
	# Mouse look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera_rotation.x -= event.relative.y * mouse_sensitivity
		camera_rotation.y -= event.relative.x * mouse_sensitivity
		camera_rotation.x = clamp(camera_rotation.x, -max_look_angle, max_look_angle)
	
	# Jump buffer
	if event.is_action_pressed("jump"):
		jump_buffer_timer = jump_buffer_time

func _physics_process(delta):
	_handle_input(delta)
	_handle_movement(delta)
	_handle_camera(delta)
	_handle_states()
	_update_audio(delta)

func _handle_input(delta):
	# Get input vector
	var input_vector = Vector3.ZERO
	input_vector.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_vector.z = Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	
	# Controller look
	var look_vector = Vector2.ZERO
	look_vector.x = Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
	look_vector.y = Input.get_action_strength("look_down") - Input.get_action_strength("look_up")
	
	if look_vector.length() > 0.1:
		camera_rotation.y -= look_vector.x * gamepad_sensitivity * delta * 60
		camera_rotation.x -= look_vector.y * gamepad_sensitivity * delta * 60
		camera_rotation.x = clamp(camera_rotation.x, -max_look_angle, max_look_angle)
	
	# Normalize input
	input_vector = input_vector.normalized()
	
	# Rotate input to camera direction
	var cam_transform = camera.get_global_transform()
	var cam_basis = cam_transform.basis
	var direction = Vector3.ZERO
	direction += cam_basis.x * input_vector.x
	direction += cam_basis.z * input_vector.z
	direction.y = 0
	direction = direction.normalized()
	
	# Sprint
	is_sprinting = Input.is_action_pressed("sprint") and not is_crouching and input_vector.z < 0
	
	# Crouch
	if Input.is_action_just_pressed("crouch"):
		_toggle_crouch()
	
	# Aim
	is_aiming = Input.is_action_pressed("aim")
	
	# Apply movement
	var target_speed = walk_speed
	if is_sprinting:
		target_speed = sprint_speed
	elif is_crouching:
		target_speed = crouch_speed
	
	if direction.length() > 0:
		velocity.x = lerp(velocity.x, direction.x * target_speed, acceleration * delta)
		velocity.z = lerp(velocity.z, direction.z * target_speed, acceleration * delta)
	else:
		var fric = friction if is_on_floor() else air_friction
		velocity.x = lerp(velocity.x, 0, fric * delta)
		velocity.z = lerp(velocity.z, 0, fric * delta)

func _handle_movement(delta):
	# Gravity
	if not is_on_floor():
		velocity.y += gravity * delta
		velocity.y = max(velocity.y, max_fall_speed)
	
	# Coyote time
	if is_on_floor():
		coyote_timer = coyote_time
		was_on_floor = true
	else:
		coyote_timer -= delta
	
	# Jump buffer
	if jump_buffer_timer > 0:
		jump_buffer_timer -= delta
	
	# Jump
	if jump_buffer_timer > 0 and coyote_timer > 0:
		velocity.y = jump_force
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		emit_signal("jumped")
		if jump_audio:
			jump_audio.play()
	
	# Snap to ground
	if is_on_floor() and velocity.y <= 0:
		snap_vector = Vector3.DOWN
	else:
		snap_vector = Vector3.ZERO
	
	# Step detection
	if is_on_floor() and step_cast and step_cast.is_colliding():
		var step_normal = step_cast.get_collision_normal()
		if step_normal.angle_to(Vector3.UP) < deg2rad(45):
			var step_height_diff = step_cast.get_collision_point().y - global_transform.origin.y
			if abs(step_height_diff) < step_height:
				global_transform.origin.y += step_height_diff + 0.01
	
	# Move
	velocity = move_and_slide_with_snap(velocity, snap_vector, Vector3.UP, true, 4, deg2rad(45))
	
	# Landing
	if is_on_floor() and not was_on_floor and velocity.y < -5:
		var fall_velocity = abs(velocity.y)
		emit_signal("landed", fall_velocity)
		if land_audio:
			land_audio.volume_db = linear2db(clamp(fall_velocity / 20.0, 0.1, 1.0))
			land_audio.play()
	
	was_on_floor = is_on_floor()

func _handle_camera(delta):
	# Apply rotation
	rotation.y = deg2rad(camera_rotation.y)
	head.rotation.x = deg2rad(camera_rotation.x)
	
	# Head bob
	if head_bob_enabled and is_on_floor() and velocity.length() > 1.0:
		head_bob_time += delta * head_bob_frequency * velocity.length() / walk_speed
		var bob_offset = sin(head_bob_time) * head_bob_amplitude
		var bob_offset_horizontal = cos(head_bob_time * 0.5) * head_bob_amplitude * 0.5
		
		head.transform.origin.y = 1.7 + bob_offset
		head.transform.origin.x = bob_offset_horizontal
	else:
		head.transform.origin.y = lerp(head.transform.origin.y, 1.7, 10 * delta)
		head.transform.origin.x = lerp(head.transform.origin.x, 0, 10 * delta)
	
	# FOV changes
	if is_sprinting and velocity.length() > walk_speed:
		target_fov = default_fov + 10
	elif is_aiming:
		target_fov = default_fov - 15
	else:
		target_fov = default_fov
	
	camera.fov = lerp(camera.fov, target_fov, 10 * delta)
	
	# Crouch camera height
	if is_crouching:
		head.transform.origin.y = lerp(head.transform.origin.y, 1.2, 10 * delta)

func _toggle_crouch():
	if is_crouching:
		# Try to stand up
		if not raycast_head.is_colliding():
			is_crouching = false
			standing_collision.disabled = false
			crouching_collision.disabled = true
	else:
		# Crouch
		is_crouching = true
		standing_collision.disabled = true
		crouching_collision.disabled = false

func _handle_states():
	var new_state = "idle"
	
	if not is_on_floor():
		new_state = "airborne"
	elif velocity.length() > 0.1:
		if is_sprinting:
			new_state = "sprinting"
		elif is_crouching:
			new_state = "crouching"
		else:
			new_state = "walking"
	
	if new_state != move_state:
		move_state = new_state
		emit_signal("state_changed", new_state)

func _update_audio(delta):
	if is_on_floor() and velocity.length() > 1.0:
		footstep_timer += delta
		
		var footstep_rate = 0.5
		if is_sprinting:
			footstep_rate = 0.3
		elif is_crouching:
			footstep_rate = 0.7
		
		if footstep_timer >= footstep_rate:
			footstep_timer = 0.0
			emit_signal("footstep")
			if footstep_audio:
				footstep_audio.pitch_scale = rand_range(0.8, 1.2)
				footstep_audio.play()

func get_interaction_target():
	if interaction_ray and interaction_ray.is_colliding():
		return interaction_ray.get_collider()
	return null

func get_camera_transform() -> Transform:
	return camera.global_transform

func apply_impulse(impulse: Vector3):
	velocity += impulse

func set_mouse_sensitivity(sensitivity: float):
	mouse_sensitivity = sensitivity

func get_movement_state() -> String:
	return move_state

func is_moving() -> bool:
	return velocity.length() > 0.1

func get_look_direction() -> Vector3:
	return -camera.global_transform.basis.z

func teleport_to(position: Vector3):
	global_transform.origin = position
	velocity = Vector3.ZERO