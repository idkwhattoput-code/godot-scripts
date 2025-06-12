extends Node

export var min_gesture_duration: float = 0.2
export var max_gesture_duration: float = 2.0
export var position_threshold: float = 0.05
export var rotation_threshold: float = 15.0
export var recognition_threshold: float = 0.7
export var max_recording_points: int = 50
export var debug_draw: bool = false

var left_controller: ARVRController
var right_controller: ARVRController
var recorded_gestures: Dictionary = {}
var is_recording: Dictionary = {"left": false, "right": false}
var current_gesture: Dictionary = {"left": [], "right": []}
var gesture_start_time: Dictionary = {"left": 0.0, "right": 0.0}
var last_position: Dictionary = {}

signal gesture_detected(controller_name, gesture_name, confidence)
signal gesture_recording_started(controller_name)
signal gesture_recording_finished(controller_name)

func _ready():
	var player = get_parent()
	left_controller = player.get_node("LeftController")
	right_controller = player.get_node("RightController")
	
	if left_controller:
		left_controller.connect("button_pressed", self, "_on_button_pressed", ["left"])
		left_controller.connect("button_released", self, "_on_button_released", ["left"])
	
	if right_controller:
		right_controller.connect("button_pressed", self, "_on_button_pressed", ["right"])
		right_controller.connect("button_released", self, "_on_button_released", ["right"])
	
	_load_default_gestures()

func _physics_process(delta):
	if is_recording["left"]:
		_record_gesture_point(left_controller, "left")
	
	if is_recording["right"]:
		_record_gesture_point(right_controller, "right")
	
	if debug_draw:
		_debug_draw_gestures()

func _on_button_pressed(button_name: String, controller_name: String):
	if button_name == "trigger":
		start_gesture_recording(controller_name)

func _on_button_released(button_name: String, controller_name: String):
	if button_name == "trigger":
		stop_gesture_recording(controller_name)

func start_gesture_recording(controller_name: String):
	if is_recording[controller_name]:
		return
	
	is_recording[controller_name] = true
	current_gesture[controller_name].clear()
	gesture_start_time[controller_name] = OS.get_ticks_msec() / 1000.0
	
	var controller = left_controller if controller_name == "left" else right_controller
	if controller:
		last_position[controller_name] = controller.global_transform.origin
	
	emit_signal("gesture_recording_started", controller_name)

func stop_gesture_recording(controller_name: String):
	if not is_recording[controller_name]:
		return
	
	is_recording[controller_name] = false
	
	var duration = (OS.get_ticks_msec() / 1000.0) - gesture_start_time[controller_name]
	
	if duration >= min_gesture_duration and duration <= max_gesture_duration:
		_process_recorded_gesture(controller_name)
	
	emit_signal("gesture_recording_finished", controller_name)

func _record_gesture_point(controller: ARVRController, controller_name: String):
	if not controller or current_gesture[controller_name].size() >= max_recording_points:
		return
	
	var current_pos = controller.global_transform.origin
	var current_rot = controller.global_transform.basis.get_euler()
	
	if last_position.has(controller_name):
		var distance = current_pos.distance_to(last_position[controller_name])
		if distance < position_threshold:
			return
	
	var gesture_point = {
		"position": current_pos,
		"rotation": current_rot,
		"timestamp": OS.get_ticks_msec() / 1000.0
	}
	
	current_gesture[controller_name].append(gesture_point)
	last_position[controller_name] = current_pos

func _process_recorded_gesture(controller_name: String):
	var gesture_data = current_gesture[controller_name]
	if gesture_data.size() < 3:
		return
	
	var normalized_gesture = _normalize_gesture(gesture_data)
	var best_match = ""
	var best_confidence = 0.0
	
	for gesture_name in recorded_gestures:
		var confidence = _compare_gestures(normalized_gesture, recorded_gestures[gesture_name])
		if confidence > best_confidence and confidence >= recognition_threshold:
			best_confidence = confidence
			best_match = gesture_name
	
	if best_match != "":
		emit_signal("gesture_detected", controller_name, best_match, best_confidence)

func _normalize_gesture(gesture_data: Array) -> Array:
	if gesture_data.size() == 0:
		return []
	
	var normalized = []
	var center = Vector3.ZERO
	
	for point in gesture_data:
		center += point.position
	center /= gesture_data.size()
	
	var max_distance = 0.0
	for point in gesture_data:
		var distance = (point.position - center).length()
		max_distance = max(max_distance, distance)
	
	if max_distance > 0:
		for point in gesture_data:
			var normalized_point = {
				"position": (point.position - center) / max_distance,
				"rotation": point.rotation,
				"timestamp": point.timestamp - gesture_data[0].timestamp
			}
			normalized.append(normalized_point)
	
	return normalized

