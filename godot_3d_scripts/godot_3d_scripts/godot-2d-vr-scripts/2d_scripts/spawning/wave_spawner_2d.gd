extends Node2D

export var spawn_points_path : NodePath
export var spawn_radius = 100.0
export var spawn_delay_between_enemies = 0.2
export var wave_start_delay = 3.0
export var infinite_waves = false
export var max_enemies_alive = 50

signal wave_started(wave_number)
signal wave_completed(wave_number)
signal enemy_spawned(enemy, wave_number)
signal all_waves_completed()
signal spawner_exhausted()

class Wave:
	var enemy_scenes : Array = []
	var enemy_counts : Dictionary = {}
	var total_enemies : int = 0
	var spawn_pattern : String = "random"
	var spawn_delay_override : float = -1.0
	var bonus_on_completion : Dictionary = {}
	
	func add_enemy_type(scene : PackedScene, count : int):
		if not scene in enemy_scenes:
			enemy_scenes.append(scene)
		enemy_counts[scene] = count
		total_enemies += count

var waves : Array = []
var current_wave : int = 0
var enemies_to_spawn : Array = []
var spawned_enemies : Array = []
var spawn_timer : float = 0.0
var wave_active : bool = false
var spawn_points : Array = []
var wave_start_timer : float = 0.0

onready var spawn_container = $SpawnedEnemies

func _ready():
	if not spawn_container:
		spawn_container = Node2D.new()
		spawn_container.name = "SpawnedEnemies"
		add_child(spawn_container)
	
	_setup_spawn_points()
	_create_default_waves()

func _setup_spawn_points():
	if spawn_points_path:
		var spawn_parent = get_node(spawn_points_path)
		if spawn_parent:
			for child in spawn_parent.get_children():
				if child is Position2D:
					spawn_points.append(child)
	
	if spawn_points.empty():
		var default_point = Position2D.new()
		default_point.position = Vector2.ZERO
		add_child(default_point)
		spawn_points.append(default_point)

func _create_default_waves():
	for i in range(5):
		var wave = Wave.new()
		waves.append(wave)

func _process(delta):
	if wave_start_timer > 0:
		wave_start_timer -= delta
		if wave_start_timer <= 0:
			_begin_wave_spawning()
		return
	
	if wave_active:
		spawn_timer -= delta
		
		if spawn_timer <= 0 and not enemies_to_spawn.empty():
			_spawn_next_enemy()
			
			var current_wave_data = waves[current_wave]
			if current_wave_data.spawn_delay_override > 0:
				spawn_timer = current_wave_data.spawn_delay_override
			else:
				spawn_timer = spawn_delay_between_enemies
		
		_clean_dead_enemies()
		
		if enemies_to_spawn.empty() and spawned_enemies.empty():
			_complete_wave()

func add_wave(wave : Wave):
	waves.append(wave)

func create_wave():
	var wave = Wave.new()
	waves.append(wave)
	return wave

func start_spawning():
	if current_wave >= waves.size():
		if infinite_waves:
			current_wave = 0
		else:
			emit_signal("spawner_exhausted")
			return
	
	wave_start_timer = wave_start_delay
	emit_signal("wave_started", current_wave + 1)

func _begin_wave_spawning():
	wave_active = true
	_prepare_enemies_for_wave()

func _prepare_enemies_for_wave():
	enemies_to_spawn.clear()
	var wave = waves[current_wave]
	
	for scene in wave.enemy_scenes:
		var count = wave.enemy_counts.get(scene, 0)
		for i in range(count):
			enemies_to_spawn.append(scene)
	
	match wave.spawn_pattern:
		"random":
			enemies_to_spawn.shuffle()
		"sequential":
			pass
		"reverse":
			enemies_to_spawn.invert()
		"grouped":
			enemies_to_spawn.sort()

func _spawn_next_enemy():
	if spawned_enemies.size() >= max_enemies_alive:
		return
	
	var enemy_scene = enemies_to_spawn.pop_front()
	if not enemy_scene:
		return
	
	var enemy = enemy_scene.instance()
	spawn_container.add_child(enemy)
	
	var spawn_pos = _get_spawn_position()
	enemy.global_position = spawn_pos
	
	if enemy.has_method("set_wave_number"):
		enemy.set_wave_number(current_wave + 1)
	
	spawned_enemies.append(enemy)
	emit_signal("enemy_spawned", enemy, current_wave + 1)

func _get_spawn_position():
	if spawn_points.empty():
		return global_position
	
	var point = spawn_points[randi() % spawn_points.size()]
	var offset = Vector2(
		rand_range(-spawn_radius, spawn_radius),
		rand_range(-spawn_radius, spawn_radius)
	)
	
	return point.global_position + offset

func _clean_dead_enemies():
	var i = 0
	while i < spawned_enemies.size():
		var enemy = spawned_enemies[i]
		if not is_instance_valid(enemy) or (enemy.has_method("is_dead") and enemy.is_dead()):
			spawned_enemies.remove(i)
		else:
			i += 1

func _complete_wave():
	wave_active = false
	var wave = waves[current_wave]
	
	if not wave.bonus_on_completion.empty():
		_grant_wave_bonus(wave.bonus_on_completion)
	
	emit_signal("wave_completed", current_wave + 1)
	
	current_wave += 1
	
	if current_wave >= waves.size():
		if infinite_waves:
			current_wave = 0
			_scale_difficulty()
		else:
			emit_signal("all_waves_completed")

func _grant_wave_bonus(bonus):
	pass

func _scale_difficulty():
	for wave in waves:
		for scene in wave.enemy_scenes:
			var old_count = wave.enemy_counts[scene]
			wave.enemy_counts[scene] = int(old_count * 1.2)
		wave.total_enemies = 0
		for count in wave.enemy_counts.values():
			wave.total_enemies += count

func skip_to_wave(wave_number):
	if wave_number > 0 and wave_number <= waves.size():
		current_wave = wave_number - 1
		stop_current_wave()

func stop_current_wave():
	wave_active = false
	wave_start_timer = 0.0
	enemies_to_spawn.clear()
	
	for enemy in spawned_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	spawned_enemies.clear()

func pause_spawning():
	wave_active = false

func resume_spawning():
	if not enemies_to_spawn.empty():
		wave_active = true

func get_current_wave_number():
	return current_wave + 1

func get_enemies_remaining():
	return enemies_to_spawn.size() + spawned_enemies.size()

func get_wave_progress():
	var wave = waves[current_wave]
	var spawned = wave.total_enemies - enemies_to_spawn.size()
	return float(spawned) / float(wave.total_enemies)

func add_spawn_point(position):
	var point = Position2D.new()
	point.position = position
	add_child(point)
	spawn_points.append(point)

func clear_spawn_points():
	spawn_points.clear()

func set_wave_enemy(wave_number, enemy_scene, count):
	if wave_number > 0 and wave_number <= waves.size():
		var wave = waves[wave_number - 1]
		wave.add_enemy_type(enemy_scene, count)