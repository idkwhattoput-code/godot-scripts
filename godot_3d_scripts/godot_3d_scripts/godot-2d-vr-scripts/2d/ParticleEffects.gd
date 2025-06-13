extends Node2D

class_name ParticleEffects

enum EffectType {
	EXPLOSION,
	SMOKE,
	SPARKLES,
	FIRE,
	RAIN,
	BLOOD,
	MAGIC,
	DUST
}

@export var auto_start: bool = false
@export var effect_type: EffectType = EffectType.EXPLOSION
@export var particle_count: int = 100
@export var effect_duration: float = 2.0
@export var effect_scale: float = 1.0

@onready var particle_system: GPUParticles2D = $GPUParticles2D
@onready var additional_particles: GPUParticles2D = $AdditionalParticles

signal effect_started()
signal effect_finished()

func _ready():
	setup_particle_system()
	if auto_start:
		play_effect()

func setup_particle_system():
	if not particle_system:
		particle_system = GPUParticles2D.new()
		add_child(particle_system)
	
	if not additional_particles:
		additional_particles = GPUParticles2D.new()
		add_child(additional_particles)
	
	particle_system.finished.connect(_on_effect_finished)
	configure_effect(effect_type)

func configure_effect(type: EffectType):
	var material = ParticleProcessMaterial.new()
	
	match type:
		EffectType.EXPLOSION:
			setup_explosion_effect(material)
		EffectType.SMOKE:
			setup_smoke_effect(material)
		EffectType.SPARKLES:
			setup_sparkles_effect(material)
		EffectType.FIRE:
			setup_fire_effect(material)
		EffectType.RAIN:
			setup_rain_effect(material)
		EffectType.BLOOD:
			setup_blood_effect(material)
		EffectType.MAGIC:
			setup_magic_effect(material)
		EffectType.DUST:
			setup_dust_effect(material)
	
	particle_system.process_material = material
	particle_system.amount = particle_count
	particle_system.lifetime = effect_duration
	particle_system.scale = Vector2(effect_scale, effect_scale)

func setup_explosion_effect(material: ParticleProcessMaterial):
	material.direction = Vector3(0, -1, 0)
	material.initial_velocity_min = 200.0
	material.initial_velocity_max = 400.0
	material.angular_velocity_min = -180.0
	material.angular_velocity_max = 180.0
	material.gravity = Vector3(0, 98, 0)
	material.scale_min = 0.5
	material.scale_max = 1.5
	
	var color_ramp = Gradient.new()
	color_ramp.add_point(0.0, Color.YELLOW)
	color_ramp.add_point(0.3, Color.ORANGE)
	color_ramp.add_point(0.7, Color.RED)
	color_ramp.add_point(1.0, Color.TRANSPARENT)
	
	material.color_ramp = color_ramp
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE

func setup_smoke_effect(material: ParticleProcessMaterial):
	material.direction = Vector3(0, -1, 0)
	material.initial_velocity_min = 20.0
	material.initial_velocity_max = 50.0
	material.gravity = Vector3(0, -30, 0)
	material.scale_min = 1.0
	material.scale_max = 3.0
	material.scale_over_velocity_min = 0.0
	material.scale_over_velocity_max = 1.2
	
	var color_ramp = Gradient.new()
	color_ramp.add_point(0.0, Color(0.8, 0.8, 0.8, 1.0))
	color_ramp.add_point(0.5, Color(0.6, 0.6, 0.6, 0.7))
	color_ramp.add_point(1.0, Color(0.4, 0.4, 0.4, 0.0))
	
	material.color_ramp = color_ramp

func setup_sparkles_effect(material: ParticleProcessMaterial):
	material.direction = Vector3(0, 0, 0)
	material.initial_velocity_min = 10.0
	material.initial_velocity_max = 80.0
	material.gravity = Vector3(0, 50, 0)
	material.angular_velocity_min = -360.0
	material.angular_velocity_max = 360.0
	material.scale_min = 0.2
	material.scale_max = 0.8
	
	var color_ramp = Gradient.new()
	color_ramp.add_point(0.0, Color.WHITE)
	color_ramp.add_point(0.3, Color.YELLOW)
	color_ramp.add_point(0.6, Color.CYAN)
	color_ramp.add_point(1.0, Color.TRANSPARENT)
	
	material.color_ramp = color_ramp
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE

func setup_fire_effect(material: ParticleProcessMaterial):
	material.direction = Vector3(0, -1, 0)
	material.initial_velocity_min = 30.0
	material.initial_velocity_max = 70.0
	material.gravity = Vector3(0, -20, 0)
	material.scale_min = 0.5
	material.scale_max = 1.2
	
	var color_ramp = Gradient.new()
	color_ramp.add_point(0.0, Color.RED)
	color_ramp.add_point(0.4, Color.ORANGE)
	color_ramp.add_point(0.8, Color.YELLOW)
	color_ramp.add_point(1.0, Color.TRANSPARENT)
	
	material.color_ramp = color_ramp

