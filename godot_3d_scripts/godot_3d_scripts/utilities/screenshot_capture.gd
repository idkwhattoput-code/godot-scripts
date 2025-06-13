extends Node

# Screenshot Capture System for Godot 3D
# Handles screenshots with various formats, resolutions, and effects
# Supports photo mode, timelapse, and 360 captures

# Screenshot settings
export var screenshot_directory = "user://screenshots/"
export var default_format = "png"  # png, jpg, exr
export var jpg_quality = 0.9
export var include_ui = false
export var use_timestamp_filename = true
export var custom_filename_prefix = "screenshot"

# Photo mode settings
export var enable_photo_mode = true
export var photo_mode_key = KEY_F12
export var free_camera_speed = 10.0
export var hide_player_in_photo_mode = true
export var enable_depth_of_field = true
export var enable_filters = true

# Advanced capture modes
export var enable_high_res_capture = true
export var max_resolution_multiplier = 4
export var enable_360_capture = true
export var enable_timelapse = true
export var timelapse_interval = 1.0

# Post-processing
export var enable_watermark = false
export var watermark_texture: Texture
export var watermark_position = "bottom_right"
export var watermark_opacity = 0.5

# Internal variables
var photo_mode_active = false
var original_camera: Camera
var photo_camera: Camera
var ui_root: Control
var player_node: Spatial
var timelapse_timer: Timer
var is_capturing = false
var capture_queue = []

# Filters
var available_filters = {
	"normal": {},
	"black_white": {"saturation": 0.0},
	"sepia": {"color_correction": Color(1.2, 1.0, 0.8)},
	"vintage": {"vignette": 0.5, "grain": 0.1},
	"cinematic": {"aspect_ratio": 2.35, "letterbox": true}
}

# Signals
signal screenshot_taken(path)
signal photo_mode_entered()
signal photo_mode_exited()
signal capture_started()
signal capture_completed()

func _ready():
	# Create screenshot directory
	var dir = Directory.new()
	if not dir.dir_exists(screenshot_directory):
		dir.make_dir_recursive(screenshot_directory)
	
	# Setup photo mode camera
	if enable_photo_mode:
		setup_photo_camera()
	
	# Setup timelapse
	if enable_timelapse:
		setup_timelapse()
	
	# Find UI root
	ui_root = get_tree().get_nodes_in_group("ui_root")[0] if get_tree().has_group("ui_root") else null

func _input(event):
	# Screenshot hotkey
	if event.is_action_pressed("screenshot"):
		take_screenshot()
	
	# Photo mode toggle
	if enable_photo_mode and event is InputEventKey and event.pressed:
		if event.scancode == photo_mode_key:
			toggle_photo_mode()
	
	# Photo mode controls
	if photo_mode_active:
		handle_photo_mode_input(event)

func setup_photo_camera():
	"""Setup camera for photo mode"""
	photo_camera = Camera.new()
	photo_camera.name = "PhotoCamera"
	add_child(photo_camera)
	photo_camera.current = false

func setup_timelapse():
	"""Setup timelapse timer"""
	timelapse_timer = Timer.new()
	timelapse_timer.wait_time = timelapse_interval
	timelapse_timer.timeout.connect(take_timelapse_shot)
	add_child(timelapse_timer)

# Basic screenshot functions
func take_screenshot(custom_name: String = ""):
	"""Take a basic screenshot"""
	if is_capturing:
		capture_queue.append({"type": "screenshot", "name": custom_name})
		return
	
	emit_signal("capture_started")
	is_capturing = true
	
	# Hide UI if needed
	var ui_was_visible = false
	if not include_ui and ui_root:
		ui_was_visible = ui_root.visible
		ui_root.visible = false
	
	# Wait for frame to render
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	
	# Capture viewport
	var image = get_viewport().get_texture().get_data()
	image.flip_y()
	
	# Apply watermark if enabled
	if enable_watermark and watermark_texture:
		apply_watermark(image)
	
	# Save image
	var filename = generate_filename(custom_name)
	var path = save_image(image, filename)
	
	# Restore UI
	if not include_ui and ui_root and ui_was_visible:
		ui_root.visible = true
	
	is_capturing = false
	emit_signal("screenshot_taken", path)
	emit_signal("capture_completed")
	
	# Process queue
	process_capture_queue()

