extends Node

class_name WallRunningController

signal wall_run_started(wall_normal)
signal wall_run_ended()
signal wall_jumped(jump_direction)
signal wall_climb_started()
signal wall_slide_started()

export var enabled: bool = true
export var wall_run_speed: float = 12.0
export var wall_climb_speed: float = 4.0
export var wall_slide_speed: float = 8.0
export var max_wall_run_time: float = 3.0
export var wall_jump_force: float = 15.0
export var wall_jump_up_force: float = 10.0
export var min_wall_run_speed: float = 5.0
export var wall_detection_distance: float = 1.2
export var wall_stick_force: float = 30.0
export var gravity_scale_on_wall: float = 0.3
export var max_wall_run_angle: float = 45.0
export var wall_run_height_loss: float = 2.0
export var allow_vertical_wall_run: bool = false
export var allow_ceiling_run: bool = false
export var auto_wall_jump: bool = false
export var wall_jump_cooldown: float = 0.2

var player: KinematicBody = null
var current_wall_normal: Vector3 = Vector3.ZERO
var wall_run_time: float = 0.0
var is_wall_running: bool = false
var is_wall_climbing: bool = false
var is_wall_sliding: bool = false
var last_wall_jump_time: float = 0.0
var initial_wall_height: float = 0.0
var wall_run_direction: Vector3 = Vector3.ZERO
var previous_walls: Array = []
var wall_run_particles: CPUParticles = null

var wall_check_rays: Array = [
	Vector3.RIGHT,
	Vector3.LEFT,
	Vector3.FORWARD,
	Vector3.BACK,
	Vector3.RIGHT + Vector3.FORWARD,
	Vector3.RIGHT + Vector3.BACK,
	Vector3.LEFT + Vector3.FORWARD,
	Vector3.LEFT + Vector3.BACK
]

class WallInfo:
	var normal: Vector3
	var point: Vector3
	var distance: float
	var angle: float
	var is_valid: bool
	
	func _init(n: Vector3 = Vector3.ZERO, p: Vector3 = Vector3.ZERO, d: float = 0.0):
		normal = n
		point = p
		distance = d
		angle = 0.0
		is_valid = false

func _ready():
	if not player:
		player = get_parent()
		if not player is KinematicBody:
			push_error("WallRunningController must be attached to a KinematicBody or have player reference set")
			set_process(false)
			set_physics_process(false)
			return
	
	setup_particles()

func setup_particles():
	wall_run_particles = CPUParticles.new()
	wall_run_particles.emitting = false
	wall_run_particles.amount = 20
	wall_run_particles.lifetime = 0.5
	wall_run_particles.spread = 10.0
	wall_run_particles.initial_velocity = 5.0
	wall_run_particles.scale_amount = 0.5
	wall_run_particles.color = Color(0.8, 0.8, 0.8, 0.5)
	player.add_child(wall_run_particles)

func _physics_process(delta):
	if not enabled:
		return
	
	update_wall_jump_cooldown(delta)
	
	if is_wall_running:
		update_wall_run(delta)
	elif player.is_on_floor():
		reset_wall_run_state()
	else:
		check_for_wall_run()

func update_wall_jump_cooldown(delta):
	if last_wall_jump_time > 0:
		last_wall_jump_time -= delta

func check_for_wall_run():
	if not can_start_wall_run():
		return
	
	var wall_info = detect_best_wall()
	if wall_info.is_valid:
		start_wall_run(wall_info)

func can_start_wall_run() -> bool:
	if player.is_on_floor():
		return false
	
	var velocity = player.get("velocity")
	if not velocity:
		return false
	
	var horizontal_speed = Vector3(velocity.x, 0, velocity.z).length()
	if horizontal_speed < min_wall_run_speed:
		return false
	
	if last_wall_jump_time > 0:
		return false
	
	return true

func detect_best_wall() -> WallInfo:
	var best_wall = WallInfo.new()
	var player_velocity = player.get("velocity")
	if not player_velocity:
		return best_wall
	
	var forward_dir = Vector3(player_velocity.x, 0, player_velocity.z).normalized()
	
	for ray_dir in wall_check_rays:
		var world_ray_dir = player.global_transform.basis * ray_dir
		var wall_info = cast_wall_ray(world_ray_dir.normalized())
		
		if not wall_info.is_valid:
			continue
		
		var dot_product = forward_dir.dot(-wall_info.normal)
		if dot_product < 0.3:
			continue
		
		wall_info.angle = rad2deg(acos(wall_info.normal.dot(Vector3.UP)))
		
		if wall_info.angle > max_wall_run_angle and wall_info.angle < (180 - max_wall_run_angle):
			if wall_info.distance < best_wall.distance or best_wall.distance == 0:
				best_wall = wall_info
	
	return best_wall

func cast_wall_ray(direction: Vector3) -> WallInfo:
	var space_state = player.get_world().direct_space_state
	var from = player.global_transform.origin
	var to = from + direction * wall_detection_distance
	
	var result = space_state.intersect_ray(from, to, [player])
	
	var wall_info = WallInfo.new()
	if result:
		wall_info.normal = result.normal
		wall_info.point = result.position
		wall_info.distance = from.distance_to(result.position)
		wall_info.is_valid = true
	
	return wall_info

