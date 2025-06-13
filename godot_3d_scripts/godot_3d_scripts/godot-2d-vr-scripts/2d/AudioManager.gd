extends Node

class_name AudioManager

@export var master_volume: float = 1.0 : set = set_master_volume
@export var music_volume: float = 0.7 : set = set_music_volume
@export var sfx_volume: float = 0.8 : set = set_sfx_volume

var music_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var current_music: AudioStream

signal music_finished()

func _ready():
	setup_players()

func setup_players():
	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	music_player.finished.connect(_on_music_finished)
	
	for i in range(10):
		var sfx_player = AudioStreamPlayer.new()
		add_child(sfx_player)
		sfx_players.append(sfx_player)

func play_music(music: AudioStream, loop: bool = true):
	if not music or current_music == music:
		return
	
	current_music = music
	music_player.stream = music
	music_player.play()

func play_sfx(sound: AudioStream, volume: float = 1.0) -> AudioStreamPlayer:
	if not sound:
		return null
	
	for player in sfx_players:
		if not player.playing:
			player.stream = sound
			player.volume_db = linear_to_db(volume * sfx_volume)
			player.play()
			return player
	
	return null

func set_master_volume(value: float):
	master_volume = clamp(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(master_volume))

func set_music_volume(value: float):
	music_volume = clamp(value, 0.0, 1.0)
	if music_player:
		music_player.volume_db = linear_to_db(music_volume)

func set_sfx_volume(value: float):
	sfx_volume = clamp(value, 0.0, 1.0)

func _on_music_finished():
	music_finished.emit()