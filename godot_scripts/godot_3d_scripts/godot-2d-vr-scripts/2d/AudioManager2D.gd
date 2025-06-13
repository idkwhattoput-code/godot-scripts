extends Node

class_name AudioManager2D

signal music_finished()
signal sfx_finished(sfx_name: String)

@export var master_volume: float = 1.0 : set = set_master_volume
@export var music_volume: float = 0.7 : set = set_music_volume
@export var sfx_volume: float = 0.8 : set = set_sfx_volume
@export var max_simultaneous_sfx: int = 10
@export var fade_duration: float = 1.0

var music_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var current_music: AudioStream
var music_position: float = 0.0
var is_music_paused: bool = false

var sfx_pool: Array[AudioStreamPlayer] = []
var active_sfx: Dictionary = {}
var music_fade_tween: Tween

@onready var audio_container: Node = Node.new()

func _ready():
	add_child(audio_container)
	audio_container.name = "AudioContainer"
	
	setup_music_player()
	setup_sfx_pool()
	
	load_audio_settings()

func setup_music_player():
	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	music_player.volume_db = linear_to_db(music_volume * master_volume)
	music_player.finished.connect(_on_music_finished)
	audio_container.add_child(music_player)

func setup_sfx_pool():
	for i in range(max_simultaneous_sfx):
		var sfx_player = AudioStreamPlayer.new()
		sfx_player.name = "SFXPlayer_" + str(i)
		sfx_player.volume_db = linear_to_db(sfx_volume * master_volume)
		sfx_player.finished.connect(_on_sfx_finished.bind(sfx_player))
		audio_container.add_child(sfx_player)
		sfx_pool.append(sfx_player)

func play_music(stream: AudioStream, fade_in: bool = true, loop: bool = true):
	if current_music == stream and music_player.playing:
		return
	
	if music_player.playing and fade_in:
		fade_out_music()
		await music_fade_tween.finished
	
	current_music = stream
	music_player.stream = stream
	
	if stream.has_method("set_loop"):
		stream.set_loop(loop)
	elif stream.has_property("loop"):
		stream.loop = loop
	
	if fade_in:
		music_player.volume_db = -80
		music_player.play()
		fade_in_music()
	else:
		music_player.volume_db = linear_to_db(music_volume * master_volume)
		music_player.play()

func stop_music(fade_out: bool = true):
	if not music_player.playing:
		return
	
	if fade_out:
		fade_out_music()
		await music_fade_tween.finished
	else:
		music_player.stop()
	
	current_music = null

func pause_music():
	if music_player.playing:
		music_position = music_player.get_playback_position()
		music_player.stream_paused = true
		is_music_paused = true

func resume_music():
	if is_music_paused:
		music_player.stream_paused = false
		is_music_paused = false

func fade_in_music():
	if music_fade_tween:
		music_fade_tween.kill()
	
	music_fade_tween = create_tween()
	music_fade_tween.tween_property(music_player, "volume_db", linear_to_db(music_volume * master_volume), fade_duration)

func fade_out_music():
	if music_fade_tween:
		music_fade_tween.kill()
	
	music_fade_tween = create_tween()
	music_fade_tween.tween_property(music_player, "volume_db", -80, fade_duration)
	music_fade_tween.tween_callback(music_player.stop)

func crossfade_music(new_stream: AudioStream, crossfade_duration: float = 2.0):
	if not music_player.playing:
		play_music(new_stream)
		return
	
	var old_player = music_player
	
	setup_music_player()
	music_player.stream = new_stream
	music_player.volume_db = -80
	music_player.play()
	
	var fade_tween = create_tween()
	fade_tween.parallel().tween_property(old_player, "volume_db", -80, crossfade_duration)
	fade_tween.parallel().tween_property(music_player, "volume_db", linear_to_db(music_volume * master_volume), crossfade_duration)
	fade_tween.tween_callback(old_player.queue_free)
	
	current_music = new_stream

func play_sfx(stream: AudioStream, volume_scale: float = 1.0, pitch_scale: float = 1.0, sfx_name: String = "") -> AudioStreamPlayer:
	var player = get_available_sfx_player()
	if not player:
		return null
	
	player.stream = stream
	player.volume_db = linear_to_db(sfx_volume * master_volume * volume_scale)
	player.pitch_scale = pitch_scale
	
	if sfx_name != "":
		active_sfx[player] = sfx_name
	
	player.play()
	return player

func play_sfx_2d(stream: AudioStream, position: Vector2, volume_scale: float = 1.0, pitch_scale: float = 1.0, sfx_name: String = "") -> AudioStreamPlayer2D:
	var player_2d = AudioStreamPlayer2D.new()
	get_tree().current_scene.add_child(player_2d)
	
	player_2d.stream = stream
	player_2d.global_position = position
	player_2d.volume_db = linear_to_db(sfx_volume * master_volume * volume_scale)
	player_2d.pitch_scale = pitch_scale
	player_2d.finished.connect(_on_sfx_2d_finished.bind(player_2d, sfx_name))
	
	player_2d.play()
	return player_2d

