extends Node

class_name ParticleEffectsManager

signal effect_spawned(effect_name, position)
signal effect_finished(effect_instance)

var effect_pools: Dictionary = {}
var active_effects: Array = []
var effect_scenes: Dictionary = {}
var effect_settings: Dictionary = {}

export var max_pool_size: int = 50
export var default_effect_lifetime: float = 3.0
export var auto_cleanup: bool = true
export var cleanup_interval: float = 5.0

var cleanup_timer: float = 0.0

func _ready():
	set_process(auto_cleanup)
	load_default_effects()

func _process(delta):
	if auto_cleanup:
		cleanup_timer += delta
		if cleanup_timer >= cleanup_interval:
			cleanup_timer = 0.0
			cleanup_finished_effects()

func load_default_effects():
	effect_settings = {
		"explosion": {
			"pool_size": 20,
			"lifetime": 2.0,
			"one_shot": true,
			"auto_destroy": true
		},
		"smoke": {
			"pool_size": 30,
			"lifetime": 5.0,
			"one_shot": false,
			"auto_destroy": false
		},
		"fire": {
			"pool_size": 15,
			"lifetime": 0.0,
			"one_shot": false,
			"auto_destroy": false
		},
		"sparks": {
			"pool_size": 40,
			"lifetime": 1.5,
			"one_shot": true,
			"auto_destroy": true
		},
		"magic_cast": {
			"pool_size": 25,
			"lifetime": 1.0,
			"one_shot": true,
			"auto_destroy": true
		},
		"blood_splatter": {
			"pool_size": 30,
			"lifetime": 3.0,
			"one_shot": true,
			"auto_destroy": false
		},
		"dust": {
			"pool_size": 35,
			"lifetime": 2.0,
			"one_shot": true,
			"auto_destroy": true
		},
		"water_splash": {
			"pool_size": 20,
			"lifetime": 1.5,
			"one_shot": true,
			"auto_destroy": true
		},
		"heal": {
			"pool_size": 15,
			"lifetime": 2.0,
			"one_shot": true,
			"auto_destroy": true
		},
		"level_up": {
			"pool_size": 10,
			"lifetime": 3.0,
			"one_shot": true,
			"auto_destroy": true
		}
	}

func register_effect(effect_name: String, scene_path: String, settings: Dictionary = {}):
	var scene = load(scene_path)
	if scene:
		effect_scenes[effect_name] = scene
		effect_settings[effect_name] = settings
		create_pool(effect_name, settings.get("pool_size", 10))

func create_pool(effect_name: String, pool_size: int):
	if not effect_name in effect_scenes:
		push_error("Effect scene not registered: " + effect_name)
		return
	
	effect_pools[effect_name] = []
	
	for i in range(pool_size):
		var instance = effect_scenes[effect_name].instance()
		instance.visible = false
		instance.set_process(false)
		instance.set_physics_process(false)
		if instance.has_method("set_emitting"):
			instance.set_emitting(false)
		add_child(instance)
		effect_pools[effect_name].append({
			"instance": instance,
			"in_use": false,
			"lifetime_timer": 0.0
		})

