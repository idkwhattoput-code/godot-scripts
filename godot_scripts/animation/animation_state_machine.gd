extends AnimationTree

# Advanced Animation State Machine for Godot 3D
# Manages complex character animations with blending and transitions
# Supports movement, combat, and interaction animations

# Animation parameters
export var blend_time = 0.2
export var root_motion_enabled = true
export var animation_speed_scale = 1.0

# Movement animations
export var idle_animation = "idle"
export var walk_animation = "walk"
export var run_animation = "run"
export var sprint_animation = "sprint"
export var crouch_idle_animation = "crouch_idle"
export var crouch_walk_animation = "crouch_walk"

# Jump animations
export var jump_start_animation = "jump_start"
export var jump_loop_animation = "jump_loop"
export var jump_land_animation = "jump_land"
export var fall_animation = "fall"

# Combat animations
export var aim_animation = "aim"
export var shoot_animation = "shoot"
export var reload_animation = "reload"
export var melee_animations = ["melee_1", "melee_2", "melee_3"]
export var hit_animations = ["hit_front", "hit_back", "hit_left", "hit_right"]
export var death_animations = ["death_1", "death_2"]

# State variables
var current_state = "idle"
var previous_state = "idle"
var movement_speed = 0.0
var is_grounded = true
var is_crouching = false
var is_aiming = false
var is_attacking = false
var combo_counter = 0
var combo_timer = 0.0

# Animation layers
var base_layer = "parameters/base_layer/"
var upper_body_layer = "parameters/upper_body/"
var additive_layer = "parameters/additive/"

# Blend space positions
var movement_blend_position = Vector2.ZERO
var aim_blend_position = Vector2.ZERO

# References
var character: Spatial
var animation_player: AnimationPlayer

func _ready():
	# Get references
	character = get_parent()
	animation_player = get_node(anim_player) if has_property("anim_player") else null
	
	# Setup animation tree
	active = true
	
	# Initialize state machine
	set_state("idle")

func _physics_process(delta):
	# Update combo timer
	if combo_timer > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			combo_counter = 0
	
	# Update animation parameters
	update_animation_parameters()
	
	# Handle state transitions
	update_state_machine()

func update_animation_parameters():
	"""Update animation tree parameters based on character state"""
	# Movement blend
	if has_parameter("movement/blend_position"):
		set("parameters/movement/blend_position", movement_blend_position)
	
	# Speed parameter for blend trees
	if has_parameter("speed"):
		set("parameters/speed", movement_speed)
	
	# Crouch parameter
	if has_parameter("is_crouching"):
		set("parameters/is_crouching", is_crouching)
	
	# Aim blend
	if has_parameter("aim/blend_position"):
		set("parameters/aim/blend_position", aim_blend_position)
	
	# Animation speed
	if has_parameter("time_scale"):
		set("parameters/time_scale", animation_speed_scale)

func update_state_machine():
	"""Handle state transitions based on character state"""
	var new_state = determine_state()
	
	if new_state != current_state:
		transition_to_state(new_state)

func determine_state() -> String:
	"""Determine which state the character should be in"""
	# Death state has highest priority
	if current_state.begins_with("death"):
		return current_state
	
	# Combat states
	if is_attacking:
		return current_state  # Keep current attack state
	
	if is_aiming:
		if movement_speed > 0.1:
			return "aim_walk"
		else:
			return "aim_idle"
	
	# Airborne states
	if not is_grounded:
		if get_vertical_velocity() > 0.5:
			return "jump"
		else:
			return "fall"
	
	# Ground movement states
	if is_crouching:
		if movement_speed > 0.1:
			return "crouch_walk"
		else:
			return "crouch_idle"
	else:
		if movement_speed > 8.0:
			return "sprint"
		elif movement_speed > 4.0:
			return "run"
		elif movement_speed > 0.1:
			return "walk"
		else:
			return "idle"

func transition_to_state(new_state: String):
	"""Transition to a new animation state"""
	previous_state = current_state
	current_state = new_state
	
	# Play appropriate animation based on state
	match new_state:
		"idle":
			play_animation(idle_animation)
		"walk":
			play_animation(walk_animation)
		"run":
			play_animation(run_animation)
		"sprint":
			play_animation(sprint_animation)
		"crouch_idle":
			play_animation(crouch_idle_animation)
		"crouch_walk":
			play_animation(crouch_walk_animation)
		"jump":
			play_animation(jump_start_animation)
			yield(get_tree().create_timer(0.2), "timeout")
			if current_state == "jump":
				play_animation(jump_loop_animation, true)
		"fall":
			play_animation(fall_animation, true)
		"aim_idle":
			play_animation(aim_animation)
		"aim_walk":
			play_animation(aim_animation)
			# Blend with walk animation
		_:
			# Handle combat states
			if new_state.begins_with("attack"):
				handle_attack_state(new_state)
			elif new_state.begins_with("hit"):
				handle_hit_state(new_state)
			elif new_state.begins_with("death"):
				handle_death_state(new_state)

