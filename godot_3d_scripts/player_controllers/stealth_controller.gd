extends KinematicBody

# Movement settings
export var walk_speed = 3.0
export var sneak_speed = 1.5
export var run_speed = 6.0
export var crawl_speed = 1.0
export var acceleration = 10.0
export var friction = 8.0

# Stealth mechanics
export var noise_radius_sneak = 2.0
export var noise_radius_walk = 5.0
export var noise_radius_run = 10.0
export var visibility_standing = 1.0
export var visibility_crouching = 0.5
export var visibility_prone = 0.2
export var visibility_in_shadow = 0.3

# Detection system
export var suspicion_increase_rate = 1.0
export var suspicion_decrease_rate = 0.5
export var detection_threshold = 100.0
export var alert_threshold = 75.0

# State
enum StealthState {
	UNDETECTED,
	SUSPICIOUS,
	SEARCHING,
	ALERT,
	COMBAT
}

enum Stance {
	STANDING,
	CROUCHING,
	PRONE
}

var current_state = StealthState.UNDETECTED
var current_stance = Stance.STANDING
var velocity = Vector3.ZERO
var is_in_shadow = false
var is_against_wall = false
var light_level = 0.0
var noise_level = 0.0
var visibility_level = 0.0

# Detection tracking
var detection_sources = {}
var global_suspicion = 0.0
var last_known_position = Vector3.ZERO
var time_since_seen = 0.0

# Cover system
var nearby_cover = []
var current_cover = null
var cover_direction = Vector3.ZERO
var is_in_cover = false

# Distraction system
var active_distractions = []
var distraction_cooldown = 0.0

# Gadgets
export var max_distractions = 3
export var max_smoke_grenades = 2
export var max_emp_charges = 1
var distraction_count = 3
var smoke_count = 2
var emp_count = 1

# Sound detection
var sound_sources = []
var footstep_timer = 0.0
var footstep_interval = 0.5

# Camouflage
export var has_camo_suit = false
export var camo_duration = 10.0
export var camo_cooldown = 30.0
var is_camo_active = false
var camo_timer = 0.0
var camo_cooldown_timer = 0.0

# Movement
var movement_vector = Vector2.ZERO
var is_sneaking = false
var is_running = false
var lean_direction = 0.0  # -1 = left, 0 = none, 1 = right

# Components
onready var camera = $CameraRotation/Camera
onready var camera_rotation = $CameraRotation
onready var visibility_detector = $VisibilityDetector
onready var noise_area = $NoiseArea
onready var cover_detector = $CoverDetector
onready var interaction_ray = $CameraRotation/Camera/InteractionRay
onready var ui_stealth_meter = $UI/StealthMeter
onready var ui_detection_indicator = $UI/DetectionIndicator

# Collision shapes for different stances
onready var standing_collision = $StandingCollision
onready var crouching_collision = $CrouchingCollision
onready var prone_collision = $ProneCollision

signal state_changed(new_state)
signal detected_by(enemy)
signal entered_shadow()
signal exited_shadow()
signal noise_made(position, radius)
signal distraction_thrown(position)

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_setup_detection_system()
	_initialize_gadgets()
	set_physics_process(true)

func _setup_detection_system():
	# Setup collision areas for detection
	noise_area.connect("body_entered", self, "_on_noise_area_entered")
	cover_detector.connect("area_entered", self, "_on_cover_detected")
	cover_detector.connect("area_exited", self, "_on_cover_lost")

func _initialize_gadgets():
	distraction_count = max_distractions
	smoke_count = max_smoke_grenades
	emp_count = max_emp_charges

func _input(event):
	if event is InputEventMouseMotion:
		# Camera rotation
		rotate_y(deg2rad(-event.relative.x * 0.2))
		camera_rotation.rotate_x(deg2rad(-event.relative.y * 0.2))
		camera_rotation.rotation.x = clamp(camera_rotation.rotation.x, deg2rad(-80), deg2rad(80))
	
	# Handle gadget inputs
	if event.is_action_pressed("throw_distraction"):
		_throw_distraction()
	elif event.is_action_pressed("throw_smoke"):
		_throw_smoke_grenade()
	elif event.is_action_pressed("use_emp"):
		_use_emp_charge()
	elif event.is_action_pressed("activate_camo"):
		_toggle_camouflage()

