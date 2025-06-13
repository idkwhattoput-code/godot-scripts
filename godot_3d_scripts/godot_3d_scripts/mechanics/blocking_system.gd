extends Node

signal block_started
signal block_ended
signal block_successful(damage_blocked)
signal block_broken
signal parry_successful(attacker)
signal stamina_depleted

export var enabled: bool = true
export var block_damage_reduction: float = 0.8
export var parry_window: float = 0.3
export var parry_damage_multiplier: float = 1.5
export var block_angle: float = 120.0
export var stamina_enabled: bool = true
export var max_block_stamina: float = 100.0
export var stamina_drain_rate: float = 10.0
export var stamina_regen_rate: float = 15.0
export var stamina_cost_per_hit: float = 20.0
export var perfect_block_window: float = 0.1
export var perfect_block_stamina_bonus: float = 10.0
export var block_break_threshold: float = 150.0
export var counter_attack_enabled: bool = true
export var counter_attack_window: float = 0.5
export var block_movement_speed: float = 0.5
export var can_block_while_moving: bool = true
export var directional_blocking: bool = false
export var auto_face_attacker: bool = true

var is_blocking: bool = false
var is_parrying: bool = false
var current_block_stamina: float
var block_time: float = 0.0
var parry_timer: float = 0.0
var counter_window_active: bool = false
var counter_timer: float = 0.0
var accumulated_damage: float = 0.0
var recent_attackers: Array = []
var block_direction: Vector3 = Vector3.FORWARD

var player: Spatial
var shield_visual: Spatial
var animation_player: AnimationPlayer
var audio_player: AudioStreamPlayer3D
var block_effect: CPUParticles

onready var block_sounds: Array = []
onready var parry_sounds: Array = []
onready var break_sounds: Array = []

func _ready():
	current_block_stamina = max_block_stamina
	set_process(false)

func initialize(player_node: Spatial, shield: Spatial = null, anim_player: AnimationPlayer = null):
	player = player_node
	shield_visual = shield
	animation_player = anim_player
	
	if player:
		player.add_to_group("can_block")
	
	_setup_audio()
	_setup_block_effect()
	set_process(true)

func _process(delta):
	if not enabled:
		return
	
	if is_blocking:
		block_time += delta
		
		if parry_timer > 0:
			parry_timer -= delta
			if parry_timer <= 0:
				is_parrying = false
		
		if stamina_enabled:
			current_block_stamina -= stamina_drain_rate * delta
			if current_block_stamina <= 0:
				_break_block()
				emit_signal("stamina_depleted")
		
		if counter_window_active:
			counter_timer -= delta
			if counter_timer <= 0:
				counter_window_active = false
	else:
		if stamina_enabled and current_block_stamina < max_block_stamina:
			current_block_stamina = min(max_block_stamina, current_block_stamina + stamina_regen_rate * delta)
		
		accumulated_damage = max(0, accumulated_damage - 50 * delta)

func start_block():
	if not _can_block():
		return false
	
	is_blocking = true
	block_time = 0.0
	parry_timer = parry_window
	is_parrying = true
	recent_attackers.clear()
	
	if directional_blocking:
		_update_block_direction()
	
	_play_block_animation("block_start")
	_update_shield_visual(true)
	
	if player.has_method("set_movement_speed_multiplier"):
		player.set_movement_speed_multiplier(block_movement_speed)
	
	emit_signal("block_started")
	return true

func end_block():
	if not is_blocking:
		return
	
	is_blocking = false
	is_parrying = false
	block_time = 0.0
	parry_timer = 0.0
	counter_window_active = false
	
	_play_block_animation("block_end")
	_update_shield_visual(false)
	
	if player.has_method("set_movement_speed_multiplier"):
		player.set_movement_speed_multiplier(1.0)
	
	emit_signal("block_ended")

func _can_block() -> bool:
	if not enabled:
		return false
	
	if stamina_enabled and current_block_stamina <= 0:
		return false
	
	if not can_block_while_moving and player.has_method("is_moving"):
		if player.is_moving():
			return false
	
	return true

func process_incoming_damage(damage: float, attacker: Node, attack_direction: Vector3) -> float:
	if not is_blocking:
		return damage
	
	if not _is_attack_blockable(attack_direction):
		return damage
	
	recent_attackers.append(attacker)
	
	if is_parrying:
		return _process_parry(damage, attacker)
	elif block_time <= perfect_block_window:
		return _process_perfect_block(damage, attacker)
	else:
		return _process_normal_block(damage, attacker)

func _is_attack_blockable(attack_direction: Vector3) -> bool:
	if not directional_blocking:
		return true
	
	var to_attacker = -attack_direction.normalized()
	var block_forward = block_direction if directional_blocking else -player.global_transform.basis.z
	
	var angle = rad2deg(acos(block_forward.dot(to_attacker)))
	return angle <= block_angle / 2.0

