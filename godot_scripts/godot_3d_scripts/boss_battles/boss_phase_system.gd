extends Node3D

class_name BossPhaseSystem

@export_group("Boss Settings")
@export var boss_name := "Ancient Guardian"
@export var max_health := 1000.0
@export var defense_multiplier := 1.0
@export var enrage_timer := 300.0

@export_group("Phase Configuration")
@export var phases: Array[BossPhase] = []
@export var transition_invulnerability_time := 2.0
@export var phase_transition_scene: PackedScene

@export_group("UI Settings")
@export var health_bar_path: NodePath
@export var phase_indicator_path: NodePath
@export var show_damage_numbers := true

var current_health: float
var current_phase_index := 0
var current_phase: BossPhase
var is_transitioning := false
var is_enraged := false
var is_defeated := false
var damage_taken_this_phase := 0.0
var time_in_phase := 0.0
var total_battle_time := 0.0
var enrage_time_remaining := 0.0

var health_bar: ProgressBar
var phase_indicator: Label
var attack_manager: Node
var movement_controller: Node

signal phase_changed(new_phase: int)
signal boss_damaged(damage: float, current_health: float)
signal boss_defeated()
signal boss_enraged()
signal transition_started()
signal transition_completed()

func _ready():
	current_health = max_health
	enrage_time_remaining = enrage_timer
	
	setup_ui_references()
	initialize_phases()
	
	if phases.size() > 0:
		enter_phase(0)

func setup_ui_references():
	if health_bar_path:
		health_bar = get_node_or_null(health_bar_path)
		if health_bar:
			health_bar.max_value = max_health
			health_bar.value = current_health
	
	if phase_indicator_path:
		phase_indicator = get_node_or_null(phase_indicator_path)

func initialize_phases():
	for i in range(phases.size()):
		var phase = phases[i]
		if not phase:
			phase = BossPhase.new()
			phases[i] = phase
		
		phase.phase_index = i
		phase.boss_system = self

func take_damage(amount: float, damage_source: Node3D = null, damage_type: String = "normal"):
	if is_defeated or is_transitioning:
		return 0.0
	
	var actual_damage = calculate_damage(amount, damage_type)
	current_health -= actual_damage
	damage_taken_this_phase += actual_damage
	
	emit_signal("boss_damaged", actual_damage, current_health)
	update_health_bar()
	
	if show_damage_numbers:
		spawn_damage_number(actual_damage, damage_source)
	
	check_phase_transition()
	
	if current_health <= 0:
		defeat_boss()
	
	return actual_damage

func calculate_damage(base_damage: float, damage_type: String) -> float:
	var damage = base_damage
	
	if current_phase:
		damage *= current_phase.get_damage_multiplier(damage_type)
	
	damage /= defense_multiplier
	
	if is_enraged:
		damage *= 0.8
	
	return max(1.0, damage)

func check_phase_transition():
	if is_transitioning or current_phase_index >= phases.size() - 1:
		return
	
	var next_phase_index = current_phase_index + 1
	var next_phase = phases[next_phase_index]
	
	if next_phase and current_health <= next_phase.health_threshold:
		start_phase_transition(next_phase_index)

func start_phase_transition(new_phase_index: int):
	is_transitioning = true
	emit_signal("transition_started")
	
	if current_phase:
		current_phase.exit_phase()
	
	make_invulnerable(true)
	play_transition_effect()
	
	var timer = Timer.new()
	timer.wait_time = transition_invulnerability_time
	timer.one_shot = true
	timer.timeout.connect(_on_transition_complete.bind(new_phase_index))
	add_child(timer)
	timer.start()

func _on_transition_complete(new_phase_index: int):
	enter_phase(new_phase_index)
	make_invulnerable(false)
	is_transitioning = false
	emit_signal("transition_completed")

func enter_phase(phase_index: int):
	if phase_index >= phases.size():
		return
	
	current_phase_index = phase_index
	current_phase = phases[phase_index]
	damage_taken_this_phase = 0.0
	time_in_phase = 0.0
	
	if current_phase:
		current_phase.enter_phase()
	
	emit_signal("phase_changed", phase_index)
	update_phase_indicator()

