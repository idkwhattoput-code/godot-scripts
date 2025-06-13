extends Control

# 3D HUD System for Godot
# Manages health bars, minimaps, objective markers, and other UI elements
# Supports both screen-space and world-space UI elements

# HUD Elements
export var show_health_bar = true
export var show_stamina_bar = true
export var show_minimap = true
export var show_compass = true
export var show_objective_markers = true
export var show_damage_numbers = true
export var show_interaction_prompts = true

# Health/Stamina settings
export var health_bar_color = Color(0.8, 0.2, 0.2)
export var stamina_bar_color = Color(0.2, 0.8, 0.2)
export var bar_background_color = Color(0.1, 0.1, 0.1, 0.8)
export var low_health_threshold = 0.3
export var low_health_pulse_speed = 2.0

# Minimap settings
export var minimap_size = Vector2(200, 200)
export var minimap_zoom = 50.0
export var minimap_follow_player = true
export var minimap_rotate_with_player = true
export var minimap_icons = {}  # Dictionary of icon textures

# Compass settings
export var compass_size = Vector2(400, 50)
export var compass_marker_size = 20
export var north_color = Color.red
export var cardinal_directions = ["N", "E", "S", "W"]

# Objective markers
export var marker_default_color = Color.yellow
export var marker_completed_color = Color.green
export var marker_failed_color = Color.red
export var marker_edge_opacity = 0.5

# Damage numbers
export var damage_number_font: DynamicFont
export var damage_number_duration = 1.5
export var damage_number_rise_speed = 50.0
export var critical_damage_color = Color.yellow
export var healing_color = Color.green

# Internal variables
var player: Spatial
var camera: Camera
var current_health = 1.0
var current_stamina = 1.0
var objective_markers = {}
var damage_number_pool = []
var interaction_prompt_pool = []
var world_space_elements = []

# UI References
onready var health_bar = $HealthBar
onready var stamina_bar = $StaminaBar
onready var minimap_viewport = $MinimapViewport
onready var minimap_camera = $MinimapViewport/MinimapCamera
onready var minimap_display = $MinimapDisplay
onready var compass = $Compass
onready var objective_container = $ObjectiveMarkers
onready var damage_numbers_container = $DamageNumbers
onready var interaction_container = $InteractionPrompts

func _ready():
	# Find player and camera
	player = get_tree().get_nodes_in_group("player")[0] if get_tree().has_group("player") else null
	camera = get_viewport().get_camera()
	
	# Setup HUD elements
	setup_health_bar()
	setup_stamina_bar()
	setup_minimap()
	setup_compass()
	
	# Create object pools
	create_damage_number_pool()
	create_interaction_prompt_pool()

func setup_health_bar():
	"""Setup health bar UI"""
	if not health_bar and show_health_bar:
		health_bar = ProgressBar.new()
		add_child(health_bar)
		health_bar.name = "HealthBar"
		health_bar.rect_size = Vector2(300, 30)
		health_bar.rect_position = Vector2(20, 20)
		health_bar.value = 100
		
		# Style the health bar
		var style_bg = StyleBoxFlat.new()
		style_bg.bg_color = bar_background_color
		style_bg.corner_radius_top_left = 5
		style_bg.corner_radius_top_right = 5
		style_bg.corner_radius_bottom_left = 5
		style_bg.corner_radius_bottom_right = 5
		health_bar.add_stylebox_override("bg", style_bg)
		
		var style_fg = StyleBoxFlat.new()
		style_fg.bg_color = health_bar_color
		style_fg.corner_radius_top_left = 5
		style_fg.corner_radius_top_right = 5
		style_fg.corner_radius_bottom_left = 5
		style_fg.corner_radius_bottom_right = 5
		health_bar.add_stylebox_override("fg", style_fg)

