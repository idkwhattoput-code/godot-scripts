extends Node

export var global_haptic_multiplier: float = 1.0
export var max_simultaneous_effects: int = 3
export var haptic_enabled: bool = true

var left_controller: ARVRController
var right_controller: ARVRController
var active_effects: Dictionary = {}
var effect_queue: Array = []

class HapticEffect:
	var controller: ARVRController
	var pattern: Array = []
	var current_index: int = 0
	var time_accumulator: float = 0.0
	var loop: bool = false
	var priority: int = 0
	var id: String = ""
	
	func _init(ctrl: ARVRController, ptrn: Array, lp: bool = false, pri: int = 0):
		controller = ctrl
		pattern = ptrn
		loop = lp
		priority = pri
		id = str(OS.get_unix_time()) + str(randi())

var haptic_patterns = {
	"click": [{"duration": 0.05, "amplitude": 0.3}],
	"double_click": [
		{"duration": 0.05, "amplitude": 0.3},
		{"duration": 0.05, "amplitude": 0.0},
		{"duration": 0.05, "amplitude": 0.3}
	],
	"soft_pulse": [{"duration": 0.2, "amplitude": 0.2}],
	"strong_pulse": [{"duration": 0.1, "amplitude": 0.8}],
	"heartbeat": [
		{"duration": 0.1, "amplitude": 0.6},
		{"duration": 0.1, "amplitude": 0.0},
		{"duration": 0.1, "amplitude": 0.8},
		{"duration": 0.3, "amplitude": 0.0}
	],
	"vibration": [{"duration": 1.0, "amplitude": 0.5}],
	"ramp_up": [
		{"duration": 0.1, "amplitude": 0.1},
		{"duration": 0.1, "amplitude": 0.3},
		{"duration": 0.1, "amplitude": 0.5},
		{"duration": 0.1, "amplitude": 0.7},
		{"duration": 0.1, "amplitude": 1.0}
	],
	"ramp_down": [
		{"duration": 0.1, "amplitude": 1.0},
		{"duration": 0.1, "amplitude": 0.7},
		{"duration": 0.1, "amplitude": 0.5},
		{"duration": 0.1, "amplitude": 0.3},
		{"duration": 0.1, "amplitude": 0.1}
	],
	"error": [
		{"duration": 0.2, "amplitude": 0.8},
		{"duration": 0.1, "amplitude": 0.0},
		{"duration": 0.2, "amplitude": 0.8},
		{"duration": 0.1, "amplitude": 0.0},
		{"duration": 0.2, "amplitude": 0.8}
	],
	"success": [
		{"duration": 0.1, "amplitude": 0.3},
		{"duration": 0.1, "amplitude": 0.5},
		{"duration": 0.2, "amplitude": 0.7}
	],
	"warning": [
		{"duration": 0.5, "amplitude": 0.4},
		{"duration": 0.2, "amplitude": 0.0},
		{"duration": 0.5, "amplitude": 0.4}
	],
	"engine": [
		{"duration": 0.05, "amplitude": 0.2},
		{"duration": 0.05, "amplitude": 0.4},
		{"duration": 0.05, "amplitude": 0.3},
		{"duration": 0.05, "amplitude": 0.5}
	],
	"impact": [
		{"duration": 0.05, "amplitude": 1.0},
		{"duration": 0.1, "amplitude": 0.5},
		{"duration": 0.15, "amplitude": 0.2}
	]
}

signal haptic_started(controller, pattern_name)
signal haptic_finished(controller, pattern_name)

func _ready():
	var player = get_parent()
	left_controller = player.get_node("LeftController")
	right_controller = player.get_node("RightController")
	
	set_physics_process(true)

func _physics_process(delta):
	if not haptic_enabled:
		return
	
	_process_active_effects(delta)
	_process_effect_queue()

func _process_active_effects(delta):
	var completed_effects = []
	
	for id in active_effects:
		var effect = active_effects[id]
		effect.time_accumulator += delta
		
		var current_step = effect.pattern[effect.current_index]
		
		if effect.controller:
			var amplitude = current_step.amplitude * global_haptic_multiplier
			effect.controller.rumble = clamp(amplitude, 0.0, 1.0)
		
		if effect.time_accumulator >= current_step.duration:
			effect.time_accumulator = 0.0
			effect.current_index += 1
			
			if effect.current_index >= effect.pattern.size():
				if effect.loop:
					effect.current_index = 0
				else:
					completed_effects.append(id)
					if effect.controller:
						effect.controller.rumble = 0.0
	
	for id in completed_effects:
		active_effects.erase(id)

