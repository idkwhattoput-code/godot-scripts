extends Control

export var enable_minimap = true
export var enable_quest_tracker = true
export var enable_hotbar = true
export var enable_status_effects = true
export var enable_compass = true
export var fade_when_inactive = true
export var inactive_alpha = 0.3

var player_reference = null
var is_hud_visible = true
var interaction_prompt_visible = false

onready var health_bar = $TopLeft/VitalBars/HealthBar
onready var health_label = $TopLeft/VitalBars/HealthBar/Label
onready var mana_bar = $TopLeft/VitalBars/ManaBar
onready var mana_label = $TopLeft/VitalBars/ManaBar/Label
onready var stamina_bar = $TopLeft/VitalBars/StaminaBar
onready var stamina_label = $TopLeft/VitalBars/StaminaBar/Label
onready var level_label = $TopLeft/PlayerInfo/LevelLabel
onready var exp_bar = $TopLeft/PlayerInfo/ExpBar
onready var minimap = $TopRight/Minimap
onready var compass = $Top/Compass
onready var quest_tracker = $Right/QuestTracker
onready var quest_list = $Right/QuestTracker/QuestList
onready var hotbar = $Bottom/Hotbar
onready var status_effects = $TopLeft/StatusEffects
onready var interaction_prompt = $Center/InteractionPrompt
onready var notification_container = $Center/NotificationContainer
onready var damage_numbers = $Center/DamageNumbers
onready var crosshair = $Center/Crosshair
onready var boss_health = $Top/BossHealth
onready var objective_popup = $Top/ObjectivePopup

signal hotbar_slot_used(slot_index)
signal minimap_clicked(position)

var current_health = 100
var max_health = 100
var current_mana = 50
var max_mana = 50
var current_stamina = 100
var max_stamina = 100
var current_exp = 0
var exp_to_next_level = 100
var player_level = 1

var active_quests = []
var active_status_effects = []
var hotbar_items = []
var boss_target = null

func _ready():
	_setup_ui()
	_connect_signals()
	_initialize_hotbar()
	
	set_process_input(true)

func _setup_ui():
	minimap.visible = enable_minimap
	quest_tracker.visible = enable_quest_tracker
	hotbar.visible = enable_hotbar
	status_effects.visible = enable_status_effects
	compass.visible = enable_compass
	
	boss_health.hide()
	objective_popup.hide()
	interaction_prompt.hide()
	
	_update_vital_displays()

func _connect_signals():
	if hotbar:
		for i in range(10):
			var slot = hotbar.get_node("Slot" + str(i))
			if slot:
				slot.connect("gui_input", self, "_on_hotbar_slot_input", [i])

func _initialize_hotbar():
	hotbar_items.resize(10)
	for i in range(10):
		hotbar_items[i] = null
		_update_hotbar_slot(i)

func _input(event):
	# Hotbar shortcuts
	for i in range(10):
		var key = i
		if i == 9:
			key = 0
		
		if event.is_action_pressed("hotbar_" + str(key + 1)):
			_use_hotbar_slot(i)
	
	# Toggle HUD visibility
	if event.is_action_pressed("toggle_hud"):
		toggle_hud_visibility()

func set_player(player):
	player_reference = player
	
	if player.has_signal("health_changed"):
		player.connect("health_changed", self, "_on_player_health_changed")
	if player.has_signal("mana_changed"):
		player.connect("mana_changed", self, "_on_player_mana_changed")
	if player.has_signal("stamina_changed"):
		player.connect("stamina_changed", self, "_on_player_stamina_changed")
	if player.has_signal("level_changed"):
		player.connect("level_changed", self, "_on_player_level_changed")
	if player.has_signal("exp_changed"):
		player.connect("exp_changed", self, "_on_player_exp_changed")

func _on_player_health_changed(current, maximum):
	current_health = current
	max_health = maximum
	_update_health_display()

func _on_player_mana_changed(current, maximum):
	current_mana = current
	max_mana = maximum
	_update_mana_display()

func _on_player_stamina_changed(current, maximum):
	current_stamina = current
	max_stamina = maximum
	_update_stamina_display()

func _on_player_level_changed(level):
	player_level = level
	level_label.text = "Level " + str(level)

