extends Area

# Zone properties
export var zone_name = "Default Zone"
export var zone_priority = 0
export var fade_distance = 5.0
export var enable_reverb = true
export var enable_occlusion = true
export var enable_ambient_sounds = true

# Reverb settings
export var reverb_room_size = 0.8
export var reverb_damping = 0.5
export var reverb_spread = 0.5
export var reverb_dry = 0.7
export var reverb_wet = 0.3
export var reverb_predelay = 0.05
export var reverb_hpf = 0.0

# Environmental audio
export var ambient_volume = -10.0
export var ambient_sounds = []  # Array of audio streams
export var randomize_ambient = true
export var ambient_interval_min = 5.0
export var ambient_interval_max = 15.0

# Acoustic properties
export var air_absorption = 1.0
export var sound_speed_modifier = 1.0
export var doppler_factor = 1.0

# Audio filters
export var enable_lowpass = false
export var lowpass_cutoff = 5000.0
export var enable_highpass = false
export var highpass_cutoff = 200.0

# Material presets
enum MaterialPreset {
	CUSTOM,
	STONE,
	WOOD,
	METAL,
	GLASS,
	CARPET,
	OUTDOOR,
	CAVE,
	UNDERWATER
}
export var material_preset = MaterialPreset.CUSTOM

# Active listeners
var active_listeners = []
var zone_bus_name = ""
var reverb_effect = null
var ambient_players = []
var ambient_timer = 0.0

# Occlusion
var occlusion_nodes = []
var occlusion_cache = {}

signal listener_entered(listener)
signal listener_exited(listener)
signal zone_became_active()
signal zone_became_inactive()

func _ready():
	_setup_zone()
	_apply_material_preset()
	_create_reverb_bus()
	_setup_ambient_sounds()
	
	connect("body_entered", self, "_on_body_entered")
	connect("body_exited", self, "_on_body_exited")
	
	set_process(false)

func _setup_zone():
	collision_layer = 0
	collision_mask = 1  # Only detect layer 1 (usually player)
	monitoring = true

func _apply_material_preset():
	match material_preset:
		MaterialPreset.STONE:
			reverb_room_size = 0.9
			reverb_damping = 0.3
			reverb_spread = 0.8
			reverb_wet = 0.4
			air_absorption = 0.8
		
		MaterialPreset.WOOD:
			reverb_room_size = 0.7
			reverb_damping = 0.7
			reverb_spread = 0.5
			reverb_wet = 0.2
			air_absorption = 1.2
		
		MaterialPreset.METAL:
			reverb_room_size = 0.8
			reverb_damping = 0.2
			reverb_spread = 0.9
			reverb_wet = 0.5
			air_absorption = 0.7
		
		MaterialPreset.GLASS:
			reverb_room_size = 0.6
			reverb_damping = 0.1
			reverb_spread = 0.7
			reverb_wet = 0.3
			air_absorption = 0.9
		
		MaterialPreset.CARPET:
			reverb_room_size = 0.4
			reverb_damping = 0.9
			reverb_spread = 0.3
			reverb_wet = 0.1
			air_absorption = 2.0
		
		MaterialPreset.OUTDOOR:
			reverb_room_size = 1.0
			reverb_damping = 0.1
			reverb_spread = 1.0
			reverb_wet = 0.1
			air_absorption = 1.5
			enable_reverb = false
		
		MaterialPreset.CAVE:
			reverb_room_size = 1.0
			reverb_damping = 0.4
			reverb_spread = 0.9
			reverb_wet = 0.6
			reverb_predelay = 0.1
			air_absorption = 0.5
		
		MaterialPreset.UNDERWATER:
			reverb_room_size = 0.9
			reverb_damping = 0.8
			reverb_spread = 0.6
			reverb_wet = 0.7
			enable_lowpass = true
			lowpass_cutoff = 2000.0
			air_absorption = 3.0
			sound_speed_modifier = 4.0

func _create_reverb_bus():
	zone_bus_name = "Zone_" + zone_name.replace(" ", "_")
	
	# Check if bus exists
	var bus_idx = AudioServer.get_bus_index(zone_bus_name)
	if bus_idx == -1:
		# Create new bus
		bus_idx = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(bus_idx, zone_bus_name)
		AudioServer.set_bus_send(bus_idx, "Master")
	
	# Add reverb effect
	if enable_reverb:
		reverb_effect = AudioEffectReverb.new()
		reverb_effect.room_size = reverb_room_size
		reverb_effect.damping = reverb_damping
		reverb_effect.spread = reverb_spread
		reverb_effect.dry = reverb_dry
		reverb_effect.wet = reverb_wet
		reverb_effect.predelay_msec = reverb_predelay * 1000
		reverb_effect.hipass = reverb_hpf
		
		AudioServer.add_bus_effect(bus_idx, reverb_effect)
	
	# Add filter effects
	if enable_lowpass:
		var lowpass = AudioEffectLowPassFilter.new()
		lowpass.cutoff_hz = lowpass_cutoff
		AudioServer.add_bus_effect(bus_idx, lowpass)
	
	if enable_highpass:
		var highpass = AudioEffectHighPassFilter.new()
		highpass.cutoff_hz = highpass_cutoff
		AudioServer.add_bus_effect(bus_idx, highpass)

func _setup_ambient_sounds():
	if not enable_ambient_sounds or ambient_sounds.empty():
		return
	
	# Create ambient sound players
	for i in range(3):  # Pool of 3 ambient players
		var player = AudioStreamPlayer3D.new()
		player.bus = zone_bus_name
		player.unit_size = 10.0
		player.max_distance = fade_distance * 2
		player.volume_db = ambient_volume
		add_child(player)
		ambient_players.append(player)

