extends Spatial

class_name VRDrawingTools

signal stroke_started(tool, position)
signal stroke_updated(tool, position)
signal stroke_ended(tool)
signal tool_changed(old_tool, new_tool)
signal color_changed(color)
signal brush_size_changed(size)
signal drawing_cleared()
signal drawing_saved(path)
signal shape_created(shape_type, shape_data)

enum DrawingTool {
	BRUSH,
	MARKER,
	PENCIL,
	ERASER,
	SPRAY_PAINT,
	CALLIGRAPHY,
	SHAPE_TOOL,
	TEXT_TOOL,
	FILL_TOOL,
	MEASURE_TOOL
}

enum ShapeType {
	LINE,
	RECTANGLE,
	CIRCLE,
	TRIANGLE,
	POLYGON,
	STAR,
	ARROW
}

export var current_tool: int = DrawingTool.BRUSH
export var current_color: Color = Color.white
export var brush_size: float = 0.01
export var brush_opacity: float = 1.0
export var enable_pressure_sensitivity: bool = true
export var smooth_strokes: bool = true
export var smoothing_factor: float = 0.3
export var enable_3d_drawing: bool = true
export var drawing_distance: float = 1.0
export var enable_surfaces: bool = true
export var snap_to_surface: bool = false
export var surface_offset: float = 0.001
export var enable_layers: bool = true
export var max_layers: int = 10
export var enable_undo_redo: bool = true
export var max_undo_steps: int = 50
export var auto_save: bool = true
export var auto_save_interval: float = 60.0

var controller: ARVRController
var current_stroke: Stroke
var strokes: Array = []
var stroke_meshes: Array = []
var layers: Array = []
var current_layer: int = 0
var undo_history: Array = []
var redo_history: Array = []
var drawing_surface: StaticBody
var preview_mesh: MeshInstance
var tool_mesh: MeshInstance
var color_palette: ColorPalette
var brush_settings: BrushSettings
var shape_preview: ShapePreview
var text_input: TextInput3D
var measure_tool: MeasureTool
var is_drawing: bool = false
var last_save_time: float = 0.0

class Stroke:
	var points: PoolVector3Array = PoolVector3Array()
	var colors: PoolColorArray = PoolColorArray()
	var widths: PoolRealArray = PoolRealArray()
	var tool: int
	var layer: int
	var timestamp: float
	var mesh_instance: MeshInstance
	
	func _init(t: int, l: int):
		tool = t
		layer = l
		timestamp = OS.get_ticks_msec() / 1000.0
	
	func add_point(position: Vector3, color: Color, width: float):
		points.append(position)
		colors.append(color)
		widths.append(width)
	
	func simplify(tolerance: float = 0.001):
		if points.size() < 3:
			return
		
		var simplified_points = PoolVector3Array()
		var simplified_colors = PoolColorArray()
		var simplified_widths = PoolRealArray()
		
		simplified_points.append(points[0])
		simplified_colors.append(colors[0])
		simplified_widths.append(widths[0])
		
		var last_index = 0
		for i in range(1, points.size() - 1):
			var distance = point_line_distance(points[i], points[last_index], points[points.size() - 1])
			if distance > tolerance:
				simplified_points.append(points[i])
				simplified_colors.append(colors[i])
				simplified_widths.append(widths[i])
				last_index = i
		
		simplified_points.append(points[points.size() - 1])
		simplified_colors.append(colors[colors.size() - 1])
		simplified_widths.append(widths[widths.size() - 1])
		
		points = simplified_points
		colors = simplified_colors
		widths = simplified_widths
	
	func point_line_distance(point: Vector3, line_start: Vector3, line_end: Vector3) -> float:
		var line_vec = line_end - line_start
		var point_vec = point - line_start
		var line_len = line_vec.length()
		var line_unitvec = line_vec.normalized()
		var point_vec_scaled = point_vec.dot(line_unitvec) / line_len
		
		if point_vec_scaled < 0.0:
			return point.distance_to(line_start)
		elif point_vec_scaled > 1.0:
			return point.distance_to(line_end)
		else:
			var nearest = line_vec * point_vec_scaled
			return (point_vec - nearest).length()

