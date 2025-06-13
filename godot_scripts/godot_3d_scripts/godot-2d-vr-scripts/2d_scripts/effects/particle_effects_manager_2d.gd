extends Node2D

var particle_pool: Dictionary = {}
var active_particles: Array = []
var effect_templates: Dictionary = {}

export var max_pool_size: int = 50
export var auto_cleanup: bool = true
export var cleanup_time: float = 5.0

signal effect_spawned(effect_name, position)
signal effect_finished(effect_name)

func _ready() -> void:
	set_process(true)
	initialize_effect_templates()

func initialize_effect_templates() -> void:
	effect_templates = {
		"explosion": {
			"emitting": true,
			"amount": 50,
			"lifetime": 1.0,
			"speed_scale": 2.0,
			"explosiveness": 1.0,
			"texture": null,
			"spread": 45.0,
			"initial_velocity": 300.0,
			"angular_velocity": 720.0,
			"damping": 100.0,
			"scale_amount": 2.0,
			"color_ramp": null
		},
		"smoke": {
			"emitting": true,
			"amount": 20,
			"lifetime": 3.0,
			"speed_scale": 0.5,
			"explosiveness": 0.0,
			"texture": null,
			"spread": 30.0,
			"initial_velocity": 50.0,
			"gravity": Vector2(0, -100),
			"scale_amount": 3.0,
			"color": Color(0.5, 0.5, 0.5, 0.8)
		},
		"sparkle": {
			"emitting": true,
			"amount": 30,
			"lifetime": 2.0,
			"speed_scale": 1.0,
			"explosiveness": 0.0,
			"texture": null,
			"spread": 360.0,
			"initial_velocity": 100.0,
			"damping": 50.0,
			"scale_amount": 0.5,
			"color": Color(1.0, 1.0, 0.0, 1.0)
		},
		"blood": {
			"emitting": true,
			"amount": 15,
			"lifetime": 1.5,
			"speed_scale": 1.5,
			"explosiveness": 0.8,
			"texture": null,
			"spread": 30.0,
			"initial_velocity": 200.0,
			"gravity": Vector2(0, 980),
			"damping": 50.0,
			"scale_amount": 1.0,
			"color": Color(0.8, 0.0, 0.0, 1.0)
		},
		"fire": {
			"emitting": true,
			"amount": 40,
			"lifetime": 1.5,
			"speed_scale": 1.0,
			"explosiveness": 0.0,
			"texture": null,
			"spread": 20.0,
			"initial_velocity": 100.0,
			"gravity": Vector2(0, -200),
			"scale_amount": 1.5,
			"color": Color(1.0, 0.5, 0.0, 1.0)
		}
	}

func spawn_effect(effect_name: String, position: Vector2, rotation: float = 0.0, custom_params: Dictionary = {}) -> CPUParticles2D:
	var particle_instance = get_particle_from_pool(effect_name)
	
	if not particle_instance:
		particle_instance = create_particle_instance()
	
	setup_particle(particle_instance, effect_name, custom_params)
	
	particle_instance.global_position = position
	particle_instance.rotation = rotation
	particle_instance.restart()
	particle_instance.emitting = true
	
	active_particles.append({
		"instance": particle_instance,
		"spawn_time": OS.get_unix_time(),
		"effect_name": effect_name
	})
	
	emit_signal("effect_spawned", effect_name, position)
	
	return particle_instance

func create_particle_instance() -> CPUParticles2D:
	var particles = CPUParticles2D.new()
	add_child(particles)
	return particles

func setup_particle(particle: CPUParticles2D, effect_name: String, custom_params: Dictionary) -> void:
	if not effect_templates.has(effect_name):
		push_warning("Effect template '%s' not found!" % effect_name)
		return
	
	var template = effect_templates[effect_name].duplicate()
	
	for key in custom_params:
		template[key] = custom_params[key]
	
	for property in template:
		if particle.get(property) != null:
			particle.set(property, template[property])

func get_particle_from_pool(effect_name: String) -> CPUParticles2D:
	if not particle_pool.has(effect_name):
		particle_pool[effect_name] = []
	
	var pool = particle_pool[effect_name]
	
	for particle in pool:
		if particle and not particle.emitting:
			pool.erase(particle)
			return particle
	
	if pool.size() < max_pool_size:
		return null
	
	var oldest_particle = pool[0]
	pool.remove(0)
	return oldest_particle

func return_to_pool(particle: CPUParticles2D, effect_name: String) -> void:
	particle.emitting = false
	particle.visible = false
	
	if not particle_pool.has(effect_name):
		particle_pool[effect_name] = []
	
	particle_pool[effect_name].append(particle)

func _process(_delta: float) -> void:
	if not auto_cleanup:
		return
	
	var current_time = OS.get_unix_time()
	var particles_to_remove = []
	
	for particle_data in active_particles:
		var particle = particle_data["instance"]
		var spawn_time = particle_data["spawn_time"]
		var effect_name = particle_data["effect_name"]
		
		if not particle.emitting or current_time - spawn_time > cleanup_time:
			particles_to_remove.append(particle_data)
			return_to_pool(particle, effect_name)
			emit_signal("effect_finished", effect_name)
	
	for particle_data in particles_to_remove:
		active_particles.erase(particle_data)

func spawn_burst(effect_name: String, position: Vector2, count: int = 5, spread: float = 50.0) -> void:
	for i in range(count):
		var offset = Vector2(
			rand_range(-spread, spread),
			rand_range(-spread, spread)
		)
		spawn_effect(effect_name, position + offset)

func spawn_trail(effect_name: String, start_pos: Vector2, end_pos: Vector2, count: int = 10) -> void:
	for i in range(count):
		var t = float(i) / float(count - 1)
		var pos = start_pos.linear_interpolate(end_pos, t)
		spawn_effect(effect_name, pos)

func spawn_circle(effect_name: String, center: Vector2, radius: float, count: int = 8) -> void:
	for i in range(count):
		var angle = (i * TAU) / count
		var pos = center + Vector2(cos(angle), sin(angle)) * radius
		spawn_effect(effect_name, pos, angle)

func add_effect_template(name: String, properties: Dictionary) -> void:
	effect_templates[name] = properties

func clear_all_effects() -> void:
	for particle_data in active_particles:
		var particle = particle_data["instance"]
		particle.emitting = false
		particle.queue_free()
	
	active_particles.clear()
	
	for effect_name in particle_pool:
		for particle in particle_pool[effect_name]:
			particle.queue_free()
	
	particle_pool.clear()

func get_active_effect_count() -> int:
	return active_particles.size()

func set_effect_texture(effect_name: String, texture: Texture) -> void:
	if effect_templates.has(effect_name):
		effect_templates[effect_name]["texture"] = texture