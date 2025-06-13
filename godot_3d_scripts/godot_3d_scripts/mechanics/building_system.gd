extends Node

signal build_mode_entered
signal build_mode_exited
signal structure_placed(structure_name: String, position: Vector3)
signal structure_removed(structure_name: String, position: Vector3)
signal build_failed(reason: String)
signal resource_insufficient(resource_type: String, required: int, available: int)

export var enabled: bool = true
export var build_range: float = 10.0
export var snap_to_grid: bool = true
export var grid_size: float = 1.0
export var preview_material: Material
export var valid_placement_color: Color = Color.green
export var invalid_placement_color: Color = Color.red
export var allow_overlap: bool = false
export var terrain_alignment: bool = true
export var max_terrain_angle: float = 45.0
export var placement_update_rate: float = 0.05
export var rotation_snap_angle: float = 15.0

var in_build_mode: bool = false
var current_structure: String = ""
var preview_instance: Spatial = null
var placement_valid: bool = false
var rotation_amount: float = 0.0
var placement_timer: float = 0.0
var placed_structures: Dictionary = {}
var structure_instances: Array = []

var structures: Dictionary = {
	"wall": {
		"scene": preload("res://structures/wall.tscn"),
		"cost": {"wood": 10, "stone": 5},
		"health": 100,
		"build_time": 2.0,
		"category": "defense",
		"description": "Basic defensive wall"
	},
	"foundation": {
		"scene": preload("res://structures/foundation.tscn"),
		"cost": {"stone": 20},
		"health": 200,
		"build_time": 3.0,
		"category": "foundation",
		"description": "Stable foundation for buildings"
	},
	"turret": {
		"scene": preload("res://structures/turret.tscn"),
		"cost": {"metal": 30, "crystal": 5},
		"health": 150,
		"build_time": 5.0,
		"category": "defense",
		"description": "Automated defense turret"
	},
	"storage": {
		"scene": preload("res://structures/storage.tscn"),
		"cost": {"wood": 20, "metal": 10},
		"health": 80,
		"build_time": 2.5,
		"category": "utility",
		"description": "Resource storage container"
	}
}

var build_categories: Array = ["foundation", "defense", "utility", "production"]

var player: Spatial
var camera: Camera
var build_ui: Control
var resource_manager: Node
var audio_player: AudioStreamPlayer3D

onready var build_sounds: Dictionary = {
	"place": null,
	"remove": null,
	"error": null
}

func _ready():
	set_process(false)

func initialize(player_node: Spatial, camera_node: Camera, resources: Node = null):
	player = player_node
	camera = camera_node
	resource_manager = resources
	
	_setup_audio()
	set_process(true)

func _process(delta):
	if not enabled:
		return
	
	if in_build_mode:
		placement_timer += delta
		if placement_timer >= placement_update_rate:
			placement_timer = 0.0
			_update_preview_placement()
		
		_handle_build_input()

func enter_build_mode(structure_name: String = ""):
	if not enabled or in_build_mode:
		return false
	
	if structure_name != "" and not structure_name in structures:
		return false
	
	in_build_mode = true
	current_structure = structure_name
	
	if current_structure != "":
		_create_preview()
	
	emit_signal("build_mode_entered")
	return true

func exit_build_mode():
	if not in_build_mode:
		return
	
	in_build_mode = false
	current_structure = ""
	
	if preview_instance:
		preview_instance.queue_free()
		preview_instance = null
	
	emit_signal("build_mode_exited")

func select_structure(structure_name: String):
	if not in_build_mode or not structure_name in structures:
		return false
	
	current_structure = structure_name
	
	if preview_instance:
		preview_instance.queue_free()
	
	_create_preview()
	return true

func _create_preview():
	if not current_structure in structures:
		return
	
	var structure_data = structures[current_structure]
	if not structure_data.has("scene"):
		return
	
	preview_instance = structure_data.scene.instance()
	get_tree().current_scene.add_child(preview_instance)
	
	_apply_preview_material(preview_instance)
	_disable_preview_functionality(preview_instance)

