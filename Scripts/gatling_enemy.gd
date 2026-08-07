extends "res://Scripts/standard_bullet_enemy.gd"

@export var burst_rounds := 8
@export var burst_interval := 0.075
@export var gatling_spread := 0.085

func _on_shoot_timer_timeout() -> void:
	if not is_multiplayer_authority() or is_dying or not target_player or not is_instance_valid(target_player):
		return
	for round_index in range(burst_rounds):
		get_tree().create_timer(float(round_index) * burst_interval, false).timeout.connect(fire_gatling_round)

func fire_gatling_round() -> void:
	if is_dying or not target_player or not is_instance_valid(target_player):
		return
	var angle := global_position.direction_to(target_player.global_position).angle() + randf_range(-gatling_spread, gatling_spread)
	rpc("spawn_enemy_bullet_rpc", global_position, angle)
