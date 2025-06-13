extends Area

class_name InteractiveObject

signal interaction_started(interactor)
signal interaction_completed(interactor)
signal interaction_cancelled(interactor)
signal state_changed(new_state)
signal highlight_changed(highlighted)

export var object_name: String = "Interactive Object"
export var interaction_prompt: String = "Press E to interact"
export var interaction_distance: float = 3.0
export var interaction_time: float = 0.0
export var require_line_of_sight: bool = true
export var single_use: bool = false
export var cooldown_time: float = 0.0
export var require_item: String = ""
export var consume_item: bool = false
export var locked: bool = false
export var lock_id: String = ""
export var highlight_on_hover: bool = true
export var highlight_color: Color = Color(1.2, 1.2, 0.8)
export var interaction_sound: AudioStream
export var locked_sound: AudioStream
export var success_sound: AudioStream

var current_state: String = "idle"
var can_interact: bool = true
var is_highlighted: bool = false
var interaction_progress: float = 0.0
var cooldown_timer: float = 0.0
var interactor_in_range: Spatial = null
var original_materials: Array = []
var interaction_callbacks: Dictionary = {}
var state_data: Dictionary = {}

onready var mesh_instance = $MeshInstance
onready var collision_shape = $CollisionShape
onready var audio_player = AudioStreamPlayer3D.new()
onready var ui_prompt = $InteractionPrompt
onready var progress_bar = $ProgressBar

func _ready():
	setup_interactive_object()
	register_default_interactions()
	set_process(false)

func setup_interactive_object():
	add_child(audio_player)
	audio_player.bus = "SFX"
	audio_player.unit_db = -5.0
	
	monitoring = true
	monitorable = true
	
	connect("body_entered", self, "_on_body_entered")
	connect("body_exited", self, "_on_body_exited")
	connect("mouse_entered", self, "_on_mouse_entered")
	connect("mouse_exited", self, "_on_mouse_exited")
	
	store_original_materials()
	create_ui_elements()

func register_default_interactions():
	register_interaction("use", funcref(self, "default_use_interaction"))
	register_interaction("examine", funcref(self, "default_examine_interaction"))
	register_interaction("activate", funcref(self, "default_activate_interaction"))

func store_original_materials():
	if not mesh_instance:
		return
	
	original_materials.clear()
	for i in range(mesh_instance.get_surface_material_count()):
		original_materials.append(mesh_instance.get_surface_material(i))

func create_ui_elements():
	if not ui_prompt:
		var prompt = Label3D.new()
		prompt.name = "InteractionPrompt"
		prompt.text = interaction_prompt
		prompt.billboard = Label3D.BILLBOARD_ENABLED
		prompt.no_depth_test = true
		prompt.fixed_size = true
		prompt.pixel_size = 0.01
		prompt.outline_size = 5
		prompt.position.y = 2.0
		prompt.visible = false
		add_child(prompt)
		ui_prompt = prompt
	
	if interaction_time > 0 and not progress_bar:
		var viewport = Viewport.new()
		viewport.size = Vector2(200, 20)
		viewport.transparent_bg = true
		
		var progress = ProgressBar.new()
		progress.name = "ProgressBar"
		progress.rect_size = Vector2(200, 20)
		progress.value = 0
		progress.visible = false
		viewport.add_child(progress)
		
		var sprite = Sprite3D.new()
		sprite.texture = viewport.get_texture()
		sprite.billboard = Sprite3D.BILLBOARD_ENABLED
		sprite.position.y = 1.5
		sprite.pixel_size = 0.01
		add_child(viewport)
		add_child(sprite)
		progress_bar = progress

func _process(delta):
	if cooldown_timer > 0:
		cooldown_timer -= delta
		if cooldown_timer <= 0:
			can_interact = true
	
	if interactor_in_range and require_line_of_sight:
		check_line_of_sight()

func _on_body_entered(body):
	if body.has_method("is_player") and body.is_player():
		interactor_in_range = body
		if can_interact and not locked:
			show_interaction_prompt()
		set_process(true)

func _on_body_exited(body):
	if body == interactor_in_range:
		interactor_in_range = null
		hide_interaction_prompt()
		if interaction_progress > 0:
			cancel_interaction()
		set_process(false)

func _on_mouse_entered():
	if highlight_on_hover and can_interact:
		apply_highlight()

func _on_mouse_exited():
	if is_highlighted:
		remove_highlight()

func check_line_of_sight():
	if not interactor_in_range:
		return
	
	var space_state = get_world().direct_space_state
	var from = global_transform.origin + Vector3.UP
	var to = interactor_in_range.global_transform.origin + Vector3.UP
	
	var result = space_state.intersect_ray(from, to, [self, interactor_in_range])
	
	if result:
		hide_interaction_prompt()
		can_interact = false
	else:
		can_interact = true
		if not locked:
			show_interaction_prompt()

func show_interaction_prompt():
	if ui_prompt:
		ui_prompt.visible = true
		ui_prompt.text = get_interaction_text()

func hide_interaction_prompt():
	if ui_prompt:
		ui_prompt.visible = false
	if progress_bar:
		progress_bar.visible = false

