extends Spatial

class_name VRPortalSystem

signal portal_entered(portal, player)
signal portal_exited(portal)
signal portal_created(portal)
signal portal_linked(portal_a, portal_b)
signal teleportation_started()
signal teleportation_completed()

export var max_portals: int = 4
export var portal_size: Vector2 = Vector2(2.0, 3.0)
export var portal_thickness: float = 0.1
export var enable_portal_rendering: bool = true
export var render_quality: int = 512
export var enable_seamless_transition: bool = true
export var transition_effect: bool = true
export var allow_object_transport: bool = true
export var maintain_momentum: bool = true
export var portal_cooldown: float = 0.5
export var enable_portal_gun: bool = true
export var max_portal_distance: float = 50.0
export var portal_placement_offset: float = 0.1
export var enable_portal_preview: bool = true

var active_portals: Array = []
var portal_pairs: Dictionary = {}
var portal_cameras: Dictionary = {}
var portal_viewports: Dictionary = {}
var player_controller: ARVROrigin
var portal_gun: PortalGun
var is_transitioning: bool = false
var last_portal_time: float = 0.0
var preview_portal: MeshInstance

class Portal:
	var id: int
	var position: Vector3
	var normal: Vector3
	var transform: Transform
	var linked_portal: Portal = null
	var mesh_instance: MeshInstance
	var area: Area
	var collision_shape: CollisionShape
	var viewport_texture: ViewportTexture
	var is_active: bool = false
	var portal_color: Color
	var objects_in_portal: Array = []
	
	func _init(pos: Vector3, norm: Vector3, color: Color = Color.cyan):
		position = pos
		normal = norm
		portal_color = color
		id = OS.get_unix_time()

class PortalGun:
	var mesh: MeshInstance
	var raycast: RayCast
	var current_portal_type: int = 0
	var preview_active: bool = false
	var haptic_feedback: bool = true
	
	func _init():
		current_portal_type = 0

class PortalCamera:
	var camera: Camera
	var viewport: Viewport
	var render_target: ViewportTexture
	
	func _init(resolution: int):
		viewport = Viewport.new()
		viewport.size = Vector2(resolution, resolution)
		viewport.render_target_v_flip = true
		viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
		
		camera = Camera.new()
		camera.fov = 90
		viewport.add_child(camera)
		
		render_target = viewport.get_texture()

func _ready():
	setup_player_reference()
	setup_portal_gun()
	setup_preview_portal()
	
	if not Engine.editor_hint:
		set_process(true)
		set_physics_process(true)

func setup_player_reference():
	var arvr_nodes = get_tree().get_nodes_in_group("arvr_origin")
	if arvr_nodes.size() > 0:
		player_controller = arvr_nodes[0]
	else:
		player_controller = ARVROrigin.new()
		add_child(player_controller)

func setup_portal_gun():
	if not enable_portal_gun:
		return
	
	portal_gun = PortalGun.new()
	
	portal_gun.mesh = MeshInstance.new()
	var gun_mesh = CylinderMesh.new()
	gun_mesh.height = 0.3
	gun_mesh.top_radius = 0.02
	gun_mesh.bottom_radius = 0.04
	portal_gun.mesh.mesh = gun_mesh
	
	portal_gun.raycast = RayCast.new()
	portal_gun.raycast.enabled = true
	portal_gun.raycast.cast_to = Vector3(0, 0, -max_portal_distance)
	portal_gun.mesh.add_child(portal_gun.raycast)
	
	if player_controller:
		var right_controller = get_node_or_null(str(player_controller.get_path()) + "/RightController")
		if right_controller:
			right_controller.add_child(portal_gun.mesh)
			portal_gun.mesh.transform.origin = Vector3(0, -0.1, -0.1)
			portal_gun.mesh.rotate_x(deg2rad(-30))

func setup_preview_portal():
	if not enable_portal_preview:
		return
	
	preview_portal = MeshInstance.new()
	var preview_mesh = QuadMesh.new()
	preview_mesh.size = portal_size
	preview_portal.mesh = preview_mesh
	
	var preview_material = SpatialMaterial.new()
	preview_material.albedo_color = Color(1, 1, 1, 0.3)
	preview_material.emission_enabled = true
	preview_material.emission = Color(0.5, 0.5, 1.0)
	preview_material.emission_energy = 0.5
	preview_portal.material_override = preview_material
	
	preview_portal.visible = false
	add_child(preview_portal)

func _process(delta):
	if portal_gun and portal_gun.preview_active:
		update_portal_preview()
	
	update_portal_rendering()
	check_portal_transitions()

func _physics_process(delta):
	if enable_portal_gun:
		handle_portal_gun_input()

