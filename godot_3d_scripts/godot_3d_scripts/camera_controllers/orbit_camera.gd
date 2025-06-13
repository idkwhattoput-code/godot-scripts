extends Spatial

# Orbit Camera Controller for Godot 3D
# Creates a smooth orbiting camera that follows a target
# Can be used for RTS games, level editors, or cinematic cameras

# Target settings
export var target_path: NodePath
export var follow_target = true
export var target_offset = Vector3(0, 1, 0)

# Camera settings
export var distance = 10.0
export var min_distance = 2.0
export var max_distance = 50.0
export var height = 5.0
export var rotation_speed = 2.0
export var zoom_speed = 1.0
export var pan_speed = 0.5
export var smoothing = 5.0

# Orbit limits
export var min_pitch = -80.0
export var max_pitch = 80.0
export var enable_rotation = true
export var enable_zoom = true
export var enable_pan = true

# Input settings
export var invert_x = false
export var invert_y = false
export var mouse_sensitivity = 0.5
export var use_mouse_wheel_zoom = true

# Internal variables
var target: Spatial
var camera: Camera
var current_rotation = Vector2.ZERO
var current_distance: float
var pan_offset = Vector3.ZERO
var is_rotating = false

func _ready():
	# Create camera if it doesn't exist
	if not has_node("Camera"):
		camera = Camera.new()
		add_child(camera)
	else:
		camera = $Camera
	
	# Get target
	if target_path:
		target = get_node(target_path)
	
	# Initialize values
	current_distance = distance
	position_camera()

func _input(event):
	# Mouse rotation
	if enable_rotation:
		if event is InputEventMouseButton:
			if event.button_index == BUTTON_MIDDLE:
				is_rotating = event.pressed
		
		if event is InputEventMouseMotion and is_rotating:
			var delta_x = event.relative.x * mouse_sensitivity * (-1 if invert_x else 1)
			var delta_y = event.relative.y * mouse_sensitivity * (-1 if invert_y else 1)
			
			current_rotation.x -= delta_x
			current_rotation.y = clamp(current_rotation.y - delta_y, min_pitch, max_pitch)
	
	# Mouse wheel zoom
	if enable_zoom and use_mouse_wheel_zoom:
		if event is InputEventMouseButton:
			if event.button_index == BUTTON_WHEEL_UP:
				current_distance = clamp(current_distance - zoom_speed, min_distance, max_distance)
			elif event.button_index == BUTTON_WHEEL_DOWN:
				current_distance = clamp(current_distance + zoom_speed, min_distance, max_distance)
	
	# Pan with right mouse button
	if enable_pan:
		if event is InputEventMouseButton and event.button_index == BUTTON_RIGHT:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE)
		
		if event is InputEventMouseMotion and Input.is_action_pressed("mouse_right"):
			var pan_delta = Vector3(event.relative.x, -event.relative.y, 0) * pan_speed * 0.01
			pan_offset += transform.basis * pan_delta

func _process(delta):
	# Keyboard input for rotation
	if enable_rotation:
		var rotation_input = Vector2.ZERO
		rotation_input.x = Input.get_action_strength("camera_right") - Input.get_action_strength("camera_left")
		rotation_input.y = Input.get_action_strength("camera_down") - Input.get_action_strength("camera_up")
		
		current_rotation.x += rotation_input.x * rotation_speed * delta * 100
		current_rotation.y = clamp(current_rotation.y + rotation_input.y * rotation_speed * delta * 100, min_pitch, max_pitch)
	
	# Keyboard input for zoom
	if enable_zoom:
		var zoom_input = Input.get_action_strength("camera_zoom_in") - Input.get_action_strength("camera_zoom_out")
		current_distance = clamp(current_distance - zoom_input * zoom_speed * delta * 10, min_distance, max_distance)
	
	# Update camera position
	position_camera()

func position_camera():
	if not camera:
		return
	
	# Calculate target position
	var target_pos = Vector3.ZERO
	if target and follow_target:
		target_pos = target.global_transform.origin + target_offset
	
	# Apply pan offset
	target_pos += pan_offset
	
	# Calculate camera position based on orbit
	var rotation_rad = Vector2(deg2rad(current_rotation.x), deg2rad(current_rotation.y))
	
	var offset = Vector3.ZERO
	offset.x = cos(rotation_rad.y) * sin(rotation_rad.x) * current_distance
	offset.y = sin(rotation_rad.y) * current_distance + height
	offset.z = cos(rotation_rad.y) * cos(rotation_rad.x) * current_distance
	
	# Smooth camera movement
	var desired_position = target_pos + offset
	global_transform.origin = global_transform.origin.linear_interpolate(desired_position, smoothing * get_process_delta_time())
	
	# Look at target
	look_at(target_pos, Vector3.UP)

# Public methods
func set_target(new_target: Spatial):
	target = new_target

func reset_camera():
	current_rotation = Vector2.ZERO
	current_distance = distance
	pan_offset = Vector3.ZERO

func focus_on_target():
	if target:
		pan_offset = Vector3.ZERO
		position_camera()

# Get required input actions
func get_required_input_actions():
	return {
		"camera_left": KEY_Q,
		"camera_right": KEY_E,
		"camera_up": KEY_R,
		"camera_down": KEY_F,
		"camera_zoom_in": KEY_PLUS,
		"camera_zoom_out": KEY_MINUS,
		"mouse_right": BUTTON_RIGHT
	}