extends Node

signal match_found(match_data)
signal match_search_started()
signal match_search_cancelled()
signal match_ready(players)

enum MatchType {
	QUICK_MATCH,
	RANKED,
	CUSTOM,
	TOURNAMENT
}

enum MatchStatus {
	IDLE,
	SEARCHING,
	FOUND,
	STARTING,
	IN_PROGRESS,
	ENDED
}

var current_status = MatchStatus.IDLE
var search_params = {}
var match_data = {}
var search_start_time = 0
var elo_rating = 1200
var search_expansion_rate = 50

func _ready():
	set_process(false)

func start_matchmaking(match_type, params = {}):
	if current_status != MatchStatus.IDLE:
		return false
	
	current_status = MatchStatus.SEARCHING
	search_start_time = OS.get_ticks_msec()
	search_params = params
	search_params.match_type = match_type
	search_params.player_id = get_tree().get_network_unique_id()
	search_params.elo = elo_rating
	
	set_process(true)
	emit_signal("match_search_started")
	
	_send_matchmaking_request()
	return true

func cancel_matchmaking():
	if current_status != MatchStatus.SEARCHING:
		return false
	
	current_status = MatchStatus.IDLE
	set_process(false)
	emit_signal("match_search_cancelled")
	
	_send_cancel_request()
	return true

func _process(delta):
	if current_status == MatchStatus.SEARCHING:
		_update_search_parameters()

func _update_search_parameters():
	var search_time = (OS.get_ticks_msec() - search_start_time) / 1000.0
	var elo_range = int(search_time * search_expansion_rate)
	
	search_params.min_elo = max(0, elo_rating - elo_range)
	search_params.max_elo = elo_rating + elo_range

func _send_matchmaking_request():
	if not get_tree().has_network_peer():
		return
	
	rpc_id(1, "request_match", search_params)

func _send_cancel_request():
	if not get_tree().has_network_peer():
		return
	
	rpc_id(1, "cancel_match_request", get_tree().get_network_unique_id())

remote func match_found_notification(data):
	if current_status != MatchStatus.SEARCHING:
		return
	
	current_status = MatchStatus.FOUND
	match_data = data
	set_process(false)
	
	emit_signal("match_found", match_data)
	
	yield(get_tree().create_timer(1.0), "timeout")
	_accept_match()

func _accept_match():
	if current_status != MatchStatus.FOUND:
		return
	
	rpc_id(1, "accept_match", match_data.match_id)
	current_status = MatchStatus.STARTING

remote func match_ready_notification(players):
	if current_status != MatchStatus.STARTING:
		return
	
	current_status = MatchStatus.IN_PROGRESS
	emit_signal("match_ready", players)

func end_match(winner_id):
	if current_status != MatchStatus.IN_PROGRESS:
		return
	
	current_status = MatchStatus.ENDED
	
	if get_tree().has_network_peer():
		rpc_id(1, "report_match_result", match_data.match_id, winner_id)
	
	yield(get_tree().create_timer(2.0), "timeout")
	current_status = MatchStatus.IDLE

func update_elo_rating(new_rating):
	elo_rating = new_rating

func get_estimated_wait_time():
	match search_params.match_type:
		MatchType.QUICK_MATCH:
			return "< 1 minute"
		MatchType.RANKED:
			return "1-3 minutes"
		MatchType.CUSTOM:
			return "Varies"
		MatchType.TOURNAMENT:
			return "Scheduled"
	
	return "Unknown"

func get_search_time():
	if current_status != MatchStatus.SEARCHING:
		return 0
	
	return (OS.get_ticks_msec() - search_start_time) / 1000.0

func is_searching():
	return current_status == MatchStatus.SEARCHING

func is_in_match():
	return current_status == MatchStatus.IN_PROGRESS