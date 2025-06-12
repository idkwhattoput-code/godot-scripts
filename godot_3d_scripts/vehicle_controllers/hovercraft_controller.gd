extends RigidBody

# Hover settings
export var hover_height = 2.0
export var hover_force = 50.0
export var hover_damping = 5.0
export var stability_force = 10.0
export var max_ground_angle = 45.0  # degrees

# Movement settings
export var thrust_power = 1000.0
export var strafe_power = 800.0
export var turn_power = 100.0
export var boost_multiplier = 2.0
export var air_brake_force = 20.0

# Physics
export var linear_drag = 0.5
export var angular_drag = 2.0
export var mass_distribution = Vector3(1, 0.5, 1.2)  # Front/back weight
export var center_of_mass_offset = Vector3(0, -0.5, 0)

# Hover points
export var hover_point_count = 4
export var hover_point_spread = 2.0
var hover_points = []
var hover_rays = []

# State
var is_hovering = false
var current_hover_height = 0.0
var ground_normal = Vector3.UP
var altitude = 0.0
var effective_thrust = 0.0

# Input
var thrust_input = 0.0
var strafe_input = 0.0
var turn_input = 0.0
var lift_input = 0.0
var is_boosting = false
var is_braking = false

# Effects
var hover_force_visual = []
var thrust_particles = []
var dust_particles = []

# Energy system
export var energy_capacity = 100.0
export var energy_consumption_rate = 5.0
export var energy_regen_rate = 10.0
var current_energy = 100.0

# Components
onready var body_mesh = $BodyMesh
onready var hover_effect = $HoverEffect
onready var thrust_effect = $ThrustEffect
onready var energy_shield = $EnergyShield
onready var hover_sound = $HoverSound
onready var thrust_sound = $ThrustSound

signal hovering_started()
signal hovering_stopped()
signal surface_changed(new_surface)
signal energy_depleted()
signal collision_detected(impact_force)

func _ready():
	set_center_of_mass(center_of_mass_offset)
	_setup_hover_points()
	_initialize_effects()
	set_physics_process(true)

func _setup_hover_points():
	# Create hover points in rectangular pattern
	var positions = []
	
	if hover_point_count == 4:
		positions = [
			Vector3(-hover_point_spread/2, 0, hover_point_spread/2),
			Vector3(hover_point_spread/2, 0, hover_point_spread/2),
			Vector3(-hover_point_spread/2, 0, -hover_point_spread/2),
			Vector3(hover_point_spread/2, 0, -hover_point_spread/2)
		]
	else:
		# Distribute points in circle
		for i in range(hover_point_count):
			var angle = i * TAU / hover_point_count
			var pos = Vector3(
				sin(angle) * hover_point_spread/2,
				0,
				cos(angle) * hover_point_spread/2
			)
			positions.append(pos)
	
	# Create raycast for each point
	for pos in positions:
		var ray = RayCast.new()
		ray.cast_to = Vector3.DOWN * (hover_height * 2)
		ray.enabled = true
		ray.translation = pos
		add_child(ray)
		
		hover_rays.append(ray)
		hover_points.append({
			"position": pos,
			"ray": ray,
			"compression": 0.0,
			"last_distance": hover_height
		})

func _initialize_effects():
	# Create hover effect visualizers
	for point in hover_points:
		var effect = CPUParticles.new()
		effect.emitting = false
		effect.amount = 20
		effect.lifetime = 0.5
		effect.spread = 10
		effect.initial_velocity = 5
		effect.scale = Vector3.ONE * 0.5
		effect.translation = point.position
		add_child(effect)
		hover_force_visual.append(effect)

func _physics_process(delta):
	_handle_input()
	_update_hover_physics(delta)
	_apply_movement(delta)
	_update_energy(delta)
	_update_effects(delta)
	_apply_drag(delta)

func _handle_input():
	thrust_input = Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
	strafe_input = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	turn_input = Input.get_action_strength("turn_right") - Input.get_action_strength("turn_left")
	lift_input = Input.get_action_strength("move_up") - Input.get_action_strength("move_down")
	
	is_boosting = Input.is_action_pressed("boost") and current_energy > 10
	is_braking = Input.is_action_pressed("handbrake")

func _update_hover_physics(delta):
	var total_compression = 0.0
	var hover_count = 0
	var average_normal = Vector3.ZERO
	var average_height = 0.0
	
	# Check each hover point
	for i in range(hover_points.size()):
		var point = hover_points[i]
		var ray = point.ray
		
		if ray.is_colliding():
			var collision_point = ray.get_collision_point()
			var collision_normal = ray.get_collision_normal()
			var distance = (collision_point - ray.global_transform.origin).length()
			
			# Check surface angle
			var surface_angle = rad2deg(collision_normal.angle_to(Vector3.UP))
			if surface_angle > max_ground_angle:
				continue
			
			# Calculate compression (0 = no compression, 1 = max compression)
			var compression = 1.0 - (distance / hover_height)
			compression = clamp(compression, 0, 1)
			
			# Apply hover force at this point
			if compression > 0:
				var force_magnitude = hover_force * compression * mass
				var force_direction = collision_normal
				
				# Add damping based on velocity
				var point_velocity = get_velocity_at_point(ray.global_transform.origin)
				var damping = -point_velocity * hover_damping
				
				apply_force(force_direction * force_magnitude + damping, ray.global_transform.origin - global_transform.origin)
				
				hover_count += 1
				total_compression += compression
				average_normal += collision_normal
				average_height += distance
			
			point.compression = compression
			point.last_distance = distance
		else:
			point.compression = 0.0
			point.last_distance = hover_height * 2
	
	# Update hover state
	if hover_count > 0:
		if not is_hovering:
			is_hovering = true
			emit_signal("hovering_started")
		
		average_normal = average_normal.normalized()
		ground_normal = average_normal
		current_hover_height = average_height / hover_count
		altitude = current_hover_height
		
		# Apply stability torque to align with ground
		_apply_stability(average_normal, delta)
	else:
		if is_hovering:
			is_hovering = false
			emit_signal("hovering_stopped")
		altitude = hover_height * 2

