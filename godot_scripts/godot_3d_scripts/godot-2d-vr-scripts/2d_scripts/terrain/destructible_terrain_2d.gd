extends Node2D

export var terrain_texture : Texture
export var destruction_radius = 30.0
export var pixel_perfect = true
export var rebuild_collision = true
export var debris_enabled = true
export var debris_scene : PackedScene
export var max_debris_count = 50

signal terrain_destroyed(position, radius)
signal terrain_regenerated()

var terrain_data : Image
var terrain_sprite : Sprite
var collision_polygon : CollisionPolygon2D
var debris_container : Node2D
var destruction_holes = []

func _ready():
	_initialize_terrain()
	_create_collision_from_texture()

func _initialize_terrain():
	if not terrain_texture:
		push_error("No terrain texture assigned!")
		return
	
	terrain_data = terrain_texture.get_data()
	terrain_data.lock()
	
	terrain_sprite = Sprite.new()
	terrain_sprite.texture = ImageTexture.new()
	terrain_sprite.texture.create_from_image(terrain_data)
	terrain_sprite.centered = false
	add_child(terrain_sprite)
	
	debris_container = Node2D.new()
	debris_container.name = "Debris"
	add_child(debris_container)

func _create_collision_from_texture():
	if not rebuild_collision:
		return
	
	var bitmap = BitMap.new()
	bitmap.create_from_image_alpha(terrain_data)
	
	var polygons = bitmap.opaque_to_polygons(Rect2(Vector2.ZERO, terrain_data.get_size()))
	
	if get_parent() is StaticBody2D:
		for polygon in polygons:
			collision_polygon = CollisionPolygon2D.new()
			collision_polygon.polygon = polygon
			get_parent().add_child(collision_polygon)

func destroy_terrain(world_position, custom_radius = -1):
	var local_pos = to_local(world_position)
	var radius = custom_radius if custom_radius > 0 else destruction_radius
	
	if pixel_perfect:
		_destroy_circle_precise(local_pos, radius)
	else:
		_destroy_circle_fast(local_pos, radius)
	
	_update_terrain_texture()
	
	if rebuild_collision:
		_rebuild_collision()
	
	if debris_enabled:
		_spawn_debris(world_position, radius)
	
	destruction_holes.append({
		"position": local_pos,
		"radius": radius,
		"time": OS.get_ticks_msec()
	})
	
	emit_signal("terrain_destroyed", world_position, radius)

func _destroy_circle_precise(center, radius):
	var min_x = max(0, int(center.x - radius))
	var max_x = min(terrain_data.get_width() - 1, int(center.x + radius))
	var min_y = max(0, int(center.y - radius))
	var max_y = min(terrain_data.get_height() - 1, int(center.y + radius))
	
	terrain_data.lock()
	
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var distance = Vector2(x - center.x, y - center.y).length()
			if distance <= radius:
				var current_color = terrain_data.get_pixel(x, y)
				if current_color.a > 0:
					var edge_fade = 1.0 - (distance / radius)
					edge_fade = smoothstep(0, 1, edge_fade)
					
					if edge_fade > 0.5:
						terrain_data.set_pixel(x, y, Color(0, 0, 0, 0))
	
	terrain_data.unlock()

func _destroy_circle_fast(center, radius):
	terrain_data.lock()
	
	var radius_squared = radius * radius
	var min_x = max(0, int(center.x - radius))
	var max_x = min(terrain_data.get_width() - 1, int(center.x + radius))
	
	for x in range(min_x, max_x + 1):
		var x_diff = x - center.x
		var y_range = sqrt(radius_squared - x_diff * x_diff)
		
		var min_y = max(0, int(center.y - y_range))
		var max_y = min(terrain_data.get_height() - 1, int(center.y + y_range))
		
		for y in range(min_y, max_y + 1):
			terrain_data.set_pixel(x, y, Color(0, 0, 0, 0))
	
	terrain_data.unlock()

func _update_terrain_texture():
	terrain_sprite.texture.set_data(terrain_data)

func _rebuild_collision():
	if not get_parent() is StaticBody2D:
		return
	
	for child in get_parent().get_children():
		if child is CollisionPolygon2D:
			child.queue_free()
	
	yield(get_tree(), "idle_frame")
	
	_create_collision_from_texture()

func _spawn_debris(position, radius):
	if not debris_scene:
		return
	
	var debris_count = min(int(radius / 10), max_debris_count)
	
	for i in range(debris_count):
		var debris = debris_scene.instance()
		debris_container.add_child(debris)
		
		var angle = randf() * TAU
		var distance = randf() * radius * 0.5
		var offset = Vector2(cos(angle), sin(angle)) * distance
		
		debris.global_position = position + offset
		
		if debris.has_method("apply_explosion_force"):
			var force_direction = offset.normalized()
			debris.apply_explosion_force(force_direction * rand_range(100, 300))

func regenerate_terrain():
	if terrain_texture:
		terrain_data = terrain_texture.get_data()
		terrain_data.lock()
		_update_terrain_texture()
		_rebuild_collision()
		destruction_holes.clear()
		emit_signal("terrain_regenerated")

func get_terrain_at_position(world_position):
	var local_pos = to_local(world_position)
	
	if local_pos.x < 0 or local_pos.x >= terrain_data.get_width():
		return false
	if local_pos.y < 0 or local_pos.y >= terrain_data.get_height():
		return false
	
	terrain_data.lock()
	var pixel = terrain_data.get_pixel(int(local_pos.x), int(local_pos.y))
	terrain_data.unlock()
	
	return pixel.a > 0

func create_explosion_pattern(world_position, pattern_type = "star"):
	match pattern_type:
		"star":
			for i in range(8):
				var angle = (TAU / 8) * i
				var direction = Vector2(cos(angle), sin(angle))
				for j in range(3):
					var pos = world_position + direction * destruction_radius * (j + 1)
					destroy_terrain(pos, destruction_radius * 0.5)
		
		"line":
			for i in range(5):
				var offset = Vector2(destruction_radius * i, 0)
				destroy_terrain(world_position + offset, destruction_radius * 0.7)
		
		"cluster":
			for i in range(5):
				var angle = randf() * TAU
				var distance = randf() * destruction_radius
				var pos = world_position + Vector2(cos(angle), sin(angle)) * distance
				destroy_terrain(pos, destruction_radius * 0.5)

func save_destruction_state():
	var save_data = {
		"holes": destruction_holes,
		"terrain_data": terrain_data.get_data()
	}
	return save_data

func load_destruction_state(save_data):
	if "holes" in save_data:
		destruction_holes = save_data.holes
	
	if "terrain_data" in save_data:
		terrain_data.set_data(save_data.terrain_data)
		_update_terrain_texture()
		_rebuild_collision()

func get_destruction_percentage():
	terrain_data.lock()
	var total_pixels = terrain_data.get_width() * terrain_data.get_height()
	var destroyed_pixels = 0
	
	for x in range(terrain_data.get_width()):
		for y in range(terrain_data.get_height()):
			if terrain_data.get_pixel(x, y).a == 0:
				destroyed_pixels += 1
	
	terrain_data.unlock()
	return float(destroyed_pixels) / float(total_pixels)

func clear_debris():
	for child in debris_container.get_children():
		child.queue_free()