func spawn_effect(effect_name: String, global_position: Vector3, rotation: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> Spatial:
	if not effect_name in effect_pools:
		push_error("Effect not registered: " + effect_name)
		return null
	
	var effect_data = get_available_effect(effect_name)
	if not effect_data:
		effect_data = expand_pool(effect_name)
		if not effect_data:
			push_warning("No available effects in pool: " + effect_name)
			return null
	
	var instance = effect_data.instance
	effect_data.in_use = true
	effect_data.lifetime_timer = 0.0
	
	instance.global_transform.origin = global_position
	instance.rotation = rotation
	instance.scale = scale
	instance.visible = true
	instance.set_process(true)
	instance.set_physics_process(true)
	
	if instance.has_method("set_emitting"):
		instance.set_emitting(true)
	
	if instance.has_method("restart"):
		instance.restart()
	
	active_effects.append({
		"name": effect_name,
		"data": effect_data,
		"settings": effect_settings.get(effect_name, {})
	})
	
	emit_signal("effect_spawned", effect_name, global_position)
	
	return instance

func spawn_effect_attached(effect_name: String, parent: Spatial, local_position: Vector3 = Vector3.ZERO, local_rotation: Vector3 = Vector3.ZERO) -> Spatial:
	var instance = spawn_effect(effect_name, parent.global_transform.origin + local_position, local_rotation)
	if instance and parent:
		remove_child(instance)
		parent.add_child(instance)
		instance.transform.origin = local_position
		instance.rotation = local_rotation
	return instance

func get_available_effect(effect_name: String) -> Dictionary:
	if not effect_name in effect_pools:
		return {}
	
	for effect_data in effect_pools[effect_name]:
		if not effect_data.in_use:
			return effect_data
	
	return {}

func expand_pool(effect_name: String) -> Dictionary:
	if not effect_name in effect_scenes:
		return {}
	
	var current_size = effect_pools[effect_name].size()
	if current_size >= max_pool_size:
		return {}
	
	var instance = effect_scenes[effect_name].instance()
	instance.visible = false
	instance.set_process(false)
	instance.set_physics_process(false)
	if instance.has_method("set_emitting"):
		instance.set_emitting(false)
	add_child(instance)
	
	var effect_data = {
		"instance": instance,
		"in_use": false,
		"lifetime_timer": 0.0
	}
	
	effect_pools[effect_name].append(effect_data)
	return effect_data

func stop_effect(instance: Spatial, immediate: bool = false):
	for i in range(active_effects.size() - 1, -1, -1):
		var effect = active_effects[i]
		if effect.data.instance == instance:
			if immediate:
				return_to_pool(effect.name, effect.data)
				active_effects.remove(i)
			else:
				if instance.has_method("set_emitting"):
					instance.set_emitting(false)
			break

func stop_all_effects(effect_name: String = "", immediate: bool = false):
	for i in range(active_effects.size() - 1, -1, -1):
		var effect = active_effects[i]
		if effect_name == "" or effect.name == effect_name:
			stop_effect(effect.data.instance, immediate)

func return_to_pool(effect_name: String, effect_data: Dictionary):
	var instance = effect_data.instance
	
	if instance.get_parent() != self:
		instance.get_parent().remove_child(instance)
		add_child(instance)
	
	instance.visible = false
	instance.set_process(false)
	instance.set_physics_process(false)
	if instance.has_method("set_emitting"):
		instance.set_emitting(false)
	
	effect_data.in_use = false
	effect_data.lifetime_timer = 0.0
	
	emit_signal("effect_finished", instance)

func cleanup_finished_effects():
	for i in range(active_effects.size() - 1, -1, -1):
		var effect = active_effects[i]
		var instance = effect.data.instance
		var settings = effect.settings
		
		effect.data.lifetime_timer += cleanup_interval
		
		var should_cleanup = false
		
		if settings.get("one_shot", false) and instance.has_method("get_emitting") and not instance.get_emitting():
			should_cleanup = true
		
		if settings.get("lifetime", 0.0) > 0.0 and effect.data.lifetime_timer >= settings.lifetime:
			should_cleanup = true
		
		if instance.has_method("is_emitting") and not instance.is_emitting():
			var has_active_particles = false
			for child in instance.get_children():
				if child is CPUParticles or child is Particles:
					if child.get_amount() > 0:
						has_active_particles = true
						break
			if not has_active_particles:
				should_cleanup = true
		
		if should_cleanup:
			return_to_pool(effect.name, effect.data)
			active_effects.remove(i)

func get_active_effect_count(effect_name: String = "") -> int:
	if effect_name == "":
		return active_effects.size()
	
	var count = 0
	for effect in active_effects:
		if effect.name == effect_name:
			count += 1
	return count

func get_pool_info(effect_name: String) -> Dictionary:
	if not effect_name in effect_pools:
		return {}
	
	var pool = effect_pools[effect_name]
	var in_use = 0
	var available = 0
	
	for effect_data in pool:
		if effect_data.in_use:
			in_use += 1
		else:
			available += 1
	
	return {
		"total": pool.size(),
		"in_use": in_use,
		"available": available
	}

func preload_effects():
	for effect_name in effect_scenes:
		if not effect_name in effect_pools:
			create_pool(effect_name, effect_settings.get(effect_name, {}).get("pool_size", 10))

func clear_all_pools():
	stop_all_effects("", true)
	
	for effect_name in effect_pools:
		for effect_data in effect_pools[effect_name]:
			effect_data.instance.queue_free()
	
	effect_pools.clear()
	active_effects.clear()

func create_burst_effect(effect_name: String, position: Vector3, count: int = 5, spread: float = 1.0):
	for i in range(count):
		var offset = Vector3(
			rand_range(-spread, spread),
			rand_range(-spread, spread),
			rand_range(-spread, spread)
		)
		var delay = i * 0.05
		if delay > 0:
			yield(get_tree().create_timer(delay), "timeout")
		spawn_effect(effect_name, position + offset)

func create_trail_effect(effect_name: String, start_pos: Vector3, end_pos: Vector3, segments: int = 10):
	var direction = end_pos - start_pos
	var segment_length = direction.length() / segments
	direction = direction.normalized()
	
	for i in range(segments + 1):
		var position = start_pos + direction * (segment_length * i)
		var delay = i * 0.05
		if delay > 0:
			yield(get_tree().create_timer(delay), "timeout")
		spawn_effect(effect_name, position)

func create_circle_effect(effect_name: String, center: Vector3, radius: float, count: int = 8):
	var angle_step = TAU / count
	
	for i in range(count):
		var angle = angle_step * i
		var offset = Vector3(
			cos(angle) * radius,
			0,
			sin(angle) * radius
		)
		spawn_effect(effect_name, center + offset)