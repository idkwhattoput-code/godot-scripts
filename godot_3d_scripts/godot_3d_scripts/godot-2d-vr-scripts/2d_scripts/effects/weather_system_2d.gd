extends Node2D

class_name WeatherSystem2D

signal weather_changed(old_weather, new_weather)
signal temperature_changed(temperature)
signal wind_changed(wind_vector)
signal season_changed(season)

enum WeatherType {
	CLEAR,
	CLOUDY,
	RAIN,
	HEAVY_RAIN,
	STORM,
	SNOW,
	BLIZZARD,
	FOG,
	WINDY,
	HAIL
}

enum Season {
	SPRING,
	SUMMER,
	AUTUMN,
	WINTER
}

export var current_weather: int = WeatherType.CLEAR
export var enable_weather_transitions: bool = true
export var transition_time: float = 10.0
export var enable_dynamic_weather: bool = true
export var weather_change_interval: float = 120.0
export var enable_seasons: bool = true
export var current_season: int = Season.SUMMER
export var days_per_season: int = 30
export var current_day: int = 0
export var temperature: float = 20.0
export var wind_strength: float = 0.0
export var wind_direction: float = 0.0
export var precipitation_intensity: float = 0.0
export var cloud_coverage: float = 0.0
export var fog_density: float = 0.0
export var lightning_enabled: bool = true
export var particle_limit: int = 1000

var weather_timer: float = 0.0
var transition_progress: float = 0.0
var is_transitioning: bool = false
var target_weather: int = WeatherType.CLEAR
var previous_weather: int = WeatherType.CLEAR
var day_timer: float = 0.0
var lightning_timer: float = 0.0
var next_lightning_time: float = 0.0

var rain_particles: CPUParticles2D
var snow_particles: CPUParticles2D
var fog_layer: ColorRect
var cloud_layer: Node2D
var wind_effect: Node2D
var lightning_flash: ColorRect
var weather_sounds: Dictionary = {}
var ambient_particles: Array = []

class Cloud:
	var sprite: Sprite
	var position: Vector2
	var speed: float
	var scale: float
	var opacity: float
	var layer: int
	
	func _init(pos: Vector2, spd: float, scl: float, op: float, lyr: int):
		position = pos
		speed = spd
		scale = scl
		opacity = op
		layer = lyr

class WeatherPreset:
	var temperature_range: Vector2
	var wind_strength_range: Vector2
	var precipitation_range: Vector2
	var cloud_coverage_range: Vector2
	var fog_density_range: Vector2
	var lightning_chance: float
	var transition_weights: Dictionary
	
	func _init():
		transition_weights = {}

var weather_presets: Dictionary = {}
var clouds: Array = []

func _ready():
	setup_weather_presets()
	setup_particles()
	setup_fog_layer()
	setup_cloud_layer()
	setup_lightning()
	setup_weather_sounds()
	
	apply_weather(current_weather)

