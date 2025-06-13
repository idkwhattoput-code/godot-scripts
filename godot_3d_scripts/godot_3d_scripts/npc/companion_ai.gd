extends CharacterBody3D

signal health_changed(current: float, max: float)
signal died
signal revived
signal enemy_spotted(enemy: Node3D)
signal item_found(item: Node3D)
signal dialogue_triggered(dialogue_id: String)

@export_group("Stats")
@export var max_health: float = 100.0
@export var movement_speed: float = 5.0
@export var run_speed: float = 8.0
@export var jump_velocity: float = 10.0
@export var attack_damage: float = 20.0
@export var attack_range: float = 15.0
@export var detection_range: float = 20.0

@export_group("AI Behavior")
@export var follow_distance: float = 3.0
@export var max_follow_distance: float = 30.0
@export var combat_style: CombatStyle = CombatStyle.BALANCED
@export var personality_traits: Array[String] = ["loyal", "brave", "cautious"]
@export var help_threshold: float = 0.3

@export_group("Abilities")
@export var can_heal_player: bool = true
@export var heal_amount: float = 30.0
@export var heal_cooldown: float = 20.0
@export var special_abilities: Array[String] = ["buff", "taunt", "stealth"]
@export var ability_cooldowns: Dictionary = {}

@export_group("Equipment")
@export var weapon_scene: PackedScene
@export var armor_value: float = 10.0
@export var inventory_size: int = 10

@export_group("Dialogue")
@export var companion_name: String = "Companion"
@export var dialogue_lines: Dictionary = {
	"greeting": ["Ready for adventure!", "Let's go!", "I'm with you!"],
	"combat": ["Watch out!", "Behind you!", "I've got your back!"],
	"low_health": ["I need healing!", "I'm hurt!", "Help me!"],
	"victory": ["We did it!", "Victory is ours!", "Well fought!"],
	"idle": ["Hmm...", "Quiet here.", "Stay alert."]
}

enum CombatStyle {
	AGGRESSIVE,
	DEFENSIVE,
	BALANCED,
	SUPPORT
}

enum CompanionState {
	FOLLOWING,
	COMBAT,
	IDLE,
	SEARCHING,
	USING_ABILITY,
	DOWNED
}

var current_health: float
var current_state: CompanionState = CompanionState.FOLLOWING
var player_reference: Node3D
var current_target: Node3D
var navigation_agent: NavigationAgent3D
var inventory: Array[Dictionary] = []
var ability_timers: Dictionary = {}
var heal_timer: float = 0.0
var dialogue_cooldown: float = 0.0
var last_known_player_position: Vector3

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var animation_player: AnimationPlayer
var weapon_instance: Node3D
var perception_area: Area3D

func _ready():
	current_health = max_health
	_setup_navigation()
	_setup_perception()
	_setup_weapon()
	_initialize_abilities()
	
	player_reference = _find_player()
	
func _setup_navigation():
	navigation_agent = NavigationAgent3D.new()
	navigation_agent.path_desired_distance = 1.0
	navigation_agent.target_desired_distance = follow_distance
	navigation_agent.avoidance_enabled = true
	add_child(navigation_agent)
	
func _setup_perception():
	perception_area = Area3D.new()
	perception_area.collision_layer = 0
	perception_area.collision_mask = 2 + 4
	
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = detection_range
	collision_shape.shape = sphere_shape
	
	perception_area.add_child(collision_shape)
	add_child(perception_area)
	
	perception_area.body_entered.connect(_on_perception_entered)
	perception_area.body_exited.connect(_on_perception_exited)
	
func _setup_weapon():
	if weapon_scene:
		weapon_instance = weapon_scene.instantiate()
		add_child(weapon_instance)
		
func _initialize_abilities():
	for ability in special_abilities:
		ability_timers[ability] = 0.0
		ability_cooldowns[ability] = 10.0
		
func _find_player() -> Node3D:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null
	
func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta
		
	_update_timers(delta)
	_process_state(delta)
	_check_player_needs(delta)
	
	move_and_slide()
	
func _update_timers(delta):
	heal_timer = max(0, heal_timer - delta)
	dialogue_cooldown = max(0, dialogue_cooldown - delta)
	
	for ability in ability_timers:
		ability_timers[ability] = max(0, ability_timers[ability] - delta)
		
