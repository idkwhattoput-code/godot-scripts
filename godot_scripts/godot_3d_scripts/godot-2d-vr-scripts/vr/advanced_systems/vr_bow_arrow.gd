extends Node3D

class_name VRBowAndArrow

@export_group("Bow Settings")
@export var max_draw_distance := 0.6
@export var min_draw_distance := 0.1
@export var draw_force_multiplier := 1.0
@export var arrow_speed_multiplier := 20.0
@export var gravity_scale := 1.0

@export_group("Arrow Settings")
@export var arrow_scene: PackedScene
@export var max_arrows_in_quiver := 30
@export var infinite_arrows := false
@export var arrow_damage_base := 50.0
@export var headshot_multiplier := 2.0

@export_group("Bow Components")
@export var bow_mesh_path: NodePath
@export var string_mesh_path: NodePath
@export var grip_position_path: NodePath
@export var arrow_nock_path: NodePath
@export var sight_path: NodePath

@export_group("Hand Controllers")
@export var left_hand_path: NodePath
@export var right_hand_path: NodePath
@export var dominant_hand := "right"

@export_group("Visual Effects")
@export var draw_effect_scene: PackedScene
@export var release_effect_scene: PackedScene
@export var trajectory_line_material: Material
@export var show_trajectory := true
@export var trajectory_points := 50

@export_group("Audio")
@export var draw_sound: AudioStream
@export var release_sound: AudioStream
@export var empty_quiver_sound: AudioStream
@export var arrow_hit_sound: AudioStream

@export_group("Haptic Feedback")
@export var draw_haptic_intensity := 0.3
@export var release_haptic_intensity := 0.8
@export var haptic_feedback_enabled := true

var left_hand: XRController3D
var right_hand: XRController3D
var bow_mesh: MeshInstance3D
var string_mesh: MeshInstance3D
var grip_position: Node3D
var arrow_nock: Node3D
var sight: Node3D

var is_bow_held := false
var is_drawing := false
var current_draw_distance := 0.0
var nocked_arrow: Node3D
var arrows_in_quiver := 30
var trajectory_line: Line3D
var audio_player: AudioStreamPlayer3D
var draw_effect_instance: Node3D

var grip_hand: XRController3D
var draw_hand: XRController3D
var original_string_position: Vector3
var bow_transform_when_grabbed: Transform3D

signal arrow_nocked()
signal bow_drawn(draw_percentage: float)
signal arrow_released(arrow: Node3D, velocity: Vector3)
signal bow_grabbed()
signal bow_released()
signal quiver_empty()
signal arrow_hit_target(target: Node3D, damage: float)

class Arrow:
	var arrow_node: RigidBody3D
	var damage: float
	var velocity: Vector3
	var has_hit: bool = false
	var flight_time: float = 0.0
	
	func _init(node: RigidBody3D):
		arrow_node = node
		damage = 50.0

func _ready():
	setup_hand_controllers()
	setup_bow_components()
	setup_audio()
	setup_trajectory_line()
	
	arrows_in_quiver = max_arrows_in_quiver
	
	set_physics_process(true)

func setup_hand_controllers():
	if left_hand_path:
		left_hand = get_node(left_hand_path)
	if right_hand_path:
		right_hand = get_node(right_hand_path)
	
	if left_hand:
		left_hand.button_pressed.connect(_on_hand_button_pressed.bind(left_hand))
		left_hand.button_released.connect(_on_hand_button_released.bind(left_hand))
	
	if right_hand:
		right_hand.button_pressed.connect(_on_hand_button_pressed.bind(right_hand))
		right_hand.button_released.connect(_on_hand_button_released.bind(right_hand))

func setup_bow_components():
	if bow_mesh_path:
		bow_mesh = get_node(bow_mesh_path)
	if string_mesh_path:
		string_mesh = get_node(string_mesh_path)
	if grip_position_path:
		grip_position = get_node(grip_position_path)
	if arrow_nock_path:
		arrow_nock = get_node(arrow_nock_path)
	if sight_path:
		sight = get_node(sight_path)
	
	if string_mesh:
		original_string_position = string_mesh.position
	
	create_default_components_if_missing()

func create_default_components_if_missing():
	if not bow_mesh:
		bow_mesh = MeshInstance3D.new()
		var bow_shape = BoxMesh.new()
		bow_shape.size = Vector3(0.05, 1.2, 0.1)
		bow_mesh.mesh = bow_shape
		add_child(bow_mesh)
	
	if not string_mesh:
		string_mesh = MeshInstance3D.new()
		var string_shape = CylinderMesh.new()
		string_shape.height = 1.0
		string_shape.top_radius = 0.01
		string_shape.bottom_radius = 0.01
		string_mesh.mesh = string_shape
		add_child(string_mesh)
		original_string_position = string_mesh.position
	
	if not grip_position:
		grip_position = Node3D.new()
		add_child(grip_position)
	
	if not arrow_nock:
		arrow_nock = Node3D.new()
		arrow_nock.position = Vector3(0, 0, -0.3)
		add_child(arrow_nock)

