shader_type spatial;
render_mode cull_back, depth_draw_always;
uniform vec4 water_color : source_color = vec4(0.07, 0.55, 0.76, 1.0);
uniform sampler2D scene_color : hint_screen_texture, filter_linear;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest;
void fragment() {
 float depth = texture(scene_depth, SCREEN_UV).r;
 vec4 floor_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
 float thickness = max(-floor_view.z / floor_view.w + VERTEX.z, 0.0);
 float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
 float fresnel = pow(1.0 - facing, 5.0);
 vec2 offset = NORMAL.xy * 0.008 * clamp(thickness, 0.0, 0.5);
 vec3 transmitted = texture(scene_color, clamp(SCREEN_UV + offset, vec2(0.002), vec2(0.998))).rgb;
 float absorption = clamp(1.0 - exp(-(thickness + 0.045) * 2.2), 0.28, 0.82);
 ALBEDO = water_color.rgb * absorption;
 EMISSION = transmitted * mix(vec3(0.68, 0.94, 1.0), vec3(1.0), fresnel) * (1.0 - absorption) * (1.0 - fresnel * 0.55);
 ROUGHNESS = 0.09;
 METALLIC = 0.0;
 SPECULAR = 0.85;
}
