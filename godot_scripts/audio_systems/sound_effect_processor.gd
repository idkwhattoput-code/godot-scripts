extends Node

# Effect types
enum EffectType {
	NONE,
	REVERB,
	DELAY,
	CHORUS,
	FLANGER,
	PHASER,
	DISTORTION,
	BITCRUSHER,
	FILTER,
	COMPRESSOR,
	LIMITER,
	GATE,
	EQ,
	PITCH_SHIFT,
	TIME_STRETCH
}

# Processing settings
export var sample_rate = 44100
export var buffer_size = 512
export var max_delay_time = 2.0  # seconds
export var processing_enabled = true

# Effect chains
var effect_chains = {}
var active_processors = []

# Audio buffers
var delay_buffers = {}
var reverb_buffers = {}
var buffer_positions = {}

# Effect parameters
var effect_presets = {
	"hall_reverb": {
		"type": EffectType.REVERB,
		"room_size": 0.8,
		"damping": 0.5,
		"wet": 0.3,
		"dry": 0.7,
		"pre_delay": 0.02
	},
	"echo": {
		"type": EffectType.DELAY,
		"delay_time": 0.5,
		"feedback": 0.5,
		"wet": 0.5,
		"dry": 0.5
	},
	"radio": {
		"type": EffectType.FILTER,
		"filter_type": "bandpass",
		"frequency": 2000,
		"resonance": 2.0
	},
	"underwater": {
		"type": EffectType.FILTER,
		"filter_type": "lowpass",
		"frequency": 800,
		"resonance": 1.5
	}
}

signal effect_applied(audio_stream, effect_type)
signal chain_created(chain_id)
signal processing_complete(audio_stream)

func _ready():
	_initialize_buffers()
	_setup_effect_presets()

func _initialize_buffers():
	var max_samples = int(max_delay_time * sample_rate)
	
	# Initialize delay line buffers
	for i in range(4):  # Support 4 delay lines
		delay_buffers[i] = []
		delay_buffers[i].resize(max_samples)
		buffer_positions[i] = 0
		
		for j in range(max_samples):
			delay_buffers[i][j] = 0.0

func _setup_effect_presets():
	# Add more complex presets
	effect_presets["telephone"] = {
		"type": EffectType.EQ,
		"bands": [
			{"freq": 300, "gain": -12, "q": 1.0},
			{"freq": 1000, "gain": 6, "q": 2.0},
			{"freq": 3000, "gain": 3, "q": 1.5},
			{"freq": 6000, "gain": -18, "q": 1.0}
		]
	}
	
	effect_presets["megaphone"] = {
		"type": EffectType.DISTORTION,
		"drive": 0.8,
		"tone": 0.3,
		"output": 0.7
	}

# Core processing functions

func process_audio_stream(audio_stream: AudioStream, effects: Array) -> AudioStream:
	if not processing_enabled:
		return audio_stream
	
	# Convert stream to samples
	var samples = _stream_to_samples(audio_stream)
	
	# Apply each effect in chain
	for effect in effects:
		samples = _apply_effect(samples, effect)
	
	# Convert back to stream
	var processed_stream = _samples_to_stream(samples, audio_stream)
	
	emit_signal("processing_complete", processed_stream)
	return processed_stream

func _apply_effect(samples: Array, effect: Dictionary) -> Array:
	match effect.type:
		EffectType.REVERB:
			return _apply_reverb(samples, effect)
		EffectType.DELAY:
			return _apply_delay(samples, effect)
		EffectType.CHORUS:
			return _apply_chorus(samples, effect)
		EffectType.FLANGER:
			return _apply_flanger(samples, effect)
		EffectType.PHASER:
			return _apply_phaser(samples, effect)
		EffectType.DISTORTION:
			return _apply_distortion(samples, effect)
		EffectType.BITCRUSHER:
			return _apply_bitcrusher(samples, effect)
		EffectType.FILTER:
			return _apply_filter(samples, effect)
		EffectType.COMPRESSOR:
			return _apply_compressor(samples, effect)
		EffectType.PITCH_SHIFT:
			return _apply_pitch_shift(samples, effect)
		_:
			return samples

# Individual effect implementations