func setup_rain_effect(material: ParticleProcessMaterial):
	material.direction = Vector3(0, 1, 0)
	material.initial_velocity_min = 300.0
	material.initial_velocity_max = 400.0
	material.gravity = Vector3(0, 500, 0)
	material.scale_min = 0.1
	material.scale_max = 0.3
	
	material.color = Color(0.7, 0.9, 1.0, 0.8)
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX

func setup_blood_effect(material: ParticleProcessMaterial):
	material.direction = Vector3(0, -1, 0)
	material.initial_velocity_min = 80.0
	material.initial_velocity_max = 150.0
	material.gravity = Vector3(0, 200, 0)
	material.scale_min = 0.3
	material.scale_max = 0.8
	
	var color_ramp = Gradient.new()
	color_ramp.add_point(0.0, Color.DARK_RED)
	color_ramp.add_point(0.5, Color.RED)
	color_ramp.add_point(1.0, Color(0.3, 0.0, 0.0, 0.0))
	
	material.color_ramp = color_ramp

func setup_magic_effect(material: ParticleProcessMaterial):
	material.direction = Vector3(0, 0, 0)
	material.initial_velocity_min = 20.0
	material.initial_velocity_max = 100.0
	material.gravity = Vector3(0, -30, 0)
	material.angular_velocity_min = -180.0
	material.angular_velocity_max = 180.0
	material.scale_min = 0.3
	material.scale_max = 1.0
	
	var color_ramp = Gradient.new()
	color_ramp.add_point(0.0, Color.MAGENTA)
	color_ramp.add_point(0.3, Color.CYAN)
	color_ramp.add_point(0.6, Color.BLUE)
	color_ramp.add_point(1.0, Color.TRANSPARENT)
	
	material.color_ramp = color_ramp
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE

func setup_dust_effect(material: ParticleProcessMaterial):
	material.direction = Vector3(0, -1, 0)
	material.initial_velocity_min = 10.0
	material.initial_velocity_max = 30.0
	material.gravity = Vector3(0, 20, 0)
	material.scale_min = 0.5
	material.scale_max = 1.5
	
	var color_ramp = Gradient.new()
	color_ramp.add_point(0.0, Color(0.8, 0.7, 0.5, 0.8))
	color_ramp.add_point(0.5, Color(0.6, 0.5, 0.3, 0.5))
	color_ramp.add_point(1.0, Color(0.4, 0.3, 0.2, 0.0))
	
	material.color_ramp = color_ramp

func play_effect(type: EffectType = effect_type):
	effect_type = type
	configure_effect(type)
	particle_system.restart()
	particle_system.emitting = true
	effect_started.emit()

func stop_effect():
	particle_system.emitting = false

func play_custom_effect(custom_material: ParticleProcessMaterial):
	particle_system.process_material = custom_material
	particle_system.restart()
	particle_system.emitting = true
	effect_started.emit()

func create_explosion_at(pos: Vector2, scale: float = 1.0):
	global_position = pos
	effect_scale = scale
	play_effect(EffectType.EXPLOSION)

func create_pickup_effect(pos: Vector2):
	global_position = pos
	play_effect(EffectType.SPARKLES)

func create_impact_effect(pos: Vector2, effect: EffectType = EffectType.DUST):
	global_position = pos
	play_effect(effect)

func create_trail_effect(start_pos: Vector2, end_pos: Vector2):
	global_position = start_pos
	var direction = (end_pos - start_pos).normalized()
	
	var material = ParticleProcessMaterial.new()
	material.direction = Vector3(direction.x, direction.y, 0)
	material.initial_velocity_min = 50.0
	material.initial_velocity_max = 100.0
	material.scale_min = 0.2
	material.scale_max = 0.6
	
	play_custom_effect(material)

func burst_effect(burst_count: int = 3, delay: float = 0.1):
	for i in range(burst_count):
		particle_system.restart()
		particle_system.emitting = true
		await get_tree().create_timer(delay).timeout

func _on_effect_finished():
	effect_finished.emit()

static func create_particle_effect(scene: Node, effect_type: EffectType, position: Vector2, duration: float = 2.0) -> ParticleEffects:
	var effect = preload("res://path/to/ParticleEffects.tscn").instantiate() as ParticleEffects
	scene.add_child(effect)
	effect.global_position = position
	effect.effect_type = effect_type
	effect.effect_duration = duration
	effect.play_effect()
	
	effect.effect_finished.connect(effect.queue_free)
	return effect