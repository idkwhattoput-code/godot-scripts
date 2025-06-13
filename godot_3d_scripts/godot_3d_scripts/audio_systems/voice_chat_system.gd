extends Node

# Voice chat configuration
export var sample_rate = 16000
export var buffer_size = 512
export var voice_activation_threshold = -40.0  # dB
export var noise_gate_threshold = -50.0
export var compression_quality = 4  # 1-10

# Network settings
export var max_voice_distance = 50.0
export var voice_falloff_curve = 2.0
export var spatial_audio = true
export var team_channels = ["global", "team", "squad", "proximity"]
export var push_to_talk = true

# Audio processing
var audio_input
var audio_capture
var playback_streams = {}
var processing_thread

# Voice detection
var is_speaking = false
var voice_activity_detector = {}
var silence_frames = 0
var speech_frames = 0

# Network
var voice_peers = {}
var current_channel = "proximity"
var muted_players = []
var voice_packet_buffer = []

# Effects and filters
export var enable_noise_suppression = true
export var enable_echo_cancellation = true
export var enable_auto_gain = true
export var voice_effects = ["normal", "radio", "megaphone", "whisper", "robot"]
var current_voice_effect = "normal"

# Recording
var is_recording = false
var recorded_audio = []
var max_recording_duration = 60.0

# UI indicators
var speaking_indicators = {}
var voice_meters = {}

# Signals
signal player_started_speaking(player_id)
signal player_stopped_speaking(player_id)
signal voice_data_received(player_id, audio_data)
signal channel_changed(new_channel)
signal recording_started()
signal recording_finished(audio_data)

func _ready():
	_initialize_audio_input()
	_setup_voice_processing()
	_initialize_network()
	set_process(true)

func _initialize_audio_input():
	# Get audio input device
	audio_input = AudioServer.capture_get_device()
	
	# Create audio capture effect
	var audio_bus_idx = AudioServer.get_bus_index("VoiceInput")
	if audio_bus_idx == -1:
		# Create voice input bus
		audio_bus_idx = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(audio_bus_idx, "VoiceInput")
	
	# Add capture effect
	audio_capture = AudioEffectCapture.new()
	audio_capture.buffer_length = float(buffer_size) / sample_rate
	AudioServer.add_bus_effect(audio_bus_idx, audio_capture)
	
	# Start capture
	AudioServer.set_bus_mute(audio_bus_idx, false)

func _setup_voice_processing():
	# Initialize voice activity detection
	voice_activity_detector = {
		"energy_history": [],
		"history_size": 10,
		"speech_threshold": 0.6,
		"silence_threshold": 0.3
	}
	
	# Create processing thread for audio
	processing_thread = Thread.new()
	processing_thread.start(self, "_audio_processing_thread")

func _initialize_network():
	# Set up multiplayer voice communication
	get_tree().connect("network_peer_connected", self, "_on_peer_connected")
	get_tree().connect("network_peer_disconnected", self, "_on_peer_disconnected")

func _process(delta):
	_capture_voice_input()
	_update_voice_activity()
	_process_voice_packets()
	_update_spatial_audio()
	_update_ui_indicators()

func _capture_voice_input():
	if not audio_capture:
		return
	
	# Check if we should transmit
	var should_transmit = false
	if push_to_talk:
		should_transmit = Input.is_action_pressed("voice_chat")
	else:
		should_transmit = is_speaking
	
	if not should_transmit:
		return
	
	# Get available frames
	var frames_available = audio_capture.get_frames_available()
	if frames_available > 0:
		# Get audio frames
		var audio_frames = audio_capture.get_buffer(frames_available)
		
		# Process audio
		audio_frames = _process_audio_input(audio_frames)
		
		# Check voice activity
		if _detect_voice_activity(audio_frames):
			# Compress and send
			var compressed = _compress_audio(audio_frames)
			_send_voice_data(compressed)
			
			# Recording
			if is_recording:
				recorded_audio.append_array(audio_frames)

