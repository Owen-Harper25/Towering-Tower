shader_type canvas_item;

uniform vec4 outline_colour : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float outline_thickness : hint_range(1.0, 5.0) = 1.0;
uniform bool outline_enabled = false;

float is_solid(float value) {
	return max(0.0, sign(value));
}

float has_solid_neighbor(sampler2D texture_sample, vec2 uv_coord, vec2 pixel_size){
	vec2 offset = outline_thickness * pixel_size;
	float sum_alpha = 0.0;
	vec2 sample_uv;

	sample_uv = clamp(uv_coord + vec2(1.0, 0.0) * offset, vec2(0.0), vec2(1.0));
	sum_alpha += texture(texture_sample, sample_uv).a;
	sample_uv = clamp(uv_coord + vec2(-1.0, 0.0) * offset, vec2(0.0), vec2(1.0));
	sum_alpha += texture(texture_sample, sample_uv).a;
	sample_uv = clamp(uv_coord + vec2(0.0, 1.0) * offset, vec2(0.0), vec2(1.0));
	sum_alpha += texture(texture_sample, sample_uv).a;
	sample_uv = clamp(uv_coord + vec2(0.0, -1.0) * offset, vec2(0.0), vec2(1.0));
	sum_alpha += texture(texture_sample, sample_uv).a;
	return is_solid(sum_alpha);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	COLOR = base;

	if (!outline_enabled) {
	} else {

	if (base.a == 0.0) {
		float outline_mask = has_solid_neighbor(TEXTURE, UV, TEXTURE_PIXEL_SIZE);
			if (outline_mask > 0.0) {
				COLOR = outline_colour;
			}
		}
	}
}
