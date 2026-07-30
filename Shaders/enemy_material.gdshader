shader_type canvas_item;

// --- Hit Flash Uniforms ---
uniform bool enabled = false;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0); // Default White

// --- Dissolve Uniforms ---
uniform float dissolve_value : hint_range(0.0, 1.0) = 1.0; // 1.0 = full sprite, 0.0 = fully dissolved
uniform sampler2D noise_tex : hint_default_white;

void fragment() {
	vec4 texture_color = texture(TEXTURE, UV);
	
	// 1. Dissolve Check (Discards pixels based on noise texture)
	float noise_val = texture(noise_tex, UV).r;
	if (noise_val > dissolve_value) {
		discard;
	}

	// 2. Hit Flash Check
	if (enabled) {
		COLOR = vec4(tint.rgb, texture_color.a);
	} else {
		COLOR = texture_color;
	}
}