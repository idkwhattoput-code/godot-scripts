extends Node3D

class_name VRSpellCasting

@export_group("Casting Settings")
@export var min_gesture_length := 10
@export var max_gesture_time := 5.0
@export var gesture_recognition_threshold := 0.8
@export var mana_cost_multiplier := 1.0
@export var cooldown_reduction := 1.0

@export_group("Visual Effects")
@export var spell_circle_scene: PackedScene
@export var magic_trail_scene: PackedScene
@export var casting_particle_scene: PackedScene
@export var spell_effect_scenes: Dictionary = {}

@export_group("Audio")
@export var spell_sounds: Dictionary = {}
@export var casting_ambient_sound: AudioStream
@export var spell_fail_sound: AudioStream

@export_group("Hand Tracking")
@export var left_hand_path: NodePath
@export var right_hand_path: NodePath
@export var require_both_hands := false
@export var hand_tracking_precision := 0.1

var left_hand: XRController3D
var right_hand: XRController3D
var current_gesture_points := []
var recorded_spells := {}
var active_spells := []
var mana_system: Node
var ui_manager: Node
var audio_player: AudioStreamPlayer3D
var spell_circle_instance: Node3D
var magic_trail_instance: Node3D
var gesture_start_time := 0.0
var is_casting := false
var current_mana := 100.0
var max_mana := 100.0
var mana_regeneration_rate := 10.0

signal spell_cast(spell_name: String, target_position: Vector3)
signal spell_failed(reason: String)
signal gesture_started()
signal gesture_completed(gesture_pattern: Array)
signal mana_changed(current: float, maximum: float)

class Spell:
	var name: String
	var gesture_pattern: Array[Vector3]
	var mana_cost: float
	var cooldown: float
	var damage: float
	var range: float
	var area_of_effect: float
	var spell_type: SpellType
	var element: ElementType
	var special_properties: Dictionary
	var last_cast_time: float = 0.0
	
	enum SpellType {
		PROJECTILE,
		AREA_EFFECT,
		SELF_BUFF,
		HEALING,
		TELEPORTATION,
		SHIELD
	}
	
	enum ElementType {
		FIRE,
		ICE,
		LIGHTNING,
		EARTH,
		WIND,
		LIGHT,
		DARK,
		ARCANE
	}
	
	func _init(spell_name: String, pattern: Array[Vector3], cost: float = 20.0):
		name = spell_name
		gesture_pattern = pattern
		mana_cost = cost
		cooldown = 2.0
		damage = 50.0
		range = 10.0
		spell_type = SpellType.PROJECTILE
		element = ElementType.ARCANE

func _ready():
	setup_hand_controllers()
	setup_audio()
	register_default_spells()
	
	set_physics_process(true)

func setup_hand_controllers():
	if left_hand_path:
		left_hand = get_node(left_hand_path)
	if right_hand_path:
		right_hand = get_node(right_hand_path)
	
	if left_hand:
		left_hand.button_pressed.connect(_on_hand_button_pressed.bind("left"))
		left_hand.button_released.connect(_on_hand_button_released.bind("left"))
	
	if right_hand:
		right_hand.button_pressed.connect(_on_hand_button_pressed.bind("right"))
		right_hand.button_released.connect(_on_hand_button_released.bind("right"))

func setup_audio():
	audio_player = AudioStreamPlayer3D.new()
	add_child(audio_player)
	audio_player.bus = "SFX"

