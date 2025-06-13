extends Node2D

signal attack_performed(damage: float, attack_type: String)
signal combo_achieved(combo_name: String, multiplier: float)
signal critical_hit(damage: float)
signal dodge_performed
signal counter_performed

@export_group("Combat Stats")
@export var base_damage: float = 10.0
@export var attack_speed: float = 1.0
@export var critical_chance: float = 0.15
@export var critical_multiplier: float = 2.0
@export var dodge_chance: float = 0.2
@export var combo_window: float = 0.5

@export_group("Attack Types")
@export var light_attack_damage: float = 1.0
@export var heavy_attack_damage: float = 1.5
@export var special_attack_damage: float = 2.0
@export var attack_cooldowns: Dictionary = {
	"light": 0.3,
	"heavy": 0.8,
	"special": 2.0
}

@export_group("Visual Effects")
@export var hit_effect_scene: PackedScene
@export var slash_effect_scene: PackedScene
@export var critical_effect_scene: PackedScene
@export var combo_colors: Array[Color] = [Color.WHITE, Color.YELLOW, Color.ORANGE, Color.RED]

@export_group("Combat Mechanics")
@export var enable_combos: bool = true
@export var enable_counter_attacks: bool = true
@export var invincibility_frames: float = 0.5
@export var knockback_force: float = 200.0

var current_combo: Array[String] = []
var combo_timer: float = 0.0
var attack_timers: Dictionary = {}
var is_invincible: bool = false
var is_attacking: bool = false
var is_dodging: bool = false
var combo_multiplier: float = 1.0

var combo_list: Dictionary = {
	"triple_slash": ["light", "light", "light"],
	"power_strike": ["heavy", "heavy"],
	"whirlwind": ["light", "heavy", "light"],
	"ultimate": ["special", "heavy", "special"]
}

func _ready():
	for attack_type in attack_cooldowns:
		attack_timers[attack_type] = 0.0

func _process(delta):
	_update_timers(delta)
	_update_combo_timer(delta)

func _update_timers(delta):
	for attack_type in attack_timers:
		if attack_timers[attack_type] > 0:
			attack_timers[attack_type] -= delta

func _update_combo_timer(delta):
	if combo_timer > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			_reset_combo()

func perform_attack(attack_type: String, target_position: Vector2) -> bool:
	if is_attacking or attack_timers.get(attack_type, 0) > 0:
		return false
	
	is_attacking = true
	attack_timers[attack_type] = attack_cooldowns.get(attack_type, 1.0)
	
	var damage = _calculate_damage(attack_type)
	var is_critical = randf() < critical_chance
	
	if is_critical:
		damage *= critical_multiplier
		critical_hit.emit(damage)
		_create_critical_effect(target_position)
	
	attack_performed.emit(damage, attack_type)
	
	if enable_combos:
		_add_to_combo(attack_type)
	
	_create_attack_effect(attack_type, target_position)
	
	await get_tree().create_timer(0.2).timeout
	is_attacking = false
	
	return true

func _calculate_damage(attack_type: String) -> float:
	var damage = base_damage
	
	match attack_type:
		"light":
			damage *= light_attack_damage
		"heavy":
			damage *= heavy_attack_damage
		"special":
			damage *= special_attack_damage
	
	damage *= combo_multiplier
	return damage

func _add_to_combo(attack_type: String):
	current_combo.append(attack_type)
	combo_timer = combo_window
	
	_check_combos()
	_update_combo_multiplier()

func _check_combos():
	for combo_name in combo_list:
		var combo_sequence = combo_list[combo_name]
		if _matches_combo(combo_sequence):
			_execute_combo(combo_name)
			break

func _matches_combo(sequence: Array) -> bool:
	if current_combo.size() < sequence.size():
		return false
	
	var start = current_combo.size() - sequence.size()
	for i in range(sequence.size()):
		if current_combo[start + i] != sequence[i]:
			return false
	
	return true

func _execute_combo(combo_name: String):
	combo_multiplier = 2.0 + (current_combo.size() * 0.5)
	combo_achieved.emit(combo_name, combo_multiplier)
	
	match combo_name:
		"triple_slash":
			_create_triple_slash_effect()
		"power_strike":
			_create_power_strike_effect()
		"whirlwind":
			_create_whirlwind_effect()
		"ultimate":
			_create_ultimate_effect()

func _update_combo_multiplier():
	combo_multiplier = 1.0 + (current_combo.size() * 0.2)

func _reset_combo():
	current_combo.clear()
	combo_multiplier = 1.0

func perform_dodge() -> bool:
	if is_dodging:
		return false
	
	is_dodging = true
	is_invincible = true
	
	var success = randf() < dodge_chance
	if success:
		dodge_performed.emit()
	
	await get_tree().create_timer(0.5).timeout
	is_dodging = false
	
	await get_tree().create_timer(invincibility_frames).timeout
	is_invincible = false
	
	return success

func perform_counter(attacker_position: Vector2) -> bool:
	if not enable_counter_attacks or is_attacking:
		return false
	
	counter_performed.emit()
	
	await get_tree().create_timer(0.1).timeout
	perform_attack("heavy", attacker_position)
	
	return true

func apply_knockback(target: Node2D, origin: Vector2):
	if not target.has_method("apply_impulse"):
		return
	
	var direction = (target.global_position - origin).normalized()
	target.apply_impulse(direction * knockback_force)

func _create_attack_effect(attack_type: String, position: Vector2):
	var effect_scene = slash_effect_scene
	
	if not effect_scene:
		return
	
	var effect = effect_scene.instantiate()
	get_tree().current_scene.add_child(effect)
	effect.global_position = position
	
	if current_combo.size() > 0:
		var color_index = min(current_combo.size() - 1, combo_colors.size() - 1)
		if effect.has_method("set_color"):
			effect.set_color(combo_colors[color_index])

func _create_critical_effect(position: Vector2):
	if not critical_effect_scene:
		return
	
	var effect = critical_effect_scene.instantiate()
	get_tree().current_scene.add_child(effect)
	effect.global_position = position

func _create_triple_slash_effect():
	pass

func _create_power_strike_effect():
	pass

func _create_whirlwind_effect():
	pass

func _create_ultimate_effect():
	pass

func take_damage(damage: float, attacker_position: Vector2) -> float:
	if is_invincible:
		return 0.0
	
	if is_dodging and perform_dodge():
		return 0.0
	
	return damage

func get_combat_stats() -> Dictionary:
	return {
		"combo_count": current_combo.size(),
		"combo_multiplier": combo_multiplier,
		"is_attacking": is_attacking,
		"is_invincible": is_invincible
	}