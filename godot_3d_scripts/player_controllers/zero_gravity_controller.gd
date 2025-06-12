extends RigidBody

# Movement settings
export var linear_thrust = 50.0
export var angular_thrust = 5.0
export var stabilization_strength = 10.0
export var max_linear_velocity = 20.0
export var max_angular_velocity = 5.0

# Jetpack/RCS settings
export var fuel_capacity = 100.0
export var fuel_consumption_rate = 5.0
export var fuel_regeneration_rate = 2.0
export var boost_multiplier = 2.0
export var emergency_brake_force = 100.0

# Magnetic boots
export var magnetic_boot_range = 2.0
export var magnetic_boot_strength = 50.0
export var boot_activation_angle = 45.0
export var auto_align_to_surface = true

# Grappling system
export var grapple_range = 30.0
export var grapple_force = 100.0
export var grapple_reel_speed = 10.0
export var max_tethers = 2

# State variables
var current_fuel = 100.0
var is_stabilized = false
var is_boosting = false
var magnetic_boots_active = false
var attached_surface = null
var surface_normal = Vector3.UP
var grapple_points = []
var active_tethers = []

# Input
var movement_input = Vector3.ZERO
var rotation_input = Vector3.ZERO
var roll_input = 0.0

# Components
onready var camera_pivot = $CameraPivot
onready var camera = $CameraPivot/Camera
onready var thruster_particles = $ThrusterParticles
onready var fuel_ui = $UI/FuelGauge
onready var velocity_ui = $UI/VelocityIndicator
onready var orientation_ui = $UI/OrientationIndicator
onready var grapple_hook = $GrappleHook
onready var tether_line = $TetherLine

signal fuel_depleted()
signal fuel_restored()
signal surface_attached(surface)
signal surface_detached()
signal grapple_attached(point)
signal grapple_detached()

func _ready():
	set_physics_process(true)
	set_gravity_scale(0.0)  # Disable gravity
	_initialize_ui()
	_setup_collision_detection()

func _initialize_ui():
	if fuel_ui:
		fuel_ui.max_value = fuel_capacity
		fuel_ui.value = current_fuel

func _setup_collision_detection():
	# Setup collision detection for magnetic boots
	connect("body_entered", self, "_on_body_entered")

func _physics_process(delta):
	_handle_input()
	_update_movement(delta)
	_update_rotation(delta)
	_update_fuel(delta)
	_update_magnetic_boots(delta)
	_update_grapples(delta)
	_apply_velocity_limits()
	_update_ui()
	_update_effects()

func _handle_input():
	# Movement input
	movement_input = Vector3.ZERO
	movement_input.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	movement_input.y = Input.get_action_strength("move_up") - Input.get_action_strength("move_down")
	movement_input.z = Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	movement_input = movement_input.normalized()
	
	# Rotation input
	rotation_input = Vector3.ZERO
	rotation_input.x = Input.get_action_strength("pitch_up") - Input.get_action_strength("pitch_down")
	rotation_input.y = Input.get_action_strength("yaw_left") - Input.get_action_strength("yaw_right")
	roll_input = Input.get_action_strength("roll_left") - Input.get_action_strength("roll_right")
	
	# Special actions
	is_stabilized = Input.is_action_pressed("stabilize")
	is_boosting = Input.is_action_pressed("boost")
	
	if Input.is_action_just_pressed("toggle_boots"):
		toggle_magnetic_boots()
	
	if Input.is_action_just_pressed("fire_grapple"):
		fire_grapple()
	
	if Input.is_action_just_pressed("detach_grapple"):
		detach_all_grapples()
	
	if Input.is_action_pressed("reel_in"):
		reel_grapples(1.0, delta)
	elif Input.is_action_pressed("reel_out"):
		reel_grapples(-1.0, delta)

func _update_movement(delta):
	if magnetic_boots_active and attached_surface:
		_update_magnetic_movement(delta)
		return
	
	if current_fuel <= 0 and not is_stabilized:
		return
	
	# Calculate thrust direction in world space
	var thrust_direction = transform.basis * movement_input
	
	# Apply thrust
	var thrust_force = linear_thrust
	if is_boosting and current_fuel > fuel_consumption_rate * 2:
		thrust_force *= boost_multiplier
	
	add_central_force(thrust_direction * thrust_force)
	
	# Emergency brake
	if Input.is_action_pressed("brake"):
		apply_central_impulse(-linear_velocity.normalized() * emergency_brake_force * delta)

