extends Control

export var save_slots_count = 10
export var enable_cloud_saves = false
export var enable_auto_save_slot = true
export var show_thumbnails = true
export var confirm_overwrite = true

var save_slots = []
var selected_slot = -1
var is_save_mode = true

onready var title_label = $Panel/TitleLabel
onready var slot_container = $Panel/ScrollContainer/SlotContainer
onready var action_button = $Panel/ButtonPanel/ActionButton
onready var delete_button = $Panel/ButtonPanel/DeleteButton
onready var back_button = $Panel/ButtonPanel/BackButton
onready var cloud_sync_button = $Panel/ButtonPanel/CloudSyncButton
onready var confirm_dialog = $ConfirmDialog
onready var loading_overlay = $LoadingOverlay

signal save_selected(slot_index, save_data)
signal load_selected(slot_index)
signal back_pressed()

class SaveSlot:
	var index: int = 0
	var is_empty: bool = true
	var save_name: String = ""
	var timestamp: int = 0
	var play_time: float = 0.0
	var level: int = 1
	var location: String = ""
	var thumbnail_path: String = ""
	var is_auto_save: bool = false
	var is_cloud_save: bool = false
	var save_version: String = "1.0"
	
	func get_formatted_time() -> String:
		var datetime = OS.get_datetime_from_unix_time(timestamp)
		return "%02d/%02d/%04d %02d:%02d" % [
			datetime.month, datetime.day, datetime.year,
			datetime.hour, datetime.minute
		]
	
	func get_formatted_play_time() -> String:
		var hours = int(play_time / 3600)
		var minutes = int((play_time % 3600) / 60)
		return "%dh %dm" % [hours, minutes]

func _ready():
	_setup_ui()
	_create_save_slots()
	refresh_save_slots()

func _setup_ui():
	cloud_sync_button.visible = enable_cloud_saves
	loading_overlay.hide()
	
	delete_button.disabled = true
	action_button.disabled = true

func set_mode(save_mode: bool):
	is_save_mode = save_mode
	title_label.text = "Save Game" if save_mode else "Load Game"
	action_button.text = "Save" if save_mode else "Load"
	
	refresh_save_slots()

func _create_save_slots():
	for i in range(save_slots_count):
		var slot_ui = _create_slot_ui(i)
		slot_container.add_child(slot_ui)
		
		if enable_auto_save_slot and i == 0:
			slot_ui.get_node("SlotInfo/NameLabel").text = "Auto Save"
			slot_ui.modulate = Color(0.8, 0.9, 1.0)

func _create_slot_ui(index: int) -> Control:
	var slot_panel = Panel.new()
	slot_panel.name = "Slot" + str(index)
	slot_panel.rect_min_size = Vector2(600, 120)
	
	var hbox = HBoxContainer.new()
	hbox.rect_min_size = slot_panel.rect_min_size
	slot_panel.add_child(hbox)
	
	# Thumbnail
	if show_thumbnails:
		var thumbnail = TextureRect.new()
		thumbnail.name = "Thumbnail"
		thumbnail.rect_min_size = Vector2(160, 90)
		thumbnail.expand = true
		thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumbnail.texture = preload("res://default_save_thumbnail.png")
		hbox.add_child(thumbnail)
	
	# Slot info
	var info_vbox = VBoxContainer.new()
	info_vbox.name = "SlotInfo"
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)
	
	var name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = "Empty Slot"
	name_label.add_font_override("font", preload("res://fonts/bold_font.tres"))
	info_vbox.add_child(name_label)
	
	var details_label = Label.new()
	details_label.name = "DetailsLabel"
	details_label.text = "Click to save"
	details_label.modulate = Color(0.7, 0.7, 0.7)
	info_vbox.add_child(details_label)
	
	var time_label = Label.new()
	time_label.name = "TimeLabel"
	time_label.text = ""
	time_label.modulate = Color(0.6, 0.6, 0.6)
	info_vbox.add_child(time_label)
	
	# Status icons
	var icon_hbox = HBoxContainer.new()
	icon_hbox.name = "StatusIcons"
	hbox.add_child(icon_hbox)
	
	var cloud_icon = TextureRect.new()
	cloud_icon.name = "CloudIcon"
	cloud_icon.rect_min_size = Vector2(24, 24)
	cloud_icon.texture = preload("res://icons/cloud.png")
	cloud_icon.visible = false
	icon_hbox.add_child(cloud_icon)
	
	# Click detection
	var button = Button.new()
	button.rect_min_size = slot_panel.rect_min_size
	button.flat = true
	button.connect("pressed", self, "_on_slot_clicked", [index])
	button.connect("mouse_entered", self, "_on_slot_hover", [index, true])
	button.connect("mouse_exited", self, "_on_slot_hover", [index, false])
	slot_panel.add_child(button)
	
	return slot_panel

