extends Node2D

signal weather_changed(old_weather: String, new_weather: String)
signal rain_started
signal rain_stopped
signal snow_started
signal snow_stopped
signal storm_started
signal storm_stopped

@export_group("Weather Types")
@export var enable_rain: bool = true
@export var enable_snow: bool = true
@export var enable_storm: bool = true
@export var enable_fog: bool = true
@export var enable_wind: bool = true

@export_group("Weather Timing")
@export var weather_change_interval: float = 120.0
@export var transition_duration: float = 10.0
@export var weather_probabilities: Dictionary = {
	"clear": 0.4,
	"rain": 0.2,
	"snow": 0.1,
	"storm": 0.1,
	"fog": 0.2
}

@export_group("Rain Settings")
@export var rain_particle_scene: PackedScene
@export var rain_density: int = 500
@export var rain_speed: Vector2 = Vector2(50, 400)
@export var rain_angle: float = 10.0
@export var rain_color: Color = Color(0.6, 0.7, 0.8, 0.6)
@export var puddle_scene: PackedScene

@export_group("Snow Settings")
@export var snow_particle_scene: PackedScene
@export var snow_density: int = 300
@export var snow_speed: Vector2 = Vector2(30, 60)
@export var snow_sway_amount: float = 20.0
@export var snow_accumulation: bool = true

@export_group("Storm Settings")
@export var lightning_frequency: float = 5.0
@export var thunder_delay: float = 3.0
@export var storm_darkness: float = 0.7
@export var lightning_scene: PackedScene
@export var thunder_sounds: Array[AudioStream] = []

@export_group("Fog Settings")
@export var fog_density: float = 0.8
@export var fog_color: Color = Color(0.7, 0.7, 0.7, 0.6)
@export var fog_speed: float = 10.0
@export var fog_texture: Texture2D

@export_group("Wind Settings")
@export var wind_strength: float = 100.0
@export var wind_direction: Vector2 = Vector2(1, 0)
@export var wind_variation: float = 30.0
@export var affect_particles: bool = true
@export var affect_objects: bool = true

@export_group("Visual Effects")
@export var screen_overlay: ColorRect
@export var ambient_light_clear: Color = Color.WHITE
@export var ambient_light_rain: Color = Color(0.7, 0.7, 0.8)
@export var ambient_light_storm: Color = Color(0.4, 0.4, 0.5)
@export var post_process_effects: bool = true

var current_weather: String = "clear"
var next_weather: String = "clear"
var is_transitioning: bool = false
var transition_progress: float = 0.0
var weather_timer: float = 0.0

var rain_particles: CPUParticles2D
var snow_particles: CPUParticles2D
var fog_layer: Node2D
var lightning_timer: float = 0.0
var wind_timer: float = 0.0
var current_wind_strength: float = 0.0

var audio_player: AudioStreamPlayer2D
var ambient_sound: AudioStreamPlayer2D

func _ready():
	_setup_particles()
	_setup_audio()
	_setup_screen_overlay()
	
	if enable_fog:
		_setup_fog()
	
	_set_weather(current_weather, true)

func _setup_particles():
	# Rain particles
	rain_particles = CPUParticles2D.new()
	rain_particles.emitting = false
	rain_particles.amount = rain_density
	rain_particles.lifetime = 2.0
	rain_particles.preprocess = 1.0
	rain_particles.speed_scale = 1.0
	rain_particles.direction = Vector2(sin(deg_to_rad(rain_angle)), 1)
	rain_particles.initial_velocity_min = rain_speed.x
	rain_particles.initial_velocity_max = rain_speed.y
	rain_particles.gravity = Vector2.ZERO
	rain_particles.scale_amount_min = 0.5
	rain_particles.scale_amount_max = 1.0
	add_child(rain_particles)
	
	# Snow particles
	snow_particles = CPUParticles2D.new()
	snow_particles.emitting = false
	snow_particles.amount = snow_density
	snow_particles.lifetime = 5.0
	snow_particles.preprocess = 2.0
	snow_particles.speed_scale = 1.0
	snow_particles.direction = Vector2(0, 1)
	snow_particles.initial_velocity_min = snow_speed.x
	snow_particles.initial_velocity_max = snow_speed.y
	snow_particles.gravity = Vector2.ZERO
	snow_particles.orbit_velocity_min = -0.1
	snow_particles.orbit_velocity_max = 0.1
	add_child(snow_particles)
	
	# Set emission shape to cover screen
	var viewport_size = get_viewport_rect().size
	rain_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	rain_particles.emission_rect_extents = Vector2(viewport_size.x, 10)
	rain_particles.position = Vector2(viewport_size.x / 2, -50)
	
	snow_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	snow_particles.emission_rect_extents = Vector2(viewport_size.x, 10)
	snow_particles.position = Vector2(viewport_size.x / 2, -50)

