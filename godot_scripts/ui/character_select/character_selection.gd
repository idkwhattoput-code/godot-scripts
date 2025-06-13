extends Control

export var max_characters = 6
export var enable_character_creation = true
export var enable_character_deletion = true
export var auto_rotate_preview = true
export var rotation_speed = 30.0

var characters = []
var selected_character_index = -1
var is_creating_character = false

onready var character_grid = $MainPanel/CharacterGrid
onready var character_preview = $PreviewPanel/Viewport/CharacterPreview
onready var preview_camera = $PreviewPanel/Viewport/Camera
onready var character_info = $InfoPanel/CharacterInfo
onready var create_button = $ButtonPanel/CreateButton
onready var select_button = $ButtonPanel/SelectButton
onready var delete_button = $ButtonPanel/DeleteButton
onready var back_button = $ButtonPanel/BackButton
onready var character_creator = $CharacterCreator
onready var loading_screen = $LoadingScreen

signal character_selected(character_data)
signal character_created(character_data)
signal character_deleted(character_id)
signal back_pressed()

class CharacterData:
	var id: String = ""
	var name: String = "Unnamed"
	var class_type: String = "Warrior"
	var level: int = 1
	var play_time: float = 0.0
	var last_played: int = 0
	var appearance: Dictionary = {}
	var stats: Dictionary = {}
	var equipment: Dictionary = {}
	var location: String = "Starting Area"
	
	func _init():
		id = _generate_id()
		last_played = OS.get_unix_time()
		_initialize_default_stats()
	
	func _generate_id() -> String:
		return "char_" + str(OS.get_unix_time()) + "_" + str(randi() % 1000)
	
	func _initialize_default_stats():
		stats = {
			"health": 100,
			"mana": 50,
			"strength": 10,
			"agility": 10,
			"intelligence": 10
		}

func _ready():
	_setup_ui()
	_load_characters()
	_connect_signals()
	
	if characters.size() > 0:
		_select_character(0)

func _setup_ui():
	character_creator.hide()
	loading_screen.hide()
	
	select_button.disabled = true
	delete_button.disabled = true
	
	if not enable_character_creation:
		create_button.hide()
	
	if not enable_character_deletion:
		delete_button.hide()

func _connect_signals():
	create_button.connect("pressed", self, "_on_create_pressed")
	select_button.connect("pressed", self, "_on_select_pressed")
	delete_button.connect("pressed", self, "_on_delete_pressed")
	back_button.connect("pressed", self, "_on_back_pressed")
	
	if character_creator:
		character_creator.connect("character_created", self, "_on_character_creation_complete")
		character_creator.connect("cancelled", self, "_on_creation_cancelled")

func _load_characters():
	characters.clear()
	_clear_character_grid()
	
	var save_dir = Directory.new()
	if save_dir.open("user://characters/") != OK:
		save_dir.make_dir_recursive("user://characters/")
		return
	
	save_dir.list_dir_begin()
	var file_name = save_dir.get_next()
	
	while file_name != "":
		if file_name.ends_with(".char"):
			var character = _load_character_file("user://characters/" + file_name)
			if character:
				characters.append(character)
		file_name = save_dir.get_next()
	
	save_dir.list_dir_end()
	
	characters.sort_custom(self, "_sort_by_last_played")
	_populate_character_grid()

func _load_character_file(path: String) -> CharacterData:
	var file = File.new()
	if file.open(path, File.READ) != OK:
		return null
	
	var save_data = file.get_var()
	file.close()
	
	var character = CharacterData.new()
	character.id = save_data.get("id", character.id)
	character.name = save_data.get("name", "Unnamed")
	character.class_type = save_data.get("class", "Warrior")
	character.level = save_data.get("level", 1)
	character.play_time = save_data.get("play_time", 0.0)
	character.last_played = save_data.get("last_played", 0)
	character.appearance = save_data.get("appearance", {})
	character.stats = save_data.get("stats", character.stats)
	character.equipment = save_data.get("equipment", {})
	character.location = save_data.get("location", "Starting Area")
	
	return character

func _sort_by_last_played(a: CharacterData, b: CharacterData) -> bool:
	return a.last_played > b.last_played

func _populate_character_grid():
	for i in range(max_characters):
		var slot = _create_character_slot(i)
		character_grid.add_child(slot)
		
		if i < characters.size():
			_update_character_slot(slot, characters[i], i)
		else:
			_show_empty_slot(slot, i)

func _create_character_slot(index: int) -> Control:
	var slot = Panel.new()
	slot.rect_min_size = Vector2(200, 250)
	slot.name = "CharacterSlot" + str(index)
	
	var vbox = VBoxContainer.new()
	vbox.rect_min_size = slot.rect_min_size
	slot.add_child(vbox)
	
	var portrait = TextureRect.new()
	portrait.name = "Portrait"
	portrait.rect_min_size = Vector2(180, 150)
	portrait.expand = true
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(portrait)
	
	var name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.align = Label.ALIGN_CENTER
	vbox.add_child(name_label)
	
	var info_label = Label.new()
	info_label.name = "InfoLabel"
	info_label.align = Label.ALIGN_CENTER
	vbox.add_child(info_label)
	
	var button = Button.new()
	button.name = "SelectButton"
	button.connect("pressed", self, "_on_slot_clicked", [index])
	slot.add_child(button)
	button.rect_min_size = slot.rect_min_size
	button.flat = true
	
	return slot

