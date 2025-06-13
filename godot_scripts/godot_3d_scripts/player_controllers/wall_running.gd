extends Node

signal wall_run_started
signal wall_run_ended
signal wall_jumped

export var enabled: bool = true
export var wall_run_speed: float = 8.0
export var wall_run_acceleration: float = 10.0
export var wall_run_max_time: float = 3.0
export var wall_run_gravity_scale: float = 0.2
export var wall_jump_force: float = 10.0
export var wall_jump_up_force: float = 8.0
export var wall_detection_distance: float = 0.6
export var wall_run_min_speed: float = 4.0
export var wall_stick_angle: float = 50.0
export var wall_run_cooldown: float = 0.5
export var require_input: bool = true
export var auto_orient_camera: bool = true
export var camera_tilt_amount: float = 15.0
export var camera_tilt_speed: float = 5.0

var is_wall_running: bool = false
var wall_run_time: float = 0.0
var wall_normal: Vector3 = Vector3.ZERO
var wall_direction: Vector3 = Vector3.ZERO
var wall_side: int = 0
var cooldown_timer: float = 0.0
var current_camera_tilt: float = 0.0
var last_wall_normal: Vector3 = Vector3.ZERO

var player: KinematicBody
var camera: Camera
var original_gravity_scale: float = 1.0

func _ready():
	set_physics_process(false)

func initialize(player_node: KinematicBody, camera_node: Camera = null):
	player = player_node
	camera = camera_node
	
	if player.has_method("get_gravity_scale"):
		original_gravity_scale = player.get_gravity_scale()
	
	set_physics_process(true)

func _physics_process(delta):
	if not enabled or not player:
		return
	
	if cooldown_timer > 0:
		cooldown_timer -= delta
	
	if is_wall_running:
		_update_wall_run(delta)
	else:
		_check_for_wall_run()
	
	if camera and auto_orient_camera:
		_update_camera_tilt(delta)

func _check_for_wall_run():
	if cooldown_timer > 0:
		return
	
	if not _can_start_wall_run():
		return
	
	var wall_data = _detect_wall()
	if wall_data.wall_found:
		_start_wall_run(wall_data.normal, wall_data.side)

func _can_start_wall_run() -> bool:
	if not player.has_method("get_velocity"):
		return false
	
	var velocity = player.get_velocity()
	
	if velocity.length() < wall_run_min_speed:
		return false
	
	if player.is_on_floor():
		return false
	
	if require_input and not _is_wall_run_input_pressed():
		return false
	
	return true

func _detect_wall() -> Dictionary:
	var result = {
		"wall_found": false,
		"normal": Vector3.ZERO,
		"side": 0
	}
	
	var velocity = player.get_velocity()
	var move_direction = velocity.normalized()
	
	var right_check = _raycast_wall(player.global_transform.basis.x)
	var left_check = _raycast_wall(-player.global_transform.basis.x)
	
	if right_check.wall_found and _is_valid_wall_angle(right_check.normal, move_direction):
		result = right_check
		result.side = 1
	elif left_check.wall_found and _is_valid_wall_angle(left_check.normal, move_direction):
		result = left_check
		result.side = -1
	
	return result

func _raycast_wall(direction: Vector3) -> Dictionary:
	var space_state = player.get_world().direct_space_state
	var from = player.global_transform.origin
	var to = from + direction * wall_detection_distance
	
	var result = space_state.intersect_ray(from, to, [player], 1)
	
	if result:
		return {
			"wall_found": true,
			"normal": result.normal,
			"position": result.position
		}
	
	return {"wall_found": false}

func _is_valid_wall_angle(wall_normal: Vector3, move_direction: Vector3) -> bool:
	var wall_angle = rad2deg(acos(wall_normal.dot(Vector3.UP)))
	if wall_angle < 85.0 or wall_angle > 95.0:
		return false
	
	var angle_to_wall = rad2deg(acos(-wall_normal.dot(move_direction)))
	return angle_to_wall <= wall_stick_angle

func _start_wall_run(normal: Vector3, side: int):
	is_wall_running = true
	wall_run_time = 0.0
	wall_normal = normal
	wall_side = side
	last_wall_normal = normal
	
	var forward = player.global_transform.basis.z
	wall_direction = wall_normal.cross(Vector3.UP).normalized()
	if forward.dot(wall_direction) < 0:
		wall_direction = -wall_direction
	
	if player.has_method("set_gravity_scale"):
		player.set_gravity_scale(wall_run_gravity_scale)
	
	emit_signal("wall_run_started")

func _update_wall_run(delta):
	wall_run_time += delta
	
	if wall_run_time >= wall_run_max_time:
		_end_wall_run()
		return
	
	if player.is_on_floor():
		_end_wall_run()
		return
	
	var wall_check = _raycast_wall(player.global_transform.basis.x * wall_side)
	if not wall_check.wall_found:
		_end_wall_run()
		return
	
	wall_normal = wall_check.normal
	
	if player.has_method("get_velocity") and player.has_method("set_velocity"):
		var velocity = player.get_velocity()
		
		velocity = velocity.move_toward(wall_direction * wall_run_speed, wall_run_acceleration * delta)
		
		velocity.y = max(velocity.y, -2.0)
		
		var push_force = wall_normal * 2.0
		velocity += push_force
		
		player.set_velocity(velocity)
	
	if _is_jump_pressed():
		_wall_jump()

func _wall_jump():
	if not player.has_method("set_velocity"):
		return
	
	var jump_direction = (wall_normal + Vector3.UP * 0.5).normalized()
	var side_direction = wall_direction.cross(wall_normal).normalized() * wall_side * 0.3
	
	var jump_velocity = jump_direction * wall_jump_force + Vector3.UP * wall_jump_up_force + side_direction * wall_jump_force * 0.5
	
	player.set_velocity(jump_velocity)
	
	emit_signal("wall_jumped")
	_end_wall_run()

func _end_wall_run():
	if not is_wall_running:
		return
	
	is_wall_running = false
	wall_run_time = 0.0
	cooldown_timer = wall_run_cooldown
	
	if player.has_method("set_gravity_scale"):
		player.set_gravity_scale(original_gravity_scale)
	
	emit_signal("wall_run_ended")

func _update_camera_tilt(delta):
	var target_tilt = 0.0
	
	if is_wall_running:
		target_tilt = camera_tilt_amount * -wall_side
	
	current_camera_tilt = lerp(current_camera_tilt, target_tilt, camera_tilt_speed * delta)
	
	if abs(current_camera_tilt) > 0.1:
		camera.rotation_degrees.z = current_camera_tilt

func _is_wall_run_input_pressed() -> bool:
	return Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right")

func _is_jump_pressed() -> bool:
	return Input.is_action_just_pressed("jump")

func stop_wall_run():
	_end_wall_run()

func is_on_wall() -> bool:
	return is_wall_running

func get_wall_normal() -> Vector3:
	return wall_normal if is_wall_running else Vector3.ZERO

func get_wall_run_time_remaining() -> float:
	if not is_wall_running:
		return 0.0
	return max(0.0, wall_run_max_time - wall_run_time)

func get_wall_run_progress() -> float:
	if wall_run_max_time <= 0:
		return 0.0
	return clamp(wall_run_time / wall_run_max_time, 0.0, 1.0)

func set_wall_run_enabled(enabled_state: bool):
	enabled = enabled_state
	if not enabled and is_wall_running:
		_end_wall_run()