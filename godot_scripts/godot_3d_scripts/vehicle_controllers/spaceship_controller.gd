extends RigidBody3D

signal shields_depleted
signal hull_damaged(damage: float)
signal warp_engaged
signal warp_disengaged
signal docked(station: Node3D)

@export_group("Propulsion")
@export var main_thrust_force: float = 50000.0
@export var maneuvering_thrust: float = 10000.0
@export var rotation_thrust: float = 1000.0
@export var max_velocity: float = 500.0
@export var boost_multiplier: float = 2.0
@export var inertia_dampening: float = 0.5

@export_group("Warp Drive")
@export var has_warp_drive: bool = true
@export var warp_charge_time: float = 3.0
@export var warp_speed_multiplier: float = 10.0
@export var warp_fuel_consumption: float = 10.0
@export var warp_cooldown: float = 5.0

@export_group("Systems")
@export var shield_capacity: float = 100.0
@export var shield_recharge_rate: float = 5.0
@export var hull_integrity: float = 100.0
@export var power_capacity: float = 1000.0
@export var power_generation_rate: float = 10.0

@export_group("Weapons")
@export var weapon_hardpoints: Array[Node3D] = []
@export var turret_nodes: Array[Node3D] = []
@export var targeting_range: float = 1000.0
@export var auto_target: bool = true

@export_group("Life Support")
@export var oxygen_capacity: float = 100.0
@export var oxygen_consumption_rate: float = 0.1
@export var gravity_generator: bool = true
@export var artificial_gravity_strength: float = 9.8

@export_group("Visual Effects")
@export var engine_particles: Array[CPUParticles3D] = []
@export var shield_mesh: MeshInstance3D
@export var warp_effect: Node3D
@export var damage_particles: CPUParticles3D

var current_shields: float
var current_power: float
var current_oxygen: float
var is_warping: bool = false
var warp_charge: float = 0.0
var warp_cooldown_timer: float = 0.0

var thrust_input: Vector3 = Vector3.ZERO
var rotation_input: Vector3 = Vector3.ZERO
var boost_active: bool = false
var dampeners_active: bool = true

var current_target: Node3D = null
var docked_station: Node3D = null
var system_failures: Dictionary = {}

var audio_players: Dictionary = {}

func _ready():
	current_shields = shield_capacity
	current_power = power_capacity
	current_oxygen = oxygen_capacity
	
	gravity_scale = 0.0
	linear_damp = 0.0
	angular_damp = 1.0
	
	_setup_audio()
	_setup_shield_visual()
	
func _setup_audio():
	var engine_audio = AudioStreamPlayer3D.new()
	engine_audio.name = "EngineAudio"
	add_child(engine_audio)
	audio_players["engine"] = engine_audio
	
	var shield_audio = AudioStreamPlayer3D.new()
	shield_audio.name = "ShieldAudio"
	add_child(shield_audio)
	audio_players["shield"] = shield_audio
	
func _setup_shield_visual():
	if shield_mesh:
		shield_mesh.visible = current_shields > 0
		var material = shield_mesh.get_surface_override_material(0)
		if material:
			material.set_shader_parameter("shield_strength", current_shields / shield_capacity)
			
func _physics_process(delta):
	_process_systems(delta)
	_apply_thrust(delta)
	_apply_rotation(delta)
	_apply_inertia_dampening(delta)
	_process_warp(delta)
	_update_visuals(delta)
	_check_velocity_limits()
	
func _process_systems(delta):
	current_power = min(current_power + power_generation_rate * delta, power_capacity)
	
	if current_shields < shield_capacity and current_power > 0:
		var recharge_amount = min(shield_recharge_rate * delta, current_power)
		current_shields = min(current_shields + recharge_amount, shield_capacity)
		current_power -= recharge_amount
		
	if gravity_generator and current_power > 0:
		current_power -= 1.0 * delta
		
	current_oxygen = max(0, current_oxygen - oxygen_consumption_rate * delta)
	
	if warp_cooldown_timer > 0:
		warp_cooldown_timer -= delta
		
func _apply_thrust(delta):
	if docked_station:
		return
		
	var thrust_multiplier = boost_active ? boost_multiplier : 1.0
	
	if boost_active and current_power > 0:
		current_power -= 5.0 * delta
		
	var forward_thrust = -transform.basis.z * thrust_input.z * main_thrust_force * thrust_multiplier
	var lateral_thrust = transform.basis.x * thrust_input.x * maneuvering_thrust
	var vertical_thrust = transform.basis.y * thrust_input.y * maneuvering_thrust
	
	var total_thrust = forward_thrust + lateral_thrust + vertical_thrust
	
	if is_warping:
		total_thrust *= warp_speed_multiplier
		
	apply_central_force(total_thrust * delta)
	
	for particle in engine_particles:
		if particle:
			particle.emitting = thrust_input.length() > 0.1
			particle.amount_ratio = thrust_input.length()
			
