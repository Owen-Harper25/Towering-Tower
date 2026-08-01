shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float darkness : hint_range(0.6, 1.0) = 0.92;
uniform float glow_strength : hint_range(0.0, 0.5) = 0.10;

float bright_mask(vec3 color) {
	return smoothstep(0.58, 0.92, max(color.r, max(color.g, color.b)));
}

void fragment() {
	vec2 pixel = SCREEN_PIXEL_SIZE * 2.0;
	vec3 base = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
	vec3 glow = vec3(0.0);
	vec3 sample_a = texture(SCREEN_TEXTURE, SCREEN_UV + vec2(pixel.x, 0.0)).rgb;
	vec3 sample_b = texture(SCREEN_TEXTURE, SCREEN_UV - vec2(pixel.x, 0.0)).rgb;
	vec3 sample_c = texture(SCREEN_TEXTURE, SCREEN_UV + vec2(0.0, pixel.y)).rgb;
	vec3 sample_d = texture(SCREEN_TEXTURE, SCREEN_UV - vec2(0.0, pixel.y)).rgb;
	glow += sample_a * bright_mask(sample_a);
	glow += sample_b * bright_mask(sample_b);
	glow += sample_c * bright_mask(sample_c);
	glow += sample_d * bright_mask(sample_d);
	glow *= 0.25;
	COLOR = vec4(base * darkness + glow * glow_strength, 1.0);
}
