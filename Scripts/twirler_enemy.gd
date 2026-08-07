extends "res://Scripts/standard_bullet_enemy.gd"

@export var spiral_arms := 5
@export var spiral_step := 0.43
@export var alternating_offset := 0.18

var spiral_rotation := 0.0
var volley_index := 0

func _on_shoot_timer_timeout() -> void:
	if not is_multiplayer_authority() or is_dying:
		return
	spiral_rotation += spiral_step
	volley_index += 1
	for arm_index in range(spiral_arms):
		var angle := spiral_rotation + TAU * float(arm_index) / float(maxi(1, spiral_arms))
		rpc("spawn_enemy_bullet_rpc", global_position, angle)
		if volley_index % 2 == 0:
			rpc("spawn_enemy_bullet_rpc", global_position, angle + alternating_offset)
