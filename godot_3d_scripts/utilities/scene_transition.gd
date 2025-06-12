extends CanvasLayer

export var default_transition_time = 1.0
export var default_transition_type = "fade"

var is_transitioning = false
var current_scene = null

onready var animation_player = $AnimationPlayer
onready var color_rect = $ColorRect
onready var progress_bar = $ProgressBar
onready var loading_label = $LoadingLabel

signal transition_started()
signal transition_finished()
signal scene_loaded(scene_path)

var transition_types = {
	"fade": {
		"in": "fade_in",
		"out": "fade_out"
	},
	"slide_left": {
		"in": "slide_in_left",
		"out": "slide_out_left"
	},
	"slide_right": {
		"in": "slide_in_right",
		"out": "slide_out_right"
	},
	"slide_up": {
		"in": "slide_in_up",
		"out": "slide_out_up"
	},
	"slide_down": {
		"in": "slide_in_down",
		"out": "slide_out_down"
	},
	"circle": {
		"in": "circle_in",
		"out": "circle_out"
	},
	"pixelate": {
		"in": "pixelate_in",
		"out": "pixelate_out"
	}
}

func _ready():
	_setup_animations()
	layer = 100
	color_rect.color = Color.black
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

func change_scene(scene_path: String, transition_type: String = "", transition_time: float = -1.0):
	if is_transitioning:
		return
	
	is_transitioning = true
	emit_signal("transition_started")
	
	if transition_type == "":
		transition_type = default_transition_type
	
	if transition_time < 0:
		transition_time = default_transition_time
	
	show()
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	yield(_play_transition_out(transition_type, transition_time), "completed")
	
	get_tree().change_scene(scene_path)
	
	yield(get_tree(), "idle_frame")
	
	yield(_play_transition_in(transition_type, transition_time), "completed")
	
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	is_transitioning = false
	
	emit_signal("scene_loaded", scene_path)
	emit_signal("transition_finished")

func change_scene_to(scene: PackedScene, transition_type: String = "", transition_time: float = -1.0):
	if is_transitioning:
		return
	
	is_transitioning = true
	emit_signal("transition_started")
	
	if transition_type == "":
		transition_type = default_transition_type
	
	if transition_time < 0:
		transition_time = default_transition_time
	
	show()
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	yield(_play_transition_out(transition_type, transition_time), "completed")
	
	get_tree().current_scene.queue_free()
	current_scene = scene.instance()
	get_tree().root.add_child(current_scene)
	get_tree().current_scene = current_scene
	
	yield(get_tree(), "idle_frame")
	
	yield(_play_transition_in(transition_type, transition_time), "completed")
	
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	is_transitioning = false
	
	emit_signal("scene_loaded", scene.resource_path)
	emit_signal("transition_finished")

func reload_current_scene(transition_type: String = "", transition_time: float = -1.0):
	var current_scene_path = get_tree().current_scene.filename
	change_scene(current_scene_path, transition_type, transition_time)

func change_scene_with_loading(scene_path: String, transition_type: String = ""):
	if is_transitioning:
		return
	
	is_transitioning = true
	emit_signal("transition_started")
	
	if transition_type == "":
		transition_type = default_transition_type
	
	show()
	mouse_filter = Control.MOUSE_FILTER_STOP
	progress_bar.show()
	loading_label.show()
	
	yield(_play_transition_out(transition_type, default_transition_time), "completed")
	
	var loader = ResourceLoader.load_interactive(scene_path)
	if loader == null:
		push_error("Failed to load scene: " + scene_path)
		_finish_loading_transition(transition_type)
		return
	
	var total_stages = loader.get_stage_count()
	
	while true:
		var err = loader.poll()
		
		if err == ERR_FILE_EOF:
			var resource = loader.get_resource()
			get_tree().change_scene_to(resource)
			break
		elif err != OK:
			push_error("Error loading scene: " + scene_path)
			_finish_loading_transition(transition_type)
			return
		
		var progress = float(loader.get_stage()) / float(total_stages)
		progress_bar.value = progress * 100
		
		yield(get_tree(), "idle_frame")
	
	yield(get_tree(), "idle_frame")
	
	_finish_loading_transition(transition_type)

