shader_type spatial;
render_mode cull_disabled;
uniform float stripe_direction = 1.0;
varying vec3 board_point;
void vertex() {
 board_point = VERTEX;
}
void fragment() {
 float phase = (board_point.x + stripe_direction * board_point.z + board_point.y) / 0.24;
 float stripe = sin(phase * 6.2831853);
 float edge = max(fwidth(stripe), 0.015);
 float yellow = smoothstep(-edge, edge, stripe);
 ALBEDO = mix(vec3(0.025, 0.035, 0.04), vec3(1.0, 0.73, 0.06), yellow);
 ROUGHNESS = 0.68;
}
