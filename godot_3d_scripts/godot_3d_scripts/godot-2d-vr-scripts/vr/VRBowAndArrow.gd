extends Node3D

signal arrow_nocked
signal bow_drawn(draw_percentage: float)
signal arrow_fired(arrow: Node3D, force: float)
signal string_snapped
signal perfect_shot(accuracy: float)

@export_group("Bow Configuration")
@export var bow_model: Node3D
@export var string_model: Node3D
@export var arrow_scene: PackedScene
@export var max_draw_distance: float = 0.8
@export var bow_strength: float = 1000.0
@export var accuracy_bonus: float = 1.5

@export_group("Arrows")
@export var arrow_speed_multiplier: float = 25.0
@export var arrow_damage_base: float = 50.0
@export var arrow_gravity: float = 9.8
@export var arrow_lifetime: float = 30.0
@export var infinite_arrows: bool = false
@export var arrow_count: int = 30

@export_group("Physics")
@export var string_tension_curve: Curve
@export var release_snap_back: float = 0.3
@export var aim_assist_enabled: bool = false
@export var aim_assist_angle: float = 5.0
@export var wind_affect: bool = true

@export_group("Visual Effects")
@export var draw_particles: CPUParticles3D
@export var release_particles: CPUParticles3D
@export var string_glow_material: Material
@export var bow_hand_attachment: Node3D
@export var string_hand_attachment: Node3D

@export_group("Audio")
@export var draw_sound: AudioStream
@export var release_sound: AudioStream
@export var string_creak_sound: AudioStream
@export var arrow_nock_sound: AudioStream

var is_bow_equipped: bool = false
var is_arrow_nocked: bool = false
var current_draw_distance: float = 0.0
var draw_percentage: float = 0.0
var nocked_arrow: Node3D = null
var string_starting_position: Vector3
var aim_target: Vector3

var bow_hand_controller: XRController3D  # Usually left hand
var string_hand_controller: XRController3D  # Usually right hand
var both_hands_holding: bool = false

var audio_players: Dictionary = {}
var string_line: Line3D
var aim_trajectory: Line3D

func _ready():
	_setup_controllers()
	_setup_audio()
	_setup_visuals()
	_initialize_bow()

func _setup_controllers():
	var xr_origin = get_node_or_null("/root/XROrigin3D")
	if not xr_origin:
		xr_origin = XROrigin3D.new()
		get_tree().root.add_child(xr_origin)
	
	bow_hand_controller = xr_origin.get_node_or_null("LeftController")
	if not bow_hand_controller:
		bow_hand_controller = XRController3D.new()
		bow_hand_controller.tracker = "left_hand"
		xr_origin.add_child(bow_hand_controller)
	
	string_hand_controller = xr_origin.get_node_or_null("RightController")
	if not string_hand_controller:
		string_hand_controller = XRController3D.new()
		string_hand_controller.tracker = "right_hand"
		xr_origin.add_child(string_hand_controller)
	
	# Connect controller signals
	bow_hand_controller.button_pressed.connect(_on_bow_hand_button.bind(true))
	bow_hand_controller.button_released.connect(_on_bow_hand_button.bind(false))
	string_hand_controller.button_pressed.connect(_on_string_hand_button.bind(true))
	string_hand_controller.button_released.connect(_on_string_hand_button.bind(false))

func _setup_audio():
	var draw_audio = AudioStreamPlayer3D.new()
	draw_audio.stream = draw_sound
	add_child(draw_audio)
	audio_players["draw"] = draw_audio
	
	var release_audio = AudioStreamPlayer3D.new()
	release_audio.stream = release_sound
	add_child(release_audio)
	audio_players["release"] = release_audio
	
	var creak_audio = AudioStreamPlayer3D.new()
	creak_audio.stream = string_creak_sound
	add_child(creak_audio)
	audio_players["creak"] = creak_audio

func _setup_visuals():
	# Create bow string visualization
	string_line = Line3D.new()
	string_line.width = 0.01
	string_line.material = string_glow_material
	add_child(string_line)
	
	# Create aim trajectory line
	aim_trajectory = Line3D.new()
	aim_trajectory.width = 0.005
	aim_trajectory.material = create_aim_material()
	aim_trajectory.visible = false
	add_child(aim_trajectory)

func create_aim_material() -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.emission_enabled = true
	material.emission = Color(1, 1, 0, 0.5)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

