shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
uniform vec4 glass_color : source_color = vec4(0.74, 0.81, 0.84, 1.0);
uniform float face_opacity = 0.065;
varying vec3 world_normal;
void vertex() {
 world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
 float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
 float fresnel = 0.025 + 0.975 * pow(1.0 - facing, 5.0);
 float side = 1.0 - abs(world_normal.y);
 ALBEDO = mix(glass_color.rgb, vec3(0.9, 0.95, 0.98), fresnel * 0.65);
 ROUGHNESS = 0.12;
 METALLIC = 0.0;
 SPECULAR = 0.65;
 CLEARCOAT = 0.7;
 CLEARCOAT_ROUGHNESS = 0.09;
 ALPHA = clamp(face_opacity + 0.36 * fresnel + 0.012 * side, 0.0, 0.65);
}
