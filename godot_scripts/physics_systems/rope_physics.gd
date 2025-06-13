extends Spatial

# Rope configuration
export var segment_count = 20
export var segment_length = 0.5
export var rope_radius = 0.05
export var total_mass = 2.0
export var stiffness = 100.0
export var damping = 5.0
export var max_stretch = 1.5
export var bend_stiffness = 10.0

# Rope behavior
export var gravity_scale = 1.0
export var air_resistance = 0.1
export var self_collision = false
export var breakable = false
export var break_force = 1000.0

# Attachment settings
export var start_attached = true
export var end_attached = false
export var start_attachment_node: NodePath
export var end_attachment_node: NodePath

# Visual settings
export var rope_material: Material
export var segment_shape = "cylinder"  # cylinder, chain, cable
export var twist_amount = 0.0
export var sway_in_wind = true
export var wind_strength = 5.0

# Rope segments
var segments = []
var constraints = []
var segment_meshes = []
var rope_mesh_instance = null

# State
var is_broken = false
var tension = 0.0
var total_length = 0.0
var rest_length = 0.0
var current_length = 0.0

# Attachment points
var start_anchor = null
var end_anchor = null
var grabbed_segment = -1
var grab_offset = Vector3.ZERO

# Forces
var external_forces = []
var wind_offset = 0.0

# Rendering
var rope_curve = Curve3D.new()
var rope_path = null
var use_verlet_integration = true

signal rope_broken(break_point)
signal tension_changed(new_tension)
signal attached(node, end)
signal detached(end)
signal segment_collided(segment_index, collision_body)

func _ready():
	_create_rope()
	_setup_rendering()
	_attach_ends()
	set_physics_process(true)

func _create_rope():
	rest_length = segment_count * segment_length
	total_length = rest_length
	var segment_mass = total_mass / segment_count
	
	# Create segments
	for i in range(segment_count + 1):
		var segment = {
			"position": Vector3(0, -i * segment_length, 0),
			"old_position": Vector3(0, -i * segment_length, 0),
			"velocity": Vector3.ZERO,
			"mass": segment_mass,
			"radius": rope_radius,
			"pinned": false,
			"forces": Vector3.ZERO
		}
		
		# Pin first segment if attached
		if i == 0 and start_attached:
			segment.pinned = true
		# Pin last segment if attached
		elif i == segment_count and end_attached:
			segment.pinned = true
		
		segments.append(segment)
	
	# Create constraints between segments
	for i in range(segment_count):
		var constraint = {
			"segment_a": i,
			"segment_b": i + 1,
			"rest_length": segment_length,
			"stiffness": stiffness,
			"damping": damping
		}
		constraints.append(constraint)

func _setup_rendering():
	# Create visual representation
	match segment_shape:
		"cylinder":
			_create_cylinder_rope()
		"chain":
			_create_chain_rope()
		"cable":
			_create_cable_rope()

func _create_cylinder_rope():
	# Create a single mesh for the entire rope using ImmediateGeometry or CSGPolygon
	rope_mesh_instance = MeshInstance.new()
	add_child(rope_mesh_instance)
	
	if rope_material:
		rope_mesh_instance.material_override = rope_material
	
	_update_rope_mesh()

func _create_chain_rope():
	# Create individual chain links
	for i in range(segment_count):
		var link = MeshInstance.new()
		link.mesh = preload("res://meshes/chain_link.mesh")  # Assuming you have this
		add_child(link)
		segment_meshes.append(link)

func _create_cable_rope():
	# Create path-based rope
	rope_path = Path.new()
	add_child(rope_path)
	
	var path_follow = PathFollow.new()
	rope_path.add_child(path_follow)
	
	var cable_mesh = MeshInstance.new()
	cable_mesh.mesh = CylinderMesh.new()
	cable_mesh.mesh.height = segment_length
	cable_mesh.mesh.top_radius = rope_radius
	cable_mesh.mesh.bottom_radius = rope_radius
	path_follow.add_child(cable_mesh)

func _attach_ends():
	# Attach start
	if start_attached and start_attachment_node:
		start_anchor = get_node(start_attachment_node)
		if start_anchor:
			segments[0].position = start_anchor.global_transform.origin
	
	# Attach end
	if end_attached and end_attachment_node:
		end_anchor = get_node(end_attachment_node)
		if end_anchor:
			segments[segments.size() - 1].position = end_anchor.global_transform.origin

