extends Node

export var projectile_scene : PackedScene
export var fire_rate = 0.5
export var reload_time = 2.0
export var magazine_size = 30
export var max_ammo = 300
export var spread_angle = 2.0
export var recoil_force = 0.1
export var aim_zoom = 1.5
export var aim_speed = 5.0

signal shot_fired(projectile)
signal reload_started()
signal reload_completed()
signal ammo_changed(current_mag, total_ammo)
signal aiming_changed(is_aiming)

var current_ammo_in_mag = 30
var current_total_ammo = 300
var fire_timer = 0.0
var reload_timer = 0.0
var is_reloading = false
var is_aiming = false
var can_fire = true

onready var muzzle_position = $MuzzlePosition
onready var muzzle_flash = $MuzzleFlash
onready var shell_ejector = $ShellEjector
onready var fire_sound = $FireSound
onready var reload_sound = $ReloadSound
onready var empty_sound = $EmptySound

func _ready():
	emit_signal("ammo_changed", current_ammo_in_mag, current_total_ammo)

func _physics_process(delta):
	if fire_timer > 0:
		fire_timer -= delta
		
	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0:
			_complete_reload()

func fire():
	if not can_fire or is_reloading or fire_timer > 0:
		return
		
	if current_ammo_in_mag <= 0:
		if current_total_ammo > 0:
			reload()
		else:
			_play_empty_sound()
		return
	
	_shoot_projectile()
	fire_timer = 1.0 / fire_rate
	
	current_ammo_in_mag -= 1
	emit_signal("ammo_changed", current_ammo_in_mag, current_total_ammo)
	
	if current_ammo_in_mag <= 0 and current_total_ammo > 0:
		yield(get_tree().create_timer(0.5), "timeout")
		reload()

func _shoot_projectile():
	if not projectile_scene or not muzzle_position:
		return
	
	var projectile = projectile_scene.instance()
	get_tree().current_scene.add_child(projectile)
	
	projectile.global_transform = muzzle_position.global_transform
	
	var spread = _calculate_spread()
	projectile.rotation.y += deg2rad(rand_range(-spread, spread))
	projectile.rotation.x += deg2rad(rand_range(-spread, spread))
	
	if projectile.has_method("set_damage"):
		projectile.set_damage(_calculate_damage())
	
	if projectile.has_method("set_owner"):
		projectile.set_owner(get_parent())
	
	emit_signal("shot_fired", projectile)
	
	_play_fire_effects()
	_apply_recoil()

func _calculate_spread():
	var base_spread = spread_angle
	
	if is_aiming:
		base_spread *= 0.3
	
	if get_parent().has_method("is_moving") and get_parent().is_moving():
		base_spread *= 1.5
		
	return base_spread

func _calculate_damage():
	return 25.0

func _play_fire_effects():
	if muzzle_flash:
		muzzle_flash.emitting = true
		
	if fire_sound:
		fire_sound.play()
		
	if shell_ejector:
		_eject_shell()

func _eject_shell():
	pass

func _apply_recoil():
	if get_parent().has_method("apply_recoil"):
		var recoil_amount = recoil_force
		if is_aiming:
			recoil_amount *= 0.6
		get_parent().apply_recoil(recoil_amount)

func reload():
	if is_reloading or current_total_ammo <= 0 or current_ammo_in_mag >= magazine_size:
		return
		
	is_reloading = true
	reload_timer = reload_time
	
	emit_signal("reload_started")
	
	if reload_sound:
		reload_sound.play()

func _complete_reload():
	is_reloading = false
	
	var ammo_needed = magazine_size - current_ammo_in_mag
	var ammo_to_reload = min(ammo_needed, current_total_ammo)
	
	current_ammo_in_mag += ammo_to_reload
	current_total_ammo -= ammo_to_reload
	
	emit_signal("reload_completed")
	emit_signal("ammo_changed", current_ammo_in_mag, current_total_ammo)

func start_aiming():
	is_aiming = true
	emit_signal("aiming_changed", true)

func stop_aiming():
	is_aiming = false
	emit_signal("aiming_changed", false)

func _play_empty_sound():
	if empty_sound:
		empty_sound.play()

func add_ammo(amount):
	current_total_ammo = min(current_total_ammo + amount, max_ammo)
	emit_signal("ammo_changed", current_ammo_in_mag, current_total_ammo)

func has_ammo():
	return current_ammo_in_mag > 0 or current_total_ammo > 0

func get_ammo_percentage():
	return float(current_ammo_in_mag) / float(magazine_size)

func get_total_ammo_percentage():
	return float(current_total_ammo) / float(max_ammo)

func interrupt_reload():
	if is_reloading:
		is_reloading = false
		reload_timer = 0.0

func set_fire_enabled(enabled):
	can_fire = enabled

func force_reload():
	if current_ammo_in_mag < magazine_size and current_total_ammo > 0:
		reload()

func get_reload_progress():
	if not is_reloading:
		return 1.0
	return 1.0 - (reload_timer / reload_time)

func set_infinite_ammo(infinite):
	if infinite:
		current_ammo_in_mag = magazine_size
		current_total_ammo = max_ammo