func _update_rotation(delta):
	if magnetic_boots_active and attached_surface:
		return
	
	if is_stabilized:
		_apply_stabilization(delta)
	else:
		# Manual rotation control
		var torque = Vector3.ZERO
		torque += transform.basis.x * rotation_input.x * angular_thrust
		torque += transform.basis.y * rotation_input.y * angular_thrust
		torque += transform.basis.z * roll_input * angular_thrust
		
		add_torque(torque)

func _apply_stabilization(delta):
	# Gradually stop rotation
	var stabilization_torque = -angular_velocity * stabilization_strength
	add_torque(stabilization_torque)
	
	# If fuel available, also stabilize orientation
	if current_fuel > 0:
		var up_direction = transform.basis.y
		var desired_up = Vector3.UP
		
		if attached_surface:
			desired_up = surface_normal
		
		var rotation_axis = up_direction.cross(desired_up)
		var rotation_angle = up_direction.angle_to(desired_up)
		
		if rotation_angle > 0.01:
			add_torque(rotation_axis * rotation_angle * stabilization_strength * 0.5)

func _update_fuel(delta):
	if movement_input.length() > 0.1 or is_stabilized:
		# Consume fuel
		var consumption = fuel_consumption_rate * delta
		if is_boosting:
			consumption *= 2.0
		
		current_fuel = max(0, current_fuel - consumption)
		
		if current_fuel == 0:
			emit_signal("fuel_depleted")
	else:
		# Regenerate fuel when not thrusting
		current_fuel = min(fuel_capacity, current_fuel + fuel_regeneration_rate * delta)
		
		if current_fuel == fuel_capacity:
			emit_signal("fuel_restored")

func _update_magnetic_boots(delta):
	if not magnetic_boots_active:
		return
	
	if attached_surface:
		# Apply force to stick to surface
		var to_surface = attached_surface.global_transform.origin - global_transform.origin
		var distance = to_surface.length()
		
		if distance > magnetic_boot_range * 2:
			detach_from_surface()
		else:
			# Magnetic attraction
			add_central_force(surface_normal * -magnetic_boot_strength)
			
			# Align to surface if enabled
			if auto_align_to_surface:
				_align_to_surface(delta)
	else:
		# Look for nearby surfaces
		_scan_for_surfaces()

func _scan_for_surfaces():
	var space_state = get_world().direct_space_state
	var directions = [
		-transform.basis.y,  # Down
		-transform.basis.z,  # Forward
		transform.basis.z,   # Back
		-transform.basis.x,  # Left
		transform.basis.x    # Right
	]
	
	for dir in directions:
		var result = space_state.intersect_ray(
			global_transform.origin,
			global_transform.origin + dir * magnetic_boot_range,
			[self]
		)
		
		if result:
			var angle = rad2deg(dir.angle_to(-result.normal))
			if angle < boot_activation_angle:
				attach_to_surface(result.collider, result.normal)
				break

func attach_to_surface(surface: PhysicsBody, normal: Vector3):
	attached_surface = surface
	surface_normal = normal
	magnetic_boots_active = true
	set_gravity_scale(0.0)
	
	# Reduce velocity
	linear_velocity *= 0.1
	angular_velocity *= 0.1
	
	emit_signal("surface_attached", surface)

func detach_from_surface():
	if attached_surface:
		# Push off from surface
		apply_central_impulse(surface_normal * 5.0)
		
		attached_surface = null
		surface_normal = Vector3.UP
		
		emit_signal("surface_detached")

func toggle_magnetic_boots():
	magnetic_boots_active = !magnetic_boots_active
	
	if not magnetic_boots_active:
		detach_from_surface()

func _align_to_surface(delta):
	var desired_up = surface_normal
	var current_up = transform.basis.y
	
	var rotation_axis = current_up.cross(desired_up)
	var rotation_angle = current_up.angle_to(desired_up)
	
	if rotation_angle > 0.01:
		# Use physics rotation for smooth alignment
		add_torque(rotation_axis * rotation_angle * 10.0)

func _update_magnetic_movement(delta):
	# Movement along surface
	var surface_forward = transform.basis.z
	var surface_right = transform.basis.x
	
	# Project movement onto surface plane
	var move_direction = surface_right * movement_input.x + surface_forward * -movement_input.z
	move_direction = move_direction.normalized()
	
	# Apply movement force
	if move_direction.length() > 0.1:
		add_central_force(move_direction * linear_thrust * 0.5)

func fire_grapple():
	if grapple_points.size() >= max_tethers:
		return
	
	# Cast ray to find grapple point
	var camera_forward = -camera.global_transform.basis.z
	var space_state = get_world().direct_space_state
	
	var result = space_state.intersect_ray(
		camera.global_transform.origin,
		camera.global_transform.origin + camera_forward * grapple_range,
		[self]
	)
	
	if result:
		create_grapple_point(result.position, result.collider)

