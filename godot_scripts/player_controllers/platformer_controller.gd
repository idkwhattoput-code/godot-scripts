extends KinematicBody

# Movement settings
export var move_speed = 300.0
export var acceleration = 2000.0
export var friction = 2000.0
export var air_friction = 200.0

# Jump settings
export var jump_velocity = -600.0
export var jump_cut_multiplier = 0.5
export var gravity = 1800.0
export var max_fall_speed = 900.0
export var double_jump_velocity = -500.0
export var wall_jump_velocity = Vector2(400, -500)

# Advanced movement
export var dash_speed = 800.0
export var dash_duration = 0.2
export var dash_cooldown = 0.5
export var wall_slide_speed = 100.0
export var wall_climb_speed = -200.0
export var ledge_grab_enabled = true

# Coyote time and jump buffering
export var coyote_time = 0.1
export var jump_buffer_time = 0.1

# States
var velocity = Vector3.ZERO
var is_jumping = false
var is_dashing = false
var is_wall_sliding = false
var is_ledge_grabbing = false
var can_double_jump = true
var can_dash = true
var facing_direction = 1

# Timers
var coyote_timer = 0.0
var jump_buffer_timer = 0.0
var dash_timer = 0.0
var dash_cooldown_timer = 0.0
var wall_jump_timer = 0.0

# Wall detection
var wall_direction = 0
var last_wall_direction = 0

# Components
onready var sprite = $Sprite3D
onready var animation_player = $AnimationPlayer
onready var state_machine = $StateMachine
onready var wall_check_left = $WallCheckLeft
onready var wall_check_right = $WallCheckRight
onready var ledge_check_left = $LedgeCheckLeft
onready var ledge_check_right = $LedgeCheckRight
onready var ground_check = $GroundCheck
onready var dash_ghost_timer = $DashGhostTimer
onready var dash_particles = $DashParticles
onready var jump_particles = $JumpParticles
onready var land_particles = $LandParticles

signal jumped()
signal double_jumped()
signal wall_jumped()
signal dashed()
signal landed()
signal wall_slide_started()
signal wall_slide_ended()
signal ledge_grabbed()

func _ready():
	dash_ghost_timer.connect("timeout", self, "_spawn_dash_ghost")

func _physics_process(delta):
	_update_timers(delta)
	_check_walls()
	_handle_gravity(delta)
	_handle_input(delta)
	_handle_movement(delta)
	_update_sprite()
	_update_particles()

func _update_timers(delta):
	# Coyote time
	if is_on_floor():
		coyote_timer = coyote_time
		can_double_jump = true
	else:
		coyote_timer -= delta
	
	# Jump buffer
	if jump_buffer_timer > 0:
		jump_buffer_timer -= delta
	
	# Dash cooldown
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta
		if dash_cooldown_timer <= 0:
			can_dash = true
	
	# Dash duration
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false
			dash_ghost_timer.stop()
	
	# Wall jump grace period
	if wall_jump_timer > 0:
		wall_jump_timer -= delta

func _check_walls():
	wall_direction = 0
	
	if wall_check_left and wall_check_left.is_colliding():
		wall_direction = -1
	elif wall_check_right and wall_check_right.is_colliding():
		wall_direction = 1
	
	# Check for ledges
	if ledge_grab_enabled and wall_direction != 0:
		var ledge_check = ledge_check_left if wall_direction == -1 else ledge_check_right
		if ledge_check and not ledge_check.is_colliding() and velocity.y > 0:
			if not is_ledge_grabbing:
				_grab_ledge()

func _handle_gravity(delta):
	if is_ledge_grabbing:
		velocity.y = 0
		return
	
	if not is_on_floor() and not is_dashing:
		if is_wall_sliding:
			velocity.y += gravity * delta * 0.5
			velocity.y = min(velocity.y, wall_slide_speed)
		else:
			velocity.y += gravity * delta
			velocity.y = min(velocity.y, max_fall_speed)

