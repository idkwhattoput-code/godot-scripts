extends Area3D

signal object_entered_wind(object: Node3D)
signal object_exited_wind(object: Node3D)

@export_group("Wind Properties")
@export var wind_direction: Vector3 = Vector3(1, 0, 0)
@export var wind_strength: float = 20.0
@export var wind_turbulence: float = 0.3
@export var gust_frequency: float = 2.0
@export var gust_strength: float = 10.0
@export var wind_falloff: bool = true
@export var falloff_curve: Curve

@export_group("Affected Objects")
@export var affect_rigid_bodies: bool = true
@export var affect_character_bodies: bool = true
@export var affect_particles: bool = true
@export var affect_cloth: bool = true
@export var mass_influence: float = 1.0
@export var size_groups: Array[String] = []

@export_group("Visual Effects")
@export var wind_particles: CPUParticles3D
@export var wind_sound: AudioStream
@export var sound_volume_curve: Curve
@export var visual_indicators: bool = true
@export var indicator_spacing: float = 2.0

@export_group("Performance")
@export var update_frequency: float = 60.0
@export var max_affected_objects: int = 100
@export var distance_culling: float = 50.0

var affected_objects: Dictionary = {}
var gust_timer: float = 0.0
var current_gust_strength: float = 0.0
var update_timer: float = 0.0
var turbulence_offset: Vector3 = Vector3.ZERO
var audio_player: AudioStreamPlayer3D

func _ready():
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	wind_direction = wind_direction.normalized()
	
	if wind_sound:
		audio_player = AudioStreamPlayer3D.new()
		audio_player.stream = wind_sound
		audio_player.unit_size = 20.0
		audio_player.max_distance = distance_culling
		add_child(audio_player)
		audio_player.play()
		
	if visual_indicators:
		_create_visual_indicators()
		
	if wind_particles:
		_setup_wind_particles()
		
func _physics_process(delta):
	update_timer += delta
	if update_timer < 1.0 / update_frequency:
		return
	update_timer = 0.0
	
	_update_gust(delta)
	_update_turbulence(delta)
	_apply_wind_forces()
	_update_audio()
	
func _update_gust(delta):
	gust_timer += delta * gust_frequency
	current_gust_strength = sin(gust_timer) * gust_strength
	current_gust_strength = max(0, current_gust_strength)
	
func _update_turbulence(delta):
	turbulence_offset += Vector3(
		randf_range(-1, 1),
		randf_range(-1, 1),
		randf_range(-1, 1)
	) * wind_turbulence * delta
	
	turbulence_offset = turbulence_offset.limit_length(wind_turbulence)
	
func _apply_wind_forces():
	var objects_to_remove = []
	var object_count = 0
	
	for object in affected_objects:
		if not is_instance_valid(object):
			objects_to_remove.append(object)
			continue
			
		if object_count >= max_affected_objects:
			break
			
		var distance = global_position.distance_to(object.global_position)
		if distance > distance_culling:
			continue
			
		var wind_force = _calculate_wind_force(object, distance)
		_apply_force_to_object(object, wind_force)
		object_count += 1
		
	for object in objects_to_remove:
		affected_objects.erase(object)
		
func _calculate_wind_force(object: Node3D, distance: float) -> Vector3:
	var base_force = wind_direction * (wind_strength + current_gust_strength)
	base_force += turbulence_offset
	
	if wind_falloff and falloff_curve:
		var falloff_factor = falloff_curve.sample(distance / distance_culling)
		base_force *= falloff_factor
		
	if object is RigidBody3D and mass_influence > 0:
		var mass_factor = 1.0 / (1.0 + object.mass * mass_influence)
		base_force *= mass_factor
		
	return base_force
	
func _apply_force_to_object(object: Node3D, force: Vector3):
	if object is RigidBody3D and affect_rigid_bodies:
		object.apply_central_force(force)
		
		var torque = force.cross(Vector3.UP) * 0.1
		object.apply_torque(torque)
		
	elif object is CharacterBody3D and affect_character_bodies:
		if object.has_method("apply_wind_force"):
			object.apply_wind_force(force)
		else:
			object.velocity += force * get_physics_process_delta_time()
			
	elif object is CPUParticles3D and affect_particles:
		object.gravity = force
		
