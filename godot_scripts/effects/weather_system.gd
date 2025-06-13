extends Node

export var transition_duration = 10.0
export var auto_weather_change = true
export var weather_change_interval = 300.0

var current_weather = "clear"
var target_weather = "clear"
var transition_progress = 1.0
var weather_timer = 0.0

var weather_presets = {
	"clear": {
		"fog_enabled": false,
		"fog_density": 0.0,
		"fog_color": Color(0.5, 0.6, 0.7),
		"rain_intensity": 0.0,
		"snow_intensity": 0.0,
		"wind_strength": Vector3(2, 0, 1),
		"ambient_light_energy": 1.0,
		"sun_energy": 1.0,
		"cloud_coverage": 0.1,
		"thunder_enabled": false
	},
	"rain": {
		"fog_enabled": true,
		"fog_density": 0.02,
		"fog_color": Color(0.4, 0.4, 0.5),
		"rain_intensity": 1.0,
		"snow_intensity": 0.0,
		"wind_strength": Vector3(8, 0, 5),
		"ambient_light_energy": 0.4,
		"sun_energy": 0.2,
		"cloud_coverage": 0.9,
		"thunder_enabled": false
	},
	"storm": {
		"fog_enabled": true,
		"fog_density": 0.04,
		"fog_color": Color(0.2, 0.2, 0.3),
		"rain_intensity": 2.0,
		"snow_intensity": 0.0,
		"wind_strength": Vector3(15, 0, 10),
		"ambient_light_energy": 0.2,
		"sun_energy": 0.0,
		"cloud_coverage": 1.0,
		"thunder_enabled": true
	},
	"snow": {
		"fog_enabled": true,
		"fog_density": 0.03,
		"fog_color": Color(0.8, 0.8, 0.9),
		"rain_intensity": 0.0,
		"snow_intensity": 1.0,
		"wind_strength": Vector3(5, 0, 3),
		"ambient_light_energy": 0.6,
		"sun_energy": 0.3,
		"cloud_coverage": 0.8,
		"thunder_enabled": false
	},
	"fog": {
		"fog_enabled": true,
		"fog_density": 0.08,
		"fog_color": Color(0.6, 0.6, 0.7),
		"rain_intensity": 0.0,
		"snow_intensity": 0.0,
		"wind_strength": Vector3(1, 0, 0.5),
		"ambient_light_energy": 0.5,
		"sun_energy": 0.1,
		"cloud_coverage": 0.7,
		"thunder_enabled": false
	}
}

var current_values = {}

onready var environment = $Environment
onready var sun_light = $SunLight
onready var rain_particles = $RainParticles
onready var snow_particles = $SnowParticles
onready var wind_area = $WindArea
onready var thunder_timer = $ThunderTimer
onready var rain_audio = $RainAudio
onready var thunder_audio = $ThunderAudio
onready var wind_audio = $WindAudio

signal weather_changed(weather_type)
signal weather_transition_started(from_weather, to_weather)
signal weather_transition_completed(weather_type)

func _ready():
	_initialize_weather_values()
	set_weather(current_weather, true)
	
	if thunder_timer:
		thunder_timer.connect("timeout", self, "_on_thunder_timer")

func _process(delta):
	if auto_weather_change:
		weather_timer += delta
		if weather_timer >= weather_change_interval:
			weather_timer = 0.0
			change_to_random_weather()
	
	if transition_progress < 1.0:
		transition_progress += delta / transition_duration
		transition_progress = min(transition_progress, 1.0)
		_update_weather_transition()
		
		if transition_progress >= 1.0:
			current_weather = target_weather
			emit_signal("weather_transition_completed", current_weather)

func set_weather(weather_type: String, instant: bool = false):
	if not weather_presets.has(weather_type):
		push_error("Unknown weather type: " + weather_type)
		return
	
	if instant:
		current_weather = weather_type
		target_weather = weather_type
		transition_progress = 1.0
		_apply_weather_preset(weather_type)
		emit_signal("weather_changed", weather_type)
	else:
		if weather_type != target_weather:
			target_weather = weather_type
			transition_progress = 0.0
			emit_signal("weather_transition_started", current_weather, target_weather)

func change_to_random_weather():
	var weather_types = weather_presets.keys()
	weather_types.erase(current_weather)
	
	if weather_types.size() > 0:
		var random_weather = weather_types[randi() % weather_types.size()]
		set_weather(random_weather)

func get_current_weather() -> String:
	return current_weather

func get_weather_intensity(weather_param: String) -> float:
	if current_values.has(weather_param):
		return current_values[weather_param]
	return 0.0

func set_transition_duration(duration: float):
	transition_duration = max(0.1, duration)

func set_auto_weather_change(enabled: bool, interval: float = 300.0):
	auto_weather_change = enabled
	weather_change_interval = interval
	weather_timer = 0.0

func _initialize_weather_values():
	current_values = weather_presets["clear"].duplicate()

