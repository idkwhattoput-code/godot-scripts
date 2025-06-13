extends Resource

class_name BossPhase

@export var phase_name := "Phase 1"
@export var health_threshold := 750.0
@export var attack_patterns: Array[String] = []
@export var movement_speed_multiplier := 1.0
@export var attack_speed_multiplier := 1.0
@export var damage_multiplier := 1.0
@export var defense_multiplier := 1.0
@export var special_mechanics: Array[String] = []

@export_group("Resistances")
@export var physical_resistance := 0.0
@export var magical_resistance := 0.0
@export var fire_resistance := 0.0
@export var ice_resistance := 0.0
@export var lightning_resistance := 0.0

@export_group("Phase Events")
@export var spawn_adds := false
@export var add_spawn_count := 3
@export var add_scene: PackedScene
@export var environmental_hazards := false
@export var shield_enabled := false
@export var shield_health := 200.0

var phase_index: int = 0
var boss_system: Node3D
var active_attack_pattern: String = ""
var pattern_index: int = 0
var time_since_last_attack: float = 0.0
var adds_spawned: Array[Node3D] = []
var shield_instance: Node3D
var current_shield_health: float = 0.0

func enter_phase():
	print("Entering boss phase: ", phase_name)
	
	if shield_enabled:
		create_shield()
	
	if spawn_adds:
		spawn_additional_enemies()
	
	if environmental_hazards:
		activate_environmental_hazards()
	
	select_next_attack_pattern()

func exit_phase():
	print("Exiting boss phase: ", phase_name)
	
	for add in adds_spawned:
		if is_instance_valid(add):
			add.queue_free()
	adds_spawned.clear()
	
	if shield_instance:
		shield_instance.queue_free()
		shield_instance = null
	
	deactivate_environmental_hazards()

func update_phase(delta: float):
	time_since_last_attack += delta
	
	if shield_instance and current_shield_health <= 0:
		break_shield()
	
	var attack_cooldown = 2.0 / attack_speed_multiplier
	if time_since_last_attack >= attack_cooldown:
		execute_current_pattern()
		time_since_last_attack = 0.0

func execute_current_pattern():
	if attack_patterns.is_empty():
		return
	
	match active_attack_pattern:
		"sweeping_laser":
			execute_sweeping_laser()
		"ground_pound":
			execute_ground_pound()
		"projectile_barrage":
			execute_projectile_barrage()
		"charge_attack":
			execute_charge_attack()
		"summon_minions":
			execute_summon_minions()
		"area_denial":
			execute_area_denial()
		"teleport_strike":
			execute_teleport_strike()
		_:
			print("Unknown attack pattern: ", active_attack_pattern)
	
	select_next_attack_pattern()

func select_next_attack_pattern():
	if attack_patterns.is_empty():
		return
	
	pattern_index = (pattern_index + 1) % attack_patterns.size()
	active_attack_pattern = attack_patterns[pattern_index]

func execute_sweeping_laser():
	if not boss_system:
		return
	
	var laser = preload("res://scenes/effects/boss_laser.tscn").instantiate()
	boss_system.add_child(laser)
	laser.sweep_angle = 180.0
	laser.sweep_duration = 3.0 / attack_speed_multiplier
	laser.damage = 30.0 * damage_multiplier
	laser.start_sweep()

func execute_ground_pound():
	if not boss_system:
		return
	
	var shockwave = preload("res://scenes/effects/shockwave.tscn").instantiate()
	boss_system.get_parent().add_child(shockwave)
	shockwave.global_position = boss_system.global_position
	shockwave.damage = 40.0 * damage_multiplier
	shockwave.radius = 10.0
	shockwave.expand()

func execute_projectile_barrage():
	if not boss_system:
		return
	
	var projectile_count = 20
	for i in range(projectile_count):
		var timer = Timer.new()
		timer.wait_time = i * 0.1 / attack_speed_multiplier
		timer.one_shot = true
		timer.timeout.connect(_spawn_projectile)
		boss_system.add_child(timer)
		timer.start()

