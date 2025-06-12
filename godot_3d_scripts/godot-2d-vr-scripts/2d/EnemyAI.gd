extends CharacterBody2D

enum AIState {
	IDLE,
	PATROL,
	CHASE,
	ATTACK,
	HURT,
	DEAD
}

@export var move_speed: float = 150.0
@export var chase_speed: float = 250.0
@export var detection_range: float = 200.0
@export var attack_range: float = 50.0
@export var patrol_distance: float = 100.0
@export var max_health: int = 3
@export var attack_damage: int = 1
@export var attack_cooldown: float = 1.5
@export var hurt_knockback: float = 200.0
@export var gravity: float = 980.0

var current_state: AIState = AIState.IDLE
var health: int
var player: Node2D = null
var patrol_start: Vector2
var patrol_target: Vector2
var facing_direction: int = 1
var attack_timer: float = 0.0
var hurt_timer: float = 0.0
var detection_area: Area2D
var attack_area: Area2D

@onready var sprite: Sprite2D = $Sprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var state_timer: Timer = $StateTimer

signal enemy_died(enemy: Node2D)
signal player_damaged(damage: int)

func _ready():
	health = max_health
	patrol_start = global_position
	patrol_target = patrol_start + Vector2(patrol_distance * facing_direction, 0)
	setup_detection_area()
	setup_attack_area()
	change_state(AIState.PATROL)

func _physics_process(delta):
	apply_gravity(delta)
	update_timers(delta)
	
	match current_state:
		AIState.IDLE:
			handle_idle_state()
		AIState.PATROL:
			handle_patrol_state(delta)
		AIState.CHASE:
			handle_chase_state(delta)
		AIState.ATTACK:
			handle_attack_state()
		AIState.HURT:
			handle_hurt_state(delta)
		AIState.DEAD:
			handle_dead_state()
	
	move_and_slide()
	update_sprite_direction()
	update_animations()

func apply_gravity(delta):
	if not is_on_floor():
		velocity.y += gravity * delta

func update_timers(delta):
	if attack_timer > 0:
		attack_timer -= delta
	if hurt_timer > 0:
		hurt_timer -= delta

func handle_idle_state():
	velocity.x = 0
	
	if player and is_player_in_detection_range():
		change_state(AIState.CHASE)
	elif state_timer.is_stopped():
		change_state(AIState.PATROL)

func handle_patrol_state(delta):
	var direction = (patrol_target - global_position).normalized()
	velocity.x = direction.x * move_speed
	
	if global_position.distance_to(patrol_target) < 10:
		patrol_target = patrol_start if patrol_target.distance_to(patrol_start) > 50 else patrol_start + Vector2(patrol_distance * facing_direction, 0)
		facing_direction *= -1
	
	if player and is_player_in_detection_range():
		change_state(AIState.CHASE)

func handle_chase_state(delta):
	if not player or not is_player_in_detection_range():
		change_state(AIState.PATROL)
		return
	
	if is_player_in_attack_range():
		change_state(AIState.ATTACK)
		return
	
	var direction = (player.global_position - global_position).normalized()
	velocity.x = direction.x * chase_speed
	facing_direction = 1 if direction.x > 0 else -1

func handle_attack_state():
	velocity.x = 0
	
	if attack_timer <= 0:
		perform_attack()
		attack_timer = attack_cooldown
		
		if not is_player_in_attack_range():
			change_state(AIState.CHASE)

func handle_hurt_state(delta):
	velocity.x = lerp(velocity.x, 0.0, 5.0 * delta)
	
	if hurt_timer <= 0:
		if health <= 0:
			change_state(AIState.DEAD)
		else:
			change_state(AIState.CHASE if player and is_player_in_detection_range() else AIState.PATROL)

func handle_dead_state():
	velocity.x = 0

func change_state(new_state: AIState):
	current_state = new_state
	
	match new_state:
		AIState.IDLE:
			state_timer.start(randf_range(1.0, 3.0))
		AIState.HURT:
			hurt_timer = 0.5
		AIState.DEAD:
			set_collision_layer_value(1, false)
			set_collision_mask_value(1, false)

func is_player_in_detection_range() -> bool:
	return player and global_position.distance_to(player.global_position) <= detection_range

func is_player_in_attack_range() -> bool:
	return player and global_position.distance_to(player.global_position) <= attack_range

func perform_attack():
	if player and is_player_in_attack_range():
		if player.has_method("take_damage"):
			player.take_damage(attack_damage)
			player_damaged.emit(attack_damage)

func take_damage(amount: int, knockback_direction: Vector2 = Vector2.ZERO):
	if current_state == AIState.DEAD:
		return
	
	health -= amount
	
	if knockback_direction != Vector2.ZERO:
		velocity += knockback_direction * hurt_knockback
	
	change_state(AIState.HURT)
	
	if health <= 0:
		die()

func die():
	change_state(AIState.DEAD)
	enemy_died.emit(self)

func setup_detection_area():
	detection_area = Area2D.new()
	add_child(detection_area)
	
	var detection_shape = CollisionShape2D.new()
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = detection_range
	detection_shape.shape = circle_shape
	detection_area.add_child(detection_shape)
	
	detection_area.body_entered.connect(_on_detection_area_body_entered)
	detection_area.body_exited.connect(_on_detection_area_body_exited)

func setup_attack_area():
	attack_area = Area2D.new()
	add_child(attack_area)
	
	var attack_shape = CollisionShape2D.new()
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = attack_range
	attack_shape.shape = circle_shape
	attack_area.add_child(attack_shape)

func _on_detection_area_body_entered(body):
	if body.is_in_group("player"):
		player = body

func _on_detection_area_body_exited(body):
	if body == player:
		player = null

func update_sprite_direction():
	if sprite:
		sprite.flip_h = facing_direction < 0

func update_animations():
	if not animation_player:
		return
	
	match current_state:
		AIState.IDLE:
			animation_player.play("idle")
		AIState.PATROL, AIState.CHASE:
			if abs(velocity.x) > 10:
				animation_player.play("walk")
			else:
				animation_player.play("idle")
		AIState.ATTACK:
			animation_player.play("attack")
		AIState.HURT:
			animation_player.play("hurt")
		AIState.DEAD:
			animation_player.play("death")

func get_current_state() -> AIState:
	return current_state

func set_player_target(target: Node2D):
	player = target