extends Node

class_name CharacterStats

signal health_changed(new_health, max_health)
signal mana_changed(new_mana, max_mana)
signal stamina_changed(new_stamina, max_stamina)
signal level_up(new_level)
signal stat_changed(stat_name, new_value)
signal died()

export var character_name: String = "Player"
export var character_class: String = "Warrior"
export var level: int = 1
export var experience: int = 0
export var experience_to_next_level: int = 100

export var max_health: float = 100.0
export var current_health: float = 100.0
export var health_regen_rate: float = 1.0

export var max_mana: float = 50.0
export var current_mana: float = 50.0
export var mana_regen_rate: float = 2.0

export var max_stamina: float = 100.0
export var current_stamina: float = 100.0
export var stamina_regen_rate: float = 10.0

export var strength: int = 10
export var dexterity: int = 10
export var intelligence: int = 10
export var vitality: int = 10
export var luck: int = 5

export var attack_power: float = 0.0
export var defense: float = 0.0
export var magic_power: float = 0.0
export var crit_chance: float = 5.0
export var crit_damage: float = 150.0
export var move_speed_multiplier: float = 1.0

export var stat_points: int = 0
export var skill_points: int = 0

var status_effects: Dictionary = {}
var is_dead: bool = false

func _ready():
	calculate_derived_stats()
	set_process(true)

func _process(delta):
	if not is_dead:
		regenerate_resources(delta)
		process_status_effects(delta)

func regenerate_resources(delta):
	if current_health < max_health:
		modify_health(health_regen_rate * delta)
	
	if current_mana < max_mana:
		modify_mana(mana_regen_rate * delta)
	
	if current_stamina < max_stamina:
		modify_stamina(stamina_regen_rate * delta)

func modify_health(amount: float):
	var old_health = current_health
	current_health = clamp(current_health + amount, 0, max_health)
	
	if current_health != old_health:
		emit_signal("health_changed", current_health, max_health)
	
	if current_health <= 0 and not is_dead:
		die()

func modify_mana(amount: float):
	var old_mana = current_mana
	current_mana = clamp(current_mana + amount, 0, max_mana)
	
	if current_mana != old_mana:
		emit_signal("mana_changed", current_mana, max_mana)

func modify_stamina(amount: float):
	var old_stamina = current_stamina
	current_stamina = clamp(current_stamina + amount, 0, max_stamina)
	
	if current_stamina != old_stamina:
		emit_signal("stamina_changed", current_stamina, max_stamina)

func take_damage(damage: float, damage_type: String = "physical"):
	if is_dead:
		return
	
	var final_damage = calculate_damage_taken(damage, damage_type)
	modify_health(-final_damage)
	
	return final_damage

func calculate_damage_taken(damage: float, damage_type: String) -> float:
	var final_damage = damage
	
	if damage_type == "physical":
		final_damage -= defense
	elif damage_type == "magical":
		final_damage *= (100.0 - get_magic_resistance()) / 100.0
	
	final_damage = max(1.0, final_damage)
	
	return final_damage

func heal(amount: float):
	modify_health(amount)

func restore_mana(amount: float):
	modify_mana(amount)

func restore_stamina(amount: float):
	modify_stamina(amount)

func use_mana(amount: float) -> bool:
	if current_mana >= amount:
		modify_mana(-amount)
		return true
	return false

func use_stamina(amount: float) -> bool:
	if current_stamina >= amount:
		modify_stamina(-amount)
		return true
	return false

func add_experience(amount: int):
	experience += amount
	
	while experience >= experience_to_next_level:
		level_up()

func level_up():
	experience -= experience_to_next_level
	level += 1
	stat_points += 5
	skill_points += 1
	
	experience_to_next_level = calculate_exp_to_next_level(level)
	
	max_health += vitality * 5
	max_mana += intelligence * 3
	max_stamina += vitality * 2
	
	current_health = max_health
	current_mana = max_mana
	current_stamina = max_stamina
	
	calculate_derived_stats()
	emit_signal("level_up", level)

