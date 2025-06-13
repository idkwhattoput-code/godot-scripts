extends Node

# Audio buses
const BUS_MASTER = "Master"
const BUS_SFX = "SFX"
const BUS_MUSIC = "Music"
const BUS_VOICE = "Voice"
const BUS_AMBIENT = "Ambient"
const BUS_UI = "UI"

# Volume settings (in dB)
var master_volume = 0.0
var sfx_volume = 0.0
var music_volume = 0.0
var voice_volume = 0.0
var ambient_volume = 0.0
var ui_volume = 0.0

# Audio pools
var sfx_players = []
var music_players = []
var ambient_players = []
var voice_player = null

# Configuration
export var max_sfx_players = 32
export var sfx_pool_size = 8
export var enable_3d_audio = true
export var enable_reverb_zones = true
export var enable_occlusion = true

# Music system
var current_music_track = ""
var music_queue = []
var is_music_fading = false
var music_fade_time = 2.0

# Sound libraries
var sound_libraries = {}
var footstep_sounds = {}
var impact_sounds = {}
var ambient_sounds = {}

# 3D audio settings
export var max_hearing_distance = 50.0
export var doppler_effect_scale = 1.0
export var attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
export var unit_size = 1.0

# Reverb zones
var reverb_zones = []
var current_reverb_zone = null

# Audio occlusion
var occlusion_checks = []
var occlusion_update_rate = 0.1
var occlusion_timer = 0.0

signal music_changed(track_name)
signal sound_played(sound_name, position)
signal reverb_zone_entered(zone)
signal reverb_zone_exited(zone)

func _ready():
	_setup_audio_buses()
	_create_audio_pools()
	_load_sound_libraries()
	
	set_process(true)

func _setup_audio_buses():
	# Ensure all buses exist
	var bus_layout = AudioServer.bus_count
	
	# Set default volumes
	set_bus_volume(BUS_MASTER, master_volume)
	set_bus_volume(BUS_SFX, sfx_volume)
	set_bus_volume(BUS_MUSIC, music_volume)
	set_bus_volume(BUS_VOICE, voice_volume)
	set_bus_volume(BUS_AMBIENT, ambient_volume)
	set_bus_volume(BUS_UI, ui_volume)

func _create_audio_pools():
	# Create SFX player pool
	for i in range(max_sfx_players):
		var player = AudioStreamPlayer3D.new() if enable_3d_audio else AudioStreamPlayer.new()
		player.bus = BUS_SFX
		add_child(player)
		sfx_players.append({
			"player": player,
			"in_use": false,
			"priority": 0
		})
	
	# Create music players for crossfading
	for i in range(2):
		var player = AudioStreamPlayer.new()
		player.bus = BUS_MUSIC
		add_child(player)
		music_players.append(player)
	
	# Create ambient sound players
	for i in range(4):
		var player = AudioStreamPlayer3D.new() if enable_3d_audio else AudioStreamPlayer.new()
		player.bus = BUS_AMBIENT
		add_child(player)
		ambient_players.append(player)
	
	# Create voice player
	voice_player = AudioStreamPlayer.new()
	voice_player.bus = BUS_VOICE
	add_child(voice_player)

func _load_sound_libraries():
	# Load footstep sounds
	footstep_sounds = {
		"concrete": [
			preload("res://audio/footsteps/concrete_1.ogg"),
			preload("res://audio/footsteps/concrete_2.ogg"),
			preload("res://audio/footsteps/concrete_3.ogg"),
			preload("res://audio/footsteps/concrete_4.ogg")
		],
		"grass": [
			preload("res://audio/footsteps/grass_1.ogg"),
			preload("res://audio/footsteps/grass_2.ogg"),
			preload("res://audio/footsteps/grass_3.ogg"),
			preload("res://audio/footsteps/grass_4.ogg")
		],
		"metal": [
			preload("res://audio/footsteps/metal_1.ogg"),
			preload("res://audio/footsteps/metal_2.ogg"),
			preload("res://audio/footsteps/metal_3.ogg"),
			preload("res://audio/footsteps/metal_4.ogg")
		]
	}
	
	# Load impact sounds
	impact_sounds = {
		"small": preload("res://audio/impacts/small_impact.ogg"),
		"medium": preload("res://audio/impacts/medium_impact.ogg"),
		"large": preload("res://audio/impacts/large_impact.ogg"),
		"explosion": preload("res://audio/impacts/explosion.ogg")
	}

func _process(delta):
	_update_music_fade(delta)
	_update_occlusion(delta)
	_cleanup_finished_sounds()

# Volume control
func set_bus_volume(bus_name: String, volume_db: float):
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, volume_db)
		AudioServer.set_bus_mute(bus_idx, volume_db <= -80)

