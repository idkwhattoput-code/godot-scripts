extends Node3D

signal entered_water
signal exited_water
signal oxygen_changed(current: float, max: float)
signal depth_changed(depth: float)

@export_group("Swimming Physics")
@export var water_density: float = 1000.0
@export var buoyancy_force: float = 9.8
@export var water_drag: float = 5.0
@export var stroke_power: float = 50.0
@export var kick_power: float = 30.0
@export var max_swim_speed: float = 5.0

@export_group("Oxygen System")
@export var max_oxygen: float = 100.0
@export var oxygen_consumption_rate: float = 5.0
@export var surface_refill_rate: float = 20.0
@export var panic_threshold: float = 20.0
@export var drowning_damage: float = 10.0

@export_group("VR Controls")
@export var stroke_detection_threshold: float = 0.5
@export var kick_detection_threshold: float = 0.3
@export var hand_cup_detection: bool = true
@export var realistic_swimming: bool = true

@export_group("Visual Effects")
@export var water_surface_material: Material
@export var underwater_fog_density: float = 0.1
@export var bubble_particle_scene: PackedScene
@export var splash_effect_scene: PackedScene
@export var underwater_tint: Color = Color(0.4, 0.6, 0.8, 0.3)

@export_group("Audio")
@export var water_enter_sound: AudioStream
@export var water_exit_sound: AudioStream
@export var swimming_sounds: Array[AudioStream] = []
@export var underwater_ambient: AudioStream
@export var bubble_sounds: Array[AudioStream] = []

var is_in_water: bool = false
var is_underwater: bool = false
var water_surface_height: float = 0.0
var current_depth: float = 0.0
var current_oxygen: float
var water_velocity: Vector3 = Vector3.ZERO

var player_body: CharacterBody3D
var left_controller: XRController3D
var right_controller: XRController3D
var left_hand_velocity: Vector3 = Vector3.ZERO
var right_hand_velocity: Vector3 = Vector3.ZERO
var previous_left_pos: Vector3
var previous_right_pos: Vector3

var stroke_timers: Dictionary = {"left": 0.0, "right": 0.0}
var last_stroke_times: Dictionary = {"left": 0.0, "right": 0.0}
var stroke_rhythm: float = 0.0
var kick_timer: float = 0.0

var underwater_overlay: ColorRect
var audio_players: Dictionary = {}
var bubble_particles: CPUParticles3D
var environment: Environment

func _ready():
	current_oxygen = max_oxygen
	_setup_player()
	_setup_controllers()
	_setup_underwater_effects()
	_setup_audio()

func _setup_player():
	var player = get_tree().get_first_node_in_group("player")
	if player and player is CharacterBody3D:
		player_body = player
	else:
		# Create a basic player body if none exists
		player_body = CharacterBody3D.new()
		var collision = CollisionShape3D.new()
		var capsule = CapsuleShape3D.new()
		capsule.height = 1.8
		capsule.radius = 0.3
		collision.shape = capsule
		player_body.add_child(collision)
		add_child(player_body)

func _setup_controllers():
	var xr_origin = get_node_or_null("/root/XROrigin3D")
	if not xr_origin:
		xr_origin = XROrigin3D.new()
		get_tree().root.add_child(xr_origin)
	
	left_controller = xr_origin.get_node_or_null("LeftController")
	if not left_controller:
		left_controller = XRController3D.new()
		left_controller.tracker = "left_hand"
		xr_origin.add_child(left_controller)
	
	right_controller = xr_origin.get_node_or_null("RightController")
	if not right_controller:
		right_controller = XRController3D.new()
		right_controller.tracker = "right_hand"
		xr_origin.add_child(right_controller)
	
	previous_left_pos = left_controller.global_position
	previous_right_pos = right_controller.global_position

func _setup_underwater_effects():
	# Create underwater overlay
	underwater_overlay = ColorRect.new()
	underwater_overlay.color = underwater_tint
	underwater_overlay.anchor_right = 1.0
	underwater_overlay.anchor_bottom = 1.0
	underwater_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	underwater_overlay.visible = false
	
	var canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 100
	canvas_layer.add_child(underwater_overlay)
	add_child(canvas_layer)
	
	# Create bubble particles
	if bubble_particle_scene:
		bubble_particles = bubble_particle_scene.instantiate()
		add_child(bubble_particles)
		bubble_particles.emitting = false
	
	# Get environment for fog effects
	var camera = get_viewport().get_camera_3d()
	if camera:
		environment = camera.environment
		if not environment:
			environment = Environment.new()
			camera.environment = environment

