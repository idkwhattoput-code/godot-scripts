extends Node3D

signal recipe_discovered(recipe_name: String)
signal item_crafted(item_name: String, item: Node3D)
signal crafting_failed(reason: String)
signal ingredient_added(ingredient: String, slot: int)
signal workbench_activated

@export_group("Crafting Configuration")
@export var workbench_model: Node3D
@export var crafting_grid_size: Vector2i = Vector2i(3, 3)
@export var requires_workbench: bool = true
@export var auto_craft_enabled: bool = true
@export var recipe_book_scene: PackedScene

@export_group("Grid Setup")
@export var slot_size: float = 0.1
@export var slot_spacing: float = 0.12
@export var grid_height: float = 1.0
@export var snap_threshold: float = 0.05
@export var ingredient_preview: bool = true

@export_group("Visual Effects")
@export var crafting_particles: CPUParticles3D
@export var success_effect_scene: PackedScene
@export var grid_material: Material
@export var highlight_material: Material
@export var slot_occupied_material: Material

@export_group("Audio")
@export var place_item_sound: AudioStream
@export var crafting_sound: AudioStream
@export var success_sound: AudioStream
@export var recipe_unlock_sound: AudioStream

var crafting_grid: Array[Array] = []
var slot_positions: Array[Vector3] = []
var slot_visuals: Array[Node3D] = []
var held_ingredients: Dictionary = {}
var known_recipes: Array[Dictionary] = []
var active_recipe: Dictionary = {}

var left_controller: XRController3D
var right_controller: XRController3D
var grabbed_items: Dictionary = {}
var workbench_active: bool = false

var audio_player: AudioStreamPlayer3D

# Example recipes
var recipe_database: Array[Dictionary] = [
	{
		"name": "wooden_sword",
		"pattern": [
			["", "wood", ""],
			["", "wood", ""],
			["", "stick", ""]
		],
		"result": {"name": "wooden_sword", "count": 1}
	},
	{
		"name": "stone_axe",
		"pattern": [
			["stone", "stone", ""],
			["stone", "stick", ""],
			["", "stick", ""]
		],
		"result": {"name": "stone_axe", "count": 1}
	},
	{
		"name": "healing_potion",
		"pattern": [
			["", "herb", ""],
			["", "water", ""],
			["", "bottle", ""]
		],
		"result": {"name": "healing_potion", "count": 1}
	},
	{
		"name": "torch",
		"pattern": [
			["", "coal", ""],
			["", "stick", ""],
			["", "", ""]
		],
		"result": {"name": "torch", "count": 4}
	}
]

func _ready():
	_setup_controllers()
	_setup_crafting_grid()
	_setup_audio()
	_initialize_recipes()

func _setup_controllers():
	var xr_origin = get_node_or_null("/root/XROrigin3D")
	if not xr_origin:
		xr_origin = XROrigin3D.new()
		get_tree().root.add_child(xr_origin)
	
	left_controller = xr_origin.get_node_or_null("LeftController")
	if not left_controller:
		left_controller = XRController3D.new()
		left_controller.tracker = "left_hand"
		xr_origin.add_child(left_controller)
	
	right_controller = xr_origin.get_node_or_null("RightController")
	if not right_controller:
		right_controller = XRController3D.new()
		right_controller.tracker = "right_hand"
		xr_origin.add_child(right_controller)
	
	# Connect controller signals
	left_controller.button_pressed.connect(_on_controller_button.bind(left_controller, true))
	left_controller.button_released.connect(_on_controller_button.bind(left_controller, false))
	right_controller.button_pressed.connect(_on_controller_button.bind(right_controller, true))
	right_controller.button_released.connect(_on_controller_button.bind(right_controller, false))

func _setup_crafting_grid():
	# Initialize grid array
	crafting_grid = []
	for x in range(crafting_grid_size.x):
		crafting_grid.append([])
		for y in range(crafting_grid_size.y):
			crafting_grid[x].append(null)
	
	# Create slot positions and visuals
	_create_slot_visuals()

