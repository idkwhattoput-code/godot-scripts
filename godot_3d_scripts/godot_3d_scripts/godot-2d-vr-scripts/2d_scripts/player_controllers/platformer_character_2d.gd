extends KinematicBody2D

export var move_speed: float = 300.0
export var jump_height: float = -600.0
export var gravity: float = 2000.0
export var wall_jump_push: float = 300.0
export var max_jumps: int = 2
export var coyote_time: float = 0.1
export var jump_buffer_time: float = 0.1

var velocity: Vector2 = Vector2.ZERO
var jump_count: int = 0
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var was_on_floor: bool = false
var is_wall_sliding: bool = false

onready var sprite: Sprite = $Sprite
onready var animation_player: AnimationPlayer = $AnimationPlayer
onready var wall_check_left: RayCast2D = $WallCheckLeft
onready var wall_check_right: RayCast2D = $WallCheckRight

func _physics_process(delta: float) -> void:
	var input_direction: float = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	
	if not is_on_floor():
		velocity.y += gravity * delta
		
		if was_on_floor and coyote_timer > 0:
			coyote_timer -= delta
	else:
		jump_count = 0
		coyote_timer = coyote_time
	
	if Input.is_action_just_pressed("ui_up"):
		jump_buffer_timer = jump_buffer_time
	
	if jump_buffer_timer > 0:
		jump_buffer_timer -= delta
	
	check_wall_slide()
	
	if (is_on_floor() or coyote_timer > 0) and jump_buffer_timer > 0:
		jump()
	elif is_wall_sliding and Input.is_action_just_pressed("ui_up"):
		wall_jump(input_direction)
	elif jump_count < max_jumps and Input.is_action_just_pressed("ui_up"):
		jump()
	
	if input_direction != 0:
		velocity.x = move_toward(velocity.x, input_direction * move_speed, 50)
		
		if sprite:
			sprite.flip_h = input_direction < 0
	else:
		velocity.x = move_toward(velocity.x, 0, 50)
	
	if is_wall_sliding:
		velocity.y = min(velocity.y, 100)
	
	was_on_floor = is_on_floor()
	velocity = move_and_slide(velocity, Vector2.UP)
	
	update_animations()

func jump() -> void:
	velocity.y = jump_height
	jump_count += 1
	coyote_timer = 0.0
	jump_buffer_timer = 0.0

func wall_jump(input_dir: float) -> void:
	velocity.y = jump_height
	if wall_check_left and wall_check_left.is_colliding():
		velocity.x = wall_jump_push
	elif wall_check_right and wall_check_right.is_colliding():
		velocity.x = -wall_jump_push
	jump_count = 1

func check_wall_slide() -> void:
	if not is_on_floor() and velocity.y > 0:
		if wall_check_left and wall_check_left.is_colliding() and Input.is_action_pressed("ui_left"):
			is_wall_sliding = true
		elif wall_check_right and wall_check_right.is_colliding() and Input.is_action_pressed("ui_right"):
			is_wall_sliding = true
		else:
			is_wall_sliding = false
	else:
		is_wall_sliding = false

func update_animations() -> void:
	if not animation_player:
		return
	
	if is_on_floor():
		if abs(velocity.x) > 10:
			if animation_player.has_animation("run"):
				animation_player.play("run")
		else:
			if animation_player.has_animation("idle"):
				animation_player.play("idle")
	else:
		if is_wall_sliding:
			if animation_player.has_animation("wall_slide"):
				animation_player.play("wall_slide")
		elif velocity.y < 0:
			if animation_player.has_animation("jump"):
				animation_player.play("jump")
		else:
			if animation_player.has_animation("fall"):
				animation_player.play("fall")

func _ready() -> void:
	print("2D Platformer Character initialized")