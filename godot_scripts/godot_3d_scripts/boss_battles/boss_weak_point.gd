extends Area3D

class_name BossWeakPoint

@export_group("Weak Point Settings")
@export var damage_multiplier := 2.0
@export var critical_hit_chance := 0.3
@export var critical_damage_multiplier := 3.0
@export var requires_specific_damage_type := false
@export var required_damage_types: Array[String] = ["physical"]

@export_group("Visibility")
@export var always_visible := false
@export var visibility_duration := 5.0
@export var visibility_cooldown := 10.0
@export var flash_when_visible := true
@export var flash_color := Color(1, 0.8, 0)
@export var flash_speed := 2.0

@export_group("Shield Settings")
@export var has_shield := false
@export var shield_health := 100.0
@export var shield_regeneration_rate := 10.0
@export var shield_regeneration_delay := 3.0

@export_group("Movement")
@export var moves_around := false
@export var movement_pattern := MovementPattern.CIRCULAR
@export var movement_radius := 2.0
@export var movement_speed := 1.0
@export var vertical_movement := false
@export var vertical_amplitude := 1.0

@export_group("Special Effects")
@export var hit_particle_scene: PackedScene
@export var destruction_particle_scene: PackedScene
@export var hit_sound: AudioStream
@export var destruction_sound: AudioStream
@export var screen_shake_on_hit := true
@export var screen_shake_intensity := 0.5

enum MovementPattern {
	CIRCULAR,
	FIGURE_EIGHT,
	RANDOM,
	LINEAR
}

var boss_system: BossPhaseSystem
var is_active := true
var is_visible := false
var current_shield_health: float
var shield_regeneration_timer: float
var visibility_timer: float
var movement_time: float
var original_position: Vector3
var flash_material: ShaderMaterial
var original_material: Material
var mesh_instance: MeshInstance3D
var shield_mesh: MeshInstance3D
var audio_player: AudioStreamPlayer3D
var hits_taken := 0
var total_damage_dealt := 0.0

signal weak_point_hit(damage: float, is_critical: bool)
signal weak_point_destroyed()
signal visibility_changed(visible: bool)
signal shield_broken()

func _ready():
	original_position = position
	current_shield_health = shield_health
	
	setup_components()
	setup_collision()
	
	if not always_visible:
		set_visible(false)
		schedule_next_visibility()

func setup_components():
	mesh_instance = get_node_or_null("MeshInstance3D")
	if not mesh_instance:
		mesh_instance = MeshInstance3D.new()
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = 0.5
		sphere_mesh.height = 1.0
		mesh_instance.mesh = sphere_mesh
		add_child(mesh_instance)
	
	if mesh_instance:
		original_material = mesh_instance.get_surface_override_material(0)
		create_flash_material()
	
	audio_player = AudioStreamPlayer3D.new()
	audio_player.bus = "SFX"
	add_child(audio_player)
	
	if has_shield:
		create_shield_visual()

func setup_collision():
	area_entered.connect(_on_projectile_entered)
	body_entered.connect(_on_body_entered)