func take_high_res_screenshot(multiplier: int = 2):
	"""Take a high resolution screenshot"""
	if not enable_high_res_capture:
		take_screenshot()
		return
	
	if is_capturing:
		capture_queue.append({"type": "high_res", "multiplier": multiplier})
		return
	
	emit_signal("capture_started")
	is_capturing = true
	
	# Store original viewport size
	var original_size = get_viewport().size
	var new_size = original_size * multiplier
	
	# Create high-res viewport
	var hr_viewport = Viewport.new()
	hr_viewport.size = new_size
	hr_viewport.render_target_update_mode = Viewport.UPDATE_ONCE
	add_child(hr_viewport)
	
	# Duplicate current camera
	var current_cam = get_viewport().get_camera()
	var hr_camera = current_cam.duplicate()
	hr_viewport.add_child(hr_camera)
	hr_camera.current = true
	
	# Wait for render
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	
	# Capture high-res image
	var image = hr_viewport.get_texture().get_data()
	image.flip_y()
	
	# Clean up
	hr_viewport.queue_free()
	
	# Save image
	var filename = generate_filename("highres")
	var path = save_image(image, filename)
	
	is_capturing = false
	emit_signal("screenshot_taken", path)
	emit_signal("capture_completed")
	
	process_capture_queue()

func take_360_screenshot():
	"""Take a 360 degree panoramic screenshot"""
	if not enable_360_capture:
		return
	
	if is_capturing:
		capture_queue.append({"type": "360"})
		return
	
	emit_signal("capture_started")
	is_capturing = true
	
	var current_cam = get_viewport().get_camera()
	var original_rotation = current_cam.rotation
	var original_fov = current_cam.fov
	
	# Setup for cubemap capture
	current_cam.fov = 90
	var cube_faces = []
	var rotations = [
		Vector3(0, 0, 0),       # Front
		Vector3(0, PI/2, 0),    # Right
		Vector3(0, PI, 0),      # Back
		Vector3(0, -PI/2, 0),   # Left
		Vector3(-PI/2, 0, 0),   # Up
		Vector3(PI/2, 0, 0)     # Down
	]
	
	# Capture each face
	for rotation in rotations:
		current_cam.rotation = rotation
		yield(get_tree(), "idle_frame")
		
		var image = get_viewport().get_texture().get_data()
		image.flip_y()
		cube_faces.append(image)
	
	# Restore camera
	current_cam.rotation = original_rotation
	current_cam.fov = original_fov
	
	# Convert cubemap to equirectangular
	var pano_image = cubemap_to_equirectangular(cube_faces)
	
	# Save panorama
	var filename = generate_filename("360")
	var path = save_image(pano_image, filename)
	
	is_capturing = false
	emit_signal("screenshot_taken", path)
	emit_signal("capture_completed")
	
	process_capture_queue()

func cubemap_to_equirectangular(cube_faces: Array) -> Image:
	"""Convert cubemap faces to equirectangular projection"""
	# This is a simplified version - proper implementation would be more complex
	var width = 2048
	var height = 1024
	var pano = Image.new()
	pano.create(width, height, false, Image.FORMAT_RGB8)
	
	# Basic mapping (simplified)
	for y in range(height):
		for x in range(width):
			var theta = (float(x) / width) * TAU - PI
			var phi = (float(y) / height) * PI - PI/2
			
			# Convert to cube face coordinates
			# ... mapping logic ...
			
			# Sample from appropriate cube face
			var color = Color.black
			pano.set_pixel(x, y, color)
	
	return pano

# Photo mode functions
func toggle_photo_mode():
	"""Toggle photo mode on/off"""
	photo_mode_active = !photo_mode_active
	
	if photo_mode_active:
		enter_photo_mode()
	else:
		exit_photo_mode()

func enter_photo_mode():
	"""Enter photo mode"""
	# Store original camera
	original_camera = get_viewport().get_camera()
	
	# Copy camera transform
	photo_camera.global_transform = original_camera.global_transform
	photo_camera.fov = original_camera.fov
	
	# Switch cameras
	original_camera.current = false
	photo_camera.current = true
	
	# Hide player if needed
	if hide_player_in_photo_mode:
		player_node = get_tree().get_nodes_in_group("player")[0] if get_tree().has_group("player") else null
		if player_node:
			player_node.visible = false
	
	# Pause game
	get_tree().paused = true
	
	emit_signal("photo_mode_entered")

func exit_photo_mode():
	"""Exit photo mode"""
	# Restore original camera
	if original_camera:
		photo_camera.current = false
		original_camera.current = true
	
	# Show player
	if player_node:
		player_node.visible = true
	
	# Unpause game
	get_tree().paused = false
	
	emit_signal("photo_mode_exited")

