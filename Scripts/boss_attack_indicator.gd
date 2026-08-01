extends Node2D

enum IndicatorType { DASH, RING, GATLING }

var indicator_type := IndicatorType.DASH
var indicator_length := 120.0
var indicator_radius := 48.0
var indicator_width := 26.0
var lifetime := 0.65
var elapsed := 0.0

func configure(new_type: int, new_length: float, new_radius: float, new_width: float, new_lifetime: float) -> void:
	indicator_type = new_type
	indicator_length = new_length
	indicator_radius = new_radius
	indicator_width = new_width
	lifetime = new_lifetime

func _ready() -> void:
	z_index = -1
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.88, minf(0.12, lifetime * 0.25))
	tween.tween_interval(maxf(0.0, lifetime - 0.20))
	tween.tween_property(self, "modulate:a", 0.0, 0.08)
	tween.tween_callback(queue_free)

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	var pulse := 0.72 + sin(elapsed * 15.0) * 0.22
	var fill := Color(1.0, 0.78, 0.12, 0.12 * pulse)
	var edge := Color(1.0, 0.87, 0.26, 0.90)
	match indicator_type:
		IndicatorType.DASH:
			draw_rect(Rect2(0.0, -indicator_width * 0.5, indicator_length, indicator_width), fill, true)
			draw_rect(Rect2(0.0, -indicator_width * 0.5, indicator_length, indicator_width), edge, false, 1.5)
			draw_line(Vector2.ZERO, Vector2(indicator_length, 0.0), edge, 1.0)
		IndicatorType.RING:
			draw_circle(Vector2.ZERO, indicator_radius, fill)
			draw_arc(Vector2.ZERO, indicator_radius, 0.0, TAU, 48, edge, 1.5)
		IndicatorType.GATLING:
			draw_rect(Rect2(0.0, -indicator_width * 0.5, indicator_length, indicator_width), fill, true)
			draw_line(Vector2.ZERO, Vector2(indicator_length, 0.0), edge, 2.0)
