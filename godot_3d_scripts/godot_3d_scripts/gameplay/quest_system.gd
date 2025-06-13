extends Node

var active_quests = {}
var completed_quests = []
var quest_database = {}

signal quest_started(quest_id)
signal quest_completed(quest_id)
signal quest_failed(quest_id)
signal objective_completed(quest_id, objective_id)
signal quest_progress_updated(quest_id, objective_id, progress)

class Quest:
	var id = ""
	var name = ""
	var description = ""
	var giver = ""
	var objectives = []
	var rewards = {}
	var prerequisites = []
	var is_main_quest = false
	var auto_complete = true
	var time_limit = -1
	var level_requirement = 0
	
	func _init(quest_id: String, quest_name: String):
		id = quest_id
		name = quest_name

class QuestObjective:
	var id = ""
	var description = ""
	var type = ""
	var target = ""
	var required_amount = 1
	var current_amount = 0
	var is_optional = false
	var is_hidden = false
	
	func _init(obj_id: String, obj_type: String):
		id = obj_id
		type = obj_type
	
	func is_complete() -> bool:
		return current_amount >= required_amount
	
	func update_progress(amount: int = 1):
		current_amount = min(current_amount + amount, required_amount)

class ActiveQuest:
	var quest: Quest
	var objectives = {}
	var start_time = 0
	var is_completed = false
	var is_failed = false
	
	func _init(quest_data: Quest):
		quest = quest_data
		start_time = OS.get_unix_time()
		
		for objective in quest.objectives:
			objectives[objective.id] = objective
	
	func check_completion() -> bool:
		if is_failed:
			return false
		
		for obj_id in objectives:
			var objective = objectives[obj_id]
			if not objective.is_optional and not objective.is_complete():
				return false
		
		return true
	
	func check_time_limit() -> bool:
		if quest.time_limit <= 0:
			return true
		
		var elapsed = OS.get_unix_time() - start_time
		return elapsed < quest.time_limit

func _ready():
	_load_quest_database()
	set_process(true)

func _process(delta):
	_check_quest_time_limits()

func start_quest(quest_id: String) -> bool:
	if active_quests.has(quest_id) or quest_id in completed_quests:
		return false
	
	if not quest_database.has(quest_id):
		push_error("Quest not found: " + quest_id)
		return false
	
	var quest_data = quest_database[quest_id]
	
	if not _check_prerequisites(quest_data):
		return false
	
	var active_quest = ActiveQuest.new(quest_data)
	active_quests[quest_id] = active_quest
	
	emit_signal("quest_started", quest_id)
	
	_show_quest_notification("Quest Started", quest_data.name)
	
	return true

func complete_quest(quest_id: String) -> bool:
	if not active_quests.has(quest_id):
		return false
	
	var active_quest = active_quests[quest_id]
	
	if not active_quest.check_completion():
		return false
	
	active_quest.is_completed = true
	completed_quests.append(quest_id)
	
	_give_rewards(active_quest.quest.rewards)
	
	active_quests.erase(quest_id)
	
	emit_signal("quest_completed", quest_id)
	
	_show_quest_notification("Quest Completed", active_quest.quest.name)
	
	_check_quest_unlocks(quest_id)
	
	return true

func fail_quest(quest_id: String, reason: String = ""):
	if not active_quests.has(quest_id):
		return
	
	var active_quest = active_quests[quest_id]
	active_quest.is_failed = true
	
	active_quests.erase(quest_id)
	
	emit_signal("quest_failed", quest_id)
	
	_show_quest_notification("Quest Failed", active_quest.quest.name + "\n" + reason)

func update_objective(quest_id: String, objective_id: String, amount: int = 1):
	if not active_quests.has(quest_id):
		return
	
	var active_quest = active_quests[quest_id]
	
	if not active_quest.objectives.has(objective_id):
		return
	
	var objective = active_quest.objectives[objective_id]
	var was_complete = objective.is_complete()
	
	objective.update_progress(amount)
	
	emit_signal("quest_progress_updated", quest_id, objective_id, objective.current_amount)
	
	if not was_complete and objective.is_complete():
		emit_signal("objective_completed", quest_id, objective_id)
		_show_objective_notification(active_quest.quest.name, objective.description)
	
	if active_quest.quest.auto_complete and active_quest.check_completion():
		complete_quest(quest_id)

func update_objective_by_type(obj_type: String, target: String, amount: int = 1):
	for quest_id in active_quests:
		var active_quest = active_quests[quest_id]
		
		for obj_id in active_quest.objectives:
			var objective = active_quest.objectives[obj_id]
			
			if objective.type == obj_type and objective.target == target:
				update_objective(quest_id, obj_id, amount)

func get_active_quest(quest_id: String) -> ActiveQuest:
	if active_quests.has(quest_id):
		return active_quests[quest_id]
	return null

func get_all_active_quests() -> Array:
	return active_quests.values()