func setup_stamina_bar():
	"""Setup stamina bar UI"""
	if not stamina_bar and show_stamina_bar:
		stamina_bar = ProgressBar.new()
		add_child(stamina_bar)
		stamina_bar.name = "StaminaBar"
		stamina_bar.rect_size = Vector2(300, 20)
		stamina_bar.rect_position = Vector2(20, 60)
		stamina_bar.value = 100
		
		# Style the stamina bar
		var style_bg = StyleBoxFlat.new()
		style_bg.bg_color = bar_background_color
		style_bg.corner_radius_top_left = 5
		style_bg.corner_radius_top_right = 5
		style_bg.corner_radius_bottom_left = 5
		style_bg.corner_radius_bottom_right = 5
		stamina_bar.add_stylebox_override("bg", style_bg)
		
		var style_fg = StyleBoxFlat.new()
		style_fg.bg_color = stamina_bar_color
		style_fg.corner_radius_top_left = 5
		style_fg.corner_radius_top_right = 5
		style_fg.corner_radius_bottom_left = 5
		style_fg.corner_radius_bottom_right = 5
		stamina_bar.add_stylebox_override("fg", style_fg)

func setup_minimap():
	"""Setup minimap viewport and camera"""
	if not show_minimap:
		return
	
	# Create viewport for minimap
	if not minimap_viewport:
		minimap_viewport = Viewport.new()
		minimap_viewport.size = minimap_size
		minimap_viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
		add_child(minimap_viewport)
	
	# Create minimap camera
	if not minimap_camera:
		minimap_camera = Camera.new()
		minimap_viewport.add_child(minimap_camera)
		minimap_camera.projection = Camera.PROJECTION_ORTHOGONAL
		minimap_camera.size = minimap_zoom
		minimap_camera.rotation_degrees.x = -90
		minimap_camera.translation.y = 50
	
	# Create display for minimap
	if not minimap_display:
		minimap_display = TextureRect.new()
		add_child(minimap_display)
		minimap_display.name = "MinimapDisplay"
		minimap_display.texture = minimap_viewport.get_texture()
		minimap_display.rect_size = minimap_size
		minimap_display.rect_position = Vector2(
			get_viewport().size.x - minimap_size.x - 20,
			20
		)
		
		# Add border
		var border = ReferenceRect.new()
		minimap_display.add_child(border)
		border.rect_size = minimap_size
		border.border_color = Color.white
		border.border_width = 2

func setup_compass():
	"""Setup compass UI"""
	if not compass and show_compass:
		compass = Control.new()
		add_child(compass)
		compass.name = "Compass"
		compass.rect_size = compass_size
		compass.rect_position = Vector2(
			(get_viewport().size.x - compass_size.x) / 2,
			20
		)
		compass.mouse_filter = Control.MOUSE_FILTER_IGNORE

func create_damage_number_pool():
	"""Create pool of damage number labels"""
	if not damage_numbers_container:
		damage_numbers_container = Control.new()
		add_child(damage_numbers_container)
		damage_numbers_container.name = "DamageNumbers"
		damage_numbers_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	for i in 20:
		var label = Label.new()
		if damage_number_font:
			label.add_font_override("font", damage_number_font)
		label.visible = false
		damage_numbers_container.add_child(label)
		damage_number_pool.append(label)

func create_interaction_prompt_pool():
	"""Create pool of interaction prompts"""
	if not interaction_container:
		interaction_container = Control.new()
		add_child(interaction_container)
		interaction_container.name = "InteractionPrompts"
		interaction_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	for i in 10:
		var prompt = create_interaction_prompt()
		prompt.visible = false
		interaction_container.add_child(prompt)
		interaction_prompt_pool.append(prompt)

func create_interaction_prompt() -> Control:
	"""Create an interaction prompt UI element"""
	var container = VBoxContainer.new()
	
	var key_label = Label.new()
	key_label.name = "KeyLabel"
	key_label.text = "[E]"
	key_label.align = Label.ALIGN_CENTER
	container.add_child(key_label)
	
	var action_label = Label.new()
	action_label.name = "ActionLabel"
	action_label.text = "Interact"
	action_label.align = Label.ALIGN_CENTER
	container.add_child(action_label)
	
	return container

