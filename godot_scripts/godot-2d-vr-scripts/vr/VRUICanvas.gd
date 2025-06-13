extends Control

class_name VRUICanvas

signal menu_opened()
signal menu_closed()
signal button_pressed(button_name: String)
signal slider_changed(slider_name: String, value: float)
signal toggle_changed(toggle_name: String, enabled: bool)

enum UIMode {
	WORLD_SPACE,
	SCREEN_SPACE,
	FOLLOW_HEAD,
	CONTROLLER_ATTACHED
}

enum InteractionMode {
	LASER_POINTER,
	DIRECT_TOUCH,
	GAZE,
	VOICE_COMMAND
}

@export var ui_mode: UIMode = UIMode.WORLD_SPACE
@export var interaction_mode: InteractionMode = InteractionMode.LASER_POINTER
@export var canvas_distance: float = 1.5
@export var canvas_scale: Vector3 = Vector3(0.001, 0.001, 0.001)
@export var follow_smoothing: float = 5.0
@export var auto_hide_distance: float = 3.0
@export var fade_duration: float = 0.3
@export var pointer_color: Color = Color.CYAN
@export var invalid_color: Color = Color.RED

var vr_origin: XROrigin3D
var vr_camera: XRCamera3D
var left_controller: XRController3D
var right_controller: XRController3D
var active_controller: XRController3D

var ui_viewport: SubViewport
var ui_canvas: CanvasLayer
var world_canvas: Node3D
var laser_pointer: MeshInstance3D
var ui_cursor: Control

var is_ui_visible: bool = false
var target_position: Vector3
var target_rotation: Vector3
var current_ui_element: Control

var interaction_ray: RayCast3D
var ui_collision_area: Area3D

@onready var fade_overlay: ColorRect = $FadeOverlay
@onready var main_menu: Control = $MainMenu
@onready var settings_menu: Control = $SettingsMenu

var ui_elements: Dictionary = {}
var menu_stack: Array[Control] = []

func _ready():
	setup_vr_references()
	setup_ui_system()
	setup_interaction_system()
	connect_controller_signals()
	
	hide_ui()

func setup_vr_references():
	vr_origin = get_tree().get_first_node_in_group("xr_origin")
	if not vr_origin:
		vr_origin = find_parent("XROrigin3D")
	
	if vr_origin:
		vr_camera = vr_origin.get_node_or_null("XRCamera3D")
		left_controller = vr_origin.get_node_or_null("LeftController")
		right_controller = vr_origin.get_node_or_null("RightController")

func setup_ui_system():
	match ui_mode:
		UIMode.WORLD_SPACE:
			setup_world_space_ui()
		UIMode.SCREEN_SPACE:
			setup_screen_space_ui()
		UIMode.FOLLOW_HEAD:
			setup_follow_head_ui()
		UIMode.CONTROLLER_ATTACHED:
			setup_controller_attached_ui()

func setup_world_space_ui():
	world_canvas = Node3D.new()
	world_canvas.name = "WorldCanvas"
	get_tree().current_scene.add_child(world_canvas)
	
	var mesh_instance = MeshInstance3D.new()
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(2, 1.5)
	mesh_instance.mesh = quad_mesh
	world_canvas.add_child(mesh_instance)
	
	ui_viewport = SubViewport.new()
	ui_viewport.size = Vector2i(1024, 768)
	ui_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	mesh_instance.add_child(ui_viewport)
	
	reparent(ui_viewport)
	
	var viewport_material = StandardMaterial3D.new()
	viewport_material.albedo_texture = ui_viewport.get_texture()
	viewport_material.flags_transparent = true
	mesh_instance.material_override = viewport_material
	
	world_canvas.scale = canvas_scale

func setup_screen_space_ui():
	pass

func setup_follow_head_ui():
	setup_world_space_ui()

func setup_controller_attached_ui():
	setup_world_space_ui()
	if right_controller:
		world_canvas.reparent(right_controller)

func setup_interaction_system():
	match interaction_mode:
		InteractionMode.LASER_POINTER:
			setup_laser_pointer()
		InteractionMode.DIRECT_TOUCH:
			setup_direct_touch()
		InteractionMode.GAZE:
			setup_gaze_interaction()

func setup_laser_pointer():
	if not right_controller:
		return
	
	laser_pointer = MeshInstance3D.new()
	laser_pointer.name = "LaserPointer"
	right_controller.add_child(laser_pointer)
	
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.top_radius = 0.002
	cylinder_mesh.bottom_radius = 0.002
	cylinder_mesh.height = canvas_distance
	laser_pointer.mesh = cylinder_mesh
	
	var laser_material = StandardMaterial3D.new()
	laser_material.albedo_color = pointer_color
	laser_material.emission_enabled = true
	laser_material.emission = pointer_color
	laser_material.flags_unshaded = true
	laser_pointer.material_override = laser_material
	
	laser_pointer.position = Vector3(0, 0, -canvas_distance * 0.5)
	laser_pointer.visible = false
	
	interaction_ray = RayCast3D.new()
	interaction_ray.target_position = Vector3(0, 0, -canvas_distance)
	interaction_ray.enabled = true
	right_controller.add_child(interaction_ray)

