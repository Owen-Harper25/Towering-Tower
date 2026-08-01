shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	centered_uv.x *= 1.7777778;
	float iris = smoothstep(0.22, 0.82, length(centered_uv));
	float pulse = 0.86 + sin(TIME * 5.5) * 0.14;
	float alpha = iris * intensity * 0.56 * pulse;
	COLOR = vec4(0.28, 0.015, 0.025, alpha);
}
