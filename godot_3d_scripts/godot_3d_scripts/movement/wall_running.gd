extends Node

export var wall_run_speed = 10.0
export var wall_run_gravity_scale = 0.3
export var wall_run_duration = 3.0
export var wall_jump_force = Vector3(5, 10, 5)
export var wall_detection_distance = 1.2
export var min_wall_run_speed = 5.0
export var wall_run_angle_tolerance = 45.0

signal wall_run_started(wall_normal)
signal wall_run_ended()
signal wall_jumped()

var is_wall_running = false
var wall_run_timer = 0.0
var current_wall_normal = Vector3.ZERO
var last_wall_normal = Vector3.ZERO
var wall_run_side = 0

onready var left_ray = $LeftWallRay
onready var right_ray = $RightWallRay
onready var forward_ray = $ForwardRay
onready var wall_run_particles = $WallRunParticles

func _ready():
	_setup_raycasts()

func _physics_process(delta):
	if is_wall_running:
		wall_run_timer -= delta
		if wall_run_timer <= 0:
			end_wall_run()
		else:
			_update_wall_run_effects()

func _setup_raycasts():
	if not left_ray:
		left_ray = RayCast.new()
		left_ray.cast_to = Vector3(-wall_detection_distance, 0, 0)
		left_ray.enabled = true
		add_child(left_ray)
	
	if not right_ray:
		right_ray = RayCast.new()
		right_ray.cast_to = Vector3(wall_detection_distance, 0, 0)
		right_ray.enabled = true
		add_child(right_ray)
	
	if not forward_ray:
		forward_ray = RayCast.new()
		forward_ray.cast_to = Vector3(0, 0, -wall_detection_distance)
		forward_ray.enabled = true
		add_child(forward_ray)

func check_for_wall_run(player_velocity):
	if is_wall_running:
		return
	
	if player_velocity.length() < min_wall_run_speed:
		return
	
	if not get_parent().is_on_floor():
		var wall_data = _detect_wall()
		if wall_data.wall_found:
			start_wall_run(wall_data.normal, wall_data.side)

func _detect_wall():
	var result = {
		"wall_found": false,
		"normal": Vector3.ZERO,
		"side": 0
	}
	
	if left_ray.is_colliding():
		result.wall_found = true
		result.normal = left_ray.get_collision_normal()
		result.side = -1
	elif right_ray.is_colliding():
		result.wall_found = true
		result.normal = right_ray.get_collision_normal()
		result.side = 1
	
	if result.wall_found:
		var wall_angle = rad2deg(result.normal.angle_to(Vector3.UP))
		if wall_angle < (90 - wall_run_angle_tolerance) or wall_angle > (90 + wall_run_angle_tolerance):
			result.wall_found = false
	
	return result

func start_wall_run(wall_normal, side):
	if wall_normal.dot(last_wall_normal) > 0.9:
		return
	
	is_wall_running = true
	wall_run_timer = wall_run_duration
	current_wall_normal = wall_normal
	wall_run_side = side
	
	emit_signal("wall_run_started", wall_normal)
	
	if wall_run_particles:
		wall_run_particles.emitting = true
		_position_particles()

func end_wall_run():
	if not is_wall_running:
		return
	
	is_wall_running = false
	wall_run_timer = 0.0
	last_wall_normal = current_wall_normal
	current_wall_normal = Vector3.ZERO
	
	emit_signal("wall_run_ended")
	
	if wall_run_particles:
		wall_run_particles.emitting = false
	
	get_tree().create_timer(0.5).connect("timeout", self, "_reset_last_wall")

func _reset_last_wall():
	last_wall_normal = Vector3.ZERO

func get_wall_run_velocity(current_velocity, forward_direction):
	if not is_wall_running:
		return current_velocity
	
	var wall_forward = current_wall_normal.cross(Vector3.UP).normalized()
	
	if wall_forward.dot(forward_direction) < 0:
		wall_forward = -wall_forward
	
	var new_velocity = wall_forward * wall_run_speed
	
	new_velocity.y = current_velocity.y * wall_run_gravity_scale
	
	return new_velocity

func wall_jump():
	if not is_wall_running:
		return false
	
	var jump_direction = current_wall_normal + Vector3.UP * 0.5
	jump_direction = jump_direction.normalized()
	
	var jump_velocity = jump_direction * wall_jump_force.length()
	
	end_wall_run()
	emit_signal("wall_jumped")
	
	return jump_velocity

func _update_wall_run_effects():
	if wall_run_particles:
		_position_particles()
	
	if get_parent().has_method("tilt_camera"):
		get_parent().tilt_camera(wall_run_side * 15.0)

func _position_particles():
	if not wall_run_particles:
		return
	
	wall_run_particles.position = Vector3(wall_run_side * 0.5, -0.5, 0)
	wall_run_particles.process_material.direction = current_wall_normal

func get_wall_run_progress():
	if not is_wall_running:
		return 0.0
	return wall_run_timer / wall_run_duration

func can_wall_run():
	return not is_wall_running and last_wall_normal == Vector3.ZERO

func get_gravity_multiplier():
	if is_wall_running:
		return wall_run_gravity_scale
	return 1.0

func reset():
	is_wall_running = false
	wall_run_timer = 0.0
	current_wall_normal = Vector3.ZERO
	last_wall_normal = Vector3.ZERO
	wall_run_side = 0
	
	if wall_run_particles:
		wall_run_particles.emitting = false