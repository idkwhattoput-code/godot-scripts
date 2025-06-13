extends ParallaxBackground

export var auto_scroll: bool = false
export var scroll_speed: Vector2 = Vector2(20, 0)
export var wind_effect: bool = false
export var wind_strength: float = 10.0
export var wind_frequency: float = 2.0

var time: float = 0.0
var base_offsets: Dictionary = {}
var layer_configs: Array = []

onready var camera: Camera2D = get_viewport().get_camera()

func _ready() -> void:
	setup_parallax_layers()
	store_base_offsets()
	
	set_physics_process(true)

func setup_parallax_layers() -> void:
	layer_configs = [
		{"name": "Sky", "scale": 0.1, "offset": Vector2(0, -200), "mirroring": Vector2(1920, 0)},
		{"name": "Clouds", "scale": 0.3, "offset": Vector2(0, -150), "mirroring": Vector2(1920, 0)},
		{"name": "Mountains", "scale": 0.5, "offset": Vector2(0, -100), "mirroring": Vector2(1920, 0)},
		{"name": "Trees", "scale": 0.7, "offset": Vector2(0, -50), "mirroring": Vector2(1920, 0)},
		{"name": "Foreground", "scale": 1.0, "offset": Vector2(0, 0), "mirroring": Vector2(1920, 0)}
	]
	
	for config in layer_configs:
		var layer = get_node_or_null(config.name)
		if layer and layer is ParallaxLayer:
			layer.motion_scale = Vector2(config.scale, config.scale)
			layer.motion_offset = config.offset
			layer.motion_mirroring = config.mirroring

func store_base_offsets() -> void:
	for child in get_children():
		if child is ParallaxLayer:
			base_offsets[child.name] = child.motion_offset

func _physics_process(delta: float) -> void:
	time += delta
	
	if auto_scroll:
		apply_auto_scroll(delta)
	
	if wind_effect:
		apply_wind_effect()
	
	update_layer_positions()

func apply_auto_scroll(delta: float) -> void:
	scroll_offset += scroll_speed * delta

func apply_wind_effect() -> void:
	for child in get_children():
		if child is ParallaxLayer and base_offsets.has(child.name):
			var wind_offset = Vector2(
				sin(time * wind_frequency) * wind_strength * child.motion_scale.x,
				0
			)
			child.motion_offset = base_offsets[child.name] + wind_offset

func update_layer_positions() -> void:
	if not camera:
		camera = get_viewport().get_camera()
		return
	
	var camera_center = camera.get_camera_screen_center()
	
	for child in get_children():
		if child is ParallaxLayer:
			var layer = child as ParallaxLayer
			
			if layer.has_node("Sprite"):
				var sprite = layer.get_node("Sprite")
				if sprite and sprite is Sprite:
					var texture_size = sprite.texture.get_size()
					var screen_size = get_viewport().size
					
					if texture_size.x < screen_size.x * 2:
						layer.motion_mirroring.x = texture_size.x
					
					if texture_size.y < screen_size.y * 2:
						layer.motion_mirroring.y = texture_size.y

func add_parallax_layer(texture: Texture, scale: float = 1.0, offset: Vector2 = Vector2.ZERO, layer_name: String = "") -> ParallaxLayer:
	var layer = ParallaxLayer.new()
	var sprite = Sprite.new()
	
	sprite.texture = texture
	sprite.centered = false
	
	layer.add_child(sprite)
	layer.motion_scale = Vector2(scale, scale)
	layer.motion_offset = offset
	layer.motion_mirroring = Vector2(texture.get_size().x, 0)
	
	if layer_name != "":
		layer.name = layer_name
	
	add_child(layer)
	move_child(layer, 0)
	
	base_offsets[layer.name] = offset
	
	return layer

func set_scroll_speed(new_speed: Vector2) -> void:
	scroll_speed = new_speed

func set_wind_parameters(strength: float, frequency: float) -> void:
	wind_strength = strength
	wind_frequency = frequency

func reset_scroll_offset() -> void:
	scroll_offset = Vector2.ZERO
	time = 0.0
	
	for child in get_children():
		if child is ParallaxLayer and base_offsets.has(child.name):
			child.motion_offset = base_offsets[child.name]

func get_layer(layer_name: String) -> ParallaxLayer:
	return get_node_or_null(layer_name) as ParallaxLayer