func _on_player_exp_changed(current, to_next_level):
	current_exp = current
	exp_to_next_level = to_next_level
	_update_exp_display()

func _update_vital_displays():
	_update_health_display()
	_update_mana_display()
	_update_stamina_display()
	_update_exp_display()

func _update_health_display():
	health_bar.value = (float(current_health) / float(max_health)) * 100
	health_label.text = "%d / %d" % [current_health, max_health]
	
	# Change color based on health percentage
	var health_percent = float(current_health) / float(max_health)
	if health_percent <= 0.25:
		health_bar.modulate = Color.red
	elif health_percent <= 0.5:
		health_bar.modulate = Color.yellow
	else:
		health_bar.modulate = Color.green

func _update_mana_display():
	mana_bar.value = (float(current_mana) / float(max_mana)) * 100
	mana_label.text = "%d / %d" % [current_mana, max_mana]

func _update_stamina_display():
	stamina_bar.value = (float(current_stamina) / float(max_stamina)) * 100
	stamina_label.text = "%d / %d" % [current_stamina, max_stamina]

func _update_exp_display():
	exp_bar.value = (float(current_exp) / float(exp_to_next_level)) * 100

func show_interaction_prompt(text: String, key: String = "E"):
	interaction_prompt.get_node("Label").text = "[%s] %s" % [key, text]
	interaction_prompt.show()
	interaction_prompt_visible = true

func hide_interaction_prompt():
	interaction_prompt.hide()
	interaction_prompt_visible = false

func show_notification(text: String, duration: float = 3.0, color: Color = Color.white):
	var notification = Label.new()
	notification.text = text
	notification.modulate = color
	notification.add_stylebox_override("normal", preload("res://notification_style.tres"))
	
	notification_container.add_child(notification)
	
	var tween = Tween.new()
	add_child(tween)
	
	# Fade in
	notification.modulate.a = 0
	tween.interpolate_property(notification, "modulate:a", 0, 1, 0.3)
	tween.start()
	
	yield(get_tree().create_timer(duration), "timeout")
	
	# Fade out
	tween.interpolate_property(notification, "modulate:a", 1, 0, 0.5)
	tween.start()
	
	yield(tween, "tween_all_completed")
	notification.queue_free()
	tween.queue_free()

func show_damage_number(amount: int, position: Vector2, is_critical: bool = false, damage_type: String = "physical"):
	var damage_label = Label.new()
	damage_label.text = str(amount)
	
	# Set color based on damage type
	match damage_type:
		"physical":
			damage_label.modulate = Color.white
		"fire":
			damage_label.modulate = Color.orange
		"ice":
			damage_label.modulate = Color.cyan
		"poison":
			damage_label.modulate = Color.green
		"heal":
			damage_label.modulate = Color.green
			damage_label.text = "+" + damage_label.text
		_:
			damage_label.modulate = Color.white
	
	if is_critical:
		damage_label.text = damage_label.text + "!"
		damage_label.rect_scale = Vector2(1.5, 1.5)
	
	damage_numbers.add_child(damage_label)
	damage_label.rect_position = position
	
	# Animate the damage number
	var tween = Tween.new()
	add_child(tween)
	
	var end_pos = position + Vector2(rand_range(-50, 50), -100)
	
	tween.interpolate_property(damage_label, "rect_position", position, end_pos, 1.0,
		Tween.TRANS_QUAD, Tween.EASE_OUT)
	tween.interpolate_property(damage_label, "modulate:a", 1.0, 0.0, 1.0,
		Tween.TRANS_LINEAR, Tween.EASE_IN)
	
	tween.start()
	
	yield(tween, "tween_all_completed")
	damage_label.queue_free()
	tween.queue_free()

func update_quest_tracker(quests: Array):
	active_quests = quests
	quest_list.clear()
	
	for quest in active_quests:
		quest_list.add_item(quest.name)
		
		for objective in quest.objectives:
			var obj_text = "  - " + objective.description
			if objective.current > 0:
				obj_text += " (%d/%d)" % [objective.current, objective.required]
			
			quest_list.add_item(obj_text)
			quest_list.set_item_custom_fg_color(quest_list.get_item_count() - 1, Color(0.8, 0.8, 0.8))
			quest_list.set_item_custom_bg_color(quest_list.get_item_count() - 1, Color(0, 0, 0, 0))

