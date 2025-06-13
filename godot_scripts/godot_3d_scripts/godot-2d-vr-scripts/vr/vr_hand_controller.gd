extends ARVRController

export var controller_id: int = 1
export var haptic_duration: float = 0.1
export var haptic_intensity: float = 0.5

onready var hand_mesh = $HandMesh
onready var controller_mesh = $ControllerMesh
onready var interaction_area = $InteractionArea
onready var pointer = $Pointer

var button_states: Dictionary = {}
var previous_button_states: Dictionary = {}
var current_velocity: Vector3 = Vector3.ZERO
var previous_position: Vector3 = Vector3.ZERO
var is_tracking: bool = false

signal button_pressed(button_name)
signal button_released(button_name)
signal trigger_pressed(value)
signal grip_pressed(value)

func _ready():
	controller_id = 1 if name == "LeftController" else 2
	set_physics_process(true)
	
	if interaction_area:
		interaction_area.connect("body_entered", self, "_on_body_entered")
		interaction_area.connect("body_exited", self, "_on_body_exited")

func _physics_process(delta):
	is_tracking = get_is_active()
	
	if is_tracking:
		_update_velocity(delta)
		_update_button_states()
		_handle_haptics()
		_update_visuals()

func _update_velocity(delta):
	if delta > 0:
		current_velocity = (global_transform.origin - previous_position) / delta
		previous_position = global_transform.origin

func _update_button_states():
	previous_button_states = button_states.duplicate()
	
	button_states["trigger"] = is_button_pressed(JOY_VR_TRIGGER)
	button_states["grip"] = is_button_pressed(JOY_VR_GRIP)
	button_states["menu"] = is_button_pressed(JOY_OPENVR_MENU)
	button_states["touchpad"] = is_button_pressed(JOY_VR_PAD)
	button_states["a_button"] = is_button_pressed(JOY_OCULUS_AX)
	button_states["b_button"] = is_button_pressed(JOY_OCULUS_BY)
	
	var trigger_value = get_joystick_axis(JOY_VR_ANALOG_TRIGGER)
	var grip_value = get_joystick_axis(JOY_VR_ANALOG_GRIP)
	
	if trigger_value > 0.1:
		emit_signal("trigger_pressed", trigger_value)
	
	if grip_value > 0.1:
		emit_signal("grip_pressed", grip_value)
	
	for button in button_states:
		if button_states[button] and not previous_button_states.get(button, false):
			emit_signal("button_pressed", button)
		elif not button_states[button] and previous_button_states.get(button, false):
			emit_signal("button_released", button)

func _handle_haptics():
	if get_rumble() > 0:
		rumble = max(0, rumble - get_physics_process_delta_time())

func _update_visuals():
	if hand_mesh and controller_mesh:
		var show_hands = ProjectSettings.get_setting("vr/show_hands", false)
		hand_mesh.visible = show_hands and is_tracking
		controller_mesh.visible = not show_hands and is_tracking

func _on_body_entered(body):
	if body.has_method("on_hand_entered"):
		body.on_hand_entered(self)
	trigger_haptic_pulse(0.1, 0.3)

func _on_body_exited(body):
	if body.has_method("on_hand_exited"):
		body.on_hand_exited(self)

func trigger_haptic_pulse(duration: float = 0.1, amplitude: float = 0.5):
	rumble = clamp(amplitude, 0.0, 1.0)
	yield(get_tree().create_timer(duration), "timeout")
	rumble = 0.0

func get_button_state(button_name: String) -> bool:
	return button_states.get(button_name, false)

func get_controller_velocity() -> Vector3:
	return current_velocity

func get_controller_angular_velocity() -> Vector3:
	return Vector3.ZERO

func is_button_just_pressed(button_name: String) -> bool:
	return button_states.get(button_name, false) and not previous_button_states.get(button_name, false)

func is_button_just_released(button_name: String) -> bool:
	return not button_states.get(button_name, false) and previous_button_states.get(button_name, false)

func get_touchpad_position() -> Vector2:
	return Vector2(
		get_joystick_axis(JOY_VR_PAD_X),
		get_joystick_axis(JOY_VR_PAD_Y)
	)

func get_thumbstick_position() -> Vector2:
	return Vector2(
		get_joystick_axis(JOY_ANALOG_LX),
		get_joystick_axis(JOY_ANALOG_LY)
	)