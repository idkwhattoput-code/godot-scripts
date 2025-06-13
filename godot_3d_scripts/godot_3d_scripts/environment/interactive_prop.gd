extends RigidBody

export var interaction_prompt = "Press E to interact"
export var interaction_distance = 3.0
export var is_pickupable = true
export var is_throwable = true
export var throw_force = 15.0
export var hold_distance = 2.0
export var hold_height = 0.5
export var requires_two_hands = false
export var interaction_sound : AudioStream
export var pickup_sound : AudioStream
export var drop_sound : AudioStream

signal interacted()
signal picked_up(player)
signal dropped(player)
signal thrown(player, force)

var is_held = false
var holding_player = null
var original_collision_layer
var original_collision_mask
var interaction_enabled = true

onready var interaction_area = $InteractionArea
onready var mesh_instance = $MeshInstance
onready var outline_mesh = $OutlineMesh
onready var audio_player = $AudioStreamPlayer3D
onready var prompt_label = $PromptLabel3D

func _ready():
	original_collision_layer = collision_layer
	original_collision_mask = collision_mask
	
	if not audio_player:
		audio_player = AudioStreamPlayer3D.new()
		add_child(audio_player)
	
	if not interaction_area:
		interaction_area = Area.new()
		var col_shape = CollisionShape.new()
		var sphere = SphereShape.new()
		sphere.radius = interaction_distance
		col_shape.shape = sphere
		interaction_area.add_child(col_shape)
		add_child(interaction_area)
	
	interaction_area.connect("body_entered", self, "_on_body_entered")
	interaction_area.connect("body_exited", self, "_on_body_exited")
	
	if outline_mesh:
		outline_mesh.visible = false
	
	if prompt_label:
		prompt_label.visible = false
		prompt_label.text = interaction_prompt

func _physics_process(delta):
	if is_held and holding_player:
		_update_held_position()

func _input(event):
	if event.is_action_pressed("interact"):
		if _player_in_range() and interaction_enabled:
			interact()
	elif event.is_action_pressed("drop") and is_held:
		drop()
	elif event.is_action_pressed("throw") and is_held and is_throwable:
		throw()

func interact():
	emit_signal("interacted")
	
	if is_pickupable and not is_held:
		var player = _get_nearby_player()
		if player:
			pickup(player)
	else:
		_play_sound(interaction_sound)

func pickup(player):
	if is_held or not is_pickupable:
		return
	
	if requires_two_hands and player.has_method("has_free_hands"):
		if not player.has_free_hands(2):
			return
	
	is_held = true
	holding_player = player
	
	mode = RigidBody.MODE_KINEMATIC
	collision_layer = 0
	collision_mask = 0
	
	_play_sound(pickup_sound)
	emit_signal("picked_up", player)
	
	if prompt_label:
		prompt_label.visible = false

func drop():
	if not is_held:
		return
	
	is_held = false
	
	mode = RigidBody.MODE_RIGID
	collision_layer = original_collision_layer
	collision_mask = original_collision_mask
	
	_play_sound(drop_sound)
	emit_signal("dropped", holding_player)
	
	holding_player = null

func throw():
	if not is_held or not is_throwable:
		return
	
	var player = holding_player
	drop()
	
	if player:
		var throw_direction = -player.global_transform.basis.z
		apply_central_impulse(throw_direction * throw_force)
		apply_torque_impulse(Vector3(
			rand_range(-5, 5),
			rand_range(-5, 5),
			rand_range(-5, 5)
		))
		
		emit_signal("thrown", player, throw_force)

func _update_held_position():
	if not holding_player:
		return
	
	var target_pos = holding_player.global_transform.origin
	target_pos += -holding_player.global_transform.basis.z * hold_distance
	target_pos.y += hold_height
	
	if holding_player.has_node("Camera"):
		var camera = holding_player.get_node("Camera")
		target_pos = camera.global_transform.origin
		target_pos += -camera.global_transform.basis.z * hold_distance
	
	global_transform.origin = global_transform.origin.linear_interpolate(target_pos, 0.2)
	
	global_transform.basis = holding_player.global_transform.basis

func _player_in_range():
	if not interaction_area:
		return false
	
	for body in interaction_area.get_overlapping_bodies():
		if body.is_in_group("player"):
			return true
	return false

func _get_nearby_player():
	if not interaction_area:
		return null
	
	for body in interaction_area.get_overlapping_bodies():
		if body.is_in_group("player"):
			return body
	return null

func _on_body_entered(body):
	if body.is_in_group("player") and not is_held:
		if outline_mesh:
			outline_mesh.visible = true
		if prompt_label:
			prompt_label.visible = true

func _on_body_exited(body):
	if body.is_in_group("player"):
		if outline_mesh:
			outline_mesh.visible = false
		if prompt_label:
			prompt_label.visible = false

func _play_sound(sound):
	if sound and audio_player:
		audio_player.stream = sound
		audio_player.play()

func set_interaction_enabled(enabled):
	interaction_enabled = enabled
	
	if not enabled:
		if outline_mesh:
			outline_mesh.visible = false
		if prompt_label:
			prompt_label.visible = false

func force_drop():
	if is_held:
		drop()

func get_weight():
	return mass

func is_being_held():
	return is_held

func get_holder():
	return holding_player

func set_outline_color(color):
	if outline_mesh and outline_mesh.material_override:
		outline_mesh.material_override.albedo_color = color

func apply_highlight(highlighted):
	if mesh_instance and mesh_instance.material_override:
		var mat = mesh_instance.material_override
		if highlighted:
			mat.emission_energy = 0.3
		else:
			mat.emission_energy = 0.0