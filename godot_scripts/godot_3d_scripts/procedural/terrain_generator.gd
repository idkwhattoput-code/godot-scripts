extends Spatial

# Procedural Terrain Generator for Godot 3D
# Generates terrain using noise functions with LOD system
# Supports texturing, vegetation placement, and chunk streaming

# Terrain parameters
export var terrain_size = Vector2(256, 256)
export var terrain_scale = 1.0
export var height_scale = 20.0
export var chunk_size = 64
export var vertex_spacing = 1.0

# Noise settings
export var noise_octaves = 4
export var noise_period = 64.0
export var noise_persistence = 0.5
export var noise_lacunarity = 2.0
export var noise_seed = 0

# LOD settings
export var lod_levels = 4
export var lod_distance_multiplier = 2.0
export var use_lod_morphing = true
export var morph_region = 0.3

# Texture settings
export var texture_scale = 0.1
export var use_triplanar_mapping = true
export var blend_sharpness = 2.0

# Material layers
export var grass_texture: Texture
export var rock_texture: Texture
export var sand_texture: Texture
export var snow_texture: Texture

# Height thresholds
export var sand_height = 5.0
export var grass_height = 15.0
export var rock_height = 25.0
export var snow_height = 35.0

# Vegetation
export var enable_vegetation = true
export var vegetation_density = 0.1
export var tree_scenes: Array = []
export var grass_scenes: Array = []
export var rock_scenes: Array = []

# Performance
export var chunks_per_frame = 2
export var async_generation = true
export var use_physics_collision = true
export var collision_lod = 2

# Internal variables
var noise: OpenSimplexNoise
var chunks = {}
var chunk_meshes = {}
var generation_queue = []
var viewer_position = Vector3.ZERO
var terrain_material: ShaderMaterial

# Chunk data structure
class TerrainChunk:
	var position: Vector2
	var lod_level: int
	var mesh_instance: MeshInstance
	var collision_shape: CollisionShape
	var height_map: Array
	var normal_map: Array
	var vegetation_instances: Array
	var is_generating: bool = false

func _ready():
	# Initialize noise
	setup_noise()
	
	# Create terrain material
	create_terrain_material()
	
	# Start terrain generation
	generate_initial_terrain()

func setup_noise():
	"""Setup noise generator"""
	noise = OpenSimplexNoise.new()
	noise.seed = noise_seed
	noise.octaves = noise_octaves
	noise.period = noise_period
	noise.persistence = noise_persistence
	noise.lacunarity = noise_lacunarity

func create_terrain_material():
	"""Create terrain shader material"""
	var shader_code = """
shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx;

uniform sampler2D grass_texture : hint_albedo;
uniform sampler2D rock_texture : hint_albedo;
uniform sampler2D sand_texture : hint_albedo;
uniform sampler2D snow_texture : hint_albedo;

uniform float texture_scale = 0.1;
uniform float blend_sharpness = 2.0;
uniform float sand_height = 5.0;
uniform float grass_height = 15.0;
uniform float rock_height = 25.0;
uniform float snow_height = 35.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 terrain_normal = normalize(world_normal);
	float height = world_pos.y;
	
	// Calculate texture coordinates for triplanar mapping
	vec2 uv_x = world_pos.yz * texture_scale;
	vec2 uv_y = world_pos.xz * texture_scale;
	vec2 uv_z = world_pos.xy * texture_scale;
	
	// Triplanar blending
	vec3 blend_weights = abs(terrain_normal);
	blend_weights = pow(blend_weights, vec3(blend_sharpness));
	blend_weights = blend_weights / (blend_weights.x + blend_weights.y + blend_weights.z);
	
	// Sample textures
	vec3 sand_color = texture(sand_texture, uv_y).rgb;
	vec3 grass_color = texture(grass_texture, uv_y).rgb;
	vec3 rock_color = (
		texture(rock_texture, uv_x).rgb * blend_weights.x +
		texture(rock_texture, uv_y).rgb * blend_weights.y +
		texture(rock_texture, uv_z).rgb * blend_weights.z
	);
	vec3 snow_color = texture(snow_texture, uv_y).rgb;
	
	// Height-based blending
	vec3 final_color;
	
	if (height < sand_height) {
		final_color = sand_color;
	} else if (height < grass_height) {
		float t = smoothstep(sand_height, grass_height, height);
		final_color = mix(sand_color, grass_color, t);
	} else if (height < rock_height) {
		float t = smoothstep(grass_height, rock_height, height);
		float slope = 1.0 - terrain_normal.y;
		final_color = mix(grass_color, rock_color, max(t, slope * 2.0));
	} else if (height < snow_height) {
		float t = smoothstep(rock_height, snow_height, height);
		final_color = mix(rock_color, snow_color, t);
	} else {
		final_color = snow_color;
	}
	
	// Slope-based rock blending
	float slope_factor = 1.0 - terrain_normal.y;
	if (slope_factor > 0.5) {
		final_color = mix(final_color, rock_color, (slope_factor - 0.5) * 2.0);
	}
	
	ALBEDO = final_color;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
}
	"""
	
	var shader = Shader.new()
	shader.code = shader_code
	
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = shader
	terrain_material.set_shader_param("grass_texture", grass_texture)
	terrain_material.set_shader_param("rock_texture", rock_texture)
	terrain_material.set_shader_param("sand_texture", sand_texture)
	terrain_material.set_shader_param("snow_texture", snow_texture)
	terrain_material.set_shader_param("texture_scale", texture_scale)
	terrain_material.set_shader_param("blend_sharpness", blend_sharpness)
	terrain_material.set_shader_param("sand_height", sand_height)
	terrain_material.set_shader_param("grass_height", grass_height)
	terrain_material.set_shader_param("rock_height", rock_height)
	terrain_material.set_shader_param("snow_height", snow_height)