func setup_weather_presets():
	var clear = WeatherPreset.new()
	clear.temperature_range = Vector2(15, 30)
	clear.wind_strength_range = Vector2(0, 5)
	clear.precipitation_range = Vector2(0, 0)
	clear.cloud_coverage_range = Vector2(0, 0.2)
	clear.fog_density_range = Vector2(0, 0)
	clear.lightning_chance = 0.0
	clear.transition_weights = {
		WeatherType.CLOUDY: 0.4,
		WeatherType.WINDY: 0.2,
		WeatherType.FOG: 0.1
	}
	weather_presets[WeatherType.CLEAR] = clear
	
	var cloudy = WeatherPreset.new()
	cloudy.temperature_range = Vector2(10, 25)
	cloudy.wind_strength_range = Vector2(5, 15)
	cloudy.precipitation_range = Vector2(0, 0)
	cloudy.cloud_coverage_range = Vector2(0.4, 0.8)
	cloudy.fog_density_range = Vector2(0, 0.1)
	cloudy.lightning_chance = 0.0
	cloudy.transition_weights = {
		WeatherType.CLEAR: 0.3,
		WeatherType.RAIN: 0.4,
		WeatherType.WINDY: 0.2
	}
	weather_presets[WeatherType.CLOUDY] = cloudy
	
	var rain = WeatherPreset.new()
	rain.temperature_range = Vector2(5, 20)
	rain.wind_strength_range = Vector2(10, 25)
	rain.precipitation_range = Vector2(0.3, 0.6)
	rain.cloud_coverage_range = Vector2(0.7, 1.0)
	rain.fog_density_range = Vector2(0.1, 0.3)
	rain.lightning_chance = 0.05
	rain.transition_weights = {
		WeatherType.CLOUDY: 0.3,
		WeatherType.HEAVY_RAIN: 0.3,
		WeatherType.STORM: 0.2,
		WeatherType.CLEAR: 0.2
	}
	weather_presets[WeatherType.RAIN] = rain
	
	var heavy_rain = WeatherPreset.new()
	heavy_rain.temperature_range = Vector2(3, 18)
	heavy_rain.wind_strength_range = Vector2(20, 40)
	heavy_rain.precipitation_range = Vector2(0.6, 1.0)
	heavy_rain.cloud_coverage_range = Vector2(0.9, 1.0)
	heavy_rain.fog_density_range = Vector2(0.2, 0.4)
	heavy_rain.lightning_chance = 0.15
	heavy_rain.transition_weights = {
		WeatherType.RAIN: 0.4,
		WeatherType.STORM: 0.4,
		WeatherType.CLOUDY: 0.2
	}
	weather_presets[WeatherType.HEAVY_RAIN] = heavy_rain
	
	var storm = WeatherPreset.new()
	storm.temperature_range = Vector2(0, 15)
	storm.wind_strength_range = Vector2(40, 80)
	storm.precipitation_range = Vector2(0.8, 1.0)
	storm.cloud_coverage_range = Vector2(1.0, 1.0)
	storm.fog_density_range = Vector2(0.3, 0.5)
	storm.lightning_chance = 0.5
	storm.transition_weights = {
		WeatherType.HEAVY_RAIN: 0.5,
		WeatherType.RAIN: 0.3,
		WeatherType.HAIL: 0.2
	}
	weather_presets[WeatherType.STORM] = storm
	
	var snow = WeatherPreset.new()
	snow.temperature_range = Vector2(-10, 2)
	snow.wind_strength_range = Vector2(5, 20)
	snow.precipitation_range = Vector2(0.3, 0.6)
	snow.cloud_coverage_range = Vector2(0.7, 1.0)
	snow.fog_density_range = Vector2(0.2, 0.4)
	snow.lightning_chance = 0.0
	snow.transition_weights = {
		WeatherType.CLOUDY: 0.3,
		WeatherType.BLIZZARD: 0.3,
		WeatherType.CLEAR: 0.4
	}
	weather_presets[WeatherType.SNOW] = snow
	
	var blizzard = WeatherPreset.new()
	blizzard.temperature_range = Vector2(-20, -5)
	blizzard.wind_strength_range = Vector2(40, 100)
	blizzard.precipitation_range = Vector2(0.8, 1.0)
	blizzard.cloud_coverage_range = Vector2(1.0, 1.0)
	blizzard.fog_density_range = Vector2(0.6, 0.9)
	blizzard.lightning_chance = 0.0
	blizzard.transition_weights = {
		WeatherType.SNOW: 0.6,
		WeatherType.CLOUDY: 0.4
	}
	weather_presets[WeatherType.BLIZZARD] = blizzard
	
	var fog = WeatherPreset.new()
	fog.temperature_range = Vector2(5, 15)
	fog.wind_strength_range = Vector2(0, 5)
	fog.precipitation_range = Vector2(0, 0)
	fog.cloud_coverage_range = Vector2(0.3, 0.6)
	fog.fog_density_range = Vector2(0.5, 0.9)
	fog.lightning_chance = 0.0
	fog.transition_weights = {
		WeatherType.CLEAR: 0.4,
		WeatherType.CLOUDY: 0.4,
		WeatherType.RAIN: 0.2
	}
	weather_presets[WeatherType.FOG] = fog
	
	var windy = WeatherPreset.new()
	windy.temperature_range = Vector2(10, 25)
	windy.wind_strength_range = Vector2(30, 60)
	windy.precipitation_range = Vector2(0, 0)
	windy.cloud_coverage_range = Vector2(0.1, 0.4)
	windy.fog_density_range = Vector2(0, 0)
	windy.lightning_chance = 0.0
	windy.transition_weights = {
		WeatherType.CLEAR: 0.3,
		WeatherType.CLOUDY: 0.4,
		WeatherType.STORM: 0.3
	}
	weather_presets[WeatherType.WINDY] = windy
	
	var hail = WeatherPreset.new()
	hail.temperature_range = Vector2(0, 10)
	hail.wind_strength_range = Vector2(20, 50)
	hail.precipitation_range = Vector2(0.4, 0.8)
	hail.cloud_coverage_range = Vector2(0.8, 1.0)
	hail.fog_density_range = Vector2(0.1, 0.3)
	hail.lightning_chance = 0.3
	hail.transition_weights = {
		WeatherType.STORM: 0.5,
		WeatherType.RAIN: 0.3,
		WeatherType.CLOUDY: 0.2
	}
	weather_presets[WeatherType.HAIL] = hail

