extends Node

signal achievement_unlocked(achievement_id, achievement_data)
signal achievement_progress(achievement_id, current, target)
signal achievement_completed(achievement_id)
signal all_achievements_unlocked()

enum AchievementType {
	INSTANT,
	PROGRESSIVE,
	HIDDEN,
	TIERED
}

enum AchievementCategory {
	GAMEPLAY,
	COMBAT,
	EXPLORATION,
	COLLECTION,
	SOCIAL,
	SPECIAL
}

var achievements = {}
var unlocked_achievements = []
var achievement_progress = {}
var achievement_stats = {}

var achievement_config = {
	"save_file": "user://achievements.dat",
	"notification_duration": 5.0,
	"unlock_animation": true,
	"steam_integration": false,
	"reward_multiplier": 1.0
}

func _ready():
	_register_achievements()
	_load_achievement_data()
	set_process(true)

func _register_achievements():
	register_achievement("first_kill", {
		"name": "First Blood",
		"description": "Defeat your first enemy",
		"type": AchievementType.INSTANT,
		"category": AchievementCategory.COMBAT,
		"icon": "achievement_first_kill",
		"points": 10,
		"reward": {"currency": 100}
	})
	
	register_achievement("speed_demon", {
		"name": "Speed Demon",
		"description": "Complete a level in under 60 seconds",
		"type": AchievementType.INSTANT,
		"category": AchievementCategory.GAMEPLAY,
		"icon": "achievement_speed",
		"points": 25,
		"reward": {"item": "speed_boots"}
	})
	
	register_achievement("monster_slayer", {
		"name": "Monster Slayer",
		"description": "Defeat 1000 enemies",
		"type": AchievementType.PROGRESSIVE,
		"category": AchievementCategory.COMBAT,
		"icon": "achievement_slayer",
		"points": 50,
		"target": 1000,
		"reward": {"title": "Monster Slayer"}
	})
	
	register_achievement("treasure_hunter", {
		"name": "Treasure Hunter",
		"description": "Find all hidden treasures",
		"type": AchievementType.PROGRESSIVE,
		"category": AchievementCategory.EXPLORATION,
		"icon": "achievement_treasure",
		"points": 100,
		"target": 50,
		"reward": {"currency": 5000, "item": "golden_compass"}
	})
	
	register_achievement("completionist", {
		"name": "Completionist",
		"description": "Unlock all other achievements",
		"type": AchievementType.SPECIAL,
		"category": AchievementCategory.SPECIAL,
		"icon": "achievement_completionist",
		"points": 200,
		"hidden": true,
		"reward": {"title": "Completionist", "skin": "golden_armor"}
	})
	
	register_achievement("combo_master", {
		"name": "Combo Master",
		"description": "Achieve combo tiers",
		"type": AchievementType.TIERED,
		"category": AchievementCategory.COMBAT,
		"icon": "achievement_combo",
		"tiers": [
			{"target": 10, "points": 10, "name": "Combo Novice"},
			{"target": 50, "points": 25, "name": "Combo Expert"},
			{"target": 100, "points": 50, "name": "Combo Master"},
			{"target": 500, "points": 100, "name": "Combo Legend"}
		],
		"reward_per_tier": true
	})

func register_achievement(achievement_id, data):
	achievements[achievement_id] = data
	
	if data.type == AchievementType.PROGRESSIVE or data.type == AchievementType.TIERED:
		achievement_progress[achievement_id] = {
			"current": 0,
			"tier": 0
		}

func unlock_achievement(achievement_id):
	if not achievements.has(achievement_id):
		return false
	
	if unlocked_achievements.has(achievement_id):
		return false
	
	var achievement = achievements[achievement_id]
	
	if achievement.type == AchievementType.PROGRESSIVE:
		if achievement_progress[achievement_id].current < achievement.target:
			return false
	
	unlocked_achievements.append(achievement_id)
	
	_give_rewards(achievement)
	_save_achievement_data()
	
	emit_signal("achievement_unlocked", achievement_id, achievement)
	emit_signal("achievement_completed", achievement_id)
	
	_check_completionist()
	
	if achievement_config.steam_integration:
		_unlock_steam_achievement(achievement_id)
	
	return true

func update_achievement_progress(achievement_id, amount = 1):
	if not achievements.has(achievement_id):
		return
	
	if unlocked_achievements.has(achievement_id):
		return
	
	var achievement = achievements[achievement_id]
	
	if achievement.type == AchievementType.INSTANT:
		unlock_achievement(achievement_id)
		return
	
	if not achievement_progress.has(achievement_id):
		return
	
	var progress = achievement_progress[achievement_id]
	progress.current += amount
	
	if achievement.type == AchievementType.PROGRESSIVE:
		var target = achievement.target
		progress.current = min(progress.current, target)
		
		emit_signal("achievement_progress", achievement_id, progress.current, target)
		
		if progress.current >= target:
			unlock_achievement(achievement_id)
	
	elif achievement.type == AchievementType.TIERED:
		_check_tier_progress(achievement_id)
	
	_save_achievement_data()

