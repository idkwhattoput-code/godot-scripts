extends Particles

# Advanced Fire Particle System for Godot 3D
# Creates realistic fire with smoke, embers, and heat distortion
# Can be used for campfires, torches, explosions, etc.

# Fire parameters
export var fire_size = 1.0
export var fire_height = 2.0
export var fire_intensity = 1.0
export var fire_color = Color(1.0, 0.4, 0.0)
export var fire_inner_color = Color(1.0, 0.8, 0.0)

# Behavior settings
export var wind_strength = 0.0
export var wind_direction = Vector3(1, 0, 0)
export var turbulence = 0.5
export var flicker_amount = 0.2
export var spread_over_time = false
export var burn_duration = -1.0  # -1 for infinite

# Components
export var enable_smoke = true
export var enable_embers = true
export var enable_light = true
export var enable_heat_distortion = true
export var enable_sound = true

# Damage settings
export var deals_damage = true
export var damage_per_second = 5.0
export var damage_radius = 2.0

# Internal variables
var base_amount: int
var time_alive = 0.0
var is_extinguishing = false
var flicker_timer = 0.0

# Child components
onready var smoke_particles = $SmokeParticles if has_node("SmokeParticles") else null
onready var ember_particles = $EmberParticles if has_node("EmberParticles") else null
onready var fire_light = $OmniLight if has_node("OmniLight") else null
onready var damage_area = $DamageArea if has_node("DamageArea") else null
onready var audio_player = $AudioStreamPlayer3D if has_node("AudioStreamPlayer3D") else null

func _ready():
	# Setup main fire particles
	setup_fire_particles()
	
	# Setup child systems
	if enable_smoke:
		setup_smoke_particles()
	
	if enable_embers:
		setup_ember_particles()
	
	if enable_light:
		setup_light()
	
	if deals_damage:
		setup_damage_area()
	
	if enable_sound:
		setup_audio()
	
	# Store base amount for flicker
	base_amount = amount

func setup_fire_particles():
	"""Configure main fire particle system"""
	emitting = true
	amount = int(50 * fire_size)
	lifetime = 0.5 + fire_height * 0.2
	
	# Process material
	if not process_material:
		process_material = ParticlesMaterial.new()
	
	var mat = process_material as ParticlesMaterial
	
	# Emission shape
	mat.emission_shape = ParticlesMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.2 * fire_size
	
	# Velocity
	mat.initial_velocity = fire_height * 2.0
	mat.initial_velocity_random = 0.3
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 20.0
	
	# Acceleration (wind effect)
	mat.gravity = Vector3(0, -2.0, 0) + wind_direction * wind_strength
	
	# Scale
	mat.scale = fire_size
	mat.scale_random = 0.3
	mat.scale_curve = create_fire_scale_curve()
	
	# Color
	mat.color = fire_color
	mat.color_ramp = create_fire_color_ramp()
	
	# Angular velocity for turbulence
	mat.angular_velocity = 360.0 * turbulence
	mat.angular_velocity_random = 0.5
	
	# Damping for more realistic movement
	mat.damping = 2.0

func setup_smoke_particles():
	"""Create smoke particle system"""
	if not smoke_particles:
		smoke_particles = Particles.new()
		add_child(smoke_particles)
		smoke_particles.name = "SmokeParticles"
	
	smoke_particles.emitting = true
	smoke_particles.amount = int(30 * fire_size)
	smoke_particles.lifetime = 3.0
	smoke_particles.translation.y = fire_height * 0.5
	
	var smoke_mat = ParticlesMaterial.new()
	smoke_particles.process_material = smoke_mat
	
	# Smoke properties
	smoke_mat.emission_shape = ParticlesMaterial.EMISSION_SHAPE_SPHERE
	smoke_mat.emission_sphere_radius = 0.5 * fire_size
	smoke_mat.initial_velocity = 2.0
	smoke_mat.direction = Vector3(0, 1, 0)
	smoke_mat.spread = 30.0
	smoke_mat.gravity = Vector3(0, 0.5, 0) + wind_direction * wind_strength * 0.5
	smoke_mat.scale = fire_size * 2.0
	smoke_mat.scale_curve = create_smoke_scale_curve()
	smoke_mat.color_ramp = create_smoke_color_ramp()

func setup_ember_particles():
	"""Create ember particle system"""
	if not ember_particles:
		ember_particles = Particles.new()
		add_child(ember_particles)
		ember_particles.name = "EmberParticles"
	
	ember_particles.emitting = true
	ember_particles.amount = int(20 * fire_size)
	ember_particles.lifetime = 2.0
	
	var ember_mat = ParticlesMaterial.new()
	ember_particles.process_material = ember_mat
	
	# Ember properties
	ember_mat.emission_shape = ParticlesMaterial.EMISSION_SHAPE_SPHERE
	ember_mat.emission_sphere_radius = 0.3 * fire_size
	ember_mat.initial_velocity = fire_height * 3.0
	ember_mat.initial_velocity_random = 0.5
	ember_mat.direction = Vector3(0, 1, 0)
	ember_mat.spread = 45.0
	ember_mat.gravity = Vector3(0, -5.0, 0) + wind_direction * wind_strength * 2.0
	ember_mat.scale = 0.1 * fire_size
	ember_mat.scale_random = 0.5
	ember_mat.color = Color(1.0, 0.3, 0.0)
	ember_mat.emission_box_extents = Vector3(fire_size * 0.5, 0, fire_size * 0.5)