func _process(delta):
	if active_listeners.empty():
		return
	
	_update_ambient_sounds(delta)
	_update_listener_blend()
	
	if enable_occlusion:
		_update_occlusion()

func _update_ambient_sounds(delta):
	if not enable_ambient_sounds or ambient_sounds.empty():
		return
	
	ambient_timer -= delta
	
	if ambient_timer <= 0:
		_play_random_ambient()
		ambient_timer = rand_range(ambient_interval_min, ambient_interval_max)

func _play_random_ambient():
	# Find available player
	var available_player = null
	for player in ambient_players:
		if not player.playing:
			available_player = player
			break
	
	if not available_player:
		return
	
	# Select random sound
	var sound = ambient_sounds[randi() % ambient_sounds.size()]
	available_player.stream = sound
	
	# Random position within zone
	if randomize_ambient:
		var zone_shape = $CollisionShape.shape
		if zone_shape is BoxShape:
			var extents = zone_shape.extents
			var random_pos = Vector3(
				rand_range(-extents.x, extents.x),
				rand_range(-extents.y, extents.y),
				rand_range(-extents.z, extents.z)
			)
			available_player.translation = random_pos
	
	available_player.play()

func _update_listener_blend():
	for listener in active_listeners:
		if not is_instance_valid(listener):
			active_listeners.erase(listener)
			continue
		
		var distance = _get_distance_to_zone_edge(listener.global_transform.origin)
		var blend = 1.0
		
		if distance < fade_distance:
			blend = distance / fade_distance
			blend = smoothstep(0.0, 1.0, blend)
		
		# Apply blend to listener's audio output
		if listener.has_method("set_zone_blend"):
			listener.set_zone_blend(zone_bus_name, blend)

func _get_distance_to_zone_edge(position: Vector3) -> float:
	# Simple implementation - improve based on actual shape
	var local_pos = to_local(position)
	var shape = $CollisionShape.shape
	
	if shape is BoxShape:
		var extents = shape.extents
		var x_dist = max(0, abs(local_pos.x) - extents.x)
		var y_dist = max(0, abs(local_pos.y) - extents.y)  
		var z_dist = max(0, abs(local_pos.z) - extents.z)
		return Vector3(x_dist, y_dist, z_dist).length()
	
	return 0.0

func _update_occlusion():
	occlusion_cache.clear()
	
	for node in occlusion_nodes:
		if not is_instance_valid(node):
			occlusion_nodes.erase(node)
			continue
		
		for listener in active_listeners:
			if not is_instance_valid(listener):
				continue
			
			var occluded = _check_occlusion(node.global_transform.origin, listener.global_transform.origin)
			occlusion_cache[node] = occluded
			
			if node.has_method("set_occlusion"):
				node.set_occlusion(occluded)

func _check_occlusion(from: Vector3, to: Vector3) -> float:
	var space_state = get_world().direct_space_state
	var result = space_state.intersect_ray(from, to, [self])
	
	if result:
		# Calculate occlusion amount based on material
		var occlusion = 1.0
		if result.collider.has_method("get_occlusion_factor"):
			occlusion = result.collider.get_occlusion_factor()
		return occlusion
	
	return 0.0

func _on_body_entered(body):
	if body.has_method("is_audio_listener") and body.is_audio_listener():
		active_listeners.append(body)
		
		if active_listeners.size() == 1:
			set_process(true)
			emit_signal("zone_became_active")
		
		emit_signal("listener_entered", body)
		
		# Apply zone effects to sounds within
		_apply_zone_to_sounds()

func _on_body_exited(body):
	if body in active_listeners:
		active_listeners.erase(body)
		
		if active_listeners.empty():
			set_process(false)
			emit_signal("zone_became_inactive")
		
		emit_signal("listener_exited", body)
		
		# Remove zone effects
		_remove_zone_from_sounds()

func _apply_zone_to_sounds():
	# Find all 3D audio sources within zone
	var sounds = get_tree().get_nodes_in_group("3d_audio_sources")
	
	for sound in sounds:
		if not sound is AudioStreamPlayer3D:
			continue
		
		if overlaps_body(sound):
			sound.bus = zone_bus_name
			
			# Apply acoustic properties
			if sound.has_method("set_air_absorption"):
				sound.set_air_absorption(air_absorption)
			
			# Register for occlusion
			if enable_occlusion:
				occlusion_nodes.append(sound)

func _remove_zone_from_sounds():
	for sound in get_tree().get_nodes_in_group("3d_audio_sources"):
		if sound.bus == zone_bus_name:
			sound.bus = "Master"
			
			if sound in occlusion_nodes:
				occlusion_nodes.erase(sound)

func register_sound_source(source: AudioStreamPlayer3D):
	if overlaps_body(source):
		source.bus = zone_bus_name
		
		if enable_occlusion:
			occlusion_nodes.append(source)

func unregister_sound_source(source: AudioStreamPlayer3D):
	if source in occlusion_nodes:
		occlusion_nodes.erase(source)
	
	if source.bus == zone_bus_name:
		source.bus = "Master"

func get_reverb_send_level(position: Vector3) -> float:
	if not enable_reverb:
		return 0.0
	
	var distance = _get_distance_to_zone_edge(position)
	if distance > fade_distance:
		return reverb_wet
	
	return lerp(0.0, reverb_wet, distance / fade_distance)

func get_zone_info() -> Dictionary:
	return {
		"name": zone_name,
		"priority": zone_priority,
		"reverb_enabled": enable_reverb,
		"reverb_wet": reverb_wet,
		"air_absorption": air_absorption,
		"active_listeners": active_listeners.size()
	}