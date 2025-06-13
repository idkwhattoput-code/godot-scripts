extends Spatial

class_name FloatingDamageNumber

signal animation_completed()

export var damage_text: String = "0"
export var text_color: Color = Color.white
export var critical_color: Color = Color(1.0, 0.8, 0.0)
export var heal_color: Color = Color(0.0, 1.0, 0.0)
export var font_size: int = 24
export var outline_size: int = 2
export var outline_color: Color = Color.black
export var float_height: float = 2.0
export var float_duration: float = 1.5
export var spread_radius: float = 0.5
export var fade_start_percent: float = 0.6
export var scale_animation: bool = true
export var critical_scale: float = 1.5
export var bounce_animation: bool = false
export var follow_target: bool = false

var damage_type: String = "normal"
var is_critical: bool = false
var target_node: Spatial = null
var initial_position: Vector3
var velocity: Vector3
var lifetime: float = 0.0
var label_3d: Label3D

func _ready():
	create_label()
	setup_animation()
	set_process(true)

func create_label():
	label_3d = Label3D.new()
	label_3d.text = damage_text
	label_3d.billboard = Label3D.BILLBOARD_ENABLED
	label_3d.no_depth_test = true
	label_3d.fixed_size = true
	label_3d.pixel_size = 0.001 * font_size
	label_3d.outline_size = outline_size
	label_3d.outline_modulate = outline_color
	
	apply_text_style()
	add_child(label_3d)

func apply_text_style():
	match damage_type:
		"critical":
			label_3d.modulate = critical_color
			is_critical = true
		"heal":
			label_3d.modulate = heal_color
		"poison":
			label_3d.modulate = Color(0.5, 1.0, 0.0)
		"fire":
			label_3d.modulate = Color(1.0, 0.5, 0.0)
		"ice":
			label_3d.modulate = Color(0.5, 0.8, 1.0)
		"lightning":
			label_3d.modulate = Color(1.0, 1.0, 0.5)
		_:
			label_3d.modulate = text_color

func setup_animation():
	initial_position = global_transform.origin
	
	var random_offset = Vector3(
		rand_range(-spread_radius, spread_radius),
		0,
		rand_range(-spread_radius, spread_radius)
	)
	
	initial_position += random_offset
	global_transform.origin = initial_position
	
	velocity = Vector3(
		rand_range(-0.5, 0.5),
		rand_range(2.0, 3.0),
		rand_range(-0.5, 0.5)
	)
	
	if is_critical and scale_animation:
		label_3d.scale = Vector3.ONE * critical_scale

func _process(delta):
	lifetime += delta
	var progress = lifetime / float_duration
	
	if progress >= 1.0:
		queue_free()
		emit_signal("animation_completed")
		return
	
	update_position(delta, progress)
	update_opacity(progress)
	update_scale(progress)

func update_position(delta: float, progress: float):
	if follow_target and is_instance_valid(target_node):
		initial_position = target_node.global_transform.origin
	
	velocity.y -= 2.0 * delta
	
	var new_position = global_transform.origin + velocity * delta
	
	if bounce_animation:
		var bounce_height = sin(progress * PI) * 0.5
		new_position.y += bounce_height * delta * 10.0
	
	global_transform.origin = new_position

func update_opacity(progress: float):
	if progress >= fade_start_percent:
		var fade_progress = (progress - fade_start_percent) / (1.0 - fade_start_percent)
		label_3d.modulate.a = 1.0 - fade_progress

func update_scale(progress: float):
	if not scale_animation:
		return
	
	var scale_value = 1.0
	
	if is_critical:
		scale_value = critical_scale * (1.0 + sin(progress * PI * 2) * 0.1)
	else:
		if progress < 0.2:
			scale_value = progress * 5.0
		elif progress > 0.8:
			scale_value = 1.0 - ((progress - 0.8) * 5.0)
	
	label_3d.scale = Vector3.ONE * scale_value

