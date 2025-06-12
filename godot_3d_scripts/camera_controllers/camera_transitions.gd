extends Node

class_name CameraTransitions

signal transition_started(from_camera, to_camera)
signal transition_completed(camera)
signal transition_interrupted()

export var default_transition_time: float = 1.0
export var default_transition_curve: Curve
export var enable_motion_blur: bool = false
export var blur_strength: float = 0.5

var active_camera: Camera = null
var previous_camera: Camera = null
var transitioning: bool = false
var transition_progress: float = 0.0
var transition_data: Dictionary = {}
var camera_stack: Array = []
var registered_cameras: Dictionary = {}

onready var tween: Tween = Tween.new()

func _ready():
	add_child(tween)
	create_default_curve()
	find_and_register_cameras()

func create_default_curve():
	if not default_transition_curve:
		default_transition_curve = Curve.new()
		default_transition_curve.add_point(Vector2(0, 0))
		default_transition_curve.add_point(Vector2(0.3, 0.7))
		default_transition_curve.add_point(Vector2(0.7, 1.0))
		default_transition_curve.add_point(Vector2(1, 1))

func find_and_register_cameras():
	var cameras = get_tree().get_nodes_in_group("cameras")
	for camera in cameras:
		if camera is Camera:
			register_camera(camera.name, camera)

func register_camera(camera_name: String, camera: Camera):
	registered_cameras[camera_name] = camera
	camera.current = false
	
	if not active_camera:
		set_active_camera(camera)

func set_active_camera(camera: Camera):
	if active_camera:
		active_camera.current = false
		previous_camera = active_camera
	
	active_camera = camera
	active_camera.current = true

func transition_to_camera(target: Variant, duration: float = -1.0, transition_type: String = "linear"):
	var target_camera: Camera = null
	
	if target is String and target in registered_cameras:
		target_camera = registered_cameras[target]
	elif target is Camera:
		target_camera = target
	else:
		push_error("Invalid camera target")
		return
	
	if target_camera == active_camera:
		return
	
	if transitioning:
		interrupt_transition()
	
	var transition_duration = duration if duration >= 0 else default_transition_time
	
	match transition_type:
		"linear":
			linear_transition(target_camera, transition_duration)
		"smooth":
			smooth_transition(target_camera, transition_duration)
		"cut":
			cut_transition(target_camera)
		"dolly":
			dolly_transition(target_camera, transition_duration)
		"orbit":
			orbit_transition(target_camera, transition_duration)
		"shake":
			shake_transition(target_camera, transition_duration)
		_:
			smooth_transition(target_camera, transition_duration)