func _create_slot_visuals():
	slot_positions.clear()
	slot_visuals.clear()
	
	var start_x = -(crafting_grid_size.x - 1) * slot_spacing / 2
	var start_z = -(crafting_grid_size.y - 1) * slot_spacing / 2
	
	for x in range(crafting_grid_size.x):
		for y in range(crafting_grid_size.y):
			var pos = Vector3(
				start_x + x * slot_spacing,
				grid_height,
				start_z + y * slot_spacing
			)
			slot_positions.append(pos)
			
			# Create visual slot
			var slot_visual = _create_slot_visual(pos)
			add_child(slot_visual)
			slot_visuals.append(slot_visual)

func _create_slot_visual(pos: Vector3) -> Node3D:
	var slot = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(slot_size, 0.01, slot_size)
	slot.mesh = box_mesh
	slot.position = pos
	
	if grid_material:
		slot.material_override = grid_material
	
	# Add collision for interaction
	var area = Area3D.new()
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(slot_size, 0.05, slot_size)
	collision.shape = shape
	area.add_child(collision)
	slot.add_child(area)
	
	return slot

func _setup_audio():
	audio_player = AudioStreamPlayer3D.new()
	add_child(audio_player)

func _initialize_recipes():
	# Load starting recipes
	for recipe in recipe_database:
		known_recipes.append(recipe)

func _physics_process(delta):
	_update_item_tracking(delta)
	_check_recipe_matching()
	_update_slot_highlights()

func _update_item_tracking(delta):
	# Track items held by controllers
	for controller in [left_controller, right_controller]:
		_check_controller_interaction(controller)

func _check_controller_interaction(controller: XRController3D):
	# Check if controller is near any crafting slot
	var controller_pos = controller.global_position
	
	for i in range(slot_positions.size()):
		var slot_pos = global_position + slot_positions[i]
		var distance = controller_pos.distance_to(slot_pos)
		
		if distance < snap_threshold:
			_highlight_slot(i)
			
			# Check if controller has an item and trigger is pressed
			if grabbed_items.has(controller) and controller.is_button_pressed("trigger_click"):
				_place_item_in_slot(grabbed_items[controller], i)

func _highlight_slot(slot_index: int):
	if slot_index >= 0 and slot_index < slot_visuals.size():
		var slot = slot_visuals[slot_index]
		if highlight_material:
			slot.material_override = highlight_material

func _place_item_in_slot(item: Dictionary, slot_index: int):
	var x = slot_index % crafting_grid_size.x
	var y = slot_index / crafting_grid_size.x
	
	if crafting_grid[x][y] != null:
		# Slot occupied, try to swap or combine
		_handle_slot_occupied(item, x, y)
		return
	
	# Place item in slot
	crafting_grid[x][y] = item
	ingredient_added.emit(item.get("name", "unknown"), slot_index)
	
	# Visual feedback
	_update_slot_visual(x, y, item)
	
	# Audio feedback
	if place_item_sound:
		audio_player.stream = place_item_sound
		audio_player.play()
	
	# Remove from controller
	var controller = _get_controller_holding_item(item)
	if controller:
		grabbed_items.erase(controller)

func _handle_slot_occupied(new_item: Dictionary, x: int, y: int):
	var existing_item = crafting_grid[x][y]
	
	# Check if items can stack
	if existing_item.get("name") == new_item.get("name"):
		var max_stack = existing_item.get("max_stack", 64)
		var current_count = existing_item.get("count", 1)
		var new_count = new_item.get("count", 1)
		
		if current_count + new_count <= max_stack:
			existing_item["count"] = current_count + new_count
			_update_slot_visual(x, y, existing_item)
			
			# Remove new item from controller
			var controller = _get_controller_holding_item(new_item)
			if controller:
				grabbed_items.erase(controller)

func _update_slot_visual(x: int, y: int, item: Dictionary):
	var slot_index = y * crafting_grid_size.x + x
	if slot_index < slot_visuals.size():
		var slot = slot_visuals[slot_index]
		
		if item:
			# Show occupied state
			if slot_occupied_material:
				slot.material_override = slot_occupied_material
			
			# Create item visual (simplified)
			_create_item_visual(slot, item)
		else:
			# Show empty state
			if grid_material:
				slot.material_override = grid_material
			
			# Remove item visual
			_remove_item_visual(slot)

