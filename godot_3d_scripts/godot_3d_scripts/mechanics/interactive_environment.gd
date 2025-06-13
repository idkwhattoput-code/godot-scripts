extends Area

signal interacted
signal interaction_started
signal interaction_ended
signal state_changed(new_state: String)

export var interaction_prompt: String = "Press E to interact"
export var interaction_distance: float = 3.0
export var interaction_angle: float = 45.0
export var requires_line_of_sight: bool = true
export var interaction_time: float = 0.0
export var cooldown_time: float = 1.0
export var max_uses: int = -1
export var requires_item: String = ""
export var consumes_item: bool = false
export var interaction_sound: AudioStream
export var disabled_sound: AudioStream
export var interaction_animations: Array = []

enum InteractionType {
	INSTANT,
	HOLD,
	TOGGLE,
	SEQUENCE
}

export var interaction_type: int = InteractionType.INSTANT
export var current_state: String = "default"
export var states: Dictionary = {
	"default": {"next": "activated", "animation": "activate"},
	"activated": {"next": "default", "animation": "deactivate"}
}

var is_interacting: bool = false
var can_interact: bool = true
var interaction_progress: float = 0.0
var uses_remaining: int
var cooldown_timer: float = 0.0
var current_interactor: Node = null
var players_in_range: Array = []

onready var mesh_instance: MeshInstance = $MeshInstance
onready var collision_shape: CollisionShape = $CollisionShape
onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
onready var animation_player: AnimationPlayer = $AnimationPlayer
onready var highlight_material: ShaderMaterial = preload("res://materials/highlight.tres")
onready var interaction_ui: Control = $InteractionUI

var original_materials: Array = []

func _ready():
	uses_remaining = max_uses
	add_to_group("interactable")
	
	if not audio_player:
		audio_player = AudioStreamPlayer3D.new()
		add_child(audio_player)
	
	connect("body_entered", self, "_on_body_entered")
	connect("body_exited", self, "_on_body_exited")
	
	_cache_original_materials()
	set_process(false)

func _process(delta):
	if cooldown_timer > 0:
		cooldown_timer -= delta
		if cooldown_timer <= 0:
			can_interact = true
	
	if is_interacting and interaction_type == InteractionType.HOLD:
		interaction_progress += delta / interaction_time
		_update_interaction_ui()
		
		if interaction_progress >= 1.0:
			_complete_interaction()
	
	_update_highlight()

func _on_body_entered(body):
	if body.is_in_group("player"):
		players_in_range.append(body)
		if players_in_range.size() == 1:
			set_process(true)
		_check_interaction_availability(body)

func _on_body_exited(body):
	if body in players_in_range:
		players_in_range.erase(body)
		if body == current_interactor:
			cancel_interaction()
		if players_in_range.size() == 0:
			set_process(false)
			_remove_highlight()

func _check_interaction_availability(player: Node):
	if not can_interact or (max_uses >= 0 and uses_remaining <= 0):
		return
	
	if _is_player_in_interaction_range(player):
		if player.has_method("show_interaction_prompt"):
			player.show_interaction_prompt(interaction_prompt)
		_apply_highlight()

func _is_player_in_interaction_range(player: Node) -> bool:
	var distance = player.global_transform.origin.distance_to(global_transform.origin)
	if distance > interaction_distance:
		return false
	
	if interaction_angle < 180:
		var to_player = (player.global_transform.origin - global_transform.origin).normalized()
		var forward = -global_transform.basis.z
		var angle = rad2deg(acos(forward.dot(to_player)))
		if angle > interaction_angle:
			return false
	
	if requires_line_of_sight:
		var space_state = get_world().direct_space_state
		var result = space_state.intersect_ray(
			global_transform.origin,
			player.global_transform.origin,
			[self, player]
		)
		if result:
			return false
	
	return true

func interact(interactor: Node):
	if not can_interact or (max_uses >= 0 and uses_remaining <= 0):
		_play_disabled_sound()
		return false
	
	if not _is_player_in_interaction_range(interactor):
		return false
	
	if requires_item != "" and not _check_required_item(interactor):
		return false
	
	current_interactor = interactor
	
	match interaction_type:
		InteractionType.INSTANT:
			_complete_interaction()
		InteractionType.HOLD:
			start_hold_interaction()
		InteractionType.TOGGLE:
			_toggle_state()
		InteractionType.SEQUENCE:
			_advance_sequence()
	
	return true

