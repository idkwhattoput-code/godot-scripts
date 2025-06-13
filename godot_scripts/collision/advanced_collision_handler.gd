extends KinematicBody

# Advanced Collision Handler for Godot 3D
# Provides detailed collision detection and response for complex interactions
# Supports slopes, stairs, edges, and various surface types

# Movement settings
export var move_speed = 5.0
export var acceleration = 10.0
export var friction = 8.0
export var air_friction = 2.0
export var gravity = -20.0
export var jump_force = 10.0
export var max_fall_speed = -50.0

# Collision settings
export var max_slope_angle = 45.0
export var stair_height = 0.3
export var step_height_tolerance = 0.1
export var edge_detection_distance = 0.5
export var push_force = 5.0
export var wall_slide_friction = 0.7

# Surface detection
export var detect_surface_types = true
export var footstep_raycast_length = 1.5
export var surface_check_radius = 0.3

# State variables
var velocity = Vector3.ZERO
var snap_vector = Vector3.ZERO
var is_on_slope = false
var slope_normal = Vector3.UP
var current_surface_type = "default"
var was_on_floor = false
var time_since_on_floor = 0.0
var coyote_time = 0.15

# Collision info
var last_collision: KinematicCollision
var floor_collision: KinematicCollision
var wall_collisions = []
var ceiling_collision: KinematicCollision

# Edge detection
var is_near_edge = false
var edge_direction = Vector3.ZERO
var edge_distance = 0.0

# Components
onready var collision_shape = $CollisionShape
onready var ground_ray = $GroundRay if has_node("GroundRay") else null
onready var step_ray_front = $StepRayFront if has_node("StepRayFront") else null
onready var step_ray_back = $StepRayBack if has_node("StepRayBack") else null

# Signals
signal surface_changed(old_surface, new_surface)
signal landed(fall_height, impact_velocity)
signal edge_detected(direction, distance)
signal collision_with_body(body, collision_point, collision_normal)

func _ready():
	# Setup raycasts
	setup_raycasts()

func setup_raycasts():
	"""Setup raycast nodes for detection"""
	# Ground detection ray
	if not ground_ray:
		ground_ray = RayCast.new()
		add_child(ground_ray)
		ground_ray.enabled = true
		ground_ray.cast_to = Vector3(0, -footstep_raycast_length, 0)
		ground_ray.collision_mask = 1
	
	# Step detection rays
	if not step_ray_front:
		step_ray_front = RayCast.new()
		add_child(step_ray_front)
		step_ray_front.enabled = true
		step_ray_front.cast_to = Vector3(0, -stair_height, 0.5)
		step_ray_front.collision_mask = 1
	
	if not step_ray_back:
		step_ray_back = RayCast.new()
		add_child(step_ray_back)
		step_ray_back.enabled = true
		step_ray_back.cast_to = Vector3(0, -stair_height, -0.5)
		step_ray_back.collision_mask = 1

func _physics_process(delta):
	# Store previous floor state
	was_on_floor = is_on_floor()
	
	# Update timers
	if not is_on_floor():
		time_since_on_floor += delta
	else:
		time_since_on_floor = 0.0
	
	# Clear collision data
	wall_collisions.clear()
	
	# Apply gravity
	if not is_on_floor():
		velocity.y = max(velocity.y + gravity * delta, max_fall_speed)
	
	# Get input and apply movement
	var input_vector = get_movement_input()
	apply_movement(input_vector, delta)
	
	# Handle jumping
	if Input.is_action_just_pressed("jump") and can_jump():
		jump()
	
	# Perform movement with collision detection
	velocity = move_and_slide_with_snap(velocity, snap_vector, Vector3.UP, true, 4, deg2rad(max_slope_angle))
	
	# Post-movement collision analysis
	analyze_collisions()
	
	# Surface detection
	if detect_surface_types:
		detect_current_surface()
	
	# Edge detection
	detect_edges()
	
	# Handle landing
	if is_on_floor() and not was_on_floor:
		handle_landing()

func get_movement_input() -> Vector3:
	"""Get movement input from player"""
	var input = Vector3.ZERO
	input.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input.z = Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	return input.normalized()

func apply_movement(input_vector: Vector3, delta: float):
	"""Apply movement with acceleration and friction"""
	var desired_velocity = input_vector * move_speed
	
	# Different acceleration for air/ground
	var current_acceleration = acceleration if is_on_floor() else acceleration * 0.5
	var current_friction = friction if is_on_floor() else air_friction
	
	# Apply acceleration/friction
	if input_vector.length() > 0:
		velocity.x = lerp(velocity.x, desired_velocity.x, current_acceleration * delta)
		velocity.z = lerp(velocity.z, desired_velocity.z, current_acceleration * delta)
	else:
		velocity.x = lerp(velocity.x, 0, current_friction * delta)
		velocity.z = lerp(velocity.z, 0, current_friction * delta)
	
	# Handle slopes
	if is_on_floor() and is_on_slope:
		velocity = adjust_velocity_for_slope(velocity)

func can_jump() -> bool:
	"""Check if player can jump (includes coyote time)"""
	return is_on_floor() or time_since_on_floor < coyote_time

func jump():
	"""Perform jump"""
	velocity.y = jump_force
	snap_vector = Vector3.ZERO
	
	# Add slight forward momentum if moving
	var horizontal_vel = Vector3(velocity.x, 0, velocity.z)
	if horizontal_vel.length() > 0.1:
		velocity += horizontal_vel.normalized() * 0.5