func setup_light():
	"""Create dynamic light for fire"""
	if not fire_light:
		fire_light = OmniLight.new()
		add_child(fire_light)
		fire_light.name = "OmniLight"
	
	fire_light.translation.y = fire_height * 0.3
	fire_light.light_energy = fire_intensity
	fire_light.light_color = fire_color
	fire_light.omni_range = 5.0 * fire_size
	fire_light.omni_attenuation = 2.0
	
	# Shadow settings
	fire_light.shadow_enabled = true
	fire_light.shadow_bias = 0.1

func setup_damage_area():
	"""Create area for damage detection"""
	if not damage_area:
		damage_area = Area.new()
		add_child(damage_area)
		damage_area.name = "DamageArea"
		
		var collision_shape = CollisionShape.new()
		var sphere = SphereShape.new()
		sphere.radius = damage_radius
		collision_shape.shape = sphere
		damage_area.add_child(collision_shape)
	
	damage_area.connect("body_entered", self, "_on_body_entered_damage_area")
	damage_area.connect("body_exited", self, "_on_body_exited_damage_area")

func setup_audio():
	"""Setup fire sound effects"""
	if not audio_player:
		audio_player = AudioStreamPlayer3D.new()
		add_child(audio_player)
		audio_player.name = "AudioStreamPlayer3D"
	
	# Set fire sound (you'll need to assign an AudioStream resource)
	# audio_player.stream = preload("res://sounds/fire_loop.ogg")
	audio_player.unit_size = 10.0
	audio_player.max_distance = 50.0
	audio_player.play()

func _process(delta):
	time_alive += delta
	
	# Handle burn duration
	if burn_duration > 0 and time_alive >= burn_duration:
		extinguish()
	
	# Update effects
	if not is_extinguishing:
		update_flicker(delta)
		update_spread()
	
	# Process damage
	if deals_damage and damage_area:
		process_damage(delta)

func update_flicker(delta):
	"""Create realistic fire flicker"""
	flicker_timer += delta * 10.0
	
	var flicker = sin(flicker_timer) * 0.5 + sin(flicker_timer * 2.3) * 0.3 + sin(flicker_timer * 5.7) * 0.2
	flicker *= flicker_amount
	
	# Apply flicker to particle amount
	amount = int(base_amount * (1.0 + flicker * 0.2))
	
	# Apply flicker to light
	if fire_light:
		fire_light.light_energy = fire_intensity * (1.0 + flicker)
		
		# Slight color variation
		var color_variation = 0.1 * flicker
		fire_light.light_color = fire_color * (1.0 + color_variation)

func update_spread():
	"""Handle fire spreading over time"""
	if not spread_over_time:
		return
	
	var spread_factor = min(time_alive / 5.0, 1.0)
	var current_size = fire_size * spread_factor
	
	# Update emission radius
	var mat = process_material as ParticlesMaterial
	mat.emission_sphere_radius = 0.2 * current_size
	
	# Update other systems
	if smoke_particles:
		var smoke_mat = smoke_particles.process_material as ParticlesMaterial
		smoke_mat.emission_sphere_radius = 0.5 * current_size
	
	if damage_area:
		var shape = damage_area.get_child(0).shape as SphereShape
		shape.radius = damage_radius * spread_factor

var bodies_in_damage_area = []

func _on_body_entered_damage_area(body):
	if body.has_method("can_burn") and body.can_burn():
		bodies_in_damage_area.append(body)

func _on_body_exited_damage_area(body):
	bodies_in_damage_area.erase(body)

func process_damage(delta):
	"""Apply fire damage to bodies in area"""
	for body in bodies_in_damage_area:
		if body.has_method("take_fire_damage"):
			body.take_fire_damage(damage_per_second * delta, global_transform.origin)

func extinguish():
	"""Extinguish the fire"""
	is_extinguishing = true
	
	# Fade out particles
	emitting = false
	if smoke_particles:
		smoke_particles.emitting = false
	if ember_particles:
		ember_particles.emitting = false
	
	# Fade out light
	if fire_light:
		var tween = create_tween()
		tween.tween_property(fire_light, "light_energy", 0.0, 2.0)
	
	# Stop audio
	if audio_player:
		var tween = create_tween()
		tween.tween_property(audio_player, "volume_db", -80.0, 2.0)
		tween.tween_callback(audio_player, "stop")
	
	# Queue free after particles die
	yield(get_tree().create_timer(lifetime + 3.0), "timeout")
	queue_free()

func reignite():
	"""Reignite an extinguished fire"""
	is_extinguishing = false
	time_alive = 0.0
	
	emitting = true
	if smoke_particles:
		smoke_particles.emitting = true
	if ember_particles:
		ember_particles.emitting = true
	
	if fire_light:
		fire_light.light_energy = fire_intensity
	
	if audio_player:
		audio_player.volume_db = 0.0
		audio_player.play()

# Helper functions to create curves and gradients
func create_fire_scale_curve() -> Curve:
	var curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(0.8, 0.7))
	curve.add_point(Vector2(1.0, 0.0))
	return curve

func create_fire_color_ramp() -> Gradient:
	var gradient = Gradient.new()
	gradient.add_point(0.0, fire_inner_color)
	gradient.add_point(0.3, fire_color)
	gradient.add_point(0.7, Color(0.3, 0.0, 0.0))
	gradient.add_point(1.0, Color(0.1, 0.0, 0.0, 0.0))
	return gradient

func create_smoke_scale_curve() -> Curve:
	var curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1.0, 2.0))
	return curve

func create_smoke_color_ramp() -> Gradient:
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.2, 0.2, 0.2, 0.3))
	gradient.add_point(0.5, Color(0.1, 0.1, 0.1, 0.5))
	gradient.add_point(1.0, Color(0.05, 0.05, 0.05, 0.0))
	return gradient