extends KinematicBody

# Movement settings
export var walk_speed = 5.0
export var run_speed = 10.0
export var sprint_speed = 15.0
export var crouch_speed = 3.0
export var acceleration = 20.0
export var friction = 15.0
export var air_control = 0.3

# Parkour settings
export var wall_run_speed = 12.0
export var wall_run_duration = 2.0
export var wall_jump_force = Vector3(8, 12, 8)
export var wall_climb_speed = 4.0
export var ledge_grab_range = 1.5
export var vault_speed = 8.0
export var slide_speed = 18.0
export var slide_friction = 0.98

# Jump settings
export var jump_height = 4.0
export var double_jump_height = 3.0
export var wall_jump_height = 5.0
export var max_air_jumps = 1
export var coyote_time = 0.15
export var jump_buffer_time = 0.2

# Physics
export var gravity = 30.0
export var terminal_velocity = 50.0
export var step_height = 0.5

# State machine
enum State {
	IDLE,
	WALKING,
	RUNNING,
	SPRINTING,
	CROUCHING,
	SLIDING,
	JUMPING,
	FALLING,
	WALL_RUNNING,
	WALL_CLIMBING,
	LEDGE_GRABBING,
	VAULTING,
	ROLLING
}

var current_state = State.IDLE
var previous_state = State.IDLE

# Movement variables
var velocity = Vector3.ZERO
var input_vector = Vector2.ZERO
var is_grounded = false
var was_grounded = false
var air_jumps_remaining = 0
var coyote_timer = 0.0
var jump_buffer_timer = 0.0

# Wall running
var wall_run_timer = 0.0
var wall_normal = Vector3.ZERO
var is_wall_running = false
var wall_run_side = 0  # -1 = left, 1 = right

# Ledge grabbing
var is_ledge_grabbing = false
var ledge_position = Vector3.ZERO
var ledge_normal = Vector3.ZERO

# Sliding
var slide_timer = 0.0
var slide_direction = Vector3.ZERO

# Momentum
var momentum = 0.0
var momentum_multiplier = 1.0

# Camera
onready var camera_pivot = $CameraPivot
onready var camera = $CameraPivot/Camera
onready var head = $Head
var mouse_sensitivity = 0.2
var camera_tilt = 0.0
var camera_fov_default = 75.0
var camera_fov_sprint = 85.0

# Collision shapes
onready var collision_shape = $CollisionShape
onready var crouch_collision = $CrouchCollisionShape
var default_height = 2.0
var crouch_height = 1.0

# Raycasts
onready var ground_check = $GroundCheck
onready var wall_check_left = $WallCheckLeft
onready var wall_check_right = $WallCheckRight
onready var wall_check_front = $WallCheckFront
onready var ledge_check = $LedgeCheck
onready var vault_check = $VaultCheck

signal state_changed(new_state)
signal parkour_move_performed(move_name)
signal momentum_gained(amount)

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_setup_collision_shapes()
	_setup_raycasts()

func _setup_collision_shapes():
	if crouch_collision:
		crouch_collision.disabled = true

func _setup_raycasts():
	# Configure raycasts for parkour detection
	if wall_check_left:
		wall_check_left.cast_to = Vector3(-1.5, 0, 0)
	if wall_check_right:
		wall_check_right.cast_to = Vector3(1.5, 0, 0)
	if wall_check_front:
		wall_check_front.cast_to = Vector3(0, 0, -2)

func _input(event):
	if event is InputEventMouseMotion:
		rotate_y(deg2rad(-event.relative.x * mouse_sensitivity))
		camera_pivot.rotate_x(deg2rad(-event.relative.y * mouse_sensitivity))
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg2rad(-90), deg2rad(90))

func _physics_process(delta):
	_handle_input()
	_update_state_machine(delta)
	_apply_gravity(delta)
	_apply_movement(delta)
	_check_collisions()
	_update_camera_effects(delta)
	_update_momentum(delta)
	
	# Apply movement
	velocity = move_and_slide(velocity, Vector3.UP, true, 4, deg2rad(45), false)
	
	# Update grounded state
	was_grounded = is_grounded
	is_grounded = is_on_floor()
	
	# Landing
	if is_grounded and not was_grounded:
		_on_landed()