func _compare_gestures(gesture1: Array, gesture2: Array) -> float:
	if gesture1.size() == 0 or gesture2.size() == 0:
		return 0.0
	
	var resampled1 = _resample_gesture(gesture1, 32)
	var resampled2 = _resample_gesture(gesture2, 32)
	
	var position_similarity = _calculate_position_similarity(resampled1, resampled2)
	var rotation_similarity = _calculate_rotation_similarity(resampled1, resampled2)
	var timing_similarity = _calculate_timing_similarity(resampled1, resampled2)
	
	return (position_similarity * 0.6 + rotation_similarity * 0.3 + timing_similarity * 0.1)

func _resample_gesture(gesture: Array, target_points: int) -> Array:
	if gesture.size() <= 1:
		return gesture
	
	var total_length = 0.0
	for i in range(1, gesture.size()):
		total_length += gesture[i].position.distance_to(gesture[i-1].position)
	
	var segment_length = total_length / (target_points - 1)
	var resampled = [gesture[0]]
	var accumulated_length = 0.0
	var current_index = 0
	
	for i in range(1, target_points):
		var target_length = i * segment_length
		
		while accumulated_length < target_length and current_index < gesture.size() - 1:
			var segment_dist = gesture[current_index + 1].position.distance_to(gesture[current_index].position)
			
			if accumulated_length + segment_dist >= target_length:
				var t = (target_length - accumulated_length) / segment_dist
				var interpolated_point = {
					"position": gesture[current_index].position.linear_interpolate(gesture[current_index + 1].position, t),
					"rotation": gesture[current_index].rotation.linear_interpolate(gesture[current_index + 1].rotation, t),
					"timestamp": lerp(gesture[current_index].timestamp, gesture[current_index + 1].timestamp, t)
				}
				resampled.append(interpolated_point)
				break
			
			accumulated_length += segment_dist
			current_index += 1
	
	return resampled

func _calculate_position_similarity(gesture1: Array, gesture2: Array) -> float:
	var total_distance = 0.0
	var min_size = min(gesture1.size(), gesture2.size())
	
	for i in range(min_size):
		total_distance += gesture1[i].position.distance_to(gesture2[i].position)
	
	return max(0.0, 1.0 - (total_distance / min_size))

func _calculate_rotation_similarity(gesture1: Array, gesture2: Array) -> float:
	var total_difference = 0.0
	var min_size = min(gesture1.size(), gesture2.size())
	
	for i in range(min_size):
		var rot_diff = (gesture1[i].rotation - gesture2[i].rotation).abs()
		total_difference += (rot_diff.x + rot_diff.y + rot_diff.z)
	
	return max(0.0, 1.0 - (total_difference / (min_size * PI * 3.0)))

func _calculate_timing_similarity(gesture1: Array, gesture2: Array) -> float:
	if gesture1.size() == 0 or gesture2.size() == 0:
		return 0.0
	
	var duration1 = gesture1[-1].timestamp - gesture1[0].timestamp
	var duration2 = gesture2[-1].timestamp - gesture2[0].timestamp
	
	if duration1 == 0 or duration2 == 0:
		return 1.0 if duration1 == duration2 else 0.0
	
	var ratio = min(duration1, duration2) / max(duration1, duration2)
	return ratio

func record_gesture(name: String, gesture_data: Array):
	recorded_gestures[name] = _normalize_gesture(gesture_data)

func remove_gesture(name: String):
	if recorded_gestures.has(name):
		recorded_gestures.erase(name)

func save_gestures(file_path: String):
	var file = File.new()
	file.open(file_path, File.WRITE)
	file.store_var(recorded_gestures)
	file.close()

func load_gestures(file_path: String):
	var file = File.new()
	if file.file_exists(file_path):
		file.open(file_path, File.READ)
		recorded_gestures = file.get_var()
		file.close()

func _load_default_gestures():
	var circle_gesture = []
	for i in range(16):
		var angle = (i / 16.0) * TAU
		circle_gesture.append({
			"position": Vector3(cos(angle), sin(angle), 0),
			"rotation": Vector3.ZERO,
			"timestamp": i * 0.05
		})
	record_gesture("circle", circle_gesture)
	
	var swipe_right = []
	for i in range(10):
		swipe_right.append({
			"position": Vector3(i * 0.1, 0, 0),
			"rotation": Vector3.ZERO,
			"timestamp": i * 0.02
		})
	record_gesture("swipe_right", swipe_right)
	
	var swipe_left = []
	for i in range(10):
		swipe_left.append({
			"position": Vector3(-i * 0.1, 0, 0),
			"rotation": Vector3.ZERO,
			"timestamp": i * 0.02
		})
	record_gesture("swipe_left", swipe_left)
	
	var swipe_up = []
	for i in range(10):
		swipe_up.append({
			"position": Vector3(0, i * 0.1, 0),
			"rotation": Vector3.ZERO,
			"timestamp": i * 0.02
		})
	record_gesture("swipe_up", swipe_up)

func _debug_draw_gestures():
	pass