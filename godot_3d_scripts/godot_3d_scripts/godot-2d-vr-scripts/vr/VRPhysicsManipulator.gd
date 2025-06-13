extends Node3D

class_name VRPhysicsManipulator

signal object_manipulation_started(object: RigidBody3D)
signal object_manipulation_ended(object: RigidBody3D)
signal force_applied(object: RigidBody3D, force: Vector3)

@export var max_manipulation_distance: float = 5.0
@export var force_multiplier: float = 1.0
@export var rotation_speed: float = 2.0
@export var scaling_speed: float = 0.5
@export var haptic_feedback_strength: float = 0.3

@onready var left_controller: XRController3D = get_node("../LeftController")
@onready var right_controller: XRController3D = get_node("../RightController")

var manipulated_objects: Dictionary = {}
var manipulation_joints: Dictionary = {}
var controller_positions: Dictionary = {}
var controller_rotations: Dictionary = {}
var initial_distances: Dictionary = {}

enum ManipulationMode {
	NONE,
	GRAB,
	FORCE_PUSH_PULL,
	ROTATE,
	SCALE
}

var current_mode: ManipulationMode = ManipulationMode.NONE
var two_handed_object: RigidBody3D = null

func _ready():
	if left_controller:
		left_controller.button_pressed.connect(_on_left_controller_pressed)
		left_controller.button_released.connect(_on_left_controller_released)
	
	if right_controller:
		right_controller.button_pressed.connect(_on_right_controller_pressed)
		right_controller.button_released.connect(_on_right_controller_released)

func _physics_process(delta):
	update_controller_tracking()
	handle_force_manipulation(delta)
	handle_two_handed_manipulation(delta)
	update_visual_feedback()

func update_controller_tracking():
	if left_controller:
		controller_positions["left"] = left_controller.global_position
		controller_rotations["left"] = left_controller.global_rotation
	
	if right_controller:
		controller_positions["right"] = right_controller.global_position
		controller_rotations["right"] = right_controller.global_rotation

func _on_left_controller_pressed(button: String):
	match button:
		"trigger":
			start_force_manipulation("left")
		"grip":
			start_grab_manipulation("left")
		"primary":
			set_manipulation_mode(ManipulationMode.ROTATE)
		"secondary":
			set_manipulation_mode(ManipulationMode.SCALE)

func _on_left_controller_released(button: String):
	match button:
		"trigger":
			end_force_manipulation("left")
		"grip":
			end_grab_manipulation("left")
		"primary", "secondary":
			set_manipulation_mode(ManipulationMode.NONE)

func _on_right_controller_pressed(button: String):
	match button:
		"trigger":
			start_force_manipulation("right")
		"grip":
			start_grab_manipulation("right")
		"primary":
			set_manipulation_mode(ManipulationMode.ROTATE)
		"secondary":
			set_manipulation_mode(ManipulationMode.SCALE)

func _on_right_controller_released(button: String):
	match button:
		"trigger":
			end_force_manipulation("right")
		"grip":
			end_grab_manipulation("right")
		"primary", "secondary":
			set_manipulation_mode(ManipulationMode.NONE)

func start_force_manipulation(hand: String):
	var controller = get_controller(hand)
	if not controller:
		return
	
	var target_object = find_target_object(controller)
	if target_object:
		manipulated_objects[hand] = target_object
		object_manipulation_started.emit(target_object)
		trigger_haptic_feedback(controller, 0.2)

func end_force_manipulation(hand: String):
	if manipulated_objects.has(hand):
		var obj = manipulated_objects[hand]
		manipulated_objects.erase(hand)
		object_manipulation_ended.emit(obj)

func start_grab_manipulation(hand: String):
	var controller = get_controller(hand)
	if not controller:
		return
	
	var target_object = find_target_object(controller)
	if not target_object:
		return
	
	if manipulated_objects.has(hand):
		end_grab_manipulation(hand)
	
	manipulated_objects[hand] = target_object
	
	var joint = Generic6DOFJoint3D.new()
	add_child(joint)
	joint.node_a = controller.get_path()
	joint.node_b = target_object.get_path()
	
	manipulation_joints[hand] = joint
	
	setup_grab_joint(joint)
	object_manipulation_started.emit(target_object)
	trigger_haptic_feedback(controller, 0.3)
	
	check_for_two_handed_manipulation(target_object)

func end_grab_manipulation(hand: String):
	if manipulation_joints.has(hand):
		manipulation_joints[hand].queue_free()
		manipulation_joints.erase(hand)
	
	if manipulated_objects.has(hand):
		var obj = manipulated_objects[hand]
		manipulated_objects.erase(hand)
		object_manipulation_ended.emit(obj)
		
		if two_handed_object == obj:
			two_handed_object = null

