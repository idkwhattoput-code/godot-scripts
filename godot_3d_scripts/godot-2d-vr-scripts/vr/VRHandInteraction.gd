extends Node3D

@export var grab_distance: float = 0.15
@export var interaction_distance: float = 0.3
@export var hand_type: String = "left"
@export var haptic_feedback_enabled: bool = true

var controller: XRController3D
var grabbed_object: RigidBody3D = null
var grab_joint: Generic6DOFJoint3D = null
var interaction_area: Area3D
var hand_mesh: MeshInstance3D

var is_gripping: bool = false
var trigger_pressure: float = 0.0
var last_controller_position: Vector3
var last_controller_rotation: Quaternion

@onready var grab_area: Area3D = $GrabArea
@onready var interaction_raycast: RayCast3D = $InteractionRaycast
@onready var hand_skeleton: XRHandModifier3D = $HandSkeleton

signal object_grabbed(object: RigidBody3D)
signal object_released(object: RigidBody3D)
signal object_interacted(object: Node3D)

func _ready():
	controller = get_parent() as XRController3D
	if not controller:
		print("VRHandInteraction must be child of XRController3D")
		return
	
	setup_grab_area()
	setup_interaction_raycast()
	
	if hand_skeleton:
		hand_skeleton.hand_tracker = "/user/hand/" + hand_type
	
	controller.button_pressed.connect(_on_controller_button_pressed)
	controller.button_released.connect(_on_controller_button_released)
	controller.input_float_changed.connect(_on_controller_input_changed)

func _physics_process(delta):
	update_hand_tracking()
	update_grabbed_object()
	highlight_interactables()

func setup_grab_area():
	if not grab_area:
		grab_area = Area3D.new()
		add_child(grab_area)
	
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = grab_distance
	collision_shape.shape = sphere_shape
	grab_area.add_child(collision_shape)
	
	grab_area.area_entered.connect(_on_grab_area_entered)
	grab_area.area_exited.connect(_on_grab_area_exited)
	grab_area.body_entered.connect(_on_grab_body_entered)
	grab_area.body_exited.connect(_on_grab_body_exited)

func setup_interaction_raycast():
	if not interaction_raycast:
		interaction_raycast = RayCast3D.new()
		add_child(interaction_raycast)
	
	interaction_raycast.target_position = Vector3(0, 0, -interaction_distance)
	interaction_raycast.enabled = true
	interaction_raycast.collision_mask = 1

func update_hand_tracking():
	if not controller:
		return
	
	last_controller_position = controller.global_position
	last_controller_rotation = controller.global_transform.basis.get_rotation_quaternion()
	
	if hand_skeleton:
		hand_skeleton.process_hand_tracking()

func try_grab():
	if grabbed_object:
		return false
	
	var bodies = grab_area.get_overlapping_bodies()
	var closest_body: RigidBody3D = null
	var closest_distance: float = INF
	
	for body in bodies:
		if body is RigidBody3D and body.has_method("can_be_grabbed"):
			if body.can_be_grabbed():
				var distance = global_position.distance_to(body.global_position)
				if distance < closest_distance:
					closest_distance = distance
					closest_body = body
	
	if closest_body:
		grab_object(closest_body)
		return true
	
	return false

func grab_object(object: RigidBody3D):
	if grabbed_object:
		release_grab()
	
	grabbed_object = object
	
	if grabbed_object.has_method("on_grabbed"):
		grabbed_object.on_grabbed(self)
	
	create_grab_joint()
	
	if haptic_feedback_enabled:
		trigger_haptic_feedback(0.3, 0.1)
	
	emit_signal("object_grabbed", grabbed_object)

func create_grab_joint():
	if not grabbed_object:
		return
	
	grab_joint = Generic6DOFJoint3D.new()
	get_tree().current_scene.add_child(grab_joint)
	
	grab_joint.node_a = grabbed_object.get_path()
	
	var static_body = StaticBody3D.new()
	get_tree().current_scene.add_child(static_body)
	static_body.global_position = controller.global_position
	static_body.global_rotation = controller.global_rotation
	
	grab_joint.node_b = static_body.get_path()

