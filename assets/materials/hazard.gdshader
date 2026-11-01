shader_type spatial;
render_mode cull_disabled;
varying vec3 world_point;
void vertex() {
 world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
 float phase = (world_point.x + world_point.z + world_point.y) / 0.24;
 float stripe = sin(phase * 6.2831853);
 float edge = max(fwidth(stripe), 0.015);
 float yellow = smoothstep(-edge, edge, stripe);
 ALBEDO = mix(vec3(0.025, 0.035, 0.04), vec3(1.0, 0.73, 0.06), yellow);
 ROUGHNESS = 0.68;
}
