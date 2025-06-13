extends Node

export var enable_auto_expand = true
export var max_pool_size = 1000
export var preload_count = 10

var pools = {}
var pool_stats = {}

signal pool_expanded(pool_name, new_size)
signal object_borrowed(pool_name)
signal object_returned(pool_name)

func _ready():
	set_process(false)

func create_pool(pool_name: String, scene_path: String, initial_size: int = 10):
	if pools.has(pool_name):
		push_warning("Pool already exists: " + pool_name)
		return
	
	var pool_data = {
		"scene": load(scene_path),
		"available": [],
		"in_use": [],
		"total_created": 0,
		"high_water_mark": 0
	}
	
	pools[pool_name] = pool_data
	pool_stats[pool_name] = {
		"borrows": 0,
		"returns": 0,
		"expansions": 0
	}
	
	for i in range(initial_size):
		_create_pool_object(pool_name)
	
	print("Created pool '" + pool_name + "' with " + str(initial_size) + " objects")

func borrow(pool_name: String) -> Node:
	if not pools.has(pool_name):
		push_error("Pool not found: " + pool_name)
		return null
	
	var pool = pools[pool_name]
	
	if pool.available.empty():
		if enable_auto_expand and pool.total_created < max_pool_size:
			_expand_pool(pool_name)
		else:
			push_warning("Pool exhausted: " + pool_name)
			return null
	
	var obj = pool.available.pop_back()
	pool.in_use.append(obj)
	
	pool_stats[pool_name].borrows += 1
	pool.high_water_mark = max(pool.high_water_mark, pool.in_use.size())
	
	_activate_object(obj)
	emit_signal("object_borrowed", pool_name)
	
	return obj

func return_object(obj: Node, pool_name: String):
	if not pools.has(pool_name):
		push_error("Pool not found: " + pool_name)
		obj.queue_free()
		return
	
	var pool = pools[pool_name]
	
	if not obj in pool.in_use:
		push_warning("Object not from this pool: " + pool_name)
		return
	
	pool.in_use.erase(obj)
	pool.available.append(obj)
	
	pool_stats[pool_name].returns += 1
	
	_deactivate_object(obj)
	emit_signal("object_returned", pool_name)

func return_all(pool_name: String):
	if not pools.has(pool_name):
		push_error("Pool not found: " + pool_name)
		return
	
	var pool = pools[pool_name]
	
	while not pool.in_use.empty():
		var obj = pool.in_use.pop_back()
		pool.available.append(obj)
		_deactivate_object(obj)
		pool_stats[pool_name].returns += 1

func clear_pool(pool_name: String):
	if not pools.has(pool_name):
		push_error("Pool not found: " + pool_name)
		return
	
	var pool = pools[pool_name]
	
	for obj in pool.available:
		obj.queue_free()
	
	for obj in pool.in_use:
		obj.queue_free()
	
	pool.available.clear()
	pool.in_use.clear()
	pool.total_created = 0

func delete_pool(pool_name: String):
	clear_pool(pool_name)
	pools.erase(pool_name)
	pool_stats.erase(pool_name)

func get_pool_info(pool_name: String) -> Dictionary:
	if not pools.has(pool_name):
		return {}
	
	var pool = pools[pool_name]
	var stats = pool_stats[pool_name]
	
	return {
		"available": pool.available.size(),
		"in_use": pool.in_use.size(),
		"total_created": pool.total_created,
		"high_water_mark": pool.high_water_mark,
		"borrows": stats.borrows,
		"returns": stats.returns,
		"expansions": stats.expansions
	}

func get_all_pool_info() -> Dictionary:
	var info = {}
	for pool_name in pools:
		info[pool_name] = get_pool_info(pool_name)
	return info

func preload_objects(pool_name: String, count: int):
	if not pools.has(pool_name):
		push_error("Pool not found: " + pool_name)
		return
	
	var pool = pools[pool_name]
	var to_create = min(count, max_pool_size - pool.total_created)
	
	for i in range(to_create):
		_create_pool_object(pool_name)

func set_pool_parent(pool_name: String, parent: Node):
	if not pools.has(pool_name):
		push_error("Pool not found: " + pool_name)
		return
	
	var pool = pools[pool_name]
	
	for obj in pool.available:
		if obj.get_parent():
			obj.get_parent().remove_child(obj)
		parent.add_child(obj)
	
	for obj in pool.in_use:
		if obj.get_parent():
			obj.get_parent().remove_child(obj)
		parent.add_child(obj)

func _create_pool_object(pool_name: String) -> Node:
	var pool = pools[pool_name]
	var obj = pool.scene.instance()
	
	add_child(obj)
	_deactivate_object(obj)
	
	pool.available.append(obj)
	pool.total_created += 1
	
	if obj.has_method("_on_pool_created"):
		obj._on_pool_created()
	
	return obj

func _expand_pool(pool_name: String, expansion_size: int = 10):
	var pool = pools[pool_name]
	var to_create = min(expansion_size, max_pool_size - pool.total_created)
	
	for i in range(to_create):
		_create_pool_object(pool_name)
	
	pool_stats[pool_name].expansions += 1
	emit_signal("pool_expanded", pool_name, pool.total_created)
	
	print("Expanded pool '" + pool_name + "' by " + str(to_create) + " objects")

func _activate_object(obj: Node):
	obj.set_physics_process(true)
	obj.set_process(true)
	obj.show()
	
	if obj.has_method("_on_pool_activate"):
		obj._on_pool_activate()

func _deactivate_object(obj: Node):
	obj.set_physics_process(false)
	obj.set_process(false)
	obj.hide()
	
	if obj is RigidBody:
		obj.sleeping = true
		obj.linear_velocity = Vector3.ZERO
		obj.angular_velocity = Vector3.ZERO
	elif obj is KinematicBody:
		obj.global_transform.origin = Vector3(0, -1000, 0)
	
	if obj.has_method("_on_pool_deactivate"):
		obj._on_pool_deactivate()

func optimize_pools():
	for pool_name in pools:
		var pool = pools[pool_name]
		var excess = pool.available.size() - preload_count
		
		if excess > 10:
			for i in range(excess / 2):
				var obj = pool.available.pop_back()
				obj.queue_free()
				pool.total_created -= 1
			
			print("Optimized pool '" + pool_name + "': removed " + str(excess / 2) + " excess objects")

func save_pool_stats() -> Dictionary:
	var stats = {}
	for pool_name in pool_stats:
		stats[pool_name] = pool_stats[pool_name].duplicate()
	return stats

func reset_pool_stats():
	for pool_name in pool_stats:
		pool_stats[pool_name] = {
			"borrows": 0,
			"returns": 0,
			"expansions": 0
		}

class PooledObject extends Node:
	var pool_name = ""
	var pool_manager = null
	
	func return_to_pool():
		if pool_manager and pool_name != "":
			pool_manager.return_object(self, pool_name)