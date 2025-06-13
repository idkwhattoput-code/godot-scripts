extends Spatial

export var hook_speed = 50.0
export var max_range = 30.0
export var pull_force = 20.0
export var swing_force = 15.0
export var rope_segments = 10
export var auto_retract = true
export var retract_speed = 2.0

var hook_point = null
var is_hooked = false
var is_retracting = false
var current_length = 0.0
var rope_points = []

onready var hook_mesh = $HookMesh
onready var rope_line = $RopeLine
onready var raycast = $RayCast
onready var hook_area = $HookArea
onready var attach_sound = $AttachSound
onready var retract_sound = $RetractSound
onready var launch_sound = $LaunchSound

signal hook_attached(point)
signal hook_detached()
signal hook_failed()

func _ready():
	_setup_hook()
	set_physics_process(false)

func _setup_hook():
	if not raycast:
		raycast = RayCast.new()
		add_child(raycast)
	
	raycast.enabled = true
	raycast.cast_to = Vector3(0, 0, -max_range)
	raycast.collision_mask = 1
	
	if hook_area:
		hook_area.connect("body_entered", self, "_on_hook_body_entered")

func _physics_process(delta):
	if is_hooked:
		_update_hooked_state(delta)
		_update_rope_visual()
	elif hook_point:
		_update_hook_flight(delta)

func launch_hook(target_position: Vector3 = Vector3.ZERO):
	if is_hooked:
		detach_hook()
		return
	
	var direction = Vector3.ZERO
	
	if target_position != Vector3.ZERO:
		direction = (target_position - global_transform.origin).normalized()
	else:
		direction = -global_transform.basis.z
	
	raycast.cast_to = direction * max_range
	raycast.force_raycast_update()
	
	if raycast.is_colliding():
		hook_point = raycast.get_collision_point()
		current_length = 0.0
		set_physics_process(true)
		
		if launch_sound:
			launch_sound.play()
	else:
		emit_signal("hook_failed")

func detach_hook():
	if not is_hooked:
		return
	
	is_hooked = false
	hook_point = null
	is_retracting = false
	set_physics_process(false)
	
	_clear_rope_visual()
	
	if retract_sound:
		retract_sound.play()
	
	emit_signal("hook_detached")

func _update_hook_flight(delta):
	if not hook_point:
		return
	
	var distance_to_hook = global_transform.origin.distance_to(hook_point)
	current_length += hook_speed * delta
	
	if current_length >= distance_to_hook:
		_attach_hook()
	
	_update_rope_visual()

func _attach_hook():
	is_hooked = true
	current_length = global_transform.origin.distance_to(hook_point)
	
	if attach_sound:
		attach_sound.play()
	
	emit_signal("hook_attached", hook_point)

func _update_hooked_state(delta):
	if not hook_point:
		return
	
	var player = get_parent()
	if not player:
		return
	
	var to_hook = hook_point - player.global_transform.origin
	var distance = to_hook.length()
	
	if distance > max_range * 1.2:
		detach_hook()
		return
	
	if is_retracting:
		current_length -= retract_speed * delta
		current_length = max(current_length, 2.0)
	
	if player.has_method("is_on_floor") and player.is_on_floor():
		_apply_ground_pull(player, to_hook, distance)
	else:
		_apply_swing_physics(player, to_hook, distance)
	
	if auto_retract and distance > current_length:
		is_retracting = true

func _apply_ground_pull(player, to_hook: Vector3, distance: float):
	if distance > current_length:
		var pull_direction = to_hook.normalized()
		
		if player.has_method("add_velocity"):
			player.add_velocity(pull_direction * pull_force)
		elif player.has("velocity"):
			player.velocity += pull_direction * pull_force

func _apply_swing_physics(player, to_hook: Vector3, distance: float):
	if distance > current_length:
		var correction_force = to_hook.normalized() * (distance - current_length) * 10.0
		
		if player.has_method("add_velocity"):
			player.add_velocity(correction_force)
		elif player.has("velocity"):
			player.velocity += correction_force
	
	var swing_right = to_hook.cross(Vector3.UP).normalized()
	var input_swing = 0.0
	
	if Input.is_action_pressed("move_left"):
		input_swing -= 1.0
	if Input.is_action_pressed("move_right"):
		input_swing += 1.0
	
	if input_swing != 0.0:
		if player.has_method("add_velocity"):
			player.add_velocity(swing_right * input_swing * swing_force)
		elif player.has("velocity"):
			player.velocity += swing_right * input_swing * swing_force
	
	if player.has("velocity"):
		var radial_velocity = player.velocity.project(to_hook.normalized())
		player.velocity -= radial_velocity * 0.5

func _update_rope_visual():
	if not rope_line or not hook_point:
		return
	
	rope_points.clear()
	var start_pos = Vector3.ZERO
	var end_pos = to_local(hook_point)
	
	for i in range(rope_segments + 1):
		var t = float(i) / float(rope_segments)
		var point = start_pos.linear_interpolate(end_pos, t)
		
		var sag = sin(t * PI) * 0.5 * (1.0 - (current_length / max_range))
		point.y -= sag
		
		rope_points.append(point)
	
	if rope_line.has_method("clear"):
		rope_line.clear()
		rope_line.begin(Mesh.PRIMITIVE_LINE_STRIP)
		
		for point in rope_points:
			rope_line.add_vertex(point)
		
		rope_line.end()

func _clear_rope_visual():
	if rope_line and rope_line.has_method("clear"):
		rope_line.clear()
	rope_points.clear()

func _on_hook_body_entered(body):
	if body != get_parent() and not is_hooked and hook_point:
		_attach_hook()

func set_hook_range(range: float):
	max_range = range
	if raycast:
		raycast.cast_to = Vector3(0, 0, -max_range)

func get_hook_point() -> Vector3:
	return hook_point if hook_point else Vector3.ZERO

func get_rope_length() -> float:
	return current_length

func is_attached() -> bool:
	return is_hooked

func start_retracting():
	if is_hooked:
		is_retracting = true

func stop_retracting():
	is_retracting = false

func get_swing_direction() -> Vector3:
	if not hook_point or not is_hooked:
		return Vector3.ZERO
	
	var to_hook = hook_point - global_transform.origin
	return to_hook.cross(Vector3.UP).normalized()