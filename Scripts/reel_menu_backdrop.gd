extends Control

const PARTICLE_COLORS: Array[Color] = [
	Color("f48fb1"), Color("80deea"), Color("b39ddb"), Color("ffe082"), Color("a5d6a7"),
]

var particle_data: Array[Vector4] = []
var elapsed := 0.0

func _ready() -> void:
	# Keep clicks from reaching lobby/debug controls while the menu is open.
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var particle_rng := RandomNumberGenerator.new()
	# A fixed seed keeps the menu composition stable, while independent random
	# coordinates prevent the arithmetic diagonal bands the old layout produced.
	particle_rng.seed = 0x746F776572
	for particle_index in range(24):
		var x := particle_rng.randf()
		var y := particle_rng.randf()
		var speed := particle_rng.randf_range(4.0, 17.0)
		var particle_size := particle_rng.randf_range(0.8, 1.9)
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
			fmod(particle.x * size.x + sin(elapsed * 0.7 + float(particle_index)) * 8.0 + size.x, size.x),
			fmod(particle.y * size.y - elapsed * particle.z + size.y * 4.0, size.y)
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
