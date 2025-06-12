extends Node3D

class_name VRComfortSettings

@export var vignette_enabled: bool = true
@export var snap_turning: bool = true
@export var smooth_turning: bool = false
@export var teleport_fade: bool = true
@export var motion_sickness_reduction: bool = true
@export var comfort_level: int = 2 : set = set_comfort_level

var player_controller: XROrigin3D
var vignette_overlay: MeshInstance3D
var fade_overlay: MeshInstance3D
var comfort_indicator: Label3D
var current_movement_speed: float = 0.0
var vignette_strength: float = 0.0

@onready var comfort_ui: Control = $ComfortUI
@onready var settings_panel: Panel = $ComfortUI/SettingsPanel

signal comfort_settings_changed(setting_name: String, value)
signal motion_sickness_detected()

enum ComfortLevel {
	MINIMAL = 0,
	STANDARD = 1,
	HIGH = 2,
	MAXIMUM = 3
}

func _ready():
	player_controller = get_parent() as XROrigin3D
	if not player_controller:
		print("VRComfortSettings must be child of XROrigin3D")
		return
	
	setup_vignette_overlay()
	setup_fade_overlay()
	setup_comfort_ui()
	apply_comfort_level(comfort_level)

func _process(delta):
	if motion_sickness_reduction:
		monitor_motion_sickness(delta)
	
	update_vignette_effect(delta)
	update_comfort_indicators()

func setup_vignette_overlay():
	vignette_overlay = MeshInstance3D.new()
	add_child(vignette_overlay)
	
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.9
	sphere_mesh.height = 1.8
	vignette_overlay.mesh = sphere_mesh
	
	var vignette_material = StandardMaterial3D.new()
	vignette_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vignette_material.albedo_color = Color.BLACK
	vignette_material.albedo_color.a = 0.0
	vignette_material.cull_mode = BaseMaterial3D.CULL_FRONT
	vignette_material.no_depth_test = true
	vignette_overlay.material_override = vignette_material
	
	vignette_overlay.position = Vector3(0, 0, 0)

func setup_fade_overlay():
	fade_overlay = MeshInstance3D.new()
	add_child(fade_overlay)
	
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(2, 2)
	fade_overlay.mesh = quad_mesh
	
	var fade_material = StandardMaterial3D.new()
	fade_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fade_material.albedo_color = Color.BLACK
	fade_material.albedo_color.a = 0.0
	fade_material.no_depth_test = true
	fade_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fade_overlay.material_override = fade_material
	
	fade_overlay.position = Vector3(0, 0, -0.1)

func setup_comfort_ui():
	if not comfort_ui:
		comfort_ui = Control.new()
		add_child(comfort_ui)
	
	comfort_ui.visible = false

func set_comfort_level(level: int):
	comfort_level = clamp(level, 0, 3)
	apply_comfort_level(comfort_level)
	comfort_settings_changed.emit("comfort_level", comfort_level)

func apply_comfort_level(level: int):
	match level:
		ComfortLevel.MINIMAL:
			apply_minimal_comfort()
		ComfortLevel.STANDARD:
			apply_standard_comfort()
		ComfortLevel.HIGH:
			apply_high_comfort()
		ComfortLevel.MAXIMUM:
			apply_maximum_comfort()

func apply_minimal_comfort():
	vignette_enabled = false
	snap_turning = false
	smooth_turning = true
	teleport_fade = false
	motion_sickness_reduction = false

func apply_standard_comfort():
	vignette_enabled = true
	snap_turning = true
	smooth_turning = false
	teleport_fade = true
	motion_sickness_reduction = false

func apply_high_comfort():
	vignette_enabled = true
	snap_turning = true
	smooth_turning = false
	teleport_fade = true
	motion_sickness_reduction = true

func apply_maximum_comfort():
	vignette_enabled = true
	snap_turning = true
	smooth_turning = false
	teleport_fade = true
	motion_sickness_reduction = true

func monitor_motion_sickness(delta):
	if not player_controller:
		return
	
	var head_tracker = player_controller.get_node("XRCamera3D")
	if not head_tracker:
		return
	
	current_movement_speed = get_movement_speed()
	
	if current_movement_speed > 3.0:
		increase_vignette_strength(delta)
		
		if vignette_strength > 0.7:
			motion_sickness_detected.emit()
	else:
		decrease_vignette_strength(delta)

