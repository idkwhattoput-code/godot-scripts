extends Node

# Adaptive music configuration
export var enable_adaptive_music = true
export var transition_time = 2.0
export var crossfade_curve = Tween.TRANS_SINE
export var beat_match_transitions = true
export var stem_based_mixing = true

# Music parameters
var music_parameters = {
	"tension": 0.0,      # 0-1: Combat intensity, danger level
	"emotion": 0.5,      # 0-1: Sad to happy
	"energy": 0.5,       # 0-1: Calm to intense
	"mystery": 0.0,      # 0-1: Exploration, puzzle solving
	"triumph": 0.0       # 0-1: Victory, achievement
}

# Stem tracks
var stem_tracks = {}
var active_stems = []
var stem_players = {}

# Musical sections
var sections = {}
var current_section = null
var next_section = null
var section_queue = []

# Timing and sync
var tempo = 120.0
var time_signature = 4
var current_bar = 0
var current_beat = 0
var beat_time = 0.0
var bars_per_section = 8

# Layers and variations
var layers = {}
var active_layers = []
var layer_volumes = {}
var layer_filters = {}

# Transitions
var transition_rules = {}
var is_transitioning = false
var transition_type = "crossfade"  # crossfade, cut, musical
var queued_transitions = []

# Stingers and one-shots
var stingers = {}
var scheduled_stingers = []

# Interactive elements
var interactive_instruments = {}
var player_performance_score = 0.0

# Emotional mapping
var emotion_presets = {
	"peaceful": {"tension": 0.0, "emotion": 0.7, "energy": 0.2},
	"combat": {"tension": 0.8, "emotion": 0.4, "energy": 0.9},
	"victory": {"tension": 0.2, "emotion": 0.9, "energy": 0.7, "triumph": 1.0},
	"defeat": {"tension": 0.1, "emotion": 0.1, "energy": 0.1},
	"exploration": {"tension": 0.3, "emotion": 0.5, "energy": 0.4, "mystery": 0.7},
	"boss": {"tension": 1.0, "emotion": 0.3, "energy": 1.0},
	"puzzle": {"tension": 0.2, "emotion": 0.5, "energy": 0.3, "mystery": 0.9}
}

# Analysis
var musical_analysis = {}
var harmonic_tension = 0.0
var rhythmic_density = 0.0

# Audio buses
var master_bus_idx = 0
var music_bus_idx = 0
var stem_bus_indices = {}

signal section_changed(new_section)
signal parameter_changed(param_name, value)
signal beat(beat_number)
signal bar(bar_number)
signal musical_event(event_type, data)

func _ready():
	_setup_audio_buses()
	_initialize_timing()
	_load_music_data()
	set_process(true)

func _setup_audio_buses():
	# Get bus indices
	master_bus_idx = AudioServer.get_bus_index("Master")
	music_bus_idx = AudioServer.get_bus_index("Music")
	
	# Create stem buses
	var stem_names = ["Drums", "Bass", "Harmony", "Melody", "Atmosphere", "Percussion"]
	for stem in stem_names:
		var bus_name = "Music_" + stem
		var idx = AudioServer.get_bus_index(bus_name)
		
		if idx == -1:
			idx = AudioServer.bus_count
			AudioServer.add_bus()
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Music")
		
		stem_bus_indices[stem] = idx

func _initialize_timing():
	beat_time = 60.0 / tempo
	
	# Create a timer for beat tracking
	var beat_timer = Timer.new()
	beat_timer.wait_time = beat_time
	beat_timer.connect("timeout", self, "_on_beat")
	add_child(beat_timer)
	beat_timer.start()

func _load_music_data():
	# Load music configuration from file or resource
	# This would typically load from a JSON or custom format
	_setup_example_music()

