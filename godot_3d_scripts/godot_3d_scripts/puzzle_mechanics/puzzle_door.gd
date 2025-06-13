extends Spatial

export var door_type = "slide"
export var open_direction = Vector3(0, 3, 0)
export var open_rotation = Vector3(0, 90, 0)
export var open_speed = 2.0
export var auto_close = false
export var auto_close_delay = 5.0
export var require_all_triggers = true
export var locked = false

signal door_opened()
signal door_closed()
signal door_locked()
signal door_unlocked()

var is_open = false
var is_moving = false
var auto_close_timer = 0.0
var connected_triggers = []
var trigger_states = {}

onready var door_body = $DoorBody
onready var collision_shape = $DoorBody/CollisionShape
onready var open_sound = $OpenSound
onready var close_sound = $CloseSound
onready var locked_sound = $LockedSound

var closed_position = Vector3()
var open_position = Vector3()
var closed_rotation = Vector3()
var open_rotation_target = Vector3()

func _ready():
	if door_body:
		closed_position = door_body.translation
		open_position = closed_position + open_direction
		closed_rotation = door_body.rotation_degrees
		open_rotation_target = closed_rotation + open_rotation
	
	_find_connected_triggers()

func _physics_process(delta):
	if auto_close and is_open and not is_moving:
		auto_close_timer += delta
		if auto_close_timer >= auto_close_delay:
			close()
	
	if is_moving and door_body:
		var target_pos = open_position if is_open else closed_position
		var target_rot = open_rotation_target if is_open else closed_rotation
		
		match door_type:
			"slide":
				door_body.translation = door_body.translation.linear_interpolate(
					target_pos, 
					open_speed * delta
				)
				if door_body.translation.is_equal_approx(target_pos):
					is_moving = false
					_on_movement_complete()
			
			"rotate":
				door_body.rotation_degrees = door_body.rotation_degrees.linear_interpolate(
					target_rot,
					open_speed * delta
				)
				if door_body.rotation_degrees.is_equal_approx(target_rot):
					is_moving = false
					_on_movement_complete()
			
			"scale":
				var target_scale = Vector3(0.1, 0.1, 0.1) if is_open else Vector3.ONE
				door_body.scale = door_body.scale.linear_interpolate(
					target_scale,
					open_speed * delta
				)
				if door_body.scale.is_equal_approx(target_scale):
					is_moving = false
					_on_movement_complete()

func open():
	if locked or is_open or is_moving:
		if locked and locked_sound:
			locked_sound.play()
		return
	
	is_open = true
	is_moving = true
	auto_close_timer = 0.0
	
	if open_sound:
		open_sound.play()
	
	emit_signal("door_opened")

func close():
	if is_moving or not is_open:
		return
	
	is_open = false
	is_moving = true
	
	if close_sound:
		close_sound.play()
	
	emit_signal("door_closed")

func toggle():
	if is_open:
		close()
	else:
		open()

func _on_movement_complete():
	if collision_shape:
		collision_shape.disabled = is_open

func _find_connected_triggers():
	connected_triggers.clear()
	trigger_states.clear()
	
	var parent = get_parent()
	if not parent:
		return
	
	for child in parent.get_children():
		if child.has_signal("activated"):
			connected_triggers.append(child)
			trigger_states[child] = false
			
			child.connect("activated", self, "_on_trigger_activated", [child])
			child.connect("deactivated", self, "_on_trigger_deactivated", [child])

func _on_trigger_activated(trigger):
	trigger_states[trigger] = true
	_check_trigger_conditions()

func _on_trigger_deactivated(trigger):
	trigger_states[trigger] = false
	_check_trigger_conditions()

func _check_trigger_conditions():
	var should_open = false
	
	if require_all_triggers:
		should_open = true
		for state in trigger_states.values():
			if not state:
				should_open = false
				break
	else:
		for state in trigger_states.values():
			if state:
				should_open = true
				break
	
	if should_open:
		open()
	else:
		close()

func lock():
	locked = true
	emit_signal("door_locked")
	if is_open:
		close()

func unlock():
	locked = false
	emit_signal("door_unlocked")

func set_locked_state(state):
	if state:
		lock()
	else:
		unlock()

func force_open():
	var was_locked = locked
	locked = false
	open()
	locked = was_locked

func force_close():
	close()

func reset():
	is_open = false
	is_moving = false
	auto_close_timer = 0.0
	
	if door_body:
		door_body.translation = closed_position
		door_body.rotation_degrees = closed_rotation
		door_body.scale = Vector3.ONE
	
	if collision_shape:
		collision_shape.disabled = false