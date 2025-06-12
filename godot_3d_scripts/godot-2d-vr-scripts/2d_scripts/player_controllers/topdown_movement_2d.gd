extends KinematicBody2D

export var move_speed: float = 250.0
export var dash_speed: float = 600.0
export var dash_duration: float = 0.2
export var dash_cooldown: float = 1.0
export var acceleration: float = 10.0
export var friction: float = 10.0
export var rotation_speed: float = 10.0

var velocity: Vector2 = Vector2.ZERO
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector2 = Vector2.ZERO
var is_dashing: bool = false
var last_direction: Vector2 = Vector2.RIGHT

onready var sprite: Sprite = $Sprite
onready var animation_player: AnimationPlayer = $AnimationPlayer
onready var dash_particles: CPUParticles2D = $DashParticles

func _physics_process(delta: float) -> void:
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta
	
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false
			velocity = dash_direction * move_speed * 0.5
	else:
		handle_input(delta)
	
	velocity = move_and_slide(velocity)
	
	if velocity.length() > 10:
		last_direction = velocity.normalized()
		update_rotation(delta)
	
	update_animations()

func handle_input(delta: float) -> void:
	var input_vector: Vector2 = Vector2.ZERO
	
	input_vector.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	input_vector.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	
	if input_vector.length() > 1:
		input_vector = input_vector.normalized()
	
	if input_vector != Vector2.ZERO:
		velocity = velocity.lerp(input_vector * move_speed, acceleration * delta)
	else:
		velocity = velocity.lerp(Vector2.ZERO, friction * delta)
	
	if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0 and input_vector != Vector2.ZERO:
		start_dash(input_vector)

func start_dash(direction: Vector2) -> void:
	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	dash_direction = direction
	velocity = dash_direction * dash_speed
	
	if dash_particles:
		dash_particles.emitting = true
		dash_particles.direction = -dash_direction
	
	if animation_player and animation_player.has_animation("dash"):
		animation_player.play("dash")

func update_rotation(delta: float) -> void:
	var target_rotation: float = last_direction.angle()
	rotation = lerp_angle(rotation, target_rotation, rotation_speed * delta)

func update_animations() -> void:
	if not animation_player or is_dashing:
		return
	
	var speed: float = velocity.length()
	
	if speed > 10:
		if animation_player.has_animation("walk"):
			animation_player.play("walk")
			if animation_player.get("playback_speed"):
				animation_player.playback_speed = speed / move_speed
	else:
		if animation_player.has_animation("idle"):
			animation_player.play("idle")
			if animation_player.get("playback_speed"):
				animation_player.playback_speed = 1.0

func take_damage(amount: float, knockback_direction: Vector2 = Vector2.ZERO) -> void:
	if knockback_direction != Vector2.ZERO:
		velocity = knockback_direction * 400
	
	if animation_player and animation_player.has_animation("hurt"):
		animation_player.play("hurt")

func _ready() -> void:
	print("2D Top-down Movement Controller initialized")