func get_quest_progress(quest_id: String) -> Dictionary:
	if not active_quests.has(quest_id):
		return {}
	
	var active_quest = active_quests[quest_id]
	var progress = {
		"quest_name": active_quest.quest.name,
		"objectives": {}
	}
	
	for obj_id in active_quest.objectives:
		var objective = active_quest.objectives[obj_id]
		progress.objectives[obj_id] = {
			"description": objective.description,
			"current": objective.current_amount,
			"required": objective.required_amount,
			"is_complete": objective.is_complete(),
			"is_optional": objective.is_optional
		}
	
	return progress

func is_quest_active(quest_id: String) -> bool:
	return active_quests.has(quest_id)

func is_quest_completed(quest_id: String) -> bool:
	return quest_id in completed_quests

func can_start_quest(quest_id: String) -> bool:
	if active_quests.has(quest_id) or quest_id in completed_quests:
		return false
	
	if not quest_database.has(quest_id):
		return false
	
	return _check_prerequisites(quest_database[quest_id])

func save_quest_data() -> Dictionary:
	var save_data = {
		"active_quests": {},
		"completed_quests": completed_quests
	}
	
	for quest_id in active_quests:
		var active_quest = active_quests[quest_id]
		save_data.active_quests[quest_id] = {
			"start_time": active_quest.start_time,
			"objectives": {}
		}
		
		for obj_id in active_quest.objectives:
			var objective = active_quest.objectives[obj_id]
			save_data.active_quests[quest_id].objectives[obj_id] = {
				"current_amount": objective.current_amount
			}
	
	return save_data

func load_quest_data(save_data: Dictionary):
	active_quests.clear()
	completed_quests.clear()
	
	if save_data.has("completed_quests"):
		completed_quests = save_data.completed_quests
	
	if save_data.has("active_quests"):
		for quest_id in save_data.active_quests:
			if quest_database.has(quest_id):
				var quest_data = quest_database[quest_id]
				var active_quest = ActiveQuest.new(quest_data)
				
				var saved_quest = save_data.active_quests[quest_id]
				active_quest.start_time = saved_quest.start_time
				
				if saved_quest.has("objectives"):
					for obj_id in saved_quest.objectives:
						if active_quest.objectives.has(obj_id):
							var saved_obj = saved_quest.objectives[obj_id]
							active_quest.objectives[obj_id].current_amount = saved_obj.current_amount
				
				active_quests[quest_id] = active_quest

func _check_prerequisites(quest: Quest) -> bool:
	for prereq in quest.prerequisites:
		if not is_quest_completed(prereq):
			return false
	
	return true

func _check_quest_unlocks(completed_quest_id: String):
	for quest_id in quest_database:
		if can_start_quest(quest_id):
			var quest = quest_database[quest_id]
			if completed_quest_id in quest.prerequisites:
				_show_quest_notification("New Quest Available", quest.name)

func _check_quest_time_limits():
	var quests_to_fail = []
	
	for quest_id in active_quests:
		var active_quest = active_quests[quest_id]
		if not active_quest.check_time_limit():
			quests_to_fail.append(quest_id)
	
	for quest_id in quests_to_fail:
		fail_quest(quest_id, "Time limit exceeded")

func _give_rewards(rewards: Dictionary):
	if rewards.has("experience"):
		pass
	
	if rewards.has("gold"):
		pass
	
	if rewards.has("items"):
		for item_data in rewards.items:
			pass

func _show_quest_notification(title: String, message: String):
	print("[QUEST] " + title + ": " + message)

func _show_objective_notification(quest_name: String, objective: String):
	print("[OBJECTIVE] " + quest_name + " - " + objective + " completed!")

func _load_quest_database():
	var fetch_quest = Quest.new("fetch_quest", "Fetch Quest")
	fetch_quest.description = "Collect 10 mushrooms for the alchemist"
	fetch_quest.giver = "Alchemist"
	
	var collect_obj = QuestObjective.new("collect_mushrooms", "collect")
	collect_obj.description = "Collect mushrooms"
	collect_obj.target = "mushroom"
	collect_obj.required_amount = 10
	
	fetch_quest.objectives.append(collect_obj)
	fetch_quest.rewards = {
		"experience": 100,
		"gold": 50,
		"items": [{"id": "health_potion", "amount": 3}]
	}
	
	quest_database["fetch_quest"] = fetch_quest
	
	var main_quest = Quest.new("main_quest", "The Hero's Journey")
	main_quest.description = "Defeat the dragon terrorizing the village"
	main_quest.is_main_quest = true
	main_quest.prerequisites = ["fetch_quest"]
	
	var kill_obj = QuestObjective.new("kill_dragon", "kill")
	kill_obj.description = "Defeat the dragon"
	kill_obj.target = "dragon"
	kill_obj.required_amount = 1
	
	main_quest.objectives.append(kill_obj)
	main_quest.rewards = {
		"experience": 1000,
		"gold": 500,
		"items": [{"id": "legendary_sword", "amount": 1}]
	}
	
	quest_database["main_quest"] = main_quest