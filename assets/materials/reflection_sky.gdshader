shader_type sky;
void sky() {
 vec3 studio = mix(vec3(0.13, 0.22, 0.30), vec3(0.70, 0.83, 0.92), clamp(EYEDIR.y * 0.65 + 0.35, 0.0, 1.0));
 float upper = smoothstep(0.22, 0.42, EYEDIR.y);
 float panel_a = (1.0 - smoothstep(0.075, 0.12, abs(EYEDIR.z + 0.25))) * (1.0 - smoothstep(0.45, 0.72, abs(EYEDIR.x))) * upper;
 float panel_b = (1.0 - smoothstep(0.06, 0.10, abs(EYEDIR.x - 0.45))) * (1.0 - smoothstep(0.35, 0.60, abs(EYEDIR.z))) * upper;
 COLOR = mix(studio, vec3(1.5, 1.55, 1.6), max(panel_a, panel_b) * 0.82);
}
