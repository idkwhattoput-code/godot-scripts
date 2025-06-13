extends Node3D

@export var enable_comfort_settings: bool = true
@export var vignette_strength: float = 0.8
@export var snap_turn_angle: float = 30.0
@export var comfort_fade_speed: float = 2.0
@export var motion_sickness_reduction: bool = true
@export var tunnel_vision_threshold: float = 0.3

@onready var vignette_overlay: ColorRect = $ComfortUI/VignetteOverlay
@onready var fade_overlay: ColorRect = $ComfortUI/FadeOverlay
@onready var grid_overlay: MeshInstance3D = $ComfortUI/GridOverlay
@onready var player_origin: XROrigin3D = get_parent()

var current_vignette_intensity: float = 0.0
var last_position: Vector3
var movement_speed: float = 0.0
var rotation_comfort_active: bool = false
var teleport_comfort_active: bool = false

signal comfort_setting_changed(setting_name: String, value)
signal motion_detected(intensity: float)

func _ready():
	setup_comfort_overlays()
	last_position = player_origin.global_position if player_origin else Vector3.ZERO
	
	if not enable_comfort_settings:
		disable_all_comfort_features()

func _process(delta):
	if not enable_comfort_settings:
		return
	
	update_movement_tracking(delta)
	update_vignette_effect(delta)
	update_comfort_grid()

func setup_comfort_overlays():
	if vignette_overlay:
		vignette_overlay.color = Color(0, 0, 0, 0)
		vignette_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		var shader_material = ShaderMaterial.new()
		var vignette_shader = preload("res://shaders/VignetteShader.gdshader") if ResourceLoader.exists("res://shaders/VignetteShader.gdshader") else null
		if vignette_shader:
			shader_material.shader = vignette_shader
			vignette_overlay.material = shader_material
	
	if fade_overlay:
		fade_overlay.color = Color(0, 0, 0, 0)
		fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	if grid_overlay:
		setup_comfort_grid()

func setup_comfort_grid():
	if not grid_overlay:
		grid_overlay = MeshInstance3D.new()
		add_child(grid_overlay)
	
	var grid_mesh = QuadMesh.new()
	grid_mesh.size = Vector2(20, 20)
	grid_overlay.mesh = grid_mesh
	
	var grid_material = StandardMaterial3D.new()
	grid_material.flags_transparent = true
	grid_material.albedo_color = Color(1, 1, 1, 0.1)
	grid_material.flags_unshaded = true
	grid_overlay.material_override = grid_material
	
	grid_overlay.visible = false

func update_movement_tracking(delta):
	if not player_origin:
		return
	
	var current_position = player_origin.global_position
	var movement_vector = current_position - last_position
	movement_speed = movement_vector.length() / delta
	
	if motion_sickness_reduction and movement_speed > tunnel_vision_threshold:
		var intensity = clamp((movement_speed - tunnel_vision_threshold) / 2.0, 0.0, 1.0)
		trigger_motion_comfort(intensity)
	
	last_position = current_position
	emit_signal("motion_detected", movement_speed)

func update_vignette_effect(delta):
	if not vignette_overlay:
		return
	
	var target_intensity = 0.0
	
	if motion_sickness_reduction and movement_speed > tunnel_vision_threshold:
		target_intensity = clamp((movement_speed - tunnel_vision_threshold) * vignette_strength, 0.0, vignette_strength)
	
	current_vignette_intensity = lerp(current_vignette_intensity, target_intensity, comfort_fade_speed * delta)
	
	if vignette_overlay.material and vignette_overlay.material is ShaderMaterial:
		var shader_mat = vignette_overlay.material as ShaderMaterial
		shader_mat.set_shader_parameter("vignette_intensity", current_vignette_intensity)
	else:
		vignette_overlay.color.a = current_vignette_intensity

func update_comfort_grid():
	if not grid_overlay or not motion_sickness_reduction:
		return
	
	if movement_speed > tunnel_vision_threshold * 1.5:
		grid_overlay.visible = true
		var alpha = clamp((movement_speed - tunnel_vision_threshold) / 3.0, 0.1, 0.3)
		var material = grid_overlay.material_override as StandardMaterial3D
		if material:
			material.albedo_color.a = alpha
	else:
		grid_overlay.visible = false

