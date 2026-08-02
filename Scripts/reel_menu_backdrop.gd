extends Control

const PARTICLE_COLORS: Array[Color] = [
	Color("f48fb1"), Color("80deea"), Color("b39ddb"), Color("ffe082"), Color("a5d6a7"),
]

var particle_data: Array[Vector4] = []
var elapsed := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for particle_index in range(24):
		var x := fmod(float(particle_index * 83 + 29), 480.0)
		var y := fmod(float(particle_index * 47 + 17), 270.0)
		var speed := 4.0 + float((particle_index * 7) % 13)
		var particle_size := 0.8 + float(particle_index % 3) * 0.55
		particle_data.append(Vector4(x, y, speed, particle_size))

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("080d12"))
	var tile_size := 18.0
	var columns := ceili(size.x / tile_size)
	var rows := ceili(size.y / tile_size)
	for row in range(rows):
		for column in range(columns):
			if (row + column) % 2 == 0:
				draw_rect(Rect2(Vector2(column, row) * tile_size, Vector2.ONE * tile_size), Color(0.055, 0.075, 0.09, 0.32))
	for particle_index in range(particle_data.size()):
		var particle := particle_data[particle_index]
		var particle_position := Vector2(
			fmod(particle.x + sin(elapsed * 0.7 + float(particle_index)) * 8.0 + size.x, size.x),
			fmod(particle.y - elapsed * particle.z + size.y * 4.0, size.y)
		)
		var pulse := 0.42 + sin(elapsed * 2.0 + float(particle_index) * 0.8) * 0.16
		var color := PARTICLE_COLORS[particle_index % PARTICLE_COLORS.size()]
		color.a = pulse
		var radius := particle.w
		var diamond := PackedVector2Array([
			particle_position + Vector2(0.0, -radius),
			particle_position + Vector2(radius, 0.0),
			particle_position + Vector2(0.0, radius),
			particle_position + Vector2(-radius, 0.0),
		])
		draw_colored_polygon(diamond, color)