class Layer:
	var name: String
	var visible: bool = true
	var locked: bool = false
	var opacity: float = 1.0
	var strokes: Array = []
	var node: Spatial
	
	func _init(layer_name: String):
		name = layer_name
		node = Spatial.new()

class ColorPalette:
	var colors: Array = [
		Color.white,
		Color.black,
		Color.red,
		Color.green,
		Color.blue,
		Color.yellow,
		Color.cyan,
		Color.magenta,
		Color.orange,
		Color.purple
	]
	var custom_colors: Array = []
	
	func add_custom_color(color: Color):
		if custom_colors.size() >= 10:
			custom_colors.pop_front()
		custom_colors.append(color)

class BrushSettings:
	var size_curve: Curve
	var opacity_curve: Curve
	var spacing: float = 0.1
	var jitter: float = 0.0
	var texture: Texture
	var blend_mode: int = 0
	
	func _init():
		size_curve = Curve.new()
		size_curve.add_point(Vector2(0, 1))
		size_curve.add_point(Vector2(1, 1))
		
		opacity_curve = Curve.new()
		opacity_curve.add_point(Vector2(0, 1))
		opacity_curve.add_point(Vector2(1, 1))

class ShapePreview:
	var mesh_instance: MeshInstance
	var shape_type: int = ShapeType.LINE
	var start_point: Vector3
	var end_point: Vector3
	var preview_points: PoolVector3Array
	
	func update_preview(start: Vector3, end: Vector3, shape: int):
		start_point = start
		end_point = end
		shape_type = shape
		
		match shape_type:
			ShapeType.LINE:
				preview_points = PoolVector3Array([start, end])
			ShapeType.RECTANGLE:
				preview_points = create_rectangle_points(start, end)
			ShapeType.CIRCLE:
				preview_points = create_circle_points(start, start.distance_to(end))
			ShapeType.TRIANGLE:
				preview_points = create_triangle_points(start, end)
	
	func create_rectangle_points(start: Vector3, end: Vector3) -> PoolVector3Array:
		var points = PoolVector3Array()
		points.append(start)
		points.append(Vector3(end.x, start.y, start.z))
		points.append(end)
		points.append(Vector3(start.x, end.y, end.z))
		points.append(start)
		return points
	
	func create_circle_points(center: Vector3, radius: float, segments: int = 32) -> PoolVector3Array:
		var points = PoolVector3Array()
		for i in range(segments + 1):
			var angle = (i / float(segments)) * TAU
			var x = center.x + cos(angle) * radius
			var z = center.z + sin(angle) * radius
			points.append(Vector3(x, center.y, z))
		return points
	
	func create_triangle_points(start: Vector3, end: Vector3) -> PoolVector3Array:
		var points = PoolVector3Array()
		var mid_x = (start.x + end.x) / 2
		points.append(start)
		points.append(Vector3(mid_x, end.y, start.z))
		points.append(end)
		points.append(start)
		return points

class TextInput3D:
	var text: String = ""
	var font_size: float = 0.1
	var font: DynamicFont
	var mesh_instance: MeshInstance
	
	func create_text_mesh(text_string: String, position: Vector3) -> MeshInstance:
		return MeshInstance.new()

class MeasureTool:
	var start_point: Vector3
	var end_point: Vector3
	var measurement_line: MeshInstance
	var measurement_label: Label3D
	var is_measuring: bool = false
	
	func start_measurement(point: Vector3):
		start_point = point
		is_measuring = true
	
	func update_measurement(point: Vector3):
		end_point = point
		var distance = start_point.distance_to(end_point)
		update_display(distance)
	
	func update_display(distance: float):
		pass

