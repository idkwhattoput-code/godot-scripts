extends Node

signal guild_created(guild_id, guild_data)
signal guild_disbanded(guild_id)
signal member_joined(guild_id, player_id)
signal member_left(guild_id, player_id)
signal member_promoted(guild_id, player_id, new_rank)
signal guild_level_up(guild_id, new_level)

enum GuildRank {
	MEMBER,
	OFFICER,
	VICE_LEADER,
	LEADER
}

var guilds = {}
var player_guilds = {}
var guild_invites = {}

var guild_config = {
	"max_members": 50,
	"creation_cost": 10000,
	"name_min_length": 3,
	"name_max_length": 20,
	"tag_length": 4,
	"xp_per_activity": 10,
	"levels": [
		{"xp": 0, "perks": ["guild_chat"]},
		{"xp": 1000, "perks": ["guild_bank", "increased_members_5"]},
		{"xp": 5000, "perks": ["guild_wars", "increased_members_10"]},
		{"xp": 15000, "perks": ["guild_buffs", "increased_members_15"]},
		{"xp": 50000, "perks": ["guild_hall", "increased_members_25"]}
	]
}

func _ready():
	if get_tree().is_network_server():
		_load_guilds()

func create_guild(player_id, guild_name, guild_tag):
	if not _validate_guild_creation(player_id, guild_name, guild_tag):
		return false
	
	var guild_id = _generate_guild_id()
	var guild_data = {
		"id": guild_id,
		"name": guild_name,
		"tag": guild_tag,
		"leader": player_id,
		"members": {
			player_id: {
				"rank": GuildRank.LEADER,
				"joined": OS.get_unix_time(),
				"contribution": 0
			}
		},
		"level": 1,
		"xp": 0,
		"bank": 0,
		"created": OS.get_unix_time(),
		"motd": "",
		"recruitment_open": true,
		"min_level_requirement": 1,
		"stats": {
			"wars_won": 0,
			"wars_lost": 0,
			"total_contribution": 0
		}
	}
	
	guilds[guild_id] = guild_data
	player_guilds[player_id] = guild_id
	
	emit_signal("guild_created", guild_id, guild_data)
	rpc("on_guild_created", guild_id, guild_data)
	
	return true

func disband_guild(player_id):
	var guild_id = player_guilds.get(player_id)
	if not guild_id or not guilds.has(guild_id):
		return false
	
	var guild = guilds[guild_id]
	if guild.leader != player_id:
		return false
	
	for member_id in guild.members:
		player_guilds.erase(member_id)
	
	guilds.erase(guild_id)
	
	emit_signal("guild_disbanded", guild_id)
	rpc("on_guild_disbanded", guild_id)
	
	return true

func invite_player(inviter_id, invited_id):
	var guild_id = player_guilds.get(inviter_id)
	if not guild_id or not guilds.has(guild_id):
		return false
	
	var guild = guilds[guild_id]
	var inviter_rank = guild.members[inviter_id].rank
	
	if inviter_rank < GuildRank.OFFICER:
		return false
	
	if player_guilds.has(invited_id):
		return false
	
	guild_invites[invited_id] = {
		"guild_id": guild_id,
		"inviter_id": inviter_id,
		"timestamp": OS.get_unix_time()
	}
	
	rpc_id(invited_id, "receive_guild_invite", guild_id, guild.name, inviter_id)
	return true

func accept_invite(player_id):
	if not guild_invites.has(player_id):
		return false
	
	var invite = guild_invites[player_id]
	var guild_id = invite.guild_id
	
	if not guilds.has(guild_id):
		guild_invites.erase(player_id)
		return false
	
	return join_guild(player_id, guild_id)

func join_guild(player_id, guild_id):
	if player_guilds.has(player_id):
		return false
	
	if not guilds.has(guild_id):
		return false
	
	var guild = guilds[guild_id]
	var max_members = guild_config.max_members + _get_member_bonus(guild.level)
	
	if guild.members.size() >= max_members:
		return false
	
	guild.members[player_id] = {
		"rank": GuildRank.MEMBER,
		"joined": OS.get_unix_time(),
		"contribution": 0
	}
	
	player_guilds[player_id] = guild_id
	guild_invites.erase(player_id)
	
	emit_signal("member_joined", guild_id, player_id)
	rpc("on_member_joined", guild_id, player_id)
	
	return true

func leave_guild(player_id):
	var guild_id = player_guilds.get(player_id)
	if not guild_id or not guilds.has(guild_id):
		return false
	
	var guild = guilds[guild_id]
	
	if guild.leader == player_id:
		if guild.members.size() > 1:
			_transfer_leadership(guild_id)
		else:
			return disband_guild(player_id)
	
	guild.members.erase(player_id)
	player_guilds.erase(player_id)
	
	emit_signal("member_left", guild_id, player_id)
	rpc("on_member_left", guild_id, player_id)
	
	return true

