extends Node

export var vignette_enabled: bool = true
export var vignette_intensity: float = 0.4
export var vignette_radius: float = 0.7
export var vignette_during_movement_only: bool = true
export var vignette_fade_speed: float = 5.0

export var comfort_turning_enabled: bool = true
export var snap_turn_angle: float = 30.0
export var smooth_turn_speed: float = 90.0
export var use_snap_turning: bool = true

export var teleport_fade_enabled: bool = true
export var teleport_fade_color: Color = Color.BLACK
export var teleport_fade_duration: float = 0.2

export var height_adjustment_enabled: bool = true
export var seated_mode: bool = false
export var seated_height_offset: float = 0.6

export var motion_sickness_reduction: bool = true
export var reduce_peripheral_motion: bool = true
export var stabilize_horizon: bool = false

onready var vignette_overlay = $VignetteOverlay
onready var fade_overlay = $FadeOverlay
onready var comfort_grid = $ComfortGrid

var player: ARVROrigin
var camera: ARVRCamera
var player_controller: Node
var current_vignette_amount: float = 0.0
var is_moving: bool = false
var previous_position: Vector3
var settings_profile: Dictionary = {}

signal comfort_settings_changed
signal vignette_triggered

func _ready():
	player = get_parent()
	camera = player.get_node("ARVRCamera")
	
	if player.has_node("PlayerController"):
		player_controller = player.get_node("PlayerController")
	
	_setup_overlays()
	load_comfort_profile("default")
	
	set_physics_process(true)

func _setup_overlays():
	if not vignette_overlay:
		vignette_overlay = ColorRect.new()
		vignette_overlay.name = "VignetteOverlay"
		vignette_overlay.anchor_right = 1.0
		vignette_overlay.anchor_bottom = 1.0
		vignette_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(vignette_overlay)
		
		var vignette_shader = Shader.new()
		vignette_shader.code = _get_vignette_shader_code()
		
		var shader_material = ShaderMaterial.new()
		shader_material.shader = vignette_shader
		shader_material.set_shader_param("vignette_intensity", vignette_intensity)
		shader_material.set_shader_param("vignette_radius", vignette_radius)
		vignette_overlay.material = shader_material
	
	if not fade_overlay:
		fade_overlay = ColorRect.new()
		fade_overlay.name = "FadeOverlay"
		fade_overlay.anchor_right = 1.0
		fade_overlay.anchor_bottom = 1.0
		fade_overlay.color = teleport_fade_color
		fade_overlay.modulate.a = 0.0
		fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fade_overlay)
	
	if not comfort_grid and reduce_peripheral_motion:
		comfort_grid = MeshInstance.new()
		comfort_grid.name = "ComfortGrid"
		player.add_child(comfort_grid)
		
		var grid_mesh = _create_comfort_grid_mesh()
		comfort_grid.mesh = grid_mesh
		comfort_grid.visible = false

func _physics_process(delta):
	if not camera:
		return
	
	_update_movement_detection(delta)
	_update_vignette(delta)
	_update_comfort_features(delta)
	
	if height_adjustment_enabled:
		_update_height_adjustment()

func _update_movement_detection(delta):
	var current_position = player.global_transform.origin
	var velocity = (current_position - previous_position) / delta
	previous_position = current_position
	
	is_moving = velocity.length() > 0.1
	
	if player_controller and player_controller.has_method("get_player_velocity"):
		var controller_velocity = player_controller.get_player_velocity()
		is_moving = is_moving or controller_velocity.length() > 0.1

func _update_vignette(delta):
	if not vignette_enabled or not vignette_overlay:
		return
	
	var target_vignette = 0.0
	
	if vignette_during_movement_only:
		target_vignette = vignette_intensity if is_moving else 0.0
	else:
		target_vignette = vignette_intensity
	
	current_vignette_amount = lerp(current_vignette_amount, target_vignette, vignette_fade_speed * delta)
	
	if vignette_overlay.material:
		vignette_overlay.material.set_shader_param("vignette_intensity", current_vignette_amount)
	
	if current_vignette_amount > 0.01 and not vignette_overlay.visible:
		vignette_overlay.visible = true
		emit_signal("vignette_triggered")
	elif current_vignette_amount <= 0.01 and vignette_overlay.visible:
		vignette_overlay.visible = false

