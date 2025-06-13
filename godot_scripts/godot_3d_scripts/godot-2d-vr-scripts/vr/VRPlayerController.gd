extends XROrigin3D

@export var movement_speed: float = 3.0
@export var turn_speed: float = 45.0
@export var snap_turn: bool = true
@export var smooth_turn: bool = false
@export var room_scale: bool = true
@export var comfort_settings: bool = true

var xr_interface: XRInterface
var left_controller: XRController3D
var right_controller: XRController3D
var head: XRCamera3D

var movement_input: Vector2
var turn_input: float
var is_teleporting: bool = false
var comfort_vignette: float = 0.0

@onready var comfort_overlay: ColorRect = $ComfortSettings/VignetteOverlay
@onready var fade_screen: ColorRect = $ComfortSettings/FadeScreen

signal player_teleported(position: Vector3)
signal controller_connected(controller: XRController3D)
signal controller_disconnected(controller: XRController3D)

func _ready():
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		print("VR interface found and initialized")
		var vp = get_viewport()
		vp.use_xr = true
		setup_controllers()
	else:
		print("VR interface not found - running in flat mode")

func setup_controllers():
	left_controller = $LeftController
	right_controller = $RightController
	head = $XRCamera3D
	
	if left_controller:
		left_controller.button_pressed.connect(_on_left_controller_button_pressed)
		left_controller.button_released.connect(_on_left_controller_button_released)
		left_controller.input_float_changed.connect(_on_left_controller_input_changed)
		left_controller.input_vector2_changed.connect(_on_left_controller_vector2_changed)
	
	if right_controller:
		right_controller.button_pressed.connect(_on_right_controller_button_pressed)
		right_controller.button_released.connect(_on_right_controller_button_released)
		right_controller.input_float_changed.connect(_on_right_controller_input_changed)
		right_controller.input_vector2_changed.connect(_on_right_controller_vector2_changed)

func _physics_process(delta):
	handle_movement(delta)
	handle_rotation(delta)
	update_comfort_settings(delta)

func handle_movement(delta):
	if not left_controller or is_teleporting:
		return
	
	var movement_vector = Vector3()
	
	if room_scale:
		movement_vector = Vector3(movement_input.x, 0, -movement_input.y)
		movement_vector = movement_vector.rotated(Vector3.UP, head.transform.basis.get_euler().y)
	else:
		movement_vector = Vector3(movement_input.x, 0, -movement_input.y)
		movement_vector = movement_vector.rotated(Vector3.UP, global_transform.basis.get_euler().y)
	
	if movement_vector.length() > 0:
		var target_position = global_position + movement_vector * movement_speed * delta
		global_position = target_position
		
		if comfort_settings:
			comfort_vignette = movement_vector.length() * 0.5

func handle_rotation(delta):
	if not right_controller:
		return
	
	if snap_turn and abs(turn_input) > 0.8:
		var snap_angle = 45.0 if turn_input > 0 else -45.0
		rotate_player(snap_angle)
		turn_input = 0
	elif smooth_turn:
		rotate_player(turn_input * turn_speed * delta)

func rotate_player(angle_degrees: float):
	if comfort_settings:
		fade_screen.modulate.a = 0.3
		var tween = create_tween()
		tween.tween_property(fade_screen, "modulate:a", 0.0, 0.2)
	
	global_rotation.y += deg_to_rad(angle_degrees)

func teleport_to_position(position: Vector3):
	if comfort_settings:
		fade_screen.modulate.a = 1.0
		var tween = create_tween()
		tween.tween_property(fade_screen, "modulate:a", 0.0, 0.3)
	
	global_position = position
	emit_signal("player_teleported", position)

func update_comfort_settings(delta):
	if not comfort_settings or not comfort_overlay:
		return
	
	comfort_vignette = lerp(comfort_vignette, 0.0, delta * 3.0)
	comfort_overlay.modulate.a = comfort_vignette

func _on_left_controller_button_pressed(name: String):
	match name:
		"menu_button":
			call_menu()
		"grip":
			start_object_grab(left_controller)
		"trigger":
			interact_with_object(left_controller)

func _on_left_controller_button_released(name: String):
	match name:
		"grip":
			end_object_grab(left_controller)

func _on_left_controller_input_changed(name: String, value: float):
	match name:
		"trigger":
			handle_trigger_pressure(left_controller, value)

func _on_left_controller_vector2_changed(name: String, value: Vector2):
	match name:
		"primary":
			movement_input = value

func _on_right_controller_button_pressed(name: String):
	match name:
		"menu_button":
			call_menu()
		"grip":
			start_object_grab(right_controller)
		"trigger":
			interact_with_object(right_controller)
		"ax_button":
			toggle_comfort_settings()
		"by_button":
			recenter_view()

func _on_right_controller_button_released(name: String):
	match name:
		"grip":
			end_object_grab(right_controller)

func _on_right_controller_input_changed(name: String, value: float):
	match name:
		"trigger":
			handle_trigger_pressure(right_controller, value)

func _on_right_controller_vector2_changed(name: String, value: Vector2):
	match name:
		"primary":
			if snap_turn:
				if abs(value.x) > 0.8 and abs(turn_input) < 0.5:
					turn_input = value.x
			else:
				turn_input = value.x

func start_object_grab(controller: XRController3D):
	var grab_component = controller.get_node_or_null("GrabComponent")
	if grab_component and grab_component.has_method("try_grab"):
		grab_component.try_grab()

func end_object_grab(controller: XRController3D):
	var grab_component = controller.get_node_or_null("GrabComponent")
	if grab_component and grab_component.has_method("release_grab"):
		grab_component.release_grab()

func interact_with_object(controller: XRController3D):
	var interact_component = controller.get_node_or_null("InteractComponent")
	if interact_component and interact_component.has_method("interact"):
		interact_component.interact()

func handle_trigger_pressure(controller: XRController3D, pressure: float):
	var haptic_strength = pressure * 0.3
	if controller.has_method("trigger_haptic_pulse"):
		controller.trigger_haptic_pulse("haptic", 0, 0.1, haptic_strength, 0.1)

func call_menu():
	var menu_system = get_node_or_null("/root/MenuSystem")
	if menu_system and menu_system.has_method("toggle_menu"):
		menu_system.toggle_menu()

func toggle_comfort_settings():
	comfort_settings = not comfort_settings
	print("Comfort settings: ", comfort_settings)

func recenter_view():
	if xr_interface and xr_interface.has_method("center_on_hmd"):
		xr_interface.center_on_hmd(XRServer.RESET_FULL_ROTATION, true)

func set_movement_method(method: String):
	match method:
		"teleport":
			room_scale = false
			movement_speed = 0
		"smooth":
			room_scale = true
			movement_speed = 3.0
		"room_scale":
			room_scale = true

func get_head_position() -> Vector3:
	if head:
		return head.global_position
	return global_position

func get_head_forward() -> Vector3:
	if head:
		return -head.global_transform.basis.z
	return -global_transform.basis.z

func get_controller_position(hand: String) -> Vector3:
	match hand:
		"left":
			return left_controller.global_position if left_controller else Vector3.ZERO
		"right":
			return right_controller.global_position if right_controller else Vector3.ZERO
	return Vector3.ZERO

func haptic_feedback(hand: String, duration: float = 0.1, frequency: float = 0.0, amplitude: float = 0.5):
	var controller = left_controller if hand == "left" else right_controller
	if controller and controller.has_method("trigger_haptic_pulse"):
		controller.trigger_haptic_pulse("haptic", frequency, duration, amplitude, 0.0)