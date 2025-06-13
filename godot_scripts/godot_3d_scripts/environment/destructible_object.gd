extends RigidBody

export var health = 100.0
export var destruction_threshold = 0.0
export var explosion_force = 10.0
export var debris_count = 10
export var debris_scene : PackedScene
export var destruction_particles : PackedScene
export var respawn_time = 0.0
export var drop_items = []
export var destruction_sound : AudioStream

signal destroyed()
signal damaged(amount)
signal health_changed(current_health)

var initial_health
var is_destroyed = false
var accumulated_damage = 0.0
var respawn_timer = 0.0
var original_transform
var original_parent

onready var mesh_instance = $MeshInstance
onready var collision_shape = $CollisionShape
onready var audio_player = $AudioStreamPlayer3D

func _ready():
	initial_health = health
	original_transform = global_transform
	original_parent = get_parent()
	
	if not audio_player:
		audio_player = AudioStreamPlayer3D.new()
		add_child(audio_player)
	
	set_contact_monitor(true)
	set_max_contacts_reported(10)
	connect("body_entered", self, "_on_body_entered")

func _physics_process(delta):
	if is_destroyed and respawn_time > 0:
		respawn_timer += delta
		if respawn_timer >= respawn_time:
			respawn()

func _on_body_entered(body):
	if is_destroyed:
		return
		
	var impact_force = linear_velocity.length()
	
	if body.has_method("get_impact_damage"):
		impact_force = body.get_impact_damage()
	elif body is RigidBody:
		impact_force = body.linear_velocity.length() * body.mass
	
	if impact_force > destruction_threshold and destruction_threshold > 0:
		take_damage(impact_force)

func take_damage(amount):
	if is_destroyed:
		return
	
	health -= amount
	accumulated_damage += amount
	
	emit_signal("damaged", amount)
	emit_signal("health_changed", health)
	
	_apply_damage_effect()
	
	if health <= 0:
		destroy()

func destroy():
	if is_destroyed:
		return
	
	is_destroyed = true
	emit_signal("destroyed")
	
	_spawn_debris()
	_spawn_destruction_effects()
	_drop_items()
	_play_destruction_sound()
	
	if respawn_time > 0:
		_hide_object()
		respawn_timer = 0.0
	else:
		queue_free()

func _spawn_debris():
	if not debris_scene:
		return
	
	for i in range(debris_count):
		var debris = debris_scene.instance()
		get_tree().current_scene.add_child(debris)
		debris.global_transform.origin = global_transform.origin + Vector3(
			rand_range(-0.5, 0.5),
			rand_range(0, 1),
			rand_range(-0.5, 0.5)
		)
		
		if debris is RigidBody:
			var explosion_dir = Vector3(
				rand_range(-1, 1),
				rand_range(0.5, 1),
				rand_range(-1, 1)
			).normalized()
			
			debris.apply_central_impulse(explosion_dir * explosion_force)
			debris.apply_torque_impulse(Vector3(
				rand_range(-10, 10),
				rand_range(-10, 10),
				rand_range(-10, 10)
			))

func _spawn_destruction_effects():
	if not destruction_particles:
		return
	
	var particles = destruction_particles.instance()
	get_tree().current_scene.add_child(particles)
	particles.global_transform.origin = global_transform.origin
	
	if particles.has_method("set_emitting"):
		particles.set_emitting(true)

func _drop_items():
	for item_data in drop_items:
		if item_data is PackedScene:
			var item = item_data.instance()
			get_tree().current_scene.add_child(item)
			item.global_transform.origin = global_transform.origin + Vector3(
				rand_range(-1, 1),
				0.5,
				rand_range(-1, 1)
			)
			
			if item is RigidBody:
				item.apply_central_impulse(Vector3(
					rand_range(-2, 2),
					rand_range(3, 5),
					rand_range(-2, 2)
				))

func _play_destruction_sound():
	if destruction_sound and audio_player:
		audio_player.stream = destruction_sound
		audio_player.play()

func _apply_damage_effect():
	if not mesh_instance:
		return
	
	var damage_ratio = 1.0 - (health / initial_health)
	
	if mesh_instance.material_override:
		var mat = mesh_instance.material_override
		if mat.has_property("albedo_color"):
			mat.albedo_color = Color(1, 1 - damage_ratio * 0.5, 1 - damage_ratio * 0.5)
	
	if damage_ratio > 0.5:
		var shake_intensity = damage_ratio * 0.1
		mesh_instance.transform.origin = Vector3(
			rand_range(-shake_intensity, shake_intensity),
			rand_range(-shake_intensity, shake_intensity),
			rand_range(-shake_intensity, shake_intensity)
		)

func _hide_object():
	visible = false
	collision_shape.disabled = true
	mode = RigidBody.MODE_STATIC

func respawn():
	is_destroyed = false
	health = initial_health
	accumulated_damage = 0.0
	respawn_timer = 0.0
	
	global_transform = original_transform
	
	visible = true
	collision_shape.disabled = false
	mode = RigidBody.MODE_RIGID
	
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	
	if mesh_instance and mesh_instance.material_override:
		var mat = mesh_instance.material_override
		if mat.has_property("albedo_color"):
			mat.albedo_color = Color.white

func repair(amount):
	if is_destroyed:
		return
	
	health = min(health + amount, initial_health)
	emit_signal("health_changed", health)
	_apply_damage_effect()

func get_health_percentage():
	return health / initial_health

func set_invulnerable(invulnerable):
	if invulnerable:
		collision_layer = 0
		collision_mask = 0
	else:
		collision_layer = 1
		collision_mask = 1