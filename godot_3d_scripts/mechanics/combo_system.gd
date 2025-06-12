extends Node

signal combo_started(combo_name)
signal combo_extended(combo_name, hit_count)
signal combo_finished(combo_name, final_count, score)
signal combo_broken(reason)
signal special_move_executed(move_name)

var combo_registry = {}
var current_combo = null
var input_buffer = []
var combo_timer = 0.0
var hit_count = 0
var combo_score = 0

var combo_config = {
	"input_buffer_size": 10,
	"input_buffer_time": 0.3,
	"combo_window": 0.5,
	"hit_window": 1.0,
	"score_multiplier_base": 1.1
}

func _ready():
	set_process(true)
	_register_default_combos()

func _register_default_combos():
	register_combo("punch_combo", ["punch", "punch", "punch"], {
		"name": "Triple Punch",
		"damage_multiplier": 1.5,
		"score": 100,
		"cooldown": 0.5
	})
	
	register_combo("kick_combo", ["kick", "kick", "uppercut"], {
		"name": "Rising Storm",
		"damage_multiplier": 2.0,
		"score": 200,
		"cooldown": 1.0
	})
	
	register_combo("aerial_combo", ["jump", "punch", "kick"], {
		"name": "Aerial Assault",
		"damage_multiplier": 1.8,
		"score": 150,
		"cooldown": 0.8
	})
	
	register_combo("special_hadouken", ["down", "down-forward", "forward", "punch"], {
		"name": "Hadouken",
		"damage_multiplier": 3.0,
		"score": 500,
		"cooldown": 2.0,
		"special": true
	})
	
	register_combo("special_shoryuken", ["forward", "down", "down-forward", "punch"], {
		"name": "Shoryuken",
		"damage_multiplier": 2.5,
		"score": 400,
		"cooldown": 1.5,
		"special": true
	})
	
	register_combo("super_combo", ["punch", "punch", "forward", "kick", "punch"], {
		"name": "Ultimate Strike",
		"damage_multiplier": 4.0,
		"score": 1000,
		"cooldown": 5.0,
		"super": true,
		"meter_cost": 3
	})

func register_combo(combo_id, input_sequence, properties):
	combo_registry[combo_id] = {
		"sequence": input_sequence,
		"properties": properties,
		"last_used": 0.0
	}

func process_input(input_action):
	var current_time = OS.get_ticks_msec() / 1000.0
	
	input_buffer.append({
		"action": input_action,
		"time": current_time
	})
	
	_clean_input_buffer(current_time)
	
	var matched_combo = _check_for_combos()
	if matched_combo:
		_execute_combo(matched_combo)
	elif current_combo:
		_check_combo_continuation(input_action)

func _clean_input_buffer(current_time):
	while input_buffer.size() > combo_config.input_buffer_size:
		input_buffer.pop_front()
	
	input_buffer = input_buffer.filter(func(input):
		return current_time - input.time < combo_config.input_buffer_time
	)

func _check_for_combos():
	var current_time = OS.get_ticks_msec() / 1000.0
	
	for combo_id in combo_registry:
		var combo = combo_registry[combo_id]
		
		if current_time - combo.last_used < combo.properties.get("cooldown", 0):
			continue
		
		if _matches_sequence(combo.sequence):
			return combo_id
	
	return null

func _matches_sequence(sequence):
	if input_buffer.size() < sequence.size():
		return false
	
	var start_index = input_buffer.size() - sequence.size()
	
	for i in range(sequence.size()):
		if input_buffer[start_index + i].action != sequence[i]:
			return false
	
	return true

func _execute_combo(combo_id):
	var combo = combo_registry[combo_id]
	var properties = combo.properties
	
	if properties.get("super", false):
		if not _check_super_meter(properties.get("meter_cost", 1)):
			return
	
	current_combo = {
		"id": combo_id,
		"name": properties.name,
		"start_time": OS.get_ticks_msec() / 1000.0,
		"properties": properties
	}
	
	hit_count = 1
	combo_score = properties.score
	combo_timer = combo_config.combo_window
	
	combo.last_used = OS.get_ticks_msec() / 1000.0
	
	emit_signal("combo_started", properties.name)
	
	if properties.get("special", false) or properties.get("super", false):
		emit_signal("special_move_executed", properties.name)

func _check_combo_continuation(input_action):
	if not current_combo:
		return
	
	var continuation_combos = _find_continuation_combos(current_combo.id, input_action)
	
	if continuation_combos.size() > 0:
		var next_combo_id = continuation_combos[0]
		_chain_combo(next_combo_id)

func _find_continuation_combos(current_combo_id, next_input):
	var continuations = []
	var current_sequence = combo_registry[current_combo_id].sequence
	
	for combo_id in combo_registry:
		if combo_id == current_combo_id:
			continue
		
		var combo = combo_registry[combo_id]
		var sequence = combo.sequence
		
		if sequence.size() > current_sequence.size():
			var matches = true
			for i in range(current_sequence.size()):
				if sequence[i] != current_sequence[i]:
					matches = false
					break
			
			if matches and sequence[current_sequence.size()] == next_input:
				continuations.append(combo_id)
	
	return continuations

func _chain_combo(new_combo_id):
	var combo = combo_registry[new_combo_id]
	var properties = combo.properties
	
	current_combo = {
		"id": new_combo_id,
		"name": properties.name,
		"start_time": OS.get_ticks_msec() / 1000.0,
		"properties": properties
	}
	
	combo_timer = combo_config.combo_window
	emit_signal("combo_started", properties.name)

func register_hit():
	if not current_combo:
		return
	
	hit_count += 1
	combo_timer = combo_config.hit_window
	
	var multiplier = pow(combo_config.score_multiplier_base, hit_count - 1)
	var hit_score = current_combo.properties.score * multiplier
	combo_score += hit_score
	
	emit_signal("combo_extended", current_combo.name, hit_count)

func _process(delta):
	if current_combo:
		combo_timer -= delta
		
		if combo_timer <= 0:
			_finish_combo()

func _finish_combo():
	if not current_combo:
		return
	
	emit_signal("combo_finished", current_combo.name, hit_count, combo_score)
	
	current_combo = null
	hit_count = 0
	combo_score = 0
	combo_timer = 0.0

func break_combo(reason = "interrupted"):
	if not current_combo:
		return
	
	emit_signal("combo_broken", reason)
	
	current_combo = null
	hit_count = 0
	combo_score = 0
	combo_timer = 0.0

func _check_super_meter(cost):
	return true

func get_current_combo():
	if current_combo:
		return {
			"name": current_combo.name,
			"hit_count": hit_count,
			"score": combo_score,
			"time_remaining": combo_timer
		}
	return null

func get_combo_list():
	var combos = []
	for combo_id in combo_registry:
		var combo = combo_registry[combo_id]
		combos.append({
			"id": combo_id,
			"name": combo.properties.name,
			"sequence": combo.sequence,
			"special": combo.properties.get("special", false),
			"super": combo.properties.get("super", false)
		})
	return combos

func get_damage_multiplier():
	if current_combo:
		return current_combo.properties.get("damage_multiplier", 1.0)
	return 1.0