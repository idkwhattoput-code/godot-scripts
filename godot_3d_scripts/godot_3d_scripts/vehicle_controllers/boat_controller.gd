extends RigidBody

# Boat specifications
export var engine_power = 1000.0  # HP
export var max_speed = 50.0  # knots
export var hull_length = 10.0  # meters
export var beam_width = 3.0  # meters
export var draft = 1.0  # meters
export var displacement = 5000.0  # kg

# Hydrodynamics
export var water_density = 1000.0  # kg/m³
export var drag_coefficient = 0.4
export var lift_coefficient = 0.3
export var hull_efficiency = 0.85
export var propeller_efficiency = 0.7

# Control surfaces
export var rudder_area = 0.5  # m²
export var rudder_effectiveness = 2.0
export var trim_tab_effectiveness = 1.0
export var hydrofoil_equipped = false

# Stability
export var metacentric_height = 0.5  # meters
export var roll_damping = 10.0
export var pitch_damping = 8.0
export var yaw_damping = 5.0

# Propulsion
enum PropulsionType { OUTBOARD, INBOARD, JET, SAIL }
export var propulsion_type = PropulsionType.OUTBOARD
export var engine_count = 1
export var engine_tilt_range = 15.0  # degrees
export var reverse_gear_ratio = 0.7

# State variables
var current_speed = 0.0
var engine_rpm = 0.0
var propeller_rpm = 0.0
var rudder_angle = 0.0
var engine_tilt = 0.0
var trim_tabs_angle = 0.0
var is_planing = false
var is_anchored = false
var fuel_level = 100.0

# Water interaction
var water_level = 0.0
var submerged_volume = 0.0
var wetted_surface_area = 0.0
var wave_height = 1.0
var wave_period = 5.0
var wave_direction = Vector3.FORWARD

# Control input
var throttle = 0.0
var steering = 0.0
var trim_input = 0.0
var gear = 1  # 1 = forward, 0 = neutral, -1 = reverse

# Navigation
var heading = 0.0  # degrees
var gps_position = Vector2.ZERO
var waypoints = []
var autopilot_enabled = false

# Safety systems
var bilge_pump_active = false
var water_in_hull = 0.0
var max_water_capacity = 1000.0  # liters
var engine_temperature = 20.0
var max_engine_temp = 90.0

# Components
onready var hull_mesh = $HullMesh
onready var propeller = $Propeller
onready var rudder = $Rudder
onready var wake_particles = $WakeParticles
onready var spray_particles = $SprayParticles
onready var engine_sound = $EngineSound
onready var water_sound = $WaterSound
onready var hull_impact_sound = $HullImpactSound

# Buoyancy points
var buoyancy_points = []
var buoyancy_probes = []

signal engine_started()
signal engine_stopped()
signal hull_breach(location)
signal ran_aground()
signal capsized()

func _ready():
	_setup_buoyancy_points()
	_initialize_systems()
	set_physics_process(true)
	
	# Set up water detection
	water_level = 0.0  # Sea level

func _setup_buoyancy_points():
	# Create buoyancy calculation points
	var point_positions = [
		Vector3(-beam_width/2, -draft, hull_length/2),    # Front left
		Vector3(beam_width/2, -draft, hull_length/2),     # Front right
		Vector3(-beam_width/2, -draft, 0),                # Mid left
		Vector3(beam_width/2, -draft, 0),                 # Mid right
		Vector3(-beam_width/2, -draft, -hull_length/2),   # Rear left
		Vector3(beam_width/2, -draft, -hull_length/2),    # Rear right
	]
	
	for pos in point_positions:
		var probe = Area.new()
		probe.translation = pos
		add_child(probe)
		
		buoyancy_probes.append(probe)
		buoyancy_points.append({
			"position": pos,
			"submerged": 0.0,
			"force": Vector3.ZERO
		})

func _initialize_systems():
	# Set boat's physical properties
	mass = displacement
	
	# Configure drag
	linear_damp = 0.5
	angular_damp = 1.0

