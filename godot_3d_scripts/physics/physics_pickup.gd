extends RayCast

# Physics Object Pickup System for Godot 3D
# Allows player to pick up, carry, and throw physics objects
# Attach to a camera or player controller with a RayCast pointing forward

# Pickup settings
export var pickup_distance = 3.0
export var carry_distance = 2.5
export var throw_force = 10.0
export var rotation_speed = 5.0
export var carry_stiffness = 10.0
export var carry_damping = 5.0

# Object constraints
export var max_object_mass = 50.0
export var max_object_size = 3.0

# Visual feedback
export var show_outline = true
export var outline_color = Color(1, 1, 0, 0.5)
export var crosshair_default_color = Color.white
export var crosshair_hover_color = Color.yellow

# Internal variables
var carried_object: RigidBody = null
var carry_position: Position3D
var pickup_offset: Vector3
var is_rotating_object = false
var hover_object: RigidBody = null

# UI elements
onready var crosshair = $"../UI/Crosshair" if has_node("../UI/Crosshair") else null
onready var pickup_prompt = $"../UI/PickupPrompt" if has_node("../UI/PickupPrompt") else null

func _ready():
	# Setup carry position marker
	carry_position = Position3D.new()
	get_parent().add_child(carry_position)
	
	# Configure raycast
	enabled = true
	cast_to = Vector3(0, 0, -pickup_distance)
	collision_mask = 1  # Adjust based on your physics layers

func _physics_process(delta):
	# Check for objects to pick up
	if not carried_object:
		check_hover_object()
	else:
		update_carried_object(delta)
	
	# Handle input
	handle_input()

func check_hover_object():
	"""Check if we're looking at a pickupable object"""
	if is_colliding():
		var collider = get_collider()
		if collider is RigidBody and can_pickup_object(collider):
			if hover_object != collider:
				hover_object = collider
				on_hover_enter(collider)
		else:
			if hover_object:
				on_hover_exit(hover_object)
				hover_object = null
	else:
		if hover_object:
			on_hover_exit(hover_object)
			hover_object = null

func handle_input():
	"""Handle pickup/drop/throw input"""
	if Input.is_action_just_pressed("interact"):
		if carried_object:
			drop_object()
		elif hover_object:
			pickup_object(hover_object)
	
	if carried_object and Input.is_action_just_pressed("throw"):
		throw_object()
	
	# Object rotation while carrying
	if carried_object and Input.is_action_pressed("rotate_object"):
		is_rotating_object = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif is_rotating_object and not Input.is_action_pressed("rotate_object"):
		is_rotating_object = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _input(event):
	"""Handle object rotation input"""
	if is_rotating_object and event is InputEventMouseMotion:
		carried_object.rotate_y(-event.relative.x * 0.01)
		carried_object.rotate_x(-event.relative.y * 0.01)

func can_pickup_object(body: RigidBody) -> bool:
	"""Check if an object can be picked up"""
	if body.mode != RigidBody.MODE_RIGID:
		return false
	
	if body.mass > max_object_mass:
		return false
	
	# Check object size
	var aabb = get_object_aabb(body)
	var size = aabb.size.length()
	if size > max_object_size:
		return false
	
	# Check if object has pickup tag or group
	if body.has_meta("pickupable"):
		return body.get_meta("pickupable")
	
	return true  # Default to pickupable

func pickup_object(body: RigidBody):
	"""Pick up an object"""
	carried_object = body
	
	# Calculate pickup offset
	pickup_offset = carried_object.global_transform.origin - global_transform.origin
	pickup_offset = pickup_offset.normalized() * carry_distance
	
	# Disable object gravity while carried
	carried_object.gravity_scale = 0
	
	# Store original collision layer
	carried_object.set_meta("original_collision_layer", carried_object.collision_layer)
	carried_object.collision_layer = 2  # Move to carried objects layer
	
	# Visual feedback
	if show_outline:
		add_outline_to_object(carried_object)

func drop_object():
	"""Drop the carried object"""
	if not carried_object:
		return
	
	# Restore physics properties
	carried_object.gravity_scale = 1
	carried_object.collision_layer = carried_object.get_meta("original_collision_layer", 1)
	
	# Remove visual effects
	if show_outline:
		remove_outline_from_object(carried_object)
	
	carried_object = null

func throw_object():
	"""Throw the carried object"""
	if not carried_object:
		return
	
	# Calculate throw direction
	var throw_direction = -global_transform.basis.z
	
	# Apply throw force
	carried_object.linear_velocity = throw_direction * throw_force
	
	# Drop the object
	drop_object()

func update_carried_object(delta):
	"""Update carried object position and physics"""
	if not is_instance_valid(carried_object):
		carried_object = null
		return
	
	# Calculate target position
	var target_pos = global_transform.origin - global_transform.basis.z * carry_distance
	carry_position.global_transform.origin = target_pos
	
	# Apply force to move object to carry position
	var distance = target_pos - carried_object.global_transform.origin
	var velocity = distance * carry_stiffness
	
	# Apply damping
	velocity -= carried_object.linear_velocity * carry_damping
	
	# Limit velocity to prevent instability
	velocity = velocity.clamped(20.0)
	
	carried_object.linear_velocity = velocity
	
	# Reduce angular velocity for stability
	carried_object.angular_velocity *= 0.9

func get_object_aabb(body: RigidBody) -> AABB:
	"""Get the AABB of a RigidBody"""
	var aabb = AABB()
	for child in body.get_children():
		if child is MeshInstance:
			if aabb.size == Vector3.ZERO:
				aabb = child.get_aabb()
			else:
				aabb = aabb.merge(child.get_aabb())
	return aabb

func on_hover_enter(body: RigidBody):
	"""Called when hover enters a pickupable object"""
	# Update UI
	if crosshair:
		crosshair.modulate = crosshair_hover_color
	if pickup_prompt:
		pickup_prompt.visible = true
		pickup_prompt.text = "Press E to pick up"
	
	# Add hover outline
	if show_outline:
		add_hover_outline(body)

func on_hover_exit(body: RigidBody):
	"""Called when hover exits a pickupable object"""
	# Update UI
	if crosshair:
		crosshair.modulate = crosshair_default_color
	if pickup_prompt:
		pickup_prompt.visible = false
	
	# Remove hover outline
	if show_outline:
		remove_hover_outline(body)

func add_outline_to_object(body: RigidBody):
	"""Add outline shader to object"""
	# This is a placeholder - implement based on your shader setup
	for child in body.get_children():
		if child is MeshInstance:
			# Store original material
			child.set_meta("original_material", child.material_override)
			# Apply outline material
			# child.material_override = outline_material

func remove_outline_from_object(body: RigidBody):
	"""Remove outline shader from object"""
	for child in body.get_children():
		if child is MeshInstance:
			child.material_override = child.get_meta("original_material", null)

func add_hover_outline(body: RigidBody):
	"""Add hover outline effect"""
	# Similar to add_outline_to_object but with different color/style
	pass

func remove_hover_outline(body: RigidBody):
	"""Remove hover outline effect"""
	# Similar to remove_outline_from_object
	pass

# Get required input actions
func get_required_input_actions():
	return {
		"interact": KEY_E,
		"throw": KEY_Q,
		"rotate_object": KEY_R
	}