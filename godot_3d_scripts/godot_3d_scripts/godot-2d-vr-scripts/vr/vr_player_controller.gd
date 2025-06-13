extends ARVROrigin

export var player_height: float = 1.8
export var movement_speed: float = 3.0
export var smooth_turn_speed: float = 90.0
export var snap_turn_angle: float = 30.0
export var use_snap_turning: bool = true
export var teleport_enabled: bool = true

var left_controller: ARVRController
var right_controller: ARVRController
var camera: ARVRCamera
var character_body: KinematicBody

var velocity: Vector3 = Vector3.ZERO
var snap_turn_cooldown: float = 0.0

func _ready():
	left_controller = get_node("LeftController")
	right_controller = get_node("RightController")
	camera = get_node("ARVRCamera")
	character_body = get_node("CharacterBody")
	
	var vr_interface = ARVRServer.find_interface("OpenXR")
	if vr_interface and vr_interface.initialize():
		get_viewport().arvr = true
		get_viewport().hdr = false
		OS.vsync_enabled = false
		Engine.target_fps = 90
	else:
		print("VR interface failed to initialize")

func _physics_process(delta):
	_handle_movement(delta)
	_handle_turning(delta)
	_update_character_position()
	
	if snap_turn_cooldown > 0:
		snap_turn_cooldown -= delta

func _handle_movement(delta):
	var movement = Vector2.ZERO
	
	if left_controller:
		movement = Vector2(
			left_controller.get_joystick_axis(0),
			left_controller.get_joystick_axis(1)
		)
	
	if movement.length() > 0.1:
		var direction = Vector3(movement.x, 0, movement.y)
		direction = direction.rotated(Vector3.UP, camera.global_transform.basis.get_euler().y)
		direction = direction.normalized()
		
		velocity = direction * movement_speed
		if character_body:
			character_body.move_and_slide(velocity, Vector3.UP)

func _handle_turning(delta):
	if not right_controller:
		return
	
	var turn_input = right_controller.get_joystick_axis(0)
	
	if use_snap_turning:
		if abs(turn_input) > 0.8 and snap_turn_cooldown <= 0:
			var turn_angle = snap_turn_angle if turn_input > 0 else -snap_turn_angle
			rotate_y(deg2rad(turn_angle))
			snap_turn_cooldown = 0.3
	else:
		if abs(turn_input) > 0.1:
			rotate_y(deg2rad(-turn_input * smooth_turn_speed * delta))

func _update_character_position():
	if not character_body or not camera:
		return
	
	var camera_position = camera.transform.origin
	camera_position.y = 0
	character_body.transform.origin = transform.origin + camera_position

func get_camera_forward():
	if camera:
		var forward = -camera.global_transform.basis.z
		forward.y = 0
		return forward.normalized()
	return Vector3.FORWARD

func get_player_height():
	if camera:
		return camera.transform.origin.y
	return player_height

func recenter_player():
	var camera_position = camera.transform.origin
	camera_position.y = 0
	transform.origin -= camera_position