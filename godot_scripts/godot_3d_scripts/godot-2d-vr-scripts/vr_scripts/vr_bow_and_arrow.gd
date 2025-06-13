extends Spatial

export var arrow_scene : PackedScene
export var max_draw_distance = 0.8
export var min_draw_distance = 0.1
export var max_draw_force = 50.0
export var haptic_intensity = 0.3
export var draw_sound : AudioStream
export var release_sound : AudioStream
export var string_material : Material

signal arrow_nocked(arrow)
signal arrow_drawn(draw_amount)
signal arrow_released(arrow, force)

var bow_hand_controller : ARVRController
var arrow_hand_controller : ARVRController
var current_arrow = null
var is_drawing = false
var draw_start_pos = Vector3.ZERO
var draw_amount = 0.0
var can_nock_arrow = true

onready var bow_mesh = $BowMesh
onready var string_path = $StringPath
onready var arrow_rest = $ArrowRest
onready var grip_area = $GripArea
onready var nock_area = $NockArea
onready var audio_player = $AudioStreamPlayer3D
onready var haptic_timer = $HapticTimer

func _ready():
	if not arrow_scene:
		push_error("No arrow scene assigned to bow!")
		return
	
	_setup_areas()
	_create_bow_string()

func _setup_areas():
	if grip_area:
		grip_area.connect("body_entered", self, "_on_grip_entered")
		grip_area.connect("body_exited", self, "_on_grip_exited")
	
	if nock_area:
		nock_area.connect("body_entered", self, "_on_nock_entered")

func _create_bow_string():
	if not string_path:
		string_path = Path.new()
		add_child(string_path)
	
	var curve = Curve3D.new()
	curve.add_point(Vector3(0, 0.5, 0))
	curve.add_point(Vector3(0, 0, -0.1))
	curve.add_point(Vector3(0, -0.5, 0))
	string_path.curve = curve

func _process(_delta):
	if is_drawing and current_arrow:
		_update_draw()
		_update_arrow_position()
		_apply_haptic_feedback()

func _on_grip_entered(body):
	if body.has_method("get_controller_id"):
		bow_hand_controller = body

func _on_grip_exited(body):
	if body == bow_hand_controller:
		if is_drawing:
			release_arrow()
		bow_hand_controller = null

func _on_nock_entered(body):
	if body.has_method("get_controller_id") and can_nock_arrow and not current_arrow:
		arrow_hand_controller = body
		nock_arrow()

func nock_arrow():
	if current_arrow or not arrow_scene:
		return
	
	current_arrow = arrow_scene.instance()
	arrow_rest.add_child(current_arrow)
	current_arrow.transform = Transform.IDENTITY
	
	can_nock_arrow = false
	emit_signal("arrow_nocked", current_arrow)

func start_draw():
	if not current_arrow or not arrow_hand_controller:
		return
	
	is_drawing = true
	draw_start_pos = arrow_hand_controller.global_transform.origin
	
	if draw_sound and audio_player:
		audio_player.stream = draw_sound
		audio_player.play()

func _update_draw():
	if not arrow_hand_controller:
		return
	
	var current_pos = arrow_hand_controller.global_transform.origin
	var bow_pos = global_transform.origin
	
	var draw_vector = bow_pos - current_pos
	var draw_distance = draw_vector.length()
	
	draw_amount = clamp(
		(draw_distance - min_draw_distance) / (max_draw_distance - min_draw_distance),
		0.0, 1.0
	)
	
	emit_signal("arrow_drawn", draw_amount)
	
	_update_bow_string()

func _update_bow_string():
	if not string_path or not string_path.curve:
		return
	
	var curve = string_path.curve
	curve.set_point_position(1, Vector3(0, 0, -0.1 - draw_amount * 0.4))

func _update_arrow_position():
	if not current_arrow:
		return
	
	current_arrow.transform.origin = Vector3(0, 0, -draw_amount * max_draw_distance)
	
	var bow_forward = -global_transform.basis.z
	var arrow_target = global_transform.origin + bow_forward * 2.0
	current_arrow.look_at(arrow_target, Vector3.UP)

func release_arrow():
	if not is_drawing or not current_arrow:
		return
	
	is_drawing = false
	
	if draw_amount < 0.1:
		drop_arrow()
		return
	
	var force = draw_amount * max_draw_force
	var direction = -global_transform.basis.z
	
	var released_arrow = current_arrow
	arrow_rest.remove_child(released_arrow)
	get_tree().current_scene.add_child(released_arrow)
	released_arrow.global_transform = current_arrow.global_transform
	
	if released_arrow.has_method("launch"):
		released_arrow.launch(direction, force)
	elif released_arrow is RigidBody:
		released_arrow.apply_central_impulse(direction * force)
	
	if release_sound and audio_player:
		audio_player.stream = release_sound
		audio_player.play()
	
	emit_signal("arrow_released", released_arrow, force)
	
	current_arrow = null
	draw_amount = 0.0
	_update_bow_string()
	
	yield(get_tree().create_timer(0.5), "timeout")
	can_nock_arrow = true

func drop_arrow():
	if not current_arrow:
		return
	
	arrow_rest.remove_child(current_arrow)
	get_tree().current_scene.add_child(current_arrow)
	current_arrow.global_transform = arrow_rest.global_transform
	
	if current_arrow is RigidBody:
		current_arrow.apply_central_impulse(Vector3(0, -1, 0))
	
	current_arrow = null
	draw_amount = 0.0
	_update_bow_string()
	can_nock_arrow = true

func _apply_haptic_feedback():
	if not arrow_hand_controller or not arrow_hand_controller.has_method("rumble"):
		return
	
	if draw_amount > 0.1:
		var intensity = haptic_intensity * draw_amount
		arrow_hand_controller.rumble = intensity

func _on_controller_button_pressed(button):
	if not arrow_hand_controller:
		return
	
	match button:
		JOY_VR_TRIGGER:
			if current_arrow and not is_drawing:
				start_draw()
		JOY_VR_GRIP:
			if current_arrow and not is_drawing:
				drop_arrow()

func _on_controller_button_released(button):
	if button == JOY_VR_TRIGGER and is_drawing:
		release_arrow()

func get_draw_percentage():
	return draw_amount

func has_arrow_nocked():
	return current_arrow != null

func force_release():
	if is_drawing:
		release_arrow()

func set_arrow_scene(scene):
	arrow_scene = scene

func calibrate_draw_distance(new_max_distance):
	max_draw_distance = clamp(new_max_distance, 0.3, 1.5)