shader_type canvas_item;

uniform bool enabled = false;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0); // Default White

void fragment() {
	vec4 texture_color = texture(TEXTURE, UV);
	
	if (enabled) {
		// Mix the sprite texture with the flash color while preserving transparency
		COLOR = vec4(tint.rgb, texture_color.a);
	} else {
		// Normal sprite rendering
		COLOR = texture_color;
	}
}