func _physics_process(delta):
	_handle_input()
	_update_buoyancy(delta)
	_update_propulsion(delta)
	_update_steering(delta)
	_update_hydrodynamics(delta)
	_update_stability(delta)
	_update_systems(delta)
	_update_effects(delta)
	_check_safety(delta)

func _handle_input():
	# Throttle
	if Input.is_action_pressed("accelerate"):
		throttle = lerp(throttle, 1.0, 0.05)
	elif Input.is_action_pressed("decelerate"):
		throttle = lerp(throttle, -1.0, 0.05)
	else:
		throttle = lerp(throttle, 0.0, 0.1)
	
	# Steering
	steering = Input.get_axis("steer_left", "steer_right")
	
	# Trim
	trim_input = Input.get_axis("trim_down", "trim_up")
	
	# Gear shifting
	if Input.is_action_just_pressed("shift_up") and gear < 1:
		gear += 1
	elif Input.is_action_just_pressed("shift_down") and gear > -1:
		gear -= 1
	
	# Anchor
	if Input.is_action_just_pressed("toggle_anchor"):
		is_anchored = !is_anchored
	
	# Engine controls
	if Input.is_action_just_pressed("start_engine"):
		_start_engine()
	elif Input.is_action_just_pressed("stop_engine"):
		_stop_engine()

func _update_buoyancy(delta):
	submerged_volume = 0.0
	var total_buoyancy_force = Vector3.ZERO
	
	for i in range(buoyancy_points.size()):
		var point = buoyancy_points[i]
		var world_pos = global_transform * point.position
		
		# Calculate wave height at this position
		var wave_offset = _calculate_wave_height(world_pos, OS.get_ticks_msec() / 1000.0)
		var water_height = water_level + wave_offset
		
		# Check submersion
		var depth = water_height - world_pos.y
		point.submerged = clamp(depth / draft, 0, 1)
		
		if point.submerged > 0:
			# Archimedes' principle
			var displaced_volume = (hull_length * beam_width * draft) / buoyancy_points.size() * point.submerged
			var buoyancy_force = water_density * 9.81 * displaced_volume
			
			# Apply force upward
			point.force = Vector3.UP * buoyancy_force
			
			# Apply force at point for realistic physics
			add_force(point.force, point.position)
			
			total_buoyancy_force += point.force
			submerged_volume += displaced_volume
	
	# Check if boat is planing
	var speed_ms = linear_velocity.length()
	var froude_number = speed_ms / sqrt(9.81 * hull_length)
	is_planing = froude_number > 1.0 and submerged_volume < displacement * 0.7

func _calculate_wave_height(position: Vector3, time: float) -> float:
	# Simple sine wave
	var wave_phase = position.dot(wave_direction) / wave_period + time
	return sin(wave_phase) * wave_height

func _update_propulsion(delta):
	if gear == 0 or throttle == 0:
		engine_rpm = lerp(engine_rpm, 800, 0.1)  # Idle
		return
	
	# Calculate engine RPM
	var target_rpm = 800 + abs(throttle) * 4200  # 800-5000 RPM range
	engine_rpm = lerp(engine_rpm, target_rpm, 0.2)
	
	# Propeller RPM based on gear
	var gear_ratio = 1.0 if gear == 1 else reverse_gear_ratio
	propeller_rpm = engine_rpm * gear_ratio * gear
	
	# Calculate thrust
	var thrust_force = 0.0
	
	match propulsion_type:
		PropulsionType.OUTBOARD, PropulsionType.INBOARD:
			# Propeller thrust
			var advance_ratio = linear_velocity.length() / (propeller_rpm / 60.0 * 0.3)  # 0.3m prop diameter
			var thrust_coefficient = propeller_efficiency * (1.0 - advance_ratio)
			thrust_force = thrust_coefficient * engine_power * 735.5 * throttle / linear_velocity.length() if linear_velocity.length() > 0.1 else engine_power * 735.5 * throttle
			
		PropulsionType.JET:
			# Water jet propulsion
			thrust_force = engine_power * 735.5 * throttle * 0.8
	
	# Apply thrust
	var thrust_direction = -transform.basis.z
	
	# Account for engine tilt (trim)
	if propulsion_type == PropulsionType.OUTBOARD:
		thrust_direction = thrust_direction.rotated(transform.basis.x, deg2rad(engine_tilt))
	
	add_central_force(thrust_direction * thrust_force * engine_count)
	
	# Fuel consumption
	fuel_level -= abs(throttle) * 0.01 * delta

