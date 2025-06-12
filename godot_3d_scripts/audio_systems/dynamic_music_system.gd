extends Node

# Music layers and states
export var enable_dynamic_music = true
export var crossfade_time = 2.0
export var beat_sync = true
export var bpm = 120.0

# Music states
enum MusicState {
	MENU,
	EXPLORATION,
	COMBAT_LOW,
	COMBAT_HIGH,
	STEALTH,
	BOSS,
	VICTORY,
	DEFEAT
}

# Current state
var current_state = MusicState.EXPLORATION
var target_state = MusicState.EXPLORATION
var is_transitioning = false

# Music tracks and layers
var music_tracks = {}
var music_layers = {}
var active_layers = []

# Timing
var beat_time = 0.0
var measure_time = 0.0
var beats_per_measure = 4
var current_beat = 0
var current_measure = 0

# Intensity system
var combat_intensity = 0.0
var intensity_decay_rate = 0.1
var intensity_increase_rate = 0.3

# Stinger system
var stingers = {}
var queued_stingers = []

# Audio players
var layer_players = {}
var stinger_player = null

# Sync groups
var sync_groups = {}

signal beat(beat_number)
signal measure(measure_number)
signal state_changed(new_state)
signal layer_activated(layer_name)
signal layer_deactivated(layer_name)
signal stinger_played(stinger_name)

func _ready():
	_setup_music_system()
	_load_music_tracks()
	set_process(true)

func _setup_music_system():
	# Create stinger player
	stinger_player = AudioStreamPlayer.new()
	stinger_player.bus = "Music"
	add_child(stinger_player)
	
	# Calculate beat time
	beat_time = 60.0 / bpm

func _load_music_tracks():
	# Define music structure
	music_tracks = {
		MusicState.EXPLORATION: {
			"base": preload("res://audio/music/exploration_base.ogg"),
			"layers": {
				"melody": preload("res://audio/music/exploration_melody.ogg"),
				"percussion": preload("res://audio/music/exploration_percussion.ogg"),
				"ambient": preload("res://audio/music/exploration_ambient.ogg")
			}
		},
		MusicState.COMBAT_LOW: {
			"base": preload("res://audio/music/combat_low_base.ogg"),
			"layers": {
				"drums": preload("res://audio/music/combat_low_drums.ogg"),
				"strings": preload("res://audio/music/combat_low_strings.ogg"),
				"brass": preload("res://audio/music/combat_low_brass.ogg")
			}
		},
		MusicState.COMBAT_HIGH: {
			"base": preload("res://audio/music/combat_high_base.ogg"),
			"layers": {
				"drums": preload("res://audio/music/combat_high_drums.ogg"),
				"orchestra": preload("res://audio/music/combat_high_orchestra.ogg"),
				"choir": preload("res://audio/music/combat_high_choir.ogg"),
				"percussion": preload("res://audio/music/combat_high_percussion.ogg")
			}
		}
	}
	
	# Load stingers
	stingers = {
		"victory": preload("res://audio/music/stinger_victory.ogg"),
		"defeat": preload("res://audio/music/stinger_defeat.ogg"),
		"discovery": preload("res://audio/music/stinger_discovery.ogg"),
		"danger": preload("res://audio/music/stinger_danger.ogg")
	}
	
	# Create layer players
	_create_layer_players()

func _create_layer_players():
	for state in music_tracks:
		var state_data = music_tracks[state]
		
		# Create base player
		var base_player = AudioStreamPlayer.new()
		base_player.bus = "Music"
		base_player.stream = state_data.base
		add_child(base_player)
		
		var state_name = _get_state_name(state)
		layer_players[state_name + "_base"] = base_player
		
		# Create layer players
		if state_data.has("layers"):
			for layer_name in state_data.layers:
				var layer_player = AudioStreamPlayer.new()
				layer_player.bus = "Music"
				layer_player.stream = state_data.layers[layer_name]
				add_child(layer_player)
				
				layer_players[state_name + "_" + layer_name] = layer_player

