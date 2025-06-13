extends Node3D

class_name VRUIManager

signal menu_opened()
signal menu_closed()
signal ui_element_selected(element: Control)

@export var ui_distance: float = 1.5
@export var ui_scale: float = 0.001
@export var fade_duration: float = 0.3
@export var follow_camera: bool = true
@export var ui_curve_radius: float = 2.0

@onready var camera: XRCamera3D = get_node("../../XRCamera3D")
@onready var left_controller: XRController3D = get_node("../../LeftController")
@onready var right_controller: XRController3D = get_node("../../RightController")

var ui_panels: Dictionary = {}
var active_panel: VRUIPanel = null
var ui_raycast: RayCast3D
var cursor_mesh: MeshInstance3D
var fade_tween: Tween

class VRUIPanel extends SubViewport:
	var panel_mesh: MeshInstance3D
	var collision_area: Area3D
	var is_visible: bool = false
	var panel_id: String
	var follow_camera: bool = true
	
	func _init(id: String, size: Vector2i, curved: bool = false):
		panel_id = id
		size = size
		render_target_update_mode = SubViewport.UPDATE_ALWAYS
		
		setup_mesh(curved)
		setup_collision()
	
	func setup_mesh(curved: bool):
		panel_mesh = MeshInstance3D.new()
		add_child(panel_mesh)
		
		if curved:
			var mesh = SphereMesh.new()
			mesh.radius = 2.0
			mesh.height = 4.0
			mesh.radial_segments = 32
			mesh.rings = 16
			panel_mesh.mesh = mesh
		else:
			var mesh = PlaneMesh.new()
			mesh.size = Vector2(2.0, 1.5)
			panel_mesh.mesh = mesh
		
		var material = StandardMaterial3D.new()
		material.flags_transparent = true
		material.flags_unshaded = true
		material.albedo_color = Color.WHITE
		panel_mesh.material_override = material
	
	func setup_collision():
		collision_area = Area3D.new()
		var collision_shape = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(2.0, 1.5, 0.1)
		collision_shape.shape = shape
		collision_area.add_child(collision_shape)
		add_child(collision_area)
	
	func show_panel():
		if not is_visible:
			is_visible = true
			panel_mesh.show()
	
	func hide_panel():
		if is_visible:
			is_visible = false
			panel_mesh.hide()

func _ready():
	setup_ui_raycast()
	setup_cursor()

func _process(delta):
	handle_ui_input()
	update_ui_positions()

func setup_ui_raycast():
	ui_raycast = RayCast3D.new()
	right_controller.add_child(ui_raycast)
	ui_raycast.target_position = Vector3(0, 0, -5.0)
	ui_raycast.collision_mask = 2

func setup_cursor():
	cursor_mesh = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.02
	cursor_mesh.mesh = sphere_mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.CYAN
	material.flags_unshaded = true
	cursor_mesh.material_override = material
	cursor_mesh.hide()
	
	add_child(cursor_mesh)

func create_ui_panel(panel_id: String, size: Vector2i, curved: bool = false) -> VRUIPanel:
	var panel = VRUIPanel.new(panel_id, size, curved)
	ui_panels[panel_id] = panel
	add_child(panel)
	panel.hide_panel()
	return panel

func show_panel(panel_id: String, position_override: Vector3 = Vector3.ZERO):
	if not ui_panels.has(panel_id):
		print("Panel not found: ", panel_id)
		return
	
	if active_panel:
		hide_active_panel()
	
	active_panel = ui_panels[panel_id]
	active_panel.show_panel()
	
	if position_override != Vector3.ZERO:
		active_panel.global_position = position_override
	else:
		position_panel_in_front_of_camera(active_panel)
	
	menu_opened.emit()

func hide_panel(panel_id: String):
	if ui_panels.has(panel_id):
		ui_panels[panel_id].hide_panel()
		if active_panel == ui_panels[panel_id]:
			active_panel = null
			menu_closed.emit()

func hide_active_panel():
	if active_panel:
		active_panel.hide_panel()
		active_panel = null
		menu_closed.emit()

