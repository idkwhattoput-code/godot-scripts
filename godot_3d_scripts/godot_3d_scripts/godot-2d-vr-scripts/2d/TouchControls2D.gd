extends Node2D

class_name TouchControls2D

signal joystick_input(direction, strength)
signal button_pressed(button_name)
signal button_released(button_name)
signal swipe_detected(direction, speed)
signal pinch_detected(scale_factor)
signal rotation_detected(angle)
signal double_tap(position)
signal long_press(position)

export var enable_virtual_joystick: bool = true
export var joystick_position: Vector2 = Vector2(150, 400)
export var joystick_size: float = 100.0
export var joystick_dead_zone: float = 0.2
export var joystick_dynamic: bool = false
export var joystick_opacity: float = 0.5

export var enable_buttons: bool = true
export var button_size: float = 60.0
export var button_opacity: float = 0.6
export var button_haptic_feedback: bool = true

export var enable_gestures: bool = true
export var swipe_threshold: float = 50.0
export var swipe_time_limit: float = 0.5
export var pinch_threshold: float = 0.1
export var rotation_threshold: float = 10.0
export var double_tap_time: float = 0.3
export var long_press_time: float = 0.5

export var enable_multitouch: bool = true
export var max_touch_points: int = 10

var touches: Dictionary = {}
var virtual_joystick: VirtualJoystick
var virtual_buttons: Dictionary = {}
var gesture_detector: GestureDetector
var button_layout: ButtonLayout

class Touch:
	var id: int
	var start_position: Vector2
	var current_position: Vector2
	var previous_position: Vector2
	var start_time: float
	var is_moving: bool = false
	var assigned_control: String = ""
	
	func _init(touch_id: int, pos: Vector2):
		id = touch_id
		start_position = pos
		current_position = pos
		previous_position = pos
		start_time = OS.get_ticks_msec() / 1000.0

class VirtualJoystick:
	var base: Sprite
	var stick: Sprite
	var position: Vector2
	var size: float
	var dead_zone: float
	var is_active: bool = false
	var touch_id: int = -1
	var direction: Vector2 = Vector2.ZERO
	var strength: float = 0.0
	var dynamic_position: Vector2
	
	func _init(pos: Vector2, s: float, dz: float):
		position = pos
		size = s
		dead_zone = dz
		dynamic_position = pos

class VirtualButton:
	var sprite: Sprite
	var label: Label
	var position: Vector2
	var size: float
	var action: String
	var is_pressed: bool = false
	var touch_id: int = -1
	var custom_texture: Texture = null
	var normal_color: Color = Color(1, 1, 1, 0.6)
	var pressed_color: Color = Color(1, 1, 1, 1.0)
	
	func _init(pos: Vector2, s: float, act: String):
		position = pos
		size = s
		action = act

class GestureDetector:
	var swipe_start_position: Vector2
	var swipe_start_time: float
	var last_tap_time: float = 0.0
	var last_tap_position: Vector2
	var pinch_start_distance: float = 0.0
	var rotation_start_angle: float = 0.0
	var long_press_timer: float = 0.0
	var long_press_position: Vector2
	var is_long_pressing: bool = false
	
	func reset():
		swipe_start_position = Vector2.ZERO
		swipe_start_time = 0.0
		pinch_start_distance = 0.0
		rotation_start_angle = 0.0
		long_press_timer = 0.0
		is_long_pressing = false

class ButtonLayout:
	var layouts: Dictionary = {}
	
	func _init():
		create_default_layouts()
	
	func create_default_layouts():
		layouts["platformer"] = [
			{"action": "left", "position": Vector2(100, 450), "label": "←"},
			{"action": "right", "position": Vector2(200, 450), "label": "→"},
			{"action": "jump", "position": Vector2(520, 400), "label": "A"},
			{"action": "action", "position": Vector2(600, 350), "label": "B"}
		]
		
		layouts["top_down"] = [
			{"action": "action1", "position": Vector2(520, 400), "label": "1"},
			{"action": "action2", "position": Vector2(600, 400), "label": "2"},
			{"action": "action3", "position": Vector2(560, 320), "label": "3"},
			{"action": "menu", "position": Vector2(300, 50), "label": "☰"}
		]
		
		layouts["fighter"] = [
			{"action": "punch", "position": Vector2(480, 400), "label": "P"},
			{"action": "kick", "position": Vector2(560, 400), "label": "K"},
			{"action": "block", "position": Vector2(520, 320), "label": "B"},
			{"action": "special", "position": Vector2(600, 320), "label": "S"}
		]