func _create_item_visual(slot: Node3D, item: Dictionary):
	# Remove existing item visual
	_remove_item_visual(slot)
	
	# Create new item representation
	var item_visual = MeshInstance3D.new()
	var mesh = _get_item_mesh(item.get("name", "unknown"))
	item_visual.mesh = mesh
	item_visual.position = Vector3(0, 0.02, 0)
	item_visual.scale = Vector3.ONE * 0.5
	item_visual.name = "ItemVisual"
	slot.add_child(item_visual)

func _remove_item_visual(slot: Node3D):
	var item_visual = slot.get_node_or_null("ItemVisual")
	if item_visual:
		item_visual.queue_free()

func _get_item_mesh(item_name: String) -> Mesh:
	# Return appropriate mesh for item type
	match item_name:
		"wood":
			var box = BoxMesh.new()
			box.size = Vector3(0.08, 0.02, 0.08)
			return box
		"stone":
			var sphere = SphereMesh.new()
			sphere.radius = 0.03
			return sphere
		"stick":
			var cylinder = CylinderMesh.new()
			cylinder.height = 0.08
			cylinder.top_radius = 0.005
			cylinder.bottom_radius = 0.005
			return cylinder
		_:
			var default_box = BoxMesh.new()
			default_box.size = Vector3(0.05, 0.05, 0.05)
			return default_box

func _check_recipe_matching():
	if not auto_craft_enabled:
		return
	
	var current_pattern = _get_current_pattern()
	var matching_recipe = _find_matching_recipe(current_pattern)
	
	if matching_recipe and matching_recipe != active_recipe:
		active_recipe = matching_recipe
		
		if _has_all_ingredients(matching_recipe):
			_craft_item(matching_recipe)

func _get_current_pattern() -> Array:
	var pattern = []
	for x in range(crafting_grid_size.x):
		pattern.append([])
		for y in range(crafting_grid_size.y):
			var item = crafting_grid[x][y]
			var item_name = item.get("name", "") if item else ""
			pattern[x].append(item_name)
	
	return pattern

func _find_matching_recipe(pattern: Array) -> Dictionary:
	for recipe in known_recipes:
		if _patterns_match(pattern, recipe.pattern):
			return recipe
	
	return {}

func _patterns_match(grid_pattern: Array, recipe_pattern: Array) -> bool:
	# Check if recipe pattern fits anywhere in the grid
	for offset_x in range(crafting_grid_size.x - recipe_pattern.size() + 1):
		for offset_y in range(crafting_grid_size.y - recipe_pattern[0].size() + 1):
			if _pattern_matches_at_offset(grid_pattern, recipe_pattern, offset_x, offset_y):
				return true
	
	return false

func _pattern_matches_at_offset(grid: Array, recipe: Array, offset_x: int, offset_y: int) -> bool:
	for recipe_x in range(recipe.size()):
		for recipe_y in range(recipe[0].size()):
			var grid_x = offset_x + recipe_x
			var grid_y = offset_y + recipe_y
			
			var grid_item = grid[grid_x][grid_y] if grid_x < grid.size() and grid_y < grid[0].size() else ""
			var recipe_item = recipe[recipe_x][recipe_y]
			
			if grid_item != recipe_item:
				return false
	
	return true

func _has_all_ingredients(recipe: Dictionary) -> bool:
	var required_counts = {}
	
	# Count required ingredients
	for row in recipe.pattern:
		for ingredient in row:
			if ingredient != "":
				required_counts[ingredient] = required_counts.get(ingredient, 0) + 1
	
	# Count available ingredients
	var available_counts = {}
	for x in range(crafting_grid_size.x):
		for y in range(crafting_grid_size.y):
			var item = crafting_grid[x][y]
			if item:
				var name = item.get("name", "")
				var count = item.get("count", 1)
				available_counts[name] = available_counts.get(name, 0) + count
	
	# Check if we have enough of each ingredient
	for ingredient in required_counts:
		if available_counts.get(ingredient, 0) < required_counts[ingredient]:
			return false
	
	return true