func create_flash_material():
	flash_material = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
	shader_type spatial;
	render_mode unshaded;
	
	uniform vec4 flash_color: source_color = vec4(1.0, 0.8, 0.0, 1.0);
	uniform float flash_intensity: hint_range(0.0, 1.0) = 0.5;
	uniform sampler2D base_texture: source_color;
	
	void fragment() {
		vec4 tex_color = texture(base_texture, UV);
		ALBEDO = mix(tex_color.rgb, flash_color.rgb, flash_intensity);
		ALPHA = tex_color.a;
	}
	"""
	flash_material.shader = shader

func create_shield_visual():
	shield_mesh = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.7
	sphere_mesh.radial_segments = 16
	sphere_mesh.rings = 8
	shield_mesh.mesh = sphere_mesh
	add_child(shield_mesh)
	
	var shield_material = StandardMaterial3D.new()
	shield_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield_material.albedo_color = Color(0.5, 0.8, 1.0, 0.3)
	shield_material.emission_enabled = true
	shield_material.emission = Color(0.5, 0.8, 1.0)
	shield_material.emission_energy = 0.5
	shield_material.rim_enabled = true
	shield_material.rim = 1.0
	shield_material.rim_tint = 0.5
	shield_mesh.set_surface_override_material(0, shield_material)

func _on_projectile_entered(area: Area3D):
	if not is_active or not is_visible:
		return
	
	if area.has_method("get_damage") and area.has_method("get_damage_type"):
		var damage = area.get_damage()
		var damage_type = area.get_damage_type()
		
		if requires_specific_damage_type and not damage_type in required_damage_types:
			return
		
		apply_damage(damage, damage_type, area)
		
		if area.has_method("on_hit"):
			area.on_hit()

func _on_body_entered(body: Node3D):
	if not is_active or not is_visible:
		return
	
	if body.has_method("get_melee_damage"):
		var damage = body.get_melee_damage()
		apply_damage(damage, "physical", body)

func apply_damage(base_damage: float, damage_type: String, source: Node3D):
	var actual_damage = base_damage * damage_multiplier
	var is_critical = randf() < critical_hit_chance
	
	if is_critical:
		actual_damage *= critical_damage_multiplier
	
	if has_shield and current_shield_health > 0:
		var shield_damage = min(actual_damage, current_shield_health)
		current_shield_health -= shield_damage
		actual_damage -= shield_damage
		
		update_shield_visual()
		
		if current_shield_health <= 0:
			break_shield()
			emit_signal("shield_broken")
		
		shield_regeneration_timer = shield_regeneration_delay
	
	if actual_damage > 0 and boss_system:
		boss_system.take_damage(actual_damage, source, damage_type)
		
	hits_taken += 1
	total_damage_dealt += actual_damage
	
	emit_signal("weak_point_hit", actual_damage, is_critical)
	
	create_hit_effect(is_critical)
	play_hit_sound()
	
	if screen_shake_on_hit:
		trigger_screen_shake()

func create_hit_effect(is_critical: bool):
	if hit_particle_scene:
		var particles = hit_particle_scene.instantiate()
		get_parent().add_child(particles)
		particles.global_position = global_position
		particles.emitting = true
		
		if is_critical and particles.has_method("set_critical"):
			particles.set_critical(true)
		
		var timer = Timer.new()
		timer.wait_time = 3.0
		timer.one_shot = true
		timer.timeout.connect(particles.queue_free)
		particles.add_child(timer)
		timer.start()
	
	flash_hit()

func flash_hit():
	if not mesh_instance or not flash_material:
		return
	
	mesh_instance.set_surface_override_material(0, flash_material)
	
	var tween = create_tween()
	tween.tween_method(set_flash_intensity, 1.0, 0.0, 0.3)
	tween.finished.connect(restore_original_material)

func set_flash_intensity(value: float):
	if flash_material:
		flash_material.set_shader_parameter("flash_intensity", value)

func restore_original_material():
	if mesh_instance:
		mesh_instance.set_surface_override_material(0, original_material)

func play_hit_sound():
	if hit_sound and audio_player:
		audio_player.stream = hit_sound
		audio_player.pitch_scale = randf_range(0.9, 1.1)
		audio_player.play()

func trigger_screen_shake():
	var camera = get_viewport().get_camera_3d()
	if camera and camera.has_method("shake"):
		camera.shake(screen_shake_intensity, 0.3)

func set_visible(visible: bool):
	is_visible = visible
	self.visible = visible
	emit_signal("visibility_changed", visible)
	
	if visible and flash_when_visible:
		start_visibility_flash()

func start_visibility_flash():
	if not mesh_instance:
		return
	
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(mesh_instance, "modulate:a", 0.3, 0.5 / flash_speed)
	tween.tween_property(mesh_instance, "modulate:a", 1.0, 0.5 / flash_speed)

func schedule_next_visibility():
	visibility_timer = visibility_cooldown

func _process(delta):
	if not is_active:
		return
	
	if not always_visible:
		handle_visibility(delta)
	
	if has_shield:
		handle_shield_regeneration(delta)
	
	if moves_around:
		handle_movement(delta)

func handle_visibility(delta: float):
	if is_visible:
		visibility_timer -= delta
		if visibility_timer <= 0:
			set_visible(false)
			schedule_next_visibility()
	else:
		visibility_timer -= delta
		if visibility_timer <= 0:
			set_visible(true)
			visibility_timer = visibility_duration

func handle_shield_regeneration(delta: float):
	if current_shield_health >= shield_health:
		return
	
	if shield_regeneration_timer > 0:
		shield_regeneration_timer -= delta
		return
	
	current_shield_health = min(current_shield_health + shield_regeneration_rate * delta, shield_health)
	update_shield_visual()

func update_shield_visual():
	if not shield_mesh:
		return
	
	var shield_percentage = current_shield_health / shield_health
	shield_mesh.visible = current_shield_health > 0
	
	if shield_mesh.visible:
		var material = shield_mesh.get_surface_override_material(0)
		if material:
			material.albedo_color.a = 0.3 * shield_percentage
			material.emission_energy = 0.5 * shield_percentage

func break_shield():
	if shield_mesh:
		var break_tween = create_tween()
		break_tween.tween_property(shield_mesh, "scale", Vector3.ONE * 1.5, 0.2)
		break_tween.parallel().tween_property(shield_mesh, "modulate:a", 0.0, 0.2)
		break_tween.tween_callback(func(): shield_mesh.visible = false)

func handle_movement(delta: float):
	movement_time += delta * movement_speed
	
	match movement_pattern:
		MovementPattern.CIRCULAR:
			var angle = movement_time * TAU
			position.x = original_position.x + cos(angle) * movement_radius
			position.z = original_position.z + sin(angle) * movement_radius
		
		MovementPattern.FIGURE_EIGHT:
			var t = movement_time * TAU
			position.x = original_position.x + sin(t) * movement_radius
			position.z = original_position.z + sin(2 * t) * movement_radius * 0.5
		
		MovementPattern.RANDOM:
			if int(movement_time) % 2 == 0:
				var random_offset = Vector3(
					randf_range(-movement_radius, movement_radius),
					0,
					randf_range(-movement_radius, movement_radius)
				)
				var tween = create_tween()
				tween.tween_property(self, "position", original_position + random_offset, 1.0)
		
		MovementPattern.LINEAR:
			var t = sin(movement_time * TAU)
			position.x = original_position.x + t * movement_radius
	
	if vertical_movement:
		position.y = original_position.y + sin(movement_time * TAU * 2) * vertical_amplitude

func destroy_weak_point():
	is_active = false
	emit_signal("weak_point_destroyed")
	
	if destruction_particle_scene:
		var particles = destruction_particle_scene.instantiate()
		get_parent().add_child(particles)
		particles.global_position = global_position
		particles.emitting = true
	
	if destruction_sound and audio_player:
		audio_player.stream = destruction_sound
		audio_player.play()
		audio_player.finished.connect(queue_free)
	else:
		queue_free()

func set_boss_system(boss: BossPhaseSystem):
	boss_system = boss

func reset():
	is_active = true
	is_visible = always_visible
	current_shield_health = shield_health
	shield_regeneration_timer = 0
	visibility_timer = 0
	movement_time = 0
	hits_taken = 0
	total_damage_dealt = 0
	position = original_position
	
	if shield_mesh:
		shield_mesh.visible = has_shield
		shield_mesh.scale = Vector3.ONE
		shield_mesh.modulate.a = 1.0