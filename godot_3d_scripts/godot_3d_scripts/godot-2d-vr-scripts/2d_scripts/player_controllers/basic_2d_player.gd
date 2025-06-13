extends KinematicBody2D

export var move_speed: float = 200.0
export var acceleration: float = 500.0
export var friction: float = 500.0

var velocity: Vector2 = Vector2.ZERO

onready var sprite: Sprite = $Sprite
onready var animation_player: AnimationPlayer = $AnimationPlayer

func _physics_process(delta: float) -> void:
	var input_vector: Vector2 = Vector2.ZERO
	
	input_vector.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	input_vector.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	input_vector = input_vector.normalized()
	
	if input_vector != Vector2.ZERO:
		velocity = velocity.move_toward(input_vector * move_speed, acceleration * delta)
		
		if animation_player and animation_player.has_animation("walk"):
			animation_player.play("walk")
		
		if sprite:
			if input_vector.x < 0:
				sprite.flip_h = true
			elif input_vector.x > 0:
				sprite.flip_h = false
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		
		if animation_player and animation_player.has_animation("idle"):
			animation_player.play("idle")
	
	velocity = move_and_slide(velocity)

func _ready() -> void:
	print("2D Player Controller initialized")