func _setup_audio():
	audio_player = AudioStreamPlayer2D.new()
	add_child(audio_player)
	
	ambient_sound = AudioStreamPlayer2D.new()
	ambient_sound.bus = "Ambient"
	add_child(ambient_sound)

func _setup_screen_overlay():
	if not screen_overlay:
		screen_overlay = ColorRect.new()
		screen_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen_overlay.anchor_right = 1.0
		screen_overlay.anchor_bottom = 1.0
		screen_overlay.color = Color.TRANSPARENT
		add_child(screen_overlay)

func _setup_fog():
	fog_layer = Node2D.new()
	fog_layer.modulate = Color(1, 1, 1, 0)
	add_child(fog_layer)
	
	# Create fog sprites
	var viewport_size = get_viewport_rect().size
	for i in range(3):
		var fog_sprite = Sprite2D.new()
		fog_sprite.texture = fog_texture
		fog_sprite.scale = viewport_size / fog_texture.get_size() * 2
		fog_sprite.position = Vector2(randf() * viewport_size.x, randf() * viewport_size.y)
		fog_layer.add_child(fog_sprite)

func _process(delta):
	weather_timer += delta
	
	if weather_timer >= weather_change_interval and not is_transitioning:
		_choose_next_weather()
	
	if is_transitioning:
		_process_transition(delta)
	
	_update_weather_effects(delta)
	_update_wind(delta)

func _choose_next_weather():
	var total_probability = 0.0
	for prob in weather_probabilities.values():
		total_probability += prob
	
	var random_value = randf() * total_probability
	var accumulated = 0.0
	
	for weather in weather_probabilities:
		accumulated += weather_probabilities[weather]
		if random_value <= accumulated:
			if weather != current_weather:
				start_weather_transition(weather)
			break

func start_weather_transition(new_weather: String):
	if is_transitioning:
		return
	
	next_weather = new_weather
	is_transitioning = true
	transition_progress = 0.0
	weather_timer = 0.0
	
	weather_changed.emit(current_weather, next_weather)

func _process_transition(delta):
	transition_progress += delta / transition_duration
	
	if transition_progress >= 1.0:
		transition_progress = 1.0
		is_transitioning = false
		_set_weather(next_weather, false)
		current_weather = next_weather
	
	_interpolate_weather_effects(transition_progress)

func _set_weather(weather: String, instant: bool):
	match weather:
		"clear":
			rain_particles.emitting = false
			snow_particles.emitting = false
			if instant:
				screen_overlay.color = Color.TRANSPARENT
				if fog_layer:
					fog_layer.modulate.a = 0
		
		"rain":
			rain_particles.emitting = true
			snow_particles.emitting = false
			rain_started.emit()
			_play_ambient_sound("rain")
			if instant:
				screen_overlay.color = Color(0.2, 0.2, 0.3, 0.1)
		
		"snow":
			rain_particles.emitting = false
			snow_particles.emitting = true
			snow_started.emit()
			_play_ambient_sound("snow")
			if instant:
				screen_overlay.color = Color(0.8, 0.8, 0.9, 0.1)
		
		"storm":
			rain_particles.emitting = true
			rain_particles.amount = rain_density * 2
			storm_started.emit()
			_play_ambient_sound("storm")
			if instant:
				screen_overlay.color = Color(0.1, 0.1, 0.2, storm_darkness)
		
		"fog":
			rain_particles.emitting = false
			snow_particles.emitting = false
			if fog_layer and instant:
				fog_layer.modulate.a = fog_density

