extends Control

export var min_display_time = 1.0
export var enable_tips = true
export var enable_progress_bar = true
export var enable_animated_background = true
export var fade_duration = 0.5

var loading_progress = 0.0
var loading_complete = false
var time_elapsed = 0.0
var current_tip_index = 0
var loader = null
var scene_path = ""

onready var background = $Background
onready var animated_bg = $AnimatedBackground
onready var logo = $CenterContainer/Logo
onready var progress_bar = $BottomPanel/ProgressBar
onready var progress_label = $BottomPanel/ProgressLabel
onready var status_label = $BottomPanel/StatusLabel
onready var tip_label = $BottomPanel/TipLabel
onready var spinner = $CenterContainer/LoadingSpinner
onready var continue_prompt = $CenterContainer/ContinuePrompt

signal loading_finished()
signal scene_loaded()

var loading_tips = [
	"Use dodge rolls to avoid enemy attacks!",
	"Save your game frequently at checkpoints.",
	"Upgrade your equipment at the blacksmith.",
	"Collect herbs to craft healing potions.",
	"Fast travel unlocks after discovering new locations.",
	"Hold shift to sprint, but watch your stamina!",
	"Different weapons have unique combat styles.",
	"Environmental objects can be used in combat.",
	"Check your map for undiscovered areas.",
	"Complete side quests for bonus rewards!"
]

var loading_stages = {
	"initializing": "Initializing...",
	"loading_assets": "Loading game assets...",
	"loading_textures": "Loading textures...",
	"loading_models": "Loading 3D models...",
	"loading_sounds": "Loading audio...",
	"loading_scripts": "Compiling scripts...",
	"loading_world": "Generating world...",
	"finalizing": "Finalizing..."
}

func _ready():
	_setup_ui()
	set_process(true)
	
	if enable_tips:
		_start_tip_rotation()

func _setup_ui():
	progress_bar.visible = enable_progress_bar
	progress_label.visible = enable_progress_bar
	animated_bg.visible = enable_animated_background
	continue_prompt.hide()
	
	if enable_animated_background:
		_setup_animated_background()
	
	_animate_spinner()

func _setup_animated_background():
	# Create shader for animated background
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float time = 0.0;
uniform vec4 color1 : hint_color = vec4(0.1, 0.1, 0.2, 1.0);
uniform vec4 color2 : hint_color = vec4(0.2, 0.1, 0.3, 1.0);
uniform float wave_speed = 0.5;

