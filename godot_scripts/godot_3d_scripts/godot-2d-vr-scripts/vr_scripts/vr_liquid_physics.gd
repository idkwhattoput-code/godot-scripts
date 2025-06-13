extends RigidBody

export var liquid_type = "water"
export var viscosity = 1.0
export var pour_rate = 50.0
export var particle_count = 100
export var evaporation_rate = 0.1
export var temperature = 20.0
export var surface_tension = 0.8

signal liquid_poured(amount, target_container)
signal container_filled(fill_percentage)
signal liquid_spilled(amount, position)
signal temperature_changed(new_temperature)

var liquid_amount = 100.0
var max_capacity = 100.0
var is_pouring = false
var pour_target = null
var liquid_particles = []
var container_tilt_threshold = 45.0
var last_rotation = Vector3.ZERO

onready var pour_point = $PourPoint
onready var liquid_mesh = $LiquidMesh
onready var splash_particles = $SplashParticles
onready var pour_sound = $PourSound
onready var splash_sound = $SplashSound
onready var detection_area = $DetectionArea

class LiquidParticle:
	var position : Vector3
	var velocity : Vector3
	var life_time : float = 5.0
	var size : float = 1.0
	var temperature : float = 20.0
	
	func _init(pos, vel):
		position = pos
		velocity = vel

func _ready():
	_setup_liquid_properties()
	_initialize_particle_system()
	
	if detection_area:
		detection_area.connect("body_entered", self, "_on_container_detected")
		detection_area.connect("body_exited", self, "_on_container_lost")

func _setup_liquid_properties():
	match liquid_type:
		"water":
			viscosity = 1.0
			pour_rate = 50.0
			surface_tension = 0.8
		"oil":
			viscosity = 5.0
			pour_rate = 30.0
			surface_tension = 0.3
		"honey":
			viscosity = 50.0
			pour_rate = 10.0
			surface_tension = 1.2
		"mercury":
			viscosity = 1.5
			pour_rate = 40.0
			surface_tension = 3.0

func _initialize_particle_system():
	if splash_particles:
		splash_particles.emitting = false
		splash_particles.amount = particle_count

func _physics_process(delta):
	_check_pouring_state()
	_update_liquid_visual()
	_update_particles(delta)
	_simulate_evaporation(delta)
	_handle_temperature_effects(delta)

func _check_pouring_state():
	var current_rotation = rotation_degrees
	var tilt_angle = abs(current_rotation.z)
	
	if tilt_angle > container_tilt_threshold and liquid_amount > 0:
		if not is_pouring:
			start_pouring()
	else:
		if is_pouring:
			stop_pouring()

func start_pouring():
	if liquid_amount <= 0:
		return
	
	is_pouring = true
	
	if pour_sound:
		pour_sound.play()
	
	if splash_particles:
		splash_particles.emitting = true

func stop_pouring():
	is_pouring = false
	
	if pour_sound:
		pour_sound.stop()
	
	if splash_particles:
		splash_particles.emitting = false

func _update_liquid_visual():
	if not liquid_mesh:
		return
	
	var fill_ratio = liquid_amount / max_capacity
	liquid_mesh.scale.y = fill_ratio
	liquid_mesh.translation.y = -0.5 + (fill_ratio * 0.5)
	
	if liquid_mesh.material_override:
		var mat = liquid_mesh.material_override
		_update_liquid_material(mat, fill_ratio)

func _update_liquid_material(material, fill_ratio):
	if not material:
		return
	
	match liquid_type:
		"water":
			material.albedo_color = Color(0.2, 0.4, 1.0, 0.8)
			material.metallic = 0.0
			material.roughness = 0.1
		"oil":
			material.albedo_color = Color(0.3, 0.2, 0.1, 0.9)
			material.metallic = 0.2
			material.roughness = 0.3
		"honey":
			material.albedo_color = Color(1.0, 0.8, 0.2, 0.95)
			material.metallic = 0.0
			material.roughness = 0.7
		"mercury":
			material.albedo_color = Color(0.8, 0.8, 0.9, 1.0)
			material.metallic = 0.9
			material.roughness = 0.1
	
	if material.has_property("emission_energy"):
		material.emission_energy = (temperature - 20.0) / 100.0

