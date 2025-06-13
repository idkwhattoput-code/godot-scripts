extends RigidBody3D

signal landed
signal crashed(impact_force: float)
signal engine_started
signal engine_stopped

@export_group("Flight Physics")
@export var thrust_force: float = 15000.0
@export var max_speed: float = 200.0
@export var lift_coefficient: float = 1.2
@export var drag_coefficient: float = 0.3
@export var stall_angle: float = 20.0
@export var min_takeoff_speed: float = 50.0

@export_group("Control Surfaces")
@export var pitch_force: float = 50.0
@export var roll_force: float = 40.0
@export var yaw_force: float = 30.0
@export var control_responsiveness: float = 5.0
@export var auto_stabilize: bool = true
@export var stabilization_strength: float = 2.0

@export_group("Engine")
@export var fuel_capacity: float = 1000.0
@export var fuel_consumption_rate: float = 1.0
@export var engine_spool_time: float = 3.0
@export var engine_sound: AudioStream
@export var propeller_node: Node3D

@export_group("Landing Gear")
@export var landing_gear_nodes: Array[Node3D] = []
@export var gear_deploy_speed: float = 2.0
@export var auto_deploy_altitude: float = 50.0
@export var landing_speed_threshold: float = 80.0

var current_fuel: float
var engine_power: float = 0.0
var is_engine_on: bool = false
var is_airborne: bool = false
var is_gear_deployed: bool = true
var current_altitude: float = 0.0
var ground_contact_points: int = 0

var pitch_input: float = 0.0
var roll_input: float = 0.0
var yaw_input: float = 0.0
var throttle_input: float = 0.0

var audio_player: AudioStreamPlayer3D
var altitude_ray: RayCast3D

func _ready():
	current_fuel = fuel_capacity
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	
	audio_player = AudioStreamPlayer3D.new()
	audio_player.stream = engine_sound
	audio_player.unit_size = 20.0
	add_child(audio_player)
	
	altitude_ray = RayCast3D.new()
	altitude_ray.target_position = Vector3(0, -1000, 0)
	altitude_ray.collision_mask = 1
	add_child(altitude_ray)
	
	_setup_landing_gear()
	
func _setup_landing_gear():
	for gear in landing_gear_nodes:
		if gear.has_node("WheelCollider"):
			var collider = gear.get_node("WheelCollider")
			collider.body_entered.connect(_on_wheel_contact)
			collider.body_exited.connect(_on_wheel_exit)
			
func _physics_process(delta):
	_update_altitude()
	_update_engine(delta)
	_apply_flight_physics(delta)
	_apply_controls(delta)
	_update_landing_gear(delta)
	_consume_fuel(delta)
	_check_stall()
	
	if propeller_node and is_engine_on:
		propeller_node.rotate_z(engine_power * delta * 50.0)
		
func _update_altitude():
	if altitude_ray.is_colliding():
		current_altitude = global_position.distance_to(altitude_ray.get_collision_point())
	else:
		current_altitude = global_position.y
		
	is_airborne = ground_contact_points == 0
	
func _update_engine(delta):
	if is_engine_on:
		engine_power = move_toward(engine_power, throttle_input, delta / engine_spool_time)
		if audio_player:
			audio_player.pitch_scale = 0.8 + engine_power * 0.6
			audio_player.volume_db = linear_to_db(0.5 + engine_power * 0.5)
	else:
		engine_power = move_toward(engine_power, 0.0, delta / engine_spool_time)
		
func _apply_flight_physics(delta):
	var velocity = linear_velocity
	var forward = -transform.basis.z
	var right = transform.basis.x
	var up = transform.basis.y
	
	var forward_speed = velocity.dot(forward)
	var thrust = forward * thrust_force * engine_power * delta
	
	if forward_speed < max_speed:
		apply_central_force(thrust)
		
	var lift_force = _calculate_lift(forward_speed, up)
	apply_central_force(lift_force * delta)
	
	var drag_force = _calculate_drag(velocity)
	apply_central_force(-drag_force * delta)
	
	if not is_airborne:
		var ground_friction = -velocity * 5.0
		ground_friction.y = 0
		apply_central_force(ground_friction * delta)
		