func play_sfx_random_pitch(stream: AudioStream, min_pitch: float = 0.8, max_pitch: float = 1.2, volume_scale: float = 1.0, sfx_name: String = "") -> AudioStreamPlayer:
	var random_pitch = randf_range(min_pitch, max_pitch)
	return play_sfx(stream, volume_scale, random_pitch, sfx_name)

func play_sfx_with_delay(stream: AudioStream, delay: float, volume_scale: float = 1.0, pitch_scale: float = 1.0, sfx_name: String = ""):
	await get_tree().create_timer(delay).timeout
	play_sfx(stream, volume_scale, pitch_scale, sfx_name)

func stop_sfx(player: AudioStreamPlayer):
	if player and player.playing:
		player.stop()
		if player in active_sfx:
			active_sfx.erase(player)

func stop_all_sfx():
	for player in sfx_pool:
		if player.playing:
			player.stop()
	active_sfx.clear()

func get_available_sfx_player() -> AudioStreamPlayer:
	for player in sfx_pool:
		if not player.playing:
			return player
	
	var oldest_player = sfx_pool[0]
	var oldest_time = oldest_player.get_playback_position()
	
	for player in sfx_pool:
		if player.playing and player.get_playback_position() > oldest_time:
			oldest_player = player
			oldest_time = player.get_playback_position()
	
	oldest_player.stop()
	return oldest_player

func set_master_volume(value: float):
	master_volume = clamp(value, 0.0, 1.0)
	update_all_volumes()

func set_music_volume(value: float):
	music_volume = clamp(value, 0.0, 1.0)
	if music_player:
		music_player.volume_db = linear_to_db(music_volume * master_volume)

func set_sfx_volume(value: float):
	sfx_volume = clamp(value, 0.0, 1.0)
	update_sfx_volumes()

func update_all_volumes():
	if music_player:
		music_player.volume_db = linear_to_db(music_volume * master_volume)
	update_sfx_volumes()

func update_sfx_volumes():
	for player in sfx_pool:
		player.volume_db = linear_to_db(sfx_volume * master_volume)

func create_sound_group(group_name: String, streams: Array[AudioStream]) -> SoundGroup:
	var sound_group = SoundGroup.new()
	sound_group.name = group_name
	sound_group.streams = streams
	return sound_group

func play_sound_group(sound_group: SoundGroup, mode: SoundGroup.PlayMode = SoundGroup.PlayMode.RANDOM) -> AudioStreamPlayer:
	return sound_group.play(mode, self)

func save_audio_settings():
	var config = ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.save("user://audio_settings.cfg")

func load_audio_settings():
	var config = ConfigFile.new()
	if config.load("user://audio_settings.cfg") == OK:
		master_volume = config.get_value("audio", "master_volume", 1.0)
		music_volume = config.get_value("audio", "music_volume", 0.7)
		sfx_volume = config.get_value("audio", "sfx_volume", 0.8)
		update_all_volumes()

func get_music_playback_position() -> float:
	if music_player.playing:
		return music_player.get_playback_position()
	return music_position

func seek_music(position: float):
	if music_player.stream:
		music_player.seek(position)

func is_music_playing() -> bool:
	return music_player.playing

func get_music_length() -> float:
	if current_music:
		return current_music.get_length()
	return 0.0

func _on_music_finished():
	emit_signal("music_finished")

func _on_sfx_finished(player: AudioStreamPlayer):
	var sfx_name = active_sfx.get(player, "")
	if sfx_name != "":
		emit_signal("sfx_finished", sfx_name)
		active_sfx.erase(player)

func _on_sfx_2d_finished(player: AudioStreamPlayer2D, sfx_name: String):
	if sfx_name != "":
		emit_signal("sfx_finished", sfx_name)
	player.queue_free()

class SoundGroup extends Resource:
	enum PlayMode {
		RANDOM,
		SEQUENTIAL,
		SIMULTANEOUS
	}
	
	@export var name: String
	@export var streams: Array[AudioStream] = []
	var current_index: int = 0
	
	func play(mode: PlayMode, audio_manager: AudioManager2D) -> AudioStreamPlayer:
		if streams.is_empty():
			return null
		
		match mode:
			PlayMode.RANDOM:
				var random_stream = streams[randi() % streams.size()]
				return audio_manager.play_sfx(random_stream)
			PlayMode.SEQUENTIAL:
				var stream = streams[current_index]
				current_index = (current_index + 1) % streams.size()
				return audio_manager.play_sfx(stream)
			PlayMode.SIMULTANEOUS:
				var first_player = null
				for stream in streams:
					var player = audio_manager.play_sfx(stream)
					if not first_player:
						first_player = player
				return first_player
		
		return null