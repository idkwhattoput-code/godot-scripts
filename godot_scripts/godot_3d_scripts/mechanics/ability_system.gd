extends Node

signal ability_cast_started(ability_id, caster)
signal ability_cast_completed(ability_id, caster)
signal ability_cast_interrupted(ability_id, caster, reason)
signal ability_cooldown_started(ability_id, duration)
signal ability_cooldown_finished(ability_id)
signal ability_upgraded(ability_id, new_level)

class_name AbilitySystem

enum AbilityType {
	INSTANT,
	CHANNELED,
	TOGGLE,
	PASSIVE
}

enum TargetType {
	SELF,
	SINGLE_ENEMY,
	SINGLE_ALLY,
	POINT,
	DIRECTION,
	AREA
}

var abilities = {}
var cooldowns = {}
var active_abilities = {}
var passive_abilities = {}
var ability_queue = []
var global_cooldown = 0.0

var character_stats = {
	"mana": 100,
	"max_mana": 100,
	"ability_power": 0,
	"cooldown_reduction": 0,
	"cast_speed": 1.0
}

func _ready():
	set_process(true)
	_register_default_abilities()

func _register_default_abilities():
	register_ability("fireball", {
		"name": "Fireball",
		"type": AbilityType.INSTANT,
		"target": TargetType.SINGLE_ENEMY,
		"cast_time": 2.0,
		"cooldown": 5.0,
		"mana_cost": 20,
		"range": 30.0,
		"damage": 50,
		"description": "Launches a fireball at target enemy",
		"icon": "fireball_icon",
		"level": 1,
		"max_level": 5
	})
	
	register_ability("heal", {
		"name": "Heal",
		"type": AbilityType.INSTANT,
		"target": TargetType.SINGLE_ALLY,
		"cast_time": 1.5,
		"cooldown": 8.0,
		"mana_cost": 30,
		"range": 20.0,
		"healing": 40,
		"description": "Heals target ally",
		"icon": "heal_icon",
		"level": 1,
		"max_level": 5
	})
	
	register_ability("lightning_storm", {
		"name": "Lightning Storm",
		"type": AbilityType.CHANNELED,
		"target": TargetType.AREA,
		"cast_time": 0.5,
		"channel_time": 5.0,
		"cooldown": 30.0,
		"mana_cost": 60,
		"mana_per_second": 10,
		"range": 25.0,
		"radius": 10.0,
		"damage_per_second": 20,
		"description": "Channels a devastating lightning storm",
		"icon": "lightning_storm_icon",
		"level": 1,
		"max_level": 3
	})
	
	register_ability("shield", {
		"name": "Mana Shield",
		"type": AbilityType.TOGGLE,
		"target": TargetType.SELF,
		"cooldown": 1.0,
		"mana_per_second": 5,
		"damage_reduction": 0.5,
		"description": "Absorbs damage using mana",
		"icon": "shield_icon",
		"level": 1,
		"max_level": 5
	})
	
	register_ability("arcane_intellect", {
		"name": "Arcane Intellect",
		"type": AbilityType.PASSIVE,
		"effect": "mana_regen",
		"value": 2.0,
		"description": "Increases mana regeneration",
		"icon": "arcane_intellect_icon",
		"level": 1,
		"max_level": 5
	})

func register_ability(ability_id, data):
	abilities[ability_id] = data
	cooldowns[ability_id] = 0.0
	
	if data.type == AbilityType.PASSIVE:
		_activate_passive(ability_id)

func cast_ability(ability_id, caster, target = null):
	if not can_cast_ability(ability_id, caster):
		return false
	
	var ability = abilities[ability_id]
	
	if not _validate_target(ability, caster, target):
		return false
	
	if not _consume_resources(ability):
		return false
	
	match ability.type:
		AbilityType.INSTANT:
			_cast_instant_ability(ability_id, caster, target)
		AbilityType.CHANNELED:
			_start_channel_ability(ability_id, caster, target)
		AbilityType.TOGGLE:
			_toggle_ability(ability_id, caster)
	
	return true

