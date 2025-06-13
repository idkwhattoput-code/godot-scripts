extends Node

signal crafting_started(recipe_id, duration)
signal crafting_completed(recipe_id, result)
signal crafting_failed(recipe_id, reason)
signal recipe_unlocked(recipe_id)
signal crafting_level_up(profession, new_level)

enum CraftingProfession {
	BLACKSMITHING,
	ALCHEMY,
	ENCHANTING,
	COOKING,
	TAILORING,
	ENGINEERING
}

enum ItemQuality {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY
}

var recipes = {}
var unlocked_recipes = {}
var crafting_queue = []
var active_craft = null
var profession_levels = {}
var profession_experience = {}

var crafting_config = {
	"max_queue_size": 10,
	"base_craft_time": 3.0,
	"quality_chance_bonus": 0.1,
	"experience_per_craft": 10,
	"level_requirements": [0, 100, 300, 600, 1000, 1500, 2100, 2800, 3600, 4500]
}

func _ready():
	set_process(true)
	_initialize_professions()
	_register_default_recipes()

func _initialize_professions():
	for profession in CraftingProfession.values():
		profession_levels[profession] = 1
		profession_experience[profession] = 0
		unlocked_recipes[profession] = []

func _register_default_recipes():
	register_recipe("iron_sword", {
		"name": "Iron Sword",
		"profession": CraftingProfession.BLACKSMITHING,
		"level_required": 1,
		"ingredients": [
			{"id": "iron_ingot", "amount": 3},
			{"id": "leather_strip", "amount": 1}
		],
		"result": {
			"id": "iron_sword",
			"amount": 1,
			"quality": ItemQuality.COMMON
		},
		"craft_time": 5.0,
		"experience": 15
	})
	
	register_recipe("health_potion", {
		"name": "Health Potion",
		"profession": CraftingProfession.ALCHEMY,
		"level_required": 1,
		"ingredients": [
			{"id": "red_herb", "amount": 2},
			{"id": "water", "amount": 1}
		],
		"result": {
			"id": "health_potion",
			"amount": 3,
			"quality": ItemQuality.COMMON
		},
		"craft_time": 2.0,
		"experience": 10
	})
	
	register_recipe("enchant_weapon_fire", {
		"name": "Fire Weapon Enchantment",
		"profession": CraftingProfession.ENCHANTING,
		"level_required": 3,
		"ingredients": [
			{"id": "fire_essence", "amount": 1},
			{"id": "enchanting_dust", "amount": 3}
		],
		"result": {
			"id": "fire_enchantment",
			"amount": 1,
			"quality": ItemQuality.UNCOMMON
		},
		"craft_time": 8.0,
		"experience": 25
	})
	
	register_recipe("steel_plate_armor", {
		"name": "Steel Plate Armor",
		"profession": CraftingProfession.BLACKSMITHING,
		"level_required": 5,
		"ingredients": [
			{"id": "steel_ingot", "amount": 8},
			{"id": "leather", "amount": 4},
			{"id": "iron_buckle", "amount": 2}
		],
		"result": {
			"id": "steel_plate_armor",
			"amount": 1,
			"quality": ItemQuality.RARE
		},
		"craft_time": 15.0,
		"experience": 50,
		"can_crit": true
	})
	
	register_recipe("explosive_bomb", {
		"name": "Explosive Bomb",
		"profession": CraftingProfession.ENGINEERING,
		"level_required": 2,
		"ingredients": [
			{"id": "gunpowder", "amount": 3},
			{"id": "iron_casing", "amount": 1},
			{"id": "fuse", "amount": 1}
		],
		"result": {
			"id": "explosive_bomb",
			"amount": 5,
			"quality": ItemQuality.COMMON
		},
		"craft_time": 4.0,
		"experience": 20
	})

func register_recipe(recipe_id, data):
	recipes[recipe_id] = data

func unlock_recipe(recipe_id):
	if not recipes.has(recipe_id):
		return false
	
	var recipe = recipes[recipe_id]
	var profession = recipe.profession
	
	if not unlocked_recipes[profession].has(recipe_id):
		unlocked_recipes[profession].append(recipe_id)
		emit_signal("recipe_unlocked", recipe_id)
		return true
	
	return false

func can_craft(recipe_id, inventory):
	if not recipes.has(recipe_id):
		return false
	
	var recipe = recipes[recipe_id]
	
	if profession_levels[recipe.profession] < recipe.level_required:
		return false
	
	if not unlocked_recipes[recipe.profession].has(recipe_id):
		return false
	
	for ingredient in recipe.ingredients:
		if not _has_ingredient(inventory, ingredient.id, ingredient.amount):
			return false
	
	return true

