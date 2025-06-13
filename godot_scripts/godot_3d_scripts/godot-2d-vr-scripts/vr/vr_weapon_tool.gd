extends Spatial

export var tool_name: String = "Default Tool"
export var requires_two_hands: bool = false
export var primary_grip_point: NodePath
export var secondary_grip_point: NodePath
export var trigger_action_delay: float = 0.0
export var continuous_action: bool = false
export var haptic_feedback_strength: float = 0.3
export var recoil_force: float = 0.0
export var tool_weight: float = 1.0

onready var primary_grip = get_node_or_null(primary_grip_point)
onready var secondary_grip = get_node_or_null(secondary_grip_point)
onready var muzzle_point = $MuzzlePoint
onready var action_audio = $ActionAudio
onready var reload_audio = $ReloadAudio

var primary_controller: ARVRController = null
var secondary_controller: ARVRController = null
var is_equipped: bool = false
var is_active: bool = false
var action_cooldown: float = 0.0
var original_transform: Transform

signal tool_equipped(controller)
signal tool_unequipped(controller)
signal tool_activated
signal tool_deactivated
signal tool_fired
signal tool_reloaded

func _ready():
	original_transform = transform
	add_to_group("vr_tools")
	
	if has_node("Grabbable"):
		var grabbable = $Grabbable
		grabbable.connect("grabbed", self, "_on_grabbed")
		grabbable.connect("released", self, "_on_released")
		grabbable.connect("secondary_grabbed", self, "_on_secondary_grabbed")
		grabbable.connect("secondary_released", self, "_on_secondary_released")

func _physics_process(delta):
	if action_cooldown > 0:
		action_cooldown -= delta
	
	if is_equipped and primary_controller:
		_handle_input(delta)
		_update_tool_orientation(delta)

func _on_grabbed(controller: ARVRController):
	equip(controller)

func _on_released(controller: ARVRController):
	unequip()

func _on_secondary_grabbed(controller: ARVRController):
	if requires_two_hands:
		secondary_controller = controller
		_adjust_two_handed_grip()

func _on_secondary_released(controller: ARVRController):
	secondary_controller = null

func equip(controller: ARVRController):
	if is_equipped:
		return
	
	primary_controller = controller
	is_equipped = true
	
	if primary_controller:
		primary_controller.connect("button_pressed", self, "_on_controller_button_pressed")
		primary_controller.connect("button_released", self, "_on_controller_button_released")
	
	emit_signal("tool_equipped", controller)
	
	if has_method("_on_equipped"):
		_on_equipped()

func unequip():
	if not is_equipped:
		return
	
	if primary_controller:
		primary_controller.disconnect("button_pressed", self, "_on_controller_button_pressed")
		primary_controller.disconnect("button_released", self, "_on_controller_button_released")
	
	is_equipped = false
	is_active = false
	primary_controller = null
	secondary_controller = null
	
	emit_signal("tool_unequipped", primary_controller)
	
	if has_method("_on_unequipped"):
		_on_unequipped()

func _handle_input(delta):
	if not primary_controller:
		return
	
	var trigger_value = primary_controller.get_joystick_axis(JOY_VR_ANALOG_TRIGGER)
	
	if continuous_action and trigger_value > 0.1:
		if action_cooldown <= 0:
			activate_tool()
	
	var grip_value = primary_controller.get_joystick_axis(JOY_VR_ANALOG_GRIP)
	if grip_value < 0.3 and not requires_two_hands:
		unequip()

func _on_controller_button_pressed(button_name: String):
	match button_name:
		"trigger":
			if not continuous_action and action_cooldown <= 0:
				activate_tool()
		"a_button", "x_button":
			reload_tool()
		"b_button", "y_button":
			if has_method("secondary_action"):
				secondary_action()

func _on_controller_button_released(button_name: String):
	match button_name:
		"trigger":
			if is_active:
				deactivate_tool()

func activate_tool():
	if action_cooldown > 0:
		return
	
	is_active = true
	action_cooldown = trigger_action_delay
	
	if has_method("_on_activate"):
		_on_activate()
	
	if action_audio:
		action_audio.play()
	
	if primary_controller and haptic_feedback_strength > 0:
		primary_controller.rumble = haptic_feedback_strength
	
	if recoil_force > 0:
		_apply_recoil()
	
	emit_signal("tool_activated")
	emit_signal("tool_fired")

func deactivate_tool():
	is_active = false
	
	if primary_controller:
		primary_controller.rumble = 0.0
	
	if has_method("_on_deactivate"):
		_on_deactivate()
	
	emit_signal("tool_deactivated")

func reload_tool():
	if has_method("can_reload") and not can_reload():
		return
	
	if reload_audio:
		reload_audio.play()
	
	if has_method("_on_reload"):
		_on_reload()
	
	emit_signal("tool_reloaded")

func _apply_recoil():
	if not primary_controller:
		return
	
	var recoil_direction = -global_transform.basis.z
	var recoil_impulse = recoil_direction * recoil_force
	
	if get_parent() is RigidBody:
		get_parent().apply_central_impulse(recoil_impulse)
	
	if primary_controller.has_method("trigger_haptic_pulse"):
		primary_controller.trigger_haptic_pulse(0.1, min(recoil_force * 0.1, 1.0))

func _update_tool_orientation(delta):
	if not requires_two_hands or not secondary_controller:
		return
	
	_adjust_two_handed_grip()

func _adjust_two_handed_grip():
	if not primary_grip or not secondary_grip:
		return
	
	var primary_pos = primary_controller.global_transform.origin
	var secondary_pos = secondary_controller.global_transform.origin
	
	var grip_direction = (secondary_pos - primary_pos).normalized()
	var up = Vector3.UP
	
	if abs(grip_direction.dot(up)) > 0.9:
		up = Vector3.RIGHT
	
	var right = grip_direction.cross(up).normalized()
	up = right.cross(grip_direction).normalized()
	
	look_at(global_transform.origin + grip_direction, up)

func get_muzzle_position() -> Vector3:
	if muzzle_point:
		return muzzle_point.global_transform.origin
	return global_transform.origin

func get_muzzle_direction() -> Vector3:
	if muzzle_point:
		return -muzzle_point.global_transform.basis.z
	return -global_transform.basis.z

func set_tool_enabled(enabled: bool):
	set_physics_process(enabled)
	visible = enabled

func get_tool_info() -> Dictionary:
	return {
		"name": tool_name,
		"equipped": is_equipped,
		"active": is_active,
		"requires_two_hands": requires_two_hands,
		"has_secondary": secondary_controller != null
	}