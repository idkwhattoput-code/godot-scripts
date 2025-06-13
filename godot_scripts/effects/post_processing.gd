extends Control

export var enable_bloom = true
export var bloom_threshold = 1.0
export var bloom_intensity = 1.0
export var bloom_blur_passes = 5

export var enable_vignette = true
export var vignette_intensity = 0.4
export var vignette_color = Color(0, 0, 0, 1)

export var enable_chromatic_aberration = false
export var aberration_strength = 5.0

export var enable_film_grain = false
export var grain_intensity = 0.05

export var enable_screen_shake = true
export var shake_power = 0.0
export var shake_duration = 0.0

export var enable_color_correction = true
export var brightness = 1.0
export var contrast = 1.0
export var saturation = 1.0

export var enable_depth_of_field = false
export var dof_blur_far_distance = 10.0
export var dof_blur_far_transition = 5.0
export var dof_blur_near_distance = 2.0
export var dof_blur_near_transition = 1.0

var time = 0.0
var current_shake_power = 0.0
var shake_timer = 0.0

onready var post_process_viewport = $PostProcessViewport
onready var screen_texture = $ScreenTexture

signal post_process_changed()

func _ready():
	_setup_post_processing()
	_create_screen_shader()

func _process(delta):
	time += delta
	
	if enable_screen_shake and shake_timer > 0:
		shake_timer -= delta
		_apply_screen_shake(delta)
	else:
		current_shake_power = 0.0
	
	_update_shader_params()

func _setup_post_processing():
	rect_min_size = OS.window_size
	rect_size = OS.window_size
	
	if not screen_texture:
		screen_texture = TextureRect.new()
		screen_texture.name = "ScreenTexture"
		screen_texture.expand = true
		screen_texture.rect_min_size = rect_size
		add_child(screen_texture)

func _create_screen_shader():
	var shader_material = ShaderMaterial.new()
	shader_material.shader = _generate_post_process_shader()
	
	if screen_texture:
		screen_texture.material = shader_material
	
	_update_shader_params()

func _generate_post_process_shader() -> Shader:
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform bool enable_bloom = true;
uniform float bloom_threshold = 1.0;
uniform float bloom_intensity = 1.0;

uniform bool enable_vignette = true;
uniform float vignette_intensity = 0.4;
uniform vec4 vignette_color : hint_color = vec4(0.0, 0.0, 0.0, 1.0);

uniform bool enable_chromatic_aberration = false;
uniform float aberration_strength = 5.0;

uniform bool enable_film_grain = false;
uniform float grain_intensity = 0.05;
uniform float time = 0.0;

uniform bool enable_color_correction = true;
uniform float brightness = 1.0;
uniform float contrast = 1.0;
uniform float saturation = 1.0;

uniform vec2 shake_offset = vec2(0.0, 0.0);

vec3 apply_bloom(vec3 color, vec2 uv, sampler2D tex) {
    if (!enable_bloom) return color;
    
    vec3 bloom = vec3(0.0);
    float total_weight = 0.0;
    
    for (int i = -2; i <= 2; i++) {
        for (int j = -2; j <= 2; j++) {
            vec2 offset = vec2(float(i), float(j)) * 0.003;
            vec3 sample_color = texture(tex, uv + offset).rgb;
            
            float luminance = dot(sample_color, vec3(0.299, 0.587, 0.114));
            if (luminance > bloom_threshold) {
                float weight = exp(-float(i*i + j*j) * 0.5);
                bloom += sample_color * weight;
                total_weight += weight;
            }
        }
    }
    
    bloom /= total_weight;
    return color + bloom * bloom_intensity;
}

vec3 apply_vignette(vec3 color, vec2 uv) {
    if (!enable_vignette) return color;
    
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(uv, center);
    float vignette = smoothstep(0.8, 0.4, dist);
    vignette = 1.0 - (1.0 - vignette) * vignette_intensity;
    
    return mix(vignette_color.rgb, color, vignette);
}

vec3 apply_chromatic_aberration(sampler2D tex, vec2 uv) {
    if (!enable_chromatic_aberration) return texture(tex, uv).rgb;
    
    vec2 center = vec2(0.5, 0.5);
    vec2 offset = (uv - center) * aberration_strength * 0.001;
    
    float r = texture(tex, uv + offset).r;
    float g = texture(tex, uv).g;
    float b = texture(tex, uv - offset).b;
    
    return vec3(r, g, b);
}

vec3 apply_film_grain(vec3 color, vec2 uv) {
    if (!enable_film_grain) return color;
    
    float noise = fract(sin(dot(uv + time, vec2(12.9898, 78.233))) * 43758.5453);
    return color + (noise - 0.5) * grain_intensity;
}

vec3 apply_color_correction(vec3 color) {
    if (!enable_color_correction) return color;
    
    // Brightness
    color *= brightness;
    
    // Contrast
    color = (color - 0.5) * contrast + 0.5;
    
    // Saturation
    vec3 gray = vec3(dot(color, vec3(0.299, 0.587, 0.114)));
    color = mix(gray, color, saturation);
    
    return clamp(color, 0.0, 1.0);
}

