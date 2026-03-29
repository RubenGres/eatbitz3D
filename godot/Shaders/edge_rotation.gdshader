shader_type canvas_item;

uniform vec2 edge_input = vec2(0.0, 0.0);
uniform float intensity = 0.0;

const float EDGE_W = 0.18;
const float LINE_SPEED = 2.0;
const float LINE_FREQ = 6.0;

float edge_glow(float dist) {
	return 1.0 - smoothstep(0.0, EDGE_W, dist);
}

float sweep_line(float dist) {
	float phase = fract(dist / EDGE_W * LINE_FREQ - TIME * LINE_SPEED);
	return smoothstep(0.35, 0.5, phase) * smoothstep(0.65, 0.5, phase);
}

void fragment() {
	vec2 uv = UV;

	float l = max(-edge_input.x, 0.0);
	float r = max(edge_input.x, 0.0);
	float t = max(-edge_input.y, 0.0);
	float b = max(edge_input.y, 0.0);

	float dist_l = uv.x;
	float dist_r = 1.0 - uv.x;
	float dist_t = uv.y;
	float dist_b = 1.0 - uv.y;

	float glow = edge_glow(dist_l) * l
	           + edge_glow(dist_r) * r
	           + edge_glow(dist_t) * t
	           + edge_glow(dist_b) * b;

	float lines = sweep_line(dist_l) * edge_glow(dist_l) * l
	            + sweep_line(dist_r) * edge_glow(dist_r) * r
	            + sweep_line(dist_t) * edge_glow(dist_t) * t
	            + sweep_line(dist_b) * edge_glow(dist_b) * b;

	float alpha = (glow * 0.5 + lines * 0.8) * intensity;
	COLOR = vec4(1.0, 1.0, 1.0, clamp(alpha * 0.4, 0.0, 0.5));
}
