extends Node

signal player_killed(killer_id, victim_id, weapon)
signal player_respawned(player_id, spawn_point)
signal game_ended(winner_id, final_scores)
signal score_updated(player_scores)

var player_scores = {}
var player_stats = {}
var spawn_points = []
var active_players = {}

var score_limit = 20
var time_limit = 600.0
var respawn_time = 3.0
var match_time = 0.0
var match_active = false

var weapon_stats = {
	"pistol": {"damage": 25, "points": 10},
	"rifle": {"damage": 35, "points": 10},
	"shotgun": {"damage": 80, "points": 10},
	"sniper": {"damage": 100, "points": 15},
	"rocket": {"damage": 120, "points": 20},
	"melee": {"damage": 50, "points": 25}
}

func _ready():
	set_process(false)
	if get_tree().is_network_server():
		_initialize_spawn_points()

func _initialize_spawn_points():
	spawn_points = [
		Vector3(0, 5, 0),
		Vector3(20, 5, 20),
		Vector3(-20, 5, 20),
		Vector3(20, 5, -20),
		Vector3(-20, 5, -20),
		Vector3(30, 5, 0),
		Vector3(-30, 5, 0),
		Vector3(0, 5, 30),
		Vector3(0, 5, -30)
	]

func start_match():
	if not get_tree().is_network_server():
		return
	
	match_active = true
	match_time = 0.0
	set_process(true)
	
	for player_id in player_scores:
		player_scores[player_id] = 0
		_spawn_player(player_id)
	
	rpc("on_match_started")

func register_player(player_id, player_name):
	player_scores[player_id] = 0
	player_stats[player_id] = {
		"name": player_name,
		"kills": 0,
		"deaths": 0,
		"streak": 0,
		"best_streak": 0,
		"headshots": 0,
		"accuracy": 0.0
	}
	active_players[player_id] = true
	
	if match_active:
		_spawn_player(player_id)

func unregister_player(player_id):
	active_players.erase(player_id)
	if player_scores.has(player_id):
		player_scores.erase(player_id)
	if player_stats.has(player_id):
		player_stats.erase(player_id)

func handle_player_death(victim_id, killer_id, weapon, headshot = false):
	if not match_active:
		return
	
	if victim_id == killer_id:
		player_scores[victim_id] = max(0, player_scores[victim_id] - 5)
		player_stats[victim_id].deaths += 1
		player_stats[victim_id].streak = 0
	else:
		var points = weapon_stats.get(weapon, {}).get("points", 10)
		if headshot:
			points = int(points * 1.5)
			player_stats[killer_id].headshots += 1
		
		player_scores[killer_id] += points
		player_stats[killer_id].kills += 1
		player_stats[killer_id].streak += 1
		
		if player_stats[killer_id].streak > player_stats[killer_id].best_streak:
			player_stats[killer_id].best_streak = player_stats[killer_id].streak
		
		player_stats[victim_id].deaths += 1
		player_stats[victim_id].streak = 0
		
		_check_special_achievements(killer_id, victim_id, weapon)
	
	emit_signal("player_killed", killer_id, victim_id, weapon)
	emit_signal("score_updated", player_scores)
	
	rpc("on_player_killed", killer_id, victim_id, weapon, player_scores)
	
	_check_win_condition()
	
	yield(get_tree().create_timer(respawn_time), "timeout")
	if active_players.has(victim_id):
		_spawn_player(victim_id)

func _spawn_player(player_id):
	var spawn_point = _get_best_spawn_point(player_id)
	emit_signal("player_respawned", player_id, spawn_point)
	rpc("on_player_respawned", player_id, spawn_point)

func _get_best_spawn_point(player_id):
	if spawn_points.empty():
		return Vector3.ZERO
	
	var best_spawn = spawn_points[0]
	var max_distance = 0.0
	
	for spawn in spawn_points:
		var total_distance = 0.0
		for other_id in active_players:
			if other_id != player_id and active_players.has(other_id):
				var other_pos = _get_player_position(other_id)
				if other_pos:
					total_distance += spawn.distance_to(other_pos)
		
		if total_distance > max_distance:
			max_distance = total_distance
			best_spawn = spawn
	
	return best_spawn

func _get_player_position(player_id):
	var player_node = get_node_or_null("/root/Game/Players/" + str(player_id))
	if player_node:
		return player_node.global_transform.origin
	return null

func _check_special_achievements(killer_id, victim_id, weapon):
	var streak = player_stats[killer_id].streak
	
	match streak:
		3:
			rpc("on_achievement", killer_id, "Triple Kill!")
		5:
			rpc("on_achievement", killer_id, "Killing Spree!")
		10:
			rpc("on_achievement", killer_id, "Unstoppable!")
		15:
			rpc("on_achievement", killer_id, "Godlike!")
		20:
			rpc("on_achievement", killer_id, "Legendary!")
	
	if weapon == "melee":
		rpc("on_achievement", killer_id, "Humiliation!")

func _process(delta):
	if not match_active:
		return
	
	match_time += delta
	
	if match_time >= time_limit:
		_end_match()

func _check_win_condition():
	for player_id in player_scores:
		if player_scores[player_id] >= score_limit:
			_end_match()
			break

func _end_match():
	match_active = false
	set_process(false)
	
	var winner_id = -1
	var highest_score = -1
	
	for player_id in player_scores:
		if player_scores[player_id] > highest_score:
			highest_score = player_scores[player_id]
			winner_id = player_id
	
	emit_signal("game_ended", winner_id, player_scores)
	rpc("on_match_ended", winner_id, player_scores, player_stats)

remote func on_match_started():
	match_active = true

remote func on_player_killed(killer_id, victim_id, weapon, scores):
	player_scores = scores

remote func on_player_respawned(player_id, spawn_point):
	pass

remote func on_achievement(player_id, achievement):
	pass

remote func on_match_ended(winner_id, final_scores, final_stats):
	player_scores = final_scores
	player_stats = final_stats
	match_active = false

func get_player_score(player_id):
	return player_scores.get(player_id, 0)

func get_time_remaining():
	return max(0, time_limit - match_time)

func get_leading_player():
	var leader_id = -1
	var highest_score = -1
	
	for player_id in player_scores:
		if player_scores[player_id] > highest_score:
			highest_score = player_scores[player_id]
			leader_id = player_id
	
	return leader_id