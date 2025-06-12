extends Spatial

# Ragdoll configuration
export var bone_count = 15
export var joint_stiffness = 10.0
export var joint_damping = 5.0
export var muscle_strength = 100.0
export var balance_strength = 50.0

# Body parts
var body_parts = {}
var joints = {}
var muscles = {}
var bone_hierarchy = {}

# State
enum RagdollState {
	ACTIVE,      # Full physics control
	ANIMATED,    # Following animation
	BLEND,       # Blending between physics and animation
	GETTING_UP,  # Recovery animation
	DEAD         # Limp ragdoll
}

var current_state = RagdollState.ANIMATED
var blend_weight = 0.0
var is_balanced = true
var recovery_timer = 0.0

# Balance and posture
var center_of_mass = Vector3.ZERO
var support_points = []
var balance_point = Vector3.ZERO
var desired_up_direction = Vector3.UP
var current_pose = "standing"

# Forces and impacts
var external_forces = []
var impact_points = []
var accumulated_damage = 0.0

# Animation targets
var animation_targets = {}
var animation_player = null
var skeleton = null

# Active ragdoll parameters
export var head_look_strength = 5.0
export var spine_flexibility = 0.3
export var limb_strength_multiplier = 1.0
export var recovery_speed = 2.0

# Muscle groups
var muscle_groups = {
	"core": ["spine", "pelvis", "chest"],
	"legs": ["thigh_l", "thigh_r", "shin_l", "shin_r"],
	"arms": ["upper_arm_l", "upper_arm_r", "forearm_l", "forearm_r"],
	"extremities": ["hand_l", "hand_r", "foot_l", "foot_r"]
}

# IK targets
var ik_targets = {
	"left_hand": null,
	"right_hand": null,
	"left_foot": null,
	"right_foot": null
}

signal ragdoll_activated()
signal ragdoll_deactivated()
signal impact_received(force, point)
signal fell_down()
signal got_up()
signal pose_changed(new_pose)

func _ready():
	_create_ragdoll_structure()
	_setup_muscles()
	_initialize_balance_system()
	set_physics_process(true)

func _create_ragdoll_structure():
	# Create body parts hierarchy
	var part_configs = {
		"pelvis": {"mass": 15.0, "shape": "box", "size": Vector3(0.4, 0.2, 0.3)},
		"spine": {"mass": 10.0, "shape": "box", "size": Vector3(0.3, 0.3, 0.2), "parent": "pelvis"},
		"chest": {"mass": 12.0, "shape": "box", "size": Vector3(0.5, 0.4, 0.3), "parent": "spine"},
		"head": {"mass": 5.0, "shape": "sphere", "radius": 0.15, "parent": "chest"},
		
		"upper_arm_l": {"mass": 3.0, "shape": "capsule", "height": 0.3, "radius": 0.05, "parent": "chest"},
		"forearm_l": {"mass": 2.0, "shape": "capsule", "height": 0.25, "radius": 0.04, "parent": "upper_arm_l"},
		"hand_l": {"mass": 0.5, "shape": "box", "size": Vector3(0.08, 0.15, 0.03), "parent": "forearm_l"},
		
		"upper_arm_r": {"mass": 3.0, "shape": "capsule", "height": 0.3, "radius": 0.05, "parent": "chest"},
		"forearm_r": {"mass": 2.0, "shape": "capsule", "height": 0.25, "radius": 0.04, "parent": "upper_arm_r"},
		"hand_r": {"mass": 0.5, "shape": "box", "size": Vector3(0.08, 0.15, 0.03), "parent": "forearm_r"},
		
		"thigh_l": {"mass": 5.0, "shape": "capsule", "height": 0.4, "radius": 0.08, "parent": "pelvis"},
		"shin_l": {"mass": 3.0, "shape": "capsule", "height": 0.35, "radius": 0.06, "parent": "thigh_l"},
		"foot_l": {"mass": 1.0, "shape": "box", "size": Vector3(0.1, 0.05, 0.2), "parent": "shin_l"},
		
		"thigh_r": {"mass": 5.0, "shape": "capsule", "height": 0.4, "radius": 0.08, "parent": "pelvis"},
		"shin_r": {"mass": 3.0, "shape": "capsule", "height": 0.35, "radius": 0.06, "parent": "thigh_r"},
		"foot_r": {"mass": 1.0, "shape": "box", "size": Vector3(0.1, 0.05, 0.2), "parent": "shin_r"}
	}
	
	# Create rigid bodies for each part
	for part_name in part_configs:
		var config = part_configs[part_name]
		var body = RigidBody.new()
		body.name = part_name
		body.mass = config.mass
		
		# Create collision shape
		var shape = CollisionShape.new()
		match config.shape:
			"box":
				shape.shape = BoxShape.new()
				shape.shape.extents = config.size / 2
			"sphere":
				shape.shape = SphereShape.new()
				shape.shape.radius = config.radius
			"capsule":
				shape.shape = CapsuleShape.new()
				shape.shape.height = config.height
				shape.shape.radius = config.radius
		
		body.add_child(shape)
		add_child(body)
		body_parts[part_name] = body
		
		# Set initial position based on typical humanoid structure
		_position_body_part(part_name, body)

