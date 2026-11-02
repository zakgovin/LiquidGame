shader_type spatial;
uniform sampler2D stone_noise : repeat_enable, filter_linear_mipmap;
uniform vec4 stone_color : source_color = vec4(0.90, 0.91, 0.88, 1.0);
uniform float low_height = -0.14;
uniform float high_height = 0.42;
uniform float vein_strength = 0.09;
varying float board_height;
void vertex() { board_height = VERTEX.y; }
void fragment() {
 float cloud = texture(stone_noise, UV * 0.13).r;
 float detail = texture(stone_noise, UV * 0.43 + vec2(0.17, 0.31)).r;
 float vein = abs(sin(UV.x * 0.94 + UV.y * 0.45 + cloud * 7.0 + detail * 0.28));
 float aa = max(fwidth(vein), 0.006);
 float line = 1.0 - smoothstep(0.025 - aa, 0.095 + aa, vein);
 float height_tone = mix(0.88, 1.0, clamp((board_height - low_height) / max(high_height - low_height, 0.01), 0.0, 1.0));
 ALBEDO = stone_color.rgb * height_tone * (1.0 - vein_strength * line - (cloud - 0.5) * 0.035);
 ROUGHNESS = 0.77 + detail * 0.07;
 SPECULAR = 0.25;
}
