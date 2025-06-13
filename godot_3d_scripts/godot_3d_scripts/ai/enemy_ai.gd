extends KinematicBody

export var move_speed = 5.0
export var rotation_speed = 2.0
export var detection_range = 15.0
export var attack_range = 2.0
export var health = 100.0
export var damage = 10.0
export var attack_cooldown = 1.5

var velocity = Vector3.ZERO
var gravity = -9.8
var current_target = null
var last_attack_time = 0.0

enum State {
	IDLE,
	PATROL,
	CHASE,
	ATTACK,
	DEAD
}

var current_state = State.IDLE
var patrol_points = []
var current_patrol_index = 0

onready var detection_area = $DetectionArea
onready var attack_timer = $AttackTimer
onready var nav_agent = $NavigationAgent

func _ready():
	detection_area.connect("body_entered", self, "_on_detection_area_entered")
	detection_area.connect("body_exited", self, "_on_detection_area_exited")
	_setup_patrol_points()

func _physics_process(delta):
	match current_state:
		State.IDLE:
			_idle_behavior(delta)
		State.PATROL:
			_patrol_behavior(delta)
		State.CHASE:
			_chase_behavior(delta)
		State.ATTACK:
			_attack_behavior(delta)
		State.DEAD:
			return
	
	velocity.y += gravity * delta
	velocity = move_and_slide(velocity, Vector3.UP)

func _idle_behavior(delta):
	velocity.x = 0
	velocity.z = 0
	
	if patrol_points.size() > 0:
		current_state = State.PATROL

func _patrol_behavior(delta):
	if patrol_points.empty():
		return
	
	var target_pos = patrol_points[current_patrol_index]
	nav_agent.set_target_location(target_pos)
	
	if global_transform.origin.distance_to(target_pos) < 1.0:
		current_patrol_index = (current_patrol_index + 1) % patrol_points.size()
		return
	
	var next_location = nav_agent.get_next_location()
	var direction = (next_location - global_transform.origin).normalized()
	
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	
	_rotate_towards(direction, delta)

func _chase_behavior(delta):
	if not is_instance_valid(current_target):
		current_state = State.PATROL
		return
	
	var distance_to_target = global_transform.origin.distance_to(current_target.global_transform.origin)
	
	if distance_to_target <= attack_range:
		current_state = State.ATTACK
		return
	elif distance_to_target > detection_range * 1.5:
		current_target = null
		current_state = State.PATROL
		return
	
	nav_agent.set_target_location(current_target.global_transform.origin)
	var next_location = nav_agent.get_next_location()
	var direction = (next_location - global_transform.origin).normalized()
	
	velocity.x = direction.x * move_speed * 1.5
	velocity.z = direction.z * move_speed * 1.5
	
	_rotate_towards(direction, delta)

func _attack_behavior(delta):
	if not is_instance_valid(current_target):
		current_state = State.PATROL
		return
	
	var distance_to_target = global_transform.origin.distance_to(current_target.global_transform.origin)
	
	if distance_to_target > attack_range:
		current_state = State.CHASE
		return
	
	velocity.x = 0
	velocity.z = 0
	
	var direction = (current_target.global_transform.origin - global_transform.origin).normalized()
	_rotate_towards(direction, delta)
	
	var current_time = OS.get_ticks_msec() / 1000.0
	if current_time - last_attack_time >= attack_cooldown:
		_perform_attack()
		last_attack_time = current_time

func _rotate_towards(direction: Vector3, delta: float):
	if direction.length() < 0.01:
		return
	
	var target_transform = transform.looking_at(global_transform.origin - direction, Vector3.UP)
	transform.basis = transform.basis.slerp(target_transform.basis, rotation_speed * delta)

func _perform_attack():
	if current_target and current_target.has_method("take_damage"):
		current_target.take_damage(damage)
	
	if has_node("AttackAnimation"):
		$AttackAnimation.play("attack")

func _on_detection_area_entered(body):
	if body.is_in_group("player") and current_state != State.DEAD:
		current_target = body
		current_state = State.CHASE

func _on_detection_area_exited(body):
	if body == current_target and current_state == State.CHASE:
		if global_transform.origin.distance_to(body.global_transform.origin) > detection_range * 1.2:
			current_target = null
			current_state = State.PATROL

func take_damage(amount):
	health -= amount
	
	if health <= 0 and current_state != State.DEAD:
		_die()
	elif current_state == State.IDLE or current_state == State.PATROL:
		current_state = State.CHASE

func _die():
	current_state = State.DEAD
	collision_layer = 0
	collision_mask = 0
	
	if has_node("DeathAnimation"):
		$DeathAnimation.play("death")
	
	yield(get_tree().create_timer(3.0), "timeout")
	queue_free()

func _setup_patrol_points():
	for child in get_parent().get_children():
		if child.is_in_group("patrol_point"):
			patrol_points.append(child.global_transform.origin)

func set_patrol_points(points: Array):
	patrol_points = points
	current_patrol_index = 0