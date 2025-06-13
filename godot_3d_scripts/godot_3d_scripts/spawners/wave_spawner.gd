extends Node

# Wave-based Enemy Spawner for Godot 3D
# Manages spawning enemies in waves with increasing difficulty
# Supports multiple spawn points, enemy types, and wave configurations

# Wave configuration
export var auto_start = false
export var waves: Array = []  # Array of wave configurations
export var time_between_waves = 10.0
export var show_wave_ui = true

# Spawn settings
export var spawn_points_group = "spawn_points"
export var spawn_radius = 2.0
export var spawn_height = 1.0
export var check_spawn_clearance = true
export var clearance_radius = 1.5

# Enemy settings
export var enemy_scenes: Array = []  # Array of PackedScene
export var enemy_parent_path: NodePath = ".."
export var enemies_group = "enemies"

# Difficulty scaling
export var scale_enemy_health = true
export var health_scale_per_wave = 0.1
export var scale_enemy_damage = true
export var damage_scale_per_wave = 0.05
export var scale_enemy_speed = true
export var speed_scale_per_wave = 0.05

# Rewards
export var credits_per_enemy = 10
export var credits_per_wave = 100
export var bonus_credits_multiplier = 1.5

# Signals
signal wave_started(wave_number)
signal wave_completed(wave_number)
signal enemy_spawned(enemy, spawn_point)
signal all_waves_completed()
signal enemy_killed(enemy, credits)

# State variables
var current_wave = 0
var enemies_spawned_this_wave = 0
var enemies_remaining = 0
var wave_active = false
var spawn_timer: Timer
var wave_timer: Timer
var spawn_points = []
var enemy_parent: Node

# UI elements
onready var wave_label = $UI/WaveLabel if has_node("UI/WaveLabel") else null
onready var enemies_label = $UI/EnemiesLabel if has_node("UI/EnemiesLabel") else null
onready var timer_label = $UI/TimerLabel if has_node("UI/TimerLabel") else null

func _ready():
	# Get enemy parent
	if enemy_parent_path:
		enemy_parent = get_node(enemy_parent_path)
	else:
		enemy_parent = get_parent()
	
	# Setup timers
	setup_timers()
	
	# Get spawn points
	spawn_points = get_tree().get_nodes_in_group(spawn_points_group)
	if spawn_points.empty():
		push_warning("No spawn points found in group: " + spawn_points_group)
	
	# Initialize waves if empty
	if waves.empty():
		generate_default_waves()
	
	# Auto start if enabled
	if auto_start:
		start_spawning()

func setup_timers():
	"""Create and configure timers"""
	spawn_timer = Timer.new()
	spawn_timer.one_shot = true
	spawn_timer.connect("timeout", self, "_on_spawn_timer_timeout")
	add_child(spawn_timer)
	
	wave_timer = Timer.new()
	wave_timer.one_shot = true
	wave_timer.connect("timeout", self, "_on_wave_timer_timeout")
	add_child(wave_timer)

func generate_default_waves():
	"""Generate default wave configurations"""
	waves = [
		{
			"enemies": [
				{"type": 0, "count": 5, "spawn_delay": 2.0}
			],
			"name": "Wave 1 - Introduction"
		},
		{
			"enemies": [
				{"type": 0, "count": 8, "spawn_delay": 1.5},
				{"type": 1, "count": 2, "spawn_delay": 3.0}
			],
			"name": "Wave 2 - Mixed Forces"
		},
		{
			"enemies": [
				{"type": 0, "count": 10, "spawn_delay": 1.0},
				{"type": 1, "count": 5, "spawn_delay": 2.0},
				{"type": 2, "count": 1, "spawn_delay": 5.0}
			],
			"name": "Wave 3 - Elite Assault"
		}
	]

func start_spawning():
	"""Start the wave spawning system"""
	current_wave = 0
	start_next_wave()

func start_next_wave():
	"""Start the next wave"""
	if current_wave >= waves.size():
		emit_signal("all_waves_completed")
		return
	
	wave_active = true
	enemies_spawned_this_wave = 0
	
	var wave_config = waves[current_wave]
	emit_signal("wave_started", current_wave + 1)
	
	# Update UI
	if show_wave_ui:
		update_wave_ui()
	
	# Start spawning enemies
	spawn_wave_enemies(wave_config)

func spawn_wave_enemies(wave_config: Dictionary):
	"""Spawn enemies for the current wave"""
	var total_enemies = 0
	
	# Count total enemies
	for enemy_group in wave_config.enemies:
		total_enemies += enemy_group.count
	
	enemies_remaining = total_enemies
	
	# Spawn each enemy group
	for enemy_group in wave_config.enemies:
		spawn_enemy_group(enemy_group)

func spawn_enemy_group(group: Dictionary):
	"""Spawn a group of enemies"""
	var enemy_type = group.type
	var count = group.count
	var delay = group.get("spawn_delay", 1.0)
	
	for i in count:
		spawn_timer.wait_time = delay * i
		spawn_timer.start()
		yield(spawn_timer, "timeout")
		
		if not wave_active:
			break
		
		spawn_single_enemy(enemy_type)