func _on_body_entered(body: Node3D):
	if _should_affect_object(body):
		affected_objects[body] = true
		object_entered_wind.emit(body)
		
func _on_body_exited(body: Node3D):
	if body in affected_objects:
		affected_objects.erase(body)
		object_exited_wind.emit(body)
		
		if body is CPUParticles3D:
			body.gravity = Vector3(0, -9.8, 0)
			
func _should_affect_object(object: Node3D) -> bool:
	if object is RigidBody3D and not affect_rigid_bodies:
		return false
		
	if object is CharacterBody3D and not affect_character_bodies:
		return false
		
	if object is CPUParticles3D and not affect_particles:
		return false
		
	if size_groups.size() > 0:
		var in_group = false
		for group in size_groups:
			if object.is_in_group(group):
				in_group = true
				break
		if not in_group:
			return false
			
	return true
	
func _create_visual_indicators():
	var bounds = get_node("CollisionShape3D").shape.get_debug_mesh().get_aabb()
	var indicator_parent = Node3D.new()
	indicator_parent.name = "WindIndicators"
	add_child(indicator_parent)
	
	for x in range(int(bounds.size.x / indicator_spacing)):
		for y in range(int(bounds.size.y / indicator_spacing)):
			for z in range(int(bounds.size.z / indicator_spacing)):
				var indicator = _create_single_indicator()
				indicator.position = Vector3(
					(x - bounds.size.x / 2) * indicator_spacing,
					(y - bounds.size.y / 2) * indicator_spacing,
					(z - bounds.size.z / 2) * indicator_spacing
				)
				indicator_parent.add_child(indicator)
				
func _create_single_indicator() -> Node3D:
	var indicator = Node3D.new()
	var mesh_instance = MeshInstance3D.new()
	
	var arrow_mesh = CylinderMesh.new()
	arrow_mesh.height = 0.5
	arrow_mesh.top_radius = 0.0
	arrow_mesh.bottom_radius = 0.05
	mesh_instance.mesh = arrow_mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.8, 1.0, 0.3)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material
	
	indicator.add_child(mesh_instance)
	return indicator
	
func _setup_wind_particles():
	wind_particles.direction = wind_direction
	wind_particles.initial_velocity_min = wind_strength * 0.5
	wind_particles.initial_velocity_max = wind_strength * 1.5
	wind_particles.gravity = Vector3.ZERO
	wind_particles.emitting = true
	
func _update_audio():
	if not audio_player:
		return
		
	var listener = get_viewport().get_camera_3d()
	if not listener:
		return
		
	var distance = global_position.distance_to(listener.global_position)
	var volume_factor = 1.0
	
	if sound_volume_curve:
		volume_factor = sound_volume_curve.sample(clamp(distance / distance_culling, 0.0, 1.0))
		
	var gust_volume = current_gust_strength / gust_strength * 0.3
	audio_player.volume_db = linear_to_db(volume_factor + gust_volume)
	audio_player.pitch_scale = 0.8 + (wind_strength / 100.0) * 0.4
	
func set_wind_direction(direction: Vector3):
	wind_direction = direction.normalized()
	if wind_particles:
		wind_particles.direction = wind_direction
		
func set_wind_strength(strength: float):
	wind_strength = strength
	if wind_particles:
		wind_particles.initial_velocity_min = strength * 0.5
		wind_particles.initial_velocity_max = strength * 1.5
		
func add_temporary_gust(strength: float, duration: float):
	var original_gust = gust_strength
	gust_strength += strength
	
	await get_tree().create_timer(duration).timeout
	gust_strength = original_gust
	
func get_wind_at_position(pos: Vector3) -> Vector3:
	var distance = global_position.distance_to(pos)
	if distance > distance_culling:
		return Vector3.ZERO
		
	var dummy_object = Node3D.new()
	dummy_object.global_position = pos
	return _calculate_wind_force(dummy_object, distance)