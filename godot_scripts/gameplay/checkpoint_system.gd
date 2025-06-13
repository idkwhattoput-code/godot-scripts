extends Node

class_name CheckpointSystem

signal checkpoint_activated(checkpoint_id)
signal checkpoint_respawned(checkpoint_id)
signal all_checkpoints_collected()

export var respawn_delay: float = 1.0
export var save_on_checkpoint: bool = true
export var show_checkpoint_ui: bool = true
export var checkpoint_sound: AudioStream
export var respawn_sound: AudioStream

var checkpoints: Dictionary = {}
var active_checkpoint: String = ""
var last_checkpoint_data: Dictionary = {}
var checkpoint_order: Array = []
var collected_checkpoints: Array = []
var player_reference: Spatial = null
var is_respawning: bool = false

onready var audio_player = AudioStreamPlayer.new()

func _ready():
	add_child(audio_player)
	audio_player.bus = "SFX"
	
	call_deferred("find_all_checkpoints")

func find_all_checkpoints():
	checkpoints.clear()
	checkpoint_order.clear()
	
	var all_checkpoints = get_tree().get_nodes_in_group("checkpoints")
	
	for checkpoint in all_checkpoints:
		if checkpoint.has_method("get_checkpoint_id"):
			var id = checkpoint.get_checkpoint_id()
			checkpoints[id] = {
				"node": checkpoint,
				"transform": checkpoint.global_transform,
				"collected": false,
				"order": checkpoint_order.size()
			}
			checkpoint_order.append(id)
			
			if checkpoint.has_signal("body_entered"):
				checkpoint.connect("body_entered", self, "_on_checkpoint_entered", [id])

func register_checkpoint(checkpoint_node: Spatial, checkpoint_id: String):
	checkpoints[checkpoint_id] = {
		"node": checkpoint_node,
		"transform": checkpoint_node.global_transform,
		"collected": false,
		"order": checkpoint_order.size()
	}
	checkpoint_order.append(checkpoint_id)
	
	if checkpoint_node.has_signal("body_entered"):
		checkpoint_node.connect("body_entered", self, "_on_checkpoint_entered", [checkpoint_id])

func _on_checkpoint_entered(body: Spatial, checkpoint_id: String):
	if body == player_reference or (body.has_method("is_player") and body.is_player()):
		activate_checkpoint(checkpoint_id)

func activate_checkpoint(checkpoint_id: String):
	if not checkpoint_id in checkpoints:
		push_error("Invalid checkpoint ID: " + checkpoint_id)
		return
	
	if checkpoints[checkpoint_id].collected and active_checkpoint == checkpoint_id:
		return
	
	var previous_checkpoint = active_checkpoint
	active_checkpoint = checkpoint_id
	checkpoints[checkpoint_id].collected = true
	
	if not checkpoint_id in collected_checkpoints:
		collected_checkpoints.append(checkpoint_id)
	
	save_checkpoint_data()
	
	if checkpoint_sound:
		audio_player.stream = checkpoint_sound
		audio_player.play()
	
	emit_signal("checkpoint_activated", checkpoint_id)
	
	if show_checkpoint_ui:
		show_checkpoint_notification(checkpoint_id)
	
	if save_on_checkpoint:
		save_game_at_checkpoint()
	
	update_checkpoint_visuals(checkpoint_id, previous_checkpoint)
	
	if collected_checkpoints.size() == checkpoints.size():
		emit_signal("all_checkpoints_collected")

func save_checkpoint_data():
	if not player_reference:
		return
	
	last_checkpoint_data = {
		"checkpoint_id": active_checkpoint,
		"player_transform": player_reference.global_transform,
		"player_health": get_player_health(),
		"player_inventory": get_player_inventory(),
		"timestamp": OS.get_unix_time(),
		"collected_checkpoints": collected_checkpoints.duplicate()
	}

func get_player_health() -> float:
	if player_reference and player_reference.has_method("get_health"):
		return player_reference.get_health()
	elif player_reference and player_reference.has_node("CharacterStats"):
		var stats = player_reference.get_node("CharacterStats")
		return stats.current_health if stats else 100.0
	return 100.0

func get_player_inventory() -> Dictionary:
	if player_reference and player_reference.has_method("get_inventory"):
		return player_reference.get_inventory()
	return {}

func respawn_at_checkpoint(checkpoint_id: String = ""):
	if is_respawning:
		return
	
	is_respawning = true
	
	var target_checkpoint = checkpoint_id if checkpoint_id != "" else active_checkpoint
	
	if not target_checkpoint or not target_checkpoint in checkpoints:
		push_error("No valid checkpoint to respawn at")
		is_respawning = false
		return
	
	if player_reference:
		start_respawn_sequence(target_checkpoint)

func start_respawn_sequence(checkpoint_id: String):
	if player_reference.has_method("disable_input"):
		player_reference.disable_input()
	
	var fade_overlay = create_fade_overlay()
	get_tree().get_root().add_child(fade_overlay)
	
	var tween = create_tween()
	tween.tween_property(fade_overlay, "modulate:a", 1.0, 0.5)
	tween.tween_callback(self, "perform_respawn", [checkpoint_id, fade_overlay])

func create_fade_overlay() -> ColorRect:
	var overlay = ColorRect.new()
	overlay.color = Color.black
	overlay.modulate.a = 0.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_margins_preset(Control.PRESET_FULL_RECT)
	return overlay

