extends XRController3D

class_name VRHandTracking

signal hand_gesture_detected(gesture_name: String)
signal finger_bend_changed(finger: FingerType, bend_amount: float)
signal hand_collision_started(body: Node3D)
signal hand_collision_ended(body: Node3D)
signal grab_attempted(target: Node3D)
signal grab_released(target: Node3D)

enum HandType {
	LEFT,
	RIGHT
}

enum FingerType {
	THUMB,
	INDEX,
	MIDDLE,
	RING,
	PINKY
}

enum GestureType {
	FIST,
	POINT,
	PEACE,
	THUMBS_UP,
	OPEN_PALM,
	PINCH,
	GRAB
}

@export var hand_type: HandType = HandType.RIGHT
@export var enable_hand_tracking: bool = true
@export var enable_gesture_recognition: bool = true
@export var enable_finger_tracking: bool = true
@export var grab_distance: float = 0.1
@export var pointer_distance: float = 2.0
@export var haptic_feedback_strength: float = 0.5

var hand_mesh: MeshInstance3D
var hand_skeleton: Skeleton3D
var collision_area: Area3D
var ray_cast: RayCast3D
var grab_area: Area3D

var finger_bones: Dictionary = {}
var finger_bend_amounts: Dictionary = {}
var current_gesture: GestureType = GestureType.OPEN_PALM
var grabbed_object: RigidBody3D
var is_grabbing: bool = false

var gesture_detection_timer: float = 0.0
var gesture_detection_delay: float = 0.1

@onready var hand_model: Node3D = $HandModel
@onready var finger_tip_markers: Array[Marker3D] = []

func _ready():
	setup_hand_components()
	setup_gesture_detection()
	connect_signals()

func setup_hand_components():
	setup_hand_mesh()
	setup_collision_detection()
	setup_ray_casting()
	setup_grab_detection()

func setup_hand_mesh():
	if hand_model:
		hand_mesh = hand_model.get_node_or_null("HandMesh")
		hand_skeleton = hand_model.get_node_or_null("HandSkeleton")
		
		if hand_skeleton:
			setup_finger_bones()

func setup_finger_bones():
	var bone_names = {
		FingerType.THUMB: ["thumb_metacarpal", "thumb_proximal", "thumb_distal"],
		FingerType.INDEX: ["index_metacarpal", "index_proximal", "index_intermediate", "index_distal"],
		FingerType.MIDDLE: ["middle_metacarpal", "middle_proximal", "middle_intermediate", "middle_distal"],
		FingerType.RING: ["ring_metacarpal", "ring_proximal", "ring_intermediate", "ring_distal"],
		FingerType.PINKY: ["pinky_metacarpal", "pinky_proximal", "pinky_intermediate", "pinky_distal"]
	}
	
	for finger_type in bone_names:
		finger_bones[finger_type] = []
		finger_bend_amounts[finger_type] = 0.0
		
		for bone_name in bone_names[finger_type]:
			var bone_idx = hand_skeleton.find_bone(bone_name)
			if bone_idx != -1:
				finger_bones[finger_type].append(bone_idx)

func setup_collision_detection():
	collision_area = Area3D.new()
	collision_area.name = "HandCollisionArea"
	add_child(collision_area)
	
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = 0.05
	collision_shape.shape = sphere_shape
	collision_area.add_child(collision_shape)
	
	collision_area.body_entered.connect(_on_hand_collision_started)
	collision_area.body_exited.connect(_on_hand_collision_ended)

func setup_ray_casting():
	ray_cast = RayCast3D.new()
	ray_cast.name = "HandRayCast"
	ray_cast.target_position = Vector3(0, 0, -pointer_distance)
	ray_cast.enabled = true
	add_child(ray_cast)

func setup_grab_detection():
	grab_area = Area3D.new()
	grab_area.name = "GrabArea"
	add_child(grab_area)
	
	var grab_shape = CollisionShape3D.new()
	var grab_sphere = SphereShape3D.new()
	grab_sphere.radius = grab_distance
	grab_shape.shape = grab_sphere
	grab_area.add_child(grab_shape)

func setup_gesture_detection():
	for finger in FingerType.values():
		finger_bend_amounts[finger] = 0.0

func connect_signals():
	button_pressed.connect(_on_button_pressed)
	button_released.connect(_on_button_released)
	input_float_changed.connect(_on_input_float_changed)

func _physics_process(delta):
	if enable_hand_tracking:
		update_hand_tracking(delta)
	
	if enable_finger_tracking:
		update_finger_tracking()
	
	if enable_gesture_recognition:
		update_gesture_recognition(delta)
	
	update_grab_system()
	update_pointer_system()