func play_transition_effect():
	if phase_transition_scene:
		var effect = phase_transition_scene.instantiate()
		add_child(effect)
		effect.global_position = global_position
		
		if effect.has_method("play"):
			effect.play()

func make_invulnerable(invulnerable: bool):
	set_meta("invulnerable", invulnerable)
	
	var collision = get_node_or_null("CollisionShape3D")
	if collision:
		collision.disabled = invulnerable

func update_health_bar():
	if health_bar:
		health_bar.value = current_health
		
		var health_percentage = current_health / max_health
		var bar_color = Color.GREEN
		
		if health_percentage < 0.25:
			bar_color = Color.RED
		elif health_percentage < 0.5:
			bar_color = Color.YELLOW
		
		health_bar.modulate = bar_color

func update_phase_indicator():
	if phase_indicator:
		phase_indicator.text = "Phase %d/%d" % [current_phase_index + 1, phases.size()]

func spawn_damage_number(damage: float, source: Node3D):
	var damage_label = Label3D.new()
	damage_label.text = str(int(damage))
	damage_label.modulate = Color.YELLOW
	damage_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	damage_label.font_size = 48
	damage_label.outline_size = 8
	
	add_child(damage_label)
	damage_label.position = Vector3(randf_range(-1, 1), 2, 0)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(damage_label, "position:y", damage_label.position.y + 2, 1.0)
	tween.tween_property(damage_label, "modulate:a", 0.0, 1.0)
	tween.chain().tween_callback(damage_label.queue_free)

func _process(delta):
	if is_defeated:
		return
	
	total_battle_time += delta
	time_in_phase += delta
	
	if current_phase:
		current_phase.update_phase(delta)
	
	if not is_enraged:
		enrage_time_remaining -= delta
		if enrage_time_remaining <= 0:
			trigger_enrage()

func trigger_enrage():
	is_enraged = true
	emit_signal("boss_enraged")
	
	if current_phase:
		current_phase.on_enrage()
	
	var enrage_effect = create_enrage_visual()
	add_child(enrage_effect)

func create_enrage_visual() -> Node3D:
	var particles = GPUParticles3D.new()
	particles.amount = 50
	particles.lifetime = 1.0
	particles.emitting = true
	
	var process_material = ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 2.0
	process_material.initial_velocity_min = 2.0
	process_material.initial_velocity_max = 4.0
	process_material.angular_velocity_min = -180.0
	process_material.angular_velocity_max = 180.0
	process_material.color = Color(1, 0.2, 0.2)
	particles.process_material = process_material
	
	return particles

func defeat_boss():
	is_defeated = true
	current_health = 0
	
	if current_phase:
		current_phase.exit_phase()
	
	emit_signal("boss_defeated")
	play_death_sequence()

func play_death_sequence():
	set_physics_process(false)
	set_process(false)
	
	var death_tween = create_tween()
	death_tween.tween_property(self, "modulate:a", 0.0, 2.0)
	death_tween.tween_callback(queue_free)

func heal(amount: float):
	if is_defeated:
		return
	
	current_health = min(current_health + amount, max_health)
	update_health_bar()

func get_health_percentage() -> float:
	return current_health / max_health

func get_current_phase_name() -> String:
	if current_phase:
		return current_phase.phase_name
	return ""

func force_phase_transition(phase_index: int):
	if phase_index >= 0 and phase_index < phases.size():
		start_phase_transition(phase_index)

func add_phase(phase: BossPhase):
	phases.append(phase)
	phase.phase_index = phases.size() - 1
	phase.boss_system = self

func reset_boss():
	current_health = max_health
	current_phase_index = 0
	is_transitioning = false
	is_enraged = false
	is_defeated = false
	damage_taken_this_phase = 0.0
	time_in_phase = 0.0
	total_battle_time = 0.0
	enrage_time_remaining = enrage_timer
	
	update_health_bar()
	enter_phase(0)