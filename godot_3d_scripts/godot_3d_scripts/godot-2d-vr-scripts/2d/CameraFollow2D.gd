extends Camera2D

@export var follow_speed: float = 5.0
@export var offset_y: float = -50.0
@export var lookahead_distance: float = 100.0
@export var enable_smoothing: bool = true
@export var dead_zone_width: float = 100.0
@export var dead_zone_height: float = 60.0

@export_node_path("Node2D") var target_path: NodePath
var target: Node2D
var target_position: Vector2

func _ready():
	if target_path:
		target = get_node(target_path)
	
	position_smoothing_enabled = enable_smoothing
	position_smoothing_speed = follow_speed

func _process(delta):
	if not target:
		return
	
	var target_pos = target.global_position
	target_pos.y += offset_y
	
	if target.has_method("get_velocity"):
		var velocity = target.get_velocity()
		var lookahead = velocity.normalized() * lookahead_distance
		target_pos += lookahead
	
	var camera_pos = global_position
	var diff = target_pos - camera_pos
	
	if abs(diff.x) > dead_zone_width:
		camera_pos.x = target_pos.x - sign(diff.x) * dead_zone_width
	
	if abs(diff.y) > dead_zone_height:
		camera_pos.y = target_pos.y - sign(diff.y) * dead_zone_height
	
	if enable_smoothing:
		global_position = global_position.lerp(camera_pos, follow_speed * delta)
	else:
		global_position = camera_pos

func set_target(new_target: Node2D):
	target = new_target

func shake(duration: float = 0.2, strength: float = 10.0):
	var shake_tween = create_tween()
	var original_offset = offset
	
	for i in range(int(duration * 60)):
		var shake_offset = Vector2(
			randf_range(-strength, strength),
			randf_range(-strength, strength)
		)
		shake_tween.tween_property(self, "offset", original_offset + shake_offset, 1.0/60.0)
	
	shake_tween.tween_property(self, "offset", original_offset, 0.1)