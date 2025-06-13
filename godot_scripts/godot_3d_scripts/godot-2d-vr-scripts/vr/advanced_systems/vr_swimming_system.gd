extends Node3D

class_name VRSwimmingSystem

@export_group("Swimming Physics")
@export var water_drag := 0.8
@export var swim_force_multiplier := 5.0
@export var buoyancy_force := 9.8
@export var surface_resistance := 0.3
@export var underwater_resistance := 0.6

@export_group("Hand Swimming")
@export var stroke_power := 10.0
@export var stroke_detection_threshold := 0.5
@export var stroke_cooldown := 0.3
@export var hand_drag_multiplier := 2.0

@export_group("Breathing System")
@export var max_breath := 100.0
@export var breath_consumption_rate := 5.0
@export var breath_recovery_rate := 20.0
@export var breath_hold_bonus := 1.5
@export var panic_threshold := 20.0

@export_group("Water Detection")
@export var water_surface_level := 0.0
@export var head_offset := Vector3(0, 1.7, 0)
@export var body_offset := Vector3(0, 1.0, 0)
@export var water_check_frequency := 0.1

@export_group("Visual Effects")
@export var underwater_overlay_scene: PackedScene
@export var splash_effect_scene: PackedScene
@export var bubble_effect_scene: PackedScene
@export var swimming_trail_scene: PackedScene

@export_group("Audio")
@export var underwater_ambient: AudioStream
@export var splash_sounds: Array[AudioStream] = []
@export var breathing_sounds: Array[AudioStream] = []
@export var drowning_sound: AudioStream

@export_group("Hand Controllers")
@export var left_hand_path: NodePath
@export var right_hand_path: NodePath

var left_hand: XRController3D
var right_hand: XRController3D
var player_body: CharacterBody3D
var camera_head: Node3D

var is_underwater := false
var is_at_surface := false
var water_depth := 0.0
var current_breath := 100.0
var is_holding_breath := false
var is_drowning := false

var left_hand_velocity := Vector3.ZERO
var right_hand_velocity := Vector3.ZERO
var left_hand_prev_pos := Vector3.ZERO
var right_hand_prev_pos := Vector3.ZERO
var left_stroke_cooldown := 0.0
var right_stroke_cooldown := 0.0

var underwater_overlay: Control
var audio_player: AudioStreamPlayer3D
var breathing_player: AudioStreamPlayer
var splash_instances := []
var bubble_instances := []

var water_check_timer := 0.0
var breath_panic_timer := 0.0

signal entered_water()
signal exited_water()
signal went_underwater()
signal surfaced()
signal breath_changed(current: float, maximum: float)
signal started_drowning()
signal stroke_performed(hand: String, power: float)

func _ready():
	setup_hand_controllers()
	setup_audio()
	setup_player_references()
	
	current_breath = max_breath
	
	set_physics_process(true)
	set_process(true)

func setup_hand_controllers():
	if left_hand_path:
		left_hand = get_node(left_hand_path)
	if right_hand_path:
		right_hand = get_node(right_hand_path)
	
	if left_hand:
		left_hand_prev_pos = left_hand.global_position
	if right_hand:
		right_hand_prev_pos = right_hand.global_position

func setup_audio():
	audio_player = AudioStreamPlayer3D.new()
	add_child(audio_player)
	audio_player.bus = "SFX"
	
	breathing_player = AudioStreamPlayer.new()
	add_child(breathing_player)
	breathing_player.bus = "SFX"

func setup_player_references():
	player_body = get_tree().get_first_node_in_group("player_body")
	camera_head = get_tree().get_first_node_in_group("xr_camera")
	
	if not camera_head:
		camera_head = get_node_or_null("../XRCamera3D")

func _physics_process(delta):
	update_hand_velocities(delta)
	check_water_status(delta)
	
	if is_in_water():
		apply_swimming_physics(delta)
		update_breath_system(delta)
		update_stroke_detection(delta)
		apply_hand_swimming_forces()

func _process(delta):
	update_visual_effects(delta)
	update_audio_effects()

