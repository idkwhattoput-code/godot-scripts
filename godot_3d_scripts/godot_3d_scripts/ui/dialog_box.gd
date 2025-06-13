extends Control

class_name DialogBox

signal dialog_started()
signal dialog_finished()
signal choice_selected(choice_index)

onready var speaker_name_label = $Panel/MarginContainer/VBoxContainer/SpeakerName
onready var dialog_text = $Panel/MarginContainer/VBoxContainer/DialogText
onready var next_indicator = $Panel/MarginContainer/VBoxContainer/NextIndicator
onready var choice_container = $Panel/MarginContainer/VBoxContainer/ChoiceContainer
onready var portrait_left = $PortraitLeft
onready var portrait_right = $PortraitRight
onready var typing_sound = $TypingSound
onready var choice_button_scene = preload("res://ui/ChoiceButton.tscn")

export var text_speed: float = 0.05
export var fast_text_speed: float = 0.01
export var auto_advance: bool = false
export var auto_advance_delay: float = 2.0
export var fade_duration: float = 0.3
export var portrait_fade_duration: float = 0.5

var current_dialog_data: Array = []
var current_dialog_index: int = 0
var is_typing: bool = false
var can_advance: bool = false
var current_text: String = ""
var displayed_text: String = ""
var char_index: int = 0
var auto_advance_timer: float = 0.0
var choices_active: bool = false

var dialog_queue: Array = []
var character_portraits: Dictionary = {}
var character_colors: Dictionary = {}
var character_fonts: Dictionary = {}

func _ready():
	visible = false
	set_process_input(false)
	next_indicator.visible = false
	choice_container.visible = false
	portrait_left.modulate.a = 0
	portrait_right.modulate.a = 0
	
	setup_default_colors()

func _input(event):
	if not visible:
		return
	
	if choices_active:
		handle_choice_input(event)
		return
	
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		if is_typing:
			complete_text()
		elif can_advance:
			advance_dialog()

func _process(delta):
	if is_typing:
		update_typing(delta)
	elif auto_advance and can_advance and not choices_active:
		auto_advance_timer += delta
		if auto_advance_timer >= auto_advance_delay:
			advance_dialog()

func setup_default_colors():
	character_colors = {
		"Player": Color(0.3, 0.7, 1.0),
		"NPC": Color(1.0, 0.9, 0.3),
		"Enemy": Color(1.0, 0.3, 0.3),
		"System": Color(0.8, 0.8, 0.8)
	}

func register_character_portrait(character_name: String, portrait_texture: Texture):
	character_portraits[character_name] = portrait_texture

func register_character_color(character_name: String, color: Color):
	character_colors[character_name] = color

func register_character_font(character_name: String, font: Font):
	character_fonts[character_name] = font

func show_dialog(dialog_data: Array):
	if visible and current_dialog_data.size() > 0:
		dialog_queue.append(dialog_data)
		return
	
	current_dialog_data = dialog_data
	current_dialog_index = 0
	start_dialog()

func start_dialog():
	visible = true
	modulate.a = 0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, fade_duration)
	tween.finished.connect(self, "_on_fade_in_complete")
	
	set_process_input(true)
	emit_signal("dialog_started")
	
	if current_dialog_index < current_dialog_data.size():
		display_current_line()

func _on_fade_in_complete():
	pass

func display_current_line():
	if current_dialog_index >= current_dialog_data.size():
		finish_dialog()
		return
	
	var line_data = current_dialog_data[current_dialog_index]
	
	speaker_name_label.text = line_data.get("speaker", "")
	
	if line_data.has("speaker") and line_data.speaker in character_colors:
		speaker_name_label.modulate = character_colors[line_data.speaker]
	else:
		speaker_name_label.modulate = Color.white
	
	if line_data.has("speaker") and line_data.speaker in character_fonts:
		dialog_text.add_font_override("font", character_fonts[line_data.speaker])
	
	update_portraits(line_data)
	
	if line_data.has("choices"):
		setup_choices(line_data.choices)
		current_text = line_data.get("text", "")
	else:
		current_text = parse_dialog_text(line_data.get("text", ""))
	
	displayed_text = ""
	char_index = 0
	is_typing = true
	can_advance = false
	next_indicator.visible = false
	auto_advance_timer = 0.0

func parse_dialog_text(text: String) -> String:
	text = text.replace("[player_name]", GameData.player_name if GameData else "Player")
	text = text.replace("[b]", "[b]")
	text = text.replace("[/b]", "[/b]")
	text = text.replace("[i]", "[i]")
	text = text.replace("[/i]", "[/i]")
	text = text.replace("[wave]", "[wave amp=50 freq=2]")
	text = text.replace("[/wave]", "[/wave]")
	text = text.replace("[shake]", "[shake rate=10 level=10]")
	text = text.replace("[/shake]", "[/shake]")
	
	return text

