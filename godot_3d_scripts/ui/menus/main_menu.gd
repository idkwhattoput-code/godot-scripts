extends Control

export var game_scene_path = "res://Game.tscn"
export var settings_scene_path = "res://Settings.tscn"
export var credits_scene_path = "res://Credits.tscn"
export var enable_continue_button = true
export var enable_multiplayer = true
export var enable_quit_button = true
export var transition_time = 0.5

var save_exists = false
var is_transitioning = false

onready var title_label = $VBoxContainer/TitleLabel
onready var version_label = $VersionLabel
onready var button_container = $VBoxContainer/ButtonContainer
onready var continue_button = $VBoxContainer/ButtonContainer/ContinueButton
onready var new_game_button = $VBoxContainer/ButtonContainer/NewGameButton
onready var load_game_button = $VBoxContainer/ButtonContainer/LoadGameButton
onready var multiplayer_button = $VBoxContainer/ButtonContainer/MultiplayerButton
onready var settings_button = $VBoxContainer/ButtonContainer/SettingsButton
onready var credits_button = $VBoxContainer/ButtonContainer/CreditsButton
onready var quit_button = $VBoxContainer/ButtonContainer/QuitButton
onready var background_animation = $BackgroundAnimation
onready var menu_music = $MenuMusic
onready var button_hover_sound = $ButtonHoverSound
onready var button_click_sound = $ButtonClickSound
onready var confirm_dialog = $ConfirmDialog
onready var fade_overlay = $FadeOverlay

signal game_started()
signal menu_closed()

func _ready():
	_setup_menu()
	_connect_signals()
	_check_save_file()
	_animate_intro()
	
	if menu_music:
		menu_music.play()

func _setup_menu():
	if version_label:
		version_label.text = "v" + ProjectSettings.get_setting("application/config/version", "1.0.0")
	
	continue_button.visible = enable_continue_button
	multiplayer_button.visible = enable_multiplayer
	quit_button.visible = enable_quit_button
	
	for button in button_container.get_children():
		if button is Button:
			button.connect("mouse_entered", self, "_on_button_hover", [button])
			button.connect("focus_entered", self, "_on_button_hover", [button])

func _connect_signals():
	continue_button.connect("pressed", self, "_on_continue_pressed")
	new_game_button.connect("pressed", self, "_on_new_game_pressed")
	load_game_button.connect("pressed", self, "_on_load_game_pressed")
	multiplayer_button.connect("pressed", self, "_on_multiplayer_pressed")
	settings_button.connect("pressed", self, "_on_settings_pressed")
	credits_button.connect("pressed", self, "_on_credits_pressed")
	quit_button.connect("pressed", self, "_on_quit_pressed")

func _check_save_file():
	var save_file = File.new()
	save_exists = save_file.file_exists("user://savegame.dat")
	
	continue_button.disabled = not save_exists
	if not save_exists:
		continue_button.modulate.a = 0.5

