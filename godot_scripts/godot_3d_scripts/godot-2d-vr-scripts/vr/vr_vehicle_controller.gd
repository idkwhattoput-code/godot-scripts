extends VehicleBody

class_name VRVehicleController

signal engine_started()
signal engine_stopped()
signal gear_changed(gear)
signal speed_changed(speed)
signal fuel_changed(fuel_level)
signal vehicle_entered()
signal vehicle_exited()
signal collision_detected(body, impulse)

enum VehicleType {
	CAR,
	MOTORCYCLE,
	TRUCK,
	BOAT,
	AIRPLANE,
	HELICOPTER,
	TANK,
	HOVERCRAFT
}

enum GearState {
	PARK,
	REVERSE,
	NEUTRAL,
	DRIVE_1,
	DRIVE_2,
	DRIVE_3,
	DRIVE_4,
	DRIVE_5,
	DRIVE_6
}

export var vehicle_type: int = VehicleType.CAR
export var max_speed: float = 30.0
export var acceleration: float = 20.0
export var brake_force: float = 30.0
export var steering_sensitivity: float = 1.0
export var max_steering_angle: float = 30.0
export var engine_power: float = 200.0
export var fuel_capacity: float = 100.0
export var fuel_consumption: float = 0.1
export var enable_manual_transmission: bool = false
export var enable_realistic_physics: bool = true
export var enable_damage_system: bool = true
export var max_damage: float = 100.0
export var enable_vr_controls: bool = true
export var steering_wheel_size: float = 0.3
export var seat_height: float = 0.8

var player_controller: ARVROrigin
var left_controller: ARVRController
var right_controller: ARVRController
var current_speed: float = 0.0
var current_gear: int = GearState.PARK
var fuel_level: float = 100.0
var damage_level: float = 0.0
var engine_running: bool = false
var is_player_inside: bool = false
var steering_input: float = 0.0
var throttle_input: float = 0.0
var brake_input: float = 0.0
var handbrake_active: bool = false

var seat_position: Spatial
var steering_wheel: VRSteeringWheel
var pedals: VRPedals
var gear_shifter: VRGearShifter
var dashboard: VRDashboard
var mirrors: Array = []
var engine_sound: AudioStreamPlayer3D
var wind_sound: AudioStreamPlayer3D
var wheel_nodes: Array = []

class VRSteeringWheel:
	var mesh: MeshInstance
	var area: Area
	var rotation_limit: float = 450.0
	var current_rotation: float = 0.0
	var grab_point: Vector3
	var is_grabbed: bool = false
	var grab_controller: ARVRController
	var force_feedback: bool = true
	
	func _init(size: float):
		setup_wheel(size)
	
	func setup_wheel(size: float):
		mesh = MeshInstance.new()
		var wheel_mesh = CylinderMesh.new()
		wheel_mesh.height = 0.05
		wheel_mesh.top_radius = size
		wheel_mesh.bottom_radius = size
		mesh.mesh = wheel_mesh
		
		area = Area.new()
		var collision = CollisionShape.new()
		var shape = CylinderShape.new()
		shape.height = 0.05
		shape.radius = size
		collision.shape = shape
		area.add_child(collision)
		mesh.add_child(area)
	
	func update_rotation(delta: float, input: float):
		if not is_grabbed:
			current_rotation = lerp(current_rotation, input * rotation_limit, delta * 5.0)
		
		mesh.rotation_degrees.z = current_rotation
	
	func get_steering_value() -> float:
		return current_rotation / rotation_limit

class VRPedals:
	var gas_pedal: VRPedal
	var brake_pedal: VRPedal
	var clutch_pedal: VRPedal
	
	func _init():
		gas_pedal = VRPedal.new("gas")
		brake_pedal = VRPedal.new("brake")
		clutch_pedal = VRPedal.new("clutch")

class VRPedal:
	var mesh: MeshInstance
	var area: Area
	var pedal_type: String
	var max_angle: float = 30.0
	var current_angle: float = 0.0
	var value: float = 0.0
	
	func _init(type: String):
		pedal_type = type
		setup_pedal()
	
	func setup_pedal():
		mesh = MeshInstance.new()
		var pedal_mesh = BoxMesh.new()
		pedal_mesh.size = Vector3(0.1, 0.03, 0.15)
		mesh.mesh = pedal_mesh
		
		area = Area.new()
		var collision = CollisionShape.new()
		var shape = BoxShape.new()
		shape.extents = Vector3(0.05, 0.015, 0.075)
		collision.shape = shape
		area.add_child(collision)
		mesh.add_child(area)
	
	func update_pedal(foot_position: Vector3):
		pass
	
	func get_pedal_value() -> float:
		return value

