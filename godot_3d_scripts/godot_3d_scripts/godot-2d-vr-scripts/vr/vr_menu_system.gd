extends Spatial

export var menu_distance: float = 1.0
export var menu_scale: float = 0.002
export var follow_head: bool = true
export var follow_smoothing: float = 5.0
export var menu_button: String = "menu"
export var auto_hide_delay: float = 0.0
export var fade_duration: float = 0.3
export var curved_menu: bool = false
export var curve_radius: float = 1.5

onready var menu_viewport = $Viewport
onready var menu_display = $MenuDisplay
onready var menu_collision = $MenuDisplay/StaticBody/CollisionShape

var player: ARVROrigin
var camera: ARVRCamera
var controllers: Array = []
var is_visible: bool = false
var auto_hide_timer: float = 0.0
var current_page: Control = null
var menu_pages: Dictionary = {}

signal menu_opened
signal menu_closed
signal page_changed(page_name)

func _ready():
	player = get_parent()
	camera = player.get_node("ARVRCamera")
	
	for child in player.get_children():
		if child is ARVRController:
			controllers.append(child)
			child.connect("button_pressed", self, "_on_controller_button_pressed", [child])
	
	_setup_menu_display()
	_load_menu_pages()
	hide_menu()

func _setup_menu_display():
	if not menu_display:
		menu_display = MeshInstance.new()
		add_child(menu_display)
		
		var quad = QuadMesh.new()
		quad.size = Vector2(1.0, 0.6)
		menu_display.mesh = quad
		
		var material = SpatialMaterial.new()
		material.albedo_texture = menu_viewport.get_texture()
		material.emission_enabled = true
		material.emission_texture = menu_viewport.get_texture()
		material.emission_energy = 0.5
		menu_display.material_override = material
		
		var static_body = StaticBody.new()
		menu_display.add_child(static_body)
		
		var collision = CollisionShape.new()
		var box = BoxShape.new()
		box.extents = Vector3(0.5, 0.3, 0.01)
		collision.shape = box
		static_body.add_child(collision)
		
		static_body.set_meta("ui_viewport", menu_viewport)
	
	menu_display.scale = Vector3.ONE * menu_scale

func _load_menu_pages():
	for child in menu_viewport.get_children():
		if child is Control:
			menu_pages[child.name] = child
			child.visible = false
	
	if menu_pages.size() > 0:
		show_page(menu_pages.keys()[0])

func _physics_process(delta):
	if is_visible and follow_head and camera:
		_update_menu_position(delta)
	
	if auto_hide_timer > 0:
		auto_hide_timer -= delta
		if auto_hide_timer <= 0:
			hide_menu()

func _update_menu_position(delta):
	var target_position = camera.global_transform.origin + -camera.global_transform.basis.z * menu_distance
	target_position.y = camera.global_transform.origin.y
	
	var target_transform = Transform()
	target_transform.origin = target_position
	target_transform = target_transform.looking_at(
		camera.global_transform.origin,
		Vector3.UP
	)
	
	if curved_menu:
		_apply_curve_to_menu()
	
	global_transform = global_transform.interpolate_with(
		target_transform,
		follow_smoothing * delta
	)

func _apply_curve_to_menu():
	if not menu_display or not menu_display.mesh is QuadMesh:
		return
	
	var mesh = menu_display.mesh as QuadMesh
	var curve_segments = 16
	var vertices = PoolVector3Array()
	var uvs = PoolVector2Array()
	var normals = PoolVector3Array()
	
	for i in range(curve_segments + 1):
		for j in range(2):
			var u = float(i) / float(curve_segments)
			var v = float(j)
			var angle = (u - 0.5) * PI * 0.5
			
			var x = sin(angle) * curve_radius
			var y = (v - 0.5) * mesh.size.y
			var z = cos(angle) * curve_radius - curve_radius
			
			vertices.append(Vector3(x, y, z))
			uvs.append(Vector2(u, v))
			normals.append(Vector3(x, 0, z).normalized())

func _on_controller_button_pressed(button_name: String, controller: ARVRController):
	if button_name == menu_button:
		toggle_menu()

func toggle_menu():
	if is_visible:
		hide_menu()
	else:
		show_menu()

func show_menu():
	if is_visible:
		return
	
	is_visible = true
	menu_display.visible = true
	
	var tween = Tween.new()
	add_child(tween)
	tween.interpolate_property(
		menu_display, "scale",
		Vector3.ZERO, Vector3.ONE * menu_scale,
		fade_duration, Tween.TRANS_ELASTIC, Tween.EASE_OUT
	)
	tween.interpolate_property(
		menu_display.material_override, "albedo_color:a",
		0.0, 1.0, fade_duration
	)
	tween.start()
	yield(tween, "tween_completed")
	tween.queue_free()
	
	if auto_hide_delay > 0:
		auto_hide_timer = auto_hide_delay
	
	emit_signal("menu_opened")

func hide_menu():
	if not is_visible:
		return
	
	is_visible = false
	
	var tween = Tween.new()
	add_child(tween)
	tween.interpolate_property(
		menu_display, "scale",
		menu_display.scale, Vector3.ZERO,
		fade_duration, Tween.TRANS_CUBIC, Tween.EASE_IN
	)
	tween.interpolate_property(
		menu_display.material_override, "albedo_color:a",
		1.0, 0.0, fade_duration
	)
	tween.start()
	yield(tween, "tween_completed")
	menu_display.visible = false
	tween.queue_free()
	
	emit_signal("menu_closed")

func show_page(page_name: String):
	if not menu_pages.has(page_name):
		return
	
	if current_page:
		current_page.visible = false
	
	current_page = menu_pages[page_name]
	current_page.visible = true
	
	emit_signal("page_changed", page_name)

func add_menu_page(page: Control, page_name: String):
	menu_viewport.add_child(page)
	menu_pages[page_name] = page
	page.visible = false

func remove_menu_page(page_name: String):
	if menu_pages.has(page_name):
		var page = menu_pages[page_name]
		menu_pages.erase(page_name)
		page.queue_free()

func get_current_page() -> Control:
	return current_page

func get_page(page_name: String) -> Control:
	return menu_pages.get(page_name, null)

func set_menu_size(size: Vector2):
	if menu_display and menu_display.mesh is QuadMesh:
		menu_display.mesh.size = size
		if menu_collision:
			menu_collision.shape.extents = Vector3(size.x * 0.5, size.y * 0.5, 0.01)

func refresh_menu():
	if menu_display and menu_viewport:
		menu_display.material_override.albedo_texture = menu_viewport.get_texture()
		menu_display.material_override.emission_texture = menu_viewport.get_texture()