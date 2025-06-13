extends Node

signal shot_fired(projectile)
signal reload_started
signal reload_finished
signal ammo_changed(current_ammo, max_ammo)
signal weapon_switched(weapon_name)
signal out_of_ammo

export var enabled: bool = true
export var projectile_scene: PackedScene
export var fire_rate: float = 0.5
export var projectile_speed: float = 30.0
export var projectile_damage: float = 25.0
export var spread_angle: float = 2.0
export var max_range: float = 100.0
export var magazine_size: int = 30
export var reload_time: float = 2.0
export var auto_reload: bool = true
export var infinite_ammo: bool = false
export var burst_mode: bool = false
export var burst_count: int = 3
export var burst_delay: float = 0.1
export var penetration_count: int = 0
export var ricochet_enabled: bool = false
export var ricochet_count: int = 2
export var hitscan_mode: bool = false
export var aim_assist_strength: float = 0.2
export var aim_assist_range: float = 10.0
export var recoil_amount: float = 1.0
export var muzzle_flash_enabled: bool = true

var current_ammo: int
var is_reloading: bool = false
var fire_cooldown: float = 0.0
var burst_shots_remaining: int = 0
var total_ammo: int = 300
var is_aiming: bool = false
var spread_multiplier: float = 1.0

var current_weapon: Dictionary = {
	"name": "default",
	"damage": 25.0,
	"fire_rate": 0.5,
	"magazine_size": 30,
	"reload_time": 2.0
}

var weapons: Dictionary = {
	"pistol": {
		"damage": 20.0,
		"fire_rate": 0.3,
		"magazine_size": 15,
		"reload_time": 1.5,
		"spread": 3.0,
		"projectile_speed": 40.0
	},
	"rifle": {
		"damage": 30.0,
		"fire_rate": 0.1,
		"magazine_size": 30,
		"reload_time": 2.5,
		"spread": 1.0,
		"projectile_speed": 50.0
	},
	"shotgun": {
		"damage": 15.0,
		"fire_rate": 0.8,
		"magazine_size": 8,
		"reload_time": 3.0,
		"spread": 10.0,
		"projectile_speed": 25.0,
		"pellet_count": 8
	}
}

var player: Spatial
var camera: Camera
var shoot_point: Spatial
var audio_player: AudioStreamPlayer3D
var muzzle_flash: CPUParticles

onready var fire_sounds: Array = []
onready var reload_sounds: Array = []
onready var empty_sounds: Array = []

func _ready():
	current_ammo = magazine_size
	set_process(false)

func initialize(player_node: Spatial, camera_node: Camera, shoot_pos: Spatial = null):
	player = player_node
	camera = camera_node
	shoot_point = shoot_pos
	
	if not shoot_point:
		_create_default_shoot_point()
	
	_setup_audio()
	_setup_muzzle_flash()
	set_process(true)

func _process(delta):
	if not enabled:
		return
	
	if fire_cooldown > 0:
		fire_cooldown -= delta
	
	if burst_shots_remaining > 0 and fire_cooldown <= 0:
		_fire_burst_shot()
	
	if is_aiming:
		spread_multiplier = 0.5
	else:
		spread_multiplier = lerp(spread_multiplier, 1.0, delta * 5.0)

func fire():
	if not _can_fire():
		if current_ammo <= 0:
			_play_empty_sound()
			emit_signal("out_of_ammo")
			if auto_reload and not is_reloading:
				reload()
		return false
	
	if burst_mode:
		burst_shots_remaining = burst_count - 1
	
	_perform_shot()
	return true

func _can_fire() -> bool:
	return enabled and not is_reloading and fire_cooldown <= 0 and current_ammo > 0

func _perform_shot():
	current_ammo -= 1
	fire_cooldown = 1.0 / fire_rate
	
	emit_signal("ammo_changed", current_ammo, magazine_size)
	
	if hitscan_mode:
		_perform_hitscan()
	else:
		_spawn_projectile()
	
	_apply_recoil()
	_play_fire_sound()
	_show_muzzle_flash()
	
	if current_ammo <= 0 and auto_reload:
		reload()