func release_grab():
	if not grabbed_object:
		return
	
	var released_object = grabbed_object
	
	if grabbed_object.has_method("on_released"):
		grabbed_object.on_released(self)
	
	if grab_joint:
		grab_joint.queue_free()
		grab_joint = null
	
	grabbed_object = null
	
	if haptic_feedback_enabled:
		trigger_haptic_feedback(0.2, 0.05)
	
	emit_signal("object_released", released_object)

func update_grabbed_object():
	if not grabbed_object or not grab_joint:
		return
	
	var static_body = get_node(grab_joint.node_b)
	if static_body:
		static_body.global_position = controller.global_position
		static_body.global_rotation = controller.global_rotation

func interact():
	if interaction_raycast.is_colliding():
		var collider = interaction_raycast.get_collider()
		if collider and collider.has_method("interact"):
			collider.interact(self)
			emit_signal("object_interacted", collider)
			
			if haptic_feedback_enabled:
				trigger_haptic_feedback(0.1, 0.05)

func highlight_interactables():
	if interaction_raycast.is_colliding():
		var collider = interaction_raycast.get_collider()
		if collider and collider.has_method("highlight"):
			collider.highlight(true)
	
	var last_highlighted = get_meta("last_highlighted", null)
	if last_highlighted and last_highlighted != interaction_raycast.get_collider():
		if last_highlighted.has_method("highlight"):
			last_highlighted.highlight(false)
	
	set_meta("last_highlighted", interaction_raycast.get_collider())

func trigger_haptic_feedback(amplitude: float, duration: float):
	if controller and controller.has_method("trigger_haptic_pulse"):
		controller.trigger_haptic_pulse("haptic", 0, duration, amplitude, 0.0)

func _on_controller_button_pressed(name: String):
	match name:
		"grip":
			is_gripping = true
			try_grab()
		"trigger":
			interact()

func _on_controller_button_released(name: String):
	match name:
		"grip":
			is_gripping = false
			release_grab()

func _on_controller_input_changed(name: String, value: float):
	match name:
		"trigger":
			trigger_pressure = value
			if trigger_pressure > 0.1 and haptic_feedback_enabled:
				trigger_haptic_feedback(trigger_pressure * 0.2, 0.02)

func _on_grab_area_entered(area: Area3D):
	if area.has_method("on_hand_nearby"):
		area.on_hand_nearby(self)

func _on_grab_area_exited(area: Area3D):
	if area.has_method("on_hand_left"):
		area.on_hand_left(self)

func _on_grab_body_entered(body: Node3D):
	if body.has_method("on_hand_nearby"):
		body.on_hand_nearby(self)

func _on_grab_body_exited(body: Node3D):
	if body.has_method("on_hand_left"):
		body.on_hand_left(self)

func get_hand_velocity() -> Vector3:
	if not controller:
		return Vector3.ZERO
	
	return controller.get_vector3("velocity") if controller.has_method("get_vector3") else Vector3.ZERO

func get_angular_velocity() -> Vector3:
	if not controller:
		return Vector3.ZERO
	
	return controller.get_vector3("angular_velocity") if controller.has_method("get_vector3") else Vector3.ZERO

func is_pointing_at(target: Node3D) -> bool:
	if not target:
		return false
	
	var direction = (target.global_position - global_position).normalized()
	var forward = -global_transform.basis.z
	var dot_product = forward.dot(direction)
	
	return dot_product > 0.8

func get_pointed_position(distance: float = 1.0) -> Vector3:
	return global_position + (-global_transform.basis.z * distance)

func set_hand_visibility(visible: bool):
	if hand_mesh:
		hand_mesh.visible = visible

func add_finger_tracking():
	if hand_skeleton and hand_skeleton.has_method("set_bone_update"):
		hand_skeleton.set_bone_update(XRHandModifier3D.BONE_UPDATE_FULL)

func get_finger_position(finger_name: String) -> Vector3:
	if hand_skeleton:
		var bone_id = hand_skeleton.find_bone(finger_name)
		if bone_id != -1:
			return hand_skeleton.get_bone_global_pose(bone_id).origin
	
	return Vector3.ZERO

func is_making_gesture(gesture_name: String) -> bool:
	match gesture_name:
		"point":
			return trigger_pressure > 0.7 and not is_gripping
		"fist":
			return is_gripping and trigger_pressure > 0.8
		"open_palm":
			return not is_gripping and trigger_pressure < 0.1
		_:
			return false