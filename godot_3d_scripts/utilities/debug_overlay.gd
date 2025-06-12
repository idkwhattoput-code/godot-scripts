extends CanvasLayer

# Debug Overlay System for Godot 3D
# Displays performance metrics, debug information, and development tools
# Highly configurable with various display modes

# Display settings
export var enabled = true
export var toggle_key = KEY_F3
export var text_color = Color.white
export var background_color = Color(0, 0, 0, 0.7)
export var font_size = 14
export var margin = 10

# Performance metrics
export var show_fps = true
export var show_frame_time = true
export var show_physics_fps = true
export var show_memory_usage = true
export var show_object_count = true
export var show_draw_calls = true
export var show_vertex_count = true

# Debug information
export var show_position = true
export var show_rotation = true
export var show_velocity = true
export var show_custom_properties = true

# Graphs
export var show_fps_graph = true
export var graph_size = Vector2(200, 100)
export var graph_history_size = 60
export var graph_update_rate = 0.1

# Development tools
export var show_collision_shapes = false
export var show_navigation_mesh = false
export var show_light_bounds = false
export var wireframe_mode = false

# Internal variables
var debug_panel: Panel
var debug_label: RichTextLabel
var fps_graph: Control
var graph_data = {
	"fps": [],
	"frame_time": [],
	"physics_fps": []
}
var graph_timer = 0.0
var tracked_object: Spatial
var custom_properties = {}

# Performance tracking
var frame_count = 0
var time_elapsed = 0.0
var fps = 0
var min_fps = 999
var max_fps = 0
var avg_fps = 0

func _ready():
	# Create UI elements
	create_debug_ui()
	
	# Initialize graphs
	initialize_graphs()
	
	# Find player or camera to track
	find_tracked_object()

func create_debug_ui():
	"""Create debug UI elements"""
	# Main panel
	debug_panel = Panel.new()
	debug_panel.name = "DebugPanel"
	debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(debug_panel)
	
	# Style panel
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = background_color
	panel_style.corner_radius_top_left = 5
	panel_style.corner_radius_top_right = 5
	panel_style.corner_radius_bottom_left = 5
	panel_style.corner_radius_bottom_right = 5
	debug_panel.add_stylebox_override("panel", panel_style)
	
	# Debug text label
	debug_label = RichTextLabel.new()
	debug_label.name = "DebugLabel"
	debug_label.bbcode_enabled = true
	debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_panel.add_child(debug_label)
	
	# Position elements
	update_ui_positions()

func initialize_graphs():
	"""Initialize performance graphs"""
	if not show_fps_graph:
		return
	
	fps_graph = Control.new()
	fps_graph.name = "FPSGraph"
	fps_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_graph.rect_size = graph_size
	debug_panel.add_child(fps_graph)
	
	# Connect draw signal
	fps_graph.connect("draw", self, "_draw_fps_graph")

func find_tracked_object():
	"""Find object to track (player or camera)"""
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		tracked_object = players[0]
	else:
		var camera = get_viewport().get_camera()
		if camera:
			tracked_object = camera

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.scancode == toggle_key:
			enabled = !enabled
			debug_panel.visible = enabled

func _process(delta):
	if not enabled:
		return
	
	# Update performance metrics
	update_performance_metrics(delta)
	
	# Update graphs
	if show_fps_graph:
		update_graph_data(delta)
	
	# Update debug text
	update_debug_text()

func update_performance_metrics(delta):
	"""Calculate performance metrics"""
	frame_count += 1
	time_elapsed += delta
	
	if time_elapsed >= 1.0:
		fps = frame_count
		min_fps = min(min_fps, fps)
		max_fps = max(max_fps, fps)
		avg_fps = (avg_fps + fps) / 2
		
		frame_count = 0
		time_elapsed = 0.0

func update_graph_data(delta):
	"""Update graph data arrays"""
	graph_timer += delta
	
	if graph_timer >= graph_update_rate:
		graph_timer = 0.0
		
		# Add new data points
		graph_data.fps.append(Engine.get_frames_per_second())
		graph_data.frame_time.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000)
		graph_data.physics_fps.append(Engine.iterations_per_second)
		
		# Limit array size
		for key in graph_data:
			if graph_data[key].size() > graph_history_size:
				graph_data[key].pop_front()
		
		# Redraw graph
		if fps_graph:
			fps_graph.update()

