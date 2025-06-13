extends Node

export var preload_on_ready = true
export var use_thread_loading = true
export var max_cache_size_mb = 100.0

signal resource_loaded(path, resource)
signal resource_load_failed(path, error)
signal loading_progress(path, progress)
signal cache_cleared()

var resource_cache = {}
var loading_queue = []
var loading_threads = {}
var cache_size = 0.0
var load_callbacks = {}

func _ready():
	if preload_on_ready:
		_preload_common_resources()

func load_resource(path, callback = null, use_cache = true):
	if use_cache and path in resource_cache:
		if callback:
			callback.call_func(resource_cache[path])
		emit_signal("resource_loaded", path, resource_cache[path])
		return resource_cache[path]
	
	if path in loading_threads:
		if callback:
			if not path in load_callbacks:
				load_callbacks[path] = []
			load_callbacks[path].append(callback)
		return null
	
	if use_thread_loading and OS.can_use_threads():
		_load_threaded(path, callback, use_cache)
	else:
		_load_immediate(path, callback, use_cache)
	
	return null

func _load_immediate(path, callback, use_cache):
	var resource = load(path)
	
	if resource:
		if use_cache:
			_cache_resource(path, resource)
		
		if callback:
			callback.call_func(resource)
		
		emit_signal("resource_loaded", path, resource)
		
		_process_callbacks(path, resource)
	else:
		emit_signal("resource_load_failed", path, "Failed to load resource")
		_process_callbacks(path, null)

func _load_threaded(path, callback, use_cache):
	var thread = Thread.new()
	loading_threads[path] = {
		"thread": thread,
		"use_cache": use_cache
	}
	
	if callback:
		if not path in load_callbacks:
			load_callbacks[path] = []
		load_callbacks[path].append(callback)
	
	thread.start(self, "_thread_load", path)

func _thread_load(path):
	var resource = load(path)
	call_deferred("_on_thread_loaded", path, resource)
	return resource

func _on_thread_loaded(path, resource):
	if path in loading_threads:
		var thread_data = loading_threads[path]
		thread_data.thread.wait_to_finish()
		
		if resource and thread_data.use_cache:
			_cache_resource(path, resource)
		
		loading_threads.erase(path)
		
		if resource:
			emit_signal("resource_loaded", path, resource)
		else:
			emit_signal("resource_load_failed", path, "Failed to load resource")
		
		_process_callbacks(path, resource)

func _process_callbacks(path, resource):
	if path in load_callbacks:
		for callback in load_callbacks[path]:
			if callback:
				callback.call_func(resource)
		load_callbacks.erase(path)

func _cache_resource(path, resource):
	resource_cache[path] = resource
	
	var size_mb = _estimate_resource_size(resource)
	cache_size += size_mb
	
	if cache_size > max_cache_size_mb:
		_cleanup_cache()

func _estimate_resource_size(resource):
	if resource is Texture:
		var image = resource.get_data()
		if image:
			return (image.get_width() * image.get_height() * 4) / 1048576.0
	elif resource is Mesh:
		return 1.0
	elif resource is AudioStream:
		return 2.0
	else:
		return 0.1

func _cleanup_cache():
	var entries = []
	for path in resource_cache:
		entries.append(path)
	
	entries.sort()
	
	while cache_size > max_cache_size_mb * 0.8 and entries.size() > 0:
		var path = entries.pop_front()
		remove_from_cache(path)

func preload_resources(paths, callback = null):
	var loaded_count = 0
	var total_count = paths.size()
	
	for path in paths:
		load_resource(path, funcref(self, "_on_batch_resource_loaded"), true)

func _on_batch_resource_loaded(resource):
	pass

func remove_from_cache(path):
	if path in resource_cache:
		var resource = resource_cache[path]
		var size_mb = _estimate_resource_size(resource)
		cache_size -= size_mb
		resource_cache.erase(path)

func clear_cache():
	resource_cache.clear()
	cache_size = 0.0
	emit_signal("cache_cleared")

func is_loading(path):
	return path in loading_threads

func is_cached(path):
	return path in resource_cache

func get_cache_size():
	return cache_size

func get_cached_resource_count():
	return resource_cache.size()

func get_loading_count():
	return loading_threads.size()

func cancel_loading(path):
	if path in loading_threads:
		loading_threads.erase(path)
		load_callbacks.erase(path)

func _preload_common_resources():
	pass

func save_resource(resource, path):
	var error = ResourceSaver.save(path, resource)
	if error == OK:
		_cache_resource(path, resource)
		return true
	else:
		push_error("Failed to save resource: " + path)
		return false

func exists(path):
	return File.new().file_exists(path)

func get_resource_type(path):
	if path in resource_cache:
		return resource_cache[path].get_class()
	
	var ext = path.get_extension().to_lower()
	match ext:
		"png", "jpg", "jpeg", "bmp", "svg", "tga":
			return "Texture"
		"ogg", "wav", "mp3":
			return "AudioStream"
		"obj", "dae", "gltf", "glb":
			return "Mesh"
		"tscn", "scn":
			return "PackedScene"
		"tres", "res":
			return "Resource"
		_:
			return "Unknown"

func _exit_tree():
	for path in loading_threads:
		loading_threads[path].thread.wait_to_finish()
	loading_threads.clear()