func get_interaction_text() -> String:
	if locked:
		return "Locked" + (" - Requires: " + lock_id if lock_id else "")
	elif require_item:
		return interaction_prompt + " (Requires: " + require_item + ")"
	else:
		return interaction_prompt

func apply_highlight():
	if not mesh_instance or is_highlighted:
		return
	
	is_highlighted = true
	emit_signal("highlight_changed", true)
	
	for i in range(mesh_instance.get_surface_material_count()):
		var material = mesh_instance.get_surface_material(i)
		if material:
			var highlighted_mat = material.duplicate()
			highlighted_mat.albedo_color *= highlight_color
			mesh_instance.set_surface_material(i, highlighted_mat)

func remove_highlight():
	if not mesh_instance or not is_highlighted:
		return
	
	is_highlighted = false
	emit_signal("highlight_changed", false)
	
	for i in range(original_materials.size()):
		if i < mesh_instance.get_surface_material_count():
			mesh_instance.set_surface_material(i, original_materials[i])

func interact(interactor: Spatial = null):
	if not can_interact or locked:
		if locked and locked_sound:
			play_sound(locked_sound)
		return false
	
	if not interactor:
		interactor = interactor_in_range
	
	if not interactor:
		return false
	
	if not check_requirements(interactor):
		return false
	
	if interaction_time > 0:
		start_timed_interaction(interactor)
	else:
		execute_interaction(interactor)
	
	return true

func check_requirements(interactor: Spatial) -> bool:
	if require_item and interactor.has_method("has_item"):
		if not interactor.has_item(require_item):
			return false
		
		if consume_item and interactor.has_method("remove_item"):
			interactor.remove_item(require_item)
	
	return true

func start_timed_interaction(interactor: Spatial):
	emit_signal("interaction_started", interactor)
	interaction_progress = 0.0
	
	if progress_bar:
		progress_bar.visible = true
		progress_bar.value = 0
	
	if interaction_sound:
		play_sound(interaction_sound)
	
	var timer = 0.0
	while timer < interaction_time and interactor_in_range == interactor:
		timer += get_process_delta_time()
		interaction_progress = timer / interaction_time
		
		if progress_bar:
			progress_bar.value = interaction_progress * 100
		
		yield(get_tree(), "idle_frame")
	
	if interaction_progress >= 1.0:
		execute_interaction(interactor)
	else:
		cancel_interaction()

func execute_interaction(interactor: Spatial):
	var interaction_type = current_state + "_interaction"
	
	if interaction_type in interaction_callbacks:
		interaction_callbacks[interaction_type].call_func(interactor)
	elif "default_interaction" in interaction_callbacks:
		interaction_callbacks["default_interaction"].call_func(interactor)
	
	emit_signal("interaction_completed", interactor)
	
	if success_sound:
		play_sound(success_sound)
	
	if single_use:
		disable_interaction()
	elif cooldown_time > 0:
		start_cooldown()
	
	hide_interaction_prompt()

func cancel_interaction():
	interaction_progress = 0.0
	
	if progress_bar:
		progress_bar.visible = false
		progress_bar.value = 0
	
	if audio_player.playing:
		audio_player.stop()
	
	emit_signal("interaction_cancelled", interactor_in_range)

func register_interaction(interaction_name: String, callback: FuncRef):
	interaction_callbacks[interaction_name] = callback

func change_state(new_state: String):
	var old_state = current_state
	current_state = new_state
	emit_signal("state_changed", new_state)
	
	if has_method("_on_state_" + new_state):
		call("_on_state_" + new_state)

func disable_interaction():
	can_interact = false
	hide_interaction_prompt()
	set_process(false)
	
	if collision_shape:
		collision_shape.disabled = true

func enable_interaction():
	can_interact = true
	
	if collision_shape:
		collision_shape.disabled = false
	
	if interactor_in_range:
		show_interaction_prompt()
		set_process(true)

func start_cooldown():
	can_interact = false
	cooldown_timer = cooldown_time
	hide_interaction_prompt()

func unlock(key_id: String = ""):
	if not locked:
		return
	
	if lock_id and key_id != lock_id:
		return false
	
	locked = false
	if interactor_in_range:
		show_interaction_prompt()
	
	return true

func lock(new_lock_id: String = ""):
	locked = true
	lock_id = new_lock_id
	hide_interaction_prompt()

func play_sound(sound: AudioStream):
	audio_player.stream = sound
	audio_player.play()

func set_state_data(key: String, value):
	state_data[key] = value

func get_state_data(key: String):
	if key in state_data:
		return state_data[key]
	return null

func default_use_interaction(interactor: Spatial):
	print(object_name + " was used by " + str(interactor))

func default_examine_interaction(interactor: Spatial):
	print("Examining " + object_name)

func default_activate_interaction(interactor: Spatial):
	print(object_name + " activated")
	change_state("active" if current_state == "idle" else "idle")

func save_state() -> Dictionary:
	return {
		"current_state": current_state,
		"can_interact": can_interact,
		"locked": locked,
		"lock_id": lock_id,
		"state_data": state_data
	}

func load_state(data: Dictionary):
	current_state = data.get("current_state", "idle")
	can_interact = data.get("can_interact", true)
	locked = data.get("locked", false)
	lock_id = data.get("lock_id", "")
	state_data = data.get("state_data", {})
	
	if not can_interact:
		disable_interaction()