func _apply_reverb(samples: Array, params: Dictionary) -> Array:
	var output = []
	var room_size = params.get("room_size", 0.5)
	var damping = params.get("damping", 0.5)
	var wet = params.get("wet", 0.3)
	var dry = params.get("dry", 0.7)
	var pre_delay = int(params.get("pre_delay", 0.0) * sample_rate)
	
	# Freeverb-style reverb using comb and allpass filters
	var comb_delays = [1557, 1617, 1491, 1422, 1277, 1356, 1188, 1116]
	var allpass_delays = [225, 556, 441, 341]
	
	# Process each sample
	for i in range(samples.size()):
		var input_sample = samples[i]
		var reverb_sample = 0.0
		
		# Pre-delay
		if i >= pre_delay:
			input_sample = samples[i - pre_delay]
		
		# Comb filters in parallel
		for delay in comb_delays:
			var delayed_idx = max(0, i - delay)
			var delayed = samples[delayed_idx] if delayed_idx < samples.size() else 0.0
			reverb_sample += delayed * room_size
		
		# Allpass filters in series
		for delay in allpass_delays:
			var delayed_idx = max(0, i - delay)
			var delayed = samples[delayed_idx] if delayed_idx < samples.size() else 0.0
			reverb_sample = reverb_sample * 0.5 + delayed * 0.5
		
		# Apply damping
		reverb_sample *= (1.0 - damping)
		
		# Mix wet and dry
		output.append(input_sample * dry + reverb_sample * wet)
	
	return output

func _apply_delay(samples: Array, params: Dictionary) -> Array:
	var output = []
	var delay_time = params.get("delay_time", 0.5)
	var feedback = params.get("feedback", 0.5)
	var wet = params.get("wet", 0.5)
	var dry = params.get("dry", 0.5)
	var delay_samples = int(delay_time * sample_rate)
	
	# Use circular buffer for delay
	var buffer_idx = params.get("buffer_index", 0)
	var buffer = delay_buffers[buffer_idx]
	var write_pos = buffer_positions[buffer_idx]
	
	for i in range(samples.size()):
		var input_sample = samples[i]
		
		# Read from delay buffer
		var read_pos = (write_pos - delay_samples + buffer.size()) % buffer.size()
		var delayed_sample = buffer[read_pos]
		
		# Write to delay buffer with feedback
		buffer[write_pos] = input_sample + delayed_sample * feedback
		
		# Mix wet and dry
		output.append(input_sample * dry + delayed_sample * wet)
		
		# Update position
		write_pos = (write_pos + 1) % buffer.size()
	
	buffer_positions[buffer_idx] = write_pos
	return output

func _apply_chorus(samples: Array, params: Dictionary) -> Array:
	var output = []
	var rate = params.get("rate", 1.5)  # Hz
	var depth = params.get("depth", 0.002)  # seconds
	var mix = params.get("mix", 0.5)
	var voices = params.get("voices", 3)
	
	for i in range(samples.size()):
		var input_sample = samples[i]
		var chorus_sample = 0.0
		
		# Multiple chorus voices
		for v in range(voices):
			var phase = float(i) / sample_rate * rate * TAU + (v * TAU / voices)
			var delay_time = depth * (1.0 + sin(phase)) * 0.5
			var delay_samples = int(delay_time * sample_rate)
			
			var delayed_idx = max(0, i - delay_samples)
			if delayed_idx < samples.size():
				chorus_sample += samples[delayed_idx] / voices
		
		output.append(input_sample * (1.0 - mix) + chorus_sample * mix)
	
	return output

func _apply_flanger(samples: Array, params: Dictionary) -> Array:
	var output = []
	var rate = params.get("rate", 0.5)  # Hz
	var depth = params.get("depth", 0.005)  # seconds
	var feedback = params.get("feedback", 0.5)
	var mix = params.get("mix", 0.5)
	
	var max_delay = int(depth * sample_rate)
	var flanger_buffer = []
	flanger_buffer.resize(max_delay + 1)
	
	for i in range(samples.size()):
		var input_sample = samples[i]
		
		# Calculate delay time
		var phase = float(i) / sample_rate * rate * TAU
		var delay_time = depth * (1.0 + sin(phase)) * 0.5
		var delay_samples = int(delay_time * sample_rate)
		
		# Read from buffer
		var buffer_idx = i % flanger_buffer.size()
		var delayed_sample = flanger_buffer[buffer_idx] if i >= delay_samples else 0.0
		
		# Apply feedback
		flanger_buffer[buffer_idx] = input_sample + delayed_sample * feedback
		
		output.append(input_sample * (1.0 - mix) + delayed_sample * mix)
	
	return output