func _handle_input():
	input_vector = Vector2.ZERO
	input_vector.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_vector.y = Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	input_vector = input_vector.normalized()
	
	# Jump buffer
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time

func _update_state_machine(delta):
	# Update timers
	if coyote_timer > 0:
		coyote_timer -= delta
	if jump_buffer_timer > 0:
		jump_buffer_timer -= delta
	
	# State transitions
	match current_state:
		State.IDLE:
			if input_vector.length() > 0:
				_change_state(State.WALKING)
			elif not is_grounded:
				_change_state(State.FALLING)
			elif Input.is_action_pressed("crouch"):
				_change_state(State.CROUCHING)
		
		State.WALKING:
			if input_vector.length() == 0:
				_change_state(State.IDLE)
			elif Input.is_action_pressed("run"):
				_change_state(State.RUNNING)
			elif not is_grounded:
				_change_state(State.FALLING)
			elif Input.is_action_pressed("crouch"):
				_change_state(State.CROUCHING)
		
		State.RUNNING:
			if input_vector.length() == 0:
				_change_state(State.IDLE)
			elif Input.is_action_pressed("sprint"):
				_change_state(State.SPRINTING)
			elif not Input.is_action_pressed("run"):
				_change_state(State.WALKING)
			elif not is_grounded:
				_change_state(State.FALLING)
			elif Input.is_action_just_pressed("crouch") and velocity.length() > run_speed:
				_start_slide()
		
		State.SPRINTING:
			if input_vector.length() == 0:
				_change_state(State.IDLE)
			elif not Input.is_action_pressed("sprint"):
				_change_state(State.RUNNING)
			elif not is_grounded:
				_change_state(State.FALLING)
			elif Input.is_action_just_pressed("crouch"):
				_start_slide()
		
		State.CROUCHING:
			if not Input.is_action_pressed("crouch"):
				if _can_stand_up():
					_change_state(State.IDLE)
			elif not is_grounded:
				_change_state(State.FALLING)
		
		State.SLIDING:
			_update_slide(delta)
			if not is_grounded or velocity.length() < walk_speed:
				_end_slide()
		
		State.FALLING:
			if is_grounded:
				_change_state(State.IDLE)
			else:
				_check_wall_run(delta)
				_check_ledge_grab()
		
		State.WALL_RUNNING:
			_update_wall_run(delta)
		
		State.LEDGE_GRABBING:
			_update_ledge_grab(delta)
		
		State.VAULTING:
			_update_vault(delta)
	
	# Handle jumping
	_handle_jumping()

func _change_state(new_state: int):
	if current_state == new_state:
		return
	
	previous_state = current_state
	current_state = new_state
	emit_signal("state_changed", new_state)
	
	# State entry logic
	match new_state:
		State.CROUCHING:
			collision_shape.disabled = true
			crouch_collision.disabled = false
		State.SLIDING:
			collision_shape.disabled = true
			crouch_collision.disabled = false
		_:
			if previous_state in [State.CROUCHING, State.SLIDING]:
				collision_shape.disabled = false
				crouch_collision.disabled = true

func _apply_gravity(delta):
	if is_grounded:
		if velocity.y < 0:
			velocity.y = -2
		coyote_timer = coyote_time
		air_jumps_remaining = max_air_jumps
	else:
		velocity.y -= gravity * delta
		velocity.y = max(velocity.y, -terminal_velocity)

func _apply_movement(delta):
	var direction = (transform.basis.x * input_vector.x + transform.basis.z * -input_vector.y).normalized()
	var target_speed = _get_target_speed()
	
	if direction.length() > 0:
		# Apply momentum boost
		target_speed *= momentum_multiplier
		
		if is_grounded:
			velocity.x = lerp(velocity.x, direction.x * target_speed, acceleration * delta)
			velocity.z = lerp(velocity.z, direction.z * target_speed, acceleration * delta)
		else:
			# Air control
			velocity.x = lerp(velocity.x, direction.x * target_speed, acceleration * air_control * delta)
			velocity.z = lerp(velocity.z, direction.z * target_speed, acceleration * air_control * delta)
	else:
		# Apply friction
		if is_grounded:
			velocity.x = lerp(velocity.x, 0, friction * delta)
			velocity.z = lerp(velocity.z, 0, friction * delta)

