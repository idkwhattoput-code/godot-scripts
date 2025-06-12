extends Control

export var apply_settings_immediately = true
export var show_restart_required = true

var current_tab = "graphics"
var changed_settings = {}
var original_settings = {}
var require_restart = []

onready var tab_buttons = $SidePanel/TabButtons
onready var content_panel = $ContentPanel
onready var graphics_tab = $ContentPanel/GraphicsTab
onready var audio_tab = $ContentPanel/AudioTab
onready var controls_tab = $ContentPanel/ControlsTab
onready var gameplay_tab = $ContentPanel/GameplayTab
onready var apply_button = $BottomPanel/ApplyButton
onready var reset_button = $BottomPanel/ResetButton
onready var back_button = $BottomPanel/BackButton
onready var restart_label = $BottomPanel/RestartLabel

# Graphics controls
onready var resolution_option = $ContentPanel/GraphicsTab/Resolution/OptionButton
onready var fullscreen_check = $ContentPanel/GraphicsTab/Fullscreen/CheckBox
onready var vsync_check = $ContentPanel/GraphicsTab/VSync/CheckBox
onready var quality_preset = $ContentPanel/GraphicsTab/QualityPreset/OptionButton
onready var shadow_quality = $ContentPanel/GraphicsTab/ShadowQuality/OptionButton
onready var texture_quality = $ContentPanel/GraphicsTab/TextureQuality/OptionButton
onready var anti_aliasing = $ContentPanel/GraphicsTab/AntiAliasing/OptionButton
onready var render_scale = $ContentPanel/GraphicsTab/RenderScale/Slider
onready var render_scale_label = $ContentPanel/GraphicsTab/RenderScale/ValueLabel
onready var max_fps = $ContentPanel/GraphicsTab/MaxFPS/SpinBox
onready var brightness_slider = $ContentPanel/GraphicsTab/Brightness/Slider
onready var brightness_label = $ContentPanel/GraphicsTab/Brightness/ValueLabel

# Audio controls
onready var master_volume = $ContentPanel/AudioTab/MasterVolume/Slider
onready var master_label = $ContentPanel/AudioTab/MasterVolume/ValueLabel
onready var sfx_volume = $ContentPanel/AudioTab/SFXVolume/Slider
onready var sfx_label = $ContentPanel/AudioTab/SFXVolume/ValueLabel
onready var music_volume = $ContentPanel/AudioTab/MusicVolume/Slider
onready var music_label = $ContentPanel/AudioTab/MusicVolume/ValueLabel
onready var voice_volume = $ContentPanel/AudioTab/VoiceVolume/Slider
onready var voice_label = $ContentPanel/AudioTab/VoiceVolume/ValueLabel
onready var audio_device = $ContentPanel/AudioTab/AudioDevice/OptionButton
onready var mute_unfocused = $ContentPanel/AudioTab/MuteUnfocused/CheckBox

# Controls
onready var sensitivity_slider = $ContentPanel/ControlsTab/MouseSensitivity/Slider
onready var sensitivity_label = $ContentPanel/ControlsTab/MouseSensitivity/ValueLabel
onready var invert_y_check = $ContentPanel/ControlsTab/InvertY/CheckBox
onready var invert_x_check = $ContentPanel/ControlsTab/InvertX/CheckBox
onready var controller_vibration = $ContentPanel/ControlsTab/ControllerVibration/CheckBox
onready var keybind_list = $ContentPanel/ControlsTab/KeybindList
onready var rebind_button = $ContentPanel/ControlsTab/RebindButton

# Gameplay
onready var difficulty_option = $ContentPanel/GameplayTab/Difficulty/OptionButton
onready var language_option = $ContentPanel/GameplayTab/Language/OptionButton
onready var subtitles_check = $ContentPanel/GameplayTab/Subtitles/CheckBox
onready var tutorials_check = $ContentPanel/GameplayTab/Tutorials/CheckBox
onready var auto_save_check = $ContentPanel/GameplayTab/AutoSave/CheckBox
onready var auto_save_interval = $ContentPanel/GameplayTab/AutoSaveInterval/SpinBox
onready var fov_slider = $ContentPanel/GameplayTab/FieldOfView/Slider
onready var fov_label = $ContentPanel/GameplayTab/FieldOfView/ValueLabel

