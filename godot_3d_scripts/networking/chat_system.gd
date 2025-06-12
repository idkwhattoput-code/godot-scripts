extends Control

export var max_messages = 50
export var message_fade_time = 10.0
export var max_message_length = 200
export var enable_profanity_filter = true
export var enable_commands = true

var messages = []
var message_history = []
var history_index = -1
var is_typing = false

var banned_words = ["badword1", "badword2"]
var chat_commands = {}

onready var chat_container = $VBoxContainer/ScrollContainer/MessageContainer
onready var input_field = $VBoxContainer/InputContainer/ChatInput
onready var scroll_container = $VBoxContainer/ScrollContainer
onready var send_button = $VBoxContainer/InputContainer/SendButton

signal message_sent(message)
signal command_executed(command, args)

func _ready():
	_setup_ui()
	_register_default_commands()
	
	input_field.connect("text_entered", self, "_on_input_entered")
	send_button.connect("pressed", self, "_on_send_pressed")
	
	set_process_input(true)

func _input(event):
	if event.is_action_pressed("chat_toggle"):
		toggle_chat()
	elif event.is_action_pressed("ui_up") and input_field.has_focus():
		_navigate_history(-1)
	elif event.is_action_pressed("ui_down") and input_field.has_focus():
		_navigate_history(1)

func _setup_ui():
	if not chat_container:
		chat_container = VBoxContainer.new()
		scroll_container.add_child(chat_container)
	
	input_field.max_length = max_message_length
	input_field.placeholder_text = "Type a message..."

func add_message(sender: String, text: String, color: Color = Color.white, is_system: bool = false):
	if messages.size() >= max_messages:
		var old_message = messages.pop_front()
		old_message.queue_free()
	
	var message_label = RichTextLabel.new()
	message_label.fit_content_height = true
	message_label.bbcode_enabled = true
	message_label.scroll_active = false
	
	var timestamp = OS.get_time()
	var time_string = "%02d:%02d" % [timestamp.hour, timestamp.minute]
	
	var formatted_text = ""
	
	if is_system:
		formatted_text = "[color=#ffff00][SYSTEM] %s[/color]" % text
	else:
		var sender_color = color.to_html()
		formatted_text = "[color=#888888][%s][/color] [color=%s]%s:[/color] %s" % [time_string, sender_color, sender, text]
	
	message_label.bbcode_text = formatted_text
	
	chat_container.add_child(message_label)
	messages.append(message_label)
	
	yield(get_tree(), "idle_frame")
	scroll_container.scroll_vertical = scroll_container.get_v_scrollbar().max_value
	
	if message_fade_time > 0 and not is_system:
		_start_message_fade(message_label)

func add_system_message(text: String):
	add_message("", text, Color.yellow, true)

func _on_input_entered(text: String):
	if text.strip_edges() == "":
		return
	
	if enable_profanity_filter:
		text = _filter_profanity(text)
	
	if enable_commands and text.begins_with("/"):
		_process_command(text)
	else:
		emit_signal("message_sent", text)
		
		if get_tree().has_network_peer():
			MultiplayerManager.send_chat_message(text)
		else:
			add_message("You", text, Color.white)
	
	message_history.append(text)
	history_index = message_history.size()
	
	input_field.text = ""

func _on_send_pressed():
	_on_input_entered(input_field.text)

func _process_command(command_text: String):
	var parts = command_text.split(" ", false)
	if parts.size() == 0:
		return
	
	var command = parts[0].substr(1)
	var args = []
	for i in range(1, parts.size()):
		args.append(parts[i])
	
	if chat_commands.has(command):
		chat_commands[command].call_func(args)
		emit_signal("command_executed", command, args)
	else:
		add_system_message("Unknown command: /" + command)

func _register_default_commands():
	register_command("help", self, "_cmd_help", "Show available commands")
	register_command("clear", self, "_cmd_clear", "Clear chat messages")
	register_command("whisper", self, "_cmd_whisper", "Send private message")
	register_command("mute", self, "_cmd_mute", "Mute a player")
	register_command("unmute", self, "_cmd_unmute", "Unmute a player")

func register_command(command: String, target: Object, method: String, description: String = ""):
	chat_commands[command] = {
		"target": target,
		"method": method,
		"description": description
	}

func _cmd_help(args: Array):
	add_system_message("Available commands:")
	for cmd in chat_commands:
		var desc = chat_commands[cmd].description
		if desc != "":
			add_system_message("  /" + cmd + " - " + desc)
		else:
			add_system_message("  /" + cmd)

func _cmd_clear(args: Array):
	for message in messages:
		message.queue_free()
	messages.clear()

func _cmd_whisper(args: Array):
	if args.size() < 2:
		add_system_message("Usage: /whisper <player> <message>")
		return
	
	var target_player = args[0]
	var message = ""
	for i in range(1, args.size()):
		message += args[i] + " "
	
	add_message("To " + target_player, message.strip_edges(), Color(0.8, 0.8, 1.0))

func _cmd_mute(args: Array):
	if args.size() < 1:
		add_system_message("Usage: /mute <player>")
		return
	
	add_system_message("Muted player: " + args[0])

func _cmd_unmute(args: Array):
	if args.size() < 1:
		add_system_message("Usage: /unmute <player>")
		return
	
	add_system_message("Unmuted player: " + args[0])

func _filter_profanity(text: String) -> String:
	var filtered = text
	
	for word in banned_words:
		var regex = RegEx.new()
		regex.compile("\\b" + word + "\\b", RegEx.CaseInsensitive)
		filtered = regex.sub(filtered, "*".repeat(word.length()), true)
	
	return filtered

func _navigate_history(direction: int):
	if message_history.size() == 0:
		return
	
	history_index = clamp(history_index + direction, -1, message_history.size() - 1)
	
	if history_index >= 0:
		input_field.text = message_history[history_index]
		input_field.caret_position = input_field.text.length()
	else:
		input_field.text = ""

func _start_message_fade(message_label: RichTextLabel):
	yield(get_tree().create_timer(message_fade_time), "timeout")
	
	if not is_instance_valid(message_label):
		return
	
	var tween = Tween.new()
	add_child(tween)
	
	tween.interpolate_property(message_label, "modulate:a", 1.0, 0.0, 2.0, Tween.TRANS_LINEAR, Tween.EASE_IN)
	tween.start()
	
	yield(tween, "tween_all_completed")
	
	if is_instance_valid(message_label):
		messages.erase(message_label)
		message_label.queue_free()
	
	tween.queue_free()

func toggle_chat():
	is_typing = not is_typing
	
	if is_typing:
		show()
		input_field.grab_focus()
	else:
		input_field.release_focus()
		if input_field.text == "":
			hide()

func set_chat_visible(visible: bool):
	self.visible = visible
	is_typing = visible
	
	if visible:
		input_field.grab_focus()
	else:
		input_field.release_focus()

func save_chat_history() -> Array:
	var history = []
	for message in messages:
		if is_instance_valid(message):
			history.append(message.bbcode_text)
	return history

func load_chat_history(history: Array):
	for message_text in history:
		var label = RichTextLabel.new()
		label.fit_content_height = true
		label.bbcode_enabled = true
		label.scroll_active = false
		label.bbcode_text = message_text
		
		chat_container.add_child(label)
		messages.append(label)