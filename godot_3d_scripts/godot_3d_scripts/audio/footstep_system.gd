extends Node

class_name FootstepSystem

signal footstep_played(surface_type, position)

export var enabled: bool = true
export var volume_db: float = -10.0
export var pitch_variation: float = 0.1
export var min_velocity: float = 0.5
export var walk_interval: float = 0.5
export var run_interval: float = 0.3
export var sprint_interval: float = 0.2
export var jump_land_threshold: float = 3.0

var footstep_sounds: Dictionary = {}
var surface_materials: Dictionary = {}
var footstep_timer: float = 0.0
var last_foot: int = 0
var is_grounded: bool = false
var was_in_air: bool = false
var air_time: float = 0.0
var player_reference: Spatial = null
var audio_players: Array = []
var current_surface: String = "concrete"

onready var raycast = RayCast.new()

func _ready():
	setup_raycast()
	create_audio_players()
	load_default_footstep_sounds()
	set_process(false)

func setup_raycast():
	raycast.enabled = true
	raycast.cast_to = Vector3(0, -2.0, 0)
	raycast.collision_mask = 1
	add_child(raycast)

func create_audio_players():
	for i in range(4):
		var audio_player = AudioStreamPlayer3D.new()
		audio_player.bus = "SFX"
		audio_player.unit_db = volume_db
		audio_player.unit_size = 10.0
		audio_player.max_db = 3.0
		audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		add_child(audio_player)
		audio_players.append(audio_player)

func load_default_footstep_sounds():
	footstep_sounds = {
		"concrete": {
			"walk": [
				preload("res://audio/footsteps/concrete_walk_01.ogg"),
				preload("res://audio/footsteps/concrete_walk_02.ogg"),
				preload("res://audio/footsteps/concrete_walk_03.ogg"),
				preload("res://audio/footsteps/concrete_walk_04.ogg")
			],
			"run": [
				preload("res://audio/footsteps/concrete_run_01.ogg"),
				preload("res://audio/footsteps/concrete_run_02.ogg"),
				preload("res://audio/footsteps/concrete_run_03.ogg")
			],
			"land": [
				preload("res://audio/footsteps/concrete_land_01.ogg"),
				preload("res://audio/footsteps/concrete_land_02.ogg")
			]
		},
		"grass": {
			"walk": [
				preload("res://audio/footsteps/grass_walk_01.ogg"),
				preload("res://audio/footsteps/grass_walk_02.ogg"),
				preload("res://audio/footsteps/grass_walk_03.ogg"),
				preload("res://audio/footsteps/grass_walk_04.ogg")
			],
			"run": [
				preload("res://audio/footsteps/grass_run_01.ogg"),
				preload("res://audio/footsteps/grass_run_02.ogg"),
				preload("res://audio/footsteps/grass_run_03.ogg")
			],
			"land": [
				preload("res://audio/footsteps/grass_land_01.ogg")
			]
		},
		"wood": {
			"walk": [
				preload("res://audio/footsteps/wood_walk_01.ogg"),
				preload("res://audio/footsteps/wood_walk_02.ogg"),
				preload("res://audio/footsteps/wood_walk_03.ogg")
			],
			"run": [
				preload("res://audio/footsteps/wood_run_01.ogg"),
				preload("res://audio/footsteps/wood_run_02.ogg")
			],
			"land": [
				preload("res://audio/footsteps/wood_land_01.ogg"),
				preload("res://audio/footsteps/wood_land_02.ogg")
			]
		},
		"metal": {
			"walk": [
				preload("res://audio/footsteps/metal_walk_01.ogg"),
				preload("res://audio/footsteps/metal_walk_02.ogg"),
				preload("res://audio/footsteps/metal_walk_03.ogg")
			],
			"run": [
				preload("res://audio/footsteps/metal_run_01.ogg"),
				preload("res://audio/footsteps/metal_run_02.ogg")
			],
			"land": [
				preload("res://audio/footsteps/metal_land_01.ogg")
			]
		},
		"water": {
			"walk": [
				preload("res://audio/footsteps/water_walk_01.ogg"),
				preload("res://audio/footsteps/water_walk_02.ogg")
			],
			"run": [
				preload("res://audio/footsteps/water_run_01.ogg"),
				preload("res://audio/footsteps/water_run_02.ogg")
			],
			"land": [
				preload("res://audio/footsteps/water_land_01.ogg")
			]
		},
		"sand": {
			"walk": [
				preload("res://audio/footsteps/sand_walk_01.ogg"),
				preload("res://audio/footsteps/sand_walk_02.ogg"),
				preload("res://audio/footsteps/sand_walk_03.ogg")
			],
			"run": [
				preload("res://audio/footsteps/sand_run_01.ogg"),
				preload("res://audio/footsteps/sand_run_02.ogg")
			],
			"land": [
				preload("res://audio/footsteps/sand_land_01.ogg")
			]
		},
		"snow": {
			"walk": [
				preload("res://audio/footsteps/snow_walk_01.ogg"),
				preload("res://audio/footsteps/snow_walk_02.ogg"),
				preload("res://audio/footsteps/snow_walk_03.ogg")
			],
			"run": [
				preload("res://audio/footsteps/snow_run_01.ogg"),
				preload("res://audio/footsteps/snow_run_02.ogg")
			],
			"land": [
				preload("res://audio/footsteps/snow_land_01.ogg")
			]
		}
	}

func register_surface_material(material_path: String, surface_type: String):
	surface_materials[material_path] = surface_type

func register_footstep_sounds(surface_type: String, sounds: Dictionary):
	footstep_sounds[surface_type] = sounds

