shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always;
uniform vec4 water_color : source_color = vec4(0.07, 0.55, 0.76, 1.0);
varying float water_depth;
void vertex() {
 water_depth = COLOR.r;
}
void fragment() {
 float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
 float fresnel = pow(1.0 - facing, 5.0);
 float absorption = 1.0 - exp(-water_depth * 3.0);
 ALBEDO = mix(water_color.rgb, vec3(0.36, 0.72, 0.84), fresnel * 0.25);
 ROUGHNESS = 0.065;
 METALLIC = 0.0;
 SPECULAR = 0.35;
 ALPHA = clamp(0.45 + absorption * 0.34 + fresnel * 0.25, 0.45, 0.92);
}