func _physics_process(delta):
	_handle_movement_input()
	_update_stance()
	_apply_movement(delta)
	_update_stealth_mechanics(delta)
	_update_detection(delta)
	_update_gadgets(delta)
	_update_ui()
	
	velocity = move_and_slide(velocity, Vector3.UP)

func _handle_movement_input():
	movement_vector = Vector2()
	movement_vector.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	movement_vector.y = Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	movement_vector = movement_vector.normalized()
	
	is_sneaking = Input.is_action_pressed("sneak")
	is_running = Input.is_action_pressed("run") and current_stance == Stance.STANDING
	
	# Leaning
	if Input.is_action_pressed("lean_left"):
		lean_direction = -1
	elif Input.is_action_pressed("lean_right"):
		lean_direction = 1
	else:
		lean_direction = 0
	
	# Cover actions
	if Input.is_action_just_pressed("take_cover") and current_cover:
		_enter_cover()
	elif Input.is_action_just_released("take_cover"):
		_exit_cover()

func _update_stance():
	var previous_stance = current_stance
	
	if Input.is_action_pressed("crouch"):
		if current_stance == Stance.STANDING:
			current_stance = Stance.CROUCHING
		elif current_stance == Stance.CROUCHING and Input.is_action_pressed("prone"):
			current_stance = Stance.PRONE
	else:
		if current_stance == Stance.PRONE:
			current_stance = Stance.CROUCHING
		elif current_stance == Stance.CROUCHING:
			current_stance = Stance.STANDING
	
	# Update collision shapes
	if current_stance != previous_stance:
		_update_collision_shape()

func _update_collision_shape():
	standing_collision.disabled = current_stance != Stance.STANDING
	crouching_collision.disabled = current_stance != Stance.CROUCHING
	prone_collision.disabled = current_stance != Stance.PRONE
	
	# Adjust camera height
	match current_stance:
		Stance.STANDING:
			camera_rotation.translation.y = 1.7
		Stance.CROUCHING:
			camera_rotation.translation.y = 1.0
		Stance.PRONE:
			camera_rotation.translation.y = 0.3

func _apply_movement(delta):
	var direction = Vector3()
	direction.x = movement_vector.x
	direction.z = -movement_vector.y
	direction = direction.rotated(Vector3.UP, rotation.y).normalized()
	
	# Calculate speed based on stance and input
	var target_speed = _get_movement_speed()
	
	if direction.length() > 0:
		velocity.x = lerp(velocity.x, direction.x * target_speed, acceleration * delta)
		velocity.z = lerp(velocity.z, direction.z * target_speed, acceleration * delta)
		
		# Update footstep timer
		footstep_timer += delta
		if footstep_timer >= footstep_interval / (target_speed / walk_speed):
			_make_footstep_noise()
			footstep_timer = 0.0
	else:
		velocity.x = lerp(velocity.x, 0, friction * delta)
		velocity.z = lerp(velocity.z, 0, friction * delta)
	
	# Gravity
	if not is_on_floor():
		velocity.y -= 20 * delta
	else:
		velocity.y = -2
	
	# Apply lean
	if lean_direction != 0 and (is_against_wall or is_in_cover):
		camera_rotation.rotation.z = lerp(camera_rotation.rotation.z, lean_direction * deg2rad(15), 5 * delta)
	else:
		camera_rotation.rotation.z = lerp(camera_rotation.rotation.z, 0, 5 * delta)

func _get_movement_speed() -> float:
	if is_in_cover:
		return sneak_speed * 0.7
	
	match current_stance:
		Stance.STANDING:
			if is_running and not is_sneaking:
				return run_speed
			elif is_sneaking:
				return sneak_speed
			else:
				return walk_speed
		Stance.CROUCHING:
			return sneak_speed
		Stance.PRONE:
			return crawl_speed
	
	return walk_speed

func _update_stealth_mechanics(delta):
	# Update light level
	light_level = _calculate_light_level()
	
	# Update visibility
	visibility_level = _calculate_visibility()
	
	# Update noise level
	noise_level = _calculate_noise_level()
	
	# Check shadows
	var was_in_shadow = is_in_shadow
	is_in_shadow = light_level < 0.3
	
	if is_in_shadow != was_in_shadow:
		if is_in_shadow:
			emit_signal("entered_shadow")
		else:
			emit_signal("exited_shadow")
	
	# Update noise area size
	if noise_area:
		var shape = noise_area.get_node("CollisionShape").shape
		if shape is SphereShape:
			shape.radius = noise_level