func _ready():
	set_process_input(true)
	
	gesture_detector = GestureDetector.new()
	button_layout = ButtonLayout.new()
	
	if enable_virtual_joystick:
		create_virtual_joystick()
	
	if enable_buttons:
		create_virtual_buttons("platformer")

func create_virtual_joystick():
	virtual_joystick = VirtualJoystick.new(joystick_position, joystick_size, joystick_dead_zone)
	
	virtual_joystick.base = Sprite.new()
	virtual_joystick.base.texture = create_circle_texture(joystick_size, Color(0.3, 0.3, 0.3, joystick_opacity))
	virtual_joystick.base.position = joystick_position
	add_child(virtual_joystick.base)
	
	virtual_joystick.stick = Sprite.new()
	virtual_joystick.stick.texture = create_circle_texture(joystick_size * 0.5, Color(0.6, 0.6, 0.6, joystick_opacity))
	virtual_joystick.stick.position = joystick_position
	add_child(virtual_joystick.stick)
	
	if joystick_dynamic:
		virtual_joystick.base.visible = false
		virtual_joystick.stick.visible = false

func create_virtual_buttons(layout_name: String):
	clear_buttons()
	
	if not layout_name in button_layout.layouts:
		return
	
	var layout = button_layout.layouts[layout_name]
	
	for button_config in layout:
		var button = VirtualButton.new(
			button_config.position,
			button_size,
			button_config.action
		)
		
		button.sprite = Sprite.new()
		button.sprite.texture = create_circle_texture(button_size, button.normal_color)
		button.sprite.position = button.position
		add_child(button.sprite)
		
		button.label = Label.new()
		button.label.text = button_config.label
		button.label.align = Label.ALIGN_CENTER
		button.label.valign = Label.VALIGN_CENTER
		button.label.rect_position = button.position - Vector2(20, 10)
		button.label.rect_size = Vector2(40, 20)
		add_child(button.label)
		
		virtual_buttons[button_config.action] = button

func create_circle_texture(size: float, color: Color) -> ImageTexture:
	var image = Image.new()
	image.create(int(size), int(size), false, Image.FORMAT_RGBA8)
	image.lock()
	
	var center = size / 2
	for y in range(size):
		for x in range(size):
			var distance = Vector2(x - center, y - center).length()
			if distance <= center:
				var alpha = color.a * (1.0 - (distance / center) * 0.3)
				image.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	
	image.unlock()
	
	var texture = ImageTexture.new()
	texture.create_from_image(image)
	return texture

func _input(event):
	if event is InputEventScreenTouch:
		handle_touch(event)
	elif event is InputEventScreenDrag:
		handle_drag(event)

func handle_touch(event: InputEventScreenTouch):
	if event.pressed:
		if touches.size() >= max_touch_points:
			return
		
		var touch = Touch.new(event.index, event.position)
		touches[event.index] = touch
		
		if check_joystick_touch(touch):
			return
		
		if check_button_touch(touch):
			return
		
		if enable_gestures:
			check_gesture_start(touch)
	else:
		if event.index in touches:
			var touch = touches[event.index]
			
			if touch.assigned_control == "joystick":
				release_joystick()
			elif touch.assigned_control != "":
				release_button(touch.assigned_control)
			
			if enable_gestures:
				check_gesture_end(touch)
			
			touches.erase(event.index)

func handle_drag(event: InputEventScreenDrag):
	if not event.index in touches:
		return
	
	var touch = touches[event.index]
	touch.previous_position = touch.current_position
	touch.current_position = event.position
	touch.is_moving = true
	
	if touch.assigned_control == "joystick":
		update_joystick(touch)
	
	if enable_gestures and touches.size() >= 2:
		check_multitouch_gestures()