func _physics_process(delta):
	if is_broken:
		return
	
	# Update attachment points
	_update_attachments()
	
	# Apply forces
	_apply_forces(delta)
	
	# Solve constraints
	if use_verlet_integration:
		_verlet_integrate(delta)
	else:
		_euler_integrate(delta)
	
	# Solve constraints multiple times for stability
	for i in range(3):
		_solve_constraints()
	
	# Check for breaking
	if breakable:
		_check_breaking()
	
	# Handle collisions
	if self_collision:
		_handle_self_collision()
	
	# Update visuals
	_update_visuals()
	
	# Calculate metrics
	_calculate_rope_metrics()

func _update_attachments():
	# Update pinned segments to follow anchors
	if start_anchor and segments.size() > 0:
		segments[0].position = start_anchor.global_transform.origin
		segments[0].old_position = segments[0].position
	
	if end_anchor and segments.size() > 0:
		var last_idx = segments.size() - 1
		segments[last_idx].position = end_anchor.global_transform.origin
		segments[last_idx].old_position = segments[last_idx].position

func _apply_forces(delta):
	wind_offset += delta
	
	for i in range(segments.size()):
		var segment = segments[i]
		if segment.pinned:
			continue
		
		# Clear forces
		segment.forces = Vector3.ZERO
		
		# Gravity
		segment.forces += Vector3.DOWN * 9.81 * gravity_scale * segment.mass
		
		# Air resistance
		segment.forces -= segment.velocity * air_resistance
		
		// Wind
		if sway_in_wind:
			var wind = Vector3(
				sin(wind_offset * 2 + i * 0.5) * wind_strength,
				0,
				cos(wind_offset * 1.5 + i * 0.3) * wind_strength * 0.5
			)
			segment.forces += wind
		
		# External forces
		for force_data in external_forces:
			if force_data.segment_index == i or force_data.segment_index == -1:
				segment.forces += force_data.force

func _verlet_integrate(delta):
	for segment in segments:
		if segment.pinned:
			continue
		
		var temp = segment.position
		var acceleration = segment.forces / segment.mass
		
		# Verlet integration
		segment.position = segment.position * 2 - segment.old_position + acceleration * delta * delta
		segment.old_position = temp
		
		# Update velocity for other calculations
		segment.velocity = (segment.position - segment.old_position) / delta

func _euler_integrate(delta):
	for segment in segments:
		if segment.pinned:
			continue
		
		var acceleration = segment.forces / segment.mass
		segment.velocity += acceleration * delta
		segment.position += segment.velocity * delta

func _solve_constraints():
	# Distance constraints
	for constraint in constraints:
		var seg_a = segments[constraint.segment_a]
		var seg_b = segments[constraint.segment_b]
		
		if seg_a.pinned and seg_b.pinned:
			continue
		
		var delta_pos = seg_b.position - seg_a.position
		var distance = delta_pos.length()
		
		if distance > 0:
			var rest_length = constraint.rest_length
			
			# Apply stretch limit
			var max_length = rest_length * max_stretch
			if distance > max_length:
				distance = max_length
			
			var difference = rest_length - distance
			var offset = delta_pos.normalized() * difference
			
			# Apply constraint
			if seg_a.pinned:
				seg_b.position += offset
			elif seg_b.pinned:
				seg_a.position -= offset
			else:
				# Both can move
				var mass_ratio_a = seg_b.mass / (seg_a.mass + seg_b.mass)
				var mass_ratio_b = seg_a.mass / (seg_a.mass + seg_b.mass)
				seg_a.position -= offset * mass_ratio_a * 0.5
				seg_b.position += offset * mass_ratio_b * 0.5
			
			# Update tension
			var strain = abs(distance - rest_length) / rest_length
			tension = max(tension, strain * stiffness)
	
	# Bending constraints (optional)
	if bend_stiffness > 0:
		_solve_bending_constraints()

