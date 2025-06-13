extends Node

# Environment types
enum Environment {
	FOREST,
	OCEAN,
	CITY,
	MOUNTAIN,
	DESERT,
	CAVE,
	SWAMP,
	ARCTIC,
	SPACE,
	UNDERWATER
}

# Time of day
enum TimeOfDay {
	DAWN,
	MORNING,
	NOON,
	AFTERNOON,
	DUSK,
	NIGHT,
	LATE_NIGHT
}

# Weather conditions
enum Weather {
	CLEAR,
	RAIN,
	STORM,
	SNOW,
	FOG,
	WIND
}

# Current state
var current_environment = Environment.FOREST
var current_time = TimeOfDay.MORNING
var current_weather = Weather.CLEAR
var intensity = 1.0

# Audio layers
var ambient_layers = {}
var weather_layers = {}
var creature_sounds = {}
var detail_sounds = {}

# Playback management
var layer_players = []
var creature_timers = {}
var detail_positions = []
var active_sounds = []

# Configuration
export var max_concurrent_sounds = 16
export var fade_time = 2.0
export var dynamic_volume = true
export var spatial_sounds = true
export var listener_node_path: NodePath

# Sound libraries
var sound_libraries = {
	"forest": {
		"ambient": ["forest_birds", "wind_trees", "leaves_rustle"],
		"creatures": ["owl_hoot", "wolf_howl", "cricket_chirp", "frog_croak"],
		"details": ["branch_snap", "bush_rustle", "water_drip"]
	},
	"ocean": {
		"ambient": ["waves_crash", "wind_ocean", "seagulls"],
		"creatures": ["whale_song", "dolphin_click", "seal_bark"],
		"details": ["splash", "foam", "sand_shift"]
	},
	"city": {
		"ambient": ["traffic_distant", "city_hum", "crowd_chatter"],
		"creatures": ["pigeon_coo", "dog_bark", "cat_meow"],
		"details": ["car_horn", "footsteps", "door_slam"]
	}
}

# Environmental parameters
var environment_params = {
	Environment.FOREST: {
		"reverb": 0.3,
		"density": 0.8,
		"frequency": 1.0,
		"variation": 0.7
	},
	Environment.OCEAN: {
		"reverb": 0.1,
		"density": 0.6,
		"frequency": 0.8,
		"variation": 0.5
	},
	Environment.CITY: {
		"reverb": 0.2,
		"density": 1.0,
		"frequency": 1.2,
		"variation": 0.9
	}
}

signal environment_changed(env)
signal time_changed(time)
signal weather_changed(weather)
signal creature_sound_played(sound_name, position)
signal detail_sound_played(sound_name, position)

func _ready():
	_initialize_players()
	_setup_timers()
	set_process(true)

func _initialize_players():
	# Create layer players for ambient sounds
	for i in range(4):
		var player = AudioStreamPlayer.new()
		player.bus = "Ambient"
		add_child(player)
		layer_players.append(player)
	
	# Create spatial players for creatures and details
	for i in range(max_concurrent_sounds):
		var player = AudioStreamPlayer3D.new() if spatial_sounds else AudioStreamPlayer.new()
		player.bus = "Ambient"
		add_child(player)
		active_sounds.append({
			"player": player,
			"in_use": false,
			"type": "",
			"fade_out": false
		})

func _setup_timers():
	# Creature sound timers
	for i in range(4):
		var timer = Timer.new()
		timer.one_shot = true
		timer.connect("timeout", self, "_play_random_creature_sound", [i])
		add_child(timer)
		creature_timers[i] = timer

func _process(delta):
	_update_ambient_layers(delta)
	_update_active_sounds(delta)
	_check_detail_triggers()

func set_environment(env: int, transition_time: float = -1):
	if transition_time < 0:
		transition_time = fade_time
	
	var old_environment = current_environment
	current_environment = env
	
	# Crossfade ambient layers
	_transition_ambient_layers(old_environment, env, transition_time)
	
	# Update creature sounds
	_update_creature_schedule()
	
	emit_signal("environment_changed", env)

func set_time_of_day(time: int, transition_time: float = -1):
	if transition_time < 0:
		transition_time = fade_time * 2
	
	current_time = time
	
	# Adjust ambient volumes and frequencies
	_adjust_for_time_of_day()
	
	emit_signal("time_changed", time)

func set_weather(weather: int, transition_time: float = -1):
	if transition_time < 0:
		transition_time = fade_time
	
	current_weather = weather
	
	# Add/remove weather layers
	_update_weather_layers(transition_time)
	
	emit_signal("weather_changed", weather)

