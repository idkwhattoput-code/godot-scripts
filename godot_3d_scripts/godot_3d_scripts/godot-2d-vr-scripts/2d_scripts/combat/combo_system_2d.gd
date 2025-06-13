extends Node

class_name ComboSystem2D

@export_group("Combo Settings")
@export var max_combo_time := 1.0
@export var combo_reset_time := 2.0
@export var max_combo_length := 10
@export var allow_same_move_repeat := false
@export var combo_damage_multiplier := 1.5

@export_group("Input Settings")
@export var input_buffer_time := 0.2
@export var direction_tolerance := 45.0
@export var require_timing_precision := true
@export var perfect_timing_window := 0.1

@export_group("Visual Feedback")
@export var show_combo_counter := true
@export var combo_counter_path: NodePath
@export var show_input_history := true
@export var flash_on_combo := true
@export var screen_shake_on_finish := true

@export_group("Audio")
@export var combo_hit_sounds: Array[AudioStream] = []
@export var combo_finish_sound: AudioStream
@export var perfect_timing_sound: AudioStream

var current_combo := []
var combo_timer := 0.0
var input_buffer := []
var input_buffer_timer := 0.0
var combo_counter: Label
var combo_multiplier := 1.0
var total_combo_damage := 0.0
var highest_combo := 0
var perfect_inputs := 0
var combo_definitions := {}
var active_combo_name := ""
var player_node: Node2D
var audio_player: AudioStreamPlayer2D

signal combo_started(combo_name: String)
signal combo_extended(move: String, count: int)
signal combo_finished(combo_name: String, length: int, damage: float)
signal combo_dropped()
signal perfect_input(move: String)
signal special_move_triggered(move_name: String)

class ComboMove:
	var name: String
	var inputs: Array[String]
	var damage: float
	var special_properties := {}
	var animation_name: String = ""
	var can_cancel_into: Array[String] = []
	
	func _init(move_name: String, move_inputs: Array[String], move_damage: float = 10.0):
		name = move_name
		inputs = move_inputs
		damage = move_damage

func _ready():
	if combo_counter_path:
		combo_counter = get_node(combo_counter_path)
	
	audio_player = AudioStreamPlayer2D.new()
	add_child(audio_player)
	
	register_default_combos()
	
	set_process(true)
	set_process_input(true)

func register_default_combos():
	register_combo("basic_combo", ["attack", "attack", "attack"], 30.0)
	register_combo("launcher", ["down", "attack", "up", "attack"], 40.0)
	register_combo("spin_attack", ["attack", "attack", "special"], 35.0)
	register_combo("power_strike", ["hold_attack", "release_attack"], 50.0)
	register_combo("aerial_rave", ["jump", "attack", "attack", "special"], 45.0)
	register_combo("ground_pound", ["jump", "down", "attack"], 35.0)
	register_combo("dash_strike", ["dash", "attack"], 25.0)
	register_combo("ultimate", ["special", "special", "attack", "special"], 100.0)

func register_combo(combo_name: String, inputs: Array[String], damage: float, properties: Dictionary = {}):
	var combo = ComboMove.new(combo_name, inputs, damage)
	combo.special_properties = properties
	combo_definitions[combo_name] = combo

func _input(event: InputEvent):
	var input_string = parse_input(event)
	if input_string != "":
		add_to_input_buffer(input_string)

func parse_input(event: InputEvent) -> String:
	if event.is_action_pressed("attack"):
		return "attack"
	elif event.is_action_released("attack") and event.is_action("attack"):
		return "release_attack"
	elif event.is_action_pressed("special"):
		return "special"
	elif event.is_action_pressed("jump"):
		return "jump"
	elif event.is_action_pressed("dash"):
		return "dash"
	elif event is InputEventKey or event is InputEventJoypadMotion:
		var direction = get_input_direction()
		if direction != "":
			return direction
	
	if event.is_action("attack") and is_holding_attack():
		return "hold_attack"
	
	return ""

func get_input_direction() -> String:
	var input_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	if input_vector.length() < 0.5:
		return ""
	
	var angle = rad_to_deg(input_vector.angle())
	
	if abs(angle) <= direction_tolerance:
		return "right"
	elif abs(angle - 180) <= direction_tolerance or abs(angle + 180) <= direction_tolerance:
		return "left"
	elif abs(angle - 90) <= direction_tolerance:
		return "down"
	elif abs(angle + 90) <= direction_tolerance:
		return "up"
	
	return ""

func is_holding_attack() -> bool:
	return Input.is_action_pressed("attack") and get_process_delta_time() > 0.3

func add_to_input_buffer(input: String):
	if not allow_same_move_repeat and input_buffer.size() > 0:
		if input_buffer[-1] == input:
			return
	
	input_buffer.append(input)
	input_buffer_timer = input_buffer_time
	
	process_input_buffer()

func process_input_buffer():
	if input_buffer.is_empty():
		return
	
	var last_input = input_buffer[-1]
	
	if current_combo.is_empty():
		start_new_combo(last_input)
	else:
		extend_combo(last_input)
	
	check_for_special_moves()

func start_new_combo(input: String):
	current_combo = [input]
	combo_timer = max_combo_time
	emit_signal("combo_started", input)
	
	if show_combo_counter:
		update_combo_display()