func trigger_motion_comfort(intensity: float):
	if not enable_comfort_settings:
		return
	
	current_vignette_intensity = intensity * vignette_strength

func trigger_rotation_comfort():
	if not enable_comfort_settings or rotation_comfort_active:
		return
	
	rotation_comfort_active = true
	perform_comfort_fade(0.2)
	
	await get_tree().create_timer(0.2).timeout
	rotation_comfort_active = false

func trigger_teleport_comfort():
	if not enable_comfort_settings or teleport_comfort_active:
		return
	
	teleport_comfort_active = true
	perform_comfort_fade(0.5)
	
	await get_tree().create_timer(0.5).timeout
	teleport_comfort_active = false

func perform_comfort_fade(duration: float):
	if not fade_overlay:
		return
	
	fade_overlay.visible = true
	
	var tween = create_tween()
	tween.tween_property(fade_overlay, "color:a", 0.8, duration / 2.0)
	tween.tween_property(fade_overlay, "color:a", 0.0, duration / 2.0)
	tween.tween_callback(func(): fade_overlay.visible = false)

func set_comfort_enabled(enabled: bool):
	enable_comfort_settings = enabled
	emit_signal("comfort_setting_changed", "enabled", enabled)
	
	if not enabled:
		disable_all_comfort_features()

func set_vignette_strength(strength: float):
	vignette_strength = clamp(strength, 0.0, 1.0)
	emit_signal("comfort_setting_changed", "vignette_strength", vignette_strength)

func set_motion_sickness_reduction(enabled: bool):
	motion_sickness_reduction = enabled
	emit_signal("comfort_setting_changed", "motion_sickness_reduction", enabled)

func set_tunnel_vision_threshold(threshold: float):
	tunnel_vision_threshold = clamp(threshold, 0.1, 2.0)
	emit_signal("comfort_setting_changed", "tunnel_vision_threshold", threshold)

func disable_all_comfort_features():
	if vignette_overlay:
		vignette_overlay.visible = false
	if grid_overlay:
		grid_overlay.visible = false
	if fade_overlay:
		fade_overlay.visible = false
	
	current_vignette_intensity = 0.0

func enable_comfort_for_action(action_type: String):
	match action_type:
		"rotation":
			trigger_rotation_comfort()
		"teleport":
			trigger_teleport_comfort()
		"fast_movement":
			current_vignette_intensity = vignette_strength * 0.7

func get_comfort_settings() -> Dictionary:
	return {
		"enabled": enable_comfort_settings,
		"vignette_strength": vignette_strength,
		"motion_sickness_reduction": motion_sickness_reduction,
		"tunnel_vision_threshold": tunnel_vision_threshold,
		"snap_turn_angle": snap_turn_angle
	}

func load_comfort_settings(settings: Dictionary):
	if settings.has("enabled"):
		set_comfort_enabled(settings.enabled)
	if settings.has("vignette_strength"):
		set_vignette_strength(settings.vignette_strength)
	if settings.has("motion_sickness_reduction"):
		set_motion_sickness_reduction(settings.motion_sickness_reduction)
	if settings.has("tunnel_vision_threshold"):
		set_tunnel_vision_threshold(settings.tunnel_vision_threshold)
	if settings.has("snap_turn_angle"):
		snap_turn_angle = settings.snap_turn_angle

func create_vignette_shader() -> String:
	return """
	shader_type canvas_item;
	
	uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.0;
	uniform float vignette_softness : hint_range(0.1, 1.0) = 0.5;
	
	void fragment() {
		vec2 uv = SCREEN_UV;
		vec2 center = vec2(0.5, 0.5);
		float dist = distance(uv, center);
		float vignette = smoothstep(vignette_softness, 1.0, dist);
		COLOR = vec4(0.0, 0.0, 0.0, vignette * vignette_intensity);
	}
	"""