func _ready():
	setup_controller()
	setup_layers()
	setup_tools()
	setup_preview()
	setup_drawing_surface()
	
	color_palette = ColorPalette.new()
	brush_settings = BrushSettings.new()
	shape_preview = ShapePreview.new()
	text_input = TextInput3D.new()
	measure_tool = MeasureTool.new()

func setup_controller():
	var controllers = get_tree().get_nodes_in_group("vr_controller")
	if controllers.size() > 0:
		controller = controllers[0]
		controller.connect("button_pressed", self, "_on_button_pressed")
		controller.connect("button_release", self, "_on_button_released")

func setup_layers():
	for i in range(max_layers):
		var layer = Layer.new("Layer " + str(i))
		add_child(layer.node)
		layers.append(layer)

func setup_tools():
	tool_mesh = MeshInstance.new()
	update_tool_mesh()
	if controller:
		controller.add_child(tool_mesh)

func setup_preview():
	preview_mesh = MeshInstance.new()
	var preview_material = SpatialMaterial.new()
	preview_material.albedo_color = current_color
	preview_material.vertex_color_use_as_albedo = true
	preview_mesh.material_override = preview_material
	add_child(preview_mesh)

func setup_drawing_surface():
	if enable_surfaces:
		drawing_surface = StaticBody.new()
		var collision_shape = CollisionShape.new()
		var shape = PlaneShape.new()
		collision_shape.shape = shape
		drawing_surface.add_child(collision_shape)
		add_child(drawing_surface)

func _process(delta):
	if auto_save and OS.get_ticks_msec() / 1000.0 - last_save_time > auto_save_interval:
		save_drawing()
	
	if controller and controller.is_button_pressed(15):
		update_drawing()
	
	update_preview_position()

func _on_button_pressed(button):
	match button:
		15:
			start_stroke()
		2:
			cycle_tool()
		1:
			undo()
		14:
			clear_drawing()

func _on_button_released(button):
	if button == 15:
		end_stroke()

func start_stroke():
	if is_drawing:
		return
	
	is_drawing = true
	current_stroke = Stroke.new(current_tool, current_layer)
	
	var position = get_drawing_position()
	emit_signal("stroke_started", current_tool, position)
	
	if current_tool == DrawingTool.SHAPE_TOOL:
		shape_preview.update_preview(position, position, ShapeType.LINE)
	elif current_tool == DrawingTool.MEASURE_TOOL:
		measure_tool.start_measurement(position)

func update_drawing():
	if not is_drawing or not current_stroke:
		return
	
	var position = get_drawing_position()
	var pressure = get_pressure()
	var width = brush_size * (pressure if enable_pressure_sensitivity else 1.0)
	
	match current_tool:
		DrawingTool.BRUSH, DrawingTool.MARKER, DrawingTool.PENCIL:
			add_stroke_point(position, current_color, width)
		DrawingTool.ERASER:
			erase_at_position(position, width)
		DrawingTool.SPRAY_PAINT:
			spray_paint_at_position(position, width)
		DrawingTool.SHAPE_TOOL:
			shape_preview.update_preview(shape_preview.start_point, position, ShapeType.LINE)
		DrawingTool.MEASURE_TOOL:
			measure_tool.update_measurement(position)
	
	emit_signal("stroke_updated", current_tool, position)

func end_stroke():
	if not is_drawing:
		return
	
	is_drawing = false
	
	if current_stroke and current_stroke.points.size() > 0:
		finalize_stroke()
	
	emit_signal("stroke_ended", current_tool)

func add_stroke_point(position: Vector3, color: Color, width: float):
	if smooth_strokes and current_stroke.points.size() > 0:
		var last_pos = current_stroke.points[current_stroke.points.size() - 1]
		position = last_pos.linear_interpolate(position, 1.0 - smoothing_factor)
	
	current_stroke.add_point(position, color, width)
	update_stroke_mesh()