func _get_target_speed() -> float:
	match current_state:
		State.WALKING:
			return walk_speed
		State.RUNNING:
			return run_speed
		State.SPRINTING:
			return sprint_speed
		State.CROUCHING:
			return crouch_speed
		State.SLIDING:
			return slide_speed
		State.WALL_RUNNING:
			return wall_run_speed
		_:
			return walk_speed

func _handle_jumping():
	var can_jump = false
	var jump_power = jump_height
	
	if is_grounded or coyote_timer > 0:
		can_jump = true
	elif air_jumps_remaining > 0:
		can_jump = true
		jump_power = double_jump_height
	elif is_wall_running:
		can_jump = true
		jump_power = wall_jump_height
	
	if can_jump and jump_buffer_timer > 0:
		jump_buffer_timer = 0
		
		if is_wall_running:
			# Wall jump
			var jump_dir = wall_normal + Vector3.UP
			velocity = jump_dir.normalized() * wall_jump_force
			_end_wall_run()
			emit_signal("parkour_move_performed", "wall_jump")
		else:
			# Regular jump
			velocity.y = sqrt(2 * gravity * jump_power)
			
			if not is_grounded:
				air_jumps_remaining -= 1
		
		_change_state(State.JUMPING)

func _check_wall_run(delta):
	if velocity.y < -5:  # Only wall run when falling
		return
	
	var left_wall = wall_check_left.is_colliding()
	var right_wall = wall_check_right.is_colliding()
	
	if (left_wall or right_wall) and input_vector.y < -0.5:  # Moving forward
		if left_wall:
			wall_normal = wall_check_left.get_collision_normal()
			wall_run_side = -1
		else:
			wall_normal = wall_check_right.get_collision_normal()
			wall_run_side = 1
		
		_start_wall_run()

func _start_wall_run():
	is_wall_running = true
	wall_run_timer = wall_run_duration
	velocity.y = 0  # Reset vertical velocity
	_change_state(State.WALL_RUNNING)
	emit_signal("parkour_move_performed", "wall_run")

func _update_wall_run(delta):
	wall_run_timer -= delta
	
	# Check if still on wall
	var wall_check = wall_check_left if wall_run_side == -1 else wall_check_right
	
	if wall_run_timer <= 0 or not wall_check.is_colliding() or input_vector.y > -0.5:
		_end_wall_run()
		return
	
	# Apply wall run movement
	var run_direction = wall_normal.cross(Vector3.UP) * wall_run_side
	velocity = run_direction * wall_run_speed
	
	# Slight upward velocity to maintain height
	velocity.y = 2.0
	
	# Camera tilt
	camera_tilt = lerp(camera_tilt, wall_run_side * 15, 5 * delta)

func _end_wall_run():
	is_wall_running = false
	wall_run_timer = 0
	_change_state(State.FALLING)

func _check_ledge_grab():
	if not ledge_check or not ledge_check.is_colliding():
		return
	
	# Check if we can grab the ledge
	var ledge_point = ledge_check.get_collision_point()
	var ledge_norm = ledge_check.get_collision_normal()
	
	# Verify it's a horizontal ledge
	if ledge_norm.y > 0.7:
		_start_ledge_grab(ledge_point, ledge_norm)

func _start_ledge_grab(position: Vector3, normal: Vector3):
	is_ledge_grabbing = true
	ledge_position = position
	ledge_normal = normal
	velocity = Vector3.ZERO
	_change_state(State.LEDGE_GRABBING)
	emit_signal("parkour_move_performed", "ledge_grab")

func _update_ledge_grab(delta):
	# Hang on ledge
	global_transform.origin = ledge_position - Vector3(0, default_height * 0.5, 0)
	
	if Input.is_action_just_pressed("jump"):
		# Climb up
		velocity.y = 10
		global_transform.origin += Vector3(0, 1, 0) - ledge_normal * 0.5
		is_ledge_grabbing = false
		_change_state(State.JUMPING)
		emit_signal("parkour_move_performed", "ledge_climb")
	elif Input.is_action_just_pressed("crouch"):
		# Let go
		is_ledge_grabbing = false
		_change_state(State.FALLING)

