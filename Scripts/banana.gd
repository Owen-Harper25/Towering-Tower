extends Area2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var bite_1: AudioStreamPlayer2D = $Bite1
@onready var bite_2: AudioStreamPlayer2D = $Bite2
@onready var sprite_2d_2: Sprite2D = $Sprite2D2
var collected = false

var bite_sounds = []

func _ready() -> void:
	bite_sounds = [bite_1, bite_2]
	sprite_2d_2.visible = false

func _on_body_entered(body: Node2D) -> void:
	if body.name == "Player" and not collected:
		collected = true
		animation_player.play("collected")
		play_random_bite()
		print(body.get_parent().banana_count)
		body.get_parent().banana_count_changed()
		await get_tree().create_timer(0.3).timeout
		queue_free()

func play_random_bite():
	var random_sound = bite_sounds[randi() % bite_sounds.size()]
	random_sound.play()
