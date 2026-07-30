extends Node2D

@onready var anim: AnimationPlayer = $"AnimationPlayer"

func _ready() -> void:
	var duration = anim.get_animation("idle").length
	anim.play("idle")
	anim.seek(randf_range(0, duration), true)
	anim.speed_scale = randf_range(0.9, 1.1)