func _apply_phaser(samples: Array, params: Dictionary) -> Array:
	var output = []
	var rate = params.get("rate", 0.5)  # Hz
	var depth = params.get("depth", 1.0)
	var stages = params.get("stages", 4)
	var feedback = params.get("feedback", 0.5)
	var mix = params.get("mix", 0.5)
	
	# Allpass filter states
	var allpass_states = []
	for s in range(stages):
		allpass_states.append(0.0)
	
	for i in range(samples.size()):
		var input_sample = samples[i]
		var phase = float(i) / sample_rate * rate * TAU
		
		# Sweep frequency
		var sweep = (1.0 + sin(phase)) * 0.5
		var frequency = 200 + sweep * 1800 * depth
		
		# Apply allpass filters
		var filtered = input_sample
		for s in range(stages):
			var coefficient = _calculate_allpass_coefficient(frequency * (s + 1))
			var old_state = allpass_states[s]
			allpass_states[s] = filtered + coefficient * old_state
			filtered = -filtered + coefficient * allpass_states[s]
		
		# Apply feedback
		filtered += input_sample * feedback
		
		output.append(input_sample * (1.0 - mix) + filtered * mix)
	
	return output

func _apply_distortion(samples: Array, params: Dictionary) -> Array:
	var output = []
	var drive = params.get("drive", 0.5)
	var tone = params.get("tone", 0.5)
	var output_level = params.get("output", 0.7)
	
	for i in range(samples.size()):
		var input_sample = samples[i]
		
		# Pre-gain
		var driven = input_sample * (1.0 + drive * 10.0)
		
		# Soft clipping
		var clipped = 0.0
		if abs(driven) < 0.7:
			clipped = driven
		else:
			clipped = sign(driven) * (0.7 + 0.3 * tanh((abs(driven) - 0.7) * 3.0))
		
		# Tone control (simple low-pass)
		if i > 0:
			clipped = clipped * tone + output[i-1] * (1.0 - tone)
		
		output.append(clipped * output_level)
	
	return output

func _apply_bitcrusher(samples: Array, params: Dictionary) -> Array:
	var output = []
	var bit_depth = params.get("bit_depth", 8)
	var downsample = params.get("downsample", 4)
	var mix = params.get("mix", 1.0)
	
	var levels = pow(2, bit_depth)
	var held_sample = 0.0
	
	for i in range(samples.size()):
		var input_sample = samples[i]
		
		# Downsampling
		if i % downsample == 0:
			# Bit reduction
			held_sample = round(input_sample * levels) / levels
		
		output.append(input_sample * (1.0 - mix) + held_sample * mix)
	
	return output

func _apply_filter(samples: Array, params: Dictionary) -> Array:
	var output = []
	var filter_type = params.get("filter_type", "lowpass")
	var frequency = params.get("frequency", 1000)
	var resonance = params.get("resonance", 1.0)
	
	# Biquad filter coefficients
	var coeffs = _calculate_filter_coefficients(filter_type, frequency, resonance)
	
	# Filter states
	var x1 = 0.0
	var x2 = 0.0
	var y1 = 0.0
	var y2 = 0.0
	
	for i in range(samples.size()):
		var input_sample = samples[i]
		
		# Apply biquad filter
		var filtered = coeffs.a0 * input_sample + coeffs.a1 * x1 + coeffs.a2 * x2
		filtered -= coeffs.b1 * y1 + coeffs.b2 * y2
		
		# Update states
		x2 = x1
		x1 = input_sample
		y2 = y1
		y1 = filtered
		
		output.append(filtered)
	
	return output

func _apply_compressor(samples: Array, params: Dictionary) -> Array:
	var output = []
	var threshold = params.get("threshold", -12.0)  # dB
	var ratio = params.get("ratio", 4.0)
	var attack = params.get("attack", 0.01)  # seconds
	var release = params.get("release", 0.1)  # seconds
	var makeup_gain = params.get("makeup", 0.0)  # dB
	
	var threshold_linear = db2linear(threshold)
	var makeup_linear = db2linear(makeup_gain)
	var envelope = 0.0
	
	# Time constants
	var attack_coeff = exp(-1.0 / (attack * sample_rate))
	var release_coeff = exp(-1.0 / (release * sample_rate))
	
	for i in range(samples.size()):
		var input_sample = samples[i]
		var input_level = abs(input_sample)
		
		# Envelope follower
		if input_level > envelope:
			envelope = input_level + (envelope - input_level) * attack_coeff
		else:
			envelope = input_level + (envelope - input_level) * release_coeff
		
		# Calculate gain reduction
		var gain = 1.0
		if envelope > threshold_linear:
			var excess_db = linear2db(envelope / threshold_linear)
			var reduction_db = excess_db * (1.0 - 1.0 / ratio)
			gain = db2linear(-reduction_db)
		
		output.append(input_sample * gain * makeup_linear)
	
	return output

