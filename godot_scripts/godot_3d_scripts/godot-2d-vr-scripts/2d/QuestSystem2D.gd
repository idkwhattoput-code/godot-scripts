extends Node

signal quest_started(quest_id: String)
signal quest_completed(quest_id: String, rewards: Dictionary)
signal quest_failed(quest_id: String)
signal objective_completed(quest_id: String, objective_id: String)
signal quest_progress_updated(quest_id: String, progress: float)

@export_group("Quest Configuration")
@export var max_active_quests: int = 10
@export var save_quest_progress: bool = true
@export var quest_database: Resource
@export var auto_track_nearest: bool = true

@export_group("UI Settings")
@export var show_notifications: bool = true
@export var notification_duration: float = 3.0
@export var quest_marker_scene: PackedScene
@export var objective_marker_color: Color = Color.YELLOW

var active_quests: Dictionary = {}
var completed_quests: Array[String] = []
var failed_quests: Array[String] = []
var tracked_quest: String = ""
var quest_markers: Dictionary = {}

var quest_templates: Dictionary = {
	"main_story": {
		"type": "main",
		"repeatable": false,
		"auto_complete": false,
		"fail_conditions": ["player_death", "time_limit"]
	},
	"side_quest": {
		"type": "side",
		"repeatable": true,
		"auto_complete": true,
		"fail_conditions": ["time_limit"]
	},
	"daily_quest": {
		"type": "daily",
		"repeatable": true,
		"auto_complete": true,
		"fail_conditions": ["day_reset"]
	}
}

class Quest:
	var id: String
	var name: String
	var description: String
	var type: String
	var objectives: Array[QuestObjective] = []
	var rewards: Dictionary = {}
	var prerequisites: Array[String] = []
	var time_limit: float = -1
	var current_time: float = 0
	var is_tracked: bool = false
	var metadata: Dictionary = {}

class QuestObjective:
	var id: String
	var description: String
	var type: String  # "kill", "collect", "reach", "interact", "survive"
	var target: String
	var required_amount: int = 1
	var current_amount: int = 0
	var is_optional: bool = false
	var is_hidden: bool = false
	var location: Vector2 = Vector2.ZERO

func _ready():
	if save_quest_progress:
		_load_quest_progress()

func _process(delta):
	_update_quest_timers(delta)
	_update_quest_markers()

func _update_quest_timers(delta):
	for quest_id in active_quests:
		var quest = active_quests[quest_id]
		if quest.time_limit > 0:
			quest.current_time += delta
			if quest.current_time >= quest.time_limit:
				fail_quest(quest_id, "Time limit exceeded")

func start_quest(quest_id: String) -> bool:
	if active_quests.has(quest_id):
		push_warning("Quest already active: " + quest_id)
		return false
	
	if active_quests.size() >= max_active_quests:
		push_warning("Maximum active quests reached")
		return false
	
	var quest_data = _get_quest_data(quest_id)
	if not quest_data:
		push_error("Quest not found: " + quest_id)
		return false
	
	if not _check_prerequisites(quest_data.get("prerequisites", [])):
		return false
	
	var quest = _create_quest_from_data(quest_id, quest_data)
	active_quests[quest_id] = quest
	
	if tracked_quest.is_empty() or auto_track_nearest:
		track_quest(quest_id)
	
	quest_started.emit(quest_id)
	_show_notification("Quest Started: " + quest.name)
	_create_quest_markers(quest)
	
	return true

func _create_quest_from_data(quest_id: String, data: Dictionary) -> Quest:
	var quest = Quest.new()
	quest.id = quest_id
	quest.name = data.get("name", "Unknown Quest")
	quest.description = data.get("description", "")
	quest.type = data.get("type", "side")
	quest.rewards = data.get("rewards", {})
	quest.prerequisites = data.get("prerequisites", [])
	quest.time_limit = data.get("time_limit", -1)
	quest.metadata = data.get("metadata", {})
	
	for obj_data in data.get("objectives", []):
		var objective = QuestObjective.new()
		objective.id = obj_data.get("id", "")
		objective.description = obj_data.get("description", "")
		objective.type = obj_data.get("type", "")
		objective.target = obj_data.get("target", "")
		objective.required_amount = obj_data.get("amount", 1)
		objective.is_optional = obj_data.get("optional", false)
		objective.is_hidden = obj_data.get("hidden", false)
		objective.location = obj_data.get("location", Vector2.ZERO)
		quest.objectives.append(objective)
	
	return quest

func complete_quest(quest_id: String):
	if not active_quests.has(quest_id):
		return
	
	var quest = active_quests[quest_id]
	
	# Check if all required objectives are complete
	for objective in quest.objectives:
		if not objective.is_optional and objective.current_amount < objective.required_amount:
			push_warning("Cannot complete quest - objectives not finished")
			return
	
	active_quests.erase(quest_id)
	completed_quests.append(quest_id)
	
	if tracked_quest == quest_id:
		tracked_quest = ""
	
	quest_completed.emit(quest_id, quest.rewards)
	_give_rewards(quest.rewards)
	_show_notification("Quest Completed: " + quest.name)
	_remove_quest_markers(quest_id)
	
	if save_quest_progress:
		_save_quest_progress()

func fail_quest(quest_id: String, reason: String = ""):
	if not active_quests.has(quest_id):
		return
	
	var quest = active_quests[quest_id]
	active_quests.erase(quest_id)
	failed_quests.append(quest_id)
	
	if tracked_quest == quest_id:
		tracked_quest = ""
	
	quest_failed.emit(quest_id)
	_show_notification("Quest Failed: " + quest.name + "\n" + reason)
	_remove_quest_markers(quest_id)

