extends Node2D

signal transition_started
signal transition_finished
signal level_loaded(level_name: String)

@export_group("Transition Settings")
@export var transition_duration: float = 1.0
@export var transition_type: TransitionType = TransitionType.FADE
@export var transition_color: Color = Color.BLACK
@export var pause_during_transition: bool = true
@export var save_game_state: bool = true

@export_group("Transition Effects")
@export var fade_curve: Curve
@export var slide_direction: Vector2 = Vector2.RIGHT
@export var iris_center: Vector2 = Vector2(0.5, 0.5)
@export var pixelate_max_size: int = 64
@export var custom_shader: Shader

@export_group("Level Management")
@export var preload_adjacent_levels: bool = false
@export var unload_previous_level: bool = true
@export var level_data_resource: Resource
@export var checkpoint_on_transition: bool = true

enum TransitionType {
	FADE,
	SLIDE,
	IRIS,
	PIXELATE,
	CURTAIN,
	DISSOLVE,
	CUSTOM
}

var transition_overlay: ColorRect
var shader_material: ShaderMaterial
var current_level: Node
var next_level_path: String
var transition_data: Dictionary = {}
var is_transitioning: bool = false
var loaded_levels: Dictionary = {}

func _ready():
	_create_transition_overlay()
	set_process(false)

func _create_transition_overlay():
	transition_overlay = ColorRect.new()
	transition_overlay.color = transition_color
	transition_overlay.anchor_right = 1.0
	transition_overlay.anchor_bottom = 1.0
	transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transition_overlay.modulate.a = 0.0
	
	if custom_shader:
		shader_material = ShaderMaterial.new()
		shader_material.shader = custom_shader
		transition_overlay.material = shader_material
	
	add_child(transition_overlay)
	move_child(transition_overlay, get_child_count() - 1)

func transition_to_level(level_path: String, spawn_point: String = "", data: Dictionary = {}):
	if is_transitioning:
		return
	
	is_transitioning = true
	next_level_path = level_path
	transition_data = data
	transition_data["spawn_point"] = spawn_point
	
	transition_started.emit()
	
	if pause_during_transition:
		get_tree().paused = true
		transition_overlay.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	
	if save_game_state:
		_save_current_state()
	
	# Start transition out
	await _transition_out()
	
	# Load new level
	await _load_level(level_path)
	
	# Transition in
	await _transition_in()
	
	is_transitioning = false
	transition_finished.emit()
	
	if pause_during_transition:
		get_tree().paused = false

func _transition_out():
	match transition_type:
		TransitionType.FADE:
			await _fade_transition(0.0, 1.0)
		TransitionType.SLIDE:
			await _slide_transition(true)
		TransitionType.IRIS:
			await _iris_transition(true)
		TransitionType.PIXELATE:
			await _pixelate_transition(true)
		TransitionType.CURTAIN:
			await _curtain_transition(true)
		TransitionType.DISSOLVE:
			await _dissolve_transition(true)
		TransitionType.CUSTOM:
			await _custom_transition(true)

func _transition_in():
	match transition_type:
		TransitionType.FADE:
			await _fade_transition(1.0, 0.0)
		TransitionType.SLIDE:
			await _slide_transition(false)
		TransitionType.IRIS:
			await _iris_transition(false)
		TransitionType.PIXELATE:
			await _pixelate_transition(false)
		TransitionType.CURTAIN:
			await _curtain_transition(false)
		TransitionType.DISSOLVE:
			await _dissolve_transition(false)
		TransitionType.CUSTOM:
			await _custom_transition(false)

func _fade_transition(from_alpha: float, to_alpha: float):
	var tween = create_tween()
	
	if fade_curve:
		tween.set_custom_interpolator(func(v): return fade_curve.sample(v))
	
	tween.tween_property(transition_overlay, "modulate:a", to_alpha, transition_duration / 2)
	await tween.finished

func _slide_transition(out: bool):
	var viewport_size = get_viewport_rect().size
	var start_pos = Vector2.ZERO if out else -slide_direction * viewport_size
	var end_pos = -slide_direction * viewport_size if out else Vector2.ZERO
	
	transition_overlay.position = start_pos
	transition_overlay.modulate.a = 1.0
	
	var tween = create_tween()
	tween.tween_property(transition_overlay, "position", end_pos, transition_duration / 2)
	await tween.finished

func _iris_transition(out: bool):
	if not shader_material:
		# Fallback to fade
		await _fade_transition(0.0 if out else 1.0, 1.0 if out else 0.0)
		return
	
	shader_material.set_shader_parameter("center", iris_center)
	
	var tween = create_tween()
	var from_radius = 1.5 if out else 0.0
	var to_radius = 0.0 if out else 1.5
	
	tween.tween_method(func(v): shader_material.set_shader_parameter("radius", v), 
		from_radius, to_radius, transition_duration / 2)
	await tween.finished

func _pixelate_transition(out: bool):
	if not shader_material:
		await _fade_transition(0.0 if out else 1.0, 1.0 if out else 0.0)
		return
	
	var tween = create_tween()
	var from_size = 1 if out else pixelate_max_size
	var to_size = pixelate_max_size if out else 1
	
	tween.tween_method(func(v): shader_material.set_shader_parameter("pixel_size", v), 
		from_size, to_size, transition_duration / 2)
	await tween.finished

