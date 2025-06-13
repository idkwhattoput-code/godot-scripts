extends Node

signal party_created(party_id, leader_id)
signal party_disbanded(party_id)
signal member_joined(party_id, player_id)
signal member_left(party_id, player_id)
signal member_kicked(party_id, player_id)
signal leader_changed(party_id, new_leader_id)
signal party_settings_changed(party_id, settings)

enum PartyRole {
	MEMBER,
	LEADER
}

enum LootMode {
	FREE_FOR_ALL,
	ROUND_ROBIN,
	MASTER_LOOTER,
	NEED_GREED
}

var parties = {}
var player_parties = {}
var party_invites = {}

var party_config = {
	"max_members": 5,
	"invite_timeout": 60.0,
	"xp_share_range": 100.0,
	"loot_share_range": 50.0
}

func _ready():
	set_process(true)

func create_party(leader_id):
	if player_parties.has(leader_id):
		return null
	
	var party_id = _generate_party_id()
	
	var party_data = {
		"id": party_id,
		"leader": leader_id,
		"members": {
			leader_id: {
				"role": PartyRole.LEADER,
				"joined": OS.get_unix_time(),
				"position": Vector3.ZERO,
				"health": 100,
				"max_health": 100,
				"level": 1
			}
		},
		"settings": {
			"loot_mode": LootMode.ROUND_ROBIN,
			"loot_threshold": 2,
			"xp_sharing": true,
			"private": false
		},
		"created": OS.get_unix_time(),
		"round_robin_index": 0
	}
	
	parties[party_id] = party_data
	player_parties[leader_id] = party_id
	
	emit_signal("party_created", party_id, leader_id)
	rpc("on_party_created", party_id, party_data)
	
	return party_id

func disband_party(player_id):
	var party_id = player_parties.get(player_id)
	if not party_id or not parties.has(party_id):
		return false
	
	var party = parties[party_id]
	if party.leader != player_id:
		return false
	
	for member_id in party.members:
		player_parties.erase(member_id)
	
	parties.erase(party_id)
	
	emit_signal("party_disbanded", party_id)
	rpc("on_party_disbanded", party_id)
	
	return true

func invite_player(inviter_id, invited_id):
	var party_id = player_parties.get(inviter_id)
	
	if not party_id:
		party_id = create_party(inviter_id)
	
	if not parties.has(party_id):
		return false
	
	var party = parties[party_id]
	
	if party.leader != inviter_id:
		return false
	
	if player_parties.has(invited_id):
		return false
	
	if party.members.size() >= party_config.max_members:
		return false
	
	party_invites[invited_id] = {
		"party_id": party_id,
		"inviter_id": inviter_id,
		"timestamp": OS.get_unix_time()
	}
	
	rpc_id(invited_id, "receive_party_invite", party_id, inviter_id)
	return true

func accept_invite(player_id):
	if not party_invites.has(player_id):
		return false
	
	var invite = party_invites[player_id]
	
	if OS.get_unix_time() - invite.timestamp > party_config.invite_timeout:
		party_invites.erase(player_id)
		return false
	
	return join_party(player_id, invite.party_id)

func join_party(player_id, party_id):
	if player_parties.has(player_id):
		return false
	
	if not parties.has(party_id):
		return false
	
	var party = parties[party_id]
	
	if party.members.size() >= party_config.max_members:
		return false
	
	party.members[player_id] = {
		"role": PartyRole.MEMBER,
		"joined": OS.get_unix_time(),
		"position": Vector3.ZERO,
		"health": 100,
		"max_health": 100,
		"level": 1
	}
	
	player_parties[player_id] = party_id
	party_invites.erase(player_id)
	
	emit_signal("member_joined", party_id, player_id)
	rpc("on_member_joined", party_id, player_id)
	
	return true

func leave_party(player_id):
	var party_id = player_parties.get(player_id)
	if not party_id or not parties.has(party_id):
		return false
	
	var party = parties[party_id]
	
	party.members.erase(player_id)
	player_parties.erase(player_id)
	
	emit_signal("member_left", party_id, player_id)
	rpc("on_member_left", party_id, player_id)
	
	if party.members.size() == 0:
		parties.erase(party_id)
		emit_signal("party_disbanded", party_id)
		rpc("on_party_disbanded", party_id)
	elif party.leader == player_id:
		_transfer_leadership(party_id)
	
	return true

func kick_member(kicker_id, kicked_id):
	var party_id = player_parties.get(kicker_id)
	if not party_id or party_id != player_parties.get(kicked_id):
		return false
	
	var party = parties[party_id]
	if party.leader != kicker_id:
		return false
	
	party.members.erase(kicked_id)
	player_parties.erase(kicked_id)
	
	emit_signal("member_kicked", party_id, kicked_id)
	rpc("on_member_kicked", party_id, kicked_id)
	
	return true

