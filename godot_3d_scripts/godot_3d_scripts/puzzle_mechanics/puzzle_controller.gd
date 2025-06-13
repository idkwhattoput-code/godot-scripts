extends Node

signal puzzle_solved
signal puzzle_reset
signal puzzle_progress_updated(progress: float)

export var puzzle_id: String = ""
export var required_elements: int = 1
export var time_limit: float = 0.0
export var auto_reset: bool = false
export var reset_delay: float = 3.0

var active_elements: Array = []
var is_solved: bool = false
var time_remaining: float = 0.0
var timer_active: bool = false

onready var puzzle_elements: Array = []

func _ready():
	set_process(false)
	_find_puzzle_elements()
	
	if time_limit > 0:
		time_remaining = time_limit

func _process(delta):
	if timer_active and time_remaining > 0:
		time_remaining -= delta
		emit_signal("puzzle_progress_updated", get_completion_progress())
		
		if time_remaining <= 0:
			_on_timeout()

func _find_puzzle_elements():
	for child in get_children():
		if child.has_method("activate") and child.has_method("deactivate"):
			puzzle_elements.append(child)
			child.connect("activated", self, "_on_element_activated", [child])
			child.connect("deactivated", self, "_on_element_deactivated", [child])

func _on_element_activated(element):
	if is_solved:
		return
		
	if not element in active_elements:
		active_elements.append(element)
		
	if not timer_active and time_limit > 0:
		start_timer()
		
	_check_puzzle_state()

func _on_element_deactivated(element):
	if is_solved:
		return
		
	active_elements.erase(element)
	_check_puzzle_state()

func _check_puzzle_state():
	var progress = get_completion_progress()
	emit_signal("puzzle_progress_updated", progress)
	
	if active_elements.size() >= required_elements:
		solve_puzzle()

func solve_puzzle():
	if is_solved:
		return
		
	is_solved = true
	timer_active = false
	emit_signal("puzzle_solved")
	
	if auto_reset:
		yield(get_tree().create_timer(reset_delay), "timeout")
		reset_puzzle()

func reset_puzzle():
	is_solved = false
	active_elements.clear()
	time_remaining = time_limit
	timer_active = false
	
	for element in puzzle_elements:
		if element.has_method("reset"):
			element.reset()
	
	emit_signal("puzzle_reset")
	emit_signal("puzzle_progress_updated", 0.0)

func start_timer():
	if time_limit > 0:
		timer_active = true
		set_process(true)

func stop_timer():
	timer_active = false
	set_process(false)

func _on_timeout():
	timer_active = false
	reset_puzzle()

func get_completion_progress() -> float:
	if required_elements == 0:
		return 1.0
	return float(active_elements.size()) / float(required_elements)

func get_time_progress() -> float:
	if time_limit <= 0:
		return 1.0
	return time_remaining / time_limit

func save_state() -> Dictionary:
	return {
		"puzzle_id": puzzle_id,
		"is_solved": is_solved,
		"active_elements": active_elements.size(),
		"time_remaining": time_remaining
	}

func load_state(data: Dictionary):
	if data.has("is_solved"):
		is_solved = data.is_solved
	if data.has("time_remaining"):
		time_remaining = data.time_remaining