func _process_audio_input(frames: PoolVector2Array) -> PoolVector2Array:
	var processed = frames
	
	# Noise suppression
	if enable_noise_suppression:
		processed = _apply_noise_suppression(processed)
	
	# Echo cancellation
	if enable_echo_cancellation:
		processed = _apply_echo_cancellation(processed)
	
	# Auto gain control
	if enable_auto_gain:
		processed = _apply_auto_gain(processed)
	
	# Voice effects
	if current_voice_effect != "normal":
		processed = _apply_voice_effect(processed, current_voice_effect)
	
	return processed

func _apply_noise_suppression(frames: PoolVector2Array) -> PoolVector2Array:
	var output = PoolVector2Array()
	
	# Simple spectral subtraction
	for i in range(frames.size()):
		var sample = frames[i]
		
		# Gate low-level noise
		var level = 20 * log(abs(sample.x)) / log(10) if sample.x != 0 else -100
		if level < noise_gate_threshold:
			output.append(Vector2.ZERO)
		else:
			output.append(sample)
	
	return output

func _apply_echo_cancellation(frames: PoolVector2Array) -> PoolVector2Array:
	# Simplified echo cancellation
	# In practice, this would use adaptive filtering
	return frames

func _apply_auto_gain(frames: PoolVector2Array) -> PoolVector2Array:
	var output = PoolVector2Array()
	
	# Calculate RMS
	var rms = 0.0
	for frame in frames:
		rms += frame.x * frame.x
	rms = sqrt(rms / frames.size())
	
	# Target level
	var target_rms = 0.1
	var gain = target_rms / max(rms, 0.001)
	gain = clamp(gain, 0.5, 3.0)
	
	# Apply gain
	for frame in frames:
		output.append(frame * gain)
	
	return output

func _apply_voice_effect(frames: PoolVector2Array, effect: String) -> PoolVector2Array:
	var output = PoolVector2Array()
	
	match effect:
		"radio":
			# Bandpass filter and distortion
			for i in range(frames.size()):
				var sample = frames[i]
				# Simple high-pass
				if i > 0:
					sample = sample * 0.7 + frames[i-1] * 0.3
				# Add crackle
				if randf() < 0.01:
					sample += Vector2(randf() * 0.1 - 0.05, randf() * 0.1 - 0.05)
				output.append(sample)
		
		"megaphone":
			# Distortion and echo
			for i in range(frames.size()):
				var sample = frames[i]
				# Clip signal
				sample.x = clamp(sample.x * 2, -0.8, 0.8)
				sample.y = clamp(sample.y * 2, -0.8, 0.8)
				# Simple echo
				if i > 100:
					sample += frames[i - 100] * 0.3
				output.append(sample)
		
		"whisper":
			# Pitch shift up and reduce volume
			for i in range(frames.size()):
				# Simple pitch shift by skipping samples
				var source_idx = int(i * 1.2)
				if source_idx < frames.size():
					output.append(frames[source_idx] * 0.3)
				else:
					output.append(Vector2.ZERO)
		
		"robot":
			# Vocoder-like effect
			for i in range(frames.size()):
				var sample = frames[i]
				# Quantize
				sample.x = round(sample.x * 8) / 8
				sample.y = round(sample.y * 8) / 8
				# Add carrier wave
				var carrier = sin(i * 0.1) * 0.2
				sample.x = sample.x * carrier
				sample.y = sample.y * carrier
				output.append(sample)
		
		_:
			output = frames
	
	return output