func _calculate_light_level() -> float:
	# Check nearby lights
	var lights = get_tree().get_nodes_in_group("lights")
	var total_light = 0.0
	
	for light in lights:
		if light is Light:
			var distance = global_transform.origin.distance_to(light.global_transform.origin)
			var range = light.light_energy * 10  # Approximate range
			
			if distance < range:
				var intensity = light.light_energy * (1.0 - distance / range)
				total_light += intensity
	
	# Add ambient light
	total_light += 0.2
	
	return clamp(total_light, 0.0, 1.0)

func _calculate_visibility() -> float:
	var base_visibility = 0.0
	
	# Stance visibility
	match current_stance:
		Stance.STANDING:
			base_visibility = visibility_standing
		Stance.CROUCHING:
			base_visibility = visibility_crouching
		Stance.PRONE:
			base_visibility = visibility_prone
	
	# Movement modifier
	var speed = velocity.length()
	if speed > run_speed * 0.8:
		base_visibility *= 1.5
	elif speed < sneak_speed:
		base_visibility *= 0.8
	
	# Shadow modifier
	if is_in_shadow:
		base_visibility *= visibility_in_shadow
	
	# Cover modifier
	if is_in_cover:
		base_visibility *= 0.4
	
	# Camouflage modifier
	if is_camo_active:
		base_visibility *= 0.1
	
	return clamp(base_visibility * light_level, 0.0, 1.0)

func _calculate_noise_level() -> float:
	var speed = velocity.length()
	var base_noise = 0.0
	
	if speed > run_speed * 0.8:
		base_noise = noise_radius_run
	elif speed > walk_speed * 0.8:
		base_noise = noise_radius_walk
	elif speed > 0.1:
		base_noise = noise_radius_sneak
	
	# Surface modifier (would check surface type)
	var surface_modifier = 1.0
	
	# Stance modifier
	match current_stance:
		Stance.CROUCHING:
			surface_modifier *= 0.7
		Stance.PRONE:
			surface_modifier *= 0.4
	
	return base_noise * surface_modifier

func _make_footstep_noise():
	emit_signal("noise_made", global_transform.origin, noise_level)

func _update_detection(delta):
	# Update suspicion from all detection sources
	global_suspicion = 0.0
	
	for source_id in detection_sources:
		var source = detection_sources[source_id]
		
		# Line of sight check
		if _check_line_of_sight(source.position):
			# In sight - increase suspicion based on visibility
			source.suspicion += visibility_level * suspicion_increase_rate * delta * 60
			time_since_seen = 0.0
			last_known_position = global_transform.origin
		else:
			# Not in sight - decrease suspicion
			source.suspicion = max(0, source.suspicion - suspicion_decrease_rate * delta * 60)
		
		global_suspicion = max(global_suspicion, source.suspicion)
	
	time_since_seen += delta
	
	# Update stealth state
	var previous_state = current_state
	
	if global_suspicion >= detection_threshold:
		current_state = StealthState.COMBAT
	elif global_suspicion >= alert_threshold:
		current_state = StealthState.ALERT
	elif global_suspicion > 25:
		current_state = StealthState.SEARCHING
	elif global_suspicion > 0:
		current_state = StealthState.SUSPICIOUS
	else:
		current_state = StealthState.UNDETECTED
	
	if current_state != previous_state:
		emit_signal("state_changed", current_state)

func _check_line_of_sight(from_position: Vector3) -> bool:
	var space_state = get_world().direct_space_state
	var result = space_state.intersect_ray(from_position, global_transform.origin + Vector3.UP, [self])
	return result.empty()

func _on_noise_area_entered(body):
	if body.has_method("hear_noise"):
		body.hear_noise(global_transform.origin, noise_level)

func _on_cover_detected(area):
	if area.is_in_group("cover"):
		nearby_cover.append(area)
		if not current_cover:
			current_cover = area

func _on_cover_lost(area):
	nearby_cover.erase(area)
	if current_cover == area:
		current_cover = nearby_cover.front() if not nearby_cover.empty() else null
		if is_in_cover:
			_exit_cover()