func _setup_example_music():
	# Example setup - replace with actual music loading
	sections = {
		"intro": {
			"stems": ["Atmosphere"],
			"duration_bars": 8,
			"next_sections": ["exploration", "combat"],
			"transition_rules": {
				"exploration": {"min_tension": 0, "max_tension": 0.5},
				"combat": {"min_tension": 0.5, "max_tension": 1.0}
			}
		},
		"exploration": {
			"stems": ["Atmosphere", "Melody", "Harmony"],
			"duration_bars": 16,
			"layers": ["percussion_light", "strings_ambient"],
			"next_sections": ["combat", "puzzle", "exploration"]
		},
		"combat": {
			"stems": ["Drums", "Bass", "Harmony", "Melody", "Percussion"],
			"duration_bars": 8,
			"intensity_stems": {
				"Drums": {"min": 0.5, "max": 1.0},
				"Percussion": {"min": 0.7, "max": 1.0}
			},
			"next_sections": ["victory", "defeat", "combat", "exploration"]
		},
		"victory": {
			"stems": ["Drums", "Bass", "Harmony", "Melody"],
			"duration_bars": 4,
			"stinger": "victory_fanfare",
			"next_sections": ["exploration"]
		}
	}

func _process(delta):
	if not enable_adaptive_music:
		return
	
	_update_musical_parameters(delta)
	_update_stem_mixing(delta)
	_update_transitions(delta)
	_process_scheduled_events()
	_analyze_musical_state()

func _on_beat():
	current_beat = (current_beat + 1) % time_signature
	
	if current_beat == 0:
		current_bar += 1
		emit_signal("bar", current_bar)
		
		# Check for section changes
		if current_section and current_bar % bars_per_section == 0:
			_check_section_transition()
	
	emit_signal("beat", current_beat)
	
	# Process beat-synchronized events
	_process_beat_events()

func _update_musical_parameters(delta):
	# Smooth parameter changes
	for param in music_parameters:
		var target = get(param + "_target") if has_method(param + "_target") else music_parameters[param]
		music_parameters[param] = lerp(music_parameters[param], target, delta * 2.0)
		
		# Notify listeners of significant changes
		if abs(music_parameters[param] - target) > 0.01:
			emit_signal("parameter_changed", param, music_parameters[param])

func _update_stem_mixing(delta):
	if not stem_based_mixing:
		return
	
	for stem in active_stems:
		if not stem_players.has(stem):
			continue
		
		var player = stem_players[stem]
		var target_volume = _calculate_stem_volume(stem)
		
		# Apply parameter-based mixing
		if stem == "Drums" or stem == "Percussion":
			target_volume *= music_parameters.tension * music_parameters.energy
		elif stem == "Bass":
			target_volume *= max(music_parameters.tension, music_parameters.energy * 0.7)
		elif stem == "Melody":
			target_volume *= music_parameters.emotion
		elif stem == "Atmosphere":
			target_volume *= music_parameters.mystery + (1.0 - music_parameters.energy) * 0.5
		
		# Smooth volume changes
		var current_volume = db2linear(player.volume_db)
		var new_volume = lerp(current_volume, target_volume, delta * 3.0)
		player.volume_db = linear2db(new_volume)
		
		# Apply filters based on parameters
		_update_stem_filters(stem, delta)

func _calculate_stem_volume(stem: String) -> float:
	if not current_section:
		return 0.0
	
	var section_data = sections[current_section]
	
	# Check if stem should be active
	if not stem in section_data.get("stems", []):
		return 0.0
	
	# Check intensity-based volume
	if section_data.has("intensity_stems") and section_data.intensity_stems.has(stem):
		var intensity_range = section_data.intensity_stems[stem]
		var intensity = music_parameters.tension
		
		if intensity < intensity_range.min:
			return 0.0
		elif intensity > intensity_range.max:
			return 1.0
		else:
			return (intensity - intensity_range.min) / (intensity_range.max - intensity_range.min)
	
	return 1.0

func _update_stem_filters(stem: String, delta):
	var bus_idx = stem_bus_indices.get(stem, -1)
	if bus_idx == -1:
		return
	
	# Example: Apply low-pass filter based on tension
	var filter_effect = AudioServer.get_bus_effect(bus_idx, 0)
	if filter_effect and filter_effect is AudioEffectLowPassFilter:
		var target_cutoff = 20000 - (1.0 - music_parameters.tension) * 15000
		filter_effect.cutoff_hz = lerp(filter_effect.cutoff_hz, target_cutoff, delta * 2.0)

