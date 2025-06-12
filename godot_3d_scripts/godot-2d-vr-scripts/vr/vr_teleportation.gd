extends Spatial

export var teleport_button: String = "trigger"
export var max_teleport_distance: float = 10.0
export var teleport_arc_segments: int = 32
export var teleport_fade_time: float = 0.2
export var valid_teleport_color: Color = Color(0, 1, 0, 0.5)
export var invalid_teleport_color: Color = Color(1, 0, 0, 0.5)
export var require_floor: bool = true
export var floor_angle_tolerance: float = 45.0

onready var teleport_arc = $TeleportArc
onready var teleport_target = $TeleportTarget
onready var fade_rect = $FadeRect

var controller: ARVRController
var player: ARVROrigin
var camera: ARVRCamera

var is_teleporting: bool = false
var teleport_position: Vector3
var is_valid_teleport: bool = false
var arc_points: PoolVector3Array

signal teleport_started
signal teleport_finished

func _ready():
	controller = get_parent()
	player = controller.get_parent()
	camera = player.get_node("ARVRCamera")
	
	if controller:
		controller.connect("button_pressed", self, "_on_button_pressed")
		controller.connect("button_released", self, "_on_button_released")
	
	_setup_visuals()

func _setup_visuals():
	if not teleport_arc:
		teleport_arc = ImmediateGeometry.new()
		add_child(teleport_arc)
		var mat = SpatialMaterial.new()
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = valid_teleport_color
		teleport_arc.material_override = mat
	
	if not teleport_target:
		teleport_target = MeshInstance.new()
		var cylinder = CylinderMesh.new()
		cylinder.height = 0.1
		cylinder.top_radius = 0.5
		cylinder.bottom_radius = 0.5
		teleport_target.mesh = cylinder
		add_child(teleport_target)
		teleport_target.visible = false

func _physics_process(delta):
	if is_teleporting:
		_update_teleport_arc()
		_update_teleport_visuals()

func _on_button_pressed(button_name):
	if button_name == teleport_button:
		is_teleporting = true
		emit_signal("teleport_started")

func _on_button_released(button_name):
	if button_name == teleport_button and is_teleporting:
		if is_valid_teleport:
			_perform_teleport()
		is_teleporting = false
		_hide_teleport_visuals()

func _update_teleport_arc():
	arc_points.clear()
	
	var start_position = controller.global_transform.origin
	var forward = -controller.global_transform.basis.z
	var velocity = forward * 10.0 - Vector3(0, 5, 0)
	
	var time_step = 0.05
	var current_position = start_position
	var current_velocity = velocity
	
	is_valid_teleport = false
	teleport_position = Vector3.ZERO
	
	for i in range(teleport_arc_segments):
		arc_points.append(current_position)
		
		var space_state = get_world().direct_space_state
		var next_position = current_position + current_velocity * time_step
		
		var result = space_state.intersect_ray(current_position, next_position)
		
		if result:
			teleport_position = result.position
			is_valid_teleport = _is_valid_teleport_location(result)
			arc_points.append(result.position)
			break
		
		current_position = next_position
		current_velocity += Vector3(0, -9.8, 0) * time_step
		
		if current_position.distance_to(start_position) > max_teleport_distance:
			break

func _is_valid_teleport_location(collision_result) -> bool:
	if not collision_result:
		return false
	
	if require_floor:
		var normal = collision_result.normal
		var angle = rad2deg(normal.angle_to(Vector3.UP))
		if angle > floor_angle_tolerance:
			return false
	
	if collision_result.collider.has_method("can_teleport_to"):
		return collision_result.collider.can_teleport_to()
	
	return true

func _update_teleport_visuals():
	if not teleport_arc.visible:
		teleport_arc.visible = true
	
	teleport_arc.clear()
	teleport_arc.begin(Mesh.PRIMITIVE_LINE_STRIP)
	
	var color = valid_teleport_color if is_valid_teleport else invalid_teleport_color
	
	for point in arc_points:
		teleport_arc.set_color(color)
		teleport_arc.add_vertex(teleport_arc.to_local(point))
	
	teleport_arc.end()
	
	if is_valid_teleport and teleport_target:
		teleport_target.visible = true
		teleport_target.global_transform.origin = teleport_position
		var mat = teleport_target.get_surface_material(0)
		if not mat:
			mat = SpatialMaterial.new()
			teleport_target.set_surface_material(0, mat)
		mat.albedo_color = valid_teleport_color
	else:
		if teleport_target:
			teleport_target.visible = false

func _hide_teleport_visuals():
	if teleport_arc:
		teleport_arc.visible = false
		teleport_arc.clear()
	if teleport_target:
		teleport_target.visible = false

func _perform_teleport():
	if not player or not is_valid_teleport:
		return
	
	_fade_out()
	yield(get_tree().create_timer(teleport_fade_time), "timeout")
	
	var camera_offset = camera.transform.origin
	camera_offset.y = 0
	var new_position = teleport_position - camera_offset
	
	player.global_transform.origin = new_position
	
	_fade_in()
	yield(get_tree().create_timer(teleport_fade_time), "timeout")
	
	emit_signal("teleport_finished")

func _fade_out():
	if fade_rect:
		var tween = Tween.new()
		add_child(tween)
		tween.interpolate_property(fade_rect, "modulate:a", 0.0, 1.0, teleport_fade_time)
		tween.start()

func _fade_in():
	if fade_rect:
		var tween = Tween.new()
		add_child(tween)
		tween.interpolate_property(fade_rect, "modulate:a", 1.0, 0.0, teleport_fade_time)
		tween.start()
		yield(tween, "tween_completed")
		tween.queue_free()