func analyze_collisions():
	"""Analyze collision data from move_and_slide"""
	# Reset slope detection
	is_on_slope = false
	slope_normal = Vector3.UP
	
	# Analyze each collision
	for i in get_slide_count():
		var collision = get_slide_collision(i)
		var normal = collision.normal
		var collider = collision.collider
		
		# Emit collision signal
		emit_signal("collision_with_body", collider, collision.position, normal)
		
		# Categorize collision
		if normal.dot(Vector3.UP) > 0.7:  # Floor
			floor_collision = collision
			
			# Check for slope
			if normal.y < 0.99:
				is_on_slope = true
				slope_normal = normal
		elif normal.dot(Vector3.UP) < -0.7:  # Ceiling
			ceiling_collision = collision
		else:  # Wall
			wall_collisions.append(collision)
			
			# Wall slide
			if not is_on_floor() and velocity.y < 0:
				velocity.y *= wall_slide_friction
		
		# Handle pushable objects
		if collider is RigidBody:
			apply_push_force(collider, collision)

func adjust_velocity_for_slope(vel: Vector3) -> Vector3:
	"""Adjust velocity to follow slope"""
	if not is_on_slope:
		return vel
	
	# Project velocity onto slope
	var projected_vel = vel - slope_normal * vel.dot(slope_normal)
	
	# Prevent sliding down gentle slopes when stationary
	if vel.length() < 0.1:
		return Vector3.ZERO
	
	return projected_vel

func detect_current_surface():
	"""Detect the type of surface under the player"""
	if not ground_ray or not ground_ray.is_colliding():
		return
	
	var collider = ground_ray.get_collider()
	var new_surface_type = "default"
	
	# Check surface type by collision layer
	if collider.collision_layer & 2:  # Grass layer
		new_surface_type = "grass"
	elif collider.collision_layer & 4:  # Stone layer
		new_surface_type = "stone"
	elif collider.collision_layer & 8:  # Wood layer
		new_surface_type = "wood"
	elif collider.collision_layer & 16:  # Metal layer
		new_surface_type = "metal"
	elif collider.collision_layer & 32:  # Water layer
		new_surface_type = "water"
	
	# Check material or metadata
	if collider.has_meta("surface_type"):
		new_surface_type = collider.get_meta("surface_type")
	
	# Emit signal if surface changed
	if new_surface_type != current_surface_type:
		var old_surface = current_surface_type
		current_surface_type = new_surface_type
		emit_signal("surface_changed", old_surface, new_surface_type)

func detect_edges():
	"""Detect nearby edges for edge-grab or warnings"""
	is_near_edge = false
	
	if not is_on_floor():
		return
	
	# Cast rays in movement direction
	var move_dir = Vector3(velocity.x, 0, velocity.z).normalized()
	if move_dir.length() < 0.1:
		return
	
	# Check for edge
	var space_state = get_world().direct_space_state
	var from = global_transform.origin + move_dir * 0.5
	var to = from + Vector3(0, -edge_detection_distance - 0.5, 0)
	
	var result = space_state.intersect_ray(from, to, [self])
	
	if not result:
		# Edge detected
		is_near_edge = true
		edge_direction = move_dir
		edge_distance = edge_detection_distance
		emit_signal("edge_detected", edge_direction, edge_distance)

func handle_landing():
	"""Handle landing after being airborne"""
	var fall_height = abs(velocity.y)
	emit_signal("landed", fall_height, velocity.y)
	
	# Apply landing effects
	if fall_height > 15:
		# Hard landing - maybe damage or stun
		pass
	elif fall_height > 8:
		# Normal landing - play animation
		pass

func apply_push_force(body: RigidBody, collision: KinematicCollision):
	"""Apply push force to rigidbodies"""
	var push_direction = -collision.normal
	push_direction.y = 0
	push_direction = push_direction.normalized()
	
	var impulse = push_direction * push_force * get_physics_process_delta_time()
	body.apply_central_impulse(impulse)

func handle_stairs():
	"""Handle stair climbing"""
	if not is_on_floor() or velocity.length() < 0.1:
		return
	
	# Check for stairs in front
	if step_ray_front and step_ray_front.is_colliding():
		var hit_point = step_ray_front.get_collision_point()
		var step_height = global_transform.origin.y - hit_point.y
		
		if step_height < stair_height and step_height > step_height_tolerance:
			# Climb stair
			global_transform.origin.y += step_height
			velocity.y = 0

# Helper methods
func get_floor_angle() -> float:
	"""Get the angle of the floor"""
	if is_on_floor() and floor_collision:
		return rad2deg(acos(floor_collision.normal.dot(Vector3.UP)))
	return 0.0

func is_on_wall() -> bool:
	"""Check if touching a wall"""
	return wall_collisions.size() > 0

func get_wall_normal() -> Vector3:
	"""Get average wall normal"""
	if wall_collisions.empty():
		return Vector3.ZERO
	
	var avg_normal = Vector3.ZERO
	for collision in wall_collisions:
		avg_normal += collision.normal
	
	return avg_normal.normalized()

func is_pushing_against_wall() -> bool:
	"""Check if player is pushing against a wall"""
	if not is_on_wall():
		return false
	
	var wall_normal = get_wall_normal()
	var move_dir = Vector3(velocity.x, 0, velocity.z).normalized()
	
	return move_dir.dot(-wall_normal) > 0.7

func get_ground_velocity() -> Vector3:
	"""Get velocity of the ground (for moving platforms)"""
	if floor_collision and floor_collision.collider.has_method("get_velocity"):
		return floor_collision.collider.get_velocity()
	return Vector3.ZERO