extends Node3D

@export var teleport_range: float = 10.0
@export var arc_resolution: int = 30
@export var arc_height: float = 2.0
@export var valid_layer_mask: int = 1
@export var fade_duration: float = 0.2
@export var haptic_feedback: bool = true

var controller: XRController3D
var player: XROrigin3D
var teleport_ray: RayCast3D
var arc_points: PackedVector3Array
var is_teleporting: bool = false
var teleport_target: Vector3
var is_valid_target: bool = false

@onready var arc_mesh: MeshInstance3D = $ArcMesh
@onready var target_indicator: MeshInstance3D = $TargetIndicator
@onready var invalid_indicator: MeshInstance3D = $InvalidIndicator
@onready var fade_overlay: ColorRect = $FadeOverlay

var arc_material: StandardMaterial3D
var target_material: StandardMaterial3D
var invalid_material: StandardMaterial3D

signal teleport_started()
signal teleport_completed(target_position: Vector3)
signal teleport_cancelled()

func _ready():
	controller = get_parent() as XRController3D
	player = get_parent().get_parent() as XROrigin3D
	
	if not controller:
		print("VRTeleportation must be child of XRController3D")
		return
	
	setup_teleport_ray()
	setup_materials()
	setup_indicators()
	
	controller.button_pressed.connect(_on_controller_button_pressed)
	controller.button_released.connect(_on_controller_button_released)
	controller.input_vector2_changed.connect(_on_controller_vector2_changed)

func _physics_process(delta):
	if is_teleporting:
		update_teleport_arc()
		update_indicators()

func setup_teleport_ray():
	teleport_ray = RayCast3D.new()
	add_child(teleport_ray)
	teleport_ray.enabled = true
	teleport_ray.collision_mask = valid_layer_mask
	teleport_ray.target_position = Vector3(0, 0, -teleport_range)

func setup_materials():
	arc_material = StandardMaterial3D.new()
	arc_material.albedo_color = Color.CYAN
	arc_material.emission_enabled = true
	arc_material.emission = Color.CYAN
	arc_material.vertex_color_use_as_albedo = true
	arc_material.no_depth_test = true
	
	target_material = StandardMaterial3D.new()
	target_material.albedo_color = Color.GREEN
	target_material.emission_enabled = true
	target_material.emission = Color.GREEN
	target_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	target_material.albedo_color.a = 0.7
	
	invalid_material = StandardMaterial3D.new()
	invalid_material.albedo_color = Color.RED
	invalid_material.emission_enabled = true
	invalid_material.emission = Color.RED
	invalid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	invalid_material.albedo_color.a = 0.7

func setup_indicators():
	if not target_indicator:
		target_indicator = MeshInstance3D.new()
		add_child(target_indicator)
	
	var target_mesh = SphereMesh.new()
	target_mesh.radius = 0.5
	target_mesh.height = 1.0
	target_indicator.mesh = target_mesh
	target_indicator.material_override = target_material
	target_indicator.visible = false
	
	if not invalid_indicator:
		invalid_indicator = MeshInstance3D.new()
		add_child(invalid_indicator)
	
	var invalid_mesh = SphereMesh.new()
	invalid_mesh.radius = 0.3
	invalid_mesh.height = 0.6
	invalid_indicator.mesh = invalid_mesh
	invalid_indicator.material_override = invalid_material
	invalid_indicator.visible = false
	
	if not arc_mesh:
		arc_mesh = MeshInstance3D.new()
		add_child(arc_mesh)
	
	arc_mesh.material_override = arc_material
	arc_mesh.visible = false

func start_teleport():
	if is_teleporting:
		return
	
	is_teleporting = true
	arc_mesh.visible = true
	emit_signal("teleport_started")

func stop_teleport():
	if not is_teleporting:
		return
	
	is_teleporting = false
	arc_mesh.visible = false
	target_indicator.visible = false
	invalid_indicator.visible = false
	emit_signal("teleport_cancelled")

func execute_teleport():
	if not is_teleporting or not is_valid_target:
		return
	
	is_teleporting = false
	arc_mesh.visible = false
	target_indicator.visible = false
	invalid_indicator.visible = false
	
	if fade_overlay:
		fade_overlay.modulate.a = 1.0
		var tween = create_tween()
		tween.tween_property(fade_overlay, "modulate:a", 0.0, fade_duration)
	
	if player:
		player.global_position = teleport_target
	
	if haptic_feedback and controller:
		trigger_haptic_feedback(0.5, 0.2)
	
	emit_signal("teleport_completed", teleport_target)