func start_hold_interaction():
	if is_interacting:
		return
	
	is_interacting = true
	interaction_progress = 0.0
	emit_signal("interaction_started")
	
	if interaction_ui:
		interaction_ui.visible = true

func cancel_interaction():
	if not is_interacting:
		return
	
	is_interacting = false
	interaction_progress = 0.0
	emit_signal("interaction_ended")
	
	if interaction_ui:
		interaction_ui.visible = false
	
	current_interactor = null

func _complete_interaction():
	is_interacting = false
	interaction_progress = 0.0
	
	if max_uses > 0:
		uses_remaining -= 1
	
	_play_interaction_sound()
	_play_interaction_animation()
	emit_signal("interacted")
	
	if interaction_type == InteractionType.HOLD:
		emit_signal("interaction_ended")
		if interaction_ui:
			interaction_ui.visible = false
	
	_start_cooldown()
	
	if consumes_item and requires_item != "" and current_interactor:
		if current_interactor.has_method("remove_item"):
			current_interactor.remove_item(requires_item)

func _toggle_state():
	if current_state in states:
		var next_state = states[current_state]["next"]
		_change_state(next_state)
	_complete_interaction()

func _advance_sequence():
	if current_state in states:
		var next_state = states[current_state]["next"]
		_change_state(next_state)
	_complete_interaction()

func _change_state(new_state: String):
	if new_state == current_state:
		return
	
	current_state = new_state
	emit_signal("state_changed", current_state)
	
	if current_state in states and "animation" in states[current_state]:
		var anim_name = states[current_state]["animation"]
		if animation_player and animation_player.has_animation(anim_name):
			animation_player.play(anim_name)

func _check_required_item(interactor: Node) -> bool:
	if not interactor.has_method("has_item"):
		return false
	
	if not interactor.has_item(requires_item):
		if interactor.has_method("show_message"):
			interactor.show_message("Requires: " + requires_item)
		return false
	
	return true

func _start_cooldown():
	if cooldown_time > 0:
		can_interact = false
		cooldown_timer = cooldown_time

func _play_interaction_sound():
	if interaction_sound and audio_player:
		audio_player.stream = interaction_sound
		audio_player.play()

func _play_disabled_sound():
	if disabled_sound and audio_player:
		audio_player.stream = disabled_sound
		audio_player.play()

func _play_interaction_animation():
	if interaction_animations.size() > 0 and animation_player:
		var anim = interaction_animations[randi() % interaction_animations.size()]
		if animation_player.has_animation(anim):
			animation_player.play(anim)

func _cache_original_materials():
	if mesh_instance:
		for i in range(mesh_instance.get_surface_material_count()):
			original_materials.append(mesh_instance.get_surface_material(i))

func _apply_highlight():
	if not mesh_instance or not highlight_material:
		return
	
	for i in range(mesh_instance.get_surface_material_count()):
		mesh_instance.set_surface_material(i, highlight_material)

func _remove_highlight():
	if not mesh_instance:
		return
	
	for i in range(min(original_materials.size(), mesh_instance.get_surface_material_count())):
		mesh_instance.set_surface_material(i, original_materials[i])

func _update_highlight():
	var should_highlight = false
	
	for player in players_in_range:
		if _is_player_in_interaction_range(player) and can_interact:
			should_highlight = true
			break
	
	if should_highlight:
		_apply_highlight()
	else:
		_remove_highlight()

func _update_interaction_ui():
	if not interaction_ui:
		return
	
	var progress_bar = interaction_ui.get_node_or_null("ProgressBar")
	if progress_bar:
		progress_bar.value = interaction_progress

func set_interaction_enabled(enabled: bool):
	can_interact = enabled
	if not enabled:
		cancel_interaction()

func reset():
	current_state = "default"
	uses_remaining = max_uses
	can_interact = true
	cooldown_timer = 0.0
	cancel_interaction()

func get_interaction_progress() -> float:
	return interaction_progress

func get_uses_remaining() -> int:
	return uses_remaining if max_uses >= 0 else -1

func add_state(state_name: String, next_state: String, animation: String = ""):
	states[state_name] = {
		"next": next_state,
		"animation": animation
	}