class VRGearShifter:
	var mesh: MeshInstance
	var area: Area
	var gear_positions: Dictionary = {}
	var current_position: Vector3
	var is_grabbed: bool = false
	
	func _init():
		setup_shifter()
	
	func setup_shifter():
		mesh = MeshInstance.new()
		var shifter_mesh = CylinderMesh.new()
		shifter_mesh.height = 0.15
		shifter_mesh.top_radius = 0.02
		shifter_mesh.bottom_radius = 0.03
		mesh.mesh = shifter_mesh
		
		area = Area.new()
		var collision = CollisionShape.new()
		var shape = CylinderShape.new()
		shape.height = 0.15
		shape.radius = 0.03
		collision.shape = shape
		area.add_child(collision)
		mesh.add_child(area)
		
		setup_gear_positions()
	
	func setup_gear_positions():
		gear_positions[GearState.PARK] = Vector3(0, 0, 0.1)
		gear_positions[GearState.REVERSE] = Vector3(-0.1, 0, 0.1)
		gear_positions[GearState.NEUTRAL] = Vector3(0, 0, 0)
		gear_positions[GearState.DRIVE_1] = Vector3(0, 0, -0.1)
		gear_positions[GearState.DRIVE_2] = Vector3(0.1, 0, -0.1)
		gear_positions[GearState.DRIVE_3] = Vector3(0.1, 0, 0)
		gear_positions[GearState.DRIVE_4] = Vector3(0.1, 0, 0.1)
	
	func get_nearest_gear(position: Vector3) -> int:
		var nearest_gear = GearState.NEUTRAL
		var min_distance = INF
		
		for gear in gear_positions:
			var distance = position.distance_to(gear_positions[gear])
			if distance < min_distance:
				min_distance = distance
				nearest_gear = gear
		
		return nearest_gear

class VRDashboard:
	var speedometer: VRGauge
	var fuel_gauge: VRGauge
	var engine_temp: VRGauge
	var rpm_gauge: VRGauge
	var warning_lights: Dictionary = {}
	
	func _init():
		setup_dashboard()
	
	func setup_dashboard():
		speedometer = VRGauge.new("Speed", 0, 200, "km/h")
		fuel_gauge = VRGauge.new("Fuel", 0, 100, "%")
		engine_temp = VRGauge.new("Temp", 0, 150, "°C")
		rpm_gauge = VRGauge.new("RPM", 0, 8000, "x1000")
	
	func update_dashboard(speed: float, fuel: float, rpm: float, temp: float):
		speedometer.update_value(speed)
		fuel_gauge.update_value(fuel)
		rpm_gauge.update_value(rpm)
		engine_temp.update_value(temp)

class VRGauge:
	var label: String
	var min_value: float
	var max_value: float
	var unit: String
	var current_value: float = 0.0
	var mesh: MeshInstance
	var needle: MeshInstance
	
	func _init(l: String, min_val: float, max_val: float, u: String):
		label = l
		min_value = min_val
		max_value = max_val
		unit = u
		setup_gauge()
	
	func setup_gauge():
		mesh = MeshInstance.new()
		var gauge_mesh = CylinderMesh.new()
		gauge_mesh.height = 0.01
		gauge_mesh.top_radius = 0.05
		gauge_mesh.bottom_radius = 0.05
		mesh.mesh = gauge_mesh
		
		needle = MeshInstance.new()
		var needle_mesh = BoxMesh.new()
		needle_mesh.size = Vector3(0.001, 0.001, 0.04)
		needle.mesh = needle_mesh
		needle.transform.origin = Vector3(0, 0.006, 0)
		mesh.add_child(needle)
	
	func update_value(value: float):
		current_value = clamp(value, min_value, max_value)
		var angle = ((current_value - min_value) / (max_value - min_value)) * 270.0 - 135.0
		needle.rotation_degrees.y = angle

func _ready():
	setup_vr_controllers()
	setup_vehicle_components()
	setup_audio()
	setup_physics()
	
	connect("body_entered", self, "_on_body_entered")

func setup_vr_controllers():
	var arvr_origin = get_tree().get_nodes_in_group("arvr_origin")
	if arvr_origin.size() > 0:
		player_controller = arvr_origin[0]
		left_controller = player_controller.get_node_or_null("LeftController")
		right_controller = player_controller.get_node_or_null("RightController")