func setup_particles():
	rain_particles = CPUParticles2D.new()
	rain_particles.amount = 500
	rain_particles.lifetime = 2.0
	rain_particles.preprocess = 1.0
	rain_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_BOX
	rain_particles.emission_box_extents = Vector3(get_viewport().size.x, 10, 0)
	rain_particles.position = Vector2(get_viewport().size.x / 2, -20)
	rain_particles.direction = Vector2(0, 1)
	rain_particles.initial_velocity = 300.0
	rain_particles.initial_velocity_random = 0.1
	rain_particles.angular_velocity = 0.0
	rain_particles.scale_amount = 0.5
	rain_particles.color = Color(0.6, 0.6, 0.8, 0.6)
	rain_particles.emitting = false
	add_child(rain_particles)
	
	snow_particles = CPUParticles2D.new()
	snow_particles.amount = 300
	snow_particles.lifetime = 5.0
	snow_particles.preprocess = 2.0
	snow_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_BOX
	snow_particles.emission_box_extents = Vector3(get_viewport().size.x, 10, 0)
	snow_particles.position = Vector2(get_viewport().size.x / 2, -20)
	snow_particles.direction = Vector2(0, 1)
	snow_particles.initial_velocity = 50.0
	snow_particles.initial_velocity_random = 0.3
	snow_particles.angular_velocity = 180.0
	snow_particles.angular_velocity_random = 1.0
	snow_particles.scale_amount = 0.8
	snow_particles.scale_amount_random = 0.3
	snow_particles.color = Color(1.0, 1.0, 1.0, 0.8)
	snow_particles.emitting = false
	add_child(snow_particles)

func setup_fog_layer():
	fog_layer = ColorRect.new()
	fog_layer.color = Color(0.7, 0.7, 0.8, 0.0)
	fog_layer.rect_size = get_viewport().size
	fog_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fog_layer)

func setup_cloud_layer():
	cloud_layer = Node2D.new()
	add_child(cloud_layer)

func setup_lightning():
	lightning_flash = ColorRect.new()
	lightning_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	lightning_flash.rect_size = get_viewport().size
	lightning_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lightning_flash)

func setup_weather_sounds():
	pass

