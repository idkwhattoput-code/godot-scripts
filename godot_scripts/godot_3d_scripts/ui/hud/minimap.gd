extends Control

export var map_size = Vector2(200, 200)
export var world_size = Vector2(1000, 1000)
export var zoom_level = 1.0
export var min_zoom = 0.5
export var max_zoom = 3.0
export var follow_player = true
export var rotate_with_player = false
export var show_icons = true
export var show_fog_of_war = true
export var discovery_radius = 50.0

var player_position = Vector3.ZERO
var player_rotation = 0.0
var map_center = Vector2.ZERO
var discovered_areas = {}
var map_markers = []

onready var map_viewport = $MapViewport
onready var map_camera = $MapViewport/Camera2D
onready var map_display = $MapDisplay
onready var player_icon = $MapDisplay/PlayerIcon
onready var marker_container = $MapDisplay/MarkerContainer
onready var fog_overlay = $MapDisplay/FogOverlay
onready var border = $Border
onready var zoom_buttons = $ZoomButtons
onready var coords_label = $CoordsLabel

signal marker_clicked(marker_data)
signal map_clicked(world_position)

class MapMarker:
	var id: String = ""
	var world_position: Vector3 = Vector3.ZERO
	var icon_texture: Texture = null
	var icon_color: Color = Color.white
	var label: String = ""
	var visible: bool = true
	var discovered: bool = false
	var marker_type: String = "generic"
	var custom_data: Dictionary = {}

func _ready():
	_setup_ui()
	_connect_signals()
	_initialize_fog_of_war()
	
	set_process(true)

func _setup_ui():
	rect_size = map_size
	map_display.rect_size = map_size
	
	if border:
		border.rect_size = map_size + Vector2(4, 4)
		border.rect_position = Vector2(-2, -2)
	
	player_icon.position = map_size / 2
	
	if coords_label:
		coords_label.text = "0, 0"

func _connect_signals():
	if zoom_buttons:
		zoom_buttons.get_node("ZoomIn").connect("pressed", self, "_on_zoom_in")
		zoom_buttons.get_node("ZoomOut").connect("pressed", self, "_on_zoom_out")
	
	map_display.connect("gui_input", self, "_on_map_input")

func _initialize_fog_of_war():
	if not show_fog_of_war or not fog_overlay:
		return
	
	# Create fog texture
	var fog_image = Image.new()
	fog_image.create(int(world_size.x), int(world_size.y), false, Image.FORMAT_RGBA8)
	fog_image.fill(Color(0, 0, 0, 0.8))
	
	var fog_texture = ImageTexture.new()
	fog_texture.create_from_image(fog_image)
	fog_overlay.texture = fog_texture

func _process(delta):
	if follow_player:
		map_center = Vector2(player_position.x, player_position.z)
	
	_update_player_icon()
	_update_markers()
	_update_fog_of_war()
	_update_coordinates()

func update_player_position(position: Vector3):
	player_position = position
	
	if show_fog_of_war:
		_discover_area(Vector2(position.x, position.z))

func update_player_rotation(rotation: float):
	player_rotation = rotation
	
	if rotate_with_player:
		map_display.rect_rotation = -rad2deg(rotation)

func _update_player_icon():
	if not follow_player:
		var map_pos = world_to_map_position(Vector2(player_position.x, player_position.z))
		player_icon.position = map_pos
	else:
		player_icon.position = map_size / 2
	
	player_icon.rotation = player_rotation

