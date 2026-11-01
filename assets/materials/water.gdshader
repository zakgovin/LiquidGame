shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always, shadows_disabled;
uniform vec4 water_color : source_color = vec4(0.07, 0.55, 0.76, 1.0);
varying float water_depth;
void vertex() {
 water_depth = COLOR.r;
}
void fragment() {
 float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
 float fresnel = pow(1.0 - facing, 5.0);
 float absorption = 1.0 - exp(-water_depth * 3.0);
 ALBEDO = mix(water_color.rgb, vec3(0.64, 0.86, 0.95), fresnel * 0.65);
 EMISSION = ALBEDO * 0.025;
 ROUGHNESS = 0.08;
 METALLIC = 0.0;
 SPECULAR = 0.45;
 ALPHA = clamp(0.55 + absorption * 0.22 + fresnel * 0.08, 0.55, 0.85);
}