func _apply_stability(target_normal: Vector3, delta):
	# Calculate desired orientation
	var current_up = transform.basis.y
	var rotation_axis = current_up.cross(target_normal)
	var rotation_angle = current_up.angle_to(target_normal)
	
	# Apply corrective torque
	if rotation_angle > 0.01:
		var stability_torque = rotation_axis * rotation_angle * stability_force
		apply_torque_impulse(stability_torque * delta)

func _apply_movement(delta):
	if current_energy <= 0:
		return
	
	# Calculate movement forces
	var forward = -transform.basis.z
	var right = transform.basis.x
	
	# Thrust
	var thrust_force = forward * thrust_input * thrust_power
	if is_boosting:
		thrust_force *= boost_multiplier
		current_energy -= energy_consumption_rate * 2 * delta
	
	# Strafe
	var strafe_force = right * strafe_input * strafe_power
	
	# Vertical lift
	var lift_force = Vector3.UP * lift_input * thrust_power * 0.5
	
	# Apply forces
	add_central_force(thrust_force + strafe_force + lift_force)
	
	# Turning
	if abs(turn_input) > 0.1:
		var turn_torque = Vector3.UP * turn_input * turn_power
		apply_torque_impulse(turn_torque * delta)
	
	# Air brake
	if is_braking:
		var brake_force = -linear_velocity * air_brake_force
		add_central_force(brake_force)
		
		# Extra angular damping when braking
		angular_velocity *= 0.95
	
	effective_thrust = thrust_force.length()

func _apply_drag(delta):
	# Linear drag based on velocity
	var speed = linear_velocity.length()
	if speed > 0.1:
		var drag_force = -linear_velocity.normalized() * speed * speed * linear_drag
		add_central_force(drag_force)
	
	# Angular drag
	angular_velocity *= (1.0 - angular_drag * delta)

func _update_energy(delta):
	if current_energy < energy_capacity and not is_boosting:
		current_energy = min(current_energy + energy_regen_rate * delta, energy_capacity)
	
	# Base energy consumption for hovering
	if is_hovering:
		current_energy -= energy_consumption_rate * 0.2 * delta
	
	if current_energy <= 0:
		current_energy = 0
		emit_signal("energy_depleted")
		# Hovercraft falls
		set_gravity_scale(1.0)
	else:
		set_gravity_scale(0.3)  # Reduced gravity when powered

func _update_effects(delta):
	# Hover point effects
	for i in range(hover_points.size()):
		var point = hover_points[i]
		var effect = hover_force_visual[i]
		
		if point.compression > 0.1:
			effect.emitting = true
			effect.initial_velocity = point.compression * 20
			effect.amount = int(point.compression * 50)
		else:
			effect.emitting = false
	
	# Thrust effects
	if thrust_effect:
		thrust_effect.emitting = abs(thrust_input) > 0.1
		thrust_effect.initial_velocity = abs(thrust_input) * 30
	
	# Dust effects when low to ground
	if is_hovering and altitude < hover_height * 0.7:
		# Create dust clouds
		pass
	
	# Sound effects
	if hover_sound:
		if is_hovering:
			if not hover_sound.playing:
				hover_sound.play()
			hover_sound.volume_db = linear2db(0.5 + total_compression * 0.5)
			hover_sound.pitch_scale = 0.8 + current_hover_height / hover_height * 0.4
		else:
			hover_sound.stop()
	
	if thrust_sound:
		if abs(thrust_input) > 0.1:
			if not thrust_sound.playing:
				thrust_sound.play()
			thrust_sound.volume_db = linear2db(abs(thrust_input))
			thrust_sound.pitch_scale = 1.0 + abs(thrust_input) * 0.5
		else:
			thrust_sound.stop()

func get_velocity_at_point(point: Vector3) -> Vector3:
	# Calculate velocity at a specific point considering rotation
	var r = point - global_transform.origin
	return linear_velocity + angular_velocity.cross(r)

func apply_impulse_at_point(impulse: Vector3, point: Vector3):
	# Apply impulse at specific point for collisions
	apply_impulse(point - global_transform.origin, impulse)

func set_hover_enabled(enabled: bool):
	for ray in hover_rays:
		ray.enabled = enabled
	
	if not enabled:
		is_hovering = false
		set_gravity_scale(1.0)

func get_hover_compression() -> float:
	var total = 0.0
	for point in hover_points:
		total += point.compression
	return total / hover_points.size()

func get_speed_kmh() -> float:
	return linear_velocity.length() * 3.6

func get_altitude() -> float:
	return altitude

func perform_barrel_roll():
	if current_energy >= 25:
		current_energy -= 25
		apply_torque_impulse(transform.basis.z * 500)

func emergency_landing():
	# Controlled descent
	set_hover_enabled(false)
	linear_velocity.y = -5
	angular_velocity *= 0.1

func _on_body_entered(body):
	# Collision handling
	var impact_velocity = linear_velocity.length()
	if impact_velocity > 10:
		emit_signal("collision_detected", impact_velocity)
		
		# Bounce off
		var bounce_direction = (global_transform.origin - body.global_transform.origin).normalized()
		apply_central_impulse(bounce_direction * impact_velocity * mass * 0.5)