func _apply_preview_material(node: Spatial):
	if not preview_material:
		return
	
	for child in node.get_children():
		if child is MeshInstance:
			for i in range(child.get_surface_material_count()):
				child.set_surface_material(i, preview_material)
		elif child is Spatial:
			_apply_preview_material(child)

func _disable_preview_functionality(node: Spatial):
	for child in node.get_children():
		if child is CollisionShape or child is CollisionShape2D:
			child.disabled = true
		elif child is Area or child is Area2D:
			child.monitoring = false
			child.monitorable = false
		elif child is RigidBody or child is KinematicBody:
			child.set_physics_process(false)
		elif child is Spatial:
			_disable_preview_functionality(child)

func _update_preview_placement():
	if not preview_instance or not camera:
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_from = camera.project_ray_origin(mouse_pos)
	var ray_to = ray_from + camera.project_ray_normal(mouse_pos) * build_range
	
	var space_state = camera.get_world().direct_space_state
	var result = space_state.intersect_ray(ray_from, ray_to, [player, preview_instance])
	
	if result:
		var placement_pos = result.position
		
		if snap_to_grid:
			placement_pos = _snap_to_grid(placement_pos)
		
		preview_instance.global_transform.origin = placement_pos
		
		if terrain_alignment:
			_align_to_terrain(result.normal)
		
		preview_instance.rotation.y = deg2rad(rotation_amount)
		
		placement_valid = _check_placement_validity(placement_pos, result.normal)
		_update_preview_visual()

func _snap_to_grid(position: Vector3) -> Vector3:
	return Vector3(
		round(position.x / grid_size) * grid_size,
		position.y,
		round(position.z / grid_size) * grid_size
	)

func _align_to_terrain(normal: Vector3):
	if not preview_instance:
		return
	
	var angle = rad2deg(acos(normal.dot(Vector3.UP)))
	if angle > max_terrain_angle:
		return
	
	var right = normal.cross(Vector3.FORWARD).normalized()
	var forward = right.cross(normal).normalized()
	
	preview_instance.global_transform.basis = Basis(right, normal, forward)
	preview_instance.rotation.y = deg2rad(rotation_amount)

func _check_placement_validity(position: Vector3, normal: Vector3) -> bool:
	if not _check_build_range(position):
		return false
	
	if not _check_terrain_angle(normal):
		return false
	
	if not allow_overlap and _check_overlap(position):
		return false
	
	if not _check_resources():
		return false
	
	return true

func _check_build_range(position: Vector3) -> bool:
	return player.global_transform.origin.distance_to(position) <= build_range

func _check_terrain_angle(normal: Vector3) -> bool:
	var angle = rad2deg(acos(normal.dot(Vector3.UP)))
	return angle <= max_terrain_angle

func _check_overlap(position: Vector3) -> bool:
	for structure in structure_instances:
		if structure.global_transform.origin.distance_to(position) < grid_size * 0.9:
			return true
	return false

func _check_resources() -> bool:
	if not resource_manager or not current_structure in structures:
		return true
	
	var cost = structures[current_structure].get("cost", {})
	
	for resource_type in cost:
		var required = cost[resource_type]
		var available = resource_manager.get_resource_amount(resource_type)
		
		if available < required:
			emit_signal("resource_insufficient", resource_type, required, available)
			return false
	
	return true

func _update_preview_visual():
	if not preview_instance or not preview_material:
		return
	
	var color = valid_placement_color if placement_valid else invalid_placement_color
	
	if preview_material.has_property("albedo_color"):
		preview_material.albedo_color = color
	elif preview_material.has_property("emission"):
		preview_material.emission = color