signal settings_applied()
signal back_pressed()

var supported_resolutions = [
	"640x480",
	"800x600",
	"1024x768",
	"1280x720",
	"1366x768",
	"1600x900",
	"1920x1080",
	"2560x1440",
	"3840x2160"
]

var quality_presets = {
	"Low": {
		"shadows": 0,
		"textures": 0,
		"aa": 0,
		"render_scale": 0.75
	},
	"Medium": {
		"shadows": 1,
		"textures": 1,
		"aa": 1,
		"render_scale": 0.9
	},
	"High": {
		"shadows": 2,
		"textures": 2,
		"aa": 2,
		"render_scale": 1.0
	},
	"Ultra": {
		"shadows": 3,
		"textures": 3,
		"aa": 4,
		"render_scale": 1.0
	}
}

func _ready():
	_setup_ui()
	_connect_signals()
	_load_current_settings()
	_show_tab("graphics")

func _setup_ui():
	# Populate dropdowns
	_populate_resolution_options()
	_populate_quality_options()
	_populate_language_options()
	_populate_audio_devices()
	_populate_keybinds()
	
	restart_label.hide()
	apply_button.disabled = true
	
	# Set slider ranges
	render_scale.min_value = 0.5
	render_scale.max_value = 2.0
	render_scale.step = 0.05
	
	brightness_slider.min_value = 0.5
	brightness_slider.max_value = 1.5
	brightness_slider.step = 0.05
	
	sensitivity_slider.min_value = 0.1
	sensitivity_slider.max_value = 3.0
	sensitivity_slider.step = 0.1
	
	fov_slider.min_value = 60
	fov_slider.max_value = 120
	fov_slider.step = 5

func _connect_signals():
	# Tab buttons
	for i in range(tab_buttons.get_child_count()):
		var button = tab_buttons.get_child(i)
		button.connect("pressed", self, "_on_tab_button_pressed", [button.name.to_lower()])
	
	# Bottom buttons
	apply_button.connect("pressed", self, "_on_apply_pressed")
	reset_button.connect("pressed", self, "_on_reset_pressed")
	back_button.connect("pressed", self, "_on_back_pressed")
	
	# Graphics
	resolution_option.connect("item_selected", self, "_on_setting_changed", ["resolution"])
	fullscreen_check.connect("toggled", self, "_on_setting_changed", ["fullscreen"])
	vsync_check.connect("toggled", self, "_on_setting_changed", ["vsync"])
	quality_preset.connect("item_selected", self, "_on_quality_preset_changed")
	shadow_quality.connect("item_selected", self, "_on_setting_changed", ["shadow_quality"])
	texture_quality.connect("item_selected", self, "_on_setting_changed", ["texture_quality"])
	anti_aliasing.connect("item_selected", self, "_on_setting_changed", ["anti_aliasing"])
	render_scale.connect("value_changed", self, "_on_render_scale_changed")
	max_fps.connect("value_changed", self, "_on_setting_changed", ["max_fps"])
	brightness_slider.connect("value_changed", self, "_on_brightness_changed")
	
	# Audio
	master_volume.connect("value_changed", self, "_on_volume_changed", ["master"])
	sfx_volume.connect("value_changed", self, "_on_volume_changed", ["sfx"])
	music_volume.connect("value_changed", self, "_on_volume_changed", ["music"])
	voice_volume.connect("value_changed", self, "_on_volume_changed", ["voice"])
	audio_device.connect("item_selected", self, "_on_setting_changed", ["audio_device"])
	mute_unfocused.connect("toggled", self, "_on_setting_changed", ["mute_unfocused"])
	
	# Controls
	sensitivity_slider.connect("value_changed", self, "_on_sensitivity_changed")
	invert_y_check.connect("toggled", self, "_on_setting_changed", ["invert_y"])
	invert_x_check.connect("toggled", self, "_on_setting_changed", ["invert_x"])
	controller_vibration.connect("toggled", self, "_on_setting_changed", ["controller_vibration"])
	rebind_button.connect("pressed", self, "_on_rebind_pressed")
	
	# Gameplay
	difficulty_option.connect("item_selected", self, "_on_setting_changed", ["difficulty"])
	language_option.connect("item_selected", self, "_on_language_changed")
	subtitles_check.connect("toggled", self, "_on_setting_changed", ["subtitles"])
	tutorials_check.connect("toggled", self, "_on_setting_changed", ["tutorials"])
	auto_save_check.connect("toggled", self, "_on_setting_changed", ["auto_save"])
	auto_save_interval.connect("value_changed", self, "_on_setting_changed", ["auto_save_interval"])
	fov_slider.connect("value_changed", self, "_on_fov_changed")

