extends Node3D

class_name VRObjectGrabbing

signal object_grabbed(obj: RigidBody3D)
signal object_released(obj: RigidBody3D)
signal grab_attempt_failed(reason: String)
signal physics_hand_collision(body: Node3D)

enum GrabType {
	PRECISE,
	DISTANCE,
	PHYSICS_HAND
}

enum GrabMode {
	RIGID,
	SPRING,
	KINEMATIC
}

@export var grab_type: GrabType = GrabType.PRECISE
@export var grab_mode: GrabMode = GrabMode.SPRING
@export var grab_distance: float = 0.15
@export var grab_strength: float = 1000.0
@export var grab_damping: float = 50.0
@export var rotation_strength: float = 500.0
@export var rotation_damping: float = 25.0
@export var break_force: float = 500.0
@export var haptic_feedback_strength: float = 0.3
@export var enable_physics_hand: bool = true
@export var hand_collision_layers: int = 1

var controller: XRController3D
var grabbed_object: RigidBody3D
var grab_joint: Generic6DOFJoint3D
var grab_area: Area3D
var physics_hand: RigidBody3D
var hand_shape: CollisionShape3D

var grab_offset: Transform3D
var original_gravity_scale: float
var is_grabbing: bool = false
var last_velocity: Vector3
var last_angular_velocity: Vector3

@onready var grab_point: Marker3D = $GrabPoint
@onready var physics_hand_mesh: MeshInstance3D = $PhysicsHand/Mesh

func _ready():
	setup_controller_reference()
	setup_grab_area()
	setup_physics_hand()
	connect_controller_signals()

func setup_controller_reference():
	controller = get_parent() as XRController3D
	if not controller:
		push_error("VRObjectGrabbing must be a child of XRController3D")

func setup_grab_area():
	grab_area = Area3D.new()
	grab_area.name = "GrabArea"
	add_child(grab_area)
	
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = grab_distance
	collision_shape.shape = sphere_shape
	grab_area.add_child(collision_shape)
	
	grab_area.body_entered.connect(_on_grabbable_entered)
	grab_area.body_exited.connect(_on_grabbable_exited)

func setup_physics_hand():
	if not enable_physics_hand:
		return
	
	physics_hand = RigidBody3D.new()
	physics_hand.name = "PhysicsHand"
	physics_hand.gravity_scale = 0
	physics_hand.lock_rotation = true
	physics_hand.collision_layer = hand_collision_layers
	physics_hand.collision_mask = hand_collision_layers
	add_child(physics_hand)
	
	hand_shape = CollisionShape3D.new()
	var capsule_shape = CapsuleShape3D.new()
	capsule_shape.radius = 0.03
	capsule_shape.height = 0.08
	hand_shape.shape = capsule_shape
	physics_hand.add_child(hand_shape)
	
	if physics_hand_mesh:
		physics_hand.add_child(physics_hand_mesh)
	
	physics_hand.body_entered.connect(_on_physics_hand_collision)

func connect_controller_signals():
	if controller:
		controller.button_pressed.connect(_on_controller_button_pressed)
		controller.button_released.connect(_on_controller_button_released)
		controller.input_float_changed.connect(_on_controller_input_changed)

func _physics_process(delta):
	update_physics_hand()
	update_grabbed_object(delta)
	update_hand_tracking()

func update_physics_hand():
	if not physics_hand or not enable_physics_hand:
		return
	
	var target_position = global_position
	var target_velocity = (target_position - physics_hand.global_position) * 60.0
	
	physics_hand.linear_velocity = target_velocity
	physics_hand.global_rotation = global_rotation

func update_grabbed_object(delta):
	if not is_grabbing or not grabbed_object:
		return
	
	match grab_mode:
		GrabMode.RIGID:
			update_rigid_grab()
		GrabMode.SPRING:
			update_spring_grab(delta)
		GrabMode.KINEMATIC:
			update_kinematic_grab()

func update_rigid_grab():
	if grab_joint:
		grab_joint.global_position = global_position

func update_spring_grab(delta):
	if not grabbed_object:
		return
	
	var target_position = global_position + global_transform.basis * grab_offset.origin
	var target_rotation = global_transform.basis * grab_offset.basis
	
	var position_error = target_position - grabbed_object.global_position
	var rotation_error = calculate_rotation_error(target_rotation, grabbed_object.global_transform.basis)
	
	var force = position_error * grab_strength - grabbed_object.linear_velocity * grab_damping
	var torque = rotation_error * rotation_strength - grabbed_object.angular_velocity * rotation_damping
	
	grabbed_object.apply_central_force(force)
	grabbed_object.apply_torque(torque)
	
	if force.length() > break_force:
		release_object()

