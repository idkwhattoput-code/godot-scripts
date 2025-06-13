extends ParallaxBackground

class_name ParallaxBackground2D

@export var auto_scroll_speed: Vector2 = Vector2.ZERO
@export var follow_camera: bool = true
@export var infinite_scrolling: bool = true
@export var vertical_sync: bool = false

var camera_reference: Camera2D
var last_camera_position: Vector2

@onready var layers: Array[ParallaxLayer] = []

func _ready():
	setup_layers()
	find_camera()

func setup_layers():
	for child in get_children():
		if child is ParallaxLayer:
			layers.append(child)
			setup_layer(child)

func setup_layer(layer: ParallaxLayer):
	if infinite_scrolling:
		layer.motion_mirroring = get_layer_mirroring_size(layer)

func get_layer_mirroring_size(layer: ParallaxLayer) -> Vector2:
	var sprite_node = find_sprite_in_layer(layer)
	if sprite_node and sprite_node.texture:
		var texture_size = sprite_node.texture.get_size()
		return texture_size * sprite_node.scale
	return Vector2(1024, 600)

func find_sprite_in_layer(layer: ParallaxLayer) -> Sprite2D:
	for child in layer.get_children():
		if child is Sprite2D:
			return child
		elif child.get_child_count() > 0:
			var nested_sprite = find_nested_sprite(child)
			if nested_sprite:
				return nested_sprite
	return null

func find_nested_sprite(node: Node) -> Sprite2D:
	for child in node.get_children():
		if child is Sprite2D:
			return child
		elif child.get_child_count() > 0:
			var nested = find_nested_sprite(child)
			if nested:
				return nested
	return null

func find_camera():
	if follow_camera:
		camera_reference = get_viewport().get_camera_2d()
		if camera_reference:
			last_camera_position = camera_reference.global_position

func _process(delta):
	update_auto_scroll(delta)
	if follow_camera:
		update_camera_follow()

func update_auto_scroll(delta):
	if auto_scroll_speed != Vector2.ZERO:
		scroll_offset += auto_scroll_speed * delta

func update_camera_follow():
	if not camera_reference:
		find_camera()
		return
	
	var current_camera_pos = camera_reference.global_position
	var camera_delta = current_camera_pos - last_camera_position
	
	if vertical_sync:
		camera_delta.y = 0
	
	scroll_offset += camera_delta
	last_camera_position = current_camera_pos

func add_parallax_layer(texture: Texture2D, motion_scale: Vector2, motion_offset: Vector2 = Vector2.ZERO, z_index: int = 0):
	var layer = ParallaxLayer.new()
	var sprite = Sprite2D.new()
	
	sprite.texture = texture
	sprite.centered = false
	
	layer.motion_scale = motion_scale
	layer.motion_offset = motion_offset
	layer.z_index = z_index
	
	if infinite_scrolling:
		layer.motion_mirroring = texture.get_size()
	
	layer.add_child(sprite)
	add_child(layer)
	layers.append(layer)
	
	return layer

func remove_parallax_layer(layer: ParallaxLayer):
	if layer in layers:
		layers.erase(layer)
		layer.queue_free()

func set_layer_speed(layer_index: int, speed: Vector2):
	if layer_index >= 0 and layer_index < layers.size():
		layers[layer_index].motion_scale = speed

func set_layer_offset(layer_index: int, offset: Vector2):
	if layer_index >= 0 and layer_index < layers.size():
		layers[layer_index].motion_offset = offset

func get_layer_count() -> int:
	return layers.size()

func set_auto_scroll(speed: Vector2):
	auto_scroll_speed = speed

func stop_auto_scroll():
	auto_scroll_speed = Vector2.ZERO

func set_camera_follow(enabled: bool):
	follow_camera = enabled

func reset_scroll():
	scroll_offset = Vector2.ZERO

func set_infinite_scrolling(enabled: bool):
	infinite_scrolling = enabled
	for layer in layers:
		if enabled:
			layer.motion_mirroring = get_layer_mirroring_size(layer)
		else:
			layer.motion_mirroring = Vector2.ZERO

func pause_scrolling():
	set_process(false)

func resume_scrolling():
	set_process(true)