func check_joystick_touch(touch: Touch) -> bool:
	if not enable_virtual_joystick:
		return false
	
	if joystick_dynamic:
		virtual_joystick.dynamic_position = touch.start_position
		virtual_joystick.base.position = touch.start_position
		virtual_joystick.stick.position = touch.start_position
		virtual_joystick.base.visible = true
		virtual_joystick.stick.visible = true
		virtual_joystick.is_active = true
		virtual_joystick.touch_id = touch.id
		touch.assigned_control = "joystick"
		return true
	else:
		var distance = touch.start_position.distance_to(virtual_joystick.position)
		if distance <= virtual_joystick.size:
			virtual_joystick.is_active = true
			virtual_joystick.touch_id = touch.id
			touch.assigned_control = "joystick"
			update_joystick(touch)
			return true
	
	return false

func check_button_touch(touch: Touch) -> bool:
	if not enable_buttons:
		return false
	
	for action in virtual_buttons:
		var button = virtual_buttons[action]
		var distance = touch.start_position.distance_to(button.position)
		
		if distance <= button.size / 2:
			button.is_pressed = true
			button.touch_id = touch.id
			button.sprite.texture = create_circle_texture(button.size, button.pressed_color)
			touch.assigned_control = action
			
			emit_signal("button_pressed", action)
			
			if button_haptic_feedback and OS.has_feature("mobile"):
				Input.vibrate_handheld(20)
			
			return true
	
	return false

func update_joystick(touch: Touch):
	if not virtual_joystick.is_active:
		return
	
	var base_pos = virtual_joystick.dynamic_position if joystick_dynamic else virtual_joystick.position
	var offset = touch.current_position - base_pos
	var distance = offset.length()
	
	if distance > virtual_joystick.size / 2:
		offset = offset.normalized() * (virtual_joystick.size / 2)
		distance = virtual_joystick.size / 2
	
	virtual_joystick.stick.position = base_pos + offset
	
	var strength = distance / (virtual_joystick.size / 2)
	if strength < virtual_joystick.dead_zone:
		virtual_joystick.direction = Vector2.ZERO
		virtual_joystick.strength = 0.0
	else:
		virtual_joystick.direction = offset.normalized()
		virtual_joystick.strength = (strength - virtual_joystick.dead_zone) / (1.0 - virtual_joystick.dead_zone)
	
	emit_signal("joystick_input", virtual_joystick.direction, virtual_joystick.strength)

func release_joystick():
	virtual_joystick.is_active = false
	virtual_joystick.touch_id = -1
	virtual_joystick.direction = Vector2.ZERO
	virtual_joystick.strength = 0.0
	
	if joystick_dynamic:
		virtual_joystick.base.visible = false
		virtual_joystick.stick.visible = false
	else:
		virtual_joystick.stick.position = virtual_joystick.position
	
	emit_signal("joystick_input", Vector2.ZERO, 0.0)

func release_button(action: String):
	if not action in virtual_buttons:
		return
	
	var button = virtual_buttons[action]
	button.is_pressed = false
	button.touch_id = -1
	button.sprite.texture = create_circle_texture(button.size, button.normal_color)
	
	emit_signal("button_released", action)

func check_gesture_start(touch: Touch):
	gesture_detector.swipe_start_position = touch.start_position
	gesture_detector.swipe_start_time = touch.start_time
	
	var current_time = OS.get_ticks_msec() / 1000.0
	if current_time - gesture_detector.last_tap_time < double_tap_time:
		var distance = touch.start_position.distance_to(gesture_detector.last_tap_position)
		if distance < 50:
			emit_signal("double_tap", touch.start_position)
			gesture_detector.last_tap_time = 0.0
			return
	
	gesture_detector.last_tap_time = current_time
	gesture_detector.last_tap_position = touch.start_position
	gesture_detector.long_press_position = touch.start_position
	gesture_detector.long_press_timer = 0.0
	gesture_detector.is_long_pressing = true

