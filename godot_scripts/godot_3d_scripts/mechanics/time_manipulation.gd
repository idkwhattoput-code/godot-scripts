extends Node

class_name TimeManipulationSystem

signal time_scale_changed(new_scale)
signal time_stopped()
signal time_resumed()
signal time_reversed()
signal time_rewind_started()
signal time_rewind_ended()
signal timeline_recorded(timestamp)
signal timeline_restored(timestamp)

export var max_time_scale: float = 3.0
export var min_time_scale: float = 0.1
export var rewind_duration: float = 5.0
export var record_interval: float = 0.1
export var max_timeline_length: float = 10.0
export var enable_object_time_control: bool = true
export var enable_physics_time_control: bool = true
export var smooth_time_transitions: bool = true
export var transition_speed: float = 5.0
export var time_energy_max: float = 100.0
export var time_energy_regen: float = 10.0
export var slow_time_cost: float = 20.0
export var stop_time_cost: float = 50.0
export var rewind_cost: float = 30.0

var current_time_scale: float = 1.0
var target_time_scale: float = 1.0
var is_time_stopped: bool = false
var is_rewinding: bool = false
var time_energy: float = 100.0
var global_time: float = 0.0
var timeline: Array = []
var tracked_objects: Dictionary = {}
var time_bubbles: Array = []
var recording_timer: float = 0.0
var rewind_timer: float = 0.0

class TimelineSnapshot:
	var timestamp: float
	var object_states: Dictionary = {}
	var global_state: Dictionary = {}
	
	func _init(time: float):
		timestamp = time

class TrackedObject:
	var node: Node
	var properties: Array = []
	var timeline: Array = []
	var original_time_scale: float = 1.0
	var custom_time_scale: float = 1.0
	var is_physics_body: bool = false
	
	func _init(object_node: Node):
		node = object_node
		is_physics_body = object_node is RigidBody or object_node is KinematicBody
		detect_properties()
	
	func detect_properties():
		properties = ["transform", "visible"]
		
		if is_physics_body:
			if node is RigidBody:
				properties.append_array(["linear_velocity", "angular_velocity", "sleeping"])
			elif node is KinematicBody:
				if "velocity" in node:
					properties.append("velocity")
		
		if node.has_method("get_animation_player"):
			properties.append("animation_position")

class ObjectState:
	var property_values: Dictionary = {}
	
	func capture_from(node: Node, properties: Array):
		for prop in properties:
			if prop in node:
				property_values[prop] = node.get(prop)
			elif prop == "animation_position" and node.has_method("get_animation_player"):
				var anim_player = node.get_animation_player()
				if anim_player and anim_player.is_playing():
					property_values["animation_name"] = anim_player.current_animation
					property_values["animation_position"] = anim_player.current_animation_position
	
	func apply_to(node: Node):
		for prop in property_values:
			if prop == "animation_name" and node.has_method("get_animation_player"):
				var anim_player = node.get_animation_player()
				if anim_player:
					anim_player.play(property_values[prop])
					if property_values.has("animation_position"):
						anim_player.seek(property_values["animation_position"])
			elif prop in node:
				node.set(prop, property_values[prop])

class TimeBubble:
	var position: Vector3
	var radius: float
	var time_scale: float
	var duration: float
	var affected_objects: Array = []
	
	func _init(pos: Vector3, r: float, scale: float, dur: float = -1):
		position = pos
		radius = r
		time_scale = scale
		duration = dur
	
	func is_point_inside(point: Vector3) -> bool:
		return position.distance_to(point) <= radius
	
	func update(delta: float) -> bool:
		if duration > 0:
			duration -= delta
			return duration > 0
		return true

func _ready():
	set_process(true)
	set_physics_process(true)

func _process(delta):
	update_time_energy(delta)
	update_time_scale(delta)
	update_recording(delta)
	update_time_bubbles(delta)
	
	if is_rewinding:
		update_rewind(delta)
	
	global_time += delta

