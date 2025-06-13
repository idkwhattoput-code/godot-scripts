extends Node2D

class_name LightingSystem2D

signal day_night_changed(is_day)
signal light_source_added(light)
signal light_source_removed(light)
signal ambient_changed(color)

export var enable_day_night_cycle: bool = true
export var day_duration: float = 120.0
export var start_time: float = 12.0
export var current_time: float = 12.0
export var time_speed: float = 1.0
export var enable_shadows: bool = true
export var shadow_color: Color = Color(0.1, 0.1, 0.2, 0.7)
export var max_lights: int = 32
export var ambient_day_color: Color = Color(1.0, 1.0, 0.9, 1.0)
export var ambient_night_color: Color = Color(0.2, 0.2, 0.4, 1.0)
export var ambient_dawn_color: Color = Color(0.8, 0.6, 0.4, 1.0)
export var ambient_dusk_color: Color = Color(0.9, 0.5, 0.3, 1.0)

var canvas_modulate: CanvasModulate
var light_sources: Array = []
var dynamic_lights: Dictionary = {}
var shadow_casters: Array = []
var is_day: bool = true
var sun_angle: float = 0.0
var moon_angle: float = 180.0
var ambient_light: Color = Color.white

class LightSource2D:
	var node: Light2D
	var base_energy: float
	var flicker: bool = false
	var flicker_speed: float = 10.0
	var flicker_intensity: float = 0.2
	var pulse: bool = false
	var pulse_speed: float = 1.0
	var pulse_min: float = 0.5
	var pulse_max: float = 1.0
	var color_shift: bool = false
	var color_shift_speed: float = 1.0
	var color_shift_colors: Array = []
	var follow_target: Node2D = null
	var offset: Vector2 = Vector2.ZERO
	
	func _init(light_node: Light2D):
		node = light_node
		base_energy = light_node.energy

class DynamicLight:
	var position: Vector2
	var color: Color
	var energy: float
	var radius: float
	var lifetime: float
	var fade_in_time: float = 0.2
	var fade_out_time: float = 0.5
	var current_time: float = 0.0
	var light_node: Light2D
	
	func _init(pos: Vector2, col: Color, e: float, r: float, life: float):
		position = pos
		color = col
		energy = e
		radius = r
		lifetime = life

class ShadowCaster:
	var polygon: Polygon2D
	var occluder: LightOccluder2D
	var shape: OccluderPolygon2D
	
	func _init(poly_points: PoolVector2Array):
		shape = OccluderPolygon2D.new()
		shape.polygon = poly_points
		shape.cull_mode = OccluderPolygon2D.CULL_CLOCKWISE

func _ready():
	setup_canvas_modulate()
	current_time = start_time
	
	if enable_day_night_cycle:
		update_day_night_cycle(0)

func setup_canvas_modulate():
	canvas_modulate = CanvasModulate.new()
	get_tree().current_scene.add_child(canvas_modulate)
	canvas_modulate.color = ambient_light

func _process(delta):
	if enable_day_night_cycle:
		update_day_night_cycle(delta)
	
	update_light_sources(delta)
	update_dynamic_lights(delta)
	update_shadows()

func update_day_night_cycle(delta):
	current_time += (delta * time_speed * 24.0) / day_duration
	if current_time >= 24.0:
		current_time -= 24.0
	
	var time_normalized = current_time / 24.0
	sun_angle = time_normalized * 360.0 - 90.0
	moon_angle = sun_angle + 180.0
	
	var new_is_day = current_time >= 6.0 and current_time < 18.0
	if new_is_day != is_day:
		is_day = new_is_day
		emit_signal("day_night_changed", is_day)
	
	update_ambient_light()

