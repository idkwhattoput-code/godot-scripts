extends RigidBody

signal destroyed
signal damaged(damage_amount: float)
signal health_changed(current_health: float, max_health: float)

export var max_health: float = 100.0
export var explosion_force: float = 500.0
export var explosion_radius: float = 5.0
export var debris_count: int = 10
export var debris_lifetime: float = 5.0
export var damage_threshold: float = 10.0
export var impact_damage_multiplier: float = 0.1
export var destroyed_mesh: Mesh
export var debris_meshes: Array = []
export var destruction_sound: AudioStream
export var impact_sounds: Array = []
export var destruction_particles: PackedScene
export var drop_items: Array = []
export var drop_chance: float = 0.5

var current_health: float
var is_destroyed: bool = false
var damage_accumulator: float = 0.0
var last_damage_time: float = 0.0
var damage_sources: Dictionary = {}

onready var mesh_instance: MeshInstance = $MeshInstance
onready var collision_shape: CollisionShape = $CollisionShape
onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
onready var damage_indicator: Spatial = $DamageIndicator

func _ready():
	current_health = max_health
	add_to_group("destructible")
	
	if not audio_player:
		audio_player = AudioStreamPlayer3D.new()
		add_child(audio_player)
	
	connect("body_entered", self, "_on_body_collision")
	contact_monitor = true
	contacts_reported = 10
	
	_update_visual_state()

func _on_body_collision(body):
	if is_destroyed:
		return
		
	var impact_velocity = linear_velocity.length()
	if body is RigidBody:
		impact_velocity = (linear_velocity - body.linear_velocity).length()
	
	var impact_damage = impact_velocity * impact_damage_multiplier
	if impact_damage >= damage_threshold:
		take_damage(impact_damage, body.global_transform.origin)
		_play_impact_sound(impact_damage)

func take_damage(amount: float, source_position: Vector3 = Vector3.ZERO, attacker: Node = null):
	if is_destroyed:
		return
	
	current_health = max(0, current_health - amount)
	damage_accumulator += amount
	last_damage_time = OS.get_ticks_msec() / 1000.0
	
	if attacker:
		if not attacker in damage_sources:
			damage_sources[attacker] = 0
		damage_sources[attacker] += amount
	
	emit_signal("damaged", amount)
	emit_signal("health_changed", current_health, max_health)
	
	_apply_damage_impulse(amount, source_position)
	_update_visual_state()
	_show_damage_indicator(source_position)
	
	if current_health <= 0:
		destroy(source_position)

func _apply_damage_impulse(damage: float, source_position: Vector3):
	if source_position != Vector3.ZERO:
		var direction = (global_transform.origin - source_position).normalized()
		var impulse = direction * damage * 0.5
		apply_central_impulse(impulse)
		apply_torque_impulse(Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * damage * 0.1)

func destroy(explosion_origin: Vector3 = Vector3.ZERO):
	if is_destroyed:
		return
	
	is_destroyed = true
	emit_signal("destroyed")
	
	_play_destruction_sound()
	_spawn_destruction_particles(explosion_origin)
	_spawn_debris(explosion_origin)
	_drop_items()
	_apply_explosion_to_nearby_objects(explosion_origin)
	
	if destroyed_mesh:
		mesh_instance.mesh = destroyed_mesh
		yield(get_tree().create_timer(0.5), "timeout")
	
	queue_free()

func _spawn_debris(explosion_origin: Vector3):
	var debris_parent = get_parent()
	
	for i in range(debris_count):
		var debris = RigidBody.new()
		var mesh_inst = MeshInstance.new()
		var collision = CollisionShape.new()
		
		if debris_meshes.size() > 0:
			mesh_inst.mesh = debris_meshes[randi() % debris_meshes.size()]
		else:
			var box_mesh = BoxMesh.new()
			box_mesh.size = Vector3(0.2 + randf() * 0.3, 0.2 + randf() * 0.3, 0.2 + randf() * 0.3)
			mesh_inst.mesh = box_mesh
		
		var shape = BoxShape.new()
		shape.extents = Vector3(0.15, 0.15, 0.15)
		collision.shape = shape
		
		debris.add_child(mesh_inst)
		debris.add_child(collision)
		debris.mass = 0.5 + randf() * 2.0
		debris.angular_damp = 0.5
		
		debris_parent.add_child(debris)
		debris.global_transform.origin = global_transform.origin + Vector3(
			randf() * 2 - 1,
			randf() * 2,
			randf() * 2 - 1
		)
		
		var explosion_dir = (debris.global_transform.origin - explosion_origin).normalized()
		if explosion_origin == Vector3.ZERO:
			explosion_dir = Vector3(randf() - 0.5, randf(), randf() - 0.5).normalized()
		
		debris.apply_central_impulse(explosion_dir * explosion_force * (0.5 + randf() * 0.5))
		debris.apply_torque_impulse(Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 10)
		
		_schedule_debris_cleanup(debris)