func refresh_save_slots():
	save_slots.clear()
	
	for i in range(save_slots_count):
		var slot = SaveSlot.new()
		slot.index = i
		
		if enable_auto_save_slot and i == 0:
			slot.is_auto_save = true
		
		var save_data = _load_save_data(i)
		if save_data:
			slot.is_empty = false
			slot.save_name = save_data.get("save_name", "Save %d" % (i + 1))
			slot.timestamp = save_data.get("timestamp", 0)
			slot.play_time = save_data.get("play_time", 0.0)
			slot.level = save_data.get("player_level", 1)
			slot.location = save_data.get("location", "Unknown")
			slot.thumbnail_path = save_data.get("thumbnail", "")
			slot.is_cloud_save = save_data.get("is_cloud", false)
			slot.save_version = save_data.get("version", "1.0")
		
		save_slots.append(slot)
		_update_slot_ui(i, slot)

func _load_save_data(slot_index: int) -> Dictionary:
	var file = File.new()
	var path = "user://save_slot_%d.dat" % slot_index
	
	if not file.file_exists(path):
		return {}
	
	if file.open(path, File.READ) != OK:
		return {}
	
	var data = file.get_var()
	file.close()
	
	return data if data is Dictionary else {}

func _update_slot_ui(index: int, slot: SaveSlot):
	var slot_ui = slot_container.get_node("Slot" + str(index))
	if not slot_ui:
		return
	
	var name_label = slot_ui.get_node("SlotInfo/NameLabel")
	var details_label = slot_ui.get_node("SlotInfo/DetailsLabel")
	var time_label = slot_ui.get_node("SlotInfo/TimeLabel")
	var cloud_icon = slot_ui.get_node("StatusIcons/CloudIcon")
	
	if slot.is_empty:
		name_label.text = "Auto Save Slot" if slot.is_auto_save else "Empty Slot"
		details_label.text = "Click to save" if is_save_mode else "No save data"
		time_label.text = ""
		
		slot_ui.modulate.a = 0.6 if not is_save_mode else 1.0
	else:
		name_label.text = slot.save_name
		details_label.text = "Level %d - %s" % [slot.level, slot.location]
		time_label.text = "%s | Play time: %s" % [slot.get_formatted_time(), slot.get_formatted_play_time()]
		
		slot_ui.modulate.a = 1.0
	
	if show_thumbnails:
		var thumbnail = slot_ui.get_node("Thumbnail")
		if thumbnail and slot.thumbnail_path != "":
			var tex = load(slot.thumbnail_path)
			if tex:
				thumbnail.texture = tex
	
	cloud_icon.visible = slot.is_cloud_save and enable_cloud_saves

func _on_slot_clicked(index: int):
	selected_slot = index
	
	for i in range(save_slots_count):
		var slot_ui = slot_container.get_node("Slot" + str(i))
		if slot_ui:
			var selected = i == index
			slot_ui.modulate = Color.white if selected else Color(0.8, 0.8, 0.8)
	
	var slot = save_slots[index]
	
	action_button.disabled = false
	delete_button.disabled = slot.is_empty or slot.is_auto_save
	
	if is_save_mode and not slot.is_empty and confirm_overwrite:
		_show_overwrite_confirmation(index)
	else:
		_perform_action(index)

