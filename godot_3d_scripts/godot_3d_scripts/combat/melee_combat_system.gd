extends Node

export var combo_window = 0.5
export var attack_cooldown = 0.2
export var damage_multipliers = {
	"light": 1.0,
	"heavy": 2.0,
	"combo_finisher": 3.0
}
export var stamina_costs = {
	"light": 10.0,
	"heavy": 25.0,
	"block": 5.0,
	"parry": 15.0
}

signal attack_performed(attack_type, damage)
signal combo_performed(combo_name, total_damage)
signal block_performed()
signal parry_performed()
signal stamina_depleted()

var current_combo = []
var combo_timer = 0.0
var attack_timer = 0.0
var is_attacking = false
var is_blocking = false
var current_stamina = 100.0
var max_stamina = 100.0

var combo_list = {
	"triple_slash": ["light", "light", "heavy"],
	"spin_attack": ["heavy", "heavy"],
	"uppercut": ["light", "heavy", "light"],
	"ground_slam": ["heavy", "light", "heavy"]
}

onready var hitbox_area = $HitboxArea
onready var weapon_trail = $WeaponTrail
onready var attack_sounds = $AttackSounds

func _ready():
	if hitbox_area:
		hitbox_area.monitoring = false
		hitbox_area.connect("body_entered", self, "_on_hitbox_entered")

func _physics_process(delta):
	if combo_timer > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			current_combo.clear()
	
	if attack_timer > 0:
		attack_timer -= delta
		if attack_timer <= 0:
			is_attacking = false
			if hitbox_area:
				hitbox_area.monitoring = false
	
	_regenerate_stamina(delta)

func perform_light_attack():
	if not _can_attack("light"):
		return
	
	_execute_attack("light", damage_multipliers["light"])
	current_combo.append("light")
	_check_combo()

func perform_heavy_attack():
	if not _can_attack("heavy"):
		return
	
	_execute_attack("heavy", damage_multipliers["heavy"])
	current_combo.append("heavy")
	_check_combo()

func start_blocking():
	if current_stamina < stamina_costs["block"]:
		return
	
	is_blocking = true
	emit_signal("block_performed")

func stop_blocking():
	is_blocking = false

func attempt_parry():
	if not is_blocking or current_stamina < stamina_costs["parry"]:
		return false
	
	_consume_stamina("parry")
	emit_signal("parry_performed")
	
	is_blocking = false
	return true

func _can_attack(attack_type):
	if is_attacking or is_blocking:
		return false
	
	if current_stamina < stamina_costs[attack_type]:
		emit_signal("stamina_depleted")
		return false
	
	return true

func _execute_attack(attack_type, damage_mult):
	is_attacking = true
	attack_timer = attack_cooldown
	combo_timer = combo_window
	
	_consume_stamina(attack_type)
	
	var base_damage = 10.0
	var damage = base_damage * damage_mult
	
	if hitbox_area:
		hitbox_area.monitoring = true
		hitbox_area.set_meta("damage", damage)
		hitbox_area.set_meta("attack_type", attack_type)
	
	if weapon_trail:
		weapon_trail.emitting = true
		
	_play_attack_sound(attack_type)
	
	emit_signal("attack_performed", attack_type, damage)

func _check_combo():
	for combo_name in combo_list:
		var combo_pattern = combo_list[combo_name]
		if _matches_combo(combo_pattern):
			_execute_combo(combo_name)
			current_combo.clear()
			break

func _matches_combo(pattern):
	if current_combo.size() < pattern.size():
		return false
	
	var start_index = current_combo.size() - pattern.size()
	for i in range(pattern.size()):
		if current_combo[start_index + i] != pattern[i]:
			return false
	
	return true

func _execute_combo(combo_name):
	var total_damage = 0.0
	var combo_pattern = combo_list[combo_name]
	
	for attack in combo_pattern:
		total_damage += damage_multipliers[attack] * 10.0
	
	total_damage *= damage_multipliers["combo_finisher"]
	
	emit_signal("combo_performed", combo_name, total_damage)
	
	_apply_combo_effects(combo_name)

func _apply_combo_effects(combo_name):
	match combo_name:
		"triple_slash":
			pass
		"spin_attack":
			if get_parent().has_method("spin_attack"):
				get_parent().spin_attack()
		"uppercut":
			if get_parent().has_method("uppercut"):
				get_parent().uppercut()
		"ground_slam":
			if get_parent().has_method("ground_slam"):
				get_parent().ground_slam()

func _on_hitbox_entered(body):
	if body == get_parent() or body.is_in_group("ally"):
		return
	
	if body.has_method("take_damage"):
		var damage = hitbox_area.get_meta("damage", 10.0)
		var attack_type = hitbox_area.get_meta("attack_type", "light")
		
		if body.has_method("is_blocking") and body.is_blocking():
			if body.has_method("block_damage"):
				body.block_damage(damage, get_parent())
		else:
			body.take_damage(damage, get_parent())
			_apply_hit_effects(body, attack_type)

func _apply_hit_effects(target, attack_type):
	if target is RigidBody:
		var knockback_force = 5.0 if attack_type == "light" else 10.0
		var knockback_dir = (target.global_transform.origin - get_parent().global_transform.origin).normalized()
		knockback_dir.y = 0.3
		target.apply_central_impulse(knockback_dir * knockback_force)

func _consume_stamina(action):
	current_stamina -= stamina_costs[action]
	current_stamina = max(0, current_stamina)

func _regenerate_stamina(delta):
	if not is_attacking and not is_blocking:
		current_stamina = min(current_stamina + 20.0 * delta, max_stamina)

func _play_attack_sound(attack_type):
	if not attack_sounds:
		return
	
	if attack_sounds.has_node(attack_type):
		attack_sounds.get_node(attack_type).play()

func get_stamina_percentage():
	return current_stamina / max_stamina

func has_stamina_for(action):
	return current_stamina >= stamina_costs.get(action, 0)

func interrupt_attack():
	is_attacking = false
	attack_timer = 0.0
	current_combo.clear()
	
	if hitbox_area:
		hitbox_area.monitoring = false

func set_weapon_active(active):
	if hitbox_area:
		hitbox_area.monitoring = active

func get_current_combo():
	return current_combo.duplicate()

func reset():
	current_combo.clear()
	combo_timer = 0.0
	attack_timer = 0.0
	is_attacking = false
	is_blocking = false
	current_stamina = max_stamina
	
	if hitbox_area:
		hitbox_area.monitoring = false