func can_cast_ability(ability_id, caster):
	if not abilities.has(ability_id):
		return false
	
	if cooldowns[ability_id] > 0:
		return false
	
	if global_cooldown > 0:
		return false
	
	var ability = abilities[ability_id]
	
	if character_stats.mana < ability.get("mana_cost", 0):
		return false
	
	if active_abilities.has(ability_id) and ability.type == AbilityType.CHANNELED:
		return false
	
	return true

func _cast_instant_ability(ability_id, caster, target):
	var ability = abilities[ability_id]
	var cast_time = ability.cast_time * (1.0 / character_stats.cast_speed)
	
	emit_signal("ability_cast_started", ability_id, caster)
	
	if cast_time > 0:
		yield(get_tree().create_timer(cast_time), "timeout")
		
		if not active_abilities.has(ability_id):
			emit_signal("ability_cast_interrupted", ability_id, caster, "cancelled")
			return
	
	_apply_ability_effects(ability_id, caster, target)
	_start_cooldown(ability_id)
	
	emit_signal("ability_cast_completed", ability_id, caster)

func _start_channel_ability(ability_id, caster, target):
	var ability = abilities[ability_id]
	var cast_time = ability.cast_time * (1.0 / character_stats.cast_speed)
	
	emit_signal("ability_cast_started", ability_id, caster)
	
	if cast_time > 0:
		yield(get_tree().create_timer(cast_time), "timeout")
	
	active_abilities[ability_id] = {
		"caster": caster,
		"target": target,
		"time_remaining": ability.channel_time,
		"tick_timer": 0.0
	}

func _toggle_ability(ability_id, caster):
	if active_abilities.has(ability_id):
		active_abilities.erase(ability_id)
		_start_cooldown(ability_id)
		emit_signal("ability_cast_completed", ability_id, caster)
	else:
		active_abilities[ability_id] = {
			"caster": caster,
			"active": true
		}
		emit_signal("ability_cast_started", ability_id, caster)

func interrupt_ability(ability_id, reason = "interrupted"):
	if not active_abilities.has(ability_id):
		return
	
	var ability_data = active_abilities[ability_id]
	active_abilities.erase(ability_id)
	
	emit_signal("ability_cast_interrupted", ability_id, ability_data.caster, reason)

func _process(delta):
	_update_cooldowns(delta)
	_update_active_abilities(delta)
	_process_ability_queue()

func _update_cooldowns(delta):
	if global_cooldown > 0:
		global_cooldown = max(0, global_cooldown - delta)
	
	for ability_id in cooldowns:
		if cooldowns[ability_id] > 0:
			cooldowns[ability_id] = max(0, cooldowns[ability_id] - delta)
			
			if cooldowns[ability_id] == 0:
				emit_signal("ability_cooldown_finished", ability_id)

func _update_active_abilities(delta):
	var abilities_to_remove = []
	
	for ability_id in active_abilities:
		var ability = abilities[ability_id]
		var active_data = active_abilities[ability_id]
		
		match ability.type:
			AbilityType.CHANNELED:
				_update_channeled_ability(ability_id, delta)
			AbilityType.TOGGLE:
				_update_toggle_ability(ability_id, delta)
		
		if active_abilities.has(ability_id):
			if active_abilities[ability_id].get("time_remaining", 0) <= 0:
				abilities_to_remove.append(ability_id)
	
	for ability_id in abilities_to_remove:
		active_abilities.erase(ability_id)
		_start_cooldown(ability_id)
		emit_signal("ability_cast_completed", ability_id, null)

func _update_channeled_ability(ability_id, delta):
	var ability = abilities[ability_id]
	var active_data = active_abilities[ability_id]
	
	active_data.time_remaining -= delta
	active_data.tick_timer += delta
	
	var mana_drain = ability.get("mana_per_second", 0) * delta
	if character_stats.mana < mana_drain:
		interrupt_ability(ability_id, "no_mana")
		return
	
	character_stats.mana -= mana_drain
	
	if active_data.tick_timer >= 1.0:
		active_data.tick_timer = 0.0
		_apply_ability_effects(ability_id, active_data.caster, active_data.target)

