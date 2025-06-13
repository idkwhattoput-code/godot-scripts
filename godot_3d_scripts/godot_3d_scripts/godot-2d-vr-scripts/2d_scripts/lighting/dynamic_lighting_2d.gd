extends Node2D

class_name DynamicLighting2D

@export_group("Lighting Settings")
@export var ambient_light_color := Color(0.1, 0.1, 0.2)
@export var ambient_light_energy := 0.3
@export var shadow_enabled := true
@export var shadow_color := Color(0, 0, 0, 0.8)
@export var shadow_smoothing := 2.0

@export_group("Day/Night Cycle")
@export var enable_day_night_cycle := true
@export var day_duration := 300.0
@export var sunrise_time := 0.25
@export var sunset_time := 0.75
@export var night_color := Color(0.05, 0.05, 0.15)
@export var day_color := Color(1.0, 0.95, 0.8)
@export var dawn_dusk_color := Color(1.0, 0.6, 0.3)

@export_group("Light Sources")
@export var max_dynamic_lights := 50
@export var light_fade_distance := 500.0
@export var enable_light_flickering := true
@export var flicker_intensity := 0.1

@export_group("Performance")
@export var update_frequency := 0.1
@export var use_light_culling := true
@export var cull_margin := 100.0

var canvas_modulate: CanvasModulate
var light_occluders := []
var dynamic_lights := []
var static_lights := []
var current_time_of_day := 0.0
var update_timer := 0.0
var player_reference: Node2D
var viewport_rect: Rect2

signal time_changed(time: float)
signal sunrise()
signal sunset()
signal light_added(light: Light2D)
signal light_removed(light: Light2D)

class LightSource:
	var light_node: Light2D
	var base_energy: float
	var base_color: Color
	var flicker_offset: float
	var is_static: bool = false
	var cast_shadows: bool = true
	
	func _init(node: Light2D):
		light_node = node
		base_energy = node.energy
		base_color = node.color
		flicker_offset = randf() * TAU

func _ready():
	setup_canvas_modulate()
	setup_viewport_tracking()
	
	find_existing_lights()
	find_occluders()

func setup_canvas_modulate():
	canvas_modulate = CanvasModulate.new()
	canvas_modulate.color = ambient_light_color
	add_child(canvas_modulate)

func setup_viewport_tracking():
	var viewport = get_viewport()
	if viewport:
		viewport_rect = viewport.get_visible_rect()
		viewport.size_changed.connect(_on_viewport_size_changed)

func _on_viewport_size_changed():
	viewport_rect = get_viewport().get_visible_rect()

func find_existing_lights():
	for child in get_children():
		if child is Light2D:
			register_light(child, true)

func find_occluders():
	for node in get_tree().get_nodes_in_group("light_occluders"):
		if node is LightOccluder2D:
			light_occluders.append(node)

func register_light(light: Light2D, is_static: bool = false) -> LightSource:
	var light_source = LightSource.new(light)
	light_source.is_static = is_static
	
	if is_static:
		static_lights.append(light_source)
	else:
		if dynamic_lights.size() >= max_dynamic_lights:
			remove_oldest_dynamic_light()
		dynamic_lights.append(light_source)
	
	emit_signal("light_added", light)
	return light_source

func remove_oldest_dynamic_light():
	if dynamic_lights.size() > 0:
		var oldest = dynamic_lights[0]
		dynamic_lights.remove_at(0)
		if is_instance_valid(oldest.light_node):
			oldest.light_node.queue_free()

func unregister_light(light: Light2D):
	for i in range(dynamic_lights.size() - 1, -1, -1):
		if dynamic_lights[i].light_node == light:
			dynamic_lights.remove_at(i)
			emit_signal("light_removed", light)
			return
	
	for i in range(static_lights.size() - 1, -1, -1):
		if static_lights[i].light_node == light:
			static_lights.remove_at(i)
			emit_signal("light_removed", light)
			return

func create_point_light(position: Vector2, color: Color, energy: float = 1.0, texture_scale: float = 1.0) -> Light2D:
	var light = PointLight2D.new()
	light.position = position
	light.color = color
	light.energy = energy
	light.texture_scale = texture_scale
	light.shadow_enabled = shadow_enabled
	
	add_child(light)
	register_light(light, false)
	
	return light

func create_directional_light(position: Vector2, direction: Vector2, color: Color, energy: float = 1.0) -> DirectionalLight2D:
	var light = DirectionalLight2D.new()
	light.position = position
	light.rotation = direction.angle()
	light.color = color
	light.energy = energy
	
	add_child(light)
	register_light(light, false)
	
	return light

func create_spot_light(position: Vector2, direction: Vector2, color: Color, angle: float = 45.0, energy: float = 1.0) -> Light2D:
	var light = PointLight2D.new()
	light.position = position
	light.color = color
	light.energy = energy
	light.shadow_enabled = shadow_enabled
	
	add_child(light)
	register_light(light, false)
	
	return light

func create_light_occluder(polygon: PackedVector2Array, position: Vector2 = Vector2.ZERO) -> LightOccluder2D:
	var occluder = LightOccluder2D.new()
	var occluder_polygon = OccluderPolygon2D.new()
	occluder_polygon.polygon = polygon
	occluder.occluder = occluder_polygon
	occluder.position = position
	
	add_child(occluder)
	light_occluders.append(occluder)
	
	return occluder

func _process(delta):
	update_timer += delta
	
	if enable_day_night_cycle:
		update_day_night_cycle(delta)
	
	if update_timer >= update_frequency:
		update_timer = 0.0
		update_lights()
		
		if use_light_culling:
			cull_lights()