func set_player_reference(player: Spatial):
	player_reference = player
	if player:
		raycast.get_parent().remove_child(raycast)
		player.add_child(raycast)
		raycast.position = Vector3.ZERO
		set_process(true)
	else:
		set_process(false)

func _process(delta):
	if not enabled or not player_reference:
		return
	
	update_ground_detection()
	detect_surface_type()
	
	if is_grounded:
		handle_movement_footsteps(delta)
		check_landing()
	else:
		air_time += delta
		was_in_air = true

func update_ground_detection():
	if player_reference.has_method("is_on_floor"):
		is_grounded = player_reference.is_on_floor()
	else:
		is_grounded = raycast.is_colliding()

func detect_surface_type():
	if not raycast.is_colliding():
		return
	
	var collider = raycast.get_collider()
	if not collider:
		return
	
	var detected_surface = "concrete"
	
	if collider.has_method("get_surface_type"):
		detected_surface = collider.get_surface_type()
	elif collider is StaticBody or collider is RigidBody:
		detected_surface = get_surface_from_collision(collider)
	
	if detected_surface != current_surface:
		current_surface = detected_surface

func get_surface_from_collision(body: PhysicsBody) -> String:
	if body.has_meta("surface_type"):
		return body.get_meta("surface_type")
	
	if body is MeshInstance:
		var material = body.get_surface_material(0)
		if material:
			var material_path = material.resource_path
			if material_path in surface_materials:
				return surface_materials[material_path]
	
	var parent = body.get_parent()
	if parent and parent is MeshInstance:
		var material = parent.get_surface_material(0)
		if material:
			var material_path = material.resource_path
			if material_path in surface_materials:
				return surface_materials[material_path]
	
	return "concrete"

func handle_movement_footsteps(delta):
	var velocity = get_player_velocity()
	var speed = velocity.length()
	
	if speed < min_velocity:
		footstep_timer = 0.0
		return
	
	var interval = get_footstep_interval(speed)
	footstep_timer += delta
	
	if footstep_timer >= interval:
		play_footstep(get_movement_type(speed))
		footstep_timer = 0.0

func get_player_velocity() -> Vector3:
	if player_reference.has_method("get_velocity"):
		return player_reference.get_velocity()
	elif player_reference.has("velocity"):
		return player_reference.velocity
	elif player_reference.has_method("get_linear_velocity"):
		return player_reference.get_linear_velocity()
	return Vector3.ZERO

func get_footstep_interval(speed: float) -> float:
	if speed > 10.0:
		return sprint_interval
	elif speed > 5.0:
		return run_interval
	else:
		return walk_interval

func get_movement_type(speed: float) -> String:
	if speed > 5.0:
		return "run"
	else:
		return "walk"

func check_landing():
	if was_in_air and air_time > 0.1:
		var fall_velocity = get_player_velocity().y
		if abs(fall_velocity) > jump_land_threshold:
			play_footstep("land", true)
		was_in_air = false
		air_time = 0.0

func play_footstep(movement_type: String = "walk", force_play: bool = false):
	if not current_surface in footstep_sounds:
		return
	
	var surface_sounds = footstep_sounds[current_surface]
	if not movement_type in surface_sounds:
		return
	
	var sound_array = surface_sounds[movement_type]
	if sound_array.empty():
		return
	
	var audio_player = get_available_audio_player()
	if not audio_player and not force_play:
		return
	
	if not audio_player:
		audio_player = audio_players[0]
		audio_player.stop()
	
	var sound_index = randi() % sound_array.size()
	audio_player.stream = sound_array[sound_index]
	audio_player.pitch_scale = 1.0 + rand_range(-pitch_variation, pitch_variation)
	audio_player.unit_db = volume_db
	
	if movement_type == "land":
		audio_player.unit_db = volume_db + 5.0
	
	if player_reference:
		audio_player.global_transform.origin = player_reference.global_transform.origin
	
	audio_player.play()
	
	last_foot = 1 - last_foot
	
	emit_signal("footstep_played", current_surface, audio_player.global_transform.origin)

func get_available_audio_player() -> AudioStreamPlayer3D:
	for audio_player in audio_players:
		if not audio_player.playing:
			return audio_player
	return null

func play_jump_sound():
	play_footstep("walk", true)

func set_volume(volume: float):
	volume_db = volume
	for audio_player in audio_players:
		audio_player.unit_db = volume_db

func set_enabled(value: bool):
	enabled = value

func get_current_surface() -> String:
	return current_surface

func override_surface_temporarily(surface_type: String, duration: float):
	var previous_surface = current_surface
	current_surface = surface_type
	yield(get_tree().create_timer(duration), "timeout")
	current_surface = previous_surface

func create_footstep_at_position(position: Vector3, surface_type: String = "concrete", movement_type: String = "walk"):
	if not surface_type in footstep_sounds:
		return
	
	var temp_player = AudioStreamPlayer3D.new()
	temp_player.bus = "SFX"
	temp_player.unit_db = volume_db
	temp_player.unit_size = 10.0
	temp_player.global_transform.origin = position
	
	var surface_sounds = footstep_sounds[surface_type]
	if movement_type in surface_sounds and not surface_sounds[movement_type].empty():
		var sound_array = surface_sounds[movement_type]
		temp_player.stream = sound_array[randi() % sound_array.size()]
		temp_player.pitch_scale = 1.0 + rand_range(-pitch_variation, pitch_variation)
		
		get_tree().get_root().add_child(temp_player)
		temp_player.play()
		temp_player.connect("finished", temp_player, "queue_free")