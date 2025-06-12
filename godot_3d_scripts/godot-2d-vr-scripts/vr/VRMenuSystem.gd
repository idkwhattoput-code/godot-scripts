extends Node3D

@export var menu_distance: float = 2.0
@export var menu_scale: Vector3 = Vector3(0.5, 0.5, 0.1)
@export var activation_button: String = "menu_button"
@export var laser_color: Color = Color.CYAN
@export var selected_color: Color = Color.YELLOW

@onready var left_controller: XRController3D = $"../LeftController"
@onready var right_controller: XRController3D = $"../RightController"
@onready var head: XRCamera3D = $"../XRCamera3D"

var menu_panel: Control
var menu_viewport: SubViewport
var menu_mesh: MeshInstance3D
var laser_line: MeshInstance3D
var is_menu_active: bool = false
var selected_button: Button = null
var menu_buttons: Array[Button] = []

signal menu_opened()
signal menu_closed()
signal button_selected(button_name: String)

func _ready():
	setup_menu_system()
	setup_laser()
	
	if left_controller:
		left_controller.button_pressed.connect(_on_controller_button_pressed.bind("left"))
		left_controller.input_vector2_changed.connect(_on_controller_vector2_changed.bind("left"))
	
	if right_controller:
		right_controller.button_pressed.connect(_on_controller_button_pressed.bind("right"))
		right_controller.input_vector2_changed.connect(_on_controller_vector2_changed.bind("right"))

func setup_menu_system():
	menu_viewport = SubViewport.new()
	menu_viewport.size = Vector2i(512, 512)
	menu_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(menu_viewport)
	
	menu_panel = create_menu_panel()
	menu_viewport.add_child(menu_panel)
	
	menu_mesh = MeshInstance3D.new()
	add_child(menu_mesh)
	
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(1, 1)
	menu_mesh.mesh = quad_mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_texture = menu_viewport.get_texture()
	material.flags_transparent = true
	material.flags_unshaded = true
	material.no_depth_test = true
	menu_mesh.material_override = material
	
	menu_mesh.visible = false

func create_menu_panel() -> Control:
	var panel = Panel.new()
	panel.size = Vector2(512, 512)
	
	var vbox = VBoxContainer.new()
	vbox.anchor_left = 0.1
	vbox.anchor_right = 0.9
	vbox.anchor_top = 0.1
	vbox.anchor_bottom = 0.9
	vbox.offset_left = 0
	vbox.offset_right = 0
	vbox.offset_top = 0
	vbox.offset_bottom = 0
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "VR MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	add_menu_button(vbox, "Settings", "settings")
	add_menu_button(vbox, "Save Game", "save")
	add_menu_button(vbox, "Load Game", "load")
	add_menu_button(vbox, "Quit to Menu", "quit_menu")
	add_menu_button(vbox, "Quit Game", "quit_game")
	add_menu_button(vbox, "Close Menu", "close")
	
	return panel

func add_menu_button(container: VBoxContainer, text: String, action: String):
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 50)
	button.pressed.connect(_on_menu_button_pressed.bind(action))
	button.mouse_entered.connect(_on_button_hover.bind(button))
	button.mouse_exited.connect(_on_button_unhover.bind(button))
	
	container.add_child(button)
	menu_buttons.append(button)

func setup_laser():
	laser_line = MeshInstance3D.new()
	add_child(laser_line)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = laser_color
	material.flags_unshaded = true
	material.flags_transparent = true
	laser_line.material_override = material
	
	laser_line.visible = false

func _on_controller_button_pressed(hand: String, button_name: String):
	match button_name:
		"menu_button":
			toggle_menu()
		"trigger_click":
			if is_menu_active:
				activate_selected_button()

func _on_controller_vector2_changed(hand: String, input_name: String, value: Vector2):
	if input_name == "primary" and is_menu_active:
		update_menu_selection(value)

func toggle_menu():
	if is_menu_active:
		close_menu()
	else:
		open_menu()

func open_menu():
	if is_menu_active:
		return
	
	is_menu_active = true
	position_menu_in_front_of_player()
	menu_mesh.visible = true
	laser_line.visible = true
	
	emit_signal("menu_opened")

func close_menu():
	if not is_menu_active:
		return
	
	is_menu_active = false
	menu_mesh.visible = false
	laser_line.visible = false
	clear_selection()
	
	emit_signal("menu_closed")

func position_menu_in_front_of_player():
	if not head:
		return
	
	var head_pos = head.global_position
	var head_forward = -head.global_transform.basis.z
	
	var menu_position = head_pos + head_forward * menu_distance
	menu_mesh.global_position = menu_position
	menu_mesh.look_at(head_pos, Vector3.UP)
	menu_mesh.scale = menu_scale

func update_menu_selection(joystick_input: Vector2):
	if not is_menu_active or menu_buttons.is_empty():
		return
	
	var current_index = -1
	if selected_button:
		current_index = menu_buttons.find(selected_button)
	
	if abs(joystick_input.y) > 0.5:
		var direction = 1 if joystick_input.y > 0 else -1
		var new_index = current_index + direction
		new_index = clamp(new_index, 0, menu_buttons.size() - 1)
		
		if new_index != current_index:
			select_button(menu_buttons[new_index])

func select_button(button: Button):
	clear_selection()
	selected_button = button
	if selected_button:
		highlight_button(selected_button, true)

func clear_selection():
	if selected_button:
		highlight_button(selected_button, false)
		selected_button = null

func highlight_button(button: Button, highlighted: bool):
	if highlighted:
		button.modulate = selected_color
	else:
		button.modulate = Color.WHITE

func activate_selected_button():
	if selected_button:
		selected_button.pressed.emit()

func _on_menu_button_pressed(action: String):
	emit_signal("button_selected", action)
	
	match action:
		"close":
			close_menu()
		"settings":
			open_settings_submenu()
		"save":
			save_game()
		"load":
			load_game()
		"quit_menu":
			quit_to_menu()
		"quit_game":
			quit_game()

func _on_button_hover(button: Button):
	select_button(button)

func _on_button_unhover(button: Button):
	if selected_button == button:
		clear_selection()

func open_settings_submenu():
	pass

func save_game():
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("save_game"):
		game_manager.save_game()

func load_game():
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("load_game"):
		game_manager.load_game()

func quit_to_menu():
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func quit_game():
	get_tree().quit()

func set_menu_distance(distance: float):
	menu_distance = distance
	if is_menu_active:
		position_menu_in_front_of_player()

func add_custom_button(text: String, callback: Callable):
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 50)
	button.pressed.connect(callback)
	
	var vbox = menu_panel.get_child(0)
	vbox.add_child(button)
	menu_buttons.append(button)