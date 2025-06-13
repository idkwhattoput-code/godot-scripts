extends Node

signal resource_collected(resource_type: String, amount: int)
signal inventory_full(resource_type: String)
signal collection_started(resource_node)
signal collection_completed(resource_node)
signal tool_equipped(tool_type: String)

export var enabled: bool = true
export var collection_range: float = 3.0
export var collection_time: float = 2.0
export var instant_collection: bool = false
export var requires_tool: bool = true
export var auto_collect_enabled: bool = false
export var auto_collect_range: float = 2.0
export var inventory_capacity: int = 100
export var stack_size: int = 64

var current_inventory: Dictionary = {}
var collecting_from: Node = null
var collection_progress: float = 0.0
var equipped_tool: String = ""
var nearby_resources: Array = []

var resource_types: Dictionary = {
	"wood": {
		"stack_size": 64,
		"weight": 1,
		"required_tool": "axe",
		"collection_time": 2.0,
		"exp_reward": 5
	},
	"stone": {
		"stack_size": 32,
		"weight": 2,
		"required_tool": "pickaxe",
		"collection_time": 3.0,
		"exp_reward": 10
	},
	"metal": {
		"stack_size": 16,
		"weight": 3,
		"required_tool": "pickaxe",
		"collection_time": 4.0,
		"exp_reward": 20
	},
	"crystal": {
		"stack_size": 8,
		"weight": 1,
		"required_tool": "special_pickaxe",
		"collection_time": 5.0,
		"exp_reward": 50
	},
	"plant": {
		"stack_size": 64,
		"weight": 0.5,
		"required_tool": "",
		"collection_time": 1.0,
		"exp_reward": 2
	}
}

var tool_efficiency: Dictionary = {
	"basic_axe": {"wood": 1.0, "durability": 100},
	"iron_axe": {"wood": 1.5, "durability": 200},
	"basic_pickaxe": {"stone": 1.0, "metal": 0.5, "durability": 150},
	"iron_pickaxe": {"stone": 1.5, "metal": 1.0, "durability": 300},
	"special_pickaxe": {"stone": 2.0, "metal": 1.5, "crystal": 1.0, "durability": 500}
}

var player: Spatial
var interaction_area: Area
var collection_ui: Control
var audio_player: AudioStreamPlayer3D

onready var collection_sounds: Dictionary = {}

func _ready():
	set_process(false)
	_initialize_inventory()

func initialize(player_node: Spatial):
	player = player_node
	
	_setup_interaction_area()
	_setup_audio()
	set_process(true)

func _process(delta):
	if not enabled:
		return
	
	if collecting_from:
		_update_collection(delta)
	
	if auto_collect_enabled:
		_check_auto_collect()

func _initialize_inventory():
	for resource_type in resource_types:
		current_inventory[resource_type] = 0

func _setup_interaction_area():
	interaction_area = Area.new()
	var shape = SphereShape.new()
	shape.radius = collection_range
	var collision = CollisionShape.new()
	collision.shape = shape
	interaction_area.add_child(collision)
	
	if player:
		player.add_child(interaction_area)
	
	interaction_area.connect("area_entered", self, "_on_resource_area_entered")
	interaction_area.connect("area_exited", self, "_on_resource_area_exited")

func _on_resource_area_entered(area):
	var resource_node = area.get_parent()
	if resource_node and resource_node.has_method("get_resource_type"):
		nearby_resources.append(resource_node)
		if resource_node.has_method("set_highlight"):
			resource_node.set_highlight(true)

func _on_resource_area_exited(area):
	var resource_node = area.get_parent()
	if resource_node in nearby_resources:
		nearby_resources.erase(resource_node)
		if resource_node.has_method("set_highlight"):
			resource_node.set_highlight(false)
		if resource_node == collecting_from:
			cancel_collection()

func start_collection(resource_node: Node = null):
	if collecting_from:
		return false
	
	if not resource_node:
		resource_node = _find_nearest_resource()
	
	if not resource_node or not _can_collect_from(resource_node):
		return false
	
	collecting_from = resource_node
	collection_progress = 0.0
	
	var resource_type = resource_node.get_resource_type()
	var collection_time_mod = _get_collection_time(resource_type)
	
	if instant_collection or collection_time_mod <= 0:
		_complete_collection()
	else:
		emit_signal("collection_started", resource_node)
		if player.has_method("play_animation"):
			player.play_animation("collecting")
	
	return true

func cancel_collection():
	if not collecting_from:
		return
	
	collection_progress = 0.0
	collecting_from = null
	
	if player.has_method("stop_animation"):
		player.stop_animation("collecting")

func _update_collection(delta):
	if not collecting_from:
		return
	
	var resource_type = collecting_from.get_resource_type()
	var collection_time_mod = _get_collection_time(resource_type)
	
	collection_progress += delta / collection_time_mod
	
	if collection_ui:
		_update_collection_ui(collection_progress)
	
	if collection_progress >= 1.0:
		_complete_collection()