func _start_slide():
	slide_direction = velocity.normalized()
	slide_timer = 1.0
	_change_state(State.SLIDING)
	emit_signal("parkour_move_performed", "slide")
	
	# Add momentum
	momentum += 0.3

func _update_slide(delta):
	slide_timer -= delta
	
	# Maintain slide velocity
	velocity = slide_direction * slide_speed * (1.0 - (1.0 - slide_timer))
	
	# Can jump out of slide
	if Input.is_action_just_pressed("jump"):
		velocity.y = sqrt(2 * gravity * jump_height * 1.2)  # Bonus height
		_end_slide()
		emit_signal("parkour_move_performed", "slide_jump")

func _end_slide():
	if _can_stand_up():
		_change_state(State.IDLE)
	else:
		_change_state(State.CROUCHING)

func _check_collisions():
	# Check for vaultable objects
	if vault_check and vault_check.is_colliding() and is_grounded:
		var collision_point = vault_check.get_collision_point()
		var height_diff = collision_point.y - global_transform.origin.y
		
		if height_diff < 1.5 and height_diff > 0.3 and input_vector.y < -0.5:
			_start_vault()

func _start_vault():
	_change_state(State.VAULTING)
	emit_signal("parkour_move_performed", "vault")
	
	# Boost forward
	var forward = -transform.basis.z
	velocity = forward * vault_speed + Vector3.UP * 5

func _update_vault(delta):
	# Simple vault animation
	yield(get_tree().create_timer(0.5), "timeout")
	_change_state(State.IDLE)

func _update_camera_effects(delta):
	# FOV changes
	var target_fov = camera_fov_default
	if current_state == State.SPRINTING:
		target_fov = camera_fov_sprint
	
	if camera:
		camera.fov = lerp(camera.fov, target_fov, 5 * delta)
	
	# Camera tilt
	camera_tilt = lerp(camera_tilt, 0, 5 * delta)
	camera_pivot.rotation.z = deg2rad(camera_tilt)
	
	# Head bob
	if is_grounded and velocity.length() > 0.1:
		var bob_amount = velocity.length() / sprint_speed
		var bob_speed = velocity.length()
		camera_pivot.translation.y = sin(OS.get_ticks_msec() * 0.01 * bob_speed) * 0.1 * bob_amount

func _update_momentum(delta):
	# Build momentum from continuous movement
	if velocity.length() > run_speed:
		momentum = min(momentum + delta * 0.2, 1.0)
	else:
		momentum = max(momentum - delta * 0.5, 0.0)
	
	# Update multiplier
	momentum_multiplier = 1.0 + momentum * 0.5

func _on_landed():
	var fall_speed = -velocity.y
	
	if fall_speed > 15:
		# Hard landing - roll
		_change_state(State.ROLLING)
		emit_signal("parkour_move_performed", "roll")
		
		# Maintain horizontal momentum
		var horizontal_vel = Vector3(velocity.x, 0, velocity.z)
		velocity = horizontal_vel * 0.8
		
		yield(get_tree().create_timer(0.5), "timeout")
		_change_state(State.IDLE)
	elif fall_speed > 8:
		# Medium landing - slight camera shake
		pass

func _can_stand_up() -> bool:
	# Check if there's room to stand
	var space_state = get_world().direct_space_state
	var result = space_state.intersect_ray(
		global_transform.origin,
		global_transform.origin + Vector3.UP * (default_height - crouch_height),
		[self]
	)
	return result.empty()

func get_movement_state() -> String:
	match current_state:
		State.IDLE: return "idle"
		State.WALKING: return "walking"
		State.RUNNING: return "running"
		State.SPRINTING: return "sprinting"
		State.CROUCHING: return "crouching"
		State.SLIDING: return "sliding"
		State.JUMPING: return "jumping"
		State.FALLING: return "falling"
		State.WALL_RUNNING: return "wall_running"
		State.LEDGE_GRABBING: return "ledge_grabbing"
		State.VAULTING: return "vaulting"
		State.ROLLING: return "rolling"
		_: return "unknown"