func _initialize_bow():
	if bow_model:
		bow_model.set_parent(bow_hand_controller)
		
	if string_model:
		string_starting_position = string_model.position

func _physics_process(delta):
	_update_bow_state(delta)
	_update_string_physics(delta)
	_update_aim_trajectory(delta)
	_update_haptic_feedback(delta)

func _update_bow_state(delta):
	if not is_bow_equipped:
		return
	
	# Check if both hands are in position
	var bow_pos = bow_hand_controller.global_position
	var string_pos = string_hand_controller.global_position
	var distance_to_bow = string_pos.distance_to(bow_pos)
	
	both_hands_holding = distance_to_bow < 1.5  # Within arm's reach
	
	if both_hands_holding and is_arrow_nocked:
		# Calculate draw distance
		var draw_vector = string_pos - bow_pos
		var bow_forward = -bow_hand_controller.global_transform.basis.z
		current_draw_distance = max(0, draw_vector.dot(bow_forward))
		draw_percentage = min(current_draw_distance / max_draw_distance, 1.0)
		
		bow_drawn.emit(draw_percentage)
		
		# Play draw sound
		if draw_percentage > 0.1 and not audio_players["draw"].playing:
			audio_players["draw"].play()
		
		# String tension sound
		if draw_percentage > 0.7:
			_play_tension_sound()
	else:
		current_draw_distance = 0.0
		draw_percentage = 0.0

func _update_string_physics(delta):
	if not string_model:
		return
	
	# Update string position based on draw
	if is_arrow_nocked and both_hands_holding:
		var string_hand_pos = string_hand_controller.global_position
		var bow_pos = bow_hand_controller.global_position
		
		# Calculate string attachment point
		var draw_direction = (string_hand_pos - bow_pos).normalized()
		var string_offset = draw_direction * current_draw_distance
		string_model.position = string_starting_position + string_offset
		
		# Update string line visualization
		_update_string_line()
	else:
		# Return string to rest position
		string_model.position = string_model.position.lerp(string_starting_position, delta * 10)

func _update_string_line():
	if not string_line:
		return
	
	string_line.clear_points()
	
	# Get bow endpoints (simplified)
	var bow_top = bow_hand_controller.global_position + Vector3(0, 0.3, 0)
	var bow_bottom = bow_hand_controller.global_position + Vector3(0, -0.3, 0)
	var string_pos = string_hand_controller.global_position
	
	# Create curved string
	string_line.add_point(bow_top)
	string_line.add_point(string_pos)
	string_line.add_point(bow_bottom)

func _update_aim_trajectory(delta):
	if not is_arrow_nocked or draw_percentage < 0.1:
		aim_trajectory.visible = false
		return
	
	aim_trajectory.visible = true
	aim_trajectory.clear_points()
	
	# Calculate arrow trajectory
	var start_pos = _get_arrow_spawn_position()
	var direction = _get_aim_direction()
	var velocity = direction * arrow_speed_multiplier * draw_percentage
	
	# Calculate trajectory points
	var trajectory_points = _calculate_trajectory(start_pos, velocity, 3.0, 0.1)
	
	for point in trajectory_points:
		aim_trajectory.add_point(point)

func _calculate_trajectory(start_pos: Vector3, velocity: Vector3, time: float, step: float) -> Array:
	var points = []
	var current_pos = start_pos
	var current_vel = velocity
	var t = 0.0
	
	while t < time:
		points.append(current_pos)
		current_vel.y -= arrow_gravity * step
		current_pos += current_vel * step
		t += step
		
		# Stop if hit ground (simplified)
		if current_pos.y < 0:
			break
	
	return points

func _update_haptic_feedback(delta):
	if not both_hands_holding:
		return
	
	# String tension haptic
	if draw_percentage > 0:
		var haptic_intensity = draw_percentage * 0.5
		string_hand_controller.trigger_haptic_pulse("haptic", 100.0, haptic_intensity, delta)
		
		# Bow hand also feels tension
		bow_hand_controller.trigger_haptic_pulse("haptic", 50.0, haptic_intensity * 0.3, delta)

func _on_bow_hand_button(button_name: String, pressed: bool):
	if button_name == "grip_click" and pressed:
		equip_bow()
	elif button_name == "grip_click" and not pressed:
		unequip_bow()

