extends Node3D

signal spell_cast_started(spell_name: String)
signal spell_cast_completed(spell_name: String)
signal spell_cast_failed(reason: String)
signal gesture_recognized(gesture_name: String)
signal mana_changed(current: float, max: float)

@export_group("Spell Configuration")
@export var max_mana: float = 100.0
@export var mana_regen_rate: float = 5.0
@export var gesture_threshold: float = 0.8
@export var cast_time_multiplier: float = 1.0
@export var dual_casting_enabled: bool = true

@export_group("Gesture Recognition")
@export var gesture_smoothing: float = 0.3
@export var min_gesture_speed: float = 0.5
@export var max_gesture_time: float = 3.0
@export var gesture_preview: bool = true
@export var haptic_feedback: bool = true

@export_group("Visual Effects")
@export var hand_glow_material: Material
@export var spell_trail_scene: PackedScene
@export var casting_particles_scene: PackedScene
@export var spell_colors: Dictionary = {
	"fire": Color.ORANGE,
	"ice": Color.CYAN,
	"lightning": Color.YELLOW,
	"heal": Color.GREEN,
	"shield": Color.BLUE
}

@export_group("Spell Database")
@export var available_spells: Array[Resource] = []
@export var starting_spells: Array[String] = ["fireball", "heal", "shield"]

var current_mana: float
var is_casting: bool = false
var current_spell: String = ""
var gesture_points: Array[Vector3] = []
var gesture_timer: float = 0.0
var recognized_gestures: Dictionary = {}

var left_controller: XRController3D
var right_controller: XRController3D
var left_hand_trail: Node3D
var right_hand_trail: Node3D
var spell_instances: Dictionary = {}

# Predefined gestures
var gesture_patterns: Dictionary = {
	"circle": {
		"points": [Vector2(1, 0), Vector2(0.7, 0.7), Vector2(0, 1), Vector2(-0.7, 0.7), 
				  Vector2(-1, 0), Vector2(-0.7, -0.7), Vector2(0, -1), Vector2(0.7, -0.7)],
		"spell": "shield"
	},
	"triangle": {
		"points": [Vector2(0, -1), Vector2(-0.87, 0.5), Vector2(0.87, 0.5), Vector2(0, -1)],
		"spell": "fireball"
	},
	"line_down": {
		"points": [Vector2(0, -1), Vector2(0, 1)],
		"spell": "lightning_bolt"
	},
	"zigzag": {
		"points": [Vector2(-1, -1), Vector2(-0.5, 0), Vector2(0, -1), Vector2(0.5, 0), Vector2(1, -1)],
		"spell": "chain_lightning"
	},
	"spiral": {
		"points": [Vector2(0, 0), Vector2(0.5, 0), Vector2(0, 0.5), Vector2(-0.5, 0), 
				  Vector2(0, -0.5), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)],
		"spell": "tornado"
	},
	"cross": {
		"points": [Vector2(0, -1), Vector2(0, 1), Vector2(0, 0), Vector2(-1, 0), Vector2(1, 0)],
		"spell": "heal"
	}
}

class Spell:
	var name: String
	var mana_cost: float
	var cast_time: float
	var damage: float
	var range: float
	var element: String
	var gesture_pattern: String
	var projectile_scene: PackedScene
	var effect_scene: PackedScene

func _ready():
	current_mana = max_mana
	_setup_controllers()
	_setup_hand_effects()
	_load_spells()

func _setup_controllers():
	var xr_origin = get_node_or_null("/root/XROrigin3D")
	if not xr_origin:
		xr_origin = XROrigin3D.new()
		get_tree().root.add_child(xr_origin)
	
	left_controller = xr_origin.get_node_or_null("LeftController")
	if not left_controller:
		left_controller = XRController3D.new()
		left_controller.tracker = "left_hand"
		xr_origin.add_child(left_controller)
	
	right_controller = xr_origin.get_node_or_null("RightController")
	if not right_controller:
		right_controller = XRController3D.new()
		right_controller.tracker = "right_hand"
		xr_origin.add_child(right_controller)
	
	# Connect controller signals
	left_controller.button_pressed.connect(_on_button_pressed.bind(left_controller))
	left_controller.button_released.connect(_on_button_released.bind(left_controller))
	right_controller.button_pressed.connect(_on_button_pressed.bind(right_controller))
	right_controller.button_released.connect(_on_button_released.bind(right_controller))

