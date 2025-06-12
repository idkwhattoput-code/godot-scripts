extends Node

class_name SaveLoadSystem

signal game_saved(save_file: String)
signal game_loaded(save_file: String)
signal save_failed(error: String)
signal load_failed(error: String)

@export var save_directory: String = "user://saves/"
@export var save_file_extension: String = ".save"
@export var auto_save_interval: float = 300.0
@export var max_save_files: int = 10
@export var encrypt_saves: bool = false
@export var encryption_key: String = "default_key"

var current_save_file: String = ""
var auto_save_timer: Timer
var save_data_registry: Dictionary = {}

func _ready():
	ensure_save_directory_exists()
	setup_auto_save()
	register_core_systems()

func ensure_save_directory_exists():
	var dir = DirAccess.open("user://")
	if not dir.dir_exists(save_directory):
		dir.make_dir_recursive(save_directory)

func setup_auto_save():
	auto_save_timer = Timer.new()
	add_child(auto_save_timer)
	auto_save_timer.wait_time = auto_save_interval
	auto_save_timer.timeout.connect(auto_save)
	auto_save_timer.start()

func register_core_systems():
	register_save_system("player", get_player_save_data, load_player_data)
	register_save_system("game_state", get_game_state_data, load_game_state_data)
	register_save_system("settings", get_settings_data, load_settings_data)

func register_save_system(system_name: String, save_func: Callable, load_func: Callable):
	save_data_registry[system_name] = {
		"save": save_func,
		"load": load_func
	}

func save_game(save_name: String = "") -> bool:
	if save_name.is_empty():
		save_name = "quicksave"
	
	var save_file_path = save_directory + save_name + save_file_extension
	var save_data = compile_save_data()
	
	if save_data.is_empty():
		save_failed.emit("No save data to write")
		return false
	
	var success = write_save_file(save_file_path, save_data)
	
	if success:
		current_save_file = save_file_path
		cleanup_old_saves()
		game_saved.emit(save_file_path)
		print("Game saved successfully: ", save_file_path)
	else:
		save_failed.emit("Failed to write save file")
	
	return success

func load_game(save_name: String = "") -> bool:
	var save_file_path: String
	
	if save_name.is_empty():
		save_file_path = get_most_recent_save()
		if save_file_path.is_empty():
			load_failed.emit("No save files found")
			return false
	else:
		save_file_path = save_directory + save_name + save_file_extension
	
	if not FileAccess.file_exists(save_file_path):
		load_failed.emit("Save file does not exist: " + save_file_path)
		return false
	
	var save_data = read_save_file(save_file_path)
	
	if save_data.is_empty():
		load_failed.emit("Failed to read save file or file is corrupted")
		return false
	
	var success = apply_save_data(save_data)
	
	if success:
		current_save_file = save_file_path
		game_loaded.emit(save_file_path)
		print("Game loaded successfully: ", save_file_path)
	else:
		load_failed.emit("Failed to apply save data")
	
	return success

func compile_save_data() -> Dictionary:
	var save_data = {
		"version": "1.0",
		"timestamp": Time.get_unix_time_from_system(),
		"scene": get_tree().current_scene.scene_file_path if get_tree().current_scene else ""
	}
	
	for system_name in save_data_registry.keys():
		var system = save_data_registry[system_name]
		var system_data = system.save.call()
		if system_data != null:
			save_data[system_name] = system_data
	
	return save_data

func apply_save_data(save_data: Dictionary) -> bool:
	if not save_data.has("version"):
		return false
	
	for system_name in save_data_registry.keys():
		if save_data.has(system_name):
			var system = save_data_registry[system_name]
			var success = system.load.call(save_data[system_name])
			if not success:
				print("Failed to load data for system: ", system_name)
				return false
	
	if save_data.has("scene") and not save_data.scene.is_empty():
		get_tree().change_scene_to_file(save_data.scene)
	
	return true

func write_save_file(file_path: String, data: Dictionary) -> bool:
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		print("Failed to open file for writing: ", file_path)
		return false
	
	var json_string = JSON.stringify(data)
	
	if encrypt_saves:
		json_string = encrypt_data(json_string)
	
	file.store_string(json_string)
	file.close()
	return true

func read_save_file(file_path: String) -> Dictionary:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("Failed to open file for reading: ", file_path)
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	if encrypt_saves:
		json_string = decrypt_data(json_string)
		if json_string.is_empty():
			print("Failed to decrypt save file")
			return {}
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		print("Failed to parse save file JSON")
		return {}
	
	return json.data

func encrypt_data(data: String) -> String:
	var encrypted = data.to_utf8_buffer()
	var key_bytes = encryption_key.to_utf8_buffer()
	
	for i in range(encrypted.size()):
		encrypted[i] ^= key_bytes[i % key_bytes.size()]
	
	return Marshalls.raw_to_base64(encrypted)

func decrypt_data(encrypted_data: String) -> String:
	var encrypted_bytes = Marshalls.base64_to_raw(encrypted_data)
	if encrypted_bytes.is_empty():
		return ""
	
	var key_bytes = encryption_key.to_utf8_buffer()
	
	for i in range(encrypted_bytes.size()):
		encrypted_bytes[i] ^= key_bytes[i % key_bytes.size()]
	
	return encrypted_bytes.get_string_from_utf8()

