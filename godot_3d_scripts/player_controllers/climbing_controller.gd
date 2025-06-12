extends KinematicBody

# Movement settings
export var walk_speed = 5.0
export var climb_speed = 3.0
export var swim_speed = 4.0
export var glide_speed = 15.0
export var glide_fall_speed = 5.0

# Climbing settings
export var climb_reach = 2.0
export var grip_strength = 100.0
export var stamina_max = 100.0
export var stamina_drain_rate = 10.0
export var stamina_regen_rate = 15.0
export var ledge_climb_stamina = 20.0
export var overhang_stamina_multiplier = 2.0

# Physics
export var gravity = 20.0
export var jump_force = 8.0
export var air_friction = 0.1

# Advanced climbing
export var dynamic_reach = true
export var momentum_climbing = true
export var chalk_effect_duration = 30.0
export var max_climb_angle = 80.0  # degrees

# State
enum ClimbingState {
	GROUND,
	CLIMBING,
	HANGING,
	SWINGING,
	SWIMMING,
	GLIDING,
	FALLING
}

var state = ClimbingState.GROUND
var velocity = Vector3.ZERO
var is_grounded = false

# Climbing variables
var current_stamina = 100.0
var is_climbing = false
var climb_surface_normal = Vector3.ZERO
var grip_points = []
var current_grip_strength = 1.0
var chalk_timer = 0.0
var climb_momentum = Vector3.ZERO

# Hand positions
var left_hand_pos = Vector3.ZERO
var right_hand_pos = Vector3.ZERO
var left_hand_attached = false
var right_hand_attached = false
var last_moved_hand = "left"

# Gliding
var glider_deployed = false
var glide_angle = 0.0

# Swimming  
var is_underwater = false
var oxygen = 100.0
var buoyancy = 5.0

# Input
var movement_input = Vector2.ZERO
var look_input = Vector2.ZERO
var mouse_sensitivity = 0.2

# Components
onready var camera = $CameraMount/Camera
onready var camera_mount = $CameraMount
onready var left_hand_target = $LeftHandTarget
onready var right_hand_target = $RightHandTarget
onready var climb_cast = $ClimbCast
onready var ground_cast = $GroundCast
onready var stamina_bar = $UI/StaminaBar

# Climbing surface detection
onready var surface_detectors = [
	$SurfaceDetectors/Front,
	$SurfaceDetectors/FrontLeft,
	$SurfaceDetectors/FrontRight,
	$SurfaceDetectors/Left,
	$SurfaceDetectors/Right
]

signal started_climbing()
signal stopped_climbing()
signal stamina_depleted()
signal grabbed_ledge(position)
signal lost_grip()

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_setup_detectors()
	current_stamina = stamina_max

func _setup_detectors():
	for detector in surface_detectors:
		detector.enabled = true
		detector.cast_to = Vector3.FORWARD * climb_reach

func _input(event):
	if event is InputEventMouseMotion:
		look_input = event.relative * mouse_sensitivity
		
		# Rotate camera
		rotate_y(deg2rad(-look_input.x))
		camera_mount.rotate_x(deg2rad(-look_input.y))
		camera_mount.rotation.x = clamp(camera_mount.rotation.x, deg2rad(-90), deg2rad(90))

func _physics_process(delta):
	_handle_input()
	_update_state_machine(delta)
	_apply_physics(delta)
	_update_stamina(delta)
	_update_ui()
	
	velocity = move_and_slide(velocity, Vector3.UP)
	is_grounded = is_on_floor()

func _handle_input():
	movement_input = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	)
	
	# Climbing input
	if Input.is_action_pressed("climb") and _can_climb():
		if state != ClimbingState.CLIMBING:
			_start_climbing()
	elif state == ClimbingState.CLIMBING:
		_stop_climbing()
	
	# Jump/Let go
	if Input.is_action_just_pressed("jump"):
		match state:
			ClimbingState.GROUND:
				if is_grounded:
					velocity.y = jump_force
			ClimbingState.CLIMBING:
				_jump_off_wall()
			ClimbingState.HANGING:
				_release_ledge()
	
	# Glider
	if Input.is_action_just_pressed("deploy_glider") and state == ClimbingState.FALLING:
		_deploy_glider()
	elif Input.is_action_just_released("deploy_glider"):
		_retract_glider()
	
	# Chalk
	if Input.is_action_just_pressed("use_chalk") and state == ClimbingState.CLIMBING:
		_use_chalk()

func _update_state_machine(delta):
	match state:
		ClimbingState.GROUND:
			_update_ground_movement(delta)
		ClimbingState.CLIMBING:
			_update_climbing(delta)
		ClimbingState.HANGING:
			_update_hanging(delta)
		ClimbingState.SWIMMING:
			_update_swimming(delta)
		ClimbingState.GLIDING:
			_update_gliding(delta)
		ClimbingState.FALLING:
			_update_falling(delta)