func update_day_night_cycle(delta: float):
	current_time_of_day += delta / day_duration
	if current_time_of_day >= 1.0:
		current_time_of_day -= 1.0
	
	var prev_is_day = is_daytime()
	
	var target_color: Color
	var target_energy: float
	
	if current_time_of_day < sunrise_time:
		var t = current_time_of_day / sunrise_time
		target_color = night_color.lerp(dawn_dusk_color, t)
		target_energy = ambient_light_energy * (0.3 + 0.7 * t)
	elif current_time_of_day < 0.5:
		var t = (current_time_of_day - sunrise_time) / (0.5 - sunrise_time)
		target_color = dawn_dusk_color.lerp(day_color, t)
		target_energy = ambient_light_energy
	elif current_time_of_day < sunset_time:
		var t = (current_time_of_day - 0.5) / (sunset_time - 0.5)
		target_color = day_color.lerp(dawn_dusk_color, t)
		target_energy = ambient_light_energy
	else:
		var t = (current_time_of_day - sunset_time) / (1.0 - sunset_time)
		target_color = dawn_dusk_color.lerp(night_color, t)
		target_energy = ambient_light_energy * (1.0 - 0.7 * t)
	
	if canvas_modulate:
		canvas_modulate.color = canvas_modulate.color.lerp(target_color * target_energy, delta * 2.0)
	
	emit_signal("time_changed", current_time_of_day)
	
	var is_day_now = is_daytime()
	if prev_is_day != is_day_now:
		if is_day_now:
			emit_signal("sunrise")
		else:
			emit_signal("sunset")

func is_daytime() -> bool:
	return current_time_of_day >= sunrise_time and current_time_of_day < sunset_time

func update_lights():
	var time = Time.get_ticks_msec() / 1000.0
	
	for light_source in dynamic_lights + static_lights:
		if not is_instance_valid(light_source.light_node):
			continue
		
		if enable_light_flickering and not light_source.is_static:
			var flicker = sin(time * 10.0 + light_source.flicker_offset) * flicker_intensity
			light_source.light_node.energy = light_source.base_energy * (1.0 + flicker)
		
		if use_light_culling:
			var distance_to_viewport = get_distance_to_viewport(light_source.light_node.global_position)
			if distance_to_viewport > light_fade_distance:
				var fade = 1.0 - (distance_to_viewport - light_fade_distance) / 100.0
				light_source.light_node.energy *= max(0.0, fade)

func cull_lights():
	if not player_reference:
		player_reference = get_tree().get_first_node_in_group("player")
		if not player_reference:
			return
	
	for light_source in dynamic_lights + static_lights:
		if not is_instance_valid(light_source.light_node):
			continue
		
		var is_visible = is_light_visible(light_source.light_node)
		light_source.light_node.visible = is_visible
		light_source.light_node.shadow_enabled = is_visible and shadow_enabled

func is_light_visible(light: Light2D) -> bool:
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return true
	
	var camera_rect = Rect2(
		camera.global_position - viewport_rect.size / 2,
		viewport_rect.size
	).grow(cull_margin)
	
	var light_radius = 0.0
	if light is PointLight2D:
		light_radius = light.texture.get_width() * light.texture_scale / 2
	
	var light_rect = Rect2(
		light.global_position - Vector2.ONE * light_radius,
		Vector2.ONE * light_radius * 2
	)
	
	return camera_rect.intersects(light_rect)

func get_distance_to_viewport(pos: Vector2) -> float:
	var camera = get_viewport().get_camera_2d()
	if camera:
		return pos.distance_to(camera.global_position)
	return 0.0

func set_ambient_light(color: Color, energy: float):
	ambient_light_color = color
	ambient_light_energy = energy
	if canvas_modulate:
		canvas_modulate.color = color * energy

func get_current_ambient_color() -> Color:
	if canvas_modulate:
		return canvas_modulate.color
	return ambient_light_color

func set_time_of_day(time: float):
	current_time_of_day = clamp(time, 0.0, 1.0)

func get_time_of_day() -> float:
	return current_time_of_day

func create_lightning_flash(duration: float = 0.2, intensity: float = 3.0):
	var original_energy = ambient_light_energy
	var flash_tween = create_tween()
	
	flash_tween.tween_method(
		func(value): set_ambient_light(ambient_light_color, value),
		ambient_light_energy,
		ambient_light_energy * intensity,
		duration * 0.1
	)
	flash_tween.tween_method(
		func(value): set_ambient_light(ambient_light_color, value),
		ambient_light_energy * intensity,
		original_energy,
		duration * 0.9
	)

func create_explosion_light(position: Vector2, color: Color = Color.ORANGE, max_radius: float = 200.0, duration: float = 0.5):
	var light = create_point_light(position, color, 2.0, max_radius / 100.0)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(light, "energy", 0.0, duration)
	tween.tween_property(light, "texture_scale", 0.0, duration)
	tween.chain().tween_callback(func():
		unregister_light(light)
		light.queue_free()
	)

func toggle_shadows(enabled: bool):
	shadow_enabled = enabled
	for light_source in dynamic_lights + static_lights:
		if is_instance_valid(light_source.light_node):
			light_source.light_node.shadow_enabled = enabled

func clear_all_dynamic_lights():
	for light_source in dynamic_lights:
		if is_instance_valid(light_source.light_node):
			light_source.light_node.queue_free()
	dynamic_lights.clear()