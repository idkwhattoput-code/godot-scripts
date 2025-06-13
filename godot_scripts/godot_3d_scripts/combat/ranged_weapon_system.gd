extends Node3D

signal shot_fired(projectile: Node3D)
signal reload_started
signal reload_finished
signal ammo_changed(current: int, max: int)
signal weapon_overheated
signal target_acquired(target: Node3D)

@export_group("Weapon Stats")
@export var damage: float = 25.0
@export var fire_rate: float = 5.0
@export var projectile_speed: float = 50.0
@export var effective_range: float = 100.0
@export var spread_angle: float = 2.0
@export var projectile_scene: PackedScene

@export_group("Ammunition")
@export var magazine_size: int = 30
@export var total_ammo: int = 120
@export var reload_time: float = 2.0
@export var infinite_ammo: bool = false
@export var ammo_type: String = "standard"

@export_group("Firing Modes")
@export var firing_modes: Array[String] = ["semi", "auto", "burst"]
@export var current_firing_mode: int = 0
@export var burst_count: int = 3
@export var burst_delay: float = 0.1

@export_group("Recoil")
@export var recoil_force: float = 5.0
@export var recoil_recovery_speed: float = 10.0
@export var max_recoil: float = 15.0
@export var recoil_pattern: Curve

@export_group("Heat System")
@export var uses_heat_system: bool = false
@export var heat_per_shot: float = 10.0
@export var cooling_rate: float = 20.0
@export var overheat_threshold: float = 100.0
@export var overheat_cooldown: float = 3.0

@export_group("Targeting")
@export var auto_aim_enabled: bool = false
@export var auto_aim_angle: float = 10.0
@export var target_lock_time: float = 0.5
@export var targeting_laser: RayCast3D

@export_group("Visual Effects")
@export var muzzle_flash: GPUParticles3D
@export var shell_ejection: CPUParticles3D
@export var weapon_model: Node3D
@export var scope_camera: Camera3D

var current_ammo: int
var is_reloading: bool = false
var can_fire: bool = true
var fire_timer: float = 0.0
var current_heat: float = 0.0
var is_overheated: bool = false
var current_recoil: Vector3 = Vector3.ZERO
var burst_shots_fired: int = 0
var current_target: Node3D = null
var target_lock_progress: float = 0.0

var audio_players: Dictionary = {}
var projectile_pool: Array = []

func _ready():
	current_ammo = magazine_size
	_setup_audio()
	_initialize_projectile_pool()
	
	if targeting_laser:
		targeting_laser.enabled = false
		
func _setup_audio():
	var fire_audio = AudioStreamPlayer3D.new()
	fire_audio.name = "FireAudio"
	add_child(fire_audio)
	audio_players["fire"] = fire_audio
	
	var reload_audio = AudioStreamPlayer3D.new()
	reload_audio.name = "ReloadAudio"
	add_child(reload_audio)
	audio_players["reload"] = reload_audio
	
func _initialize_projectile_pool():
	if not projectile_scene:
		return
		
	for i in range(50):
		var projectile = projectile_scene.instantiate()
		projectile.set_physics_process(false)
		projectile.visible = false
		get_tree().root.add_child(projectile)
		projectile_pool.append(projectile)
		
func _process(delta):
	_update_fire_timer(delta)
	_update_heat_system(delta)
	_update_recoil(delta)
	_update_targeting(delta)
	
func _update_fire_timer(delta):
	if fire_timer > 0:
		fire_timer -= delta
		can_fire = fire_timer <= 0
		
func _update_heat_system(delta):
	if not uses_heat_system:
		return
		
	if current_heat > 0:
		current_heat = max(0, current_heat - cooling_rate * delta)
		
	if is_overheated and current_heat <= overheat_threshold * 0.5:
		is_overheated = false
		
func _update_recoil(delta):
	current_recoil = current_recoil.lerp(Vector3.ZERO, recoil_recovery_speed * delta)
	
func _update_targeting(delta):
	if not auto_aim_enabled or not targeting_laser:
		return
		
	targeting_laser.force_raycast_update()
	
	if targeting_laser.is_colliding():
		var collider = targeting_laser.get_collider()
		if collider and collider.is_in_group("enemy"):
			if collider == current_target:
				target_lock_progress = min(target_lock_progress + delta, target_lock_time)
				if target_lock_progress >= target_lock_time:
					target_acquired.emit(current_target)
			else:
				current_target = collider
				target_lock_progress = 0
	else:
		current_target = null
		target_lock_progress = 0
		
func fire():
	if not can_fire or is_reloading or is_overheated or current_ammo <= 0:
		return false
		
	match firing_modes[current_firing_mode]:
		"semi":
			_fire_single_shot()
		"auto":
			_fire_single_shot()
		"burst":
			_fire_burst()
			
	return true
	