func _apply_pitch_shift(samples: Array, params: Dictionary) -> Array:
	var output = []
	var pitch_factor = params.get("pitch_factor", 1.0)  # 2.0 = octave up, 0.5 = octave down
	var window_size = params.get("window_size", 1024)
	var hop_size = int(window_size / 4)
	
	# Simple pitch shift using granular synthesis
	for i in range(samples.size()):
		var source_index = int(i / pitch_factor)
		
		if source_index < samples.size():
			output.append(samples[source_index])
		else:
			output.append(0.0)
	
	return output

# Helper functions

func _stream_to_samples(stream: AudioStream) -> Array:
	# This is a placeholder - actual implementation would depend on stream type
	var samples = []
	
	# For now, return empty array
	# In practice, you'd decode the audio stream to raw samples
	
	return samples

func _samples_to_stream(samples: Array, original_stream: AudioStream) -> AudioStream:
	# This is a placeholder - actual implementation would create new stream
	# In practice, you'd encode the samples back to the appropriate format
	
	return original_stream

func _calculate_allpass_coefficient(frequency: float) -> float:
	var tan_half = tan(PI * frequency / sample_rate)
	return (tan_half - 1.0) / (tan_half + 1.0)

func _calculate_filter_coefficients(type: String, frequency: float, resonance: float) -> Dictionary:
	var omega = TAU * frequency / sample_rate
	var cos_omega = cos(omega)
	var sin_omega = sin(omega)
	var alpha = sin_omega / (2.0 * resonance)
	
	var coeffs = {}
	
	match type:
		"lowpass":
			coeffs.b0 = (1.0 - cos_omega) / 2.0
			coeffs.b1 = 1.0 - cos_omega
			coeffs.b2 = (1.0 - cos_omega) / 2.0
			coeffs.a0 = 1.0 + alpha
			coeffs.a1 = -2.0 * cos_omega
			coeffs.a2 = 1.0 - alpha
		
		"highpass":
			coeffs.b0 = (1.0 + cos_omega) / 2.0
			coeffs.b1 = -(1.0 + cos_omega)
			coeffs.b2 = (1.0 + cos_omega) / 2.0
			coeffs.a0 = 1.0 + alpha
			coeffs.a1 = -2.0 * cos_omega
			coeffs.a2 = 1.0 - alpha
		
		"bandpass":
			coeffs.b0 = alpha
			coeffs.b1 = 0.0
			coeffs.b2 = -alpha
			coeffs.a0 = 1.0 + alpha
			coeffs.a1 = -2.0 * cos_omega
			coeffs.a2 = 1.0 - alpha
	
	# Normalize
	coeffs.b0 /= coeffs.a0
	coeffs.b1 /= coeffs.a0
	coeffs.b2 /= coeffs.a0
	coeffs.a1 /= coeffs.a0
	coeffs.a2 /= coeffs.a0
	coeffs.a0 = 1.0
	
	return coeffs

# Public API

func apply_preset(stream: AudioStream, preset_name: String) -> AudioStream:
	if not effect_presets.has(preset_name):
		push_warning("Preset not found: " + preset_name)
		return stream
	
	var preset = effect_presets[preset_name]
	return process_audio_stream(stream, [preset])

func create_effect_chain(chain_id: String) -> void:
	effect_chains[chain_id] = []
	emit_signal("chain_created", chain_id)

func add_effect_to_chain(chain_id: String, effect: Dictionary) -> void:
	if effect_chains.has(chain_id):
		effect_chains[chain_id].append(effect)

func process_with_chain(stream: AudioStream, chain_id: String) -> AudioStream:
	if not effect_chains.has(chain_id):
		return stream
	
	return process_audio_stream(stream, effect_chains[chain_id])

func get_available_presets() -> Array:
	return effect_presets.keys()

func create_custom_preset(name: String, effect: Dictionary) -> void:
	effect_presets[name] = effect