func setup_audio():
	audio_player = AudioStreamPlayer3D.new()
	add_child(audio_player)
	audio_player.bus = "SFX"

func setup_trajectory_line():
	if show_trajectory:
		trajectory_line = Line3D.new()
		add_child(trajectory_line)
		trajectory_line.visible = false
		
		if trajectory_line_material:
			trajectory_line.material_override = trajectory_line_material

func _on_hand_button_pressed(hand: XRController3D, button_name: String):
	if button_name == "grip_click":
		try_grab_bow(hand)
	elif button_name == "trigger_click" and is_bow_held:
		try_nock_arrow(hand)

func _on_hand_button_released(hand: XRController3D, button_name: String):
	if button_name == "grip_click" and hand == grip_hand:
		release_bow()
	elif button_name == "trigger_click" and is_drawing:
		release_arrow()

func try_grab_bow(hand: XRController3D):
	if is_bow_held:
		return
	
	var distance_to_grip = hand.global_position.distance_to(grip_position.global_position)
	if distance_to_grip <= 0.15:
		grab_bow(hand)

func grab_bow(hand: XRController3D):
	is_bow_held = true
	grip_hand = hand
	bow_transform_when_grabbed = global_transform
	
	emit_signal("bow_grabbed")
	
	if haptic_feedback_enabled:
		hand.trigger_haptic_pulse("haptic", 0, 0.1, 0.3, 0)

func release_bow():
	is_bow_held = false
	grip_hand = null
	
	if is_drawing:
		cancel_draw()
	
	emit_signal("bow_released")

func try_nock_arrow(hand: XRController3D):
	if not is_bow_held or hand == grip_hand:
		return
	
	if arrows_in_quiver <= 0 and not infinite_arrows:
		play_sound(empty_quiver_sound)
		emit_signal("quiver_empty")
		return
	
	var distance_to_nock = hand.global_position.distance_to(arrow_nock.global_position)
	if distance_to_nock <= 0.1:
		nock_arrow(hand)

func nock_arrow(hand: XRController3D):
	if nocked_arrow:
		return
	
	draw_hand = hand
	
	if arrow_scene:
		nocked_arrow = arrow_scene.instantiate()
	else:
		nocked_arrow = create_default_arrow()
	
	add_child(nocked_arrow)
	nocked_arrow.global_position = arrow_nock.global_position
	nocked_arrow.global_rotation = arrow_nock.global_rotation
	
	if not infinite_arrows:
		arrows_in_quiver -= 1
	
	emit_signal("arrow_nocked")

func create_default_arrow() -> RigidBody3D:
	var arrow = RigidBody3D.new()
	
	var mesh_instance = MeshInstance3D.new()
	var arrow_mesh = CylinderMesh.new()
	arrow_mesh.height = 0.8
	arrow_mesh.top_radius = 0.01
	arrow_mesh.bottom_radius = 0.01
	mesh_instance.mesh = arrow_mesh
	arrow.add_child(mesh_instance)
	
	var collision = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.height = 0.8
	shape.radius = 0.01
	collision.shape = shape
	arrow.add_child(collision)
	
	arrow.mass = 0.1
	arrow.gravity_scale = gravity_scale
	
	return arrow

func _physics_process(delta):
	if is_bow_held:
		update_bow_position()
		
		if nocked_arrow and draw_hand:
			update_draw_state()
			update_trajectory_preview()

func update_bow_position():
	if grip_hand:
		global_position = grip_hand.global_position
		global_rotation = grip_hand.global_rotation

func update_draw_state():
	var nock_to_hand_distance = arrow_nock.global_position.distance_to(draw_hand.global_position)
	current_draw_distance = clamp(nock_to_hand_distance, 0, max_draw_distance)
	
	var was_drawing = is_drawing
	is_drawing = current_draw_distance >= min_draw_distance
	
	if is_drawing and not was_drawing:
		start_drawing()
	elif not is_drawing and was_drawing:
		stop_drawing()
	
	if is_drawing:
		update_string_position()
		update_arrow_position()
		
		var draw_percentage = current_draw_distance / max_draw_distance
		emit_signal("bow_drawn", draw_percentage)
		
		if haptic_feedback_enabled:
			var haptic_strength = draw_percentage * draw_haptic_intensity
			draw_hand.trigger_haptic_pulse("haptic", 0, 0.1, haptic_strength, 0)

func start_drawing():
	play_sound(draw_sound)
	
	if draw_effect_scene:
		draw_effect_instance = draw_effect_scene.instantiate()
		add_child(draw_effect_instance)

func stop_drawing():
	if draw_effect_instance:
		draw_effect_instance.queue_free()
		draw_effect_instance = null