func _solve_bending_constraints():
	# Simple bending resistance
	for i in range(1, segments.size() - 1):
		var prev = segments[i - 1]
		var curr = segments[i]
		var next = segments[i + 1]
		
		if curr.pinned:
			continue
		
		# Calculate angle
		var dir1 = (curr.position - prev.position).normalized()
		var dir2 = (next.position - curr.position).normalized()
		var dot = dir1.dot(dir2)
		
		# Apply bending force if angle is too sharp
		if dot < 0.9:  # About 25 degrees
			var midpoint = (prev.position + next.position) * 0.5
			var offset = (midpoint - curr.position) * bend_stiffness * 0.01
			curr.position += offset

func _check_breaking():
	var max_tension_found = 0.0
	var break_index = -1
	
	for i in range(constraints.size()):
		var constraint = constraints[i]
		var seg_a = segments[constraint.segment_a]
		var seg_b = segments[constraint.segment_b]
		
		var delta = seg_b.position - seg_a.position
		var distance = delta.length()
		var strain = abs(distance - constraint.rest_length) / constraint.rest_length
		var force = strain * stiffness
		
		if force > max_tension_found:
			max_tension_found = force
			break_index = i
	
	if max_tension_found > break_force:
		_break_rope(break_index)

func _break_rope(constraint_index: int):
	is_broken = true
	
	# Remove the constraint
	constraints.remove(constraint_index)
	
	# Unpin segments at break point
	var break_segment = constraints[constraint_index].segment_b
	segments[break_segment].pinned = false
	
	emit_signal("rope_broken", break_segment)

func _handle_self_collision():
	# Simple self-collision using spatial hashing or brute force
	for i in range(segments.size()):
		for j in range(i + 2, segments.size()):  # Skip adjacent segments
			var seg_a = segments[i]
			var seg_b = segments[j]
			
			var distance = seg_a.position.distance_to(seg_b.position)
			var min_distance = (seg_a.radius + seg_b.radius) * 2
			
			if distance < min_distance:
				# Push apart
				var direction = (seg_b.position - seg_a.position).normalized()
				var overlap = min_distance - distance
				
				if not seg_a.pinned:
					seg_a.position -= direction * overlap * 0.5
				if not seg_b.pinned:
					seg_b.position += direction * overlap * 0.5

func _update_visuals():
	match segment_shape:
		"cylinder":
			_update_rope_mesh()
		"chain":
			_update_chain_positions()
		"cable":
			_update_cable_path()

func _update_rope_mesh():
	if not rope_mesh_instance:
		return
	
	# Generate rope mesh from segments
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var vertices = PoolVector3Array()
	var normals = PoolVector3Array()
	var uvs = PoolVector2Array()
	var indices = PoolIntArray()
	
	# Generate cylinder mesh along rope path
	var sides = 8
	for i in range(segments.size()):
		var segment = segments[i]
		var position = segment.position
		
		# Calculate tangent
		var tangent = Vector3.UP
		if i > 0:
			tangent = (position - segments[i-1].position).normalized()
		elif i < segments.size() - 1:
			tangent = (segments[i+1].position - position).normalized()
		
		# Generate ring of vertices
		var right = tangent.cross(Vector3.FORWARD).normalized()
		if right.length() < 0.1:
			right = tangent.cross(Vector3.RIGHT).normalized()
		var forward = tangent.cross(right).normalized()
		
		for j in range(sides):
			var angle = j * TAU / sides + twist_amount * i
			var offset = (right * cos(angle) + forward * sin(angle)) * rope_radius
			vertices.append(position + offset)
			normals.append(offset.normalized())
			uvs.append(Vector2(float(j) / sides, float(i) / segments.size()))
		
		# Generate indices
		if i > 0:
			var prev_base = (i - 1) * sides
			var curr_base = i * sides
			
			for j in range(sides):
				var next_j = (j + 1) % sides
				
				# Triangle 1
				indices.append(prev_base + j)
				indices.append(curr_base + j)
				indices.append(curr_base + next_j)
				
				# Triangle 2
				indices.append(prev_base + j)
				indices.append(curr_base + next_j)
				indices.append(prev_base + next_j)
	
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	
	# Create mesh
	var array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	rope_mesh_instance.mesh = array_mesh