func handle_portal_gun_input():
	if not portal_gun or not player_controller:
		return
	
	var right_controller = get_node_or_null(str(player_controller.get_path()) + "/RightController")
	if not right_controller:
		return
	
	if right_controller.is_button_pressed(15):
		portal_gun.current_portal_type = 0
		portal_gun.preview_active = true
		if preview_portal:
			preview_portal.visible = true
	elif right_controller.is_button_pressed(2):
		portal_gun.current_portal_type = 1
		portal_gun.preview_active = true
		if preview_portal:
			preview_portal.visible = true
	else:
		if portal_gun.preview_active:
			portal_gun.preview_active = false
			if preview_portal:
				preview_portal.visible = false
	
	if right_controller.is_button_pressed(1) and OS.get_ticks_msec() / 1000.0 - last_portal_time > portal_cooldown:
		fire_portal()

func update_portal_preview():
	if not portal_gun.raycast.is_colliding():
		return
	
	var hit_point = portal_gun.raycast.get_collision_point()
	var hit_normal = portal_gun.raycast.get_collision_normal()
	
	preview_portal.global_transform.origin = hit_point + hit_normal * portal_placement_offset
	preview_portal.look_at(hit_point + hit_normal, Vector3.UP)
	
	var preview_color = Color.cyan if portal_gun.current_portal_type == 0 else Color.orange
	preview_portal.material_override.emission = preview_color

func fire_portal():
	if not portal_gun.raycast.is_colliding():
		return
	
	var hit_point = portal_gun.raycast.get_collision_point()
	var hit_normal = portal_gun.raycast.get_collision_normal()
	
	if hit_normal.dot(Vector3.UP) < 0.3:
		hit_normal = Vector3.UP
	
	var portal_color = Color.cyan if portal_gun.current_portal_type == 0 else Color.orange
	create_portal(hit_point, hit_normal, portal_color, portal_gun.current_portal_type)
	
	last_portal_time = OS.get_ticks_msec() / 1000.0
	
	if portal_gun.haptic_feedback:
		var right_controller = get_node_or_null(str(player_controller.get_path()) + "/RightController")
		if right_controller:
			right_controller.rumble = 0.5

func create_portal(position: Vector3, normal: Vector3, color: Color, portal_type: int = 0) -> Portal:
	if active_portals.size() >= max_portals:
		remove_oldest_portal()
	
	var existing_portal_of_type = find_portal_by_type(portal_type)
	if existing_portal_of_type:
		remove_portal(existing_portal_of_type)
	
	var portal = Portal.new(position + normal * portal_placement_offset, normal, color)
	
	portal.mesh_instance = MeshInstance.new()
	var portal_mesh = QuadMesh.new()
	portal_mesh.size = portal_size
	portal.mesh_instance.mesh = portal_mesh
	
	var portal_material = SpatialMaterial.new()
	portal_material.albedo_color = color
	portal_material.emission_enabled = true
	portal_material.emission = color
	portal_material.emission_energy = 1.0
	
	if enable_portal_rendering:
		var portal_camera = create_portal_camera()
		portal_cameras[portal.id] = portal_camera
		portal_material.albedo_texture = portal_camera.render_target
		portal_material.emission_enabled = false
	
	portal.mesh_instance.material_override = portal_material
	portal.mesh_instance.global_transform.origin = position + normal * portal_placement_offset
	portal.mesh_instance.look_at(position + normal * 2, Vector3.UP)
	
	portal.area = Area.new()
	portal.collision_shape = CollisionShape.new()
	var shape = BoxShape.new()
	shape.extents = Vector3(portal_size.x / 2, portal_size.y / 2, portal_thickness / 2)
	portal.collision_shape.shape = shape
	portal.area.add_child(portal.collision_shape)
	portal.mesh_instance.add_child(portal.area)
	
	portal.area.connect("body_entered", self, "_on_portal_body_entered", [portal])
	portal.area.connect("body_exited", self, "_on_portal_body_exited", [portal])
	
	add_child(portal.mesh_instance)
	
	portal.transform = portal.mesh_instance.global_transform
	portal.is_active = true
	active_portals.append(portal)
	
	try_link_portals()
	
	emit_signal("portal_created", portal)
	return portal

func create_portal_camera() -> PortalCamera:
	return PortalCamera.new(render_quality)

func try_link_portals():
	var unlinked_portals = []
	for portal in active_portals:
		if not portal.linked_portal:
			unlinked_portals.append(portal)
	
	if unlinked_portals.size() >= 2:
		var portal_a = unlinked_portals[0]
		var portal_b = unlinked_portals[1]
		link_portals(portal_a, portal_b)

func link_portals(portal_a: Portal, portal_b: Portal):
	portal_a.linked_portal = portal_b
	portal_b.linked_portal = portal_a
	
	portal_pairs[portal_a.id] = portal_b.id
	portal_pairs[portal_b.id] = portal_a.id
	
	emit_signal("portal_linked", portal_a, portal_b)

func update_portal_rendering():
	if not enable_portal_rendering:
		return
	
	for portal in active_portals:
		if not portal.linked_portal or not portal.is_active:
			continue
		
		if portal.id in portal_cameras:
			var portal_camera = portal_cameras[portal.id]
			update_portal_camera(portal, portal.linked_portal, portal_camera)

