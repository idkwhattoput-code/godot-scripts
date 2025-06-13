extends Node

# Save System for Godot 3D Games
# Handles game saves, settings, and persistent data
# Supports multiple save slots, compression, and encryption

# Save settings
export var save_directory = "user://saves/"
export var settings_file = "user://settings.cfg"
export var max_save_slots = 10
export var auto_save_enabled = true
export var auto_save_interval = 300.0  # 5 minutes
export var use_compression = true
export var use_encryption = false
export var encryption_key = "your-encryption-key-here"

# Save versioning
export var save_version = 1
export var min_compatible_version = 1

# Signals
signal save_completed(slot)
signal load_completed(slot)
signal save_failed(slot, error)
signal load_failed(slot, error)
signal auto_save_triggered()

# Internal variables
var current_save_slot = 0
var save_data = {}
var settings = {}
var auto_save_timer: Timer
var is_saving = false

# Save data structure
var default_save_data = {
	"version": save_version,
	"timestamp": 0,
	"play_time": 0.0,
	"player": {
		"position": Vector3.ZERO,
		"rotation": Vector3.ZERO,
		"health": 100,
		"inventory": []
	},
	"world": {
		"current_level": "",
		"unlocked_areas": [],
		"collected_items": []
	},
	"stats": {
		"enemies_defeated": 0,
		"distance_traveled": 0.0,
		"deaths": 0
	}
}

# Settings structure
var default_settings = {
	"graphics": {
		"resolution": "1920x1080",
		"fullscreen": false,
		"vsync": true,
		"quality": 2,
		"shadows": true,
		"anti_aliasing": "MSAA_4X"
	},
	"audio": {
		"master_volume": 1.0,
		"sfx_volume": 1.0,
		"music_volume": 0.8,
		"voice_volume": 1.0
	},
	"controls": {
		"mouse_sensitivity": 0.3,
		"invert_y": false,
		"controller_vibration": true
	},
	"gameplay": {
		"difficulty": 1,
		"language": "en",
		"subtitles": true
	}
}

func _ready():
	# Create save directory if it doesn't exist
	var dir = Directory.new()
	if not dir.dir_exists(save_directory):
		dir.make_dir_recursive(save_directory)
	
	# Load settings
	load_settings()
	
	# Setup auto-save
	if auto_save_enabled:
		setup_auto_save()

func setup_auto_save():
	"""Setup auto-save timer"""
	auto_save_timer = Timer.new()
	auto_save_timer.wait_time = auto_save_interval
	auto_save_timer.timeout.connect(trigger_auto_save)
	add_child(auto_save_timer)
	auto_save_timer.start()

func trigger_auto_save():
	"""Trigger an auto-save"""
	if not is_saving:
		emit_signal("auto_save_triggered")
		save_game(current_save_slot)

# Save methods
func save_game(slot: int) -> bool:
	"""Save game to specified slot"""
	if is_saving:
		return false
	
	is_saving = true
	
	# Prepare save data
	var data = prepare_save_data()
	
	# Save to file
	var success = write_save_file(slot, data)
	
	is_saving = false
	
	if success:
		emit_signal("save_completed", slot)
	else:
		emit_signal("save_failed", slot, "Failed to write save file")
	
	return success

func prepare_save_data() -> Dictionary:
	"""Prepare data for saving"""
	var data = default_save_data.duplicate(true)
	
	# Update metadata
	data.version = save_version
	data.timestamp = OS.get_unix_time()
	
	# Collect data from game systems
	collect_player_data(data)
	collect_world_data(data)
	collect_stats_data(data)
	
	# Allow other systems to add data
	get_tree().call_group("save_listeners", "_on_save_game", data)
	
	return data

func collect_player_data(data: Dictionary):
	"""Collect player-related data"""
	var player = get_tree().get_nodes_in_group("player")[0] if get_tree().has_group("player") else null
	if player:
		data.player.position = player.global_transform.origin
		data.player.rotation = player.rotation
		
		if player.has_method("get_health"):
			data.player.health = player.get_health()
		
		if player.has_method("get_inventory"):
			data.player.inventory = player.get_inventory()

