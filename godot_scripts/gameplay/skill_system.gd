extends Node

export var max_skill_points = 100
export var level_cap = 50
export var skills_per_level = 1

var available_skill_points = 0
var player_level = 1
var unlocked_skills = {}
var skill_cooldowns = {}
var skill_tree = {}

signal skill_unlocked(skill_id)
signal skill_upgraded(skill_id, level)
signal skill_used(skill_id)
signal skill_points_changed(points)
signal level_up(level)

class Skill:
	var id = ""
	var name = ""
	var description = ""
	var icon_path = ""
	var max_level = 5
	var current_level = 0
	var skill_point_cost = 1
	var prerequisites = []
	var type = "active"
	var cooldown = 0.0
	var mana_cost = 0.0
	var effects = {}
	
	func _init(skill_id: String, skill_name: String):
		id = skill_id
		name = skill_name
	
	func can_unlock(available_points: int, unlocked_skills: Dictionary) -> bool:
		if current_level >= max_level:
			return false
		
		if available_points < skill_point_cost:
			return false
		
		for prereq in prerequisites:
			if not unlocked_skills.has(prereq):
				return false
		
		return true
	
	func get_effect_value(effect_name: String) -> float:
		if effects.has(effect_name):
			var base_value = effects[effect_name].base_value
			var per_level = effects[effect_name].per_level
			return base_value + (per_level * current_level)
		return 0.0

class SkillEffect:
	var base_value = 0.0
	var per_level = 0.0
	var type = ""
	
	func _init(effect_type: String, base: float, increment: float):
		type = effect_type
		base_value = base
		per_level = increment

func _ready():
	_initialize_skill_tree()
	_load_player_skills()

func _initialize_skill_tree():
	var fireball = Skill.new("fireball", "Fireball")
	fireball.description = "Launch a fireball at your enemies"
	fireball.max_level = 10
	fireball.skill_point_cost = 1
	fireball.cooldown = 2.0
	fireball.mana_cost = 20.0
	fireball.effects["damage"] = SkillEffect.new("damage", 50.0, 10.0)
	fireball.effects["burn_duration"] = SkillEffect.new("duration", 2.0, 0.5)
	skill_tree["fireball"] = fireball
	
	var frost_armor = Skill.new("frost_armor", "Frost Armor")
	frost_armor.description = "Surround yourself with protective ice"
	frost_armor.max_level = 5
	frost_armor.skill_point_cost = 2
	frost_armor.type = "passive"
	frost_armor.effects["defense"] = SkillEffect.new("defense", 10.0, 5.0)
	frost_armor.effects["slow_chance"] = SkillEffect.new("chance", 0.1, 0.05)
	skill_tree["frost_armor"] = frost_armor
	
	var meteor = Skill.new("meteor", "Meteor Strike")
	meteor.description = "Call down a devastating meteor"
	meteor.max_level = 3
	meteor.skill_point_cost = 3
	meteor.prerequisites = ["fireball"]
	meteor.cooldown = 30.0
	meteor.mana_cost = 100.0
	meteor.effects["damage"] = SkillEffect.new("damage", 200.0, 50.0)
	meteor.effects["radius"] = SkillEffect.new("radius", 5.0, 1.0)
	skill_tree["meteor"] = meteor
	
	var teleport = Skill.new("teleport", "Teleport")
	teleport.description = "Instantly teleport a short distance"
	teleport.max_level = 5
	teleport.skill_point_cost = 1
	teleport.cooldown = 10.0
	teleport.mana_cost = 30.0
	teleport.effects["distance"] = SkillEffect.new("distance", 10.0, 2.0)
	skill_tree["teleport"] = teleport
	
	var healing_aura = Skill.new("healing_aura", "Healing Aura")
	healing_aura.description = "Emit a healing aura that restores health"
	healing_aura.max_level = 5
	healing_aura.skill_point_cost = 2
	healing_aura.type = "toggle"
	healing_aura.mana_cost = 5.0
	healing_aura.effects["heal_per_second"] = SkillEffect.new("heal", 5.0, 2.0)
	healing_aura.effects["radius"] = SkillEffect.new("radius", 5.0, 1.0)
	skill_tree["healing_aura"] = healing_aura

func unlock_skill(skill_id: String) -> bool:
	if not skill_tree.has(skill_id):
		return false
	
	var skill = skill_tree[skill_id]
	
	if not skill.can_unlock(available_skill_points, unlocked_skills):
		return false
	
	if not unlocked_skills.has(skill_id):
		unlocked_skills[skill_id] = skill
		skill.current_level = 1
	else:
		skill.current_level += 1
	
	available_skill_points -= skill.skill_point_cost
	
	if skill.current_level == 1:
		emit_signal("skill_unlocked", skill_id)
	else:
		emit_signal("skill_upgraded", skill_id, skill.current_level)
	
	emit_signal("skill_points_changed", available_skill_points)
	
	return true