func calculate_exp_to_next_level(lvl: int) -> int:
	return int(100 * pow(1.5, lvl - 1))

func increase_stat(stat_name: String):
	if stat_points <= 0:
		return
	
	stat_points -= 1
	
	match stat_name:
		"strength":
			strength += 1
		"dexterity":
			dexterity += 1
		"intelligence":
			intelligence += 1
		"vitality":
			vitality += 1
		"luck":
			luck += 1
	
	calculate_derived_stats()
	emit_signal("stat_changed", stat_name, get(stat_name))

func calculate_derived_stats():
	attack_power = strength * 2.0 + dexterity * 0.5
	defense = vitality * 1.5 + strength * 0.5
	magic_power = intelligence * 2.5
	crit_chance = 5.0 + luck * 0.5 + dexterity * 0.2
	crit_damage = 150.0 + luck * 2.0
	move_speed_multiplier = 1.0 + (dexterity * 0.002)
	
	health_regen_rate = 1.0 + vitality * 0.2
	mana_regen_rate = 2.0 + intelligence * 0.3
	stamina_regen_rate = 10.0 + vitality * 0.5

func add_status_effect(effect_name: String, duration: float, effect_data: Dictionary = {}):
	status_effects[effect_name] = {
		"duration": duration,
		"data": effect_data,
		"timer": 0.0
	}

func remove_status_effect(effect_name: String):
	if effect_name in status_effects:
		status_effects.erase(effect_name)

func has_status_effect(effect_name: String) -> bool:
	return effect_name in status_effects

func process_status_effects(delta):
	var effects_to_remove = []
	
	for effect_name in status_effects:
		var effect = status_effects[effect_name]
		effect.timer += delta
		
		if effect.timer >= effect.duration:
			effects_to_remove.append(effect_name)
		else:
			apply_status_effect(effect_name, effect.data, delta)
	
	for effect_name in effects_to_remove:
		remove_status_effect(effect_name)

func apply_status_effect(effect_name: String, effect_data: Dictionary, delta):
	match effect_name:
		"poison":
			var damage_per_second = effect_data.get("damage_per_second", 5.0)
			take_damage(damage_per_second * delta, "poison")
		"burn":
			var damage_per_second = effect_data.get("damage_per_second", 10.0)
			take_damage(damage_per_second * delta, "fire")
		"regeneration":
			var heal_per_second = effect_data.get("heal_per_second", 10.0)
			heal(heal_per_second * delta)
		"slow":
			move_speed_multiplier = effect_data.get("speed_multiplier", 0.5)

func get_magic_resistance() -> float:
	return intelligence * 0.5 + vitality * 0.3

func die():
	is_dead = true
	emit_signal("died")

func revive(health_percent: float = 0.5):
	is_dead = false
	current_health = max_health * health_percent
	emit_signal("health_changed", current_health, max_health)

func save_data() -> Dictionary:
	return {
		"character_name": character_name,
		"character_class": character_class,
		"level": level,
		"experience": experience,
		"current_health": current_health,
		"current_mana": current_mana,
		"current_stamina": current_stamina,
		"strength": strength,
		"dexterity": dexterity,
		"intelligence": intelligence,
		"vitality": vitality,
		"luck": luck,
		"stat_points": stat_points,
		"skill_points": skill_points
	}

func load_data(data: Dictionary):
	character_name = data.get("character_name", character_name)
	character_class = data.get("character_class", character_class)
	level = data.get("level", level)
	experience = data.get("experience", experience)
	current_health = data.get("current_health", current_health)
	current_mana = data.get("current_mana", current_mana)
	current_stamina = data.get("current_stamina", current_stamina)
	strength = data.get("strength", strength)
	dexterity = data.get("dexterity", dexterity)
	intelligence = data.get("intelligence", intelligence)
	vitality = data.get("vitality", vitality)
	luck = data.get("luck", luck)
	stat_points = data.get("stat_points", stat_points)
	skill_points = data.get("skill_points", skill_points)
	
	calculate_derived_stats()