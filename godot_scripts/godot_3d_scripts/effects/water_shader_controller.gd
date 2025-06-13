extends MeshInstance

export var wave_speed = 0.5
export var wave_amplitude = 0.5
export var wave_frequency = 2.0
export var water_color = Color(0.0, 0.3, 0.5, 0.8)
export var deep_water_color = Color(0.0, 0.1, 0.3, 1.0)
export var foam_color = Color(1.0, 1.0, 1.0, 0.8)
export var transparency = 0.6
export var refraction_amount = 0.3
export var reflection_amount = 0.5
export var fresnel_power = 2.0

export var enable_foam = true
export var foam_distance = 2.0
export var foam_cutoff = 0.8

export var enable_caustics = true
export var caustics_scale = 5.0
export var caustics_speed = 0.3

export var enable_underwater_fog = true
export var fog_distance = 20.0

var time = 0.0
var water_material: ShaderMaterial

onready var reflection_probe = $ReflectionProbe
onready var foam_particles = $FoamParticles
onready var splash_area = $SplashArea

signal object_entered_water(object)
signal object_exited_water(object)

func _ready():
	_setup_water_material()
	_setup_collision_detection()
	
	if splash_area:
		splash_area.connect("body_entered", self, "_on_body_entered_water")
		splash_area.connect("body_exited", self, "_on_body_exited_water")

func _process(delta):
	time += delta
	_update_water_shader(delta)
	_update_foam_system()

func _setup_water_material():
	water_material = ShaderMaterial.new()
	water_material.shader = _create_water_shader()
	
	_update_material_parameters()
	
	set_surface_material(0, water_material)

func _create_water_shader() -> Shader:
	var shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float wave_speed = 0.5;
uniform float wave_amplitude = 0.5;
uniform float wave_frequency = 2.0;
uniform vec4 water_color : hint_color = vec4(0.0, 0.3, 0.5, 0.8);
uniform vec4 deep_water_color : hint_color = vec4(0.0, 0.1, 0.3, 1.0);
uniform vec4 foam_color : hint_color = vec4(1.0, 1.0, 1.0, 0.8);
uniform float transparency = 0.6;
uniform float refraction_amount = 0.3;
uniform float reflection_amount = 0.5;
uniform float fresnel_power = 2.0;
uniform float time = 0.0;

uniform bool enable_foam = true;
uniform float foam_distance = 2.0;
uniform float foam_cutoff = 0.8;

uniform sampler2D foam_texture;
uniform sampler2D normal_texture;
uniform sampler2D caustics_texture;

uniform bool enable_caustics = true;
uniform float caustics_scale = 5.0;
uniform float caustics_speed = 0.3;

varying vec3 world_pos;
varying vec3 world_normal;

float wave(vec2 position, float t) {
    float wave1 = sin(position.x * wave_frequency + t * wave_speed) * wave_amplitude;
    float wave2 = sin(position.y * wave_frequency * 0.8 + t * wave_speed * 1.3) * wave_amplitude * 0.7;
    float wave3 = sin((position.x + position.y) * wave_frequency * 0.5 + t * wave_speed * 0.7) * wave_amplitude * 0.5;
    return wave1 + wave2 + wave3;
}

vec3 get_wave_normal(vec2 position, float t) {
    float delta = 0.1;
    float height_center = wave(position, t);
    float height_x = wave(position + vec2(delta, 0.0), t);
    float height_z = wave(position + vec2(0.0, delta), t);
    
    vec3 tangent_x = vec3(delta, height_x - height_center, 0.0);
    vec3 tangent_z = vec3(0.0, height_z - height_center, delta);
    
    return normalize(cross(tangent_z, tangent_x));
}

void vertex() {
    world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
    
    float wave_height = wave(world_pos.xz, time);
    VERTEX.y += wave_height;
    
    world_normal = get_wave_normal(world_pos.xz, time);
    NORMAL = normalize((WORLD_MATRIX * vec4(world_normal, 0.0)).xyz);
}

