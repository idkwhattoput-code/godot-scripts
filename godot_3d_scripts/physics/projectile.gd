extends RigidBody

# Projectile Physics for Godot 3D
# Configurable projectile with various behaviors
# Supports bullets, arrows, grenades, rockets, etc.

# Projectile settings
export var initial_velocity = 50.0
export var lifetime = 5.0
export var damage = 10.0
export var explosion_radius = 0.0  # 0 means no explosion
export var gravity_multiplier = 1.0
export var air_resistance = 0.0

# Behavior flags
export var destroy_on_impact = true
export var bounce_on_impact = false
export var penetrate_objects = false
export var is_homing = false
export var homing_strength = 5.0

# Visual effects
export var trail_enabled = true
export var trail_length = 1.0
export var impact_effect_scene: PackedScene
export var explosion_effect_scene: PackedScene

# Audio
export var launch_sound: AudioStream
export var impact_sound: AudioStream
export var flight_sound: AudioStream

# Internal variables
var velocity: Vector3
var lifetime_timer = 0.0
var target: Spatial = null
var has_impacted = false
var trail_points = []
var penetration_count = 0
var max_penetrations = 3

# Components
onready var mesh_instance = $MeshInstance if has_node("MeshInstance") else null
onready var collision_shape = $CollisionShape if has_node("CollisionShape") else null
onready var audio_player = $AudioStreamPlayer3D if has_node("AudioStreamPlayer3D") else null
onready var trail_particles = $TrailParticles if has_node("TrailParticles") else null
onready var area_detector = $Area if has_node("Area") else null

func _ready():
	# Setup physics
	set_as_toplevel(true)
	gravity_scale = gravity_multiplier
	
	# Setup collision
	contact_monitor = true
	contacts_reported = 10
	connect("body_entered", self, "_on_body_entered")
	
	# Setup area for explosion detection
	if explosion_radius > 0 and not area_detector:
		create_explosion_area()
	
	# Play launch sound
	if launch_sound and audio_player:
		audio_player.stream = launch_sound
		audio_player.play()
	
	# Start flight sound
	if flight_sound and audio_player:
		yield(get_tree().create_timer(0.1), "timeout")
		audio_player.stream = flight_sound
		audio_player.play()

func launch(direction: Vector3, additional_velocity: Vector3 = Vector3.ZERO):
	"""Launch the projectile in a direction"""
	velocity = direction.normalized() * initial_velocity + additional_velocity
	linear_velocity = velocity
	
	# Orient projectile to face direction
	look_at(global_transform.origin + direction, Vector3.UP)

func set_homing_target(new_target: Spatial):
	"""Set a target for homing projectiles"""
	target = new_target
	is_homing = true

func _physics_process(delta):
	# Lifetime management
	lifetime_timer += delta
	if lifetime_timer >= lifetime:
		destroy()
		return
	
	# Apply air resistance
	if air_resistance > 0:
		linear_velocity *= 1.0 - (air_resistance * delta)
	
	# Homing behavior
	if is_homing and is_instance_valid(target):
		apply_homing(delta)
	
	# Update trail
	if trail_enabled:
		update_trail()
	
	# Orient to velocity direction
	if linear_velocity.length() > 0.1:
		look_at(global_transform.origin + linear_velocity.normalized(), Vector3.UP)

func apply_homing(delta):
	"""Apply homing behavior to track target"""
	var target_direction = (target.global_transform.origin - global_transform.origin).normalized()
	var current_direction = linear_velocity.normalized()
	
	# Smoothly rotate towards target
	var new_direction = current_direction.linear_interpolate(target_direction, homing_strength * delta)
	linear_velocity = new_direction * linear_velocity.length()

func _on_body_entered(body):
	"""Handle collision with bodies"""
	if has_impacted and not penetrate_objects:
		return
	
	# Don't collide with owner
	if body == get_owner():
		return
	
	# Handle impact
	on_impact(body)