func get_bus_volume(bus_name: String) -> float:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		return AudioServer.get_bus_volume_db(bus_idx)
	return 0.0

# SFX playback
func play_sfx(sound_name: String, position: Vector3 = Vector3.ZERO, volume: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer3D:
	var stream = _get_sound_stream(sound_name)
	if not stream:
		push_warning("Sound not found: " + sound_name)
		return null
	
	var player_data = _get_available_sfx_player()
	if not player_data:
		return null
	
	var player = player_data.player
	player_data.in_use = true
	
	player.stream = stream
	player.volume_db = volume
	player.pitch_scale = pitch
	
	if player is AudioStreamPlayer3D:
		player.global_transform.origin = position
		player.max_distance = max_hearing_distance
		player.attenuation_model = attenuation_model
		player.unit_size = unit_size
		player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP if doppler_effect_scale > 0 else AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	
	player.play()
	emit_signal("sound_played", sound_name, position)
	
	return player

func play_sfx_2d(sound_name: String, volume: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	var stream = _get_sound_stream(sound_name)
	if not stream:
		return null
	
	var player = AudioStreamPlayer.new()
	player.bus = BUS_SFX
	player.stream = stream
	player.volume_db = volume
	player.pitch_scale = pitch
	add_child(player)
	
	player.play()
	player.connect("finished", player, "queue_free")
	
	return player

# Music playback
func play_music(track_name: String, fade_in: bool = true):
	var stream = _get_music_stream(track_name)
	if not stream:
		push_warning("Music track not found: " + track_name)
		return
	
	if current_music_track == track_name:
		return
	
	current_music_track = track_name
	
	if fade_in and music_players[0].playing:
		_crossfade_music(stream)
	else:
		music_players[0].stream = stream
		music_players[0].volume_db = 0 if not fade_in else -80
		music_players[0].play()
		
		if fade_in:
			is_music_fading = true
	
	emit_signal("music_changed", track_name)

func stop_music(fade_out: bool = true):
	if fade_out:
		is_music_fading = true
		music_fade_time = 1.0
	else:
		for player in music_players:
			player.stop()
	
	current_music_track = ""

func queue_music(track_name: String):
	music_queue.append(track_name)

# Footstep sounds
func play_footstep(surface_type: String, position: Vector3, volume: float = 0.0):
	if not footstep_sounds.has(surface_type):
		surface_type = "concrete"  # Default
	
	var sounds = footstep_sounds[surface_type]
	var sound = sounds[randi() % sounds.size()]
	
	var player = _get_available_sfx_player()
	if player:
		player.player.stream = sound
		player.player.volume_db = volume
		player.player.pitch_scale = rand_range(0.9, 1.1)
		
		if player.player is AudioStreamPlayer3D:
			player.player.global_transform.origin = position
		
		player.player.play()
		player.in_use = true

# Impact sounds
func play_impact(impact_force: float, position: Vector3):
	var impact_type = "small"
	if impact_force > 50:
		impact_type = "large"
	elif impact_force > 20:
		impact_type = "medium"
	
	if impact_force > 100:
		impact_type = "explosion"
	
	play_sfx(impact_type, position, 0, rand_range(0.8, 1.2))

# Voice playback
func play_voice(dialogue_id: String, interrupt: bool = true):
	var stream = _get_voice_stream(dialogue_id)
	if not stream:
		return
	
	if interrupt or not voice_player.playing:
		voice_player.stream = stream
		voice_player.play()

# Ambient sounds
func play_ambient(sound_name: String, position: Vector3, loop: bool = true, volume: float = 0.0) -> AudioStreamPlayer3D:
	var stream = _get_sound_stream(sound_name)
	if not stream:
		return null
	
	for player in ambient_players:
		if not player.playing:
			player.stream = stream
			if player is AudioStreamPlayer3D:
				player.global_transform.origin = position
				player.max_distance = max_hearing_distance * 2
			player.volume_db = volume
			player.play()
			
			if loop and stream is AudioStreamOGGVorbis:
				stream.loop = true
			
			return player
	
	return null

func stop_ambient(player: AudioStreamPlayer3D):
	if player in ambient_players:
		player.stop()

# Reverb zones
func register_reverb_zone(zone: Area, reverb_bus: String, blend: float = 0.5):
	reverb_zones.append({
		"area": zone,
		"bus": reverb_bus,
		"blend": blend
	})
	
	zone.connect("body_entered", self, "_on_reverb_zone_entered", [zone])
	zone.connect("body_exited", self, "_on_reverb_zone_exited", [zone])

func _on_reverb_zone_entered(body: Node, zone: Area):
	if body.is_in_group("player"):
		for reverb_data in reverb_zones:
			if reverb_data.area == zone:
				current_reverb_zone = reverb_data
				_apply_reverb(reverb_data)
				emit_signal("reverb_zone_entered", zone)
				break

func _on_reverb_zone_exited(body: Node, zone: Area):
	if body.is_in_group("player") and current_reverb_zone and current_reverb_zone.area == zone:
		_remove_reverb()
		current_reverb_zone = null
		emit_signal("reverb_zone_exited", zone)

func _apply_reverb(reverb_data: Dictionary):
	# Apply reverb effect to appropriate buses
	var sfx_idx = AudioServer.get_bus_index(BUS_SFX)
	var reverb_idx = AudioServer.get_bus_index(reverb_data.bus)
	
	# Route SFX to reverb bus
	AudioServer.set_bus_send(sfx_idx, reverb_data.bus)

func _remove_reverb():
	var sfx_idx = AudioServer.get_bus_index(BUS_SFX)
	AudioServer.set_bus_send(sfx_idx, BUS_MASTER)

# Audio occlusion
func enable_occlusion_for_player(player: AudioStreamPlayer3D, check_rate: float = 0.1):
	occlusion_checks.append({
		"player": player,
		"rate": check_rate,
		"timer": 0.0,
		"occluded": false
	})

func _update_occlusion(delta):
	if not enable_occlusion:
		return
	
	occlusion_timer += delta
	
	for check in occlusion_checks:
		check.timer += delta
		if check.timer >= check.rate:
			check.timer = 0.0
			_check_occlusion(check)

func _check_occlusion(check_data: Dictionary):
	var player = check_data.player
	if not player.playing:
		return
	
	var listener = get_viewport().get_camera()
	if not listener:
		return
	
	var space_state = player.get_world().direct_space_state
	var result = space_state.intersect_ray(
		player.global_transform.origin,
		listener.global_transform.origin,
		[player]
	)
	
	var was_occluded = check_data.occluded
	check_data.occluded = result.size() > 0
	
	if check_data.occluded != was_occluded:
		# Apply occlusion effect
		if check_data.occluded:
			player.volume_db -= 10  # Reduce volume
			# Could also apply low-pass filter here
		else:
			player.volume_db += 10  # Restore volume

# Helper functions
func _get_available_sfx_player() -> Dictionary:
	# First try to find unused player
	for player_data in sfx_players:
		if not player_data.in_use and not player_data.player.playing:
			return player_data
	
	# Find lowest priority playing sound
	var lowest_priority = null
	for player_data in sfx_players:
		if not lowest_priority or player_data.priority < lowest_priority.priority:
			lowest_priority = player_data
	
	if lowest_priority:
		lowest_priority.player.stop()
		return lowest_priority
	
	return {}

func _get_sound_stream(sound_name: String) -> AudioStream:
	# Check libraries
	if sound_libraries.has(sound_name):
		return sound_libraries[sound_name]
	
	# Try to load from file
	var path = "res://audio/sfx/" + sound_name + ".ogg"
	if ResourceLoader.exists(path):
		return load(path)
	
	return null

func _get_music_stream(track_name: String) -> AudioStream:
	var path = "res://audio/music/" + track_name + ".ogg"
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _get_voice_stream(dialogue_id: String) -> AudioStream:
	var path = "res://audio/voice/" + dialogue_id + ".ogg"
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _update_music_fade(delta):
	if not is_music_fading:
		return
	
	var fade_complete = true
	
	for player in music_players:
		if player.playing:
			if player.volume_db < 0:
				player.volume_db = min(player.volume_db + (60 * delta / music_fade_time), 0)
				if player.volume_db < 0:
					fade_complete = false
			elif player.volume_db > -80:
				player.volume_db = max(player.volume_db - (60 * delta / music_fade_time), -80)
				if player.volume_db > -80:
					fade_complete = false
				else:
					player.stop()
	
	if fade_complete:
		is_music_fading = false
		
		# Check music queue
		if music_queue.size() > 0:
			var next_track = music_queue.pop_front()
			play_music(next_track)

func _crossfade_music(new_stream: AudioStream):
	var current_player = music_players[0]
	var next_player = music_players[1]
	
	# Swap players
	music_players[0] = next_player
	music_players[1] = current_player
	
	next_player.stream = new_stream
	next_player.volume_db = -80
	next_player.play()
	
	is_music_fading = true

func _cleanup_finished_sounds():
	for player_data in sfx_players:
		if player_data.in_use and not player_data.player.playing:
			player_data.in_use = false
			player_data.priority = 0

func set_listener_position(position: Vector3):
	# Update audio listener position for 2D falloff calculations
	pass

func get_playing_sounds_count() -> int:
	var count = 0
	for player_data in sfx_players:
		if player_data.in_use:
			count += 1
	return count