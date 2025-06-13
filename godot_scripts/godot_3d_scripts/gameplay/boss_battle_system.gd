extends Node

class_name BossBattleSystem

signal boss_spawned(boss)
signal boss_phase_changed(boss, phase)
signal boss_defeated(boss)
signal boss_enraged(boss)
signal boss_ability_used(boss, ability_name)
signal player_warning(warning_type, position)

export var arena_bounds: AABB = AABB(Vector3(-50, 0, -50), Vector3(100, 50, 100))
export var enable_phase_transitions: bool = true
export var enable_enrage_timer: bool = true
export var enrage_time: float = 300.0
export var show_health_bar: bool = true
export var save_boss_progress: bool = true

var active_boss: Boss = null
var battle_timer: float = 0.0
var is_battle_active: bool = false
var player_deaths: int = 0
var damage_dealt: float = 0.0
var damage_taken: float = 0.0

class Boss:
	var name: String = ""
	var max_health: float = 1000.0
	var current_health: float = 1000.0
	var defense: float = 10.0
	var current_phase: int = 0
	var phases: Array = []
	var abilities: Dictionary = {}
	var position: Vector3 = Vector3.ZERO
	var is_enraged: bool = false
	var is_invulnerable: bool = false
	var status_effects: Array = []
	var threat_list: Dictionary = {}
	var target: Node = null
	
	func _init(boss_name: String, health: float = 1000.0):
		name = boss_name
		max_health = health
		current_health = health
	
	func take_damage(amount: float, source: Node = null) -> float:
		if is_invulnerable:
			return 0.0
		
		var actual_damage = max(0, amount - defense)
		current_health -= actual_damage
		
		if source:
			add_threat(source, actual_damage)
		
		return actual_damage
	
	func heal(amount: float):
		current_health = min(current_health + amount, max_health)
	
	func add_threat(source: Node, amount: float):
		if not source in threat_list:
			threat_list[source] = 0.0
		threat_list[source] += amount
	
	func get_highest_threat_target() -> Node:
		var highest_threat = 0.0
		var highest_target = null
		
		for target in threat_list:
			if threat_list[target] > highest_threat:
				highest_threat = threat_list[target]
				highest_target = target
		
		return highest_target
	
	func get_health_percentage() -> float:
		return (current_health / max_health) * 100.0

class BossPhase:
	var phase_number: int = 0
	var health_threshold: float = 100.0
	var abilities: Array = []
	var movement_speed: float = 1.0
	var damage_multiplier: float = 1.0
	var defense_bonus: float = 0.0
	var special_mechanics: Dictionary = {}
	var transition_dialogue: String = ""
	var environmental_changes: Array = []
	
	func _init(num: int, threshold: float = 100.0):
		phase_number = num
		health_threshold = threshold

class BossAbility:
	var name: String = ""
	var damage: float = 0.0
	var cooldown: float = 5.0
	var cast_time: float = 1.0
	var range: float = 10.0
	var area_of_effect: float = 0.0
	var pattern_type: String = "single_target"
	var warning_time: float = 1.5
	var animation_name: String = ""
	var effects: Array = []
	var targeting_type: String = "highest_threat"
	var current_cooldown: float = 0.0
	
	func _init(ability_name: String):
		name = ability_name
	
	func can_use() -> bool:
		return current_cooldown <= 0.0
	
	func use():
		current_cooldown = cooldown
	
	func update_cooldown(delta: float):
		if current_cooldown > 0:
			current_cooldown -= delta

class MeleeSwipe extends BossAbility:
	func _init()._init("Melee Swipe"):
		damage = 150.0
		cooldown = 3.0
		cast_time = 0.5
		range = 5.0
		area_of_effect = 3.0
		pattern_type = "cone"
		warning_time = 0.5

class GroundSlam extends BossAbility:
	func _init()._init("Ground Slam"):
		damage = 200.0
		cooldown = 8.0
		cast_time = 1.5
		range = 0.0
		area_of_effect = 15.0
		pattern_type = "circle"
		warning_time = 1.5
		effects = ["knockback", "stun"]

