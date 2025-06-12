extends Node

signal player_sync_received(player_id, data)
signal object_sync_received(object_id, data)

const SYNC_RATE = 0.05
const INTERPOLATION_BUFFER = 3
const EXTRAPOLATION_LIMIT = 0.5

var sync_timer = 0.0
var player_states = {}
var object_states = {}
var state_buffer = {}

func _ready():
	set_process(true)
	if get_tree().is_network_server():
		set_physics_process(true)

func _process(delta):
	sync_timer += delta
	if sync_timer >= SYNC_RATE:
		sync_timer = 0.0
		if get_tree().is_network_server():
			_broadcast_server_state()
		else:
			_send_client_input()
	
	_interpolate_states(delta)

func _broadcast_server_state():
	var state = {
		"timestamp": OS.get_ticks_msec(),
		"players": {},
		"objects": {}
	}
	
	for player_id in player_states:
		state.players[player_id] = player_states[player_id]
	
	for object_id in object_states:
		state.objects[object_id] = object_states[object_id]
	
	rpc_unreliable("receive_server_state", state)

func _send_client_input():
	var input_data = {
		"timestamp": OS.get_ticks_msec(),
		"input": _get_current_input(),
		"position": _get_player_position(),
		"rotation": _get_player_rotation()
	}
	
	rpc_unreliable_id(1, "receive_client_input", get_tree().get_network_unique_id(), input_data)

remote func receive_server_state(state):
	if not get_tree().is_network_server():
		_buffer_state(state)

remote func receive_client_input(player_id, input_data):
	if get_tree().is_network_server():
		_process_client_input(player_id, input_data)

func _buffer_state(state):
	var timestamp = state.timestamp
	if not state_buffer.has(timestamp):
		state_buffer[timestamp] = state
	
	while state_buffer.size() > INTERPOLATION_BUFFER * 2:
		var oldest_time = state_buffer.keys().min()
		state_buffer.erase(oldest_time)

func _interpolate_states(delta):
	if state_buffer.size() < INTERPOLATION_BUFFER:
		return
	
	var render_time = OS.get_ticks_msec() - (INTERPOLATION_BUFFER * SYNC_RATE * 1000)
	var states = state_buffer.keys()
	states.sort()
	
	var from_state = null
	var to_state = null
	
	for i in range(states.size() - 1):
		if states[i] <= render_time and states[i + 1] >= render_time:
			from_state = state_buffer[states[i]]
			to_state = state_buffer[states[i + 1]]
			break
	
	if from_state and to_state:
		var factor = (render_time - from_state.timestamp) / float(to_state.timestamp - from_state.timestamp)
		_apply_interpolation(from_state, to_state, factor)

func _apply_interpolation(from_state, to_state, factor):
	for player_id in from_state.players:
		if to_state.players.has(player_id):
			var from = from_state.players[player_id]
			var to = to_state.players[player_id]
			var interpolated = {
				"position": from.position.linear_interpolate(to.position, factor),
				"rotation": from.rotation.linear_interpolate(to.rotation, factor)
			}
			emit_signal("player_sync_received", player_id, interpolated)

func _get_current_input():
	return {
		"movement": Input.get_vector("move_left", "move_right", "move_forward", "move_back"),
		"jump": Input.is_action_pressed("jump"),
		"shoot": Input.is_action_pressed("shoot"),
		"aim": Input.is_action_pressed("aim")
	}

func _get_player_position():
	var player = get_node("/root/Game/Player")
	if player:
		return player.global_transform.origin
	return Vector3.ZERO

func _get_player_rotation():
	var player = get_node("/root/Game/Player")
	if player:
		return player.global_transform.basis.get_euler()
	return Vector3.ZERO

func _process_client_input(player_id, input_data):
	if not player_states.has(player_id):
		player_states[player_id] = {}
	
	player_states[player_id] = {
		"position": input_data.position,
		"rotation": input_data.rotation,
		"input": input_data.input,
		"timestamp": input_data.timestamp
	}

func register_sync_object(object_id, object_ref):
	object_states[object_id] = {
		"position": object_ref.global_transform.origin,
		"rotation": object_ref.global_transform.basis.get_euler(),
		"state": {}
	}

func unregister_sync_object(object_id):
	object_states.erase(object_id)

func update_object_state(object_id, state_data):
	if object_states.has(object_id):
		object_states[object_id].state = state_data