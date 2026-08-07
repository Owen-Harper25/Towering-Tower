extends Area2D

@export var interact_name: String = ""
@export var is_interactable: bool = true
@onready var player = get_tree().get_root().find_child("Player", true, false)

var interact: Callable = func(): pass
var sprite: CanvasItem = null
var base_modulate := Color.WHITE

func _ready() -> void:
	sprite = get_parent().get_node_or_null("Sprite2D")

	if sprite == null:
		sprite = get_parent().get_node_or_null("AnimatedSprite2D")
	if sprite == null:
		for child in get_parent().get_children():
			if child is Sprite2D or child is AnimatedSprite2D or child is Polygon2D:
				sprite = child
				break
	if sprite:
		base_modulate = sprite.modulate

func set_highlighted(state: bool) -> void:
	if not sprite:
		return
	if sprite.material is ShaderMaterial:
		var shader_material := sprite.material as ShaderMaterial
		shader_material.set_shader_parameter("outline_enabled", state)
	else:
		sprite.modulate = Color("d8f8ff") if state else base_modulate
