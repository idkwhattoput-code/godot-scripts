extends KinematicBody

# First Person Controller for Godot 3D
# Attach this script to a KinematicBody with a CollisionShape and a Camera as child
# Features: WASD movement, jump, sprint, crouch, head bob, mouse look

# Movement settings
export var walk_speed = 7.0
export var sprint_speed = 12.0
export var crouch_speed = 3.0
export var jump_force = 12.0
export var gravity = -30.0
export var acceleration = 10.0
export var friction = 6.0

# Mouse sensitivity
export var mouse_sensitivity = 0.3
export var mouse_smoothing = 0.05

# Head bob settings
export var head_bob_sprint_speed = 22.0
export var head_bob_walk_speed = 14.0
export var head_bob_sprint_intensity = 0.2
export var head_bob_walk_intensity = 0.1

# States
var velocity = Vector3.ZERO
var snap_vector = Vector3.ZERO
var current_speed = walk_speed
var is_sprinting = false
var is_crouching = false

# Components
onready var camera = $Camera
onready var collision_shape = $CollisionShape

# Head bob variables
var head_bob_timer = 0.0
var head_bob_vector = Vector2.ZERO

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	if event is InputEventMouseMotion:
		rotate_y(deg2rad(-event.relative.x * mouse_sensitivity))
		camera.rotate_x(deg2rad(-event.relative.y * mouse_sensitivity))
		camera.rotation.x = clamp(camera.rotation.x, deg2rad(-90), deg2rad(90))
	
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta):
	# Handle movement input
	var input_vector = Vector2.ZERO
	input_vector.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_vector.y = Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	input_vector = input_vector.normalized()
	
	# Get movement direction
	var direction = Vector3.ZERO
	direction += transform.basis.x * input_vector.x
	direction += transform.basis.z * input_vector.y
	
	# Handle sprint and crouch
	if Input.is_action_pressed("sprint") and not is_crouching:
		is_sprinting = true
		current_speed = sprint_speed
	else:
		is_sprinting = false
		current_speed = walk_speed
	
	if Input.is_action_pressed("crouch"):
		is_crouching = true
		current_speed = crouch_speed
		# Reduce collision shape height
		if collision_shape.shape is CapsuleShape:
			collision_shape.shape.height = 1.0
	else:
		is_crouching = false
		# Reset collision shape height
		if collision_shape.shape is CapsuleShape:
			collision_shape.shape.height = 2.0
	
	# Apply movement
	if direction.length() > 0:
		velocity.x = lerp(velocity.x, direction.x * current_speed, acceleration * delta)
		velocity.z = lerp(velocity.z, direction.z * current_speed, acceleration * delta)
		
		# Head bob
		if is_on_floor():
			if is_sprinting:
				head_bob_timer += delta * head_bob_sprint_speed
				head_bob_vector = Vector2(
					cos(head_bob_timer) * head_bob_sprint_intensity,
					abs(sin(head_bob_timer)) * head_bob_sprint_intensity
				)
			else:
				head_bob_timer += delta * head_bob_walk_speed
				head_bob_vector = Vector2(
					cos(head_bob_timer) * head_bob_walk_intensity,
					abs(sin(head_bob_timer)) * head_bob_walk_intensity
				)
	else:
		velocity.x = lerp(velocity.x, 0, friction * delta)
		velocity.z = lerp(velocity.z, 0, friction * delta)
		head_bob_vector = head_bob_vector.linear_interpolate(Vector2.ZERO, 0.1)
	
	# Apply head bob to camera
	camera.transform.origin = Vector3(
		head_bob_vector.x,
		1.5 + head_bob_vector.y,
		0
	)
	
	# Handle jump
	if is_on_floor():
		snap_vector = -get_floor_normal()
		if Input.is_action_just_pressed("jump") and not is_crouching:
			velocity.y = jump_force
			snap_vector = Vector3.ZERO
	else:
		snap_vector = Vector3.ZERO
		velocity.y += gravity * delta
	
	# Move the player
	velocity = move_and_slide_with_snap(velocity, snap_vector, Vector3.UP, true)

# Helper function to add required input actions
func get_required_input_actions():
	return {
		"move_forward": KEY_W,
		"move_backward": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"jump": KEY_SPACE,
		"sprint": KEY_SHIFT,
		"crouch": KEY_CONTROL
	}