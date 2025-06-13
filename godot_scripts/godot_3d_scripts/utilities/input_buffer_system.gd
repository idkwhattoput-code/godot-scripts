extends Node

export var buffer_time = 0.2
export var max_buffer_size = 10
export var enable_debug = false

signal input_buffered(action)
signal input_consumed(action)
signal buffer_cleared()

var input_buffer = []
var action_timers = {}
var registered_actions = []

class BufferedInput:
	var action : String
	var timestamp : float
	var consumed : bool = false
	
	func _init(act, time):
		action = act
		timestamp = time

func _ready():
	set_process_input(true)
	set_physics_process(true)

func register_action(action_name, priority = 0):
	if not action_name in registered_actions:
		registered_actions.append(action_name)
		action_timers[action_name] = 0.0

func _input(event):
	for action in registered_actions:
		if event.is_action_pressed(action):
			_buffer_input(action)

func _physics_process(delta):
	_clean_expired_inputs()
	_update_action_timers(delta)

func _buffer_input(action):
	if input_buffer.size() >= max_buffer_size:
		input_buffer.pop_front()
	
	var buffered_input = BufferedInput.new(action, OS.get_ticks_msec() / 1000.0)
	input_buffer.append(buffered_input)
	
	emit_signal("input_buffered", action)
	
	if enable_debug:
		print("Buffered input: ", action)

func _clean_expired_inputs():
	var current_time = OS.get_ticks_msec() / 1000.0
	var i = 0
	
	while i < input_buffer.size():
		var input = input_buffer[i]
		if current_time - input.timestamp > buffer_time or input.consumed:
			input_buffer.remove(i)
		else:
			i += 1

func _update_action_timers(delta):
	for action in action_timers:
		if action_timers[action] > 0:
			action_timers[action] -= delta

func check_buffered_input(action, consume = true):
	var current_time = OS.get_ticks_msec() / 1000.0
	
	for input in input_buffer:
		if input.action == action and not input.consumed:
			if current_time - input.timestamp <= buffer_time:
				if consume:
					input.consumed = true
					emit_signal("input_consumed", action)
					
					if enable_debug:
						print("Consumed buffered input: ", action)
				
				return true
	
	return false

func get_buffered_input(action):
	var current_time = OS.get_ticks_msec() / 1000.0
	
	for input in input_buffer:
		if input.action == action and not input.consumed:
			if current_time - input.timestamp <= buffer_time:
				return input
	
	return null

func consume_input(action):
	var input = get_buffered_input(action)
	if input:
		input.consumed = true
		emit_signal("input_consumed", action)
		return true
	return false

func has_buffered_input(action):
	return check_buffered_input(action, false)

func get_all_buffered_actions():
	var actions = []
	var current_time = OS.get_ticks_msec() / 1000.0
	
	for input in input_buffer:
		if not input.consumed and current_time - input.timestamp <= buffer_time:
			actions.append(input.action)
	
	return actions

func clear_buffer():
	input_buffer.clear()
	emit_signal("buffer_cleared")

func clear_action(action):
	var i = 0
	while i < input_buffer.size():
		if input_buffer[i].action == action:
			input_buffer.remove(i)
		else:
			i += 1

func set_buffer_time(time):
	buffer_time = max(0.0, time)

func get_buffer_size():
	return input_buffer.size()

func is_action_on_cooldown(action):
	return action_timers.get(action, 0.0) > 0

func set_action_cooldown(action, time):
	if action in action_timers:
		action_timers[action] = time

func get_oldest_buffered_input():
	if input_buffer.empty():
		return null
	
	var current_time = OS.get_ticks_msec() / 1000.0
	
	for input in input_buffer:
		if not input.consumed and current_time - input.timestamp <= buffer_time:
			return input
	
	return null

func get_newest_buffered_input():
	if input_buffer.empty():
		return null
	
	var current_time = OS.get_ticks_msec() / 1000.0
	
	for i in range(input_buffer.size() - 1, -1, -1):
		var input = input_buffer[i]
		if not input.consumed and current_time - input.timestamp <= buffer_time:
			return input
	
	return null

func debug_print_buffer():
	if not enable_debug:
		return
	
	print("\n=== Input Buffer State ===")
	print("Buffer size: ", input_buffer.size())
	
	var current_time = OS.get_ticks_msec() / 1000.0
	
	for i in range(input_buffer.size()):
		var input = input_buffer[i]
		var age = current_time - input.timestamp
		print("  [", i, "] Action: ", input.action, 
			  " | Age: ", "%.3f" % age, "s",
			  " | Consumed: ", input.consumed)
	
	print("=========================\n")