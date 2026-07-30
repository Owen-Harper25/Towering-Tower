shader_type canvas_item;

uniform float iris_radius : hint_range(0.0, 2.0) = 2.0;
uniform vec4 transition_color : source_color = vec4(0.025, 0.04, 0.09, 1.0);

void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	centered_uv.x *= 1.7777778;
	float edge = smoothstep(iris_radius - 0.035, iris_radius + 0.035, length(centered_uv));
	COLOR = vec4(transition_color.rgb, edge * transition_color.a);
}
