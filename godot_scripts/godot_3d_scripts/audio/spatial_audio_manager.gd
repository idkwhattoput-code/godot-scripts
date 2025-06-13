extends Node

# Spatial Audio Manager for Godot 3D
# Manages 3D audio sources, ambient sounds, and dynamic audio effects
# Supports audio occlusion, reverb zones, and distance-based mixing

# Audio settings
export var max_audio_sources = 32
export var ambient_fade_time = 2.0
export var master_volume = 1.0
export var use_audio_occlusion = true
export var occlusion_check_interval = 0.1
export var reverb_update_interval = 0.2

# Audio buses
export var master_bus = "Master"
export var sfx_bus = "SFX"
export var ambient_bus = "Ambient"
export var music_bus = "Music"
export var voice_bus = "Voice"

# Distance settings
export var max_hearing_distance = 50.0
export var reference_distance = 10.0
export var rolloff_factor = 1.0

# Pool management
var audio_source_pool = []
var active_sources = []
var ambient_sources = {}
var music_tracks = {}

# Reverb zones
var reverb_zones = []
var current_reverb_zone = null

# Listener reference
var audio_listener: Spatial

# Occlusion
var occlusion_timer = 0.0
var occluded_sources = {}

# Singleton pattern
static var instance: Node

func _ready():
	instance = self
	
	# Initialize audio source pool
	create_audio_pool()
	
	# Find audio listener
	find_audio_listener()
	
	# Setup audio buses
	setup_audio_buses()

func create_audio_pool():
	"""Create a pool of reusable audio sources"""
	for i in max_audio_sources:
		var audio_source = AudioStreamPlayer3D.new()
		audio_source.name = "AudioSource_" + str(i)
		add_child(audio_source)
		audio_source.bus = sfx_bus
		audio_source.unit_db = 0
		audio_source.unit_size = reference_distance
		audio_source.max_db = 3
		audio_source.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		audio_source_pool.append(audio_source)

func find_audio_listener():
	"""Find the active audio listener in the scene"""
	var cameras = get_tree().get_nodes_in_group("cameras")
	for camera in cameras:
		if camera is Camera and camera.current:
			audio_listener = camera
			return
	
	# Fallback to first camera
	var camera = get_tree().get_root().find_node("Camera", true, false)
	if camera:
		audio_listener = camera

func setup_audio_buses():
	"""Setup audio bus configuration"""
	# This assumes audio buses are configured in project settings
	# You can also create them programmatically here
	pass

func _process(delta):
	# Update occlusion
	if use_audio_occlusion:
		occlusion_timer += delta
		if occlusion_timer >= occlusion_check_interval:
			occlusion_timer = 0.0
			update_audio_occlusion()
	
	# Update reverb zones
	update_reverb_zones()
	
	# Update active sources
	update_active_sources()