func setup_grab_joint(joint: Generic6DOFJoint3D):
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LIMIT_ENABLED, true)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LIMIT_ENABLED, true)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LIMIT_ENABLED, true)
	
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_ENABLED, true)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_ENABLED, true)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_ENABLED, true)
	
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS, 2000)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS, 2000)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS, 2000)
	
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_DAMPING, 100)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_DAMPING, 100)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_DAMPING, 100)

func handle_force_manipulation(delta: float):
	for hand in manipulated_objects.keys():
		if not manipulation_joints.has(hand):
			var controller = get_controller(hand)
			var obj = manipulated_objects[hand]
			
			if controller and obj and is_instance_valid(obj):
				apply_force_manipulation(controller, obj, delta)

func apply_force_manipulation(controller: XRController3D, object: RigidBody3D, delta: float):
	var controller_pos = controller.global_position
	var object_pos = object.global_position
	var distance = controller_pos.distance_to(object_pos)
	
	if distance > max_manipulation_distance:
		return
	
	var trigger_value = controller.get_float("trigger")
	var direction = (controller_pos - object_pos).normalized()
	
	var force_strength = trigger_value * force_multiplier / (distance * distance + 1.0)
	var force = direction * force_strength
	
	object.apply_central_force(force)
	force_applied.emit(object, force)
	
	if trigger_value > 0.5:
		trigger_haptic_feedback(controller, trigger_value * 0.1)

func check_for_two_handed_manipulation(object: RigidBody3D):
	var hands_on_object = 0
	for hand in manipulated_objects.keys():
		if manipulated_objects[hand] == object:
			hands_on_object += 1
	
	if hands_on_object >= 2:
		two_handed_object = object
		store_initial_two_handed_data()

func store_initial_two_handed_data():
	if not two_handed_object:
		return
	
	if controller_positions.has("left") and controller_positions.has("right"):
		var distance = controller_positions["left"].distance_to(controller_positions["right"])
		initial_distances["two_handed"] = distance

func handle_two_handed_manipulation(delta: float):
	if not two_handed_object or not is_instance_valid(two_handed_object):
		return
	
	if not (manipulated_objects.has("left") and manipulated_objects.has("right")):
		return
	
	if manipulated_objects["left"] != two_handed_object or manipulated_objects["right"] != two_handed_object:
		return
	
	match current_mode:
		ManipulationMode.ROTATE:
			handle_two_handed_rotation(delta)
		ManipulationMode.SCALE:
			handle_two_handed_scaling(delta)

func handle_two_handed_rotation(delta: float):
	if not controller_positions.has("left") or not controller_positions.has("right"):
		return
	
	var left_pos = controller_positions["left"]
	var right_pos = controller_positions["right"]
	var center = (left_pos + right_pos) * 0.5
	
	var current_vector = (right_pos - left_pos).normalized()
	var rotation_axis = Vector3.UP
	
	var angular_velocity = rotation_speed * delta
	two_handed_object.angular_velocity = rotation_axis * angular_velocity

func handle_two_handed_scaling(delta: float):
	if not controller_positions.has("left") or not controller_positions.has("right"):
		return
	
	var current_distance = controller_positions["left"].distance_to(controller_positions["right"])
	
	if not initial_distances.has("two_handed"):
		initial_distances["two_handed"] = current_distance
		return
	
	var distance_ratio = current_distance / initial_distances["two_handed"]
	var scale_change = (distance_ratio - 1.0) * scaling_speed * delta
	
	var new_scale = two_handed_object.scale + Vector3.ONE * scale_change
	new_scale = new_scale.clamp(Vector3.ONE * 0.1, Vector3.ONE * 5.0)
	two_handed_object.scale = new_scale

func find_target_object(controller: XRController3D) -> RigidBody3D:
	var space_state = get_world_3d().direct_space_state
	var from = controller.global_position
	var to = from + (-controller.global_transform.basis.z * max_manipulation_distance)
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	
	var result = space_state.intersect_ray(query)
	if result and result.collider is RigidBody3D:
		return result.collider as RigidBody3D
	
	return null

func get_controller(hand: String) -> XRController3D:
	match hand:
		"left":
			return left_controller
		"right":
			return right_controller
	return null

func set_manipulation_mode(mode: ManipulationMode):
	current_mode = mode

func trigger_haptic_feedback(controller: XRController3D, duration: float):
	if controller and controller.has_method("trigger_haptic_pulse"):
		controller.trigger_haptic_pulse("haptic", 0, haptic_feedback_strength, duration, 0)

func update_visual_feedback():
	pass

func get_manipulated_object(hand: String) -> RigidBody3D:
	return manipulated_objects.get(hand, null)

func is_manipulating() -> bool:
	return manipulated_objects.size() > 0

func force_release_all():
	for hand in manipulated_objects.keys():
		end_grab_manipulation(hand)
		end_force_manipulation(hand)