extends Camera2D

export var follow_speed: float = 5.0
export var offset_push: float = 50.0
export var deadzone_width: float = 100.0
export var deadzone_height: float = 100.0
export var lookahead_distance: float = 150.0
export var lookahead_speed: float = 3.0
export var enable_limits: bool = true
export var shake_intensity: float = 0.0
export var shake_decay: float = 5.0

var target: Node2D = null
var shake_timer: float = 0.0
var shake_offset: Vector2 = Vector2.ZERO
var lookahead_offset: Vector2 = Vector2.ZERO

onready var limit_left_node: Position2D = get_node_or_null("../CameraLimits/LimitLeft")
onready var limit_right_node: Position2D = get_node_or_null("../CameraLimits/LimitRight")
onready var limit_top_node: Position2D = get_node_or_null("../CameraLimits/LimitTop")
onready var limit_bottom_node: Position2D = get_node_or_null("../CameraLimits/LimitBottom")

func _ready() -> void:
	set_physics_process(true)
	find_player()
	setup_camera_limits()
	
	current = true
	smoothing_enabled = true
	smoothing_speed = follow_speed

func find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		target = players[0]
		global_position = target.global_position
	else:
		target = get_parent()

func setup_camera_limits() -> void:
	if not enable_limits:
		return
	
	if limit_left_node:
		limit_left = int(limit_left_node.global_position.x)
	if limit_right_node:
		limit_right = int(limit_right_node.global_position.x)
	if limit_top_node:
		limit_top = int(limit_top_node.global_position.y)
	if limit_bottom_node:
		limit_bottom = int(limit_bottom_node.global_position.y)

func _physics_process(delta: float) -> void:
	if not target:
		return
	
	update_position(delta)
	update_lookahead(delta)
	update_shake(delta)
	
	offset = lookahead_offset + shake_offset

func update_position(delta: float) -> void:
	var target_pos: Vector2 = target.global_position
	var current_pos: Vector2 = global_position
	
	var distance: Vector2 = target_pos - current_pos
	
	if abs(distance.x) > deadzone_width:
		current_pos.x = lerp(current_pos.x, target_pos.x, follow_speed * delta)
	
	if abs(distance.y) > deadzone_height:
		current_pos.y = lerp(current_pos.y, target_pos.y, follow_speed * delta)
	
	global_position = current_pos

func update_lookahead(delta: float) -> void:
	if not target.has_method("get_velocity"):
		return
	
	var velocity: Vector2 = target.call("get_velocity") if target.has_method("get_velocity") else Vector2.ZERO
	
	if velocity.length() > 10:
		var target_lookahead: Vector2 = velocity.normalized() * lookahead_distance
		lookahead_offset = lookahead_offset.lerp(target_lookahead, lookahead_speed * delta)
	else:
		lookahead_offset = lookahead_offset.lerp(Vector2.ZERO, lookahead_speed * delta)

func update_shake(delta: float) -> void:
	if shake_timer > 0:
		shake_timer -= delta
		shake_offset = Vector2(
			rand_range(-shake_intensity, shake_intensity),
			rand_range(-shake_intensity, shake_intensity)
		)
		shake_intensity = lerp(shake_intensity, 0.0, shake_decay * delta)
	else:
		shake_offset = Vector2.ZERO
		shake_intensity = 0.0

func shake(duration: float, intensity: float) -> void:
	shake_timer = duration
	shake_intensity = intensity

func set_target(new_target: Node2D) -> void:
	target = new_target

func reset_position() -> void:
	if target:
		global_position = target.global_position
		lookahead_offset = Vector2.ZERO

func set_limits(left: float, top: float, right: float, bottom: float) -> void:
	limit_left = int(left)
	limit_top = int(top)
	limit_right = int(right)
	limit_bottom = int(bottom)