func register_default_spells():
	var fireball_pattern = create_circle_pattern(Vector3.ZERO, 1.0, 8)
	register_spell("Fireball", fireball_pattern, 25.0, Spell.SpellType.PROJECTILE, Spell.ElementType.FIRE)
	
	var lightning_pattern = create_zigzag_pattern(Vector3.ZERO, Vector3(2, 2, 0), 6)
	register_spell("Lightning Bolt", lightning_pattern, 30.0, Spell.SpellType.PROJECTILE, Spell.ElementType.LIGHTNING)
	
	var heal_pattern = create_upward_spiral_pattern(Vector3.ZERO, 1.5, 10)
	register_spell("Heal", heal_pattern, 20.0, Spell.SpellType.HEALING, Spell.ElementType.LIGHT)
	
	var shield_pattern = create_dome_pattern(Vector3.ZERO, 1.0, 12)
	register_spell("Magic Shield", shield_pattern, 40.0, Spell.SpellType.SHIELD, Spell.ElementType.ARCANE)
	
	var teleport_pattern = create_infinity_pattern(Vector3.ZERO, 1.0, 16)
	register_spell("Teleport", teleport_pattern, 50.0, Spell.SpellType.TELEPORTATION, Spell.ElementType.ARCANE)

func register_spell(name: String, pattern: Array[Vector3], mana_cost: float, type: Spell.SpellType, element: Spell.ElementType):
	var spell = Spell.new(name, pattern, mana_cost)
	spell.spell_type = type
	spell.element = element
	recorded_spells[name] = spell

func create_circle_pattern(center: Vector3, radius: float, points: int) -> Array[Vector3]:
	var pattern: Array[Vector3] = []
	for i in range(points):
		var angle = (i * TAU) / points
		var point = center + Vector3(cos(angle) * radius, sin(angle) * radius, 0)
		pattern.append(point)
	return pattern

func create_zigzag_pattern(start: Vector3, end: Vector3, segments: int) -> Array[Vector3]:
	var pattern: Array[Vector3] = []
	var segment_length = start.distance_to(end) / segments
	var direction = (end - start).normalized()
	var perpendicular = Vector3(direction.z, direction.y, -direction.x) * 0.5
	
	for i in range(segments + 1):
		var progress = float(i) / segments
		var base_point = start.lerp(end, progress)
		var offset = perpendicular * (1 if i % 2 == 0 else -1)
		pattern.append(base_point + offset)
	
	return pattern

func create_upward_spiral_pattern(center: Vector3, radius: float, points: int) -> Array[Vector3]:
	var pattern: Array[Vector3] = []
	for i in range(points):
		var progress = float(i) / points
		var angle = progress * TAU * 2
		var height = progress * 2.0
		var point = center + Vector3(cos(angle) * radius, height, sin(angle) * radius)
		pattern.append(point)
	return pattern

func create_dome_pattern(center: Vector3, radius: float, points: int) -> Array[Vector3]:
	var pattern: Array[Vector3] = []
	for i in range(points):
		var angle = (i * TAU) / points
		var height = sin(angle) * radius * 0.5
		var point = center + Vector3(cos(angle) * radius, height, sin(angle) * radius)
		pattern.append(point)
	return pattern

func create_infinity_pattern(center: Vector3, scale: float, points: int) -> Array[Vector3]:
	var pattern: Array[Vector3] = []
	for i in range(points):
		var t = (i * TAU) / points
		var x = scale * sin(t)
		var y = scale * sin(t) * cos(t)
		pattern.append(center + Vector3(x, y, 0))
	return pattern

func _on_hand_button_pressed(hand: String, button_name: String):
	if button_name == "trigger_click":
		start_gesture_capture(hand)

func _on_hand_button_released(hand: String, button_name: String):
	if button_name == "trigger_click" and is_casting:
		complete_gesture_capture()

func start_gesture_capture(hand: String):
	if is_casting:
		return
	
	is_casting = true
	gesture_start_time = Time.get_ticks_msec() / 1000.0
	current_gesture_points.clear()
	
	create_spell_circle()
	create_magic_trail()
	
	emit_signal("gesture_started")
	
	if casting_ambient_sound:
		audio_player.stream = casting_ambient_sound
		audio_player.play()

