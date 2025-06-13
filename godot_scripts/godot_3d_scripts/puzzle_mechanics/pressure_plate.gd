extends Area

signal activated
signal deactivated
signal weight_changed(current_weight: float)

export var required_weight: float = 50.0
export var weight_tolerance: float = 5.0
export var activation_height: float = 0.05
export var depress_speed: float = 2.0
export var return_speed: float = 1.5
export var requires_continuous_pressure: bool = true
export var activation_sound: AudioStream
export var deactivation_sound: AudioStream
export var plate_material: Material

var current_weight: float = 0.0
var is_active: bool = false
var bodies_on_plate: Dictionary = {}
var plate_depression: float = 0.0
var target_depression: float = 0.0

onready var plate_mesh: MeshInstance = $PlateMesh
onready var collision_shape: CollisionShape = $CollisionShape
onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
onready var particles: CPUParticles = $ActivationParticles

func _ready():
	if not audio_player:
		audio_player = AudioStreamPlayer3D.new()
		add_child(audio_player)
	
	if plate_mesh and plate_material:
		plate_mesh.set_surface_material(0, plate_material)
	
	connect("body_entered", self, "_on_body_entered")
	connect("body_exited", self, "_on_body_exited")
	
	set_physics_process(true)

func _physics_process(delta):
	_update_plate_depression(delta)
	_check_activation_state()

func _on_body_entered(body):
	if not body.has_method("get_weight") and not body is RigidBody:
		return
	
	var weight = _get_body_weight(body)
	bodies_on_plate[body] = weight
	_recalculate_weight()

func _on_body_exited(body):
	if body in bodies_on_plate:
		bodies_on_plate.erase(body)
		_recalculate_weight()

func _get_body_weight(body) -> float:
	if body.has_method("get_weight"):
		return body.get_weight()
	elif body is RigidBody:
		return body.mass * 10.0
	else:
		return 10.0

func _recalculate_weight():
	current_weight = 0.0
	
	for body in bodies_on_plate:
		current_weight += bodies_on_plate[body]
	
	emit_signal("weight_changed", current_weight)
	
	var weight_ratio = clamp(current_weight / required_weight, 0.0, 1.0)
	target_depression = activation_height * weight_ratio

func _update_plate_depression(delta):
	if abs(plate_depression - target_depression) < 0.001:
		return
	
	var speed = depress_speed if target_depression > plate_depression else return_speed
	plate_depression = lerp(plate_depression, target_depression, speed * delta)
	
	if plate_mesh:
		var pos = plate_mesh.translation
		pos.y = -plate_depression
		plate_mesh.translation = pos

func _check_activation_state():
	var should_be_active = _is_weight_sufficient()
	
	if should_be_active and not is_active:
		activate()
	elif not should_be_active and is_active and requires_continuous_pressure:
		deactivate()

func _is_weight_sufficient() -> bool:
	return abs(current_weight - required_weight) <= weight_tolerance or current_weight >= required_weight

func activate():
	if is_active:
		return
	
	is_active = true
	emit_signal("activated")
	
	if activation_sound and audio_player:
		audio_player.stream = activation_sound
		audio_player.play()
	
	if particles:
		particles.emitting = true
	
	_update_visual_state()

func deactivate():
	if not is_active:
		return
	
	is_active = false
	emit_signal("deactivated")
	
	if deactivation_sound and audio_player:
		audio_player.stream = deactivation_sound
		audio_player.play()
	
	if particles:
		particles.emitting = false
	
	_update_visual_state()

func _update_visual_state():
	if not plate_mesh or not plate_mesh.get_surface_material(0):
		return
	
	var mat = plate_mesh.get_surface_material(0)
	if is_active:
		mat.emission_energy = 1.0
		mat.emission = Color.green
	else:
		mat.emission_energy = 0.2
		mat.emission = Color.red

func reset():
	bodies_on_plate.clear()
	current_weight = 0.0
	target_depression = 0.0
	plate_depression = 0.0
	is_active = false
	
	if plate_mesh:
		plate_mesh.translation.y = 0
	
	_update_visual_state()

func set_required_weight(weight: float):
	required_weight = weight
	_recalculate_weight()

func add_weight(amount: float):
	var dummy_body = Node.new()
	bodies_on_plate[dummy_body] = amount
	_recalculate_weight()

func remove_weight(amount: float):
	for body in bodies_on_plate:
		if bodies_on_plate[body] == amount:
			bodies_on_plate.erase(body)
			break
	_recalculate_weight()

func get_progress() -> float:
	return clamp(current_weight / required_weight, 0.0, 1.0)

func get_state() -> Dictionary:
	return {
		"is_active": is_active,
		"current_weight": current_weight,
		"required_weight": required_weight,
		"bodies_count": bodies_on_plate.size()
	}