func _update_particles(delta):
	if not is_pouring:
		return
	
	var pour_amount = (pour_rate / viscosity) * delta
	pour_amount = min(pour_amount, liquid_amount)
	
	if pour_amount > 0:
		_create_liquid_stream(pour_amount)
		liquid_amount -= pour_amount
		emit_signal("container_filled", liquid_amount / max_capacity)

func _create_liquid_stream(amount):
	if not pour_point:
		return
	
	var stream_particles = int(amount * 0.1)
	
	for i in range(stream_particles):
		var particle = LiquidParticle.new(
			pour_point.global_transform.origin,
			-global_transform.basis.y * (5.0 / viscosity) + Vector3(
				rand_range(-0.5, 0.5),
				rand_range(-0.5, 0.5),
				rand_range(-0.5, 0.5)
			)
		)
		particle.temperature = temperature
		liquid_particles.append(particle)
	
	_check_particle_collisions(amount)

func _check_particle_collisions(amount):
	if pour_target and pour_target.has_method("receive_liquid"):
		pour_target.receive_liquid(liquid_type, amount, temperature)
		emit_signal("liquid_poured", amount, pour_target)
	else:
		var spill_pos = pour_point.global_transform.origin if pour_point else global_transform.origin
		emit_signal("liquid_spilled", amount, spill_pos)
		_create_spill_effect(spill_pos, amount)

func _create_spill_effect(position, amount):
	if splash_sound:
		splash_sound.play()
	
	var spill_particles = int(amount * 0.2)
	for i in range(spill_particles):
		var particle = LiquidParticle.new(
			position,
			Vector3(
				rand_range(-2, 2),
				rand_range(1, 3),
				rand_range(-2, 2)
			)
		)
		liquid_particles.append(particle)

func _simulate_evaporation(delta):
	if temperature > 30.0:
		var evap_amount = evaporation_rate * (temperature - 30.0) * delta
		liquid_amount = max(0, liquid_amount - evap_amount)

func _handle_temperature_effects(delta):
	var ambient_temp = 20.0
	var temp_diff = ambient_temp - temperature
	temperature += temp_diff * 0.1 * delta
	
	if temperature != temperature:
		emit_signal("temperature_changed", temperature)

func _on_container_detected(body):
	if body.has_method("receive_liquid"):
		pour_target = body

func _on_container_lost(body):
	if body == pour_target:
		pour_target = null

func receive_liquid(type, amount, temp):
	if type == liquid_type or liquid_type == "empty":
		liquid_type = type
		temperature = (temperature * liquid_amount + temp * amount) / (liquid_amount + amount)
		liquid_amount = min(liquid_amount + amount, max_capacity)
		emit_signal("container_filled", liquid_amount / max_capacity)
		return amount
	else:
		_mix_liquids(type, amount, temp)
		return amount * 0.5

func _mix_liquids(other_type, amount, temp):
	var total_amount = liquid_amount + amount
	if total_amount > max_capacity:
		var overflow = total_amount - max_capacity
		emit_signal("liquid_spilled", overflow, global_transform.origin)
		amount -= overflow
		total_amount = max_capacity
	
	temperature = (temperature * liquid_amount + temp * amount) / total_amount
	liquid_amount = total_amount
	
	liquid_type = "mixture"
	_setup_liquid_properties()

func heat_liquid(heat_amount):
	temperature += heat_amount
	temperature = min(temperature, 100.0)
	emit_signal("temperature_changed", temperature)

func cool_liquid(cool_amount):
	temperature -= cool_amount
	temperature = max(temperature, -20.0)
	emit_signal("temperature_changed", temperature)

func empty_container():
	liquid_amount = 0.0
	liquid_type = "empty"
	emit_signal("container_filled", 0.0)

func get_fill_percentage():
	return liquid_amount / max_capacity

func is_container_full():
	return liquid_amount >= max_capacity

func is_container_empty():
	return liquid_amount <= 0

func get_liquid_info():
	return {
		"type": liquid_type,
		"amount": liquid_amount,
		"temperature": temperature,
		"viscosity": viscosity,
		"fill_percentage": get_fill_percentage()
	}

func set_liquid_properties(props):
	if "viscosity" in props:
		viscosity = props.viscosity
	if "pour_rate" in props:
		pour_rate = props.pour_rate
	if "surface_tension" in props:
		surface_tension = props.surface_tension