func _fire_single_shot():
	var projectile = _spawn_projectile()
	if not projectile:
		return
		
	current_ammo -= 1
	fire_timer = 1.0 / fire_rate
	
	_apply_spread(projectile)
	_apply_recoil()
	_add_heat()
	
	shot_fired.emit(projectile)
	ammo_changed.emit(current_ammo, magazine_size)
	
	_play_fire_effects()
	
func _fire_burst():
	if burst_shots_fired >= burst_count:
		burst_shots_fired = 0
		fire_timer = 1.0 / fire_rate
		return
		
	_fire_single_shot()
	burst_shots_fired += 1
	
	if burst_shots_fired < burst_count and current_ammo > 0:
		await get_tree().create_timer(burst_delay).timeout
		_fire_burst()
		
func _spawn_projectile() -> Node3D:
	var projectile = _get_pooled_projectile()
	if not projectile and projectile_scene:
		projectile = projectile_scene.instantiate()
		get_tree().root.add_child(projectile)
		
	if not projectile:
		return null
		
	projectile.global_transform = global_transform
	projectile.visible = true
	
	if projectile.has_method("setup"):
		projectile.setup(damage, projectile_speed, effective_range, get_parent())
		
	if auto_aim_enabled and current_target and target_lock_progress >= target_lock_time:
		var direction = (current_target.global_position - global_position).normalized()
		projectile.look_at(global_position + direction, Vector3.UP)
		
	return projectile
	
func _get_pooled_projectile() -> Node3D:
	for projectile in projectile_pool:
		if not projectile.visible:
			projectile.set_physics_process(true)
			return projectile
	return null
	
func _apply_spread(projectile: Node3D):
	var spread_x = randf_range(-spread_angle, spread_angle)
	var spread_y = randf_range(-spread_angle, spread_angle)
	
	projectile.rotate_y(deg_to_rad(spread_x))
	projectile.rotate_x(deg_to_rad(spread_y))
	
func _apply_recoil():
	var recoil_amount = Vector3(
		randf_range(-1, 1) * recoil_force * 0.3,
		recoil_force,
		0
	)
	
	if recoil_pattern:
		var pattern_value = recoil_pattern.sample(fire_timer)
		recoil_amount *= pattern_value
		
	current_recoil += recoil_amount
	current_recoil = current_recoil.limit_length(max_recoil)
	
	if get_parent().has_method("apply_recoil"):
		get_parent().apply_recoil(current_recoil)
		
func _add_heat():
	if not uses_heat_system:
		return
		
	current_heat += heat_per_shot
	
	if current_heat >= overheat_threshold:
		is_overheated = true
		weapon_overheated.emit()
		_start_overheat_cooldown()
		
func _start_overheat_cooldown():
	can_fire = false
	await get_tree().create_timer(overheat_cooldown).timeout
	can_fire = true
	
func reload():
	if is_reloading or current_ammo == magazine_size or total_ammo == 0:
		return
		
	is_reloading = true
	reload_started.emit()
	
	if audio_players.has("reload"):
		audio_players["reload"].play()
		
	await get_tree().create_timer(reload_time).timeout
	
	if not infinite_ammo:
		var ammo_needed = magazine_size - current_ammo
		var ammo_available = min(ammo_needed, total_ammo)
		current_ammo += ammo_available
		total_ammo -= ammo_available
	else:
		current_ammo = magazine_size
		
	is_reloading = false
	reload_finished.emit()
	ammo_changed.emit(current_ammo, magazine_size)
	
func switch_firing_mode():
	current_firing_mode = (current_firing_mode + 1) % firing_modes.size()
	burst_shots_fired = 0
	
func add_ammo(amount: int):
	total_ammo += amount
	
func _play_fire_effects():
	if muzzle_flash:
		muzzle_flash.restart()
		muzzle_flash.emitting = true
		
	if shell_ejection:
		shell_ejection.restart()
		shell_ejection.emitting = true
		
	if audio_players.has("fire"):
		audio_players["fire"].pitch_scale = randf_range(0.9, 1.1)
		audio_players["fire"].play()
		
func enable_scope(enabled: bool):
	if scope_camera:
		scope_camera.current = enabled
		
func get_weapon_stats() -> Dictionary:
	return {
		"ammo": current_ammo,
		"magazine_size": magazine_size,
		"total_ammo": total_ammo,
		"heat": current_heat / overheat_threshold if uses_heat_system else 0.0,
		"is_overheated": is_overheated,
		"firing_mode": firing_modes[current_firing_mode],
		"is_reloading": is_reloading
	}