func update_kinematic_grab():
	if not grabbed_object:
		return
	
	grabbed_object.global_position = global_position + global_transform.basis * grab_offset.origin
	grabbed_object.global_transform.basis = global_transform.basis * grab_offset.basis

func update_hand_tracking():
	var current_velocity = calculate_velocity()
	var current_angular_velocity = calculate_angular_velocity()
	
	last_velocity = current_velocity
	last_angular_velocity = current_angular_velocity

func calculate_velocity() -> Vector3:
	if controller and controller.has_method("get_velocity"):
		return controller.get_velocity()
	return Vector3.ZERO

func calculate_angular_velocity() -> Vector3:
	if controller and controller.has_method("get_angular_velocity"):
		return controller.get_angular_velocity()
	return Vector3.ZERO

func calculate_rotation_error(target_basis: Basis, current_basis: Basis) -> Vector3:
	var rotation_diff = target_basis * current_basis.transposed()
	return rotation_diff.get_euler()

func attempt_grab() -> bool:
	if is_grabbing:
		return false
	
	var target_object = find_closest_grabbable()
	if not target_object:
		emit_signal("grab_attempt_failed", "No grabbable object in range")
		return false
	
	return grab_object(target_object)

func find_closest_grabbable() -> RigidBody3D:
	var closest_object: RigidBody3D = null
	var closest_distance: float = INF
	
	for body in grab_area.get_overlapping_bodies():
		if body is RigidBody3D and body.is_in_group("grabbable"):
			var distance = global_position.distance_to(body.global_position)
			if distance < closest_distance:
				closest_distance = distance
				closest_object = body
	
	return closest_object

func grab_object(obj: RigidBody3D) -> bool:
	if not obj or is_grabbing:
		return false
	
	if obj.has_method("can_be_grabbed") and not obj.can_be_grabbed():
		emit_signal("grab_attempt_failed", "Object cannot be grabbed")
		return false
	
	grabbed_object = obj
	is_grabbing = true
	
	calculate_grab_offset()
	setup_grab_constraint()
	
	if obj.has_method("on_grabbed"):
		obj.on_grabbed(controller)
	
	provide_haptic_feedback(haptic_feedback_strength, 0.1)
	emit_signal("object_grabbed", obj)
	
	return true

func calculate_grab_offset():
	if not grabbed_object:
		return
	
	grab_offset = global_transform.inverse() * grabbed_object.global_transform

func setup_grab_constraint():
	if not grabbed_object or grab_mode == GrabMode.KINEMATIC:
		return
	
	match grab_mode:
		GrabMode.RIGID:
			setup_rigid_constraint()
		GrabMode.SPRING:
			original_gravity_scale = grabbed_object.gravity_scale
			grabbed_object.gravity_scale = 0

func setup_rigid_constraint():
	if grab_joint:
		grab_joint.queue_free()
	
	grab_joint = Generic6DOFJoint3D.new()
	get_tree().current_scene.add_child(grab_joint)
	
	var anchor = StaticBody3D.new()
	get_tree().current_scene.add_child(anchor)
	anchor.global_position = global_position
	
	grab_joint.node_a = anchor.get_path()
	grab_joint.node_b = grabbed_object.get_path()
	
	for i in range(3):
		grab_joint.set_flag_x(i, true)
		grab_joint.set_flag_y(i, true)
		grab_joint.set_flag_z(i, true)

func release_object():
	if not is_grabbing or not grabbed_object:
		return
	
	var released_object = grabbed_object
	
	if grabbed_object.has_method("on_released"):
		grabbed_object.on_released(controller)
	
	apply_release_velocity()
	cleanup_grab_constraint()
	
	grabbed_object = null
	is_grabbing = false
	
	provide_haptic_feedback(haptic_feedback_strength * 0.5, 0.05)
	emit_signal("object_released", released_object)

func apply_release_velocity():
	if not grabbed_object:
		return
	
	var release_velocity = last_velocity * 1.5
	var release_angular_velocity = last_angular_velocity * 1.2
	
	grabbed_object.linear_velocity = release_velocity
	grabbed_object.angular_velocity = release_angular_velocity