func update_stroke_mesh():
	if not current_stroke or current_stroke.points.size() < 2:
		return
	
	if not current_stroke.mesh_instance:
		current_stroke.mesh_instance = MeshInstance.new()
		layers[current_layer].node.add_child(current_stroke.mesh_instance)
	
	var mesh = generate_stroke_mesh(current_stroke)
	current_stroke.mesh_instance.mesh = mesh

func generate_stroke_mesh(stroke: Stroke) -> Mesh:
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	
	for i in range(stroke.points.size()):
		var point = stroke.points[i]
		var color = stroke.colors[i]
		var width = stroke.widths[i]
		
		var direction = Vector3.UP
		if i > 0:
			direction = (point - stroke.points[i - 1]).normalized()
		elif i < stroke.points.size() - 1:
			direction = (stroke.points[i + 1] - point).normalized()
		
		var right = direction.cross(Vector3.UP).normalized() * width / 2
		
		surface_tool.add_color(color)
		surface_tool.add_vertex(point - right)
		surface_tool.add_color(color)
		surface_tool.add_vertex(point + right)
	
	return surface_tool.commit()

func finalize_stroke():
	if smooth_strokes:
		current_stroke.simplify()
	
	strokes.append(current_stroke)
	layers[current_layer].strokes.append(current_stroke)
	
	add_to_undo_history({
		"type": "stroke",
		"stroke": current_stroke,
		"layer": current_layer
	})
	
	current_stroke = null

func erase_at_position(position: Vector3, radius: float):
	var strokes_to_remove = []
	
	for layer in layers:
		if layer.locked:
			continue
		
		for stroke in layer.strokes:
			var should_remove = false
			
			for point in stroke.points:
				if point.distance_to(position) < radius:
					should_remove = true
					break
			
			if should_remove:
				strokes_to_remove.append({"layer": layer, "stroke": stroke})
	
	for item in strokes_to_remove:
		item.layer.strokes.erase(item.stroke)
		if item.stroke.mesh_instance:
			item.stroke.mesh_instance.queue_free()

func spray_paint_at_position(position: Vector3, radius: float):
	for i in range(10):
		var offset = Vector3(
			randf() * radius - radius / 2,
			randf() * radius - radius / 2,
			randf() * radius - radius / 2
		)
		var spray_pos = position + offset
		var spray_size = brush_size * randf_range(0.1, 0.3)
		add_stroke_point(spray_pos, current_color, spray_size)

func get_drawing_position() -> Vector3:
	if not controller:
		return Vector3.ZERO
	
	var origin = controller.global_transform.origin
	var forward = -controller.global_transform.basis.z
	
	if snap_to_surface and drawing_surface:
		var space_state = get_world().direct_space_state
		var result = space_state.intersect_ray(origin, origin + forward * drawing_distance)
		if result:
			return result.position + result.normal * surface_offset
	
	return origin + forward * drawing_distance

func get_pressure() -> float:
	if controller and controller.has_method("get_rumble"):
		return controller.get_rumble()
	return 1.0

func update_preview_position():
	if not preview_mesh or not controller:
		return
	
	var position = get_drawing_position()
	preview_mesh.global_transform.origin = position

func update_tool_mesh():
	if not tool_mesh:
		return
	
	match current_tool:
		DrawingTool.BRUSH:
			tool_mesh.mesh = create_brush_mesh()
		DrawingTool.MARKER:
			tool_mesh.mesh = create_marker_mesh()
		DrawingTool.PENCIL:
			tool_mesh.mesh = create_pencil_mesh()
		DrawingTool.ERASER:
			tool_mesh.mesh = create_eraser_mesh()

func create_brush_mesh() -> Mesh:
	var mesh = CylinderMesh.new()
	mesh.height = 0.1
	mesh.top_radius = 0.01
	mesh.bottom_radius = 0.005
	return mesh