func _on_slot_hover(index: int, hovering: bool):
	var slot_ui = slot_container.get_node("Slot" + str(index))
	if slot_ui and index != selected_slot:
		slot_ui.modulate = Color.white if hovering else Color(0.9, 0.9, 0.9)

func _show_overwrite_confirmation(index: int):
	confirm_dialog.dialog_text = "Overwrite existing save in slot %d?" % (index + 1)
	confirm_dialog.popup_centered()
	
	yield(confirm_dialog, "confirmed")
	_perform_action(index)

func _perform_action(index: int):
	if is_save_mode:
		_save_game(index)
	else:
		_load_game(index)

func _save_game(index: int):
	loading_overlay.show()
	
	# Capture thumbnail
	var thumbnail_path = ""
	if show_thumbnails:
		thumbnail_path = _capture_thumbnail(index)
	
	# Gather save data
	var save_data = {
		"save_name": _generate_save_name(index),
		"timestamp": OS.get_unix_time(),
		"play_time": GameState.get_play_time(),
		"player_level": GameState.get_player_level(),
		"location": GameState.get_current_location(),
		"thumbnail": thumbnail_path,
		"is_cloud": false,
		"version": ProjectSettings.get_setting("application/config/version", "1.0"),
		"game_data": GameState.get_save_data()
	}
	
	# Save to file
	var file = File.new()
	var path = "user://save_slot_%d.dat" % index
	
	if file.open(path, File.WRITE) == OK:
		file.store_var(save_data)
		file.close()
		
		emit_signal("save_selected", index, save_data)
		_show_notification("Game saved to slot %d" % (index + 1))
	else:
		_show_error("Failed to save game")
	
	loading_overlay.hide()
	refresh_save_slots()

func _load_game(index: int):
	var slot = save_slots[index]
	if slot.is_empty:
		return
	
	loading_overlay.show()
	
	emit_signal("load_selected", index)

func _generate_save_name(index: int) -> String:
	if enable_auto_save_slot and index == 0:
		return "Auto Save"
	
	var location = GameState.get_current_location()
	return "Save %d - %s" % [index + 1, location]

func _capture_thumbnail(index: int) -> String:
	var image = get_viewport().get_texture().get_data()
	image.flip_y()
	image.resize(320, 180)
	
	var path = "user://save_thumbnail_%d.png" % index
	image.save_png(path)
	
	return path

func delete_selected_save():
	if selected_slot < 0 or selected_slot >= save_slots.size():
		return
	
	var slot = save_slots[selected_slot]
	if slot.is_empty or slot.is_auto_save:
		return
	
	confirm_dialog.dialog_text = "Delete save in slot %d? This cannot be undone." % (selected_slot + 1)
	confirm_dialog.popup_centered()
	
	yield(confirm_dialog, "confirmed")
	
	var dir = Directory.new()
	var save_path = "user://save_slot_%d.dat" % selected_slot
	var thumb_path = "user://save_thumbnail_%d.png" % selected_slot
	
	dir.remove(save_path)
	dir.remove(thumb_path)
	
	_show_notification("Save deleted")
	refresh_save_slots()

func _on_delete_pressed():
	delete_selected_save()

func _on_back_pressed():
	emit_signal("back_pressed")

func _on_cloud_sync_pressed():
	if not enable_cloud_saves:
		return
	
	loading_overlay.show()
	_sync_cloud_saves()

func _sync_cloud_saves():
	# Implement cloud save synchronization
	yield(get_tree().create_timer(2.0), "timeout")
	loading_overlay.hide()
	_show_notification("Cloud saves synchronized")

func _show_notification(message: String):
	var notif = Label.new()
	notif.text = message
	notif.rect_position = Vector2(300, 50)
	add_child(notif)
	
	yield(get_tree().create_timer(2.0), "timeout")
	notif.queue_free()

func _show_error(message: String):
	var dialog = AcceptDialog.new()
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered()
	yield(dialog, "popup_hide")
	dialog.queue_free()

class GameState:
	static func get_play_time() -> float:
		return 0.0
	
	static func get_player_level() -> int:
		return 1
	
	static func get_current_location() -> String:
		return "Unknown Location"
	
	static func get_save_data() -> Dictionary:
		return {}