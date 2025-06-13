extends Node

const SETTINGS_FILE = "user://settings.cfg"

var settings = {}
var default_settings = {
	"video": {
		"resolution": Vector2(1920, 1080),
		"fullscreen": false,
		"vsync": true,
		"msaa": 2,
		"fxaa": true,
		"shadows": 2,
		"shadow_quality": 2,
		"anisotropic_filter": 4,
		"texture_quality": 2,
		"render_scale": 1.0,
		"max_fps": 0
	},
	"audio": {
		"master_volume": 1.0,
		"sfx_volume": 1.0,
		"music_volume": 0.7,
		"voice_volume": 1.0,
		"ambient_volume": 0.8,
		"mute_when_unfocused": true
	},
	"controls": {
		"mouse_sensitivity": 1.0,
		"invert_y": false,
		"invert_x": false,
		"controller_vibration": true,
		"controller_deadzone": 0.2,
		"key_bindings": {}
	},
	"gameplay": {
		"difficulty": 1,
		"language": "en",
		"subtitles": true,
		"tutorials": true,
		"auto_save": true,
		"auto_save_interval": 300,
		"show_fps": false,
		"field_of_view": 75
	},
	"graphics": {
		"brightness": 1.0,
		"contrast": 1.0,
		"gamma": 1.0,
		"motion_blur": true,
		"bloom": true,
		"ambient_occlusion": true,
		"screen_space_reflections": false,
		"particle_quality": 2
	}
}

signal settings_changed(category, setting, value)
signal settings_saved()
signal settings_loaded()

func _ready():
	load_settings()
	apply_all_settings()

func load_settings():
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_FILE)
	
	if err != OK:
		print("No settings file found, using defaults")
		settings = default_settings.duplicate(true)
		save_settings()
		return
	
	settings = {}
	
	for category in default_settings:
		if not settings.has(category):
			settings[category] = {}
		
		for setting in default_settings[category]:
			if config.has_section_key(category, setting):
				settings[category][setting] = config.get_value(category, setting)
			else:
				settings[category][setting] = default_settings[category][setting]
	
	emit_signal("settings_loaded")

func save_settings():
	var config = ConfigFile.new()
	
	for category in settings:
		for setting in settings[category]:
			config.set_value(category, setting, settings[category][setting])
	
	var err = config.save(SETTINGS_FILE)
	
	if err == OK:
		emit_signal("settings_saved")
	else:
		push_error("Failed to save settings")

func get_setting(category: String, setting: String):
	if settings.has(category) and settings[category].has(setting):
		return settings[category][setting]
	elif default_settings.has(category) and default_settings[category].has(setting):
		return default_settings[category][setting]
	else:
		push_error("Setting not found: " + category + "/" + setting)
		return null

func set_setting(category: String, setting: String, value):
	if not settings.has(category):
		settings[category] = {}
	
	settings[category][setting] = value
	apply_setting(category, setting, value)
	emit_signal("settings_changed", category, setting, value)

func apply_all_settings():
	for category in settings:
		for setting in settings[category]:
			apply_setting(category, setting, settings[category][setting])

func apply_setting(category: String, setting: String, value):
	match category:
		"video":
			_apply_video_setting(setting, value)
		"audio":
			_apply_audio_setting(setting, value)
		"controls":
			_apply_control_setting(setting, value)
		"gameplay":
			_apply_gameplay_setting(setting, value)
		"graphics":
			_apply_graphics_setting(setting, value)

func _apply_video_setting(setting: String, value):
	match setting:
		"resolution":
			OS.window_size = value
			OS.center_window()
		"fullscreen":
			OS.window_fullscreen = value
		"vsync":
			OS.vsync_enabled = value
		"msaa":
			get_viewport().msaa = value
		"fxaa":
			get_viewport().fxaa = value
		"shadows":
			var quality = ProjectSettings.get_setting("rendering/quality/shadows/filter_mode")
			ProjectSettings.set_setting("rendering/quality/shadows/filter_mode", value)
		"anisotropic_filter":
			ProjectSettings.set_setting("rendering/quality/filters/anisotropic_filter_level", value)
		"render_scale":
			get_viewport().set_size(OS.window_size * value)
		"max_fps":
			Engine.target_fps = value if value > 0 else 0

func _apply_audio_setting(setting: String, value):
	match setting:
		"master_volume":
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear2db(value))
		"sfx_volume":
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear2db(value))
		"music_volume":
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear2db(value))
		"voice_volume":
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Voice"), linear2db(value))
		"ambient_volume":
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambient"), linear2db(value))

func _apply_control_setting(setting: String, value):
	match setting:
		"key_bindings":
			_apply_key_bindings(value)

func _apply_gameplay_setting(setting: String, value):
	match setting:
		"language":
			TranslationServer.set_locale(value)
		"field_of_view":
			if has_node("/root/Game/Player/Camera"):
				get_node("/root/Game/Player/Camera").fov = value

func _apply_graphics_setting(setting: String, value):
	pass

func _apply_key_bindings(bindings: Dictionary):
	for action in bindings:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
			
			for event in bindings[action]:
				InputMap.action_add_event(action, event)

func reset_to_defaults(category: String = ""):
	if category == "":
		settings = default_settings.duplicate(true)
	elif default_settings.has(category):
		settings[category] = default_settings[category].duplicate(true)
	
	apply_all_settings()
	save_settings()

func reset_controls():
	InputMap.load_from_globals()
	settings["controls"]["key_bindings"] = {}

func get_all_settings() -> Dictionary:
	return settings.duplicate(true)

func import_settings(settings_dict: Dictionary):
	settings = settings_dict
	apply_all_settings()
	save_settings()

func export_settings() -> String:
	return to_json(settings)

func validate_settings():
	for category in default_settings:
		if not settings.has(category):
			settings[category] = default_settings[category].duplicate(true)
		else:
			for setting in default_settings[category]:
				if not settings[category].has(setting):
					settings[category][setting] = default_settings[category][setting]

func add_custom_setting(category: String, setting: String, default_value, apply_func: FuncRef = null):
	if not default_settings.has(category):
		default_settings[category] = {}
	
	default_settings[category][setting] = default_value
	
	if not settings.has(category):
		settings[category] = {}
	
	if not settings[category].has(setting):
		settings[category][setting] = default_value

func remove_custom_setting(category: String, setting: String):
	if default_settings.has(category) and default_settings[category].has(setting):
		default_settings[category].erase(setting)
	
	if settings.has(category) and settings[category].has(setting):
		settings[category].erase(setting)

func bind_setting_to_node(category: String, setting: String, node: Node, property: String):
	var value = get_setting(category, setting)
	if value != null:
		node.set(property, value)
	
	connect("settings_changed", self, "_on_setting_changed_for_node", [node, property])

func _on_setting_changed_for_node(category: String, setting: String, value, node: Node, property: String):
	if is_instance_valid(node):
		node.set(property, value)