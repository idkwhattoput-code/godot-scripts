extends Node3D

class_name VRUIInteraction

@export var ui_interaction_distance: float = 1.0
@export var laser_thickness: float = 0.01
@export var cursor_size: float = 0.05
@export var haptic_feedback_enabled: bool = true

var controller: XRController3D
var ui_ray: RayCast3D
var laser_mesh: MeshInstance3D
var cursor_mesh: MeshInstance3D
var current_ui_element: Control = null
var is_ui_pressed: bool = false
var ui_click_position: Vector2

signal ui_element_hovered(element: Control)
signal ui_element_pressed(element: Control, position: Vector2)
signal ui_element_released(element: Control, position: Vector2)

func _ready():
	controller = get_parent() as XRController3D
	if not controller:
		print("VRUIInteraction must be child of XRController3D")
		return
	
	setup_ui_ray()
	setup_laser_pointer()
	setup_cursor()
	
	controller.button_pressed.connect(_on_controller_button_pressed)
	controller.button_released.connect(_on_controller_button_released)

func _process(delta):
	update_ui_interaction()
	update_visual()

func setup_ui_ray():
	ui_ray = RayCast3D.new()
	add_child(ui_ray)
	ui_ray.target_position = Vector3(0, 0, -ui_interaction_distance)
	ui_ray.enabled = true

func setup_laser_pointer():
	laser_mesh = MeshInstance3D.new()
	add_child(laser_mesh)
	
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.top_radius = laser_thickness
	cylinder_mesh.bottom_radius = laser_thickness
	cylinder_mesh.height = ui_interaction_distance
	laser_mesh.mesh = cylinder_mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.CYAN
	material.emission_enabled = true
	material.emission = Color.CYAN * 0.8
	laser_mesh.material_override = material
	
	laser_mesh.position = Vector3(0, 0, -ui_interaction_distance / 2.0)
	laser_mesh.visible = false

func setup_cursor():
	cursor_mesh = MeshInstance3D.new()
	add_child(cursor_mesh)
	
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = cursor_size
	cursor_mesh.mesh = sphere_mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.emission_enabled = true
	material.emission = Color.WHITE * 0.5
	cursor_mesh.material_override = material
	cursor_mesh.visible = false

func update_ui_interaction():
	var hit_ui_element = get_ui_element_at_ray()
	
	if hit_ui_element != current_ui_element:
		if current_ui_element:
			unhover_ui_element(current_ui_element)
		
		current_ui_element = hit_ui_element
		
		if current_ui_element:
			hover_ui_element(current_ui_element)
	
	if current_ui_element:
		show_ui_visual()
	else:
		hide_ui_visual()

func get_ui_element_at_ray() -> Control:
	if ui_ray.is_colliding():
		var collider = ui_ray.get_collider()
		if collider and collider.has_method("get_ui_element"):
			return collider.get_ui_element()
	return null

func hover_ui_element(element: Control):
	if haptic_feedback_enabled:
		trigger_haptic_feedback(0.1, 0.05)
	ui_element_hovered.emit(element)

func unhover_ui_element(element: Control):
	pass

func press_ui_element(element: Control):
	if not element:
		return
	
	is_ui_pressed = true
	ui_click_position = get_ui_local_position(element)
	
	if element is Button:
		element.pressed.emit()
	
	if haptic_feedback_enabled:
		trigger_haptic_feedback(0.3, 0.1)
	
	ui_element_pressed.emit(element, ui_click_position)

func release_ui_element(element: Control):
	if not element or not is_ui_pressed:
		return
	
	is_ui_pressed = false
	
	if haptic_feedback_enabled:
		trigger_haptic_feedback(0.2, 0.05)
	
	ui_element_released.emit(element, ui_click_position)

func get_ui_local_position(element: Control) -> Vector2:
	return Vector2.ZERO

func show_ui_visual():
	var hit_distance = ui_interaction_distance
	
	if ui_ray.is_colliding():
		hit_distance = global_transform.origin.distance_to(ui_ray.get_collision_point())
		cursor_mesh.global_transform.origin = ui_ray.get_collision_point()
		cursor_mesh.visible = true
	
	laser_mesh.visible = true
	laser_mesh.scale.z = hit_distance / ui_interaction_distance
	laser_mesh.position.z = -hit_distance / 2.0

func hide_ui_visual():
	laser_mesh.visible = false
	cursor_mesh.visible = false

func update_visual():
	if not laser_mesh.visible:
		return
	
	var material = laser_mesh.material_override as StandardMaterial3D
	if is_ui_pressed:
		material.emission = Color.GREEN * 0.8
	else:
		material.emission = Color.CYAN * 0.8

func trigger_haptic_feedback(amplitude: float, duration: float):
	if controller and controller.has_method("trigger_haptic_pulse"):
		controller.trigger_haptic_pulse("haptic", 0, duration, amplitude, 0.0)

func _on_controller_button_pressed(name: String):
	if name == "trigger" and current_ui_element:
		press_ui_element(current_ui_element)

func _on_controller_button_released(name: String):
	if name == "trigger" and current_ui_element:
		release_ui_element(current_ui_element)