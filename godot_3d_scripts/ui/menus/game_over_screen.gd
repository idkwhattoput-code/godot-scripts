extends Control

export var fade_in_duration = 1.0
export var show_stats = true
export var enable_continue = true
export var continue_cost = 100
export var show_death_reason = true
export var auto_save_before_death = true

var death_reason = ""
var death_stats = {}
var can_continue = false
var is_processing_choice = false

onready var overlay = $Overlay
onready var main_panel = $CenterContainer/MainPanel
onready var title_label = $CenterContainer/MainPanel/VBox/TitleLabel
onready var subtitle_label = $CenterContainer/MainPanel/VBox/SubtitleLabel
onready var death_reason_label = $CenterContainer/MainPanel/VBox/DeathReasonLabel
onready var stats_container = $CenterContainer/MainPanel/VBox/StatsContainer
onready var button_container = $CenterContainer/MainPanel/VBox/ButtonContainer
onready var continue_button = $CenterContainer/MainPanel/VBox/ButtonContainer/ContinueButton
onready var restart_button = $CenterContainer/MainPanel/VBox/ButtonContainer/RestartButton
onready var load_button = $CenterContainer/MainPanel/VBox/ButtonContainer/LoadButton
onready var quit_button = $CenterContainer/MainPanel/VBox/ButtonContainer/QuitButton
onready var death_sound = $DeathSound
onready var music = $GameOverMusic

signal continue_selected()
signal restart_selected()
signal load_selected()
signal quit_selected()

var death_messages = {
	"fall": "You fell to your death",
	"combat": "You were defeated in combat",
	"drowning": "You drowned",
	"poison": "You succumbed to poison",
	"trap": "You triggered a deadly trap",
	"boss": "You were overwhelmed by a powerful foe",
	"environment": "The environment proved too harsh",
	"unknown": "You have died"
}

func _ready():
	hide()
	_setup_ui()
	_connect_signals()

func _setup_ui():
	overlay.color = Color(0, 0, 0, 0)
	main_panel.modulate.a = 0
	
	continue_button.visible = enable_continue
	death_reason_label.visible = show_death_reason
	stats_container.visible = show_stats
	
	if enable_continue:
		continue_button.text = "Continue (%d Gold)" % continue_cost

func _connect_signals():
	continue_button.connect("pressed", self, "_on_continue_pressed")
	restart_button.connect("pressed", self, "_on_restart_pressed")
	load_button.connect("pressed", self, "_on_load_pressed")
	quit_button.connect("pressed", self, "_on_quit_pressed")

func show_game_over(reason: String = "unknown", stats: Dictionary = {}):
	death_reason = reason
	death_stats = stats
	
	if auto_save_before_death:
		_create_death_save()
	
	show()
	
	_update_display()
	_animate_entrance()
	_play_sounds()
	
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _update_display():
	# Set death message
	if death_messages.has(death_reason):
		death_reason_label.text = death_messages[death_reason]
	else:
		death_reason_label.text = death_reason
	
	# Update continue button availability
	if enable_continue:
		var player_gold = GameState.get_player_gold()
		can_continue = player_gold >= continue_cost
		continue_button.disabled = !can_continue
		
		if not can_continue:
			continue_button.modulate = Color(0.5, 0.5, 0.5)
	
	# Display stats
	if show_stats and stats_container:
		_populate_stats()

func _populate_stats():
	# Clear existing stats
	for child in stats_container.get_children():
		child.queue_free()
	
	var stats_to_show = {
		"Time Survived": _format_time(death_stats.get("survival_time", 0)),
		"Enemies Defeated": str(death_stats.get("enemies_killed", 0)),
		"Damage Dealt": str(death_stats.get("damage_dealt", 0)),
		"Damage Taken": str(death_stats.get("damage_taken", 0)),
		"Gold Collected": str(death_stats.get("gold_collected", 0)),
		"Level Reached": str(death_stats.get("player_level", 1))
	}
	
	for stat_name in stats_to_show:
		var stat_line = HBoxContainer.new()
		
		var name_label = Label.new()
		name_label.text = stat_name + ":"
		name_label.rect_min_size.x = 150
		stat_line.add_child(name_label)
		
		var value_label = Label.new()
		value_label.text = stats_to_show[stat_name]
		value_label.modulate = Color(1, 1, 0.5)
		stat_line.add_child(value_label)
		
		stats_container.add_child(stat_line)

