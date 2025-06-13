extends Node

signal music_finished()
signal sound_effect_finished()

@export var master_volume: float = 1.0 : set = set_master_volume
@export var music_volume: float = 0.7 : set = set_music_volume
@export var sfx_volume: float = 0.8 : set = set_sfx_volume

var music_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var max_sfx_players: int = 10
var current_music: AudioStream
var music_fade_tween: Tween

func _ready():
	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	music_player.finished.connect(_on_music_finished)
	
	for i in max_sfx_players:
		var sfx_player = AudioStreamPlayer.new()
		add_child(sfx_player)
		sfx_players.append(sfx_player)

func play_music(music: AudioStream, fade_in: bool = false, fade_duration: float = 1.0):
	if current_music == music and music_player.playing:
		return
	
	if music_fade_tween:
		music_fade_tween.kill()
	
	if fade_in and music_player.playing:
		music_fade_tween = create_tween()
		music_fade_tween.tween_property(music_player, "volume_db", -80.0, fade_duration * 0.5)
		music_fade_tween.tween_callback(_switch_music.bind(music))
		music_fade_tween.tween_property(music_player, "volume_db", linear_to_db(music_volume * master_volume), fade_duration * 0.5)
	else:
		_switch_music(music)

func _switch_music(music: AudioStream):
	current_music = music
	music_player.stream = music
	music_player.volume_db = linear_to_db(music_volume * master_volume)
	music_player.play()

func stop_music(fade_out: bool = false, fade_duration: float = 1.0):
	if not music_player.playing:
		return
	
	if fade_out:
		if music_fade_tween:
			music_fade_tween.kill()
		music_fade_tween = create_tween()
		music_fade_tween.tween_property(music_player, "volume_db", -80.0, fade_duration)
		music_fade_tween.tween_callback(music_player.stop)
	else:
		music_player.stop()

func play_sfx(sound: AudioStream, pitch: float = 1.0, volume_override: float = -1.0) -> AudioStreamPlayer:
	var available_player = get_available_sfx_player()
	if not available_player:
		return null
	
	available_player.stream = sound
	available_player.pitch_scale = pitch
	
	var final_volume = sfx_volume if volume_override < 0 else volume_override
	available_player.volume_db = linear_to_db(final_volume * master_volume)
	available_player.play()
	
	return available_player

func get_available_sfx_player() -> AudioStreamPlayer:
	for player in sfx_players:
		if not player.playing:
			return player
	return sfx_players[0]

func set_master_volume(value: float):
	master_volume = clamp(value, 0.0, 1.0)
	update_all_volumes()

func set_music_volume(value: float):
	music_volume = clamp(value, 0.0, 1.0)
	update_music_volume()

func set_sfx_volume(value: float):
	sfx_volume = clamp(value, 0.0, 1.0)

func update_all_volumes():
	update_music_volume()

func update_music_volume():
	if music_player:
		music_player.volume_db = linear_to_db(music_volume * master_volume)

func _on_music_finished():
	music_finished.emit()