func update_debug_text():
	"""Update debug information text"""
	var text = ""
	
	# Performance section
	if show_fps or show_frame_time or show_physics_fps:
		text += "[b][color=#00ff00]Performance[/color][/b]\n"
		
		if show_fps:
			var current_fps = Engine.get_frames_per_second()
			var fps_color = "#00ff00" if current_fps >= 60 else "#ffff00" if current_fps >= 30 else "#ff0000"
			text += "FPS: [color=%s]%d[/color] (Min: %d, Max: %d, Avg: %d)\n" % [fps_color, current_fps, min_fps, max_fps, avg_fps]
		
		if show_frame_time:
			var frame_time = Performance.get_monitor(Performance.TIME_PROCESS) * 1000
			text += "Frame Time: %.2f ms\n" % frame_time
		
		if show_physics_fps:
			text += "Physics FPS: %d\n" % Engine.iterations_per_second
		
		text += "\n"
	
	# Memory section
	if show_memory_usage:
		text += "[b][color=#00ff00]Memory[/color][/b]\n"
		text += "Static: %.2f MB\n" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
		text += "Dynamic: %.2f MB\n" % (Performance.get_monitor(Performance.MEMORY_DYNAMIC) / 1048576.0)
		text += "Message Buffer: %.2f MB\n" % (Performance.get_monitor(Performance.MEMORY_MESSAGE_BUFFER_MAX) / 1048576.0)
		text += "\n"
	
	# Rendering section
	if show_object_count or show_draw_calls or show_vertex_count:
		text += "[b][color=#00ff00]Rendering[/color][/b]\n"
		
		if show_object_count:
			text += "Objects: %d\n" % Performance.get_monitor(Performance.OBJECT_COUNT)
			text += "Resources: %d\n" % Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
			text += "Nodes: %d\n" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		
		if show_draw_calls:
			text += "Draw Calls: %d\n" % Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME)
			text += "Material Changes: %d\n" % Performance.get_monitor(Performance.RENDER_MATERIAL_CHANGES_IN_FRAME)
			text += "Shader Changes: %d\n" % Performance.get_monitor(Performance.RENDER_SHADER_CHANGES_IN_FRAME)
		
		if show_vertex_count:
			text += "Vertices: %d\n" % Performance.get_monitor(Performance.RENDER_VERTICES_IN_FRAME)
		
		text += "\n"
	
	# Object tracking section
	if tracked_object and (show_position or show_rotation or show_velocity):
		text += "[b][color=#00ff00]%s[/color][/b]\n" % tracked_object.name
		
		if show_position:
			var pos = tracked_object.global_transform.origin
			text += "Position: (%.2f, %.2f, %.2f)\n" % [pos.x, pos.y, pos.z]
		
		if show_rotation:
			var rot = tracked_object.rotation_degrees
			text += "Rotation: (%.1f°, %.1f°, %.1f°)\n" % [rot.x, rot.y, rot.z]
		
		if show_velocity and tracked_object.has_method("get_velocity"):
			var vel = tracked_object.get_velocity()
			var speed = vel.length()
			text += "Velocity: %.2f m/s\n" % speed
			text += "Direction: (%.2f, %.2f, %.2f)\n" % [vel.x, vel.y, vel.z]
		
		text += "\n"
	
	# Custom properties section
	if show_custom_properties and custom_properties.size() > 0:
		text += "[b][color=#00ff00]Custom Properties[/color][/b]\n"
		for key in custom_properties:
			text += "%s: %s\n" % [key, str(custom_properties[key])]
	
	debug_label.bbcode_text = text