func _check_tier_progress(achievement_id):
	var achievement = achievements[achievement_id]
	var progress = achievement_progress[achievement_id]
	var tiers = achievement.tiers
	
	for i in range(progress.tier, tiers.size()):
		var tier = tiers[i]
		if progress.current >= tier.target:
			progress.tier = i + 1
			
			var tier_achievement_id = achievement_id + "_tier_" + str(i + 1)
			if not unlocked_achievements.has(tier_achievement_id):
				unlocked_achievements.append(tier_achievement_id)
				
				emit_signal("achievement_unlocked", tier_achievement_id, {
					"name": tier.name,
					"description": achievement.description,
					"points": tier.points,
					"tier": i + 1
				})
				
				if achievement.reward_per_tier and achievement.has("reward"):
					_give_rewards(achievement)
		else:
			break
	
	var current_tier = min(progress.tier, tiers.size() - 1)
	var target = tiers[current_tier].target if current_tier < tiers.size() else tiers.back().target
	
	emit_signal("achievement_progress", achievement_id, progress.current, target)

func track_stat(stat_name, value = 1):
	if not achievement_stats.has(stat_name):
		achievement_stats[stat_name] = 0
	
	achievement_stats[stat_name] += value
	
	_check_stat_achievements(stat_name, achievement_stats[stat_name])

func _check_stat_achievements(stat_name, value):
	var stat_achievements = {
		"enemies_killed": ["first_kill", "monster_slayer"],
		"distance_traveled": ["explorer", "world_traveler"],
		"gold_collected": ["gold_digger", "rich_player"],
		"items_crafted": ["crafter", "master_crafter"],
		"players_helped": ["helpful_player", "saint"],
		"deaths": ["die_hard", "immortal"],
		"play_time": ["dedicated", "no_life"],
		"combo_count": ["combo_master"]
	}
	
	if stat_achievements.has(stat_name):
		for achievement_id in stat_achievements[stat_name]:
			if achievements.has(achievement_id):
				update_achievement_progress(achievement_id, 0)

func _give_rewards(achievement):
	if not achievement.has("reward"):
		return
	
	var reward = achievement.reward
	
	if reward.has("currency"):
		var amount = reward.currency * achievement_config.reward_multiplier
		pass
	
	if reward.has("item"):
		pass
	
	if reward.has("title"):
		pass
	
	if reward.has("skin"):
		pass

func _check_completionist():
	var total_achievements = 0
	var unlocked_count = 0
	
	for achievement_id in achievements:
		var achievement = achievements[achievement_id]
		if achievement.category != AchievementCategory.SPECIAL:
			total_achievements += 1
			if unlocked_achievements.has(achievement_id):
				unlocked_count += 1
	
	if unlocked_count >= total_achievements and total_achievements > 0:
		unlock_achievement("completionist")
		emit_signal("all_achievements_unlocked")

func get_achievement_info(achievement_id):
	if not achievements.has(achievement_id):
		return null
	
	var achievement = achievements[achievement_id]
	var info = {
		"id": achievement_id,
		"name": achievement.name,
		"description": achievement.description,
		"type": achievement.type,
		"category": achievement.category,
		"points": achievement.get("points", 0),
		"unlocked": unlocked_achievements.has(achievement_id),
		"hidden": achievement.get("hidden", false) and not unlocked_achievements.has(achievement_id)
	}
	
	if achievement_progress.has(achievement_id):
		var progress = achievement_progress[achievement_id]
		info["progress"] = progress.current
		
		if achievement.type == AchievementType.PROGRESSIVE:
			info["target"] = achievement.target
		elif achievement.type == AchievementType.TIERED:
			info["tier"] = progress.tier
			info["tiers"] = achievement.tiers
	
	return info

func get_achievements_by_category(category):
	var category_achievements = []
	
	for achievement_id in achievements:
		var achievement = achievements[achievement_id]
		if achievement.category == category:
			category_achievements.append(get_achievement_info(achievement_id))
	
	return category_achievements

func get_achievement_statistics():
	var total = 0
	var unlocked = 0
	var points_earned = 0
	var total_points = 0
	
	for achievement_id in achievements:
		var achievement = achievements[achievement_id]
		if achievement.category != AchievementCategory.SPECIAL:
			total += 1
			total_points += achievement.get("points", 0)
			
			if unlocked_achievements.has(achievement_id):
				unlocked += 1
				points_earned += achievement.get("points", 0)
	
	return {
		"total": total,
		"unlocked": unlocked,
		"completion_percentage": (unlocked / float(total)) * 100 if total > 0 else 0,
		"points_earned": points_earned,
		"total_points": total_points
	}

func reset_achievements():
	unlocked_achievements.clear()
	achievement_progress.clear()
	achievement_stats.clear()
	
	for achievement_id in achievements:
		var achievement = achievements[achievement_id]
		if achievement.type == AchievementType.PROGRESSIVE or achievement.type == AchievementType.TIERED:
			achievement_progress[achievement_id] = {
				"current": 0,
				"tier": 0
			}
	
	_save_achievement_data()

func _save_achievement_data():
	var save_data = {
		"unlocked": unlocked_achievements,
		"progress": achievement_progress,
		"stats": achievement_stats
	}
	
	var file = File.new()
	if file.open(achievement_config.save_file, File.WRITE) == OK:
		file.store_var(save_data)
		file.close()

func _load_achievement_data():
	var file = File.new()
	if not file.file_exists(achievement_config.save_file):
		return
	
	if file.open(achievement_config.save_file, File.READ) == OK:
		var save_data = file.get_var()
		file.close()
		
		if save_data.has("unlocked"):
			unlocked_achievements = save_data.unlocked
		if save_data.has("progress"):
			achievement_progress = save_data.progress
		if save_data.has("stats"):
			achievement_stats = save_data.stats

func _unlock_steam_achievement(achievement_id):
	pass

func export_achievement_data():
	return {
		"achievements": achievements,
		"unlocked": unlocked_achievements,
		"progress": achievement_progress,
		"stats": achievement_stats,
		"statistics": get_achievement_statistics()
	}