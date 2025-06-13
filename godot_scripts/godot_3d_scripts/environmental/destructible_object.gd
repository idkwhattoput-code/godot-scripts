extends RigidBody3D

class_name DestructibleObject

@export_group("Health Settings")
@export var max_health := 100.0
@export var explosion_damage_threshold := 50.0
@export var damage_resistance := 0.0

@export_group("Destruction Effects")
@export var debris_scenes: Array[PackedScene] = []
@export var debris_count_min := 5
@export var debris_count_max := 10
@export var debris_force_min := 5.0
@export var debris_force_max := 15.0
@export var debris_lifetime := 5.0
@export var destruction_particle_scene: PackedScene
@export var destruction_sound: AudioStream

@export_group("Physics")
@export var break_force_threshold := 100.0
@export var impact_damage_multiplier := 0.5
@export var falls_when_destroyed := true

@export_group("Rewards")
@export var drop_items: Array[PackedScene] = []
@export var drop_chance := 0.5
@export var experience_value := 10

var current_health: float
var is_destroyed := false
var accumulated_damage := {}
var damage_cooldown := 0.1
var last_damage_time := 0.0
var original_collision_layer: int
var original_collision_mask: int

signal destroyed()
signal damaged(amount: float, damage_type: String)
signal health_changed(new_health: float, max_health: float)

func _ready():
	current_health = max_health
	original_collision_layer = collision_layer
	original_collision_mask = collision_mask
	
	body_entered.connect(_on_body_entered)
	
	if not freeze_mode:
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC

func take_damage(amount: float, damage_type: String = "normal", damage_source: Node3D = null, hit_position: Vector3 = Vector3.ZERO):
	if is_destroyed:
		return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_damage_time < damage_cooldown:
		return
	
	last_damage_time = current_time
	
	var actual_damage = calculate_damage(amount, damage_type)
	current_health -= actual_damage
	
	emit_signal("damaged", actual_damage, damage_type)
	emit_signal("health_changed", current_health, max_health)
	
	apply_damage_effects(hit_position, damage_source, actual_damage)
	
	if damage_type in accumulated_damage:
		accumulated_damage[damage_type] += actual_damage
	else:
		accumulated_damage[damage_type] = actual_damage
	
	if current_health <= 0:
		destroy(damage_source, hit_position)
	elif actual_damage >= explosion_damage_threshold:
		create_explosion_effect(hit_position)

func calculate_damage(base_damage: float, damage_type: String) -> float:
	var multiplier = 1.0
	
	match damage_type:
		"fire":
			multiplier = 1.5
		"explosive":
			multiplier = 2.0
		"electric":
			multiplier = 1.2
		"ice":
			multiplier = 0.8
	
	return max(0, base_damage * multiplier * (1.0 - damage_resistance))

func apply_damage_effects(hit_position: Vector3, damage_source: Node3D, damage_amount: float):
	if freeze_mode == RigidBody3D.FREEZE_MODE_STATIC and damage_amount > 20:
		freeze = false
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	
	if freeze == false and damage_source:
		var force_direction = (global_position - damage_source.global_position).normalized()
		var force_position = hit_position - global_position
		apply_impulse(force_position, force_direction * damage_amount * 0.1)
	
	create_damage_decal(hit_position)
	flash_damage_color()

func destroy(destroyer: Node3D = null, impact_point: Vector3 = Vector3.ZERO):
	if is_destroyed:
		return
	
	is_destroyed = true
	emit_signal("destroyed")
	
	spawn_debris(impact_point)
	spawn_drops()
	play_destruction_effects()
	
	if destroyer and destroyer.has_method("on_object_destroyed"):
		destroyer.on_object_destroyed(self, experience_value)
	
	collision_layer = 0
	collision_mask = 0
	
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.3)
	tween.finished.connect(queue_free)

