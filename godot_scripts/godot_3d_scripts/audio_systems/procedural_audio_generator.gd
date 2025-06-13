extends Node

# Waveform types
enum WaveType {
	SINE,
	SQUARE,
	TRIANGLE,
	SAWTOOTH,
	NOISE
}

# Generator settings
export var sample_rate = 44100
export var buffer_size = 1024
export var max_generators = 8

# Active generators
var generators = []
var audio_stream_generator
var playback

# Noise generation
var noise_seed = 0
var white_noise_buffer = []
var pink_noise_buffer = []
var brown_noise_buffer = []

# Effects
export var enable_reverb = false
export var reverb_room_size = 0.5
export var reverb_damping = 0.5
export var enable_delay = false
export var delay_time = 0.25
export var delay_feedback = 0.3

# Synthesis parameters
var phase_accumulator = {}
var pink_noise_state = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var brown_noise_state = 0.0

signal tone_generated(frequency, wave_type)
signal effect_applied(effect_name)
signal generator_created(id)
signal generator_removed(id)

func _ready():
	_setup_audio_stream()
	_initialize_noise_buffers()
	set_process(true)

func _setup_audio_stream():
	var player = AudioStreamPlayer.new()
	add_child(player)
	
	audio_stream_generator = AudioStreamGenerator.new()
	audio_stream_generator.mix_rate = sample_rate
	audio_stream_generator.buffer_length = buffer_size / float(sample_rate)
	
	player.stream = audio_stream_generator
	player.play()
	
	playback = player.get_stream_playback()

func _initialize_noise_buffers():
	randomize()
	noise_seed = randi()
	
	# Pre-generate noise buffers
	for i in range(buffer_size * 4):
		white_noise_buffer.append(rand_range(-1.0, 1.0))

func _process(_delta):
	_fill_audio_buffer()

func _fill_audio_buffer():
	var frames_available = playback.get_frames_available()
	
	while frames_available > 0:
		var frame = Vector2.ZERO
		
		# Mix all active generators
		for gen in generators:
			if gen.active:
				var sample = _generate_sample(gen)
				frame += Vector2(sample, sample) * gen.volume
		
		# Apply effects
		if enable_reverb:
			frame = _apply_reverb(frame)
		if enable_delay:
			frame = _apply_delay(frame)
		
		# Clamp to prevent clipping
		frame.x = clamp(frame.x, -1.0, 1.0)
		frame.y = clamp(frame.y, -1.0, 1.0)
		
		playback.push_frame(frame)
		frames_available -= 1

func _generate_sample(generator: Dictionary) -> float:
	var sample = 0.0
	
	match generator.wave_type:
		WaveType.SINE:
			sample = _generate_sine(generator)
		WaveType.SQUARE:
			sample = _generate_square(generator)
		WaveType.TRIANGLE:
			sample = _generate_triangle(generator)
		WaveType.SAWTOOTH:
			sample = _generate_sawtooth(generator)
		WaveType.NOISE:
			sample = _generate_noise(generator)
	
	# Apply envelope
	sample = _apply_envelope(sample, generator)
	
	# Apply filter
	if generator.filter_enabled:
		sample = _apply_filter(sample, generator)
	
	return sample

func _generate_sine(gen: Dictionary) -> float:
	var phase = phase_accumulator.get(gen.id, 0.0)
	var sample = sin(phase * TAU)
	
	# Update phase
	phase += gen.frequency / sample_rate
	if phase >= 1.0:
		phase -= 1.0
	phase_accumulator[gen.id] = phase
	
	return sample

func _generate_square(gen: Dictionary) -> float:
	var phase = phase_accumulator.get(gen.id, 0.0)
	var sample = 1.0 if phase < 0.5 else -1.0
	
	# Update phase
	phase += gen.frequency / sample_rate
	if phase >= 1.0:
		phase -= 1.0
	phase_accumulator[gen.id] = phase
	
	return sample

func _generate_triangle(gen: Dictionary) -> float:
	var phase = phase_accumulator.get(gen.id, 0.0)
	var sample = 0.0
	
	if phase < 0.5:
		sample = 4.0 * phase - 1.0
	else:
		sample = 3.0 - 4.0 * phase
	
	# Update phase
	phase += gen.frequency / sample_rate
	if phase >= 1.0:
		phase -= 1.0
	phase_accumulator[gen.id] = phase
	
	return sample

