shader_type spatial;
render_mode unshaded;

uniform sampler2D color_texture : source_color;

varying vec3 particle_color;

void vertex() {
    // Generate random UV coordinates based on instance ID
    float random_seed = float(INSTANCE_ID);
    vec2 random_uv = vec2(
        fract(sin(random_seed * 12.9898) * 43758.5453),
        fract(sin(random_seed * 78.233) * 43758.5453)
    );
    
    // Sample the texture color in vertex shader
    particle_color = texture(color_texture, random_uv).rgb;
    
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

void fragment() {
    ALBEDO = particle_color;
    
    vec2 centered_uv = UV * 2.0 - 1.0;
    float dist = length(centered_uv);
    float circle = 1.0 - smoothstep(0.0, 1.0, dist);
    
    ALPHA = COLOR.a * circle;
}