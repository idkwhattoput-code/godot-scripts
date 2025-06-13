extends Node

signal score_changed(new_score: int)
signal game_over()
signal level_completed()
signal game_paused(is_paused: bool)

@export var starting_lives: int = 3
@export var max_score: int = 999999
@export var checkpoint_save_enabled: bool = true

var current_score: int = 0
var player_lives: int
var current_level: int = 1
var is_paused: bool = false
var game_time: float = 0.0
var high_score: int = 0
var collected_items: Dictionary = {}
var checkpoints: Dictionary = {}
var player_stats: Dictionary = {
	"coins": 0,
	"gems": 0,
	"keys": 0,
	"power_ups": []
}

const SAVE_PATH = "user://savegame.save"
const SETTINGS_PATH = "user://settings.cfg"

@onready var ui_manager: Node = $UIManager
@onready var sound_manager: Node = $SoundManager
@onready var level_timer: Timer = $LevelTimer

func _ready():
	player_lives = starting_lives
	load_settings()
	load_high_score()
	
	if level_timer:
		level_timer.timeout.connect(_on_level_timeout)

func _process(delta):
	if not is_paused:
		game_time += delta

func _input(event):
	if event.is_action_pressed("pause"):
		toggle_pause()
	
	if event.is_action_pressed("restart") and is_game_over():
		restart_game()

func add_score(points: int):
	current_score = min(current_score + points, max_score)
	emit_signal("score_changed", current_score)
	
	if current_score > high_score:
		high_score = current_score
		save_high_score()

func add_life():
	player_lives += 1
	update_ui()

func lose_life():
	player_lives -= 1
	update_ui()
	
	if player_lives <= 0:
		trigger_game_over()
	else:
		respawn_player()

func collect_item(item_type: String, value: int = 1):
	if not collected_items.has(item_type):
		collected_items[item_type] = 0
	
	collected_items[item_type] += value
	
	match item_type:
		"coin":
			player_stats["coins"] += value
			add_score(10 * value)
		"gem":
			player_stats["gems"] += value
			add_score(50 * value)
		"key":
			player_stats["keys"] += value
		"health":
			add_life()
		_:
			if item_type.ends_with("_powerup"):
				player_stats["power_ups"].append(item_type)

func save_checkpoint(checkpoint_name: String):
	if not checkpoint_save_enabled:
		return
	
	var checkpoint_data = {
		"position": get_player_position(),
		"score": current_score,
		"lives": player_lives,
		"time": game_time,
		"items": collected_items.duplicate(),
		"stats": player_stats.duplicate()
	}
	
	checkpoints[checkpoint_name] = checkpoint_data
	save_game()

func load_checkpoint(checkpoint_name: String):
	if not checkpoints.has(checkpoint_name):
		return false
	
	var data = checkpoints[checkpoint_name]
	current_score = data["score"]
	player_lives = data["lives"]
	game_time = data["time"]
	collected_items = data["items"].duplicate()
	player_stats = data["stats"].duplicate()
	
	emit_signal("score_changed", current_score)
	update_ui()
	
	return true

func complete_level():
	emit_signal("level_completed")
	save_game()
	
	await get_tree().create_timer(2.0).timeout
	next_level()

func next_level():
	current_level += 1
	var next_scene = "res://levels/level_" + str(current_level) + ".tscn"
	
	if ResourceLoader.exists(next_scene):
		get_tree().change_scene_to_file(next_scene)
	else:
		show_victory_screen()

func trigger_game_over():
	emit_signal("game_over")
	is_paused = true
	
	if ui_manager and ui_manager.has_method("show_game_over"):
		ui_manager.show_game_over()

func restart_game():
	current_score = 0
	player_lives = starting_lives
	game_time = 0.0
	collected_items.clear()
	checkpoints.clear()
	player_stats = {
		"coins": 0,
		"gems": 0,
		"keys": 0,
		"power_ups": []
	}
	
	is_paused = false
	get_tree().reload_current_scene()

func toggle_pause():
	is_paused = not is_paused
	get_tree().paused = is_paused
	emit_signal("game_paused", is_paused)

func save_game():
	var save_file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not save_file:
		return
	
	var save_data = {
		"level": current_level,
		"score": current_score,
		"lives": player_lives,
		"time": game_time,
		"checkpoints": checkpoints,
		"items": collected_items,
		"stats": player_stats
	}
	
	save_file.store_var(save_data)
	save_file.close()

func load_game():
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	
	var save_file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not save_file:
		return false
	
	var save_data = save_file.get_var()
	save_file.close()
	
	current_level = save_data.get("level", 1)
	current_score = save_data.get("score", 0)
	player_lives = save_data.get("lives", starting_lives)
	game_time = save_data.get("time", 0.0)
	checkpoints = save_data.get("checkpoints", {})
	collected_items = save_data.get("items", {})
	player_stats = save_data.get("stats", player_stats)
	
	return true

func save_settings():
	var config = ConfigFile.new()
	config.set_value("audio", "master_volume", AudioServer.get_bus_volume_db(0))
	config.set_value("audio", "sfx_volume", AudioServer.get_bus_volume_db(1))
	config.set_value("audio", "music_volume", AudioServer.get_bus_volume_db(2))
	config.set_value("game", "checkpoint_save", checkpoint_save_enabled)
	config.save(SETTINGS_PATH)

func load_settings():
	var config = ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	
	AudioServer.set_bus_volume_db(0, config.get_value("audio", "master_volume", 0))
	AudioServer.set_bus_volume_db(1, config.get_value("audio", "sfx_volume", 0))
	AudioServer.set_bus_volume_db(2, config.get_value("audio", "music_volume", 0))
	checkpoint_save_enabled = config.get_value("game", "checkpoint_save", true)

func save_high_score():
	var config = ConfigFile.new()
	config.set_value("scores", "high_score", high_score)
	config.save(SETTINGS_PATH)

func load_high_score():
	var config = ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		high_score = config.get_value("scores", "high_score", 0)

func get_player_position() -> Vector2:
	var player = get_tree().get_first_node_in_group("player")
	if player:
		return player.global_position
	return Vector2.ZERO

func respawn_player():
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("respawn"):
		player.respawn()

func update_ui():
	if ui_manager and ui_manager.has_method("update_display"):
		ui_manager.update_display(current_score, player_lives, game_time)

func show_victory_screen():
	if ui_manager and ui_manager.has_method("show_victory"):
		ui_manager.show_victory()

func is_game_over() -> bool:
	return player_lives <= 0

func _on_level_timeout():
	trigger_game_over()