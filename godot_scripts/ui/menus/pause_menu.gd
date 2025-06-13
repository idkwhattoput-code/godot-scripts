extends Control

export var blur_background = true
export var pause_game = true
export var show_game_time = true
export var enable_quick_save = true

var is_paused = false
var game_time = 0.0
var can_pause = true

onready var main_panel = $MainPanel
onready var resume_button = $MainPanel/ButtonContainer/ResumeButton
onready var save_button = $MainPanel/ButtonContainer/SaveButton
onready var load_button = $MainPanel/ButtonContainer/LoadButton
onready var settings_button = $MainPanel/ButtonContainer/SettingsButton
onready var help_button = $MainPanel/ButtonContainer/HelpButton
onready var quit_button = $MainPanel/ButtonContainer/QuitButton
onready var game_time_label = $MainPanel/GameTimeLabel
onready var blur_overlay = $BlurOverlay
onready var settings_menu = $SettingsMenu
onready var save_menu = $SaveMenu
onready var load_menu = $LoadMenu
onready var help_menu = $HelpMenu
onready var confirm_dialog = $ConfirmDialog
onready var notification_label = $NotificationLabel

signal game_resumed()
signal game_saved()
signal game_loaded()
signal quit_to_menu()
signal quit_to_desktop()

func _ready():
	hide()
	_setup_ui()
	_connect_signals()
	
	set_process(false)
	set_process_input(true)

func _setup_ui():
	main_panel.show()
	settings_menu.hide()
	save_menu.hide()
	load_menu.hide()
	help_menu.hide()
	notification_label.hide()
	
	if blur_background and blur_overlay:
		blur_overlay.material = preload("res://blur_shader.tres")
	
	game_time_label.visible = show_game_time
	save_button.visible = enable_quick_save

func _connect_signals():
	resume_button.connect("pressed", self, "_on_resume_pressed")
	save_button.connect("pressed", self, "_on_save_pressed")
	load_button.connect("pressed", self, "_on_load_pressed")
	settings_button.connect("pressed", self, "_on_settings_pressed")
	help_button.connect("pressed", self, "_on_help_pressed")
	quit_button.connect("pressed", self, "_on_quit_pressed")
	
	if settings_menu:
		settings_menu.connect("back_pressed", self, "_on_settings_back")
	if save_menu:
		save_menu.connect("save_selected", self, "_on_save_selected")
		save_menu.connect("back_pressed", self, "_on_save_back")
	if load_menu:
		load_menu.connect("load_selected", self, "_on_load_selected")
		load_menu.connect("back_pressed", self, "_on_load_back")
	if help_menu:
		help_menu.connect("back_pressed", self, "_on_help_back")

func _input(event):
	if event.is_action_pressed("pause_menu") and can_pause:
		if is_paused:
			resume_game()
		else:
			pause_game()

func pause_game():
	if is_paused or not can_pause:
		return
	
	is_paused = true
	show()
	
	if pause_game:
		get_tree().paused = true
	
	set_process(true)
	
	# Update game time
	if show_game_time:
		_update_game_time_display()
	
	# Play pause sound
	if has_node("PauseSound"):
		$PauseSound.play()
	
	# Animate menu appearance
	_animate_menu_in()
	
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func resume_game():
	if not is_paused:
		return
	
	is_paused = false
	
	_animate_menu_out()
	
	yield(get_tree().create_timer(0.2), "timeout")
	
	hide()
	
	if pause_game:
		get_tree().paused = false
	
	set_process(false)
	
	emit_signal("game_resumed")
	
	# Play resume sound
	if has_node("ResumeSound"):
		$ResumeSound.play()
	
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _animate_menu_in():
	var tween = Tween.new()
	add_child(tween)
	
	# Fade in background
	if blur_overlay:
		blur_overlay.modulate.a = 0
		tween.interpolate_property(blur_overlay, "modulate:a", 0, 1, 0.3)
	
	# Scale in main panel
	main_panel.rect_scale = Vector2(0.8, 0.8)
	main_panel.modulate.a = 0
	
	tween.interpolate_property(main_panel, "rect_scale", Vector2(0.8, 0.8), Vector2(1, 1), 0.3,
		Tween.TRANS_BACK, Tween.EASE_OUT)
	tween.interpolate_property(main_panel, "modulate:a", 0, 1, 0.3)
	
	tween.start()
	yield(tween, "tween_all_completed")
	tween.queue_free()

func _animate_menu_out():
	var tween = Tween.new()
	add_child(tween)
	
	# Fade out background
	if blur_overlay:
		tween.interpolate_property(blur_overlay, "modulate:a", 1, 0, 0.2)
	
	# Scale out main panel
	tween.interpolate_property(main_panel, "rect_scale", Vector2(1, 1), Vector2(0.8, 0.8), 0.2,
		Tween.TRANS_BACK, Tween.EASE_IN)
	tween.interpolate_property(main_panel, "modulate:a", 1, 0, 0.2)
	
	tween.start()
	yield(tween, "tween_all_completed")
	tween.queue_free()

func _on_resume_pressed():
	resume_game()

func _on_save_pressed():
	if enable_quick_save:
		_quick_save()
	else:
		_show_save_menu()

