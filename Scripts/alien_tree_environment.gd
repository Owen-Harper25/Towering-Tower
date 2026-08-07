class_name AlienTreeEnvironment
extends Node2D

const CAPITAL_BOLD_FONT := preload("res://Assets/Capital Bold - Normal.ttf")

enum Context { HEADQUARTERS, EXPEDITION, ROOT_SIMULATION, CROWN_NEST }

var context: Context = Context.EXPEDITION
var branch_data: Dictionary = {}
var seed_value := 1
var far_parallax: Parallax2D
var near_parallax: Parallax2D
var far_shapes: Array[CanvasItem] = []
var near_shapes: Array[CanvasItem] = []

func configure(new_context: Context, new_branch_data: Dictionary = {}, new_seed: int = 1) -> void:
	context = new_context
	branch_data = new_branch_data
	seed_value = new_seed
	update_parallax_palette()
	queue_redraw()

func _ready() -> void:
	z_index = -20
	create_gameplay_parallax()
	queue_redraw()

func create_gameplay_parallax() -> void:
	far_parallax = Parallax2D.new()
	far_parallax.name = "FarSporesParallax"
	far_parallax.scroll_scale = Vector2(0.08, 0.08)
	far_parallax.repeat_size = Vector2(480.0, 270.0)
	far_parallax.repeat_times = 3
	far_parallax.autoscroll = Vector2(-1.2, 0.35)
	far_parallax.z_index = 1
	add_child(far_parallax)
	near_parallax = Parallax2D.new()
	near_parallax.name = "NearRootsParallax"
	near_parallax.scroll_scale = Vector2(0.32, 0.32)
	near_parallax.repeat_size = Vector2(480.0, 270.0)
	near_parallax.repeat_times = 3
	near_parallax.autoscroll = Vector2(0.55, -0.18)
	near_parallax.z_index = 2
	add_child(near_parallax)
	var random := RandomNumberGenerator.new()
	random.seed = 71027
	for spore_index in range(30):
		var spore := Polygon2D.new()
		var spore_size := random.randf_range(0.65, 1.8)
		spore.position = Vector2(random.randf_range(0.0, 480.0), random.randf_range(0.0, 270.0))
		spore.polygon = PackedVector2Array([
			Vector2(0.0, -spore_size * 1.7), Vector2(spore_size, 0.0),
			Vector2(0.0, spore_size * 1.7), Vector2(-spore_size, 0.0),
		])
		spore.set_meta("palette_role", "accent")
		far_parallax.add_child(spore)
		far_shapes.append(spore)
	for root_index in range(7):
		var root_line := Line2D.new()
		var start_y := 34.0 + float(root_index) * 34.0
		var wave := -1.0 if root_index % 2 == 0 else 1.0
		root_line.points = PackedVector2Array([
			Vector2(-30.0, start_y), Vector2(120.0, start_y + wave * 16.0),
			Vector2(270.0, start_y - wave * 11.0), Vector2(510.0, start_y + wave * 21.0),
		])
		root_line.width = 2.0 + float(root_index % 3)
		root_line.set_meta("palette_role", "root")
		near_parallax.add_child(root_line)
		near_shapes.append(root_line)
	update_parallax_palette()

func update_parallax_palette() -> void:
	if not far_parallax or not near_parallax:
		return
	var color: Color = branch_data.get("color", Color("405b91"))
	var accent: Color = branch_data.get("accent", Color("8bd7ed"))
	far_parallax.visible = true
	near_parallax.visible = context != Context.HEADQUARTERS
	for shape in far_shapes:
		if is_instance_valid(shape):
			shape.modulate = Color(accent.r, accent.g, accent.b, 0.20 if context == Context.HEADQUARTERS else 0.34)
	for shape in near_shapes:
		if not is_instance_valid(shape):
			continue
		var line := shape as Line2D
		if line:
			line.default_color = Color(color.r, color.g, color.b, 0.16)

func _draw() -> void:
	var viewport_size := get_viewport_rect().size
	var dark: Color = branch_data.get("dark", Color("101425"))
	var color: Color = branch_data.get("color", Color("405b91"))
	var accent: Color = branch_data.get("accent", Color("8bd7ed"))
	draw_rect(Rect2(Vector2.ZERO, viewport_size), dark, true)
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.015, 0.025, 0.045, 0.42), true)
	if context == Context.HEADQUARTERS:
		draw_headquarters(viewport_size, color, accent)
	else:
		draw_tree_chamber(viewport_size, color, accent)

func draw_headquarters(viewport_size: Vector2, color: Color, accent: Color) -> void:
	for grid_x in range(0, int(viewport_size.x) + 32, 32):
		draw_line(Vector2(grid_x, 0), Vector2(grid_x, viewport_size.y), Color(0.15, 0.22, 0.27, 0.16), 1.0)
	for grid_y in range(0, int(viewport_size.y) + 32, 32):
		draw_line(Vector2(0, grid_y), Vector2(viewport_size.x, grid_y), Color(0.15, 0.22, 0.27, 0.16), 1.0)
	var center_x := viewport_size.x * 0.5
	draw_rect(Rect2(center_x - 90.0, 10.0, 180.0, 22.0), Color("182331"), true)
	draw_string(CAPITAL_BOLD_FONT, Vector2(center_x - 72.0, 26.0), "AGENCY FOR EXOTIC BIOLOGY", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, accent)
	for panel_index in range(4):
		var panel_position := Vector2(18.0 + float(panel_index % 2) * (viewport_size.x - 152.0), 46.0 + float(panel_index / 2) * 130.0)
		draw_rect(Rect2(panel_position, Vector2(116.0, 48.0)), Color("121c29"), true)
		draw_rect(Rect2(panel_position, Vector2(116.0, 48.0)), color.darkened(0.2), false, 2.0)
		draw_circle(panel_position + Vector2(16.0, 16.0), 4.0, accent)
		draw_line(panel_position + Vector2(28.0, 13.0), panel_position + Vector2(98.0, 13.0), accent.darkened(0.35), 2.0)

func draw_tree_chamber(viewport_size: Vector2, color: Color, accent: Color) -> void:
	var bounds: Rect2 = branch_data.get("arena_bounds", Rect2(viewport_size * 0.5 - Vector2(218.0, 116.0), Vector2(436.0, 232.0)))
	var center := bounds.get_center()
	var arena_radii := bounds.size * 0.5
	for ring_index in range(5, 0, -1):
		var ratio := float(ring_index) / 5.0
		draw_set_transform(center, 0.0, Vector2(arena_radii.x / arena_radii.y, 1.0))
		draw_circle(Vector2.ZERO, arena_radii.y * ratio, color.darkened(0.58 - ratio * 0.22), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for root_index in range(13):
		var angle := TAU * float(root_index) / 13.0 + float(seed_value % 7) * 0.07
		var inner := center + Vector2.from_angle(angle) * 68.0
		var outer := center + Vector2.from_angle(angle) * 215.0
		draw_line(inner, outer, color.darkened(0.28), 7.0 - float(root_index % 3))
		draw_line(inner, outer, color.lightened(0.08), 2.0)
	for crystal_index in range(9):
		var angle := TAU * float(crystal_index) / 9.0 + 0.21
		var position := center + Vector2.from_angle(angle) * Vector2(175.0, 86.0)
		var size := 3.0 + float(crystal_index % 3)
		draw_colored_polygon(PackedVector2Array([
			position + Vector2(0.0, -size * 1.8), position + Vector2(size, 0.0),
			position + Vector2(0.0, size * 1.5), position + Vector2(-size, 0.0)
		]), accent)