func _generate_sawtooth(gen: Dictionary) -> float:
	var phase = phase_accumulator.get(gen.id, 0.0)
	var sample = 2.0 * phase - 1.0
	
	# Update phase
	phase += gen.frequency / sample_rate
	if phase >= 1.0:
		phase -= 1.0
	phase_accumulator[gen.id] = phase
	
	return sample

func _generate_noise(gen: Dictionary) -> float:
	match gen.noise_type:
		"white":
			return _generate_white_noise()
		"pink":
			return _generate_pink_noise()
		"brown":
			return _generate_brown_noise()
		_:
			return _generate_white_noise()

func _generate_white_noise() -> float:
	return rand_range(-1.0, 1.0)

func _generate_pink_noise() -> float:
	# Paul Kellet's pink noise filter
	var white = _generate_white_noise()
	
	pink_noise_state[0] = 0.99886 * pink_noise_state[0] + white * 0.0555179
	pink_noise_state[1] = 0.99332 * pink_noise_state[1] + white * 0.0750759
	pink_noise_state[2] = 0.96900 * pink_noise_state[2] + white * 0.1538520
	pink_noise_state[3] = 0.86650 * pink_noise_state[3] + white * 0.3104856
	pink_noise_state[4] = 0.55000 * pink_noise_state[4] + white * 0.5329522
	pink_noise_state[5] = -0.7616 * pink_noise_state[5] - white * 0.0168980
	
	var pink = pink_noise_state[0] + pink_noise_state[1] + pink_noise_state[2] + \
			   pink_noise_state[3] + pink_noise_state[4] + pink_noise_state[5] + \
			   pink_noise_state[6] + white * 0.5362
	
	pink_noise_state[6] = white * 0.115926
	
	return pink * 0.11  # Normalize

func _generate_brown_noise() -> float:
	var white = _generate_white_noise()
	brown_noise_state = (brown_noise_state + (0.02 * white)) / 1.02
	return brown_noise_state * 3.5  # Normalize

func _apply_envelope(sample: float, gen: Dictionary) -> float:
	var env_value = 1.0
	var time_since_start = (OS.get_ticks_msec() - gen.start_time) / 1000.0
	
	if time_since_start < gen.attack:
		# Attack phase
		env_value = time_since_start / gen.attack
	elif time_since_start < gen.attack + gen.decay:
		# Decay phase
		var decay_progress = (time_since_start - gen.attack) / gen.decay
		env_value = 1.0 - (decay_progress * (1.0 - gen.sustain))
	elif gen.gate_open:
		# Sustain phase
		env_value = gen.sustain
	else:
		# Release phase
		var release_time = (OS.get_ticks_msec() - gen.release_time) / 1000.0
		env_value = gen.sustain * (1.0 - release_time / gen.release)
		
		if release_time >= gen.release:
			gen.active = false
	
	return sample * env_value

func _apply_filter(sample: float, gen: Dictionary) -> float:
	# Simple low-pass filter
	if not gen.has("filter_state"):
		gen.filter_state = 0.0
	
	var cutoff = gen.filter_cutoff / sample_rate
	var resonance = gen.filter_resonance
	
	# Calculate filter coefficient
	var c = 1.0 / tan(PI * cutoff)
	var a1 = 1.0 / (1.0 + resonance * c + c * c)
	var a2 = 2.0 * a1
	var a3 = a1
	var b1 = 2.0 * (1.0 - c * c) * a1
	var b2 = (1.0 - resonance * c + c * c) * a1
	
	# Apply filter
	var filtered = a1 * sample + a2 * gen.filter_state
	gen.filter_state = sample
	
	return filtered

func _apply_reverb(frame: Vector2) -> Vector2:
	# Simple reverb using delay lines
	# This is a placeholder - implement proper reverb algorithm
	return frame

func _apply_delay(frame: Vector2) -> Vector2:
	# Simple delay effect
	# This is a placeholder - implement proper delay with buffer
	return frame

# Public API

func create_tone_generator(frequency: float, wave_type: int = WaveType.SINE, volume: float = 0.5) -> int:
	if generators.size() >= max_generators:
		push_warning("Maximum number of generators reached")
		return -1
	
	var gen_id = OS.get_unix_time() * 1000 + randi() % 1000
	
	var generator = {
		"id": gen_id,
		"frequency": frequency,
		"wave_type": wave_type,
		"volume": volume,
		"active": true,
		"start_time": OS.get_ticks_msec(),
		"gate_open": true,
		# ADSR envelope
		"attack": 0.01,
		"decay": 0.1,
		"sustain": 0.7,
		"release": 0.2,
		"release_time": 0,
		# Filter
		"filter_enabled": false,
		"filter_cutoff": 1000.0,
		"filter_resonance": 1.0
	}
	
	generators.append(generator)
	emit_signal("generator_created", gen_id)
	emit_signal("tone_generated", frequency, wave_type)
	
	return gen_id

