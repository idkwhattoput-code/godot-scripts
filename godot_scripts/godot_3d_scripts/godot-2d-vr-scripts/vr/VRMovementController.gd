extends XROrigin3D

@export var movement_speed: float = 3.0
@export var sprint_multiplier: float = 1.5
@export var smooth_turning_speed: float = 90.0
@export var snap_turn_angle: float = 30.0
@export var comfort_mode: bool = true
@export var snap_turning: bool = false
@export var teleport_range: float = 10.0

var xr_interface: XRInterface
var left_controller: XRController3D
var right_controller: XRController3D
var player_body: CharacterBody3D
var camera: XRCamera3D

var turning_input_threshold: float = 0.7
var last_turn_input: float = 0.0
var can_snap_turn: bool = true

signal teleport_performed(position: Vector3)
signal movement_mode_changed(mode: String)

func _ready():
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		print("VR interface initialized successfully")
		setup_vr_controllers()
	else:
		print("VR interface not found or not initialized")
	
	camera = get_node("XRCamera3D")
	player_body = get_parent()

func setup_vr_controllers():
	left_controller = get_node("LeftController")
	right_controller = get_node("RightController")
	
	if left_controller:
		left_controller.button_pressed.connect(_on_left_button_pressed)
		left_controller.button_released.connect(_on_left_button_released)
	
	if right_controller:
		right_controller.button_pressed.connect(_on_right_button_pressed)
		right_controller.button_released.connect(_on_right_button_released)

func _process(delta):
	handle_movement(delta)
	handle_turning(delta)

func handle_movement(delta):
	if not left_controller or not player_body:
		return
	
	var input_vector = left_controller.get_vector2("primary")
	
	if input_vector.length() > 0.1:
		var forward = -camera.global_transform.basis.z
		var right = camera.global_transform.basis.x
		
		forward.y = 0
		right.y = 0
		forward = forward.normalized()
		right = right.normalized()
		
		var movement_direction = (forward * input_vector.y + right * input_vector.x)
		var speed = movement_speed
		
		if left_controller.is_button_pressed("grip_click"):
			speed *= sprint_multiplier
		
		if comfort_mode:
			movement_direction *= speed * delta
			player_body.global_position += movement_direction
		else:
			if player_body.has_method("set_velocity"):
				var velocity = movement_direction * speed
				velocity.y = player_body.velocity.y if player_body.has_property("velocity") else 0
				player_body.velocity = velocity

func handle_turning(delta):
	if not right_controller:
		return
	
	var turn_input = right_controller.get_vector2("primary").x
	
	if snap_turning:
		handle_snap_turning(turn_input)
	else:
		handle_smooth_turning(turn_input, delta)

func handle_smooth_turning(turn_input: float, delta: float):
	if abs(turn_input) > 0.1:
		var turn_amount = turn_input * smooth_turning_speed * delta
		rotate_y(deg_to_rad(turn_amount))

func handle_snap_turning(turn_input: float):
	if abs(turn_input) > turning_input_threshold and can_snap_turn:
		var turn_direction = sign(turn_input)
		var turn_angle = turn_direction * snap_turn_angle
		rotate_y(deg_to_rad(turn_angle))
		can_snap_turn = false
	elif abs(turn_input) < 0.3:
		can_snap_turn = true

func handle_teleportation():
	if not right_controller:
		return
	
	var space_state = get_world_3d().direct_space_state
	var from = right_controller.global_position
	var to = from + (-right_controller.global_transform.basis.z * teleport_range)
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result:
		teleport_to_position(result.position)

func teleport_to_position(target_position: Vector3):
	global_position = target_position
	teleport_performed.emit(target_position)

func set_movement_mode(mode: String):
	match mode:
		"comfort":
			comfort_mode = true
			movement_mode_changed.emit("comfort")
		"direct":
			comfort_mode = false
			movement_mode_changed.emit("direct")

func set_turning_mode(snap: bool):
	snap_turning = snap
	var mode = "snap" if snap else "smooth"
	movement_mode_changed.emit("turning_" + mode)

func _on_left_button_pressed(button: String):
	match button:
		"trigger_click":
			pass
		"grip_click":
			pass

func _on_left_button_released(button: String):
	match button:
		"trigger_click":
			pass
		"grip_click":
			pass

func _on_right_button_pressed(button: String):
	match button:
		"trigger_click":
			handle_teleportation()
		"by_button":
			snap_turning = !snap_turning

func _on_right_button_released(button: String):
	match button:
		"trigger_click":
			pass