# Sound playback methods
func play_sound_3d(sound: AudioStream, position: Vector3, volume: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer3D:
	"""Play a 3D sound at a position"""
	var source = get_available_source()
	if not source:
		push_warning("No available audio sources")
		return null
	
	source.stream = sound
	source.global_transform.origin = position
	source.volume_db = volume
	source.pitch_scale = pitch
	source.play()
	
	active_sources.append(source)
	
	return source

func play_sound_3d_attached(sound: AudioStream, target: Spatial, volume: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer3D:
	"""Play a 3D sound attached to a node"""
	var source = play_sound_3d(sound, target.global_transform.origin, volume, pitch)
	if source:
		# Attach to target
		target.add_child(source)
		source.transform.origin = Vector3.ZERO
	
	return source

func play_sound_2d(sound: AudioStream, volume: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	"""Play a 2D (non-spatial) sound"""
	var source = AudioStreamPlayer.new()
	add_child(source)
	source.stream = sound
	source.volume_db = volume
	source.pitch_scale = pitch
	source.bus = sfx_bus
	source.play()
	
	# Auto-remove when finished
	source.connect("finished", source, "queue_free")
	
	return source

# Ambient sound methods
func play_ambient_sound(id: String, sound: AudioStream, position: Vector3, volume: float = 0.0, fade_in: bool = true):
	"""Play an ambient sound that loops"""
	if id in ambient_sources:
		return  # Already playing
	
	var source = get_available_source()
	if not source:
		return
	
	source.stream = sound
	source.global_transform.origin = position
	source.bus = ambient_bus
	source.stream.loop = true
	
	if fade_in:
		source.volume_db = -80
		source.play()
		fade_audio_source(source, volume, ambient_fade_time)
	else:
		source.volume_db = volume
		source.play()
	
	ambient_sources[id] = source
	active_sources.append(source)

func stop_ambient_sound(id: String, fade_out: bool = true):
	"""Stop an ambient sound"""
	if not id in ambient_sources:
		return
	
	var source = ambient_sources[id]
	
	if fade_out:
		fade_audio_source(source, -80, ambient_fade_time)
		yield(get_tree().create_timer(ambient_fade_time), "timeout")
	
	source.stop()
	active_sources.erase(source)
	ambient_sources.erase(id)
	audio_source_pool.append(source)

func update_ambient_position(id: String, new_position: Vector3):
	"""Update position of ambient sound"""
	if id in ambient_sources:
		ambient_sources[id].global_transform.origin = new_position

# Music methods
func play_music(track_name: String, sound: AudioStream, volume: float = 0.0, fade_in: bool = true):
	"""Play a music track"""
	if track_name in music_tracks:
		return  # Already playing
	
	var source = AudioStreamPlayer.new()
	add_child(source)
	source.stream = sound
	source.bus = music_bus
	source.stream.loop = true
	
	if fade_in:
		source.volume_db = -80
		source.play()
		fade_audio_source(source, volume, ambient_fade_time)
	else:
		source.volume_db = volume
		source.play()
	
	music_tracks[track_name] = source

func stop_music(track_name: String, fade_out: bool = true):
	"""Stop a music track"""
	if not track_name in music_tracks:
		return
	
	var source = music_tracks[track_name]
	
	if fade_out:
		fade_audio_source(source, -80, ambient_fade_time)
		yield(get_tree().create_timer(ambient_fade_time), "timeout")
	
	source.queue_free()
	music_tracks.erase(track_name)

func crossfade_music(from_track: String, to_track: String, sound: AudioStream, duration: float = 2.0):
	"""Crossfade between music tracks"""
	if from_track in music_tracks:
		stop_music(from_track, true)
	
	play_music(to_track, sound, 0.0, true)

# Audio source management
func get_available_source() -> AudioStreamPlayer3D:
	"""Get an available audio source from the pool"""
	for source in audio_source_pool:
		if not source.playing:
			audio_source_pool.erase(source)
			return source
	
	# All sources in use, steal oldest one
	if active_sources.size() > 0:
		var oldest = active_sources[0]
		oldest.stop()
		active_sources.erase(oldest)
		return oldest
	
	return null

func update_active_sources():
	"""Update and clean up active audio sources"""
	var to_remove = []
	
	for source in active_sources:
		if not source.playing:
			to_remove.append(source)
	
	for source in to_remove:
		active_sources.erase(source)
		audio_source_pool.append(source)
		
		# Reset source to pool state
		if source.get_parent() != self:
			source.get_parent().remove_child(source)
			add_child(source)

# Audio occlusion
func update_audio_occlusion():
	"""Check for audio occlusion between sources and listener"""
	if not audio_listener:
		return
	
	var space_state = get_world().direct_space_state
	var listener_pos = audio_listener.global_transform.origin
	
	for source in active_sources:
		if not source.playing:
			continue
		
		var source_pos = source.global_transform.origin
		var result = space_state.intersect_ray(listener_pos, source_pos, [audio_listener])
		
		if result:
			# Source is occluded
			if not source in occluded_sources:
				occluded_sources[source] = source.volume_db
				# Reduce volume for occlusion
				source.volume_db -= 10
		else:
			# Source is not occluded
			if source in occluded_sources:
				source.volume_db = occluded_sources[source]
				occluded_sources.erase(source)

# Reverb zones
func register_reverb_zone(zone: Area, reverb_bus: String, blend: float = 1.0):
	"""Register a reverb zone"""
	reverb_zones.append({
		"area": zone,
		"bus": reverb_bus,
		"blend": blend
	})
	
	zone.connect("body_entered", self, "_on_reverb_zone_entered", [zone])
	zone.connect("body_exited", self, "_on_reverb_zone_exited", [zone])

func _on_reverb_zone_entered(body: Node, zone: Area):
	"""Handle entering reverb zone"""
	if body == audio_listener or (audio_listener and body == audio_listener.get_parent()):
		for reverb_data in reverb_zones:
			if reverb_data.area == zone:
				current_reverb_zone = reverb_data
				apply_reverb_settings(reverb_data)
				break

func _on_reverb_zone_exited(body: Node, zone: Area):
	"""Handle exiting reverb zone"""
	if body == audio_listener or (audio_listener and body == audio_listener.get_parent()):
		if current_reverb_zone and current_reverb_zone.area == zone:
			current_reverb_zone = null
			remove_reverb_settings()

func apply_reverb_settings(reverb_data: Dictionary):
	"""Apply reverb settings to audio buses"""
	# This would typically involve adjusting audio bus effects
	# Example: AudioServer.set_bus_effect_enabled(bus_idx, effect_idx, true)
	pass

func remove_reverb_settings():
	"""Remove reverb settings"""
	# Reset audio bus effects
	pass

func update_reverb_zones():
	"""Update reverb zone blending"""
	# Implement smooth transitions between reverb zones
	pass

# Utility methods
func fade_audio_source(source: Node, target_volume: float, duration: float):
	"""Fade audio source volume"""
	var start_volume = source.volume_db
	var elapsed = 0.0
	
	while elapsed < duration:
		elapsed += get_process_delta_time()
		var t = elapsed / duration
		source.volume_db = lerp(start_volume, target_volume, t)
		yield(get_tree(), "idle_frame")

func set_master_volume(volume: float):
	"""Set master volume (0-1)"""
	master_volume = clamp(volume, 0.0, 1.0)
	var db = linear2db(master_volume)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(master_bus), db)

func set_bus_volume(bus_name: String, volume: float):
	"""Set specific bus volume (0-1)"""
	var db = linear2db(clamp(volume, 0.0, 1.0))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus_name), db)

func get_listener_position() -> Vector3:
	"""Get current audio listener position"""
	if audio_listener:
		return audio_listener.global_transform.origin
	return Vector3.ZERO

# Static helper methods
static func play_3d(sound: AudioStream, position: Vector3, volume: float = 0.0) -> AudioStreamPlayer3D:
	"""Static method to play 3D sound"""
	if instance:
		return instance.play_sound_3d(sound, position, volume)
	return null

static func play_2d(sound: AudioStream, volume: float = 0.0) -> AudioStreamPlayer:
	"""Static method to play 2D sound"""
	if instance:
		return instance.play_sound_2d(sound, volume)
	return null