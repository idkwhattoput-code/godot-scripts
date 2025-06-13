extends RigidBody3D

signal landed
signal crashed(impact_force: float)
signal altitude_warning(altitude: float)

@export_group("Flight Dynamics")
@export var main_rotor_force: float = 20000.0
@export var tail_rotor_force: float = 500.0
@export var max_tilt_angle: float = 30.0
@export var cyclic_sensitivity: float = 2.0
@export var collective_sensitivity: float = 5.0
@export var yaw_sensitivity: float = 3.0
@export var hover_height: float = 10.0
@export var auto_hover: bool = false

@export_group("Stabilization")
@export var gyro_stabilization: bool = true
@export var stabilization_strength: float = 5.0
@export var wind_resistance: float = 0.5
@export var ground_effect_height: float = 3.0
@export var ground_effect_multiplier: float = 1.3

@export_group("Engine")
@export var engine_spool_time: float = 5.0
@export var fuel_capacity: float = 500.0
@export var fuel_consumption_rate: float = 0.5
@export var auto_rotation_enabled: bool = true
@export var engine_failure_chance: float = 0.0

@export_group("Rotors")
@export var main_rotor_node: Node3D
@export var tail_rotor_node: Node3D
@export var rotor_speed_idle: float = 100.0
@export var rotor_speed_max: float = 500.0
@export var rotor_sound: AudioStream

@export_group("Safety")
@export var low_altitude_warning: float = 5.0
@export var max_safe_landing_speed: float = 5.0
@export var damage_threshold: float = 10.0

var engine_power: float = 0.0
var is_engine_on: bool = false
var current_fuel: float
var rotor_speed: float = 0.0
var is_grounded: bool = false
var ground_distance: float = 0.0

var cyclic_input: Vector2 = Vector2.ZERO
var collective_input: float = 0.0
var pedal_input: float = 0.0

var current_tilt: Vector2 = Vector2.ZERO
var hover_target_height: float = 0.0
var auto_rotation_active: bool = false

var audio_player: AudioStreamPlayer3D
var ground_ray: RayCast3D
var damage_taken: float = 0.0

func _ready():
	current_fuel = fuel_capacity
	
	audio_player = AudioStreamPlayer3D.new()
	audio_player.stream = rotor_sound
	audio_player.unit_size = 30.0
	add_child(audio_player)
	
	ground_ray = RayCast3D.new()
	ground_ray.target_position = Vector3(0, -100, 0)
	ground_ray.collision_mask = 1
	add_child(ground_ray)
	
	contact_monitor = true
	max_contacts_reported = 10
	body_entered.connect(_on_body_entered)
	
func _physics_process(delta):
	_update_ground_detection()
	_update_engine(delta)
	_update_rotors(delta)
	_apply_flight_forces(delta)
	_apply_stabilization(delta)
	_consume_fuel(delta)
	_check_altitude_warning()
	
func _update_ground_detection():
	if ground_ray.is_colliding():
		ground_distance = global_position.distance_to(ground_ray.get_collision_point())
		is_grounded = ground_distance < 0.5
	else:
		ground_distance = 999.0
		is_grounded = false
		
func _update_engine(delta):
	if is_engine_on and current_fuel > 0:
		engine_power = move_toward(engine_power, 1.0, delta / engine_spool_time)
		rotor_speed = move_toward(rotor_speed, rotor_speed_max, delta * 100)
	else:
		engine_power = move_toward(engine_power, 0.0, delta / engine_spool_time)
		rotor_speed = move_toward(rotor_speed, 0.0, delta * 50)
		
		if auto_rotation_enabled and not is_grounded and rotor_speed > rotor_speed_idle:
			auto_rotation_active = true
			rotor_speed = max(rotor_speed - delta * 20, rotor_speed_idle)
			
	if audio_player and rotor_speed > 0:
		if not audio_player.playing:
			audio_player.play()
		audio_player.pitch_scale = 0.5 + (rotor_speed / rotor_speed_max) * 0.5
		audio_player.volume_db = linear_to_db(rotor_speed / rotor_speed_max)
	elif audio_player and audio_player.playing:
		audio_player.stop()
		
func _update_rotors(delta):
	if main_rotor_node:
		main_rotor_node.rotate_y(rotor_speed * delta * 0.1)
		
	if tail_rotor_node:
		tail_rotor_node.rotate_x(rotor_speed * delta * 0.3)
		