func complete_gesture_capture():
	if not is_casting:
		return
	
	is_casting = false
	destroy_visual_effects()
	
	var gesture_time = Time.get_ticks_msec() / 1000.0 - gesture_start_time
	
	if gesture_time > max_gesture_time:
		fail_spell("Gesture took too long")
		return
	
	if current_gesture_points.size() < min_gesture_length:
		fail_spell("Gesture too short")
		return
	
	emit_signal("gesture_completed", current_gesture_points)
	
	var matched_spell = recognize_gesture()
	if matched_spell:
		cast_spell(matched_spell)
	else:
		fail_spell("Gesture not recognized")

func _physics_process(delta):
	if is_casting:
		capture_hand_position()
		update_visual_effects()
	
	update_mana_regeneration(delta)
	update_spell_cooldowns(delta)

func capture_hand_position():
	var hand_controller = right_hand if right_hand else left_hand
	if not hand_controller:
		return
	
	var current_pos = hand_controller.global_position
	
	if current_gesture_points.size() == 0 or current_pos.distance_to(current_gesture_points[-1]) > hand_tracking_precision:
		current_gesture_points.append(current_pos)

func recognize_gesture() -> Spell:
	var best_match: Spell = null
	var best_score := 0.0
	
	for spell_name in recorded_spells:
		var spell = recorded_spells[spell_name]
		var score = calculate_gesture_similarity(current_gesture_points, spell.gesture_pattern)
		
		if score > best_score and score >= gesture_recognition_threshold:
			best_score = score
			best_match = spell
	
	return best_match

func calculate_gesture_similarity(captured: Array, pattern: Array[Vector3]) -> float:
	if captured.size() < pattern.size() / 2:
		return 0.0
	
	var normalized_captured = normalize_gesture(captured)
	var normalized_pattern = normalize_gesture(pattern)
	
	var total_distance := 0.0
	var step = float(normalized_captured.size()) / normalized_pattern.size()
	
	for i in range(normalized_pattern.size()):
		var captured_index = int(i * step)
		if captured_index < normalized_captured.size():
			total_distance += normalized_captured[captured_index].distance_to(normalized_pattern[i])
	
	var max_distance = normalized_pattern.size() * 2.0
	return 1.0 - (total_distance / max_distance)

func normalize_gesture(points: Array) -> Array[Vector3]:
	if points.size() < 2:
		return points
	
	var normalized: Array[Vector3] = []
	var bounds = calculate_bounds(points)
	var center = bounds.get_center()
	var scale = 1.0 / max(bounds.size.x, max(bounds.size.y, bounds.size.z))
	
	for point in points:
		var normalized_point = (point - center) * scale
		normalized.append(normalized_point)
	
	return normalized

func calculate_bounds(points: Array) -> AABB:
	if points.size() == 0:
		return AABB()
	
	var min_point = points[0]
	var max_point = points[0]
	
	for point in points:
		min_point.x = min(min_point.x, point.x)
		min_point.y = min(min_point.y, point.y)
		min_point.z = min(min_point.z, point.z)
		max_point.x = max(max_point.x, point.x)
		max_point.y = max(max_point.y, point.y)
		max_point.z = max(max_point.z, point.z)
	
	return AABB(min_point, max_point - min_point)

func cast_spell(spell: Spell):
	if not can_cast_spell(spell):
		return
	
	var adjusted_cost = spell.mana_cost * mana_cost_multiplier
	current_mana -= adjusted_cost
	spell.last_cast_time = Time.get_ticks_msec() / 1000.0
	
	emit_signal("mana_changed", current_mana, max_mana)
	
	var target_position = get_spell_target_position()
	emit_signal("spell_cast", spell.name, target_position)
	
	execute_spell_effect(spell, target_position)
	play_spell_sound(spell)

func can_cast_spell(spell: Spell) -> bool:
	if current_mana < spell.mana_cost * mana_cost_multiplier:
		fail_spell("Not enough mana")
		return false
	
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - spell.last_cast_time < spell.cooldown / cooldown_reduction:
		fail_spell("Spell on cooldown")
		return false
	
	return true