func _detect_voice_activity(frames: PoolVector2Array) -> bool:
	# Calculate frame energy
	var energy = 0.0
	for frame in frames:
		energy += frame.x * frame.x
	energy = 10 * log(energy / frames.size()) / log(10) if frames.size() > 0 else -100
	
	# Update history
	voice_activity_detector.energy_history.append(energy)
	if voice_activity_detector.energy_history.size() > voice_activity_detector.history_size:
		voice_activity_detector.energy_history.pop_front()
	
	# Calculate average energy
	var avg_energy = 0.0
	for e in voice_activity_detector.energy_history:
		avg_energy += e
	avg_energy /= voice_activity_detector.energy_history.size()
	
	# Detect speech
	var was_speaking = is_speaking
	
	if energy > voice_activation_threshold and energy > avg_energy + 10:
		speech_frames += 1
		silence_frames = 0
	else:
		silence_frames += 1
		speech_frames = 0
	
	# Hysteresis
	if not is_speaking and speech_frames > 3:
		is_speaking = true
		emit_signal("player_started_speaking", get_tree().get_network_unique_id())
	elif is_speaking and silence_frames > 10:
		is_speaking = false
		emit_signal("player_stopped_speaking", get_tree().get_network_unique_id())
	
	return is_speaking

func _compress_audio(frames: PoolVector2Array) -> PoolByteArray:
	# Simple compression - convert to 16-bit PCM
	var compressed = PoolByteArray()
	
	for frame in frames:
		# Convert float to 16-bit integer
		var sample = int(clamp(frame.x, -1.0, 1.0) * 32767)
		compressed.append(sample & 0xFF)
		compressed.append((sample >> 8) & 0xFF)
	
	# Further compression could use Opus or similar codec
	return compressed

func _send_voice_data(data: PoolByteArray):
	if not get_tree().has_network_peer():
		return
	
	var packet = {
		"type": "voice",
		"channel": current_channel,
		"position": get_parent().global_transform.origin if get_parent() is Spatial else Vector3.ZERO,
		"data": data,
		"timestamp": OS.get_ticks_msec()
	}
	
	# Send to appropriate players based on channel
	match current_channel:
		"global":
			rpc("_receive_voice_data", packet)
		"team":
			# Send to team members only
			for peer_id in voice_peers:
				if _is_teammate(peer_id):
					rpc_id(peer_id, "_receive_voice_data", packet)
		"proximity":
			# Send to nearby players
			for peer_id in voice_peers:
				var peer_pos = voice_peers[peer_id].position
				var distance = peer_pos.distance_to(packet.position)
				if distance < max_voice_distance:
					rpc_id(peer_id, "_receive_voice_data", packet)

remote func _receive_voice_data(packet: Dictionary):
	var sender_id = get_tree().get_rpc_sender_id()
	
	# Check if muted
	if sender_id in muted_players:
		return
	
	# Add to buffer for processing
	packet.sender_id = sender_id
	voice_packet_buffer.append(packet)
	
	emit_signal("voice_data_received", sender_id, packet.data)

func _process_voice_packets():
	while voice_packet_buffer.size() > 0:
		var packet = voice_packet_buffer.pop_front()
		
		# Decompress audio
		var audio_frames = _decompress_audio(packet.data)
		
		# Get or create playback stream for this player
		if not playback_streams.has(packet.sender_id):
			_create_playback_stream(packet.sender_id)
		
		var stream_player = playback_streams[packet.sender_id]
		
		# Apply spatial audio if enabled
		if spatial_audio and stream_player is AudioStreamPlayer3D:
			stream_player.global_transform.origin = packet.position
			
			# Calculate volume based on distance
			var listener_pos = get_viewport().get_camera().global_transform.origin if get_viewport().get_camera() else Vector3.ZERO
			var distance = listener_pos.distance_to(packet.position)
			var volume = 1.0 - pow(distance / max_voice_distance, voice_falloff_curve)
			stream_player.volume_db = linear2db(clamp(volume, 0, 1))
		
		# Play audio
		_play_audio_frames(stream_player, audio_frames)

