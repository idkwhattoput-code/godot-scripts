extends Control

signal marker_clicked(marker_id: String)
signal zoom_changed(zoom_level: float)

@export_group("Minimap Settings")
@export var minimap_size: Vector2 = Vector2(200, 200)
@export var world_size: Vector2 = Vector2(1000, 1000)
@export var follow_player: bool = true
@export var rotate_with_player: bool = false
@export var zoom_levels: Array[float] = [0.5, 1.0, 2.0, 4.0]
@export var current_zoom_index: int = 1

@export_group("Visual Style")
@export var background_color: Color = Color(0.1, 0.1, 0.1, 0.8)
@export var border_color: Color = Color(0.3, 0.3, 0.3, 1.0)
@export var border_width: float = 2.0
@export var grid_enabled: bool = true
@export var grid_color: Color = Color(0.2, 0.2, 0.2, 0.5)
@export var grid_spacing: float = 50.0

@export_group("Markers")
@export var player_icon: Texture2D
@export var player_color: Color = Color.GREEN
@export var enemy_icon: Texture2D
@export var enemy_color: Color = Color.RED
@export var objective_icon: Texture2D
@export var objective_color: Color = Color.YELLOW
@export var custom_markers: Dictionary = {}

@export_group("Fog of War")
@export var fog_enabled: bool = true
@export var fog_color: Color = Color(0, 0, 0, 0.8)
@export var visibility_radius: float = 100.0
@export var persistent_fog: bool = true

var viewport: SubViewport
var camera: Camera2D
var map_content: Node2D
var fog_texture: ImageTexture
var fog_image: Image
var discovered_areas: PackedVector2Array = []

var player_ref: Node2D
var tracked_objects: Dictionary = {}
var marker_nodes: Dictionary = {}
var zoom_level: float = 1.0

class MinimapMarker:
	var id: String
	var position: Vector2
	var icon: Texture2D
	var color: Color
	var size: Vector2 = Vector2(8, 8)
	var visible: bool = true
	var label: String = ""
	var priority: int = 0

func _ready():
	custom_minimum_size = minimap_size
	_setup_viewport()
	_setup_camera()
	_create_map_content()
	
	if fog_enabled:
		_initialize_fog()
	
	_find_player()

func _setup_viewport():
	viewport = SubViewport.new()
	viewport.size = minimap_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	
	var viewport_container = SubViewportContainer.new()
	viewport_container.custom_minimum_size = minimap_size
	viewport_container.stretch = true
	viewport_container.add_child(viewport)
	add_child(viewport_container)

func _setup_camera():
	camera = Camera2D.new()
	camera.enabled = true
	viewport.add_child(camera)
	_update_zoom()

func _create_map_content():
	map_content = Node2D.new()
	viewport.add_child(map_content)

func _find_player():
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player_ref = players[0]

func _draw():
	# Draw background
	draw_rect(Rect2(Vector2.ZERO, minimap_size), background_color)
	
	# Draw border
	draw_rect(Rect2(Vector2.ZERO, minimap_size), border_color, false, border_width)
	
	# Draw grid
	if grid_enabled:
		_draw_grid()

func _draw_grid():
	var grid_size = grid_spacing * zoom_level
	var offset = Vector2.ZERO
	
	if follow_player and player_ref:
		offset = player_ref.global_position * zoom_level
		offset = offset.posmod(grid_size)
	
	# Vertical lines
	var x = -offset.x
	while x < minimap_size.x:
		draw_line(Vector2(x, 0), Vector2(x, minimap_size.y), grid_color)
		x += grid_size
	
	# Horizontal lines
	var y = -offset.y
	while y < minimap_size.y:
		draw_line(Vector2(0, y), Vector2(minimap_size.x, y), grid_color)
		y += grid_size

func _process(_delta):
	if follow_player and player_ref:
		camera.global_position = player_ref.global_position
		
		if rotate_with_player:
			camera.rotation = player_ref.rotation
	
	_update_markers()
	
	if fog_enabled:
		_update_fog()
	
	queue_redraw()

func _update_markers():
	# Clear old markers
	for marker in marker_nodes.values():
		marker.queue_free()
	marker_nodes.clear()
	
	# Update player marker
	if player_ref:
		_create_marker_node("player", player_ref.global_position, player_icon, player_color, 1)
	
	# Update tracked objects
	for obj_id in tracked_objects:
		var obj = tracked_objects[obj_id]
		if is_instance_valid(obj.node):
			_create_marker_node(obj_id, obj.node.global_position, obj.icon, obj.color, obj.priority)
	
	# Sort markers by priority
	var sorted_markers = marker_nodes.values()
	sorted_markers.sort_custom(func(a, b): return a.get_meta("priority") > b.get_meta("priority"))

