extends Node2D

export var hook_speed = 1000.0
export var max_length = 500.0
export var retract_speed = 1200.0
export var swing_force = 300.0
export var rope_segments = 20
export var rope_color = Color(0.8, 0.8, 0.8)
export var hook_sprite : Texture
export var recharge_time = 0.5

signal hook_attached(target_pos)
signal hook_detached()
signal hook_retracted()

var hook_point = Vector2.ZERO
var is_hooked = false
var is_firing = false
var hook_body = null
var rope_points = []
var hook_velocity = Vector2.ZERO
var can_fire = true
var recharge_timer = 0.0

onready var hook_sprite_node = $HookSprite
onready var line_2d = $Line2D
onready var raycast = $RayCast2D
onready var hook_area = $HookArea
onready var fire_sound = $FireSound
onready var attach_sound = $AttachSound
onready var retract_sound = $RetractSound

func _ready():
	if not line_2d:
		line_2d = Line2D.new()
		line_2d.width = 4.0
		line_2d.default_color = rope_color
		add_child(line_2d)
	
	if not hook_sprite_node and hook_sprite:
		hook_sprite_node = Sprite.new()
		hook_sprite_node.texture = hook_sprite
		hook_sprite_node.visible = false
		add_child(hook_sprite_node)
	
	_initialize_rope_points()

func _physics_process(delta):
	if recharge_timer > 0:
		recharge_timer -= delta
		if recharge_timer <= 0:
			can_fire = true
	
	if is_firing:
		_update_hook_flight(delta)
	elif is_hooked:
		_update_rope_physics(delta)
		_apply_swing_physics()
	
	_update_visuals()

func _initialize_rope_points():
	rope_points.clear()
	for i in range(rope_segments):
		rope_points.append(global_position)

func fire_hook(target_direction):
	if not can_fire or is_hooked or is_firing:
		return false
	
	is_firing = true
	hook_velocity = target_direction.normalized() * hook_speed
	hook_point = global_position
	
	if hook_sprite_node:
		hook_sprite_node.visible = true
		hook_sprite_node.rotation = target_direction.angle()
	
	if fire_sound:
		fire_sound.play()
	
	return true

func _update_hook_flight(delta):
	hook_point += hook_velocity * delta
	
	var distance = global_position.distance_to(hook_point)
	
	if distance > max_length:
		retract_hook()
		return
	
	if raycast:
		raycast.cast_to = to_local(hook_point)
		raycast.force_raycast_update()
		
		if raycast.is_colliding():
			attach_hook(raycast.get_collision_point())

func attach_hook(target_pos):
	is_firing = false
	is_hooked = true
	hook_point = target_pos
	
	emit_signal("hook_attached", target_pos)
	
	if attach_sound:
		attach_sound.play()
	
	_initialize_rope_at_position()

func detach_hook():
	if not is_hooked:
		return
	
	is_hooked = false
	emit_signal("hook_detached")
	
	if hook_sprite_node:
		hook_sprite_node.visible = false
	
	can_fire = false
	recharge_timer = recharge_time

func retract_hook():
	if not is_hooked and not is_firing:
		return
	
	is_firing = false
	is_hooked = false
	
	if hook_sprite_node:
		hook_sprite_node.visible = false
	
	if retract_sound:
		retract_sound.play()
	
	emit_signal("hook_retracted")
	
	can_fire = false
	recharge_timer = recharge_time

func _initialize_rope_at_position():
	var distance = global_position.distance_to(hook_point)
	for i in range(rope_segments):
		var t = float(i) / float(rope_segments - 1)
		rope_points[i] = global_position.linear_interpolate(hook_point, t)

func _update_rope_physics(delta):
	rope_points[0] = global_position
	rope_points[rope_segments - 1] = hook_point
	
	for i in range(1, rope_segments - 1):
		var prev_point = rope_points[i - 1]
		var curr_point = rope_points[i]
		var next_point = rope_points[i + 1]
		
		var gravity = Vector2(0, 980 * delta)
		rope_points[i] += gravity
		
		var segment_length = max_length / float(rope_segments - 1)
		
		var to_prev = prev_point - curr_point
		var prev_dist = to_prev.length()
		if prev_dist > segment_length:
			rope_points[i] += to_prev.normalized() * (prev_dist - segment_length) * 0.5
		
		var to_next = next_point - curr_point
		var next_dist = to_next.length()
		if next_dist > segment_length:
			rope_points[i] += to_next.normalized() * (next_dist - segment_length) * 0.5

func _apply_swing_physics():
	if not get_parent().has_method("add_force"):
		return
	
	var to_hook = hook_point - global_position
	var distance = to_hook.length()
	
	if distance > max_length:
		var pull_direction = to_hook.normalized()
		get_parent().add_force(pull_direction * swing_force)
	
	var tangent = to_hook.rotated(PI/2).normalized()
	var player_velocity = Vector2.ZERO
	
	if get_parent().has_method("get_velocity"):
		player_velocity = get_parent().get_velocity()
	
	var swing_amount = player_velocity.dot(tangent)
	get_parent().add_force(tangent * swing_amount * 0.1)

func _update_visuals():
	if not line_2d:
		return
	
	line_2d.clear_points()
	
	if is_firing or is_hooked:
		if is_firing:
			line_2d.add_point(to_local(global_position))
			line_2d.add_point(to_local(hook_point))
		else:
			for point in rope_points:
				line_2d.add_point(to_local(point))
	
	if hook_sprite_node and hook_sprite_node.visible:
		hook_sprite_node.global_position = hook_point

func get_hook_direction():
	if is_hooked:
		return (hook_point - global_position).normalized()
	return Vector2.ZERO

func get_hook_distance():
	if is_hooked:
		return global_position.distance_to(hook_point)
	return 0.0

func is_attached():
	return is_hooked

func can_fire_hook():
	return can_fire and not is_hooked and not is_firing

func get_rope_tension():
	if not is_hooked:
		return 0.0
	
	var distance = get_hook_distance()
	return clamp((distance - max_length * 0.8) / (max_length * 0.2), 0.0, 1.0)

func set_hook_color(color):
	rope_color = color
	if line_2d:
		line_2d.default_color = color