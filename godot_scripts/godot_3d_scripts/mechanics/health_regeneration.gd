extends Node

class_name HealthRegeneration

signal regeneration_started()
signal regeneration_stopped()
signal health_regenerated(amount)
signal regeneration_triggered(source)

export var enabled: bool = true
export var base_regen_rate: float = 1.0
export var regen_delay: float = 3.0
export var combat_regen_multiplier: float = 0.0
export var out_of_combat_multiplier: float = 1.5
export var max_regen_percentage: float = 1.0
export var regen_tick_interval: float = 0.5
export var require_stationary: bool = false
export var stationary_threshold: float = 0.5
export var require_safe_zone: bool = false
export var visual_effect: bool = true
export var regen_sound: AudioStream
export var particle_effect: PackedScene

var current_regen_rate: float = 0.0
var is_regenerating: bool = false
var time_since_damage: float = 0.0
var in_combat: bool = false
var in_safe_zone: bool = false
var regen_sources: Dictionary = {}
var regen_modifiers: Array = []
var character_stats: Node = null
var last_position: Vector3 = Vector3.ZERO
var tick_timer: float = 0.0

onready var audio_player = AudioStreamPlayer.new()
onready var effect_instance = null

func _ready():
	add_child(audio_player)
	audio_player.bus = "SFX"
	set_process(false)

func initialize(stats_node: Node):
	character_stats = stats_node
	
	if character_stats.has_signal("health_changed"):
		character_stats.connect("health_changed", self, "_on_health_changed")
	
	if character_stats.has_signal("damage_taken"):
		character_stats.connect("damage_taken", self, "_on_damage_taken")
	
	set_process(enabled)

func _process(delta):
	if not enabled or not character_stats:
		return
	
	update_combat_status(delta)
	update_stationary_check()
	update_regeneration(delta)

func update_combat_status(delta):
	if in_combat:
		time_since_damage += delta
		if time_since_damage >= regen_delay:
			exit_combat()
	
	update_regen_rate()

func update_stationary_check():
	if not require_stationary or not character_stats.get_parent():
		return
	
	var current_pos = character_stats.get_parent().global_transform.origin
	var movement = current_pos.distance_to(last_position)
	
	if movement > stationary_threshold:
		last_position = current_pos

func update_regeneration(delta):
	if not can_regenerate():
		if is_regenerating:
			stop_regeneration()
		return
	
	if not is_regenerating:
		start_regeneration()
	
	tick_timer += delta
	if tick_timer >= regen_tick_interval:
		tick_timer = 0.0
		apply_regeneration()

func can_regenerate() -> bool:
	if not character_stats:
		return false
	
	if character_stats.current_health >= character_stats.max_health * max_regen_percentage:
		return false
	
	if character_stats.is_dead:
		return false
	
	if in_combat and combat_regen_multiplier <= 0:
		return false
	
	if require_safe_zone and not in_safe_zone:
		return false
	
	if require_stationary:
		var current_pos = character_stats.get_parent().global_transform.origin
		if current_pos.distance_to(last_position) > stationary_threshold:
			return false
	
	return current_regen_rate > 0

func start_regeneration():
	is_regenerating = true
	emit_signal("regeneration_started")
	
	if visual_effect and particle_effect:
		create_visual_effect()
	
	if regen_sound:
		audio_player.stream = regen_sound
		audio_player.play()

func stop_regeneration():
	is_regenerating = false
	emit_signal("regeneration_stopped")
	
	if effect_instance:
		remove_visual_effect()
	
	if audio_player.playing:
		audio_player.stop()

func apply_regeneration():
	var regen_amount = calculate_regen_amount()
	
	if regen_amount > 0:
		character_stats.heal(regen_amount)
		emit_signal("health_regenerated", regen_amount)

