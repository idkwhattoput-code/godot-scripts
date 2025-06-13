extends Control

export var lobby_refresh_rate = 5.0
export var max_lobbies_displayed = 20
export var enable_password_protection = true

var current_lobbies = {}
var selected_lobby = null
var refresh_timer = 0.0
var is_hosting = false

onready var lobby_list = $MainPanel/LobbyList
onready var player_list = $LobbyPanel/PlayerList
onready var host_button = $MainPanel/HostButton
onready var join_button = $MainPanel/JoinButton
onready var refresh_button = $MainPanel/RefreshButton
onready var ready_button = $LobbyPanel/ReadyButton
onready var start_button = $LobbyPanel/StartButton
onready var leave_button = $LobbyPanel/LeaveButton
onready var lobby_name_input = $HostDialog/NameInput
onready var max_players_spin = $HostDialog/MaxPlayersSpin
onready var password_input = $HostDialog/PasswordInput
onready var main_panel = $MainPanel
onready var lobby_panel = $LobbyPanel
onready var host_dialog = $HostDialog
onready var join_dialog = $JoinDialog

signal lobby_created(lobby_info)
signal lobby_joined(lobby_id)
signal lobby_left()
signal game_starting()

func _ready():
	_setup_ui()
	_connect_signals()
	_connect_multiplayer_signals()
	
	refresh_lobby_list()

func _process(delta):
	refresh_timer += delta
	if refresh_timer >= lobby_refresh_rate and main_panel.visible:
		refresh_timer = 0.0
		refresh_lobby_list()

func _setup_ui():
	lobby_panel.hide()
	host_dialog.hide()
	join_dialog.hide()
	
	max_players_spin.value = 4
	max_players_spin.min_value = 2
	max_players_spin.max_value = 16

func _connect_signals():
	host_button.connect("pressed", self, "_on_host_pressed")
	join_button.connect("pressed", self, "_on_join_pressed")
	refresh_button.connect("pressed", self, "refresh_lobby_list")
	ready_button.connect("pressed", self, "_on_ready_pressed")
	start_button.connect("pressed", self, "_on_start_pressed")
	leave_button.connect("pressed", self, "_on_leave_pressed")
	
	lobby_list.connect("item_selected", self, "_on_lobby_selected")
	lobby_list.connect("item_activated", self, "_on_lobby_double_clicked")

func _connect_multiplayer_signals():
	MultiplayerManager.connect("player_connected", self, "_on_player_connected")
	MultiplayerManager.connect("player_disconnected", self, "_on_player_disconnected")
	MultiplayerManager.connect("connection_succeeded", self, "_on_connection_succeeded")
	MultiplayerManager.connect("connection_failed", self, "_on_connection_failed")
	MultiplayerManager.connect("server_disconnected", self, "_on_server_disconnected")
	MultiplayerManager.connect("player_list_changed", self, "_update_player_list")
	MultiplayerManager.connect("game_started", self, "_on_game_started")

func refresh_lobby_list():
	lobby_list.clear()
	
	for lobby_id in current_lobbies:
		var lobby = current_lobbies[lobby_id]
		var item_text = "%s - %d/%d players" % [lobby.name, lobby.current_players, lobby.max_players]
		
		if lobby.has_password:
			item_text += " 🔒"
		
		lobby_list.add_item(item_text)
		lobby_list.set_item_metadata(lobby_list.get_item_count() - 1, lobby_id)

func _on_host_pressed():
	host_dialog.popup_centered()

func _on_join_pressed():
	if selected_lobby == null:
		return
	
	var lobby = current_lobbies.get(selected_lobby)
	if lobby == null:
		return
	
	if lobby.has_password:
		join_dialog.popup_centered()
		join_dialog.get_node("PasswordInput").text = ""
	else:
		_join_lobby(selected_lobby)

func _on_lobby_selected(index: int):
	selected_lobby = lobby_list.get_item_metadata(index)
	join_button.disabled = false

func _on_lobby_double_clicked(index: int):
	selected_lobby = lobby_list.get_item_metadata(index)
	_on_join_pressed()

func _on_ready_pressed():
	var is_ready = ready_button.pressed
	MultiplayerManager.update_player_ready_state(is_ready)
	
	ready_button.text = "Not Ready" if is_ready else "Ready"