func setup_direct_touch():
	if not left_controller or not right_controller:
		return
	
	for controller in [left_controller, right_controller]:
		var touch_area = Area3D.new()
		touch_area.name = "TouchArea"
		controller.add_child(touch_area)
		
		var collision_shape = CollisionShape3D.new()
		var sphere_shape = SphereShape3D.new()
		sphere_shape.radius = 0.05
		collision_shape.shape = sphere_shape
		touch_area.add_child(collision_shape)

func setup_gaze_interaction():
	if not vr_camera:
		return
	
	interaction_ray = RayCast3D.new()
	interaction_ray.target_position = Vector3(0, 0, -canvas_distance)
	interaction_ray.enabled = true
	vr_camera.add_child(interaction_ray)

func connect_controller_signals():
	if left_controller:
		left_controller.button_pressed.connect(_on_controller_button_pressed.bind(left_controller))
		left_controller.button_released.connect(_on_controller_button_released.bind(left_controller))
	
	if right_controller:
		right_controller.button_pressed.connect(_on_controller_button_pressed.bind(right_controller))
		right_controller.button_released.connect(_on_controller_button_released.bind(right_controller))

func _physics_process(delta):
	update_ui_positioning(delta)
	update_interaction_system()
	update_visibility_based_on_distance()

func update_ui_positioning(delta):
	if not world_canvas or not vr_camera:
		return
	
	match ui_mode:
		UIMode.FOLLOW_HEAD:
			update_follow_head_positioning(delta)
		UIMode.WORLD_SPACE:
			update_world_space_positioning()

func update_follow_head_positioning(delta):
	var head_transform = vr_camera.global_transform
	target_position = head_transform.origin + head_transform.basis.z * -canvas_distance
	target_rotation = head_transform.basis.get_euler()
	
	world_canvas.global_position = world_canvas.global_position.lerp(target_position, follow_smoothing * delta)
	world_canvas.rotation = world_canvas.rotation.lerp(target_rotation, follow_smoothing * delta)

func update_world_space_positioning():
	if not world_canvas.global_position:
		world_canvas.global_position = Vector3(0, 1.5, -2)

func update_interaction_system():
	match interaction_mode:
		InteractionMode.LASER_POINTER:
			update_laser_pointer_interaction()
		InteractionMode.GAZE:
			update_gaze_interaction()

func update_laser_pointer_interaction():
	if not interaction_ray or not laser_pointer:
		return
	
	if interaction_ray.is_colliding():
		var collision_point = interaction_ray.get_collision_point()
		var collider = interaction_ray.get_collider()
		
		if is_ui_collision(collider):
			laser_pointer.material_override.albedo_color = pointer_color
			update_ui_cursor_position(collision_point)
		else:
			laser_pointer.material_override.albedo_color = invalid_color

func update_gaze_interaction():
	if not interaction_ray:
		return
	
	if interaction_ray.is_colliding():
		var collider = interaction_ray.get_collider()
		if is_ui_collision(collider):
			var collision_point = interaction_ray.get_collision_point()
			update_ui_cursor_position(collision_point)

func is_ui_collision(collider: Node3D) -> bool:
	return collider == world_canvas or collider.get_parent() == world_canvas

func update_ui_cursor_position(world_position: Vector3):
	pass

func update_visibility_based_on_distance():
	if not vr_camera or not world_canvas:
		return
	
	var distance = vr_camera.global_position.distance_to(world_canvas.global_position)
	
	if distance > auto_hide_distance and is_ui_visible:
		hide_ui()
	elif distance <= auto_hide_distance and not is_ui_visible:
		show_ui()

func show_ui():
	if is_ui_visible:
		return
	
	is_ui_visible = true
	visible = true
	
	if world_canvas:
		world_canvas.visible = true
	
	if laser_pointer:
		laser_pointer.visible = true
	
	fade_in()
	emit_signal("menu_opened")

func hide_ui():
	if not is_ui_visible:
		return
	
	is_ui_visible = false
	
	if laser_pointer:
		laser_pointer.visible = false
	
	fade_out()
	emit_signal("menu_closed")

func fade_in():
	if not fade_overlay:
		return
	
	fade_overlay.modulate.a = 1.0
	var tween = create_tween()
	tween.tween_property(fade_overlay, "modulate:a", 0.0, fade_duration)

func fade_out():
	if not fade_overlay:
		return
	
	var tween = create_tween()
	tween.tween_property(fade_overlay, "modulate:a", 1.0, fade_duration)
	tween.tween_callback(func(): visible = false)
	
	if world_canvas:
		tween.tween_callback(func(): world_canvas.visible = false)

func toggle_ui():
	if is_ui_visible:
		hide_ui()
	else:
		show_ui()

func show_menu(menu_name: String):
	hide_all_menus()
	
	var menu = get_node_or_null(menu_name)
	if menu and menu is Control:
		menu.visible = true
		menu_stack.append(menu)

func hide_menu(menu_name: String):
	var menu = get_node_or_null(menu_name)
	if menu and menu is Control:
		menu.visible = false
		menu_stack.erase(menu)

func hide_all_menus():
	for child in get_children():
		if child is Control and child != fade_overlay:
			child.visible = false
	menu_stack.clear()

func go_back():
	if menu_stack.size() > 1:
		var current_menu = menu_stack.pop_back()
		current_menu.visible = false
		
		var previous_menu = menu_stack[-1]
		previous_menu.visible = true

func add_ui_element(element_name: String, element: Control):
	ui_elements[element_name] = element
	add_child(element)

func remove_ui_element(element_name: String):
	if ui_elements.has(element_name):
		var element = ui_elements[element_name]
		element.queue_free()
		ui_elements.erase(element_name)

func get_ui_element(element_name: String) -> Control:
	return ui_elements.get(element_name)

func create_button(text: String, position: Vector2, size: Vector2) -> Button:
	var button = Button.new()
	button.text = text
	button.position = position
	button.size = size
	button.pressed.connect(_on_ui_button_pressed.bind(text))
	return button

func create_slider(min_value: float, max_value: float, current_value: float, position: Vector2) -> HSlider:
	var slider = HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.value = current_value
	slider.position = position
	slider.value_changed.connect(_on_ui_slider_changed.bind(slider.name))
	return slider

func create_toggle(text: String, enabled: bool, position: Vector2) -> CheckBox:
	var toggle = CheckBox.new()
	toggle.text = text
	toggle.button_pressed = enabled
	toggle.position = position
	toggle.toggled.connect(_on_ui_toggle_changed.bind(text))
	return toggle

func set_ui_scale(scale: Vector3):
	canvas_scale = scale
	if world_canvas:
		world_canvas.scale = scale

func set_ui_distance(distance: float):
	canvas_distance = distance
	if ui_mode == UIMode.FOLLOW_HEAD:
		update_ui_positioning(0.0)

func _on_controller_button_pressed(controller: XRController3D, button: String):
	active_controller = controller
	
	match button:
		"menu_button":
			toggle_ui()
		"trigger":
			if is_ui_visible:
				perform_ui_interaction()
		"by_button", "ax_button":
			if is_ui_visible:
				go_back()

func _on_controller_button_released(controller: XRController3D, button: String):
	pass

func perform_ui_interaction():
	match interaction_mode:
		InteractionMode.LASER_POINTER:
			perform_laser_interaction()
		InteractionMode.GAZE:
			perform_gaze_interaction()

func perform_laser_interaction():
	if not interaction_ray or not interaction_ray.is_colliding():
		return
	
	var collision_point = interaction_ray.get_collision_point()
	simulate_mouse_click(collision_point)

func perform_gaze_interaction():
	if not interaction_ray or not interaction_ray.is_colliding():
		return
	
	var collision_point = interaction_ray.get_collision_point()
	simulate_mouse_click(collision_point)

func simulate_mouse_click(world_position: Vector3):
	pass

func _on_ui_button_pressed(button_name: String):
	emit_signal("button_pressed", button_name)
	
	if active_controller and active_controller.has_method("trigger_haptic_pulse"):
		active_controller.trigger_haptic_pulse("haptic", 0, 0.1, 0.3, 0.0)

func _on_ui_slider_changed(slider_name: String, value: float):
	emit_signal("slider_changed", slider_name, value)

func _on_ui_toggle_changed(toggle_name: String, enabled: bool):
	emit_signal("toggle_changed", toggle_name, enabled)

func get_ui_settings() -> Dictionary:
	return {
		"ui_mode": ui_mode,
		"interaction_mode": interaction_mode,
		"canvas_distance": canvas_distance,
		"canvas_scale": canvas_scale,
		"follow_smoothing": follow_smoothing,
		"auto_hide_distance": auto_hide_distance
	}

func apply_ui_settings(settings: Dictionary):
	ui_mode = settings.get("ui_mode", UIMode.WORLD_SPACE)
	interaction_mode = settings.get("interaction_mode", InteractionMode.LASER_POINTER)
	canvas_distance = settings.get("canvas_distance", 1.5)
	canvas_scale = settings.get("canvas_scale", Vector3(0.001, 0.001, 0.001))
	follow_smoothing = settings.get("follow_smoothing", 5.0)
	auto_hide_distance = settings.get("auto_hide_distance", 3.0)
	
	set_ui_scale(canvas_scale)
	set_ui_distance(canvas_distance)