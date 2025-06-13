extends Area

class_name ItemPickup

signal picked_up(item_data)
signal pickup_failed(reason)

export var item_id: String = "generic_item"
export var item_name: String = "Item"
export var item_icon: Texture
export var item_description: String = "A useful item"
export var item_type: String = "consumable"
export var stack_size: int = 1
export var auto_pickup: bool = false
export var pickup_range: float = 2.0
export var respawn_time: float = 0.0
export var requires_interaction: bool = true
export var pickup_sound: AudioStream
export var float_animation: bool = true
export var float_speed: float = 1.0
export var float_height: float = 0.2
export var rotate_speed: float = 1.0
export var particle_effect: PackedScene
export var highlight_on_hover: bool = true
export var highlight_color: Color = Color(1.2, 1.2, 1.0, 1.0)

var item_data: Dictionary = {}
var can_pickup: bool = true
var is_highlighted: bool = false
var initial_position: Vector3
var float_offset: float = 0.0
var original_materials: Array = []
var player_in_range: Spatial = null

onready var mesh_instance = $MeshInstance
onready var collision_shape = $CollisionShape
onready var audio_player = AudioStreamPlayer3D.new()
onready var interaction_prompt = $InteractionPrompt

func _ready():
	setup_item()
	setup_audio()
	setup_signals()
	initial_position = transform.origin
	
	if float_animation:
		set_process(true)
	else:
		set_process(false)
	
	store_original_materials()

func setup_item():
	item_data = {
		"id": item_id,
		"name": item_name,
		"icon": item_icon,
		"description": item_description,
		"type": item_type,
		"stack_size": stack_size,
		"properties": get_item_properties()
	}
	
	if not collision_shape:
		collision_shape = CollisionShape.new()
		add_child(collision_shape)
	
	monitoring = true
	monitorable = true

func setup_audio():
	add_child(audio_player)
	audio_player.bus = "SFX"
	audio_player.unit_db = -5.0
	audio_player.unit_size = 10.0
	audio_player.max_db = 3.0

func setup_signals():
	connect("body_entered", self, "_on_body_entered")
	connect("body_exited", self, "_on_body_exited")
	connect("mouse_entered", self, "_on_mouse_entered")
	connect("mouse_exited", self, "_on_mouse_exited")

func _process(delta):
	if float_animation:
		animate_float(delta)
	
	if rotate_speed > 0:
		rotate_y(rotate_speed * delta)

func animate_float(delta):
	float_offset += float_speed * delta
	var new_position = initial_position
	new_position.y += sin(float_offset) * float_height
	transform.origin = new_position

func _on_body_entered(body):
	if body.has_method("is_player") and body.is_player():
		player_in_range = body
		
		if auto_pickup and can_pickup:
			attempt_pickup(body)
		elif requires_interaction:
			show_interaction_prompt()

func _on_body_exited(body):
	if body == player_in_range:
		player_in_range = null
		hide_interaction_prompt()

func _on_mouse_entered():
	if highlight_on_hover and mesh_instance:
		apply_highlight()

func _on_mouse_exited():
	if highlight_on_hover and mesh_instance:
		remove_highlight()

func show_interaction_prompt():
	if interaction_prompt:
		interaction_prompt.visible = true
		interaction_prompt.text = "Press E to pick up " + item_name
	else:
		create_interaction_prompt()

func hide_interaction_prompt():
	if interaction_prompt:
		interaction_prompt.visible = false

func create_interaction_prompt():
	var prompt = Label3D.new()
	prompt.text = "Press E to pick up " + item_name
	prompt.billboard = Label3D.BILLBOARD_ENABLED
	prompt.no_depth_test = true
	prompt.fixed_size = true
	prompt.pixel_size = 0.01
	prompt.outline_size = 5
	prompt.position.y = 1.5
	add_child(prompt)
	interaction_prompt = prompt

func store_original_materials():
	if not mesh_instance:
		return
	
	original_materials.clear()
	for i in range(mesh_instance.get_surface_material_count()):
		original_materials.append(mesh_instance.get_surface_material(i))

func apply_highlight():
	if not mesh_instance or is_highlighted:
		return
	
	is_highlighted = true
	
	for i in range(mesh_instance.get_surface_material_count()):
		var material = mesh_instance.get_surface_material(i)
		if material:
			var highlighted_mat = material.duplicate()
			highlighted_mat.albedo_color *= highlight_color
			if highlighted_mat.has("emission_enabled"):
				highlighted_mat.emission_enabled = true
				highlighted_mat.emission = highlight_color
				highlighted_mat.emission_energy = 0.5
			mesh_instance.set_surface_material(i, highlighted_mat)