void fragment() {
    vec3 view_dir = normalize(CAMERA_MATRIX[3].xyz - world_pos);
    
    vec2 normal_uv1 = world_pos.xz * 0.1 + vec2(time * 0.05, time * 0.03);
    vec2 normal_uv2 = world_pos.xz * 0.05 + vec2(-time * 0.04, time * 0.02);
    vec3 normal_map1 = texture(normal_texture, normal_uv1).xyz * 2.0 - 1.0;
    vec3 normal_map2 = texture(normal_texture, normal_uv2).xyz * 2.0 - 1.0;
    vec3 normal_combined = normalize(normal_map1 + normal_map2);
    
    NORMAL = normalize(mix(NORMAL, normal_combined, 0.3));
    
    float fresnel = pow(1.0 - dot(view_dir, NORMAL), fresnel_power);
    
    vec4 water = mix(deep_water_color, water_color, fresnel);
    
    if (enable_foam) {
        vec2 foam_uv = world_pos.xz * 0.5 + vec2(time * 0.1);
        float foam_tex = texture(foam_texture, foam_uv).r;
        
        float depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
        vec4 world_coord = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
        world_coord.xyz /= world_coord.w;
        float distance_to_surface = length(world_coord.xyz);
        
        float foam_factor = 1.0 - smoothstep(0.0, foam_distance, distance_to_surface);
        foam_factor *= step(foam_cutoff, foam_tex);
        
        water = mix(water, foam_color, foam_factor);
    }
    
    if (enable_caustics) {
        vec2 caustics_uv = world_pos.xz * caustics_scale;
        caustics_uv += vec2(time * caustics_speed, time * caustics_speed * 0.7);
        float caustics = texture(caustics_texture, caustics_uv).r;
        water.rgb += caustics * 0.2 * (1.0 - fresnel);
    }
    
    ALBEDO = water.rgb;
    ALPHA = mix(transparency, 1.0, fresnel);
    METALLIC = 0.0;
    ROUGHNESS = 0.1;
    SPECULAR = reflection_amount;
    
    vec2 refraction_offset = NORMAL.xz * refraction_amount * 0.1;
    EMISSION = texture(SCREEN_TEXTURE, SCREEN_UV + refraction_offset).rgb * transparency * 0.5;
}
"""
	return shader

func _update_material_parameters():
	if not water_material:
		return
	
	water_material.set_shader_param("wave_speed", wave_speed)
	water_material.set_shader_param("wave_amplitude", wave_amplitude)
	water_material.set_shader_param("wave_frequency", wave_frequency)
	water_material.set_shader_param("water_color", water_color)
	water_material.set_shader_param("deep_water_color", deep_water_color)
	water_material.set_shader_param("foam_color", foam_color)
	water_material.set_shader_param("transparency", transparency)
	water_material.set_shader_param("refraction_amount", refraction_amount)
	water_material.set_shader_param("reflection_amount", reflection_amount)
	water_material.set_shader_param("fresnel_power", fresnel_power)
	water_material.set_shader_param("enable_foam", enable_foam)
	water_material.set_shader_param("foam_distance", foam_distance)
	water_material.set_shader_param("foam_cutoff", foam_cutoff)
	water_material.set_shader_param("enable_caustics", enable_caustics)
	water_material.set_shader_param("caustics_scale", caustics_scale)
	water_material.set_shader_param("caustics_speed", caustics_speed)

func _update_water_shader(delta):
	if water_material:
		water_material.set_shader_param("time", time)

func _update_foam_system():
	if not foam_particles or not enable_foam:
		return
	
	foam_particles.emitting = true

func _setup_collision_detection():
	if not has_node("SplashArea"):
		var area = Area.new()
		area.name = "SplashArea"
		add_child(area)
		
		var shape = CollisionShape.new()
		var box = BoxShape.new()
		box.extents = Vector3(50, 5, 50)
		shape.shape = box
		area.add_child(shape)
		
		splash_area = area

func _on_body_entered_water(body):
	emit_signal("object_entered_water", body)
	_create_splash(body.global_transform.origin)
	
	if body.has_method("enter_water"):
		body.enter_water()

func _on_body_exited_water(body):
	emit_signal("object_exited_water", body)
	
	if body.has_method("exit_water"):
		body.exit_water()

func _create_splash(position: Vector3):
	var splash = CPUParticles.new()
	splash.emitting = true
	splash.amount = 50
	splash.lifetime = 1.0
	splash.one_shot = true
	splash.initial_velocity = 5.0
	splash.angular_velocity = 45.0
	splash.emission_shape = CPUParticles.EMISSION_SHAPE_SPHERE
	splash.emission_sphere_radius = 0.5
	splash.direction = Vector3.UP
	splash.gravity = Vector3(0, -9.8, 0)
	splash.color = Color(1, 1, 1, 0.8)
	
	add_child(splash)
	splash.global_transform.origin = position
	
	yield(get_tree().create_timer(2.0), "timeout")
	splash.queue_free()

func get_wave_height_at_position(position: Vector3) -> float:
	var wave1 = sin(position.x * wave_frequency + time * wave_speed) * wave_amplitude
	var wave2 = sin(position.z * wave_frequency * 0.8 + time * wave_speed * 1.3) * wave_amplitude * 0.7
	var wave3 = sin((position.x + position.z) * wave_frequency * 0.5 + time * wave_speed * 0.7) * wave_amplitude * 0.5
	return wave1 + wave2 + wave3 + global_transform.origin.y

func set_water_parameters(params: Dictionary):
	for param in params:
		if param in self:
			set(param, params[param])
	_update_material_parameters()

func create_ripple(position: Vector3, strength: float = 1.0):
	pass