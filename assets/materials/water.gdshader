shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always, shadows_disabled;
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear;
uniform vec4 water_color : source_color = vec4(0.07, 0.55, 0.76, 1.0);
// Foreground simulation time also freezes the fine waves during pause.
uniform float flow_time = 0.0;
varying float optical_path;
varying vec2 flow;
varying vec3 local_point;
varying mat3 local_to_view;
void vertex() {
 optical_path = COLOR.r;
 flow = (COLOR.gb - vec2(0.5)) * 6.4;
 local_point = VERTEX;
 local_to_view = mat3(MODELVIEW_MATRIX);
}
vec2 wave_slope(vec2 p, float t) {
 return vec2(cos(p.x * 23.0 + p.y * 11.0 - t * 2.1), sin(p.x * 9.0 - p.y * 19.0 + t * 1.7));
}
void fragment() {
 float speed = length(flow);
 float phase = fract(flow_time * 0.35);
 float second = fract(phase + 0.5);
 vec2 a = wave_slope(local_point.xz - flow * phase * 0.12, flow_time);
 vec2 b = wave_slope(local_point.xz - flow * second * 0.12, flow_time);
 vec2 slope = mix(a, b, abs(phase * 2.0 - 1.0));
 float amplitude = 0.004 * smoothstep(0.02, 0.35, speed);
 vec3 n = normalize(NORMAL + local_to_view * vec3(slope.x, 0.0, slope.y) * amplitude);
 NORMAL = n;
 float facing = clamp(dot(n, normalize(VIEW)), 0.0, 1.0);
 float fresnel = 0.0204 + 0.9796 * pow(1.0 - facing, 5.0);
 float thickness = max(optical_path, 0.0);
 vec2 sample_uv = clamp(SCREEN_UV + n.xy * min(thickness * 0.035, 0.012), vec2(0.002), vec2(0.998));
 vec3 behind = textureLod(scene_color, sample_uv, 0.0).rgb;
 // Optical path through real parcel volume, including airborne water.
 vec3 transmission = exp(-vec3(7.0, 2.3, 0.8) * thickness);
 vec3 scattering = mix(water_color.rgb, vec3(0.12,0.42,0.52), 0.65);
 EMISSION = behind * transmission * (1.0 - fresnel);
 ALBEDO = scattering * (vec3(1.0) - transmission) + vec3(0.10,0.15,0.17) * fresnel;
 ROUGHNESS = 0.07 + 0.025 * clamp(speed, 0.0, 1.0);
 METALLIC = 0.0;
 SPECULAR = 0.36;
 ALPHA = 1.0;
}
