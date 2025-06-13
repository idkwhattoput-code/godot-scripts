extends Node

export var max_jumps = 2
export var double_jump_force = 10.0
export var air_jump_multiplier = 0.8
export var coyote_time = 0.15
export var jump_buffer_time = 0.1
export var variable_jump_height = true
export var min_jump_height_multiplier = 0.5

signal jumped(jump_number)
signal double_jumped()
signal landed()

var current_jumps = 0
var coyote_timer = 0.0
var jump_buffer_timer = 0.0
var was_on_floor = false
var is_jumping = false
var jump_held_time = 0.0

onready var jump_particles = $JumpParticles
onready var double_jump_particles = $DoubleJumpParticles
onready var jump_sound = $JumpSound
onready var double_jump_sound = $DoubleJumpSound
onready var land_sound = $LandSound

func _ready():
	pass

func _physics_process(delta):
	var on_floor = get_parent().is_on_floor()
	
	if on_floor and not was_on_floor:
		_on_landed()
	elif was_on_floor and not on_floor and current_jumps == 0:
		coyote_timer = coyote_time
	
	if not on_floor and coyote_timer > 0:
		coyote_timer -= delta
	
	if jump_buffer_timer > 0:
		jump_buffer_timer -= delta
		if on_floor or (coyote_timer > 0 and current_jumps == 0):
			if perform_jump():
				jump_buffer_timer = 0.0
	
	if is_jumping and variable_jump_height:
		jump_held_time += delta
		if not Input.is_action_pressed("jump") and jump_held_time < 0.2:
			_reduce_jump_height()
	
	was_on_floor = on_floor

func request_jump():
	if can_jump():
		return perform_jump()
	else:
		jump_buffer_timer = jump_buffer_time
		return false

func perform_jump():
	if not can_jump():
		return false
	
	var jump_force = calculate_jump_force()
	
	get_parent().velocity.y = jump_force
	
	current_jumps += 1
	is_jumping = true
	jump_held_time = 0.0
	coyote_timer = 0.0
	
	_play_jump_effects()
	
	emit_signal("jumped", current_jumps)
	
	if current_jumps > 1:
		emit_signal("double_jumped")
	
	return true

func can_jump():
	if get_parent().is_on_floor():
		return true
	
	if coyote_timer > 0 and current_jumps == 0:
		return true
	
	if current_jumps < max_jumps:
		return true
	
	return false

func calculate_jump_force():
	var base_force = double_jump_force
	
	if current_jumps > 0:
		base_force *= air_jump_multiplier
	
	return base_force

func _reduce_jump_height():
	if is_jumping and get_parent().velocity.y > 0:
		get_parent().velocity.y *= min_jump_height_multiplier
		is_jumping = false

func _on_landed():
	var was_airborne = current_jumps > 0
	
	current_jumps = 0
	coyote_timer = 0.0
	is_jumping = false
	jump_held_time = 0.0
	
	if was_airborne:
		emit_signal("landed")
		_play_land_effects()

func _play_jump_effects():
	if current_jumps == 1:
		if jump_particles:
			jump_particles.emitting = true
			jump_particles.restart()
		
		if jump_sound:
			jump_sound.play()
	else:
		if double_jump_particles:
			double_jump_particles.emitting = true
			double_jump_particles.restart()
		
		if double_jump_sound:
			double_jump_sound.play()

func _play_land_effects():
	if land_sound:
		var fall_speed = abs(get_parent().velocity.y)
		land_sound.volume_db = -20 + min(fall_speed, 20)
		land_sound.play()

func add_extra_jump():
	max_jumps += 1

func remove_extra_jump():
	max_jumps = max(1, max_jumps - 1)
	if current_jumps >= max_jumps:
		current_jumps = max_jumps

func reset_jumps():
	current_jumps = 0

func get_jumps_remaining():
	return max_jumps - current_jumps

func set_max_jumps(jumps):
	max_jumps = max(1, jumps)

func force_jump(force):
	get_parent().velocity.y = force
	current_jumps = min(current_jumps + 1, max_jumps)
	is_jumping = true
	
	_play_jump_effects()
	emit_signal("jumped", current_jumps)

func is_in_coyote_time():
	return coyote_timer > 0

func has_jump_buffered():
	return jump_buffer_timer > 0

func get_jump_charge():
	if not is_jumping:
		return 0.0
	return min(jump_held_time / 0.2, 1.0)

func reset():
	current_jumps = 0
	coyote_timer = 0.0
	jump_buffer_timer = 0.0
	is_jumping = false
	jump_held_time = 0.0