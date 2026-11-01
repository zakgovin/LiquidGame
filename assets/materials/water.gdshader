shader_type spatial;
render_mode cull_back;
uniform vec4 water_color : source_color = vec4(0.07, 0.55, 0.76, 1.0);
void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 5.0);
	ALBEDO = mix(water_color.rgb, vec3(0.58, 0.81, 0.89), fresnel * 0.32);
	ROUGHNESS = 0.075;
	METALLIC = 0.0;
	SPECULAR = 0.85;

}