func _apply_physics(delta):
	if state != ClimbingState.CLIMBING and state != ClimbingState.HANGING:
		# Apply gravity
		if state == ClimbingState.GLIDING:
			velocity.y = max(velocity.y - gravity * 0.3 * delta, -glide_fall_speed)
		elif state == ClimbingState.SWIMMING:
			velocity.y = max(velocity.y - (gravity - buoyancy) * delta, -swim_speed)
		else:
			velocity.y -= gravity * delta

func _update_ground_movement(delta):
	var direction = transform.basis * Vector3(movement_input.x, 0, -movement_input.y)
	direction = direction.normalized()
	
	if direction.length() > 0:
		velocity.x = lerp(velocity.x, direction.x * walk_speed, 10 * delta)
		velocity.z = lerp(velocity.z, direction.z * walk_speed, 10 * delta)
	else:
		velocity.x = lerp(velocity.x, 0, 10 * delta)
		velocity.z = lerp(velocity.z, 0, 10 * delta)
	
	# Check for water
	if _check_water():
		state = ClimbingState.SWIMMING
	elif not is_grounded and velocity.y < -5:
		state = ClimbingState.FALLING

func _can_climb() -> bool:
	if current_stamina <= 0:
		return false
	
	# Check all surface detectors
	for detector in surface_detectors:
		if detector.is_colliding():
			var normal = detector.get_collision_normal()
			var angle = rad2deg(normal.angle_to(Vector3.UP))
			
			if angle >= 45 and angle <= max_climb_angle + 45:
				return true
	
	return false

func _start_climbing():
	state = ClimbingState.CLIMBING
	emit_signal("started_climbing")
	
	# Find initial grip points
	_find_grip_points()
	
	# Attach hands to nearest points
	if grip_points.size() > 0:
		left_hand_pos = grip_points[0]
		left_hand_attached = true
	if grip_points.size() > 1:
		right_hand_pos = grip_points[1]
		right_hand_attached = true

func _stop_climbing():
	state = ClimbingState.GROUND
	left_hand_attached = false
	right_hand_attached = false
	emit_signal("stopped_climbing")

func _update_climbing(delta):
	# Check if still on climbable surface
	if not _can_climb():
		_stop_climbing()
		return
	
	# Update grip strength based on angle
	var wall_angle = rad2deg(climb_surface_normal.angle_to(Vector3.UP))
	var is_overhang = wall_angle > 90
	
	# Stamina drain
	var stamina_drain = stamina_drain_rate * delta
	if is_overhang:
		stamina_drain *= overhang_stamina_multiplier
	
	# Chalk reduces stamina drain
	if chalk_timer > 0:
		stamina_drain *= 0.7
		chalk_timer -= delta
	
	current_stamina -= stamina_drain
	
	if current_stamina <= 0:
		_lose_grip()
		return
	
	# Climbing movement
	var climb_dir = Vector3.ZERO
	
	# Horizontal movement along wall
	var right = climb_surface_normal.cross(Vector3.UP).normalized()
	var up = right.cross(climb_surface_normal).normalized()
	
	climb_dir += right * movement_input.x
	climb_dir += up * -movement_input.y
	
	# Apply climbing movement
	if climb_dir.length() > 0:
		climb_dir = climb_dir.normalized()
		
		# Move hands alternately
		if _should_move_hand():
			_move_hand(climb_dir)
		
		# Apply movement with momentum
		if momentum_climbing:
			climb_momentum = lerp(climb_momentum, climb_dir * climb_speed, 5 * delta)
			velocity = climb_momentum
		else:
			velocity = climb_dir * climb_speed
		
		# Stick to wall
		velocity += -climb_surface_normal * 2
	else:
		velocity = Vector3.ZERO
		climb_momentum = Vector3.ZERO
	
	# Check for ledges
	if _check_ledge():
		state = ClimbingState.HANGING

func _find_grip_points():
	grip_points.clear()
	
	# Cast rays in grid pattern to find grip points
	for detector in surface_detectors:
		if detector.is_colliding():
			var point = detector.get_collision_point()
			var normal = detector.get_collision_normal()
			
			# Check grip quality based on surface angle
			var grip_quality = _calculate_grip_quality(point, normal)
			
			if grip_quality > 0.3:
				grip_points.append(point)
	
	# Sort by distance to hands
	grip_points.sort_custom(self, "_sort_by_distance_to_hands")

func _calculate_grip_quality(point: Vector3, normal: Vector3) -> float:
	# Better grips on less steep surfaces
	var angle_quality = normal.dot(Vector3.UP)
	
	# Distance from current position
	var distance = (point - global_transform.origin).length()
	var distance_quality = 1.0 - (distance / climb_reach)
	
	return (angle_quality + distance_quality) / 2.0

func _sort_by_distance_to_hands(a: Vector3, b: Vector3) -> bool:
	var dist_a = (a - global_transform.origin).length()
	var dist_b = (b - global_transform.origin).length()
	return dist_a < dist_b