func _curtain_transition(out: bool):
	# Create curtain effect with multiple strips
	var strips = []
	var strip_count = 10
	var viewport_width = get_viewport_rect().size.x
	var strip_width = viewport_width / strip_count
	
	for i in range(strip_count):
		var strip = ColorRect.new()
		strip.color = transition_color
		strip.size = Vector2(strip_width, get_viewport_rect().size.y)
		strip.position.x = i * strip_width
		strip.position.y = -get_viewport_rect().size.y if out else 0
		add_child(strip)
		strips.append(strip)
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	for i in range(strips.size()):
		var delay = i * 0.05
		var target_y = 0 if out else get_viewport_rect().size.y
		tween.tween_property(strips[i], "position:y", target_y, transition_duration / 2).set_delay(delay)
	
	await tween.finished
	
	for strip in strips:
		strip.queue_free()

func _dissolve_transition(out: bool):
	if not shader_material:
		await _fade_transition(0.0 if out else 1.0, 1.0 if out else 0.0)
		return
	
	var tween = create_tween()
	var from_threshold = 0.0 if out else 1.0
	var to_threshold = 1.0 if out else 0.0
	
	tween.tween_method(func(v): shader_material.set_shader_parameter("dissolve_threshold", v), 
		from_threshold, to_threshold, transition_duration / 2)
	await tween.finished

func _custom_transition(out: bool):
	if not shader_material:
		await _fade_transition(0.0 if out else 1.0, 1.0 if out else 0.0)
		return
	
	# Implement custom shader transition
	shader_material.set_shader_parameter("transition_progress", 0.0 if out else 1.0)
	
	var tween = create_tween()
	tween.tween_method(func(v): shader_material.set_shader_parameter("transition_progress", v), 
		0.0 if out else 1.0, 1.0 if out else 0.0, transition_duration / 2)
	await tween.finished

func _load_level(level_path: String):
	# Check if level is already loaded
	if loaded_levels.has(level_path):
		_switch_to_loaded_level(level_path)
		return
	
	# Load new level
	var level_scene = load(level_path)
	if not level_scene:
		push_error("Failed to load level: " + level_path)
		return
	
	var new_level = level_scene.instantiate()
	
	# Handle current level
	if current_level:
		if unload_previous_level:
			current_level.queue_free()
		else:
			current_level.visible = false
			loaded_levels[current_level.scene_file_path] = current_level
	
	# Add new level
	get_tree().current_scene.add_child(new_level)
	current_level = new_level
	
	# Set spawn point
	if transition_data.has("spawn_point") and transition_data.spawn_point != "":
		_set_player_spawn_point(transition_data.spawn_point)
	
	# Apply transition data
	if new_level.has_method("apply_transition_data"):
		new_level.apply_transition_data(transition_data)
	
	level_loaded.emit(level_path)
	
	# Preload adjacent levels if enabled
	if preload_adjacent_levels:
		_preload_adjacent_levels(level_path)

func _switch_to_loaded_level(level_path: String):
	if current_level:
		current_level.visible = false
	
	current_level = loaded_levels[level_path]
	current_level.visible = true
	
	if transition_data.has("spawn_point") and transition_data.spawn_point != "":
		_set_player_spawn_point(transition_data.spawn_point)

func _set_player_spawn_point(spawn_point_name: String):
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	
	var spawn_point = current_level.get_node_or_null("SpawnPoints/" + spawn_point_name)
	if spawn_point:
		player.global_position = spawn_point.global_position
		if player.has_method("reset_velocity"):
			player.reset_velocity()
	else:
		push_warning("Spawn point not found: " + spawn_point_name)

func _save_current_state():
	if not current_level:
		return
	
	var save_data = {
		"level_path": current_level.scene_file_path,
		"player_data": _get_player_save_data(),
		"level_data": {}
	}
	
	if current_level.has_method("get_save_data"):
		save_data.level_data = current_level.get_save_data()
	
	# Save to file or game state manager
	if checkpoint_on_transition:
		_create_checkpoint(save_data)

func _get_player_save_data() -> Dictionary:
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("get_save_data"):
		return player.get_save_data()
	return {}

func _create_checkpoint(data: Dictionary):
	# Save checkpoint data
	pass

func _preload_adjacent_levels(current_path: String):
	if not level_data_resource or not level_data_resource.has_method("get_adjacent_levels"):
		return
	
	var adjacent = level_data_resource.get_adjacent_levels(current_path)
	for level_path in adjacent:
		if not loaded_levels.has(level_path):
			# Load in background
			ResourceLoader.load_threaded_request(level_path)

func instant_transition(level_path: String, spawn_point: String = ""):
	if current_level:
		current_level.queue_free()
	
	var level_scene = load(level_path)
	var new_level = level_scene.instantiate()
	get_tree().current_scene.add_child(new_level)
	current_level = new_level
	
	if spawn_point != "":
		_set_player_spawn_point(spawn_point)
	
	level_loaded.emit(level_path)

func get_transition_overlay() -> ColorRect:
	return transition_overlay

func is_level_loaded(level_path: String) -> bool:
	return loaded_levels.has(level_path)

func unload_level(level_path: String):
	if loaded_levels.has(level_path):
		loaded_levels[level_path].queue_free()
		loaded_levels.erase(level_path)