func _decompress_audio(data: PoolByteArray) -> PoolVector2Array:
	var frames = PoolVector2Array()
	
	# Convert 16-bit PCM back to float
	for i in range(0, data.size(), 2):
		if i + 1 < data.size():
			var sample = data[i] | (data[i + 1] << 8)
			# Handle sign extension for 16-bit
			if sample & 0x8000:
				sample = sample | 0xFFFF0000
			var float_sample = float(sample) / 32767.0
			frames.append(Vector2(float_sample, float_sample))
	
	return frames

func _create_playback_stream(player_id: int):
	var stream_player
	
	if spatial_audio:
		stream_player = AudioStreamPlayer3D.new()
		stream_player.unit_db = 0
		stream_player.max_distance = max_voice_distance
		stream_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	else:
		stream_player = AudioStreamPlayer.new()
	
	stream_player.bus = "Voice"
	stream_player.name = "VoicePlayer_" + str(player_id)
	add_child(stream_player)
	
	# Create audio stream generator
	var stream_generator = AudioStreamGenerator.new()
	stream_generator.mix_rate = sample_rate
	stream_generator.buffer_length = 0.1
	stream_player.stream = stream_generator
	stream_player.play()
	
	playback_streams[player_id] = stream_player

func _play_audio_frames(stream_player, frames: PoolVector2Array):
	if not stream_player.playing:
		stream_player.play()
	
	var playback = stream_player.get_stream_playback()
	if playback and playback.can_push_buffer(frames.size()):
		playback.push_buffer(frames)

func _update_spatial_audio():
	# Update 3D audio positions for voice chat
	for player_id in playback_streams:
		var stream_player = playback_streams[player_id]
		if stream_player is AudioStreamPlayer3D and voice_peers.has(player_id):
			stream_player.global_transform.origin = voice_peers[player_id].position

func _update_ui_indicators():
	# Update speaking indicators
	for player_id in voice_peers:
		if speaking_indicators.has(player_id):
			speaking_indicators[player_id].visible = voice_peers[player_id].is_speaking

func _audio_processing_thread(userdata):
	# Background audio processing
	while true:
		# Process any heavy audio operations here
		OS.delay_msec(10)

# Channel management
func set_voice_channel(channel: String):
	if channel in team_channels:
		current_channel = channel
		emit_signal("channel_changed", channel)

func join_channel(channel: String):
	# Join additional channel (for multi-channel support)
	pass

func leave_channel(channel: String):
	# Leave a channel
	pass

# Player management
func mute_player(player_id: int):
	if not player_id in muted_players:
		muted_players.append(player_id)

func unmute_player(player_id: int):
	muted_players.erase(player_id)

func set_player_volume(player_id: int, volume: float):
	if playback_streams.has(player_id):
		playback_streams[player_id].volume_db = linear2db(volume)

# Recording
func start_recording():
	is_recording = true
	recorded_audio.clear()
	emit_signal("recording_started")

func stop_recording():
	is_recording = false
	emit_signal("recording_finished", recorded_audio)

# Effects
func set_voice_effect(effect: String):
	if effect in voice_effects:
		current_voice_effect = effect

# Network callbacks
func _on_peer_connected(id: int):
	voice_peers[id] = {
		"position": Vector3.ZERO,
		"is_speaking": false,
		"volume": 1.0
	}

func _on_peer_disconnected(id: int):
	voice_peers.erase(id)
	if playback_streams.has(id):
		playback_streams[id].queue_free()
		playback_streams.erase(id)

func _is_teammate(player_id: int) -> bool:
	# Implement team checking logic
	return true

# Public API
func get_voice_activity_level() -> float:
	if voice_activity_detector.energy_history.empty():
		return 0.0
	return voice_activity_detector.energy_history.back()

func get_active_speakers() -> Array:
	var speakers = []
	for player_id in voice_peers:
		if voice_peers[player_id].is_speaking:
			speakers.append(player_id)
	return speakers

func test_microphone():
	# Play back microphone input for testing
	pass

func get_audio_devices() -> Array:
	return AudioServer.capture_get_device_list()

func set_audio_device(device: String):
	AudioServer.capture_set_device(device)