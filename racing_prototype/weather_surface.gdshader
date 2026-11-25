shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D surface_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 surface_tint : source_color = vec4(1.0);
uniform vec2 texture_scale = vec2(1.0);
uniform float normal_strength = 1.0;
uniform float roughness_strength = 1.0;
uniform float base_specular = 0.38;
uniform float snow_retention : hint_range(0.0, 1.0) = 0.4;
uniform float rain : hint_range(0.0, 1.0) = 0.0;
uniform float snow : hint_range(0.0, 1.0) = 0.0;

varying vec2 terrain_position;

void vertex() {
	terrain_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 tiles = UV * texture_scale;
	vec3 painted_surface = texture(surface_color, tiles).rgb * surface_tint.rgb;
	float roughness = texture(surface_roughness, tiles).r * roughness_strength;
	float packed_snow = 0.0;
	if (snow > 0.0) {
		vec2 p = terrain_position;
		float drift = sin(dot(p, vec2(0.31, 0.57))) * sin(dot(p, vec2(0.29, -0.43)));
		packed_snow = snow * snow_retention * (0.83 + 0.17 * drift);
	}
	vec3 wet_surface = mix(painted_surface, painted_surface * vec3(0.58, 0.66, 0.74), rain);
	float snow_grain = mix(0.73, 0.93, roughness);
	ALBEDO = mix(wet_surface, vec3(0.81, 0.89, 0.99) * snow_grain, packed_snow);
	ROUGHNESS = mix(max(0.11, roughness * (1.0 - 0.72 * rain)), 0.87, packed_snow);
	SPECULAR = mix(base_specular + 0.27 * rain, 0.29, packed_snow);
	NORMAL_MAP = texture(surface_normal, tiles).rgb;
	NORMAL_MAP_DEPTH = normal_strength * (1.0 - 0.60 * packed_snow);
}