func get_spell_target_position() -> Vector3:
	var hand_controller = right_hand if right_hand else left_hand
	if hand_controller:
		return hand_controller.global_position + hand_controller.global_transform.basis.z * 5.0
	return global_position

func execute_spell_effect(spell: Spell, target_position: Vector3):
	match spell.spell_type:
		Spell.SpellType.PROJECTILE:
			launch_projectile(spell, target_position)
		Spell.SpellType.AREA_EFFECT:
			create_area_effect(spell, target_position)
		Spell.SpellType.HEALING:
			apply_healing(spell)
		Spell.SpellType.SHIELD:
			create_shield(spell)
		Spell.SpellType.TELEPORTATION:
			teleport_player(target_position)
		Spell.SpellType.SELF_BUFF:
			apply_self_buff(spell)

func launch_projectile(spell: Spell, target_position: Vector3):
	if spell_effect_scenes.has(spell.name):
		var projectile = spell_effect_scenes[spell.name].instantiate()
		get_parent().add_child(projectile)
		projectile.global_position = global_position
		
		var direction = (target_position - global_position).normalized()
		if projectile.has_method("set_direction"):
			projectile.set_direction(direction)
		if projectile.has_method("set_damage"):
			projectile.set_damage(spell.damage)

func create_area_effect(spell: Spell, target_position: Vector3):
	if spell_effect_scenes.has(spell.name):
		var effect = spell_effect_scenes[spell.name].instantiate()
		get_parent().add_child(effect)
		effect.global_position = target_position
		
		if effect.has_method("set_damage"):
			effect.set_damage(spell.damage)
		if effect.has_method("set_radius"):
			effect.set_radius(spell.area_of_effect)

func apply_healing(spell: Spell):
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("heal"):
		player.heal(spell.damage)

func create_shield(spell: Spell):
	pass

func teleport_player(target_position: Vector3):
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.global_position = target_position

func apply_self_buff(spell: Spell):
	pass

func fail_spell(reason: String):
	emit_signal("spell_failed", reason)
	destroy_visual_effects()
	
	if spell_fail_sound:
		audio_player.stream = spell_fail_sound
		audio_player.play()

func create_spell_circle():
	if spell_circle_scene:
		spell_circle_instance = spell_circle_scene.instantiate()
		add_child(spell_circle_instance)

func create_magic_trail():
	if magic_trail_scene:
		magic_trail_instance = magic_trail_scene.instantiate()
		add_child(magic_trail_instance)

func update_visual_effects():
	if magic_trail_instance and current_gesture_points.size() > 0:
		var hand_controller = right_hand if right_hand else left_hand
		if hand_controller and magic_trail_instance.has_method("add_point"):
			magic_trail_instance.add_point(hand_controller.global_position)

func destroy_visual_effects():
	if spell_circle_instance:
		spell_circle_instance.queue_free()
		spell_circle_instance = null
	
	if magic_trail_instance:
		magic_trail_instance.queue_free()
		magic_trail_instance = null
	
	if audio_player.playing:
		audio_player.stop()

func play_spell_sound(spell: Spell):
	if spell_sounds.has(spell.name):
		audio_player.stream = spell_sounds[spell.name]
		audio_player.play()

func update_mana_regeneration(delta: float):
	if current_mana < max_mana:
		current_mana = min(current_mana + mana_regeneration_rate * delta, max_mana)
		emit_signal("mana_changed", current_mana, max_mana)

func update_spell_cooldowns(delta: float):
	pass

func get_mana_percentage() -> float:
	return current_mana / max_mana

func add_mana(amount: float):
	current_mana = min(current_mana + amount, max_mana)
	emit_signal("mana_changed", current_mana, max_mana)

func learn_spell(spell_name: String, pattern: Array[Vector3], properties: Dictionary = {}):
	register_spell(spell_name, pattern, properties.get("mana_cost", 20.0), properties.get("type", Spell.SpellType.PROJECTILE), properties.get("element", Spell.ElementType.ARCANE))