func _populate_resolution_options():
	resolution_option.clear()
	for res in supported_resolutions:
		resolution_option.add_item(res)
	
	# Select current resolution
	var current_res = "%dx%d" % [OS.window_size.x, OS.window_size.y]
	for i in range(resolution_option.get_item_count()):
		if resolution_option.get_item_text(i) == current_res:
			resolution_option.select(i)
			break

func _populate_quality_options():
	quality_preset.clear()
	quality_preset.add_item("Custom")
	for preset in ["Low", "Medium", "High", "Ultra"]:
		quality_preset.add_item(preset)
	
	shadow_quality.clear()
	shadow_quality.add_item("Disabled")
	shadow_quality.add_item("Low")
	shadow_quality.add_item("Medium")
	shadow_quality.add_item("High")
	
	texture_quality.clear()
	texture_quality.add_item("Low")
	texture_quality.add_item("Medium")
	texture_quality.add_item("High")
	texture_quality.add_item("Ultra")
	
	anti_aliasing.clear()
	anti_aliasing.add_item("None")
	anti_aliasing.add_item("FXAA")
	anti_aliasing.add_item("2x MSAA")
	anti_aliasing.add_item("4x MSAA")
	anti_aliasing.add_item("8x MSAA")

func _populate_language_options():
	language_option.clear()
	language_option.add_item("English")
	language_option.add_item("Spanish")
	language_option.add_item("French")
	language_option.add_item("German")
	language_option.add_item("Japanese")
	language_option.add_item("Chinese")

func _populate_audio_devices():
	audio_device.clear()
	audio_device.add_item("Default")
	# Add actual audio devices if available

func _populate_keybinds():
	keybind_list.clear()
	
	var actions = InputMap.get_actions()
	for action in actions:
		if action.begins_with("ui_"):
			continue
		
		keybind_list.add_item(action.capitalize())
		var events = InputMap.get_action_list(action)
		
		var key_text = "Not Bound"
		if events.size() > 0 and events[0] is InputEventKey:
			key_text = OS.get_scancode_string(events[0].scancode)
		
		keybind_list.add_item(key_text)
		keybind_list.set_item_custom_fg_color(keybind_list.get_item_count() - 1, Color(0.7, 0.7, 1.0))

func _show_tab(tab_name: String):
	current_tab = tab_name
	
	# Hide all tabs
	for child in content_panel.get_children():
		child.hide()
	
	# Show selected tab
	match tab_name:
		"graphics":
			graphics_tab.show()
		"audio":
			audio_tab.show()
		"controls":
			controls_tab.show()
		"gameplay":
			gameplay_tab.show()
	
	# Update button states
	for button in tab_buttons.get_children():
		button.pressed = button.name.to_lower() == tab_name

func _on_tab_button_pressed(tab_name: String):
	_show_tab(tab_name)

func _on_setting_changed(value, setting_name: String):
	changed_settings[setting_name] = value
	apply_button.disabled = false
	
	if apply_settings_immediately:
		_apply_setting(setting_name, value)

func _on_quality_preset_changed(index: int):
	if index == 0:  # Custom
		return
	
	var preset_name = quality_preset.get_item_text(index)
	if quality_presets.has(preset_name):
		var preset = quality_presets[preset_name]
		
		shadow_quality.select(preset.shadows)
		texture_quality.select(preset.textures)
		anti_aliasing.select(preset.aa)
		render_scale.value = preset.render_scale
		
		_on_setting_changed(preset.shadows, "shadow_quality")
		_on_setting_changed(preset.textures, "texture_quality")
		_on_setting_changed(preset.aa, "anti_aliasing")
		_on_setting_changed(preset.render_scale, "render_scale")

func _on_render_scale_changed(value: float):
	render_scale_label.text = "%d%%" % (value * 100)
	_on_setting_changed(value, "render_scale")

