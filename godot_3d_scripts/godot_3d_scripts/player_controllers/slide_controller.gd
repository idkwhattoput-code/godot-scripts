extends Node

signal slide_started
signal slide_ended
signal slide_jumped

export var enabled: bool = true
export var slide_speed: float = 12.0
export var slide_acceleration: float = 15.0
export var slide_deceleration: float = 8.0
export var slide_min_speed: float = 5.0
export var slide_max_duration: float = 2.0
export var slide_cooldown: float = 0.5
export var slide_height_reduction: float = 0.5
export var slide_jump_boost: float = 1.3
export var slope_slide_enabled: bool = true
export var slope_acceleration_factor: float = 1.5
export var min_slope_angle: float = 10.0
export var slide_turn_rate: float = 2.0
export var slide_friction: float = 0.98
export var slide_input_key: String = "crouch"
export var require_minimum_speed: bool = true
export var camera_slide_offset: Vector3 = Vector3(0, -0.3, 0)
export var camera_slide_fov_increase: float = 10.0
export var slide_particles_enabled: bool = true

var is_sliding: bool = false
var slide_time: float = 0.0
var slide_direction: Vector3 = Vector3.ZERO
var cooldown_timer: float = 0.0
var original_height: float = 2.0
var original_camera_position: Vector3
var original_camera_fov: float
var current_slide_speed: float = 0.0
var entry_speed: float = 0.0

var player: KinematicBody
var collision_shape: CollisionShape
var camera: Camera
var particles: CPUParticles

func _ready():
	set_physics_process(false)

func initialize(player_node: KinematicBody, shape: CollisionShape, camera_node: Camera = null):
	player = player_node
	collision_shape = shape
	camera = camera_node
	
	if collision_shape and collision_shape.shape is CapsuleShape:
		original_height = collision_shape.shape.height
	
	if camera:
		original_camera_position = camera.transform.origin
		original_camera_fov = camera.fov
	
	_setup_slide_particles()
	set_physics_process(true)

func _physics_process(delta):
	if not enabled or not player:
		return
	
	if cooldown_timer > 0:
		cooldown_timer -= delta
	
	if is_sliding:
		_update_slide(delta)
	else:
		_check_for_slide_start()

func _check_for_slide_start():
	if cooldown_timer > 0:
		return
	
	if not _can_start_slide():
		return
	
	if Input.is_action_just_pressed(slide_input_key):
		_start_slide()

func _can_start_slide() -> bool:
	if not player.is_on_floor():
		return false
	
	if require_minimum_speed and player.has_method("get_velocity"):
		var velocity = player.get_velocity()
		var horizontal_speed = Vector2(velocity.x, velocity.z).length()
		if horizontal_speed < slide_min_speed:
			return false
	
	return true

func _start_slide():
	is_sliding = true
	slide_time = 0.0
	
	if player.has_method("get_velocity"):
		var velocity = player.get_velocity()
		slide_direction = Vector3(velocity.x, 0, velocity.z).normalized()
		entry_speed = Vector2(velocity.x, velocity.z).length()
		current_slide_speed = max(entry_speed, slide_speed)
	else:
		slide_direction = -player.global_transform.basis.z
		current_slide_speed = slide_speed
	
	_adjust_collision_shape(true)
	_adjust_camera(true)
	
	if slide_particles_enabled and particles:
		particles.emitting = true
	
	emit_signal("slide_started")

func _update_slide(delta):
	slide_time += delta
	
	if slide_time >= slide_max_duration:
		_end_slide()
		return
	
	if not player.is_on_floor():
		if Input.is_action_just_pressed("jump"):
			_slide_jump()
		else:
			_end_slide()
		return
	
	if Input.is_action_just_released(slide_input_key):
		_end_slide()
		return
	
	_update_slide_movement(delta)
	
	if current_slide_speed < slide_min_speed * 0.5:
		_end_slide()

