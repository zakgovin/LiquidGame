shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
uniform vec4 glass_color : source_color = vec4(0.43, 0.68, 0.79, 1.0);
uniform float face_opacity = 0.22;
void fragment() {
 float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
 float edge = pow(1.0 - facing, 3.0);
 ALBEDO = mix(glass_color.rgb, vec3(0.83, 0.94, 0.98), edge * 0.55);
 ROUGHNESS = 0.14;
 METALLIC = 0.0;
 SPECULAR = 0.8;
 ALPHA = face_opacity + edge * 0.40;
}
