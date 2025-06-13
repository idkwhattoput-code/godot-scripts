extends Node

export var default_port = 7000
export var max_clients = 8
export var use_upnp = true

var peer = null
var is_server = false
var player_info = {}
var my_info = {
	"name": "Player",
	"color": Color.white,
	"position": Vector3.ZERO,
	"ready": false
}

signal player_connected(id, info)
signal player_disconnected(id)
signal server_disconnected()
signal connection_failed()
signal connection_succeeded()
signal game_started()
signal player_list_changed()

func _ready():
	get_tree().connect("network_peer_connected", self, "_player_connected")
	get_tree().connect("network_peer_disconnected", self, "_player_disconnected")
	get_tree().connect("connected_to_server", self, "_connected_ok")
	get_tree().connect("connection_failed", self, "_connected_fail")
	get_tree().connect("server_disconnected", self, "_server_disconnected")
	
	if use_upnp:
		_setup_upnp()

func host_game(port: int = default_port, player_name: String = "Host") -> bool:
	peer = NetworkedMultiplayerENet.new()
	var result = peer.create_server(port, max_clients)
	
	if result != OK:
		print("Failed to create server")
		return false
	
	get_tree().set_network_peer(peer)
	is_server = true
	
	my_info.name = player_name
	my_info.color = Color(randf(), randf(), randf())
	
	player_info[1] = my_info
	
	print("Server started on port " + str(port))
	emit_signal("player_list_changed")
	
	return true

func join_game(ip: String, port: int = default_port, player_name: String = "Player") -> bool:
	peer = NetworkedMultiplayerENet.new()
	var result = peer.create_client(ip, port)
	
	if result != OK:
		print("Failed to create client")
		return false
	
	get_tree().set_network_peer(peer)
	is_server = false
	
	my_info.name = player_name
	my_info.color = Color(randf(), randf(), randf())
	
	print("Attempting to connect to " + ip + ":" + str(port))
	
	return true

func close_connection():
	if peer:
		peer.close_connection()
		get_tree().set_network_peer(null)
		peer = null
		is_server = false
		player_info.clear()
		emit_signal("player_list_changed")

func _player_connected(id):
	if is_server:
		rpc_id(id, "register_player", my_info)
		
		for p_id in player_info:
			if p_id != id:
				rpc_id(id, "register_player", player_info[p_id], p_id)
		
		emit_signal("player_connected", id, null)

func _player_disconnected(id):
	player_info.erase(id)
	emit_signal("player_disconnected", id)
	emit_signal("player_list_changed")
	
	if has_node("/root/World/Players/" + str(id)):
		get_node("/root/World/Players/" + str(id)).queue_free()

func _connected_ok():
	rpc("register_player", my_info)
	emit_signal("connection_succeeded")

func _connected_fail():
	get_tree().set_network_peer(null)
	peer = null
	emit_signal("connection_failed")

func _server_disconnected():
	get_tree().set_network_peer(null)
	peer = null
	player_info.clear()
	is_server = false
	emit_signal("server_disconnected")
	emit_signal("player_list_changed")

remote func register_player(info, id = null):
	if id == null:
		id = get_tree().get_rpc_sender_id()
	
	player_info[id] = info
	emit_signal("player_connected", id, info)
	emit_signal("player_list_changed")
	
	if has_node("/root/World"):
		spawn_player(id)

func spawn_player(id):
	var player_scene = preload("res://Player.tscn")
	var player = player_scene.instance()
	
	player.name = str(id)
	player.set_network_master(id)
	
	var spawn_pos = Vector3(rand_range(-10, 10), 0, rand_range(-10, 10))
	player.global_transform.origin = spawn_pos
	
	if player_info.has(id):
		player.set_player_name(player_info[id].name)
		player.set_player_color(player_info[id].color)
	
	if not has_node("/root/World/Players"):
		var players_node = Node.new()
		players_node.name = "Players"
		get_node("/root/World").add_child(players_node)
	
	get_node("/root/World/Players").add_child(player)

func get_player_list() -> Array:
	var players = []
	for id in player_info:
		var info = player_info[id].duplicate()
		info["id"] = id
		players.append(info)
	return players

func get_player_count() -> int:
	return player_info.size()

func is_player_connected(id: int) -> bool:
	return player_info.has(id)

func get_player_info(id: int) -> Dictionary:
	if player_info.has(id):
		return player_info[id]
	return {}

func kick_player(id: int):
	if is_server and id != 1:
		rpc_id(id, "kicked")
		peer.disconnect_peer(id)

remote func kicked():
	get_tree().quit()

func start_game():
	if not is_server:
		return
	
	rpc("begin_game")
	begin_game()

remotesync func begin_game():
	emit_signal("game_started")
	
	get_tree().change_scene("res://Game.tscn")

func send_player_position(position: Vector3, rotation: Vector3):
	rpc_unreliable("update_player_position", position, rotation)

remote func update_player_position(position: Vector3, rotation: Vector3):
	var sender_id = get_tree().get_rpc_sender_id()
	
	if has_node("/root/World/Players/" + str(sender_id)):
		var player = get_node("/root/World/Players/" + str(sender_id))
		player.update_remote_position(position, rotation)

func send_chat_message(message: String):
	rpc("receive_chat_message", my_info.name, message)

remotesync func receive_chat_message(sender_name: String, message: String):
	if has_node("/root/World/UI/Chat"):
		get_node("/root/World/UI/Chat").add_message(sender_name, message)

func update_player_ready_state(ready: bool):
	my_info.ready = ready
	rpc("update_ready_state", ready)

remote func update_ready_state(ready: bool):
	var sender_id = get_tree().get_rpc_sender_id()
	if player_info.has(sender_id):
		player_info[sender_id].ready = ready
		emit_signal("player_list_changed")

func are_all_players_ready() -> bool:
	if not is_server:
		return false
	
	for id in player_info:
		if not player_info[id].ready:
			return false
	
	return player_info.size() > 0

func _setup_upnp():
	var upnp = UPNP.new()
	
	var discover_result = upnp.discover()
	if discover_result != UPNP.UPNP_RESULT_SUCCESS:
		print("UPNP discover failed")
		return
	
	if upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
		var map_result = upnp.add_port_mapping(default_port, default_port, "Godot Game Server", "UDP")
		if map_result != UPNP.UPNP_RESULT_SUCCESS:
			print("UPNP port mapping failed")
			return
		
		print("UPNP port mapping successful")

func save_connection_info() -> Dictionary:
	return {
		"is_server": is_server,
		"port": default_port,
		"player_info": my_info
	}

func load_connection_info(data: Dictionary):
	if data.has("player_info"):
		my_info = data.player_info