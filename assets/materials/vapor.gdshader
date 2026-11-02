shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
varying float opacity;
void vertex() {
 mat4 facing = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
 facing[0].xyz *= length(MODEL_MATRIX[0].xyz);
 facing[1].xyz *= length(MODEL_MATRIX[1].xyz);
 facing[2].xyz *= length(MODEL_MATRIX[2].xyz);
 MODELVIEW_MATRIX = VIEW_MATRIX * facing;
 opacity = INSTANCE_CUSTOM.r;
}
void fragment() {
 float radius = length(UV - vec2(0.5)) * 2.0;
 ALBEDO = vec3(0.90, 0.94, 0.96);
 ALPHA = (1.0 - smoothstep(0.1, 1.0, radius)) * opacity;
}