func _update_comfort_features(delta):
	if comfort_grid and reduce_peripheral_motion:
		comfort_grid.visible = is_moving
		
		if comfort_grid.visible:
			var grid_position = player.global_transform.origin
			grid_position.y = 0
			comfort_grid.global_transform.origin = grid_position
	
	if stabilize_horizon and camera:
		var camera_rotation = camera.global_transform.basis.get_euler()
		camera.rotation.z = -camera_rotation.z * 0.5

func _update_height_adjustment():
	if seated_mode:
		var height_offset = seated_height_offset - camera.transform.origin.y
		player.transform.origin.y = height_offset

func _get_vignette_shader_code() -> String:
	return """
shader_type canvas_item;

uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.4;
uniform float vignette_radius : hint_range(0.0, 1.0) = 0.7;
uniform vec4 vignette_color : hint_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 uv = UV;
	vec2 center = vec2(0.5, 0.5);
	float dist = distance(uv, center);
	float vignette = smoothstep(vignette_radius, vignette_radius - 0.2, dist);
	vignette = 1.0 - (1.0 - vignette) * vignette_intensity;
	COLOR = mix(vignette_color, vec4(1.0), vignette);
}
"""

func _create_comfort_grid_mesh() -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var vertices = PoolVector3Array()
	var uvs = PoolVector2Array()
	var colors = PoolColorArray()
	
	var grid_size = 20
	var grid_spacing = 1.0
	var grid_height = 3.0
	
	for x in range(-grid_size, grid_size + 1):
		for z in range(-grid_size, grid_size + 1):
			if x % 5 == 0 and z % 5 == 0:
				var pos = Vector3(x * grid_spacing, 0, z * grid_spacing)
				
				vertices.append(pos)
				vertices.append(pos + Vector3(0, grid_height, 0))
				
				var alpha = 1.0 - (Vector2(x, z).length() / float(grid_size))
				colors.append(Color(1, 1, 1, alpha * 0.3))
				colors.append(Color(1, 1, 1, alpha * 0.1))
	
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	
	var material = SpatialMaterial.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_set_material(0, material)
	
	return mesh

func apply_comfort_profile(profile_name: String):
	match profile_name:
		"comfort":
			vignette_enabled = true
			vignette_intensity = 0.6
			use_snap_turning = true
			motion_sickness_reduction = true
			reduce_peripheral_motion = true
		"moderate":
			vignette_enabled = true
			vignette_intensity = 0.3
			use_snap_turning = false
			motion_sickness_reduction = true
			reduce_peripheral_motion = false
		"intense":
			vignette_enabled = false
			use_snap_turning = false
			motion_sickness_reduction = false
			reduce_peripheral_motion = false
	
	emit_signal("comfort_settings_changed")

func fade_out(duration: float = -1):
	if duration < 0:
		duration = teleport_fade_duration
	
	var tween = Tween.new()
	add_child(tween)
	tween.interpolate_property(fade_overlay, "modulate:a", 0.0, 1.0, duration)
	tween.start()
	yield(tween, "tween_completed")
	tween.queue_free()

func fade_in(duration: float = -1):
	if duration < 0:
		duration = teleport_fade_duration
	
	var tween = Tween.new()
	add_child(tween)
	tween.interpolate_property(fade_overlay, "modulate:a", 1.0, 0.0, duration)
	tween.start()
	yield(tween, "tween_completed")
	tween.queue_free()

func save_comfort_profile(profile_name: String):
	var profile = {
		"vignette_enabled": vignette_enabled,
		"vignette_intensity": vignette_intensity,
		"vignette_radius": vignette_radius,
		"use_snap_turning": use_snap_turning,
		"snap_turn_angle": snap_turn_angle,
		"smooth_turn_speed": smooth_turn_speed,
		"motion_sickness_reduction": motion_sickness_reduction,
		"reduce_peripheral_motion": reduce_peripheral_motion,
		"seated_mode": seated_mode
	}
	
	var file = File.new()
	file.open("user://vr_comfort_" + profile_name + ".dat", File.WRITE)
	file.store_var(profile)
	file.close()

func load_comfort_profile(profile_name: String):
	var file = File.new()
	if not file.file_exists("user://vr_comfort_" + profile_name + ".dat"):
		return
	
	file.open("user://vr_comfort_" + profile_name + ".dat", File.READ)
	var profile = file.get_var()
	file.close()
	
	for key in profile:
		if key in self:
			set(key, profile[key])
	
	emit_signal("comfort_settings_changed")