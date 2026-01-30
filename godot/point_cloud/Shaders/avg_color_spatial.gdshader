shader_type spatial;
render_mode unshaded;

uniform sampler2D input_texture : source_color;

void fragment() {
    vec4 avg_color = textureLod(input_texture, vec2(0.5), 99.0);
    
    // Undo premultiplied alpha to recover opaque average
    ALBEDO = avg_color.a > 0.001 ? avg_color.rgb / avg_color.a : vec3(0.0);
    ALPHA = 1.0;
}