func _apply_weather_preset(weather_type: String):
	var preset = weather_presets[weather_type]
	current_values = preset.duplicate()
	
	if environment:
		environment.environment.fog_enabled = preset.fog_enabled
		environment.environment.fog_depth_begin = 10.0
		environment.environment.fog_depth_end = 100.0 / (1.0 + preset.fog_density * 50.0)
		environment.environment.fog_color = preset.fog_color
		environment.environment.ambient_light_energy = preset.ambient_light_energy
	
	if sun_light:
		sun_light.light_energy = preset.sun_energy
	
	if rain_particles:
		rain_particles.emitting = preset.rain_intensity > 0
		rain_particles.amount = int(preset.rain_intensity * 1000)
		rain_particles.process_material.initial_velocity = 20.0 * preset.rain_intensity
	
	if snow_particles:
		snow_particles.emitting = preset.snow_intensity > 0
		snow_particles.amount = int(preset.snow_intensity * 500)
	
	if wind_area:
		wind_area.wind_strength = preset.wind_strength
	
	_update_audio(preset)
	_update_thunder(preset.thunder_enabled)

func _update_weather_transition():
	var from_preset = weather_presets[current_weather]
	var to_preset = weather_presets[target_weather]
	
	for param in from_preset:
		if typeof(from_preset[param]) == TYPE_REAL:
			current_values[param] = lerp(from_preset[param], to_preset[param], transition_progress)
		elif typeof(from_preset[param]) == TYPE_BOOL:
			current_values[param] = to_preset[param] if transition_progress > 0.5 else from_preset[param]
		elif typeof(from_preset[param]) == TYPE_COLOR:
			current_values[param] = from_preset[param].linear_interpolate(to_preset[param], transition_progress)
		elif typeof(from_preset[param]) == TYPE_VECTOR3:
			current_values[param] = from_preset[param].linear_interpolate(to_preset[param], transition_progress)
	
	_apply_current_values()

func _apply_current_values():
	if environment:
		environment.environment.fog_enabled = current_values.fog_enabled
		environment.environment.fog_depth_end = 100.0 / (1.0 + current_values.fog_density * 50.0)
		environment.environment.fog_color = current_values.fog_color
		environment.environment.ambient_light_energy = current_values.ambient_light_energy
	
	if sun_light:
		sun_light.light_energy = current_values.sun_energy
	
	if rain_particles:
		rain_particles.emitting = current_values.rain_intensity > 0
		rain_particles.amount = int(current_values.rain_intensity * 1000)
		if rain_particles.process_material:
			rain_particles.process_material.initial_velocity = 20.0 * current_values.rain_intensity
	
	if snow_particles:
		snow_particles.emitting = current_values.snow_intensity > 0
		snow_particles.amount = int(current_values.snow_intensity * 500)
	
	if wind_area:
		wind_area.wind_strength = current_values.wind_strength
	
	_update_audio_volumes()

func _update_audio(preset: Dictionary):
	if rain_audio:
		if preset.rain_intensity > 0:
			rain_audio.volume_db = linear2db(preset.rain_intensity)
			if not rain_audio.playing:
				rain_audio.play()
		else:
			rain_audio.stop()
	
	if wind_audio:
		var wind_intensity = preset.wind_strength.length() / 20.0
		if wind_intensity > 0.1:
			wind_audio.volume_db = linear2db(wind_intensity)
			if not wind_audio.playing:
				wind_audio.play()
		else:
			wind_audio.stop()

func _update_audio_volumes():
	if rain_audio and rain_audio.playing:
		rain_audio.volume_db = linear2db(current_values.rain_intensity)
	
	if wind_audio and wind_audio.playing:
		var wind_intensity = current_values.wind_strength.length() / 20.0
		wind_audio.volume_db = linear2db(wind_intensity)

func _update_thunder(enabled: bool):
	if enabled and thunder_timer:
		if thunder_timer.is_stopped():
			thunder_timer.wait_time = rand_range(5.0, 20.0)
			thunder_timer.start()
	elif thunder_timer:
		thunder_timer.stop()

func _on_thunder_timer():
	if current_values.thunder_enabled:
		_trigger_lightning()
		
		yield(get_tree().create_timer(rand_range(0.1, 0.5)), "timeout")
		
		if thunder_audio:
			thunder_audio.pitch_scale = rand_range(0.8, 1.2)
			thunder_audio.play()
		
		thunder_timer.wait_time = rand_range(5.0, 20.0)
		thunder_timer.start()

func _trigger_lightning():
	if environment:
		var original_energy = environment.environment.ambient_light_energy
		environment.environment.ambient_light_energy = 2.0
		
		yield(get_tree().create_timer(0.1), "timeout")
		environment.environment.ambient_light_energy = original_energy

func add_weather_preset(name: String, preset: Dictionary):
	weather_presets[name] = preset

func remove_weather_preset(name: String):
	if weather_presets.has(name) and name != "clear":
		weather_presets.erase(name)