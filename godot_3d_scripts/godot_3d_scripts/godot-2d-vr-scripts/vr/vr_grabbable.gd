extends RigidBody

export var grab_distance: float = 0.1
export var throw_velocity_multiplier: float = 2.0
export var rotation_smoothing: float = 10.0
export var position_smoothing: float = 15.0
export var haptic_on_grab: float = 0.2
export var haptic_on_release: float = 0.1
export var two_handed_grab: bool = true
export var maintain_grab_offset: bool = true
export var scale_with_distance: bool = false

var grabbed_by_controller: ARVRController = null
var secondary_controller: ARVRController = null
var grab_offset: Transform
var original_parent: Node
var was_kinematic: bool = false
var grab_point_offset: Vector3

signal grabbed(controller)
signal released(controller)
signal secondary_grabbed(controller)
signal secondary_released(controller)

func _ready():
	add_to_group("grabbable")
	collision_layer = collision_layer | 4
	
	if not has_meta("original_scale"):
		set_meta("original_scale", scale)

func _physics_process(delta):
	if grabbed_by_controller:
		_update_grabbed_position(delta)
		
		if secondary_controller and two_handed_grab:
			_update_two_handed_grab(delta)

func can_grab() -> bool:
	return grabbed_by_controller == null

func grab(controller: ARVRController):
	if grabbed_by_controller:
		return false
	
	grabbed_by_controller = controller
	original_parent = get_parent()
	was_kinematic = mode == MODE_KINEMATIC
	
	mode = MODE_KINEMATIC
	collision_layer = collision_layer & ~4
	
	if maintain_grab_offset:
		grab_offset = global_transform.inverse() * controller.global_transform
		grab_point_offset = controller.global_transform.origin - global_transform.origin
	else:
		grab_offset = Transform()
		grab_point_offset = Vector3.ZERO
	
	if controller.has_method("trigger_haptic_pulse"):
		controller.trigger_haptic_pulse(haptic_on_grab, 0.5)
	
	emit_signal("grabbed", controller)
	return true

func release(controller: ARVRController, velocity: Vector3 = Vector3.ZERO):
	if grabbed_by_controller != controller:
		return
	
	grabbed_by_controller = null
	
	if not was_kinematic:
		mode = MODE_RIGID
		linear_velocity = velocity * throw_velocity_multiplier
		
		if controller.has_method("get_controller_angular_velocity"):
			angular_velocity = controller.get_controller_angular_velocity()
	
	collision_layer = collision_layer | 4
	
	if secondary_controller:
		secondary_controller = null
		emit_signal("secondary_released", controller)
	
	if controller.has_method("trigger_haptic_pulse"):
		controller.trigger_haptic_pulse(haptic_on_release, 0.3)
	
	emit_signal("released", controller)

func add_secondary_grab(controller: ARVRController):
	if not two_handed_grab or secondary_controller or controller == grabbed_by_controller:
		return false
	
	secondary_controller = controller
	emit_signal("secondary_grabbed", controller)
	return true

func remove_secondary_grab(controller: ARVRController):
	if secondary_controller != controller:
		return
	
	secondary_controller = null
	emit_signal("secondary_released", controller)

func _update_grabbed_position(delta):
	if not grabbed_by_controller:
		return
	
	var target_transform: Transform
	
	if maintain_grab_offset:
		target_transform = grabbed_by_controller.global_transform * grab_offset
	else:
		target_transform = grabbed_by_controller.global_transform
		target_transform.origin -= grab_point_offset
	
	if position_smoothing > 0:
		global_transform.origin = global_transform.origin.linear_interpolate(
			target_transform.origin, 
			position_smoothing * delta
		)
	else:
		global_transform.origin = target_transform.origin
	
	if rotation_smoothing > 0:
		global_transform.basis = global_transform.basis.slerp(
			target_transform.basis,
			rotation_smoothing * delta
		)
	else:
		global_transform.basis = target_transform.basis

func _update_two_handed_grab(delta):
	if not secondary_controller or not grabbed_by_controller:
		return
	
	var primary_pos = grabbed_by_controller.global_transform.origin
	var secondary_pos = secondary_controller.global_transform.origin
	
	var center_pos = (primary_pos + secondary_pos) * 0.5
	global_transform.origin = center_pos
	
	var direction = (secondary_pos - primary_pos).normalized()
	var up = Vector3.UP
	
	if abs(direction.dot(up)) > 0.9:
		up = Vector3.RIGHT
	
	var right = direction.cross(up).normalized()
	up = right.cross(direction).normalized()
	
	global_transform.basis = Basis(right, up, -direction)
	
	if scale_with_distance and has_meta("original_scale"):
		var current_distance = primary_pos.distance_to(secondary_pos)
		var scale_factor = current_distance / 0.3
		scale = get_meta("original_scale") * scale_factor

func get_grab_controller() -> ARVRController:
	return grabbed_by_controller

func get_secondary_controller() -> ARVRController:
	return secondary_controller

func is_grabbed() -> bool:
	return grabbed_by_controller != null

func is_two_hand_grabbed() -> bool:
	return grabbed_by_controller != null and secondary_controller != null

func force_drop():
	if grabbed_by_controller:
		release(grabbed_by_controller, Vector3.ZERO)

func set_grabbable(grabbable: bool):
	if grabbable:
		add_to_group("grabbable")
		collision_layer = collision_layer | 4
	else:
		remove_from_group("grabbable")
		collision_layer = collision_layer & ~4
		if grabbed_by_controller:
			force_drop()