extends StaticBody

export var switch_type = "lever"
export var auto_reset = false
export var reset_time = 2.0
export var requires_interaction = true
export var rotation_axis = Vector3(1, 0, 0)
export var rotation_angle = 45.0
export var animation_speed = 3.0

signal activated()
signal deactivated()
signal state_changed(is_on)

var is_on = false
var is_animating = false
var reset_timer = 0.0
var can_interact = true

onready var interaction_area = $InteractionArea
onready var mesh_instance = $MeshInstance
onready var activation_sound = $ActivationSound
onready var interaction_prompt = $InteractionPrompt

var original_rotation = Vector3()
var target_rotation = Vector3()

func _ready():
	if interaction_area:
		interaction_area.connect("body_entered", self, "_on_body_entered")
		interaction_area.connect("body_exited", self, "_on_body_exited")
	
	if mesh_instance:
		original_rotation = mesh_instance.rotation_degrees
		target_rotation = original_rotation
	
	if interaction_prompt:
		interaction_prompt.visible = false

func _input(event):
	if requires_interaction and event.is_action_pressed("interact"):
		if _player_in_range() and can_interact and not is_animating:
			toggle()

func _physics_process(delta):
	if auto_reset and is_on:
		reset_timer += delta
		if reset_timer >= reset_time:
			toggle()
			reset_timer = 0.0
	
	if mesh_instance and not mesh_instance.rotation_degrees.is_equal_approx(target_rotation):
		mesh_instance.rotation_degrees = mesh_instance.rotation_degrees.linear_interpolate(
			target_rotation,
			animation_speed * delta
		)
		
		if mesh_instance.rotation_degrees.is_equal_approx(target_rotation):
			is_animating = false

func toggle():
	is_on = !is_on
	is_animating = true
	reset_timer = 0.0
	
	if is_on:
		target_rotation = original_rotation + rotation_axis * rotation_angle
		emit_signal("activated")
	else:
		target_rotation = original_rotation
		emit_signal("deactivated")
	
	emit_signal("state_changed", is_on)
	
	if activation_sound:
		activation_sound.play()
	
	_update_visual_state()

func _update_visual_state():
	if mesh_instance and mesh_instance.material_override:
		var mat = mesh_instance.material_override
		if mat.has_property("emission_enabled"):
			mat.emission_enabled = is_on
			mat.emission_energy = 2.0 if is_on else 0.0

func _player_in_range():
	if not interaction_area:
		return false
		
	for body in interaction_area.get_overlapping_bodies():
		if body.is_in_group("player"):
			return true
	return false

func _on_body_entered(body):
	if body.is_in_group("player") and interaction_prompt:
		interaction_prompt.visible = true

func _on_body_exited(body):
	if body.is_in_group("player") and interaction_prompt:
		interaction_prompt.visible = false

func set_state(new_state):
	if is_on != new_state:
		toggle()

func disable():
	can_interact = false
	if interaction_prompt:
		interaction_prompt.visible = false

func enable():
	can_interact = true

func get_state():
	return is_on

func reset():
	is_on = false
	reset_timer = 0.0
	is_animating = false
	
	if mesh_instance:
		mesh_instance.rotation_degrees = original_rotation
		target_rotation = original_rotation
	
	_update_visual_state()