func _create_marker_node(id: String, world_pos: Vector2, icon: Texture2D, color: Color, priority: int):
	var marker_sprite = Sprite2D.new()
	marker_sprite.texture = icon
	marker_sprite.modulate = color
	marker_sprite.position = world_to_minimap(world_pos)
	marker_sprite.scale = Vector2.ONE / zoom_level
	marker_sprite.set_meta("priority", priority)
	
	map_content.add_child(marker_sprite)
	marker_nodes[id] = marker_sprite

func _initialize_fog():
	fog_image = Image.create(int(world_size.x), int(world_size.y), false, Image.FORMAT_RGBA8)
	fog_image.fill(fog_color)
	fog_texture = ImageTexture.create_from_image(fog_image)

func _update_fog():
	if not player_ref:
		return
	
	var player_world_pos = player_ref.global_position
	
	# Clear fog around player
	var clear_radius = int(visibility_radius)
	var player_fog_pos = world_to_fog_coords(player_world_pos)
	
	for x in range(-clear_radius, clear_radius):
		for y in range(-clear_radius, clear_radius):
			var pos = player_fog_pos + Vector2i(x, y)
			if pos.x >= 0 and pos.x < fog_image.get_width() and pos.y >= 0 and pos.y < fog_image.get_height():
				var distance = Vector2(x, y).length()
				if distance <= clear_radius:
					var alpha = 0.0 if distance < clear_radius * 0.8 else (distance - clear_radius * 0.8) / (clear_radius * 0.2) * fog_color.a
					fog_image.set_pixelv(pos, Color(fog_color.r, fog_color.g, fog_color.b, alpha))
	
	fog_texture.update(fog_image)
	
	if persistent_fog:
		discovered_areas.append(player_world_pos)

func add_marker(id: String, node: Node2D, icon: Texture2D = null, color: Color = Color.WHITE, priority: int = 0):
	tracked_objects[id] = {
		"node": node,
		"icon": icon if icon else objective_icon,
		"color": color,
		"priority": priority
	}

func remove_marker(id: String):
	if tracked_objects.has(id):
		tracked_objects.erase(id)
	
	if marker_nodes.has(id):
		marker_nodes[id].queue_free()
		marker_nodes.erase(id)

func add_custom_marker(id: String, position: Vector2, icon: Texture2D, color: Color = Color.WHITE, label: String = ""):
	custom_markers[id] = MinimapMarker.new()
	custom_markers[id].id = id
	custom_markers[id].position = position
	custom_markers[id].icon = icon
	custom_markers[id].color = color
	custom_markers[id].label = label

func zoom_in():
	if current_zoom_index < zoom_levels.size() - 1:
		current_zoom_index += 1
		_update_zoom()

func zoom_out():
	if current_zoom_index > 0:
		current_zoom_index -= 1
		_update_zoom()

func _update_zoom():
	zoom_level = zoom_levels[current_zoom_index]
	camera.zoom = Vector2.ONE * zoom_level
	zoom_changed.emit(zoom_level)

func world_to_minimap(world_pos: Vector2) -> Vector2:
	if not follow_player:
		return (world_pos / world_size) * minimap_size
	
	var relative_pos = world_pos - camera.global_position
	relative_pos *= zoom_level
	return minimap_size / 2 + relative_pos

func minimap_to_world(minimap_pos: Vector2) -> Vector2:
	if not follow_player:
		return (minimap_pos / minimap_size) * world_size
	
	var relative_pos = minimap_pos - minimap_size / 2
	relative_pos /= zoom_level
	return camera.global_position + relative_pos

func world_to_fog_coords(world_pos: Vector2) -> Vector2i:
	var normalized = world_pos / world_size
	return Vector2i(normalized * Vector2(fog_image.get_width(), fog_image.get_height()))

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				var world_pos = minimap_to_world(event.position)
				_check_marker_click(event.position)
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom_in()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom_out()

func _check_marker_click(click_pos: Vector2):
	for id in marker_nodes:
		var marker = marker_nodes[id]
		var marker_rect = Rect2(marker.position - Vector2(4, 4), Vector2(8, 8))
		if marker_rect.has_point(click_pos):
			marker_clicked.emit(id)
			break

func set_world_bounds(bounds: Rect2):
	world_size = bounds.size

func clear_fog():
	if fog_enabled and fog_image:
		fog_image.fill(Color.TRANSPARENT)
		fog_texture.update(fog_image)

func save_discovered_areas() -> Dictionary:
	return {
		"discovered": discovered_areas,
		"fog_data": fog_image.get_data() if fog_enabled else []
	}

func load_discovered_areas(data: Dictionary):
	discovered_areas = data.get("discovered", PackedVector2Array())
	
	if fog_enabled and data.has("fog_data"):
		# Restore fog image from saved data
		pass