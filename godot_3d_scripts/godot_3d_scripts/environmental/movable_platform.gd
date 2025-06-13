extends AnimatableBody3D

class_name MovablePlatform

@export_group("Movement Settings")
@export var movement_points: Array[Vector3] = []
@export var movement_speed := 2.0
@export var rotation_speed := 1.0
@export var pause_duration := 1.0
@export var movement_mode := MovementMode.LOOP
@export var easing_type := Tween.EaseType.EASE_IN_OUT
@export var transition_type := Tween.TransitionType.TRANS_SINE

@export_group("Activation")
@export var start_on_ready := true
@export var requires_activation := false
@export var activation_delay := 0.0
@export var deactivation_returns_to_start := true

@export_group("Physics")
@export var push_force := 10.0
@export var carry_players := true
@export var sync_to_physics := true

@export_group("Safety")
@export var crush_damage := 20.0
@export var stop_on_obstacle := false
@export var obstacle_detection_distance := 0.5

@export_group("Visual Effects")
@export var glow_when_moving := true
@export var glow_color := Color(0.5, 0.8, 1.0)
@export var particle_trail: PackedScene
@export var movement_sound: AudioStream
@export var arrival_sound: AudioStream

enum MovementMode {
	LOOP,
	PING_PONG,
	ONE_SHOT,
	RANDOM
}

var current_point_index := 0
var movement_direction := 1
var is_moving := false
var is_paused := false
var carried_bodies := {}
var movement_tween: Tween
var pause_timer: Timer
var activation_timer: Timer
var audio_player: AudioStreamPlayer3D
var particle_instance: Node3D
var original_material: Material
var glow_material: Material
var start_position: Vector3
var obstacles_detected := false

signal platform_started()
signal platform_stopped()
signal reached_point(index: int)
signal movement_completed()
signal obstacle_detected(body: Node3D)
signal body_crushed(body: Node3D)

func _ready():
	start_position = global_position
	
	if movement_points.is_empty():
		movement_points.append(Vector3.ZERO)
		movement_points.append(Vector3(0, 2, 0))
	
	setup_components()
	setup_materials()
	
	if start_on_ready and not requires_activation:
		start_platform()

func setup_components():
	pause_timer = Timer.new()
	pause_timer.one_shot = true
	pause_timer.timeout.connect(_on_pause_timeout)
	add_child(pause_timer)
	
	if requires_activation and activation_delay > 0:
		activation_timer = Timer.new()
		activation_timer.one_shot = true
		activation_timer.timeout.connect(_on_activation_timeout)
		add_child(activation_timer)
	
	audio_player = AudioStreamPlayer3D.new()
	audio_player.bus = "SFX"
	add_child(audio_player)
	
	var area = Area3D.new()
	area.monitoring = true
	add_child(area)
	
	var collision = get_node_or_null("CollisionShape3D")
	if collision:
		var area_collision = collision.duplicate()
		area.add_child(area_collision)
	
	area.body_entered.connect(_on_body_entered_platform)
	area.body_exited.connect(_on_body_exited_platform)

func setup_materials():
	var mesh_instance = get_node_or_null("MeshInstance3D")
	if mesh_instance:
		original_material = mesh_instance.get_surface_override_material(0)
		
		glow_material = StandardMaterial3D.new()
		if original_material:
			glow_material = original_material.duplicate()
		glow_material.emission_enabled = true
		glow_material.emission = glow_color
		glow_material.emission_energy = 0.5

func start_platform():
	if is_moving:
		return
	
	is_moving = true
	emit_signal("platform_started")
	
	if activation_delay > 0 and activation_timer:
		activation_timer.wait_time = activation_delay
		activation_timer.start()
	else:
		begin_movement()

func stop_platform():
	if not is_moving:
		return
	
	is_moving = false
	is_paused = false
	
	if movement_tween:
		movement_tween.kill()
	
	if pause_timer:
		pause_timer.stop()
	
	stop_effects()
	emit_signal("platform_stopped")
	
	if deactivation_returns_to_start:
		return_to_start()

func begin_movement():
	if glow_when_moving:
		apply_glow(true)
	
	if particle_trail:
		spawn_particles()
	
	if movement_sound and audio_player:
		audio_player.stream = movement_sound
		audio_player.play()
		audio_player.loop = true
	
	move_to_next_point()

func move_to_next_point():
	if not is_moving or movement_points.is_empty():
		return
	
	if stop_on_obstacle and check_for_obstacles():
		handle_obstacle_stop()
		return
	
	var target_position = get_world_position(movement_points[current_point_index])
	var distance = global_position.distance_to(target_position)
	var duration = distance / movement_speed
	
	if movement_tween:
		movement_tween.kill()
	
	movement_tween = create_tween()
	movement_tween.set_trans(transition_type)
	movement_tween.set_ease(easing_type)
	
	movement_tween.tween_property(self, "global_position", target_position, duration)
	movement_tween.finished.connect(_on_reached_point)