func get_movement_speed() -> float:
	if player_controller and player_controller.has_method("get_velocity"):
		return player_controller.get_velocity().length()
	return 0.0

func increase_vignette_strength(delta):
	if vignette_enabled:
		vignette_strength = min(vignette_strength + delta * 2.0, 0.8)

func decrease_vignette_strength(delta):
	vignette_strength = max(vignette_strength - delta * 1.5, 0.0)

func update_vignette_effect(delta):
	if not vignette_overlay or not vignette_enabled:
		return
	
	var material = vignette_overlay.material_override as StandardMaterial3D
	if material:
		material.albedo_color.a = vignette_strength

func update_comfort_indicators():
	pass

func perform_comfort_fade(duration: float = 0.3, color: Color = Color.BLACK):
	if not teleport_fade or not fade_overlay:
		return
	
	var material = fade_overlay.material_override as StandardMaterial3D
	if not material:
		return
	
	var tween = create_tween()
	
	material.albedo_color = color
	material.albedo_color.a = 0.0
	
	tween.tween_property(material, "albedo_color:a", 1.0, duration / 2.0)
	tween.tween_property(material, "albedo_color:a", 0.0, duration / 2.0)

func trigger_snap_turn(angle: float):
	if not snap_turning:
		return
	
	perform_comfort_fade(0.2)
	
	await get_tree().create_timer(0.1).timeout
	
	if player_controller:
		player_controller.rotation.y += deg_to_rad(angle)

func enable_comfort_mode():
	set_comfort_level(ComfortLevel.HIGH)

func disable_comfort_mode():
	set_comfort_level(ComfortLevel.MINIMAL)

func toggle_vignette():
	vignette_enabled = not vignette_enabled
	comfort_settings_changed.emit("vignette_enabled", vignette_enabled)

func toggle_snap_turning():
	snap_turning = not snap_turning
	smooth_turning = not snap_turning
	comfort_settings_changed.emit("snap_turning", snap_turning)

func set_vignette_enabled(enabled: bool):
	vignette_enabled = enabled
	if not enabled:
		vignette_strength = 0.0
	comfort_settings_changed.emit("vignette_enabled", enabled)

func set_snap_turning_enabled(enabled: bool):
	snap_turning = enabled
	smooth_turning = not enabled
	comfort_settings_changed.emit("snap_turning", enabled)

func set_teleport_fade_enabled(enabled: bool):
	teleport_fade = enabled
	comfort_settings_changed.emit("teleport_fade", enabled)

func set_motion_sickness_reduction(enabled: bool):
	motion_sickness_reduction = enabled
	comfort_settings_changed.emit("motion_sickness_reduction", enabled)

func get_comfort_settings() -> Dictionary:
	return {
		"comfort_level": comfort_level,
		"vignette_enabled": vignette_enabled,
		"snap_turning": snap_turning,
		"smooth_turning": smooth_turning,
		"teleport_fade": teleport_fade,
		"motion_sickness_reduction": motion_sickness_reduction
	}

func load_comfort_settings(settings: Dictionary):
	if settings.has("comfort_level"):
		set_comfort_level(settings["comfort_level"])
	if settings.has("vignette_enabled"):
		set_vignette_enabled(settings["vignette_enabled"])
	if settings.has("snap_turning"):
		set_snap_turning_enabled(settings["snap_turning"])
	if settings.has("teleport_fade"):
		set_teleport_fade_enabled(settings["teleport_fade"])
	if settings.has("motion_sickness_reduction"):
		set_motion_sickness_reduction(settings["motion_sickness_reduction"])

func reset_to_defaults():
	set_comfort_level(ComfortLevel.STANDARD)

func show_comfort_settings():
	if comfort_ui:
		comfort_ui.visible = true

func hide_comfort_settings():
	if comfort_ui:
		comfort_ui.visible = false

func calibrate_comfort_automatically():
	await get_tree().create_timer(5.0).timeout
	
	if vignette_strength > 0.5:
		set_comfort_level(ComfortLevel.HIGH)
	elif current_movement_speed > 2.0:
		set_comfort_level(ComfortLevel.STANDARD)
	else:
		set_comfort_level(ComfortLevel.MINIMAL)