func spawn_debris(impact_point: Vector3):
	var debris_count = randi_range(debris_count_min, debris_count_max)
	
	for i in range(debris_count):
		var debris_instance: RigidBody3D
		
		if debris_scenes.size() > 0:
			var debris_scene = debris_scenes[randi() % debris_scenes.size()]
			debris_instance = debris_scene.instantiate()
		else:
			debris_instance = create_default_debris()
		
		get_parent().add_child(debris_instance)
		debris_instance.global_position = global_position + Vector3(
			randf_range(-0.5, 0.5),
			randf_range(0, 1),
			randf_range(-0.5, 0.5)
		)
		
		var force_direction = (debris_instance.global_position - impact_point).normalized()
		if force_direction.length() < 0.1:
			force_direction = Vector3(randf_range(-1, 1), randf_range(0.5, 1), randf_range(-1, 1)).normalized()
		
		var force_magnitude = randf_range(debris_force_min, debris_force_max)
		debris_instance.apply_central_impulse(force_direction * force_magnitude)
		debris_instance.apply_torque_impulse(Vector3(
			randf_range(-5, 5),
			randf_range(-5, 5),
			randf_range(-5, 5)
		))
		
		if debris_lifetime > 0:
			create_debris_lifetime_timer(debris_instance, debris_lifetime)

func create_default_debris() -> RigidBody3D:
	var debris = RigidBody3D.new()
	var mesh_instance = MeshInstance3D.new()
	var collision_shape = CollisionShape3D.new()
	
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(0.2, 0.2, 0.2)
	mesh_instance.mesh = box_mesh
	
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(0.2, 0.2, 0.2)
	collision_shape.shape = box_shape
	
	debris.add_child(mesh_instance)
	debris.add_child(collision_shape)
	debris.mass = 0.5
	
	return debris

func create_debris_lifetime_timer(debris: Node3D, lifetime: float):
	var timer = Timer.new()
	timer.wait_time = lifetime
	timer.one_shot = true
	timer.timeout.connect(debris.queue_free)
	debris.add_child(timer)
	timer.start()

func spawn_drops():
	if drop_items.size() == 0 or randf() > drop_chance:
		return
	
	var drop_scene = drop_items[randi() % drop_items.size()]
	var drop_instance = drop_scene.instantiate()
	get_parent().add_child(drop_instance)
	drop_instance.global_position = global_position + Vector3(0, 0.5, 0)
	
	if drop_instance is RigidBody3D:
		drop_instance.apply_central_impulse(Vector3(
			randf_range(-2, 2),
			randf_range(3, 5),
			randf_range(-2, 2)
		))

func play_destruction_effects():
	if destruction_particle_scene:
		var particles = destruction_particle_scene.instantiate()
		get_parent().add_child(particles)
		particles.global_position = global_position
		particles.emitting = true
		
		var lifetime_timer = Timer.new()
		lifetime_timer.wait_time = 5.0
		lifetime_timer.one_shot = true
		lifetime_timer.timeout.connect(particles.queue_free)
		particles.add_child(lifetime_timer)
		lifetime_timer.start()
	
	if destruction_sound:
		var audio_player = AudioStreamPlayer3D.new()
		audio_player.stream = destruction_sound
		audio_player.volume_db = 0
		audio_player.pitch_scale = randf_range(0.9, 1.1)
		get_parent().add_child(audio_player)
		audio_player.global_position = global_position
		audio_player.play()
		audio_player.finished.connect(audio_player.queue_free)

func _on_body_entered(body: Node):
	if is_destroyed:
		return
	
	if body is RigidBody3D:
		var impact_force = body.linear_velocity.length() * body.mass
		if impact_force > break_force_threshold:
			take_damage(impact_force * impact_damage_multiplier, "impact", body, body.global_position)

func create_damage_decal(position: Vector3):
	pass

func flash_damage_color():
	var mesh_instance = get_node_or_null("MeshInstance3D")
	if not mesh_instance:
		return
	
	var material = mesh_instance.get_surface_override_material(0)
	if not material:
		material = StandardMaterial3D.new()
		mesh_instance.set_surface_override_material(0, material)
	
	var original_color = material.albedo_color
	var tween = create_tween()
	tween.tween_property(material, "albedo_color", Color(1, 0.3, 0.3), 0.1)
	tween.tween_property(material, "albedo_color", original_color, 0.2)

func create_explosion_effect(position: Vector3):
	pass

func repair(amount: float):
	if is_destroyed:
		return
	
	current_health = min(current_health + amount, max_health)
	emit_signal("health_changed", current_health, max_health)

func get_health_percentage() -> float:
	return current_health / max_health * 100.0

func reset():
	current_health = max_health
	is_destroyed = false
	accumulated_damage.clear()
	collision_layer = original_collision_layer
	collision_mask = original_collision_mask
	scale = Vector3.ONE
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC