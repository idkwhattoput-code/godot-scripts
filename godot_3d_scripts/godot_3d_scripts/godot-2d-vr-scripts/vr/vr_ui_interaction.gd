extends RayCast

export var ui_interaction_distance: float = 5.0
export var pointer_radius: float = 0.01
export var pointer_color: Color = Color(1, 1, 1, 0.8)
export var hover_color: Color = Color(0, 1, 1, 1)
export var click_color: Color = Color(0, 1, 0, 1)
export var interaction_button: String = "trigger"
export var scroll_speed: float = 10.0
export var haptic_on_hover: float = 0.05
export var haptic_on_click: float = 0.2

onready var laser_pointer = $LaserPointer
onready var hit_indicator = $HitIndicator

var controller: ARVRController
var current_ui_element: Control = null
var is_pressing: bool = false
var last_hover_element: Control = null
var pointer_material: SpatialMaterial

signal ui_hover_started(element)
signal ui_hover_ended(element)
signal ui_clicked(element)

func _ready():
	controller = get_parent()
	enabled = true
	cast_to = Vector3(0, 0, -ui_interaction_distance)
	
	if controller:
		controller.connect("button_pressed", self, "_on_button_pressed")
		controller.connect("button_released", self, "_on_button_released")
	
	_setup_pointer_visuals()

func _setup_pointer_visuals():
	if not laser_pointer:
		laser_pointer = MeshInstance.new()
		add_child(laser_pointer)
		
		var cylinder = CylinderMesh.new()
		cylinder.height = ui_interaction_distance
		cylinder.top_radius = pointer_radius
		cylinder.bottom_radius = pointer_radius * 0.5
		laser_pointer.mesh = cylinder
		
		pointer_material = SpatialMaterial.new()
		pointer_material.albedo_color = pointer_color
		pointer_material.emission_enabled = true
		pointer_material.emission = pointer_color
		pointer_material.emission_energy = 0.5
		laser_pointer.material_override = pointer_material
		
		laser_pointer.transform.origin.z = -ui_interaction_distance * 0.5
		laser_pointer.rotate_x(deg2rad(90))
	
	if not hit_indicator:
		hit_indicator = MeshInstance.new()
		add_child(hit_indicator)
		
		var sphere = SphereMesh.new()
		sphere.radius = 0.02
		sphere.height = 0.04
		hit_indicator.mesh = sphere
		
		var hit_material = SpatialMaterial.new()
		hit_material.albedo_color = hover_color
		hit_material.emission_enabled = true
		hit_material.emission = hover_color
		hit_indicator.material_override = hit_material
		hit_indicator.visible = false

func _physics_process(delta):
	if not controller or not controller.get_is_active():
		_hide_pointer()
		return
	
	_update_raycast()
	_handle_ui_interaction()
	_handle_scrolling(delta)
	_update_pointer_visuals()

func _update_raycast():
	force_raycast_update()

func _handle_ui_interaction():
	if is_colliding():
		var collider = get_collider()
		
		if collider and collider.has_method("get_ui_element"):
			current_ui_element = collider.get_ui_element()
		elif collider is Viewport:
			var point = get_collision_point()
			var local_point = collider.get_global_transform().affine_inverse() * point
			current_ui_element = _get_control_at_position(collider, local_point)
		else:
			current_ui_element = null
	else:
		current_ui_element = null
	
	if current_ui_element != last_hover_element:
		if last_hover_element:
			_on_hover_exit(last_hover_element)
		if current_ui_element:
			_on_hover_enter(current_ui_element)
		last_hover_element = current_ui_element

func _on_hover_enter(element: Control):
	emit_signal("ui_hover_started", element)
	
	if element.has_method("_on_vr_hover_entered"):
		element._on_vr_hover_entered(self)
	
	if controller.has_method("trigger_haptic_pulse"):
		controller.trigger_haptic_pulse(haptic_on_hover, 0.3)
	
	pointer_material.albedo_color = hover_color
	pointer_material.emission = hover_color

func _on_hover_exit(element: Control):
	emit_signal("ui_hover_ended", element)
	
	if element.has_method("_on_vr_hover_exited"):
		element._on_vr_hover_exited(self)
	
	pointer_material.albedo_color = pointer_color
	pointer_material.emission = pointer_color

func _on_button_pressed(button_name):
	if button_name != interaction_button:
		return
	
	is_pressing = true
	
	if current_ui_element:
		_simulate_ui_input(current_ui_element, "pressed")
		
		if controller.has_method("trigger_haptic_pulse"):
			controller.trigger_haptic_pulse(haptic_on_click, 0.5)
		
		pointer_material.albedo_color = click_color
		pointer_material.emission = click_color
		
		emit_signal("ui_clicked", current_ui_element)

func _on_button_released(button_name):
	if button_name != interaction_button:
		return
	
	is_pressing = false
	
	if current_ui_element:
		_simulate_ui_input(current_ui_element, "released")
	
	pointer_material.albedo_color = hover_color if current_ui_element else pointer_color
	pointer_material.emission = hover_color if current_ui_element else pointer_color

func _simulate_ui_input(element: Control, action: String):
	if not element:
		return
	
	var event = InputEventMouseButton.new()
	event.button_index = BUTTON_LEFT
	event.pressed = (action == "pressed")
	
	if is_colliding():
		var viewport = element.get_viewport()
		var point = get_collision_point()
		var local_point = viewport.get_global_transform().affine_inverse() * point
		event.position = Vector2(local_point.x, local_point.y)
		event.global_position = event.position
	
	element.get_viewport().input(event)
	
	if element.has_method("_on_vr_" + action):
		element.call("_on_vr_" + action, self)

func _handle_scrolling(delta):
	if not current_ui_element or not controller:
		return
	
	var touchpad_pos = Vector2.ZERO
	if controller.has_method("get_touchpad_position"):
		touchpad_pos = controller.get_touchpad_position()
	
	if touchpad_pos.length() > 0.5:
		var scroll_event = InputEventMouseButton.new()
		
		if touchpad_pos.y > 0:
			scroll_event.button_index = BUTTON_WHEEL_UP
		else:
			scroll_event.button_index = BUTTON_WHEEL_DOWN
		
		scroll_event.pressed = true
		scroll_event.factor = abs(touchpad_pos.y) * scroll_speed * delta
		
		current_ui_element.get_viewport().input(scroll_event)

func _update_pointer_visuals():
	if not laser_pointer:
		return
	
	laser_pointer.visible = controller.get_is_active()
	
	if is_colliding():
		var distance = global_transform.origin.distance_to(get_collision_point())
		laser_pointer.scale.z = distance / ui_interaction_distance
		laser_pointer.transform.origin.z = -distance * 0.5
		
		if hit_indicator:
			hit_indicator.visible = true
			hit_indicator.global_transform.origin = get_collision_point()
	else:
		laser_pointer.scale.z = 1.0
		laser_pointer.transform.origin.z = -ui_interaction_distance * 0.5
		
		if hit_indicator:
			hit_indicator.visible = false

func _hide_pointer():
	if laser_pointer:
		laser_pointer.visible = false
	if hit_indicator:
		hit_indicator.visible = false

func _get_control_at_position(viewport: Viewport, position: Vector2) -> Control:
	var gui_input_event = InputEventMouseMotion.new()
	gui_input_event.position = position
	
	viewport.input(gui_input_event)
	
	return viewport.gui_get_focus_owner()

func set_pointer_color(color: Color):
	pointer_color = color
	if pointer_material and not current_ui_element:
		pointer_material.albedo_color = color
		pointer_material.emission = color

func get_current_ui_element() -> Control:
	return current_ui_element

func is_pointing_at_ui() -> bool:
	return current_ui_element != null