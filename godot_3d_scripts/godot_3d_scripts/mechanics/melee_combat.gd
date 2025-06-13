extends Node

signal attack_started
signal attack_hit(target, damage)
signal attack_missed
signal combo_performed(combo_name)
signal stamina_changed(current, maximum)

export var enabled: bool = true
export var base_damage: float = 20.0
export var attack_range: float = 2.0
export var attack_arc: float = 90.0
export var attack_speed: float = 1.0
export var combo_window: float = 0.5
export var max_combo_length: int = 3
export var stamina_enabled: bool = true
export var max_stamina: float = 100.0
export var stamina_regen_rate: float = 10.0
export var attack_stamina_cost: float = 15.0
export var heavy_attack_multiplier: float = 1.5
export var heavy_attack_stamina_multiplier: float = 2.0
export var critical_hit_chance: float = 0.15
export var critical_hit_multiplier: float = 2.0
export var knockback_force: float = 10.0

var current_stamina: float
var is_attacking: bool = false
var combo_count: int = 0
var combo_timer: float = 0.0
var attack_cooldown: float = 0.0
var current_attack_type: String = "light"
var attack_queue: Array = []
var recent_targets: Array = []

var combos: Dictionary = {
	"triple_strike": ["light", "light", "light"],
	"heavy_finisher": ["light", "light", "heavy"],
	"spinning_attack": ["heavy", "light", "heavy"],
	"guard_breaker": ["heavy", "heavy"]
}

var player: Spatial
var weapon_hitbox: Area
var animation_player: AnimationPlayer
var audio_player: AudioStreamPlayer3D

onready var attack_sounds: Array = []
onready var hit_sounds: Array = []
onready var miss_sounds: Array = []

func _ready():
	current_stamina = max_stamina
	set_process(false)

func initialize(player_node: Spatial, hitbox: Area = null, anim_player: AnimationPlayer = null):
	player = player_node
	weapon_hitbox = hitbox
	animation_player = anim_player
	
	if not weapon_hitbox:
		_create_default_hitbox()
	
	if weapon_hitbox:
		weapon_hitbox.monitoring = false
		weapon_hitbox.connect("body_entered", self, "_on_hitbox_body_entered")
		weapon_hitbox.connect("area_entered", self, "_on_hitbox_area_entered")
	
	_setup_audio()
	set_process(true)

func _process(delta):
	if not enabled:
		return
	
	if combo_timer > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			_reset_combo()
	
	if attack_cooldown > 0:
		attack_cooldown -= delta
	
	if stamina_enabled and current_stamina < max_stamina:
		current_stamina = min(max_stamina, current_stamina + stamina_regen_rate * delta)
		emit_signal("stamina_changed", current_stamina, max_stamina)
	
	_process_attack_queue()

func attack(attack_type: String = "light"):
	if not _can_attack():
		return false
	
	var stamina_cost = attack_stamina_cost
	if attack_type == "heavy":
		stamina_cost *= heavy_attack_stamina_multiplier
	
	if stamina_enabled and current_stamina < stamina_cost:
		return false
	
	if is_attacking:
		if attack_queue.size() < 2:
			attack_queue.append(attack_type)
		return true
	
	_perform_attack(attack_type)
	return true

func _can_attack() -> bool:
	return enabled and attack_cooldown <= 0

func _perform_attack(attack_type: String):
	is_attacking = true
	current_attack_type = attack_type
	recent_targets.clear()
	
	var stamina_cost = attack_stamina_cost
	if attack_type == "heavy":
		stamina_cost *= heavy_attack_stamina_multiplier
	
	if stamina_enabled:
		current_stamina -= stamina_cost
		emit_signal("stamina_changed", current_stamina, max_stamina)
	
	_add_to_combo(attack_type)
	_play_attack_animation(attack_type)
	_play_attack_sound()
	
	emit_signal("attack_started")
	
	yield(get_tree().create_timer(0.2 / attack_speed), "timeout")
	_activate_hitbox()
	
	yield(get_tree().create_timer(0.3 / attack_speed), "timeout")
	_deactivate_hitbox()
	
	yield(get_tree().create_timer(0.2 / attack_speed), "timeout")
	_finish_attack()

func _activate_hitbox():
	if weapon_hitbox:
		weapon_hitbox.monitoring = true

func _deactivate_hitbox():
	if weapon_hitbox:
		weapon_hitbox.monitoring = false
	
	if recent_targets.size() == 0:
		emit_signal("attack_missed")
		_play_miss_sound()

func _finish_attack():
	is_attacking = false
	attack_cooldown = 0.5 / attack_speed
	combo_timer = combo_window

func _process_attack_queue():
	if not is_attacking and attack_queue.size() > 0 and attack_cooldown <= 0:
		var next_attack = attack_queue.pop_front()
		_perform_attack(next_attack)

func _on_hitbox_body_entered(body):
	if body == player or body in recent_targets:
		return
	
	if body.has_method("take_damage"):
		_apply_damage_to_target(body)

func _on_hitbox_area_entered(area):
	if area == weapon_hitbox or area.get_parent() in recent_targets:
		return
	
	var target = area.get_parent()
	if target and target.has_method("take_damage"):
		_apply_damage_to_target(target)

