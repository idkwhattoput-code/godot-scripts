extends Node

class_name ClientPrediction

signal prediction_corrected(difference)

const MAX_PREDICTION_FRAMES = 60
const RECONCILIATION_THRESHOLD = 0.1

var prediction_buffer = []
var server_buffer = []
var input_sequence = 0
var last_server_state = null
var prediction_enabled = true

func _ready():
	set_physics_process(true)

func _physics_process(delta):
	if not get_tree().has_network_peer():
		return
	
	if get_tree().is_network_server():
		return
	
	_process_predictions(delta)
	_reconcile_with_server()

func predict_movement(player, input, delta):
	if not prediction_enabled:
		return
	
	var predicted_state = {
		"sequence": input_sequence,
		"position": player.global_transform.origin,
		"velocity": player.velocity if "velocity" in player else Vector3.ZERO,
		"input": input,
		"timestamp": OS.get_ticks_msec()
	}
	
	player.move_and_slide(input * player.move_speed * delta)
	
	predicted_state.result_position = player.global_transform.origin
	predicted_state.result_velocity = player.velocity if "velocity" in player else Vector3.ZERO
	
	prediction_buffer.append(predicted_state)
	
	while prediction_buffer.size() > MAX_PREDICTION_FRAMES:
		prediction_buffer.pop_front()
	
	input_sequence += 1
	
	return predicted_state

func receive_server_update(server_state):
	server_buffer.append(server_state)
	
	while server_buffer.size() > MAX_PREDICTION_FRAMES:
		server_buffer.pop_front()
	
	last_server_state = server_state

func _reconcile_with_server():
	if not last_server_state:
		return
	
	var server_sequence = last_server_state.get("sequence", -1)
	if server_sequence == -1:
		return
	
	var prediction_index = -1
	for i in range(prediction_buffer.size()):
		if prediction_buffer[i].sequence == server_sequence:
			prediction_index = i
			break
	
	if prediction_index == -1:
		return
	
	var predicted_state = prediction_buffer[prediction_index]
	var position_diff = last_server_state.position - predicted_state.result_position
	
	if position_diff.length() > RECONCILIATION_THRESHOLD:
		_apply_correction(position_diff, prediction_index)
		emit_signal("prediction_corrected", position_diff)

func _apply_correction(correction, from_index):
	var player = get_node("/root/Game/Player")
	if not player:
		return
	
	player.global_transform.origin += correction
	
	for i in range(from_index + 1, prediction_buffer.size()):
		var state = prediction_buffer[i]
		state.position += correction
		state.result_position += correction

func _process_predictions(delta):
	_clean_old_predictions()

func _clean_old_predictions():
	var current_time = OS.get_ticks_msec()
	var cutoff_time = current_time - 1000
	
	prediction_buffer = prediction_buffer.filter(func(state): 
		return state.timestamp > cutoff_time
	)

func get_current_prediction():
	if prediction_buffer.size() > 0:
		return prediction_buffer.back()
	return null

func set_prediction_enabled(enabled):
	prediction_enabled = enabled
	if not enabled:
		prediction_buffer.clear()

func get_prediction_latency():
	if not last_server_state:
		return 0
	
	return OS.get_ticks_msec() - last_server_state.timestamp

func get_prediction_accuracy():
	if prediction_buffer.size() == 0:
		return 1.0
	
	var total_error = 0.0
	var count = 0
	
	for state in prediction_buffer:
		if state.has("server_position"):
			var error = (state.result_position - state.server_position).length()
			total_error += error
			count += 1
	
	if count == 0:
		return 1.0
	
	var avg_error = total_error / count
	return max(0.0, 1.0 - (avg_error / 10.0))