extends Spatial

export var body_height: float = 1.8
export var shoulder_width: float = 0.45
export var arm_length: float = 0.7
export var enable_full_body_ik: bool = true
export var foot_step_height: float = 0.1
export var foot_step_distance: float = 0.3
export var crouching_enabled: bool = true
export var crouch_height_threshold: float = 1.2
export var physical_body_enabled: bool = true
export var collision_capsule_radius: float = 0.3

onready var head = $Head
onready var torso = $Torso
onready var left_shoulder = $Torso/LeftShoulder
onready var right_shoulder = $Torso/RightShoulder
onready var left_hand_ik = $LeftHandIK
onready var right_hand_ik = $RightHandIK
onready var left_foot = $LeftFoot
onready var right_foot = $RightFoot
onready var hips = $Hips
onready var physical_body = $PhysicalBody

var player: ARVROrigin
var camera: ARVRCamera
var left_controller: ARVRController
var right_controller: ARVRController

var is_crouching: bool = false
var current_body_height: float
var left_foot_position: Vector3
var right_foot_position: Vector3
var last_foot_movement: String = "left"
var step_accumulator: float = 0.0
var body_velocity: Vector3

signal body_crouched
signal body_stood_up
signal foot_step(foot_name, position)

func _ready():
	player = get_parent()
	camera = player.get_node("ARVRCamera")
	left_controller = player.get_node("LeftController")
	right_controller = player.get_node("RightController")
	
	_setup_body_parts()
	_setup_physical_body()
	
	current_body_height = body_height

func _setup_body_parts():
	if not head:
		head = MeshInstance.new()
		head.name = "Head"
		add_child(head)
		var sphere = SphereMesh.new()
		sphere.radius = 0.1
		head.mesh = sphere
	
	if not torso:
		torso = MeshInstance.new()
		torso.name = "Torso"
		add_child(torso)
		var box = BoxMesh.new()
		box.size = Vector3(shoulder_width, 0.5, 0.2)
		torso.mesh = box
	
	if not hips:
		hips = MeshInstance.new()
		hips.name = "Hips"
		add_child(hips)
		var box = BoxMesh.new()
		box.size = Vector3(shoulder_width * 0.8, 0.2, 0.15)
		hips.mesh = box
	
	for foot_name in ["LeftFoot", "RightFoot"]:
		if not has_node(foot_name):
			var foot = MeshInstance.new()
			foot.name = foot_name
			add_child(foot)
			var box = BoxMesh.new()
			box.size = Vector3(0.1, 0.05, 0.25)
			foot.mesh = box

func _setup_physical_body():
	if not physical_body_enabled:
		return
	
	if not physical_body:
		physical_body = KinematicBody.new()
		physical_body.name = "PhysicalBody"
		add_child(physical_body)
		
		var collision = CollisionShape.new()
		var capsule = CapsuleShape.new()
		capsule.radius = collision_capsule_radius
		capsule.height = body_height - collision_capsule_radius * 2
		collision.shape = capsule
		physical_body.add_child(collision)

func _physics_process(delta):
	if not camera:
		return
	
	_update_head_position()
	_update_torso_position()
	_update_crouch_state()
	
	if enable_full_body_ik:
		_update_arm_ik()
		_update_leg_ik(delta)
	
	if physical_body_enabled and physical_body:
		_update_physical_body(delta)

func _update_head_position():
	if head and camera:
		head.global_transform.origin = camera.global_transform.origin

func _update_torso_position():
	if not torso or not camera:
		return
	
	var head_pos = camera.global_transform.origin
	var torso_height = head_pos.y - 0.3
	
	if is_crouching:
		torso_height = head_pos.y - 0.2
	
	torso.global_transform.origin = Vector3(head_pos.x, torso_height, head_pos.z)
	
	var look_direction = -camera.global_transform.basis.z
	look_direction.y = 0
	if look_direction.length() > 0.1:
		torso.look_at(torso.global_transform.origin + look_direction, Vector3.UP)
	
	if hips:
		hips.global_transform.origin = torso.global_transform.origin - Vector3(0, 0.4, 0)
		hips.global_transform.basis = torso.global_transform.basis

func _update_crouch_state():
	if not crouching_enabled or not camera:
		return
	
	var head_height = camera.global_transform.origin.y
	var was_crouching = is_crouching
	
	is_crouching = head_height < crouch_height_threshold
	
	if is_crouching and not was_crouching:
		emit_signal("body_crouched")
		_adjust_collision_for_crouch(true)
	elif not is_crouching and was_crouching:
		emit_signal("body_stood_up")
		_adjust_collision_for_crouch(false)