func update_ambient_light():
	var target_color: Color
	
	if current_time >= 5.0 and current_time < 7.0:
		var t = (current_time - 5.0) / 2.0
		target_color = ambient_night_color.linear_interpolate(ambient_dawn_color, t)
	elif current_time >= 7.0 and current_time < 9.0:
		var t = (current_time - 7.0) / 2.0
		target_color = ambient_dawn_color.linear_interpolate(ambient_day_color, t)
	elif current_time >= 9.0 and current_time < 17.0:
		target_color = ambient_day_color
	elif current_time >= 17.0 and current_time < 19.0:
		var t = (current_time - 17.0) / 2.0
		target_color = ambient_day_color.linear_interpolate(ambient_dusk_color, t)
	elif current_time >= 19.0 and current_time < 21.0:
		var t = (current_time - 19.0) / 2.0
		target_color = ambient_dusk_color.linear_interpolate(ambient_night_color, t)
	else:
		target_color = ambient_night_color
	
	ambient_light = ambient_light.linear_interpolate(target_color, 0.02)
	
	if canvas_modulate:
		canvas_modulate.color = ambient_light
	
	emit_signal("ambient_changed", ambient_light)

func update_light_sources(delta):
	for light_source in light_sources:
		if not is_instance_valid(light_source.node):
			continue
		
		if light_source.flicker:
			update_flicker(light_source, delta)
		
		if light_source.pulse:
			update_pulse(light_source, delta)
		
		if light_source.color_shift:
			update_color_shift(light_source, delta)
		
		if light_source.follow_target and is_instance_valid(light_source.follow_target):
			light_source.node.global_position = light_source.follow_target.global_position + light_source.offset

func update_flicker(light_source: LightSource2D, delta):
	var flicker_value = sin(OS.get_ticks_msec() * light_source.flicker_speed * 0.001) * light_source.flicker_intensity
	light_source.node.energy = light_source.base_energy + flicker_value

func update_pulse(light_source: LightSource2D, delta):
	var pulse_value = (sin(OS.get_ticks_msec() * light_source.pulse_speed * 0.001) + 1.0) * 0.5
	var energy = lerp(light_source.pulse_min, light_source.pulse_max, pulse_value)
	light_source.node.energy = light_source.base_energy * energy

func update_color_shift(light_source: LightSource2D, delta):
	if light_source.color_shift_colors.empty():
		return
	
	var time = OS.get_ticks_msec() * light_source.color_shift_speed * 0.001
	var index = int(time) % light_source.color_shift_colors.size()
	var next_index = (index + 1) % light_source.color_shift_colors.size()
	var t = fmod(time, 1.0)
	
	var current_color = light_source.color_shift_colors[index]
	var next_color = light_source.color_shift_colors[next_index]
	light_source.node.color = current_color.linear_interpolate(next_color, t)

func update_dynamic_lights(delta):
	var lights_to_remove = []
	
	for id in dynamic_lights:
		var light = dynamic_lights[id]
		light.current_time += delta
		
		if light.current_time >= light.lifetime:
			lights_to_remove.append(id)
			if is_instance_valid(light.light_node):
				light.light_node.queue_free()
			continue
		
		if not is_instance_valid(light.light_node):
			continue
		
		var progress = light.current_time / light.lifetime
		var energy_multiplier = 1.0
		
		if light.current_time < light.fade_in_time:
			energy_multiplier = light.current_time / light.fade_in_time
		elif light.current_time > light.lifetime - light.fade_out_time:
			var fade_progress = (light.current_time - (light.lifetime - light.fade_out_time)) / light.fade_out_time
			energy_multiplier = 1.0 - fade_progress
		
		light.light_node.energy = light.energy * energy_multiplier
	
	for id in lights_to_remove:
		dynamic_lights.erase(id)

func update_shadows():
	if not enable_shadows:
		return
	
	for caster in shadow_casters:
		if is_instance_valid(caster.occluder):
			update_shadow_direction(caster)

func update_shadow_direction(caster: ShadowCaster):
	if not is_day:
		return
	
	var shadow_direction = Vector2(cos(deg2rad(sun_angle)), sin(deg2rad(sun_angle)))
	var shadow_length = 20.0 * (1.0 - abs(sin(deg2rad(sun_angle))))
	
	if caster.occluder and caster.shape:
		var offset = shadow_direction * shadow_length
		caster.occluder.position = offset

func add_light_source(light: Light2D, properties: Dictionary = {}) -> LightSource2D:
	if light_sources.size() >= max_lights:
		push_warning("Maximum light sources reached")
		return null
	
	var light_source = LightSource2D.new(light)
	
	for key in properties:
		if key in light_source:
			light_source.set(key, properties[key])
	
	light_sources.append(light_source)
	emit_signal("light_source_added", light)
	
	return light_source

