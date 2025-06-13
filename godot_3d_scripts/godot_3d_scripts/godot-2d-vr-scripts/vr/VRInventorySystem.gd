extends Node3D

class_name VRInventorySystem

@export var inventory_slots: int = 12
@export var slot_size: float = 0.1
@export var inventory_distance: float = 0.3
@export var auto_organize: bool = true

var controller: XRController3D
var inventory_panel: Node3D
var inventory_items: Array[VRInventoryItem] = []
var slot_positions: Array[Vector3] = []
var is_inventory_open: bool = false
var selected_item: VRInventoryItem = null
var hover_preview: MeshInstance3D

@onready var inventory_container: Node3D = $InventoryContainer
@onready var slot_indicators: Array[MeshInstance3D] = []

signal inventory_opened()
signal inventory_closed() 
signal item_selected(item: VRInventoryItem)
signal item_used(item: VRInventoryItem)

class VRInventoryItem:
	var id: String
	var name: String
	var description: String
	var mesh: Mesh
	var icon: Texture2D
	var quantity: int = 1
	var max_stack: int = 1
	var item_type: String = "misc"
	var usable: bool = false
	var data: Dictionary = {}
	var mesh_instance: MeshInstance3D = null
	var slot_index: int = -1
	
	func _init(item_id: String = "", item_name: String = ""):
		id = item_id
		name = item_name

func _ready():
	controller = get_parent() as XRController3D
	if not controller:
		print("VRInventorySystem must be child of XRController3D")
		return
	
	setup_inventory_layout()
	setup_slot_indicators()
	setup_hover_preview()
	hide_inventory()
	
	controller.button_pressed.connect(_on_controller_button_pressed)
	inventory_items.resize(inventory_slots)

func _process(delta):
	if is_inventory_open:
		update_inventory_interaction()
		update_hover_preview()

func setup_inventory_layout():
	if not inventory_container:
		inventory_container = Node3D.new()
		add_child(inventory_container)
	
	inventory_container.position = Vector3(0, 0, -inventory_distance)
	
	var rows = 3
	var cols = inventory_slots / rows
	var start_x = -(cols - 1) * slot_size / 2.0
	var start_y = (rows - 1) * slot_size / 2.0
	
	slot_positions.clear()
	for row in range(rows):
		for col in range(cols):
			var x = start_x + col * slot_size
			var y = start_y - row * slot_size
			slot_positions.append(Vector3(x, y, 0))

func setup_slot_indicators():
	slot_indicators.clear()
	
	for i in range(inventory_slots):
		var indicator = MeshInstance3D.new()
		inventory_container.add_child(indicator)
		
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(slot_size * 0.9, slot_size * 0.9, 0.01)
		indicator.mesh = box_mesh
		
		var material = StandardMaterial3D.new()
		material.albedo_color = Color.DARK_GRAY
		material.emission_enabled = true
		material.emission = Color.DARK_GRAY * 0.3
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0.7
		indicator.material_override = material
		
		indicator.position = slot_positions[i]
		slot_indicators.append(indicator)

func setup_hover_preview():
	hover_preview = MeshInstance3D.new()
	inventory_container.add_child(hover_preview)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.YELLOW
	material.emission_enabled = true
	material.emission = Color.YELLOW * 0.5
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.8
	hover_preview.material_override = material
	
	hover_preview.visible = false

func toggle_inventory():
	if is_inventory_open:
		close_inventory()
	else:
		open_inventory()

func open_inventory():
	if is_inventory_open:
		return
	
	is_inventory_open = true
	show_inventory()
	refresh_inventory_display()
	inventory_opened.emit()

func close_inventory():
	if not is_inventory_open:
		return
	
	is_inventory_open = false
	hide_inventory()
	selected_item = null
	inventory_closed.emit()

func show_inventory():
	inventory_container.visible = true
	
	var tween = create_tween()
	inventory_container.scale = Vector3.ZERO
	tween.tween_property(inventory_container, "scale", Vector3.ONE, 0.3)

func hide_inventory():
	var tween = create_tween()
	tween.tween_property(inventory_container, "scale", Vector3.ZERO, 0.2)
	await tween.finished
	inventory_container.visible = false

func add_item(item: VRInventoryItem) -> bool:
	if not item:
		return false
	
	var slot_index = find_empty_slot()
	if slot_index == -1:
		return false
	
	inventory_items[slot_index] = item
	item.slot_index = slot_index
	
	if is_inventory_open:
		display_item_in_slot(item, slot_index)
	
	return true

