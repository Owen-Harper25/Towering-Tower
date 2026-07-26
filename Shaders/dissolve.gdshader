shader_type canvas_item;

uniform float dissolve_value : hint_range(0.0, 1.0);
uniform float mix_ratio : hint_range(0, 1.0);
uniform sampler2D dissolve_noise;
uniform sampler2D dissolve_gradient;

void fragment() {
	vec4 main_texture = texture(TEXTURE, UV);
	vec4 a = texture(dissolve_noise, UV);
	vec4 b = texture(dissolve_gradient, UV);
	vec4 noise_texture = mix(a,b, mix_ratio);
	main_texture.a *= floor(dissolve_value + min(1, noise_texture.x));
	COLOR = main_texture;
}