func _setup_hand_effects():
	# Create hand trails
	if spell_trail_scene:
		left_hand_trail = spell_trail_scene.instantiate()
		left_controller.add_child(left_hand_trail)
		left_hand_trail.visible = false
		
		right_hand_trail = spell_trail_scene.instantiate()
		right_controller.add_child(right_hand_trail)
		right_hand_trail.visible = false
	
	# Add hand glow meshes
	_create_hand_glow(left_controller)
	_create_hand_glow(right_controller)

func _create_hand_glow(controller: XRController3D):
	var glow_mesh = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.05
	sphere_mesh.height = 0.1
	glow_mesh.mesh = sphere_mesh
	
	if hand_glow_material:
		glow_mesh.material_override = hand_glow_material
	
	glow_mesh.visible = false
	controller.add_child(glow_mesh)

func _load_spells():
	for spell_resource in available_spells:
		if spell_resource and spell_resource.has_method("get_spell_data"):
			var spell_data = spell_resource.get_spell_data()
			spell_instances[spell_data.name] = spell_data

func _process(delta):
	_update_mana(delta)
	_update_gesture_tracking(delta)
	_update_hand_effects(delta)

func _update_mana(delta):
	if current_mana < max_mana and not is_casting:
		current_mana = min(current_mana + mana_regen_rate * delta, max_mana)
		mana_changed.emit(current_mana, max_mana)

func _update_gesture_tracking(delta):
	if not is_casting:
		return
	
	gesture_timer += delta
	if gesture_timer > max_gesture_time:
		_cancel_casting("Gesture took too long")
		return
	
	# Track hand movement
	var controller = right_controller if current_spell.ends_with("_right") else left_controller
	var hand_pos = controller.global_position
	var hand_velocity = controller.get_pose().linear_velocity.length()
	
	if hand_velocity >= min_gesture_speed:
		gesture_points.append(hand_pos)
		
		if gesture_preview:
			_update_gesture_preview()
		
		# Check if gesture is complete
		if gesture_points.size() >= 10:
			_analyze_gesture()

func _update_hand_effects(delta):
	# Update hand glow based on mana level
	for controller in [left_controller, right_controller]:
		if controller and controller.has_node("MeshInstance3D"):
			var glow_mesh = controller.get_node("MeshInstance3D")
			var mana_percentage = current_mana / max_mana
			
			if is_casting and controller == (right_controller if current_spell.ends_with("_right") else left_controller):
				glow_mesh.visible = true
				# Pulsing effect during casting
				var pulse = sin(gesture_timer * 5.0) * 0.5 + 0.5
				glow_mesh.scale = Vector3.ONE * (0.05 + pulse * 0.02)
			else:
				glow_mesh.visible = mana_percentage > 0.1
				glow_mesh.scale = Vector3.ONE * 0.05 * mana_percentage

func _on_button_pressed(button_name: String, controller: XRController3D):
	if button_name == "trigger_click":
		_start_casting(controller)
	elif button_name == "grip_click":
		_quick_cast(controller)
	elif button_name == "menu_button":
		_open_spell_book()

func _on_button_released(button_name: String, controller: XRController3D):
	if button_name == "trigger_click" and is_casting:
		_finish_casting()

func _start_casting(controller: XRController3D):
	if is_casting or current_mana <= 0:
		return
	
	is_casting = true
	gesture_points.clear()
	gesture_timer = 0.0
	
	var hand_name = "left" if controller == left_controller else "right"
	current_spell = "gesture_" + hand_name
	
	spell_cast_started.emit(current_spell)
	
	# Enable trail effect
	var trail = left_hand_trail if controller == left_controller else right_hand_trail
	if trail:
		trail.visible = true
	
	# Start haptic feedback
	if haptic_feedback:
		controller.trigger_haptic_pulse("haptic", 500.0, 0.1, 0.1)

func _finish_casting():
	if not is_casting:
		return
	
	is_casting = false
	
	# Disable trail effects
	if left_hand_trail:
		left_hand_trail.visible = false
	if right_hand_trail:
		right_hand_trail.visible = false
	
	# Final gesture check
	if gesture_points.size() >= 5:
		_analyze_gesture()

func _cancel_casting(reason: String):
	is_casting = false
	gesture_points.clear()
	current_spell = ""
	
	if left_hand_trail:
		left_hand_trail.visible = false
	if right_hand_trail:
		right_hand_trail.visible = false
	
	spell_cast_failed.emit(reason)

