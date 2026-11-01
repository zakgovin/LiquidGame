shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
uniform vec4 glass_color : source_color = vec4(0.47, 0.75, 0.87, 1.0);
uniform float face_opacity = 0.13;
void fragment() {
 float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
 float fresnel = 0.04 + 0.96 * pow(1.0 - facing, 5.0);
 float side = 1.0 - abs(NORMAL.y);
 ALBEDO = mix(glass_color.rgb, vec3(0.78, 0.94, 1.0), fresnel * 0.6);
 ROUGHNESS = 0.07;
 METALLIC = 0.0;
 SPECULAR = 0.65;
 CLEARCOAT = 0.7;
 CLEARCOAT_ROUGHNESS = 0.09;
 ALPHA = clamp(face_opacity + 0.46 * fresnel + 0.035 * side, 0.0, 0.86);
}
