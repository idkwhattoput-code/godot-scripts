extends Node

# Dynamic Day/Night Cycle for Godot 3D
# Controls sun/moon rotation, lighting, sky colors, and ambient effects
# Attach to a Node with DirectionalLight children for sun and moon

# Time settings
export var day_duration = 300.0  # Duration of a full day in seconds
export var start_time = 12.0  # Starting hour (0-24)
export var time_scale = 1.0  # Time multiplier for testing

# Sun/Moon settings
export var sun_path: NodePath
export var moon_path: NodePath
export var sun_intensity_curve: Curve
export var moon_intensity_curve: Curve
export var sun_color_gradient: Gradient
export var ambient_color_gradient: Gradient

# Sky settings
export var sky_top_color_gradient: Gradient
export var sky_horizon_color_gradient: Gradient
export var ground_color_gradient: Gradient
export var fog_enabled = true
export var fog_color_gradient: Gradient
export var fog_density_curve: Curve

# Shadow settings
export var shadow_color_gradient: Gradient
export var shadow_opacity_curve: Curve

# Time of day events
signal hour_changed(hour)
signal sunrise()
signal sunset()
signal noon()
signal midnight()

# Internal variables
var current_time = 0.0  # Current time in hours (0-24)
var sun: DirectionalLight
var moon: DirectionalLight
var environment: Environment
var previous_hour = -1

func _ready():
	# Get sun and moon lights
	if sun_path:
		sun = get_node(sun_path)
	if moon_path:
		moon = get_node(moon_path)
	
	# Get or create environment
	if get_viewport().environment:
		environment = get_viewport().environment
	else:
		environment = Environment.new()
		get_viewport().environment = environment
	
	# Initialize gradients and curves if not set
	initialize_defaults()
	
	# Set initial time
	current_time = start_time
	update_time_of_day()

func initialize_defaults():
	"""Initialize default gradients and curves"""
	if not sun_intensity_curve:
		sun_intensity_curve = Curve.new()
		sun_intensity_curve.add_point(Vector2(0.0, 0.0))
		sun_intensity_curve.add_point(Vector2(0.25, 0.0))
		sun_intensity_curve.add_point(Vector2(0.3, 0.5))
		sun_intensity_curve.add_point(Vector2(0.5, 1.0))
		sun_intensity_curve.add_point(Vector2(0.7, 0.5))
		sun_intensity_curve.add_point(Vector2(0.75, 0.0))
		sun_intensity_curve.add_point(Vector2(1.0, 0.0))
	
	if not sun_color_gradient:
		sun_color_gradient = Gradient.new()
		sun_color_gradient.add_point(0.0, Color(0.1, 0.1, 0.3))  # Night
		sun_color_gradient.add_point(0.25, Color(0.5, 0.2, 0.1))  # Dawn
		sun_color_gradient.add_point(0.3, Color(1.0, 0.6, 0.3))  # Sunrise
		sun_color_gradient.add_point(0.5, Color(1.0, 0.95, 0.8))  # Noon
		sun_color_gradient.add_point(0.7, Color(1.0, 0.7, 0.4))  # Sunset
		sun_color_gradient.add_point(0.75, Color(0.5, 0.2, 0.1))  # Dusk
		sun_color_gradient.add_point(1.0, Color(0.1, 0.1, 0.3))  # Night
	
	if not ambient_color_gradient:
		ambient_color_gradient = Gradient.new()
		ambient_color_gradient.add_point(0.0, Color(0.05, 0.07, 0.13))
		ambient_color_gradient.add_point(0.25, Color(0.15, 0.12, 0.15))
		ambient_color_gradient.add_point(0.5, Color(0.4, 0.6, 0.8))
		ambient_color_gradient.add_point(0.75, Color(0.15, 0.12, 0.15))
		ambient_color_gradient.add_point(1.0, Color(0.05, 0.07, 0.13))

func _process(delta):
	# Update time
	current_time += (delta * time_scale * 24.0) / day_duration
	if current_time >= 24.0:
		current_time -= 24.0
	
	# Update environment
	update_time_of_day()
	
	# Check for hour changes
	var current_hour = int(current_time)
	if current_hour != previous_hour:
		previous_hour = current_hour
		emit_signal("hour_changed", current_hour)
		check_time_events(current_hour)

func update_time_of_day():
	"""Update all time-based properties"""
	var time_normalized = current_time / 24.0
	
	# Update sun and moon rotation
	update_celestial_bodies(time_normalized)
	
	# Update lighting
	update_lighting(time_normalized)
	
	# Update sky
	update_sky(time_normalized)
	
	# Update fog
	if fog_enabled:
		update_fog(time_normalized)
	
	# Update shadows
	update_shadows(time_normalized)

