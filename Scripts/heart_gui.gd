extends TextureRect

@export var full_texture: Texture2D
@export var half_texture: Texture2D
@export var empty_texture: Texture2D

enum HeartState { FULL, HALF, EMPTY }

var current_state: HeartState = HeartState.FULL

func set_heart_state(new_state: HeartState) -> void:
	# If state hasn't changed, do nothing
	if current_state == new_state and texture != null:
		return

	current_state = new_state

	# Apply new texture based on state
	match current_state:
		HeartState.FULL:
			texture = full_texture
		HeartState.HALF:
			texture = half_texture
		HeartState.EMPTY:
			texture = empty_texture

	# Play Gungeon-style damage feedback
	play_hit_animations()

func play_hit_animations() -> void:
	# Reset pivot offset to center so scale tween grows from the middle of the heart
	pivot_offset = size / 2.0

	# 1. Scale Pulse Tween (Pops up to 1.3x and snaps back down)
	var scale_tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(self, "scale", Vector2(1.35, 1.35), 0.08)
	scale_tween.tween_property(self, "scale", Vector2.ONE, 0.12)

	# 2. Flash Red Effect (Flashes crimson red and restores to normal)
	var flash_tween := create_tween()
	flash_tween.tween_property(self, "modulate", Color(2.5, 0.3, 0.3, 1.0), 0.05) # Bright red highlight
	flash_tween.tween_property(self, "modulate", Color.WHITE, 0.15)
