extends Spatial

export var spell_scenes : Dictionary = {}
export var gesture_threshold = 0.8
export var cast_time_window = 2.0
export var mana_cost_multiplier = 1.0
export var haptic_feedback = true
export var particle_trail : PackedScene

signal gesture_recognized(gesture_name)
signal spell_cast(spell_name, target_position)
signal spell_failed(reason)
signal mana_depleted()

class Gesture:
	var name : String
	var points : Array = []
	var timestamp : float
	
	func add_point(pos):
		points.append({
			"position": pos,
			"time": OS.get_ticks_msec() / 1000.0
		})

class Spell:
	var name : String
	var required_gestures : Array = []
	var mana_cost : float = 10.0
	var cast_time : float = 1.0
	var cooldown : float = 0.5
	var two_handed : bool = false
	var element : String = "neutral"

var registered_spells : Dictionary = {}
var current_gestures : Array = []
var gesture_history : Array = []
var is_casting : bool = false
var current_mana : float = 100.0
var max_mana : float = 100.0
var active_trails : Array = []
var spell_cooldowns : Dictionary = {}

onready var left_controller = $LeftController
onready var right_controller = $RightController
onready var cast_area = $CastArea
onready var mana_regen_timer = $ManaRegenTimer
onready var gesture_visualizer = $GestureVisualizer

func _ready():
	_register_default_spells()
	_setup_controllers()
	
	if mana_regen_timer:
		mana_regen_timer.connect("timeout", self, "_regenerate_mana")
		mana_regen_timer.start()

func _register_default_spells():
	var fireball = Spell.new()
	fireball.name = "Fireball"
	fireball.required_gestures = ["circle", "push"]
	fireball.mana_cost = 20.0
	fireball.element = "fire"
	register_spell(fireball)
	
	var lightning = Spell.new()
	lightning.name = "Lightning"
	lightning.required_gestures = ["zigzag", "point"]
	lightning.mana_cost = 30.0
	lightning.element = "electric"
	register_spell(lightning)
	
	var shield = Spell.new()
	shield.name = "Shield"
	shield.required_gestures = ["square"]
	shield.mana_cost = 15.0
	shield.element = "neutral"
	register_spell(shield)
	
	var telekinesis = Spell.new()
	telekinesis.name = "Telekinesis"
	telekinesis.required_gestures = ["grab", "pull"]
	telekinesis.mana_cost = 10.0
	telekinesis.two_handed = true
	register_spell(telekinesis)

func _setup_controllers():
	if left_controller:
		left_controller.connect("button_pressed", self, "_on_left_button_pressed")
		left_controller.connect("button_released", self, "_on_left_button_released")
	
	if right_controller:
		right_controller.connect("button_pressed", self, "_on_right_button_pressed")
		right_controller.connect("button_released", self, "_on_right_button_released")

func _process(delta):
	_update_spell_cooldowns(delta)
	
	if is_casting:
		_track_gesture_movement()
		_update_particle_trails()

func register_spell(spell : Spell):
	registered_spells[spell.name] = spell
	spell_cooldowns[spell.name] = 0.0

func _on_left_button_pressed(button):
	if button == JOY_VR_TRIGGER:
		_start_gesture_tracking("left")

func _on_right_button_pressed(button):
	if button == JOY_VR_TRIGGER:
		_start_gesture_tracking("right")

func _on_left_button_released(button):
	if button == JOY_VR_TRIGGER:
		_end_gesture_tracking("left")

func _on_right_button_released(button):
	if button == JOY_VR_TRIGGER:
		_end_gesture_tracking("right")

func _start_gesture_tracking(hand):
	is_casting = true
	var gesture = Gesture.new()
	gesture.name = hand + "_gesture"
	current_gestures.append(gesture)
	
	if particle_trail:
		var trail = particle_trail.instance()
		add_child(trail)
		active_trails.append({
			"trail": trail,
			"hand": hand
		})

func _track_gesture_movement():
	for i in range(current_gestures.size()):
		var gesture = current_gestures[i]
		var controller = left_controller if gesture.name.begins_with("left") else right_controller
		
		if controller:
			gesture.add_point(controller.global_transform.origin)

func _end_gesture_tracking(hand):
	var completed_gesture = null
	
	for i in range(current_gestures.size() - 1, -1, -1):
		var gesture = current_gestures[i]
		if gesture.name.begins_with(hand):
			completed_gesture = gesture
			current_gestures.remove(i)
			break
	
	if completed_gesture:
		var recognized = _recognize_gesture(completed_gesture)
		if recognized:
			gesture_history.append({
				"name": recognized,
				"time": OS.get_ticks_msec() / 1000.0
			})
			emit_signal("gesture_recognized", recognized)
			_check_spell_completion()
	
	_cleanup_trails(hand)
	
	if current_gestures.empty():
		is_casting = false

func _recognize_gesture(gesture : Gesture):
	if gesture.points.size() < 3:
		return null
	
	var pattern = _analyze_gesture_pattern(gesture.points)
	
	if _is_circle_pattern(pattern):
		return "circle"
	elif _is_zigzag_pattern(pattern):
		return "zigzag"
	elif _is_square_pattern(pattern):
		return "square"
	elif _is_push_pattern(pattern):
		return "push"
	elif _is_point_pattern(pattern):
		return "point"
	elif _is_grab_pattern(pattern):
		return "grab"
	elif _is_pull_pattern(pattern):
		return "pull"
	
	return null