func _should_move_hand() -> bool:
	# Alternating hand movement system
	var move_threshold = 0.5
	
	if last_moved_hand == "left":
		var right_distance = (right_hand_pos - global_transform.origin).length()
		return right_distance > move_threshold
	else:
		var left_distance = (left_hand_pos - global_transform.origin).length()
		return left_distance > move_threshold

func _move_hand(direction: Vector3):
	_find_grip_points()
	
	if grip_points.empty():
		return
	
	if last_moved_hand == "left":
		# Move right hand
		for point in grip_points:
			if (point - left_hand_pos).length() > 0.3:  # Don't grab too close to other hand
				right_hand_pos = point
				right_hand_attached = true
				last_moved_hand = "right"
				break
	else:
		# Move left hand
		for point in grip_points:
			if (point - right_hand_pos).length() > 0.3:
				left_hand_pos = point
				left_hand_attached = true
				last_moved_hand = "left"
				break

func _update_hanging(delta):
	# Hanging from ledge
	current_stamina -= stamina_drain_rate * 0.5 * delta
	
	if current_stamina <= 0:
		_release_ledge()
		return
	
	# Shimmy along ledge
	var shimmy_dir = transform.basis.x * movement_input.x
	velocity = shimmy_dir * climb_speed * 0.5
	
	# Climb up
	if Input.is_action_pressed("move_forward") and current_stamina >= ledge_climb_stamina:
		_climb_up_ledge()

func _climb_up_ledge():
	current_stamina -= ledge_climb_stamina
	velocity.y = jump_force
	global_transform.origin.y += 1.0
	state = ClimbingState.GROUND

func _check_ledge() -> bool:
	# Simple ledge detection
	var space_state = get_world().direct_space_state
	var from = global_transform.origin + Vector3(0, 1, 0)
	var to = from + transform.basis.z * -1
	
	var result = space_state.intersect_ray(from, to, [self])
	
	if result:
		# Check if horizontal surface
		if result.normal.y > 0.7:
			emit_signal("grabbed_ledge", result.position)
			return true
	
	return false

func _jump_off_wall():
	var jump_direction = climb_surface_normal + Vector3.UP * 0.5
	velocity = jump_direction.normalized() * jump_force
	_stop_climbing()
	state = ClimbingState.FALLING

func _lose_grip():
	emit_signal("lost_grip")
	_stop_climbing()
	state = ClimbingState.FALLING
	
	# Add some push away from wall
	velocity = climb_surface_normal * 3

func _release_ledge():
	state = ClimbingState.FALLING

func _update_swimming(delta):
	# Swimming movement
	var swim_dir = transform.basis * Vector3(movement_input.x, 0, -movement_input.y)
	swim_dir = swim_dir.normalized()
	
	# Can swim up/down with jump/crouch
	if Input.is_action_pressed("jump"):
		swim_dir.y = 1
	elif Input.is_action_pressed("crouch"):
		swim_dir.y = -1
	
	velocity = swim_dir * swim_speed
	
	# Oxygen
	if is_underwater:
		oxygen -= 10 * delta
		if oxygen <= 0:
			# Take damage
			pass
	else:
		oxygen = min(oxygen + 30 * delta, 100)
	
	# Check if still in water
	if not _check_water():
		state = ClimbingState.GROUND

func _update_gliding(delta):
	if not glider_deployed:
		state = ClimbingState.FALLING
		return
	
	# Glider physics
	var forward = -transform.basis.z
	var glide_velocity = forward * glide_speed
	
	# Allow some steering
	glide_angle = movement_input.x * 30
	rotate_y(deg2rad(glide_angle * delta))
	
	velocity.x = glide_velocity.x
	velocity.z = glide_velocity.z
	
	# Check landing
	if is_grounded:
		_retract_glider()
		state = ClimbingState.GROUND

func _update_falling(delta):
	# Air control
	var air_dir = transform.basis * Vector3(movement_input.x, 0, -movement_input.y)
	air_dir = air_dir.normalized()
	
	velocity.x = lerp(velocity.x, air_dir.x * walk_speed * 0.3, air_friction * delta)
	velocity.z = lerp(velocity.z, air_dir.z * walk_speed * 0.3, air_friction * delta)
	
	# Check for surfaces to grab
	if Input.is_action_pressed("climb") and _can_climb():
		_start_climbing()
	
	# Check landing
	if is_grounded:
		state = ClimbingState.GROUND

func _deploy_glider():
	glider_deployed = true
	state = ClimbingState.GLIDING

func _retract_glider():
	glider_deployed = false

func _use_chalk():
	if current_stamina < stamina_max:
		chalk_timer = chalk_effect_duration
		current_stamina = min(current_stamina + 20, stamina_max)

func _check_water() -> bool:
	# Simple water detection - implement based on your water system
	return false

func _update_stamina(delta):
	if state != ClimbingState.CLIMBING and state != ClimbingState.HANGING:
		current_stamina = min(current_stamina + stamina_regen_rate * delta, stamina_max)

func _update_ui():
	if stamina_bar:
		stamina_bar.value = current_stamina / stamina_max * 100