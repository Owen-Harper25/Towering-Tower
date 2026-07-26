shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform vec3 color_shift = vec3(1.0, 1.0, 1.0);
uniform float vibrancy : hint_range(0.0, 2.0) = 1.0;
uniform float brightness : hint_range(0.5, 1.5) = 1.0;

void fragment() {
	vec4 screen_color = texture(SCREEN_TEXTURE, SCREEN_UV);
	vec3 rgb = screen_color.rgb;

    // 1. Apply Vibrancy (Saturation)
	float gray = dot(rgb, vec3(0.299, 0.587, 0.114));
	rgb = mix(vec3(gray), rgb, vibrancy);

    // 2. Apply Color Shift (Seasonal Tone)
    // We use a "Soft Light" blend math to keep it from looking like a flat overlay
	vec3 shift;
	shift.r = rgb.r < 0.5 ? (2.0 * rgb.r * color_shift.r) : (1.0 - 2.0 * (1.0 - rgb.r) * (1.0 - color_shift.r));
	shift.g = rgb.g < 0.5 ? (2.0 * rgb.g * color_shift.g) : (1.0 - 2.0 * (1.0 - rgb.g) * (1.0 - color_shift.g));
	shift.b = rgb.b < 0.5 ? (2.0 * rgb.b * color_shift.b) : (1.0 - 2.0 * (1.0 - rgb.b) * (1.0 - color_shift.b));

    // 3. Final Adjustments
	rgb = mix(rgb, shift, 0.6); // 60% shift for a balanced look
	rgb *= brightness;

	COLOR = vec4(rgb, 1.0);
}