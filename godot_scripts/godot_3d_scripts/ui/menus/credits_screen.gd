extends Control

export var scroll_speed = 30.0
export var auto_scroll = true
export var enable_sections = true
export var enable_images = true
export var loop_credits = false
export var background_music_path = ""

var is_scrolling = false
var scroll_position = 0.0
var total_height = 0.0
var manual_scroll_timer = 0.0

onready var scroll_container = $ScrollContainer
onready var credits_container = $ScrollContainer/CreditsContainer
onready var back_button = $BackButton
onready var speed_slider = $SpeedControl/Slider
onready var speed_label = $SpeedControl/Label
onready var background_music = $BackgroundMusic

signal credits_finished()
signal back_pressed()

var credits_data = {
	"Game Director": ["John Smith"],
	"Lead Programmer": ["Jane Doe"],
	"Art Director": ["Bob Johnson"],
	"Game Designers": ["Alice Brown", "Charlie Wilson"],
	"Programmers": [
		"David Lee",
		"Emma Davis",
		"Frank Miller",
		"Grace Taylor"
	],
	"Artists": [
		"Henry Anderson",
		"Isabella Martinez",
		"Jack Thomas",
		"Karen Jackson"
	],
	"Sound Design": ["Lucas White", "Maria Garcia"],
	"Music": ["Nathan Harris", "Olivia Rodriguez"],
	"Writers": ["Paul Lewis", "Quinn Walker"],
	"Quality Assurance": [
		"Rachel Hall",
		"Samuel Young",
		"Tina Allen",
		"Uma King"
	],
	"Special Thanks": [
		"Our Families",
		"The Community",
		"Coffee",
		"You, the Player!"
	]
}

var section_styles = {
	"title": {
		"font_size": 32,
		"color": Color.yellow,
		"spacing": 60
	},
	"section": {
		"font_size": 24,
		"color": Color.cyan,
		"spacing": 40
	},
	"name": {
		"font_size": 18,
		"color": Color.white,
		"spacing": 25
	}
}

func _ready():
	_setup_ui()
	_build_credits()
	_connect_signals()
	
	if auto_scroll:
		start_scrolling()
	
	if background_music_path != "":
		_play_background_music()

func _setup_ui():
	back_button.connect("pressed", self, "_on_back_pressed")
	
	if speed_slider:
		speed_slider.min_value = 10
		speed_slider.max_value = 100
		speed_slider.value = scroll_speed
		speed_slider.connect("value_changed", self, "_on_speed_changed")
		_update_speed_label()

func _build_credits():
	# Add game title
	_add_title(ProjectSettings.get_setting("application/config/name", "Game Title"))
	_add_spacing(100)
	
	# Add sections
	for section_title in credits_data:
		_add_section(section_title)
		
		for name in credits_data[section_title]:
			_add_name(name)
		
		_add_spacing(section_styles.section.spacing)
	
	# Add images if enabled
	if enable_images:
		_add_logo_section()
	
	# Add final message
	_add_spacing(100)
	_add_centered_text("Thank you for playing!", section_styles.title.font_size)
	_add_spacing(200)
	
	# Calculate total height
	yield(get_tree(), "idle_frame")
	total_height = credits_container.rect_size.y

func _add_title(text: String):
	var label = Label.new()
	label.text = text
	label.align = Label.ALIGN_CENTER
	label.add_font_override("font", preload("res://fonts/title_font.tres"))
	label.modulate = section_styles.title.color
	label.rect_min_size.x = scroll_container.rect_size.x
	credits_container.add_child(label)

func _add_section(text: String):
	var label = Label.new()
	label.text = text.to_upper()
	label.align = Label.ALIGN_CENTER
	label.add_font_override("font", preload("res://fonts/section_font.tres"))
	label.modulate = section_styles.section.color
	label.rect_min_size.x = scroll_container.rect_size.x
	credits_container.add_child(label)
	_add_spacing(20)

func _add_name(text: String):
	var label = Label.new()
	label.text = text
	label.align = Label.ALIGN_CENTER
	label.modulate = section_styles.name.color
	label.rect_min_size.x = scroll_container.rect_size.x
	credits_container.add_child(label)

func _add_centered_text(text: String, size: int = 18):
	var label = Label.new()
	label.text = text
	label.align = Label.ALIGN_CENTER
	label.rect_min_size.x = scroll_container.rect_size.x
	
	var dynamic_font = DynamicFont.new()
	dynamic_font.size = size
	label.add_font_override("font", dynamic_font)
	
	credits_container.add_child(label)

func _add_spacing(height: float):
	var spacer = Control.new()
	spacer.rect_min_size.y = height
	credits_container.add_child(spacer)

func _add_logo_section():
	_add_spacing(100)
	_add_section("Powered By")
	_add_spacing(40)
	
	var logo_container = HBoxContainer.new()
	logo_container.alignment = HBoxContainer.ALIGN_CENTER
	logo_container.rect_min_size.x = scroll_container.rect_size.x
	credits_container.add_child(logo_container)
	
	# Add engine logo
	var godot_logo = TextureRect.new()
	godot_logo.texture = preload("res://logos/godot_logo.png")
	godot_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	godot_logo.rect_min_size = Vector2(200, 100)
	logo_container.add_child(godot_logo)
	
	_add_spacing(100)

func _connect_signals():
	scroll_container.get_v_scrollbar().connect("value_changed", self, "_on_manual_scroll")

func _process(delta):
	if is_scrolling and manual_scroll_timer <= 0:
		scroll_position += scroll_speed * delta
		
		if scroll_position >= total_height + scroll_container.rect_size.y:
			if loop_credits:
				scroll_position = -scroll_container.rect_size.y
			else:
				is_scrolling = false
				emit_signal("credits_finished")
		
		scroll_container.scroll_vertical = int(scroll_position)
	
	if manual_scroll_timer > 0:
		manual_scroll_timer -= delta

func _on_manual_scroll(value):
	if is_scrolling:
		manual_scroll_timer = 2.0
		scroll_position = value

func start_scrolling():
	is_scrolling = true
	scroll_position = -scroll_container.rect_size.y

func stop_scrolling():
	is_scrolling = false

func reset_credits():
	scroll_position = 0
	scroll_container.scroll_vertical = 0
	if auto_scroll:
		start_scrolling()

func _on_speed_changed(value):
	scroll_speed = value
	_update_speed_label()

func _update_speed_label():
	if speed_label:
		speed_label.text = "Speed: %.0f" % scroll_speed

func _on_back_pressed():
	stop_scrolling()
	if background_music:
		background_music.stop()
	emit_signal("back_pressed")

func _play_background_music():
	if not background_music:
		background_music = AudioStreamPlayer.new()
		add_child(background_music)
	
	var stream = load(background_music_path)
	if stream:
		background_music.stream = stream
		background_music.play()

func add_custom_section(title: String, names: Array):
	credits_data[title] = names

func set_section_style(section_type: String, style: Dictionary):
	if section_styles.has(section_type):
		for key in style:
			section_styles[section_type][key] = style[key]

func export_credits_to_file(path: String):
	var file = File.new()
	if file.open(path, File.WRITE) != OK:
		return
	
	file.store_line(ProjectSettings.get_setting("application/config/name", "Game Title"))
	file.store_line("")
	
	for section in credits_data:
		file.store_line(section.to_upper())
		for name in credits_data[section]:
			file.store_line("  " + name)
		file.store_line("")
	
	file.close()