void fragment() {
	vec2 uv = UV;
	float wave = sin(uv.x * 10.0 + time * wave_speed) * 0.05;
	uv.y += wave;
	
	float gradient = smoothstep(0.0, 1.0, uv.y + sin(time * 0.3) * 0.1);
	COLOR = mix(color1, color2, gradient);
}
"""
	
	var mat = ShaderMaterial.new()
	mat.shader = shader
	animated_bg.material = mat

func _process(delta):
	time_elapsed += delta
	
	if enable_animated_background and animated_bg.material:
		animated_bg.material.set_shader_param("time", time_elapsed)
	
	if loader:
		_update_loading_progress()
	
	if loading_complete and time_elapsed >= min_display_time:
		_finish_loading()

func load_scene(path: String):
	scene_path = path
	loader = ResourceLoader.load_interactive(path)
	
	if loader == null:
		_show_error("Failed to load scene: " + path)
		return
	
	set_process(true)
	_update_status("initializing")

func _update_loading_progress():
	if loader == null:
		return
	
	var err = loader.poll()
	
	if err == ERR_FILE_EOF:
		# Loading complete
		loading_progress = 1.0
		loading_complete = true
		_update_status("finalizing")
		_update_progress_display()
		return
	elif err != OK:
		_show_error("Error loading scene")
		loader = null
		return
	
	# Calculate progress
	var stage = loader.get_stage()
	var stage_count = loader.get_stage_count()
	loading_progress = float(stage) / float(stage_count)
	
	_update_progress_display()
	_update_status_by_progress()

func _update_progress_display():
	if progress_bar:
		progress_bar.value = loading_progress * 100
	
	if progress_label:
		progress_label.text = "%d%%" % (loading_progress * 100)

func _update_status(stage_key: String):
	if status_label and loading_stages.has(stage_key):
		status_label.text = loading_stages[stage_key]

func _update_status_by_progress():
	var stage_index = int(loading_progress * (loading_stages.size() - 1))
	var stages = loading_stages.keys()
	if stage_index < stages.size():
		_update_status(stages[stage_index])

func _animate_spinner():
	if not spinner:
		return
	
	var tween = Tween.new()
	add_child(tween)
	
	tween.interpolate_property(spinner, "rect_rotation", 0, 360, 1.0,
		Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
	tween.set_loops()
	tween.start()

func _start_tip_rotation():
	if not enable_tips or loading_tips.empty():
		return
	
	_show_next_tip()
	
	var timer = Timer.new()
	timer.wait_time = 5.0
	timer.connect("timeout", self, "_show_next_tip")
	add_child(timer)
	timer.start()

func _show_next_tip():
	if not tip_label:
		return
	
	var tween = Tween.new()
	add_child(tween)
	
	# Fade out current tip
	tween.interpolate_property(tip_label, "modulate:a", 1.0, 0.0, 0.3)
	tween.start()
	
	yield(tween, "tween_all_completed")
	
	# Update tip text
	tip_label.text = "Tip: " + loading_tips[current_tip_index]
	current_tip_index = (current_tip_index + 1) % loading_tips.size()
	
	# Fade in new tip
	tween.interpolate_property(tip_label, "modulate:a", 0.0, 1.0, 0.3)
	tween.start()
	
	yield(tween, "tween_all_completed")
	tween.queue_free()

func _finish_loading():
	set_process(false)
	
	var resource = loader.get_resource()
	loader = null
	
	emit_signal("loading_finished")
	
	# Show continue prompt or auto-transition
	if ProjectSettings.get_setting("loading_screen/require_input", false):
		_show_continue_prompt()
	else:
		_transition_to_scene(resource)

func _show_continue_prompt():
	continue_prompt.show()
	spinner.hide()
	
	var tween = Tween.new()
	add_child(tween)
	
	# Pulse animation for prompt
	tween.interpolate_property(continue_prompt, "modulate:a", 0.5, 1.0, 0.5,
		Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	tween.set_loops()
	tween.start()
	
	# Wait for input
	set_process_input(true)

func _input(event):
	if continue_prompt.visible and event.is_pressed():
		_transition_to_scene(loader.get_resource())

func _transition_to_scene(scene_resource):
	set_process_input(false)
	
	# Fade out
	var tween = Tween.new()
	add_child(tween)
	
	tween.interpolate_property(self, "modulate:a", 1.0, 0.0, fade_duration)
	tween.start()
	
	yield(tween, "tween_all_completed")
	
	# Change scene
	get_tree().change_scene_to(scene_resource)
	emit_signal("scene_loaded")
	
	queue_free()

func _show_error(message: String):
	var error_dialog = AcceptDialog.new()
	error_dialog.dialog_text = message
	add_child(error_dialog)
	error_dialog.popup_centered()
	
	loading_complete = true
	set_process(false)

func set_custom_tips(tips: Array):
	loading_tips = tips
	current_tip_index = 0

func add_loading_stage(key: String, description: String):
	loading_stages[key] = description

func set_loading_progress(value: float):
	loading_progress = clamp(value, 0.0, 1.0)
	_update_progress_display()

func set_status_text(text: String):
	if status_label:
		status_label.text = text

func show_loading_screen():
	show()
	_animate_fade_in()

func hide_loading_screen():
	_animate_fade_out()
	yield(get_tree().create_timer(fade_duration), "timeout")
	hide()

func _animate_fade_in():
	modulate.a = 0
	var tween = Tween.new()
	add_child(tween)
	
	tween.interpolate_property(self, "modulate:a", 0.0, 1.0, fade_duration)
	tween.start()
	
	yield(tween, "tween_all_completed")
	tween.queue_free()

func _animate_fade_out():
	var tween = Tween.new()
	add_child(tween)
	
	tween.interpolate_property(self, "modulate:a", 1.0, 0.0, fade_duration)
	tween.start()
	
	yield(tween, "tween_all_completed")
	tween.queue_free()