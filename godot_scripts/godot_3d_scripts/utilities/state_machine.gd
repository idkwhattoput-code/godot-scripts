extends Node

export var initial_state : NodePath
export var debug_mode = false

signal state_changed(old_state, new_state)
signal state_entered(state_name)
signal state_exited(state_name)

var states = {}
var current_state = null
var previous_state = null
var state_time = 0.0

func _ready():
	_initialize_states()
	
	if initial_state:
		var init_state = get_node(initial_state)
		if init_state:
			change_state(init_state.name)

func _initialize_states():
	for child in get_children():
		if child.has_method("enter") and child.has_method("exit"):
			states[child.name] = child
			child.state_machine = self
			
			if child.has_signal("finished"):
				child.connect("finished", self, "_on_state_finished", [child.name])

func _physics_process(delta):
	if current_state and current_state.has_method("physics_update"):
		current_state.physics_update(delta)
	
	state_time += delta

func _process(delta):
	if current_state and current_state.has_method("update"):
		current_state.update(delta)

func _unhandled_input(event):
	if current_state and current_state.has_method("handle_input"):
		current_state.handle_input(event)

func change_state(state_name, params = {}):
	if not state_name in states:
		push_error("State '" + state_name + "' does not exist")
		return
	
	var new_state = states[state_name]
	
	if new_state == current_state:
		return
	
	if current_state:
		if current_state.has_method("exit"):
			current_state.exit()
		emit_signal("state_exited", current_state.name)
	
	previous_state = current_state
	current_state = new_state
	state_time = 0.0
	
	if current_state.has_method("enter"):
		current_state.enter(params)
	
	emit_signal("state_entered", current_state.name)
	emit_signal("state_changed", 
		previous_state.name if previous_state else null, 
		current_state.name
	)
	
	if debug_mode:
		print("State changed: ", 
			previous_state.name if previous_state else "null", 
			" -> ", current_state.name)

func _on_state_finished(state_name):
	if current_state and current_state.name == state_name:
		if current_state.has_method("get_next_state"):
			var next_state = current_state.get_next_state()
			if next_state:
				change_state(next_state)

func get_current_state_name():
	return current_state.name if current_state else ""

func get_previous_state_name():
	return previous_state.name if previous_state else ""

func is_current_state(state_name):
	return current_state and current_state.name == state_name

func get_state_time():
	return state_time

func has_state(state_name):
	return state_name in states

func get_state(state_name):
	return states.get(state_name, null)

func get_all_states():
	return states.keys()

func set_state_enabled(state_name, enabled):
	if state_name in states:
		states[state_name].set_process(enabled)
		states[state_name].set_physics_process(enabled)
		states[state_name].set_process_input(enabled)

func restart_current_state():
	if current_state:
		var state_name = current_state.name
		var temp_state = current_state
		
		current_state = null
		change_state(state_name)

func get_state_data():
	var data = {}
	
	for state_name in states:
		var state = states[state_name]
		if state.has_method("get_data"):
			data[state_name] = state.get_data()
	
	return {
		"current_state": get_current_state_name(),
		"previous_state": get_previous_state_name(),
		"state_time": state_time,
		"states_data": data
	}

func load_state_data(data):
	if "states_data" in data:
		for state_name in data.states_data:
			if state_name in states:
				var state = states[state_name]
				if state.has_method("set_data"):
					state.set_data(data.states_data[state_name])
	
	if "current_state" in data and data.current_state:
		change_state(data.current_state)
	
	if "state_time" in data:
		state_time = data.state_time

class State:
	extends Node
	
	var state_machine = null
	
	signal finished()
	
	func enter(params = {}):
		pass
	
	func exit():
		pass
	
	func update(delta):
		pass
	
	func physics_update(delta):
		pass
	
	func handle_input(event):
		pass
	
	func get_next_state():
		return null
	
	func get_data():
		return {}
	
	func set_data(data):
		pass