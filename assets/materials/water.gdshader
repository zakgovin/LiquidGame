shader_type spatial;
render_mode cull_disabled, unshaded;

uniform vec4 water_color : source_color = vec4(0.035, 0.59, 0.82, 1.0);
varying vec3 world_position;
varying float surface_shade;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	surface_shade = 0.72 + 0.28 * abs(NORMAL.y);
	VERTEX.y += 0.006 * sin(VERTEX.x * 13.0 + TIME * 2.0) * cos(VERTEX.z * 10.0 - TIME * 1.5);
}

void fragment() {
	float ripple = sin(world_position.x * 14.0 + world_position.z * 9.0 + TIME * 2.3);
	float glint = pow(max(0.0, sin(world_position.x * 5.0 - world_position.z * 6.0 + TIME * 1.3)), 32.0);
	ALBEDO = (water_color.rgb + vec3(0.005, 0.015, 0.02) * ripple + vec3(0.025, 0.045, 0.055) * glint) * surface_shade;
	ROUGHNESS = 0.19;
	METALLIC = 0.15;
	SPECULAR = 0.8;
	NORMAL = normalize(NORMAL + vec3(ripple * 0.045, 0.0, cos(world_position.z * 12.0 + TIME) * 0.045));
}