func update_time_energy(delta):
	if current_time_scale != 1.0 and not is_rewinding:
		var cost = 0.0
		if is_time_stopped:
			cost = stop_time_cost * delta
		elif current_time_scale < 1.0:
			cost = slow_time_cost * delta * (1.0 - current_time_scale)
		
		time_energy = max(0, time_energy - cost)
		
		if time_energy <= 0:
			set_time_scale(1.0)
	else:
		time_energy = min(time_energy_max, time_energy + time_energy_regen * delta)

func update_time_scale(delta):
	if smooth_time_transitions and current_time_scale != target_time_scale:
		current_time_scale = lerp(current_time_scale, target_time_scale, transition_speed * delta)
		
		if abs(current_time_scale - target_time_scale) < 0.01:
			current_time_scale = target_time_scale
		
		apply_global_time_scale()
		emit_signal("time_scale_changed", current_time_scale)

func update_recording(delta):
	if is_rewinding:
		return
	
	recording_timer += delta
	if recording_timer >= record_interval:
		recording_timer = 0.0
		record_timeline_snapshot()

func update_time_bubbles(delta):
	var bubbles_to_remove = []
	
	for i in range(time_bubbles.size()):
		var bubble = time_bubbles[i]
		if not bubble.update(delta * current_time_scale):
			bubbles_to_remove.append(i)
			restore_bubble_objects(bubble)
	
	for i in range(bubbles_to_remove.size() - 1, -1, -1):
		time_bubbles.remove(bubbles_to_remove[i])
	
	for bubble in time_bubbles:
		update_bubble_objects(bubble)

func update_rewind(delta):
	rewind_timer += delta
	
	if rewind_timer >= rewind_duration or timeline.empty():
		end_rewind()
		return
	
	var rewind_progress = rewind_timer / rewind_duration
	var target_time = global_time - (rewind_progress * rewind_duration)
	
	restore_timeline_state(target_time)

func set_time_scale(scale: float):
	if time_energy <= 0 and scale < 1.0:
		return
	
	target_time_scale = clamp(scale, min_time_scale, max_time_scale)
	
	if not smooth_time_transitions:
		current_time_scale = target_time_scale
		apply_global_time_scale()
		emit_signal("time_scale_changed", current_time_scale)

func stop_time():
	if time_energy < stop_time_cost:
		return
	
	is_time_stopped = true
	set_time_scale(0.0)
	emit_signal("time_stopped")

func resume_time():
	is_time_stopped = false
	set_time_scale(1.0)
	emit_signal("time_resumed")

func slow_time(factor: float = 0.5):
	set_time_scale(factor)

func speed_up_time(factor: float = 2.0):
	set_time_scale(factor)

func start_rewind():
	if time_energy < rewind_cost or timeline.empty():
		return
	
	is_rewinding = true
	rewind_timer = 0.0
	time_energy -= rewind_cost
	emit_signal("time_rewind_started")

func end_rewind():
	is_rewinding = false
	rewind_timer = 0.0
	emit_signal("time_rewind_ended")

func create_time_bubble(position: Vector3, radius: float, time_scale: float, duration: float = -1):
	var bubble = TimeBubble.new(position, radius, time_scale, duration)
	time_bubbles.append(bubble)
	
	for obj_id in tracked_objects:
		var tracked = tracked_objects[obj_id]
		if tracked.node and tracked.node.global_transform.origin.distance_to(position) <= radius:
			bubble.affected_objects.append(tracked)
	
	return bubble

func register_object(node: Node, properties: Array = []):
	if not enable_object_time_control:
		return
	
	var tracked = TrackedObject.new(node)
	if not properties.empty():
		tracked.properties = properties
	
	tracked_objects[node.get_instance_id()] = tracked

func unregister_object(node: Node):
	tracked_objects.erase(node.get_instance_id())