func _position_body_part(part_name: String, body: RigidBody):
	# Set initial positions for a T-pose
	match part_name:
		"pelvis":
			body.translation = Vector3(0, 1, 0)
		"spine":
			body.translation = Vector3(0, 1.3, 0)
		"chest":
			body.translation = Vector3(0, 1.6, 0)
		"head":
			body.translation = Vector3(0, 1.9, 0)
		"upper_arm_l":
			body.translation = Vector3(-0.3, 1.6, 0)
			body.rotation.z = deg2rad(-90)
		"forearm_l":
			body.translation = Vector3(-0.6, 1.6, 0)
			body.rotation.z = deg2rad(-90)
		"hand_l":
			body.translation = Vector3(-0.85, 1.6, 0)
		"upper_arm_r":
			body.translation = Vector3(0.3, 1.6, 0)
			body.rotation.z = deg2rad(90)
		"forearm_r":
			body.translation = Vector3(0.6, 1.6, 0)
			body.rotation.z = deg2rad(90)
		"hand_r":
			body.translation = Vector3(0.85, 1.6, 0)
		"thigh_l":
			body.translation = Vector3(-0.1, 0.6, 0)
		"shin_l":
			body.translation = Vector3(-0.1, 0.2, 0)
		"foot_l":
			body.translation = Vector3(-0.1, 0, 0)
		"thigh_r":
			body.translation = Vector3(0.1, 0.6, 0)
		"shin_r":
			body.translation = Vector3(0.1, 0.2, 0)
		"foot_r":
			body.translation = Vector3(0.1, 0, 0)

func _setup_muscles():
	# Create joints between body parts
	var joint_configs = [
		{"parent": "pelvis", "child": "spine", "type": "ball"},
		{"parent": "spine", "child": "chest", "type": "ball"},
		{"parent": "chest", "child": "head", "type": "ball"},
		
		{"parent": "chest", "child": "upper_arm_l", "type": "ball"},
		{"parent": "upper_arm_l", "child": "forearm_l", "type": "hinge"},
		{"parent": "forearm_l", "child": "hand_l", "type": "ball"},
		
		{"parent": "chest", "child": "upper_arm_r", "type": "ball"},
		{"parent": "upper_arm_r", "child": "forearm_r", "type": "hinge"},
		{"parent": "forearm_r", "child": "hand_r", "type": "ball"},
		
		{"parent": "pelvis", "child": "thigh_l", "type": "ball"},
		{"parent": "thigh_l", "child": "shin_l", "type": "hinge"},
		{"parent": "shin_l", "child": "foot_l", "type": "ball"},
		
		{"parent": "pelvis", "child": "thigh_r", "type": "ball"},
		{"parent": "thigh_r", "child": "shin_r", "type": "hinge"},
		{"parent": "shin_r", "child": "foot_r", "type": "ball"}
	]
	
	for config in joint_configs:
		var joint = _create_joint(config.parent, config.child, config.type)
		joints[config.child] = joint
		
		# Create muscle controller
		var muscle = {
			"joint": joint,
			"parent": body_parts[config.parent],
			"child": body_parts[config.child],
			"target_rotation": Quat.IDENTITY,
			"strength": muscle_strength,
			"active": true
		}
		muscles[config.child] = muscle