func update_hand_velocities(delta):
	if left_hand:
		left_hand_velocity = (left_hand.global_position - left_hand_prev_pos) / delta
		left_hand_prev_pos = left_hand.global_position
	
	if right_hand:
		right_hand_velocity = (right_hand.global_position - right_hand_prev_pos) / delta
		right_hand_prev_pos = right_hand.global_position

func check_water_status(delta):
	water_check_timer += delta
	if water_check_timer < water_check_frequency:
		return
	
	water_check_timer = 0.0
	
	var head_position = get_head_position()
	var body_position = get_body_position()
	
	var was_underwater = is_underwater
	var was_at_surface = is_at_surface
	
	is_underwater = head_position.y < water_surface_level
	is_at_surface = not is_underwater and body_position.y < water_surface_level
	water_depth = water_surface_level - body_position.y
	
	if is_underwater and not was_underwater:
		on_went_underwater()
	elif not is_underwater and was_underwater:
		on_surfaced()
	elif is_at_surface and not was_at_surface:
		on_entered_water()
	elif not is_at_surface and not is_underwater and was_at_surface:
		on_exited_water()

func get_head_position() -> Vector3:
	if camera_head:
		return camera_head.global_position
	return global_position + head_offset

func get_body_position() -> Vector3:
	return global_position + body_offset

func is_in_water() -> bool:
	return is_underwater or is_at_surface

func on_entered_water():
	emit_signal("entered_water")
	create_splash_effect()

func on_exited_water():
	emit_signal("exited_water")
	cleanup_water_effects()

func on_went_underwater():
	emit_signal("went_underwater")
	create_underwater_overlay()
	start_breath_holding()
	play_underwater_audio()

func on_surfaced():
	emit_signal("surfaced")
	remove_underwater_overlay()
	stop_breath_holding()
	stop_underwater_audio()
	create_splash_effect()

func apply_swimming_physics(delta):
	if not player_body:
		return
	
	var resistance = underwater_resistance if is_underwater else surface_resistance
	
	player_body.velocity *= (1.0 - resistance * delta)
	
	if water_depth > 0:
		var buoyancy = Vector3.UP * buoyancy_force * min(water_depth, 1.0) * delta
		player_body.velocity += buoyancy

func update_breath_system(delta):
	if is_underwater:
		if is_holding_breath:
			current_breath -= breath_consumption_rate * breath_hold_bonus * delta
		else:
			current_breath -= breath_consumption_rate * delta
		
		if current_breath <= 0:
			current_breath = 0
			if not is_drowning:
				start_drowning()
		elif current_breath <= panic_threshold:
			breath_panic_timer += delta
			if breath_panic_timer > 1.0:
				trigger_panic_breathing()
				breath_panic_timer = 0.0
	else:
		if current_breath < max_breath:
			current_breath += breath_recovery_rate * delta
			current_breath = min(current_breath, max_breath)
		
		if is_drowning:
			stop_drowning()
		
		breath_panic_timer = 0.0
	
	emit_signal("breath_changed", current_breath, max_breath)

func update_stroke_detection(delta):
	if left_stroke_cooldown > 0:
		left_stroke_cooldown -= delta
	if right_stroke_cooldown > 0:
		right_stroke_cooldown -= delta

func apply_hand_swimming_forces():
	if not player_body:
		return
	
	detect_and_apply_stroke(left_hand, left_hand_velocity, "left")
	detect_and_apply_stroke(right_hand, right_hand_velocity, "right")

func detect_and_apply_stroke(hand: XRController3D, velocity: Vector3, hand_name: String):
	if not hand:
		return
	
	var cooldown = left_stroke_cooldown if hand_name == "left" else right_stroke_cooldown
	if cooldown > 0:
		return
	
	var speed = velocity.length()
	if speed < stroke_detection_threshold:
		return
	
	var stroke_direction = velocity.normalized()
	var is_backward_stroke = stroke_direction.dot(-player_body.global_transform.basis.z) > 0.5
	
	if is_backward_stroke:
		perform_stroke(stroke_direction, speed, hand_name)

