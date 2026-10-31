shader_type spatial;
render_mode cull_disabled, unshaded;

uniform vec4 water_color : source_color = vec4(0.035, 0.59, 0.82, 1.0);
varying vec3 world_position;
varying float surface_shade;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	surface_shade = 0.90 + 0.10 * abs(NORMAL.y);
	VERTEX.y += 0.003 * sin(VERTEX.x * 13.0 + TIME * 2.0) * cos(VERTEX.z * 10.0 - TIME * 1.5);
}

void fragment() {
	float ripple = sin(world_position.x * 8.0 + world_position.z * 6.0 + sin(world_position.z * 5.0 - TIME * 1.8) * 0.6 + TIME * 2.0);
	float glint = smoothstep(0.94, 1.0, ripple);
	ALBEDO = (water_color.rgb + vec3(0.005, 0.015, 0.02) * ripple + vec3(0.045, 0.065, 0.07) * glint) * surface_shade;
	ROUGHNESS = 0.19;
	METALLIC = 0.15;
	SPECULAR = 0.8;
	NORMAL = normalize(NORMAL + vec3(ripple * 0.045, 0.0, cos(world_position.z * 12.0 + TIME) * 0.045));
}