func _draw_fps_graph():
	"""Draw FPS graph"""
	if not fps_graph or graph_data.fps.size() < 2:
		return
	
	var rect = Rect2(Vector2.ZERO, graph_size)
	
	# Background
	fps_graph.draw_rect(rect, Color(0, 0, 0, 0.5))
	
	# Grid lines
	for i in range(5):
		var y = rect.size.y * (i / 4.0)
		fps_graph.draw_line(Vector2(0, y), Vector2(rect.size.x, y), Color(1, 1, 1, 0.2))
	
	# Reference lines
	var target_fps_y = rect.size.y - (60.0 / 120.0) * rect.size.y  # 60 FPS line
	fps_graph.draw_line(Vector2(0, target_fps_y), Vector2(rect.size.x, target_fps_y), Color(0, 1, 0, 0.5))
	
	# Draw FPS curve
	draw_graph_line(graph_data.fps, Color(0, 1, 0), 0, 120)
	
	# Draw frame time curve (scaled)
	if graph_data.frame_time.size() > 1:
		draw_graph_line(graph_data.frame_time, Color(1, 1, 0), 0, 33.33)  # 33.33ms = 30 FPS

func draw_graph_line(data: Array, color: Color, min_value: float, max_value: float):
	"""Draw a line graph from data array"""
	if data.size() < 2:
		return
	
	var points = []
	var x_step = graph_size.x / float(graph_history_size - 1)
	
	for i in range(data.size()):
		var value = clamp(data[i], min_value, max_value)
		var normalized = (value - min_value) / (max_value - min_value)
		var x = i * x_step
		var y = graph_size.y - (normalized * graph_size.y)
		points.append(Vector2(x, y))
	
	# Draw lines between points
	for i in range(points.size() - 1):
		fps_graph.draw_line(points[i], points[i + 1], color, 2.0)

func update_ui_positions():
	"""Update UI element positions"""
	var viewport_size = get_viewport().size
	
	# Position panel
	debug_panel.rect_position = Vector2(margin, margin)
	debug_panel.rect_size = Vector2(400, viewport_size.y - margin * 2)
	
	# Position label
	debug_label.rect_position = Vector2(margin, margin)
	debug_label.rect_size = debug_panel.rect_size - Vector2(margin * 2, margin * 2)
	
	# Position graph
	if fps_graph:
		fps_graph.rect_position = Vector2(
			debug_panel.rect_size.x - graph_size.x - margin,
			debug_panel.rect_size.y - graph_size.y - margin
		)

# Public API
func add_custom_property(key: String, value):
	"""Add a custom property to display"""
	custom_properties[key] = value

func remove_custom_property(key: String):
	"""Remove a custom property"""
	custom_properties.erase(key)

func set_tracked_object(object: Spatial):
	"""Set the object to track"""
	tracked_object = object

func toggle_debug_mode(mode: String, enabled: bool):
	"""Toggle specific debug visualization modes"""
	match mode:
		"collision":
			show_collision_shapes = enabled
			get_tree().debug_collisions_hint = enabled
		"navigation":
			show_navigation_mesh = enabled
			get_tree().debug_navigation_hint = enabled
		"wireframe":
			wireframe_mode = enabled
			# Apply wireframe mode to viewport
			get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if enabled else Viewport.DEBUG_DRAW_DISABLED

func capture_performance_snapshot() -> Dictionary:
	"""Capture current performance metrics"""
	return {
		"fps": Engine.get_frames_per_second(),
		"frame_time": Performance.get_monitor(Performance.TIME_PROCESS) * 1000,
		"physics_fps": Engine.iterations_per_second,
		"memory_static": Performance.get_monitor(Performance.MEMORY_STATIC),
		"memory_dynamic": Performance.get_monitor(Performance.MEMORY_DYNAMIC),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"draw_calls": Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME),
		"vertices": Performance.get_monitor(Performance.RENDER_VERTICES_IN_FRAME),
		"timestamp": OS.get_unix_time()
	}

func export_performance_log(filepath: String):
	"""Export performance data to file"""
	var file = File.new()
	if file.open(filepath, File.WRITE) != OK:
		push_error("Failed to open file for performance log export")
		return
	
	# Write header
	file.store_line("Godot Performance Log")
	file.store_line("Generated: " + str(OS.get_datetime()))
	file.store_line("")
	
	# Write current metrics
	var snapshot = capture_performance_snapshot()
	for key in snapshot:
		file.store_line("%s: %s" % [key, str(snapshot[key])])
	
	file.close()