func _on_start_pressed():
	if not is_hosting:
		return
	
	if MultiplayerManager.are_all_players_ready():
		emit_signal("game_starting")
		MultiplayerManager.start_game()
	else:
		_show_message("Not all players are ready!")

func _on_leave_pressed():
	MultiplayerManager.close_connection()
	_return_to_main_menu()
	emit_signal("lobby_left")

func create_lobby():
	var lobby_name = lobby_name_input.text.strip_edges()
	if lobby_name == "":
		lobby_name = "Player's Lobby"
	
	var max_players = int(max_players_spin.value)
	var password = password_input.text.strip_edges()
	
	host_dialog.hide()
	
	if MultiplayerManager.host_game(MultiplayerManager.default_port, lobby_name):
		is_hosting = true
		_show_lobby_panel()
		
		var lobby_info = {
			"name": lobby_name,
			"max_players": max_players,
			"has_password": password != "",
			"password": password
		}
		
		emit_signal("lobby_created", lobby_info)
		
		_update_ui_for_host()

func _join_lobby(lobby_id: String, password: String = ""):
	var lobby = current_lobbies.get(lobby_id)
	if lobby == null:
		return
	
	if lobby.has_password and password != lobby.password:
		_show_message("Incorrect password!")
		return
	
	join_dialog.hide()
	
	if MultiplayerManager.join_game(lobby.ip, lobby.port, "Player"):
		_show_loading_screen()

func _show_lobby_panel():
	main_panel.hide()
	lobby_panel.show()
	_update_player_list()

func _return_to_main_menu():
	lobby_panel.hide()
	main_panel.show()
	is_hosting = false
	refresh_lobby_list()

func _update_player_list():
	player_list.clear()
	
	var players = MultiplayerManager.get_player_list()
	
	for player in players:
		var item_text = player.name
		
		if player.id == 1:
			item_text += " (Host)"
		
		if player.ready:
			item_text += " ✓"
		
		player_list.add_item(item_text)
		player_list.set_item_custom_fg_color(player_list.get_item_count() - 1, player.color)
	
	if is_hosting:
		start_button.disabled = not MultiplayerManager.are_all_players_ready()

func _update_ui_for_host():
	ready_button.hide()
	start_button.show()
	start_button.disabled = true

func _update_ui_for_client():
	ready_button.show()
	start_button.hide()

func _on_player_connected(id, info):
	if lobby_panel.visible:
		_show_message("Player joined: " + (info.name if info else "Unknown"))

func _on_player_disconnected(id):
	if lobby_panel.visible:
		_show_message("Player left")

func _on_connection_succeeded():
	_hide_loading_screen()
	_show_lobby_panel()
	_update_ui_for_client()
	emit_signal("lobby_joined", selected_lobby)

func _on_connection_failed():
	_hide_loading_screen()
	_show_message("Failed to connect to lobby")

func _on_server_disconnected():
	_return_to_main_menu()
	_show_message("Disconnected from lobby")

func _on_game_started():
	hide()

func _show_message(text: String):
	var dialog = AcceptDialog.new()
	dialog.dialog_text = text
	add_child(dialog)
	dialog.popup_centered()
	yield(dialog, "popup_hide")
	dialog.queue_free()

func _show_loading_screen():
	var loading_label = Label.new()
	loading_label.text = "Connecting..."
	loading_label.name = "LoadingLabel"
	add_child(loading_label)

func _hide_loading_screen():
	if has_node("LoadingLabel"):
		get_node("LoadingLabel").queue_free()

func add_lobby(lobby_info: Dictionary):
	var lobby_id = lobby_info.get("id", str(OS.get_unix_time()))
	current_lobbies[lobby_id] = lobby_info

func remove_lobby(lobby_id: String):
	current_lobbies.erase(lobby_id)

func update_lobby(lobby_id: String, lobby_info: Dictionary):
	if current_lobbies.has(lobby_id):
		current_lobbies[lobby_id] = lobby_info

func get_lobby_info(lobby_id: String) -> Dictionary:
	return current_lobbies.get(lobby_id, {})

func set_lobby_list(lobbies: Array):
	current_lobbies.clear()
	for lobby in lobbies:
		if lobby.has("id"):
			current_lobbies[lobby.id] = lobby
	refresh_lobby_list()