class FireBreath extends BossAbility:
	func _init()._init("Fire Breath"):
		damage = 100.0
		cooldown = 10.0
		cast_time = 2.0
		range = 20.0
		area_of_effect = 5.0
		pattern_type = "line"
		warning_time = 2.0
		effects = ["burn"]

class SummonMinions extends BossAbility:
	var minion_count: int = 3
	var minion_type: String = "basic"
	
	func _init()._init("Summon Minions"):
		damage = 0.0
		cooldown = 20.0
		cast_time = 3.0
		pattern_type = "summon"
		warning_time = 2.0

class ChargeAttack extends BossAbility:
	var charge_speed: float = 30.0
	var charge_distance: float = 25.0
	
	func _init()._init("Charge Attack"):
		damage = 250.0
		cooldown = 12.0
		cast_time = 2.0
		pattern_type = "charge"
		warning_time = 2.0
		effects = ["knockdown"]

class AoEExplosion extends BossAbility:
	var explosion_count: int = 5
	var explosion_delay: float = 0.5
	
	func _init()._init("AoE Explosion"):
		damage = 150.0
		cooldown = 15.0
		cast_time = 1.0
		area_of_effect = 8.0
		pattern_type = "random_areas"
		warning_time = 1.0

class Teleport extends BossAbility:
	var teleport_positions: Array = []
	
	func _init()._init("Teleport"):
		damage = 0.0
		cooldown = 10.0
		cast_time = 0.5
		pattern_type = "movement"

class ShieldWall extends BossAbility:
	var shield_duration: float = 5.0
	var damage_reduction: float = 0.8
	
	func _init()._init("Shield Wall"):
		damage = 0.0
		cooldown = 30.0
		cast_time = 1.0
		pattern_type = "defensive"
		effects = ["damage_reduction"]

class EnrageMode extends BossAbility:
	var enrage_duration: float = 20.0
	var damage_increase: float = 2.0
	var speed_increase: float = 1.5
	
	func _init()._init("Enrage"):
		damage = 0.0
		cooldown = 60.0
		cast_time = 2.0
		pattern_type = "buff"
		effects = ["enrage"]

func _ready():
	set_process(false)
	if save_boss_progress:
		load_battle_progress()

func create_boss(boss_name: String, config: Dictionary = {}) -> Boss:
	var boss = Boss.new(boss_name, config.get("health", 1000.0))
	boss.defense = config.get("defense", 10.0)
	
	setup_boss_phases(boss, config.get("phases", []))
	setup_boss_abilities(boss, config.get("abilities", []))
	
	return boss

func setup_boss_phases(boss: Boss, phase_configs: Array):
	if phase_configs.empty():
		var default_phase = BossPhase.new(0, 100.0)
		boss.phases.append(default_phase)
		return
	
	for i in range(phase_configs.size()):
		var config = phase_configs[i]
		var phase = BossPhase.new(i, config.get("health_threshold", 100.0))
		phase.abilities = config.get("abilities", [])
		phase.movement_speed = config.get("movement_speed", 1.0)
		phase.damage_multiplier = config.get("damage_multiplier", 1.0)
		phase.defense_bonus = config.get("defense_bonus", 0.0)
		phase.special_mechanics = config.get("special_mechanics", {})
		phase.transition_dialogue = config.get("transition_dialogue", "")
		phase.environmental_changes = config.get("environmental_changes", [])
		boss.phases.append(phase)

func setup_boss_abilities(boss: Boss, ability_names: Array):
	if ability_names.empty():
		boss.abilities["melee"] = MeleeSwipe.new()
		boss.abilities["slam"] = GroundSlam.new()
		return
	
	for ability_name in ability_names:
		match ability_name:
			"melee_swipe":
				boss.abilities[ability_name] = MeleeSwipe.new()
			"ground_slam":
				boss.abilities[ability_name] = GroundSlam.new()
			"fire_breath":
				boss.abilities[ability_name] = FireBreath.new()
			"summon_minions":
				boss.abilities[ability_name] = SummonMinions.new()
			"charge":
				boss.abilities[ability_name] = ChargeAttack.new()
			"aoe_explosion":
				boss.abilities[ability_name] = AoEExplosion.new()
			"teleport":
				boss.abilities[ability_name] = Teleport.new()
			"shield_wall":
				boss.abilities[ability_name] = ShieldWall.new()
			"enrage":
				boss.abilities[ability_name] = EnrageMode.new()