func remove_highlight():
	if not mesh_instance or not is_highlighted:
		return
	
	is_highlighted = false
	
	for i in range(original_materials.size()):
		if i < mesh_instance.get_surface_material_count():
			mesh_instance.set_surface_material(i, original_materials[i])

func interact():
	if player_in_range and can_pickup:
		attempt_pickup(player_in_range)

func attempt_pickup(player):
	if not can_pickup:
		emit_signal("pickup_failed", "Cannot pick up item")
		return
	
	if player.has_method("can_add_item") and not player.can_add_item(item_data):
		emit_signal("pickup_failed", "Inventory full")
		return
	
	if player.has_method("add_item"):
		var success = player.add_item(item_data)
		if success:
			on_pickup_success(player)
		else:
			emit_signal("pickup_failed", "Failed to add item")
	else:
		on_pickup_success(player)

func on_pickup_success(player):
	emit_signal("picked_up", item_data)
	
	if pickup_sound:
		play_pickup_sound()
	
	if particle_effect:
		spawn_pickup_effect()
	
	hide_interaction_prompt()
	can_pickup = false
	
	if respawn_time > 0:
		hide_item()
		yield(get_tree().create_timer(respawn_time), "timeout")
		respawn_item()
	else:
		queue_free()

func play_pickup_sound():
	audio_player.stream = pickup_sound
	audio_player.play()
	
	if respawn_time <= 0:
		audio_player.connect("finished", self, "queue_free")

func spawn_pickup_effect():
	var effect = particle_effect.instance()
	get_tree().get_root().add_child(effect)
	effect.global_transform.origin = global_transform.origin
	effect.emitting = true

func hide_item():
	visible = false
	collision_shape.disabled = true
	set_process(false)

func respawn_item():
	visible = true
	collision_shape.disabled = false
	can_pickup = true
	if float_animation:
		set_process(true)
	
	var respawn_effect = create_respawn_effect()
	if respawn_effect:
		add_child(respawn_effect)
		respawn_effect.emitting = true
		respawn_effect.connect("tree_exited", respawn_effect, "queue_free")

func create_respawn_effect() -> CPUParticles:
	var particles = CPUParticles.new()
	particles.emitting = false
	particles.amount = 20
	particles.lifetime = 0.5
	particles.one_shot = true
	particles.emission_shape = CPUParticles.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.5
	particles.initial_velocity = 2.0
	particles.angular_velocity = 45.0
	particles.scale_amount = 0.5
	particles.color = Color(1.0, 1.0, 0.0, 1.0)
	return particles

func get_item_properties() -> Dictionary:
	var properties = {}
	
	match item_type:
		"consumable":
			properties = {
				"heal_amount": 0,
				"mana_restore": 0,
				"stamina_restore": 0,
				"buff_duration": 0.0,
				"buff_type": ""
			}
		"weapon":
			properties = {
				"damage": 10,
				"attack_speed": 1.0,
				"range": 1.0,
				"damage_type": "physical"
			}
		"armor":
			properties = {
				"defense": 5,
				"magic_resistance": 0,
				"movement_penalty": 0.0,
				"slot": "chest"
			}
		"quest":
			properties = {
				"quest_id": "",
				"objective_id": ""
			}
		"currency":
			properties = {
				"value": 1
			}
		"crafting":
			properties = {
				"material_type": "",
				"quality": "common"
			}
	
	return properties

func set_item_property(key: String, value):
	if item_data.has("properties"):
		item_data.properties[key] = value
	else:
		item_data.properties = {key: value}

func get_item_property(key: String):
	if item_data.has("properties") and item_data.properties.has(key):
		return item_data.properties[key]
	return null

func set_custom_data(data: Dictionary):
	item_data = data
	if data.has("id"):
		item_id = data.id
	if data.has("name"):
		item_name = data.name
	if data.has("type"):
		item_type = data.type

func save_state() -> Dictionary:
	return {
		"item_data": item_data,
		"position": transform.origin,
		"can_pickup": can_pickup,
		"respawn_timer": 0.0
	}

func load_state(state: Dictionary):
	if state.has("item_data"):
		item_data = state.item_data
	if state.has("position"):
		transform.origin = state.position
		initial_position = state.position
	if state.has("can_pickup"):
		can_pickup = state.can_pickup
		if not can_pickup:
			hide_item()