func _setup_audio():
	# Swimming audio
	var swim_audio = AudioStreamPlayer3D.new()
	add_child(swim_audio)
	audio_players["swimming"] = swim_audio
	
	# Underwater ambient
	var ambient_audio = AudioStreamPlayer3D.new()
	ambient_audio.stream = underwater_ambient
	ambient_audio.autoplay = false
	add_child(ambient_audio)
	audio_players["ambient"] = ambient_audio
	
	# Bubble audio
	var bubble_audio = AudioStreamPlayer3D.new()
	add_child(bubble_audio)
	audio_players["bubbles"] = bubble_audio

func _physics_process(delta):
	_update_hand_tracking(delta)
	_update_swimming_physics(delta)
	_update_oxygen_system(delta)
	_update_stroke_detection(delta)
	_update_effects(delta)

func _update_hand_tracking(delta):
	# Track hand velocities
	var current_left_pos = left_controller.global_position
	var current_right_pos = right_controller.global_position
	
	left_hand_velocity = (current_left_pos - previous_left_pos) / delta
	right_hand_velocity = (current_right_pos - previous_right_pos) / delta
	
	previous_left_pos = current_left_pos
	previous_right_pos = current_right_pos
	
	# Update stroke timers
	stroke_timers["left"] += delta
	stroke_timers["right"] += delta

func _update_swimming_physics(delta):
	if not is_in_water or not player_body:
		return
	
	var velocity = player_body.velocity
	
	# Apply buoyancy
	if is_underwater:
		velocity.y += buoyancy_force * delta
	
	# Apply water drag
	velocity = velocity * (1.0 - water_drag * delta)
	
	# Apply swimming forces
	velocity += _calculate_stroke_force() * delta
	velocity += _calculate_kick_force() * delta
	
	# Apply water current
	velocity += water_velocity * delta
	
	# Limit speed
	if velocity.length() > max_swim_speed:
		velocity = velocity.normalized() * max_swim_speed
	
	player_body.velocity = velocity

func _update_stroke_detection(delta):
	# Detect swimming strokes
	_detect_stroke("left", left_hand_velocity, delta)
	_detect_stroke("right", right_hand_velocity, delta)
	
	# Update stroke rhythm
	var time_since_left = stroke_timers["left"] - last_stroke_times["left"]
	var time_since_right = stroke_timers["right"] - last_stroke_times["right"]
	
	if time_since_left < 2.0 and time_since_right < 2.0:
		stroke_rhythm = 1.0 / max(abs(time_since_left - time_since_right), 0.1)
	else:
		stroke_rhythm = max(0, stroke_rhythm - delta * 2)

func _detect_stroke(hand: String, velocity: Vector3, delta: float):
	var speed = velocity.length()
	var direction = velocity.normalized()
	
	# Check if hand is moving fast enough in swimming motion
	if speed > stroke_detection_threshold:
		# Check if motion is primarily horizontal/forward
		if abs(direction.y) < 0.5 and direction.z < -0.3:  # Forward stroke
			_perform_stroke(hand, speed, direction)

func _perform_stroke(hand: String, speed: float, direction: Vector3):
	last_stroke_times[hand] = stroke_timers[hand]
	
	# Play swimming sound
	if swimming_sounds.size() > 0 and audio_players.has("swimming"):
		var sound = swimming_sounds[randi() % swimming_sounds.size()]
		audio_players["swimming"].stream = sound
		audio_players["swimming"].pitch_scale = 0.8 + speed * 0.4
		audio_players["swimming"].play()
	
	# Create splash effect if near surface
	if abs(current_depth) < 0.5 and splash_effect_scene:
		var splash = splash_effect_scene.instantiate()
		get_tree().current_scene.add_child(splash)
		var controller = left_controller if hand == "left" else right_controller
		splash.global_position = controller.global_position
	
	# Haptic feedback
	var controller = left_controller if hand == "left" else right_controller
	controller.trigger_haptic_pulse("haptic", 200.0, 0.3, 0.1)

func _calculate_stroke_force() -> Vector3:
	var force = Vector3.ZERO
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Left hand stroke
	if current_time - last_stroke_times["left"] < 0.5:
		var stroke_strength = (0.5 - (current_time - last_stroke_times["left"])) * 2
		force += left_controller.global_transform.basis.z * stroke_power * stroke_strength
	
	# Right hand stroke
	if current_time - last_stroke_times["right"] < 0.5:
		var stroke_strength = (0.5 - (current_time - last_stroke_times["right"])) * 2
		force += right_controller.global_transform.basis.z * stroke_power * stroke_strength
	
	# Bonus for synchronized strokes
	if stroke_rhythm > 0.5:
		force *= 1.0 + stroke_rhythm * 0.5
	
	return force