func spawn_single_enemy(type_index: int):
	"""Spawn a single enemy"""
	if type_index >= enemy_scenes.size():
		push_error("Invalid enemy type index: " + str(type_index))
		return
	
	var enemy_scene = enemy_scenes[type_index]
	if not enemy_scene:
		push_error("Enemy scene is null for type: " + str(type_index))
		return
	
	# Get spawn position
	var spawn_pos = get_spawn_position()
	if spawn_pos == Vector3.INF:
		push_warning("No valid spawn position found")
		return
	
	# Instance enemy
	var enemy = enemy_scene.instance()
	enemy_parent.add_child(enemy)
	enemy.global_transform.origin = spawn_pos
	
	# Add to enemies group
	enemy.add_to_group(enemies_group)
	
	# Apply difficulty scaling
	apply_difficulty_scaling(enemy)
	
	# Connect death signal
	if enemy.has_signal("died"):
		enemy.connect("died", self, "_on_enemy_died", [enemy])
	
	enemies_spawned_this_wave += 1
	emit_signal("enemy_spawned", enemy, spawn_pos)

func get_spawn_position() -> Vector3:
	"""Get a valid spawn position"""
	if spawn_points.empty():
		return Vector3.INF
	
	# Try multiple times to find clear spawn point
	for i in 10:
		var spawn_point = spawn_points[randi() % spawn_points.size()]
		var base_pos = spawn_point.global_transform.origin
		
		# Add random offset
		var offset = Vector3(
			randf_range(-spawn_radius, spawn_radius),
			spawn_height,
			randf_range(-spawn_radius, spawn_radius)
		)
		
		var spawn_pos = base_pos + offset
		
		# Check clearance if enabled
		if check_spawn_clearance:
			if is_spawn_position_clear(spawn_pos):
				return spawn_pos
		else:
			return spawn_pos
	
	return Vector3.INF

func is_spawn_position_clear(pos: Vector3) -> bool:
	"""Check if spawn position is clear of obstacles"""
	var space_state = get_world().direct_space_state
	var shape = SphereShape.new()
	shape.radius = clearance_radius
	
	var query = PhysicsShapeQueryParameters.new()
	query.set_shape(shape)
	query.transform.origin = pos
	query.collision_mask = 1  # Adjust based on your collision layers
	
	var results = space_state.intersect_shape(query)
	return results.empty()

func apply_difficulty_scaling(enemy):
	"""Apply difficulty scaling to enemy"""
	var wave_multiplier = current_wave
	
	# Scale health
	if scale_enemy_health and enemy.has_property("max_health"):
		enemy.max_health *= (1.0 + health_scale_per_wave * wave_multiplier)
		if enemy.has_property("health"):
			enemy.health = enemy.max_health
	
	# Scale damage
	if scale_enemy_damage and enemy.has_property("damage"):
		enemy.damage *= (1.0 + damage_scale_per_wave * wave_multiplier)
	
	# Scale speed
	if scale_enemy_speed and enemy.has_property("move_speed"):
		enemy.move_speed *= (1.0 + speed_scale_per_wave * wave_multiplier)

func _on_enemy_died(enemy):
	"""Handle enemy death"""
	enemies_remaining -= 1
	
	# Award credits
	var credits = credits_per_enemy
	emit_signal("enemy_killed", enemy, credits)
	
	# Update UI
	if show_wave_ui:
		update_wave_ui()
	
	# Check if wave is complete
	if enemies_remaining <= 0 and wave_active:
		complete_wave()

func complete_wave():
	"""Complete the current wave"""
	wave_active = false
	
	# Award wave completion bonus
	var bonus = credits_per_wave
	if enemies_spawned_this_wave > 0:  # No deaths bonus
		bonus *= bonus_credits_multiplier
	
	emit_signal("wave_completed", current_wave + 1)
	
	current_wave += 1
	
	# Start timer for next wave
	if current_wave < waves.size():
		wave_timer.wait_time = time_between_waves
		wave_timer.start()
	else:
		emit_signal("all_waves_completed")

func _on_wave_timer_timeout():
	"""Handle wave timer timeout"""
	start_next_wave()

func _on_spawn_timer_timeout():
	"""Handle spawn timer timeout"""
	# Handled in spawn_enemy_group
	pass

func update_wave_ui():
	"""Update wave UI elements"""
	if wave_label:
		wave_label.text = "Wave %d / %d" % [current_wave + 1, waves.size()]
	
	if enemies_label:
		enemies_label.text = "Enemies: %d" % enemies_remaining
	
	if timer_label and wave_timer.time_left > 0:
		timer_label.text = "Next wave in: %d" % int(wave_timer.time_left)
		timer_label.visible = true
	elif timer_label:
		timer_label.visible = false

func _process(delta):
	"""Update UI timer"""
	if show_wave_ui and timer_label and wave_timer.time_left > 0:
		timer_label.text = "Next wave in: %d" % int(wave_timer.time_left)

# Public methods
func stop_spawning():
	"""Stop the spawning system"""
	wave_active = false
	spawn_timer.stop()
	wave_timer.stop()

func skip_to_wave(wave_number: int):
	"""Skip to a specific wave"""
	stop_spawning()
	current_wave = clamp(wave_number - 1, 0, waves.size() - 1)
	start_next_wave()

func add_spawn_point(position: Vector3):
	"""Add a new spawn point"""
	var spawn_point = Position3D.new()
	spawn_point.global_transform.origin = position
	spawn_point.add_to_group(spawn_points_group)
	get_parent().add_child(spawn_point)
	spawn_points.append(spawn_point)

func get_wave_info(wave_number: int) -> Dictionary:
	"""Get information about a specific wave"""
	if wave_number <= 0 or wave_number > waves.size():
		return {}
	
	return waves[wave_number - 1]