func collect_world_data(data: Dictionary):
	"""Collect world state data"""
	# Get current level
	var current_scene = get_tree().current_scene
	if current_scene:
		data.world.current_level = current_scene.filename
	
	# Collect other world data
	# This would be customized for your game

func collect_stats_data(data: Dictionary):
	"""Collect gameplay statistics"""
	# This would be customized for your game
	pass

func write_save_file(slot: int, data: Dictionary) -> bool:
	"""Write save data to file"""
	var file_path = save_directory + "save_" + str(slot) + ".sav"
	var file = File.new()
	
	var open_mode = File.WRITE
	if use_compression:
		open_mode = File.WRITE_READ | File.COMPRESSION_DEFLATE
	
	var error
	if use_encryption:
		error = file.open_encrypted_with_pass(file_path, open_mode, encryption_key)
	else:
		error = file.open(file_path, open_mode)
	
	if error != OK:
		push_error("Failed to open save file: " + file_path)
		return false
	
	# Convert data to JSON
	var json_string = JSON.print(data)
	file.store_string(json_string)
	file.close()
	
	# Create backup
	create_backup(slot)
	
	return true

func create_backup(slot: int):
	"""Create backup of save file"""
	var original = save_directory + "save_" + str(slot) + ".sav"
	var backup = save_directory + "save_" + str(slot) + ".bak"
	
	var dir = Directory.new()
	if dir.file_exists(original):
		dir.copy(original, backup)

# Load methods
func load_game(slot: int) -> bool:
	"""Load game from specified slot"""
	var data = read_save_file(slot)
	if not data:
		emit_signal("load_failed", slot, "Failed to read save file")
		return false
	
	# Check version compatibility
	if not is_save_compatible(data):
		emit_signal("load_failed", slot, "Incompatible save version")
		return false
	
	# Apply save data
	apply_save_data(data)
	
	current_save_slot = slot
	emit_signal("load_completed", slot)
	
	return true

func read_save_file(slot: int) -> Dictionary:
	"""Read save data from file"""
	var file_path = save_directory + "save_" + str(slot) + ".sav"
	var file = File.new()
	
	# Check if file exists
	if not file.file_exists(file_path):
		# Try backup
		var backup_path = save_directory + "save_" + str(slot) + ".bak"
		if file.file_exists(backup_path):
			file_path = backup_path
		else:
			return {}
	
	var open_mode = File.READ
	if use_compression:
		open_mode = File.READ | File.COMPRESSION_DEFLATE
	
	var error
	if use_encryption:
		error = file.open_encrypted_with_pass(file_path, open_mode, encryption_key)
	else:
		error = file.open(file_path, open_mode)
	
	if error != OK:
		push_error("Failed to open save file: " + file_path)
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	# Parse JSON
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		push_error("Failed to parse save file")
		return {}
	
	return json.data

func is_save_compatible(data: Dictionary) -> bool:
	"""Check if save file is compatible with current version"""
	if not data.has("version"):
		return false
	
	return data.version >= min_compatible_version

func apply_save_data(data: Dictionary):
	"""Apply loaded save data to game"""
	save_data = data
	
	# Apply player data
	apply_player_data(data.player)
	
	# Load level if different
	if data.world.has("current_level") and data.world.current_level != "":
		get_tree().change_scene(data.world.current_level)
		yield(get_tree(), "idle_frame")
	
	# Apply world data
	apply_world_data(data.world)
	
	# Apply stats
	apply_stats_data(data.stats)
	
	# Notify other systems
	get_tree().call_group("save_listeners", "_on_load_game", data)

func apply_player_data(player_data: Dictionary):
	"""Apply player data from save"""
	var player = get_tree().get_nodes_in_group("player")[0] if get_tree().has_group("player") else null
	if player:
		player.global_transform.origin = player_data.position
		player.rotation = player_data.rotation
		
		if player.has_method("set_health"):
			player.set_health(player_data.health)
		
		if player.has_method("set_inventory"):
			player.set_inventory(player_data.inventory)

func apply_world_data(world_data: Dictionary):
	"""Apply world state from save"""
	# This would be customized for your game
	pass

