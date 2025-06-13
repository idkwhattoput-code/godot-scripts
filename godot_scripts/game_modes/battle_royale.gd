extends Node

signal player_eliminated(player_id, eliminator_id)
signal zone_shrinking(new_center, new_radius)
signal zone_damage(player_id, damage)
signal winner_determined(winner_id)
signal player_landed(player_id, position)
signal supply_drop(position, items)

var players_alive = {}
var player_stats = {}
var zone_center = Vector3.ZERO
var zone_radius = 500.0
var zone_damage = 1.0
var zone_timer = 0.0
var zone_phase = 0

var zone_phases = [
	{"duration": 120, "radius": 400, "damage": 1},
	{"duration": 90, "radius": 300, "damage": 2},
	{"duration": 90, "radius": 200, "damage": 3},
	{"duration": 60, "radius": 100, "damage": 5},
	{"duration": 60, "radius": 50, "damage": 8},
	{"duration": 45, "radius": 25, "damage": 10},
	{"duration": 30, "radius": 10, "damage": 15}
]

var match_started = false
var drop_phase = true
var drop_timer = 30.0
var supply_drop_timer = 0.0
var supply_drop_interval = 90.0

var loot_spawns = []
var vehicle_spawns = []

func _ready():
	set_process(false)
	if get_tree().is_network_server():
		_initialize_map()

func _initialize_map():
	zone_center = Vector3.ZERO
	zone_radius = 500.0
	_generate_loot_spawns()
	_generate_vehicle_spawns()

func start_match(player_list):
	if not get_tree().is_network_server():
		return
	
	for player_id in player_list:
		register_player(player_id)
	
	drop_phase = true
	match_started = true
	set_process(true)
	
	rpc("on_match_started", zone_center, zone_radius)

func register_player(player_id):
	players_alive[player_id] = true
	player_stats[player_id] = {
		"eliminations": 0,
		"damage_dealt": 0,
		"distance_traveled": 0,
		"items_looted": 0,
		"placement": 0,
		"survival_time": 0,
		"in_zone": true
	}

func _process(delta):
	if not match_started:
		return
	
	if drop_phase:
		_handle_drop_phase(delta)
	else:
		_handle_battle_phase(delta)

func _handle_drop_phase(delta):
	drop_timer -= delta
	
	if drop_timer <= 0:
		drop_phase = false
		zone_timer = zone_phases[0].duration
		rpc("on_drop_phase_ended")

func _handle_battle_phase(delta):
	_update_zone(delta)
	_check_zone_damage(delta)
	_update_supply_drops(delta)
	_update_player_stats(delta)

func _update_zone(delta):
	zone_timer -= delta
	
	if zone_timer <= 0 and zone_phase < zone_phases.size() - 1:
		zone_phase += 1
		var phase = zone_phases[zone_phase]
		
		zone_timer = phase.duration
		var new_radius = phase.radius
		zone_damage = phase.damage
		
		var new_center = _calculate_new_zone_center(new_radius)
		
		emit_signal("zone_shrinking", new_center, new_radius)
		rpc("on_zone_update", new_center, new_radius, zone_damage)
		
		zone_center = new_center
		zone_radius = new_radius

func _calculate_new_zone_center(new_radius):
	var offset_range = zone_radius - new_radius
	var offset = Vector3(
		randf_range(-offset_range, offset_range),
		0,
		randf_range(-offset_range, offset_range)
	)
	
	return zone_center + offset

func _check_zone_damage(delta):
	for player_id in players_alive:
		if not players_alive[player_id]:
			continue
		
		var player_pos = _get_player_position(player_id)
		if not player_pos:
			continue
		
		var distance_from_center = player_pos.distance_to(zone_center)
		
		if distance_from_center > zone_radius:
			player_stats[player_id].in_zone = false
			var damage = zone_damage * delta
			emit_signal("zone_damage", player_id, damage)
			rpc_id(player_id, "receive_zone_damage", damage)
		else:
			player_stats[player_id].in_zone = true

func handle_player_elimination(victim_id, eliminator_id):
	if not players_alive.has(victim_id):
		return
	
	players_alive[victim_id] = false
	var remaining = _get_players_alive_count()
	player_stats[victim_id].placement = remaining + 1
	
	if eliminator_id != victim_id and eliminator_id != -1:
		player_stats[eliminator_id].eliminations += 1
	
	emit_signal("player_eliminated", victim_id, eliminator_id)
	rpc("on_player_eliminated", victim_id, eliminator_id, remaining)
	
	if remaining == 1:
		_end_match()

func _get_players_alive_count():
	var count = 0
	for player_id in players_alive:
		if players_alive[player_id]:
			count += 1
	return count

func _end_match():
	match_started = false
	set_process(false)
	
	var winner_id = -1
	for player_id in players_alive:
		if players_alive[player_id]:
			winner_id = player_id
			player_stats[player_id].placement = 1
			break
	
	emit_signal("winner_determined", winner_id)
	rpc("on_match_ended", winner_id, player_stats)

func handle_player_landing(player_id, position):
	emit_signal("player_landed", player_id, position)
	rpc("on_player_landed", player_id, position)

func _update_supply_drops(delta):
	supply_drop_timer += delta
	
	if supply_drop_timer >= supply_drop_interval:
		supply_drop_timer = 0.0
		_spawn_supply_drop()

func _spawn_supply_drop():
	var drop_position = Vector3(
		randf_range(-zone_radius * 0.8, zone_radius * 0.8),
		100,
		randf_range(-zone_radius * 0.8, zone_radius * 0.8)
	) + zone_center
	
	var items = _generate_supply_drop_items()
	
	emit_signal("supply_drop", drop_position, items)
	rpc("on_supply_drop", drop_position, items)

func _generate_supply_drop_items():
	return [
		{"type": "weapon", "id": "sniper_rifle", "rarity": "legendary"},
		{"type": "armor", "id": "level_3_armor", "amount": 1},
		{"type": "healing", "id": "medkit", "amount": 3},
		{"type": "ammo", "id": "sniper_ammo", "amount": 40}
	]

func _generate_loot_spawns():
	for i in range(100):
		loot_spawns.append({
			"position": Vector3(
				randf_range(-400, 400),
				0,
				randf_range(-400, 400)
			),
			"tier": randi() % 3 + 1
		})

func _generate_vehicle_spawns():
	for i in range(20):
		vehicle_spawns.append({
			"position": Vector3(
				randf_range(-400, 400),
				0,
				randf_range(-400, 400)
			),
			"type": ["car", "truck", "motorcycle"][randi() % 3]
		})

func _get_player_position(player_id):
	var player_node = get_node_or_null("/root/Game/Players/" + str(player_id))
	if player_node:
		return player_node.global_transform.origin
	return null

func _update_player_stats(delta):
	for player_id in players_alive:
		if players_alive[player_id]:
			player_stats[player_id].survival_time += delta

remote func on_match_started(center, radius):
	zone_center = center
	zone_radius = radius

remote func on_drop_phase_ended():
	drop_phase = false

remote func on_zone_update(center, radius, damage):
	zone_center = center
	zone_radius = radius
	zone_damage = damage

remote func on_player_eliminated(victim_id, eliminator_id, remaining):
	players_alive[victim_id] = false

remote func on_match_ended(winner_id, final_stats):
	player_stats = final_stats

remote func on_player_landed(player_id, position):
	pass

remote func on_supply_drop(position, items):
	pass

remote func receive_zone_damage(damage):
	pass

func get_safe_zone_info():
	return {
		"center": zone_center,
		"radius": zone_radius,
		"phase": zone_phase,
		"time_until_shrink": zone_timer
	}