func update_portraits(line_data: Dictionary):
	var speaker = line_data.get("speaker", "")
	var portrait_position = line_data.get("portrait_position", "left")
	var portrait_texture = null
	
	if speaker in character_portraits:
		portrait_texture = character_portraits[speaker]
	elif line_data.has("portrait"):
		portrait_texture = load(line_data.portrait)
	
	var show_left = portrait_position == "left" and portrait_texture != null
	var show_right = portrait_position == "right" and portrait_texture != null
	
	fade_portrait(portrait_left, show_left, portrait_texture if show_left else null)
	fade_portrait(portrait_right, show_right, portrait_texture if show_right else null)

func fade_portrait(portrait: TextureRect, show: bool, texture: Texture):
	var tween = create_tween()
	
	if show and texture:
		portrait.texture = texture
		tween.tween_property(portrait, "modulate:a", 1.0, portrait_fade_duration)
	else:
		tween.tween_property(portrait, "modulate:a", 0.0, portrait_fade_duration)

func update_typing(delta):
	var speed = fast_text_speed if Input.is_action_pressed("ui_cancel") else text_speed
	
	while char_index < current_text.length() and delta > 0:
		var char_time = speed
		
		if current_text[char_index] in ".,!?":
			char_time *= 3
		
		if delta >= char_time:
			displayed_text += current_text[char_index]
			char_index += 1
			delta -= char_time
			
			if typing_sound and current_text[char_index - 1] != " ":
				typing_sound.pitch_scale = rand_range(0.9, 1.1)
				typing_sound.play()
		else:
			break
	
	dialog_text.bbcode_text = displayed_text
	
	if char_index >= current_text.length():
		complete_text()

func complete_text():
	displayed_text = current_text
	dialog_text.bbcode_text = displayed_text
	is_typing = false
	can_advance = true
	
	if not choices_active:
		next_indicator.visible = true
		var tween = create_tween()
		tween.set_loops()
		tween.tween_property(next_indicator, "modulate:a", 0.3, 0.5)
		tween.tween_property(next_indicator, "modulate:a", 1.0, 0.5)

func advance_dialog():
	current_dialog_index += 1
	
	if current_dialog_index < current_dialog_data.size():
		display_current_line()
	else:
		finish_dialog()

func setup_choices(choices: Array):
	choices_active = true
	choice_container.visible = true
	
	for child in choice_container.get_children():
		child.queue_free()
	
	for i in range(choices.size()):
		var choice_text = choices[i]
		var button = Button.new()
		button.text = choice_text
		button.connect("pressed", self, "_on_choice_selected", [i])
		choice_container.add_child(button)
		
		if i == 0:
			button.grab_focus()

func handle_choice_input(event):
	if event.is_action_pressed("ui_up"):
		navigate_choices(-1)
	elif event.is_action_pressed("ui_down"):
		navigate_choices(1)

func navigate_choices(direction: int):
	var buttons = choice_container.get_children()
	if buttons.empty():
		return
	
	var focused_index = -1
	for i in range(buttons.size()):
		if buttons[i].has_focus():
			focused_index = i
			break
	
	if focused_index == -1:
		buttons[0].grab_focus()
	else:
		var new_index = (focused_index + direction) % buttons.size()
		if new_index < 0:
			new_index = buttons.size() - 1
		buttons[new_index].grab_focus()

func _on_choice_selected(choice_index: int):
	emit_signal("choice_selected", choice_index)
	choices_active = false
	choice_container.visible = false
	advance_dialog()

func finish_dialog():
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	tween.finished.connect(self, "_on_fade_out_complete")

func _on_fade_out_complete():
	visible = false
	set_process_input(false)
	emit_signal("dialog_finished")
	
	current_dialog_data.clear()
	current_dialog_index = 0
	
	if dialog_queue.size() > 0:
		var next_dialog = dialog_queue.pop_front()
		show_dialog(next_dialog)

func skip_dialog():
	if is_typing:
		complete_text()
	else:
		finish_dialog()

func pause_dialog():
	set_process(false)
	set_process_input(false)

func resume_dialog():
	set_process(true)
	set_process_input(true)

func get_current_speaker() -> String:
	if current_dialog_index < current_dialog_data.size():
		return current_dialog_data[current_dialog_index].get("speaker", "")
	return ""

func insert_dialog_line(line_data: Dictionary):
	current_dialog_data.insert(current_dialog_index + 1, line_data)

func create_dialog_line(speaker: String, text: String, portrait_position: String = "left") -> Dictionary:
	return {
		"speaker": speaker,
		"text": text,
		"portrait_position": portrait_position
	}

func create_choice_dialog(speaker: String, text: String, choices: Array) -> Dictionary:
	return {
		"speaker": speaker,
		"text": text,
		"choices": choices
	}