func play_animation(anim_name: String, loop: bool = true):
	"""Play an animation through the animation tree"""
	if has_parameter("current_animation"):
		set("parameters/current_animation", anim_name)
	
	# Set loop mode
	if animation_player and animation_player.has_animation(anim_name):
		var animation = animation_player.get_animation(anim_name)
		animation.loop = loop

func handle_attack_state(state: String):
	"""Handle attack animation states"""
	is_attacking = true
	
	match state:
		"attack_melee":
			var attack_anim = melee_animations[combo_counter % melee_animations.size()]
			play_animation(attack_anim, false)
			combo_counter += 1
			combo_timer = 1.0  # Reset combo window
		"attack_shoot":
			play_animation(shoot_animation, false)
		"attack_reload":
			play_animation(reload_animation, false)
	
	# Return to previous state after animation
	yield(get_tree().create_timer(get_animation_length(current_state)), "timeout")
	is_attacking = false
	transition_to_state(determine_state())

func handle_hit_state(state: String):
	"""Handle hit reaction animations"""
	var direction_index = int(state.split("_")[1])
	if direction_index < hit_animations.size():
		play_animation(hit_animations[direction_index], false)
	
	# Return to idle after hit
	yield(get_tree().create_timer(0.5), "timeout")
	transition_to_state("idle")

func handle_death_state(state: String):
	"""Handle death animations"""
	var death_index = randi() % death_animations.size()
	play_animation(death_animations[death_index], false)
	
	# Disable further state changes
	set_physics_process(false)

# Public methods for character controller
func set_movement_speed(speed: float):
	"""Set the character's movement speed"""
	movement_speed = speed

func set_movement_direction(direction: Vector2):
	"""Set movement direction for strafing animations"""
	movement_blend_position = direction

func set_grounded(grounded: bool):
	"""Set whether character is on ground"""
	var was_airborne = not is_grounded
	is_grounded = grounded
	
	# Handle landing
	if grounded and was_airborne:
		transition_to_state("land")
		yield(get_tree().create_timer(0.3), "timeout")
		transition_to_state(determine_state())

func set_crouching(crouching: bool):
	"""Set crouch state"""
	is_crouching = crouching

func set_aiming(aiming: bool, aim_direction: Vector2 = Vector2.ZERO):
	"""Set aiming state"""
	is_aiming = aiming
	aim_blend_position = aim_direction

func play_attack(attack_type: String = "melee"):
	"""Trigger an attack animation"""
	match attack_type:
		"melee":
			transition_to_state("attack_melee")
		"shoot":
			transition_to_state("attack_shoot")
		"reload":
			transition_to_state("attack_reload")

func play_hit_reaction(hit_direction: Vector3):
	"""Play hit reaction based on hit direction"""
	# Calculate hit direction relative to character
	var local_dir = character.global_transform.basis.xform_inv(hit_direction)
	var angle = atan2(local_dir.x, local_dir.z)
	
	var direction_index = 0
	if abs(angle) < PI / 4:
		direction_index = 0  # Front
	elif abs(angle) > 3 * PI / 4:
		direction_index = 1  # Back
	elif angle > 0:
		direction_index = 2  # Right
	else:
		direction_index = 3  # Left
	
	transition_to_state("hit_" + str(direction_index))

func play_death():
	"""Play death animation"""
	transition_to_state("death")

func get_animation_length(anim_name: String) -> float:
	"""Get the length of an animation"""
	if animation_player and animation_player.has_animation(anim_name):
		return animation_player.get_animation(anim_name).length
	return 1.0

func get_vertical_velocity() -> float:
	"""Get character's vertical velocity"""
	if character.has_method("get_velocity"):
		return character.get_velocity().y
	return 0.0

func has_parameter(param_name: String) -> bool:
	"""Check if animation tree has a parameter"""
	# This is a helper method - implement based on your AnimationTree setup
	return true

# Root motion extraction
func get_root_motion_transform() -> Transform:
	"""Get root motion transform for this frame"""
	if root_motion_enabled and has_method("get_root_motion_transform"):
		return .get_root_motion_transform()
	return Transform()

func apply_root_motion(delta: float):
	"""Apply root motion to character"""
	if not root_motion_enabled:
		return
	
	var root_motion = get_root_motion_transform()
	if character.has_method("apply_root_motion"):
		character.apply_root_motion(root_motion, delta)