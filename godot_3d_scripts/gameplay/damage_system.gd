extends Node

class_name DamageSystem

enum DamageType {
	PHYSICAL,
	FIRE,
	ICE,
	ELECTRIC,
	POISON,
	PSYCHIC,
	HOLY,
	DARK
}

enum HitLocation {
	HEAD,
	TORSO,
	LEFT_ARM,
	RIGHT_ARM,
	LEFT_LEG,
	RIGHT_LEG
}

class DamageInfo:
	var amount: float = 0.0
	var type: int = DamageType.PHYSICAL
	var source: Node = null
	var position: Vector3 = Vector3.ZERO
	var direction: Vector3 = Vector3.ZERO
	var hit_location: int = HitLocation.TORSO
	var is_critical: bool = false
	var knockback_force: float = 0.0
	var status_effects: Array = []
	
	func _init(dmg_amount: float = 0.0, dmg_type: int = DamageType.PHYSICAL):
		amount = dmg_amount
		type = dmg_type

class DamageableEntity extends Node:
	export var max_health: float = 100.0
	export var current_health: float = 100.0
	export var armor: float = 0.0
	export var resistances: Dictionary = {}
	export var vulnerabilities: Dictionary = {}
	export var is_invulnerable: bool = false
	export var invulnerability_time: float = 0.5
	
	var invulnerability_timer: float = 0.0
	var damage_multipliers: Dictionary = {}
	var active_status_effects: Array = []
	
	signal health_changed(new_health, max_health)
	signal damage_taken(damage_info)
	signal died()
	signal status_effect_applied(effect)
	signal status_effect_removed(effect)
	
	func _ready():
		current_health = max_health
		_initialize_resistances()
	
	func _process(delta):
		if invulnerability_timer > 0:
			invulnerability_timer -= delta
		
		_process_status_effects(delta)
	
	func take_damage(damage_info: DamageInfo) -> float:
		if is_invulnerable or invulnerability_timer > 0:
			return 0.0
		
		var final_damage = _calculate_final_damage(damage_info)
		
		if final_damage <= 0:
			return 0.0
		
		current_health -= final_damage
		current_health = max(0, current_health)
		
		emit_signal("damage_taken", damage_info)
		emit_signal("health_changed", current_health, max_health)
		
		if damage_info.knockback_force > 0:
			_apply_knockback(damage_info.direction, damage_info.knockback_force)
		
		for effect in damage_info.status_effects:
			apply_status_effect(effect)
		
		if current_health <= 0:
			_die()
		else:
			invulnerability_timer = invulnerability_time
		
		return final_damage
	
	func heal(amount: float):
		var old_health = current_health
		current_health = min(current_health + amount, max_health)
		
		if current_health != old_health:
			emit_signal("health_changed", current_health, max_health)
	
	func _calculate_final_damage(damage_info: DamageInfo) -> float:
		var damage = damage_info.amount
		
		damage -= armor
		
		if resistances.has(damage_info.type):
			damage *= (1.0 - resistances[damage_info.type])
		
		if vulnerabilities.has(damage_info.type):
			damage *= (1.0 + vulnerabilities[damage_info.type])
		
		if damage_multipliers.has(damage_info.type):
			damage *= damage_multipliers[damage_info.type]
		
		if damage_info.is_critical:
			damage *= 2.0
		
		var location_multiplier = _get_location_multiplier(damage_info.hit_location)
		damage *= location_multiplier
		
		return max(0, damage)
	
	func _get_location_multiplier(location: int) -> float:
		match location:
			HitLocation.HEAD:
				return 2.0
			HitLocation.TORSO:
				return 1.0
			HitLocation.LEFT_ARM, HitLocation.RIGHT_ARM:
				return 0.8
			HitLocation.LEFT_LEG, HitLocation.RIGHT_LEG:
				return 0.7
			_:
				return 1.0
	
	func _apply_knockback(direction: Vector3, force: float):
		if has_method("apply_impulse"):
			call("apply_impulse", Vector3.ZERO, direction.normalized() * force)
		elif has_method("add_force"):
			call("add_force", direction.normalized() * force, Vector3.ZERO)
	
	func apply_status_effect(effect: StatusEffect):
		for existing_effect in active_status_effects:
			if existing_effect.id == effect.id:
				existing_effect.refresh()
				return
		
		active_status_effects.append(effect)
		effect.apply(self)
		emit_signal("status_effect_applied", effect)
	
	func remove_status_effect(effect_id: String):
		for i in range(active_status_effects.size() - 1, -1, -1):
			if active_status_effects[i].id == effect_id:
				var effect = active_status_effects[i]
				effect.remove(self)
				active_status_effects.remove(i)
				emit_signal("status_effect_removed", effect)
	
	func _process_status_effects(delta):
		for i in range(active_status_effects.size() - 1, -1, -1):
			var effect = active_status_effects[i]
			effect.update(self, delta)
			
			if effect.is_expired():
				remove_status_effect(effect.id)
	
	func _die():
		emit_signal("died")
		
		for effect in active_status_effects:
			effect.remove(self)
		active_status_effects.clear()
	
	func _initialize_resistances():
		if resistances.empty():
			resistances = {
				DamageType.PHYSICAL: 0.0,
				DamageType.FIRE: 0.0,
				DamageType.ICE: 0.0,
				DamageType.ELECTRIC: 0.0,
				DamageType.POISON: 0.0,
				DamageType.PSYCHIC: 0.0,
				DamageType.HOLY: 0.0,
				DamageType.DARK: 0.0
			}
	
	func set_resistance(damage_type: int, value: float):
		resistances[damage_type] = clamp(value, 0.0, 1.0)
	
	func set_vulnerability(damage_type: int, value: float):
		vulnerabilities[damage_type] = max(0.0, value)
	
	func get_health_percentage() -> float:
		return current_health / max_health if max_health > 0 else 0.0