func _format_time(seconds: float) -> String:
	var minutes = int(seconds / 60)
	var secs = int(seconds % 60)
	return "%d:%02d" % [minutes, secs]

func _animate_entrance():
	var tween = Tween.new()
	add_child(tween)
	
	# Fade in overlay
	tween.interpolate_property(overlay, "color:a", 0, 0.8, fade_in_duration,
		Tween.TRANS_QUAD, Tween.EASE_OUT)
	
	# Fade in and scale main panel
	main_panel.rect_scale = Vector2(0.8, 0.8)
	tween.interpolate_property(main_panel, "modulate:a", 0, 1, fade_in_duration,
		Tween.TRANS_QUAD, Tween.EASE_OUT)
	tween.interpolate_property(main_panel, "rect_scale", Vector2(0.8, 0.8), Vector2(1, 1),
		fade_in_duration, Tween.TRANS_BACK, Tween.EASE_OUT)
	
	# Stagger button appearances
	var delay = 0.5
	for button in button_container.get_children():
		button.modulate.a = 0
		tween.interpolate_property(button, "modulate:a", 0, 1, 0.3,
			Tween.TRANS_QUAD, Tween.EASE_OUT, fade_in_duration + delay)
		delay += 0.1
	
	tween.start()
	yield(tween, "tween_all_completed")
	tween.queue_free()

func _play_sounds():
	if death_sound:
		death_sound.play()
	
	if music:
		music.play()

func _on_continue_pressed():
	if not can_continue or is_processing_choice:
		return
	
	is_processing_choice = true
	
	# Deduct gold
	GameState.spend_gold(continue_cost)
	
	# Restore player
	emit_signal("continue_selected")
	
	_animate_exit()

func _on_restart_pressed():
	if is_processing_choice:
		return
	
	is_processing_choice = true
	
	var confirm = ConfirmationDialog.new()
	confirm.dialog_text = "Restart from last checkpoint?"
	add_child(confirm)
	confirm.popup_centered()
	
	yield(confirm, "confirmed")
	
	emit_signal("restart_selected")
	_animate_exit()
	
	confirm.queue_free()

func _on_load_pressed():
	if is_processing_choice:
		return
	
	is_processing_choice = true
	
	emit_signal("load_selected")
	# The game should show the load menu

func _on_quit_pressed():
	if is_processing_choice:
		return
	
	is_processing_choice = true
	
	var confirm = ConfirmationDialog.new()
	confirm.dialog_text = "Return to main menu?"
	add_child(confirm)
	confirm.popup_centered()
	
	yield(confirm, "confirmed")
	
	emit_signal("quit_selected")
	get_tree().change_scene("res://MainMenu.tscn")
	
	confirm.queue_free()

func _animate_exit():
	var tween = Tween.new()
	add_child(tween)
	
	tween.interpolate_property(self, "modulate:a", 1, 0, 0.5,
		Tween.TRANS_QUAD, Tween.EASE_IN)
	
	if music:
		tween.interpolate_property(music, "volume_db", music.volume_db, -40, 0.5)
	
	tween.start()
	yield(tween, "tween_all_completed")
	
	hide()
	queue_free()

func _create_death_save():
	# Create an automatic save before death
	var save_data = {
		"is_death_save": true,
		"death_time": OS.get_unix_time(),
		"death_reason": death_reason,
		"death_stats": death_stats
	}
	
	# Save to a special slot
	SaveSystem.create_death_save(save_data)

func set_continue_enabled(enabled: bool):
	enable_continue = enabled
	continue_button.visible = enabled

func set_continue_cost(cost: int):
	continue_cost = cost
	if continue_button:
		continue_button.text = "Continue (%d Gold)" % cost

func add_death_message(key: String, message: String):
	death_messages[key] = message

func show_custom_stats(custom_stats: Dictionary):
	death_stats = custom_stats
	if is_visible_in_tree():
		_populate_stats()

# Helper classes
class GameState:
	static func get_player_gold() -> int:
		return 1000  # Placeholder
	
	static func spend_gold(amount: int):
		pass  # Placeholder

class SaveSystem:
	static func create_death_save(data: Dictionary):
		var file = File.new()
		if file.open("user://death_save.dat", File.WRITE) == OK:
			file.store_var(data)
			file.close()