func check_gesture_end(touch: Touch):
	var current_time = OS.get_ticks_msec() / 1000.0
	var duration = current_time - touch.start_time
	
	if duration < swipe_time_limit and touch.is_moving:
		var swipe_distance = touch.current_position - touch.start_position
		if swipe_distance.length() > swipe_threshold:
			var direction = swipe_distance.normalized()
			var speed = swipe_distance.length() / duration
			emit_signal("swipe_detected", direction, speed)
	
	gesture_detector.is_long_pressing = false

func check_multitouch_gestures():
	if touches.size() < 2:
		return
	
	var touch_positions = []
	for id in touches:
		touch_positions.append(touches[id].current_position)
	
	if touch_positions.size() >= 2:
		var current_distance = touch_positions[0].distance_to(touch_positions[1])
		var current_angle = (touch_positions[1] - touch_positions[0]).angle()
		
		if gesture_detector.pinch_start_distance == 0:
			gesture_detector.pinch_start_distance = current_distance
			gesture_detector.rotation_start_angle = current_angle
		else:
			var scale_factor = current_distance / gesture_detector.pinch_start_distance
			if abs(scale_factor - 1.0) > pinch_threshold:
				emit_signal("pinch_detected", scale_factor)
				gesture_detector.pinch_start_distance = current_distance
			
			var angle_diff = rad2deg(current_angle - gesture_detector.rotation_start_angle)
			if abs(angle_diff) > rotation_threshold:
				emit_signal("rotation_detected", angle_diff)
				gesture_detector.rotation_start_angle = current_angle

func _process(delta):
	if not enable_gestures:
		return
	
	if gesture_detector.is_long_pressing:
		gesture_detector.long_press_timer += delta
		if gesture_detector.long_press_timer >= long_press_time:
			emit_signal("long_press", gesture_detector.long_press_position)
			gesture_detector.is_long_pressing = false

func get_joystick_input() -> Vector2:
	if virtual_joystick and virtual_joystick.is_active:
		return virtual_joystick.direction * virtual_joystick.strength
	return Vector2.ZERO

func is_button_pressed(action: String) -> bool:
	if action in virtual_buttons:
		return virtual_buttons[action].is_pressed
	return false

func set_button_layout(layout_name: String):
	if enable_buttons:
		create_virtual_buttons(layout_name)

func add_custom_button(action: String, position: Vector2, label: String = ""):
	if not enable_buttons:
		return
	
	var button = VirtualButton.new(position, button_size, action)
	
	button.sprite = Sprite.new()
	button.sprite.texture = create_circle_texture(button_size, button.normal_color)
	button.sprite.position = position
	add_child(button.sprite)
	
	if label != "":
		button.label = Label.new()
		button.label.text = label
		button.label.align = Label.ALIGN_CENTER
		button.label.valign = Label.VALIGN_CENTER
		button.label.rect_position = position - Vector2(20, 10)
		button.label.rect_size = Vector2(40, 20)
		add_child(button.label)
	
	virtual_buttons[action] = button

func remove_button(action: String):
	if action in virtual_buttons:
		var button = virtual_buttons[action]
		if button.sprite:
			button.sprite.queue_free()
		if button.label:
			button.label.queue_free()
		virtual_buttons.erase(action)

func clear_buttons():
	for action in virtual_buttons:
		remove_button(action)

func set_control_visibility(visible: bool):
	if virtual_joystick:
		virtual_joystick.base.visible = visible and not joystick_dynamic
		virtual_joystick.stick.visible = visible and not joystick_dynamic
	
	for action in virtual_buttons:
		var button = virtual_buttons[action]
		if button.sprite:
			button.sprite.visible = visible
		if button.label:
			button.label.visible = visible

func set_joystick_position(position: Vector2):
	if virtual_joystick and not joystick_dynamic:
		virtual_joystick.position = position
		virtual_joystick.base.position = position
		virtual_joystick.stick.position = position

func get_touch_count() -> int:
	return touches.size()

func get_touch_positions() -> Array:
	var positions = []
	for id in touches:
		positions.append(touches[id].current_position)
	return positions