func create_marker_mesh() -> Mesh:
	var mesh = CylinderMesh.new()
	mesh.height = 0.12
	mesh.top_radius = 0.015
	mesh.bottom_radius = 0.015
	return mesh

func create_pencil_mesh() -> Mesh:
	var mesh = CylinderMesh.new()
	mesh.height = 0.15
	mesh.top_radius = 0.003
	mesh.bottom_radius = 0.01
	return mesh

func create_eraser_mesh() -> Mesh:
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.03, 0.02, 0.04)
	return mesh

func cycle_tool():
	var old_tool = current_tool
	current_tool = (current_tool + 1) % DrawingTool.size()
	update_tool_mesh()
	emit_signal("tool_changed", old_tool, current_tool)

func set_tool(tool: int):
	if tool >= 0 and tool < DrawingTool.size():
		var old_tool = current_tool
		current_tool = tool
		update_tool_mesh()
		emit_signal("tool_changed", old_tool, current_tool)

func set_color(color: Color):
	current_color = color
	color_palette.add_custom_color(color)
	emit_signal("color_changed", color)

func set_brush_size(size: float):
	brush_size = clamp(size, 0.001, 0.1)
	emit_signal("brush_size_changed", brush_size)

func undo():
	if undo_history.empty():
		return
	
	var action = undo_history.pop_back()
	redo_history.append(action)
	
	match action.type:
		"stroke":
			var stroke = action.stroke
			layers[action.layer].strokes.erase(stroke)
			if stroke.mesh_instance:
				stroke.mesh_instance.queue_free()

func redo():
	if redo_history.empty():
		return
	
	var action = redo_history.pop_back()
	undo_history.append(action)
	
	match action.type:
		"stroke":
			var stroke = action.stroke
			layers[action.layer].strokes.append(stroke)
			if stroke.mesh_instance:
				layers[action.layer].node.add_child(stroke.mesh_instance)

func clear_drawing():
	for layer in layers:
		for stroke in layer.strokes:
			if stroke.mesh_instance:
				stroke.mesh_instance.queue_free()
		layer.strokes.clear()
	
	strokes.clear()
	undo_history.clear()
	redo_history.clear()
	
	emit_signal("drawing_cleared")

func save_drawing(path: String = "user://vr_drawing.dat"):
	var save_data = {
		"strokes": [],
		"layers": []
	}
	
	for stroke in strokes:
		save_data.strokes.append({
			"points": stroke.points,
			"colors": stroke.colors,
			"widths": stroke.widths,
			"tool": stroke.tool,
			"layer": stroke.layer
		})
	
	var file = File.new()
	file.open(path, File.WRITE)
	file.store_var(save_data)
	file.close()
	
	last_save_time = OS.get_ticks_msec() / 1000.0
	emit_signal("drawing_saved", path)

func load_drawing(path: String = "user://vr_drawing.dat"):
	var file = File.new()
	if not file.file_exists(path):
		return
	
	clear_drawing()
	
	file.open(path, File.READ)
	var save_data = file.get_var()
	file.close()
	
	for stroke_data in save_data.strokes:
		var stroke = Stroke.new(stroke_data.tool, stroke_data.layer)
		stroke.points = stroke_data.points
		stroke.colors = stroke_data.colors
		stroke.widths = stroke_data.widths
		
		stroke.mesh_instance = MeshInstance.new()
		stroke.mesh_instance.mesh = generate_stroke_mesh(stroke)
		layers[stroke.layer].node.add_child(stroke.mesh_instance)
		
		strokes.append(stroke)
		layers[stroke.layer].strokes.append(stroke)

func add_to_undo_history(action: Dictionary):
	if undo_history.size() >= max_undo_steps:
		undo_history.pop_front()
	undo_history.append(action)
	redo_history.clear()

func export_as_mesh() -> Mesh:
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for stroke in strokes:
		pass
	
	return surface_tool.commit()