func transfer_leadership(current_leader_id, new_leader_id):
	var party_id = player_parties.get(current_leader_id)
	if not party_id or party_id != player_parties.get(new_leader_id):
		return false
	
	var party = parties[party_id]
	if party.leader != current_leader_id:
		return false
	
	party.leader = new_leader_id
	party.members[current_leader_id].role = PartyRole.MEMBER
	party.members[new_leader_id].role = PartyRole.LEADER
	
	emit_signal("leader_changed", party_id, new_leader_id)
	rpc("on_leader_changed", party_id, new_leader_id)
	
	return true

func update_party_settings(leader_id, new_settings):
	var party_id = player_parties.get(leader_id)
	if not party_id or not parties.has(party_id):
		return false
	
	var party = parties[party_id]
	if party.leader != leader_id:
		return false
	
	party.settings = new_settings
	
	emit_signal("party_settings_changed", party_id, new_settings)
	rpc("on_party_settings_changed", party_id, new_settings)
	
	return true

func update_member_info(player_id, info):
	var party_id = player_parties.get(player_id)
	if not party_id or not parties.has(party_id):
		return false
	
	var party = parties[party_id]
	if not party.members.has(player_id):
		return false
	
	for key in info:
		party.members[player_id][key] = info[key]
	
	rpc("on_member_info_updated", party_id, player_id, info)
	
	return true

func distribute_experience(party_id, total_xp, source_position):
	if not parties.has(party_id):
		return
	
	var party = parties[party_id]
	var eligible_members = []
	
	for member_id in party.members:
		var member = party.members[member_id]
		if member.position.distance_to(source_position) <= party_config.xp_share_range:
			eligible_members.append(member_id)
	
	if eligible_members.size() == 0:
		return
	
	var xp_per_member = total_xp / eligible_members.size()
	
	for member_id in eligible_members:
		rpc_id(member_id, "receive_party_xp", xp_per_member)

func handle_loot_drop(party_id, item_data, drop_position):
	if not parties.has(party_id):
		return null
	
	var party = parties[party_id]
	var eligible_members = []
	
	for member_id in party.members:
		var member = party.members[member_id]
		if member.position.distance_to(drop_position) <= party_config.loot_share_range:
			eligible_members.append(member_id)
	
	if eligible_members.size() == 0:
		return null
	
	match party.settings.loot_mode:
		LootMode.FREE_FOR_ALL:
			return null
		LootMode.ROUND_ROBIN:
			var recipient = eligible_members[party.round_robin_index % eligible_members.size()]
			party.round_robin_index += 1
			return recipient
		LootMode.MASTER_LOOTER:
			return party.leader
		LootMode.NEED_GREED:
			return null
	
	return null

func _transfer_leadership(party_id):
	var party = parties[party_id]
	var new_leader = null
	
	for member_id in party.members:
		new_leader = member_id
		break
	
	if new_leader:
		party.leader = new_leader
		party.members[new_leader].role = PartyRole.LEADER
		emit_signal("leader_changed", party_id, new_leader)
		rpc("on_leader_changed", party_id, new_leader)

func _process(delta):
	_check_invite_timeouts()

func _check_invite_timeouts():
	var current_time = OS.get_unix_time()
	var expired_invites = []
	
	for player_id in party_invites:
		var invite = party_invites[player_id]
		if current_time - invite.timestamp > party_config.invite_timeout:
			expired_invites.append(player_id)
	
	for player_id in expired_invites:
		party_invites.erase(player_id)

func _generate_party_id():
	return "party_" + str(OS.get_unix_time()) + "_" + str(randi() % 10000)

remote func receive_party_invite(party_id, inviter_id):
	pass

remote func on_party_created(party_id, party_data):
	parties[party_id] = party_data

remote func on_party_disbanded(party_id):
	parties.erase(party_id)

remote func on_member_joined(party_id, player_id):
	pass

remote func on_member_left(party_id, player_id):
	pass

remote func on_member_kicked(party_id, player_id):
	pass

remote func on_leader_changed(party_id, new_leader_id):
	pass

remote func on_party_settings_changed(party_id, settings):
	pass

remote func on_member_info_updated(party_id, player_id, info):
	pass

remote func receive_party_xp(xp_amount):
	pass

func get_party_data(party_id):
	return parties.get(party_id)

func get_player_party(player_id):
	return player_parties.get(player_id)

func get_party_members(party_id):
	if parties.has(party_id):
		return parties[party_id].members
	return {}

func is_party_leader(player_id):
	var party_id = player_parties.get(player_id)
	if party_id and parties.has(party_id):
		return parties[party_id].leader == player_id
	return false

func get_party_size(party_id):
	if parties.has(party_id):
		return parties[party_id].members.size()
	return 0