func remove_item(slot_index: int) -> VRInventoryItem:
	if slot_index < 0 or slot_index >= inventory_slots:
		return null
	
	var item = inventory_items[slot_index]
	if not item:
		return null
	
	inventory_items[slot_index] = null
	
	if item.mesh_instance:
		item.mesh_instance.queue_free()
		item.mesh_instance = null
	
	return item

func find_empty_slot() -> int:
	for i in range(inventory_slots):
		if not inventory_items[i]:
			return i
	return -1

func display_item_in_slot(item: VRInventoryItem, slot_index: int):
	if not item or slot_index < 0 or slot_index >= slot_positions.size():
		return
	
	if item.mesh_instance:
		item.mesh_instance.queue_free()
	
	item.mesh_instance = MeshInstance3D.new()
	inventory_container.add_child(item.mesh_instance)
	
	item.mesh_instance.mesh = item.mesh
	item.mesh_instance.position = slot_positions[slot_index]
	item.mesh_instance.scale = Vector3.ONE * 0.05
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	item.mesh_instance.material_override = material

func refresh_inventory_display():
	for i in range(inventory_slots):
		var item = inventory_items[i]
		if item:
			display_item_in_slot(item, i)

func update_inventory_interaction():
	var ray_origin = global_transform.origin
	var ray_direction = -global_transform.basis.z
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_direction * inventory_distance * 2
	)
	
	var result = space_state.intersect_ray(query)
	if result:
		var hit_item = get_item_at_position(result.position)
		if hit_item != selected_item:
			selected_item = hit_item
			if selected_item:
				item_selected.emit(selected_item)

func get_item_at_position(world_pos: Vector3) -> VRInventoryItem:
	var local_pos = inventory_container.to_local(world_pos)
	
	for i in range(inventory_slots):
		var slot_pos = slot_positions[i]
		var distance = local_pos.distance_to(slot_pos)
		
		if distance < slot_size / 2 and inventory_items[i]:
			return inventory_items[i]
	
	return null

func update_hover_preview():
	if selected_item and selected_item.mesh_instance:
		hover_preview.visible = true
		hover_preview.mesh = selected_item.mesh
		hover_preview.position = selected_item.mesh_instance.position + Vector3(0, 0, -0.02)
	else:
		hover_preview.visible = false

func use_selected_item():
	if not selected_item or not selected_item.usable:
		return
	
	item_used.emit(selected_item)
	
	match selected_item.item_type:
		"health_potion":
			consume_health_potion(selected_item)
		"tool":
			equip_tool(selected_item)
		"key":
			use_key(selected_item)
	
	if selected_item.quantity <= 1:
		remove_item(selected_item.slot_index)
		selected_item = null
	else:
		selected_item.quantity -= 1

func consume_health_potion(item: VRInventoryItem):
	var heal_amount = item.data.get("heal_amount", 20)
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("heal"):
		player.heal(heal_amount)

func equip_tool(item: VRInventoryItem):
	var hand = controller.get_parent() as XRController3D
	if hand and hand.has_method("equip_tool"):
		hand.equip_tool(item)

func use_key(item: VRInventoryItem):
	var doors = get_tree().get_nodes_in_group("doors")
	for door in doors:
		if door.has_method("try_unlock") and door.try_unlock(item.id):
			break

func create_vr_item(id: String, name: String, mesh: Mesh) -> VRInventoryItem:
	var item = VRInventoryItem.new(id, name)
	item.mesh = mesh
	return item

func has_item(item_id: String) -> bool:
	for item in inventory_items:
		if item and item.id == item_id:
			return true
	return false

func get_item_count(item_id: String) -> int:
	var count = 0
	for item in inventory_items:
		if item and item.id == item_id:
			count += item.quantity
	return count

func _on_controller_button_pressed(name: String):
	match name:
		"menu_button":
			toggle_inventory()
		"trigger":
			if is_inventory_open and selected_item:
				use_selected_item()
		"grip":
			if is_inventory_open and selected_item:
				drop_selected_item()

func drop_selected_item():
	if not selected_item:
		return
	
	var dropped_item = remove_item(selected_item.slot_index)
	if dropped_item:
		spawn_item_in_world(dropped_item)

func spawn_item_in_world(item: VRInventoryItem):
	var item_body = RigidBody3D.new()
	get_tree().current_scene.add_child(item_body)
	
	var mesh_instance = MeshInstance3D.new()
	item_body.add_child(mesh_instance)
	mesh_instance.mesh = item.mesh
	
	var collision_shape = CollisionShape3D.new()
	item_body.add_child(collision_shape)
	
	item_body.global_position = controller.global_position + controller.global_transform.basis.z * -0.5
	item_body.linear_velocity = controller.global_transform.basis.z * -2.0