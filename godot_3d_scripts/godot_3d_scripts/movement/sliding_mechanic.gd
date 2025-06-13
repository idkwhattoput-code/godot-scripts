extends Node

export var slide_speed = 15.0
export var slide_duration = 1.5
export var slide_cooldown = 0.5
export var slide_friction = 0.98
export var min_slide_speed = 3.0
export var slide_height_reduction = 0.5
export var slope_slide_boost = 1.5

signal slide_started()
signal slide_ended()
signal slide_jumped()

var is_sliding = false
var can_slide = true
var slide_timer = 0.0
var cooldown_timer = 0.0
var slide_direction = Vector3.ZERO
var current_slide_speed = 0.0
var original_collision_height = 2.0

onready var collision_shape = get_parent().get_node("CollisionShape")
onready var slide_particles = $SlideParticles
onready var slide_sound = $SlideSound

func _ready():
	if collision_shape and collision_shape.shape is CapsuleShape:
		original_collision_height = collision_shape.shape.height

func _physics_process(delta):
	if is_sliding:
		slide_timer -= delta
		if slide_timer <= 0 or current_slide_speed < min_slide_speed:
			end_slide()
		else:
			_update_slide_velocity()
	
	if cooldown_timer > 0:
		cooldown_timer -= delta
		if cooldown_timer <= 0:
			can_slide = true

func start_slide(player_velocity, player_direction):
	if not can_slide or is_sliding:
		return false
	
	if not get_parent().is_on_floor():
		return false
	
	if player_velocity.length() < min_slide_speed:
		return false
	
	is_sliding = true
	can_slide = false
	slide_timer = slide_duration
	
	slide_direction = player_direction.normalized()
	current_slide_speed = max(player_velocity.length(), slide_speed)
	
	_adjust_collision_shape(true)
	
	emit_signal("slide_started")
	
	if slide_particles:
		slide_particles.emitting = true
	
	if slide_sound:
		slide_sound.play()
	
	return true

func end_slide():
	if not is_sliding:
		return
	
	is_sliding = false
	slide_timer = 0.0
	cooldown_timer = slide_cooldown
	
	_adjust_collision_shape(false)
	
	emit_signal("slide_ended")
	
	if slide_particles:
		slide_particles.emitting = false
	
	if slide_sound:
		slide_sound.stop()

func _adjust_collision_shape(sliding):
	if not collision_shape or not collision_shape.shape is CapsuleShape:
		return
	
	if sliding:
		collision_shape.shape.height = original_collision_height * slide_height_reduction
		collision_shape.translation.y = -(original_collision_height - collision_shape.shape.height) / 2
	else:
		if not _check_space_to_stand():
			return
		
		collision_shape.shape.height = original_collision_height
		collision_shape.translation.y = 0

func _check_space_to_stand():
	var space_state = get_parent().get_world().direct_space_state
	var player_pos = get_parent().global_transform.origin
	
	var test_height = original_collision_height - collision_shape.shape.height
	var result = space_state.intersect_ray(
		player_pos,
		player_pos + Vector3(0, test_height, 0),
		[get_parent()]
	)
	
	return result.empty()

func _update_slide_velocity():
	current_slide_speed *= slide_friction
	
	var floor_normal = get_parent().get_floor_normal()
	var slope_factor = floor_normal.dot(Vector3.UP)
	
	if slope_factor < 0.99:
		var slope_direction = Vector3.UP.cross(floor_normal.cross(Vector3.UP)).normalized()
		if slope_direction.y < 0:
			current_slide_speed *= slope_slide_boost

func get_slide_velocity():
	if not is_sliding:
		return Vector3.ZERO
	
	var velocity = slide_direction * current_slide_speed
	
	var floor_normal = get_parent().get_floor_normal()
	if floor_normal != Vector3.UP:
		var right = slide_direction.cross(Vector3.UP).normalized()
		var slide_plane_normal = right.cross(floor_normal).normalized()
		velocity = slide_plane_normal * current_slide_speed
	
	return velocity

func slide_jump():
	if not is_sliding:
		return false
	
	end_slide()
	emit_signal("slide_jumped")
	
	return true

func can_slide_jump():
	return is_sliding and slide_timer > 0.1

func get_slide_progress():
	if not is_sliding:
		return 0.0
	return slide_timer / slide_duration

func force_end_slide():
	if is_sliding:
		end_slide()

func is_slide_available():
	return can_slide and not is_sliding and get_parent().is_on_floor()

func get_height_multiplier():
	if is_sliding:
		return slide_height_reduction
	return 1.0

func reset():
	is_sliding = false
	can_slide = true
	slide_timer = 0.0
	cooldown_timer = 0.0
	slide_direction = Vector3.ZERO
	current_slide_speed = 0.0
	
	_adjust_collision_shape(false)
	
	if slide_particles:
		slide_particles.emitting = false
	
	if slide_sound:
		slide_sound.stop()