func _quick_save():
	# Perform quick save
	var save_data = _gather_save_data()
	var result = SaveSystem.quick_save(save_data)
	
	if result:
		show_notification("Game Saved!")
		emit_signal("game_saved")
	else:
		show_notification("Save Failed!", Color.red)

func _show_save_menu():
	main_panel.hide()
	save_menu.show()
	save_menu.refresh_save_slots()

func _on_save_selected(slot_index: int):
	var save_data = _gather_save_data()
	var result = SaveSystem.save_game(slot_index, save_data)
	
	if result:
		show_notification("Game Saved to Slot " + str(slot_index + 1))
		emit_signal("game_saved")
		_on_save_back()
	else:
		show_notification("Save Failed!", Color.red)

func _on_save_back():
	save_menu.hide()
	main_panel.show()

func _on_load_pressed():
	_show_load_menu()

func _show_load_menu():
	main_panel.hide()
	load_menu.show()
	load_menu.refresh_save_slots()

func _on_load_selected(slot_index: int):
	confirm_dialog.dialog_text = "Load game from slot %d? Unsaved progress will be lost." % (slot_index + 1)
	confirm_dialog.popup_centered()
	
	yield(confirm_dialog, "confirmed")
	
	var result = SaveSystem.load_game(slot_index)
	if result:
		emit_signal("game_loaded")
		resume_game()
		get_tree().reload_current_scene()
	else:
		show_notification("Load Failed!", Color.red)

func _on_load_back():
	load_menu.hide()
	main_panel.show()

func _on_settings_pressed():
	main_panel.hide()
	settings_menu.show()

func _on_settings_back():
	settings_menu.hide()
	main_panel.show()

func _on_help_pressed():
	main_panel.hide()
	help_menu.show()

func _on_help_back():
	help_menu.hide()
	main_panel.show()

func _on_quit_pressed():
	var quit_dialog = AcceptDialog.new()
	quit_dialog.dialog_text = "What would you like to do?"
	quit_dialog.window_title = "Quit Game"
	
	quit_dialog.add_button("Main Menu", false, "main_menu")
	quit_dialog.add_button("Desktop", false, "desktop")
	
	add_child(quit_dialog)
	quit_dialog.popup_centered()
	
	var result = yield(quit_dialog, "custom_action")
	
	match result:
		"main_menu":
			_quit_to_main_menu()
		"desktop":
			_quit_to_desktop()
	
	quit_dialog.queue_free()

func _quit_to_main_menu():
	confirm_dialog.dialog_text = "Return to main menu? Unsaved progress will be lost."
	confirm_dialog.popup_centered()
	
	yield(confirm_dialog, "confirmed")
	
	emit_signal("quit_to_menu")
	
	if pause_game:
		get_tree().paused = false
	
	get_tree().change_scene("res://MainMenu.tscn")

func _quit_to_desktop():
	confirm_dialog.dialog_text = "Quit to desktop? Unsaved progress will be lost."
	confirm_dialog.popup_centered()
	
	yield(confirm_dialog, "confirmed")
	
	emit_signal("quit_to_desktop")
	get_tree().quit()

func show_notification(text: String, color: Color = Color.green):
	notification_label.text = text
	notification_label.modulate = color
	notification_label.show()
	
	var tween = Tween.new()
	add_child(tween)
	
	# Fade in and out
	notification_label.modulate.a = 0
	tween.interpolate_property(notification_label, "modulate:a", 0, 1, 0.3)
	tween.interpolate_property(notification_label, "modulate:a", 1, 0, 0.3,
		Tween.TRANS_LINEAR, Tween.EASE_IN_OUT, 2.0)
	
	tween.start()
	
	yield(tween, "tween_all_completed")
	notification_label.hide()
	tween.queue_free()

func _update_game_time_display():
	game_time = OS.get_unix_time() - GameState.session_start_time
	
	var hours = int(game_time / 3600)
	var minutes = int((game_time % 3600) / 60)
	var seconds = int(game_time % 60)
	
	game_time_label.text = "Play Time: %02d:%02d:%02d" % [hours, minutes, seconds]

func _gather_save_data() -> Dictionary:
	return {
		"player_data": _get_player_data(),
		"game_state": _get_game_state(),
		"timestamp": OS.get_unix_time()
	}

func _get_player_data() -> Dictionary:
	# Gather player data from the game
	return {}

func _get_game_state() -> Dictionary:
	# Gather current game state
	return {}

func set_pause_enabled(enabled: bool):
	can_pause = enabled

func is_game_paused() -> bool:
	return is_paused

# Utility classes
class SaveSystem:
	static func quick_save(data: Dictionary) -> bool:
		return save_game(0, data)
	
	static func save_game(slot: int, data: Dictionary) -> bool:
		var save_file = File.new()
		var path = "user://save_slot_%d.dat" % slot
		
		if save_file.open(path, File.WRITE) != OK:
			return false
		
		save_file.store_var(data)
		save_file.close()
		return true
	
	static func load_game(slot: int) -> Dictionary:
		var save_file = File.new()
		var path = "user://save_slot_%d.dat" % slot
		
		if save_file.open(path, File.READ) != OK:
			return {}
		
		var data = save_file.get_var()
		save_file.close()
		return data

class GameState:
	static var session_start_time = OS.get_unix_time()