func apply_global_time_scale():
	Engine.time_scale = current_time_scale
	
	if enable_physics_time_control:
		Engine.iterations_per_second = int(60 * current_time_scale)
	
	for obj_id in tracked_objects:
		var tracked = tracked_objects[obj_id]
		if not tracked.node:
			continue
		
		apply_object_time_scale(tracked, current_time_scale * tracked.custom_time_scale)

func apply_object_time_scale(tracked: TrackedObject, scale: float):
	if not tracked.node:
		return
	
	if tracked.node.has_method("set_physics_process"):
		tracked.node.set_physics_process(scale > 0.01)
	
	if tracked.node.has_method("set_process"):
		tracked.node.set_process(scale > 0.01)
	
	if tracked.node.has_method("get_animation_player"):
		var anim_player = tracked.node.get_animation_player()
		if anim_player:
			anim_player.playback_speed = scale
	
	if tracked.is_physics_body and tracked.node is RigidBody:
		tracked.node.set_sleeping(scale < 0.01)

func record_timeline_snapshot():
	var snapshot = TimelineSnapshot.new(global_time)
	
	for obj_id in tracked_objects:
		var tracked = tracked_objects[obj_id]
		if not tracked.node:
			continue
		
		var state = ObjectState.new()
		state.capture_from(tracked.node, tracked.properties)
		snapshot.object_states[obj_id] = state
	
	snapshot.global_state["time_scale"] = current_time_scale
	snapshot.global_state["time_energy"] = time_energy
	
	timeline.append(snapshot)
	
	while timeline.size() > 0 and timeline[0].timestamp < global_time - max_timeline_length:
		timeline.pop_front()
	
	emit_signal("timeline_recorded", global_time)

func restore_timeline_state(target_time: float):
	var best_snapshot = null
	var best_diff = INF
	
	for snapshot in timeline:
		var diff = abs(snapshot.timestamp - target_time)
		if diff < best_diff:
			best_diff = diff
			best_snapshot = snapshot
	
	if not best_snapshot:
		return
	
	for obj_id in best_snapshot.object_states:
		if obj_id in tracked_objects:
			var tracked = tracked_objects[obj_id]
			if tracked.node:
				best_snapshot.object_states[obj_id].apply_to(tracked.node)
	
	time_energy = best_snapshot.global_state.get("time_energy", time_energy)
	emit_signal("timeline_restored", best_snapshot.timestamp)

func update_bubble_objects(bubble: TimeBubble):
	for tracked in bubble.affected_objects:
		if tracked.node:
			apply_object_time_scale(tracked, bubble.time_scale)

func restore_bubble_objects(bubble: TimeBubble):
	for tracked in bubble.affected_objects:
		if tracked.node:
			apply_object_time_scale(tracked, current_time_scale * tracked.custom_time_scale)

func set_object_custom_time_scale(node: Node, scale: float):
	var obj_id = node.get_instance_id()
	if obj_id in tracked_objects:
		tracked_objects[obj_id].custom_time_scale = scale

func get_time_energy_percentage() -> float:
	return (time_energy / time_energy_max) * 100.0

func can_use_ability(cost: float) -> bool:
	return time_energy >= cost

func toggle_time_stop():
	if is_time_stopped:
		resume_time()
	else:
		stop_time()

func clear_timeline():
	timeline.clear()
	recording_timer = 0.0

func get_current_time_scale() -> float:
	return current_time_scale

func is_time_manipulated() -> bool:
	return current_time_scale != 1.0 or is_rewinding

func get_timeline_duration() -> float:
	if timeline.empty():
		return 0.0
	return global_time - timeline[0].timestamp

func create_time_field(position: Vector3, radius: float, params: Dictionary):
	var time_scale = params.get("time_scale", 0.5)
	var duration = params.get("duration", 5.0)
	var bubble = create_time_bubble(position, radius, time_scale, duration)
	return bubble