func update_string_position():
	if string_mesh and draw_hand:
		var draw_offset = draw_hand.global_position - arrow_nock.global_position
		var local_offset = to_local(draw_hand.global_position) - to_local(arrow_nock.global_position)
		string_mesh.position = original_string_position + local_offset * 0.5

func update_arrow_position():
	if nocked_arrow and draw_hand:
		nocked_arrow.global_position = draw_hand.global_position
		nocked_arrow.look_at(arrow_nock.global_position + (arrow_nock.global_position - draw_hand.global_position).normalized())

func update_trajectory_preview():
	if not show_trajectory or not trajectory_line or not is_drawing:
		return
	
	trajectory_line.visible = true
	trajectory_line.clear_points()
	
	var launch_velocity = calculate_arrow_velocity()
	var current_pos = arrow_nock.global_position
	var velocity = launch_velocity
	var time_step = 0.1
	
	for i in range(trajectory_points):
		trajectory_line.add_point(to_local(current_pos))
		
		current_pos += velocity * time_step
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) * gravity_scale * time_step
		
		if current_pos.y < global_position.y - 10:
			break

func calculate_arrow_velocity() -> Vector3:
	if not nocked_arrow or not is_drawing:
		return Vector3.ZERO
	
	var direction = (arrow_nock.global_position - draw_hand.global_position).normalized()
	var draw_power = current_draw_distance / max_draw_distance
	var speed = draw_power * arrow_speed_multiplier * draw_force_multiplier
	
	return direction * speed

func release_arrow():
	if not nocked_arrow or not is_drawing:
		return
	
	var arrow_velocity = calculate_arrow_velocity()
	
	var arrow_body = nocked_arrow as RigidBody3D
	if arrow_body:
		arrow_body.freeze = false
		arrow_body.linear_velocity = arrow_velocity
		arrow_body.angular_velocity = Vector3.ZERO
		
		setup_arrow_collision_detection(arrow_body)
	
	emit_signal("arrow_released", nocked_arrow, arrow_velocity)
	
	play_sound(release_sound)
	
	if release_effect_scene:
		var effect = release_effect_scene.instantiate()
		add_child(effect)
		effect.global_position = arrow_nock.global_position
	
	if haptic_feedback_enabled and draw_hand:
		draw_hand.trigger_haptic_pulse("haptic", 0, 0.2, release_haptic_intensity, 0)
	
	cleanup_after_release()

func setup_arrow_collision_detection(arrow_body: RigidBody3D):
	arrow_body.body_entered.connect(_on_arrow_hit.bind(arrow_body))
	
	var timer = Timer.new()
	timer.wait_time = 10.0
	timer.one_shot = true
	timer.timeout.connect(func(): 
		if is_instance_valid(arrow_body):
			arrow_body.queue_free()
	)
	arrow_body.add_child(timer)
	timer.start()

func _on_arrow_hit(arrow_body: RigidBody3D, hit_body: Node3D):
	arrow_body.freeze = true
	arrow_body.linear_velocity = Vector3.ZERO
	arrow_body.angular_velocity = Vector3.ZERO
	
	var damage = calculate_arrow_damage(arrow_body, hit_body)
	
	if hit_body.has_method("take_damage"):
		hit_body.take_damage(damage, self)
	
	emit_signal("arrow_hit_target", hit_body, damage)
	play_sound(arrow_hit_sound)

func calculate_arrow_damage(arrow_body: RigidBody3D, target: Node3D) -> float:
	var base_damage = arrow_damage_base
	var velocity_bonus = arrow_body.linear_velocity.length() / arrow_speed_multiplier
	var total_damage = base_damage * (1.0 + velocity_bonus)
	
	if target.has_meta("is_headshot_target") and target.get_meta("is_headshot_target"):
		total_damage *= headshot_multiplier
	
	return total_damage

func cancel_draw():
	if nocked_arrow:
		nocked_arrow.queue_free()
		nocked_arrow = null
	
	is_drawing = false
	draw_hand = null
	
	if string_mesh:
		string_mesh.position = original_string_position
	
	if trajectory_line:
		trajectory_line.visible = false
	
	stop_drawing()

func cleanup_after_release():
	nocked_arrow = null
	is_drawing = false
	draw_hand = null
	
	if string_mesh:
		string_mesh.position = original_string_position
	
	if trajectory_line:
		trajectory_line.visible = false
	
	stop_drawing()

func play_sound(sound: AudioStream):
	if sound and audio_player:
		audio_player.stream = sound
		audio_player.play()

func add_arrows_to_quiver(amount: int):
	arrows_in_quiver = min(arrows_in_quiver + amount, max_arrows_in_quiver)

func get_draw_percentage() -> float:
	return current_draw_distance / max_draw_distance if is_drawing else 0.0

func get_arrows_remaining() -> int:
	return arrows_in_quiver if not infinite_arrows else -1

func set_bow_stats(draw_force: float, arrow_speed: float, damage: float):
	draw_force_multiplier = draw_force
	arrow_speed_multiplier = arrow_speed
	arrow_damage_base = damage