func cleanup_grab_constraint():
	if grab_joint:
		grab_joint.queue_free()
		grab_joint = null
	
	if grabbed_object and grab_mode == GrabMode.SPRING:
		grabbed_object.gravity_scale = original_gravity_scale

func force_release():
	if is_grabbing:
		release_object()

func set_grab_strength(strength: float):
	grab_strength = strength

func set_grab_distance(distance: float):
	grab_distance = distance
	if grab_area and grab_area.get_child(0):
		var shape = grab_area.get_child(0).shape as SphereShape3D
		if shape:
			shape.radius = distance

func get_grabbed_object() -> RigidBody3D:
	return grabbed_object

func is_object_grabbed() -> bool:
	return is_grabbing

func provide_haptic_feedback(strength: float, duration: float):
	if controller and controller.has_method("trigger_haptic_pulse"):
		controller.trigger_haptic_pulse("haptic", 0, duration, strength, 0.0)

func throw_object(force_multiplier: float = 2.0):
	if not is_grabbing or not grabbed_object:
		return
	
	var throw_velocity = last_velocity * force_multiplier
	var throw_angular_velocity = last_angular_velocity * force_multiplier
	
	grabbed_object.linear_velocity = throw_velocity
	grabbed_object.angular_velocity = throw_angular_velocity
	
	release_object()

func can_grab_object(obj: RigidBody3D) -> bool:
	if not obj or obj == grabbed_object:
		return false
	
	if not obj.is_in_group("grabbable"):
		return false
	
	if obj.has_method("can_be_grabbed"):
		return obj.can_be_grabbed()
	
	return true

func get_grab_candidates() -> Array[RigidBody3D]:
	var candidates: Array[RigidBody3D] = []
	
	for body in grab_area.get_overlapping_bodies():
		if body is RigidBody3D and can_grab_object(body):
			candidates.append(body)
	
	return candidates

func highlight_grabbable_objects(enable: bool):
	for body in get_grab_candidates():
		if body.has_method("set_highlight"):
			body.set_highlight(enable)

func _on_controller_button_pressed(button_name: String):
	match button_name:
		"grip", "trigger":
			attempt_grab()

func _on_controller_button_released(button_name: String):
	match button_name:
		"grip", "trigger":
			if is_grabbing:
				release_object()

func _on_controller_input_changed(input_name: String, value: float):
	match input_name:
		"grip":
			if value > 0.8 and not is_grabbing:
				attempt_grab()
			elif value < 0.2 and is_grabbing:
				release_object()

func _on_grabbable_entered(body: Node3D):
	if body is RigidBody3D and body.is_in_group("grabbable"):
		if body.has_method("on_hover_enter"):
			body.on_hover_enter(controller)

func _on_grabbable_exited(body: Node3D):
	if body is RigidBody3D and body.is_in_group("grabbable"):
		if body.has_method("on_hover_exit"):
			body.on_hover_exit(controller)

func _on_physics_hand_collision(body: Node3D):
	emit_signal("physics_hand_collision", body)
	
	if body.has_method("on_hand_touch"):
		body.on_hand_touch(controller)

func enable_physics_hand_collision(enable: bool):
	enable_physics_hand = enable
	if physics_hand:
		physics_hand.freeze = not enable

func set_hand_collision_layers(layers: int):
	hand_collision_layers = layers
	if physics_hand:
		physics_hand.collision_layer = layers
		physics_hand.collision_mask = layers

func get_grab_settings() -> Dictionary:
	return {
		"grab_type": grab_type,
		"grab_mode": grab_mode,
		"grab_distance": grab_distance,
		"grab_strength": grab_strength,
		"grab_damping": grab_damping,
		"break_force": break_force,
		"haptic_feedback": haptic_feedback_strength
	}

func apply_grab_settings(settings: Dictionary):
	grab_type = settings.get("grab_type", GrabType.PRECISE)
	grab_mode = settings.get("grab_mode", GrabMode.SPRING)
	grab_distance = settings.get("grab_distance", 0.15)
	grab_strength = settings.get("grab_strength", 1000.0)
	grab_damping = settings.get("grab_damping", 50.0)
	break_force = settings.get("break_force", 500.0)
	haptic_feedback_strength = settings.get("haptic_feedback", 0.3)
	
	set_grab_distance(grab_distance)