func set_damage_value(value: float, type: String = "normal"):
	damage_text = format_damage_text(value, type)
	damage_type = type
	
	if label_3d:
		label_3d.text = damage_text
		apply_text_style()

func format_damage_text(value: float, type: String) -> String:
	var formatted_text = ""
	
	if value >= 1000000:
		formatted_text = "%.1fM" % (value / 1000000.0)
	elif value >= 1000:
		formatted_text = "%.1fK" % (value / 1000.0)
	else:
		formatted_text = str(int(value))
	
	match type:
		"critical":
			formatted_text = formatted_text + "!"
		"heal":
			formatted_text = "+" + formatted_text
		"dodge":
			formatted_text = "Dodge!"
		"miss":
			formatted_text = "Miss!"
		"block":
			formatted_text = "Block!"
		"immune":
			formatted_text = "Immune!"
	
	return formatted_text

func set_target(target: Spatial):
	target_node = target
	follow_target = true

func set_custom_animation(animation_data: Dictionary):
	if "float_height" in animation_data:
		float_height = animation_data.float_height
	if "float_duration" in animation_data:
		float_duration = animation_data.float_duration
	if "spread_radius" in animation_data:
		spread_radius = animation_data.spread_radius
	if "bounce" in animation_data:
		bounce_animation = animation_data.bounce

static func create_damage_number(position: Vector3, damage: float, type: String = "normal") -> FloatingDamageNumber:
	var damage_number = preload("res://ui/FloatingDamageNumber.tscn").instance()
	damage_number.global_transform.origin = position
	damage_number.set_damage_value(damage, type)
	return damage_number

class FloatingDamageManager extends Node:
	
	var damage_number_pool: Array = []
	var active_numbers: Array = []
	var max_pool_size: int = 50
	var damage_number_scene = preload("res://ui/FloatingDamageNumber.tscn")
	
	func _ready():
		create_pool()
	
	func create_pool():
		for i in range(max_pool_size):
			var damage_number = damage_number_scene.instance()
			damage_number.visible = false
			damage_number.set_process(false)
			add_child(damage_number)
			damage_number_pool.append(damage_number)
	
	func spawn_damage_number(position: Vector3, damage: float, type: String = "normal") -> FloatingDamageNumber:
		var damage_number = get_from_pool()
		
		if not damage_number:
			damage_number = damage_number_scene.instance()
			add_child(damage_number)
		
		damage_number.global_transform.origin = position
		damage_number.set_damage_value(damage, type)
		damage_number.visible = true
		damage_number.set_process(true)
		damage_number.lifetime = 0.0
		
		active_numbers.append(damage_number)
		damage_number.connect("animation_completed", self, "_on_number_completed", [damage_number], CONNECT_ONESHOT)
		
		return damage_number
	
	func get_from_pool() -> FloatingDamageNumber:
		if damage_number_pool.size() > 0:
			return damage_number_pool.pop_back()
		return null
	
	func return_to_pool(damage_number: FloatingDamageNumber):
		damage_number.visible = false
		damage_number.set_process(false)
		damage_number.target_node = null
		damage_number.follow_target = false
		
		if damage_number_pool.size() < max_pool_size:
			damage_number_pool.append(damage_number)
		else:
			damage_number.queue_free()
	
	func _on_number_completed(damage_number: FloatingDamageNumber):
		active_numbers.erase(damage_number)
		return_to_pool(damage_number)
	
	func spawn_combat_text(position: Vector3, text: String, color: Color = Color.white):
		var damage_number = spawn_damage_number(position, 0, "normal")
		damage_number.damage_text = text
		damage_number.label_3d.text = text
		damage_number.label_3d.modulate = color
	
	func clear_all():
		for number in active_numbers:
			number.queue_free()
		active_numbers.clear()
		
		for number in damage_number_pool:
			number.queue_free()
		damage_number_pool.clear()