func linear_transition(target_camera: Camera, duration: float):
	start_transition(target_camera)
	
	var start_transform = active_camera.global_transform
	var end_transform = target_camera.global_transform
	var start_fov = active_camera.fov
	var end_fov = target_camera.fov
	
	create_transition_camera()
	var temp_camera = get_node("TransitionCamera")
	temp_camera.global_transform = start_transform
	temp_camera.fov = start_fov
	temp_camera.current = true
	active_camera.current = false
	
	tween.interpolate_property(temp_camera, "global_transform", 
		start_transform, end_transform, duration, 
		Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
	
	tween.interpolate_property(temp_camera, "fov", 
		start_fov, end_fov, duration, 
		Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
	
	tween.start()
	yield(tween, "tween_all_completed")
	
	complete_transition(target_camera, temp_camera)

func smooth_transition(target_camera: Camera, duration: float):
	start_transition(target_camera)
	
	var start_transform = active_camera.global_transform
	var end_transform = target_camera.global_transform
	var start_fov = active_camera.fov
	var end_fov = target_camera.fov
	
	create_transition_camera()
	var temp_camera = get_node("TransitionCamera")
	temp_camera.global_transform = start_transform
	temp_camera.fov = start_fov
	temp_camera.current = true
	active_camera.current = false
	
	var timer = 0.0
	while timer < duration and transitioning:
		timer += get_process_delta_time()
		var progress = timer / duration
		
		if default_transition_curve:
			progress = default_transition_curve.interpolate(progress)
		else:
			progress = smoothstep(0.0, 1.0, progress)
		
		temp_camera.global_transform = start_transform.interpolate_with(end_transform, progress)
		temp_camera.fov = lerp(start_fov, end_fov, progress)
		
		yield(get_tree(), "idle_frame")
	
	if transitioning:
		complete_transition(target_camera, temp_camera)

func cut_transition(target_camera: Camera):
	start_transition(target_camera)
	set_active_camera(target_camera)
	emit_signal("transition_completed", target_camera)
	transitioning = false

func dolly_transition(target_camera: Camera, duration: float):
	start_transition(target_camera)
	
	var start_pos = active_camera.global_transform.origin
	var end_pos = target_camera.global_transform.origin
	var mid_point = (start_pos + end_pos) / 2.0
	mid_point += active_camera.global_transform.basis.z * 5.0
	
	create_transition_camera()
	var temp_camera = get_node("TransitionCamera")
	temp_camera.global_transform = active_camera.global_transform
	temp_camera.current = true
	active_camera.current = false
	
	var points = [start_pos, mid_point, end_pos]
	var timer = 0.0
	
	while timer < duration and transitioning:
		timer += get_process_delta_time()
		var t = timer / duration
		
		var position = bezier_interpolate(points, t)
		temp_camera.global_transform.origin = position
		
		var look_direction = (end_pos - position).normalized()
		if look_direction.length() > 0:
			temp_camera.look_at(position + look_direction, Vector3.UP)
		
		yield(get_tree(), "idle_frame")
	
	if transitioning:
		complete_transition(target_camera, temp_camera)

func orbit_transition(target_camera: Camera, duration: float):
	start_transition(target_camera)
	
	var pivot_point = (active_camera.global_transform.origin + target_camera.global_transform.origin) / 2.0
	var start_offset = active_camera.global_transform.origin - pivot_point
	var end_offset = target_camera.global_transform.origin - pivot_point
	var radius = start_offset.length()
	
	create_transition_camera()
	var temp_camera = get_node("TransitionCamera")
	temp_camera.global_transform = active_camera.global_transform
	temp_camera.current = true
	active_camera.current = false
	
	var timer = 0.0
	while timer < duration and transitioning:
		timer += get_process_delta_time()
		var t = timer / duration
		
		var angle = t * PI
		var height_offset = sin(angle) * 2.0
		var position = start_offset.slerp(end_offset, t) + Vector3(0, height_offset, 0)
		position = position.normalized() * radius + pivot_point
		
		temp_camera.global_transform.origin = position
		temp_camera.look_at(pivot_point, Vector3.UP)
		
		yield(get_tree(), "idle_frame")
	
	if transitioning:
		complete_transition(target_camera, temp_camera)

func shake_transition(target_camera: Camera, duration: float):
	start_transition(target_camera)
	
	var shake_intensity = 0.5
	var shake_frequency = 30.0
	
	create_transition_camera()
	var temp_camera = get_node("TransitionCamera")
	temp_camera.global_transform = active_camera.global_transform
	temp_camera.current = true
	active_camera.current = false
	
	var timer = 0.0
	var shake_timer = 0.0
	
	while timer < duration and transitioning:
		timer += get_process_delta_time()
		shake_timer += get_process_delta_time() * shake_frequency
		
		var t = timer / duration
		var shake_amount = (1.0 - t) * shake_intensity
		
		var base_transform = active_camera.global_transform.interpolate_with(
			target_camera.global_transform, t)
		
		var shake_offset = Vector3(
			sin(shake_timer * 1.0) * shake_amount,
			sin(shake_timer * 1.5) * shake_amount,
			sin(shake_timer * 2.0) * shake_amount
		)
		
		temp_camera.global_transform = base_transform
		temp_camera.global_transform.origin += shake_offset
		
		yield(get_tree(), "idle_frame")
	
	if transitioning:
		complete_transition(target_camera, temp_camera)

func create_transition_camera():
	if has_node("TransitionCamera"):
		get_node("TransitionCamera").queue_free()
	
	var temp_camera = Camera.new()
	temp_camera.name = "TransitionCamera"
	temp_camera.fov = active_camera.fov
	temp_camera.near = active_camera.near
	temp_camera.far = active_camera.far
	add_child(temp_camera)
	
	if enable_motion_blur:
		apply_motion_blur(temp_camera)

func apply_motion_blur(camera: Camera):
	pass

func start_transition(target_camera: Camera):
	transitioning = true
	transition_progress = 0.0
	transition_data = {
		"from": active_camera,
		"to": target_camera,
		"start_time": OS.get_ticks_msec()
	}
	emit_signal("transition_started", active_camera, target_camera)

func complete_transition(target_camera: Camera, temp_camera: Camera = null):
	if temp_camera:
		temp_camera.current = false
		temp_camera.queue_free()
	
	set_active_camera(target_camera)
	transitioning = false
	transition_progress = 1.0
	emit_signal("transition_completed", target_camera)

func interrupt_transition():
	if transitioning:
		transitioning = false
		if has_node("TransitionCamera"):
			get_node("TransitionCamera").queue_free()
		emit_signal("transition_interrupted")

func push_camera(camera: Variant):
	var cam = get_camera_from_variant(camera)
	if cam:
		camera_stack.push_back(active_camera)
		transition_to_camera(cam)

func pop_camera(duration: float = -1.0):
	if camera_stack.size() > 0:
		var previous = camera_stack.pop_back()
		transition_to_camera(previous, duration)

func get_camera_from_variant(camera: Variant) -> Camera:
	if camera is String and camera in registered_cameras:
		return registered_cameras[camera]
	elif camera is Camera:
		return camera
	return null

func bezier_interpolate(points: Array, t: float) -> Vector3:
	if points.size() == 2:
		return points[0].linear_interpolate(points[1], t)
	elif points.size() == 3:
		var p0 = points[0].linear_interpolate(points[1], t)
		var p1 = points[1].linear_interpolate(points[2], t)
		return p0.linear_interpolate(p1, t)
	return Vector3.ZERO

func set_camera_limits(camera: Camera, limits: Dictionary):
	if "fov_min" in limits:
		camera.fov = max(camera.fov, limits.fov_min)
	if "fov_max" in limits:
		camera.fov = min(camera.fov, limits.fov_max)

func get_active_camera() -> Camera:
	return active_camera

func get_camera_by_name(camera_name: String) -> Camera:
	if camera_name in registered_cameras:
		return registered_cameras[camera_name]
	return null

func is_transitioning() -> bool:
	return transitioning

func get_transition_progress() -> float:
	return transition_progress