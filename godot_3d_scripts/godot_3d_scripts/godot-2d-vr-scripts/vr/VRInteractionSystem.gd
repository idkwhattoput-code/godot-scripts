extends Node3D

@export var grab_distance: float = 2.0
@export var interaction_distance: float = 3.0
@export var highlight_material: Material
@export var grab_strength: float = 10.0

@onready var left_hand: XRController3D = $"../LeftController"
@onready var right_hand: XRController3D = $"../RightController"

var left_grabbed_object: VRGrabbable = null
var right_grabbed_object: VRGrabbable = null
var left_highlighted_object: VRInteractable = null
var right_highlighted_object: VRInteractable = null

signal object_grabbed(hand: String, object: VRGrabbable)
signal object_released(hand: String, object: VRGrabbable)
signal object_interacted(hand: String, object: VRInteractable)

class VRGrabbable extends RigidBody3D:
	var is_grabbed: bool = false
	var grabbing_hand: XRController3D = null
	var original_parent: Node3D
	var grab_offset: Vector3
	
	func grab(hand: XRController3D):
		if is_grabbed:
			return
		
		is_grabbed = true
		grabbing_hand = hand
		original_parent = get_parent()
		grab_offset = global_position - hand.global_position
		
		freeze = true
		reparent(hand)
		position = grab_offset
	
	func release():
		if not is_grabbed:
			return
		
		is_grabbed = false
		freeze = false
		
		var world_pos = global_position
		var world_rot = global_rotation
		
		reparent(original_parent)
		global_position = world_pos
		global_rotation = world_rot
		
		if grabbing_hand:
			var velocity = grabbing_hand.get_vector3("velocity") if grabbing_hand.has_method("get_vector3") else Vector3.ZERO
			linear_velocity = velocity * 2.0
		
		grabbing_hand = null

class VRInteractable extends Area3D:
	@export var interaction_text: String = "Interact"
	@export var one_shot: bool = false
	@export var require_trigger: bool = true
	
	var has_been_used: bool = false
	
	signal interacted(hand: XRController3D)
	
	func interact(hand: XRController3D):
		if one_shot and has_been_used:
			return
		
		has_been_used = true
		interacted.emit(hand)
	
	func highlight(enable: bool):
		var mesh_instance = get_node_or_null("MeshInstance3D")
		if mesh_instance and mesh_instance.material_override != null:
			if enable:
				mesh_instance.material_overlay = highlight_material
			else:
				mesh_instance.material_overlay = null

func _ready():
	if left_hand:
		left_hand.button_pressed.connect(_on_left_button_pressed)
		left_hand.button_released.connect(_on_left_button_released)
	
	if right_hand:
		right_hand.button_pressed.connect(_on_right_button_pressed)
		right_hand.button_released.connect(_on_right_button_released)

func _physics_process(delta):
	update_hand_interactions("left", left_hand)
	update_hand_interactions("right", right_hand)
	
	update_grabbed_objects()

func update_hand_interactions(hand_name: String, controller: XRController3D):
	if not controller:
		return
	
	var nearest_grabbable = find_nearest_grabbable(controller)
	var nearest_interactable = find_nearest_interactable(controller)
	
	update_highlights(hand_name, nearest_interactable)

func find_nearest_grabbable(controller: XRController3D) -> VRGrabbable:
	var nearest: VRGrabbable = null
	var nearest_distance: float = grab_distance
	
	for node in get_tree().get_nodes_in_group("vr_grabbable"):
		if node is VRGrabbable and not node.is_grabbed:
			var distance = controller.global_position.distance_to(node.global_position)
			if distance < nearest_distance:
				nearest = node
				nearest_distance = distance
	
	return nearest

func find_nearest_interactable(controller: XRController3D) -> VRInteractable:
	var nearest: VRInteractable = null
	var nearest_distance: float = interaction_distance
	
	for node in get_tree().get_nodes_in_group("vr_interactable"):
		if node is VRInteractable:
			var distance = controller.global_position.distance_to(node.global_position)
			if distance < nearest_distance:
				nearest = node
				nearest_distance = distance
	
	return nearest

func update_highlights(hand_name: String, interactable: VRInteractable):
	var current_highlighted = left_highlighted_object if hand_name == "left" else right_highlighted_object
	
	if current_highlighted != interactable:
		if current_highlighted:
			current_highlighted.highlight(false)
		
		if interactable:
			interactable.highlight(true)
		
		if hand_name == "left":
			left_highlighted_object = interactable
		else:
			right_highlighted_object = interactable

func _on_left_button_pressed(button_name: String):
	handle_button_press("left", left_hand, button_name)

func _on_right_button_pressed(button_name: String):
	handle_button_press("right", right_hand, button_name)

func handle_button_press(hand_name: String, controller: XRController3D, button_name: String):
	match button_name:
		"grip_click", "squeeze":
			attempt_grab(hand_name, controller)
		"trigger_click":
			attempt_interaction(hand_name, controller)

func _on_left_button_released(button_name: String):
	handle_button_release("left", left_hand, button_name)

func _on_right_button_released(button_name: String):
	handle_button_release("right", right_hand, button_name)

func handle_button_release(hand_name: String, controller: XRController3D, button_name: String):
	match button_name:
		"grip_click", "squeeze":
			attempt_release(hand_name, controller)

func attempt_grab(hand_name: String, controller: XRController3D):
	var current_grabbed = left_grabbed_object if hand_name == "left" else right_grabbed_object
	
	if current_grabbed:
		return
	
	var grabbable = find_nearest_grabbable(controller)
	if grabbable:
		grabbable.grab(controller)
		
		if hand_name == "left":
			left_grabbed_object = grabbable
		else:
			right_grabbed_object = grabbable
		
		emit_signal("object_grabbed", hand_name, grabbable)
		
		if controller.has_method("trigger_haptic_pulse"):
			controller.trigger_haptic_pulse("haptic", 0, 0.1, 0.5, 0)

func attempt_release(hand_name: String, controller: XRController3D):
	var current_grabbed = left_grabbed_object if hand_name == "left" else right_grabbed_object
	
	if current_grabbed:
		current_grabbed.release()
		emit_signal("object_released", hand_name, current_grabbed)
		
		if hand_name == "left":
			left_grabbed_object = null
		else:
			right_grabbed_object = null

func attempt_interaction(hand_name: String, controller: XRController3D):
	var interactable = find_nearest_interactable(controller)
	if interactable:
		interactable.interact(controller)
		emit_signal("object_interacted", hand_name, interactable)
		
		if controller.has_method("trigger_haptic_pulse"):
			controller.trigger_haptic_pulse("haptic", 0, 0.05, 0.3, 0)

func update_grabbed_objects():
	if left_grabbed_object and left_hand:
		update_grabbed_object_position(left_grabbed_object, left_hand)
	
	if right_grabbed_object and right_hand:
		update_grabbed_object_position(right_grabbed_object, right_hand)

func update_grabbed_object_position(grabbable: VRGrabbable, controller: XRController3D):
	if not grabbable.is_grabbed:
		return
	
	var target_position = controller.global_position + grabbable.grab_offset
	var lerp_factor = grab_strength * get_physics_process_delta_time()
	
	grabbable.global_position = grabbable.global_position.lerp(target_position, lerp_factor)
	grabbable.global_rotation = grabbable.global_rotation.lerp(controller.global_rotation, lerp_factor)

func force_release_all():
	if left_grabbed_object:
		attempt_release("left", left_hand)
	if right_grabbed_object:
		attempt_release("right", right_hand)