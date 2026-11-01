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
 // A grazing surface reflects pale light instead of becoming an opaque
 // blue rim. Keep a little fill light on steep sides of the stream.
 ALBEDO = mix(water_color.rgb, vec3(0.72, 0.89, 0.95), 0.25 + fresnel * 0.55);
 EMISSION = ALBEDO * 0.16;
 ROUGHNESS = 0.065;
 METALLIC = 0.0;
 SPECULAR = 0.35;
 ALPHA = clamp(0.25 + absorption * 0.20 + fresnel * 0.12, 0.25, 0.57);
}
