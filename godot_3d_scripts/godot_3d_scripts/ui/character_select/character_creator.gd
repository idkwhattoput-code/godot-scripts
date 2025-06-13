extends Control

export var available_classes = ["Warrior", "Mage", "Rogue", "Ranger", "Paladin", "Necromancer"]
export var min_name_length = 3
export var max_name_length = 16
export var starting_stat_points = 10

var current_class_index = 0
var character_data = null
var remaining_stat_points = starting_stat_points
var base_stats = {
	"strength": 10,
	"agility": 10,
	"intelligence": 10,
	"vitality": 10,
	"wisdom": 10
}
var allocated_stats = {
	"strength": 0,
	"agility": 0,
	"intelligence": 0,
	"vitality": 0,
	"wisdom": 0
}

var appearance_options = {
	"hair_style": 0,
	"hair_color": 0,
	"skin_tone": 0,
	"face_type": 0,
	"body_type": 0,
	"voice_type": 0
}

onready var name_input = $StepsContainer/BasicInfo/NameInput
onready var class_label = $StepsContainer/BasicInfo/ClassSelection/ClassLabel
onready var class_prev_button = $StepsContainer/BasicInfo/ClassSelection/PrevButton
onready var class_next_button = $StepsContainer/BasicInfo/ClassSelection/NextButton
onready var class_description = $StepsContainer/BasicInfo/ClassDescription
onready var character_preview = $PreviewPanel/Viewport/CharacterModel
onready var preview_camera = $PreviewPanel/Viewport/Camera
onready var stat_container = $StepsContainer/Stats/StatContainer
onready var remaining_points_label = $StepsContainer/Stats/RemainingPointsLabel
onready var appearance_container = $StepsContainer/Appearance/OptionsContainer
onready var step_indicator = $StepIndicator
onready var prev_step_button = $NavigationButtons/PrevStepButton
onready var next_step_button = $NavigationButtons/NextStepButton
onready var create_button = $NavigationButtons/CreateButton
onready var cancel_button = $NavigationButtons/CancelButton

var current_step = 0
var total_steps = 3

signal character_created(character_data)
signal cancelled()

var class_descriptions = {
	"Warrior": "Masters of melee combat, excelling in strength and defense.",
	"Mage": "Wielders of arcane magic, dealing powerful elemental damage.",
	"Rogue": "Stealthy assassins specializing in critical strikes and evasion.",
	"Ranger": "Expert marksmen with nature magic and pet companions.",
	"Paladin": "Holy warriors combining combat prowess with divine magic.",
	"Necromancer": "Dark magic users who command the undead and drain life."
}

var class_base_stats = {
	"Warrior": {"strength": 15, "agility": 8, "intelligence": 5, "vitality": 12, "wisdom": 5},
	"Mage": {"strength": 5, "agility": 7, "intelligence": 15, "vitality": 8, "wisdom": 10},
	"Rogue": {"strength": 8, "agility": 15, "intelligence": 7, "vitality": 8, "wisdom": 7},
	"Ranger": {"strength": 10, "agility": 13, "intelligence": 7, "vitality": 10, "wisdom": 5},
	"Paladin": {"strength": 12, "agility": 8, "intelligence": 8, "vitality": 12, "wisdom": 5},
	"Necromancer": {"strength": 6, "agility": 8, "intelligence": 13, "vitality": 8, "wisdom": 10}
}

func _ready():
	_setup_ui()
	_connect_signals()
	_show_step(0)

func _setup_ui():
	create_button.hide()
	
	_setup_stat_controls()
	_setup_appearance_controls()
	_update_class_display()
	_update_remaining_points()

func _connect_signals():
	name_input.connect("text_changed", self, "_on_name_changed")
	class_prev_button.connect("pressed", self, "_on_class_prev")
	class_next_button.connect("pressed", self, "_on_class_next")
	prev_step_button.connect("pressed", self, "_on_prev_step")
	next_step_button.connect("pressed", self, "_on_next_step")
	create_button.connect("pressed", self, "_on_create_character")
	cancel_button.connect("pressed", self, "_on_cancel")

func _setup_stat_controls():
	for stat in base_stats:
		var stat_control = _create_stat_control(stat)
		stat_container.add_child(stat_control)