func start_wall_run(wall_info: WallInfo):
	if wall_info.normal in previous_walls:
		return
	
	is_wall_running = true
	current_wall_normal = wall_info.normal
	wall_run_time = 0.0
	initial_wall_height = player.global_transform.origin.y
	
	var player_velocity = player.get("velocity")
	if player_velocity:
		var forward = Vector3(player_velocity.x, 0, player_velocity.z).normalized()
		var wall_right = current_wall_normal.cross(Vector3.UP).normalized()
		wall_run_direction = wall_right if forward.dot(wall_right) > 0 else -wall_right
		
		if wall_info.angle < 10 and allow_vertical_wall_run:
			is_wall_climbing = true
			wall_run_direction = Vector3.UP
		elif wall_info.angle > 170 and allow_ceiling_run:
			wall_run_direction = forward
	
	if wall_run_particles:
		wall_run_particles.emitting = true
		wall_run_particles.direction = current_wall_normal
	
	emit_signal("wall_run_started", current_wall_normal)

func update_wall_run(delta):
	wall_run_time += delta
	
	if wall_run_time > max_wall_run_time:
		end_wall_run()
		return
	
	if not is_wall_still_valid():
		end_wall_run()
		return
	
	apply_wall_run_movement(delta)
	
	if Input.is_action_just_pressed("jump"):
		perform_wall_jump()
	elif auto_wall_jump and wall_run_time > max_wall_run_time * 0.8:
		perform_wall_jump()

func is_wall_still_valid() -> bool:
	var wall_info = cast_wall_ray(-current_wall_normal)
	
	if not wall_info.is_valid:
		for ray_dir in wall_check_rays:
			var world_ray_dir = player.global_transform.basis * ray_dir
			wall_info = cast_wall_ray(world_ray_dir.normalized())
			if wall_info.is_valid and wall_info.normal.dot(current_wall_normal) > 0.7:
				current_wall_normal = wall_info.normal
				return true
		return false
	
	return wall_info.distance < wall_detection_distance * 1.5

func apply_wall_run_movement(delta):
	var velocity = player.get("velocity")
	if not velocity:
		return
	
	if is_wall_climbing:
		velocity = Vector3.UP * wall_climb_speed
		velocity.y -= gravity_scale_on_wall * 9.8 * delta
	else:
		var run_velocity = wall_run_direction * wall_run_speed
		
		velocity.x = run_velocity.x
		velocity.z = run_velocity.z
		
		var height_factor = 1.0 - (wall_run_time / max_wall_run_time)
		velocity.y = -wall_run_height_loss * (1.0 - height_factor)
		velocity.y -= gravity_scale_on_wall * 9.8 * delta
	
	velocity += current_wall_normal * wall_stick_force * delta
	
	player.set("velocity", velocity)
	
	align_player_to_wall()

func align_player_to_wall():
	if not player.has_method("look_at"):
		return
	
	var look_direction = wall_run_direction
	if is_wall_climbing:
		look_direction = Vector3.UP.cross(current_wall_normal).normalized()
	
	var target_position = player.global_transform.origin + look_direction
	player.look_at(target_position, Vector3.UP)

func perform_wall_jump():
	if last_wall_jump_time > 0:
		return
	
	var jump_direction = current_wall_normal + Vector3.UP * 0.5
	jump_direction = jump_direction.normalized()
	
	var velocity = player.get("velocity")
	if velocity:
		velocity = jump_direction * wall_jump_force
		velocity.y = wall_jump_up_force
		
		if Input.is_action_pressed("move_forward"):
			var camera = player.get_node_or_null("Camera")
			if camera:
				var forward = -camera.global_transform.basis.z
				forward.y = 0
				forward = forward.normalized()
				velocity += forward * wall_jump_force * 0.5
		
		player.set("velocity", velocity)
	
	previous_walls.append(current_wall_normal)
	if previous_walls.size() > 3:
		previous_walls.pop_front()
	
	last_wall_jump_time = wall_jump_cooldown
	emit_signal("wall_jumped", jump_direction)
	end_wall_run()

func end_wall_run():
	is_wall_running = false
	is_wall_climbing = false
	is_wall_sliding = false
	wall_run_time = 0.0
	
	if wall_run_particles:
		wall_run_particles.emitting = false
	
	emit_signal("wall_run_ended")

func reset_wall_run_state():
	previous_walls.clear()
	current_wall_normal = Vector3.ZERO

func start_wall_slide():
	if is_wall_running:
		return
	
	is_wall_sliding = true
	emit_signal("wall_slide_started")

func get_wall_run_progress() -> float:
	if not is_wall_running:
		return 0.0
	return wall_run_time / max_wall_run_time

func is_on_wall() -> bool:
	return is_wall_running or is_wall_climbing or is_wall_sliding

func get_current_wall_normal() -> Vector3:
	return current_wall_normal

func force_wall_jump(custom_force: float = 0.0):
	if not is_on_wall():
		return
	
	var original_force = wall_jump_force
	if custom_force > 0:
		wall_jump_force = custom_force
	
	perform_wall_jump()
	wall_jump_force = original_force

func set_player(new_player: KinematicBody):
	player = new_player
	if wall_run_particles and wall_run_particles.get_parent():
		wall_run_particles.get_parent().remove_child(wall_run_particles)
	
	if player:
		player.add_child(wall_run_particles)

func toggle_wall_run(enable: bool):
	enabled = enable
	if not enabled and is_wall_running:
		end_wall_run()

func set_wall_run_parameters(params: Dictionary):
	for key in params:
		if key in self:
			set(key, params[key])