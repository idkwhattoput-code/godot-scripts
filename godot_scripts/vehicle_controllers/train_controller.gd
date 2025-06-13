extends Spatial

# Train configuration
export var locomotive_power = 5000.0  # kW
export var max_speed = 200.0  # km/h
export var brake_force = 3000.0
export var emergency_brake_force = 8000.0
export var track_gauge = 1.435  # meters (standard gauge)

# Physics
export var train_mass = 50000.0  # kg per car
export var rolling_resistance = 0.002
export var air_resistance = 0.003
export var gradient_resistance = 0.01
export var wheel_slip_threshold = 0.2

# Train composition
export var car_count = 5
export var car_length = 20.0
export var car_spacing = 1.0
export var max_cars = 20

# Track system
var current_track_segment = null
var track_position = 0.0  # Position along current segment
var track_network = {}
var junction_connections = {}
var current_speed = 0.0
var target_speed = 0.0

# Controls
var throttle = 0.0
var brake_amount = 0.0
var reverser = 1  # 1 = forward, -1 = reverse, 0 = neutral
var is_emergency_braking = false
var horn_active = false
var bell_active = false

# Train cars
var train_cars = []
var car_physics_bodies = []
var couplers = []

# Signals and safety
export var signal_detection_range = 500.0
var current_signal_state = "green"
var dead_mans_switch_timer = 0.0
export var dead_mans_timeout = 30.0
var safety_systems_active = true

# Passengers/cargo
export var passenger_capacity = 100  # per car
export var cargo_capacity = 50000.0  # kg per car
var current_passengers = 0
var current_cargo = 0.0
var passenger_comfort = 1.0

# Effects
onready var locomotive = $Locomotive
onready var wheels = []
onready var steam_effect = $Locomotive/SteamEffect
onready var smoke_stack = $Locomotive/SmokeStack
onready var headlight = $Locomotive/Headlight
onready var engine_sound = $Locomotive/EngineSound
onready var wheel_sound = $Locomotive/WheelSound
onready var brake_sound = $Locomotive/BrakeSound
onready var horn_sound = $Locomotive/HornSound
onready var bell_sound = $Locomotive/BellSound

# Track detection
onready var track_scanner = $Locomotive/TrackScanner
onready var front_bogie = $Locomotive/FrontBogie
onready var rear_bogie = $Locomotive/RearBogie

signal speed_changed(speed)
signal arrived_at_station(station_name)
signal signal_passed(signal_state)
signal emergency_stop()
signal derailed()
signal coupled(car)
signal decoupled(car)

func _ready():
	_setup_train()
	_initialize_track_system()
	set_physics_process(true)

func _setup_train():
	# Create train cars
	for i in range(car_count):
		var car = _create_train_car(i)
		train_cars.append(car)
		
		# Position car
		var car_offset = (car_length + car_spacing) * (i + 1)
		car.translation.z = car_offset
		
		# Create physics body for car
		var car_body = RigidBody.new()
		car_body.mass = train_mass
		car_body.add_child(car)
		car_physics_bodies.append(car_body)
		
		# Create coupler
		if i > 0:
			var coupler = _create_coupler(train_cars[i-1], car)
			couplers.append(coupler)
	
	# Setup wheel references
	_find_all_wheels()

func _create_train_car(index: int) -> Spatial:
	var car = Spatial.new()
	car.name = "Car_" + str(index)
	
	# Add car mesh
	var mesh_instance = MeshInstance.new()
	# Set up car mesh
	car.add_child(mesh_instance)
	
	# Add bogies (wheel assemblies)
	var front_bogie = _create_bogie()
	front_bogie.translation.z = -car_length * 0.4
	car.add_child(front_bogie)
	
	var rear_bogie = _create_bogie()
	rear_bogie.translation.z = car_length * 0.4
	car.add_child(rear_bogie)
	
	add_child(car)
	return car

func _create_bogie() -> Spatial:
	var bogie = Spatial.new()
	
	# Add wheels
	for i in range(4):  # 4 wheels per bogie
		var wheel = MeshInstance.new()
		# Configure wheel mesh
		wheel.translation.x = (i % 2) * track_gauge - track_gauge/2
		wheel.translation.z = (i / 2) * 2.0 - 1.0
		bogie.add_child(wheel)
		wheels.append(wheel)
	
	return bogie

func _create_coupler(front_car: Spatial, rear_car: Spatial) -> Joint:
	var coupler = Generic6DOFJoint.new()
	coupler.set_node_a(front_car.get_path())
	coupler.set_node_b(rear_car.get_path())
	
	# Configure joint limits for realistic coupling
	coupler.set_param_x(Generic6DOFJoint.PARAM_LINEAR_LOWER_LIMIT, -0.5)
	coupler.set_param_x(Generic6DOFJoint.PARAM_LINEAR_UPPER_LIMIT, 0.5)
	
	add_child(coupler)
	return coupler

func _initialize_track_system():
	# Load track network from scene or data
	# This would typically load track segments, junctions, signals, etc.
	pass