func _update_character_slot(slot: Control, character: CharacterData, index: int):
	var portrait = slot.get_node("VBoxContainer/Portrait")
	var name_label = slot.get_node("VBoxContainer/NameLabel")
	var info_label = slot.get_node("VBoxContainer/InfoLabel")
	
	name_label.text = character.name
	info_label.text = "Lv.%d %s" % [character.level, character.class_type]
	
	var portrait_path = "res://portraits/" + character.class_type.to_lower() + ".png"
	if ResourceLoader.exists(portrait_path):
		portrait.texture = load(portrait_path)

func _show_empty_slot(slot: Control, index: int):
	var name_label = slot.get_node("VBoxContainer/NameLabel")
	var info_label = slot.get_node("VBoxContainer/InfoLabel")
	
	name_label.text = "Empty Slot"
	info_label.text = "Click to create"
	
	slot.modulate.a = 0.5

func _clear_character_grid():
	for child in character_grid.get_children():
		child.queue_free()

func _on_slot_clicked(index: int):
	if index < characters.size():
		_select_character(index)
	elif enable_character_creation and not is_creating_character:
		_start_character_creation()

func _select_character(index: int):
	selected_character_index = index
	var character = characters[index]
	
	select_button.disabled = false
	delete_button.disabled = not enable_character_deletion
	
	_update_character_preview(character)
	_update_character_info(character)
	
	for i in range(character_grid.get_child_count()):
		var slot = character_grid.get_child(i)
		slot.modulate = Color.white if i == index else Color(0.7, 0.7, 0.7)

func _update_character_preview(character: CharacterData):
	if not character_preview:
		return
	
	for child in character_preview.get_children():
		child.queue_free()
	
	var model_path = "res://models/characters/" + character.class_type.to_lower() + ".tscn"
	if ResourceLoader.exists(model_path):
		var model = load(model_path).instance()
		character_preview.add_child(model)
		
		if model.has_method("apply_appearance"):
			model.apply_appearance(character.appearance)

func _update_character_info(character: CharacterData):
	if not character_info:
		return
	
	character_info.clear()
	character_info.add_text("Name: " + character.name + "\n")
	character_info.add_text("Class: " + character.class_type + "\n")
	character_info.add_text("Level: " + str(character.level) + "\n")
	character_info.add_text("Location: " + character.location + "\n")
	character_info.add_text("\nStats:\n")
	
	for stat in character.stats:
		character_info.add_text("  " + stat.capitalize() + ": " + str(character.stats[stat]) + "\n")
	
	character_info.add_text("\nPlay Time: " + _format_play_time(character.play_time) + "\n")
	character_info.add_text("Last Played: " + _format_last_played(character.last_played))

func _format_play_time(seconds: float) -> String:
	var hours = int(seconds / 3600)
	var minutes = int((seconds % 3600) / 60)
	return "%d hours %d minutes" % [hours, minutes]

func _format_last_played(timestamp: int) -> String:
	var datetime = OS.get_datetime_from_unix_time(timestamp)
	return "%02d/%02d/%04d" % [datetime.day, datetime.month, datetime.year]

func _process(delta):
	if auto_rotate_preview and character_preview:
		character_preview.rotate_y(deg2rad(rotation_speed * delta))

func _on_create_pressed():
	if characters.size() >= max_characters:
		_show_message("Maximum number of characters reached!")
		return
	
	_start_character_creation()

func _start_character_creation():
	is_creating_character = true
	character_creator.show()
	character_creator.start_creation()

func _on_character_creation_complete(character_data: CharacterData):
	characters.append(character_data)
	_save_character(character_data)
	
	character_creator.hide()
	is_creating_character = false
	
	_clear_character_grid()
	_populate_character_grid()
	
	_select_character(characters.size() - 1)
	
	emit_signal("character_created", character_data)

func _on_creation_cancelled():
	character_creator.hide()
	is_creating_character = false

func _save_character(character: CharacterData):
	var file = File.new()
	var path = "user://characters/" + character.id + ".char"
	
	if file.open(path, File.WRITE) != OK:
		push_error("Failed to save character: " + character.name)
		return
	
	var save_data = {
		"id": character.id,
		"name": character.name,
		"class": character.class_type,
		"level": character.level,
		"play_time": character.play_time,
		"last_played": character.last_played,
		"appearance": character.appearance,
		"stats": character.stats,
		"equipment": character.equipment,
		"location": character.location
	}
	
	file.store_var(save_data)
	file.close()

func _on_select_pressed():
	if selected_character_index < 0 or selected_character_index >= characters.size():
		return
	
	var character = characters[selected_character_index]
	
	loading_screen.show()
	yield(get_tree().create_timer(0.5), "timeout")
	
	emit_signal("character_selected", character)

func _on_delete_pressed():
	if selected_character_index < 0 or selected_character_index >= characters.size():
		return
	
	var character = characters[selected_character_index]
	
	var confirm = ConfirmationDialog.new()
	confirm.dialog_text = "Delete character '%s'?\nThis action cannot be undone." % character.name
	add_child(confirm)
	confirm.popup_centered()
	
	yield(confirm, "confirmed")
	
	_delete_character(character)
	confirm.queue_free()

func _delete_character(character: CharacterData):
	var dir = Directory.new()
	var path = "user://characters/" + character.id + ".char"
	
	if dir.remove(path) == OK:
		characters.erase(character)
		
		_clear_character_grid()
		_populate_character_grid()
		
		selected_character_index = -1
		select_button.disabled = true
		delete_button.disabled = true
		
		emit_signal("character_deleted", character.id)

func _on_back_pressed():
	emit_signal("back_pressed")

func _show_message(text: String):
	var dialog = AcceptDialog.new()
	dialog.dialog_text = text
	add_child(dialog)
	dialog.popup_centered()
	yield(dialog, "popup_hide")
	dialog.queue_free()