func _finish_loading_transition(transition_type: String):
	progress_bar.hide()
	loading_label.hide()
	
	yield(_play_transition_in(transition_type, default_transition_time), "completed")
	
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	is_transitioning = false
	
	emit_signal("transition_finished")

func _play_transition_out(type: String, duration: float):
	if not transition_types.has(type):
		type = "fade"
	
	var anim_name = transition_types[type].out
	
	if animation_player.has_animation(anim_name):
		animation_player.playback_speed = 1.0 / duration
		animation_player.play(anim_name)
		yield(animation_player, "animation_finished")
	else:
		yield(get_tree().create_timer(duration / 2), "timeout")

func _play_transition_in(type: String, duration: float):
	if not transition_types.has(type):
		type = "fade"
	
	var anim_name = transition_types[type].in
	
	if animation_player.has_animation(anim_name):
		animation_player.playback_speed = 1.0 / duration
		animation_player.play(anim_name)
		yield(animation_player, "animation_finished")
	else:
		yield(get_tree().create_timer(duration / 2), "timeout")

func _setup_animations():
	if not animation_player:
		animation_player = AnimationPlayer.new()
		add_child(animation_player)
	
	_create_fade_animations()
	_create_slide_animations()
	_create_special_animations()

func _create_fade_animations():
	var fade_out = Animation.new()
	fade_out.length = 1.0
	fade_out.add_track(Animation.TYPE_VALUE, 0)
	fade_out.track_set_path(0, "ColorRect:modulate:a")
	fade_out.track_insert_key(0, 0.0, 0.0)
	fade_out.track_insert_key(0, 1.0, 1.0)
	animation_player.add_animation("fade_out", fade_out)
	
	var fade_in = Animation.new()
	fade_in.length = 1.0
	fade_in.add_track(Animation.TYPE_VALUE, 0)
	fade_in.track_set_path(0, "ColorRect:modulate:a")
	fade_in.track_insert_key(0, 0.0, 1.0)
	fade_in.track_insert_key(0, 1.0, 0.0)
	animation_player.add_animation("fade_in", fade_in)

func _create_slide_animations():
	var directions = {
		"left": Vector2(-1920, 0),
		"right": Vector2(1920, 0),
		"up": Vector2(0, -1080),
		"down": Vector2(0, 1080)
	}
	
	for dir in directions:
		var slide_out = Animation.new()
		slide_out.length = 1.0
		slide_out.add_track(Animation.TYPE_VALUE, 0)
		slide_out.track_set_path(0, "ColorRect:rect_position")
		slide_out.track_insert_key(0, 0.0, Vector2.ZERO)
		slide_out.track_insert_key(0, 1.0, -directions[dir])
		animation_player.add_animation("slide_out_" + dir, slide_out)
		
		var slide_in = Animation.new()
		slide_in.length = 1.0
		slide_in.add_track(Animation.TYPE_VALUE, 0)
		slide_in.track_set_path(0, "ColorRect:rect_position")
		slide_in.track_insert_key(0, 0.0, directions[dir])
		slide_in.track_insert_key(0, 1.0, Vector2.ZERO)
		animation_player.add_animation("slide_in_" + dir, slide_in)

func _create_special_animations():
	pass

func add_custom_transition(name: String, out_animation: Animation, in_animation: Animation):
	animation_player.add_animation(name + "_out", out_animation)
	animation_player.add_animation(name + "_in", in_animation)
	
	transition_types[name] = {
		"in": name + "_in",
		"out": name + "_out"
	}

func set_transition_color(color: Color):
	color_rect.color = color

func is_transitioning() -> bool:
	return is_transitioning