class StatusEffect:
	var id: String = ""
	var name: String = ""
	var duration: float = 0.0
	var tick_rate: float = 1.0
	var tick_timer: float = 0.0
	var stacks: int = 1
	var max_stacks: int = 1
	
	func apply(target: DamageableEntity):
		pass
	
	func update(target: DamageableEntity, delta: float):
		duration -= delta
		tick_timer += delta
		
		if tick_timer >= tick_rate:
			tick_timer = 0.0
			tick(target)
	
	func tick(target: DamageableEntity):
		pass
	
	func remove(target: DamageableEntity):
		pass
	
	func refresh():
		duration = get_max_duration()
	
	func is_expired() -> bool:
		return duration <= 0
	
	func get_max_duration() -> float:
		return 5.0

class BurnEffect extends StatusEffect:
	var damage_per_tick: float = 5.0
	
	func _init():
		id = "burn"
		name = "Burn"
		duration = 5.0
		tick_rate = 0.5
	
	func tick(target: DamageableEntity):
		var damage_info = DamageInfo.new(damage_per_tick * stacks, DamageType.FIRE)
		target.take_damage(damage_info)

class PoisonEffect extends StatusEffect:
	var damage_per_tick: float = 3.0
	
	func _init():
		id = "poison"
		name = "Poison"
		duration = 10.0
		tick_rate = 1.0
		max_stacks = 5
	
	func tick(target: DamageableEntity):
		var damage_info = DamageInfo.new(damage_per_tick * stacks, DamageType.POISON)
		target.take_damage(damage_info)

class FreezeEffect extends StatusEffect:
	var slow_amount: float = 0.5
	
	func _init():
		id = "freeze"
		name = "Freeze"
		duration = 3.0
	
	func apply(target: DamageableEntity):
		if target.has_method("set_movement_speed_multiplier"):
			target.call("set_movement_speed_multiplier", 1.0 - slow_amount)
	
	func remove(target: DamageableEntity):
		if target.has_method("set_movement_speed_multiplier"):
			target.call("set_movement_speed_multiplier", 1.0)

static func create_damage_info(amount: float, type: int = DamageType.PHYSICAL) -> DamageInfo:
	return DamageInfo.new(amount, type)

static func calculate_critical_chance(attacker_luck: float, target_evasion: float = 0.0) -> bool:
	var crit_chance = 0.05 + (attacker_luck * 0.01)
	crit_chance -= target_evasion * 0.005
	return randf() < crit_chance

static func get_damage_type_name(type: int) -> String:
	match type:
		DamageType.PHYSICAL: return "Physical"
		DamageType.FIRE: return "Fire"
		DamageType.ICE: return "Ice"
		DamageType.ELECTRIC: return "Electric"
		DamageType.POISON: return "Poison"
		DamageType.PSYCHIC: return "Psychic"
		DamageType.HOLY: return "Holy"
		DamageType.DARK: return "Dark"
		_: return "Unknown"