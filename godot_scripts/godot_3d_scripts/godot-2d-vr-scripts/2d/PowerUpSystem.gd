extends Node2D

class_name PowerUpSystem

signal power_up_activated(power_up_name: String)
signal power_up_deactivated(power_up_name: String)
signal power_up_collected(power_up_name: String)

@export var max_active_power_ups: int = 3
@export var show_ui_feedback: bool = true

var active_power_ups: Dictionary = {}
var power_up_timers: Dictionary = {}
var player_reference: Node2D

@onready var ui_container: Control = $UIContainer
@onready var collection_sound: AudioStreamPlayer2D = $CollectionSound
@onready var activation_sound: AudioStreamPlayer2D = $ActivationSound

class PowerUp extends Resource:
	@export var id: String
	@export var name: String
	@export var description: String
	@export var icon: Texture2D
	@export var duration: float = 10.0
	@export var is_permanent: bool = false
	@export var stackable: bool = false
	@export var max_stacks: int = 1
	@export var collect_sound: AudioStream
	@export var activate_sound: AudioStream
	@export var deactivate_sound: AudioStream
	@export var particle_effect: PackedScene
	@export var effects: Array[PowerUpEffect] = []

class PowerUpEffect extends Resource:
	@export var type: EffectType
	@export var value: float
	@export var is_multiplier: bool = false

enum EffectType {
	SPEED_BOOST,
	JUMP_BOOST,
	DAMAGE_BOOST,
	HEALTH_BOOST,
	INVINCIBILITY,
	DOUBLE_JUMP,
	DASH_BOOST,
	MAGNET_COINS,
	SLOW_TIME,
	SHIELD,
	FIRE_IMMUNITY,
	WATER_BREATHING,
	WALL_JUMP,
	GLIDE,
	TELEPORT
}

func _ready():
	if not player_reference:
		player_reference = get_tree().get_first_node_in_group("player")
	
	setup_ui()

func setup_ui():
	if not ui_container:
		return
	
	ui_container.position = Vector2(10, 10)

func collect_power_up(power_up: PowerUp) -> bool:
	if not power_up:
		return false
	
	if not can_collect_power_up(power_up):
		return false
	
	if power_up.collect_sound and collection_sound:
		collection_sound.stream = power_up.collect_sound
		collection_sound.play()
	
	emit_signal("power_up_collected", power_up.name)
	
	activate_power_up(power_up)
	return true

func can_collect_power_up(power_up: PowerUp) -> bool:
	if power_up.stackable and active_power_ups.has(power_up.id):
		var current_stacks = active_power_ups[power_up.id].stacks
		return current_stacks < power_up.max_stacks
	
	if not power_up.stackable and active_power_ups.has(power_up.id):
		return false
	
	if active_power_ups.size() >= max_active_power_ups and not active_power_ups.has(power_up.id):
		return false
	
	return true

func activate_power_up(power_up: PowerUp):
	if active_power_ups.has(power_up.id) and power_up.stackable:
		var existing_data = active_power_ups[power_up.id]
		existing_data.stacks = min(existing_data.stacks + 1, power_up.max_stacks)
		refresh_power_up_timer(power_up)
	else:
		var power_up_data = {
			"power_up": power_up,
			"stacks": 1,
			"start_time": Time.get_time_dict_from_system()
		}
		active_power_ups[power_up.id] = power_up_data
		
		apply_power_up_effects(power_up, true)
		
		if not power_up.is_permanent:
			create_power_up_timer(power_up)
	
	if power_up.activate_sound and activation_sound:
		activation_sound.stream = power_up.activate_sound
		activation_sound.play()
	
	create_visual_effects(power_up)
	update_ui()
	emit_signal("power_up_activated", power_up.name)

func deactivate_power_up(power_up_id: String):
	if not active_power_ups.has(power_up_id):
		return
	
	var power_up_data = active_power_ups[power_up_id]
	var power_up = power_up_data.power_up
	
	apply_power_up_effects(power_up, false)
	
	if power_up.deactivate_sound and activation_sound:
		activation_sound.stream = power_up.deactivate_sound
		activation_sound.play()
	
	active_power_ups.erase(power_up_id)
	
	if power_up_timers.has(power_up_id):
		power_up_timers[power_up_id].queue_free()
		power_up_timers.erase(power_up_id)
	
	update_ui()
	emit_signal("power_up_deactivated", power_up.name)