func _apply_damage_to_target(target):
	if target in recent_targets:
		return
	
	recent_targets.append(target)
	
	var damage = _calculate_damage()
	var is_critical = randf() < critical_hit_chance
	
	if is_critical:
		damage *= critical_hit_multiplier
	
	target.take_damage(damage, player.global_transform.origin, player)
	
	_apply_knockback(target)
	_play_hit_sound()
	
	emit_signal("attack_hit", target, damage)

func _calculate_damage() -> float:
	var damage = base_damage
	
	if current_attack_type == "heavy":
		damage *= heavy_attack_multiplier
	
	var combo_multiplier = 1.0 + (combo_count * 0.1)
	damage *= combo_multiplier
	
	return damage

func _apply_knockback(target):
	if not target is RigidBody and not target.has_method("apply_impulse"):
		return
	
	var direction = (target.global_transform.origin - player.global_transform.origin).normalized()
	var force = knockback_force
	
	if current_attack_type == "heavy":
		force *= 1.5
	
	if target is RigidBody:
		target.apply_central_impulse(direction * force + Vector3.UP * force * 0.3)
	elif target.has_method("apply_impulse"):
		target.apply_impulse(direction * force + Vector3.UP * force * 0.3)

func _add_to_combo(attack_type: String):
	combo_count += 1
	attack_queue.append(attack_type)
	
	if attack_queue.size() > max_combo_length:
		attack_queue.pop_front()
	
	_check_for_combos()

func _check_for_combos():
	for combo_name in combos:
		var combo_pattern = combos[combo_name]
		if _matches_combo_pattern(combo_pattern):
			emit_signal("combo_performed", combo_name)
			_apply_combo_effects(combo_name)
			break

func _matches_combo_pattern(pattern: Array) -> bool:
	if attack_queue.size() < pattern.size():
		return false
	
	var start_index = attack_queue.size() - pattern.size()
	for i in range(pattern.size()):
		if attack_queue[start_index + i] != pattern[i]:
			return false
	
	return true

func _apply_combo_effects(combo_name: String):
	match combo_name:
		"triple_strike":
			base_damage *= 1.2
			yield(get_tree().create_timer(0.1), "timeout")
			base_damage /= 1.2
		"heavy_finisher":
			_perform_area_attack(attack_range * 1.5, base_damage * 2)
		"spinning_attack":
			_perform_spin_attack()
		"guard_breaker":
			pass

func _perform_area_attack(radius: float, damage: float):
	var space_state = player.get_world().direct_space_state
	var query = PhysicsShapeQueryParameters.new()
	var sphere = SphereShape.new()
	sphere.radius = radius
	query.set_shape(sphere)
	query.transform.origin = player.global_transform.origin
	
	var results = space_state.intersect_shape(query, 32)
	
	for result in results:
		var target = result.collider
		if target != player and target.has_method("take_damage"):
			target.take_damage(damage, player.global_transform.origin, player)
			_apply_knockback(target)

func _perform_spin_attack():
	pass

func _reset_combo():
	combo_count = 0
	attack_queue.clear()
	combo_timer = 0.0

func _create_default_hitbox():
	weapon_hitbox = Area.new()
	var shape = BoxShape.new()
	shape.extents = Vector3(0.3, 0.3, attack_range / 2.0)
	var collision = CollisionShape.new()
	collision.shape = shape
	weapon_hitbox.add_child(collision)
	
	if player:
		player.add_child(weapon_hitbox)
		weapon_hitbox.transform.origin = Vector3(0, 0, -attack_range / 2.0)

func _play_attack_animation(attack_type: String):
	if not animation_player:
		return
	
	var anim_name = attack_type + "_attack_" + str((combo_count - 1) % 3 + 1)
	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name, -1, attack_speed)
	elif animation_player.has_animation(attack_type + "_attack"):
		animation_player.play(attack_type + "_attack", -1, attack_speed)

func _setup_audio():
	if not audio_player:
		audio_player = AudioStreamPlayer3D.new()
		if player:
			player.add_child(audio_player)

func _play_attack_sound():
	if attack_sounds.size() > 0 and audio_player:
		audio_player.stream = attack_sounds[randi() % attack_sounds.size()]
		audio_player.pitch_scale = 0.9 + randf() * 0.2
		audio_player.play()

func _play_hit_sound():
	if hit_sounds.size() > 0 and audio_player:
		audio_player.stream = hit_sounds[randi() % hit_sounds.size()]
		audio_player.pitch_scale = 0.9 + randf() * 0.2
		audio_player.play()

func _play_miss_sound():
	if miss_sounds.size() > 0 and audio_player:
		audio_player.stream = miss_sounds[randi() % miss_sounds.size()]
		audio_player.pitch_scale = 0.9 + randf() * 0.2
		audio_player.play()

func set_combat_enabled(enabled_state: bool):
	enabled = enabled_state
	if not enabled:
		_reset_combo()
		attack_queue.clear()

func get_stamina_percentage() -> float:
	return (current_stamina / max_stamina) * 100.0

func restore_stamina(amount: float):
	current_stamina = min(max_stamina, current_stamina + amount)
	emit_signal("stamina_changed", current_stamina, max_stamina)

func add_combo(name: String, pattern: Array):
	combos[name] = pattern