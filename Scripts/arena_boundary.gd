extends Node2D

@export var arena_bounds: Rect2 = Rect2(28, 30, 424, 220)
@export var segments: int = 48

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	var points := PackedVector2Array()
	var center := arena_bounds.get_center()
	var radii := arena_bounds.size * 0.5
	for index in range(segments):
		var angle: float = TAU * float(index) / float(segments)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	points.append(points[0])
	draw_colored_polygon(points, Color(0.25, 0.9, 1.0, 0.05))
	draw_polyline(points, Color(0.35, 0.95, 1.0, 0.8), 2.0, true)
