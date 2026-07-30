extends ColorRect

var mask : Image
var mask_tex : ImageTexture
var footprint_brush : Image

@onready var player = get_parent().get_node("Player")

var last_footprint_pos : Vector2 = Vector2.ZERO
@export var step_distance : float = 5
@export var fade_speed : float = 7

func _ready() -> void:
	mask = Image.create(int(size.x), int(size.y), false, Image.FORMAT_RGBA8)
	mask.fill(Color(0.0, 0.0, 0.0, 1.0))
	
	mask_tex = ImageTexture.create_from_image(mask)
	material.set_shader_parameter("mask", mask_tex)
	
	footprint_brush = preload("res://Assets/plus particle.png").get_image()
	
	if player:
		last_footprint_pos = player.global_position

func _process(delta: float) -> void:
	var fade_overlay = Image.create(int(size.x), int(size.y), false, Image.FORMAT_RGBA8)
	fade_overlay.fill(Color(0.0, 0.0, 0.0, fade_speed * delta))
	mask.blend_rect(fade_overlay, Rect2i(0, 0, int(size.x), int(size.y)), Vector2i.ZERO)

	if player:
		var dist = player.global_position.distance_to(last_footprint_pos)
		
		if dist >= step_distance:
			draw_footprint()
			last_footprint_pos = player.global_position
			
	mask_tex.update(mask)

func draw_footprint():
	var local_pos = player.global_position - global_position
	
	local_pos.y += 7.0 
	
	var brush_size = Vector2(footprint_brush.get_size())
	var draw_pos = local_pos - (brush_size / 2.0)
	
	mask.blend_rect(footprint_brush, Rect2i(Vector2i.ZERO, footprint_brush.get_size()), Vector2i(draw_pos))