func _update_toggle_ability(ability_id, delta):
	var ability = abilities[ability_id]
	
	var mana_drain = ability.get("mana_per_second", 0) * delta
	if character_stats.mana < mana_drain:
		interrupt_ability(ability_id, "no_mana")
		return
	
	character_stats.mana -= mana_drain

func _apply_ability_effects(ability_id, caster, target):
	var ability = abilities[ability_id]
	
	if ability.has("damage"):
		var damage = _calculate_damage(ability)
		_deal_damage(target, damage)
	
	if ability.has("healing"):
		var healing = _calculate_healing(ability)
		_apply_healing(target, healing)
	
	if ability.has("damage_per_second"):
		var dps = _calculate_damage_per_second(ability)
		_apply_area_damage(target, dps, ability.get("radius", 0))

func _calculate_damage(ability):
	var base_damage = ability.damage
	var scaling = ability.get("ability_power_scaling", 1.0)
	return base_damage + (character_stats.ability_power * scaling)

func _calculate_healing(ability):
	var base_healing = ability.healing
	var scaling = ability.get("ability_power_scaling", 0.5)
	return base_healing + (character_stats.ability_power * scaling)

func _calculate_damage_per_second(ability):
	var base_dps = ability.damage_per_second
	var scaling = ability.get("ability_power_scaling", 0.8)
	return base_dps + (character_stats.ability_power * scaling)

func _deal_damage(target, amount):
	pass

func _apply_healing(target, amount):
	pass

func _apply_area_damage(center, damage, radius):
	pass

func _start_cooldown(ability_id):
	var ability = abilities[ability_id]
	var cooldown = ability.cooldown * (1.0 - character_stats.cooldown_reduction)
	cooldowns[ability_id] = cooldown
	global_cooldown = 1.0
	
	emit_signal("ability_cooldown_started", ability_id, cooldown)

func _validate_target(ability, caster, target):
	match ability.target:
		TargetType.SELF:
			return true
		TargetType.SINGLE_ENEMY:
			return target != null and target != caster
		TargetType.SINGLE_ALLY:
			return target != null
		TargetType.POINT:
			return target is Vector3
		TargetType.DIRECTION:
			return target is Vector3
		TargetType.AREA:
			return target is Vector3
	
	return false

func _consume_resources(ability):
	var mana_cost = ability.get("mana_cost", 0)
	if character_stats.mana >= mana_cost:
		character_stats.mana -= mana_cost
		return true
	return false

func _activate_passive(ability_id):
	var ability = abilities[ability_id]
	passive_abilities[ability_id] = ability
	
	match ability.get("effect"):
		"mana_regen":
			pass
		"ability_power":
			character_stats.ability_power += ability.value
		"cooldown_reduction":
			character_stats.cooldown_reduction = min(0.4, character_stats.cooldown_reduction + ability.value)

func upgrade_ability(ability_id):
	if not abilities.has(ability_id):
		return false
	
	var ability = abilities[ability_id]
	if ability.level >= ability.max_level:
		return false
	
	ability.level += 1
	
	ability.damage = ability.get("damage", 0) * 1.2
	ability.healing = ability.get("healing", 0) * 1.2
	ability.mana_cost = ability.get("mana_cost", 0) * 0.95
	
	emit_signal("ability_upgraded", ability_id, ability.level)
	return true

func _process_ability_queue():
	if ability_queue.size() == 0:
		return
	
	var next_ability = ability_queue[0]
	if can_cast_ability(next_ability.id, next_ability.caster):
		ability_queue.pop_front()
		cast_ability(next_ability.id, next_ability.caster, next_ability.target)

func queue_ability(ability_id, caster, target = null):
	ability_queue.append({
		"id": ability_id,
		"caster": caster,
		"target": target
	})

func get_ability_info(ability_id):
	if abilities.has(ability_id):
		var ability = abilities[ability_id]
		return {
			"name": ability.name,
			"description": ability.description,
			"cooldown_remaining": cooldowns[ability_id],
			"level": ability.level,
			"mana_cost": ability.get("mana_cost", 0),
			"is_active": active_abilities.has(ability_id)
		}
	return null