func _process(delta):
	# Update health bar pulse effect
	if show_health_bar and current_health < low_health_threshold:
		update_low_health_effect(delta)
	
	# Update minimap
	if show_minimap and minimap_follow_player and player:
		update_minimap()
	
	# Update compass
	if show_compass:
		update_compass()
	
	# Update objective markers
	if show_objective_markers:
		update_objective_markers()
	
	# Update world space UI elements
	update_world_space_elements()

func update_low_health_effect(delta):
	"""Pulse health bar when low"""
	var pulse = (sin(OS.get_ticks_msec() * 0.001 * low_health_pulse_speed) + 1.0) * 0.5
	var color = health_bar_color.linear_interpolate(Color.red, pulse)
	
	var style = health_bar.get_stylebox("fg")
	if style is StyleBoxFlat:
		style.bg_color = color

func update_minimap():
	"""Update minimap camera position"""
	if not minimap_camera or not player:
		return
	
	minimap_camera.translation.x = player.translation.x
	minimap_camera.translation.z = player.translation.z
	
	if minimap_rotate_with_player:
		minimap_camera.rotation.y = player.rotation.y

func update_compass():
	"""Update compass display"""
	if not compass or not player:
		return
	
	# Clear previous markers
	for child in compass.get_children():
		child.queue_free()
	
	var player_rotation = player.rotation.y
	
	# Draw compass background
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.5)
	bg.rect_size = compass_size
	compass.add_child(bg)
	
	# Draw cardinal directions
	for i in range(4):
		var angle = i * PI / 2
		var screen_x = (angle - player_rotation) / PI * compass_size.x
		screen_x = fmod(screen_x + compass_size.x * 1.5, compass_size.x)
		
		if screen_x >= 0 and screen_x <= compass_size.x:
			var label = Label.new()
			label.text = cardinal_directions[i]
			label.rect_position.x = screen_x - 10
			label.rect_position.y = compass_size.y / 2 - 10
			
			if i == 0:  # North
				label.modulate = north_color
			
			compass.add_child(label)

func update_objective_markers():
	"""Update objective marker positions"""
	if not camera:
		return
	
	for marker_id in objective_markers:
		var marker_data = objective_markers[marker_id]
		var marker_ui = marker_data.ui_element
		var world_pos = marker_data.world_position
		
		# Convert world position to screen position
		var screen_pos = camera.unproject_position(world_pos)
		
		# Check if position is behind camera
		var cam_transform = camera.global_transform
		var cam_facing = -cam_transform.basis.z
		var to_marker = (world_pos - cam_transform.origin).normalized()
		
		if cam_facing.dot(to_marker) < 0:
			# Behind camera, position at edge
			screen_pos = get_edge_position(screen_pos)
			marker_ui.modulate.a = marker_edge_opacity
		else:
			marker_ui.modulate.a = 1.0
		
		# Clamp to screen bounds
		var viewport_size = get_viewport().size
		screen_pos.x = clamp(screen_pos.x, 50, viewport_size.x - 50)
		screen_pos.y = clamp(screen_pos.y, 50, viewport_size.y - 50)
		
		marker_ui.rect_position = screen_pos - marker_ui.rect_size / 2

func get_edge_position(screen_pos: Vector2) -> Vector2:
	"""Get screen edge position for off-screen markers"""
	var viewport_size = get_viewport().size
	var center = viewport_size / 2
	var direction = (screen_pos - center).normalized()
	
	# Find intersection with screen edge
	var edge_x = viewport_size.x / 2 - 50
	var edge_y = viewport_size.y / 2 - 50
	
	var t_x = edge_x / abs(direction.x) if direction.x != 0 else INF
	var t_y = edge_y / abs(direction.y) if direction.y != 0 else INF
	
	var t = min(t_x, t_y)
	return center + direction * t