func _analyze_gesture():
	# Normalize gesture points
	var normalized_points = _normalize_gesture(gesture_points)
	
	# Compare with known patterns
	var best_match = ""
	var best_score = 0.0
	
	for pattern_name in gesture_patterns:
		var pattern = gesture_patterns[pattern_name]
		var score = _compare_gestures(normalized_points, pattern.points)
		
		if score > best_score and score >= gesture_threshold:
			best_score = score
			best_match = pattern_name
	
	if best_match != "":
		gesture_recognized.emit(best_match)
		var spell_name = gesture_patterns[best_match].spell
		_cast_spell(spell_name)
	else:
		spell_cast_failed.emit("Gesture not recognized")

func _normalize_gesture(points: Array) -> Array:
	if points.size() < 2:
		return []
	
	# Find bounding box
	var min_pos = points[0]
	var max_pos = points[0]
	
	for point in points:
		min_pos = Vector3(min(min_pos.x, point.x), min(min_pos.y, point.y), min(min_pos.z, point.z))
		max_pos = Vector3(max(max_pos.x, point.x), max(max_pos.y, point.y), max(max_pos.z, point.z))
	
	var size = max_pos - min_pos
	var max_dim = max(max(size.x, size.y), size.z)
	
	if max_dim == 0:
		return []
	
	# Normalize to -1 to 1 range
	var normalized = []
	var center = (min_pos + max_pos) / 2
	
	for point in points:
		var norm_point = (point - center) / (max_dim / 2)
		normalized.append(Vector2(norm_point.x, norm_point.y))  # Project to 2D
	
	return normalized

func _compare_gestures(gesture1: Array, gesture2: Array) -> float:
	# Resample gestures to same number of points
	var sample_count = 32
	var resampled1 = _resample_gesture(gesture1, sample_count)
	var resampled2 = _resample_gesture(gesture2, sample_count)
	
	# Calculate similarity score
	var total_distance = 0.0
	for i in range(sample_count):
		total_distance += resampled1[i].distance_to(resampled2[i])
	
	var avg_distance = total_distance / sample_count
	return max(0, 1.0 - avg_distance / 2.0)  # Convert to 0-1 score

func _resample_gesture(points: Array, target_count: int) -> Array:
	if points.size() < 2:
		return []
	
	var resampled = []
	var total_length = 0.0
	
	# Calculate total length
	for i in range(1, points.size()):
		total_length += points[i].distance_to(points[i-1])
	
	var segment_length = total_length / (target_count - 1)
	var accumulated_length = 0.0
	var current_index = 0
	
	resampled.append(points[0])
	
	for i in range(1, target_count - 1):
		var target_length = i * segment_length
		
		while current_index < points.size() - 1:
			var segment_dist = points[current_index + 1].distance_to(points[current_index])
			
			if accumulated_length + segment_dist >= target_length:
				var t = (target_length - accumulated_length) / segment_dist
				var interpolated = points[current_index].lerp(points[current_index + 1], t)
				resampled.append(interpolated)
				break
			
			accumulated_length += segment_dist
			current_index += 1
	
	resampled.append(points[-1])
	return resampled

func _cast_spell(spell_name: String):
	if not spell_instances.has(spell_name):
		spell_cast_failed.emit("Unknown spell")
		return
	
	var spell = spell_instances[spell_name]
	
	if current_mana < spell.mana_cost:
		spell_cast_failed.emit("Not enough mana")
		return
	
	current_mana -= spell.mana_cost
	mana_changed.emit(current_mana, max_mana)
	
	# Create spell effect
	if spell.projectile_scene:
		var projectile = spell.projectile_scene.instantiate()
		get_tree().current_scene.add_child(projectile)
		
		var controller = right_controller if current_spell.ends_with("_right") else left_controller
		projectile.global_position = controller.global_position
		projectile.look_at(controller.global_position + controller.global_transform.basis.z, Vector3.UP)
		
		if projectile.has_method("initialize"):
			projectile.initialize(spell.damage, spell.range, spell.element)
	
	spell_cast_completed.emit(spell_name)
	
	# Haptic feedback
	if haptic_feedback:
		var controller = right_controller if current_spell.ends_with("_right") else left_controller
		controller.trigger_haptic_pulse("haptic", 1000.0, 0.5, 0.3)

func _quick_cast(controller: XRController3D):
	# Cast the last successful spell without gesture
	pass

func _update_gesture_preview():
	# Show gesture trail in real-time
	pass

func _open_spell_book():
	# Open VR spell book interface
	pass

func learn_spell(spell_name: String):
	if spell_name in starting_spells:
		starting_spells.append(spell_name)

func get_known_spells() -> Array:
	return starting_spells