func _process_parry(damage: float, attacker: Node) -> float:
	emit_signal("parry_successful", attacker)
	
	_play_parry_sound()
	_play_block_animation("parry")
	_spawn_parry_effect()
	
	if stamina_enabled:
		current_block_stamina = min(max_block_stamina, current_block_stamina + perfect_block_stamina_bonus)
	
	counter_window_active = true
	counter_timer = counter_attack_window
	
	if attacker.has_method("stun"):
		attacker.stun(0.5)
	
	if attacker.has_method("take_damage") and counter_attack_enabled:
		attacker.take_damage(damage * parry_damage_multiplier * 0.5, player.global_transform.origin, player)
	
	return 0.0

func _process_perfect_block(damage: float, attacker: Node) -> float:
	var blocked_damage = damage * 0.95
	
	emit_signal("block_successful", blocked_damage)
	
	_play_block_sound(0.5)
	_spawn_block_effect(player.global_transform.origin)
	
	if stamina_enabled:
		current_block_stamina = min(max_block_stamina, current_block_stamina + perfect_block_stamina_bonus * 0.5)
	
	counter_window_active = true
	counter_timer = counter_attack_window * 0.75
	
	return damage * 0.05

func _process_normal_block(damage: float, attacker: Node) -> float:
	var blocked_damage = damage * block_damage_reduction
	var remaining_damage = damage * (1.0 - block_damage_reduction)
	
	accumulated_damage += damage
	
	if stamina_enabled:
		current_block_stamina -= stamina_cost_per_hit
		if current_block_stamina <= 0:
			_break_block()
			return damage
	
	if accumulated_damage >= block_break_threshold:
		_break_block()
		return damage
	
	emit_signal("block_successful", blocked_damage)
	
	_play_block_sound(1.0)
	_spawn_block_effect(player.global_transform.origin)
	_apply_block_knockback(attacker, damage)
	
	if auto_face_attacker and attacker:
		_face_attacker(attacker)
	
	return remaining_damage

func _break_block():
	end_block()
	
	emit_signal("block_broken")
	
	_play_break_sound()
	_play_block_animation("block_break")
	
	if player.has_method("stun"):
		player.stun(1.0)
	
	accumulated_damage = 0.0
	current_block_stamina = 0.0

func _apply_block_knockback(attacker: Node, damage: float):
	if not player.has_method("apply_impulse"):
		return
	
	var knockback_direction = (player.global_transform.origin - attacker.global_transform.origin).normalized()
	var knockback_force = min(damage * 0.1, 5.0)
	
	player.apply_impulse(knockback_direction * knockback_force)

func _face_attacker(attacker: Node):
	if not player:
		return
	
	var to_attacker = (attacker.global_transform.origin - player.global_transform.origin)
	to_attacker.y = 0
	to_attacker = to_attacker.normalized()
	
	var new_transform = player.global_transform
	new_transform.basis = new_transform.basis.slerp(
		Transform().looking_at(-to_attacker, Vector3.UP).basis,
		0.3
	)
	player.global_transform = new_transform

func _update_block_direction():
	if not directional_blocking or not player:
		return
	
	block_direction = -player.global_transform.basis.z

func can_counter_attack() -> bool:
	return counter_window_active and counter_attack_enabled

func perform_counter_attack():
	if not can_counter_attack():
		return false
	
	counter_window_active = false
	_play_block_animation("counter_attack")
	
	return true

func _update_shield_visual(blocking: bool):
	if not shield_visual:
		return
	
	shield_visual.visible = blocking

func _play_block_animation(anim_name: String):
	if not animation_player:
		return
	
	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name)

func _setup_audio():
	if not audio_player:
		audio_player = AudioStreamPlayer3D.new()
		if player:
			player.add_child(audio_player)

func _setup_block_effect():
	block_effect = CPUParticles.new()
	block_effect.emitting = false
	block_effect.amount = 20
	block_effect.lifetime = 0.3
	block_effect.one_shot = true
	block_effect.initial_velocity = 5.0
	block_effect.scale_amount = 0.5
	
	if player:
		player.add_child(block_effect)

func _spawn_block_effect(position: Vector3):
	if block_effect:
		block_effect.global_transform.origin = position
		block_effect.restart()

func _spawn_parry_effect():
	if block_effect:
		block_effect.amount = 40
		block_effect.initial_velocity = 10.0
		block_effect.restart()
		block_effect.amount = 20

func _play_block_sound(pitch_scale: float = 1.0):
	if block_sounds.size() > 0 and audio_player:
		audio_player.stream = block_sounds[randi() % block_sounds.size()]
		audio_player.pitch_scale = pitch_scale * (0.9 + randf() * 0.2)
		audio_player.play()

func _play_parry_sound():
	if parry_sounds.size() > 0 and audio_player:
		audio_player.stream = parry_sounds[randi() % parry_sounds.size()]
		audio_player.pitch_scale = 1.2
		audio_player.play()

func _play_break_sound():
	if break_sounds.size() > 0 and audio_player:
		audio_player.stream = break_sounds[randi() % break_sounds.size()]
		audio_player.play()

func get_block_stamina_percentage() -> float:
	return (current_block_stamina / max_block_stamina) * 100.0

func restore_stamina(amount: float):
	current_block_stamina = min(max_block_stamina, current_block_stamina + amount)

func set_blocking_enabled(enabled_state: bool):
	enabled = enabled_state
	if not enabled and is_blocking:
		end_block()