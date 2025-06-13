extends Node

signal trade_requested(trader_id, target_id)
signal trade_accepted(trade_id)
signal trade_cancelled(trade_id, canceller_id)
signal trade_completed(trade_id)
signal trade_item_added(trade_id, player_id, item)
signal trade_item_removed(trade_id, player_id, item_slot)
signal trade_gold_updated(trade_id, player_id, amount)
signal trade_locked(trade_id, player_id)

enum TradeStatus {
	PENDING,
	ACTIVE,
	LOCKED,
	COMPLETED,
	CANCELLED
}

var active_trades = {}
var trade_requests = {}
var player_trades = {}

var trade_config = {
	"max_items_per_side": 12,
	"max_gold": 999999999,
	"trade_range": 10.0,
	"request_timeout": 30.0,
	"inactivity_timeout": 300.0
}

func _ready():
	set_process(true)

func request_trade(trader_id, target_id):
	if not _can_trade(trader_id, target_id):
		return false
	
	if player_trades.has(trader_id) or player_trades.has(target_id):
		return false
	
	trade_requests[target_id] = {
		"from": trader_id,
		"timestamp": OS.get_unix_time()
	}
	
	emit_signal("trade_requested", trader_id, target_id)
	rpc_id(target_id, "receive_trade_request", trader_id)
	
	return true

func accept_trade_request(accepter_id):
	if not trade_requests.has(accepter_id):
		return false
	
	var request = trade_requests[accepter_id]
	var trader_id = request.from
	
	if OS.get_unix_time() - request.timestamp > trade_config.request_timeout:
		trade_requests.erase(accepter_id)
		return false
	
	var trade_id = _create_trade(trader_id, accepter_id)
	trade_requests.erase(accepter_id)
	
	return trade_id != null

func _create_trade(player1_id, player2_id):
	if not _can_trade(player1_id, player2_id):
		return null
	
	var trade_id = _generate_trade_id()
	
	var trade_data = {
		"id": trade_id,
		"status": TradeStatus.ACTIVE,
		"player1": {
			"id": player1_id,
			"items": {},
			"gold": 0,
			"locked": false
		},
		"player2": {
			"id": player2_id,
			"items": {},
			"gold": 0,
			"locked": false
		},
		"created": OS.get_unix_time(),
		"last_activity": OS.get_unix_time()
	}
	
	active_trades[trade_id] = trade_data
	player_trades[player1_id] = trade_id
	player_trades[player2_id] = trade_id
	
	emit_signal("trade_accepted", trade_id)
	rpc("on_trade_started", trade_id, trade_data)
	
	return trade_id

func add_item_to_trade(player_id, item_data, slot = -1):
	var trade_id = player_trades.get(player_id)
	if not trade_id or not active_trades.has(trade_id):
		return false
	
	var trade = active_trades[trade_id]
	if trade.status != TradeStatus.ACTIVE:
		return false
	
	var player_side = _get_player_side(trade, player_id)
	if not player_side:
		return false
	
	if player_side.locked:
		return false
	
	if slot == -1:
		slot = _find_empty_slot(player_side.items)
	
	if slot < 0 or slot >= trade_config.max_items_per_side:
		return false
	
	if player_side.items.has(slot):
		return false
	
	player_side.items[slot] = item_data
	trade.last_activity = OS.get_unix_time()
	
	_unlock_both_players(trade)
	
	emit_signal("trade_item_added", trade_id, player_id, item_data)
	rpc("on_trade_item_added", trade_id, player_id, slot, item_data)
	
	return true

func remove_item_from_trade(player_id, slot):
	var trade_id = player_trades.get(player_id)
	if not trade_id or not active_trades.has(trade_id):
		return false
	
	var trade = active_trades[trade_id]
	if trade.status != TradeStatus.ACTIVE:
		return false
	
	var player_side = _get_player_side(trade, player_id)
	if not player_side:
		return false
	
	if player_side.locked:
		return false
	
	if not player_side.items.has(slot):
		return false
	
	player_side.items.erase(slot)
	trade.last_activity = OS.get_unix_time()
	
	_unlock_both_players(trade)
	
	emit_signal("trade_item_removed", trade_id, player_id, slot)
	rpc("on_trade_item_removed", trade_id, player_id, slot)
	
	return true

func update_trade_gold(player_id, amount):
	if amount < 0 or amount > trade_config.max_gold:
		return false
	
	var trade_id = player_trades.get(player_id)
	if not trade_id or not active_trades.has(trade_id):
		return false
	
	var trade = active_trades[trade_id]
	if trade.status != TradeStatus.ACTIVE:
		return false
	
	var player_side = _get_player_side(trade, player_id)
	if not player_side:
		return false
	
	if player_side.locked:
		return false
	
	player_side.gold = amount
	trade.last_activity = OS.get_unix_time()
	
	_unlock_both_players(trade)
	
	emit_signal("trade_gold_updated", trade_id, player_id, amount)
	rpc("on_trade_gold_updated", trade_id, player_id, amount)
	
	return true

