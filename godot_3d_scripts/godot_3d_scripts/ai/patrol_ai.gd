extends KinematicBody

export var patrol_speed = 3.0
export var run_speed = 8.0
export var rotation_speed = 3.0
export var wait_time = 2.0
export var detection_range = 10.0
export var memory_time = 5.0

var velocity = Vector3.ZERO
var gravity = -9.8

var patrol_points = []
var current_patrol_index = 0
var wait_timer = 0.0
var is_waiting = false

var last_known_position = Vector3.ZERO
var memory_timer = 0.0
var has_seen_target = false

var current_target = null

enum PatrolMode {
	LOOP,
	PING_PONG,
	RANDOM
}

export var patrol_mode = PatrolMode.LOOP
var patrol_direction = 1

onready var nav_agent = $NavigationAgent
onready var vision_cast = $VisionCast
onready var detection_area = $DetectionArea

signal target_spotted(target)
signal target_lost(target)
signal reached_patrol_point(index)

func _ready():
	detection_area.connect("body_entered", self, "_on_detection_area_entered")
	detection_area.connect("body_exited", self, "_on_detection_area_exited")
	_collect_patrol_points()

func _physics_process(delta):
	if current_target:
		_pursue_target(delta)
	elif has_seen_target and memory_timer > 0:
		_search_last_position(delta)
	else:
		_patrol(delta)
	
	velocity.y += gravity * delta
	velocity = move_and_slide(velocity, Vector3.UP)
	
	if memory_timer > 0:
		memory_timer -= delta
		if memory_timer <= 0:
			has_seen_target = false

func _patrol(delta):
	if patrol_points.empty():
		velocity.x = 0
		velocity.z = 0
		return
	
	if is_waiting:
		wait_timer -= delta
		velocity.x = 0
		velocity.z = 0
		
		if wait_timer <= 0:
			is_waiting = false
			_get_next_patrol_point()
		return
	
	var target_point = patrol_points[current_patrol_index]
	nav_agent.set_target_location(target_point)
	
	var distance_to_target = global_transform.origin.distance_to(target_point)
	
	if distance_to_target < 1.0:
		emit_signal("reached_patrol_point", current_patrol_index)
		is_waiting = true
		wait_timer = wait_time
		return
	
	var next_location = nav_agent.get_next_location()
	var direction = (next_location - global_transform.origin).normalized()
	
	velocity.x = direction.x * patrol_speed
	velocity.z = direction.z * patrol_speed
	
	_rotate_towards(direction, delta)

func _get_next_patrol_point():
	match patrol_mode:
		PatrolMode.LOOP:
			current_patrol_index = (current_patrol_index + 1) % patrol_points.size()
		
		PatrolMode.PING_PONG:
			current_patrol_index += patrol_direction
			if current_patrol_index >= patrol_points.size() - 1:
				current_patrol_index = patrol_points.size() - 1
				patrol_direction = -1
			elif current_patrol_index <= 0:
				current_patrol_index = 0
				patrol_direction = 1
		
		PatrolMode.RANDOM:
			var new_index = randi() % patrol_points.size()
			while new_index == current_patrol_index and patrol_points.size() > 1:
				new_index = randi() % patrol_points.size()
			current_patrol_index = new_index

func _pursue_target(delta):
	if not is_instance_valid(current_target):
		current_target = null
		return
	
	if _can_see_target():
		last_known_position = current_target.global_transform.origin
		memory_timer = memory_time
		has_seen_target = true
		
		nav_agent.set_target_location(last_known_position)
		var next_location = nav_agent.get_next_location()
		var direction = (next_location - global_transform.origin).normalized()
		
		velocity.x = direction.x * run_speed
		velocity.z = direction.z * run_speed
		
		_rotate_towards(direction, delta)
	else:
		current_target = null
		emit_signal("target_lost", current_target)

func _search_last_position(delta):
	var distance_to_last_pos = global_transform.origin.distance_to(last_known_position)
	
	if distance_to_last_pos < 1.0:
		memory_timer = 0
		has_seen_target = false
		return
	
	nav_agent.set_target_location(last_known_position)
	var next_location = nav_agent.get_next_location()
	var direction = (next_location - global_transform.origin).normalized()
	
	velocity.x = direction.x * patrol_speed * 1.5
	velocity.z = direction.z * patrol_speed * 1.5
	
	_rotate_towards(direction, delta)

func _can_see_target() -> bool:
	if not is_instance_valid(current_target):
		return false
	
	var target_pos = current_target.global_transform.origin + Vector3(0, 1, 0)
	var my_pos = global_transform.origin + Vector3(0, 1.5, 0)
	var direction = (target_pos - my_pos).normalized()
	
	vision_cast.cast_to = direction * detection_range
	vision_cast.force_raycast_update()
	
	if vision_cast.is_colliding():
		var collider = vision_cast.get_collider()
		return collider == current_target
	
	return false

func _rotate_towards(direction: Vector3, delta: float):
	if direction.length() < 0.01:
		return
	
	direction.y = 0
	var target_transform = transform.looking_at(global_transform.origin - direction, Vector3.UP)
	transform.basis = transform.basis.slerp(target_transform.basis, rotation_speed * delta)

func _on_detection_area_entered(body):
	if body.is_in_group("player") and not current_target:
		if _can_see_target_body(body):
			current_target = body
			emit_signal("target_spotted", body)

func _on_detection_area_exited(body):
	if body == current_target:
		memory_timer = memory_time
		last_known_position = body.global_transform.origin

func _can_see_target_body(body) -> bool:
	var target_pos = body.global_transform.origin + Vector3(0, 1, 0)
	var my_pos = global_transform.origin + Vector3(0, 1.5, 0)
	var direction = (target_pos - my_pos).normalized()
	
	vision_cast.cast_to = direction * detection_range
	vision_cast.force_raycast_update()
	
	if vision_cast.is_colliding():
		var collider = vision_cast.get_collider()
		return collider == body
	
	return false

func _collect_patrol_points():
	var parent = get_parent()
	for child in parent.get_children():
		if child.is_in_group("patrol_point"):
			patrol_points.append(child.global_transform.origin)
	
	if patrol_points.empty():
		for i in range(4):
			var angle = i * PI * 0.5
			var offset = Vector3(cos(angle), 0, sin(angle)) * 10
			patrol_points.append(global_transform.origin + offset)

func add_patrol_point(position: Vector3):
	patrol_points.append(position)

func clear_patrol_points():
	patrol_points.clear()
	current_patrol_index = 0

func set_patrol_mode(mode: int):
	patrol_mode = mode
	if mode == PatrolMode.RANDOM:
		randomize()