func _create_stat_control(stat_name: String) -> Control:
	var container = HBoxContainer.new()
	container.name = stat_name + "_container"
	
	var label = Label.new()
	label.text = stat_name.capitalize() + ":"
	label.rect_min_size.x = 100
	container.add_child(label)
	
	var value_label = Label.new()
	value_label.name = stat_name + "_value"
	value_label.text = str(base_stats[stat_name])
	value_label.rect_min_size.x = 40
	container.add_child(value_label)
	
	var minus_button = Button.new()
	minus_button.text = "-"
	minus_button.rect_min_size = Vector2(30, 30)
	minus_button.connect("pressed", self, "_on_stat_minus", [stat_name])
	container.add_child(minus_button)
	
	var plus_button = Button.new()
	plus_button.text = "+"
	plus_button.rect_min_size = Vector2(30, 30)
	plus_button.connect("pressed", self, "_on_stat_plus", [stat_name])
	container.add_child(plus_button)
	
	return container

func _setup_appearance_controls():
	var options = ["Hair Style", "Hair Color", "Skin Tone", "Face Type", "Body Type", "Voice Type"]
	
	for i in range(options.size()):
		var option_control = _create_appearance_control(options[i], appearance_options.keys()[i])
		appearance_container.add_child(option_control)

func _create_appearance_control(display_name: String, option_key: String) -> Control:
	var container = HBoxContainer.new()
	container.name = option_key + "_container"
	
	var label = Label.new()
	label.text = display_name + ":"
	label.rect_min_size.x = 120
	container.add_child(label)
	
	var prev_button = Button.new()
	prev_button.text = "<"
	prev_button.rect_min_size = Vector2(30, 30)
	prev_button.connect("pressed", self, "_on_appearance_prev", [option_key])
	container.add_child(prev_button)
	
	var value_label = Label.new()
	value_label.name = option_key + "_value"
	value_label.text = "Option 1"
	value_label.rect_min_size.x = 80
	value_label.align = Label.ALIGN_CENTER
	container.add_child(value_label)
	
	var next_button = Button.new()
	next_button.text = ">"
	next_button.rect_min_size = Vector2(30, 30)
	next_button.connect("pressed", self, "_on_appearance_next", [option_key])
	container.add_child(next_button)
	
	return container

func start_creation():
	character_data = CharacterData.new()
	current_step = 0
	_reset_stats()
	_show_step(0)
	name_input.text = ""
	name_input.grab_focus()

func _show_step(step: int):
	var steps = $StepsContainer.get_children()
	for i in range(steps.size()):
		steps[i].visible = i == step
	
	prev_step_button.visible = step > 0
	next_step_button.visible = step < total_steps - 1
	create_button.visible = step == total_steps - 1
	
	_update_step_indicator()

func _update_step_indicator():
	var step_names = ["Basic Info", "Stats", "Appearance"]
	step_indicator.text = "Step %d/%d: %s" % [current_step + 1, total_steps, step_names[current_step]]

func _on_prev_step():
	if current_step > 0:
		current_step -= 1
		_show_step(current_step)

func _on_next_step():
	if _validate_current_step():
		if current_step < total_steps - 1:
			current_step += 1
			_show_step(current_step)

func _validate_current_step() -> bool:
	match current_step:
		0:  # Basic Info
			var name = name_input.text.strip_edges()
			if name.length() < min_name_length:
				_show_error("Name must be at least %d characters long" % min_name_length)
				return false
			if name.length() > max_name_length:
				_show_error("Name must be no more than %d characters long" % max_name_length)
				return false
			if not _is_valid_name(name):
				_show_error("Name contains invalid characters")
				return false
			return true
		1:  # Stats
			return true
		2:  # Appearance
			return true
		_:
			return true

func _is_valid_name(name: String) -> bool:
	var regex = RegEx.new()
	regex.compile("^[a-zA-Z][a-zA-Z0-9_-]*$")
	return regex.search(name) != null

func _on_name_changed(new_text: String):
	var cleaned_text = ""
	for c in new_text:
		if c.is_valid_identifier() or c == "-":
			cleaned_text += c
	
	if cleaned_text != new_text:
		name_input.text = cleaned_text
		name_input.caret_position = cleaned_text.length()