func get_world_position(local_point: Vector3) -> Vector3:
	return start_position + local_point

func _on_reached_point():
	emit_signal("reached_point", current_point_index)
	
	if arrival_sound and audio_player:
		var arrival_player = AudioStreamPlayer3D.new()
		arrival_player.stream = arrival_sound
		arrival_player.bus = "SFX"
		add_child(arrival_player)
		arrival_player.play()
		arrival_player.finished.connect(arrival_player.queue_free)
	
	update_point_index()
	
	if should_continue_movement():
		if pause_duration > 0:
			is_paused = true
			pause_timer.wait_time = pause_duration
			pause_timer.start()
		else:
			move_to_next_point()
	else:
		stop_platform()
		emit_signal("movement_completed")

func update_point_index():
	match movement_mode:
		MovementMode.LOOP:
			current_point_index = (current_point_index + 1) % movement_points.size()
		
		MovementMode.PING_PONG:
			current_point_index += movement_direction
			if current_point_index >= movement_points.size() - 1:
				current_point_index = movement_points.size() - 1
				movement_direction = -1
			elif current_point_index <= 0:
				current_point_index = 0
				movement_direction = 1
		
		MovementMode.ONE_SHOT:
			current_point_index += 1
		
		MovementMode.RANDOM:
			var prev_index = current_point_index
			while current_point_index == prev_index and movement_points.size() > 1:
				current_point_index = randi() % movement_points.size()

func should_continue_movement() -> bool:
	match movement_mode:
		MovementMode.ONE_SHOT:
			return current_point_index < movement_points.size()
		_:
			return true

func check_for_obstacles() -> bool:
	var space_state = get_world_3d().direct_space_state
	var next_position = get_world_position(movement_points[current_point_index])
	var direction = (next_position - global_position).normalized()
	
	var query = PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + direction * obstacle_detection_distance
	)
	query.exclude = [self]
	query.collision_mask = 0xFFFFFFFF
	
	var result = space_state.intersect_ray(query)
	return result.has("collider")

func handle_obstacle_stop():
	obstacles_detected = true
	stop_platform()
	
	var retry_timer = Timer.new()
	retry_timer.wait_time = 1.0
	retry_timer.one_shot = true
	retry_timer.timeout.connect(_on_obstacle_retry)
	add_child(retry_timer)
	retry_timer.start()

func _on_obstacle_retry():
	if not check_for_obstacles():
		obstacles_detected = false
		start_platform()

func _on_body_entered_platform(body: Node3D):
	if carry_players and body.has_method("is_player"):
		carried_bodies[body] = body.global_position - global_position

func _on_body_exited_platform(body: Node3D):
	carried_bodies.erase(body)

func _physics_process(delta):
	if not is_moving or is_paused:
		return
	
	for body in carried_bodies:
		if is_instance_valid(body):
			var offset = carried_bodies[body]
			body.global_position = global_position + offset

func apply_glow(enable: bool):
	var mesh_instance = get_node_or_null("MeshInstance3D")
	if not mesh_instance:
		return
	
	if enable and glow_material:
		mesh_instance.set_surface_override_material(0, glow_material)
	else:
		mesh_instance.set_surface_override_material(0, original_material)

func spawn_particles():
	if not particle_trail:
		return
	
	particle_instance = particle_trail.instantiate()
	add_child(particle_instance)
	
	if particle_instance.has_method("set_emitting"):
		particle_instance.set_emitting(true)

func stop_effects():
	apply_glow(false)
	
	if particle_instance:
		if particle_instance.has_method("set_emitting"):
			particle_instance.set_emitting(false)
		particle_instance.queue_free()
		particle_instance = null
	
	if audio_player and audio_player.playing:
		audio_player.stop()

func return_to_start():
	var return_tween = create_tween()
	return_tween.tween_property(self, "global_position", start_position, 2.0)
	return_tween.finished.connect(func(): current_point_index = 0)

func _on_pause_timeout():
	is_paused = false
	move_to_next_point()

func _on_activation_timeout():
	begin_movement()

func activate():
	if requires_activation:
		start_platform()

func deactivate():
	stop_platform()

func toggle():
	if is_moving:
		stop_platform()
	else:
		start_platform()

func set_speed(new_speed: float):
	movement_speed = new_speed

func add_waypoint(point: Vector3):
	movement_points.append(point)

func clear_waypoints():
	movement_points.clear()
	current_point_index = 0

func teleport_to_point(index: int):
	if index >= 0 and index < movement_points.size():
		global_position = get_world_position(movement_points[index])
		current_point_index = index