func setup_vehicle_components():
	seat_position = Spatial.new()
	seat_position.transform.origin = Vector3(0, seat_height, 0)
	add_child(seat_position)
	
	steering_wheel = VRSteeringWheel.new(steering_wheel_size)
	steering_wheel.mesh.transform.origin = Vector3(0, seat_height + 0.2, -0.4)
	steering_wheel.mesh.rotation_degrees = Vector3(15, 0, 0)
	add_child(steering_wheel.mesh)
	
	pedals = VRPedals.new()
	pedals.gas_pedal.mesh.transform.origin = Vector3(0.1, seat_height - 0.3, -0.2)
	pedals.brake_pedal.mesh.transform.origin = Vector3(0, seat_height - 0.3, -0.2)
	pedals.clutch_pedal.mesh.transform.origin = Vector3(-0.1, seat_height - 0.3, -0.2)
	add_child(pedals.gas_pedal.mesh)
	add_child(pedals.brake_pedal.mesh)
	add_child(pedals.clutch_pedal.mesh)
	
	if enable_manual_transmission:
		gear_shifter = VRGearShifter.new()
		gear_shifter.mesh.transform.origin = Vector3(0.3, seat_height, -0.1)
		add_child(gear_shifter.mesh)
	
	dashboard = VRDashboard.new()
	setup_dashboard_layout()
	
	setup_wheels()

func setup_dashboard_layout():
	dashboard.speedometer.mesh.transform.origin = Vector3(0, seat_height + 0.15, -0.5)
	dashboard.fuel_gauge.mesh.transform.origin = Vector3(-0.1, seat_height + 0.15, -0.5)
	dashboard.rpm_gauge.mesh.transform.origin = Vector3(0.1, seat_height + 0.15, -0.5)
	dashboard.engine_temp.mesh.transform.origin = Vector3(0, seat_height + 0.1, -0.5)
	
	add_child(dashboard.speedometer.mesh)
	add_child(dashboard.fuel_gauge.mesh)
	add_child(dashboard.rpm_gauge.mesh)
	add_child(dashboard.engine_temp.mesh)

func setup_wheels():
	wheel_nodes = [
		$WheelFrontLeft,
		$WheelFrontRight,
		$WheelRearLeft,
		$WheelRearRight
	]
	
	for wheel in wheel_nodes:
		if wheel:
			wheel.use_as_steering = wheel.name.find("Front") != -1
			wheel.use_as_traction = wheel.name.find("Rear") != -1

func setup_audio():
	engine_sound = AudioStreamPlayer3D.new()
	engine_sound.stream = preload("res://sounds/engine.ogg")
	engine_sound.autoplay = false
	add_child(engine_sound)
	
	wind_sound = AudioStreamPlayer3D.new()
	wind_sound.stream = preload("res://sounds/wind.ogg")
	wind_sound.autoplay = false
	add_child(wind_sound)

func setup_physics():
	mass = 1500.0
	if enable_realistic_physics:
		match vehicle_type:
			VehicleType.CAR:
				mass = 1500.0
			VehicleType.MOTORCYCLE:
				mass = 200.0
			VehicleType.TRUCK:
				mass = 8000.0
			VehicleType.BOAT:
				mass = 2000.0

func _physics_process(delta):
	if is_player_inside:
		handle_vr_input()
		update_vehicle_physics(delta)
		update_dashboard_values()
		update_audio()
		consume_fuel(delta)
		check_damage()

func handle_vr_input():
	if not enable_vr_controls:
		return
	
	handle_steering_input()
	handle_pedal_input()
	handle_gear_input()
	handle_button_input()

func handle_steering_input():
	if steering_wheel.is_grabbed and steering_wheel.grab_controller:
		var controller_pos = steering_wheel.grab_controller.global_transform.origin
		var wheel_center = steering_wheel.mesh.global_transform.origin
		var offset = controller_pos - wheel_center
		
		var angle = atan2(offset.x, offset.z)
		steering_wheel.current_rotation = clamp(rad2deg(angle), -steering_wheel.rotation_limit/2, steering_wheel.rotation_limit/2)
	
	steering_input = steering_wheel.get_steering_value() * steering_sensitivity
	
	for wheel in wheel_nodes:
		if wheel and wheel.use_as_steering:
			wheel.steering = deg2rad(steering_input * max_steering_angle)

func handle_pedal_input():
	if right_controller:
		var controller_pos = right_controller.global_transform.origin
		
		var gas_distance = controller_pos.distance_to(pedals.gas_pedal.mesh.global_transform.origin)
		var brake_distance = controller_pos.distance_to(pedals.brake_pedal.mesh.global_transform.origin)
		
		if gas_distance < 0.1:
			throttle_input = right_controller.get_joystick_axis(1)
		else:
			throttle_input = 0.0
		
		if brake_distance < 0.1:
			brake_input = right_controller.get_joystick_axis(1)
		else:
			brake_input = 0.0
	
	apply_throttle(throttle_input)
	apply_brake(brake_input)

