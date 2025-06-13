extends Node

export var max_offset = Vector2(100, 75)
export var max_rotation = 0.1
export var trauma_reduction_speed = 1.0
export var noise_speed = 30.0
export var camera_path : NodePath

signal shake_started()
signal shake_ended()

var trauma = 0.0
var time = 0.0
var noise = OpenSimplexNoise.new()
var camera : Camera2D
var original_offset = Vector2.ZERO
var is_shaking = false

class ShakeProfile:
	var intensity : float = 1.0
	var duration : float = 0.5
	var frequency : float = 15.0
	var decay_curve : Curve
	var rotation_strength : float = 1.0
	var position_strength : float = 1.0
	
	func _init():
		decay_curve = Curve.new()
		decay_curve.add_point(Vector2(0, 1))
		decay_curve.add_point(Vector2(1, 0))

var active_shakes = []
var shake_profiles = {
	"light": _create_light_shake(),
	"medium": _create_medium_shake(),
	"heavy": _create_heavy_shake(),
	"explosion": _create_explosion_shake(),
	"earthquake": _create_earthquake_shake()
}

func _ready():
	if camera_path:
		camera = get_node(camera_path)
	else:
		camera = _find_camera()
	
	if camera:
		original_offset = camera.offset
	
	noise.seed = randi()
	noise.octaves = 4
	noise.period = 20.0
	noise.persistence = 0.8

func _find_camera():
	var viewport = get_viewport()
	if viewport:
		for child in viewport.get_children():
			if child is Camera2D and child.current:
				return child
	return null

func _create_light_shake():
	var profile = ShakeProfile.new()
	profile.intensity = 0.3
	profile.duration = 0.2
	profile.frequency = 20.0
	profile.rotation_strength = 0.5
	return profile

func _create_medium_shake():
	var profile = ShakeProfile.new()
	profile.intensity = 0.6
	profile.duration = 0.4
	profile.frequency = 15.0
	return profile

func _create_heavy_shake():
	var profile = ShakeProfile.new()
	profile.intensity = 1.0
	profile.duration = 0.6
	profile.frequency = 12.0
	profile.rotation_strength = 1.5
	return profile

func _create_explosion_shake():
	var profile = ShakeProfile.new()
	profile.intensity = 1.2
	profile.duration = 0.3
	profile.frequency = 25.0
	profile.position_strength = 1.5
	var curve = Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(0.1, 0.8))
	curve.add_point(Vector2(1, 0))
	profile.decay_curve = curve
	return profile

func _create_earthquake_shake():
	var profile = ShakeProfile.new()
	profile.intensity = 0.8
	profile.duration = 2.0
	profile.frequency = 8.0
	profile.rotation_strength = 0.3
	profile.position_strength = 2.0
	return profile

func _process(delta):
	time += delta
	
	_update_active_shakes(delta)
	
	if trauma > 0:
		trauma = max(trauma - trauma_reduction_speed * delta, 0)
		_apply_shake()
		
		if not is_shaking:
			is_shaking = true
			emit_signal("shake_started")
	elif is_shaking:
		is_shaking = false
		_reset_camera()
		emit_signal("shake_ended")

func _update_active_shakes(delta):
	var i = 0
	while i < active_shakes.size():
		var shake = active_shakes[i]
		shake.time += delta
		
		if shake.time >= shake.profile.duration:
			active_shakes.remove(i)
		else:
			i += 1

func _apply_shake():
	if not camera:
		return
	
	var shake_power = pow(trauma, 2)
	
	var offset_x = max_offset.x * shake_power * _get_noise_value(0, time)
	var offset_y = max_offset.y * shake_power * _get_noise_value(1, time)
	var rotation = max_rotation * shake_power * _get_noise_value(2, time)
	
	for shake in active_shakes:
		var progress = shake.time / shake.profile.duration
		var intensity = shake.profile.intensity * shake.profile.decay_curve.interpolate(progress)
		
		offset_x += max_offset.x * intensity * shake.profile.position_strength * _get_noise_value(3, time * shake.profile.frequency)
		offset_y += max_offset.y * intensity * shake.profile.position_strength * _get_noise_value(4, time * shake.profile.frequency)
		rotation += max_rotation * intensity * shake.profile.rotation_strength * _get_noise_value(5, time * shake.profile.frequency)
	
	camera.offset = original_offset + Vector2(offset_x, offset_y)
	camera.rotation = rotation

func _get_noise_value(seed_offset, time_value):
	return noise.get_noise_2d(seed_offset * 1000, time_value * noise_speed)

func _reset_camera():
	if camera:
		camera.offset = original_offset
		camera.rotation = 0

func add_trauma(amount):
	trauma = min(trauma + amount, 1.0)

func shake(intensity = 0.5, duration = 0.5):
	add_trauma(intensity)
	
	if duration > 0:
		yield(get_tree().create_timer(duration), "timeout")
		trauma = 0

func shake_with_profile(profile_name):
	if not profile_name in shake_profiles:
		push_warning("Shake profile '" + profile_name + "' not found")
		return
	
	var profile = shake_profiles[profile_name]
	var shake_instance = {
		"profile": profile,
		"time": 0.0
	}
	active_shakes.append(shake_instance)
	add_trauma(profile.intensity * 0.5)

func create_custom_shake(intensity, duration, frequency, rotation_strength = 1.0, position_strength = 1.0):
	var profile = ShakeProfile.new()
	profile.intensity = intensity
	profile.duration = duration
	profile.frequency = frequency
	profile.rotation_strength = rotation_strength
	profile.position_strength = position_strength
	
	var shake_instance = {
		"profile": profile,
		"time": 0.0
	}
	active_shakes.append(shake_instance)
	add_trauma(intensity * 0.5)

func directional_shake(direction, intensity = 0.5):
	if not camera:
		return
	
	var shake_offset = direction.normalized() * max_offset * intensity
	camera.offset = original_offset + shake_offset
	
	yield(get_tree().create_timer(0.1), "timeout")
	_reset_camera()

func stop_shake():
	trauma = 0
	active_shakes.clear()
	_reset_camera()

func set_camera(new_camera):
	camera = new_camera
	if camera:
		original_offset = camera.offset

func is_camera_shaking():
	return is_shaking

func get_current_trauma():
	return trauma

func set_trauma_reduction_speed(speed):
	trauma_reduction_speed = max(0.1, speed)