func _process(delta):
	if not enable_dynamic_music:
		return
	
	_update_timing(delta)
	_update_intensity(delta)
	_update_transitions(delta)
	_process_stinger_queue()

func _update_timing(delta):
	if not beat_sync:
		return
	
	measure_time += delta
	
	if measure_time >= beat_time:
		measure_time -= beat_time
		current_beat = (current_beat + 1) % beats_per_measure
		
		emit_signal("beat", current_beat)
		
		if current_beat == 0:
			current_measure += 1
			emit_signal("measure", current_measure)
			
			# Check for transitions on measure boundaries
			if target_state != current_state and not is_transitioning:
				_start_transition()

func _update_intensity(delta):
	# Decay intensity over time
	if combat_intensity > 0:
		combat_intensity = max(0, combat_intensity - intensity_decay_rate * delta)
		
		# Update combat music layers based on intensity
		if current_state == MusicState.COMBAT_LOW or current_state == MusicState.COMBAT_HIGH:
			_update_combat_layers()

func _update_transitions(delta):
	if not is_transitioning:
		return
	
	# Handle crossfading logic here

func set_music_state(new_state: int, immediate: bool = false):
	if new_state == current_state:
		return
	
	target_state = new_state
	
	if immediate or not beat_sync:
		_start_transition()
	# Otherwise wait for next measure

func _start_transition():
	is_transitioning = true
	var old_state = current_state
	current_state = target_state
	
	emit_signal("state_changed", current_state)
	
	# Stop old state music
	_stop_state_music(old_state)
	
	# Start new state music
	_start_state_music(current_state)
	
	is_transitioning = false

func _start_state_music(state: int):
	var state_name = _get_state_name(state)
	var base_player = layer_players.get(state_name + "_base")
	
	if base_player:
		base_player.play()
		base_player.volume_db = -80
		_fade_in_player(base_player)
		
		# Start appropriate layers
		match state:
			MusicState.EXPLORATION:
				_activate_layer(state_name + "_ambient", 0.0)
			MusicState.COMBAT_LOW:
				_activate_layer(state_name + "_drums", 0.5)
			MusicState.COMBAT_HIGH:
				_activate_layer(state_name + "_drums", 0.0)
				_activate_layer(state_name + "_orchestra", 1.0)

func _stop_state_music(state: int):
	var state_name = _get_state_name(state)
	
	for player_name in layer_players:
		if player_name.begins_with(state_name):
			var player = layer_players[player_name]
			if player.playing:
				_fade_out_player(player)

func activate_layer(layer_name: String, fade_time: float = 1.0):
	var player = layer_players.get(layer_name)
	if not player:
		return
	
	if not player.playing:
		player.play()
		player.volume_db = -80
	
	_fade_in_player(player, fade_time)
	
	if not layer_name in active_layers:
		active_layers.append(layer_name)
		emit_signal("layer_activated", layer_name)

func deactivate_layer(layer_name: String, fade_time: float = 1.0):
	var player = layer_players.get(layer_name)
	if not player:
		return
	
	_fade_out_player(player, fade_time)
	
	if layer_name in active_layers:
		active_layers.erase(layer_name)
		emit_signal("layer_deactivated", layer_name)

func _activate_layer(full_layer_name: String, delay: float = 0.0):
	if delay > 0:
		yield(get_tree().create_timer(delay), "timeout")
	
	activate_layer(full_layer_name)

func increase_intensity(amount: float):
	combat_intensity = min(1.0, combat_intensity + amount)
	_update_combat_layers()

func decrease_intensity(amount: float):
	combat_intensity = max(0.0, combat_intensity - amount)
	_update_combat_layers()

