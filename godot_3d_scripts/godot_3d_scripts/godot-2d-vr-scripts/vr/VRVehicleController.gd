extends Node3D

signal engine_started
signal engine_stopped
signal gear_changed(new_gear: int)
signal collision_detected(impact_force: float)

@export_group("Vehicle Configuration")
@export var vehicle_type: VehicleType = VehicleType.CAR
@export var max_speed: float = 30.0
@export var acceleration: float = 10.0
@export var brake_force: float = 20.0
@export var turn_speed: float = 2.0
@export var enable_physics: bool = true

@export_group("VR Controls")
@export var steering_wheel: Node3D
@export var throttle_lever: Node3D
@export var brake_lever: Node3D
@export var gear_shifter: Node3D
@export var ignition_key: Node3D
@export var hand_brake: Node3D

@export_group("Haptic Feedback")
@export var engine_vibration_intensity: float = 0.1
@export var collision_haptic_intensity: float = 1.0
@export var gear_shift_haptic: float = 0.3
@export var steering_resistance: float = 0.5

@export_group("Dashboard")
@export var speedometer: Node3D
@export var tachometer: Node3D
@export var fuel_gauge: Node3D
@export var dashboard_display: Viewport
@export var warning_lights: Dictionary = {}

@export_group("Audio")
@export var engine_idle_sound: AudioStream
@export var engine_running_sound: AudioStream
@export var brake_sound: AudioStream
@export var horn_sound: AudioStream
@export var turn_signal_sound: AudioStream

enum VehicleType {
	CAR,
	TRUCK,
	MOTORCYCLE,
	BOAT,
	AIRCRAFT
}

var current_speed: float = 0.0
var current_gear: int = 0  # 0 = Neutral, -1 = Reverse, 1-6 = Forward gears
var engine_rpm: float = 0.0
var is_engine_running: bool = false
var fuel_level: float = 100.0
var steering_angle: float = 0.0
var throttle_position: float = 0.0
var brake_position: float = 0.0
var hand_brake_engaged: bool = false

var vehicle_body: RigidBody3D
var wheels: Array[Node3D] = []
var audio_players: Dictionary = {}
var haptic_timers: Dictionary = {}
var grabbed_controls: Dictionary = {}

var left_controller: XRController3D
var right_controller: XRController3D

func _ready():
	_setup_vehicle_body()
	_setup_controllers()
	_setup_audio()
	_setup_controls()
	_initialize_dashboard()

func _setup_vehicle_body():
	if enable_physics:
		vehicle_body = RigidBody3D.new()
		vehicle_body.mass = 1000.0 if vehicle_type == VehicleType.CAR else 500.0
		add_child(vehicle_body)
		
		# Add collision shape
		var collision_shape = CollisionShape3D.new()
		var box_shape = BoxShape3D.new()
		box_shape.size = Vector3(2, 1, 4)
		collision_shape.shape = box_shape
		vehicle_body.add_child(collision_shape)

func _setup_controllers():
	var xr_origin = XROrigin3D.new()
	add_child(xr_origin)
	
	left_controller = XRController3D.new()
	left_controller.tracker = "left_hand"
	xr_origin.add_child(left_controller)
	
	right_controller = XRController3D.new()
	right_controller.tracker = "right_hand"
	xr_origin.add_child(right_controller)
	
	# Connect controller signals
	left_controller.button_pressed.connect(_on_controller_button_pressed.bind(left_controller))
	right_controller.button_pressed.connect(_on_controller_button_pressed.bind(right_controller))

func _setup_audio():
	# Engine audio
	var engine_audio = AudioStreamPlayer3D.new()
	engine_audio.stream = engine_idle_sound
	engine_audio.autoplay = false
	add_child(engine_audio)
	audio_players["engine"] = engine_audio
	
	# Brake audio
	var brake_audio = AudioStreamPlayer3D.new()
	brake_audio.stream = brake_sound
	add_child(brake_audio)
	audio_players["brake"] = brake_audio
	
	# Horn audio
	var horn_audio = AudioStreamPlayer3D.new()
	horn_audio.stream = horn_sound
	add_child(horn_audio)
	audio_players["horn"] = horn_audio