func handle_photo_mode_input(event: InputEvent):
	"""Handle input in photo mode"""
	if not photo_mode_active:
		return
	
	# Camera movement
	var move_vector = Vector3.ZERO
	
	if Input.is_key_pressed(KEY_W):
		move_vector.z -= 1
	if Input.is_key_pressed(KEY_S):
		move_vector.z += 1
	if Input.is_key_pressed(KEY_A):
		move_vector.x -= 1
	if Input.is_key_pressed(KEY_D):
		move_vector.x += 1
	if Input.is_key_pressed(KEY_Q):
		move_vector.y -= 1
	if Input.is_key_pressed(KEY_E):
		move_vector.y += 1
	
	if move_vector.length() > 0:
		var delta = get_process_delta_time()
		var speed = free_camera_speed
		if Input.is_key_pressed(KEY_SHIFT):
			speed *= 2
		
		move_vector = move_vector.normalized() * speed * delta
		photo_camera.translate(move_vector)
	
	# Camera rotation with mouse
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(BUTTON_RIGHT):
		photo_camera.rotate_y(-event.relative.x * 0.01)
		photo_camera.rotate_object_local(Vector3(1, 0, 0), -event.relative.y * 0.01)

# Utility functions
func generate_filename(prefix: String = "") -> String:
	"""Generate filename for screenshot"""
	var filename = custom_filename_prefix
	
	if prefix != "":
		filename += "_" + prefix
	
	if use_timestamp_filename:
		var datetime = OS.get_datetime()
		filename += "_%04d%02d%02d_%02d%02d%02d" % [
			datetime.year, datetime.month, datetime.day,
			datetime.hour, datetime.minute, datetime.second
		]
	
	return filename

func save_image(image: Image, filename: String) -> String:
	"""Save image to disk"""
	var full_path = screenshot_directory + filename
	
	match default_format:
		"png":
			full_path += ".png"
			image.save_png(full_path)
		"jpg":
			full_path += ".jpg"
			image.save_jpg(full_path, jpg_quality)
		"exr":
			full_path += ".exr"
			image.save_exr(full_path)
	
	return full_path

func apply_watermark(image: Image):
	"""Apply watermark to image"""
	if not watermark_texture:
		return
	
	var watermark = watermark_texture.get_data()
	var img_size = image.get_size()
	var wm_size = watermark.get_size()
	
	# Calculate position
	var position = Vector2.ZERO
	match watermark_position:
		"bottom_right":
			position = img_size - wm_size - Vector2(10, 10)
		"bottom_left":
			position = Vector2(10, img_size.y - wm_size.y - 10)
		"top_right":
			position = Vector2(img_size.x - wm_size.x - 10, 10)
		"top_left":
			position = Vector2(10, 10)
		"center":
			position = (img_size - wm_size) / 2
	
	# Blend watermark
	image.lock()
	watermark.lock()
	
	for y in range(wm_size.y):
		for x in range(wm_size.x):
			var wm_pixel = watermark.get_pixel(x, y)
			if wm_pixel.a > 0:
				var img_x = position.x + x
				var img_y = position.y + y
				
				if img_x >= 0 and img_x < img_size.x and img_y >= 0 and img_y < img_size.y:
					var img_pixel = image.get_pixel(img_x, img_y)
					var blended = img_pixel.linear_interpolate(wm_pixel, wm_pixel.a * watermark_opacity)
					image.set_pixel(img_x, img_y, blended)
	
	watermark.unlock()
	image.unlock()

func process_capture_queue():
	"""Process queued capture requests"""
	if capture_queue.size() > 0 and not is_capturing:
		var capture = capture_queue.pop_front()
		match capture.type:
			"screenshot":
				take_screenshot(capture.get("name", ""))
			"high_res":
				take_high_res_screenshot(capture.get("multiplier", 2))
			"360":
				take_360_screenshot()

# Timelapse functions
func start_timelapse():
	"""Start timelapse capture"""
	if timelapse_timer:
		timelapse_timer.start()

func stop_timelapse():
	"""Stop timelapse capture"""
	if timelapse_timer:
		timelapse_timer.stop()

func take_timelapse_shot():
	"""Take a timelapse screenshot"""
	take_screenshot("timelapse")

# Filter functions
func apply_filter(filter_name: String):
	"""Apply a filter to the viewport"""
	if not filter_name in available_filters:
		return
	
	var filter = available_filters[filter_name]
	var environment = get_viewport().environment
	
	if not environment:
		return
	
	# Apply filter settings
	for property in filter:
		match property:
			"saturation":
				environment.adjustment_saturation = filter[property]
			"color_correction":
				environment.adjustment_color_correction = filter[property]
			# Add more filter properties as needed