func _update_slide_movement(delta):
	if not player.has_method("get_velocity") or not player.has_method("set_velocity"):
		return
	
	var input_vector = _get_movement_input()
	if input_vector.length() > 0:
		var turn_direction = (player.global_transform.basis.x * input_vector.x + player.global_transform.basis.z * input_vector.y).normalized()
		slide_direction = slide_direction.lerp(turn_direction, slide_turn_rate * delta).normalized()
	
	var slope_factor = _calculate_slope_factor()
	
	if slope_factor > 0 and slope_slide_enabled:
		current_slide_speed = min(current_slide_speed + slide_acceleration * slope_factor * delta, slide_speed * 2.0)
	else:
		current_slide_speed = max(current_slide_speed - slide_deceleration * delta, 0.0)
	
	current_slide_speed *= slide_friction
	
	var velocity = player.get_velocity()
	velocity.x = slide_direction.x * current_slide_speed
	velocity.z = slide_direction.z * current_slide_speed
	
	if slope_factor > 0:
		velocity.y = min(velocity.y, -slope_factor * 2.0)
	
	player.set_velocity(velocity)

func _calculate_slope_factor() -> float:
	if not player.has_method("get_floor_normal"):
		return 0.0
	
	var floor_normal = player.get_floor_normal()
	var slope_angle = rad2deg(acos(floor_normal.dot(Vector3.UP)))
	
	if slope_angle < min_slope_angle:
		return 0.0
	
	var slope_direction = Vector3.UP.cross(floor_normal).cross(floor_normal).normalized()
	var alignment = slide_direction.dot(slope_direction)
	
	return alignment * (slope_angle / 45.0) * slope_acceleration_factor

func _slide_jump():
	if not player.has_method("set_velocity"):
		return
	
	var velocity = player.get_velocity()
	velocity.y = player.get("jump_velocity") * slide_jump_boost if player.has("jump_velocity") else 10.0 * slide_jump_boost
	
	var boost_direction = slide_direction * current_slide_speed * 0.3
	velocity.x += boost_direction.x
	velocity.z += boost_direction.z
	
	player.set_velocity(velocity)
	
	emit_signal("slide_jumped")
	_end_slide()

func _end_slide():
	if not is_sliding:
		return
	
	is_sliding = false
	slide_time = 0.0
	cooldown_timer = slide_cooldown
	current_slide_speed = 0.0
	
	_adjust_collision_shape(false)
	_adjust_camera(false)
	
	if particles:
		particles.emitting = false
	
	emit_signal("slide_ended")

func _adjust_collision_shape(sliding: bool):
	if not collision_shape or not collision_shape.shape is CapsuleShape:
		return
	
	var capsule = collision_shape.shape as CapsuleShape
	
	if sliding:
		capsule.height = original_height * slide_height_reduction
		collision_shape.transform.origin.y = -(original_height - capsule.height) / 2.0
	else:
		capsule.height = original_height
		collision_shape.transform.origin.y = 0.0

func _adjust_camera(sliding: bool):
	if not camera:
		return
	
	if sliding:
		camera.transform.origin = original_camera_position + camera_slide_offset
		camera.fov = original_camera_fov + camera_slide_fov_increase
	else:
		camera.transform.origin = original_camera_position
		camera.fov = original_camera_fov

func _get_movement_input() -> Vector2:
	var input = Vector2.ZERO
	input.x = Input.get_axis("move_left", "move_right")
	input.y = Input.get_axis("move_forward", "move_backward")
	return input.normalized()

func _setup_slide_particles():
	if not slide_particles_enabled:
		return
	
	particles = CPUParticles.new()
	particles.emitting = false
	particles.amount = 20
	particles.lifetime = 0.5
	particles.direction = Vector3(0, 0.2, -1)
	particles.initial_velocity = 2.0
	particles.initial_velocity_random = 0.5
	particles.scale_amount = 0.2
	particles.scale_amount_random = 0.1
	
	if player:
		player.add_child(particles)
		particles.transform.origin = Vector3(0, -0.8, 0)

func stop_slide():
	_end_slide()

func is_player_sliding() -> bool:
	return is_sliding

func get_slide_progress() -> float:
	if slide_max_duration <= 0:
		return 0.0
	return clamp(slide_time / slide_max_duration, 0.0, 1.0)

func get_slide_speed() -> float:
	return current_slide_speed if is_sliding else 0.0

func set_slide_enabled(enabled_state: bool):
	enabled = enabled_state
	if not enabled and is_sliding:
		_end_slide()

func can_slide() -> bool:
	return enabled and cooldown_timer <= 0 and _can_start_slide()