func _setup_controls():
	# Setup steering wheel
	if steering_wheel:
		_make_control_grabbable(steering_wheel, "steering_wheel")
		
	# Setup throttle
	if throttle_lever:
		_make_control_grabbable(throttle_lever, "throttle")
		
	# Setup brake
	if brake_lever:
		_make_control_grabbable(brake_lever, "brake")
		
	# Setup gear shifter
	if gear_shifter:
		_make_control_grabbable(gear_shifter, "gear_shifter")
		
	# Setup ignition
	if ignition_key:
		_make_control_grabbable(ignition_key, "ignition")

func _make_control_grabbable(control: Node3D, control_name: String):
	var area = Area3D.new()
	area.collision_layer = 2  # Grabbable layer
	area.set_meta("control_name", control_name)
	
	var collision = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.1
	collision.shape = shape
	
	area.add_child(collision)
	control.add_child(area)

func _physics_process(delta):
	_update_vehicle_physics(delta)
	_update_controls(delta)
	_update_dashboard(delta)
	_update_audio(delta)
	_update_haptics(delta)

func _update_vehicle_physics(delta):
	if not enable_physics or not vehicle_body:
		return
	
	if is_engine_running:
		# Calculate engine RPM
		engine_rpm = 800 + (throttle_position * 6000)
		
		# Apply acceleration
		var acceleration_force = throttle_position * acceleration * current_gear
		
		if current_gear != 0 and not hand_brake_engaged:
			var forward = -transform.basis.z
			vehicle_body.apply_central_force(forward * acceleration_force * 1000)
		
		# Apply braking
		if brake_position > 0 or hand_brake_engaged:
			var brake_multiplier = hand_brake_engaged ? 1.0 : brake_position
			var velocity = vehicle_body.linear_velocity
			var brake_direction = -velocity.normalized()
			vehicle_body.apply_central_force(brake_direction * brake_force * brake_multiplier * 1000)
		
		# Apply steering
		if abs(steering_angle) > 0.01 and current_speed > 0.1:
			var turn_force = steering_angle * turn_speed * (current_speed / max_speed)
			vehicle_body.apply_torque(Vector3(0, turn_force, 0))
		
		# Update current speed
		current_speed = vehicle_body.linear_velocity.length()
		
		# Speed limiting
		if current_speed > max_speed:
			vehicle_body.linear_velocity = vehicle_body.linear_velocity.normalized() * max_speed

func _update_controls(delta):
	# Update steering wheel
	if steering_wheel and grabbed_controls.has("steering_wheel"):
		var controller = grabbed_controls["steering_wheel"]
		var wheel_rotation = steering_wheel.rotation.y
		steering_angle = clamp(wheel_rotation / (PI / 2), -1.0, 1.0)
		
		# Apply resistance haptic
		if controller:
			var resistance = abs(steering_angle) * steering_resistance
			_trigger_haptic(controller, resistance, 0.1)
	
	# Update throttle
	if throttle_lever and grabbed_controls.has("throttle"):
		var lever_angle = throttle_lever.rotation.x
		throttle_position = clamp(lever_angle / (PI / 4), 0.0, 1.0)
	
	# Update brake
	if brake_lever and grabbed_controls.has("brake"):
		var lever_angle = brake_lever.rotation.x
		brake_position = clamp(lever_angle / (PI / 4), 0.0, 1.0)
		
		if brake_position > 0.1 and current_speed > 1.0:
			audio_players["brake"].play()

func _update_dashboard(delta):
	# Update speedometer
	if speedometer:
		var speed_percentage = current_speed / max_speed
		var needle_rotation = lerp(-135, 135, speed_percentage)
		speedometer.rotation_degrees.z = needle_rotation
	
	# Update tachometer
	if tachometer:
		var rpm_percentage = engine_rpm / 8000.0
		var needle_rotation = lerp(-135, 135, rpm_percentage)
		tachometer.rotation_degrees.z = needle_rotation
	
	# Update fuel gauge
	if fuel_gauge:
		fuel_level = max(0, fuel_level - delta * 0.1)  # Consume fuel
		var fuel_percentage = fuel_level / 100.0
		var needle_rotation = lerp(-45, 45, fuel_percentage)
		fuel_gauge.rotation_degrees.z = needle_rotation
	
	# Update dashboard display
	if dashboard_display:
		# Update digital readouts
		pass