func _process_state(delta):
	match current_state:
		CompanionState.FOLLOWING:
			_follow_player(delta)
		CompanionState.COMBAT:
			_engage_combat(delta)
		CompanionState.IDLE:
			_idle_behavior(delta)
		CompanionState.SEARCHING:
			_search_area(delta)
		CompanionState.USING_ABILITY:
			_use_ability_behavior(delta)
		CompanionState.DOWNED:
			_downed_behavior(delta)
			
func _follow_player(delta):
	if not player_reference:
		return
		
	var distance_to_player = global_position.distance_to(player_reference.global_position)
	
	if distance_to_player > max_follow_distance:
		_teleport_to_player()
		return
		
	if distance_to_player > follow_distance:
		navigation_agent.target_position = player_reference.global_position
		
		if navigation_agent.is_navigation_finished():
			return
			
		var next_position = navigation_agent.get_next_path_position()
		var direction = (next_position - global_position).normalized()
		
		var speed = run_speed if distance_to_player > follow_distance * 2 else movement_speed
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		
		_look_at_direction(direction)
		
		if animation_player:
			animation_player.play("run" if speed == run_speed else "walk")
	else:
		velocity.x = move_toward(velocity.x, 0, movement_speed * delta)
		velocity.z = move_toward(velocity.z, 0, movement_speed * delta)
		
		if animation_player:
			animation_player.play("idle")
			
	last_known_player_position = player_reference.global_position
	
func _engage_combat(delta):
	if not current_target or not is_instance_valid(current_target):
		_find_new_target()
		if not current_target:
			current_state = CompanionState.FOLLOWING
			return
			
	var distance_to_target = global_position.distance_to(current_target.global_position)
	
	match combat_style:
		CombatStyle.AGGRESSIVE:
			_aggressive_combat(distance_to_target, delta)
		CombatStyle.DEFENSIVE:
			_defensive_combat(distance_to_target, delta)
		CombatStyle.BALANCED:
			_balanced_combat(distance_to_target, delta)
		CombatStyle.SUPPORT:
			_support_combat(distance_to_target, delta)
			
func _aggressive_combat(distance: float, delta):
	if distance > 2.0:
		navigation_agent.target_position = current_target.global_position
		var direction = (navigation_agent.get_next_path_position() - global_position).normalized()
		velocity = direction * run_speed
		_look_at_direction(direction)
	else:
		_attack_target()
		
func _defensive_combat(distance: float, delta):
	var ideal_distance = attack_range * 0.8
	
	if distance < ideal_distance - 1.0:
		var direction = (global_position - current_target.global_position).normalized()
		velocity = direction * movement_speed
	elif distance > ideal_distance + 1.0:
		navigation_agent.target_position = current_target.global_position
		var direction = (navigation_agent.get_next_path_position() - global_position).normalized()
		velocity = direction * movement_speed
	else:
		velocity = Vector3.ZERO
		_attack_target()
		
func _balanced_combat(distance: float, delta):
	if distance > attack_range:
		_aggressive_combat(distance, delta)
	else:
		_defensive_combat(distance, delta)
		
func _support_combat(distance: float, delta):
	if player_reference and player_reference.has_method("get_health_percentage"):
		var player_health_percent = player_reference.get_health_percentage()
		if player_health_percent < 0.5 and can_heal_player and heal_timer <= 0:
			_move_to_player_and_heal()
			return
			
	_use_support_ability()
	_defensive_combat(distance, delta)
	
func _attack_target():
	if not current_target or not current_target.has_method("take_damage"):
		return
		
	current_target.take_damage(attack_damage, "companion", self)
	
	if weapon_instance and weapon_instance.has_method("attack"):
		weapon_instance.attack(current_target)
		
	if animation_player:
		animation_player.play("attack")
		
func _move_to_player_and_heal():
	if not player_reference:
		return
		
	var distance_to_player = global_position.distance_to(player_reference.global_position)
	
	if distance_to_player > 3.0:
		navigation_agent.target_position = player_reference.global_position
		var direction = (navigation_agent.get_next_path_position() - global_position).normalized()
		velocity = direction * run_speed
	else:
		velocity = Vector3.ZERO
		_heal_player()
		
func _heal_player():
	if player_reference and player_reference.has_method("heal"):
		player_reference.heal(heal_amount)
		heal_timer = heal_cooldown
		_speak("dialogue_lines", "I've healed you!")
		
		if animation_player:
			animation_player.play("cast_heal")
			