func update_teleport_arc():
	arc_points.clear()
	
	var start_pos = global_position
	var direction = -global_transform.basis.z
	var gravity = Vector3(0, -9.8, 0)
	
	var current_pos = start_pos
	var current_velocity = direction * teleport_range
	var dt = 1.0 / arc_resolution
	
	for i in range(arc_resolution):
		arc_points.append(current_pos)
		
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(current_pos, current_pos + current_velocity * dt)
		query.collision_mask = valid_layer_mask
		var result = space_state.intersect_ray(query)
		
		if result:
			teleport_target = result.position
			is_valid_target = is_valid_teleport_target(result)
			arc_points.append(teleport_target)
			break
		
		current_velocity += gravity * dt
		current_pos += current_velocity * dt
	
	if arc_points.size() < 2:
		is_valid_target = false
		return
	
	update_arc_mesh()

func update_arc_mesh():
	if arc_points.size() < 2:
		return
	
	var array_mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var vertices = PackedVector3Array()
	var colors = PackedColorArray()
	var indices = PackedInt32Array()
	
	for i in range(arc_points.size()):
		vertices.append(to_local(arc_points[i]))
		
		var color = Color.CYAN
		if i == arc_points.size() - 1:
			color = Color.GREEN if is_valid_target else Color.RED
		colors.append(color)
		
		if i < arc_points.size() - 1:
			indices.append(i)
			indices.append(i + 1)
	
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	arc_mesh.mesh = array_mesh

func update_indicators():
	if arc_points.size() == 0:
		target_indicator.visible = false
		invalid_indicator.visible = false
		return
	
	var indicator = target_indicator if is_valid_target else invalid_indicator
	var other_indicator = invalid_indicator if is_valid_target else target_indicator
	
	indicator.visible = true
	other_indicator.visible = false
	indicator.global_position = teleport_target

func is_valid_teleport_target(collision_result: Dictionary) -> bool:
	if not collision_result:
		return false
	
	var normal = collision_result.normal
	var angle = normal.angle_to(Vector3.UP)
	
	if angle > deg_to_rad(45):
		return false
	
	var collider = collision_result.collider
	if collider and collider.has_method("can_teleport_here"):
		return collider.can_teleport_here()
	
	return true

func trigger_haptic_feedback(amplitude: float, duration: float):
	if controller and controller.has_method("trigger_haptic_pulse"):
		controller.trigger_haptic_pulse("haptic", 0, duration, amplitude, 0.0)

func _on_controller_button_pressed(name: String):
	match name:
		"ax_button", "by_button":
			start_teleport()

func _on_controller_button_released(name: String):
	match name:
		"ax_button", "by_button":
			if is_teleporting:
				execute_teleport()

func _on_controller_vector2_changed(name: String, value: Vector2):
	if name == "primary" and is_teleporting:
		if value.length() > 0.8:
			stop_teleport()

func set_teleport_range(new_range: float):
	teleport_range = new_range
	if teleport_ray:
		teleport_ray.target_position = Vector3(0, 0, -teleport_range)

func set_valid_layers(layer_mask: int):
	valid_layer_mask = layer_mask
	if teleport_ray:
		teleport_ray.collision_mask = layer_mask

func get_teleport_prediction(look_direction: Vector3) -> Dictionary:
	var space_state = get_world_3d().direct_space_state
	var start_pos = global_position
	var gravity = Vector3(0, -9.8, 0)
	
	var current_pos = start_pos
	var current_velocity = look_direction.normalized() * teleport_range
	var dt = 0.1
	
	for i in range(50):
		var query = PhysicsRayQueryParameters3D.create(current_pos, current_pos + current_velocity * dt)
		query.collision_mask = valid_layer_mask
		var result = space_state.intersect_ray(query)
		
		if result:
			return {
				"position": result.position,
				"normal": result.normal,
				"valid": is_valid_teleport_target(result),
				"distance": start_pos.distance_to(result.position)
			}
		
		current_velocity += gravity * dt
		current_pos += current_velocity * dt
	
	return {"valid": false}

func enable_continuous_teleport(enabled: bool):
	if enabled:
		controller.input_vector2_changed.connect(_on_continuous_teleport_input)
	else:
		if controller.input_vector2_changed.is_connected(_on_continuous_teleport_input):
			controller.input_vector2_changed.disconnect(_on_continuous_teleport_input)

func _on_continuous_teleport_input(name: String, value: Vector2):
	if name == "primary":
		if value.y < -0.8:
			if not is_teleporting:
				start_teleport()
		elif is_teleporting:
			execute_teleport()