func on_impact(body):
	"""Handle projectile impact"""
	has_impacted = true
	
	# Apply damage
	if body.has_method("take_damage"):
		body.take_damage(damage, global_transform.origin, -transform.basis.z)
	
	# Play impact sound
	if impact_sound and audio_player:
		audio_player.stream = impact_sound
		audio_player.play()
	
	# Spawn impact effect
	if impact_effect_scene:
		spawn_effect(impact_effect_scene, global_transform.origin)
	
	# Handle explosion
	if explosion_radius > 0:
		explode()
	
	# Handle penetration
	if penetrate_objects:
		penetration_count += 1
		if penetration_count >= max_penetrations:
			destroy()
		else:
			# Reduce velocity after penetration
			linear_velocity *= 0.7
			has_impacted = false
	elif bounce_on_impact:
		# Bounce logic handled by physics engine
		has_impacted = false
	elif destroy_on_impact:
		destroy()

func explode():
	"""Create explosion effect"""
	# Spawn explosion effect
	if explosion_effect_scene:
		spawn_effect(explosion_effect_scene, global_transform.origin)
	
	# Apply explosion damage
	var bodies = []
	if area_detector:
		bodies = area_detector.get_overlapping_bodies()
	else:
		# Fallback: use physics query
		var space_state = get_world().direct_space_state
		var shape = SphereShape.new()
		shape.radius = explosion_radius
		var query = PhysicsShapeQueryParameters.new()
		query.set_shape(shape)
		query.transform.origin = global_transform.origin
		var results = space_state.intersect_shape(query)
		for result in results:
			bodies.append(result.collider)
	
	# Apply damage to all bodies in explosion radius
	for body in bodies:
		if body != self and body.has_method("take_explosion_damage"):
			var distance = body.global_transform.origin.distance_to(global_transform.origin)
			var damage_falloff = 1.0 - (distance / explosion_radius)
			var explosion_damage = damage * damage_falloff
			var direction = (body.global_transform.origin - global_transform.origin).normalized()
			body.take_explosion_damage(explosion_damage, global_transform.origin, direction)

func create_explosion_area():
	"""Create area for explosion detection"""
	area_detector = Area.new()
	add_child(area_detector)
	
	var sphere_shape = SphereShape.new()
	sphere_shape.radius = explosion_radius
	
	var collision_shape = CollisionShape.new()
	collision_shape.shape = sphere_shape
	area_detector.add_child(collision_shape)

func update_trail():
	"""Update trail effect"""
	# Add current position to trail
	trail_points.append(global_transform.origin)
	
	# Limit trail length
	while trail_points.size() > trail_length * 10:
		trail_points.pop_front()
	
	# Update trail visual (implement based on your trail system)
	if trail_particles:
		trail_particles.emitting = linear_velocity.length() > 1.0

func spawn_effect(effect_scene: PackedScene, position: Vector3):
	"""Spawn a visual effect"""
	if not effect_scene:
		return
	
	var effect = effect_scene.instance()
	get_tree().current_scene.add_child(effect)
	effect.global_transform.origin = position
	
	# Auto-destroy effect after time
	if effect.has_method("set_emitting"):
		effect.set_emitting(true)
	yield(get_tree().create_timer(5.0), "timeout")
	if is_instance_valid(effect):
		effect.queue_free()

func destroy():
	"""Destroy the projectile"""
	# Stop all particles
	if trail_particles:
		trail_particles.emitting = false
	
	# Wait for audio to finish
	if audio_player and audio_player.playing:
		hide()
		collision_shape.disabled = true
		yield(audio_player, "finished")
	
	queue_free()

# Projectile factory methods
static func create_bullet(scene: PackedScene, origin: Vector3, direction: Vector3) -> RigidBody:
	"""Create a standard bullet projectile"""
	var bullet = scene.instance()
	bullet.global_transform.origin = origin
	bullet.launch(direction)
	return bullet

static func create_grenade(scene: PackedScene, origin: Vector3, direction: Vector3, force: float) -> RigidBody:
	"""Create a grenade projectile with arc"""
	var grenade = scene.instance()
	grenade.global_transform.origin = origin
	grenade.bounce_on_impact = true
	grenade.destroy_on_impact = false
	grenade.explosion_radius = 5.0
	grenade.gravity_multiplier = 1.0
	
	# Calculate launch velocity for arc
	var launch_direction = direction.normalized()
	launch_direction.y += 0.5  # Add upward component
	grenade.launch(launch_direction, Vector3.ZERO)
	
	return grenade