func _on_string_hand_button(button_name: String, pressed: bool):
	if button_name == "trigger_click" and pressed and is_bow_equipped:
		nock_arrow()
	elif button_name == "trigger_click" and not pressed and is_arrow_nocked:
		release_arrow()

func equip_bow():
	is_bow_equipped = true
	
	if bow_model:
		bow_model.visible = true
		
	# Attach bow to hand
	if bow_hand_attachment:
		bow_hand_attachment.visible = true

func unequip_bow():
	is_bow_equipped = false
	is_arrow_nocked = false
	
	if bow_model:
		bow_model.visible = false
		
	if nocked_arrow:
		nocked_arrow.queue_free()
		nocked_arrow = null

func nock_arrow():
	if not is_bow_equipped or is_arrow_nocked or (not infinite_arrows and arrow_count <= 0):
		return
	
	if not infinite_arrows:
		arrow_count -= 1
	
	is_arrow_nocked = true
	
	# Create arrow instance
	if arrow_scene:
		nocked_arrow = arrow_scene.instantiate()
		add_child(nocked_arrow)
		nocked_arrow.global_position = _get_arrow_spawn_position()
	
	arrow_nocked.emit()
	
	# Play nock sound
	if arrow_nock_sound:
		var audio = AudioStreamPlayer3D.new()
		audio.stream = arrow_nock_sound
		audio.autoplay = true
		add_child(audio)
		audio.finished.connect(audio.queue_free)

func release_arrow():
	if not is_arrow_nocked or not nocked_arrow:
		return
	
	# Calculate release force and direction
	var release_force = bow_strength * draw_percentage
	var direction = _get_aim_direction()
	
	# Apply aim assist if enabled
	if aim_assist_enabled:
		direction = _apply_aim_assist(direction)
	
	# Release the arrow
	var arrow_velocity = direction * arrow_speed_multiplier * draw_percentage
	
	if nocked_arrow.has_method("fire"):
		nocked_arrow.fire(arrow_velocity, arrow_damage_base * draw_percentage, arrow_lifetime)
	
	arrow_fired.emit(nocked_arrow, release_force)
	
	# Check for perfect shot
	if draw_percentage > 0.95:
		perfect_shot.emit(draw_percentage)
	
	# Reset state
	is_arrow_nocked = false
	nocked_arrow = null
	
	# Play release sound
	if audio_players.has("release"):
		audio_players["release"].pitch_scale = 0.8 + draw_percentage * 0.4
		audio_players["release"].play()
	
	# Release particles
	if release_particles:
		release_particles.restart()
	
	# String snap back haptic
	string_hand_controller.trigger_haptic_pulse("haptic", 1000.0, 1.0, release_snap_back)
	bow_hand_controller.trigger_haptic_pulse("haptic", 500.0, 0.5, release_snap_back)

func _get_arrow_spawn_position() -> Vector3:
	if string_hand_controller and bow_hand_controller:
		return (string_hand_controller.global_position + bow_hand_controller.global_position) / 2
	return global_position

func _get_aim_direction() -> Vector3:
	var bow_forward = -bow_hand_controller.global_transform.basis.z
	var string_to_bow = (bow_hand_controller.global_position - string_hand_controller.global_position).normalized()
	
	# Blend between bow direction and string angle
	return bow_forward.lerp(string_to_bow, 0.3).normalized()

func _apply_aim_assist(direction: Vector3) -> Vector3:
	# Find nearby targets
	var targets = get_tree().get_nodes_in_group("target")
	var closest_target = null
	var closest_angle = aim_assist_angle
	
	for target in targets:
		var to_target = (target.global_position - _get_arrow_spawn_position()).normalized()
		var angle = rad_to_deg(direction.angle_to(to_target))
		
		if angle < closest_angle:
			closest_angle = angle
			closest_target = target
	
	if closest_target:
		var to_target = (closest_target.global_position - _get_arrow_spawn_position()).normalized()
		return direction.lerp(to_target, 0.3)
	
	return direction

func _play_tension_sound():
	if string_tension_curve and draw_percentage > 0.7:
		var tension_amount = string_tension_curve.sample(draw_percentage)
		
		if not audio_players["creak"].playing and tension_amount > 0.8:
			audio_players["creak"].play()

func add_arrows(count: int):
	arrow_count += count

func get_arrow_count() -> int:
	return arrow_count

func get_draw_strength() -> float:
	return draw_percentage