func perform_respawn(checkpoint_id: String, fade_overlay: ColorRect):
	yield(get_tree().create_timer(respawn_delay), "timeout")
	
	var checkpoint_data = checkpoints[checkpoint_id]
	player_reference.global_transform = checkpoint_data.transform
	
	if player_reference.has_method("reset_velocity"):
		player_reference.reset_velocity()
	
	if last_checkpoint_data.has("player_health"):
		restore_player_health(last_checkpoint_data.player_health)
	
	if respawn_sound:
		audio_player.stream = respawn_sound
		audio_player.play()
	
	emit_signal("checkpoint_respawned", checkpoint_id)
	
	var tween = create_tween()
	tween.tween_property(fade_overlay, "modulate:a", 0.0, 0.5)
	tween.tween_callback(self, "finish_respawn", [fade_overlay])

func finish_respawn(fade_overlay: ColorRect):
	fade_overlay.queue_free()
	
	if player_reference and player_reference.has_method("enable_input"):
		player_reference.enable_input()
	
	is_respawning = false

func restore_player_health(health: float):
	if player_reference and player_reference.has_method("set_health"):
		player_reference.set_health(health)
	elif player_reference and player_reference.has_node("CharacterStats"):
		var stats = player_reference.get_node("CharacterStats")
		if stats:
			stats.current_health = health

func show_checkpoint_notification(checkpoint_id: String):
	var notification = preload("res://ui/CheckpointNotification.tscn").instance()
	notification.set_checkpoint_name(get_checkpoint_name(checkpoint_id))
	get_tree().get_root().add_child(notification)

func get_checkpoint_name(checkpoint_id: String) -> String:
	if checkpoint_id in checkpoints:
		var node = checkpoints[checkpoint_id].node
		if node.has_method("get_checkpoint_name"):
			return node.get_checkpoint_name()
	return "Checkpoint " + str(checkpoints[checkpoint_id].order + 1)

func update_checkpoint_visuals(new_checkpoint: String, old_checkpoint: String):
	if old_checkpoint and old_checkpoint in checkpoints:
		var old_node = checkpoints[old_checkpoint].node
		if old_node.has_method("set_inactive"):
			old_node.set_inactive()
	
	if new_checkpoint in checkpoints:
		var new_node = checkpoints[new_checkpoint].node
		if new_node.has_method("set_active"):
			new_node.set_active()

func save_game_at_checkpoint():
	var save_data = {
		"checkpoint_system": {
			"active_checkpoint": active_checkpoint,
			"collected_checkpoints": collected_checkpoints,
			"last_checkpoint_data": last_checkpoint_data
		}
	}
	
	if has_node("/root/SaveSystem"):
		get_node("/root/SaveSystem").save_game(save_data)

func load_checkpoint_save(save_data: Dictionary):
	if not save_data.has("checkpoint_system"):
		return
	
	var data = save_data.checkpoint_system
	active_checkpoint = data.get("active_checkpoint", "")
	collected_checkpoints = data.get("collected_checkpoints", [])
	last_checkpoint_data = data.get("last_checkpoint_data", {})
	
	for checkpoint_id in collected_checkpoints:
		if checkpoint_id in checkpoints:
			checkpoints[checkpoint_id].collected = true
	
	if active_checkpoint:
		update_checkpoint_visuals(active_checkpoint, "")

func get_next_checkpoint() -> String:
	var current_order = -1
	if active_checkpoint in checkpoints:
		current_order = checkpoints[active_checkpoint].order
	
	for checkpoint_id in checkpoint_order:
		if checkpoints[checkpoint_id].order > current_order:
			return checkpoint_id
	
	return ""

func get_checkpoint_progress() -> Dictionary:
	return {
		"total": checkpoints.size(),
		"collected": collected_checkpoints.size(),
		"percentage": float(collected_checkpoints.size()) / float(max(checkpoints.size(), 1)) * 100.0
	}

func reset_checkpoints():
	active_checkpoint = ""
	collected_checkpoints.clear()
	last_checkpoint_data.clear()
	
	for checkpoint_id in checkpoints:
		checkpoints[checkpoint_id].collected = false
		var node = checkpoints[checkpoint_id].node
		if node.has_method("reset"):
			node.reset()

func set_player_reference(player: Spatial):
	player_reference = player
	
	if player.has_signal("died"):
		player.connect("died", self, "respawn_at_checkpoint", [""])

func get_checkpoint_position(checkpoint_id: String) -> Vector3:
	if checkpoint_id in checkpoints:
		return checkpoints[checkpoint_id].transform.origin
	return Vector3.ZERO

func get_nearest_checkpoint(position: Vector3) -> String:
	var nearest_id = ""
	var nearest_distance = INF
	
	for checkpoint_id in checkpoints:
		var checkpoint_pos = checkpoints[checkpoint_id].transform.origin
		var distance = position.distance_to(checkpoint_pos)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = checkpoint_id
	
	return nearest_id

func debug_teleport_to_checkpoint(checkpoint_id: String):
	if player_reference and checkpoint_id in checkpoints:
		player_reference.global_transform = checkpoints[checkpoint_id].transform
		print("Teleported to checkpoint: " + checkpoint_id)