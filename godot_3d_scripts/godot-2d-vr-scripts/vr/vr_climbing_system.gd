extends Node

export var climb_speed_multiplier: float = 1.0
export var stamina_enabled: bool = true
export var max_stamina: float = 100.0
export var stamina_drain_rate: float = 10.0
export var stamina_regen_rate: float = 5.0
export var grip_threshold: float = 0.7
export var haptic_feedback: bool = true
export var allow_jumping_from_climb: bool = true
export var jump_force: float = 5.0

var player: ARVROrigin
var left_controller: ARVRController
var right_controller: ARVRController
var character_body: KinematicBody

var is_climbing: bool = false
var left_hand_climbing: bool = false
var right_hand_climbing: bool = false
var left_climb_point: Vector3
var right_climb_point: Vector3
var previous_controller_positions: Dictionary = {}
var current_stamina: float = max_stamina
var climb_velocity: Vector3 = Vector3.ZERO

var climbable_bodies: Dictionary = {}

signal started_climbing
signal stopped_climbing
signal stamina_depleted
signal climb_jump

func _ready():
	player = get_parent()
	left_controller = player.get_node("LeftController")
	right_controller = player.get_node("RightController")
	character_body = player.get_node("CharacterBody")
	
	_setup_climb_areas()
	
	if left_controller:
		left_controller.connect("button_pressed", self, "_on_left_button_pressed")
		left_controller.connect("button_released", self, "_on_left_button_released")
	
	if right_controller:
		right_controller.connect("button_pressed", self, "_on_right_button_pressed")
		right_controller.connect("button_released", self, "_on_right_button_released")

func _setup_climb_areas():
	for controller in [left_controller, right_controller]:
		if controller:
			var area = Area.new()
			area.name = "ClimbDetector"
			controller.add_child(area)
			
			var shape = CollisionShape.new()
			var sphere = SphereShape.new()
			sphere.radius = 0.1
			shape.shape = sphere
			area.add_child(shape)
			
			area.connect("body_entered", self, "_on_climb_area_entered", [controller])
			area.connect("body_exited", self, "_on_climb_area_exited", [controller])

func _physics_process(delta):
	_update_climbing(delta)
	_update_stamina(delta)
	
	if is_climbing:
		_apply_climbing_movement(delta)

func _on_climb_area_entered(body: PhysicsBody, controller: ARVRController):
	if body.is_in_group("climbable"):
		climbable_bodies[controller] = body
		if haptic_feedback and controller.has_method("trigger_haptic_pulse"):
			controller.trigger_haptic_pulse(0.05, 0.3)

func _on_climb_area_exited(body: PhysicsBody, controller: ARVRController):
	if climbable_bodies.has(controller) and climbable_bodies[controller] == body:
		climbable_bodies.erase(controller)

func _on_left_button_pressed(button_name: String):
	if button_name == "grip":
		_try_grab_climb(left_controller, true)

func _on_left_button_released(button_name: String):
	if button_name == "grip":
		_release_climb(left_controller, true)

func _on_right_button_pressed(button_name: String):
	if button_name == "grip":
		_try_grab_climb(right_controller, false)
	elif button_name == "a_button" and is_climbing and allow_jumping_from_climb:
		_perform_climb_jump()

func _on_right_button_released(button_name: String):
	if button_name == "grip":
		_release_climb(right_controller, false)

func _try_grab_climb(controller: ARVRController, is_left: bool):
	if not climbable_bodies.has(controller):
		return
	
	if stamina_enabled and current_stamina <= 0:
		return
	
	var grip_value = controller.get_joystick_axis(JOY_VR_ANALOG_GRIP)
	if grip_value < grip_threshold:
		return
	
	if is_left:
		left_hand_climbing = true
		left_climb_point = controller.global_transform.origin
	else:
		right_hand_climbing = true
		right_climb_point = controller.global_transform.origin
	
	previous_controller_positions[controller] = controller.global_transform.origin
	
	if not is_climbing and (left_hand_climbing or right_hand_climbing):
		_start_climbing()

func _release_climb(controller: ARVRController, is_left: bool):
	if is_left:
		left_hand_climbing = false
	else:
		right_hand_climbing = false
	
	if previous_controller_positions.has(controller):
		previous_controller_positions.erase(controller)
	
	if not left_hand_climbing and not right_hand_climbing:
		_stop_climbing()

func _start_climbing():
	is_climbing = true
	if character_body:
		character_body.set("gravity_scale", 0.0)
	emit_signal("started_climbing")

func _stop_climbing():
	is_climbing = false
	if character_body:
		character_body.set("gravity_scale", 1.0)
	climb_velocity = Vector3.ZERO
	emit_signal("stopped_climbing")

func _update_climbing(delta):
	if not is_climbing:
		return
	
	var total_movement = Vector3.ZERO
	var active_hands = 0
	
	if left_hand_climbing and left_controller:
		var current_pos = left_controller.global_transform.origin
		if previous_controller_positions.has(left_controller):
			var movement = previous_controller_positions[left_controller] - current_pos
			total_movement += movement
			active_hands += 1
		previous_controller_positions[left_controller] = current_pos
	
	if right_hand_climbing and right_controller:
		var current_pos = right_controller.global_transform.origin
		if previous_controller_positions.has(right_controller):
			var movement = previous_controller_positions[right_controller] - current_pos
			total_movement += movement
			active_hands += 1
		previous_controller_positions[right_controller] = current_pos
	
	if active_hands > 0:
		climb_velocity = total_movement / active_hands * climb_speed_multiplier

func _apply_climbing_movement(delta):
	if not character_body or climb_velocity.length() < 0.001:
		return
	
	character_body.move_and_slide(climb_velocity / delta, Vector3.UP)
	
	if haptic_feedback and climb_velocity.length() > 0.1:
		var intensity = clamp(climb_velocity.length() * 0.1, 0.0, 0.3)
		if left_hand_climbing and left_controller:
			left_controller.rumble = intensity
		if right_hand_climbing and right_controller:
			right_controller.rumble = intensity

func _update_stamina(delta):
	if not stamina_enabled:
		return
	
	if is_climbing:
		current_stamina -= stamina_drain_rate * delta
		if current_stamina <= 0:
			current_stamina = 0
			_force_release_climb()
			emit_signal("stamina_depleted")
	else:
		current_stamina = min(current_stamina + stamina_regen_rate * delta, max_stamina)

func _force_release_climb():
	left_hand_climbing = false
	right_hand_climbing = false
	previous_controller_positions.clear()
	_stop_climbing()

func _perform_climb_jump():
	if not is_climbing or not character_body:
		return
	
	var jump_direction = Vector3.UP
	
	if left_hand_climbing and right_hand_climbing:
		var hand_direction = (right_controller.global_transform.origin - left_controller.global_transform.origin).normalized()
		var forward = -player.global_transform.basis.z
		jump_direction = (Vector3.UP + forward * 0.5).normalized()
	
	character_body.set("velocity", jump_direction * jump_force)
	_force_release_climb()
	emit_signal("climb_jump")

func get_stamina_percentage() -> float:
	if not stamina_enabled:
		return 1.0
	return current_stamina / max_stamina

func set_stamina(value: float):
	current_stamina = clamp(value, 0.0, max_stamina)

func is_near_climbable() -> bool:
	return climbable_bodies.size() > 0

func get_climb_velocity() -> Vector3:
	return climb_velocity