func _calculate_lift(speed: float, up_vector: Vector3) -> Vector3:
	if speed < min_takeoff_speed * 0.5:
		return Vector3.ZERO
		
	var angle_of_attack = rad_to_deg(acos(up_vector.dot(Vector3.UP)))
	var lift_multiplier = 1.0 - (angle_of_attack / 90.0)
	lift_multiplier = clamp(lift_multiplier, 0.0, 1.0)
	
	var lift_magnitude = lift_coefficient * speed * speed * lift_multiplier
	return Vector3.UP * lift_magnitude
	
func _calculate_drag(velocity: Vector3) -> Vector3:
	var speed = velocity.length()
	return velocity.normalized() * drag_coefficient * speed * speed
	
func _apply_controls(delta):
	if is_airborne:
		apply_torque(transform.basis.x * pitch_input * pitch_force * delta)
		apply_torque(transform.basis.z * roll_input * roll_force * delta)
		apply_torque(transform.basis.y * yaw_input * yaw_force * delta)
		
		if auto_stabilize and pitch_input == 0 and roll_input == 0:
			_apply_stabilization(delta)
	else:
		apply_torque(transform.basis.y * yaw_input * yaw_force * 0.3 * delta)
		
func _apply_stabilization(delta):
	var current_rotation = transform.basis.get_euler()
	var stabilization_torque = Vector3.ZERO
	
	stabilization_torque.x = -current_rotation.x * stabilization_strength
	stabilization_torque.z = -current_rotation.z * stabilization_strength
	
	apply_torque(stabilization_torque * delta)
	
func _update_landing_gear(delta):
	if auto_deploy_altitude > 0 and current_altitude < auto_deploy_altitude:
		deploy_landing_gear()
	elif current_altitude > auto_deploy_altitude * 2:
		retract_landing_gear()
		
	for gear in landing_gear_nodes:
		if gear:
			var target_scale = Vector3.ONE if is_gear_deployed else Vector3(1, 0.1, 1)
			gear.scale = gear.scale.lerp(target_scale, gear_deploy_speed * delta)
			
func _consume_fuel(delta):
	if is_engine_on and current_fuel > 0:
		current_fuel -= fuel_consumption_rate * engine_power * delta
		if current_fuel <= 0:
			current_fuel = 0
			stop_engine()
			
func _check_stall():
	var forward_speed = linear_velocity.dot(-transform.basis.z)
	var angle_of_attack = rad_to_deg(acos(transform.basis.y.dot(Vector3.UP)))
	
	if is_airborne and forward_speed < min_takeoff_speed and angle_of_attack > stall_angle:
		apply_central_force(Vector3.DOWN * 1000)
		apply_torque(transform.basis.x * 10)
		
func start_engine():
	if current_fuel > 0:
		is_engine_on = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		engine_started.emit()
		if audio_player:
			audio_player.play()
			
func stop_engine():
	is_engine_on = false
	engine_stopped.emit()
	if audio_player:
		audio_player.stop()
		
func deploy_landing_gear():
	is_gear_deployed = true
	
func retract_landing_gear():
	if is_airborne:
		is_gear_deployed = false
		
func set_controls(pitch: float, roll: float, yaw: float, throttle: float):
	pitch_input = clamp(pitch, -1.0, 1.0) * control_responsiveness
	roll_input = clamp(roll, -1.0, 1.0) * control_responsiveness
	yaw_input = clamp(yaw, -1.0, 1.0) * control_responsiveness
	throttle_input = clamp(throttle, 0.0, 1.0)
	
func _on_wheel_contact(body: Node3D):
	ground_contact_points += 1
	
	if linear_velocity.length() > landing_speed_threshold:
		var impact_force = linear_velocity.length() - landing_speed_threshold
		crashed.emit(impact_force)
	elif ground_contact_points >= 3:
		landed.emit()
		
func _on_wheel_exit(body: Node3D):
	ground_contact_points = max(0, ground_contact_points - 1)
	
func refuel(amount: float):
	current_fuel = min(current_fuel + amount, fuel_capacity)
	
func get_flight_data() -> Dictionary:
	return {
		"altitude": current_altitude,
		"speed": linear_velocity.length(),
		"fuel": current_fuel / fuel_capacity,
		"engine_power": engine_power,
		"is_airborne": is_airborne,
		"gear_deployed": is_gear_deployed
	}