func start_boss_battle(boss: Boss, player_node: Node = null):
	if is_battle_active:
		return
	
	active_boss = boss
	is_battle_active = true
	battle_timer = 0.0
	player_deaths = 0
	damage_dealt = 0.0
	damage_taken = 0.0
	
	if player_node:
		boss.target = player_node
		boss.add_threat(player_node, 1.0)
	
	emit_signal("boss_spawned", boss)
	set_process(true)

func end_boss_battle(victory: bool = true):
	is_battle_active = false
	set_process(false)
	
	if victory and active_boss:
		emit_signal("boss_defeated", active_boss)
		if save_boss_progress:
			save_battle_progress()
	
	active_boss = null

func damage_boss(damage: float, source: Node = null):
	if not active_boss or not is_battle_active:
		return
	
	var actual_damage = active_boss.take_damage(damage, source)
	damage_dealt += actual_damage
	
	check_phase_transition()
	
	if active_boss.current_health <= 0:
		end_boss_battle(true)

func get_boss_health_percentage() -> float:
	if active_boss:
		return active_boss.get_health_percentage()
	return 0.0

func check_phase_transition():
	if not enable_phase_transitions or not active_boss:
		return
	
	var health_percent = active_boss.get_health_percentage()
	var current_phase = active_boss.current_phase
	
	for i in range(active_boss.phases.size()):
		var phase = active_boss.phases[i]
		if i > current_phase and health_percent <= phase.health_threshold:
			transition_to_phase(i)
			break

func transition_to_phase(phase_index: int):
	if not active_boss or phase_index >= active_boss.phases.size():
		return
	
	var old_phase = active_boss.current_phase
	active_boss.current_phase = phase_index
	var new_phase = active_boss.phases[phase_index]
	
	active_boss.defense += new_phase.defense_bonus
	
	if new_phase.transition_dialogue != "":
		display_boss_dialogue(new_phase.transition_dialogue)
	
	for change in new_phase.environmental_changes:
		apply_environmental_change(change)
	
	emit_signal("boss_phase_changed", active_boss, phase_index)

func use_boss_ability(ability_name: String):
	if not active_boss or not is_battle_active:
		return
	
	if not ability_name in active_boss.abilities:
		return
	
	var ability = active_boss.abilities[ability_name]
	if not ability.can_use():
		return
	
	if ability.warning_time > 0:
		show_ability_warning(ability)
		yield(get_tree().create_timer(ability.warning_time), "timeout")
	
	ability.use()
	execute_ability(ability)
	emit_signal("boss_ability_used", active_boss, ability_name)

func execute_ability(ability: BossAbility):
	match ability.pattern_type:
		"single_target":
			execute_single_target_ability(ability)
		"cone":
			execute_cone_ability(ability)
		"circle":
			execute_circle_ability(ability)
		"line":
			execute_line_ability(ability)
		"summon":
			execute_summon_ability(ability)
		"charge":
			execute_charge_ability(ability)
		"random_areas":
			execute_random_area_ability(ability)
		"movement":
			execute_movement_ability(ability)
		"defensive":
			execute_defensive_ability(ability)
		"buff":
			execute_buff_ability(ability)

func execute_single_target_ability(ability: BossAbility):
	if active_boss.target:
		var distance = active_boss.position.distance_to(active_boss.target.global_transform.origin)
		if distance <= ability.range:
			deal_damage_to_target(active_boss.target, ability.damage)

func execute_cone_ability(ability: BossAbility):
	emit_signal("player_warning", "cone", active_boss.position)

func execute_circle_ability(ability: BossAbility):
	emit_signal("player_warning", "circle", active_boss.position)

func execute_line_ability(ability: BossAbility):
	if active_boss.target:
		var direction = (active_boss.target.global_transform.origin - active_boss.position).normalized()
		emit_signal("player_warning", "line", active_boss.position)