func _calculate_kick_force() -> Vector3:
	# Simple kick simulation - could be enhanced with leg tracking
	var kick_force = Vector3.ZERO
	
	if kick_timer > 0:
		kick_force = Vector3.FORWARD * kick_power * kick_timer
		kick_timer -= get_physics_process_delta_time() * 2
	
	return kick_force

func _update_oxygen_system(delta):
	if not is_underwater:
		# Refill oxygen at surface
		current_oxygen = min(current_oxygen + surface_refill_rate * delta, max_oxygen)
	else:
		# Consume oxygen underwater
		current_oxygen = max(current_oxygen - oxygen_consumption_rate * delta, 0)
		
		# Panic effects at low oxygen
		if current_oxygen < panic_threshold:
			_apply_panic_effects()
		
		# Drowning damage
		if current_oxygen <= 0:
			_apply_drowning_damage(delta)
	
	oxygen_changed.emit(current_oxygen, max_oxygen)

func _apply_panic_effects():
	# Screen shake, faster oxygen consumption, etc.
	if environment:
		environment.fog_density = underwater_fog_density * 2
	
	# Haptic feedback for panic
	left_controller.trigger_haptic_pulse("haptic", 100.0, 0.1, 0.1)
	right_controller.trigger_haptic_pulse("haptic", 100.0, 0.1, 0.1)

func _apply_drowning_damage(delta: float):
	if player_body.has_method("take_damage"):
		player_body.take_damage(drowning_damage * delta)

func _update_effects(delta):
	# Update underwater visual effects
	if is_underwater:
		underwater_overlay.visible = true
		
		if environment:
			environment.fog_enabled = true
			environment.fog_density = underwater_fog_density
			environment.fog_color = Color(0.2, 0.4, 0.6)
		
		if bubble_particles:
			bubble_particles.emitting = true
			# Adjust bubble rate based on activity
			var activity = (left_hand_velocity.length() + right_hand_velocity.length()) / 2
			bubble_particles.amount_ratio = min(0.1 + activity * 0.5, 1.0)
	else:
		underwater_overlay.visible = false
		
		if environment:
			environment.fog_enabled = false
		
		if bubble_particles:
			bubble_particles.emitting = false

func enter_water(surface_height: float):
	if is_in_water:
		return
	
	is_in_water = true
	water_surface_height = surface_height
	entered_water.emit()
	
	# Play enter water sound
	if water_enter_sound and audio_players.has("swimming"):
		audio_players["swimming"].stream = water_enter_sound
		audio_players["swimming"].play()
	
	# Create splash effect
	if splash_effect_scene:
		var splash = splash_effect_scene.instantiate()
		get_tree().current_scene.add_child(splash)
		splash.global_position = player_body.global_position

func exit_water():
	if not is_in_water:
		return
	
	is_in_water = false
	is_underwater = false
	exited_water.emit()
	
	# Play exit water sound
	if water_exit_sound and audio_players.has("swimming"):
		audio_players["swimming"].stream = water_exit_sound
		audio_players["swimming"].play()
	
	# Stop underwater ambient
	if audio_players.has("ambient"):
		audio_players["ambient"].stop()

func update_water_depth():
	if not is_in_water:
		current_depth = 0
		return
	
	var player_head_height = player_body.global_position.y + 1.5  # Approximate head height
	current_depth = water_surface_height - player_head_height
	
	var was_underwater = is_underwater
	is_underwater = current_depth > 0
	
	# Transition effects
	if is_underwater and not was_underwater:
		# Just went underwater
		if audio_players.has("ambient"):
			audio_players["ambient"].play()
	elif not is_underwater and was_underwater:
		# Just surfaced
		if audio_players.has("ambient"):
			audio_players["ambient"].stop()
	
	depth_changed.emit(current_depth)

func perform_kick():
	kick_timer = 1.0

func set_water_current(velocity: Vector3):
	water_velocity = velocity

func get_swimming_efficiency() -> float:
	# Return 0-1 based on stroke rhythm and technique
	return clamp(stroke_rhythm / 2.0, 0.0, 1.0)

func is_swimming() -> bool:
	return is_in_water and (left_hand_velocity.length() > 0.1 or right_hand_velocity.length() > 0.1)