func _apply_flight_forces(delta):
	var rotor_efficiency = rotor_speed / rotor_speed_max
	
	if auto_rotation_active:
		rotor_efficiency *= 0.3
		
	var lift_force = Vector3.UP * main_rotor_force * collective_input * rotor_efficiency
	
	if ground_distance < ground_effect_height:
		var ground_effect = 1.0 + (ground_effect_multiplier - 1.0) * (1.0 - ground_distance / ground_effect_height)
		lift_force *= ground_effect
		
	apply_central_force(lift_force * delta)
	
	var forward = -transform.basis.z
	var right = transform.basis.x
	
	current_tilt = current_tilt.lerp(cyclic_input * deg_to_rad(max_tilt_angle), cyclic_sensitivity * delta)
	
	var tilt_torque = Vector3.ZERO
	tilt_torque.x = current_tilt.y
	tilt_torque.z = -current_tilt.x
	apply_torque(transform.basis * tilt_torque * 10.0 * delta)
	
	var forward_thrust = forward * current_tilt.y * main_rotor_force * 0.3 * rotor_efficiency
	var lateral_thrust = right * current_tilt.x * main_rotor_force * 0.3 * rotor_efficiency
	apply_central_force((forward_thrust + lateral_thrust) * delta)
	
	var yaw_torque = transform.basis.y * pedal_input * tail_rotor_force * rotor_efficiency
	apply_torque(yaw_torque * delta)
	
	var anti_torque = -transform.basis.y * collective_input * tail_rotor_force * 0.2 * rotor_efficiency
	apply_torque(anti_torque * delta)
	
	var drag = -linear_velocity * wind_resistance
	apply_central_force(drag * delta)
	
	if auto_hover and collective_input > 0.1:
		_apply_auto_hover(delta)
		
func _apply_stabilization(delta):
	if not gyro_stabilization or is_grounded:
		return
		
	var current_rotation = transform.basis.get_euler()
	var stabilization_torque = Vector3.ZERO
	
	if cyclic_input.length() < 0.1:
		stabilization_torque.x = -current_rotation.x * stabilization_strength
		stabilization_torque.z = -current_rotation.z * stabilization_strength
		
	stabilization_torque.y = -angular_velocity.y * stabilization_strength * 0.5
	
	apply_torque(stabilization_torque * delta)
	
func _apply_auto_hover(delta):
	if hover_target_height == 0:
		hover_target_height = ground_distance
		
	var height_error = hover_target_height - ground_distance
	var hover_correction = clamp(height_error * 0.5, -1.0, 1.0)
	
	collective_input = move_toward(collective_input, 0.5 + hover_correction * 0.3, delta)
	
func _consume_fuel(delta):
	if is_engine_on and current_fuel > 0:
		current_fuel -= fuel_consumption_rate * collective_input * delta
		if current_fuel <= 0:
			current_fuel = 0
			stop_engine()
			
	if engine_failure_chance > 0 and randf() < engine_failure_chance * delta:
		stop_engine()
		
func _check_altitude_warning():
	if ground_distance < low_altitude_warning and not is_grounded and linear_velocity.y < 0:
		altitude_warning.emit(ground_distance)
		
func start_engine():
	if current_fuel > 0 and damage_taken < damage_threshold:
		is_engine_on = true
		auto_rotation_active = false
		
func stop_engine():
	is_engine_on = false
	
func set_controls(cyclic: Vector2, collective: float, pedals: float):
	cyclic_input = cyclic.limit_length(1.0) * cyclic_sensitivity
	collective_input = clamp(collective, 0.0, 1.0) * collective_sensitivity
	pedal_input = clamp(pedals, -1.0, 1.0) * yaw_sensitivity
	
	if not auto_hover:
		hover_target_height = 0
		
func emergency_autorotation():
	stop_engine()
	auto_rotation_active = true
	collective_input = 0.2
	
func _on_body_entered(body: Node3D):
	var impact_velocity = linear_velocity.length()
	
	if impact_velocity > max_safe_landing_speed:
		var impact_force = impact_velocity - max_safe_landing_speed
		damage_taken += impact_force
		crashed.emit(impact_force)
		
		if damage_taken >= damage_threshold:
			stop_engine()
	elif is_grounded and impact_velocity <= max_safe_landing_speed:
		landed.emit()
		
func refuel(amount: float):
	current_fuel = min(current_fuel + amount, fuel_capacity)
	
func repair(amount: float):
	damage_taken = max(0, damage_taken - amount)
	
func get_flight_data() -> Dictionary:
	return {
		"altitude": ground_distance,
		"speed": linear_velocity.length(),
		"fuel": current_fuel / fuel_capacity,
		"rotor_speed": rotor_speed / rotor_speed_max,
		"engine_power": engine_power,
		"is_grounded": is_grounded,
		"damage": damage_taken / damage_threshold,
		"auto_rotation": auto_rotation_active
	}