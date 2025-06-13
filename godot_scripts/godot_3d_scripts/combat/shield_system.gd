extends Node3D

signal shield_activated
signal shield_deactivated
signal shield_damaged(damage: float, remaining: float)
signal shield_depleted
signal shield_recharged
signal damage_absorbed(amount: float)

@export_group("Shield Properties")
@export var max_shield_health: float = 100.0
@export var shield_recharge_rate: float = 10.0
@export var shield_recharge_delay: float = 3.0
@export var shield_radius: float = 2.0
@export var damage_reduction: float = 0.0
@export var energy_cost_per_second: float = 5.0

@export_group("Shield Types")
@export var shield_type: ShieldType = ShieldType.ENERGY
@export var physical_shield_scene: PackedScene
@export var directional_shield: bool = false
@export var shield_arc: float = 180.0

@export_group("Visual Effects")
@export var shield_mesh: MeshInstance3D
@export var shield_material: ShaderMaterial
@export var hit_effect_scene: PackedScene
@export var shield_color: Color = Color(0.2, 0.6, 1.0, 0.5)
@export var shield_particles: GPUParticles3D

@export_group("Advanced Features")
@export var reflective_shield: bool = false
@export var reflection_chance: float = 0.3
@export var absorption_mode: bool = false
@export var max_absorbed_damage: float = 50.0
@export var discharge_damage: float = 100.0

enum ShieldType {
	ENERGY,
	PHYSICAL,
	KINETIC,
	PLASMA,
	ADAPTIVE
}

var current_shield_health: float
var is_active: bool = false
var shield_collider: Area3D
var recharge_timer: float = 0.0
var shield_broken: bool = false
var absorbed_damage: float = 0.0
var current_energy: float = 100.0
var hit_positions: Array = []

var shield_instance: Node3D
var audio_player: AudioStreamPlayer3D

func _ready():
	current_shield_health = max_shield_health
	_setup_shield_collider()
	_setup_shield_visual()
	_setup_audio()
	
func _setup_shield_collider():
	shield_collider = Area3D.new()
	shield_collider.name = "ShieldCollider"
	shield_collider.collision_layer = 8
	shield_collider.collision_mask = 0
	shield_collider.monitoring = false
	shield_collider.monitorable = true
	
	var collision_shape = CollisionShape3D.new()
	
	if directional_shield:
		var box_shape = BoxShape3D.new()
		box_shape.size = Vector3(shield_radius * 2, shield_radius * 2, 0.5)
		collision_shape.shape = box_shape
	else:
		var sphere_shape = SphereShape3D.new()
		sphere_shape.radius = shield_radius
		collision_shape.shape = sphere_shape
		
	shield_collider.add_child(collision_shape)
	add_child(shield_collider)
	
func _setup_shield_visual():
	if not shield_mesh:
		shield_mesh = MeshInstance3D.new()
		add_child(shield_mesh)
		
	match shield_type:
		ShieldType.ENERGY:
			_create_energy_shield()
		ShieldType.PHYSICAL:
			_create_physical_shield()
		ShieldType.PLASMA:
			_create_plasma_shield()
			
	shield_mesh.visible = false
	
func _create_energy_shield():
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = shield_radius
	sphere_mesh.height = shield_radius * 2
	sphere_mesh.radial_segments = 32
	sphere_mesh.rings = 16
	shield_mesh.mesh = sphere_mesh
	
	if not shield_material:
		shield_material = ShaderMaterial.new()
		
	shield_mesh.material_override = shield_material
	_update_shield_material()
	
func _create_physical_shield():
	if physical_shield_scene:
		shield_instance = physical_shield_scene.instantiate()
		add_child(shield_instance)
		shield_instance.scale = Vector3.ONE * shield_radius
		
func _create_plasma_shield():
	_create_energy_shield()
	
	if shield_particles:
		shield_particles.emission_sphere_radius = shield_radius
		shield_particles.amount = int(shield_radius * 50)
		
func _setup_audio():
	audio_player = AudioStreamPlayer3D.new()
	add_child(audio_player)
	
func _process(delta):
	if is_active:
		_drain_energy(delta)
		_update_shield_visual(delta)
		
	if shield_broken and recharge_timer > 0:
		recharge_timer -= delta
		if recharge_timer <= 0:
			_start_recharge()
			
	if not is_active and current_shield_health < max_shield_health and not shield_broken:
		current_shield_health = min(current_shield_health + shield_recharge_rate * delta, max_shield_health)
		if current_shield_health >= max_shield_health:
			shield_recharged.emit()
			
func activate_shield():
	if shield_broken or current_energy <= 0:
		return false
		
	is_active = true
	shield_collider.monitoring = true
	shield_collider.monitorable = true
	
	if shield_mesh:
		shield_mesh.visible = true
		
	if shield_particles:
		shield_particles.emitting = true
		
	shield_activated.emit()
	return true
	
func deactivate_shield():
	is_active = false
	shield_collider.monitoring = false
	shield_collider.monitorable = false
	
	if shield_mesh:
		shield_mesh.visible = false
		
	if shield_particles:
		shield_particles.emitting = false
		
	shield_deactivated.emit()
	