func update_hand_tracking(delta):
	if not has_method("get_hand_joint_transform"):
		return
	
	update_hand_position_and_rotation()

func update_hand_position_and_rotation():
	if has_method("get_hand_joint_transform"):
		var wrist_transform = get_hand_joint_transform(0)
		if wrist_transform != Transform3D.IDENTITY:
			transform = wrist_transform

func update_finger_tracking():
	if not hand_skeleton or not enable_finger_tracking:
		return
	
	for finger_type in finger_bones:
		var bend_amount = calculate_finger_bend(finger_type)
		if abs(bend_amount - finger_bend_amounts[finger_type]) > 0.05:
			finger_bend_amounts[finger_type] = bend_amount
			emit_signal("finger_bend_changed", finger_type, bend_amount)

func calculate_finger_bend(finger_type: FingerType) -> float:
	if not finger_bones.has(finger_type) or finger_bones[finger_type].is_empty():
		return 0.0
	
	var total_bend = 0.0
	var bone_count = 0
	
	for bone_idx in finger_bones[finger_type]:
		var bone_pose = hand_skeleton.get_bone_pose_rotation(bone_idx)
		var bend_angle = abs(bone_pose.get_euler().x)
		total_bend += bend_angle
		bone_count += 1
	
	return total_bend / bone_count if bone_count > 0 else 0.0

func update_gesture_recognition(delta):
	gesture_detection_timer += delta
	
	if gesture_detection_timer >= gesture_detection_delay:
		var detected_gesture = detect_current_gesture()
		
		if detected_gesture != current_gesture:
			current_gesture = detected_gesture
			emit_signal("hand_gesture_detected", get_gesture_name(detected_gesture))
		
		gesture_detection_timer = 0.0

func detect_current_gesture() -> GestureType:
	var thumb_bend = finger_bend_amounts.get(FingerType.THUMB, 0.0)
	var index_bend = finger_bend_amounts.get(FingerType.INDEX, 0.0)
	var middle_bend = finger_bend_amounts.get(FingerType.MIDDLE, 0.0)
	var ring_bend = finger_bend_amounts.get(FingerType.RING, 0.0)
	var pinky_bend = finger_bend_amounts.get(FingerType.PINKY, 0.0)
	
	var all_fingers_bent = index_bend > 0.8 and middle_bend > 0.8 and ring_bend > 0.8 and pinky_bend > 0.8
	var only_index_extended = index_bend < 0.3 and middle_bend > 0.8 and ring_bend > 0.8 and pinky_bend > 0.8
	var peace_sign = index_bend < 0.3 and middle_bend < 0.3 and ring_bend > 0.8 and pinky_bend > 0.8
	var thumbs_up = thumb_bend < 0.3 and index_bend > 0.8 and middle_bend > 0.8 and ring_bend > 0.8 and pinky_bend > 0.8
	var all_fingers_extended = index_bend < 0.3 and middle_bend < 0.3 and ring_bend < 0.3 and pinky_bend < 0.3
	var pinch_gesture = thumb_bend < 0.4 and index_bend < 0.4 and middle_bend > 0.6 and ring_bend > 0.6 and pinky_bend > 0.6
	
	if all_fingers_bent:
		return GestureType.FIST
	elif only_index_extended:
		return GestureType.POINT
	elif peace_sign:
		return GestureType.PEACE
	elif thumbs_up:
		return GestureType.THUMBS_UP
	elif pinch_gesture:
		return GestureType.PINCH
	elif all_fingers_extended:
		return GestureType.OPEN_PALM
	else:
		return GestureType.GRAB

func get_gesture_name(gesture: GestureType) -> String:
	match gesture:
		GestureType.FIST:
			return "fist"
		GestureType.POINT:
			return "point"
		GestureType.PEACE:
			return "peace"
		GestureType.THUMBS_UP:
			return "thumbs_up"
		GestureType.OPEN_PALM:
			return "open_palm"
		GestureType.PINCH:
			return "pinch"
		GestureType.GRAB:
			return "grab"
		_:
			return "unknown"

func update_grab_system():
	if current_gesture == GestureType.GRAB or current_gesture == GestureType.FIST:
		if not is_grabbing:
			attempt_grab()
	else:
		if is_grabbing:
			release_grab()

func attempt_grab():
	var grabbable_objects = grab_area.get_overlapping_bodies()
	
	for body in grabbable_objects:
		if body.is_in_group("grabbable") and body is RigidBody3D:
			grab_object(body)
			break

