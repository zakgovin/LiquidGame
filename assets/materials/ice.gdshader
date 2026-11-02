shader_type spatial;
render_mode cull_disabled;
void fragment() {
 float edge = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
 ALBEDO = mix(vec3(0.43, 0.72, 0.84), vec3(0.90, 0.97, 0.99), 0.55 + edge * 0.4);
 ROUGHNESS = 0.20;
 SPECULAR = 0.85;
 METALLIC = 0.035;
 EMISSION = vec3(0.025, 0.05, 0.065) * edge;
}