func _handle_input(delta):
	var input_dir = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	
	# Jump input
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time
		
		if is_ledge_grabbing:
			_ledge_climb()
	
	# Jump execution
	if jump_buffer_timer > 0:
		if coyote_timer > 0:
			_jump()
		elif is_wall_sliding and wall_jump_timer <= 0:
			_wall_jump()
		elif can_double_jump and not is_on_floor():
			_double_jump()
	
	# Variable jump height
	if Input.is_action_just_released("jump") and velocity.y < 0 and is_jumping:
		velocity.y *= jump_cut_multiplier
		is_jumping = false
	
	# Dash
	if Input.is_action_just_pressed("dash") and can_dash and not is_dashing:
		_start_dash(input_dir)
	
	# Wall sliding
	if wall_direction != 0 and not is_on_floor() and velocity.y > 0:
		if (wall_direction == -1 and input_dir < 0) or (wall_direction == 1 and input_dir > 0):
			if not is_wall_sliding:
				is_wall_sliding = true
				emit_signal("wall_slide_started")
		else:
			if is_wall_sliding:
				is_wall_sliding = false
				emit_signal("wall_slide_ended")
	else:
		if is_wall_sliding:
			is_wall_sliding = false
			emit_signal("wall_slide_ended")
	
	# Ledge release
	if is_ledge_grabbing:
		if Input.is_action_just_pressed("move_down"):
			_release_ledge()

func _handle_movement(delta):
	var input_dir = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	
	if is_dashing or is_ledge_grabbing:
		return
	
	# Horizontal movement
	if input_dir != 0:
		facing_direction = sign(input_dir)
		
		var target_speed = input_dir * move_speed
		var accel = acceleration if is_on_floor() else air_friction
		
		# Wall jump momentum preservation
		if wall_jump_timer > 0:
			accel *= 0.5
		
		velocity.x = move_toward(velocity.x, target_speed, accel * delta)
	else:
		var fric = friction if is_on_floor() else air_friction
		velocity.x = move_toward(velocity.x, 0, fric * delta)
	
	# Move
	velocity = move_and_slide(velocity, Vector3.UP)
	
	# Landing
	if is_on_floor() and not was_on_floor:
		emit_signal("landed")
		_spawn_land_particles()

func _jump():
	velocity.y = jump_velocity
	is_jumping = true
	coyote_timer = 0
	jump_buffer_timer = 0
	emit_signal("jumped")
	_spawn_jump_particles()

func _double_jump():
	velocity.y = double_jump_velocity
	can_double_jump = false
	jump_buffer_timer = 0
	emit_signal("double_jumped")
	_spawn_jump_particles()

func _wall_jump():
	velocity.x = wall_jump_velocity.x * -wall_direction
	velocity.y = wall_jump_velocity.y
	wall_jump_timer = 0.3
	is_wall_sliding = false
	jump_buffer_timer = 0
	emit_signal("wall_jumped")
	_spawn_jump_particles()

func _start_dash(input_dir: float):
	is_dashing = true
	can_dash = false
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	
	var dash_dir = input_dir if input_dir != 0 else facing_direction
	velocity.x = dash_dir * dash_speed
	velocity.y = 0
	
	dash_ghost_timer.start(0.05)
	emit_signal("dashed")

func _grab_ledge():
	is_ledge_grabbing = true
	velocity = Vector3.ZERO
	emit_signal("ledge_grabbed")

func _ledge_climb():
	is_ledge_grabbing = false
	velocity.y = wall_climb_speed
	# Move player up and forward
	global_transform.origin.y += 32  # Adjust based on your tile size
	global_transform.origin.x += 16 * wall_direction

func _release_ledge():
	is_ledge_grabbing = false
	velocity.y = 0

func _spawn_dash_ghost():
	if not is_dashing:
		return
	
	var ghost = Sprite3D.new()
	ghost.texture = sprite.texture
	ghost.modulate = Color(1, 1, 1, 0.5)
	ghost.global_transform = sprite.global_transform
	get_parent().add_child(ghost)
	
	# Fade out ghost
	var tween = Tween.new()
	ghost.add_child(tween)
	tween.interpolate_property(ghost, "modulate:a", 0.5, 0, 0.5)
	tween.start()
	
	yield(tween, "tween_all_completed")
	ghost.queue_free()

func _spawn_jump_particles():
	if jump_particles:
		jump_particles.emitting = true

func _spawn_land_particles():
	if land_particles:
		land_particles.emitting = true

func _update_sprite():
	if sprite:
		sprite.flip_h = facing_direction < 0

func _update_particles():
	if dash_particles:
		dash_particles.emitting = is_dashing

func get_state() -> String:
	if is_ledge_grabbing:
		return "ledge_grab"
	elif is_dashing:
		return "dash"
	elif is_wall_sliding:
		return "wall_slide"
	elif not is_on_floor():
		return "air"
	elif abs(velocity.x) > 10:
		return "run"
	else:
		return "idle"

var was_on_floor = false
func _process(_delta):
	was_on_floor = is_on_floor()