func _update_chain_positions():
	for i in range(min(segment_meshes.size(), segments.size() - 1)):
		var mesh = segment_meshes[i]
		var seg_a = segments[i]
		var seg_b = segments[i + 1]
		
		# Position at midpoint
		mesh.global_transform.origin = (seg_a.position + seg_b.position) * 0.5
		
		# Rotate to align with segment
		var direction = seg_b.position - seg_a.position
		if direction.length() > 0.001:
			mesh.look_at(mesh.global_transform.origin + direction, Vector3.UP)

func _update_cable_path():
	if not rope_path:
		return
	
	rope_curve.clear_points()
	
	for segment in segments:
		rope_curve.add_point(segment.position)
	
	# Smooth the curve
	for i in range(rope_curve.get_point_count()):
		if i > 0 and i < rope_curve.get_point_count() - 1:
			var prev = rope_curve.get_point_position(i - 1)
			var curr = rope_curve.get_point_position(i)
			var next = rope_curve.get_point_position(i + 1)
			
			var in_control = (prev - curr) * 0.3
			var out_control = (next - curr) * 0.3
			
			rope_curve.set_point_in(i, in_control)
			rope_curve.set_point_out(i, out_control)
	
	rope_path.curve = rope_curve

func _calculate_rope_metrics():
	# Calculate current length
	current_length = 0.0
	for i in range(segments.size() - 1):
		current_length += segments[i].position.distance_to(segments[i + 1].position)
	
	# Calculate average tension
	var total_tension = 0.0
	for constraint in constraints:
		var seg_a = segments[constraint.segment_a]
		var seg_b = segments[constraint.segment_b]
		var distance = seg_a.position.distance_to(seg_b.position)
		var strain = (distance - constraint.rest_length) / constraint.rest_length
		total_tension += abs(strain)
	
	tension = total_tension / constraints.size() * stiffness
	emit_signal("tension_changed", tension)

# Public API

func apply_force(force: Vector3, segment_index: int = -1, duration: float = 0.0):
	external_forces.append({
		"force": force,
		"segment_index": segment_index,
		"duration": duration,
		"timer": 0.0
	})

func attach_start(node: Spatial):
	start_anchor = node
	start_attached = true
	if segments.size() > 0:
		segments[0].pinned = true
	emit_signal("attached", node, true)

func attach_end(node: Spatial):
	end_anchor = node
	end_attached = true
	if segments.size() > 0:
		segments[segments.size() - 1].pinned = true
	emit_signal("attached", node, false)

func detach_start():
	start_anchor = null
	start_attached = false
	if segments.size() > 0:
		segments[0].pinned = false
	emit_signal("detached", true)

func detach_end():
	end_anchor = null
	end_attached = false
	if segments.size() > 0:
		segments[segments.size() - 1].pinned = false
	emit_signal("detached", false)

func grab_rope(world_position: Vector3) -> int:
	var closest_segment = -1
	var closest_distance = INF
	
	for i in range(segments.size()):
		var distance = segments[i].position.distance_to(world_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_segment = i
	
	if closest_distance < rope_radius * 3:
		grabbed_segment = closest_segment
		grab_offset = world_position - segments[grabbed_segment].position
		segments[grabbed_segment].pinned = true
		return grabbed_segment
	
	return -1

func release_rope():
	if grabbed_segment >= 0:
		segments[grabbed_segment].pinned = false
		grabbed_segment = -1

func move_grabbed_point(world_position: Vector3):
	if grabbed_segment >= 0 and grabbed_segment < segments.size():
		segments[grabbed_segment].position = world_position - grab_offset
		segments[grabbed_segment].old_position = segments[grabbed_segment].position

func cut_rope(segment_index: int):
	if segment_index > 0 and segment_index < constraints.size():
		_break_rope(segment_index - 1)

func get_segment_position(index: int) -> Vector3:
	if index >= 0 and index < segments.size():
		return segments[index].position
	return Vector3.ZERO

func get_rope_length() -> float:
	return current_length

func get_tension() -> float:
	return tension

func set_wind_strength(strength: float):
	wind_strength = strength

func reset_rope():
	is_broken = false
	for i in range(segments.size()):
		segments[i].position = Vector3(0, -i * segment_length, 0)
		segments[i].old_position = segments[i].position
		segments[i].velocity = Vector3.ZERO