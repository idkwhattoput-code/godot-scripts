extends Area

signal activated
signal deactivated
signal state_changed(is_active: bool)

export var switch_type: int = SwitchType.TOGGLE
export var activation_delay: float = 0.0
export var auto_deactivate: bool = false
export var auto_deactivate_time: float = 5.0
export var requires_item: String = ""
export var consumes_item: bool = false
export var activation_sound: AudioStream
export var deactivation_sound: AudioStream
export var interaction_prompt: String = "Press E to activate"

enum SwitchType {
	TOGGLE,
	HOLD,
	TIMED,
	SEQUENCE,
	PRESSURE
}

var is_active: bool = false
var can_interact: bool = true
var activation_timer: Timer
var deactivation_timer: Timer
var interacting_body: Node = null

onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
onready var animation_player: AnimationPlayer = $AnimationPlayer
onready var visual_indicator: MeshInstance = $VisualIndicator

func _ready():
	if not audio_player:
		audio_player = AudioStreamPlayer3D.new()
		add_child(audio_player)
	
	if activation_delay > 0:
		activation_timer = Timer.new()
		activation_timer.wait_time = activation_delay
		activation_timer.one_shot = true
		activation_timer.connect("timeout", self, "_delayed_activation")
		add_child(activation_timer)
	
	if auto_deactivate:
		deactivation_timer = Timer.new()
		deactivation_timer.wait_time = auto_deactivate_time
		deactivation_timer.one_shot = true
		deactivation_timer.connect("timeout", self, "deactivate")
		add_child(deactivation_timer)
	
	connect("body_entered", self, "_on_body_entered")
	connect("body_exited", self, "_on_body_exited")
	
	_update_visual_state()

func _on_body_entered(body):
	if not body.is_in_group("player"):
		return
		
	interacting_body = body
	
	if switch_type == SwitchType.PRESSURE:
		activate()
	elif body.has_method("show_interaction_prompt"):
		body.show_interaction_prompt(interaction_prompt)

func _on_body_exited(body):
	if body != interacting_body:
		return
		
	if switch_type == SwitchType.PRESSURE:
		deactivate()
	elif switch_type == SwitchType.HOLD and is_active:
		deactivate()
	
	if body.has_method("hide_interaction_prompt"):
		body.hide_interaction_prompt()
	
	interacting_body = null

func interact(interactor: Node = null):
	if not can_interact:
		return false
		
	if requires_item != "" and interactor:
		if not _check_required_item(interactor):
			return false
	
	match switch_type:
		SwitchType.TOGGLE:
			if is_active:
				deactivate()
			else:
				activate()
		SwitchType.HOLD:
			activate()
		SwitchType.TIMED:
			activate()
		SwitchType.SEQUENCE:
			if not is_active:
				activate()
	
	return true

func _check_required_item(interactor: Node) -> bool:
	if not interactor.has_method("has_item"):
		return false
		
	if not interactor.has_item(requires_item):
		if interactor.has_method("show_message"):
			interactor.show_message("Requires: " + requires_item)
		return false
	
	if consumes_item and interactor.has_method("remove_item"):
		interactor.remove_item(requires_item)
	
	return true

func activate():
	if is_active:
		return
		
	if activation_delay > 0:
		activation_timer.start()
		can_interact = false
	else:
		_perform_activation()

func _delayed_activation():
	can_interact = true
	_perform_activation()

func _perform_activation():
	is_active = true
	emit_signal("activated")
	emit_signal("state_changed", true)
	
	if activation_sound and audio_player:
		audio_player.stream = activation_sound
		audio_player.play()
	
	if animation_player and animation_player.has_animation("activate"):
		animation_player.play("activate")
	
	_update_visual_state()
	
	if auto_deactivate and deactivation_timer:
		deactivation_timer.start()

func deactivate():
	if not is_active:
		return
		
	is_active = false
	emit_signal("deactivated")
	emit_signal("state_changed", false)
	
	if deactivation_sound and audio_player:
		audio_player.stream = deactivation_sound
		audio_player.play()
	
	if animation_player and animation_player.has_animation("deactivate"):
		animation_player.play("deactivate")
	
	_update_visual_state()
	
	if deactivation_timer:
		deactivation_timer.stop()

func reset():
	is_active = false
	can_interact = true
	interacting_body = null
	
	if activation_timer:
		activation_timer.stop()
	if deactivation_timer:
		deactivation_timer.stop()
	
	_update_visual_state()

func _update_visual_state():
	if not visual_indicator:
		return
		
	if is_active:
		visual_indicator.get_surface_material(0).emission_energy = 2.0
		visual_indicator.get_surface_material(0).emission = Color.green
	else:
		visual_indicator.get_surface_material(0).emission_energy = 0.5
		visual_indicator.get_surface_material(0).emission = Color.red

func set_active(active: bool):
	if active:
		activate()
	else:
		deactivate()

func toggle():
	if is_active:
		deactivate()
	else:
		activate()

func get_state() -> Dictionary:
	return {
		"is_active": is_active,
		"can_interact": can_interact
	}