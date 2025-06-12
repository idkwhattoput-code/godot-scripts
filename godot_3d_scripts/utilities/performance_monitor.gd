extends Control

export var update_interval = 0.5
export var show_fps = true
export var show_memory = true
export var show_draw_calls = true
export var show_physics = true
export var show_nodes = true

var update_timer = 0.0
var fps_history = []
var max_history = 60

onready var fps_label = $Panel/VBox/FPSLabel
onready var memory_label = $Panel/VBox/MemoryLabel
onready var draw_calls_label = $Panel/VBox/DrawCallsLabel
onready var physics_label = $Panel/VBox/PhysicsLabel
onready var nodes_label = $Panel/VBox/NodesLabel
onready var fps_graph = $Panel/VBox/FPSGraph

signal performance_data_updated(data)

func _ready():
	_setup_ui()
	set_process(true)

func _setup_ui():
	var panel = Panel.new()
	panel.rect_min_size = Vector2(200, 150)
	add_child(panel)
	
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)
	
	fps_label = Label.new()
	memory_label = Label.new()
	draw_calls_label = Label.new()
	physics_label = Label.new()
	nodes_label = Label.new()
	
	vbox.add_child(fps_label)
	vbox.add_child(memory_label)
	vbox.add_child(draw_calls_label)
	vbox.add_child(physics_label)
	vbox.add_child(nodes_label)

func _process(delta):
	update_timer += delta
	
	if update_timer >= update_interval:
		update_timer = 0.0
		_update_performance_data()

func _update_performance_data():
	var data = {}
	
	if show_fps:
		var fps = Engine.get_frames_per_second()
		data.fps = fps
		fps_history.append(fps)
		if fps_history.size() > max_history:
			fps_history.pop_front()
		
		fps_label.text = "FPS: %d (%.2f ms)" % [fps, 1000.0 / max(fps, 1)]
		
		var avg_fps = 0
		for f in fps_history:
			avg_fps += f
		avg_fps /= fps_history.size()
		fps_label.text += "\nAvg: %d" % avg_fps
	
	if show_memory:
		var static_memory = OS.get_static_memory_usage() / 1048576.0
		var dynamic_memory = OS.get_dynamic_memory_usage() / 1048576.0
		data.static_memory = static_memory
		data.dynamic_memory = dynamic_memory
		
		memory_label.text = "Memory: %.1f MB\nDynamic: %.1f MB" % [static_memory, dynamic_memory]
	
	if show_draw_calls:
		var draw_calls = Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME)
		var material_changes = Performance.get_monitor(Performance.RENDER_MATERIAL_CHANGES_IN_FRAME)
		var shader_changes = Performance.get_monitor(Performance.RENDER_SHADER_CHANGES_IN_FRAME)
		data.draw_calls = draw_calls
		
		draw_calls_label.text = "Draw Calls: %d\nMat Changes: %d\nShader Changes: %d" % [draw_calls, material_changes, shader_changes]
	
	if show_physics:
		var physics_process = Performance.get_monitor(Performance.PHYSICS_PROCESS_TIME) * 1000
		var active_bodies = Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)
		var collision_pairs = Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)
		data.physics_time = physics_process
		
		physics_label.text = "Physics: %.2f ms\nActive: %d\nPairs: %d" % [physics_process, active_bodies, collision_pairs]
	
	if show_nodes:
		var node_count = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		var resource_count = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
		data.node_count = node_count
		
		nodes_label.text = "Nodes: %d\nResources: %d" % [node_count, resource_count]
	
	emit_signal("performance_data_updated", data)
	
	if fps_graph:
		fps_graph.update()

func toggle_visibility():
	visible = !visible

func set_position(pos: Vector2):
	rect_position = pos

func enable_metric(metric: String, enabled: bool):
	match metric:
		"fps":
			show_fps = enabled
			fps_label.visible = enabled
		"memory":
			show_memory = enabled
			memory_label.visible = enabled
		"draw_calls":
			show_draw_calls = enabled
			draw_calls_label.visible = enabled
		"physics":
			show_physics = enabled
			physics_label.visible = enabled
		"nodes":
			show_nodes = enabled
			nodes_label.visible = enabled

func get_performance_report() -> Dictionary:
	return {
		"fps": {
			"current": Engine.get_frames_per_second(),
			"average": _calculate_average_fps(),
			"min": fps_history.min() if fps_history.size() > 0 else 0,
			"max": fps_history.max() if fps_history.size() > 0 else 0
		},
		"memory": {
			"static": OS.get_static_memory_usage() / 1048576.0,
			"dynamic": OS.get_dynamic_memory_usage() / 1048576.0,
			"peak": OS.get_static_memory_peak_usage() / 1048576.0
		},
		"rendering": {
			"draw_calls": Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME),
			"vertices": Performance.get_monitor(Performance.RENDER_VERTICES_IN_FRAME),
			"material_changes": Performance.get_monitor(Performance.RENDER_MATERIAL_CHANGES_IN_FRAME),
			"shader_changes": Performance.get_monitor(Performance.RENDER_SHADER_CHANGES_IN_FRAME)
		},
		"physics": {
			"process_time": Performance.get_monitor(Performance.PHYSICS_PROCESS_TIME),
			"active_objects": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
			"collision_pairs": Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
			"islands": Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)
		},
		"objects": {
			"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
			"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
		}
	}

func _calculate_average_fps() -> float:
	if fps_history.size() == 0:
		return 0
	
	var sum = 0
	for fps in fps_history:
		sum += fps
	
	return sum / fps_history.size()

func start_profiling():
	fps_history.clear()
	update_timer = 0.0

func stop_profiling() -> Dictionary:
	return get_performance_report()

func export_performance_log(filepath: String):
	var file = File.new()
	if file.open(filepath, File.WRITE) != OK:
		push_error("Failed to open file for writing: " + filepath)
		return
	
	var report = get_performance_report()
	file.store_string(to_json(report))
	file.close()