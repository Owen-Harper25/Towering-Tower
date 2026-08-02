shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float speed : hint_range(0.0, 2.0) = 0.55;

void fragment() {
	vec2 uv = UV;
	float travel = fract(TIME * speed);
	float diagonal = uv.x * 0.72 + uv.y * 0.28;
	float band = 1.0 - smoothstep(0.0, 0.16, abs(diagonal - travel));
	vec3 rainbow = 0.58 + 0.42 * cos(6.28318 * (diagonal + TIME * 0.10 + vec3(0.0, 0.33, 0.67)));
	float grain = sin((uv.x + uv.y) * 72.0 + TIME * 2.0) * 0.04;
	COLOR = vec4(rainbow + grain, band * 0.26 * intensity);
}