func _update_markers():
	# Clear existing marker visuals
	for child in marker_container.get_children():
		child.queue_free()
	
	for marker in map_markers:
		if not marker.visible:
			continue
		
		if show_fog_of_war and not marker.discovered:
			continue
		
		var marker_pos = world_to_map_position(Vector2(marker.world_position.x, marker.world_position.z))
		
		# Check if marker is within map bounds
		if not Rect2(Vector2.ZERO, map_size).has_point(marker_pos):
			continue
		
		var marker_node = TextureRect.new()
		marker_node.texture = marker.icon_texture
		marker_node.modulate = marker.icon_color
		marker_node.rect_position = marker_pos - marker_node.texture.get_size() / 2
		marker_node.mouse_filter = Control.MOUSE_FILTER_PASS
		marker_node.connect("gui_input", self, "_on_marker_input", [marker])
		
		marker_container.add_child(marker_node)
		
		if marker.label != "":
			var label = Label.new()
			label.text = marker.label
			label.rect_position = marker_pos + Vector2(0, 10)
			label.add_font_override("font", preload("res://fonts/minimap_font.tres"))
			marker_container.add_child(label)

func _update_fog_of_war():
	if not show_fog_of_war or not fog_overlay:
		return
	
	# Update fog texture based on discovered areas
	# This is simplified - in practice you'd use a more efficient method
	pass

func _update_coordinates():
	if coords_label:
		coords_label.text = "%d, %d" % [int(player_position.x), int(player_position.z)]

func _discover_area(world_pos: Vector2):
	var grid_pos = world_pos / discovery_radius
	grid_pos = grid_pos.floor()
	
	var key = "%d,%d" % [grid_pos.x, grid_pos.y]
	discovered_areas[key] = true
	
	# Update fog texture
	if fog_overlay and fog_overlay.texture:
		# Clear fog in discovered area
		pass

func world_to_map_position(world_pos: Vector2) -> Vector2:
	var relative_pos = world_pos - map_center
	relative_pos = relative_pos / world_size * map_size * zoom_level
	return map_size / 2 + relative_pos

func map_to_world_position(map_pos: Vector2) -> Vector2:
	var relative_pos = map_pos - map_size / 2
	relative_pos = relative_pos / (map_size * zoom_level) * world_size
	return map_center + relative_pos

func add_marker(marker: MapMarker):
	map_markers.append(marker)

func remove_marker(marker_id: String):
	for i in range(map_markers.size() - 1, -1, -1):
		if map_markers[i].id == marker_id:
			map_markers.remove(i)
			break

func update_marker(marker_id: String, property: String, value):
	for marker in map_markers:
		if marker.id == marker_id:
			marker.set(property, value)
			break

func clear_markers():
	map_markers.clear()

func set_zoom(level: float):
	zoom_level = clamp(level, min_zoom, max_zoom)

func _on_zoom_in():
	set_zoom(zoom_level + 0.25)

func _on_zoom_out():
	set_zoom(zoom_level - 0.25)

func _on_map_input(event):
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == BUTTON_LEFT:
			var world_pos = map_to_world_position(event.position)
			emit_signal("map_clicked", Vector3(world_pos.x, 0, world_pos.y))

func _on_marker_input(event, marker):
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == BUTTON_LEFT:
			emit_signal("marker_clicked", marker)

func toggle_follow_mode():
	follow_player = !follow_player

func toggle_rotation_mode():
	rotate_with_player = !rotate_with_player

func set_map_texture(texture: Texture):
	if map_display:
		map_display.texture = texture

func reveal_all():
	show_fog_of_war = false
	if fog_overlay:
		fog_overlay.hide()

func reset_fog():
	discovered_areas.clear()
	show_fog_of_war = true
	if fog_overlay:
		fog_overlay.show()
	_initialize_fog_of_war()

func take_screenshot() -> Image:
	yield(VisualServer, "frame_post_draw")
	return map_viewport.get_texture().get_data()

func load_custom_markers(file_path: String):
	var file = File.new()
	if file.open(file_path, File.READ) != OK:
		return
	
	clear_markers()
	
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line == "":
			continue
		
		var parts = line.split(",")
		if parts.size() >= 4:
			var marker = MapMarker.new()
			marker.id = parts[0]
			marker.world_position = Vector3(float(parts[1]), 0, float(parts[2]))
			marker.label = parts[3]
			marker.marker_type = parts[4] if parts.size() > 4 else "generic"
			
			add_marker(marker)
	
	file.close()