void fragment() {
    vec2 uv = UV + shake_offset;
    
    vec3 color = apply_chromatic_aberration(TEXTURE, uv);
    color = apply_bloom(color, uv, TEXTURE);
    color = apply_vignette(color, UV);
    color = apply_film_grain(color, UV);
    color = apply_color_correction(color);
    
    COLOR = vec4(color, 1.0);
}
"""
	return shader

func _update_shader_params():
	if not screen_texture or not screen_texture.material:
		return
	
	var mat = screen_texture.material
	
	mat.set_shader_param("enable_bloom", enable_bloom)
	mat.set_shader_param("bloom_threshold", bloom_threshold)
	mat.set_shader_param("bloom_intensity", bloom_intensity)
	
	mat.set_shader_param("enable_vignette", enable_vignette)
	mat.set_shader_param("vignette_intensity", vignette_intensity)
	mat.set_shader_param("vignette_color", vignette_color)
	
	mat.set_shader_param("enable_chromatic_aberration", enable_chromatic_aberration)
	mat.set_shader_param("aberration_strength", aberration_strength)
	
	mat.set_shader_param("enable_film_grain", enable_film_grain)
	mat.set_shader_param("grain_intensity", grain_intensity)
	mat.set_shader_param("time", time)
	
	mat.set_shader_param("enable_color_correction", enable_color_correction)
	mat.set_shader_param("brightness", brightness)
	mat.set_shader_param("contrast", contrast)
	mat.set_shader_param("saturation", saturation)
	
	if current_shake_power > 0:
		var shake_x = (randf() - 0.5) * 2.0 * current_shake_power
		var shake_y = (randf() - 0.5) * 2.0 * current_shake_power
		mat.set_shader_param("shake_offset", Vector2(shake_x, shake_y) * 0.01)
	else:
		mat.set_shader_param("shake_offset", Vector2.ZERO)

func apply_screen_shake(power: float, duration: float):
	shake_power = power
	shake_duration = duration
	shake_timer = duration
	current_shake_power = power

func _apply_screen_shake(delta):
	var damping = ease(shake_timer / shake_duration, 1.0)
	current_shake_power = shake_power * damping

func set_bloom_params(threshold: float, intensity: float):
	bloom_threshold = threshold
	bloom_intensity = intensity
	_update_shader_params()
	emit_signal("post_process_changed")

func set_vignette_params(intensity: float, color: Color):
	vignette_intensity = intensity
	vignette_color = color
	_update_shader_params()
	emit_signal("post_process_changed")

func set_color_correction(bright: float, cont: float, sat: float):
	brightness = bright
	contrast = cont
	saturation = sat
	_update_shader_params()
	emit_signal("post_process_changed")

func enable_effect(effect_name: String, enabled: bool):
	match effect_name:
		"bloom":
			enable_bloom = enabled
		"vignette":
			enable_vignette = enabled
		"chromatic_aberration":
			enable_chromatic_aberration = enabled
		"film_grain":
			enable_film_grain = enabled
		"color_correction":
			enable_color_correction = enabled
	
	_update_shader_params()
	emit_signal("post_process_changed")

func save_settings() -> Dictionary:
	return {
		"bloom": {
			"enabled": enable_bloom,
			"threshold": bloom_threshold,
			"intensity": bloom_intensity
		},
		"vignette": {
			"enabled": enable_vignette,
			"intensity": vignette_intensity,
			"color": vignette_color
		},
		"chromatic_aberration": {
			"enabled": enable_chromatic_aberration,
			"strength": aberration_strength
		},
		"film_grain": {
			"enabled": enable_film_grain,
			"intensity": grain_intensity
		},
		"color_correction": {
			"enabled": enable_color_correction,
			"brightness": brightness,
			"contrast": contrast,
			"saturation": saturation
		}
	}

func load_settings(settings: Dictionary):
	if settings.has("bloom"):
		enable_bloom = settings.bloom.enabled
		bloom_threshold = settings.bloom.threshold
		bloom_intensity = settings.bloom.intensity
	
	if settings.has("vignette"):
		enable_vignette = settings.vignette.enabled
		vignette_intensity = settings.vignette.intensity
		vignette_color = settings.vignette.color
	
	if settings.has("chromatic_aberration"):
		enable_chromatic_aberration = settings.chromatic_aberration.enabled
		aberration_strength = settings.chromatic_aberration.strength
	
	if settings.has("film_grain"):
		enable_film_grain = settings.film_grain.enabled
		grain_intensity = settings.film_grain.intensity
	
	if settings.has("color_correction"):
		enable_color_correction = settings.color_correction.enabled
		brightness = settings.color_correction.brightness
		contrast = settings.color_correction.contrast
		saturation = settings.color_correction.saturation
	
	_update_shader_params()
	emit_signal("post_process_changed")