extends Spatial

export var portal_pairs : Array = []
export var portal_radius = 2.0
export var max_portal_distance = 50.0
export var portal_lifetime = -1.0
export var can_create_portals = true
export var portal_material : Material

signal portal_created(portal_a, portal_b)
signal portal_entered(portal, traveler)
signal portal_closed(portal)
signal portal_pair_destroyed()

class Portal:
	var id : String
	var pair_id : String
	var position : Vector3
	var rotation : Vector3
	var normal : Vector3
	var is_active : bool = true
	var creation_time : float
	var surface_normal : Vector3
	var mesh_instance : MeshInstance
	var area : Area
	var particles : CPUParticles
	
	func _init():
		id = _generate_id()
		creation_time = OS.get_ticks_msec() / 1000.0
	
	func _generate_id():
		return "portal_" + str(randi() % 100000)

var active_portals : Dictionary = {}
var portal_queue : Array = []
var left_controller : ARVRController
var right_controller : ARVRController
var is_aiming : bool = false
var aim_ray : RayCast

onready var portal_container = $PortalContainer
onready var creation_sound = $CreationSound
onready var travel_sound = $TravelSound
onready var close_sound = $CloseSound

func _ready():
	_setup_controllers()
	_create_aim_ray()
	
	if not portal_container:
		portal_container = Spatial.new()
		portal_container.name = "PortalContainer"
		add_child(portal_container)

func _setup_controllers():
	var arvr_interface = ARVRServer.primary_interface
	if arvr_interface:
		for i in range(16):
			var controller = ARVRController.new()
			controller.controller_id = i
			if controller.is_connected():
				if not left_controller:
					left_controller = controller
				elif not right_controller:
					right_controller = controller
					break

func _create_aim_ray():
	aim_ray = RayCast.new()
	aim_ray.enabled = true
	aim_ray.cast_to = Vector3(0, 0, -max_portal_distance)
	add_child(aim_ray)

func _input(event):
	if event is InputEventKey:
		if event.pressed:
			match event.scancode:
				KEY_Q:
					if can_create_portals:
						_aim_portal("left")
				KEY_E:
					if can_create_portals:
						_aim_portal("right")

func _process(delta):
	_update_portal_lifetimes(delta)
	_handle_portal_travel()

func _aim_portal(hand):
	var controller = left_controller if hand == "left" else right_controller
	if not controller:
		return
	
	var from = controller.global_transform.origin
	var to = from + (-controller.global_transform.basis.z * max_portal_distance)
	
	var space_state = get_world().direct_space_state
	var result = space_state.intersect_ray(from, to, [self])
	
	if result:
		_create_portal_at_surface(result.position, result.normal, hand)

func _create_portal_at_surface(position, normal, portal_type):
	var portal = Portal.new()
	portal.position = position
	portal.normal = normal
	portal.surface_normal = normal
	
	var existing_portal = _find_existing_portal_of_type(portal_type)
	if existing_portal:
		_destroy_portal(existing_portal.id)
	
	_instantiate_portal_visual(portal)
	active_portals[portal.id] = portal
	
	var other_type = "right" if portal_type == "left" else "left"
	var other_portal = _find_existing_portal_of_type(other_type)
	
	if other_portal:
		portal.pair_id = other_portal.id
		other_portal.pair_id = portal.id
		emit_signal("portal_created", portal, other_portal)
		
		if creation_sound:
			creation_sound.play()
	
	portal_queue.append({
		"portal": portal,
		"type": portal_type
	})

func _find_existing_portal_of_type(portal_type):
	for queue_item in portal_queue:
		if queue_item.type == portal_type:
			return queue_item.portal
	return null

func _instantiate_portal_visual(portal):
	var mesh_instance = MeshInstance.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(portal_radius * 2, portal_radius * 2)
	mesh_instance.mesh = plane_mesh
	
	if portal_material:
		mesh_instance.material_override = portal_material
	else:
		var default_material = SpatialMaterial.new()
		default_material.albedo_color = Color(0.2, 0.4, 1.0, 0.8)
		default_material.flags_transparent = true
		default_material.emission_enabled = true
		default_material.emission = Color(0.5, 0.8, 1.0)
		mesh_instance.material_override = default_material
	
	mesh_instance.transform.origin = portal.position
	mesh_instance.look_at(portal.position + portal.normal, Vector3.UP)
	
	portal_container.add_child(mesh_instance)
	portal.mesh_instance = mesh_instance
	
	var area = Area.new()
	var collision_shape = CollisionShape.new()
	var box_shape = BoxShape.new()
	box_shape.extents = Vector3(portal_radius, portal_radius, 0.1)
	collision_shape.shape = box_shape
	
	area.add_child(collision_shape)
	mesh_instance.add_child(area)
	area.connect("body_entered", self, "_on_portal_entered", [portal])
	portal.area = area
	
	var particles = CPUParticles.new()
	particles.emitting = true
	particles.amount = 100
	particles.emission_shape = CPUParticles.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = portal_radius
	particles.local_coords = false
	mesh_instance.add_child(particles)
	portal.particles = particles