func toggle_panel(panel_id: String):
	if not ui_panels.has(panel_id):
		return
	
	var panel = ui_panels[panel_id]
	if panel.is_visible:
		hide_panel(panel_id)
	else:
		show_panel(panel_id)

func position_panel_in_front_of_camera(panel: VRUIPanel):
	if not camera:
		return
	
	var camera_forward = -camera.global_transform.basis.z
	var target_position = camera.global_position + camera_forward * ui_distance
	
	panel.global_position = target_position
	panel.look_at(camera.global_position, Vector3.UP)
	panel.scale = Vector3.ONE * ui_scale

func update_ui_positions():
	if not active_panel or not follow_camera:
		return
	
	position_panel_in_front_of_camera(active_panel)

func handle_ui_input():
	if not active_panel or not right_controller:
		cursor_mesh.hide()
		return
	
	ui_raycast.force_raycast_update()
	
	if ui_raycast.is_colliding():
		var hit_point = ui_raycast.get_collision_point()
		cursor_mesh.global_position = hit_point
		cursor_mesh.show()
		
		var collider = ui_raycast.get_collider()
		if collider and collider.get_parent() == active_panel:
			var local_hit = active_panel.to_local(hit_point)
			simulate_mouse_input(local_hit)
			
			if right_controller.is_button_pressed("trigger"):
				handle_ui_click(local_hit)
	else:
		cursor_mesh.hide()

func simulate_mouse_input(local_position: Vector3):
	if not active_panel:
		return
	
	var ui_size = active_panel.size
	var uv_x = (local_position.x + 1.0) * 0.5
	var uv_y = 1.0 - (local_position.y + 0.75) * 0.667
	
	var screen_x = uv_x * ui_size.x
	var screen_y = uv_y * ui_size.y
	
	var mouse_event = InputEventMouseMotion.new()
	mouse_event.position = Vector2(screen_x, screen_y)
	active_panel.push_input(mouse_event)

func handle_ui_click(local_position: Vector3):
	if not active_panel:
		return
	
	var ui_size = active_panel.size
	var uv_x = (local_position.x + 1.0) * 0.5
	var uv_y = 1.0 - (local_position.y + 0.75) * 0.667
	
	var screen_x = uv_x * ui_size.x
	var screen_y = uv_y * ui_size.y
	
	var click_event = InputEventMouseButton.new()
	click_event.button_index = MOUSE_BUTTON_LEFT
	click_event.pressed = true
	click_event.position = Vector2(screen_x, screen_y)
	active_panel.push_input(click_event)
	
	var release_event = InputEventMouseButton.new()
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	release_event.position = Vector2(screen_x, screen_y)
	active_panel.push_input(release_event)
	
	right_controller.trigger_haptic_pulse("haptic", 0, 0.3, 0.1, 0)

func add_ui_control(panel_id: String, control: Control):
	if ui_panels.has(panel_id):
		ui_panels[panel_id].add_child(control)

func remove_ui_control(panel_id: String, control: Control):
	if ui_panels.has(panel_id) and control.get_parent() == ui_panels[panel_id]:
		ui_panels[panel_id].remove_child(control)

func set_panel_texture(panel_id: String, texture: Texture2D):
	if ui_panels.has(panel_id):
		var panel = ui_panels[panel_id]
		var material = panel.panel_mesh.material_override as StandardMaterial3D
		if material:
			material.albedo_texture = texture

func fade_panel(panel_id: String, target_alpha: float):
	if not ui_panels.has(panel_id):
		return
	
	var panel = ui_panels[panel_id]
	var material = panel.panel_mesh.material_override as StandardMaterial3D
	
	if material and fade_tween:
		fade_tween.kill()
	
	fade_tween = create_tween()
	fade_tween.tween_property(material, "albedo_color:a", target_alpha, fade_duration)

func get_active_panel() -> VRUIPanel:
	return active_panel

func is_ui_active() -> bool:
	return active_panel != null and active_panel.is_visible