func handle_gear_input():
	if enable_manual_transmission and gear_shifter and gear_shifter.is_grabbed:
		var new_gear = gear_shifter.get_nearest_gear(gear_shifter.current_position)
		if new_gear != current_gear:
			change_gear(new_gear)

func handle_button_input():
	if right_controller:
		if right_controller.is_button_pressed(1):
			toggle_engine()
		
		if right_controller.is_button_pressed(2):
			handbrake_active = not handbrake_active

func apply_throttle(input: float):
	if not engine_running or current_gear == GearState.PARK:
		return
	
	var force = input * engine_power
	
	if current_gear == GearState.REVERSE:
		force = -force
	
	for wheel in wheel_nodes:
		if wheel and wheel.use_as_traction:
			wheel.engine_force = force

func apply_brake(input: float):
	var force = input * brake_force
	
	for wheel in wheel_nodes:
		if wheel:
			wheel.brake = force

func change_gear(new_gear: int):
	if new_gear == current_gear:
		return
	
	current_gear = new_gear
	emit_signal("gear_changed", current_gear)
	
	if gear_shifter:
		gear_shifter.mesh.transform.origin = gear_shifter.gear_positions[current_gear]

func toggle_engine():
	engine_running = not engine_running
	
	if engine_running:
		emit_signal("engine_started")
		if engine_sound:
			engine_sound.play()
	else:
		emit_signal("engine_stopped")
		if engine_sound:
			engine_sound.stop()

func update_vehicle_physics(delta):
	current_speed = linear_velocity.length() * 3.6
	emit_signal("speed_changed", current_speed)
	
	if current_speed > max_speed:
		apply_speed_limit()

func apply_speed_limit():
	if linear_velocity.length() > max_speed / 3.6:
		linear_velocity = linear_velocity.normalized() * (max_speed / 3.6)

func update_dashboard_values():
	var rpm = calculate_rpm()
	var temperature = calculate_engine_temperature()
	
	dashboard.update_dashboard(current_speed, fuel_level, rpm, temperature)

func calculate_rpm() -> float:
	if not engine_running:
		return 0.0
	
	var base_rpm = 800.0
	var speed_factor = current_speed / max_speed
	return base_rpm + (speed_factor * 6000.0)

func calculate_engine_temperature() -> float:
	var base_temp = 80.0
	var speed_factor = current_speed / max_speed
	var damage_factor = damage_level / max_damage
	return base_temp + (speed_factor * 40.0) + (damage_factor * 30.0)

func update_audio():
	if engine_sound:
		var rpm = calculate_rpm()
		engine_sound.pitch_scale = 0.5 + (rpm / 8000.0) * 1.5
		engine_sound.unit_db = -20 + (throttle_input * 10)
	
	if wind_sound:
		var wind_volume = (current_speed / max_speed) * 20 - 30
		wind_sound.unit_db = wind_volume
		if current_speed > 5:
			if not wind_sound.playing:
				wind_sound.play()
		else:
			wind_sound.stop()

func consume_fuel(delta):
	if engine_running and throttle_input > 0:
		var consumption = fuel_consumption * throttle_input * delta
		fuel_level = max(0, fuel_level - consumption)
		emit_signal("fuel_changed", fuel_level)
		
		if fuel_level <= 0:
			engine_running = false
			emit_signal("engine_stopped")

func check_damage():
	if not enable_damage_system:
		return
	
	if damage_level >= max_damage:
		engine_running = false
		emit_signal("engine_stopped")

func enter_vehicle():
	if is_player_inside:
		return
	
	is_player_inside = true
	
	if player_controller:
		player_controller.global_transform.origin = seat_position.global_transform.origin
	
	emit_signal("vehicle_entered")

func exit_vehicle():
	if not is_player_inside:
		return
	
	is_player_inside = false
	engine_running = false
	
	if player_controller:
		player_controller.global_transform.origin = global_transform.origin + Vector3(2, 0, 0)
	
	emit_signal("vehicle_exited")

func _on_body_entered(body):
	if body == player_controller:
		enter_vehicle()

func get_vehicle_stats() -> Dictionary:
	return {
		"speed": current_speed,
		"fuel": fuel_level,
		"damage": damage_level,
		"gear": current_gear,
		"engine_running": engine_running,
		"rpm": calculate_rpm()
	}

func repair_vehicle():
	damage_level = 0.0

func refuel(amount: float = -1):
	if amount < 0:
		fuel_level = fuel_capacity
	else:
		fuel_level = min(fuel_capacity, fuel_level + amount)
	
	emit_signal("fuel_changed", fuel_level)