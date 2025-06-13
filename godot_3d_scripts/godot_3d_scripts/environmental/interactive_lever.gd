extends Node3D

class_name InteractiveLever

@export_group("Lever Settings")
@export var lever_angle_min := -45.0
@export var lever_angle_max := 45.0
@export var lever_speed := 2.0
@export var auto_return := false
@export var auto_return_delay := 2.0
@export var requires_hold := false
@export var activation_threshold := 0.8

@export_group("Interaction")
@export var interaction_distance := 3.0
@export var interaction_prompt := "Press E to use lever"
@export var hold_prompt := "Hold E to use lever"
@export var outline_color := Color(1, 1, 0)
@export var outline_width := 2.0

@export_group("Linked Objects")
@export var linked_objects: Array[NodePath] = []
@export var activation_mode := ActivationMode.TOGGLE

@export_group("Visual Settings")
@export var lever_mesh_path: NodePath = "LeverMesh"
@export var base_mesh_path: NodePath = "BaseMesh"
@export var highlight_material: Material

@export_group("Audio")
@export var activation_sound: AudioStream
@export var deactivation_sound: AudioStream
@export var movement_sound: AudioStream

enum ActivationMode {
	TOGGLE,
	MOMENTARY,
	ONE_WAY,
	SEQUENCE
}

var current_angle := 0.0
var target_angle := 0.0
var is_activated := false
var is_interacting := false
var can_interact := true
var return_timer: Timer
var lever_mesh: Node3D
var base_mesh: Node3D
var outline_shader: ShaderMaterial
var audio_player: AudioStreamPlayer3D
var movement_audio: AudioStreamPlayer3D
var linked_nodes := []
var player_in_range := false
var current_player: Node3D
var original_materials := {}
var sequence_index := 0

signal lever_activated()
signal lever_deactivated()
signal lever_pulled(angle: float)
signal interaction_started()
signal interaction_ended()

func _ready():
	setup_components()
	cache_linked_nodes()
	setup_interaction_area()
	setup_timers()
	
	if lever_mesh:
		lever_mesh.rotation_degrees.x = current_angle

func setup_components():
	if lever_mesh_path != "":
		lever_mesh = get_node_or_null(lever_mesh_path)
	
	if base_mesh_path != "":
		base_mesh = get_node_or_null(base_mesh_path)
	
	if not lever_mesh:
		create_default_lever()
	
	audio_player = AudioStreamPlayer3D.new()
	add_child(audio_player)
	audio_player.bus = "SFX"
	
	movement_audio = AudioStreamPlayer3D.new()
	add_child(movement_audio)
	movement_audio.bus = "SFX"
	if movement_sound:
		movement_audio.stream = movement_sound
		movement_audio.volume_db = -10

func create_default_lever():
	lever_mesh = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.height = 1.0
	cylinder.top_radius = 0.05
	cylinder.bottom_radius = 0.05
	lever_mesh.mesh = cylinder
	lever_mesh.position.y = 0.5
	add_child(lever_mesh)
	
	if not base_mesh:
		base_mesh = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.3, 0.1, 0.3)
		base_mesh.mesh = box
		add_child(base_mesh)

func setup_interaction_area():
	var area = Area3D.new()
	area.monitoring = true
	add_child(area)
	
	var collision = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = interaction_distance
	collision.shape = shape
	area.add_child(collision)
	
	area.body_entered.connect(_on_player_entered)
	area.body_exited.connect(_on_player_exited)

func setup_timers():
	if auto_return:
		return_timer = Timer.new()
		return_timer.wait_time = auto_return_delay
		return_timer.one_shot = true
		return_timer.timeout.connect(_on_return_timeout)
		add_child(return_timer)

func cache_linked_nodes():
	linked_nodes.clear()
	for path in linked_objects:
		var node = get_node_or_null(path)
		if node:
			linked_nodes.append(node)

func _on_player_entered(body: Node3D):
	if body.has_method("is_player") and body.is_player():
		player_in_range = true
		current_player = body
		show_interaction_prompt()

func _on_player_exited(body: Node3D):
	if body == current_player:
		player_in_range = false
		current_player = null
		hide_interaction_prompt()
		if is_interacting and requires_hold:
			stop_interaction()

func show_interaction_prompt():
	if current_player and current_player.has_method("show_interaction_prompt"):
		var prompt = hold_prompt if requires_hold else interaction_prompt
		current_player.show_interaction_prompt(prompt)
	
	apply_outline(true)

func hide_interaction_prompt():
	if current_player and current_player.has_method("hide_interaction_prompt"):
		current_player.hide_interaction_prompt()
	
	apply_outline(false)