func _animate_intro():
	var tween = Tween.new()
	add_child(tween)
	
	for i in range(button_container.get_child_count()):
		var button = button_container.get_child(i)
		if button is Button:
			button.modulate.a = 0
			button.rect_position.x -= 100
			
			tween.interpolate_property(button, "modulate:a", 0, 1, 0.3, 
				Tween.TRANS_QUAD, Tween.EASE_OUT, i * 0.1)
			tween.interpolate_property(button, "rect_position:x", 
				button.rect_position.x, button.rect_position.x + 100, 0.3,
				Tween.TRANS_QUAD, Tween.EASE_OUT, i * 0.1)
	
	if title_label:
		title_label.modulate.a = 0
		tween.interpolate_property(title_label, "modulate:a", 0, 1, 1.0,
			Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	
	tween.start()
	yield(tween, "tween_all_completed")
	tween.queue_free()

func _on_button_hover(button: Button):
	if button_hover_sound:
		button_hover_sound.play()
	
	var tween = Tween.new()
	add_child(tween)
	tween.interpolate_property(button, "rect_scale", Vector2(1, 1), Vector2(1.05, 1.05), 0.1)
	tween.start()
	
	button.connect("mouse_exited", self, "_on_button_exit", [button, tween], CONNECT_ONESHOT)
	button.connect("focus_exited", self, "_on_button_exit", [button, tween], CONNECT_ONESHOT)

func _on_button_exit(button: Button, tween: Tween):
	tween.interpolate_property(button, "rect_scale", button.rect_scale, Vector2(1, 1), 0.1)
	tween.start()
	yield(tween, "tween_all_completed")
	tween.queue_free()

func _on_continue_pressed():
	if not save_exists or is_transitioning:
		return
	
	_play_button_sound()
	_transition_to_game(true)

func _on_new_game_pressed():
	if is_transitioning:
		return
	
	_play_button_sound()
	
	if save_exists:
		confirm_dialog.dialog_text = "Starting a new game will overwrite your existing save. Continue?"
		confirm_dialog.popup_centered()
		
		yield(confirm_dialog, "confirmed")
	
	_transition_to_game(false)

func _on_load_game_pressed():
	if is_transitioning:
		return
	
	_play_button_sound()
	_transition_to_scene("res://LoadGameMenu.tscn")

func _on_multiplayer_pressed():
	if is_transitioning:
		return
	
	_play_button_sound()
	_transition_to_scene("res://MultiplayerLobby.tscn")

func _on_settings_pressed():
	if is_transitioning:
		return
	
	_play_button_sound()
	_transition_to_scene(settings_scene_path)

func _on_credits_pressed():
	if is_transitioning:
		return
	
	_play_button_sound()
	_transition_to_scene(credits_scene_path)

func _on_quit_pressed():
	if is_transitioning:
		return
	
	_play_button_sound()
	
	confirm_dialog.dialog_text = "Are you sure you want to quit?"
	confirm_dialog.popup_centered()
	
	yield(confirm_dialog, "confirmed")
	
	_animate_outro()
	yield(get_tree().create_timer(0.5), "timeout")
	get_tree().quit()

func _play_button_sound():
	if button_click_sound:
		button_click_sound.play()

func _transition_to_game(load_save: bool):
	is_transitioning = true
	emit_signal("game_started")
	
	if load_save:
		GameData.load_game()
	else:
		GameData.new_game()
	
	_animate_outro()
	yield(get_tree().create_timer(transition_time), "timeout")
	
	get_tree().change_scene(game_scene_path)

func _transition_to_scene(scene_path: String):
	is_transitioning = true
	
	_animate_outro()
	yield(get_tree().create_timer(transition_time), "timeout")
	
	get_tree().change_scene(scene_path)

func _animate_outro():
	var tween = Tween.new()
	add_child(tween)
	
	if fade_overlay:
		fade_overlay.show()
		fade_overlay.modulate.a = 0
		tween.interpolate_property(fade_overlay, "modulate:a", 0, 1, transition_time)
	
	for button in button_container.get_children():
		if button is Button:
			tween.interpolate_property(button, "modulate:a", 1, 0, transition_time * 0.5)
	
	if menu_music:
		tween.interpolate_property(menu_music, "volume_db", 
			menu_music.volume_db, -40, transition_time)
	
	tween.start()
	
	emit_signal("menu_closed")

func set_game_title(title: String):
	if title_label:
		title_label.text = title

func refresh_save_status():
	_check_save_file()

func show_notification(message: String, duration: float = 2.0):
	var notification = Label.new()
	notification.text = message
	notification.add_stylebox_override("normal", load("res://notification_style.tres"))
	notification.rect_position = Vector2(OS.window_size.x / 2 - 150, OS.window_size.y - 100)
	notification.rect_min_size = Vector2(300, 50)
	add_child(notification)
	
	var tween = Tween.new()
	add_child(tween)
	
	notification.modulate.a = 0
	tween.interpolate_property(notification, "modulate:a", 0, 1, 0.3)
	tween.start()
	
	yield(get_tree().create_timer(duration), "timeout")
	
	tween.interpolate_property(notification, "modulate:a", 1, 0, 0.3)
	tween.start()
	
	yield(tween, "tween_all_completed")
	notification.queue_free()
	tween.queue_free()

class GameData:
	static func load_game():
		print("Loading saved game...")
	
	static func new_game():
		print("Starting new game...")