func grab_object(obj: RigidBody3D):
	if grabbed_object:
		release_grab()
	
	grabbed_object = obj
	is_grabbing = true
	
	if grabbed_object.has_method("on_grab"):
		grabbed_object.on_grab(self)
	
	provide_haptic_feedback(haptic_feedback_strength, 0.1)
	emit_signal("grab_attempted", grabbed_object)

func release_grab():
	if grabbed_object:
		if grabbed_object.has_method("on_release"):
			grabbed_object.on_release(self)
		
		emit_signal("grab_released", grabbed_object)
		grabbed_object = null
	
	is_grabbing = false

func update_pointer_system():
	if current_gesture == GestureType.POINT:
		ray_cast.enabled = true
		
		if ray_cast.is_colliding():
			var collision_point = ray_cast.get_collision_point()
			var collision_object = ray_cast.get_collider()
			
			if collision_object and collision_object.has_method("on_pointed_at"):
				collision_object.on_pointed_at(collision_point, self)
	else:
		ray_cast.enabled = false

func provide_haptic_feedback(strength: float, duration: float):
	if has_method("trigger_haptic_pulse"):
		trigger_haptic_pulse("haptic", 0, duration, strength, 0.0)

func get_finger_tip_position(finger: FingerType) -> Vector3:
	if finger_tip_markers.size() > finger:
		return finger_tip_markers[finger].global_position
	return global_position

func get_palm_center() -> Vector3:
	return global_position

func get_palm_normal() -> Vector3:
	return -global_transform.basis.z

func is_finger_extended(finger: FingerType) -> bool:
	return finger_bend_amounts.get(finger, 0.0) < 0.3

func is_hand_open() -> bool:
	return current_gesture == GestureType.OPEN_PALM

func is_hand_closed() -> bool:
	return current_gesture == GestureType.FIST

func get_hand_velocity() -> Vector3:
	if has_method("get_velocity"):
		return get_velocity()
	return Vector3.ZERO

func get_hand_angular_velocity() -> Vector3:
	if has_method("get_angular_velocity"):
		return get_angular_velocity()
	return Vector3.ZERO

func set_hand_visibility(visible: bool):
	if hand_mesh:
		hand_mesh.visible = visible

func animate_finger(finger: FingerType, target_bend: float, duration: float):
	if not finger_bones.has(finger):
		return
	
	var tween = create_tween()
	var current_bend = finger_bend_amounts[finger]
	
	tween.tween_method(
		_animate_finger_bones.bind(finger),
		current_bend,
		target_bend,
		duration
	)

func _animate_finger_bones(finger: FingerType, bend_amount: float):
	if not hand_skeleton or not finger_bones.has(finger):
		return
	
	for bone_idx in finger_bones[finger]:
		var rotation = Quaternion.from_euler(Vector3(bend_amount, 0, 0))
		hand_skeleton.set_bone_pose_rotation(bone_idx, rotation)

func calibrate_hand():
	for finger in FingerType.values():
		finger_bend_amounts[finger] = 0.0
	
	current_gesture = GestureType.OPEN_PALM

func _on_button_pressed(name: String):
	match name:
		"grip":
			attempt_grab()
		"trigger":
			if current_gesture == GestureType.POINT:
				trigger_pointer_action()

func _on_button_released(name: String):
	match name:
		"grip":
			release_grab()

func _on_input_float_changed(name: String, value: float):
	if name == "grip" and value > 0.8:
		attempt_grab()
	elif name == "grip" and value < 0.2:
		release_grab()

func trigger_pointer_action():
	if ray_cast.is_colliding():
		var collision_object = ray_cast.get_collider()
		if collision_object and collision_object.has_method("on_interact"):
			collision_object.on_interact(self)

func _on_hand_collision_started(body: Node3D):
	emit_signal("hand_collision_started", body)

func _on_hand_collision_ended(body: Node3D):
	emit_signal("hand_collision_ended", body)

func save_hand_calibration() -> Dictionary:
	return {
		"finger_bend_amounts": finger_bend_amounts,
		"grab_distance": grab_distance,
		"pointer_distance": pointer_distance
	}

func load_hand_calibration(data: Dictionary):
	finger_bend_amounts = data.get("finger_bend_amounts", {})
	grab_distance = data.get("grab_distance", 0.1)
	pointer_distance = data.get("pointer_distance", 2.0)
	
	if grab_area and grab_area.get_child(0) and grab_area.get_child(0).shape:
		grab_area.get_child(0).shape.radius = grab_distance
	
	if ray_cast:
		ray_cast.target_position = Vector3(0, 0, -pointer_distance)