func update_objective(quest_id: String, objective_id: String, amount: int = 1):
	if not active_quests.has(quest_id):
		return
	
	var quest = active_quests[quest_id]
	var objective_found = false
	
	for objective in quest.objectives:
		if objective.id == objective_id:
			objective.current_amount = min(objective.current_amount + amount, objective.required_amount)
			objective_found = true
			
			if objective.current_amount >= objective.required_amount:
				objective_completed.emit(quest_id, objective_id)
				_show_notification("Objective Complete: " + objective.description)
			
			break
	
	if objective_found:
		var progress = _calculate_quest_progress(quest)
		quest_progress_updated.emit(quest_id, progress)
		
		# Auto-complete if enabled
		var template = quest_templates.get(quest.type, {})
		if template.get("auto_complete", false) and progress >= 1.0:
			complete_quest(quest_id)

func track_quest(quest_id: String):
	if not active_quests.has(quest_id):
		return
	
	if tracked_quest:
		active_quests[tracked_quest].is_tracked = false
	
	tracked_quest = quest_id
	active_quests[quest_id].is_tracked = true

func abandon_quest(quest_id: String):
	if not active_quests.has(quest_id):
		return
	
	var quest = active_quests[quest_id]
	
	# Check if quest can be abandoned
	if quest.type == "main":
		push_warning("Cannot abandon main story quests")
		return
	
	active_quests.erase(quest_id)
	
	if tracked_quest == quest_id:
		tracked_quest = ""
	
	_show_notification("Quest Abandoned: " + quest.name)
	_remove_quest_markers(quest_id)

func get_active_quests() -> Array:
	return active_quests.values()

func get_quest_by_id(quest_id: String) -> Quest:
	return active_quests.get(quest_id)

func is_quest_active(quest_id: String) -> bool:
	return active_quests.has(quest_id)

func is_quest_completed(quest_id: String) -> bool:
	return quest_id in completed_quests

func _calculate_quest_progress(quest: Quest) -> float:
	if quest.objectives.is_empty():
		return 0.0
	
	var total_required = 0
	var total_current = 0
	
	for objective in quest.objectives:
		if not objective.is_optional:
			total_required += objective.required_amount
			total_current += objective.current_amount
	
	return float(total_current) / float(total_required) if total_required > 0 else 0.0

func _check_prerequisites(prerequisites: Array) -> bool:
	for prereq in prerequisites:
		if prereq.begins_with("quest:"):
			var quest_id = prereq.substr(6)
			if not is_quest_completed(quest_id):
				return false
		elif prereq.begins_with("level:"):
			var required_level = int(prereq.substr(6))
			# Check player level here
		elif prereq.begins_with("item:"):
			var item_id = prereq.substr(5)
			# Check if player has item
	
	return true

func _give_rewards(rewards: Dictionary):
	if rewards.has("experience"):
		# Give experience to player
		pass
	
	if rewards.has("gold"):
		# Give gold to player
		pass
	
	if rewards.has("items"):
		for item_id in rewards.items:
			# Give item to player
			pass

func _create_quest_markers(quest: Quest):
	if not quest_marker_scene:
		return
	
	var markers = []
	
	for objective in quest.objectives:
		if objective.location != Vector2.ZERO and not objective.is_hidden:
			var marker = quest_marker_scene.instantiate()
			get_tree().current_scene.add_child(marker)
			marker.global_position = objective.location
			marker.modulate = objective_marker_color
			markers.append(marker)
	
	quest_markers[quest.id] = markers

func _remove_quest_markers(quest_id: String):
	if not quest_markers.has(quest_id):
		return
	
	for marker in quest_markers[quest_id]:
		marker.queue_free()
	
	quest_markers.erase(quest_id)

func _update_quest_markers():
	# Update marker positions or visibility
	pass

func _show_notification(text: String):
	if not show_notifications:
		return
	
	# Show notification UI
	print("[QUEST] " + text)

func _get_quest_data(quest_id: String) -> Dictionary:
	# Load from quest database resource
	if quest_database and quest_database.has_method("get_quest"):
		return quest_database.get_quest(quest_id)
	
	# Fallback to built-in quest data
	return {}

func _save_quest_progress():
	var save_data = {
		"active": {},
		"completed": completed_quests,
		"failed": failed_quests
	}
	
	for quest_id in active_quests:
		var quest = active_quests[quest_id]
		save_data.active[quest_id] = {
			"objectives": []
		}
		
		for objective in quest.objectives:
			save_data.active[quest_id].objectives.append({
				"id": objective.id,
				"current_amount": objective.current_amount
			})
	
	# Save to file
	var save_file = FileAccess.open("user://quest_progress.save", FileAccess.WRITE)
	if save_file:
		save_file.store_var(save_data)
		save_file.close()

func _load_quest_progress():
	if not FileAccess.file_exists("user://quest_progress.save"):
		return
	
	var save_file = FileAccess.open("user://quest_progress.save", FileAccess.READ)
	if save_file:
		var save_data = save_file.get_var()
		save_file.close()
		
		completed_quests = save_data.get("completed", [])
		failed_quests = save_data.get("failed", [])
		
		# Restore active quests
		for quest_id in save_data.get("active", {}):
			start_quest(quest_id)
			# Restore objective progress
			if active_quests.has(quest_id):
				var quest = active_quests[quest_id]
				var saved_objectives = save_data.active[quest_id].objectives
				for i in range(min(quest.objectives.size(), saved_objectives.size())):
					quest.objectives[i].current_amount = saved_objectives[i].current_amount