func _schedule_debris_cleanup(debris: RigidBody):
	yield(get_tree().create_timer(debris_lifetime), "timeout")
	if is_instance_valid(debris):
		debris.queue_free()

func _spawn_destruction_particles(origin: Vector3):
	if destruction_particles:
		var particles = destruction_particles.instance()
		get_parent().add_child(particles)
		particles.global_transform.origin = global_transform.origin
		particles.emitting = true

func _apply_explosion_to_nearby_objects(explosion_origin: Vector3):
	var space_state = get_world().direct_space_state
	var query = PhysicsShapeQueryParameters.new()
	var sphere = SphereShape.new()
	sphere.radius = explosion_radius
	query.set_shape(sphere)
	query.transform.origin = global_transform.origin
	
	var results = space_state.intersect_shape(query, 32)
	
	for result in results:
		var body = result.collider
		if body == self or not body is RigidBody:
			continue
			
		var distance = body.global_transform.origin.distance_to(global_transform.origin)
		var force_scale = 1.0 - (distance / explosion_radius)
		
		if force_scale > 0:
			var direction = (body.global_transform.origin - global_transform.origin).normalized()
			body.apply_central_impulse(direction * explosion_force * force_scale)
			
			if body.has_method("take_damage"):
				body.take_damage(max_health * 0.5 * force_scale, global_transform.origin, self)

func _drop_items():
	if drop_items.size() == 0:
		return
		
	for item_scene in drop_items:
		if randf() <= drop_chance and item_scene is PackedScene:
			var item = item_scene.instance()
			get_parent().add_child(item)
			item.global_transform.origin = global_transform.origin + Vector3(0, 1, 0)
			
			if item is RigidBody:
				var throw_direction = Vector3(randf() - 0.5, randf() * 0.5 + 0.5, randf() - 0.5).normalized()
				item.apply_central_impulse(throw_direction * 5)

func _play_destruction_sound():
	if destruction_sound and audio_player:
		audio_player.stream = destruction_sound
		audio_player.pitch_scale = 0.9 + randf() * 0.2
		audio_player.play()

func _play_impact_sound(impact_force: float):
	if impact_sounds.size() > 0 and audio_player and not audio_player.playing:
		audio_player.stream = impact_sounds[randi() % impact_sounds.size()]
		audio_player.volume_db = linear2db(clamp(impact_force / 100.0, 0.1, 1.0))
		audio_player.pitch_scale = 0.9 + randf() * 0.2
		audio_player.play()

func _update_visual_state():
	if not mesh_instance:
		return
		
	var health_ratio = current_health / max_health
	var material = mesh_instance.get_surface_material(0)
	
	if material:
		if health_ratio < 0.3:
			material.albedo_color = Color(1, 0.3, 0.3)
		elif health_ratio < 0.6:
			material.albedo_color = Color(1, 0.7, 0.3)

func _show_damage_indicator(source_position: Vector3):
	if damage_indicator:
		damage_indicator.look_at(source_position, Vector3.UP)
		damage_indicator.visible = true
		yield(get_tree().create_timer(0.2), "timeout")
		if damage_indicator:
			damage_indicator.visible = false

func repair(amount: float):
	if is_destroyed:
		return
		
	current_health = min(max_health, current_health + amount)
	emit_signal("health_changed", current_health, max_health)
	_update_visual_state()

func get_health_percentage() -> float:
	return (current_health / max_health) * 100.0

func get_last_attacker() -> Node:
	var max_damage = 0
	var last_attacker = null
	
	for attacker in damage_sources:
		if damage_sources[attacker] > max_damage:
			max_damage = damage_sources[attacker]
			last_attacker = attacker
	
	return last_attacker