func _process_effect_queue():
	if effect_queue.size() == 0:
		return
	
	if active_effects.size() < max_simultaneous_effects:
		var next_effect = effect_queue.pop_front()
		active_effects[next_effect.id] = next_effect
		emit_signal("haptic_started", next_effect.controller, next_effect.id)

func play_haptic_pattern(controller: ARVRController, pattern_name: String, loop: bool = false, priority: int = 0):
	if not haptic_enabled or not controller or not haptic_patterns.has(pattern_name):
		return ""
	
	var pattern = haptic_patterns[pattern_name]
	var effect = HapticEffect.new(controller, pattern, loop, priority)
	
	if active_effects.size() >= max_simultaneous_effects:
		_handle_effect_overflow(effect)
	else:
		active_effects[effect.id] = effect
		emit_signal("haptic_started", controller, pattern_name)
	
	return effect.id

func play_custom_haptic(controller: ARVRController, pattern: Array, loop: bool = false, priority: int = 0):
	if not haptic_enabled or not controller:
		return ""
	
	var effect = HapticEffect.new(controller, pattern, loop, priority)
	
	if active_effects.size() >= max_simultaneous_effects:
		_handle_effect_overflow(effect)
	else:
		active_effects[effect.id] = effect
	
	return effect.id

func _handle_effect_overflow(new_effect: HapticEffect):
	var lowest_priority_id = ""
	var lowest_priority = 999
	
	for id in active_effects:
		if active_effects[id].priority < lowest_priority:
			lowest_priority = active_effects[id].priority
			lowest_priority_id = id
	
	if new_effect.priority >= lowest_priority:
		effect_queue.append(new_effect)
	else:
		stop_haptic(lowest_priority_id)
		active_effects[new_effect.id] = new_effect

func stop_haptic(effect_id: String):
	if active_effects.has(effect_id):
		var effect = active_effects[effect_id]
		if effect.controller:
			effect.controller.rumble = 0.0
		active_effects.erase(effect_id)
		emit_signal("haptic_finished", effect.controller, effect_id)

func stop_all_haptics(controller: ARVRController = null):
	if controller:
		for id in active_effects:
			if active_effects[id].controller == controller:
				stop_haptic(id)
	else:
		for id in active_effects:
			stop_haptic(id)
		effect_queue.clear()

func play_haptic_for_both(pattern_name: String, loop: bool = false, priority: int = 0):
	var left_id = play_haptic_pattern(left_controller, pattern_name, loop, priority)
	var right_id = play_haptic_pattern(right_controller, pattern_name, loop, priority)
	return [left_id, right_id]

func create_dynamic_haptic(controller: ARVRController, amplitude: float, frequency: float, duration: float):
	var steps = int(duration * frequency)
	var pattern = []
	
	for i in range(steps):
		var t = float(i) / float(steps)
		var step_amplitude = amplitude * sin(t * PI * 2.0 * frequency)
		pattern.append({
			"duration": 1.0 / frequency,
			"amplitude": abs(step_amplitude)
		})
	
	return play_custom_haptic(controller, pattern)

func play_collision_haptic(controller: ARVRController, impact_force: float):
	var amplitude = clamp(impact_force * 0.1, 0.1, 1.0)
	var duration = clamp(impact_force * 0.01, 0.05, 0.3)
	
	var pattern = [
		{"duration": duration * 0.3, "amplitude": amplitude},
		{"duration": duration * 0.7, "amplitude": amplitude * 0.3}
	]
	
	play_custom_haptic(controller, pattern)

func add_haptic_pattern(name: String, pattern: Array):
	haptic_patterns[name] = pattern

func remove_haptic_pattern(name: String):
	if haptic_patterns.has(name):
		haptic_patterns.erase(name)

func set_haptic_enabled(enabled: bool):
	haptic_enabled = enabled
	if not enabled:
		stop_all_haptics()

func get_active_effect_count() -> int:
	return active_effects.size()

func is_effect_playing(effect_id: String) -> bool:
	return active_effects.has(effect_id)