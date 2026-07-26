extends Area2D
@onready var audio_stream_player_2d: AudioStreamPlayer2D = $AudioStreamPlayer2D

func _on_body_entered(body: Node2D) -> void:
	if body.name == "Player":
		audio_stream_player_2d.play()
		body.get_parent().coin_count += 1
		body.get_parent().coin_count_changed()
		await get_tree().create_timer(0.3).timeout
		queue_free()