func apply_outline(show: bool):
	if not highlight_material:
		return
	
	if lever_mesh is MeshInstance3D:
		if show:
			store_original_material(lever_mesh)
			lever_mesh.material_overlay = highlight_material
		else:
			restore_original_material(lever_mesh)

func store_original_material(mesh_instance: MeshInstance3D):
	if not mesh_instance in original_materials:
		original_materials[mesh_instance] = mesh_instance.material_overlay

func restore_original_material(mesh_instance: MeshInstance3D):
	if mesh_instance in original_materials:
		mesh_instance.material_overlay = original_materials[mesh_instance]

func _input(event: InputEvent):
	if not player_in_range or not can_interact:
		return
	
	if event.is_action_pressed("interact"):
		start_interaction()
	elif event.is_action_released("interact") and requires_hold:
		stop_interaction()

func start_interaction():
	if not can_interact:
		return
	
	is_interacting = true
	emit_signal("interaction_started")
	
	if not requires_hold:
		toggle_lever()
	else:
		activate_lever()

func stop_interaction():
	if not is_interacting:
		return
	
	is_interacting = false
	emit_signal("interaction_ended")
	
	if requires_hold and is_activated:
		deactivate_lever()

func toggle_lever():
	if is_activated:
		deactivate_lever()
	else:
		activate_lever()

func activate_lever():
	if activation_mode == ActivationMode.ONE_WAY and is_activated:
		return
	
	is_activated = true
	target_angle = lever_angle_max
	emit_signal("lever_activated")
	
	play_sound(activation_sound)
	trigger_linked_objects(true)
	
	if auto_return and return_timer:
		return_timer.start()

func deactivate_lever():
	if activation_mode == ActivationMode.ONE_WAY:
		return
	
	is_activated = false
	target_angle = lever_angle_min
	emit_signal("lever_deactivated")
	
	play_sound(deactivation_sound)
	trigger_linked_objects(false)
	
	if return_timer:
		return_timer.stop()

func trigger_linked_objects(activate: bool):
	match activation_mode:
		ActivationMode.TOGGLE:
			for node in linked_nodes:
				if node.has_method("toggle"):
					node.toggle()
				elif node.has_method("set_active"):
					node.set_active(activate)
		
		ActivationMode.MOMENTARY:
			for node in linked_nodes:
				if node.has_method("set_active"):
					node.set_active(activate)
		
		ActivationMode.ONE_WAY:
			if activate:
				for node in linked_nodes:
					if node.has_method("activate"):
						node.activate()
		
		ActivationMode.SEQUENCE:
			if activate and sequence_index < linked_nodes.size():
				var node = linked_nodes[sequence_index]
				if node.has_method("activate"):
					node.activate()
				sequence_index = (sequence_index + 1) % linked_nodes.size()

func _physics_process(delta):
	if not lever_mesh:
		return
	
	if current_angle != target_angle:
		var prev_angle = current_angle
		current_angle = move_toward(current_angle, target_angle, lever_speed * rad_to_deg(delta))
		lever_mesh.rotation_degrees.x = current_angle
		
		var progress = abs(current_angle - lever_angle_min) / abs(lever_angle_max - lever_angle_min)
		emit_signal("lever_pulled", progress)
		
		if abs(current_angle - target_angle) > 0.1:
			if movement_audio and not movement_audio.playing:
				movement_audio.play()
		else:
			if movement_audio and movement_audio.playing:
				movement_audio.stop()
		
		check_activation_threshold(progress)

func check_activation_threshold(progress: float):
	if activation_mode == ActivationMode.MOMENTARY:
		var should_activate = progress >= activation_threshold
		if should_activate != is_activated:
			if should_activate:
				activate_lever()
			else:
				deactivate_lever()

func _on_return_timeout():
	if is_activated and not is_interacting:
		deactivate_lever()

func play_sound(sound: AudioStream):
	if sound and audio_player:
		audio_player.stream = sound
		audio_player.pitch_scale = randf_range(0.9, 1.1)
		audio_player.play()

func set_lever_position(angle: float):
	current_angle = clamp(angle, lever_angle_min, lever_angle_max)
	target_angle = current_angle
	if lever_mesh:
		lever_mesh.rotation_degrees.x = current_angle

func force_activate():
	activate_lever()

func force_deactivate():
	deactivate_lever()

func set_interactable(interactable: bool):
	can_interact = interactable
	if not interactable and is_interacting:
		stop_interaction()

func reset():
	is_activated = false
	is_interacting = false
	current_angle = lever_angle_min
	target_angle = lever_angle_min
	sequence_index = 0
	if lever_mesh:
		lever_mesh.rotation_degrees.x = current_angle
	if return_timer:
		return_timer.stop()