func _update_audio(delta):
	if is_engine_running and audio_players.has("engine"):
		var engine_audio = audio_players["engine"]
		
		# Switch between idle and running sounds based on RPM
		if engine_rpm < 1500 and engine_audio.stream != engine_idle_sound:
			engine_audio.stream = engine_idle_sound
			engine_audio.play()
		elif engine_rpm >= 1500 and engine_audio.stream != engine_running_sound:
			engine_audio.stream = engine_running_sound
			engine_audio.play()
		
		# Adjust pitch based on RPM
		engine_audio.pitch_scale = 0.8 + (engine_rpm / 8000.0)

func _update_haptics(delta):
	# Engine vibration
	if is_engine_running:
		for controller in [left_controller, right_controller]:
			if controller:
				var vibration = engine_vibration_intensity * (engine_rpm / 8000.0)
				_trigger_haptic(controller, vibration, delta)

func _on_controller_button_pressed(button_name: String, controller: XRController3D):
	match button_name:
		"trigger_click":
			_handle_grab(controller)
		"grip_click":
			_handle_horn()
		"menu_button":
			_toggle_dashboard_view()

func _handle_grab(controller: XRController3D):
	# Check what control is being grabbed
	var grab_area = _get_grab_area_near_controller(controller)
	if grab_area:
		var control_name = grab_area.get_meta("control_name")
		grabbed_controls[control_name] = controller
		
		# Special handling for ignition
		if control_name == "ignition":
			_toggle_engine()
		elif control_name == "gear_shifter":
			_handle_gear_shift(controller)

func _get_grab_area_near_controller(controller: XRController3D) -> Area3D:
	# Find grabbable areas near the controller
	var grab_distance = 0.2
	var controller_pos = controller.global_position
	
	for control_name in ["steering_wheel", "throttle", "brake", "gear_shifter", "ignition"]:
		var control = get(control_name)
		if control and control.has_node("Area3D"):
			var area = control.get_node("Area3D")
			if controller_pos.distance_to(area.global_position) < grab_distance:
				return area
	
	return null

func _toggle_engine():
	if is_engine_running:
		stop_engine()
	else:
		start_engine()

func start_engine():
	if fuel_level <= 0:
		# Show warning
		return
	
	is_engine_running = true
	engine_started.emit()
	
	if audio_players.has("engine"):
		audio_players["engine"].play()

func stop_engine():
	is_engine_running = false
	engine_rpm = 0
	engine_stopped.emit()
	
	if audio_players.has("engine"):
		audio_players["engine"].stop()

func _handle_gear_shift(controller: XRController3D):
	# Detect gear shift pattern
	var shift_position = gear_shifter.position - gear_shifter.get_parent().position
	
	# Simple H-pattern detection
	if shift_position.x < -0.1 and shift_position.z < -0.1:
		current_gear = 1
	elif shift_position.x > 0.1 and shift_position.z < -0.1:
		current_gear = 2
	elif shift_position.x < -0.1 and shift_position.z > 0.1:
		current_gear = 3
	elif shift_position.x > 0.1 and shift_position.z > 0.1:
		current_gear = 4
	elif abs(shift_position.x) < 0.1 and shift_position.z < -0.1:
		current_gear = 5
	elif abs(shift_position.x) < 0.1 and shift_position.z > 0.1:
		current_gear = -1  # Reverse
	else:
		current_gear = 0  # Neutral
	
	gear_changed.emit(current_gear)
	_trigger_haptic(controller, gear_shift_haptic, 0.2)

func _handle_horn():
	if audio_players.has("horn"):
		audio_players["horn"].play()

func _toggle_dashboard_view():
	# Toggle between normal and zoomed dashboard view
	pass

func _trigger_haptic(controller: XRController3D, intensity: float, duration: float):
	if controller and controller.is_inside_tree():
		controller.trigger_haptic_pulse("haptic", 1000.0, intensity, duration)

func _initialize_dashboard():
	# Set up warning lights
	for light_name in warning_lights:
		var light = warning_lights[light_name]
		if light:
			light.visible = false

func set_vehicle_position(pos: Vector3):
	if vehicle_body:
		vehicle_body.position = pos
	else:
		position = pos

func reset_vehicle():
	current_speed = 0.0
	current_gear = 0
	engine_rpm = 0
	throttle_position = 0.0
	brake_position = 0.0
	steering_angle = 0.0
	
	if vehicle_body:
		vehicle_body.linear_velocity = Vector3.ZERO
		vehicle_body.angular_velocity = Vector3.ZERO