func _check_section_transition():
	if not current_section or is_transitioning:
		return
	
	var section_data = sections[current_section]
	var possible_next = section_data.get("next_sections", [])
	
	if possible_next.empty():
		return
	
	# Choose next section based on parameters and rules
	var best_section = null
	var best_score = -1.0
	
	for next in possible_next:
		var score = _evaluate_transition_score(current_section, next)
		if score > best_score:
			best_score = score
			best_section = next
	
	if best_section and best_section != current_section:
		queue_section_transition(best_section)

func _evaluate_transition_score(from_section: String, to_section: String) -> float:
	var score = 0.5  # Base score
	
	# Check transition rules
	var from_data = sections[from_section]
	if from_data.has("transition_rules") and from_data.transition_rules.has(to_section):
		var rules = from_data.transition_rules[to_section]
		
		# Check parameter requirements
		for param in rules:
			if param.ends_with("_min") or param.ends_with("_max"):
				continue
			
			var param_value = music_parameters.get(param.replace("min_", "").replace("max_", ""), 0.5)
			var min_val = rules.get(param + "_min", 0.0)
			var max_val = rules.get(param + "_max", 1.0)
			
			if param_value >= min_val and param_value <= max_val:
				score += 0.2
			else:
				score -= 0.3
	
	# Prefer variety (avoid repeating the same section)
	if to_section == from_section:
		score -= 0.2
	
	return clamp(score, 0.0, 1.0)

func _update_transitions(delta):
	if not is_transitioning or not next_section:
		return
	
	match transition_type:
		"crossfade":
			_update_crossfade_transition(delta)
		"cut":
			_update_cut_transition()
		"musical":
			_update_musical_transition(delta)

func _update_crossfade_transition(delta):
	# Handled by stem volume updates
	pass

func _update_cut_transition():
	# Immediate transition
	_switch_to_section(next_section)
	is_transitioning = false
	next_section = null

func _update_musical_transition(delta):
	# Wait for musical boundary
	if beat_match_transitions and current_beat != 0:
		return
	
	_switch_to_section(next_section)
	is_transitioning = false
	next_section = null

func _switch_to_section(section_name: String):
	if not sections.has(section_name):
		push_warning("Unknown section: " + section_name)
		return
	
	current_section = section_name
	var section_data = sections[section_name]
	
	# Update active stems
	active_stems = section_data.get("stems", [])
	
	# Start/stop stem players
	for stem in stem_players:
		if stem in active_stems:
			if not stem_players[stem].playing:
				stem_players[stem].play()
		else:
			stem_players[stem].stop()
	
	# Play section stinger if any
	if section_data.has("stinger"):
		play_stinger(section_data.stinger)
	
	emit_signal("section_changed", section_name)

func _process_scheduled_events():
	# Process scheduled stingers
	var current_time = OS.get_ticks_msec() / 1000.0
	var completed_stingers = []
	
	for stinger_data in scheduled_stingers:
		if current_time >= stinger_data.time:
			_play_stinger_immediate(stinger_data.name)
			completed_stingers.append(stinger_data)
	
	for stinger in completed_stingers:
		scheduled_stingers.erase(stinger)

func _process_beat_events():
	# Process events that should happen on specific beats
	emit_signal("musical_event", "beat", {
		"beat": current_beat,
		"bar": current_bar,
		"section": current_section
	})

func _analyze_musical_state():
	# Analyze current musical properties
	harmonic_tension = _calculate_harmonic_tension()
	rhythmic_density = _calculate_rhythmic_density()
	
	musical_analysis = {
		"harmonic_tension": harmonic_tension,
		"rhythmic_density": rhythmic_density,
		"overall_intensity": (harmonic_tension + rhythmic_density) / 2.0,
		"mood": _calculate_mood()
	}

func _calculate_harmonic_tension() -> float:
	# Simplified - would analyze actual harmonic content
	return music_parameters.tension * 0.7 + music_parameters.energy * 0.3

func _calculate_rhythmic_density() -> float:
	# Simplified - would analyze actual rhythmic patterns
	var density = 0.0
	
	if "Drums" in active_stems:
		density += 0.4
	if "Percussion" in active_stems:
		density += 0.3
	if music_parameters.energy > 0.7:
		density += 0.3
	
	return clamp(density, 0.0, 1.0)

