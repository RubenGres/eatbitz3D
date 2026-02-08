shader_type spatial;
render_mode unshaded;

void fragment() {
    ALBEDO = COLOR.rgb;
    
    vec2 centered_uv = UV * 2.0 - 1.0;
    
    float dist = length(centered_uv);
    
    float circle = 1.0 - smoothstep(0.0, 1.0, dist);
    
    ALPHA = COLOR.a * circle;
}

void vertex() {
    vec3 scale = vec3(
        length(MODEL_MATRIX[0].xyz),
        length(MODEL_MATRIX[1].xyz),
        length(MODEL_MATRIX[2].xyz)
    );
    
    mat4 modified_model_view = VIEW_MATRIX * mat4(
        INV_VIEW_MATRIX[0] * scale.x,
        INV_VIEW_MATRIX[1] * scale.y,
        INV_VIEW_MATRIX[2] * scale.z,
        MODEL_MATRIX[3]
    );
    MODELVIEW_MATRIX = modified_model_view;
}
