extends CharacterBody2D

@export var move_speed: float = 300.0
@export var jump_velocity: float = -400.0
@export var acceleration: float = 10.0
@export var friction: float = 10.0
@export var gravity_multiplier: float = 1.0

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var double_jump_available: bool = true
var is_dashing: bool = false
var dash_speed: float = 600.0
var dash_duration: float = 0.2
var dash_cooldown: float = 1.0
var can_dash: bool = true

@onready var sprite: Sprite2D = $Sprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var coyote_timer: Timer = $CoyoteTimer
@onready var dash_timer: Timer = $DashTimer
@onready var dash_cooldown_timer: Timer = $DashCooldownTimer

func _ready():
	coyote_timer.timeout.connect(_on_coyote_timeout)
	dash_timer.timeout.connect(_on_dash_timeout)
	dash_cooldown_timer.timeout.connect(_on_dash_cooldown_timeout)

func _physics_process(delta):
	if not is_on_floor():
		velocity.y += gravity * gravity_multiplier * delta
		
		if coyote_timer.is_stopped() and double_jump_available:
			coyote_timer.start(0.1)
	else:
		double_jump_available = true
		coyote_timer.stop()
	
	if not is_dashing:
		handle_movement(delta)
		handle_jump()
		handle_dash()
	
	move_and_slide()
	update_animations()

func handle_movement(delta):
	var input_dir = Input.get_axis("move_left", "move_right")
	
	if input_dir != 0:
		velocity.x = move_toward(velocity.x, input_dir * move_speed, acceleration * move_speed * delta)
		sprite.flip_h = input_dir < 0
	else:
		velocity.x = move_toward(velocity.x, 0, friction * move_speed * delta)

func handle_jump():
	if Input.is_action_just_pressed("jump"):
		if is_on_floor() or not coyote_timer.is_stopped():
			velocity.y = jump_velocity
			coyote_timer.stop()
		elif double_jump_available:
			velocity.y = jump_velocity
			double_jump_available = false

func handle_dash():
	if Input.is_action_just_pressed("dash") and can_dash:
		is_dashing = true
		can_dash = false
		
		var dash_direction = Vector2.ZERO
		dash_direction.x = Input.get_axis("move_left", "move_right")
		dash_direction.y = Input.get_axis("move_up", "move_down")
		
		if dash_direction.length() == 0:
			dash_direction.x = 1 if not sprite.flip_h else -1
		
		dash_direction = dash_direction.normalized()
		velocity = dash_direction * dash_speed
		
		dash_timer.start(dash_duration)
		dash_cooldown_timer.start(dash_cooldown)

func update_animations():
	if not animation_player:
		return
		
	if is_dashing:
		animation_player.play("dash")
	elif not is_on_floor():
		if velocity.y < 0:
			animation_player.play("jump")
		else:
			animation_player.play("fall")
	elif velocity.x != 0:
		animation_player.play("run")
	else:
		animation_player.play("idle")

func _on_coyote_timeout():
	pass

func _on_dash_timeout():
	is_dashing = false
	velocity *= 0.5

func _on_dash_cooldown_timeout():
	can_dash = true

func take_damage(amount: int):
	pass

func collect_item(item_type: String):
	pass