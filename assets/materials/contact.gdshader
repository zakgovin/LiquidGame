shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float strength = 1.0;
void fragment() {
 ALBEDO = vec3(0.055, 0.065, 0.07);
 ALPHA = COLOR.a * strength;
}
