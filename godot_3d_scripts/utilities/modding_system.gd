extends Node

signal mod_loaded(mod_id, mod_data)
signal mod_unloaded(mod_id)
signal mod_enabled(mod_id)
signal mod_disabled(mod_id)
signal mod_error(mod_id, error)

var mods_directory = "user://mods/"
var loaded_mods = {}
var enabled_mods = []
var mod_load_order = []
var mod_conflicts = {}

var mod_config = {
	"api_version": "1.0",
	"max_mod_size": 100 * 1024 * 1024,
	"allowed_extensions": [".pck", ".zip"],
	"required_files": ["mod.json", "main.gd"]
}

func _ready():
	_create_mods_directory()
	_load_mod_configuration()
	_scan_for_mods()

func _create_mods_directory():
	var dir = Directory.new()
	if not dir.dir_exists(mods_directory):
		dir.make_dir_recursive(mods_directory)

func _scan_for_mods():
	var dir = Directory.new()
	if dir.open(mods_directory) != OK:
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if _is_valid_mod_file(file_name):
			_load_mod(file_name)
		file_name = dir.get_next()
	
	dir.list_dir_end()
	_resolve_dependencies()

func _is_valid_mod_file(file_name):
	for ext in mod_config.allowed_extensions:
		if file_name.ends_with(ext):
			return true
	return false

func _load_mod(file_name):
	var mod_path = mods_directory + file_name
	var mod_id = file_name.get_basename()
	
	var mod_data = _extract_mod_data(mod_path)
	if not mod_data:
		emit_signal("mod_error", mod_id, "Failed to extract mod data")
		return
	
	if not _validate_mod(mod_data):
		emit_signal("mod_error", mod_id, "Invalid mod structure")
		return
	
	loaded_mods[mod_id] = mod_data
	emit_signal("mod_loaded", mod_id, mod_data)

func _extract_mod_data(mod_path):
	var mod_data = {
		"path": mod_path,
		"info": {},
		"scripts": [],
		"resources": [],
		"dependencies": [],
		"conflicts": []
	}
	
	if mod_path.ends_with(".pck"):
		if not ProjectSettings.load_resource_pack(mod_path):
			return null
	
	var mod_info = _load_mod_info(mod_path)
	if not mod_info:
		return null
	
	mod_data.info = mod_info
	mod_data.dependencies = mod_info.get("dependencies", [])
	mod_data.conflicts = mod_info.get("conflicts", [])
	
	return mod_data

func _load_mod_info(mod_path):
	var file = File.new()
	var info_path = "res://mods/" + mod_path.get_basename() + "/mod.json"
	
	if not file.file_exists(info_path):
		return null
	
	if file.open(info_path, File.READ) != OK:
		return null
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_text)
	
	if parse_result != OK:
		return null
	
	return json.data

func _validate_mod(mod_data):
	var info = mod_data.info
	
	if not info.has("name") or not info.has("version") or not info.has("author"):
		return false
	
	if info.get("api_version", "") != mod_config.api_version:
		return false
	
	return true

func enable_mod(mod_id):
	if not loaded_mods.has(mod_id):
		return false
	
	if enabled_mods.has(mod_id):
		return true
	
	var mod_data = loaded_mods[mod_id]
	
	if not _check_dependencies(mod_id):
		emit_signal("mod_error", mod_id, "Missing dependencies")
		return false
	
	if not _check_conflicts(mod_id):
		emit_signal("mod_error", mod_id, "Conflicting mods enabled")
		return false
	
	if not _initialize_mod(mod_id):
		emit_signal("mod_error", mod_id, "Failed to initialize")
		return false
	
	enabled_mods.append(mod_id)
	emit_signal("mod_enabled", mod_id)
	
	_save_mod_configuration()
	return true

func disable_mod(mod_id):
	if not enabled_mods.has(mod_id):
		return false
	
	_cleanup_mod(mod_id)
	enabled_mods.erase(mod_id)
	
	emit_signal("mod_disabled", mod_id)
	
	_save_mod_configuration()
	return true