func _analyze_gesture_pattern(points):
	var pattern = {
		"total_distance": 0.0,
		"direction_changes": 0,
		"average_speed": 0.0,
		"bounding_box": Rect2()
	}
	
	if points.size() < 2:
		return pattern
	
	var min_pos = points[0].position
	var max_pos = points[0].position
	var last_direction = Vector3.ZERO
	
	for i in range(1, points.size()):
		var delta = points[i].position - points[i-1].position
		pattern.total_distance += delta.length()
		
		min_pos = min_pos.min(points[i].position)
		max_pos = max_pos.max(points[i].position)
		
		if delta.length() > 0.01:
			var direction = delta.normalized()
			if last_direction != Vector3.ZERO:
				var angle = last_direction.angle_to(direction)
				if angle > PI/4:
					pattern.direction_changes += 1
			last_direction = direction
	
	var total_time = points[-1].time - points[0].time
	if total_time > 0:
		pattern.average_speed = pattern.total_distance / total_time
	
	return pattern

func _is_circle_pattern(pattern):
	return pattern.direction_changes > 6 and pattern.total_distance > 0.5

func _is_zigzag_pattern(pattern):
	return pattern.direction_changes >= 3 and pattern.direction_changes <= 6

func _is_square_pattern(pattern):
	return pattern.direction_changes == 3 or pattern.direction_changes == 4

func _is_push_pattern(pattern):
	return pattern.average_speed > 2.0 and pattern.direction_changes < 2

func _is_point_pattern(pattern):
	return pattern.total_distance < 0.2 and pattern.average_speed < 0.5

func _is_grab_pattern(pattern):
	return pattern.total_distance < 0.3 and pattern.average_speed < 1.0

func _is_pull_pattern(pattern):
	return pattern.average_speed > 1.5 and pattern.direction_changes < 2

func _check_spell_completion():
	var current_time = OS.get_ticks_msec() / 1000.0
	
	gesture_history = gesture_history.filter(funcref(self, "_is_recent_gesture"))
	
	for spell_name in registered_spells:
		var spell = registered_spells[spell_name]
		if _matches_spell_pattern(spell):
			cast_spell(spell_name)
			gesture_history.clear()
			break

func _is_recent_gesture(gesture_data):
	var current_time = OS.get_ticks_msec() / 1000.0
	return current_time - gesture_data.time < cast_time_window

func _matches_spell_pattern(spell : Spell):
	if gesture_history.size() < spell.required_gestures.size():
		return false
	
	var required_index = 0
	for gesture_data in gesture_history:
		if gesture_data.name == spell.required_gestures[required_index]:
			required_index += 1
			if required_index >= spell.required_gestures.size():
				return true
	
	return false

func cast_spell(spell_name):
	if not spell_name in registered_spells:
		emit_signal("spell_failed", "Unknown spell")
		return
	
	var spell = registered_spells[spell_name]
	
	if spell_cooldowns[spell_name] > 0:
		emit_signal("spell_failed", "Spell on cooldown")
		return
	
	if current_mana < spell.mana_cost:
		emit_signal("mana_depleted")
		emit_signal("spell_failed", "Not enough mana")
		return
	
	current_mana -= spell.mana_cost
	spell_cooldowns[spell_name] = spell.cooldown
	
	var target_pos = _get_spell_target()
	
	if spell_name in spell_scenes:
		var spell_instance = spell_scenes[spell_name].instance()
		get_tree().current_scene.add_child(spell_instance)
		spell_instance.global_transform.origin = cast_area.global_transform.origin
		
		if spell_instance.has_method("set_target"):
			spell_instance.set_target(target_pos)
		
		if spell_instance.has_method("set_caster"):
			spell_instance.set_caster(self)
	
	emit_signal("spell_cast", spell_name, target_pos)
	
	if haptic_feedback:
		_apply_cast_haptics(spell)

func _get_spell_target():
	var forward = -global_transform.basis.z
	var cast_origin = cast_area.global_transform.origin
	
	var space_state = get_world().direct_space_state
	var result = space_state.intersect_ray(
		cast_origin,
		cast_origin + forward * 50.0,
		[self]
	)
	
	if result:
		return result.position
	else:
		return cast_origin + forward * 10.0

func _apply_cast_haptics(spell : Spell):
	var intensity = spell.mana_cost / 50.0
	
	if left_controller and left_controller.has_method("rumble"):
		left_controller.rumble = intensity
		
	if spell.two_handed and right_controller and right_controller.has_method("rumble"):
		right_controller.rumble = intensity

func _update_particle_trails():
	for trail_data in active_trails:
		var controller = left_controller if trail_data.hand == "left" else right_controller
		if controller and trail_data.trail:
			trail_data.trail.global_transform.origin = controller.global_transform.origin

func _cleanup_trails(hand):
	for i in range(active_trails.size() - 1, -1, -1):
		if active_trails[i].hand == hand:
			active_trails[i].trail.queue_free()
			active_trails.remove(i)

func _update_spell_cooldowns(delta):
	for spell_name in spell_cooldowns:
		if spell_cooldowns[spell_name] > 0:
			spell_cooldowns[spell_name] -= delta

func _regenerate_mana():
	current_mana = min(current_mana + 5.0, max_mana)

func get_mana_percentage():
	return current_mana / max_mana

func add_mana(amount):
	current_mana = min(current_mana + amount, max_mana)

func get_spell_info(spell_name):
	if spell_name in registered_spells:
		return registered_spells[spell_name]
	return null

func is_spell_ready(spell_name):
	return spell_cooldowns.get(spell_name, 0.0) <= 0.0