func _physics_process(delta):
	_handle_input()
	_update_train_physics(delta)
	_update_track_following(delta)
	_update_safety_systems(delta)
	_check_signals()
	_update_effects(delta)
	_update_passenger_comfort(delta)

func _handle_input():
	# Throttle control
	if Input.is_action_pressed("throttle_up"):
		throttle = min(throttle + 0.02, 1.0)
	elif Input.is_action_pressed("throttle_down"):
		throttle = max(throttle - 0.02, 0.0)
	
	# Brake control
	if Input.is_action_pressed("brake"):
		brake_amount = Input.get_action_strength("brake")
	else:
		brake_amount = 0.0
	
	# Emergency brake
	if Input.is_action_just_pressed("emergency_brake"):
		_activate_emergency_brake()
	
	# Reverser
	if Input.is_action_just_pressed("reverse") and abs(current_speed) < 0.1:
		reverser = -reverser
	
	# Horn and bell
	horn_active = Input.is_action_pressed("horn")
	if Input.is_action_just_pressed("bell"):
		bell_active = !bell_active
	
	# Dead man's switch
	if Input.is_action_pressed("acknowledge"):
		dead_mans_switch_timer = 0.0
	
	# Junction control
	if Input.is_action_just_pressed("switch_track"):
		_switch_junction()

func _update_train_physics(delta):
	# Calculate tractive effort
	var speed_ms = current_speed / 3.6
	var tractive_effort = 0.0
	
	if abs(speed_ms) < max_speed / 3.6:
		var power_watts = locomotive_power * 1000 * throttle
		if speed_ms > 0.1:
			tractive_effort = power_watts / speed_ms
		else:
			tractive_effort = power_watts / 0.1  # Starting tractive effort
		
		tractive_effort = min(tractive_effort, _calculate_max_tractive_effort())
	
	# Apply reverser
	tractive_effort *= reverser
	
	# Calculate resistances
	var total_mass = train_mass * (car_count + 1)
	var rolling_resistance_force = total_mass * 9.81 * rolling_resistance * sign(current_speed)
	var air_resistance_force = 0.5 * air_resistance * speed_ms * speed_ms * sign(current_speed)
	var gradient_force = _calculate_gradient_resistance() * total_mass * 9.81
	
	# Calculate braking force
	var braking_force = 0.0
	if is_emergency_braking:
		braking_force = emergency_brake_force * sign(current_speed)
	else:
		braking_force = brake_force * brake_amount * sign(current_speed)
	
	# Net force
	var net_force = tractive_effort - rolling_resistance_force - air_resistance_force - gradient_force - braking_force
	
	# Check for wheel slip
	if abs(tractive_effort) > _calculate_max_tractive_effort():
		net_force *= 0.3  # Reduced effectiveness during wheel slip
		_trigger_wheel_slip_effects()
	
	# Update speed
	var acceleration = net_force / total_mass
	current_speed += acceleration * delta * 3.6  # Convert to km/h
	
	# Clamp speed
	current_speed = clamp(current_speed, -max_speed * 0.3, max_speed)
	
	# Stop if very slow
	if abs(current_speed) < 0.1 and throttle == 0:
		current_speed = 0
	
	emit_signal("speed_changed", current_speed)

func _calculate_max_tractive_effort() -> float:
	# Maximum tractive effort limited by wheel adhesion
	var total_mass = train_mass * (car_count + 1)
	var weight_on_drivers = total_mass * 9.81 * 0.5  # Assume 50% on drive wheels
	return weight_on_drivers * wheel_slip_threshold

func _calculate_gradient_resistance() -> float:
	# Get track gradient at current position
	if current_track_segment:
		# return current_track_segment.get_gradient_at(track_position)
		return 0.0  # Placeholder
	return 0.0

func _update_track_following(delta):
	if not current_track_segment:
		return
	
	# Move along track
	var distance = (current_speed / 3.6) * delta
	track_position += distance
	
	# Check if we need to move to next segment
	# if track_position > current_track_segment.length:
	#     _move_to_next_segment()
	
	# Update train position and rotation based on track
	_align_train_to_track()

func _align_train_to_track():
	# This would calculate the position and rotation of each car
	# based on the track geometry
	
	# For now, simple forward movement
	translate(transform.basis.z * -(current_speed / 3.6) * get_physics_process_delta_time())
	
	# Rotate wheels
	for wheel in wheels:
		if wheel:
			wheel.rotate_x((current_speed / 3.6) * get_physics_process_delta_time() / 0.5)

func _update_safety_systems(delta):
	if not safety_systems_active:
		return
	
	# Dead man's switch
	dead_mans_switch_timer += delta
	if dead_mans_switch_timer > dead_mans_timeout:
		_activate_emergency_brake()
		push_warning("Dead man's switch activated!")
	
	# Speed limit enforcement
	var speed_limit = _get_current_speed_limit()
	if current_speed > speed_limit:
		# Automatic brake application
		brake_amount = min((current_speed - speed_limit) / 20.0, 1.0)
	
	# Collision detection
	if track_scanner and track_scanner.is_colliding():
		var obstacle = track_scanner.get_collider()
		if obstacle.is_in_group("trains") or obstacle.is_in_group("obstacles"):
			_activate_emergency_brake()
			push_warning("Obstacle detected!")