func calculate_regen_amount() -> float:
	var tick_rate = current_regen_rate * regen_tick_interval
	var final_amount = tick_rate
	
	for modifier in regen_modifiers:
		if modifier.type == "multiplicative":
			final_amount *= modifier.value
		elif modifier.type == "additive":
			final_amount += modifier.value
	
	var remaining_health = character_stats.max_health * max_regen_percentage - character_stats.current_health
	final_amount = min(final_amount, remaining_health)
	
	return final_amount

func update_regen_rate():
	current_regen_rate = base_regen_rate
	
	if in_combat:
		current_regen_rate *= combat_regen_multiplier
	else:
		current_regen_rate *= out_of_combat_multiplier
	
	for source in regen_sources:
		current_regen_rate += regen_sources[source]
	
	if character_stats and character_stats.has("health_regen_rate"):
		current_regen_rate += character_stats.health_regen_rate

func _on_health_changed(new_health: float, max_health: float):
	if new_health >= max_health * max_regen_percentage and is_regenerating:
		stop_regeneration()

func _on_damage_taken(damage: float):
	enter_combat()

func enter_combat():
	in_combat = true
	time_since_damage = 0.0
	update_regen_rate()

func exit_combat():
	in_combat = false
	update_regen_rate()

func enter_safe_zone():
	in_safe_zone = true
	emit_signal("regeneration_triggered", "safe_zone")

func exit_safe_zone():
	in_safe_zone = false

func add_regen_source(source_name: String, regen_value: float):
	regen_sources[source_name] = regen_value
	update_regen_rate()
	emit_signal("regeneration_triggered", source_name)

func remove_regen_source(source_name: String):
	if source_name in regen_sources:
		regen_sources.erase(source_name)
		update_regen_rate()

func add_regen_modifier(modifier_name: String, value: float, type: String = "multiplicative"):
	var modifier = {
		"name": modifier_name,
		"value": value,
		"type": type
	}
	
	remove_regen_modifier(modifier_name)
	regen_modifiers.append(modifier)

func remove_regen_modifier(modifier_name: String):
	for i in range(regen_modifiers.size() - 1, -1, -1):
		if regen_modifiers[i].name == modifier_name:
			regen_modifiers.remove(i)

func create_visual_effect():
	if not particle_effect or not character_stats.get_parent():
		return
	
	effect_instance = particle_effect.instance()
	character_stats.get_parent().add_child(effect_instance)
	
	if effect_instance.has_method("set_emitting"):
		effect_instance.set_emitting(true)

func remove_visual_effect():
	if effect_instance:
		if effect_instance.has_method("set_emitting"):
			effect_instance.set_emitting(false)
		effect_instance.queue_free()
		effect_instance = null

func apply_instant_regen(amount: float, source: String = "instant"):
	if character_stats:
		character_stats.heal(amount)
		emit_signal("health_regenerated", amount)
		emit_signal("regeneration_triggered", source)

func apply_regen_over_time(amount: float, duration: float, source: String = "hot"):
	var regen_per_second = amount / duration
	add_regen_source(source, regen_per_second)
	
	yield(get_tree().create_timer(duration), "timeout")
	
	remove_regen_source(source)

func set_base_regen_rate(rate: float):
	base_regen_rate = rate
	update_regen_rate()

func get_effective_regen_rate() -> float:
	return current_regen_rate

func get_regen_info() -> Dictionary:
	return {
		"is_regenerating": is_regenerating,
		"current_rate": current_regen_rate,
		"base_rate": base_regen_rate,
		"in_combat": in_combat,
		"sources": regen_sources.duplicate(),
		"modifiers": regen_modifiers.duplicate()
	}

func pause_regeneration():
	set_process(false)

func resume_regeneration():
	set_process(enabled)

func reset():
	in_combat = false
	time_since_damage = 0.0
	regen_sources.clear()
	regen_modifiers.clear()
	tick_timer = 0.0
	update_regen_rate()
	
	if is_regenerating:
		stop_regeneration()