func generate_initial_terrain():
	"""Generate initial terrain chunks around origin"""
	var chunks_per_side = int(terrain_size.x / chunk_size)
	
	for x in range(-chunks_per_side / 2, chunks_per_side / 2):
		for z in range(-chunks_per_side / 2, chunks_per_side / 2):
			var chunk_pos = Vector2(x, z)
			request_chunk(chunk_pos, 0)

func request_chunk(chunk_pos: Vector2, lod_level: int):
	"""Request generation of a chunk"""
	var key = str(chunk_pos) + "_" + str(lod_level)
	
	if key in chunks:
		return  # Already exists
	
	# Add to generation queue
	generation_queue.append({
		"position": chunk_pos,
		"lod": lod_level
	})

func _process(delta):
	# Update viewer position (usually camera or player)
	var camera = get_viewport().get_camera()
	if camera:
		viewer_position = camera.global_transform.origin
	
	# Process generation queue
	process_generation_queue()
	
	# Update LODs
	update_chunk_lods()
	
	# Update vegetation if enabled
	if enable_vegetation:
		update_vegetation()

func process_generation_queue():
	"""Process chunk generation queue"""
	var chunks_generated = 0
	
	while generation_queue.size() > 0 and chunks_generated < chunks_per_frame:
		var chunk_data = generation_queue.pop_front()
		generate_chunk(chunk_data.position, chunk_data.lod)
		chunks_generated += 1

func generate_chunk(chunk_pos: Vector2, lod_level: int):
	"""Generate a single terrain chunk"""
	var chunk = TerrainChunk.new()
	chunk.position = chunk_pos
	chunk.lod_level = lod_level
	chunk.is_generating = true
	
	# Calculate world position
	var world_pos = Vector3(
		chunk_pos.x * chunk_size * vertex_spacing,
		0,
		chunk_pos.y * chunk_size * vertex_spacing
	)
	
	# Generate height map
	chunk.height_map = generate_height_map(chunk_pos, lod_level)
	chunk.normal_map = calculate_normals(chunk.height_map, lod_level)
	
	# Create mesh
	var mesh = generate_chunk_mesh(chunk)
	
	# Create mesh instance
	chunk.mesh_instance = MeshInstance.new()
	chunk.mesh_instance.mesh = mesh
	chunk.mesh_instance.material_override = terrain_material
	chunk.mesh_instance.transform.origin = world_pos
	add_child(chunk.mesh_instance)
	
	# Create collision if needed
	if use_physics_collision and lod_level <= collision_lod:
		create_chunk_collision(chunk, mesh)
	
	# Store chunk
	var key = str(chunk_pos) + "_" + str(lod_level)
	chunks[key] = chunk
	
	chunk.is_generating = false
	
	# Generate vegetation if enabled
	if enable_vegetation and lod_level == 0:
		generate_vegetation(chunk)

