shader_type particles;

uniform sampler2D input_texture : source_color;
uniform sampler2D height_texture: source_color;
uniform sampler2D noise_texture : hint_default_white;
uniform sampler2D scale_curve : repeat_disable;
uniform vec2 emission_shape = vec2(1.0, 1.0);
uniform float height_min = 0.0;
uniform float height_max = 1.0;
uniform float z_multiplier = 10.0;
uniform float jitter_strength = 0.1;
uniform float jitter_speed = 1.0;

vec2 hash(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

void start() {
	vec2 uv = hash(vec2(float(INDEX), float(INDEX) * 0.7123 + 42.0));
	
	float spawn_delay = 0.1;
	
	if (TIME < spawn_delay) {
		ACTIVE = false;
	} else {
		COLOR = texture(input_texture, uv);
		vec4 height = texture(height_texture, uv);
	    if (COLOR.a < 0.1) {
			ACTIVE = false;
		} else {
		    CUSTOM.xy = uv;
			CUSTOM.z = 0.0;
		    
			float normalized_height = (height.g - height_min) / max(height_max - height_min, 0.001);
			normalized_height = clamp(normalized_height, 0.0, 1.0);
			TRANSFORM[3].xyz = vec3(
			    (uv.x - 0.5) * emission_shape.x,
			    -(uv.y - 0.5) * emission_shape.y,
			    normalized_height * z_multiplier
			);
			
		}
	}
}

void process() {
    vec2 uv = CUSTOM.xy;
    vec2 noise = vec2(
        texture(noise_texture, uv + vec2(TIME * jitter_speed * 0.1, 0.0)).r,
        texture(noise_texture, uv + vec2(0.0, TIME * jitter_speed * 0.1 + 0.5)).r
    );
    TRANSFORM[3].xy += (noise - 0.5) * 2.0 * jitter_strength * DELTA;
    
	
	CUSTOM.z = min(1.0, CUSTOM.z + DELTA / LIFETIME);
	float lifetime_percent = CUSTOM.z;
	float scale = texture(scale_curve, vec2(lifetime_percent, 0.0)).r;
	float s = texture(scale_curve, vec2(lifetime_percent, 0.0)).r;

	// Set scale, don't multiply
	TRANSFORM[0] = vec4(scale, 0.0, 0.0, 0.0);
	TRANSFORM[1] = vec4(0.0, scale, 0.0, 0.0);
	TRANSFORM[2] = vec4(0.0, 0.0, scale, 0.0);
}