func _update_steering(delta):
	# Update rudder angle
	rudder_angle = lerp(rudder_angle, steering * 35, 0.1)  # Max 35 degrees
	
	# Calculate rudder force
	var speed_ms = linear_velocity.length()
	if speed_ms > 0.5:
		var rudder_force = 0.5 * water_density * rudder_area * speed_ms * speed_ms * sin(deg2rad(rudder_angle)) * rudder_effectiveness
		
		# Apply turning moment
		var rudder_position = Vector3(0, -draft * 0.5, hull_length * 0.4)
		add_force(transform.basis.x * rudder_force, rudder_position)
	
	# Update heading
	var forward = -transform.basis.z
	heading = rad2deg(atan2(forward.x, forward.z))

func _update_hydrodynamics(delta):
	var velocity = linear_velocity
	var speed = velocity.length()
	
	if speed > 0.01:
		# Hull drag
		var reynolds_number = speed * hull_length / 0.000001  # Kinematic viscosity of water
		var friction_coefficient = 0.075 / pow(log(reynolds_number) / log(10) - 2, 2)
		
		wetted_surface_area = 2 * draft * hull_length + beam_width * hull_length * (1 - is_planing.real * 0.5)
		var friction_drag = 0.5 * water_density * wetted_surface_area * friction_coefficient * speed * speed
		
		# Form drag
		var form_drag = 0.5 * water_density * beam_width * draft * drag_coefficient * speed * speed
		
		# Wave-making resistance (significant at higher speeds)
		var froude = speed / sqrt(9.81 * hull_length)
		var wave_drag = form_drag * pow(froude, 4) if froude > 0.4 else 0
		
		# Total drag
		var total_drag = friction_drag + form_drag + wave_drag
		add_central_force(-velocity.normalized() * total_drag)
		
		# Lift force when planing
		if is_planing:
			var lift_force = 0.5 * water_density * wetted_surface_area * lift_coefficient * speed * speed
			add_central_force(Vector3.UP * lift_force * 0.5)
	
	# Trim tab effects
	if abs(trim_tabs_angle) > 0.1:
		var trim_force = speed * speed * trim_tabs_angle * trim_tab_effectiveness
		add_force(Vector3.UP * trim_force, Vector3(0, 0, hull_length * 0.4))

func _update_stability(delta):
	# Calculate righting moment (prevents capsizing)
	var roll = transform.basis.get_euler().z
	var righting_moment = -sin(roll) * displacement * 9.81 * metacentric_height
	add_torque(transform.basis.z * righting_moment)
	
	# Add damping to reduce oscillations
	var angular_vel = angular_velocity
	add_torque(-angular_vel.x * transform.basis.x * pitch_damping)
	add_torque(-angular_vel.y * transform.basis.y * yaw_damping)
	add_torque(-angular_vel.z * transform.basis.z * roll_damping)
	
	# Check for capsize
	if abs(roll) > deg2rad(90):
		emit_signal("capsized")