func apply_stats_data(stats_data: Dictionary):
	"""Apply statistics from save"""
	# This would be customized for your game
	pass

# Save slot management
func get_save_slots() -> Array:
	"""Get information about all save slots"""
	var slots = []
	
	for i in range(max_save_slots):
		var slot_info = get_save_slot_info(i)
		slots.append(slot_info)
	
	return slots

func get_save_slot_info(slot: int) -> Dictionary:
	"""Get information about a specific save slot"""
	var info = {
		"slot": slot,
		"exists": false,
		"timestamp": 0,
		"play_time": 0.0,
		"level": "",
		"thumbnail": null
	}
	
	var data = read_save_file(slot)
	if data:
		info.exists = true
		info.timestamp = data.get("timestamp", 0)
		info.play_time = data.get("play_time", 0.0)
		info.level = data.get("world", {}).get("current_level", "")
		# Load thumbnail if exists
		var thumbnail_path = save_directory + "save_" + str(slot) + ".png"
		if File.new().file_exists(thumbnail_path):
			var image = Image.new()
			if image.load(thumbnail_path) == OK:
				var texture = ImageTexture.new()
				texture.create_from_image(image)
				info.thumbnail = texture
	
	return info

func delete_save(slot: int) -> bool:
	"""Delete a save file"""
	var dir = Directory.new()
	var file_path = save_directory + "save_" + str(slot) + ".sav"
	var backup_path = save_directory + "save_" + str(slot) + ".bak"
	var thumbnail_path = save_directory + "save_" + str(slot) + ".png"
	
	var success = true
	
	if dir.file_exists(file_path):
		success = success and dir.remove(file_path) == OK
	
	if dir.file_exists(backup_path):
		dir.remove(backup_path)
	
	if dir.file_exists(thumbnail_path):
		dir.remove(thumbnail_path)
	
	return success

func save_thumbnail(slot: int):
	"""Save a screenshot thumbnail for the save slot"""
	var image = get_viewport().get_texture().get_data()
	image.flip_y()
	
	# Resize to thumbnail size
	image.resize(320, 180, Image.INTERPOLATE_BILINEAR)
	
	var thumbnail_path = save_directory + "save_" + str(slot) + ".png"
	image.save_png(thumbnail_path)

# Settings management
func save_settings():
	"""Save game settings"""
	var config = ConfigFile.new()
	
	for section in settings:
		for key in settings[section]:
			config.set_value(section, key, settings[section][key])
	
	config.save(settings_file)

func load_settings():
	"""Load game settings"""
	var config = ConfigFile.new()
	var error = config.load(settings_file)
	
	if error != OK:
		# Use default settings
		settings = default_settings.duplicate(true)
		save_settings()
		return
	
	# Load settings from file
	settings = {}
	for section in config.get_sections():
		settings[section] = {}
		for key in config.get_section_keys(section):
			settings[section][key] = config.get_value(section, key)
	
	# Apply settings
	apply_settings()

func apply_settings():
	"""Apply loaded settings to game"""
	# Graphics settings
	if settings.has("graphics"):
		var graphics = settings.graphics
		
		# Resolution
		if graphics.has("resolution"):
			var res = graphics.resolution.split("x")
			OS.window_size = Vector2(int(res[0]), int(res[1]))
		
		# Fullscreen
		if graphics.has("fullscreen"):
			OS.window_fullscreen = graphics.fullscreen
		
		# VSync
		if graphics.has("vsync"):
			OS.vsync_enabled = graphics.vsync
	
	# Audio settings
	if settings.has("audio"):
		var audio = settings.audio
		
		if audio.has("master_volume"):
			AudioServer.set_bus_volume_db(0, linear2db(audio.master_volume))
	
	# Notify other systems
	get_tree().call_group("settings_listeners", "_on_settings_changed", settings)

func get_setting(category: String, key: String, default_value = null):
	"""Get a specific setting value"""
	if settings.has(category) and settings[category].has(key):
		return settings[category][key]
	return default_value

func set_setting(category: String, key: String, value):
	"""Set a specific setting value"""
	if not settings.has(category):
		settings[category] = {}
	
	settings[category][key] = value
	save_settings()
	
	# Apply immediately
	apply_settings()