func _craft_item(recipe: Dictionary):
	# Remove ingredients from grid
	_consume_ingredients(recipe)
	
	# Create result item
	var result = recipe.result.duplicate()
	var crafted_item = _spawn_item(result)
	
	item_crafted.emit(result.name, crafted_item)
	
	# Visual and audio feedback
	if success_effect_scene:
		var effect = success_effect_scene.instantiate()
		add_child(effect)
		effect.global_position = global_position + Vector3(0, grid_height + 0.2, 0)
	
	if success_sound:
		audio_player.stream = success_sound
		audio_player.play()
	
	if crafting_particles:
		crafting_particles.restart()
	
	# Clear active recipe
	active_recipe = {}

func _consume_ingredients(recipe: Dictionary):
	var required_counts = {}
	
	# Count required ingredients
	for row in recipe.pattern:
		for ingredient in row:
			if ingredient != "":
				required_counts[ingredient] = required_counts.get(ingredient, 0) + 1
	
	# Remove ingredients from grid
	for x in range(crafting_grid_size.x):
		for y in range(crafting_grid_size.y):
			var item = crafting_grid[x][y]
			if item:
				var name = item.get("name", "")
				if required_counts.has(name) and required_counts[name] > 0:
					var current_count = item.get("count", 1)
					if current_count > 1:
						item["count"] = current_count - 1
						_update_slot_visual(x, y, item)
					else:
						crafting_grid[x][y] = null
						_update_slot_visual(x, y, null)
					
					required_counts[name] -= 1

func _spawn_item(item_data: Dictionary) -> Node3D:
	# Create physical item instance
	var item_instance = RigidBody3D.new()
	
	# Add mesh
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = _get_item_mesh(item_data.name)
	item_instance.add_child(mesh_instance)
	
	# Add collision
	var collision = CollisionShape3D.new()
	collision.shape = mesh_instance.mesh.create_single_convex_collision_shape()
	item_instance.add_child(collision)
	
	# Set position above crafting table
	item_instance.global_position = global_position + Vector3(0, grid_height + 0.3, 0)
	
	# Add to scene
	get_tree().current_scene.add_child(item_instance)
	
	return item_instance

func _update_slot_highlights():
	# Reset all slot materials
	for i in range(slot_visuals.size()):
		var slot = slot_visuals[i]
		var x = i % crafting_grid_size.x
		var y = i / crafting_grid_size.x
		
		if crafting_grid[x][y] != null:
			if slot_occupied_material:
				slot.material_override = slot_occupied_material
		else:
			if grid_material:
				slot.material_override = grid_material

func _on_controller_button(controller: XRController3D, button_name: String, pressed: bool):
	if button_name == "grip_click" and pressed:
		_try_grab_item(controller)
	elif button_name == "menu_button" and pressed:
		_open_recipe_book()

func _try_grab_item(controller: XRController3D):
	# Check if controller is near any item in grid
	var controller_pos = controller.global_position
	
	for x in range(crafting_grid_size.x):
		for y in range(crafting_grid_size.y):
			if crafting_grid[x][y] != null:
				var slot_index = y * crafting_grid_size.x + x
				var slot_pos = global_position + slot_positions[slot_index]
				
				if controller_pos.distance_to(slot_pos) < snap_threshold:
					var item = crafting_grid[x][y]
					grabbed_items[controller] = item
					crafting_grid[x][y] = null
					_update_slot_visual(x, y, null)
					break

func _get_controller_holding_item(item: Dictionary) -> XRController3D:
	for controller in grabbed_items:
		if grabbed_items[controller] == item:
			return controller
	return null

func _open_recipe_book():
	if recipe_book_scene:
		var recipe_book = recipe_book_scene.instantiate()
		add_child(recipe_book)
		recipe_book.global_position = global_position + Vector3(0, 1.5, -0.5)

func clear_grid():
	for x in range(crafting_grid_size.x):
		for y in range(crafting_grid_size.y):
			crafting_grid[x][y] = null
			_update_slot_visual(x, y, null)

func learn_recipe(recipe_name: String):
	for recipe in recipe_database:
		if recipe.name == recipe_name and not recipe in known_recipes:
			known_recipes.append(recipe)
			recipe_discovered.emit(recipe_name)
			
			if recipe_unlock_sound:
				audio_player.stream = recipe_unlock_sound
				audio_player.play()
			
			break