func add_status_effect(effect_name: String, icon_path: String, duration: float = -1):
	var effect_icon = TextureRect.new()
	effect_icon.texture = load(icon_path)
	effect_icon.rect_min_size = Vector2(32, 32)
	effect_icon.name = effect_name
	
	status_effects.add_child(effect_icon)
	active_status_effects.append(effect_name)
	
	if duration > 0:
		yield(get_tree().create_timer(duration), "timeout")
		remove_status_effect(effect_name)

func remove_status_effect(effect_name: String):
	if status_effects.has_node(effect_name):
		status_effects.get_node(effect_name).queue_free()
		active_status_effects.erase(effect_name)

func set_hotbar_item(slot_index: int, item_data: Dictionary):
	if slot_index < 0 or slot_index >= 10:
		return
	
	hotbar_items[slot_index] = item_data
	_update_hotbar_slot(slot_index)

func _update_hotbar_slot(slot_index: int):
	var slot = hotbar.get_node("Slot" + str(slot_index))
	if not slot:
		return
	
	var icon = slot.get_node("Icon")
	var count = slot.get_node("Count")
	var keybind = slot.get_node("Keybind")
	
	if hotbar_items[slot_index]:
		var item = hotbar_items[slot_index]
		if item.has("icon"):
			icon.texture = load(item.icon)
		if item.has("count") and item.count > 1:
			count.text = str(item.count)
			count.show()
		else:
			count.hide()
	else:
		icon.texture = null
		count.hide()
	
	# Show keybind
	var key = slot_index + 1
	if slot_index == 9:
		key = 0
	keybind.text = str(key)

func _use_hotbar_slot(slot_index: int):
	if slot_index < 0 or slot_index >= 10:
		return
	
	if hotbar_items[slot_index]:
		emit_signal("hotbar_slot_used", slot_index)
		
		# Visual feedback
		var slot = hotbar.get_node("Slot" + str(slot_index))
		if slot:
			var tween = Tween.new()
			add_child(tween)
			
			tween.interpolate_property(slot, "rect_scale", Vector2(1, 1), Vector2(0.8, 0.8), 0.1)
			tween.interpolate_property(slot, "rect_scale", Vector2(0.8, 0.8), Vector2(1, 1), 0.1, 
				Tween.TRANS_LINEAR, Tween.EASE_IN_OUT, 0.1)
			
			tween.start()
			yield(tween, "tween_all_completed")
			tween.queue_free()

func show_boss_health(boss_name: String, current: int, maximum: int):
	boss_health.show()
	boss_health.get_node("NameLabel").text = boss_name
	boss_health.get_node("HealthBar").value = (float(current) / float(maximum)) * 100
	boss_health.get_node("HealthBar/Label").text = "%d / %d" % [current, maximum]

func hide_boss_health():
	boss_health.hide()

func show_objective(text: String, duration: float = 5.0):
	objective_popup.get_node("Label").text = text
	objective_popup.show()
	
	var tween = Tween.new()
	add_child(tween)
	
	# Slide in from top
	objective_popup.rect_position.y = -50
	tween.interpolate_property(objective_popup, "rect_position:y", -50, 10, 0.5,
		Tween.TRANS_QUAD, Tween.EASE_OUT)
	
	tween.start()
	
	yield(get_tree().create_timer(duration), "timeout")
	
	# Slide out
	tween.interpolate_property(objective_popup, "rect_position:y", 10, -50, 0.5,
		Tween.TRANS_QUAD, Tween.EASE_IN)
	
	tween.start()
	
	yield(tween, "tween_all_completed")
	objective_popup.hide()
	tween.queue_free()

func toggle_hud_visibility():
	is_hud_visible = !is_hud_visible
	visible = is_hud_visible

func set_crosshair_style(style: String):
	# Change crosshair based on context (default, interact, combat, etc.)
	pass

func update_minimap_position(player_pos: Vector3):
	if minimap and minimap.has_method("update_player_position"):
		minimap.update_player_position(player_pos)