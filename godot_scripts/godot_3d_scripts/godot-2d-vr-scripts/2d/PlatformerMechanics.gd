extends Node

class_name PlatformerMechanics

signal coin_collected(amount: int)
signal checkpoint_reached(checkpoint_position: Vector2)
signal player_died()

@export var respawn_time: float = 1.5

var coins_collected: int = 0
var current_checkpoint: Vector2
var player: CharacterBody2D

func setup_player(player_node: CharacterBody2D):
	player = player_node
	current_checkpoint = player.global_position

func collect_coin(value: int = 1):
	coins_collected += value
	coin_collected.emit(value)

func reach_checkpoint(checkpoint_pos: Vector2):
	current_checkpoint = checkpoint_pos
	checkpoint_reached.emit(checkpoint_pos)

func handle_player_death():
	player_died.emit()
	player.set_physics_process(false)
	player.hide()
	
	await player.get_tree().create_timer(respawn_time).timeout
	respawn_player()

func respawn_player():
	player.global_position = current_checkpoint
	player.velocity = Vector2.ZERO
	player.show()
	player.set_physics_process(true)

class MovingPlatform extends CharacterBody2D:
	@export var move_speed: float = 100.0
	@export var move_distance: float = 200.0
	@export var move_direction: Vector2 = Vector2.RIGHT
	@export var pause_duration: float = 1.0
	
	var start_position: Vector2
	var end_position: Vector2
	var moving_forward: bool = true
	var is_paused: bool = false
	
	func _ready():
		start_position = global_position
		end_position = start_position + (move_direction.normalized() * move_distance)
	
	func _physics_process(delta):
		if is_paused:
			return
		
		var target_pos = end_position if moving_forward else start_position
		var direction = (target_pos - global_position).normalized()
		
		velocity = direction * move_speed
		move_and_slide()
		
		if global_position.distance_to(target_pos) < 5.0:
			moving_forward = !moving_forward
			pause_movement()
	
	func pause_movement():
		is_paused = true
		await get_tree().create_timer(pause_duration).timeout
		is_paused = false

class SpringPad extends Area2D:
	@export var spring_force: float = -800.0
	@export var animation_player_path: NodePath
	
	var animation_player: AnimationPlayer
	
	func _ready():
		if animation_player_path:
			animation_player = get_node(animation_player_path)
		body_entered.connect(_on_body_entered)
	
	func _on_body_entered(body):
		if body.has_method("apply_spring_force"):
			body.apply_spring_force(spring_force)
		elif body is CharacterBody2D:
			body.velocity.y = spring_force
		
		if animation_player:
			animation_player.play("spring")

class Collectible extends Area2D:
	@export var coin_value: int = 1
	@export var collect_sound: AudioStream
	@export var particle_effect_scene: PackedScene
	
	signal collected()
	
	func _ready():
		body_entered.connect(_on_body_entered)
	
	func _on_body_entered(body):
		if body.is_in_group("player"):
			collected.emit()
			
			if particle_effect_scene:
				var particles = particle_effect_scene.instantiate()
				get_parent().add_child(particles)
				particles.global_position = global_position
			
			if collect_sound:
				var audio_player = AudioStreamPlayer2D.new()
				get_parent().add_child(audio_player)
				audio_player.stream = collect_sound
				audio_player.global_position = global_position
				audio_player.play()
				audio_player.finished.connect(audio_player.queue_free)
			
			queue_free()

class Hazard extends Area2D:
	@export var damage_amount: int = 1
	@export var knockback_force: float = 300.0
	
	func _ready():
		body_entered.connect(_on_body_entered)
	
	func _on_body_entered(body):
		if body.has_method("take_damage"):
			body.take_damage(damage_amount)
			
			if body is CharacterBody2D:
				var knockback_dir = (body.global_position - global_position).normalized()
				body.velocity = knockback_dir * knockback_force