func _create_joint(parent_name: String, child_name: String, type: String) -> Joint:
	var parent = body_parts[parent_name]
	var child = body_parts[child_name]
	
	var joint
	match type:
		"hinge":
			joint = HingeJoint.new()
			# Configure hinge limits
			joint.set_param(HingeJoint.PARAM_LIMIT_LOWER, deg2rad(-90))
			joint.set_param(HingeJoint.PARAM_LIMIT_UPPER, deg2rad(90))
		"ball":
			joint = Generic6DOFJoint.new()
			# Configure ball joint limits
			for axis in [Vector3.AXIS_X, Vector3.AXIS_Y, Vector3.AXIS_Z]:
				joint.set_param_x(Generic6DOFJoint.PARAM_ANGULAR_LOWER_LIMIT, deg2rad(-45))
				joint.set_param_x(Generic6DOFJoint.PARAM_ANGULAR_UPPER_LIMIT, deg2rad(45))
	
	joint.set_node_a(parent.get_path())
	joint.set_node_b(child.get_path())
	add_child(joint)
	
	return joint

func _initialize_balance_system():
	# Setup balance detection
	support_points = ["foot_l", "foot_r"]

func _physics_process(delta):
	_update_center_of_mass()
	_update_balance(delta)
	_apply_muscle_forces(delta)
	_process_external_forces(delta)
	_update_state_machine(delta)
	_handle_recovery(delta)

func _update_center_of_mass():
	var total_mass = 0.0
	center_of_mass = Vector3.ZERO
	
	for part_name in body_parts:
		var part = body_parts[part_name]
		var mass = part.mass
		center_of_mass += part.global_transform.origin * mass
		total_mass += mass
	
	center_of_mass /= total_mass

func _update_balance(delta):
	if current_state != RagdollState.ACTIVE:
		return
	
	# Calculate support polygon
	var support_polygon = []
	for point_name in support_points:
		if body_parts.has(point_name):
			var part = body_parts[point_name]
			# Check if touching ground
			var space_state = part.get_world().direct_space_state
			var result = space_state.intersect_ray(
				part.global_transform.origin,
				part.global_transform.origin + Vector3.DOWN * 0.1,
				[part]
			)
			
			if result:
				support_polygon.append(result.position)
	
	# Check if center of mass is within support polygon
	is_balanced = _point_in_polygon(center_of_mass, support_polygon)
	
	if not is_balanced and current_state == RagdollState.ACTIVE:
		_initiate_fall()

func _point_in_polygon(point: Vector3, polygon: Array) -> bool:
	if polygon.size() < 3:
		return false
	
	# Simple point-in-polygon test (2D projection)
	# This is simplified - real implementation would be more robust
	var center = Vector3.ZERO
	for p in polygon:
		center += p
	center /= polygon.size()
	
	var distance = Vector2(point.x - center.x, point.z - center.z).length()
	return distance < 0.3  # Within 30cm of center

func _apply_muscle_forces(delta):
	if current_state == RagdollState.DEAD:
		return
	
	for muscle_name in muscles:
		var muscle = muscles[muscle_name]
		if not muscle.active:
			continue
		
		var parent = muscle.parent
		var child = muscle.child
		
		# Calculate desired rotation based on state
		var target_rotation = Quat.IDENTITY
		
		match current_state:
			RagdollState.ANIMATED:
				# Follow animation targets
				if animation_targets.has(muscle_name):
					target_rotation = animation_targets[muscle_name]
			
			RagdollState.ACTIVE:
				# Active ragdoll - maintain pose
				target_rotation = _get_pose_rotation(muscle_name, current_pose)
			
			RagdollState.BLEND:
				# Blend between animation and physics
				if animation_targets.has(muscle_name):
					var anim_rot = animation_targets[muscle_name]
					var physics_rot = child.transform.basis.get_rotation_quat()
					target_rotation = anim_rot.slerp(physics_rot, blend_weight)
		
		# Apply torque to achieve target rotation
		var current_rotation = child.transform.basis.get_rotation_quat()
		var rotation_difference = target_rotation * current_rotation.inverse()
		var axis_angle = rotation_difference.get_axis() * rotation_difference.get_angle()
		
		# Apply PD controller
		var torque = axis_angle * muscle.strength * joint_stiffness
		torque -= child.angular_velocity * joint_damping
		
		child.add_torque(torque * delta)

func _get_pose_rotation(part_name: String, pose: String) -> Quat:
	# Return target rotation for specific pose
	# This would be configured per pose
	match pose:
		"standing":
			match part_name:
				"spine", "chest":
					return Quat(Vector3.RIGHT, deg2rad(-5))  # Slight forward lean
				"thigh_l", "thigh_r":
					return Quat.IDENTITY
				"shin_l", "shin_r":
					return Quat(Vector3.RIGHT, deg2rad(5))
		"crouching":
			match part_name:
				"spine", "chest":
					return Quat(Vector3.RIGHT, deg2rad(-30))
				"thigh_l", "thigh_r":
					return Quat(Vector3.RIGHT, deg2rad(-90))
				"shin_l", "shin_r":
					return Quat(Vector3.RIGHT, deg2rad(90))
	
	return Quat.IDENTITY

