shader_type canvas_item;

uniform float radius : hint_range(0.0, 0.5) = 0.05;

void fragment() {
    vec2 uv = UV;
    vec2 half_size = vec2(0.5);
    vec2 d = abs(uv - half_size) - (half_size - vec2(radius));
    float dist = length(max(d, 0.0)) - radius;
    float alpha = 1.0 - smoothstep(-0.005, 0.005, dist);
    COLOR = texture(TEXTURE, uv);
    COLOR.a *= alpha;
}