func _spawn_projectile():
	if not projectile_scene or not shoot_point:
		return
	
	var projectile = projectile_scene.instance()
	get_tree().current_scene.add_child(projectile)
	
	projectile.global_transform = shoot_point.global_transform
	
	var spread = _calculate_spread()
	var direction = -shoot_point.global_transform.basis.z
	direction = direction.rotated(Vector3.RIGHT, deg2rad(randf_range(-spread, spread)))
	direction = direction.rotated(Vector3.UP, deg2rad(randf_range(-spread, spread)))
	
	if aim_assist_strength > 0:
		direction = _apply_aim_assist(direction)
	
	_setup_projectile(projectile, direction)
	
	emit_signal("shot_fired", projectile)

func _setup_projectile(projectile, direction: Vector3):
	if projectile.has_method("initialize"):
		projectile.initialize(direction * projectile_speed, projectile_damage, max_range, penetration_count)
	elif projectile is RigidBody:
		projectile.linear_velocity = direction * projectile_speed
	
	if projectile.has_method("set_owner"):
		projectile.set_owner(player)

func _perform_hitscan():
	var ray_start = camera.global_transform.origin
	var spread = _calculate_spread()
	var ray_direction = -camera.global_transform.basis.z
	
	ray_direction = ray_direction.rotated(Vector3.RIGHT, deg2rad(randf_range(-spread, spread)))
	ray_direction = ray_direction.rotated(Vector3.UP, deg2rad(randf_range(-spread, spread)))
	
	if aim_assist_strength > 0:
		ray_direction = _apply_aim_assist(ray_direction)
	
	var ray_end = ray_start + ray_direction * max_range
	
	var space_state = camera.get_world().direct_space_state
	var result = space_state.intersect_ray(ray_start, ray_end, [player])
	
	if result:
		_process_hit(result)
		
		if ricochet_enabled:
			_perform_ricochet(result, ray_direction, ricochet_count)

func _process_hit(result: Dictionary):
	var target = result.collider
	var hit_position = result.position
	var hit_normal = result.normal
	
	if target.has_method("take_damage"):
		target.take_damage(projectile_damage, player.global_transform.origin, player)
	
	_spawn_impact_effect(hit_position, hit_normal)

func _perform_ricochet(hit_result: Dictionary, incoming_direction: Vector3, bounces_left: int):
	if bounces_left <= 0:
		return
	
	var normal = hit_result.normal
	var reflect_direction = incoming_direction.bounce(normal)
	var new_start = hit_result.position + normal * 0.01
	var new_end = new_start + reflect_direction * max_range
	
	var space_state = camera.get_world().direct_space_state
	var result = space_state.intersect_ray(new_start, new_end, [player])
	
	if result:
		_process_hit(result)
		_perform_ricochet(result, reflect_direction, bounces_left - 1)

func _calculate_spread() -> float:
	var base_spread = spread_angle * spread_multiplier
	
	if player and player.has_method("get_velocity"):
		var velocity = player.get_velocity()
		var movement_factor = velocity.length() / 10.0
		base_spread *= (1.0 + movement_factor * 0.5)
	
	return base_spread

func _apply_aim_assist(direction: Vector3) -> Vector3:
	if aim_assist_strength <= 0:
		return direction
	
	var closest_target = _find_closest_target()
	if not closest_target:
		return direction
	
	var to_target = (closest_target.global_transform.origin - shoot_point.global_transform.origin).normalized()
	return direction.lerp(to_target, aim_assist_strength).normalized()

func _find_closest_target() -> Spatial:
	var space_state = player.get_world().direct_space_state
	var query = PhysicsShapeQueryParameters.new()
	var sphere = SphereShape.new()
	sphere.radius = aim_assist_range
	query.set_shape(sphere)
	query.transform.origin = player.global_transform.origin
	
	var results = space_state.intersect_shape(query, 32)
	var closest_target = null
	var closest_distance = INF
	
	for result in results:
		var target = result.collider
		if target.is_in_group("enemy") and target != player:
			var distance = target.global_transform.origin.distance_to(player.global_transform.origin)
			if distance < closest_distance:
				closest_distance = distance
				closest_target = target
	
	return closest_target

