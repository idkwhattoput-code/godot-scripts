extends Camera

# Camera Shake Effect for Godot 3D
# Adds realistic camera shake for explosions, impacts, earthquakes, etc.
# Supports multiple shake types and can layer multiple shakes

# Shake parameters
export var max_rotation = 0.1  # Maximum rotation in radians
export var max_offset = 0.5    # Maximum position offset
export var trauma_reduction_rate = 1.0  # How fast trauma decreases

# Shake types
enum ShakeType { RANDOM, PERLIN, SINE_WAVE, EARTHQUAKE }
export var shake_type = ShakeType.RANDOM

# Perlin noise settings
export var noise_speed = 50.0
export var noise_scale = 1.0

# Current shake state
var trauma = 0.0
var trauma_power = 2.0
var time = 0.0
var noise: OpenSimplexNoise
var initial_transform: Transform

# Shake queue for multiple simultaneous shakes
var shake_queue = []

func _ready():
	# Store initial transform
	initial_transform = transform
	
	# Initialize noise for perlin shake
	randomize()
	noise = OpenSimplexNoise.new()
	noise.seed = randi()
	noise.period = 4
	noise.octaves = 2

func _process(delta):
	# Update time
	time += delta
	
	# Process shake queue
	process_shake_queue(delta)
	
	# Reduce trauma over time
	if trauma > 0:
		trauma = max(trauma - trauma_reduction_rate * delta, 0)
		apply_shake()
	else:
		# Reset to initial transform when not shaking
		transform = initial_transform

func add_trauma(amount: float):
	"""Add trauma to trigger camera shake"""
	trauma = min(trauma + amount, 1.0)

func shake(duration: float, frequency: float, amplitude: float, shake_type_override = -1):
	"""Add a timed shake effect"""
	shake_queue.append({
		"duration": duration,
		"frequency": frequency,
		"amplitude": amplitude,
		"elapsed": 0.0,
		"type": shake_type_override if shake_type_override >= 0 else shake_type
	})

func process_shake_queue(delta):
	"""Process all active shakes"""
	var total_amplitude = 0.0
	var i = shake_queue.size() - 1
	
	while i >= 0:
		var shake = shake_queue[i]
		shake.elapsed += delta
		
		if shake.elapsed < shake.duration:
			var progress = shake.elapsed / shake.duration
			var current_amplitude = shake.amplitude * (1.0 - progress)
			total_amplitude += current_amplitude
			shake_queue[i] = shake
		else:
			shake_queue.remove(i)
		
		i -= 1
	
	if total_amplitude > 0:
		add_trauma(total_amplitude)

func apply_shake():
	"""Apply the actual shake effect"""
	var amount = pow(trauma, trauma_power)
	
	# Reset to initial transform
	transform = initial_transform
	
	match shake_type:
		ShakeType.RANDOM:
			apply_random_shake(amount)
		ShakeType.PERLIN:
			apply_perlin_shake(amount)
		ShakeType.SINE_WAVE:
			apply_sine_shake(amount)
		ShakeType.EARTHQUAKE:
			apply_earthquake_shake(amount)

func apply_random_shake(amount):
	"""Random shake - good for explosions and impacts"""
	# Rotation
	rotation.x = initial_transform.basis.get_euler().x + (randf() - 0.5) * 2.0 * max_rotation * amount
	rotation.y = initial_transform.basis.get_euler().y + (randf() - 0.5) * 2.0 * max_rotation * amount
	rotation.z = initial_transform.basis.get_euler().z + (randf() - 0.5) * 2.0 * max_rotation * amount
	
	# Translation
	var offset = Vector3()
	offset.x = (randf() - 0.5) * 2.0 * max_offset * amount
	offset.y = (randf() - 0.5) * 2.0 * max_offset * amount
	translate(offset)

func apply_perlin_shake(amount):
	"""Perlin noise shake - smoother, more natural movement"""
	var noise_offset = time * noise_speed
	
	# Rotation using noise
	rotation.x = initial_transform.basis.get_euler().x + noise.get_noise_2d(noise_offset, 0) * max_rotation * amount
	rotation.y = initial_transform.basis.get_euler().y + noise.get_noise_2d(noise_offset, 100) * max_rotation * amount
	rotation.z = initial_transform.basis.get_euler().z + noise.get_noise_2d(noise_offset, 200) * max_rotation * amount
	
	# Translation using noise
	var offset = Vector3()
	offset.x = noise.get_noise_2d(noise_offset, 300) * max_offset * amount
	offset.y = noise.get_noise_2d(noise_offset, 400) * max_offset * amount
	translate(offset)

func apply_sine_shake(amount):
	"""Sine wave shake - rhythmic, good for machinery or vibrations"""
	var frequency = 30.0
	
	# Rotation
	rotation.x = initial_transform.basis.get_euler().x + sin(time * frequency) * max_rotation * amount
	rotation.z = initial_transform.basis.get_euler().z + cos(time * frequency * 0.7) * max_rotation * amount * 0.5
	
	# Translation
	var offset = Vector3()
	offset.y = sin(time * frequency * 2.0) * max_offset * amount * 0.3
	translate(offset)

func apply_earthquake_shake(amount):
	"""Earthquake shake - combines low frequency movement with high frequency vibration"""
	var low_freq = 2.0
	var high_freq = 30.0
	
	# Low frequency sway
	rotation.x = initial_transform.basis.get_euler().x + sin(time * low_freq) * max_rotation * amount * 0.5
	rotation.z = initial_transform.basis.get_euler().z + cos(time * low_freq * 0.7) * max_rotation * amount * 0.5
	
	# High frequency vibration
	rotation.x += (randf() - 0.5) * max_rotation * amount * 0.3
	rotation.y += (randf() - 0.5) * max_rotation * amount * 0.3
	
	# Translation - mostly horizontal
	var offset = Vector3()
	offset.x = sin(time * low_freq) * max_offset * amount + (randf() - 0.5) * max_offset * amount * 0.2
	offset.z = cos(time * low_freq * 0.8) * max_offset * amount * 0.7
	offset.y = sin(time * high_freq) * max_offset * amount * 0.1
	translate(offset)

# Preset shake effects
func explosion_shake():
	"""Preset for explosion shake"""
	shake(0.5, 30.0, 0.8, ShakeType.RANDOM)

func impact_shake():
	"""Preset for impact/hit shake"""
	shake(0.2, 20.0, 0.5, ShakeType.RANDOM)

func earthquake_shake():
	"""Preset for earthquake shake"""
	shake(5.0, 2.0, 0.6, ShakeType.EARTHQUAKE)

func machine_vibration():
	"""Preset for machinery vibration"""
	shake(2.0, 30.0, 0.2, ShakeType.SINE_WAVE)