func start_crafting(recipe_id, inventory):
	if not can_craft(recipe_id, inventory):
		emit_signal("crafting_failed", recipe_id, "requirements_not_met")
		return false
	
	if active_craft != null:
		if crafting_queue.size() >= crafting_config.max_queue_size:
			emit_signal("crafting_failed", recipe_id, "queue_full")
			return false
		
		crafting_queue.append(recipe_id)
		return true
	
	var recipe = recipes[recipe_id]
	
	for ingredient in recipe.ingredients:
		_consume_ingredient(inventory, ingredient.id, ingredient.amount)
	
	active_craft = {
		"recipe_id": recipe_id,
		"time_remaining": recipe.craft_time,
		"inventory": inventory
	}
	
	emit_signal("crafting_started", recipe_id, recipe.craft_time)
	return true

func cancel_crafting():
	if active_craft == null:
		return false
	
	var recipe = recipes[active_craft.recipe_id]
	
	for ingredient in recipe.ingredients:
		_return_ingredient(active_craft.inventory, ingredient.id, ingredient.amount)
	
	emit_signal("crafting_failed", active_craft.recipe_id, "cancelled")
	active_craft = null
	
	_process_queue()
	return true

func _process(delta):
	if active_craft == null:
		return
	
	active_craft.time_remaining -= delta
	
	if active_craft.time_remaining <= 0:
		_complete_crafting()

func _complete_crafting():
	var recipe_id = active_craft.recipe_id
	var recipe = recipes[recipe_id]
	var inventory = active_craft.inventory
	
	var result = _generate_result(recipe)
	
	_add_to_inventory(inventory, result.id, result.amount)
	
	_grant_experience(recipe.profession, recipe.experience)
	
	emit_signal("crafting_completed", recipe_id, result)
	
	active_craft = null
	_process_queue()

func _generate_result(recipe):
	var result = recipe.result.duplicate()
	
	var profession_level = profession_levels[recipe.profession]
	var quality_bonus = profession_level * crafting_config.quality_chance_bonus
	
	if recipe.get("can_crit", false) and randf() < quality_bonus:
		result.quality = min(result.quality + 1, ItemQuality.LEGENDARY)
		result.amount = int(result.amount * 1.5)
	
	if randf() < quality_bonus * 0.5:
		result.amount += randi() % 2 + 1
	
	return result

func _grant_experience(profession, amount):
	profession_experience[profession] += amount
	
	var current_level = profession_levels[profession]
	var next_level_xp = _get_experience_for_level(current_level + 1)
	
	if profession_experience[profession] >= next_level_xp:
		profession_levels[profession] += 1
		emit_signal("crafting_level_up", profession, profession_levels[profession])
		_check_new_recipes(profession)

func _get_experience_for_level(level):
	if level <= 0 or level > crafting_config.level_requirements.size():
		return 999999
	
	return crafting_config.level_requirements[level - 1]

func _check_new_recipes(profession):
	var new_level = profession_levels[profession]
	
	for recipe_id in recipes:
		var recipe = recipes[recipe_id]
		if recipe.profession == profession and recipe.level_required == new_level:
			unlock_recipe(recipe_id)

func _process_queue():
	if crafting_queue.size() == 0:
		return
	
	var next_recipe = crafting_queue.pop_front()
	start_crafting(next_recipe, null)

func _has_ingredient(inventory, item_id, amount):
	return true

func _consume_ingredient(inventory, item_id, amount):
	pass

func _return_ingredient(inventory, item_id, amount):
	pass

func _add_to_inventory(inventory, item_id, amount):
	pass

func get_recipe_info(recipe_id):
	if not recipes.has(recipe_id):
		return null
	
	var recipe = recipes[recipe_id]
	return {
		"name": recipe.name,
		"profession": recipe.profession,
		"level_required": recipe.level_required,
		"ingredients": recipe.ingredients,
		"result": recipe.result,
		"craft_time": recipe.craft_time,
		"unlocked": unlocked_recipes[recipe.profession].has(recipe_id),
		"can_craft": can_craft(recipe_id, null)
	}

func get_profession_info(profession):
	return {
		"level": profession_levels[profession],
		"experience": profession_experience[profession],
		"next_level_xp": _get_experience_for_level(profession_levels[profession] + 1),
		"unlocked_recipes": unlocked_recipes[profession].size()
	}

func get_recipes_for_profession(profession):
	var profession_recipes = []
	
	for recipe_id in recipes:
		var recipe = recipes[recipe_id]
		if recipe.profession == profession:
			profession_recipes.append({
				"id": recipe_id,
				"name": recipe.name,
				"level_required": recipe.level_required,
				"unlocked": unlocked_recipes[profession].has(recipe_id)
			})
	
	return profession_recipes

func get_crafting_progress():
	if active_craft == null:
		return 0.0
	
	var recipe = recipes[active_craft.recipe_id]
	return 1.0 - (active_craft.time_remaining / recipe.craft_time)

func get_queue_size():
	return crafting_queue.size()