func _process(delta):
	if enable_dynamic_weather:
		update_weather_timer(delta)
	
	if enable_seasons:
		update_season_timer(delta)
	
	if is_transitioning:
		update_weather_transition(delta)
	
	update_weather_effects(delta)
	update_wind_effect(delta)
	update_clouds(delta)
	update_lightning(delta)
	update_temperature(delta)

func update_weather_timer(delta):
	weather_timer += delta
	if weather_timer >= weather_change_interval:
		weather_timer = 0.0
		change_weather_randomly()

func update_season_timer(delta):
	day_timer += delta
	if day_timer >= 86400.0:
		day_timer = 0.0
		current_day += 1
		
		if current_day >= days_per_season:
			current_day = 0
			advance_season()

func advance_season():
	var old_season = current_season
	current_season = (current_season + 1) % Season.size()
	emit_signal("season_changed", current_season)
	
	adjust_weather_for_season()

func adjust_weather_for_season():
	match current_season:
		Season.SPRING:
			if current_weather == WeatherType.SNOW or current_weather == WeatherType.BLIZZARD:
				change_weather(WeatherType.RAIN)
		Season.SUMMER:
			if current_weather == WeatherType.SNOW or current_weather == WeatherType.BLIZZARD:
				change_weather(WeatherType.CLEAR)
		Season.AUTUMN:
			if current_weather == WeatherType.SNOW:
				change_weather(WeatherType.RAIN)
		Season.WINTER:
			if current_weather == WeatherType.RAIN:
				change_weather(WeatherType.SNOW)
			elif current_weather == WeatherType.HEAVY_RAIN:
				change_weather(WeatherType.BLIZZARD)

func change_weather_randomly():
	if not current_weather in weather_presets:
		return
	
	var preset = weather_presets[current_weather]
	var total_weight = 0.0
	
	for weather in preset.transition_weights:
		total_weight += preset.transition_weights[weather]
	
	var random_value = randf() * total_weight
	var accumulated_weight = 0.0
	
	for weather in preset.transition_weights:
		accumulated_weight += preset.transition_weights[weather]
		if random_value <= accumulated_weight:
			change_weather(weather)
			break

func change_weather(new_weather: int):
	if new_weather == current_weather:
		return
	
	previous_weather = current_weather
	target_weather = new_weather
	is_transitioning = true
	transition_progress = 0.0
	
	emit_signal("weather_changed", previous_weather, target_weather)

func update_weather_transition(delta):
	transition_progress += delta / transition_time
	
	if transition_progress >= 1.0:
		transition_progress = 1.0
		is_transitioning = false
		current_weather = target_weather
		apply_weather(current_weather)
	else:
		interpolate_weather_values(transition_progress)

func interpolate_weather_values(progress: float):
	var prev_preset = weather_presets.get(previous_weather)
	var next_preset = weather_presets.get(target_weather)
	
	if not prev_preset or not next_preset:
		return
	
	temperature = lerp(
		rand_range(prev_preset.temperature_range.x, prev_preset.temperature_range.y),
		rand_range(next_preset.temperature_range.x, next_preset.temperature_range.y),
		progress
	)
	
	wind_strength = lerp(
		rand_range(prev_preset.wind_strength_range.x, prev_preset.wind_strength_range.y),
		rand_range(next_preset.wind_strength_range.x, next_preset.wind_strength_range.y),
		progress
	)
	
	precipitation_intensity = lerp(
		rand_range(prev_preset.precipitation_range.x, prev_preset.precipitation_range.y),
		rand_range(next_preset.precipitation_range.x, next_preset.precipitation_range.y),
		progress
	)
	
	cloud_coverage = lerp(
		rand_range(prev_preset.cloud_coverage_range.x, prev_preset.cloud_coverage_range.y),
		rand_range(next_preset.cloud_coverage_range.x, next_preset.cloud_coverage_range.y),
		progress
	)
	
	fog_density = lerp(
		rand_range(prev_preset.fog_density_range.x, prev_preset.fog_density_range.y),
		rand_range(next_preset.fog_density_range.x, next_preset.fog_density_range.y),
		progress
	)

