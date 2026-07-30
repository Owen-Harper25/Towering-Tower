extends Area2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var bite_1: AudioStreamPlayer2D = $Bite1
@onready var bite_2: AudioStreamPlayer2D = $Bite2
var collected = false

var bite_sounds = []

func _ready() -> void:
	bite_sounds = [bite_1, bite_2]

func _on_body_entered(body: Node2D) -> void:
	if body.name == "Player" and not collected:
		collected = true
		animation_player.play("Collected")
		play_random_bite()
		body.get_parent().apple_count_changed()
		await get_tree().create_timer(0.3).timeout
		queue_free()

func play_random_bite():
	var random_sound = bite_sounds[randi() % bite_sounds.size()]
	random_sound.play()
