extends CanvasLayer

@export var fade_duration: float = 1.0
@export var notification_duration: float = 3.0

@onready var health_bar: ProgressBar = $UI/TopPanel/HealthBar
@onready var score_label: Label = $UI/TopPanel/ScoreLabel
@onready var lives_label: Label = $UI/TopPanel/LivesLabel
@onready var pause_menu: Control = $UI/PauseMenu
@onready var game_over_screen: Control = $UI/GameOverScreen
@onready var victory_screen: Control = $UI/VictoryScreen
@onready var notification_panel: Control = $UI/NotificationPanel
@onready var notification_label: Label = $UI/NotificationPanel/NotificationLabel
@onready var fade_overlay: ColorRect = $UI/FadeOverlay

var notification_tween: Tween
var fade_tween: Tween

signal menu_button_pressed(button_name: String)

func _ready():
	if pause_menu:
		pause_menu.visible = false
	if game_over_screen:
		game_over_screen.visible = false
	if victory_screen:
		victory_screen.visible = false
	if notification_panel:
		notification_panel.visible = false
	
	setup_menu_buttons()

func setup_menu_buttons():
	connect_button("PauseMenu/ResumeButton", "resume")
	connect_button("PauseMenu/RestartButton", "restart")
	connect_button("PauseMenu/MainMenuButton", "main_menu")
	connect_button("GameOverScreen/RestartButton", "restart")
	connect_button("GameOverScreen/MainMenuButton", "main_menu")
	connect_button("VictoryScreen/NextLevelButton", "next_level")
	connect_button("VictoryScreen/MainMenuButton", "main_menu")

func connect_button(path: String, action: String):
	var button = get_node_or_null("UI/" + path)
	if button and button is Button:
		button.pressed.connect(func(): emit_signal("menu_button_pressed", action))

func update_health(current: int, maximum: int):
	if health_bar:
		health_bar.max_value = maximum
		health_bar.value = current
		
		var health_percentage = float(current) / float(maximum)
		if health_percentage < 0.3:
			health_bar.modulate = Color.RED
		elif health_percentage < 0.6:
			health_bar.modulate = Color.YELLOW
		else:
			health_bar.modulate = Color.GREEN

func update_score(score: int):
	if score_label:
		score_label.text = "Score: " + str(score)

func update_lives(lives: int):
	if lives_label:
		lives_label.text = "Lives: " + str(lives)

func show_notification(message: String, duration: float = -1):
	if not notification_panel or not notification_label:
		return
	
	if duration <= 0:
		duration = notification_duration
	
	notification_label.text = message
	notification_panel.visible = true
	
	if notification_tween:
		notification_tween.kill()
	
	notification_tween = create_tween()
	notification_panel.modulate.a = 0
	notification_tween.tween_property(notification_panel, "modulate:a", 1.0, 0.3)
	notification_tween.tween_delay(duration)
	notification_tween.tween_property(notification_panel, "modulate:a", 0.0, 0.3)
	notification_tween.tween_callback(func(): notification_panel.visible = false)

func show_pause_menu():
	if pause_menu:
		pause_menu.visible = true

func hide_pause_menu():
	if pause_menu:
		pause_menu.visible = false

func show_game_over():
	if game_over_screen:
		game_over_screen.visible = true

func hide_game_over():
	if game_over_screen:
		game_over_screen.visible = false

func show_victory():
	if victory_screen:
		victory_screen.visible = true

func hide_victory():
	if victory_screen:
		victory_screen.visible = false

func fade_in(duration: float = -1):
	if duration <= 0:
		duration = fade_duration
	
	if not fade_overlay:
		return
	
	fade_overlay.visible = true
	fade_overlay.color.a = 1.0
	
	if fade_tween:
		fade_tween.kill()
	
	fade_tween = create_tween()
	fade_tween.tween_property(fade_overlay, "color:a", 0.0, duration)
	fade_tween.tween_callback(func(): fade_overlay.visible = false)

func fade_out(duration: float = -1):
	if duration <= 0:
		duration = fade_duration
	
	if not fade_overlay:
		return
	
	fade_overlay.visible = true
	fade_overlay.color.a = 0.0
	
	if fade_tween:
		fade_tween.kill()
	
	fade_tween = create_tween()
	fade_tween.tween_property(fade_overlay, "color:a", 1.0, duration)

func fade_to_scene(scene_path: String, duration: float = -1):
	fade_out(duration)
	await fade_tween.finished
	get_tree().change_scene_to_file(scene_path)

func show_tooltip(text: String, position: Vector2):
	var tooltip = preload("res://ui/Tooltip.tscn").instantiate()
	add_child(tooltip)
	tooltip.setup(text, position)

func hide_all_menus():
	hide_pause_menu()
	hide_game_over()
	hide_victory()

func animate_score_increase(amount: int):
	if not score_label:
		return
	
	var popup = Label.new()
	popup.text = "+" + str(amount)
	popup.add_theme_color_override("font_color", Color.YELLOW)
	popup.position = score_label.global_position + Vector2(0, -30)
	add_child(popup)
	
	var popup_tween = create_tween()
	popup_tween.parallel().tween_property(popup, "position:y", popup.position.y - 50, 1.0)
	popup_tween.parallel().tween_property(popup, "modulate:a", 0.0, 1.0)
	popup_tween.tween_callback(popup.queue_free)

func update_display(score: int, lives: int, health: int = -1, max_health: int = -1):
	update_score(score)
	update_lives(lives)
	if health >= 0 and max_health > 0:
		update_health(health, max_health)