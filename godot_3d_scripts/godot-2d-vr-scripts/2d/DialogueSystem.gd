extends Control

class_name DialogueSystem

@export var typing_speed: float = 50.0
@export var auto_advance_time: float = 0.0
@export var dialogue_box_theme: Theme

@onready var dialogue_box: NinePatchRect = $DialogueBox
@onready var speaker_label: Label = $DialogueBox/SpeakerLabel
@onready var dialogue_text: RichTextLabel = $DialogueBox/DialogueText
@onready var continue_indicator: TextureRect = $DialogueBox/ContinueIndicator
@onready var choice_container: VBoxContainer = $DialogueBox/ChoiceContainer
@onready var portrait: TextureRect = $DialogueBox/Portrait
@onready var typing_timer: Timer = $TypingTimer

var current_dialogue: DialogueData = null
var current_line_index: int = 0
var is_typing: bool = false
var full_text: String = ""
var displayed_text: String = ""
var current_char_index: int = 0
var dialogue_queue: Array[DialogueData] = []
var auto_advance_timer: float = 0.0

signal dialogue_started(dialogue: DialogueData)
signal dialogue_finished(dialogue: DialogueData)
signal choice_selected(choice_index: int, choice_text: String)
signal line_finished(line_index: int)

class DialogueData:
	var id: String
	var speaker_name: String
	var lines: Array[String] = []
	var portraits: Array[Texture2D] = []
	var choices: Array[String] = []
	var choice_targets: Array[String] = []
	var auto_advance: bool = false
	var sound_effects: Array[AudioStream] = []
	var animations: Array[String] = []
	
	func _init():
		pass

func _ready():
	hide()
	typing_timer.timeout.connect(_on_typing_timer_timeout)
	
	if dialogue_box_theme:
		theme = dialogue_box_theme

func _input(event):
	if not visible or not current_dialogue:
		return
	
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("dialogue_advance"):
		if is_typing:
			complete_current_line()
		else:
			advance_dialogue()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("dialogue_skip"):
		skip_dialogue()
		get_viewport().set_input_as_handled()

func _process(delta):
	if current_dialogue and current_dialogue.auto_advance and auto_advance_time > 0:
		auto_advance_timer += delta
		if auto_advance_timer >= auto_advance_time and not is_typing:
			advance_dialogue()

func start_dialogue(dialogue: DialogueData):
	if not dialogue or dialogue.lines.is_empty():
		return
	
	current_dialogue = dialogue
	current_line_index = 0
	show()
	
	speaker_label.text = dialogue.speaker_name
	
	if dialogue.portraits.size() > 0:
		portrait.texture = dialogue.portraits[0]
		portrait.show()
	else:
		portrait.hide()
	
	display_current_line()
	dialogue_started.emit(dialogue)

func display_current_line():
	if not current_dialogue or current_line_index >= current_dialogue.lines.size():
		finish_dialogue()
		return
	
	full_text = current_dialogue.lines[current_line_index]
	displayed_text = ""
	current_char_index = 0
	is_typing = true
	
	choice_container.hide()
	continue_indicator.hide()
	
	if current_dialogue.portraits.size() > current_line_index:
		portrait.texture = current_dialogue.portraits[current_line_index]
	
	dialogue_text.text = ""
	typing_timer.start(1.0 / typing_speed)

func _on_typing_timer_timeout():
	if not is_typing or current_char_index >= full_text.length():
		complete_current_line()
		return
	
	displayed_text += full_text[current_char_index]
	dialogue_text.text = displayed_text
	current_char_index += 1
	
	if current_char_index < full_text.length():
		typing_timer.start(1.0 / typing_speed)
	else:
		complete_current_line()

func complete_current_line():
	if not is_typing:
		return
	
	is_typing = false
	typing_timer.stop()
	dialogue_text.text = full_text
	
	if is_last_line() and current_dialogue.choices.size() > 0:
		show_choices()
	else:
		continue_indicator.show()
		auto_advance_timer = 0.0
	
	line_finished.emit(current_line_index)

func advance_dialogue():
	if is_typing:
		return
	
	current_line_index += 1
	
	if current_line_index >= current_dialogue.lines.size():
		if current_dialogue.choices.size() > 0:
			show_choices()
		else:
			finish_dialogue()
	else:
		display_current_line()

func show_choices():
	choice_container.show()
	continue_indicator.hide()
	
	for child in choice_container.get_children():
		child.queue_free()
	
	for i in range(current_dialogue.choices.size()):
		var choice_button = Button.new()
		choice_button.text = current_dialogue.choices[i]
		choice_button.pressed.connect(_on_choice_selected.bind(i))
		choice_container.add_child(choice_button)

func _on_choice_selected(choice_index: int):
	var choice_text = current_dialogue.choices[choice_index]
	choice_selected.emit(choice_index, choice_text)
	finish_dialogue()

func finish_dialogue():
	if current_dialogue:
		var finished_dialogue = current_dialogue
		current_dialogue = null
		dialogue_finished.emit(finished_dialogue)
	
	hide()

func is_last_line() -> bool:
	return current_line_index >= current_dialogue.lines.size() - 1

func create_dialogue(speaker: String, lines: Array[String]) -> DialogueData:
	var dialogue = DialogueData.new()
	dialogue.speaker_name = speaker
	dialogue.lines = lines
	return dialogue