func generate_height_map(chunk_pos: Vector2, lod_level: int) -> Array:
	"""Generate height map for chunk"""
	var lod_scale = pow(2, lod_level)
	var size = chunk_size / lod_scale + 1
	var height_map = []
	
	for z in range(size):
		var row = []
		for x in range(size):
			var world_x = (chunk_pos.x * chunk_size + x * lod_scale) * vertex_spacing
			var world_z = (chunk_pos.y * chunk_size + z * lod_scale) * vertex_spacing
			
			var height = get_height_at_position(world_x, world_z)
			row.append(height)
		height_map.append(row)
	
	return height_map

func get_height_at_position(x: float, z: float) -> float:
	"""Get terrain height at world position"""
	var height = 0.0
	
	# Base terrain shape
	height += noise.get_noise_2d(x * 0.01, z * 0.01) * height_scale
	
	# Add detail layers
	height += noise.get_noise_2d(x * 0.05, z * 0.05) * height_scale * 0.5
	height += noise.get_noise_2d(x * 0.1, z * 0.1) * height_scale * 0.25
	
	# Add features like mountains or valleys
	var feature_noise = noise.get_noise_2d(x * 0.002, z * 0.002)
	if feature_noise > 0.3:
		height += pow(feature_noise, 2) * height_scale * 2
	
	return height

func calculate_normals(height_map: Array, lod_level: int) -> Array:
	"""Calculate normal vectors from height map"""
	var size = height_map.size()
	var normal_map = []
	var lod_scale = pow(2, lod_level) * vertex_spacing
	
	for z in range(size):
		var row = []
		for x in range(size):
			var h_left = height_map[z][max(0, x-1)]
			var h_right = height_map[z][min(size-1, x+1)]
			var h_down = height_map[max(0, z-1)][x]
			var h_up = height_map[min(size-1, z+1)][x]
			
			var normal = Vector3(
				h_left - h_right,
				2.0 * lod_scale,
				h_down - h_up
			).normalized()
			
			row.append(normal)
		normal_map.append(row)
	
	return normal_map

func generate_chunk_mesh(chunk: TerrainChunk) -> ArrayMesh:
	"""Generate mesh for terrain chunk"""
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var vertices = PoolVector3Array()
	var normals = PoolVector3Array()
	var uvs = PoolVector2Array()
	var indices = PoolIntArray()
	
	var lod_scale = pow(2, chunk.lod_level)
	var size = chunk_size / lod_scale + 1
	
	# Generate vertices
	for z in range(size):
		for x in range(size):
			var height = chunk.height_map[z][x]
			var normal = chunk.normal_map[z][x]
			
			vertices.append(Vector3(
				x * lod_scale * vertex_spacing,
				height,
				z * lod_scale * vertex_spacing
			))
			normals.append(normal)
			uvs.append(Vector2(float(x) / (size - 1), float(z) / (size - 1)))
	
	# Generate indices
	for z in range(size - 1):
		for x in range(size - 1):
			var idx = z * size + x
			
			# First triangle
			indices.append(idx)
			indices.append(idx + size)
			indices.append(idx + 1)
			
			# Second triangle
			indices.append(idx + 1)
			indices.append(idx + size)
			indices.append(idx + size + 1)
	
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	return mesh

func create_chunk_collision(chunk: TerrainChunk, mesh: ArrayMesh):
	"""Create collision shape for chunk"""
	var static_body = StaticBody.new()
	chunk.mesh_instance.add_child(static_body)
	
	var collision_shape = CollisionShape.new()
	static_body.add_child(collision_shape)
	
	# Create trimesh collision from mesh
	collision_shape.shape = mesh.create_trimesh_shape()

func generate_vegetation(chunk: TerrainChunk):
	"""Generate vegetation for chunk"""
	# Implementation for vegetation placement
	pass

func update_chunk_lods():
	"""Update chunk LOD levels based on viewer distance"""
	# Implementation for LOD updates
	pass

func update_vegetation():
	"""Update vegetation visibility"""
	# Implementation for vegetation updates
	pass