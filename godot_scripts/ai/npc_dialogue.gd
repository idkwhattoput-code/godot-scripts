extends Spatial

export var npc_name = "NPC"
export var interaction_range = 3.0
export var dialogue_resource : Resource
export var can_move = true
export var look_at_player = true

var player_in_range = false
var current_dialogue_index = 0
var is_talking = false
var player_reference = null

signal dialogue_started
signal dialogue_ended
signal dialogue_line_finished(line)

onready var interaction_area = $InteractionArea
onready var dialogue_ui = $DialogueUI
onready var name_label = $DialogueUI/Panel/NameLabel
onready var text_label = $DialogueUI/Panel/TextLabel
onready var choice_container = $DialogueUI/Panel/ChoiceContainer

var dialogue_data = {
	"greeting": [
		{"text": "Hello there, traveler!", "choices": []},
		{"text": "How can I help you today?", "choices": ["Tell me about this place", "Do you have any quests?", "Goodbye"]}
	],
	"place_info": [
		{"text": "This is the village of Greendale.", "choices": []},
		{"text": "We're known for our beautiful gardens and friendly people.", "choices": ["Interesting", "Tell me more", "Thanks"]}
	],
	"quest_info": [
		{"text": "Actually, I do need some help!", "choices": []},
		{"text": "Could you deliver this package to the merchant?", "choices": ["Accept Quest", "Maybe later"]}
	]
}

var current_dialogue_branch = "greeting"
var dialogue_queue = []

func _ready():
	interaction_area.connect("body_entered", self, "_on_body_entered")
	interaction_area.connect("body_exited", self, "_on_body_exited")
	dialogue_ui.visible = false
	
	_setup_dialogue_ui()

func _process(delta):
	if player_in_range and Input.is_action_just_pressed("interact") and not is_talking:
		start_dialogue()
	
	if is_talking and look_at_player and is_instance_valid(player_reference):
		_look_at_player(delta)

func _setup_dialogue_ui():
	for i in range(3):
		var choice_button = Button.new()
		choice_button.connect("pressed", self, "_on_choice_selected", [i])
		choice_container.add_child(choice_button)
		choice_button.visible = false

func start_dialogue():
	if is_talking:
		return
	
	is_talking = true
	dialogue_ui.visible = true
	current_dialogue_index = 0
	current_dialogue_branch = "greeting"
	
	emit_signal("dialogue_started")
	
	if can_move:
		set_physics_process(false)
	
	_display_current_dialogue()

func end_dialogue():
	is_talking = false
	dialogue_ui.visible = false
	current_dialogue_index = 0
	
	emit_signal("dialogue_ended")
	
	if can_move:
		set_physics_process(true)

func _display_current_dialogue():
	if not dialogue_data.has(current_dialogue_branch):
		end_dialogue()
		return
	
	var branch = dialogue_data[current_dialogue_branch]
	if current_dialogue_index >= branch.size():
		end_dialogue()
		return
	
	var current_line = branch[current_dialogue_index]
	
	name_label.text = npc_name
	text_label.text = ""
	
	_hide_all_choices()
	
	_typewriter_effect(current_line.text)

func _typewriter_effect(text: String):
	var char_delay = 0.03
	for i in range(text.length()):
		text_label.text = text.substr(0, i + 1)
		yield(get_tree().create_timer(char_delay), "timeout")
	
	var current_line = dialogue_data[current_dialogue_branch][current_dialogue_index]
	if current_line.choices.size() > 0:
		_show_choices(current_line.choices)
	else:
		yield(get_tree().create_timer(1.0), "timeout")
		_advance_dialogue()

func _show_choices(choices: Array):
	for i in range(min(choices.size(), choice_container.get_child_count())):
		var button = choice_container.get_child(i)
		button.text = choices[i]
		button.visible = true

func _hide_all_choices():
	for child in choice_container.get_children():
		child.visible = false

func _on_choice_selected(choice_index: int):
	var current_line = dialogue_data[current_dialogue_branch][current_dialogue_index]
	if choice_index >= current_line.choices.size():
		return
	
	var selected_choice = current_line.choices[choice_index]
	
	match selected_choice:
		"Tell me about this place":
			current_dialogue_branch = "place_info"
			current_dialogue_index = 0
		"Do you have any quests?":
			current_dialogue_branch = "quest_info"
			current_dialogue_index = 0
		"Goodbye":
			end_dialogue()
			return
		"Accept Quest":
			_give_quest()
			end_dialogue()
			return
		"Maybe later":
			end_dialogue()
			return
		_:
			_advance_dialogue()
			return
	
	_display_current_dialogue()

func _advance_dialogue():
	current_dialogue_index += 1
	
	var branch = dialogue_data[current_dialogue_branch]
	if current_dialogue_index >= branch.size():
		end_dialogue()
	else:
		_display_current_dialogue()

func _give_quest():
	if player_reference and player_reference.has_method("add_quest"):
		player_reference.add_quest("delivery_quest", "Deliver package to merchant")
	
	print("Quest given: Deliver package to merchant")

func _look_at_player(delta: float):
	var player_pos = player_reference.global_transform.origin
	var look_pos = Vector3(player_pos.x, global_transform.origin.y, player_pos.z)
	
	var target_transform = global_transform.looking_at(look_pos, Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(target_transform.basis, 5.0 * delta)

func _on_body_entered(body):
	if body.is_in_group("player"):
		player_in_range = true
		player_reference = body
		
		if has_node("InteractionPrompt"):
			$InteractionPrompt.visible = true

func _on_body_exited(body):
	if body.is_in_group("player"):
		player_in_range = false
		
		if has_node("InteractionPrompt"):
			$InteractionPrompt.visible = false
		
		if is_talking:
			end_dialogue()

func add_dialogue_branch(branch_name: String, dialogue: Array):
	dialogue_data[branch_name] = dialogue

func set_dialogue_branch(branch_name: String):
	if dialogue_data.has(branch_name):
		current_dialogue_branch = branch_name
		current_dialogue_index = 0