func _use_support_ability():
	for ability in special_abilities:
		if ability_timers[ability] <= 0:
			use_ability(ability)
			break
			
func use_ability(ability_name: String):
	if ability_timers.get(ability_name, 0) > 0:
		return
		
	current_state = CompanionState.USING_ABILITY
	ability_timers[ability_name] = ability_cooldowns.get(ability_name, 10.0)
	
	match ability_name:
		"buff":
			_cast_buff()
		"taunt":
			_cast_taunt()
		"stealth":
			_cast_stealth()
			
	await get_tree().create_timer(1.0).timeout
	current_state = CompanionState.COMBAT
	
func _cast_buff():
	if player_reference and player_reference.has_method("apply_buff"):
		player_reference.apply_buff("damage_boost", 10.0, 1.5)
		_speak("combat", "Power increased!")
		
func _cast_taunt():
	var enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		if global_position.distance_to(enemy.global_position) < detection_range:
			if enemy.has_method("set_target"):
				enemy.set_target(self)
				
	_speak("combat", "Come get me!")
	
func _cast_stealth():
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.3, 0.5)
	
	collision_layer = 0
	
	await get_tree().create_timer(5.0).timeout
	
	collision_layer = 1
	tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.5)
	
func _idle_behavior(delta):
	if randf() < 0.01:
		_speak("idle")
		
	if player_reference and global_position.distance_to(player_reference.global_position) > follow_distance * 1.5:
		current_state = CompanionState.FOLLOWING
		
func _search_area(delta):
	pass
	
func _use_ability_behavior(delta):
	pass
	
func _downed_behavior(delta):
	if player_reference and player_reference.has_method("revive_companion"):
		var distance = global_position.distance_to(player_reference.global_position)
		if distance < 2.0:
			_speak("low_health", "Help me up!")
			
func _check_player_needs(delta):
	if not player_reference:
		return
		
	if player_reference.has_method("get_health_percentage"):
		var health_percent = player_reference.get_health_percentage()
		if health_percent < help_threshold and dialogue_cooldown <= 0:
			_speak("combat", "You're hurt!")
			dialogue_cooldown = 5.0
			
func _find_new_target():
	var enemies = get_tree().get_nodes_in_group("enemy")
	var closest_enemy = null
	var closest_distance = detection_range
	
	for enemy in enemies:
		var distance = global_position.distance_to(enemy.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_enemy = enemy
			
	current_target = closest_enemy
	
	if current_target:
		enemy_spotted.emit(current_target)
		
func _teleport_to_player():
	if player_reference:
		global_position = player_reference.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
		
func _look_at_direction(direction: Vector3):
	if direction.length() > 0:
		direction.y = 0
		look_at(global_position + direction, Vector3.UP)
		
func _on_perception_entered(body: Node3D):
	if body.is_in_group("enemy") and current_state != CompanionState.COMBAT:
		current_target = body
		current_state = CompanionState.COMBAT
		enemy_spotted.emit(body)
		_speak("combat")
		
	elif body.is_in_group("item"):
		item_found.emit(body)
		
func _on_perception_exited(body: Node3D):
	if body == current_target:
		_find_new_target()
		
func take_damage(damage: float, source: Node3D = null):
	current_health = max(0, current_health - (damage - armor_value))
	health_changed.emit(current_health, max_health)
	
	if current_health <= 0:
		_die()
	else:
		_speak("low_health")
		
func _die():
	current_state = CompanionState.DOWNED
	died.emit()
	collision_layer = 0
	
	if animation_player:
		animation_player.play("death")
		
func revive():
	current_health = max_health * 0.5
	current_state = CompanionState.FOLLOWING
	collision_layer = 1
	revived.emit()
	_speak("greeting", "Thanks for reviving me!")
	
func add_item(item: Dictionary):
	if inventory.size() < inventory_size:
		inventory.append(item)
		return true
	return false
	
func _speak(category: String, override_text: String = ""):
	if dialogue_cooldown > 0:
		return
		
	var text = override_text
	if text == "" and dialogue_lines.has(category):
		var lines = dialogue_lines[category]
		text = lines[randi() % lines.size()]
		
	if text != "":
		dialogue_triggered.emit(text)
		dialogue_cooldown = 3.0
		
func get_companion_data() -> Dictionary:
	return {
		"name": companion_name,
		"health": current_health / max_health,
		"state": CompanionState.keys()[current_state],
		"inventory": inventory
	}