func _apply_rotation(delta):
	if docked_station:
		return
		
	var pitch_torque = transform.basis.x * rotation_input.x * rotation_thrust
	var yaw_torque = transform.basis.y * rotation_input.y * rotation_thrust
	var roll_torque = transform.basis.z * rotation_input.z * rotation_thrust
	
	apply_torque((pitch_torque + yaw_torque + roll_torque) * delta)
	
func _apply_inertia_dampening(delta):
	if not dampeners_active or docked_station:
		return
		
	linear_velocity = linear_velocity.lerp(Vector3.ZERO, inertia_dampening * delta)
	angular_velocity = angular_velocity.lerp(Vector3.ZERO, inertia_dampening * 2.0 * delta)
	
func _process_warp(delta):
	if not has_warp_drive:
		return
		
	if is_warping:
		current_power -= warp_fuel_consumption * delta
		if current_power <= 0:
			disengage_warp()
			
func _check_velocity_limits():
	if linear_velocity.length() > max_velocity and not is_warping:
		linear_velocity = linear_velocity.normalized() * max_velocity
		
func _update_visuals(delta):
	if shield_mesh and shield_mesh.get_surface_override_material(0):
		shield_mesh.visible = current_shields > 0
		var mat = shield_mesh.get_surface_override_material(0)
		mat.set_shader_parameter("shield_strength", current_shields / shield_capacity)
		
	if warp_effect:
		warp_effect.visible = is_warping
		
func set_thrust_input(input: Vector3):
	thrust_input = input.limit_length(1.0)
	
func set_rotation_input(input: Vector3):
	rotation_input = input.limit_length(1.0)
	
func engage_warp():
	if not has_warp_drive or is_warping or warp_cooldown_timer > 0:
		return false
		
	if current_power < warp_fuel_consumption * warp_charge_time:
		return false
		
	is_warping = true
	warp_engaged.emit()
	
	if warp_effect:
		warp_effect.visible = true
		
	return true
	
func disengage_warp():
	if not is_warping:
		return
		
	is_warping = false
	warp_cooldown_timer = warp_cooldown
	warp_disengaged.emit()
	
	if warp_effect:
		warp_effect.visible = false
		
func take_damage(amount: float, bypass_shields: bool = false):
	if not bypass_shields and current_shields > 0:
		var shield_damage = min(amount, current_shields)
		current_shields -= shield_damage
		amount -= shield_damage
		
		if current_shields <= 0:
			shields_depleted.emit()
			
		if audio_players.has("shield"):
			audio_players["shield"].play()
			
	if amount > 0:
		hull_integrity -= amount
		hull_damaged.emit(amount)
		
		if damage_particles:
			damage_particles.emitting = true
			damage_particles.amount_ratio = 1.0 - (hull_integrity / 100.0)
			
func repair_hull(amount: float):
	hull_integrity = min(hull_integrity + amount, 100.0)
	
func recharge_shields(amount: float):
	current_shields = min(current_shields + amount, shield_capacity)
	
func dock_with_station(station: Node3D):
	if not station or docked_station:
		return
		
	docked_station = station
	freeze = true
	docked.emit(station)
	
func undock():
	if not docked_station:
		return
		
	freeze = false
	docked_station = null
	
func set_dampeners(enabled: bool):
	dampeners_active = enabled
	
func toggle_boost():
	boost_active = not boost_active
	
func fire_weapon(hardpoint_index: int):
	if hardpoint_index >= 0 and hardpoint_index < weapon_hardpoints.size():
		var hardpoint = weapon_hardpoints[hardpoint_index]
		if hardpoint and hardpoint.has_method("fire"):
			hardpoint.fire(current_target)
			
func acquire_target(target: Node3D):
	if target and global_position.distance_to(target.global_position) <= targeting_range:
		current_target = target
		return true
	return false
	
func get_nearest_hostile() -> Node3D:
	var hostiles = get_tree().get_nodes_in_group("hostile")
	var nearest = null
	var min_distance = targeting_range
	
	for hostile in hostiles:
		var distance = global_position.distance_to(hostile.global_position)
		if distance < min_distance:
			min_distance = distance
			nearest = hostile
			
	return nearest
	
func get_ship_status() -> Dictionary:
	return {
		"shields": current_shields / shield_capacity,
		"hull": hull_integrity / 100.0,
		"power": current_power / power_capacity,
		"oxygen": current_oxygen / oxygen_capacity,
		"velocity": linear_velocity.length(),
		"is_warping": is_warping,
		"docked": docked_station != null
	}