func _update_combat_layers():
	var state_name = _get_state_name(current_state)
	
	if current_state == MusicState.COMBAT_LOW:
		if combat_intensity > 0.3:
			activate_layer(state_name + "_strings")
		else:
			deactivate_layer(state_name + "_strings")
		
		if combat_intensity > 0.6:
			activate_layer(state_name + "_brass")
		else:
			deactivate_layer(state_name + "_brass")
	
	elif current_state == MusicState.COMBAT_HIGH:
		if combat_intensity > 0.5:
			activate_layer(state_name + "_choir")
		else:
			deactivate_layer(state_name + "_choir")
		
		if combat_intensity > 0.8:
			activate_layer(state_name + "_percussion")
		else:
			deactivate_layer(state_name + "_percussion")

func play_stinger(stinger_name: String, interrupt_current: bool = false):
	if not stingers.has(stinger_name):
		push_warning("Stinger not found: " + stinger_name)
		return
	
	if interrupt_current or not stinger_player.playing:
		stinger_player.stream = stingers[stinger_name]
		stinger_player.play()
		emit_signal("stinger_played", stinger_name)
	else:
		queued_stingers.append(stinger_name)

func _process_stinger_queue():
	if queued_stingers.size() > 0 and not stinger_player.playing:
		var next_stinger = queued_stingers.pop_front()
		play_stinger(next_stinger, true)

func set_sync_group(player_name: String, group: String):
	if not sync_groups.has(group):
		sync_groups[group] = []
	
	sync_groups[group].append(player_name)

func sync_players_in_group(group: String):
	if not sync_groups.has(group):
		return
	
	var players = sync_groups[group]
	if players.size() < 2:
		return
	
	# Get playback position from first player
	var sync_position = 0.0
	var first_player = layer_players.get(players[0])
	if first_player and first_player.playing:
		sync_position = first_player.get_playback_position()
	
	# Sync all other players
	for i in range(1, players.size()):
		var player = layer_players.get(players[i])
		if player and player.playing:
			player.seek(sync_position)

func _fade_in_player(player: AudioStreamPlayer, duration: float = -1):
	if duration < 0:
		duration = crossfade_time
	
	var tween = Tween.new()
	add_child(tween)
	tween.interpolate_property(player, "volume_db", player.volume_db, 0, duration)
	tween.start()
	
	yield(tween, "tween_all_completed")
	tween.queue_free()

func _fade_out_player(player: AudioStreamPlayer, duration: float = -1):
	if duration < 0:
		duration = crossfade_time
	
	var tween = Tween.new()
	add_child(tween)
	tween.interpolate_property(player, "volume_db", player.volume_db, -80, duration)
	tween.start()
	
	yield(tween, "tween_all_completed")
	player.stop()
	tween.queue_free()

func _get_state_name(state: int) -> String:
	match state:
		MusicState.MENU: return "menu"
		MusicState.EXPLORATION: return "exploration"
		MusicState.COMBAT_LOW: return "combat_low"
		MusicState.COMBAT_HIGH: return "combat_high"
		MusicState.STEALTH: return "stealth"
		MusicState.BOSS: return "boss"
		MusicState.VICTORY: return "victory"
		MusicState.DEFEAT: return "defeat"
		_: return "unknown"

func get_current_beat() -> int:
	return current_beat

func get_current_measure() -> int:
	return current_measure

func get_time_to_next_beat() -> float:
	return beat_time - measure_time

func get_time_to_next_measure() -> float:
	var beats_remaining = beats_per_measure - current_beat
	return (beats_remaining * beat_time) - measure_time

func set_bpm(new_bpm: float):
	bpm = new_bpm
	beat_time = 60.0 / bpm

func register_combat_event():
	increase_intensity(intensity_increase_rate)
	
	if current_state == MusicState.EXPLORATION:
		set_music_state(MusicState.COMBAT_LOW)
	elif current_state == MusicState.COMBAT_LOW and combat_intensity > 0.7:
		set_music_state(MusicState.COMBAT_HIGH)

func register_combat_end():
	if current_state == MusicState.COMBAT_LOW or current_state == MusicState.COMBAT_HIGH:
		set_music_state(MusicState.EXPLORATION)
		combat_intensity = 0.0