func _on_brightness_changed(value: float):
	brightness_label.text = "%d%%" % (value * 100)
	_on_setting_changed(value, "brightness")

func _on_volume_changed(value: float, bus_name: String):
	var label = get_node("ContentPanel/AudioTab/%sVolume/ValueLabel" % bus_name.capitalize())
	label.text = "%d%%" % (value * 100)
	_on_setting_changed(value, bus_name + "_volume")
	
	if apply_settings_immediately:
		var bus_idx = AudioServer.get_bus_index(bus_name.capitalize())
		AudioServer.set_bus_volume_db(bus_idx, linear2db(value))

func _on_sensitivity_changed(value: float):
	sensitivity_label.text = "%.1f" % value
	_on_setting_changed(value, "mouse_sensitivity")

func _on_fov_changed(value: float):
	fov_label.text = "%d°" % value
	_on_setting_changed(value, "field_of_view")

func _on_language_changed(index: int):
	_on_setting_changed(index, "language")
	
	if show_restart_required and not "language" in require_restart:
		require_restart.append("language")
		restart_label.show()

func _on_rebind_pressed():
	# Show keybind dialog
	pass

func _on_apply_pressed():
	for setting in changed_settings:
		_apply_setting(setting, changed_settings[setting])
	
	changed_settings.clear()
	apply_button.disabled = true
	
	emit_signal("settings_applied")
	
	if require_restart.size() > 0:
		_show_restart_dialog()

func _on_reset_pressed():
	var confirm = ConfirmationDialog.new()
	confirm.dialog_text = "Reset all settings to default values?"
	add_child(confirm)
	confirm.popup_centered()
	
	yield(confirm, "confirmed")
	
	_reset_to_defaults()
	confirm.queue_free()

func _on_back_pressed():
	if changed_settings.size() > 0:
		var confirm = ConfirmationDialog.new()
		confirm.dialog_text = "You have unsaved changes. Discard them?"
		add_child(confirm)
		confirm.popup_centered()
		
		yield(confirm, "confirmed")
		confirm.queue_free()
	
	emit_signal("back_pressed")

func _apply_setting(setting_name: String, value):
	# Apply the setting to the game
	SettingsManager.set_setting(current_tab, setting_name, value)

func _load_current_settings():
	# Load graphics settings
	fullscreen_check.pressed = OS.window_fullscreen
	vsync_check.pressed = OS.vsync_enabled
	render_scale.value = SettingsManager.get_setting("graphics", "render_scale", 1.0)
	brightness_slider.value = SettingsManager.get_setting("graphics", "brightness", 1.0)
	
	# Load audio settings
	master_volume.value = SettingsManager.get_setting("audio", "master_volume", 1.0)
	sfx_volume.value = SettingsManager.get_setting("audio", "sfx_volume", 1.0)
	music_volume.value = SettingsManager.get_setting("audio", "music_volume", 0.7)
	voice_volume.value = SettingsManager.get_setting("audio", "voice_volume", 1.0)
	
	# Load control settings
	sensitivity_slider.value = SettingsManager.get_setting("controls", "mouse_sensitivity", 1.0)
	invert_y_check.pressed = SettingsManager.get_setting("controls", "invert_y", false)
	invert_x_check.pressed = SettingsManager.get_setting("controls", "invert_x", false)
	
	# Load gameplay settings
	subtitles_check.pressed = SettingsManager.get_setting("gameplay", "subtitles", true)
	tutorials_check.pressed = SettingsManager.get_setting("gameplay", "tutorials", true)
	auto_save_check.pressed = SettingsManager.get_setting("gameplay", "auto_save", true)
	fov_slider.value = SettingsManager.get_setting("gameplay", "field_of_view", 75)
	
	# Store original values
	original_settings = SettingsManager.get_all_settings()

func _reset_to_defaults():
	SettingsManager.reset_to_defaults()
	_load_current_settings()
	changed_settings.clear()
	apply_button.disabled = true

func _show_restart_dialog():
	var dialog = AcceptDialog.new()
	dialog.dialog_text = "Some changes require a game restart to take effect."
	add_child(dialog)
	dialog.popup_centered()
	yield(dialog, "popup_hide")
	dialog.queue_free()