func _transition_ambient_layers(from_env: int, to_env: int, duration: float):
	# Get sound library for new environment
	var env_name = _get_environment_name(to_env)
	
	if not sound_libraries.has(env_name):
		return
	
	var ambient_sounds = sound_libraries[env_name]["ambient"]
	
	# Fade in new layers
	for i in range(min(ambient_sounds.size(), layer_players.size())):
		var player = layer_players[i]
		var sound_path = "res://audio/ambient/" + ambient_sounds[i] + ".ogg"
		
		if ResourceLoader.exists(sound_path):
			var stream = load(sound_path)
			
			# Start new sound
			player.stream = stream
			player.volume_db = -80
			player.play()
			
			# Fade in
			var tween = get_tree().create_tween()
			tween.tween_property(player, "volume_db", _get_layer_volume(i, to_env), duration)

func _update_creature_schedule():
	var params = environment_params.get(current_environment, {})
	var base_frequency = params.get("frequency", 1.0)
	
	# Schedule creature sounds based on environment and time
	for i in creature_timers:
		var timer = creature_timers[i]
		var wait_time = rand_range(5.0, 30.0) / base_frequency
		
		# Adjust for time of day
		match current_time:
			TimeOfDay.DAWN, TimeOfDay.DUSK:
				wait_time *= 0.5  # More active
			TimeOfDay.NIGHT, TimeOfDay.LATE_NIGHT:
				wait_time *= 0.7  # Night creatures
			TimeOfDay.NOON:
				wait_time *= 1.5  # Less active
		
		timer.wait_time = wait_time
		timer.start()

func _play_random_creature_sound(index: int):
	var env_name = _get_environment_name(current_environment)
	
	if not sound_libraries.has(env_name):
		return
	
	var creatures = sound_libraries[env_name].get("creatures", [])
	if creatures.empty():
		return
	
	# Select random creature sound
	var sound_name = creatures[randi() % creatures.size()]
	
	# Get available player
	var sound_data = _get_available_sound_player()
	if not sound_data:
		return
	
	var player = sound_data.player
	sound_data.in_use = true
	sound_data.type = "creature"
	
	# Load and play sound
	var sound_path = "res://audio/creatures/" + sound_name + ".ogg"
	if ResourceLoader.exists(sound_path):
		player.stream = load(sound_path)
		
		# Position sound randomly around listener
		if player is AudioStreamPlayer3D:
			var angle = randf() * TAU
			var distance = rand_range(5, 30)
			var height = rand_range(-2, 5)
			
			var listener = _get_listener()
			if listener:
				var pos = listener.global_transform.origin
				pos += Vector3(cos(angle) * distance, height, sin(angle) * distance)
				player.global_transform.origin = pos
		
		# Vary pitch slightly
		player.pitch_scale = rand_range(0.9, 1.1)
		
		# Volume based on time and weather
		var volume = 0.0
		if current_weather == Weather.RAIN or current_weather == Weather.STORM:
			volume -= 6  # Quieter during rain
		
		player.volume_db = volume
		player.play()
		
		emit_signal("creature_sound_played", sound_name, player.global_transform.origin)
	
	# Reschedule
	creature_timers[index].wait_time = rand_range(10, 60) / environment_params[current_environment].get("frequency", 1.0)
	creature_timers[index].start()

func _adjust_for_time_of_day():
	var volume_modifier = 0.0
	var pitch_modifier = 1.0
	
	match current_time:
		TimeOfDay.DAWN:
			volume_modifier = -3
			pitch_modifier = 1.1  # Higher pitched morning sounds
		TimeOfDay.NIGHT, TimeOfDay.LATE_NIGHT:
			volume_modifier = -6
			pitch_modifier = 0.9  # Lower pitched night ambience
		TimeOfDay.NOON:
			volume_modifier = 3  # Louder during day
	
	# Apply to all ambient layers
	for player in layer_players:
		if player.playing:
			var tween = get_tree().create_tween()
			tween.tween_property(player, "volume_db", player.volume_db + volume_modifier, fade_time)
			tween.parallel().tween_property(player, "pitch_scale", pitch_modifier, fade_time)

func _update_weather_layers(duration: float):
	match current_weather:
		Weather.RAIN:
			_start_weather_sound("rain_medium", -6)
		Weather.STORM:
			_start_weather_sound("rain_heavy", -3)
			_start_weather_sound("thunder_distant", -12)
		Weather.SNOW:
			_start_weather_sound("snow_fall", -9)
		Weather.WIND:
			_start_weather_sound("wind_strong", -6)
		_:
			_stop_all_weather_sounds()