func kick_member(kicker_id, kicked_id):
	var guild_id = player_guilds.get(kicker_id)
	if not guild_id or guild_id != player_guilds.get(kicked_id):
		return false
	
	var guild = guilds[guild_id]
	var kicker_rank = guild.members[kicker_id].rank
	var kicked_rank = guild.members[kicked_id].rank
	
	if kicker_rank <= kicked_rank or kicker_rank < GuildRank.OFFICER:
		return false
	
	guild.members.erase(kicked_id)
	player_guilds.erase(kicked_id)
	
	emit_signal("member_left", guild_id, kicked_id)
	rpc("on_member_kicked", guild_id, kicked_id, kicker_id)
	
	return true

func promote_member(promoter_id, promoted_id, new_rank):
	var guild_id = player_guilds.get(promoter_id)
	if not guild_id or guild_id != player_guilds.get(promoted_id):
		return false
	
	var guild = guilds[guild_id]
	var promoter_rank = guild.members[promoter_id].rank
	
	if promoter_rank != GuildRank.LEADER:
		return false
	
	if new_rank >= GuildRank.LEADER:
		return false
	
	guild.members[promoted_id].rank = new_rank
	
	emit_signal("member_promoted", guild_id, promoted_id, new_rank)
	rpc("on_member_promoted", guild_id, promoted_id, new_rank)
	
	return true

func contribute_to_guild(player_id, contribution_type, amount):
	var guild_id = player_guilds.get(player_id)
	if not guild_id or not guilds.has(guild_id):
		return false
	
	var guild = guilds[guild_id]
	
	match contribution_type:
		"gold":
			guild.bank += amount
			guild.members[player_id].contribution += amount
			guild.stats.total_contribution += amount
		"xp":
			add_guild_xp(guild_id, amount)
	
	rpc("on_guild_contribution", guild_id, player_id, contribution_type, amount)
	return true

func add_guild_xp(guild_id, xp_amount):
	if not guilds.has(guild_id):
		return
	
	var guild = guilds[guild_id]
	guild.xp += xp_amount
	
	var new_level = _calculate_guild_level(guild.xp)
	if new_level > guild.level:
		guild.level = new_level
		emit_signal("guild_level_up", guild_id, new_level)
		rpc("on_guild_level_up", guild_id, new_level)

func _calculate_guild_level(total_xp):
	var level = 1
	for i in range(guild_config.levels.size()):
		if total_xp >= guild_config.levels[i].xp:
			level = i + 1
	return level

func _get_member_bonus(level):
	var bonus = 0
	for i in range(min(level, guild_config.levels.size())):
		for perk in guild_config.levels[i].perks:
			if perk.begins_with("increased_members_"):
				bonus += int(perk.split("_")[2])
	return bonus

func _transfer_leadership(guild_id):
	var guild = guilds[guild_id]
	var highest_rank = GuildRank.MEMBER
	var new_leader = null
	
	for member_id in guild.members:
		if member_id != guild.leader:
			var rank = guild.members[member_id].rank
			if rank > highest_rank:
				highest_rank = rank
				new_leader = member_id
	
	if new_leader:
		guild.leader = new_leader
		guild.members[new_leader].rank = GuildRank.LEADER

func _validate_guild_creation(player_id, guild_name, guild_tag):
	if player_guilds.has(player_id):
		return false
	
	if guild_name.length() < guild_config.name_min_length or guild_name.length() > guild_config.name_max_length:
		return false
	
	if guild_tag.length() != guild_config.tag_length:
		return false
	
	for guild_id in guilds:
		if guilds[guild_id].name == guild_name or guilds[guild_id].tag == guild_tag:
			return false
	
	return true

func _generate_guild_id():
	return "guild_" + str(OS.get_unix_time()) + "_" + str(randi() % 10000)

func _load_guilds():
	pass

func _save_guilds():
	pass

remote func on_guild_created(guild_id, guild_data):
	guilds[guild_id] = guild_data

remote func on_guild_disbanded(guild_id):
	guilds.erase(guild_id)

remote func on_member_joined(guild_id, player_id):
	pass

remote func on_member_left(guild_id, player_id):
	pass

remote func on_member_kicked(guild_id, kicked_id, kicker_id):
	pass

remote func on_member_promoted(guild_id, player_id, new_rank):
	pass

remote func on_guild_level_up(guild_id, new_level):
	pass

remote func on_guild_contribution(guild_id, player_id, contribution_type, amount):
	pass

remote func receive_guild_invite(guild_id, guild_name, inviter_id):
	pass

func get_player_guild(player_id):
	return player_guilds.get(player_id)

func get_guild_data(guild_id):
	return guilds.get(guild_id)

func get_guild_members(guild_id):
	if guilds.has(guild_id):
		return guilds[guild_id].members
	return {}

func search_guilds(search_term = "", filters = {}):
	var results = []
	for guild_id in guilds:
		var guild = guilds[guild_id]
		if search_term == "" or search_term.to_lower() in guild.name.to_lower():
			if _matches_filters(guild, filters):
				results.append({
					"id": guild_id,
					"name": guild.name,
					"tag": guild.tag,
					"level": guild.level,
					"members": guild.members.size(),
					"recruitment_open": guild.recruitment_open
				})
	return results

func _matches_filters(guild, filters):
	if filters.has("min_level") and guild.level < filters.min_level:
		return false
	if filters.has("has_space") and guild.members.size() >= guild_config.max_members:
		return false
	if filters.has("recruiting") and not guild.recruitment_open:
		return false
	return true