func perform_stroke(direction: Vector3, speed: float, hand_name: String):
	var stroke_force = direction * speed * stroke_power * swim_force_multiplier
	
	if player_body:
		player_body.velocity += stroke_force * get_physics_process_delta_time()
	
	var cooldown_time = stroke_cooldown
	if hand_name == "left":
		left_stroke_cooldown = cooldown_time
	else:
		right_stroke_cooldown = cooldown_time
	
	emit_signal("stroke_performed", hand_name, speed)
	
	create_swimming_trail(hand_name)
	play_stroke_sound()

func start_breath_holding():
	is_holding_breath = true

func stop_breath_holding():
	is_holding_breath = false

func start_drowning():
	is_drowning = true
	emit_signal("started_drowning")
	
	if drowning_sound and breathing_player:
		breathing_player.stream = drowning_sound
		breathing_player.play()

func stop_drowning():
	is_drowning = false
	
	if breathing_player.playing:
		breathing_player.stop()

func trigger_panic_breathing():
	if breathing_sounds.size() > 0 and breathing_player and not breathing_player.playing:
		var panic_sound = breathing_sounds[randi() % breathing_sounds.size()]
		breathing_player.stream = panic_sound
		breathing_player.pitch_scale = randf_range(1.2, 1.5)
		breathing_player.play()

func create_underwater_overlay():
	if underwater_overlay_scene:
		underwater_overlay = underwater_overlay_scene.instantiate()
		get_tree().current_scene.add_child(underwater_overlay)

func remove_underwater_overlay():
	if underwater_overlay:
		underwater_overlay.queue_free()
		underwater_overlay = null

func create_splash_effect():
	if splash_effect_scene:
		var splash = splash_effect_scene.instantiate()
		get_parent().add_child(splash)
		splash.global_position = get_body_position()
		splash_instances.append(splash)
		
		var timer = Timer.new()
		timer.wait_time = 3.0
		timer.one_shot = true
		timer.timeout.connect(func():
			if splash in splash_instances:
				splash_instances.erase(splash)
			splash.queue_free()
		)
		splash.add_child(timer)
		timer.start()
	
	play_splash_sound()

func create_swimming_trail(hand_name: String):
	if swimming_trail_scene:
		var hand = left_hand if hand_name == "left" else right_hand
		if hand:
			var trail = swimming_trail_scene.instantiate()
			get_parent().add_child(trail)
			trail.global_position = hand.global_position

func create_bubble_effect():
	if bubble_effect_scene and is_underwater:
		var bubbles = bubble_effect_scene.instantiate()
		get_parent().add_child(bubbles)
		bubbles.global_position = get_head_position()
		bubble_instances.append(bubbles)

func play_underwater_audio():
	if underwater_ambient and audio_player:
		audio_player.stream = underwater_ambient
		audio_player.play()

func stop_underwater_audio():
	if audio_player.playing:
		audio_player.stop()

func play_splash_sound():
	if splash_sounds.size() > 0 and audio_player:
		var splash_sound = splash_sounds[randi() % splash_sounds.size()]
		var splash_player = AudioStreamPlayer3D.new()
		get_parent().add_child(splash_player)
		splash_player.stream = splash_sound
		splash_player.global_position = get_body_position()
		splash_player.play()
		splash_player.finished.connect(splash_player.queue_free)

func play_stroke_sound():
	pass

func update_visual_effects(delta):
	if is_underwater and randf() < 0.1:
		create_bubble_effect()

func update_audio_effects():
	pass

func cleanup_water_effects():
	remove_underwater_overlay()
	stop_underwater_audio()
	
	for splash in splash_instances:
		if is_instance_valid(splash):
			splash.queue_free()
	splash_instances.clear()
	
	for bubbles in bubble_instances:
		if is_instance_valid(bubbles):
			bubbles.queue_free()
	bubble_instances.clear()

func set_water_level(level: float):
	water_surface_level = level

func get_breath_percentage() -> float:
	return current_breath / max_breath

func add_breath(amount: float):
	current_breath = min(current_breath + amount, max_breath)
	emit_signal("breath_changed", current_breath, max_breath)

func force_surface():
	if is_in_water():
		global_position = Vector3(global_position.x, water_surface_level + 1.0, global_position.z)

func set_swimming_stats(force: float, drag: float, breath_capacity: float):
	swim_force_multiplier = force
	water_drag = drag
	max_breath = breath_capacity
	current_breath = max_breath