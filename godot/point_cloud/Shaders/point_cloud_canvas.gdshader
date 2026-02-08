shader_type canvas_item;

// Uniforms for easy tweaking
uniform float point_density : hint_range(1.0, 500.0, 1.0) = 400.0;
uniform float point_size : hint_range(0.1, 2.0, 0.1) = 0.6;
uniform float edge_threshold : hint_range(0.0, 0.2, 0.01) = 0.03;
uniform float edge_width : hint_range(0.1, 1.0, 0.05) = 0.3;
uniform float movement_speed : hint_range(0.0, 5.0, 0.1) = 1.0;
uniform float movement_range : hint_range(0.0, 10.0, 0.5) = 3.0;
uniform sampler2D input_texture : source_color;

// Edge detection function using Sobel operator
float get_edge(vec2 uv, vec2 texel_size) {
    // Sobel kernels
    mat3 sobel_x = mat3(
        vec3(-1.0, 0.0, 1.0),
        vec3(-2.0, 0.0, 2.0),
        vec3(-1.0, 0.0, 1.0)
    );
    
    mat3 sobel_y = mat3(
        vec3(-1.0, -2.0, -1.0),
        vec3(0.0, 0.0, 0.0),
        vec3(1.0, 2.0, 1.0)
    );
    
    float gx = 0.0;
    float gy = 0.0;
    
    // Sample 3x3 neighborhood
    for(int i = -1; i <= 1; i++) {
        for(int j = -1; j <= 1; j++) {
            vec2 offset = vec2(float(i), float(j)) * texel_size;
            vec4 sample_color = texture(input_texture, uv + offset);
            float gray = dot(sample_color.rgb, vec3(0.299, 0.587, 0.114));
            
            gx += gray * sobel_x[i+1][j+1];
            gy += gray * sobel_y[i+1][j+1];
        }
    }
    
    return length(vec2(gx, gy));
}

void fragment() {
    // Get texture resolution
    vec2 resolution = vec2(textureSize(input_texture, 0));
    vec2 texel_size = 1.0 / resolution;
    
    // Use UV
    vec2 uv = UV;
    
    // Calculate grid cell
    vec2 grid_uv = uv * point_density;
    vec2 cell_id = floor(grid_uv);
    vec2 cell_uv = fract(grid_uv);
    
    // Create pseudo-random offset within each cell
    vec2 random_offset = fract(sin(vec2(
        dot(cell_id, vec2(127.1, 311.7)),
        dot(cell_id, vec2(269.5, 183.3))
    )) * 43758.5453);
    
    // Create smooth, circular movement using sine waves
    float phase1 = dot(cell_id, vec2(0.134, 0.247)) * 6.28318530718;
    float phase2 = dot(cell_id, vec2(0.391, 0.178)) * 6.28318530718;
    
    vec2 movement = vec2(
        sin(TIME * movement_speed + phase1),
        cos(TIME * movement_speed * 0.7 + phase2)
    ) * movement_range;
    
    // Animate the offset
    random_offset = fract(random_offset + movement * 0.1);
    
    // Point position within cell
    vec2 point_pos = random_offset;
    
    // Sample texture at the point position
    vec2 tex_coord = (cell_id + random_offset) / point_density;
    vec4 tex_color = texture(input_texture, tex_coord);
    
    // Get edge strength at this point
    float edge_strength = get_edge(tex_coord, texel_size);
    
    // Only show points near edges
    float edge_mask = smoothstep(edge_threshold, edge_threshold + edge_width, edge_strength);
    
    // Distance from current pixel to point
    float dist = length(cell_uv - point_pos);
    
    // Create circular point
    float point = smoothstep(point_size, point_size * 0.8, dist);
    
    // Apply edge mask to points
    point *= edge_mask;
    
    // Colored points on edges, with original alpha
    vec3 color = tex_color.rgb * point;
    float alpha = tex_color.a * point;
    
    COLOR = vec4(tex_color.rgb, alpha);
}