func _initialize_mod(mod_id):
	var mod_data = loaded_mods[mod_id]
	var main_script_path = "res://mods/" + mod_id + "/main.gd"
	
	if not ResourceLoader.exists(main_script_path):
		return false
	
	var main_script = load(main_script_path)
	if not main_script:
		return false
	
	var mod_instance = main_script.new()
	if not mod_instance.has_method("_mod_init"):
		return false
	
	mod_data["instance"] = mod_instance
	add_child(mod_instance)
	
	mod_instance._mod_init()
	
	return true

func _cleanup_mod(mod_id):
	var mod_data = loaded_mods[mod_id]
	
	if mod_data.has("instance"):
		var instance = mod_data.instance
		if instance.has_method("_mod_cleanup"):
			instance._mod_cleanup()
		
		instance.queue_free()
		mod_data.erase("instance")

func _check_dependencies(mod_id):
	var mod_data = loaded_mods[mod_id]
	
	for dep in mod_data.dependencies:
		var dep_id = dep.get("id", "")
		var dep_version = dep.get("version", "")
		
		if not loaded_mods.has(dep_id):
			return false
		
		if not enabled_mods.has(dep_id):
			enable_mod(dep_id)
	
	return true

func _check_conflicts(mod_id):
	var mod_data = loaded_mods[mod_id]
	
	for conflict in mod_data.conflicts:
		if enabled_mods.has(conflict):
			return false
	
	return true

func _resolve_dependencies():
	var resolved = []
	var unresolved = loaded_mods.keys()
	
	while unresolved.size() > 0:
		var progress = false
		
		for mod_id in unresolved:
			var can_resolve = true
			var mod_data = loaded_mods[mod_id]
			
			for dep in mod_data.dependencies:
				var dep_id = dep.get("id", "")
				if not resolved.has(dep_id) and loaded_mods.has(dep_id):
					can_resolve = false
					break
			
			if can_resolve:
				resolved.append(mod_id)
				unresolved.erase(mod_id)
				progress = true
		
		if not progress:
			break
	
	mod_load_order = resolved

func _save_mod_configuration():
	var config = {
		"enabled_mods": enabled_mods,
		"load_order": mod_load_order
	}
	
	var file = File.new()
	if file.open("user://mod_config.json", File.WRITE) == OK:
		file.store_string(JSON.print(config))
		file.close()

func _load_mod_configuration():
	var file = File.new()
	if not file.file_exists("user://mod_config.json"):
		return
	
	if file.open("user://mod_config.json", File.READ) != OK:
		return
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_text)
	
	if parse_result != OK:
		return
	
	var config = json.data
	enabled_mods = config.get("enabled_mods", [])
	mod_load_order = config.get("load_order", [])

func get_mod_info(mod_id):
	if not loaded_mods.has(mod_id):
		return null
	
	var mod_data = loaded_mods[mod_id]
	return {
		"id": mod_id,
		"name": mod_data.info.get("name", ""),
		"version": mod_data.info.get("version", ""),
		"author": mod_data.info.get("author", ""),
		"description": mod_data.info.get("description", ""),
		"enabled": enabled_mods.has(mod_id),
		"dependencies": mod_data.dependencies,
		"conflicts": mod_data.conflicts
	}

func get_loaded_mods():
	var mods = []
	for mod_id in loaded_mods:
		mods.append(get_mod_info(mod_id))
	return mods

func get_enabled_mods():
	return enabled_mods.duplicate()

func reload_mods():
	for mod_id in enabled_mods:
		disable_mod(mod_id)
	
	loaded_mods.clear()
	_scan_for_mods()
	
	for mod_id in enabled_mods:
		enable_mod(mod_id)

func get_mod_api():
	return {
		"version": mod_config.api_version,
		"register_hook": funcref(self, "register_mod_hook"),
		"call_hook": funcref(self, "call_mod_hook"),
		"get_game_data": funcref(self, "get_mod_game_data")
	}

func register_mod_hook(hook_name, callback):
	pass

func call_mod_hook(hook_name, args):
	pass

func get_mod_game_data():
	return {}