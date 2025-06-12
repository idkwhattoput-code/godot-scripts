extends Node

signal flag_captured(team_id, player_id)
signal flag_dropped(team_id, position)
signal flag_returned(team_id)
signal game_won(winning_team)

enum Team {
	RED,
	BLUE
}

enum FlagState {
	AT_BASE,
	CARRIED,
	DROPPED
}

var team_scores = {
	Team.RED: 0,
	Team.BLUE: 0
}

var flag_states = {
	Team.RED: FlagState.AT_BASE,
	Team.BLUE: FlagState.AT_BASE
}

var flag_carriers = {
	Team.RED: null,
	Team.BLUE: null
}

var flag_positions = {}
var flag_base_positions = {}
var dropped_flag_timers = {}

var score_limit = 3
var flag_return_time = 30.0
var flag_pickup_radius = 2.0

var players = {}

func _ready():
	set_physics_process(true)
	if get_tree().is_network_server():
		_initialize_flags()

func _initialize_flags():
	flag_base_positions[Team.RED] = Vector3(-50, 0, 0)
	flag_base_positions[Team.BLUE] = Vector3(50, 0, 0)
	
	flag_positions[Team.RED] = flag_base_positions[Team.RED]
	flag_positions[Team.BLUE] = flag_base_positions[Team.BLUE]

func register_player(player_id, team):
	players[player_id] = {
		"team": team,
		"captures": 0,
		"returns": 0,
		"position": Vector3.ZERO
	}

func unregister_player(player_id):
	if flag_carriers[Team.RED] == player_id:
		_drop_flag(Team.RED, players[player_id].position)
	elif flag_carriers[Team.BLUE] == player_id:
		_drop_flag(Team.BLUE, players[player_id].position)
	
	players.erase(player_id)

func update_player_position(player_id, position):
	if players.has(player_id):
		players[player_id].position = position
		
		if flag_carriers[Team.RED] == player_id:
			flag_positions[Team.RED] = position
		elif flag_carriers[Team.BLUE] == player_id:
			flag_positions[Team.BLUE] = position

func _physics_process(delta):
	if not get_tree().is_network_server():
		return
	
	_check_flag_pickups()
	_check_flag_captures()
	_update_dropped_flags(delta)

func _check_flag_pickups():
	for player_id in players:
		var player = players[player_id]
		var player_team = player.team
		var enemy_team = Team.BLUE if player_team == Team.RED else Team.RED
		
		if flag_states[enemy_team] != FlagState.CARRIED:
			var distance = player.position.distance_to(flag_positions[enemy_team])
			if distance < flag_pickup_radius:
				_pickup_flag(enemy_team, player_id)
		
		if flag_states[player_team] == FlagState.DROPPED:
			var distance = player.position.distance_to(flag_positions[player_team])
			if distance < flag_pickup_radius:
				_return_flag(player_team, player_id)

func _pickup_flag(team, player_id):
	flag_states[team] = FlagState.CARRIED
	flag_carriers[team] = player_id
	
	if dropped_flag_timers.has(team):
		dropped_flag_timers[team].queue_free()
		dropped_flag_timers.erase(team)
	
	rpc("on_flag_picked_up", team, player_id)

func _drop_flag(team, position):
	flag_states[team] = FlagState.DROPPED
	flag_carriers[team] = null
	flag_positions[team] = position
	
	var timer = Timer.new()
	timer.wait_time = flag_return_time
	timer.one_shot = true
	timer.connect("timeout", self, "_auto_return_flag", [team])
	add_child(timer)
	timer.start()
	
	dropped_flag_timers[team] = timer
	
	emit_signal("flag_dropped", team, position)
	rpc("on_flag_dropped", team, position)

func _return_flag(team, player_id):
	flag_states[team] = FlagState.AT_BASE
	flag_positions[team] = flag_base_positions[team]
	
	if dropped_flag_timers.has(team):
		dropped_flag_timers[team].queue_free()
		dropped_flag_timers.erase(team)
	
	players[player_id].returns += 1
	
	emit_signal("flag_returned", team)
	rpc("on_flag_returned", team, player_id)

func _auto_return_flag(team):
	if flag_states[team] == FlagState.DROPPED:
		flag_states[team] = FlagState.AT_BASE
		flag_positions[team] = flag_base_positions[team]
		
		emit_signal("flag_returned", team)
		rpc("on_flag_returned", team, -1)

func _check_flag_captures():
	for player_id in players:
		var player = players[player_id]
		var player_team = player.team
		var enemy_team = Team.BLUE if player_team == Team.RED else Team.RED
		
		if flag_carriers[enemy_team] == player_id:
			var distance = player.position.distance_to(flag_base_positions[player_team])
			if distance < flag_pickup_radius and flag_states[player_team] == FlagState.AT_BASE:
				_capture_flag(player_team, player_id)

func _capture_flag(team, player_id):
	var enemy_team = Team.BLUE if team == Team.RED else Team.RED
	
	team_scores[team] += 1
	players[player_id].captures += 1
	
	flag_states[enemy_team] = FlagState.AT_BASE
	flag_positions[enemy_team] = flag_base_positions[enemy_team]
	flag_carriers[enemy_team] = null
	
	emit_signal("flag_captured", team, player_id)
	rpc("on_flag_captured", team, player_id, team_scores)
	
	if team_scores[team] >= score_limit:
		_end_game(team)

func _end_game(winning_team):
	emit_signal("game_won", winning_team)
	rpc("on_game_ended", winning_team, team_scores)

func _update_dropped_flags(delta):
	pass

remote func on_flag_picked_up(team, player_id):
	pass

remote func on_flag_dropped(team, position):
	pass

remote func on_flag_returned(team, player_id):
	pass

remote func on_flag_captured(team, player_id, scores):
	team_scores = scores

remote func on_game_ended(winning_team, final_scores):
	team_scores = final_scores

func get_team_score(team):
	return team_scores[team]

func get_flag_state(team):
	return flag_states[team]

func get_flag_position(team):
	return flag_positions[team]