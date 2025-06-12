extends KinematicBody

# Third Person Controller for Godot 3D
# Attach to a KinematicBody with a CollisionShape and a Spatial node for camera pivot
# Camera should be a child of the pivot point with a spring arm

# Movement settings
export var move_speed = 8.0
export var sprint_multiplier = 1.8
export var jump_height = 10.0
export var gravity = -30.0
export var air_control = 0.3
export var ground_acceleration = 10.0
export var ground_friction = 8.0
export var rotation_speed = 10.0

# Camera settings
export var camera_distance = 5.0
export var camera_height = 2.0
export var camera_sensitivity = 0.005
export var camera_smoothing = 0.1

# Animation states
export var idle_animation = "idle"
export var walk_animation = "walk"
export var run_animation = "run"
export var jump_animation = "jump"
export var fall_animation = "fall"

# Internal variables
var velocity = Vector3.ZERO
var camera_rotation = Vector2.ZERO
var is_sprinting = false
var move_direction = Vector3.ZERO

# Components
onready var camera_pivot = $CameraPivot
onready var spring_arm = $CameraPivot/SpringArm
onready var camera = $CameraPivot/SpringArm/Camera
onready var animation_player = $AnimationPlayer if has_node("AnimationPlayer") else null
onready var mesh_instance = $MeshInstance if has_node("MeshInstance") else null

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Setup spring arm
	if spring_arm:
		spring_arm.spring_length = camera_distance
		spring_arm.translation.y = camera_height

func _input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera_rotation.x -= event.relative.x * camera_sensitivity
		camera_rotation.y = clamp(camera_rotation.y - event.relative.y * camera_sensitivity, -1.2, 0.5)
	
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta):
	# Get input
	var input_vector = Vector2.ZERO
	input_vector.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_vector.y = Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	input_vector = input_vector.normalized()
	
	# Calculate movement direction relative to camera
	var cam_transform = camera.get_global_transform()
	var cam_basis = cam_transform.basis
	move_direction = Vector3.ZERO
	move_direction += -cam_basis.z * input_vector.y
	move_direction += cam_basis.x * input_vector.x
	move_direction.y = 0
	move_direction = move_direction.normalized()
	
	# Sprint handling
	is_sprinting = Input.is_action_pressed("sprint") and is_on_floor()
	var current_speed = move_speed * (sprint_multiplier if is_sprinting else 1.0)
	
	# Apply movement
	if move_direction.length() > 0:
		# Rotate character to face movement direction
		var target_rotation = atan2(move_direction.x, move_direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)
		
		# Move character
		if is_on_floor():
			velocity.x = lerp(velocity.x, move_direction.x * current_speed, ground_acceleration * delta)
			velocity.z = lerp(velocity.z, move_direction.z * current_speed, ground_acceleration * delta)
		else:
			# Air control
			velocity.x = lerp(velocity.x, move_direction.x * current_speed, air_control * delta)
			velocity.z = lerp(velocity.z, move_direction.z * current_speed, air_control * delta)
	else:
		# Apply friction when not moving
		if is_on_floor():
			velocity.x = lerp(velocity.x, 0, ground_friction * delta)
			velocity.z = lerp(velocity.z, 0, ground_friction * delta)
	
	# Jump handling
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_height
	
	# Apply gravity
	if not is_on_floor():
		velocity.y += gravity * delta
	
	# Move the character
	velocity = move_and_slide(velocity, Vector3.UP)
	
	# Update camera
	if camera_pivot:
		camera_pivot.rotation.y = lerp_angle(camera_pivot.rotation.y, camera_rotation.x, camera_smoothing)
		if spring_arm:
			spring_arm.rotation.x = lerp(spring_arm.rotation.x, camera_rotation.y, camera_smoothing)
	
	# Update animations
	update_animations()

func update_animations():
	if not animation_player:
		return
	
	var speed = Vector2(velocity.x, velocity.z).length()
	
	if not is_on_floor():
		if velocity.y > 0:
			play_animation(jump_animation)
		else:
			play_animation(fall_animation)
	elif speed > 0.1:
		if is_sprinting:
			play_animation(run_animation)
		else:
			play_animation(walk_animation)
	else:
		play_animation(idle_animation)

func play_animation(anim_name):
	if animation_player and animation_player.has_animation(anim_name):
		if animation_player.current_animation != anim_name:
			animation_player.play(anim_name)

# Helper function for smooth angle interpolation
func lerp_angle(from, to, weight):
	var difference = fmod(to - from, TAU)
	var distance = fmod(2.0 * difference, TAU) - difference
	return from + distance * weight