func _process_external_forces(delta):
	# Apply accumulated external forces
	var forces_to_remove = []
	
	for i in range(external_forces.size()):
		var force_data = external_forces[i]
		var part = force_data.part
		var force = force_data.force
		var duration = force_data.duration
		
		part.add_force(force, force_data.local_position)
		
		force_data.duration -= delta
		if force_data.duration <= 0:
			forces_to_remove.append(i)
	
	# Remove expired forces
	for i in forces_to_remove:
		external_forces.remove(i)

func _update_state_machine(delta):
	match current_state:
		RagdollState.ANIMATED:
			# Check for impacts that should trigger ragdoll
			if accumulated_damage > 50:
				activate_ragdoll()
		
		RagdollState.ACTIVE:
			# Check if we should start recovery
			if is_balanced and recovery_timer <= 0:
				recovery_timer = 1.0
		
		RagdollState.GETTING_UP:
			# Blend back to animation
			blend_weight = max(0, blend_weight - recovery_speed * delta)
			if blend_weight <= 0:
				deactivate_ragdoll()

func _handle_recovery(delta):
	if recovery_timer > 0:
		recovery_timer -= delta
		
		if recovery_timer <= 0 and current_state == RagdollState.ACTIVE:
			# Start getting up
			current_state = RagdollState.GETTING_UP
			emit_signal("got_up")
			
			# Choose recovery animation based on position
			var pelvis_forward = body_parts.pelvis.transform.basis.z
			if pelvis_forward.y < 0:
				current_pose = "prone_recovery"
			else:
				current_pose = "supine_recovery"

func _initiate_fall():
	emit_signal("fell_down")
	recovery_timer = 2.0  # Wait before trying to get up

# Public API

func activate_ragdoll(blend_time: float = 0.2):
	if current_state == RagdollState.ACTIVE:
		return
	
	current_state = RagdollState.BLEND
	blend_weight = 0.0
	
	# Enable physics on all parts
	for part_name in body_parts:
		var part = body_parts[part_name]
		part.mode = RigidBody.MODE_RIGID
	
	emit_signal("ragdoll_activated")
	
	# Transition to full ragdoll
	yield(get_tree().create_timer(blend_time), "timeout")
	current_state = RagdollState.ACTIVE

func deactivate_ragdoll():
	current_state = RagdollState.ANIMATED
	
	# Set bodies to kinematic
	for part_name in body_parts:
		var part = body_parts[part_name]
		part.mode = RigidBody.MODE_KINEMATIC
	
	emit_signal("ragdoll_deactivated")

func apply_impact(part_name: String, force: Vector3, local_position: Vector3 = Vector3.ZERO, damage: float = 0.0):
	if not body_parts.has(part_name):
		return
	
	external_forces.append({
		"part": body_parts[part_name],
		"force": force,
		"local_position": local_position,
		"duration": 0.1
	})
	
	accumulated_damage += damage
	emit_signal("impact_received", force, body_parts[part_name].global_transform.origin + local_position)
	
	# Auto-activate ragdoll on strong impacts
	if force.length() > 500 and current_state == RagdollState.ANIMATED:
		activate_ragdoll()

func set_muscle_strength(group: String, strength: float):
	if not muscle_groups.has(group):
		return
	
	for part_name in muscle_groups[group]:
		if muscles.has(part_name):
			muscles[part_name].strength = muscle_strength * strength

func set_pose(pose_name: String):
	current_pose = pose_name
	emit_signal("pose_changed", pose_name)

func kill():
	current_state = RagdollState.DEAD
	activate_ragdoll()
	
	# Disable all muscles
	for muscle in muscles.values():
		muscle.active = false

func set_ik_target(limb: String, target_position: Vector3):
	if ik_targets.has(limb):
		ik_targets[limb] = target_position

func get_bone_transform(part_name: String) -> Transform:
	if body_parts.has(part_name):
		return body_parts[part_name].global_transform
	return Transform.IDENTITY

func freeze_ragdoll():
	for part in body_parts.values():
		part.mode = RigidBody.MODE_STATIC

func unfreeze_ragdoll():
	for part in body_parts.values():
		part.mode = RigidBody.MODE_RIGID