func update_portal_camera(viewing_portal: Portal, target_portal: Portal, portal_camera: PortalCamera):
	if not player_controller:
		return
	
	var player_camera = player_controller.get_node_or_null("Camera")
	if not player_camera:
		return
	
	var player_to_portal = viewing_portal.transform.inverse() * player_camera.global_transform
	var rotated_transform = player_to_portal.rotated(Vector3.UP, PI)
	var final_transform = target_portal.transform * rotated_transform
	
	portal_camera.camera.global_transform = final_transform
	portal_camera.camera.fov = player_camera.fov

func check_portal_transitions():
	if is_transitioning:
		return
	
	for portal in active_portals:
		if portal.objects_in_portal.has(player_controller):
			check_player_portal_transition(portal)

func check_player_portal_transition(portal: Portal):
	if not portal.linked_portal or not portal.is_active:
		return
	
	var player_camera = player_controller.get_node_or_null("Camera")
	if not player_camera:
		return
	
	var to_player = player_camera.global_transform.origin - portal.position
	var portal_forward = -portal.transform.basis.z
	
	if to_player.dot(portal_forward) > 0:
		teleport_through_portal(player_controller, portal, portal.linked_portal)

func _on_portal_body_entered(body: Node, portal: Portal):
	if not body in portal.objects_in_portal:
		portal.objects_in_portal.append(body)
	
	if body == player_controller:
		emit_signal("portal_entered", portal, body)

func _on_portal_body_exited(body: Node, portal: Portal):
	if body in portal.objects_in_portal:
		portal.objects_in_portal.erase(body)
	
	if body == player_controller:
		emit_signal("portal_exited", portal)

func teleport_through_portal(object: Node, from_portal: Portal, to_portal: Portal):
	if is_transitioning:
		return
	
	is_transitioning = true
	emit_signal("teleportation_started")
	
	var object_to_portal = from_portal.transform.inverse() * object.global_transform
	var rotated_transform = object_to_portal.rotated(Vector3.UP, PI)
	var final_transform = to_portal.transform * rotated_transform
	
	if transition_effect:
		apply_transition_effect()
	
	object.global_transform = final_transform
	
	if maintain_momentum and object.has_method("get_linear_velocity"):
		var velocity = object.get_linear_velocity()
		var rotated_velocity = from_portal.transform.basis.inverse() * velocity
		rotated_velocity = rotated_velocity.rotated(Vector3.UP, PI)
		var final_velocity = to_portal.transform.basis * rotated_velocity
		object.set_linear_velocity(final_velocity)
	
	if object in from_portal.objects_in_portal:
		from_portal.objects_in_portal.erase(object)
	if not object in to_portal.objects_in_portal:
		to_portal.objects_in_portal.append(object)
	
	yield(get_tree().create_timer(0.1), "timeout")
	
	is_transitioning = false
	emit_signal("teleportation_completed")

func apply_transition_effect():
	var fade_rect = ColorRect.new()
	fade_rect.color = Color(1, 1, 1, 0)
	fade_rect.rect_size = get_viewport().size
	get_viewport().add_child(fade_rect)
	
	var tween = Tween.new()
	add_child(tween)
	
	tween.interpolate_property(fade_rect, "color:a", 0, 1, 0.1, Tween.TRANS_LINEAR, Tween.EASE_IN)
	tween.interpolate_property(fade_rect, "color:a", 1, 0, 0.1, Tween.TRANS_LINEAR, Tween.EASE_OUT, 0.1)
	tween.start()
	
	yield(tween, "tween_all_completed")
	
	fade_rect.queue_free()
	tween.queue_free()

func remove_portal(portal: Portal):
	if portal.linked_portal:
		portal.linked_portal.linked_portal = null
	
	if portal.id in portal_cameras:
		var portal_camera = portal_cameras[portal.id]
		portal_camera.viewport.queue_free()
		portal_cameras.erase(portal.id)
	
	if portal.id in portal_pairs:
		portal_pairs.erase(portal.id)
	
	portal.mesh_instance.queue_free()
	active_portals.erase(portal)

func remove_oldest_portal():
	if active_portals.size() > 0:
		remove_portal(active_portals[0])

func find_portal_by_type(portal_type: int) -> Portal:
	var portal_index = portal_type * 2
	if portal_index < active_portals.size():
		return active_portals[portal_index]
	return null

func clear_all_portals():
	for portal in active_portals:
		remove_portal(portal)
	active_portals.clear()
	portal_pairs.clear()

func get_linked_portal(portal: Portal) -> Portal:
	return portal.linked_portal

func set_portal_rendering_enabled(enabled: bool):
	enable_portal_rendering = enabled
	
	if not enabled:
		for id in portal_cameras:
			portal_cameras[id].viewport.queue_free()
		portal_cameras.clear()

func create_portal_pair(pos_a: Vector3, normal_a: Vector3, pos_b: Vector3, normal_b: Vector3):
	var portal_a = create_portal(pos_a, normal_a, Color.cyan, 0)
	var portal_b = create_portal(pos_b, normal_b, Color.orange, 1)
	link_portals(portal_a, portal_b)

func teleport_object(object: Node, portal: Portal):
	if portal.linked_portal and allow_object_transport:
		teleport_through_portal(object, portal, portal.linked_portal)