func _spawn_projectile():
	var projectile = preload("res://scenes/projectiles/boss_projectile.tscn").instantiate()
	boss_system.get_parent().add_child(projectile)
	projectile.global_position = boss_system.global_position + Vector3(0, 2, 0)
	
	var player = boss_system.get_tree().get_first_node_in_group("player")
	if player:
		var direction = (player.global_position - projectile.global_position).normalized()
		direction += Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2))
		projectile.set_direction(direction)
		projectile.damage = 15.0 * damage_multiplier
		projectile.speed = 20.0

func execute_charge_attack():
	if not boss_system or not boss_system.has_method("charge_at_player"):
		return
	
	boss_system.charge_at_player(movement_speed_multiplier * 2.0, damage_multiplier * 50.0)

func execute_summon_minions():
	spawn_additional_enemies(3)

func execute_area_denial():
	if not boss_system:
		return
	
	var zone_count = 5
	for i in range(zone_count):
		var danger_zone = preload("res://scenes/effects/danger_zone.tscn").instantiate()
		boss_system.get_parent().add_child(danger_zone)
		
		var angle = (TAU / zone_count) * i
		var radius = 8.0
		danger_zone.global_position = boss_system.global_position + Vector3(
			cos(angle) * radius,
			0,
			sin(angle) * radius
		)
		danger_zone.damage = 20.0 * damage_multiplier
		danger_zone.duration = 5.0
		danger_zone.activate()

func execute_teleport_strike():
	if not boss_system or not boss_system.has_method("teleport_behind_player"):
		return
	
	boss_system.teleport_behind_player()
	
	var timer = Timer.new()
	timer.wait_time = 0.5
	timer.one_shot = true
	timer.timeout.connect(func(): boss_system.perform_strike_attack(damage_multiplier * 60.0))
	boss_system.add_child(timer)
	timer.start()

func create_shield():
	if not boss_system:
		return
	
	shield_instance = preload("res://scenes/effects/boss_shield.tscn").instantiate()
	boss_system.add_child(shield_instance)
	current_shield_health = shield_health
	shield_instance.set_health(shield_health)

func damage_shield(amount: float):
	if not shield_instance:
		return
	
	current_shield_health -= amount
	shield_instance.take_damage(amount)
	
	if current_shield_health <= 0:
		break_shield()

func break_shield():
	if shield_instance:
		shield_instance.break_effect()
		shield_instance.queue_free()
		shield_instance = null

func spawn_additional_enemies(count: int = -1):
	if not add_scene or not boss_system:
		return
	
	var spawn_count = count if count > 0 else add_spawn_count
	
	for i in range(spawn_count):
		var add = add_scene.instantiate()
		boss_system.get_parent().add_child(add)
		
		var angle = (TAU / spawn_count) * i
		var spawn_radius = 5.0
		add.global_position = boss_system.global_position + Vector3(
			cos(angle) * spawn_radius,
			0,
			sin(angle) * spawn_radius
		)
		
		adds_spawned.append(add)
		
		if add.has_method("set_target"):
			var player = boss_system.get_tree().get_first_node_in_group("player")
			if player:
				add.set_target(player)

func activate_environmental_hazards():
	var hazards = boss_system.get_tree().get_nodes_in_group("boss_environmental_hazards")
	for hazard in hazards:
		if hazard.has_method("activate"):
			hazard.activate()

func deactivate_environmental_hazards():
	var hazards = boss_system.get_tree().get_nodes_in_group("boss_environmental_hazards")
	for hazard in hazards:
		if hazard.has_method("deactivate"):
			hazard.deactivate()

func get_damage_multiplier(damage_type: String) -> float:
	var resistance = 0.0
	
	match damage_type:
		"physical":
			resistance = physical_resistance
		"magical":
			resistance = magical_resistance
		"fire":
			resistance = fire_resistance
		"ice":
			resistance = ice_resistance
		"lightning":
			resistance = lightning_resistance
	
	return 1.0 - (resistance / 100.0)

func on_enrage():
	attack_speed_multiplier *= 1.5
	damage_multiplier *= 1.3
	movement_speed_multiplier *= 1.2
	
	if not spawn_adds:
		spawn_adds = true
		add_spawn_count = 2