func _enter_cover():
	if not current_cover:
		return
	
	is_in_cover = true
	# Calculate cover direction
	var cover_normal = current_cover.global_transform.basis.z
	cover_direction = cover_normal
	
	# Snap to cover
	var cover_pos = current_cover.global_transform.origin
	global_transform.origin = cover_pos + cover_normal * 0.5

func _exit_cover():
	is_in_cover = false
	cover_direction = Vector3.ZERO

func _throw_distraction():
	if distraction_count <= 0 or distraction_cooldown > 0:
		return
	
	distraction_count -= 1
	distraction_cooldown = 2.0
	
	# Calculate throw direction
	var throw_origin = camera.global_transform.origin
	var throw_direction = -camera.global_transform.basis.z
	
	# Create distraction object
	var distraction = preload("res://objects/distraction_device.tscn").instance()
	get_parent().add_child(distraction)
	distraction.global_transform.origin = throw_origin
	distraction.apply_impulse(Vector3.ZERO, throw_direction * 15)
	
	emit_signal("distraction_thrown", throw_origin + throw_direction * 10)

func _throw_smoke_grenade():
	if smoke_count <= 0:
		return
	
	smoke_count -= 1
	
	# Similar to distraction but creates smoke area
	var smoke = preload("res://objects/smoke_grenade.tscn").instance()
	get_parent().add_child(smoke)
	smoke.global_transform.origin = camera.global_transform.origin
	smoke.activate()

func _use_emp_charge():
	if emp_count <= 0:
		return
	
	emp_count -= 1
	
	# Disable nearby electronics
	var electronics = get_tree().get_nodes_in_group("electronic")
	for device in electronics:
		if device.global_transform.origin.distance_to(global_transform.origin) < 10:
			if device.has_method("emp_disable"):
				device.emp_disable(5.0)  # 5 second disable

func _toggle_camouflage():
	if not has_camo_suit or camo_cooldown_timer > 0:
		return
	
	if is_camo_active:
		_deactivate_camouflage()
	else:
		_activate_camouflage()

func _activate_camouflage():
	is_camo_active = true
	camo_timer = camo_duration
	
	# Visual effect
	var material = get_node("PlayerMesh").material_override
	if material:
		material.albedo_color.a = 0.2

func _deactivate_camouflage():
	is_camo_active = false
	camo_cooldown_timer = camo_cooldown
	
	# Reset visual
	var material = get_node("PlayerMesh").material_override
	if material:
		material.albedo_color.a = 1.0

func _update_gadgets(delta):
	# Update cooldowns
	if distraction_cooldown > 0:
		distraction_cooldown -= delta
	
	if camo_cooldown_timer > 0:
		camo_cooldown_timer -= delta
	
	# Update active camouflage
	if is_camo_active:
		camo_timer -= delta
		if camo_timer <= 0:
			_deactivate_camouflage()

func _update_ui():
	# Update stealth meter
	if ui_stealth_meter:
		ui_stealth_meter.value = 100 - global_suspicion
	
	# Update detection indicator
	if ui_detection_indicator:
		ui_detection_indicator.visible = current_state != StealthState.UNDETECTED
		
		# Set indicator color based on state
		match current_state:
			StealthState.SUSPICIOUS:
				ui_detection_indicator.modulate = Color.yellow
			StealthState.SEARCHING:
				ui_detection_indicator.modulate = Color.orange
			StealthState.ALERT:
				ui_detection_indicator.modulate = Color.red
			StealthState.COMBAT:
				ui_detection_indicator.modulate = Color.red
				# Make it flash
				ui_detection_indicator.modulate.a = sin(OS.get_ticks_msec() * 0.01) * 0.5 + 0.5

# Enemy detection interface
func register_detection_source(enemy_id: int, position: Vector3):
	detection_sources[enemy_id] = {
		"position": position,
		"suspicion": 0.0
	}

func update_detection_source(enemy_id: int, position: Vector3):
	if detection_sources.has(enemy_id):
		detection_sources[enemy_id].position = position

func unregister_detection_source(enemy_id: int):
	detection_sources.erase(enemy_id)

func get_last_known_position() -> Vector3:
	return last_known_position

func get_visibility_level() -> float:
	return visibility_level

func get_noise_level() -> float:
	return noise_level