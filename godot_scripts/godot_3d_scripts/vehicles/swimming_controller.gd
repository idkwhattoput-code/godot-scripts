extends KinematicBody

export var swim_speed = 5.0
export var dive_speed = 3.0
export var surface_speed = 7.0
export var underwater_drag = 0.95
export var buoyancy = 9.8
export var oxygen_max = 100.0
export var oxygen_depletion_rate = 5.0

var velocity = Vector3.ZERO
var oxygen_level = oxygen_max
var is_underwater = false
var is_at_surface = false
var water_level = 0.0

export var can_dive = true
export var auto_surface = true
export var swim_stamina = 100.0
export var stamina_drain_rate = 10.0
export var stamina_regen_rate = 15.0

var current_stamina = swim_stamina
var is_swimming = false
var last_breath_time = 0.0

onready var water_detector = $WaterDetector
onready var bubble_particles = $BubbleParticles
onready var splash_particles = $SplashParticles
onready var swim_sound = $SwimSound
onready var dive_sound = $DiveSound
onready var breath_sound = $BreathSound

signal entered_water()
signal exited_water()
signal oxygen_changed(amount)
signal stamina_changed(amount)
signal drowned()

func _ready():
	if water_detector:
		water_detector.connect("area_entered", self, "_on_water_entered")
		water_detector.connect("area_exited", self, "_on_water_exited")

func _physics_process(delta):
	if is_underwater or is_at_surface:
		_handle_swimming(delta)
		_update_oxygen(delta)
		_update_stamina(delta)
	else:
		_handle_normal_movement(delta)
	
	velocity = move_and_slide(velocity, Vector3.UP)
	
	_check_water_surface()
	_update_effects()

func _handle_swimming(delta):
	var input_vector = Vector3.ZERO
	
	input_vector.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_vector.z = Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	
	if can_dive and is_underwater:
		if Input.is_action_pressed("dive_down"):
			input_vector.y = -1
		elif Input.is_action_pressed("swim_up"):
			input_vector.y = 1
	
	input_vector = input_vector.normalized()
	
	var camera_transform = get_viewport().get_camera().global_transform
	var camera_basis = camera_transform.basis
	
	var movement = Vector3.ZERO
	movement += camera_basis.x * input_vector.x
	movement += camera_basis.z * input_vector.z
	movement.y = input_vector.y
	
	is_swimming = input_vector.length() > 0.1
	
	var current_speed = swim_speed
	if is_at_surface:
		current_speed = surface_speed
	elif is_underwater and global_transform.origin.y < water_level - 5:
		current_speed = dive_speed
	
	if Input.is_action_pressed("sprint") and current_stamina > 0:
		current_speed *= 1.5
		is_swimming = true
	
	velocity = velocity.linear_interpolate(movement * current_speed, 5.0 * delta)
	
	if is_underwater:
		velocity *= underwater_drag
		
		if auto_surface and oxygen_level < 20:
			velocity.y += buoyancy * 2 * delta
		else:
			velocity.y += (buoyancy * 0.1) * delta
	
	if is_at_surface:
		velocity.y = 0
		global_transform.origin.y = water_level

func _handle_normal_movement(delta):
	velocity.y -= 9.8 * delta
	
	var input_vector = Vector3.ZERO
	input_vector.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_vector.z = Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = 10
	
	var movement = input_vector.normalized() * 7.0
	velocity.x = movement.x
	velocity.z = movement.z

func _check_water_surface():
	if not is_underwater:
		is_at_surface = false
		return
	
	var head_position = global_transform.origin.y + 1.5
	is_at_surface = head_position >= water_level and head_position <= water_level + 0.5
	
	if is_at_surface and last_breath_time + 1.0 < OS.get_ticks_msec() / 1000.0:
		_take_breath()

func _update_oxygen(delta):
	if is_underwater and not is_at_surface:
		oxygen_level -= oxygen_depletion_rate * delta
		oxygen_level = max(0, oxygen_level)
		
		if oxygen_level <= 0:
			emit_signal("drowned")
			_apply_drowning_effects()
	else:
		oxygen_level += oxygen_depletion_rate * 3 * delta
		oxygen_level = min(oxygen_max, oxygen_level)
	
	emit_signal("oxygen_changed", oxygen_level)

func _update_stamina(delta):
	if is_swimming and Input.is_action_pressed("sprint"):
		current_stamina -= stamina_drain_rate * delta
		current_stamina = max(0, current_stamina)
	else:
		current_stamina += stamina_regen_rate * delta
		current_stamina = min(swim_stamina, current_stamina)
	
	emit_signal("stamina_changed", current_stamina)

func _take_breath():
	last_breath_time = OS.get_ticks_msec() / 1000.0
	oxygen_level = min(oxygen_level + 30, oxygen_max)
	
	if breath_sound and oxygen_level < 50:
		breath_sound.play()

func _apply_drowning_effects():
	velocity *= 0.5
	
	get_tree().create_timer(2.0).connect("timeout", self, "respawn")

func _update_effects():
	if bubble_particles:
		bubble_particles.emitting = is_underwater and is_swimming
	
	if swim_sound:
		if is_swimming and (is_underwater or is_at_surface):
			if not swim_sound.playing:
				swim_sound.play()
		else:
			swim_sound.stop()

func _on_water_entered(area):
	if area.is_in_group("water"):
		is_underwater = true
		water_level = area.global_transform.origin.y + area.get_node("CollisionShape").shape.extents.y
		
		velocity *= 0.5
		
		emit_signal("entered_water")
		
		if splash_particles:
			splash_particles.emitting = true
			splash_particles.restart()
		
		if dive_sound:
			dive_sound.play()

func _on_water_exited(area):
	if area.is_in_group("water"):
		is_underwater = false
		is_at_surface = false
		
		emit_signal("exited_water")
		
		if splash_particles:
			splash_particles.emitting = true
			splash_particles.restart()

func respawn():
	global_transform.origin = Vector3(0, 10, 0)
	velocity = Vector3.ZERO
	oxygen_level = oxygen_max
	current_stamina = swim_stamina

func set_water_level(level: float):
	water_level = level

func force_surface():
	if is_underwater:
		velocity.y = buoyancy * 5

func get_swim_depth() -> float:
	if is_underwater:
		return water_level - global_transform.origin.y
	return 0.0