func _calculate_mood() -> String:
	# Determine overall mood from parameters
	var moods = []
	
	if music_parameters.tension > 0.7:
		moods.append("tense")
	if music_parameters.emotion > 0.7:
		moods.append("uplifting")
	elif music_parameters.emotion < 0.3:
		moods.append("melancholic")
	if music_parameters.mystery > 0.6:
		moods.append("mysterious")
	if music_parameters.triumph > 0.7:
		moods.append("triumphant")
	
	return moods.front() if not moods.empty() else "neutral"

# Public API

func set_parameter(param_name: String, value: float, transition_time: float = 1.0):
	if not music_parameters.has(param_name):
		push_warning("Unknown parameter: " + param_name)
		return
	
	# Set target value for smooth transition
	set(param_name + "_target", clamp(value, 0.0, 1.0))

func set_emotion_preset(preset_name: String, transition_time: float = 2.0):
	if not emotion_presets.has(preset_name):
		push_warning("Unknown emotion preset: " + preset_name)
		return
	
	var preset = emotion_presets[preset_name]
	for param in preset:
		set_parameter(param, preset[param], transition_time)

func queue_section_transition(section_name: String, transition_type: String = "crossfade"):
	next_section = section_name
	self.transition_type = transition_type
	is_transitioning = true

func play_stinger(stinger_name: String, delay: float = 0.0):
	if delay > 0:
		scheduled_stingers.append({
			"name": stinger_name,
			"time": OS.get_ticks_msec() / 1000.0 + delay
		})
	else:
		_play_stinger_immediate(stinger_name)

func _play_stinger_immediate(stinger_name: String):
	if not stingers.has(stinger_name):
		return
	
	var stinger_player = AudioStreamPlayer.new()
	stinger_player.stream = stingers[stinger_name]
	stinger_player.bus = "Music"
	add_child(stinger_player)
	stinger_player.play()
	stinger_player.connect("finished", stinger_player, "queue_free")
	
	emit_signal("musical_event", "stinger", {"name": stinger_name})

func register_stem(stem_name: String, audio_stream: AudioStream):
	if not stem_players.has(stem_name):
		var player = AudioStreamPlayer.new()
		player.stream = audio_stream
		player.bus = "Music_" + stem_name
		player.volume_db = -80
		add_child(player)
		stem_players[stem_name] = player

func add_interactive_instrument(instrument_name: String, audio_stream: AudioStream):
	interactive_instruments[instrument_name] = {
		"stream": audio_stream,
		"player": null,
		"active": false
	}

func trigger_instrument(instrument_name: String, note: int = 60, velocity: float = 1.0):
	if not interactive_instruments.has(instrument_name):
		return
	
	# Play instrument sound with pitch adjustment
	var instrument = interactive_instruments[instrument_name]
	var player = AudioStreamPlayer.new()
	player.stream = instrument.stream
	player.pitch_scale = pow(2, (note - 60) / 12.0)  # MIDI note to pitch
	player.volume_db = linear2db(velocity)
	player.bus = "Music"
	add_child(player)
	player.play()
	player.connect("finished", player, "queue_free")
	
	# Update performance score
	player_performance_score = min(1.0, player_performance_score + 0.1)

func get_musical_analysis() -> Dictionary:
	return musical_analysis

func get_current_section() -> String:
	return current_section if current_section else ""

func get_beat_info() -> Dictionary:
	return {
		"beat": current_beat,
		"bar": current_bar,
		"tempo": tempo,
		"time_signature": time_signature,
		"next_beat_time": beat_time - fmod(OS.get_ticks_msec() / 1000.0, beat_time)
	}

func sync_to_beat(callback: String, target: Object):
	# Schedule callback for next beat
	var next_beat_time = beat_time - fmod(OS.get_ticks_msec() / 1000.0, beat_time)
	get_tree().create_timer(next_beat_time).connect("timeout", target, callback)

func set_tempo(new_tempo: float):
	tempo = new_tempo
	beat_time = 60.0 / tempo