func execute_summon_ability(ability: BossAbility):
	if ability is SummonMinions:
		for i in range(ability.minion_count):
			spawn_minion(ability.minion_type)

func execute_charge_ability(ability: BossAbility):
	if active_boss.target and ability is ChargeAttack:
		var direction = (active_boss.target.global_transform.origin - active_boss.position).normalized()
		emit_signal("player_warning", "charge", active_boss.position)

func execute_random_area_ability(ability: BossAbility):
	if ability is AoEExplosion:
		for i in range(ability.explosion_count):
			var random_pos = arena_bounds.position + Vector3(
				randf() * arena_bounds.size.x,
				0,
				randf() * arena_bounds.size.z
			)
			emit_signal("player_warning", "explosion", random_pos)
			yield(get_tree().create_timer(ability.explosion_delay), "timeout")

func execute_movement_ability(ability: BossAbility):
	if ability is Teleport and not ability.teleport_positions.empty():
		var new_pos = ability.teleport_positions[randi() % ability.teleport_positions.size()]
		active_boss.position = new_pos

func execute_defensive_ability(ability: BossAbility):
	if ability is ShieldWall:
		active_boss.is_invulnerable = true
		yield(get_tree().create_timer(ability.shield_duration), "timeout")
		active_boss.is_invulnerable = false

func execute_buff_ability(ability: BossAbility):
	if ability is EnrageMode:
		active_boss.is_enraged = true
		emit_signal("boss_enraged", active_boss)

func show_ability_warning(ability: BossAbility):
	var warning_type = ability.pattern_type
	var warning_position = active_boss.position
	
	if active_boss.target and ability.targeting_type == "player_position":
		warning_position = active_boss.target.global_transform.origin
	
	emit_signal("player_warning", warning_type, warning_position)

func deal_damage_to_target(target: Node, damage: float):
	if target.has_method("take_damage"):
		var actual_damage = target.take_damage(damage)
		damage_taken += actual_damage

func spawn_minion(minion_type: String):
	pass

func display_boss_dialogue(dialogue: String):
	pass

func apply_environmental_change(change: Dictionary):
	pass

func _process(delta):
	if not is_battle_active or not active_boss:
		return
	
	battle_timer += delta
	
	for ability in active_boss.abilities.values():
		ability.update_cooldown(delta)
	
	if enable_enrage_timer and battle_timer >= enrage_time and not active_boss.is_enraged:
		active_boss.is_enraged = true
		emit_signal("boss_enraged", active_boss)
	
	update_boss_ai(delta)

func update_boss_ai(delta: float):
	if not active_boss.target:
		active_boss.target = active_boss.get_highest_threat_target()
		if not active_boss.target:
			return
	
	var current_phase = active_boss.phases[active_boss.current_phase]
	var available_abilities = []
	
	for ability_name in active_boss.abilities:
		var ability = active_boss.abilities[ability_name]
		if ability.can_use() and (current_phase.abilities.empty() or ability_name in current_phase.abilities):
			available_abilities.append(ability_name)
	
	if not available_abilities.empty():
		var chosen_ability = available_abilities[randi() % available_abilities.size()]
		use_boss_ability(chosen_ability)

func get_battle_stats() -> Dictionary:
	return {
		"duration": battle_timer,
		"damage_dealt": damage_dealt,
		"damage_taken": damage_taken,
		"player_deaths": player_deaths,
		"boss_health_remaining": active_boss.current_health if active_boss else 0
	}

func save_battle_progress():
	var save_file = File.new()
	save_file.open("user://boss_battles.save", File.WRITE)
	
	var save_data = {
		"last_battle_stats": get_battle_stats(),
		"defeated_bosses": []
	}
	
	save_file.store_string(to_json(save_data))
	save_file.close()

func load_battle_progress():
	var save_file = File.new()
	if not save_file.file_exists("user://boss_battles.save"):
		return
	
	save_file.open("user://boss_battles.save", File.READ)
	var save_data = parse_json(save_file.get_as_text())
	save_file.close()