func apply_power_up_effects(power_up: PowerUp, activate: bool):
	if not player_reference:
		return
	
	for effect in power_up.effects:
		apply_single_effect(effect, activate, power_up.stackable)

func apply_single_effect(effect: PowerUpEffect, activate: bool, is_stackable: bool):
	if not player_reference:
		return
	
	var multiplier = 1 if activate else -1
	var effect_value = effect.value * multiplier
	
	if is_stackable and activate:
		effect_value *= get_effect_stack_count(effect.type)
	
	match effect.type:
		EffectType.SPEED_BOOST:
			modify_player_speed(effect_value, effect.is_multiplier)
		EffectType.JUMP_BOOST:
			modify_player_jump(effect_value, effect.is_multiplier)
		EffectType.DAMAGE_BOOST:
			modify_player_damage(effect_value, effect.is_multiplier)
		EffectType.HEALTH_BOOST:
			modify_player_health(effect_value, activate)
		EffectType.INVINCIBILITY:
			set_player_invincible(activate)
		EffectType.DOUBLE_JUMP:
			set_player_double_jump(activate)
		EffectType.DASH_BOOST:
			modify_player_dash(effect_value, effect.is_multiplier)
		EffectType.MAGNET_COINS:
			set_coin_magnet(activate, effect_value)
		EffectType.SLOW_TIME:
			modify_time_scale(effect_value if activate else 1.0)
		EffectType.SHIELD:
			set_player_shield(activate)
		EffectType.FIRE_IMMUNITY:
			set_element_immunity("fire", activate)
		EffectType.WATER_BREATHING:
			set_element_immunity("water", activate)
		EffectType.WALL_JUMP:
			set_player_wall_jump(activate)
		EffectType.GLIDE:
			set_player_glide(activate)
		EffectType.TELEPORT:
			enable_player_teleport(activate)

func get_effect_stack_count(effect_type: EffectType) -> int:
	var count = 0
	for power_up_data in active_power_ups.values():
		var power_up = power_up_data.power_up
		for effect in power_up.effects:
			if effect.type == effect_type:
				count += power_up_data.stacks
	return count

func modify_player_speed(value: float, is_multiplier: bool):
	if player_reference.has_method("modify_speed"):
		player_reference.modify_speed(value, is_multiplier)

func modify_player_jump(value: float, is_multiplier: bool):
	if player_reference.has_method("modify_jump_strength"):
		player_reference.modify_jump_strength(value, is_multiplier)

func modify_player_damage(value: float, is_multiplier: bool):
	if player_reference.has_method("modify_damage"):
		player_reference.modify_damage(value, is_multiplier)

func modify_player_health(value: float, activate: bool):
	if player_reference.has_method("modify_max_health") and activate:
		player_reference.modify_max_health(value)
	elif player_reference.has_method("heal") and activate:
		player_reference.heal(value)

func set_player_invincible(active: bool):
	if player_reference.has_method("set_invincible"):
		player_reference.set_invincible(active)

func set_player_double_jump(active: bool):
	if player_reference.has_method("set_double_jump_enabled"):
		player_reference.set_double_jump_enabled(active)

func modify_player_dash(value: float, is_multiplier: bool):
	if player_reference.has_method("modify_dash"):
		player_reference.modify_dash(value, is_multiplier)

func set_coin_magnet(active: bool, range_value: float):
	if player_reference.has_method("set_coin_magnet"):
		player_reference.set_coin_magnet(active, range_value)

func modify_time_scale(scale: float):
	Engine.time_scale = scale

func set_player_shield(active: bool):
	if player_reference.has_method("set_shield"):
		player_reference.set_shield(active)

func set_element_immunity(element: String, active: bool):
	if player_reference.has_method("set_element_immunity"):
		player_reference.set_element_immunity(element, active)

func set_player_wall_jump(active: bool):
	if player_reference.has_method("set_wall_jump_enabled"):
		player_reference.set_wall_jump_enabled(active)

func set_player_glide(active: bool):
	if player_reference.has_method("set_glide_enabled"):
		player_reference.set_glide_enabled(active)