func take_damage(damage: float, damage_type: String = "normal", impact_position: Vector3 = Vector3.ZERO, attacker: Node3D = null) -> float:
	if not is_active:
		return damage
		
	var absorbed = _calculate_absorbed_damage(damage, damage_type)
	current_shield_health -= absorbed
	
	shield_damaged.emit(absorbed, current_shield_health)
	damage_absorbed.emit(absorbed)
	
	_create_hit_effect(impact_position)
	hit_positions.append(impact_position)
	
	if reflective_shield and randf() < reflection_chance and attacker:
		_reflect_damage(attacker, absorbed * 0.5, impact_position)
		
	if absorption_mode:
		absorbed_damage += absorbed
		absorbed_damage = min(absorbed_damage, max_absorbed_damage)
		
	if current_shield_health <= 0:
		_break_shield()
		return damage - absorbed
		
	return damage - absorbed
	
func _calculate_absorbed_damage(damage: float, damage_type: String) -> float:
	var type_multiplier = 1.0
	
	match shield_type:
		ShieldType.KINETIC:
			type_multiplier = 1.5 if damage_type == "physical" else 0.5
		ShieldType.PLASMA:
			type_multiplier = 1.5 if damage_type == "energy" else 0.5
		ShieldType.ADAPTIVE:
			type_multiplier = 1.0
			
	var absorbed = damage * (1.0 - damage_reduction) * type_multiplier
	return min(absorbed, current_shield_health)
	
func _break_shield():
	shield_broken = true
	current_shield_health = 0
	recharge_timer = shield_recharge_delay
	
	deactivate_shield()
	shield_depleted.emit()
	
	if absorption_mode and absorbed_damage > 0:
		_discharge_absorbed_damage()
		
func _discharge_absorbed_damage():
	var discharge_area = Area3D.new()
	discharge_area.collision_mask = 2
	
	var collision = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = shield_radius * 2
	collision.shape = sphere
	discharge_area.add_child(collision)
	
	add_child(discharge_area)
	
	await get_tree().physics_frame
	
	for body in discharge_area.get_overlapping_bodies():
		if body != get_parent() and body.has_method("take_damage"):
			var discharge_dmg = absorbed_damage + discharge_damage
			body.take_damage(discharge_dmg, "energy", body.global_position, get_parent())
			
	discharge_area.queue_free()
	absorbed_damage = 0
	
func _start_recharge():
	shield_broken = false
	
func _reflect_damage(target: Node3D, damage: float, origin: Vector3):
	if target.has_method("take_damage"):
		target.take_damage(damage, "reflected", target.global_position, get_parent())
		
	var reflection_visual = Line3D.new()
	add_child(reflection_visual)
	reflection_visual.add_point(origin)
	reflection_visual.add_point(target.global_position)
	
	await get_tree().create_timer(0.2).timeout
	reflection_visual.queue_free()
	
func _drain_energy(delta):
	current_energy -= energy_cost_per_second * delta
	if current_energy <= 0:
		current_energy = 0
		deactivate_shield()
		
func _update_shield_visual(delta):
	if not shield_material:
		return
		
	var shield_percentage = current_shield_health / max_shield_health
	shield_material.set_shader_parameter("shield_strength", shield_percentage)
	shield_material.set_shader_parameter("shield_color", shield_color)
	
	for i in range(hit_positions.size() - 1, -1, -1):
		var age = get_tree().get_frame() * delta
		if age > 1.0:
			hit_positions.remove_at(i)
		else:
			shield_material.set_shader_parameter("hit_position_" + str(i), hit_positions[i])
			shield_material.set_shader_parameter("hit_age_" + str(i), age)
			
func _update_shield_material():
	if shield_material:
		shield_material.set_shader_parameter("shield_radius", shield_radius)
		shield_material.set_shader_parameter("shield_color", shield_color)
		shield_material.set_shader_parameter("shield_strength", 1.0)
		
func _create_hit_effect(position: Vector3):
	if hit_effect_scene:
		var effect = hit_effect_scene.instantiate()
		get_tree().root.add_child(effect)
		effect.global_position = position
		
func recharge_energy(amount: float):
	current_energy = min(current_energy + amount, 100.0)
	
func repair_shield(amount: float):
	if not shield_broken:
		current_shield_health = min(current_shield_health + amount, max_shield_health)
		
func overcharge_shield(multiplier: float, duration: float):
	var original_max = max_shield_health
	max_shield_health *= multiplier
	current_shield_health = max_shield_health
	
	await get_tree().create_timer(duration).timeout
	
	max_shield_health = original_max
	current_shield_health = min(current_shield_health, max_shield_health)
	
func get_shield_status() -> Dictionary:
	return {
		"health": current_shield_health,
		"max_health": max_shield_health,
		"percentage": current_shield_health / max_shield_health,
		"is_active": is_active,
		"is_broken": shield_broken,
		"energy": current_energy,
		"absorbed_damage": absorbed_damage
	}