func _start_weather_sound(sound_name: String, volume: float):
	# Find or create weather player
	if not weather_layers.has(sound_name):
		var player = AudioStreamPlayer.new()
		player.bus = "Ambient"
		add_child(player)
		weather_layers[sound_name] = player
	
	var player = weather_layers[sound_name]
	var sound_path = "res://audio/weather/" + sound_name + ".ogg"
	
	if ResourceLoader.exists(sound_path):
		if not player.playing:
			player.stream = load(sound_path)
			player.volume_db = -80
			player.play()
		
		# Fade to target volume
		var tween = get_tree().create_tween()
		tween.tween_property(player, "volume_db", volume, fade_time)

func _stop_all_weather_sounds():
	for sound_name in weather_layers:
		var player = weather_layers[sound_name]
		if player.playing:
			var tween = get_tree().create_tween()
			tween.tween_property(player, "volume_db", -80, fade_time)
			tween.tween_callback(player, "stop")

func _check_detail_triggers():
	var listener = _get_listener()
	if not listener:
		return
	
	var params = environment_params.get(current_environment, {})
	var density = params.get("density", 0.5)
	
	# Random chance to play detail sound
	if randf() < density * 0.001:  # Adjust probability
		_play_detail_sound()

func _play_detail_sound():
	var env_name = _get_environment_name(current_environment)
	
	if not sound_libraries.has(env_name):
		return
	
	var details = sound_libraries[env_name].get("details", [])
	if details.empty():
		return
	
	var sound_name = details[randi() % details.size()]
	var sound_data = _get_available_sound_player()
	
	if not sound_data:
		return
	
	var player = sound_data.player
	sound_data.in_use = true
	sound_data.type = "detail"
	
	var sound_path = "res://audio/details/" + sound_name + ".ogg"
	if ResourceLoader.exists(sound_path):
		player.stream = load(sound_path)
		
		# Position near listener
		if player is AudioStreamPlayer3D:
			var listener = _get_listener()
			if listener:
				var offset = Vector3(
					rand_range(-10, 10),
					rand_range(-2, 2),
					rand_range(-10, 10)
				)
				player.global_transform.origin = listener.global_transform.origin + offset
		
		player.pitch_scale = rand_range(0.8, 1.2)
		player.volume_db = rand_range(-12, 0)
		player.play()
		
		emit_signal("detail_sound_played", sound_name, player.global_transform.origin)

func _update_ambient_layers(delta):
	# Update layer volumes based on intensity
	for i in range(layer_players.size()):
		var player = layer_players[i]
		if player.playing:
			var target_volume = _get_layer_volume(i, current_environment) * intensity
			player.volume_db = lerp(player.volume_db, target_volume, delta)

func _update_active_sounds(delta):
	for sound_data in active_sounds:
		if sound_data.in_use and not sound_data.player.playing:
			sound_data.in_use = false
			sound_data.type = ""
		
		# Handle fade outs
		if sound_data.fade_out:
			sound_data.player.volume_db -= 20 * delta
			if sound_data.player.volume_db <= -80:
				sound_data.player.stop()
				sound_data.fade_out = false

func _get_available_sound_player() -> Dictionary:
	for sound_data in active_sounds:
		if not sound_data.in_use:
			return sound_data
	return {}

func _get_listener() -> Spatial:
	if not listener_node_path.is_empty():
		return get_node(listener_node_path)
	
	var camera = get_viewport().get_camera()
	if camera:
		return camera
	
	return null

func _get_layer_volume(layer: int, env: int) -> float:
	# Base volumes for different layers
	var base_volumes = [-6, -9, -12, -15]
	
	if layer >= base_volumes.size():
		return -80
	
	return base_volumes[layer]

func _get_environment_name(env: int) -> String:
	match env:
		Environment.FOREST: return "forest"
		Environment.OCEAN: return "ocean"
		Environment.CITY: return "city"
		Environment.MOUNTAIN: return "mountain"
		Environment.DESERT: return "desert"
		Environment.CAVE: return "cave"
		Environment.SWAMP: return "swamp"
		Environment.ARCTIC: return "arctic"
		Environment.SPACE: return "space"
		Environment.UNDERWATER: return "underwater"
		_: return "forest"

# Public API

func set_intensity(value: float):
	intensity = clamp(value, 0.0, 1.0)

func trigger_event_sound(event_name: String, position: Vector3 = Vector3.ZERO):
	# Play specific event sounds (explosions, alarms, etc)
	pass

func register_sound_emitter(emitter: Spatial, sound_type: String):
	# Register objects that can trigger contextual sounds
	pass

func get_current_ambience_info() -> Dictionary:
	return {
		"environment": current_environment,
		"time": current_time,
		"weather": current_weather,
		"intensity": intensity,
		"active_sounds": active_sounds.size()
	}