func apply_weather(weather: int):
	if not weather in weather_presets:
		return
	
	var preset = weather_presets[weather]
	
	temperature = rand_range(preset.temperature_range.x, preset.temperature_range.y)
	wind_strength = rand_range(preset.wind_strength_range.x, preset.wind_strength_range.y)
	wind_direction = randf() * 360.0
	precipitation_intensity = rand_range(preset.precipitation_range.x, preset.precipitation_range.y)
	cloud_coverage = rand_range(preset.cloud_coverage_range.x, preset.cloud_coverage_range.y)
	fog_density = rand_range(preset.fog_density_range.x, preset.fog_density_range.y)
	
	update_particle_effects()
	spawn_clouds()

func update_weather_effects(delta):
	update_particle_effects()
	update_fog_effect()

func update_particle_effects():
	match current_weather:
		WeatherType.RAIN, WeatherType.HEAVY_RAIN, WeatherType.STORM:
			rain_particles.emitting = true
			snow_particles.emitting = false
			rain_particles.amount = int(precipitation_intensity * particle_limit)
			rain_particles.initial_velocity = 300.0 + wind_strength * 2
		WeatherType.SNOW, WeatherType.BLIZZARD:
			rain_particles.emitting = false
			snow_particles.emitting = true
			snow_particles.amount = int(precipitation_intensity * particle_limit * 0.6)
			snow_particles.initial_velocity = 50.0 + wind_strength
		WeatherType.HAIL:
			rain_particles.emitting = true
			snow_particles.emitting = false
			rain_particles.amount = int(precipitation_intensity * particle_limit * 0.5)
			rain_particles.initial_velocity = 400.0
			rain_particles.scale_amount = 1.0
		_:
			rain_particles.emitting = false
			snow_particles.emitting = false

func update_fog_effect():
	fog_layer.color.a = fog_density * 0.8

func update_wind_effect(delta):
	var wind_vector = Vector2(cos(deg2rad(wind_direction)), sin(deg2rad(wind_direction))) * wind_strength
	
	if rain_particles.emitting:
		rain_particles.gravity = wind_vector
	if snow_particles.emitting:
		snow_particles.gravity = wind_vector * 0.5
	
	emit_signal("wind_changed", wind_vector)

func update_clouds(delta):
	while clouds.size() < int(cloud_coverage * 10):
		spawn_cloud()
	
	var clouds_to_remove = []
	
	for i in range(clouds.size()):
		var cloud = clouds[i]
		cloud.position.x += cloud.speed * wind_strength * delta * 0.1
		
		if cloud.sprite:
			cloud.sprite.position = cloud.position
		
		if cloud.position.x > get_viewport().size.x + 200:
			clouds_to_remove.append(i)
	
	for i in range(clouds_to_remove.size() - 1, -1, -1):
		var cloud = clouds[clouds_to_remove[i]]
		if cloud.sprite:
			cloud.sprite.queue_free()
		clouds.remove(clouds_to_remove[i])

func spawn_cloud():
	var cloud = Cloud.new(
		Vector2(-200, randf() * get_viewport().size.y * 0.5),
		rand_range(0.5, 2.0),
		rand_range(0.5, 1.5),
		rand_range(0.3, 0.8),
		randi() % 3
	)
	
	cloud.sprite = Sprite.new()
	cloud.sprite.texture = preload("res://icon.png")
	cloud.sprite.modulate = Color(0.8, 0.8, 0.8, cloud.opacity * cloud_coverage)
	cloud.sprite.scale = Vector2.ONE * cloud.scale
	cloud.sprite.position = cloud.position
	
	cloud_layer.add_child(cloud.sprite)
	clouds.append(cloud)

