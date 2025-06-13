extends Area3D

class_name PressurePlate

@export var activation_weight := 10.0
@export var plate_color_inactive := Color(0.5, 0.5, 0.5)
@export var plate_color_active := Color(0.2, 0.8, 0.2)
@export var activation_delay := 0.0
@export var deactivation_delay := 0.2
@export var plate_depression := 0.05
@export var animation_speed := 10.0
@export var linked_objects: Array[NodePath] = []
@export var require_all_plates := false
@export var group_name := ""

var is_activated := false
var current_weight := 0.0
var objects_on_plate := {}
var activation_timer := 0.0
var deactivation_timer := 0.0
var plate_mesh: MeshInstance3D
var original_y_position := 0.0
var linked_nodes := []

signal activated()
signal deactivated()
signal weight_changed(new_weight: float)

func _ready():
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	setup_plate_visuals()
	cache_linked_nodes()
	
	if group_name != "":
		add_to_group(group_name)

func setup_plate_visuals():
	plate_mesh = get_node_or_null("PlateMesh")
	if not plate_mesh:
		plate_mesh = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(2.0, 0.1, 2.0)
		plate_mesh.mesh = box_mesh
		add_child(plate_mesh)
	
	original_y_position = plate_mesh.position.y
	update_plate_visual()

func cache_linked_nodes():
	linked_nodes.clear()
	for path in linked_objects:
		var node = get_node_or_null(path)
		if node:
			linked_nodes.append(node)

func _on_body_entered(body: Node3D):
	if body.has_method("get_weight"):
		var weight = body.get_weight()
		objects_on_plate[body.get_instance_id()] = weight
	else:
		var rigid_body = body as RigidBody3D
		if rigid_body:
			objects_on_plate[body.get_instance_id()] = rigid_body.mass
		else:
			objects_on_plate[body.get_instance_id()] = 1.0
	
	calculate_total_weight()

func _on_body_exited(body: Node3D):
	objects_on_plate.erase(body.get_instance_id())
	calculate_total_weight()

func calculate_total_weight():
	current_weight = 0.0
	for weight in objects_on_plate.values():
		current_weight += weight
	
	emit_signal("weight_changed", current_weight)
	
	if current_weight >= activation_weight and not is_activated:
		activation_timer = activation_delay
		deactivation_timer = 0.0
	elif current_weight < activation_weight and is_activated:
		deactivation_timer = deactivation_delay
		activation_timer = 0.0

func _physics_process(delta):
	if activation_timer > 0:
		activation_timer -= delta
		if activation_timer <= 0:
			activate()
	
	if deactivation_timer > 0:
		deactivation_timer -= delta
		if deactivation_timer <= 0:
			deactivate()
	
	update_plate_depression(delta)

func activate():
	if is_activated:
		return
	
	is_activated = true
	emit_signal("activated")
	update_plate_visual()
	
	if require_all_plates and group_name != "":
		check_group_activation()
	else:
		trigger_linked_objects(true)

func deactivate():
	if not is_activated:
		return
	
	is_activated = false
	emit_signal("deactivated")
	update_plate_visual()
	
	if require_all_plates and group_name != "":
		check_group_activation()
	else:
		trigger_linked_objects(false)

func check_group_activation():
	if group_name == "":
		return
	
	var all_activated = true
	for plate in get_tree().get_nodes_in_group(group_name):
		if plate is PressurePlate and not plate.is_activated:
			all_activated = false
			break
	
	trigger_linked_objects(all_activated)

func trigger_linked_objects(activate: bool):
	for node in linked_nodes:
		if node.has_method("on_pressure_plate_activated") and activate:
			node.on_pressure_plate_activated()
		elif node.has_method("on_pressure_plate_deactivated") and not activate:
			node.on_pressure_plate_deactivated()
		elif node.has_method("set_activated"):
			node.set_activated(activate)
		elif node.has_method("toggle"):
			if activate:
				node.toggle()

func update_plate_visual():
	if not plate_mesh:
		return
	
	var material = plate_mesh.get_surface_override_material(0)
	if not material:
		material = StandardMaterial3D.new()
		plate_mesh.set_surface_override_material(0, material)
	
	material.albedo_color = plate_color_active if is_activated else plate_color_inactive
	material.emission_enabled = is_activated
	material.emission = plate_color_active if is_activated else Color.BLACK
	material.emission_energy = 0.5 if is_activated else 0.0

func update_plate_depression(delta):
	if not plate_mesh:
		return
	
	var target_y = original_y_position
	if current_weight > 0:
		var depression_amount = min(current_weight / activation_weight, 1.0) * plate_depression
		target_y = original_y_position - depression_amount
	
	plate_mesh.position.y = lerp(plate_mesh.position.y, target_y, animation_speed * delta)

func get_activation_progress() -> float:
	if activation_weight <= 0:
		return 1.0
	return min(current_weight / activation_weight, 1.0)

func force_activate():
	activate()

func force_deactivate():
	deactivate()

func reset():
	objects_on_plate.clear()
	current_weight = 0.0
	activation_timer = 0.0
	deactivation_timer = 0.0
	is_activated = false
	update_plate_visual()
	update_plate_depression(1.0)