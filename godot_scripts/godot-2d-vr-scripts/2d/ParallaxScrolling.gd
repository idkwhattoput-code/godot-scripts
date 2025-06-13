extends ParallaxBackground

@export var scroll_speed: Vector2 = Vector2(50, 0)
@export var follow_camera: bool = true
@export var auto_scroll: bool = false
@export var layer_speeds: Array[float] = [0.1, 0.3, 0.6, 1.0]

var camera: Camera2D
var base_offset: Vector2

func _ready():
	if follow_camera:
		camera = get_viewport().get_camera_2d()
		if camera:
			base_offset = scroll_base_offset
	
	setup_layer_speeds()

func _process(delta):
	if auto_scroll:
		scroll_base_offset += scroll_speed * delta
	
	if follow_camera and camera:
		var camera_offset = camera.global_position - camera.get_screen_center_position()
		scroll_base_offset = base_offset + camera_offset * 0.1

func setup_layer_speeds():
	var layers = get_children()
	for i in range(min(layers.size(), layer_speeds.size())):
		if layers[i] is ParallaxLayer:
			var layer = layers[i] as ParallaxLayer
			layer.motion_scale.x = layer_speeds[i]
			layer.motion_scale.y = layer_speeds[i]

func set_scroll_speed(new_speed: Vector2):
	scroll_speed = new_speed

func pause_scrolling():
	auto_scroll = false

func resume_scrolling():
	auto_scroll = true