func _fire_burst_shot():
	_perform_shot()
	burst_shots_remaining -= 1
	
	if burst_shots_remaining > 0:
		fire_cooldown = burst_delay

func reload():
	if is_reloading or (current_ammo == magazine_size and not infinite_ammo):
		return
	
	is_reloading = true
	emit_signal("reload_started")
	_play_reload_sound()
	
	yield(get_tree().create_timer(reload_time), "timeout")
	
	if not infinite_ammo:
		var needed_ammo = magazine_size - current_ammo
		var available_ammo = min(needed_ammo, total_ammo)
		current_ammo += available_ammo
		total_ammo -= available_ammo
	else:
		current_ammo = magazine_size
	
	is_reloading = false
	emit_signal("reload_finished")
	emit_signal("ammo_changed", current_ammo, magazine_size)

func switch_weapon(weapon_name: String):
	if not weapon_name in weapons:
		return
	
	current_weapon = weapons[weapon_name].duplicate()
	projectile_damage = current_weapon.damage
	fire_rate = current_weapon.get("fire_rate", fire_rate)
	magazine_size = current_weapon.get("magazine_size", magazine_size)
	reload_time = current_weapon.get("reload_time", reload_time)
	spread_angle = current_weapon.get("spread", spread_angle)
	projectile_speed = current_weapon.get("projectile_speed", projectile_speed)
	
	current_ammo = magazine_size
	emit_signal("weapon_switched", weapon_name)
	emit_signal("ammo_changed", current_ammo, magazine_size)

func aim(aiming: bool):
	is_aiming = aiming

func _apply_recoil():
	if not camera:
		return
	
	var recoil_x = randf_range(-recoil_amount, recoil_amount) * 0.5
	var recoil_y = recoil_amount * (0.5 + randf() * 0.5)
	
	if player.has_method("add_camera_recoil"):
		player.add_camera_recoil(Vector2(recoil_x, recoil_y))

func _create_default_shoot_point():
	shoot_point = Spatial.new()
	if camera:
		camera.add_child(shoot_point)
		shoot_point.transform.origin = Vector3(0.2, -0.1, -0.5)

func _setup_audio():
	if not audio_player:
		audio_player = AudioStreamPlayer3D.new()
		if player:
			player.add_child(audio_player)

func _setup_muzzle_flash():
	if not muzzle_flash_enabled:
		return
	
	muzzle_flash = CPUParticles.new()
	muzzle_flash.emitting = false
	muzzle_flash.amount = 1
	muzzle_flash.lifetime = 0.05
	muzzle_flash.one_shot = true
	muzzle_flash.scale_amount = 0.3
	
	if shoot_point:
		shoot_point.add_child(muzzle_flash)

func _show_muzzle_flash():
	if muzzle_flash:
		muzzle_flash.restart()

func _spawn_impact_effect(position: Vector3, normal: Vector3):
	pass

func _play_fire_sound():
	if fire_sounds.size() > 0 and audio_player:
		audio_player.stream = fire_sounds[randi() % fire_sounds.size()]
		audio_player.pitch_scale = 0.95 + randf() * 0.1
		audio_player.play()

func _play_reload_sound():
	if reload_sounds.size() > 0 and audio_player:
		audio_player.stream = reload_sounds[randi() % reload_sounds.size()]
		audio_player.play()

func _play_empty_sound():
	if empty_sounds.size() > 0 and audio_player:
		audio_player.stream = empty_sounds[randi() % empty_sounds.size()]
		audio_player.play()

func add_ammo(amount: int):
	total_ammo += amount

func get_ammo_percentage() -> float:
	return float(current_ammo) / float(magazine_size) * 100.0

func set_combat_enabled(enabled_state: bool):
	enabled = enabled_state