func lock_trade(player_id):
	var trade_id = player_trades.get(player_id)
	if not trade_id or not active_trades.has(trade_id):
		return false
	
	var trade = active_trades[trade_id]
	if trade.status != TradeStatus.ACTIVE:
		return false
	
	var player_side = _get_player_side(trade, player_id)
	if not player_side:
		return false
	
	player_side.locked = true
	trade.last_activity = OS.get_unix_time()
	
	emit_signal("trade_locked", trade_id, player_id)
	rpc("on_trade_locked", trade_id, player_id)
	
	if trade.player1.locked and trade.player2.locked:
		_complete_trade(trade_id)
	
	return true

func unlock_trade(player_id):
	var trade_id = player_trades.get(player_id)
	if not trade_id or not active_trades.has(trade_id):
		return false
	
	var trade = active_trades[trade_id]
	if trade.status != TradeStatus.ACTIVE:
		return false
	
	var player_side = _get_player_side(trade, player_id)
	if not player_side:
		return false
	
	player_side.locked = false
	trade.last_activity = OS.get_unix_time()
	
	rpc("on_trade_unlocked", trade_id, player_id)
	
	return true

func cancel_trade(player_id):
	var trade_id = player_trades.get(player_id)
	if not trade_id or not active_trades.has(trade_id):
		return false
	
	var trade = active_trades[trade_id]
	if trade.status == TradeStatus.COMPLETED:
		return false
	
	trade.status = TradeStatus.CANCELLED
	
	player_trades.erase(trade.player1.id)
	player_trades.erase(trade.player2.id)
	
	emit_signal("trade_cancelled", trade_id, player_id)
	rpc("on_trade_cancelled", trade_id, player_id)
	
	active_trades.erase(trade_id)
	
	return true

func _complete_trade(trade_id):
	if not active_trades.has(trade_id):
		return
	
	var trade = active_trades[trade_id]
	trade.status = TradeStatus.COMPLETED
	
	var trade_result = {
		"player1_receives": {
			"items": trade.player2.items.values(),
			"gold": trade.player2.gold
		},
		"player2_receives": {
			"items": trade.player1.items.values(),
			"gold": trade.player1.gold
		}
	}
	
	player_trades.erase(trade.player1.id)
	player_trades.erase(trade.player2.id)
	
	emit_signal("trade_completed", trade_id)
	rpc("on_trade_completed", trade_id, trade_result)
	
	active_trades.erase(trade_id)

func _process(delta):
	_check_trade_timeouts()
	_check_inactive_trades()

func _check_trade_timeouts():
	var current_time = OS.get_unix_time()
	var expired_requests = []
	
	for target_id in trade_requests:
		var request = trade_requests[target_id]
		if current_time - request.timestamp > trade_config.request_timeout:
			expired_requests.append(target_id)
	
	for target_id in expired_requests:
		trade_requests.erase(target_id)

func _check_inactive_trades():
	var current_time = OS.get_unix_time()
	var inactive_trades = []
	
	for trade_id in active_trades:
		var trade = active_trades[trade_id]
		if current_time - trade.last_activity > trade_config.inactivity_timeout:
			inactive_trades.append(trade_id)
	
	for trade_id in inactive_trades:
		var trade = active_trades[trade_id]
		cancel_trade(trade.player1.id)

func _can_trade(player1_id, player2_id):
	if player1_id == player2_id:
		return false
	
	var player1_pos = _get_player_position(player1_id)
	var player2_pos = _get_player_position(player2_id)
	
	if not player1_pos or not player2_pos:
		return false
	
	var distance = player1_pos.distance_to(player2_pos)
	return distance <= trade_config.trade_range

func _get_player_position(player_id):
	var player_node = get_node_or_null("/root/Game/Players/" + str(player_id))
	if player_node:
		return player_node.global_transform.origin
	return null

func _get_player_side(trade, player_id):
	if trade.player1.id == player_id:
		return trade.player1
	elif trade.player2.id == player_id:
		return trade.player2
	return null

func _unlock_both_players(trade):
	trade.player1.locked = false
	trade.player2.locked = false

func _find_empty_slot(items):
	for i in range(trade_config.max_items_per_side):
		if not items.has(i):
			return i
	return -1

func _generate_trade_id():
	return "trade_" + str(OS.get_unix_time()) + "_" + str(randi() % 10000)

remote func receive_trade_request(from_player_id):
	pass

remote func on_trade_started(trade_id, trade_data):
	active_trades[trade_id] = trade_data

remote func on_trade_item_added(trade_id, player_id, slot, item_data):
	pass

remote func on_trade_item_removed(trade_id, player_id, slot):
	pass

remote func on_trade_gold_updated(trade_id, player_id, amount):
	pass

remote func on_trade_locked(trade_id, player_id):
	pass

remote func on_trade_unlocked(trade_id, player_id):
	pass

remote func on_trade_cancelled(trade_id, canceller_id):
	active_trades.erase(trade_id)

remote func on_trade_completed(trade_id, trade_result):
	active_trades.erase(trade_id)

func get_active_trade(player_id):
	var trade_id = player_trades.get(player_id)
	if trade_id and active_trades.has(trade_id):
		return active_trades[trade_id]
	return null

func has_active_trade(player_id):
	return player_trades.has(player_id)