func _update_systems(delta):
	# Engine temperature
	if engine_rpm > 800:
		engine_temperature += (engine_rpm / 5000.0) * 10 * delta
	else:
		engine_temperature -= 5 * delta
	engine_temperature = clamp(engine_temperature, 20, max_engine_temp)
	
	# Bilge pump
	if bilge_pump_active and water_in_hull > 0:
		water_in_hull -= 10 * delta  # 10 liters per second
		water_in_hull = max(0, water_in_hull)
	
	# Trim adjustment
	engine_tilt = lerp(engine_tilt, trim_input * engine_tilt_range, 0.05)
	trim_tabs_angle = lerp(trim_tabs_angle, trim_input * 30, 0.05)
	
	# Anchor drag
	if is_anchored:
		linear_velocity *= 0.95
		angular_velocity *= 0.9

func _update_effects(delta):
	# Engine sound
	if engine_sound:
		engine_sound.pitch_scale = 0.5 + engine_rpm / 10000.0
		engine_sound.volume_db = linear2db(0.3 + throttle * 0.7)
		if engine_rpm > 0 and not engine_sound.playing:
			engine_sound.play()
	
	# Water sounds
	if water_sound:
		var speed_normalized = linear_velocity.length() / (max_speed * 0.514)  # Convert knots to m/s
		water_sound.volume_db = linear2db(speed_normalized)
		water_sound.pitch_scale = 0.8 + speed_normalized * 0.4
		if not water_sound.playing and speed_normalized > 0.1:
			water_sound.play()
	
	# Wake particles
	if wake_particles:
		wake_particles.emitting = linear_velocity.length() > 1.0
		wake_particles.amount = int(linear_velocity.length() * 10)
		wake_particles.initial_velocity = linear_velocity.length() * 2
	
	// Spray particles when planing
	if spray_particles:
		spray_particles.emitting = is_planing
		spray_particles.amount = int(linear_velocity.length() * 5)
	
	# Propeller rotation
	if propeller:
		propeller.rotate_z(propeller_rpm * delta * 0.1)

func _check_safety(delta):
	# Check if grounded
	var space_state = get_world().direct_space_state
	var from = global_transform.origin
	var to = from + Vector3.DOWN * (draft + 1)
	
	var result = space_state.intersect_ray(from, to, [self])
	if result and result.collider.is_in_group("terrain"):
		emit_signal("ran_aground")
		# Damage from grounding
		var impact_speed = linear_velocity.y
		if impact_speed < -5:
			_create_hull_breach(result.position)
	
	# Check water in hull
	if water_in_hull > max_water_capacity * 0.8:
		# Boat is sinking
		mass = displacement + water_in_hull
		add_central_force(Vector3.DOWN * water_in_hull * 9.81)

func _start_engine():
	if fuel_level > 0:
		engine_rpm = 800
		emit_signal("engine_started")

func _stop_engine():
	engine_rpm = 0
	throttle = 0
	emit_signal("engine_stopped")

func _create_hull_breach(position: Vector3):
	emit_signal("hull_breach", position)
	# Water ingress rate based on depth
	var depth = water_level - position.y
	var ingress_rate = sqrt(2 * 9.81 * depth) * 0.01  # Small hole
	water_in_hull += ingress_rate * get_physics_process_delta_time()

# Navigation functions
func set_autopilot_waypoint(waypoint: Vector3):
	waypoints.append(waypoint)
	autopilot_enabled = true

func get_navigation_data() -> Dictionary:
	return {
		"heading": heading,
		"speed_knots": linear_velocity.length() * 1.944,  # m/s to knots
		"position": global_transform.origin,
		"fuel": fuel_level,
		"engine_temp": engine_temperature,
		"water_in_hull": water_in_hull
	}

# Public API
func drop_anchor():
	is_anchored = true

func raise_anchor():
	is_anchored = false

func activate_bilge_pump():
	bilge_pump_active = true

func deploy_flares():
	# Emergency signal
	pass

func get_boat_status() -> Dictionary:
	return {
		"speed": linear_velocity.length() * 1.944,
		"heading": heading,
		"engine_rpm": engine_rpm,
		"fuel": fuel_level,
		"trim": engine_tilt,
		"is_planing": is_planing,
		"water_in_hull": water_in_hull
	}