func _check_signals():
	# Check for signals ahead
	var space_state = get_world().direct_space_state
	var from = global_transform.origin
	var to = from + transform.basis.z * -signal_detection_range
	
	var result = space_state.intersect_ray(from, to, [self], 1)  # Layer 1 for signals
	
	if result and result.collider.is_in_group("signals"):
		var signal_state = result.collider.get_state()
		if signal_state != current_signal_state:
			current_signal_state = signal_state
			emit_signal("signal_passed", signal_state)
			
			# React to signal
			match signal_state:
				"red":
					if safety_systems_active:
						_activate_emergency_brake()
				"yellow":
					target_speed = min(current_speed, 40.0)

func _activate_emergency_brake():
	is_emergency_braking = true
	throttle = 0
	emit_signal("emergency_stop")
	
	# Reset after stop
	if abs(current_speed) < 0.1:
		is_emergency_braking = false

func _switch_junction():
	# Switch to alternate track at junction
	# This would interact with the track network system
	pass

func _update_effects(delta):
	# Engine sound
	if engine_sound:
		engine_sound.pitch_scale = 0.8 + throttle * 0.4
		engine_sound.volume_db = linear2db(0.5 + throttle * 0.5)
		if not engine_sound.playing and abs(current_speed) > 0:
			engine_sound.play()
	
	# Wheel sound
	if wheel_sound:
		wheel_sound.pitch_scale = 0.5 + abs(current_speed) / max_speed
		wheel_sound.volume_db = linear2db(abs(current_speed) / max_speed)
		if not wheel_sound.playing and abs(current_speed) > 1:
			wheel_sound.play()
		elif wheel_sound.playing and abs(current_speed) < 1:
			wheel_sound.stop()
	
	# Brake sound
	if brake_sound:
		if brake_amount > 0.1:
			if not brake_sound.playing:
				brake_sound.play()
			brake_sound.volume_db = linear2db(brake_amount)
		else:
			brake_sound.stop()
	
	# Horn
	if horn_sound:
		if horn_active and not horn_sound.playing:
			horn_sound.play()
		elif not horn_active and horn_sound.playing:
			horn_sound.stop()
	
	# Bell
	if bell_sound:
		if bell_active and not bell_sound.playing:
			bell_sound.play()
		elif not bell_active and bell_sound.playing:
			bell_sound.stop()
	
	# Steam/smoke effects
	if steam_effect:
		steam_effect.emitting = throttle > 0.1
		steam_effect.amount = int(50 * throttle)
	
	# Headlight
	if headlight:
		headlight.light_energy = 2.0 if current_signal_state != "red" else 0.5

func _update_passenger_comfort(delta):
	# Calculate comfort based on acceleration and jerk
	var acceleration = 0  # Calculate from speed changes
	var jerk = 0  # Calculate from acceleration changes
	
	passenger_comfort = 1.0
	passenger_comfort -= abs(acceleration) * 0.1
	passenger_comfort -= abs(jerk) * 0.2
	passenger_comfort = clamp(passenger_comfort, 0, 1)

func _trigger_wheel_slip_effects():
	# Visual and audio effects for wheel slip
	pass

func _find_all_wheels():
	# Recursively find all wheel meshes
	wheels.clear()
	_find_wheels_recursive(self)

func _find_wheels_recursive(node: Node):
	if node.name.find("Wheel") != -1 and node is MeshInstance:
		wheels.append(node)
	
	for child in node.get_children():
		_find_wheels_recursive(child)

func _get_current_speed_limit() -> float:
	# Get speed limit for current track section
	return max_speed  # Default to max

# Public API
func set_destination(station_name: String):
	# Set automated route to station
	pass

func couple_car(car: Spatial):
	# Add car to train
	if train_cars.size() < max_cars:
		train_cars.append(car)
		car_count += 1
		emit_signal("coupled", car)

func decouple_car(index: int):
	# Remove car from train
	if index >= 0 and index < train_cars.size():
		var car = train_cars[index]
		train_cars.remove(index)
		car_count -= 1
		emit_signal("decoupled", car)

func load_passengers(count: int):
	current_passengers = min(current_passengers + count, passenger_capacity * car_count)

func load_cargo(weight: float):
	current_cargo = min(current_cargo + weight, cargo_capacity * car_count)

func get_train_info() -> Dictionary:
	return {
		"speed": current_speed,
		"throttle": throttle,
		"brake": brake_amount,
		"cars": car_count,
		"passengers": current_passengers,
		"cargo": current_cargo,
		"signal": current_signal_state,
		"comfort": passenger_comfort
	}