func update_celestial_bodies(time_normalized: float):
	"""Update sun and moon positions"""
	# Sun rotation (rises at 6am, sets at 6pm)
	if sun:
		var sun_angle = (time_normalized - 0.25) * TAU
		sun.rotation.x = sun_angle
		
		# Update sun intensity
		if sun_intensity_curve:
			sun.light_energy = sun_intensity_curve.interpolate(time_normalized)
		
		# Update sun color
		if sun_color_gradient:
			sun.light_color = sun_color_gradient.interpolate(time_normalized)
	
	# Moon rotation (opposite of sun)
	if moon:
		var moon_angle = (time_normalized + 0.25) * TAU
		moon.rotation.x = moon_angle
		
		# Update moon intensity
		if moon_intensity_curve:
			moon.light_energy = moon_intensity_curve.interpolate(time_normalized)
		else:
			# Simple inverse of sun
			moon.light_energy = 0.3 * (1.0 - sun.light_energy) if sun else 0.3

func update_lighting(time_normalized: float):
	"""Update ambient lighting"""
	if not environment:
		return
	
	# Update ambient light
	if ambient_color_gradient:
		environment.ambient_light_color = ambient_color_gradient.interpolate(time_normalized)
		environment.ambient_light_energy = 0.3 + 0.2 * sin(time_normalized * TAU - PI/2)
	
	# Update ambient light source
	if sun and sun.light_energy > 0.1:
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	else:
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR

func update_sky(time_normalized: float):
	"""Update sky colors"""
	if not environment or not environment.background_mode == Environment.BG_MODE_SKY:
		return
	
	# This assumes procedural sky - adjust for your sky setup
	if environment.background_sky and environment.background_sky is ProceduralSky:
		var sky = environment.background_sky as ProceduralSky
		
		if sky_top_color_gradient:
			sky.sky_top_color = sky_top_color_gradient.interpolate(time_normalized)
		
		if sky_horizon_color_gradient:
			sky.sky_horizon_color = sky_horizon_color_gradient.interpolate(time_normalized)
		
		if ground_color_gradient:
			sky.ground_horizon_color = ground_color_gradient.interpolate(time_normalized)
		
		# Update sun properties
		sky.sun_color = sun.light_color if sun else Color.white
		sky.sun_energy = sun.light_energy if sun else 1.0

func update_fog(time_normalized: float):
	"""Update fog settings"""
	if not environment:
		return
	
	environment.fog_enabled = true
	
	if fog_color_gradient:
		environment.fog_color = fog_color_gradient.interpolate(time_normalized)
	
	if fog_density_curve:
		environment.fog_density = fog_density_curve.interpolate(time_normalized)
	else:
		# More fog at dawn/dusk
		var fog_amount = 0.01 + 0.05 * (1.0 - abs(sin(time_normalized * TAU)))
		environment.fog_density = fog_amount
	
	# Adjust fog distance based on time
	environment.fog_depth_begin = 10.0
	environment.fog_depth_end = 100.0 + 50.0 * sin(time_normalized * TAU)

func update_shadows(time_normalized: float):
	"""Update shadow settings"""
	if sun:
		if shadow_color_gradient:
			sun.shadow_color = shadow_color_gradient.interpolate(time_normalized)
		
		# Softer shadows at dawn/dusk
		var shadow_blur = 1.0 + 2.0 * (1.0 - abs(sin(time_normalized * TAU)))
		sun.directional_shadow_blur_stages = int(shadow_blur)

func check_time_events(hour: int):
	"""Emit signals for specific times"""
	match hour:
		6:
			emit_signal("sunrise")
		12:
			emit_signal("noon")
		18:
			emit_signal("sunset")
		0:
			emit_signal("midnight")

# Public methods
func set_time(hour: float):
	"""Set the current time (0-24)"""
	current_time = clamp(hour, 0.0, 23.99)
	update_time_of_day()

func get_time() -> float:
	"""Get the current time in hours"""
	return current_time

func get_time_of_day_string() -> String:
	"""Get formatted time string"""
	var hours = int(current_time)
	var minutes = int((current_time - hours) * 60)
	return "%02d:%02d" % [hours, minutes]

func is_day() -> bool:
	"""Check if it's daytime (6am-6pm)"""
	return current_time >= 6.0 and current_time < 18.0

func is_night() -> bool:
	"""Check if it's nighttime"""
	return not is_day()

func skip_hours(hours: float):
	"""Skip forward in time"""
	set_time(current_time + hours)