func _handle_build_input():
	if Input.is_action_just_pressed("rotate_left"):
		rotation_amount -= rotation_snap_angle
	elif Input.is_action_just_pressed("rotate_right"):
		rotation_amount += rotation_snap_angle
	
	rotation_amount = fmod(rotation_amount, 360.0)
	
	if Input.is_action_just_pressed("place_structure"):
		place_structure()
	elif Input.is_action_just_pressed("cancel_build"):
		exit_build_mode()

func place_structure():
	if not placement_valid or not preview_instance:
		emit_signal("build_failed", "Invalid placement")
		_play_sound("error")
		return false
	
	if not _consume_resources():
		emit_signal("build_failed", "Insufficient resources")
		_play_sound("error")
		return false
	
	var structure_data = structures[current_structure]
	var instance = structure_data.scene.instance()
	get_tree().current_scene.add_child(instance)
	
	instance.global_transform = preview_instance.global_transform
	
	structure_instances.append(instance)
	
	var pos_key = _position_to_key(instance.global_transform.origin)
	placed_structures[pos_key] = {
		"name": current_structure,
		"instance": instance,
		"health": structure_data.get("health", 100),
		"position": instance.global_transform.origin
	}
	
	if instance.has_method("on_placed"):
		instance.on_placed(player)
	
	emit_signal("structure_placed", current_structure, instance.global_transform.origin)
	_play_sound("place")
	
	_create_preview()
	
	return true

func remove_structure(position: Vector3):
	var pos_key = _position_to_key(position)
	
	if not pos_key in placed_structures:
		return false
	
	var structure_info = placed_structures[pos_key]
	var instance = structure_info.instance
	
	if resource_manager:
		var cost = structures[structure_info.name].get("cost", {})
		for resource_type in cost:
			var refund_amount = int(cost[resource_type] * 0.5)
			resource_manager.add_to_inventory(resource_type, refund_amount)
	
	structure_instances.erase(instance)
	placed_structures.erase(pos_key)
	
	if instance.has_method("on_removed"):
		instance.on_removed()
	
	instance.queue_free()
	
	emit_signal("structure_removed", structure_info.name, position)
	_play_sound("remove")
	
	return true

func _consume_resources() -> bool:
	if not resource_manager or not current_structure in structures:
		return true
	
	var cost = structures[current_structure].get("cost", {})
	
	for resource_type in cost:
		if not resource_manager.remove_from_inventory(resource_type, cost[resource_type]):
			return false
	
	return true

func _position_to_key(position: Vector3) -> String:
	var snapped = _snap_to_grid(position)
	return "%d,%d,%d" % [int(snapped.x), int(snapped.y), int(snapped.z)]

func get_structure_at_position(position: Vector3) -> Dictionary:
	var pos_key = _position_to_key(position)
	return placed_structures.get(pos_key, {})

func get_nearby_structures(position: Vector3, radius: float) -> Array:
	var nearby = []
	
	for structure in structure_instances:
		if structure.global_transform.origin.distance_to(position) <= radius:
			nearby.append(structure)
	
	return nearby

func _setup_audio():
	if not audio_player:
		audio_player = AudioStreamPlayer3D.new()
		if player:
			player.add_child(audio_player)

func _play_sound(sound_type: String):
	if not audio_player or not sound_type in build_sounds:
		return
	
	if build_sounds[sound_type]:
		audio_player.stream = build_sounds[sound_type]
		audio_player.play()

func add_structure_type(name: String, data: Dictionary):
	structures[name] = data

func get_structure_cost(structure_name: String) -> Dictionary:
	if structure_name in structures:
		return structures[structure_name].get("cost", {})
	return {}

func get_build_categories() -> Array:
	return build_categories

func get_structures_by_category(category: String) -> Array:
	var result = []
	for name in structures:
		if structures[name].get("category", "") == category:
			result.append(name)
	return result

func set_building_enabled(enabled_state: bool):
	enabled = enabled_state
	if not enabled and in_build_mode:
		exit_build_mode()