func _interpolate_weather_effects(progress: float):
	# Interpolate screen overlay
	var current_overlay = _get_weather_overlay_color(current_weather)
	var next_overlay = _get_weather_overlay_color(next_weather)
	screen_overlay.color = current_overlay.lerp(next_overlay, progress)
	
	# Interpolate fog
	if fog_layer:
		var current_fog = 0.0 if current_weather != "fog" else fog_density
		var next_fog = 0.0 if next_weather != "fog" else fog_density
		fog_layer.modulate.a = lerp(current_fog, next_fog, progress)
	
	# Interpolate particle density
	if current_weather == "rain" or next_weather == "rain":
		var current_density = rain_density if current_weather == "rain" else 0
		var next_density = rain_density if next_weather == "rain" else 0
		rain_particles.amount = int(lerp(float(current_density), float(next_density), progress))

func _get_weather_overlay_color(weather: String) -> Color:
	match weather:
		"clear":
			return Color.TRANSPARENT
		"rain":
			return Color(0.2, 0.2, 0.3, 0.1)
		"snow":
			return Color(0.8, 0.8, 0.9, 0.1)
		"storm":
			return Color(0.1, 0.1, 0.2, storm_darkness)
		"fog":
			return Color(0.5, 0.5, 0.5, 0.2)
		_:
			return Color.TRANSPARENT

func _update_weather_effects(delta):
	if current_weather == "storm" or (is_transitioning and next_weather == "storm"):
		_update_storm_effects(delta)
	
	if current_weather == "snow" and snow_accumulation:
		_update_snow_accumulation(delta)
	
	if fog_layer and fog_layer.modulate.a > 0:
		_update_fog_movement(delta)

func _update_storm_effects(delta):
	lightning_timer += delta
	
	if lightning_timer >= lightning_frequency:
		lightning_timer = 0.0
		_create_lightning()

func _create_lightning():
	# Flash effect
	var flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0.8)
	flash.anchor_right = 1.0
	flash.anchor_bottom = 1.0
	add_child(flash)
	
	var tween = create_tween()
	tween.tween_property(flash, "color:a", 0.0, 0.2)
	tween.tween_callback(flash.queue_free)
	
	# Thunder sound
	if thunder_sounds.size() > 0:
		await get_tree().create_timer(thunder_delay).timeout
		audio_player.stream = thunder_sounds[randi() % thunder_sounds.size()]
		audio_player.play()

func _update_fog_movement(delta):
	for child in fog_layer.get_children():
		if child is Sprite2D:
			child.position.x += fog_speed * delta
			
			# Wrap around screen
			if child.position.x > get_viewport_rect().size.x + child.texture.get_width():
				child.position.x = -child.texture.get_width()

func _update_wind(delta):
	if not enable_wind:
		return
	
	wind_timer += delta
	current_wind_strength = wind_strength + sin(wind_timer) * wind_variation
	
	if affect_particles:
		var wind_effect = wind_direction * current_wind_strength * 0.1
		rain_particles.gravity = wind_effect
		snow_particles.gravity = wind_effect * 0.5

func _play_ambient_sound(sound_type: String):
	# Load and play appropriate ambient sound
	pass

func get_current_weather() -> String:
	return current_weather

func set_weather(weather: String, instant: bool = false):
	if instant:
		current_weather = weather
		_set_weather(weather, true)
	else:
		start_weather_transition(weather)

func get_wind_at_position(pos: Vector2) -> Vector2:
	if not enable_wind:
		return Vector2.ZERO
	
	return wind_direction * current_wind_strength

func is_indoor_position(pos: Vector2) -> bool:
	# Check if position is sheltered from weather
	return false

func _update_snow_accumulation(delta):
	# Create snow accumulation effect
	pass

func create_puddle(position: Vector2):
	if puddle_scene:
		var puddle = puddle_scene.instantiate()
		add_child(puddle)
		puddle.global_position = position