func spawn_clouds():
	for cloud in clouds:
		if cloud.sprite:
			cloud.sprite.queue_free()
	clouds.clear()
	
	var cloud_count = int(cloud_coverage * 10)
	for i in range(cloud_count):
		var x = randf() * (get_viewport().size.x + 400) - 200
		var cloud = Cloud.new(
			Vector2(x, randf() * get_viewport().size.y * 0.5),
			rand_range(0.5, 2.0),
			rand_range(0.5, 1.5),
			rand_range(0.3, 0.8),
			randi() % 3
		)
		
		cloud.sprite = Sprite.new()
		cloud.sprite.texture = preload("res://icon.png")
		cloud.sprite.modulate = Color(0.8, 0.8, 0.8, cloud.opacity * cloud_coverage)
		cloud.sprite.scale = Vector2.ONE * cloud.scale
		cloud.sprite.position = cloud.position
		
		cloud_layer.add_child(cloud.sprite)
		clouds.append(cloud)

func update_lightning(delta):
	if not lightning_enabled:
		return
	
	var preset = weather_presets.get(current_weather)
	if not preset or preset.lightning_chance <= 0:
		return
	
	lightning_timer += delta
	
	if lightning_timer >= next_lightning_time:
		if randf() < preset.lightning_chance:
			create_lightning_flash()
		
		lightning_timer = 0.0
		next_lightning_time = rand_range(2.0, 10.0)

func create_lightning_flash():
	var tween = Tween.new()
	add_child(tween)
	
	tween.interpolate_property(lightning_flash, "color:a", 0.0, 0.8, 0.05, Tween.TRANS_LINEAR, Tween.EASE_IN)
	tween.interpolate_property(lightning_flash, "color:a", 0.8, 0.0, 0.2, Tween.TRANS_LINEAR, Tween.EASE_OUT, 0.05)
	tween.start()
	
	yield(tween, "tween_completed")
	tween.queue_free()

func update_temperature(delta):
	var time_factor = 1.0
	var hour = fmod(OS.get_unix_time() / 3600.0, 24.0)
	
	if hour >= 6 and hour <= 18:
		time_factor = 1.0 + 0.2 * sin((hour - 6) * PI / 12)
	else:
		time_factor = 0.8
	
	var season_factor = 1.0
	match current_season:
		Season.SUMMER:
			season_factor = 1.2
		Season.WINTER:
			season_factor = 0.6
		Season.SPRING, Season.AUTUMN:
			season_factor = 0.9
	
	var adjusted_temp = temperature * time_factor * season_factor
	emit_signal("temperature_changed", adjusted_temp)

func set_weather(weather: int):
	current_weather = weather
	apply_weather(weather)

func get_weather_name(weather: int = -1) -> String:
	if weather == -1:
		weather = current_weather
	
	match weather:
		WeatherType.CLEAR: return "Clear"
		WeatherType.CLOUDY: return "Cloudy"
		WeatherType.RAIN: return "Rain"
		WeatherType.HEAVY_RAIN: return "Heavy Rain"
		WeatherType.STORM: return "Storm"
		WeatherType.SNOW: return "Snow"
		WeatherType.BLIZZARD: return "Blizzard"
		WeatherType.FOG: return "Fog"
		WeatherType.WINDY: return "Windy"
		WeatherType.HAIL: return "Hail"
		_: return "Unknown"

func get_season_name(season: int = -1) -> String:
	if season == -1:
		season = current_season
	
	match season:
		Season.SPRING: return "Spring"
		Season.SUMMER: return "Summer"
		Season.AUTUMN: return "Autumn"
		Season.WINTER: return "Winter"
		_: return "Unknown"

func get_wind_vector() -> Vector2:
	return Vector2(cos(deg2rad(wind_direction)), sin(deg2rad(wind_direction))) * wind_strength

func is_precipitating() -> bool:
	return precipitation_intensity > 0.0

func get_visibility() -> float:
	return 1.0 - fog_density