func _on_class_prev():
	current_class_index = (current_class_index - 1) % available_classes.size()
	if current_class_index < 0:
		current_class_index = available_classes.size() - 1
	_update_class_display()
	_reset_stats()

func _on_class_next():
	current_class_index = (current_class_index + 1) % available_classes.size()
	_update_class_display()
	_reset_stats()

func _update_class_display():
	var class_name = available_classes[current_class_index]
	class_label.text = class_name
	class_description.text = class_descriptions.get(class_name, "")
	
	_update_character_preview()

func _update_character_preview():
	if not character_preview:
		return
	
	for child in character_preview.get_children():
		child.queue_free()
	
	var class_name = available_classes[current_class_index]
	var model_path = "res://models/characters/" + class_name.to_lower() + "_preview.tscn"
	
	if ResourceLoader.exists(model_path):
		var model = load(model_path).instance()
		character_preview.add_child(model)
		_apply_appearance_to_preview(model)

func _apply_appearance_to_preview(model):
	if model.has_method("set_appearance"):
		model.set_appearance(appearance_options)

func _reset_stats():
	var class_name = available_classes[current_class_index]
	base_stats = class_base_stats.get(class_name, base_stats).duplicate()
	
	for stat in allocated_stats:
		allocated_stats[stat] = 0
	
	remaining_stat_points = starting_stat_points
	_update_stat_display()
	_update_remaining_points()

func _on_stat_minus(stat: String):
	if allocated_stats[stat] > 0:
		allocated_stats[stat] -= 1
		remaining_stat_points += 1
		_update_stat_display()
		_update_remaining_points()

func _on_stat_plus(stat: String):
	if remaining_stat_points > 0:
		allocated_stats[stat] += 1
		remaining_stat_points -= 1
		_update_stat_display()
		_update_remaining_points()

func _update_stat_display():
	for stat in base_stats:
		var container = stat_container.get_node(stat + "_container")
		if container:
			var value_label = container.get_node(stat + "_value")
			var total = base_stats[stat] + allocated_stats[stat]
			value_label.text = str(total)
			
			if allocated_stats[stat] > 0:
				value_label.modulate = Color(0.2, 1.0, 0.2)
			else:
				value_label.modulate = Color.white

func _update_remaining_points():
	remaining_points_label.text = "Remaining Points: " + str(remaining_stat_points)

func _on_appearance_prev(option: String):
	appearance_options[option] = max(0, appearance_options[option] - 1)
	_update_appearance_display(option)
	_update_character_preview()

func _on_appearance_next(option: String):
	appearance_options[option] = min(9, appearance_options[option] + 1)
	_update_appearance_display(option)
	_update_character_preview()

func _update_appearance_display(option: String):
	var container = appearance_container.get_node(option + "_container")
	if container:
		var value_label = container.get_node(option + "_value")
		value_label.text = "Option " + str(appearance_options[option] + 1)

func _on_create_character():
	if not _validate_all_steps():
		return
	
	_finalize_character_data()
	emit_signal("character_created", character_data)

func _validate_all_steps() -> bool:
	current_step = 0
	for i in range(total_steps):
		if not _validate_current_step():
			_show_step(current_step)
			return false
		current_step += 1
	return true

func _finalize_character_data():
	character_data.name = name_input.text.strip_edges()
	character_data.class_type = available_classes[current_class_index]
	
	character_data.stats.clear()
	for stat in base_stats:
		character_data.stats[stat] = base_stats[stat] + allocated_stats[stat]
	
	character_data.appearance = appearance_options.duplicate()
	
	var class_name = available_classes[current_class_index]
	character_data.stats["health"] = 100 + (character_data.stats["vitality"] * 10)
	character_data.stats["mana"] = 50 + (character_data.stats["intelligence"] * 5)

func _on_cancel():
	emit_signal("cancelled")

func _show_error(message: String):
	var dialog = AcceptDialog.new()
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered()
	yield(dialog, "popup_hide")
	dialog.queue_free()

func _process(delta):
	if character_preview:
		character_preview.rotate_y(deg2rad(30) * delta)