func extend_combo(input: String):
	if current_combo.size() >= max_combo_length:
		return
	
	var timing_bonus = check_timing_precision()
	if timing_bonus:
		perfect_inputs += 1
		emit_signal("perfect_input", input)
		play_sound(perfect_timing_sound)
	
	current_combo.append(input)
	combo_timer = max_combo_time
	combo_multiplier = calculate_combo_multiplier()
	
	emit_signal("combo_extended", input, current_combo.size())
	
	play_combo_sound()
	
	if show_combo_counter:
		update_combo_display()
	
	if flash_on_combo and player_node:
		flash_player()

func check_timing_precision() -> bool:
	if not require_timing_precision:
		return false
	
	return combo_timer > max_combo_time - perfect_timing_window

func check_for_special_moves():
	for combo_name in combo_definitions:
		var combo = combo_definitions[combo_name]
		if is_combo_match(combo.inputs):
			execute_special_move(combo_name)
			break

func is_combo_match(required_inputs: Array[String]) -> bool:
	if current_combo.size() < required_inputs.size():
		return false
	
	var start_index = current_combo.size() - required_inputs.size()
	for i in range(required_inputs.size()):
		if current_combo[start_index + i] != required_inputs[i]:
			return false
	
	return true

func execute_special_move(combo_name: String):
	var combo = combo_definitions[combo_name]
	active_combo_name = combo_name
	
	var damage = combo.damage * combo_multiplier
	total_combo_damage += damage
	
	emit_signal("special_move_triggered", combo_name)
	
	if combo.animation_name != "" and player_node and player_node.has_method("play_animation"):
		player_node.play_animation(combo.animation_name)
	
	if combo.special_properties.has("screen_shake"):
		trigger_screen_shake(combo.special_properties.screen_shake)
	
	if combo.special_properties.has("invincible"):
		make_player_invincible(combo.special_properties.invincible)
	
	play_sound(combo_finish_sound)

func _process(delta):
	if input_buffer_timer > 0:
		input_buffer_timer -= delta
		if input_buffer_timer <= 0:
			input_buffer.clear()
	
	if combo_timer > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			end_combo()
	
	if show_combo_counter and combo_counter:
		update_combo_display()

func end_combo():
	if current_combo.size() > highest_combo:
		highest_combo = current_combo.size()
	
	if current_combo.size() > 1:
		emit_signal("combo_finished", active_combo_name, current_combo.size(), total_combo_damage)
		
		if screen_shake_on_finish:
			trigger_screen_shake(0.3)
	else:
		emit_signal("combo_dropped")
	
	current_combo.clear()
	active_combo_name = ""
	combo_multiplier = 1.0
	total_combo_damage = 0.0
	perfect_inputs = 0
	
	if show_combo_counter:
		update_combo_display()

func calculate_combo_multiplier() -> float:
	var base_multiplier = 1.0 + (current_combo.size() - 1) * 0.1
	var perfect_bonus = perfect_inputs * 0.05
	return min(base_multiplier + perfect_bonus, combo_damage_multiplier)

func update_combo_display():
	if not combo_counter:
		return
	
	if current_combo.is_empty():
		combo_counter.text = ""
		combo_counter.visible = false
	else:
		combo_counter.visible = true
		combo_counter.text = "%d HIT COMBO! x%.1f" % [current_combo.size(), combo_multiplier]
		
		if perfect_inputs > 0:
			combo_counter.text += " PERFECT!"
		
		var color = Color.WHITE
		if current_combo.size() >= 5:
			color = Color.YELLOW
		if current_combo.size() >= 10:
			color = Color.ORANGE
		if current_combo.size() >= 15:
			color = Color.RED
		
		combo_counter.modulate = color

func flash_player():
	if not player_node:
		return
	
	var sprite = player_node.get_node_or_null("Sprite2D")
	if not sprite:
		return
	
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE * 2.0, 0.1)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.1)

func play_combo_sound():
	if combo_hit_sounds.is_empty() or not audio_player:
		return
	
	var sound_index = min(current_combo.size() - 1, combo_hit_sounds.size() - 1)
	play_sound(combo_hit_sounds[sound_index])

func play_sound(sound: AudioStream):
	if sound and audio_player:
		audio_player.stream = sound
		audio_player.pitch_scale = 1.0 + randf_range(-0.1, 0.1)
		audio_player.play()

func trigger_screen_shake(intensity: float):
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("shake"):
		camera.shake(intensity, 0.2)

func make_player_invincible(duration: float):
	if player_node and player_node.has_method("set_invincible"):
		player_node.set_invincible(true)
		
		await get_tree().create_timer(duration).timeout
		
		if player_node:
			player_node.set_invincible(false)

func get_combo_string() -> String:
	return " > ".join(current_combo)

func get_combo_history(count: int = 5) -> Array[String]:
	var history := []
	var start = max(0, current_combo.size() - count)
	for i in range(start, current_combo.size()):
		history.append(current_combo[i])
	return history

func can_cancel_current_move(into_move: String) -> bool:
	if active_combo_name == "":
		return true
	
	var current_combo_def = combo_definitions.get(active_combo_name)
	if current_combo_def:
		return into_move in current_combo_def.can_cancel_into
	
	return true

func reset_combo():
	end_combo()

func set_player(player: Node2D):
	player_node = player

func get_stats() -> Dictionary:
	return {
		"highest_combo": highest_combo,
		"current_combo_length": current_combo.size(),
		"perfect_inputs": perfect_inputs,
		"combo_multiplier": combo_multiplier,
		"total_damage": total_combo_damage
	}