func remove_light_source(light: Light2D):
	for i in range(light_sources.size()):
		if light_sources[i].node == light:
			light_sources.remove(i)
			emit_signal("light_source_removed", light)
			break

func create_dynamic_light(position: Vector2, color: Color = Color.white, energy: float = 1.0, radius: float = 100.0, lifetime: float = 1.0) -> Light2D:
	var light = Light2D.new()
	light.texture = preload("res://icon.png")
	light.position = position
	light.color = color
	light.energy = energy
	light.texture_scale = radius / 64.0
	light.enabled = true
	
	get_parent().add_child(light)
	
	var dynamic_light = DynamicLight.new(position, color, energy, radius, lifetime)
	dynamic_light.light_node = light
	
	var id = light.get_instance_id()
	dynamic_lights[id] = dynamic_light
	
	return light

func create_fire_light(position: Vector2, size: float = 1.0) -> LightSource2D:
	var light = Light2D.new()
	light.texture = preload("res://icon.png")
	light.position = position
	light.color = Color(1.0, 0.6, 0.2)
	light.energy = 0.8
	light.texture_scale = size
	
	get_parent().add_child(light)
	
	return add_light_source(light, {
		"flicker": true,
		"flicker_speed": 15.0,
		"flicker_intensity": 0.3,
		"color_shift": true,
		"color_shift_speed": 0.5,
		"color_shift_colors": [
			Color(1.0, 0.6, 0.2),
			Color(1.0, 0.5, 0.1),
			Color(1.0, 0.7, 0.3)
		]
	})

func create_torch_light(position: Vector2) -> LightSource2D:
	return create_fire_light(position, 1.5)

func create_candle_light(position: Vector2) -> LightSource2D:
	return create_fire_light(position, 0.5)

func create_electric_light(position: Vector2, color: Color = Color(0.9, 0.9, 1.0)) -> LightSource2D:
	var light = Light2D.new()
	light.texture = preload("res://icon.png")
	light.position = position
	light.color = color
	light.energy = 1.0
	light.texture_scale = 2.0
	
	get_parent().add_child(light)
	
	return add_light_source(light, {
		"flicker": true,
		"flicker_speed": 50.0,
		"flicker_intensity": 0.05
	})

func create_spotlight(position: Vector2, direction: Vector2, color: Color = Color.white) -> Light2D:
	var light = Light2D.new()
	light.texture = preload("res://icon.png")
	light.position = position
	light.color = color
	light.energy = 1.5
	light.texture_scale = 3.0
	light.shadow_enabled = enable_shadows
	
	get_parent().add_child(light)
	
	return light

func add_shadow_caster(polygon_points: PoolVector2Array, parent: Node2D = null):
	if not enable_shadows:
		return
	
	var caster = ShadowCaster.new(polygon_points)
	
	caster.occluder = LightOccluder2D.new()
	caster.occluder.occluder = caster.shape
	
	if parent:
		parent.add_child(caster.occluder)
	else:
		get_parent().add_child(caster.occluder)
	
	shadow_casters.append(caster)

func create_lightning_flash(duration: float = 0.2):
	var flash = create_dynamic_light(
		Vector2(get_viewport().size.x / 2, -100),
		Color(0.9, 0.9, 1.0),
		3.0,
		2000.0,
		duration
	)
	flash.shadow_enabled = false

func set_time_of_day(hour: float):
	current_time = clamp(hour, 0.0, 23.99)
	update_day_night_cycle(0)

func get_time_of_day() -> float:
	return current_time

func is_daytime() -> bool:
	return is_day

func get_ambient_brightness() -> float:
	return ambient_light.v

func toggle_shadows(enabled: bool):
	enable_shadows = enabled
	for light_source in light_sources:
		if light_source.node:
			light_source.node.shadow_enabled = enabled

func clear_all_lights():
	for light_source in light_sources:
		if light_source.node:
			light_source.node.queue_free()
	light_sources.clear()
	
	for id in dynamic_lights:
		if dynamic_lights[id].light_node:
			dynamic_lights[id].light_node.queue_free()
	dynamic_lights.clear()