func _complete_collection():
	if not collecting_from:
		return
	
	var resource_type = collecting_from.get_resource_type()
	var amount = collecting_from.harvest() if collecting_from.has_method("harvest") else 1
	
	if _add_to_inventory(resource_type, amount):
		emit_signal("resource_collected", resource_type, amount)
		emit_signal("collection_completed", collecting_from)
		_play_collection_sound(resource_type)
		
		if collecting_from.has_method("respawn"):
			collecting_from.respawn()
		elif collecting_from.has_method("queue_free"):
			nearby_resources.erase(collecting_from)
			collecting_from.queue_free()
	else:
		emit_signal("inventory_full", resource_type)
	
	collecting_from = null
	collection_progress = 0.0

func _can_collect_from(resource_node: Node) -> bool:
	if not resource_node.has_method("get_resource_type"):
		return false
	
	var resource_type = resource_node.get_resource_type()
	
	if not resource_type in resource_types:
		return false
	
	if requires_tool:
		var required_tool = resource_types[resource_type].get("required_tool", "")
		if required_tool != "" and not _has_required_tool(required_tool):
			return false
	
	if resource_node.has_method("can_harvest"):
		return resource_node.can_harvest()
	
	return true

func _has_required_tool(tool_type: String) -> bool:
	if equipped_tool == "":
		return false
	
	if tool_type == "axe":
		return equipped_tool.ends_with("_axe")
	elif tool_type == "pickaxe":
		return equipped_tool.ends_with("_pickaxe")
	elif tool_type == "special_pickaxe":
		return equipped_tool == "special_pickaxe"
	
	return equipped_tool == tool_type

func _get_collection_time(resource_type: String) -> float:
	var base_time = resource_types[resource_type].get("collection_time", collection_time)
	
	if equipped_tool in tool_efficiency:
		var efficiency = tool_efficiency[equipped_tool].get(resource_type, 1.0)
		return base_time / efficiency
	
	return base_time

func _add_to_inventory(resource_type: String, amount: int) -> bool:
	var current_amount = current_inventory.get(resource_type, 0)
	var max_stack = resource_types[resource_type].get("stack_size", stack_size)
	var total_stacks = _get_total_inventory_stacks()
	
	if total_stacks >= inventory_capacity:
		return false
	
	var new_amount = current_amount + amount
	var stacks_needed = ceil(float(new_amount) / float(max_stack))
	
	if total_stacks - ceil(float(current_amount) / float(max_stack)) + stacks_needed > inventory_capacity:
		return false
	
	current_inventory[resource_type] = new_amount
	return true

func _get_total_inventory_stacks() -> int:
	var total = 0
	for resource_type in current_inventory:
		var amount = current_inventory[resource_type]
		var max_stack = resource_types[resource_type].get("stack_size", stack_size)
		total += ceil(float(amount) / float(max_stack))
	return total

func _find_nearest_resource() -> Node:
	var nearest = null
	var nearest_distance = INF
	
	for resource in nearby_resources:
		if _can_collect_from(resource):
			var distance = player.global_transform.origin.distance_to(resource.global_transform.origin)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = resource
	
	return nearest

func _check_auto_collect():
	for resource in nearby_resources:
		var distance = player.global_transform.origin.distance_to(resource.global_transform.origin)
		if distance <= auto_collect_range and _can_collect_from(resource):
			if resource.has_method("is_auto_collectable") and resource.is_auto_collectable():
				var resource_type = resource.get_resource_type()
				var amount = resource.harvest() if resource.has_method("harvest") else 1
				
				if _add_to_inventory(resource_type, amount):
					emit_signal("resource_collected", resource_type, amount)
					_play_collection_sound(resource_type, 0.5)
					resource.queue_free()
					nearby_resources.erase(resource)

func equip_tool(tool_name: String):
	if tool_name in tool_efficiency:
		equipped_tool = tool_name
		emit_signal("tool_equipped", tool_name)
	else:
		equipped_tool = ""

func remove_from_inventory(resource_type: String, amount: int) -> bool:
	if not resource_type in current_inventory:
		return false
	
	if current_inventory[resource_type] < amount:
		return false
	
	current_inventory[resource_type] -= amount
	return true

func get_resource_amount(resource_type: String) -> int:
	return current_inventory.get(resource_type, 0)

func get_inventory() -> Dictionary:
	return current_inventory.duplicate()

func get_inventory_weight() -> float:
	var total_weight = 0.0
	for resource_type in current_inventory:
		var amount = current_inventory[resource_type]
		var weight = resource_types[resource_type].get("weight", 1.0)
		total_weight += amount * weight
	return total_weight

func _setup_audio():
	if not audio_player:
		audio_player = AudioStreamPlayer3D.new()
		if player:
			player.add_child(audio_player)

func _play_collection_sound(resource_type: String, volume_scale: float = 1.0):
	if not audio_player:
		return
	
	if resource_type in collection_sounds and collection_sounds[resource_type]:
		audio_player.stream = collection_sounds[resource_type]
		audio_player.volume_db = linear2db(volume_scale)
		audio_player.play()

func _update_collection_ui(progress: float):
	if not collection_ui:
		return
	
	var progress_bar = collection_ui.get_node_or_null("ProgressBar")
	if progress_bar:
		progress_bar.value = progress * 100

func set_collection_enabled(enabled_state: bool):
	enabled = enabled_state
	if not enabled:
		cancel_collection()

func add_resource_type(name: String, properties: Dictionary):
	resource_types[name] = properties
	current_inventory[name] = 0

func set_auto_collect(enabled_state: bool):
	auto_collect_enabled = enabled_state