func create_noise_generator(noise_type: String = "white", volume: float = 0.3) -> int:
	var gen_id = create_tone_generator(0, WaveType.NOISE, volume)
	
	if gen_id != -1:
		for gen in generators:
			if gen.id == gen_id:
				gen.noise_type = noise_type
				break
	
	return gen_id

func stop_generator(gen_id: int):
	for gen in generators:
		if gen.id == gen_id:
			gen.gate_open = false
			gen.release_time = OS.get_ticks_msec()
			break

func remove_generator(gen_id: int):
	for i in range(generators.size()):
		if generators[i].id == gen_id:
			generators.remove(i)
			phase_accumulator.erase(gen_id)
			emit_signal("generator_removed", gen_id)
			break

func set_generator_frequency(gen_id: int, frequency: float):
	for gen in generators:
		if gen.id == gen_id:
			gen.frequency = frequency
			break

func set_generator_volume(gen_id: int, volume: float):
	for gen in generators:
		if gen.id == gen_id:
			gen.volume = clamp(volume, 0.0, 1.0)
			break

func set_generator_envelope(gen_id: int, attack: float, decay: float, sustain: float, release: float):
	for gen in generators:
		if gen.id == gen_id:
			gen.attack = attack
			gen.decay = decay
			gen.sustain = clamp(sustain, 0.0, 1.0)
			gen.release = release
			break

func set_generator_filter(gen_id: int, enabled: bool, cutoff: float = 1000.0, resonance: float = 1.0):
	for gen in generators:
		if gen.id == gen_id:
			gen.filter_enabled = enabled
			gen.filter_cutoff = cutoff
			gen.filter_resonance = resonance
			break

func clear_all_generators():
	generators.clear()
	phase_accumulator.clear()

# Sound effect generation

func generate_explosion(size: float = 1.0) -> int:
	var gen_id = create_noise_generator("brown", 0.8 * size)
	set_generator_envelope(gen_id, 0.0, 0.05, 0.3, 1.0 * size)
	set_generator_filter(gen_id, true, 200 / size, 2.0)
	stop_generator(gen_id)
	return gen_id

func generate_laser(frequency: float = 2000.0) -> int:
	var gen_id = create_tone_generator(frequency, WaveType.SAWTOOTH, 0.6)
	set_generator_envelope(gen_id, 0.0, 0.0, 1.0, 0.3)
	
	# Frequency sweep
	var tween = get_tree().create_tween()
	tween.tween_method(self, "set_generator_frequency", frequency, frequency * 0.1, 0.3, [gen_id])
	
	stop_generator(gen_id)
	return gen_id

func generate_coin_pickup() -> int:
	# Two-tone coin sound
	var gen1 = create_tone_generator(800, WaveType.SQUARE, 0.4)
	var gen2 = create_tone_generator(1200, WaveType.SQUARE, 0.4)
	
	set_generator_envelope(gen1, 0.0, 0.05, 0.0, 0.1)
	set_generator_envelope(gen2, 0.0, 0.05, 0.0, 0.15)
	
	stop_generator(gen1)
	yield(get_tree().create_timer(0.1), "timeout")
	stop_generator(gen2)
	
	return gen2

func generate_footstep(surface: String = "concrete") -> int:
	var gen_id = -1
	
	match surface:
		"concrete":
			gen_id = create_noise_generator("white", 0.3)
			set_generator_envelope(gen_id, 0.0, 0.02, 0.0, 0.05)
			set_generator_filter(gen_id, true, 800, 1.0)
		"grass":
			gen_id = create_noise_generator("pink", 0.2)
			set_generator_envelope(gen_id, 0.01, 0.03, 0.0, 0.08)
			set_generator_filter(gen_id, true, 400, 1.0)
		"metal":
			gen_id = create_tone_generator(150, WaveType.SINE, 0.2)
			set_generator_envelope(gen_id, 0.0, 0.01, 0.1, 0.1)
			var noise = create_noise_generator("white", 0.4)
			set_generator_envelope(noise, 0.0, 0.01, 0.0, 0.02)
			stop_generator(noise)
	
	if gen_id != -1:
		stop_generator(gen_id)
	
	return gen_id