func create_grapple_point(position: Vector3, target: PhysicsBody):
	var grapple_data = {
		"position": position,
		"target": target,
		"length": (position - global_transform.origin).length(),
		"joint": null
	}
	
	# Create physics joint
	var joint = Generic6DOFJoint.new()
	add_child(joint)
	joint.set_node_a(self.get_path())
	joint.set_node_b(target.get_path())
	
	# Configure as rope constraint
	joint.set_param_x(Generic6DOFJoint.PARAM_LINEAR_LOWER_LIMIT, -grapple_data.length)
	joint.set_param_x(Generic6DOFJoint.PARAM_LINEAR_UPPER_LIMIT, grapple_data.length)
	joint.set_param_y(Generic6DOFJoint.PARAM_LINEAR_LOWER_LIMIT, -grapple_data.length)
	joint.set_param_y(Generic6DOFJoint.PARAM_LINEAR_UPPER_LIMIT, grapple_data.length)
	joint.set_param_z(Generic6DOFJoint.PARAM_LINEAR_LOWER_LIMIT, -grapple_data.length)
	joint.set_param_z(Generic6DOFJoint.PARAM_LINEAR_UPPER_LIMIT, grapple_data.length)
	
	grapple_data.joint = joint
	grapple_points.append(grapple_data)
	active_tethers.append(grapple_data)
	
	emit_signal("grapple_attached", position)

func detach_all_grapples():
	for grapple in grapple_points:
		if grapple.joint:
			grapple.joint.queue_free()
	
	grapple_points.clear()
	active_tethers.clear()
	emit_signal("grapple_detached")

func reel_grapples(direction: float, delta: float):
	for grapple in grapple_points:
		grapple.length = max(2.0, grapple.length - direction * grapple_reel_speed * delta)
		
		# Update joint limits
		if grapple.joint:
			grapple.joint.set_param_x(Generic6DOFJoint.PARAM_LINEAR_LOWER_LIMIT, -grapple.length)
			grapple.joint.set_param_x(Generic6DOFJoint.PARAM_LINEAR_UPPER_LIMIT, grapple.length)
			# Update Y and Z limits similarly

func _update_grapples(delta):
	# Visual update for tether lines
	if tether_line:
		tether_line.clear()
		for grapple in grapple_points:
			tether_line.add_vertex(global_transform.origin)
			tether_line.add_vertex(grapple.position)
	
	# Apply tension forces
	for grapple in grapple_points:
		var to_grapple = grapple.position - global_transform.origin
		var distance = to_grapple.length()
		
		if distance > grapple.length:
			# Apply tension
			var tension_force = to_grapple.normalized() * (distance - grapple.length) * grapple_force
			add_central_force(tension_force)

func _apply_velocity_limits():
	# Limit linear velocity
	if linear_velocity.length() > max_linear_velocity:
		linear_velocity = linear_velocity.normalized() * max_linear_velocity
	
	# Limit angular velocity
	if angular_velocity.length() > max_angular_velocity:
		angular_velocity = angular_velocity.normalized() * max_angular_velocity

func _update_ui():
	if fuel_ui:
		fuel_ui.value = current_fuel
	
	if velocity_ui:
		velocity_ui.text = "Velocity: %.1f m/s" % linear_velocity.length()
	
	if orientation_ui:
		var euler = transform.basis.get_euler()
		orientation_ui.text = "Pitch: %.1f° Yaw: %.1f° Roll: %.1f°" % [
			rad2deg(euler.x),
			rad2deg(euler.y),
			rad2deg(euler.z)
		]

func _update_effects():
	# Thruster particles
	if thruster_particles:
		thruster_particles.emitting = movement_input.length() > 0.1
		
		if is_boosting:
			thruster_particles.amount = 100
			thruster_particles.initial_velocity = 20.0
		else:
			thruster_particles.amount = 50
			thruster_particles.initial_velocity = 10.0

func get_velocity_relative_to_surface() -> Vector3:
	if attached_surface:
		return linear_velocity - attached_surface.linear_velocity
	return linear_velocity

func apply_external_force(force: Vector3, duration: float = 0.1):
	# Apply external forces (explosions, collisions, etc)
	apply_central_impulse(force)
	
	# Temporarily disable stabilization
	if is_stabilized:
		is_stabilized = false
		yield(get_tree().create_timer(duration), "timeout")
		is_stabilized = true