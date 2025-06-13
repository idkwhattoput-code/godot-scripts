extends Node2D

export var sprite_path: NodePath = "Sprite"
export var animation_player_path: NodePath = "AnimationPlayer"
export var default_animation: String = "idle"
export var transition_time: float = 0.1

var current_animation: String = ""
var animation_queue: Array = []
var is_locked: bool = false
var animation_speeds: Dictionary = {}
var animation_callbacks: Dictionary = {}

onready var sprite: Sprite = get_node_or_null(sprite_path)
onready var animation_player: AnimationPlayer = get_node_or_null(animation_player_path)

signal animation_started(anim_name)
signal animation_finished(anim_name)
signal animation_changed(from, to)

func _ready() -> void:
	if animation_player:
		animation_player.connect("animation_finished", self, "_on_animation_finished")
		animation_player.connect("animation_started", self, "_on_animation_started")
		
		if default_animation and animation_player.has_animation(default_animation):
			play_animation(default_animation)
	
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	process_animation_queue()

func play_animation(anim_name: String, force: bool = false, speed: float = 1.0, lock: bool = false) -> void:
	if not animation_player or not animation_player.has_animation(anim_name):
		push_warning("Animation '%s' not found!" % anim_name)
		return
	
	if is_locked and not force:
		queue_animation(anim_name, speed)
		return
	
	if current_animation == anim_name and not force:
		return
	
	var previous_animation: String = current_animation
	current_animation = anim_name
	is_locked = lock
	
	animation_player.playback_speed = speed
	
	if animation_player.current_animation != "" and transition_time > 0:
		var current_pos: float = animation_player.current_animation_position
		animation_player.play(anim_name, -1, speed, false)
		animation_player.seek(min(current_pos, animation_player.current_animation_length), true)
	else:
		animation_player.play(anim_name, -1, speed, false)
	
	emit_signal("animation_changed", previous_animation, anim_name)

func queue_animation(anim_name: String, speed: float = 1.0) -> void:
	animation_queue.append({"name": anim_name, "speed": speed})

func process_animation_queue() -> void:
	if animation_queue.size() > 0 and not is_locked:
		var next_anim: Dictionary = animation_queue.pop_front()
		play_animation(next_anim.name, false, next_anim.speed)

func stop_animation() -> void:
	if animation_player:
		animation_player.stop()
		current_animation = ""
		is_locked = false
		animation_queue.clear()

func pause_animation() -> void:
	if animation_player:
		animation_player.playback_active = false

func resume_animation() -> void:
	if animation_player:
		animation_player.playback_active = true

func set_animation_speed(anim_name: String, speed: float) -> void:
	animation_speeds[anim_name] = speed
	if current_animation == anim_name and animation_player:
		animation_player.playback_speed = speed

func unlock() -> void:
	is_locked = false

func flip_sprite(horizontal: bool = true, vertical: bool = false) -> void:
	if sprite:
		sprite.flip_h = horizontal
		sprite.flip_v = vertical

func set_sprite_frame(frame: int) -> void:
	if sprite and sprite.hframes * sprite.vframes > 1:
		sprite.frame = frame

func get_sprite_frame() -> int:
	if sprite:
		return sprite.frame
	return 0

func register_animation_callback(anim_name: String, callback: FuncRef) -> void:
	if not animation_callbacks.has(anim_name):
		animation_callbacks[anim_name] = []
	animation_callbacks[anim_name].append(callback)

func chain_animations(animations: Array, loop_last: bool = false) -> void:
	if animations.size() == 0:
		return
	
	animation_queue.clear()
	
	for i in range(animations.size()):
		var anim = animations[i]
		if i == 0:
			play_animation(anim.get("name", ""), false, anim.get("speed", 1.0), true)
		else:
			queue_animation(anim.get("name", ""), anim.get("speed", 1.0))
	
	if loop_last and animations.size() > 0:
		var last_anim = animations[-1]
		animation_player.connect("animation_finished", self, "_loop_last_animation", [last_anim], CONNECT_ONESHOT)

func _loop_last_animation(anim_name: String, last_anim: Dictionary) -> void:
	if anim_name == last_anim.get("name", ""):
		play_animation(anim_name, true, last_anim.get("speed", 1.0), false)

func _on_animation_started(anim_name: String) -> void:
	emit_signal("animation_started", anim_name)

func _on_animation_finished(anim_name: String) -> void:
	is_locked = false
	emit_signal("animation_finished", anim_name)
	
	if animation_callbacks.has(anim_name):
		for callback in animation_callbacks[anim_name]:
			if callback.is_valid():
				callback.call_func()
	
	if animation_queue.size() == 0 and default_animation != "":
		play_animation(default_animation)