func _adjust_collision_for_crouch(crouching: bool):
	if not physical_body or not physical_body.has_node("CollisionShape"):
		return
	
	var collision = physical_body.get_node("CollisionShape")
	if collision.shape is CapsuleShape:
		var capsule = collision.shape as CapsuleShape
		if crouching:
			capsule.height = (crouch_height_threshold - collision_capsule_radius * 2) * 0.8
		else:
			capsule.height = body_height - collision_capsule_radius * 2

func _update_arm_ik():
	if left_controller and left_shoulder:
		var target_pos = left_controller.global_transform.origin
		var shoulder_pos = left_shoulder.global_transform.origin
		
		var distance = shoulder_pos.distance_to(target_pos)
		if distance > arm_length:
			var direction = (target_pos - shoulder_pos).normalized()
			target_pos = shoulder_pos + direction * arm_length
		
		if left_hand_ik:
			left_hand_ik.global_transform.origin = target_pos
			left_hand_ik.global_transform.basis = left_controller.global_transform.basis
	
	if right_controller and right_shoulder:
		var target_pos = right_controller.global_transform.origin
		var shoulder_pos = right_shoulder.global_transform.origin
		
		var distance = shoulder_pos.distance_to(target_pos)
		if distance > arm_length:
			var direction = (target_pos - shoulder_pos).normalized()
			target_pos = shoulder_pos + direction * arm_length
		
		if right_hand_ik:
			right_hand_ik.global_transform.origin = target_pos
			right_hand_ik.global_transform.basis = right_controller.global_transform.basis

func _update_leg_ik(delta):
	if not player:
		return
	
	var player_velocity = _calculate_player_velocity(delta)
	var movement_speed = player_velocity.length()
	
	step_accumulator += movement_speed * delta
	
	if step_accumulator > foot_step_distance:
		step_accumulator = 0.0
		_perform_foot_step()
	
	_position_feet()

func _calculate_player_velocity(delta) -> Vector3:
	if not player:
		return Vector3.ZERO
	
	var current_pos = player.global_transform.origin
	body_velocity = (current_pos - left_foot_position) / delta if delta > 0 else Vector3.ZERO
	body_velocity.y = 0
	
	return body_velocity

func _perform_foot_step():
	var base_position = player.global_transform.origin
	var movement_direction = body_velocity.normalized()
	
	if movement_direction.length() < 0.1:
		movement_direction = -player.global_transform.basis.z
	
	if last_foot_movement == "left":
		right_foot_position = base_position + movement_direction * foot_step_distance * 0.5
		right_foot_position += player.global_transform.basis.x * shoulder_width * 0.3
		last_foot_movement = "right"
		emit_signal("foot_step", "right", right_foot_position)
	else:
		left_foot_position = base_position + movement_direction * foot_step_distance * 0.5
		left_foot_position -= player.global_transform.basis.x * shoulder_width * 0.3
		last_foot_movement = "left"
		emit_signal("foot_step", "left", left_foot_position)

func _position_feet():
	if left_foot:
		var target_pos = left_foot_position
		target_pos.y = _get_floor_height(target_pos) + foot_step_height
		left_foot.global_transform.origin = left_foot.global_transform.origin.linear_interpolate(target_pos, 0.2)
	
	if right_foot:
		var target_pos = right_foot_position
		target_pos.y = _get_floor_height(target_pos) + foot_step_height
		right_foot.global_transform.origin = right_foot.global_transform.origin.linear_interpolate(target_pos, 0.2)

func _get_floor_height(position: Vector3) -> float:
	var space_state = get_world().direct_space_state
	var from = position + Vector3(0, 1, 0)
	var to = position - Vector3(0, 2, 0)
	
	var result = space_state.intersect_ray(from, to)
	if result:
		return result.position.y
	
	return 0.0

func _update_physical_body(delta):
	if not physical_body or not camera:
		return
	
	var target_position = player.global_transform.origin
	target_position.y = camera.global_transform.origin.y - current_body_height * 0.5
	
	physical_body.global_transform.origin = target_position
	
	if body_velocity.length() > 0.1:
		physical_body.move_and_slide(body_velocity, Vector3.UP)

func set_body_visible(visible: bool):
	for child in get_children():
		if child is MeshInstance:
			child.visible = visible

func get_body_height() -> float:
	if camera:
		return camera.global_transform.origin.y
	return current_body_height

func get_estimated_arm_positions() -> Dictionary:
	return {
		"left": left_hand_ik.global_transform.origin if left_hand_ik else Vector3.ZERO,
		"right": right_hand_ik.global_transform.origin if right_hand_ik else Vector3.ZERO
	}

func calibrate_body_proportions():
	if camera:
		current_body_height = camera.global_transform.origin.y
		
		if left_controller and right_controller:
			var controller_distance = left_controller.global_transform.origin.distance_to(
				right_controller.global_transform.origin
			)
			shoulder_width = controller_distance * 0.8