func update_world_space_elements():
	"""Update world-space UI elements"""
	for element in world_space_elements:
		if not is_instance_valid(element.node):
			world_space_elements.erase(element)
			continue
		
		var screen_pos = camera.unproject_position(element.node.global_transform.origin + element.offset)
		element.ui.rect_position = screen_pos - element.ui.rect_size / 2
		
		# Hide if behind camera
		var cam_transform = camera.global_transform
		var cam_facing = -cam_transform.basis.z
		var to_element = (element.node.global_transform.origin - cam_transform.origin).normalized()
		element.ui.visible = cam_facing.dot(to_element) > 0

# Public methods
func set_health(value: float):
	"""Set health bar value (0-1)"""
	current_health = clamp(value, 0.0, 1.0)
	if health_bar:
		health_bar.value = current_health * 100

func set_stamina(value: float):
	"""Set stamina bar value (0-1)"""
	current_stamina = clamp(value, 0.0, 1.0)
	if stamina_bar:
		stamina_bar.value = current_stamina * 100

func show_damage_number(position: Vector3, damage: float, is_critical: bool = false, is_healing: bool = false):
	"""Display damage number at world position"""
	if not show_damage_numbers:
		return
	
	var label = get_available_damage_number()
	if not label:
		return
	
	# Configure label
	label.text = str(int(damage))
	label.visible = true
	
	if is_healing:
		label.modulate = healing_color
		label.text = "+" + label.text
	elif is_critical:
		label.modulate = critical_damage_color
		label.text = label.text + "!"
	else:
		label.modulate = Color.white
	
	# Position label
	var screen_pos = camera.unproject_position(position)
	label.rect_position = screen_pos
	
	# Animate
	animate_damage_number(label, screen_pos)

func get_available_damage_number() -> Label:
	"""Get available damage number from pool"""
	for label in damage_number_pool:
		if not label.visible:
			return label
	return null

func animate_damage_number(label: Label, start_pos: Vector2):
	"""Animate damage number"""
	var tween = create_tween()
	
	# Rise and fade
	tween.tween_property(label, "rect_position:y", start_pos.y - damage_number_rise_speed, damage_number_duration)
	tween.parallel().tween_property(label, "modulate:a", 0.0, damage_number_duration)
	tween.tween_callback(label, "hide")

func add_objective_marker(id: String, world_position: Vector3, icon: Texture = null, color: Color = Color.white):
	"""Add an objective marker"""
	if not show_objective_markers:
		return
	
	var marker = TextureRect.new()
	marker.texture = icon if icon else preload("res://icons/objective_marker.png")
	marker.modulate = color
	marker.rect_size = Vector2(32, 32)
	objective_container.add_child(marker)
	
	objective_markers[id] = {
		"ui_element": marker,
		"world_position": world_position,
		"color": color
	}

func remove_objective_marker(id: String):
	"""Remove an objective marker"""
	if id in objective_markers:
		objective_markers[id].ui_element.queue_free()
		objective_markers.erase(id)

func show_interaction_prompt(text: String, key: String = "E"):
	"""Show interaction prompt"""
	if not show_interaction_prompts:
		return
	
	var prompt = get_available_interaction_prompt()
	if not prompt:
		return
	
	prompt.get_node("KeyLabel").text = "[" + key + "]"
	prompt.get_node("ActionLabel").text = text
	prompt.visible = true
	
	# Center on screen
	var viewport_size = get_viewport().size
	prompt.rect_position = Vector2(
		(viewport_size.x - prompt.rect_size.x) / 2,
		viewport_size.y * 0.7
	)

func get_available_interaction_prompt() -> Control:
	"""Get available interaction prompt from pool"""
	for prompt in interaction_prompt_pool:
		if not prompt.visible:
			return prompt
	return null

func hide_interaction_prompts():
	"""Hide all interaction prompts"""
	for prompt in interaction_prompt_pool:
		prompt.visible = false

func add_world_space_ui(node: Spatial, ui_element: Control, offset: Vector3 = Vector3.ZERO):
	"""Add a UI element that follows a 3D node"""
	add_child(ui_element)
	world_space_elements.append({
		"node": node,
		"ui": ui_element,
		"offset": offset
	})