func use_skill(skill_id: String, target_position: Vector3 = Vector3.ZERO) -> bool:
	if not unlocked_skills.has(skill_id):
		return false
	
	var skill = unlocked_skills[skill_id]
	
	if skill.type == "passive":
		return false
	
	if is_skill_on_cooldown(skill_id):
		return false
	
	if not _has_enough_mana(skill.mana_cost):
		return false
	
	_apply_skill_effects(skill, target_position)
	
	_consume_mana(skill.mana_cost)
	
	_start_cooldown(skill_id, skill.cooldown)
	
	emit_signal("skill_used", skill_id)
	
	return true

func is_skill_on_cooldown(skill_id: String) -> bool:
	return skill_cooldowns.has(skill_id) and skill_cooldowns[skill_id] > 0

func get_cooldown_remaining(skill_id: String) -> float:
	if skill_cooldowns.has(skill_id):
		return skill_cooldowns[skill_id]
	return 0.0

func get_skill_info(skill_id: String) -> Dictionary:
	if not skill_tree.has(skill_id):
		return {}
	
	var skill = skill_tree[skill_id]
	var info = {
		"name": skill.name,
		"description": skill.description,
		"current_level": skill.current_level,
		"max_level": skill.max_level,
		"is_unlocked": unlocked_skills.has(skill_id),
		"can_unlock": skill.can_unlock(available_skill_points, unlocked_skills),
		"cost": skill.skill_point_cost,
		"type": skill.type,
		"effects": {}
	}
	
	for effect_name in skill.effects:
		info.effects[effect_name] = skill.get_effect_value(effect_name)
	
	return info

func get_all_skills() -> Array:
	var skills = []
	for skill_id in skill_tree:
		skills.append(get_skill_info(skill_id))
	return skills

func level_up():
	player_level += 1
	available_skill_points += skills_per_level
	
	emit_signal("level_up", player_level)
	emit_signal("skill_points_changed", available_skill_points)

func reset_skills() -> bool:
	var total_points_spent = 0
	
	for skill_id in unlocked_skills:
		var skill = unlocked_skills[skill_id]
		total_points_spent += skill.skill_point_cost * skill.current_level
		skill.current_level = 0
	
	unlocked_skills.clear()
	skill_cooldowns.clear()
	
	available_skill_points += total_points_spent
	
	emit_signal("skill_points_changed", available_skill_points)
	
	return true

func save_skills() -> Dictionary:
	var save_data = {
		"level": player_level,
		"skill_points": available_skill_points,
		"unlocked_skills": {}
	}
	
	for skill_id in unlocked_skills:
		save_data.unlocked_skills[skill_id] = unlocked_skills[skill_id].current_level
	
	return save_data

func load_skills(save_data: Dictionary):
	if save_data.has("level"):
		player_level = save_data.level
	
	if save_data.has("skill_points"):
		available_skill_points = save_data.skill_points
	
	if save_data.has("unlocked_skills"):
		unlocked_skills.clear()
		for skill_id in save_data.unlocked_skills:
			if skill_tree.has(skill_id):
				var skill = skill_tree[skill_id]
				skill.current_level = save_data.unlocked_skills[skill_id]
				unlocked_skills[skill_id] = skill

func _process(delta):
	var cooldowns_to_remove = []
	
	for skill_id in skill_cooldowns:
		skill_cooldowns[skill_id] -= delta
		if skill_cooldowns[skill_id] <= 0:
			cooldowns_to_remove.append(skill_id)
	
	for skill_id in cooldowns_to_remove:
		skill_cooldowns.erase(skill_id)

func _apply_skill_effects(skill: Skill, target_position: Vector3):
	match skill.id:
		"fireball":
			_spawn_fireball(target_position, skill.get_effect_value("damage"))
		"meteor":
			_spawn_meteor(target_position, skill.get_effect_value("damage"), skill.get_effect_value("radius"))
		"teleport":
			_teleport_player(skill.get_effect_value("distance"))
		"healing_aura":
			_toggle_healing_aura(skill.get_effect_value("heal_per_second"), skill.get_effect_value("radius"))

func _spawn_fireball(target: Vector3, damage: float):
	pass

func _spawn_meteor(target: Vector3, damage: float, radius: float):
	pass

func _teleport_player(distance: float):
	pass

func _toggle_healing_aura(heal_amount: float, radius: float):
	pass

func _start_cooldown(skill_id: String, duration: float):
	skill_cooldowns[skill_id] = duration

func _has_enough_mana(cost: float) -> bool:
	return true

func _consume_mana(amount: float):
	pass

func _load_player_skills():
	pass