func enable_player_teleport(active: bool):
	if player_reference.has_method("set_teleport_enabled"):
		player_reference.set_teleport_enabled(active)

func create_power_up_timer(power_up: PowerUp):
	var timer = Timer.new()
	timer.wait_time = power_up.duration
	timer.one_shot = true
	timer.timeout.connect(_on_power_up_expired.bind(power_up.id))
	add_child(timer)
	timer.start()
	power_up_timers[power_up.id] = timer

func refresh_power_up_timer(power_up: PowerUp):
	if power_up_timers.has(power_up.id):
		power_up_timers[power_up.id].start(power_up.duration)

func create_visual_effects(power_up: PowerUp):
	if power_up.particle_effect and player_reference:
		var effect = power_up.particle_effect.instantiate()
		player_reference.add_child(effect)

func update_ui():
	if not show_ui_feedback or not ui_container:
		return
	
	for child in ui_container.get_children():
		child.queue_free()
	
	for power_up_data in active_power_ups.values():
		create_power_up_ui_element(power_up_data)

func create_power_up_ui_element(power_up_data: Dictionary):
	var power_up = power_up_data.power_up
	
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(64, 64)
	
	var texture_rect = TextureRect.new()
	texture_rect.texture = power_up.icon
	texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	panel.add_child(texture_rect)
	
	if power_up_data.stacks > 1:
		var stack_label = Label.new()
		stack_label.text = str(power_up_data.stacks)
		stack_label.position = Vector2(40, 40)
		panel.add_child(stack_label)
	
	if not power_up.is_permanent and power_up_timers.has(power_up.id):
		var timer = power_up_timers[power_up.id]
		var progress_bar = ProgressBar.new()
		progress_bar.max_value = power_up.duration
		progress_bar.value = timer.time_left
		progress_bar.size = Vector2(60, 8)
		progress_bar.position = Vector2(2, 54)
		panel.add_child(progress_bar)
	
	ui_container.add_child(panel)

func get_active_power_ups() -> Array:
	return active_power_ups.values()

func has_power_up(power_up_id: String) -> bool:
	return active_power_ups.has(power_up_id)

func get_power_up_stacks(power_up_id: String) -> int:
	if active_power_ups.has(power_up_id):
		return active_power_ups[power_up_id].stacks
	return 0

func clear_all_power_ups():
	for power_up_id in active_power_ups.keys():
		deactivate_power_up(power_up_id)

func extend_power_up_duration(power_up_id: String, additional_time: float):
	if power_up_timers.has(power_up_id):
		var timer = power_up_timers[power_up_id]
		timer.start(timer.time_left + additional_time)

func _on_power_up_expired(power_up_id: String):
	deactivate_power_up(power_up_id)

func save_power_ups() -> Dictionary:
	var save_data = {}
	for power_up_id in active_power_ups.keys():
		var power_up_data = active_power_ups[power_up_id]
		var timer_time_left = 0.0
		if power_up_timers.has(power_up_id):
			timer_time_left = power_up_timers[power_up_id].time_left
		
		save_data[power_up_id] = {
			"stacks": power_up_data.stacks,
			"time_left": timer_time_left,
			"start_time": power_up_data.start_time
		}
	return save_data

func load_power_ups(save_data: Dictionary, power_up_database: Dictionary):
	clear_all_power_ups()
	
	for power_up_id in save_data.keys():
		if power_up_database.has(power_up_id):
			var power_up = power_up_database[power_up_id]
			var data = save_data[power_up_id]
			
			var power_up_data = {
				"power_up": power_up,
				"stacks": data.get("stacks", 1),
				"start_time": data.get("start_time", Time.get_time_dict_from_system())
			}
			active_power_ups[power_up_id] = power_up_data
			
			apply_power_up_effects(power_up, true)
			
			var time_left = data.get("time_left", 0.0)
			if time_left > 0 and not power_up.is_permanent:
				var timer = Timer.new()
				timer.wait_time = time_left
				timer.one_shot = true
				timer.timeout.connect(_on_power_up_expired.bind(power_up_id))
				add_child(timer)
				timer.start()
				power_up_timers[power_up_id] = timer
	
	update_ui()