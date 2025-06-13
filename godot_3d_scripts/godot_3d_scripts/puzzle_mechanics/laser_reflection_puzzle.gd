extends Node3D

class_name LaserReflectionPuzzle

@export var laser_color := Color(1.0, 0.0, 0.0)
@export var laser_width := 0.05
@export var max_reflections := 10
@export var reflection_angle_tolerance := 5.0
@export var laser_damage := 10.0
@export var laser_range := 100.0
@export var update_frequency := 0.05

var laser_path := []
var laser_visuals := []
var current_targets_hit := []
var last_update_time := 0.0
var is_active := true

signal target_hit(target: Node3D)
signal target_lost(target: Node3D)
signal puzzle_solved()
signal laser_blocked()

func _ready():
	set_physics_process(true)

func _physics_process(delta):
	last_update_time += delta
	if last_update_time >= update_frequency:
		last_update_time = 0.0
		if is_active:
			update_laser_path()

func update_laser_path():
	clear_laser_visuals()
	laser_path.clear()
	var previous_targets = current_targets_hit.duplicate()
	current_targets_hit.clear()
	
	var start_pos = global_transform.origin
	var direction = -global_transform.basis.z
	
	trace_laser(start_pos, direction, 0)
	
	update_laser_visuals()
	check_target_changes(previous_targets)

func trace_laser(start: Vector3, direction: Vector3, reflection_count: int):
	if reflection_count >= max_reflections:
		return
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		start, 
		start + direction * laser_range
	)
	query.collision_mask = 0xFFFFFFFF
	query.exclude = [self]
	
	var result = space_state.intersect_ray(query)
	
	if result:
		var end_pos = result.position
		laser_path.append({"start": start, "end": end_pos})
		
		var hit_object = result.collider
		
		if hit_object.has_method("on_laser_hit"):
			hit_object.on_laser_hit(self, result.position, direction)
			if hit_object.has_method("is_laser_target") and hit_object.is_laser_target():
				if not hit_object in current_targets_hit:
					current_targets_hit.append(hit_object)
		
		if hit_object.has_method("reflect_laser"):
			var new_direction = hit_object.reflect_laser(direction, result.normal)
			if new_direction:
				trace_laser(end_pos + new_direction * 0.01, new_direction, reflection_count + 1)
		elif hit_object.has_method("is_mirror") and hit_object.is_mirror():
			var new_direction = calculate_reflection(direction, result.normal)
			trace_laser(end_pos + new_direction * 0.01, new_direction, reflection_count + 1)
		else:
			emit_signal("laser_blocked")
	else:
		laser_path.append({"start": start, "end": start + direction * laser_range})

func calculate_reflection(incident: Vector3, normal: Vector3) -> Vector3:
	return incident - 2 * incident.dot(normal) * normal

func clear_laser_visuals():
	for visual in laser_visuals:
		visual.queue_free()
	laser_visuals.clear()

func update_laser_visuals():
	for segment in laser_path:
		create_laser_segment(segment.start, segment.end)

func create_laser_segment(start: Vector3, end: Vector3):
	var mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	laser_visuals.append(mesh_instance)
	
	var cylinder_mesh = CylinderMesh.new()
	var length = start.distance_to(end)
	cylinder_mesh.height = length
	cylinder_mesh.top_radius = laser_width
	cylinder_mesh.bottom_radius = laser_width
	cylinder_mesh.radial_segments = 8
	mesh_instance.mesh = cylinder_mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = laser_color
	material.emission_enabled = true
	material.emission = laser_color
	material.emission_energy = 2.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.8
	mesh_instance.set_surface_override_material(0, material)
	
	var mid_point = (start + end) / 2.0
	mesh_instance.global_position = mid_point
	
	var direction = (end - start).normalized()
	if direction.length() > 0:
		var up = Vector3.UP
		if abs(direction.dot(up)) > 0.99:
			up = Vector3.RIGHT
		mesh_instance.look_at(mid_point + direction, up)
		mesh_instance.rotate_object_local(Vector3.RIGHT, PI/2)
	
	add_laser_particles(start, end)

func add_laser_particles(start: Vector3, end: Vector3):
	var particles = GPUParticles3D.new()
	add_child(particles)
	laser_visuals.append(particles)
	
	particles.amount = 20
	particles.lifetime = 0.5
	particles.emitting = true
	
	var process_material = ParticleProcessMaterial.new()
	process_material.direction = (end - start).normalized()
	process_material.initial_velocity_min = 0.5
	process_material.initial_velocity_max = 1.0
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(laser_width, laser_width, start.distance_to(end) / 2.0)
	process_material.color = laser_color
	particles.process_material = process_material
	
	particles.draw_pass_1 = SphereMesh.new()
	particles.draw_pass_1.radial_segments = 4
	particles.draw_pass_1.rings = 2
	particles.draw_pass_1.radius = 0.01
	particles.draw_pass_1.height = 0.02
	
	particles.global_position = (start + end) / 2.0
	particles.look_at(end, Vector3.UP)

func check_target_changes(previous_targets: Array):
	for target in current_targets_hit:
		if not target in previous_targets:
			emit_signal("target_hit", target)
	
	for target in previous_targets:
		if not target in current_targets_hit:
			emit_signal("target_lost", target)
	
	check_puzzle_completion()

func check_puzzle_completion():
	var required_targets = get_tree().get_nodes_in_group("laser_targets")
	var all_hit = true
	
	for target in required_targets:
		if target.has_method("is_activated") and not target.is_activated():
			all_hit = false
			break
	
	if all_hit and required_targets.size() > 0:
		emit_signal("puzzle_solved")

func set_laser_active(active: bool):
	is_active = active
	if not active:
		clear_laser_visuals()
		laser_path.clear()
		for target in current_targets_hit:
			emit_signal("target_lost", target)
		current_targets_hit.clear()

func get_laser_path() -> Array:
	return laser_path

func is_hitting_target(target: Node3D) -> bool:
	return target in current_targets_hit