shader_type spatial;
render_mode cull_back, depth_prepass_alpha;
uniform vec4 water_color : source_color = vec4(0.035, 0.59, 0.82, 1.0);
void fragment() {
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 4.0);
	ALBEDO = mix(water_color.rgb, vec3(0.55, 0.84, 0.94), fresnel * 0.35);
	EMISSION = water_color.rgb * 0.20;
	ROUGHNESS = 0.13;
	METALLIC = 0.03;
	SPECULAR = 0.85;
	ALPHA = 0.84 + 0.12 * fresnel;
}