func get_player_save_data() -> Dictionary:
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return {}
	
	var data = {
		"position": var_to_str(player.global_position),
		"health": player.get("health"),
		"level": player.get("level"),
		"experience": player.get("experience")
	}
	
	if player.has_method("get_save_data"):
		var custom_data = player.get_save_data()
		data.merge(custom_data)
	
	return data

func load_player_data(data: Dictionary) -> bool:
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return false
	
	if data.has("position"):
		player.global_position = str_to_var(data.position)
	
	if data.has("health") and player.has_method("set_health"):
		player.set_health(data.health)
	
	if data.has("level") and player.has_property("level"):
		player.level = data.level
	
	if data.has("experience") and player.has_property("experience"):
		player.experience = data.experience
	
	if player.has_method("load_save_data"):
		player.load_save_data(data)
	
	return true

func get_game_state_data() -> Dictionary:
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager and game_manager.has_method("get_save_data"):
		return game_manager.get_save_data()
	
	return {
		"current_level": get_tree().current_scene.scene_file_path,
		"game_time": Time.get_unix_time_from_system(),
		"score": 0
	}

func load_game_state_data(data: Dictionary) -> bool:
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager and game_manager.has_method("load_save_data"):
		return game_manager.load_save_data(data)
	
	return true

func get_settings_data() -> Dictionary:
	return {
		"master_volume": AudioServer.get_bus_volume_db(0),
		"sfx_volume": AudioServer.get_bus_volume_db(1) if AudioServer.get_bus_count() > 1 else 0,
		"music_volume": AudioServer.get_bus_volume_db(2) if AudioServer.get_bus_count() > 2 else 0,
		"fullscreen": DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN,
		"vsync": DisplayServer.window_get_vsync_mode()
	}

func load_settings_data(data: Dictionary) -> bool:
	if data.has("master_volume"):
		AudioServer.set_bus_volume_db(0, data.master_volume)
	
	if data.has("sfx_volume") and AudioServer.get_bus_count() > 1:
		AudioServer.set_bus_volume_db(1, data.sfx_volume)
	
	if data.has("music_volume") and AudioServer.get_bus_count() > 2:
		AudioServer.set_bus_volume_db(2, data.music_volume)
	
	if data.has("fullscreen"):
		var mode = DisplayServer.WINDOW_MODE_FULLSCREEN if data.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		DisplayServer.window_set_mode(mode)
	
	if data.has("vsync"):
		DisplayServer.window_set_vsync_mode(data.vsync)
	
	return true

func auto_save():
	if current_save_file.is_empty():
		save_game("autosave")
	else:
		var file_name = current_save_file.get_file().get_basename()
		save_game("autosave_" + str(Time.get_unix_time_from_system()))

func quick_save():
	save_game("quicksave")

func quick_load():
	load_game("quicksave")

func get_save_files() -> Array[String]:
	var save_files: Array[String] = []
	var dir = DirAccess.open(save_directory)
	
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if file_name.ends_with(save_file_extension):
				save_files.append(file_name.get_basename())
			file_name = dir.get_next()
	
	return save_files

func get_most_recent_save() -> String:
	var save_files = get_save_files()
	if save_files.is_empty():
		return ""
	
	var most_recent_file = ""
	var most_recent_time = 0
	
	for save_file in save_files:
		var file_path = save_directory + save_file + save_file_extension
		var file_time = FileAccess.get_modified_time(file_path)
		
		if file_time > most_recent_time:
			most_recent_time = file_time
			most_recent_file = file_path
	
	return most_recent_file

func delete_save(save_name: String) -> bool:
	var file_path = save_directory + save_name + save_file_extension
	
	if FileAccess.file_exists(file_path):
		var dir = DirAccess.open(save_directory)
		return dir.remove(file_path) == OK
	
	return false

func cleanup_old_saves():
	var save_files = get_save_files()
	
	if save_files.size() <= max_save_files:
		return
	
	var file_times: Array[Dictionary] = []
	
	for save_file in save_files:
		var file_path = save_directory + save_file + save_file_extension
		file_times.append({
			"file": save_file,
			"time": FileAccess.get_modified_time(file_path)
		})
	
	file_times.sort_custom(func(a, b): return a.time > b.time)
	
	for i in range(max_save_files, file_times.size()):
		delete_save(file_times[i].file)

func has_save_file(save_name: String) -> bool:
	var file_path = save_directory + save_name + save_file_extension
	return FileAccess.file_exists(file_path)

func get_save_info(save_name: String) -> Dictionary:
	var file_path = save_directory + save_name + save_file_extension
	
	if not FileAccess.file_exists(file_path):
		return {}
	
	var save_data = read_save_file(file_path)
	
	return {
		"name": save_name,
		"timestamp": save_data.get("timestamp", 0),
		"scene": save_data.get("scene", ""),
		"version": save_data.get("version", ""),
		"file_size": FileAccess.get_file_as_bytes(file_path).size()
	}

func set_auto_save_enabled(enabled: bool):
	if enabled:
		auto_save_timer.start()
	else:
		auto_save_timer.stop()

func set_auto_save_interval(interval: float):
	auto_save_interval = interval
	auto_save_timer.wait_time = interval