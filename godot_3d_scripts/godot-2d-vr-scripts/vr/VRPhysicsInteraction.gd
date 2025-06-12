extends Node3D

class_name VRPhysicsInteraction

@export var interaction_force: float = 500.0
@export var max_interaction_distance: float = 2.0
@export var physics_layers: int = 1
@export var enable_haptic_feedback: bool = true

var controller: XRController3D
var interaction_ray: RayCast3D
var physics_body: RigidBody3D = null
var joint: Generic6DOFJoint3D = null
var interaction_point: Vector3
var target_position: Vector3
var is_interacting: bool = false

@onready var interaction_area: Area3D = $InteractionArea
@onready var force_indicator: MeshInstance3D = $ForceIndicator

signal physics_interaction_started(body: RigidBody3D)
signal physics_interaction_ended(body: RigidBody3D)
signal object_thrown(body: RigidBody3D, velocity: Vector3)

func _ready():
	controller = get_parent() as XRController3D
	if not controller:
		print("VRPhysicsInteraction must be child of XRController3D")
		return
	
	setup_interaction_ray()
	setup_interaction_area()
	setup_force_indicator()
	
	controller.button_pressed.connect(_on_controller_button_pressed)
	controller.button_released.connect(_on_controller_button_released)

func _physics_process(delta):
	if is_interacting and physics_body:
		update_physics_interaction(delta)
	
	update_interaction_preview()

func setup_interaction_ray():
	interaction_ray = RayCast3D.new()
	add_child(interaction_ray)
	interaction_ray.target_position = Vector3(0, 0, -max_interaction_distance)
	interaction_ray.collision_mask = physics_layers
	interaction_ray.enabled = true

func setup_interaction_area():
	if not interaction_area:
		interaction_area = Area3D.new()
		add_child(interaction_area)
	
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = max_interaction_distance
	collision_shape.shape = sphere_shape
	interaction_area.add_child(collision_shape)
	
	interaction_area.collision_layer = 0
	interaction_area.collision_mask = physics_layers

func setup_force_indicator():
	if not force_indicator:
		force_indicator = MeshInstance3D.new()
		add_child(force_indicator)
	
	var arrow_mesh = BoxMesh.new()
	arrow_mesh.size = Vector3(0.02, 0.02, 0.2)
	force_indicator.mesh = arrow_mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.YELLOW
	material.emission_enabled = true
	material.emission = Color.YELLOW * 0.5
	force_indicator.material_override = material
	
	force_indicator.visible = false

func start_physics_interaction():
	if is_interacting or not interaction_ray.is_colliding():
		return
	
	var collider = interaction_ray.get_collider()
	if not collider is RigidBody3D:
		return
	
	physics_body = collider as RigidBody3D
	interaction_point = interaction_ray.get_collision_point()
	target_position = interaction_point
	is_interacting = true
	
	create_physics_joint()
	
	if enable_haptic_feedback:
		trigger_haptic_feedback(0.3, 0.1)
	
	physics_interaction_started.emit(physics_body)

func end_physics_interaction():
	if not is_interacting:
		return
	
	var released_body = physics_body
	var controller_velocity = get_controller_velocity()
	
	if joint:
		joint.queue_free()
		joint = null
	
	if physics_body and controller_velocity.length() > 2.0:
		physics_body.linear_velocity = controller_velocity * 2.0
		object_thrown.emit(physics_body, controller_velocity)
	
	is_interacting = false
	physics_body = null
	force_indicator.visible = false
	
	if enable_haptic_feedback:
		trigger_haptic_feedback(0.2, 0.05)
	
	physics_interaction_ended.emit(released_body)

func create_physics_joint():
	if not physics_body:
		return
	
	joint = Generic6DOFJoint3D.new()
	get_tree().current_scene.add_child(joint)
	
	var static_body = StaticBody3D.new()
	get_tree().current_scene.add_child(static_body)
	static_body.global_position = global_position
	
	joint.node_a = physics_body.get_path()
	joint.node_b = static_body.get_path()
	
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_ENABLED, true)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_ENABLED, true)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_ENABLED, true)
	
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS, interaction_force)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS, interaction_force)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS, interaction_force)
	
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_DAMPING, 50)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_DAMPING, 50)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_DAMPING, 50)

func update_physics_interaction(delta):
	if not physics_body or not joint:
		return
	
	target_position = global_position
	
	var static_body = get_node(joint.node_b)
	if static_body:
		static_body.global_position = target_position
	
	var distance = physics_body.global_position.distance_to(target_position)
	var force_strength = min(distance / max_interaction_distance, 1.0)
	
	update_force_indicator(force_strength)
	
	if enable_haptic_feedback and force_strength > 0.5:
		trigger_haptic_feedback(force_strength * 0.1, 0.02)

func update_force_indicator(strength: float):
	if not physics_body:
		force_indicator.visible = false
		return
	
	force_indicator.visible = true
	force_indicator.global_position = physics_body.global_position
	force_indicator.look_at(target_position, Vector3.UP)
	
	var scale_factor = strength * 2.0
	force_indicator.scale = Vector3(1, 1, scale_factor)
	
	var material = force_indicator.material_override as StandardMaterial3D
	if material:
		var color_intensity = strength
		material.emission = Color.YELLOW * color_intensity

func update_interaction_preview():
	if is_interacting:
		return
	
	if interaction_ray.is_colliding():
		var collider = interaction_ray.get_collider()
		if collider is RigidBody3D:
			highlight_interactable(collider, true)
		else:
			clear_highlights()
	else:
		clear_highlights()

func highlight_interactable(body: Node3D, highlight: bool):
	if body.has_method("set_highlight"):
		body.set_highlight(highlight)

func clear_highlights():
	var bodies = interaction_area.get_overlapping_bodies()
	for body in bodies:
		if body.has_method("set_highlight"):
			body.set_highlight(false)

func apply_impulse_to_physics_body(impulse: Vector3):
	if physics_body:
		physics_body.apply_central_impulse(impulse)

func get_controller_velocity() -> Vector3:
	if controller and controller.has_method("get_velocity"):
		return controller.get_velocity()
	return Vector3.ZERO

func trigger_haptic_feedback(amplitude: float, duration: float):
	if controller and controller.has_method("trigger_haptic_pulse"):
		controller.trigger_haptic_pulse("haptic", 0, duration, amplitude, 0.0)

func _on_controller_button_pressed(name: String):
	match name:
		"trigger":
			start_physics_interaction()
		"grip":
			if is_interacting:
				increase_interaction_force()

func _on_controller_button_released(name: String):
	match name:
		"trigger":
			end_physics_interaction()

func increase_interaction_force():
	interaction_force = min(interaction_force * 1.5, 2000.0)
	
	if joint:
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS, interaction_force)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS, interaction_force)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS, interaction_force)

func set_interaction_layers(layers: int):
	physics_layers = layers
	if interaction_ray:
		interaction_ray.collision_mask = layers
	if interaction_area:
		interaction_area.collision_mask = layers

func get_interacting_body() -> RigidBody3D:
	return physics_body

func is_physics_interacting() -> bool:
	return is_interacting

func force_release():
	if is_interacting:
		end_physics_interaction()