func _on_portal_entered(body, portal):
	if not portal.is_active or not portal.pair_id:
		return
	
	if not portal.pair_id in active_portals:
		return
	
	var destination_portal = active_portals[portal.pair_id]
	if not destination_portal.is_active:
		return
	
	_teleport_through_portal(body, portal, destination_portal)

func _teleport_through_portal(body, from_portal, to_portal):
	if body.has_method("set_global_transform"):
		var relative_pos = body.global_transform.origin - from_portal.position
		var rotated_pos = _rotate_vector_by_portal_diff(relative_pos, from_portal, to_portal)
		
		var new_position = to_portal.position + rotated_pos + to_portal.normal * 1.0
		body.global_transform.origin = new_position
		
		var new_rotation = _calculate_exit_rotation(body.global_transform.basis, from_portal, to_portal)
		body.global_transform.basis = new_rotation
		
		if body.has_method("set_velocity"):
			var velocity = body.get_velocity() if body.has_method("get_velocity") else Vector3.ZERO
			var rotated_velocity = _rotate_vector_by_portal_diff(velocity, from_portal, to_portal)
			body.set_velocity(rotated_velocity)
	
	emit_signal("portal_entered", from_portal, body)
	
	if travel_sound:
		travel_sound.play()

func _rotate_vector_by_portal_diff(vector, from_portal, to_portal):
	var from_forward = -from_portal.normal
	var to_forward = to_portal.normal
	
	var rotation_basis = Basis()
	rotation_basis = rotation_basis.rotated(Vector3.UP, from_forward.angle_to(to_forward))
	
	return rotation_basis * vector

func _calculate_exit_rotation(current_basis, from_portal, to_portal):
	var rotation_diff = from_portal.normal.angle_to(-to_portal.normal)
	var rotation_basis = Basis()
	rotation_basis = rotation_basis.rotated(Vector3.UP, rotation_diff)
	
	return rotation_basis * current_basis

func _update_portal_lifetimes(delta):
	if portal_lifetime <= 0:
		return
	
	var current_time = OS.get_ticks_msec() / 1000.0
	var to_remove = []
	
	for portal_id in active_portals:
		var portal = active_portals[portal_id]
		if current_time - portal.creation_time > portal_lifetime:
			to_remove.append(portal_id)
	
	for portal_id in to_remove:
		_destroy_portal(portal_id)

func _handle_portal_travel():
	pass

func _destroy_portal(portal_id):
	if not portal_id in active_portals:
		return
	
	var portal = active_portals[portal_id]
	
	if portal.mesh_instance:
		portal.mesh_instance.queue_free()
	
	var pair_portal = null
	if portal.pair_id and portal.pair_id in active_portals:
		pair_portal = active_portals[portal.pair_id]
		pair_portal.pair_id = ""
	
	active_portals.erase(portal_id)
	
	for i in range(portal_queue.size() - 1, -1, -1):
		if portal_queue[i].portal.id == portal_id:
			portal_queue.remove(i)
			break
	
	emit_signal("portal_closed", portal)
	
	if close_sound:
		close_sound.play()

func destroy_all_portals():
	var portal_ids = active_portals.keys()
	for portal_id in portal_ids:
		_destroy_portal(portal_id)
	
	emit_signal("portal_pair_destroyed")

func get_portal_count():
	return active_portals.size()

func get_portal_pair_count():
	var pairs = 0
	for portal_id in active_portals:
		var portal = active_portals[portal_id]
		if portal.pair_id and portal.pair_id in active_portals:
			pairs += 1
	return pairs / 2

func set_portal_enabled(portal_id, enabled):
	if portal_id in active_portals:
		active_portals[portal_id].is_active = enabled

func can_place_portal_at(position, normal):
	for portal_id in active_portals:
		var portal = active_portals[portal_id]
		if portal.position.distance_to(position) < portal_radius:
			return false
	return true