func create_cloud_layer(cloud_texture: Texture2D, speed: float = 0.1, count: int = 5) -> ParallaxLayer:
	var layer = ParallaxLayer.new()
	layer.motion_scale = Vector2(speed, speed)
	
	var layer_size = get_viewport().get_visible_rect().size
	
	for i in range(count):
		var cloud = Sprite2D.new()
		cloud.texture = cloud_texture
		cloud.position = Vector2(
			randf_range(0, layer_size.x * 2),
			randf_range(0, layer_size.y * 0.5)
		)
		cloud.scale = Vector2(randf_range(0.5, 1.5), randf_range(0.5, 1.5))
		layer.add_child(cloud)
	
	if infinite_scrolling:
		layer.motion_mirroring = Vector2(layer_size.x * 2, layer_size.y)
	
	add_child(layer)
	layers.append(layer)
	return layer

func create_mountain_layer(mountain_texture: Texture2D, speed: float = 0.3) -> ParallaxLayer:
	var layer = ParallaxLayer.new()
	layer.motion_scale = Vector2(speed, 0)
	
	var sprite = Sprite2D.new()
	sprite.texture = mountain_texture
	sprite.centered = false
	
	if infinite_scrolling:
		layer.motion_mirroring = Vector2(mountain_texture.get_size().x, 0)
	
	layer.add_child(sprite)
	add_child(layer)
	layers.append(layer)
	return layer

func create_star_field(star_texture: Texture2D, speed: float = 0.05, star_count: int = 50) -> ParallaxLayer:
	var layer = ParallaxLayer.new()
	layer.motion_scale = Vector2(speed, speed)
	
	var layer_size = get_viewport().get_visible_rect().size
	
	for i in range(star_count):
		var star = Sprite2D.new()
		star.texture = star_texture
		star.position = Vector2(
			randf_range(0, layer_size.x * 2),
			randf_range(0, layer_size.y * 2)
		)
		star.scale = Vector2(randf_range(0.2, 1.0), randf_range(0.2, 1.0))
		star.modulate = Color(1, 1, 1, randf_range(0.3, 1.0))
		layer.add_child(star)
	
	if infinite_scrolling:
		layer.motion_mirroring = Vector2(layer_size.x * 2, layer_size.y * 2)
	
	add_child(layer)
	layers.append(layer)
	return layer

func animate_layer_to_speed(layer_index: int, target_speed: Vector2, duration: float):
	if layer_index < 0 or layer_index >= layers.size():
		return
	
	var layer = layers[layer_index]
	var tween = create_tween()
	tween.tween_property(layer, "motion_scale", target_speed, duration)

func shake_layer(layer_index: int, intensity: float, duration: float):
	if layer_index < 0 or layer_index >= layers.size():
		return
	
	var layer = layers[layer_index]
	var original_offset = layer.motion_offset
	
	var shake_tween = create_tween()
	shake_tween.set_loops(int(duration * 30))
	
	var shake_offset = Vector2(
		randf_range(-intensity, intensity),
		randf_range(-intensity, intensity)
	)
	
	shake_tween.tween_property(layer, "motion_offset", original_offset + shake_offset, 1.0/30.0)
	shake_tween.tween_property(layer, "motion_offset", original_offset, 1.0/30.0)

func fade_layer(layer_index: int, target_alpha: float, duration: float):
	if layer_index < 0 or layer_index >= layers.size():
		return
	
	var layer = layers[layer_index]
	var tween = create_tween()
	tween.tween_property(layer, "modulate:a", target_alpha, duration)

func get_parallax_data() -> Dictionary:
	var data = {
		"scroll_offset": scroll_offset,
		"auto_scroll_speed": auto_scroll_speed,
		"follow_camera": follow_camera,
		"infinite_scrolling": infinite_scrolling,
		"layers": []
	}
	
	for layer in layers:
		data.layers.append({
			"motion_scale": layer.motion_scale,
			"motion_offset": layer.motion_offset,
			"motion_mirroring": layer.motion_mirroring,
			"z_index": layer.z_index,
			"modulate": layer.modulate
		})
	
	return data

func load_parallax_data(data: Dictionary):
	scroll_offset = data.get("scroll_offset", Vector2.ZERO)
	auto_scroll_speed = data.get("auto_scroll_speed", Vector2.ZERO)
	follow_camera = data.get("follow_camera", true)
	infinite_scrolling = data.get("infinite_scrolling", true)
	
	var layer_data = data.get("layers", [])
	for i in range(min(layer_data.size(), layers.size())):
		var layer = layers[i]
		var layer_info = layer_data[i]
		
		layer.motion_scale = layer_info.get("motion_scale", Vector2.ONE)
		layer.motion_offset = layer_info.get("motion_offset", Vector2.ZERO)
		layer.motion_mirroring = layer_info.get("motion_mirroring", Vector2.ZERO)
		layer.z_index = layer_info.get("z_index", 0)
		layer.modulate = layer_info.get("modulate", Color.WHITE)