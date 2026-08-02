extends CharacterBody2D

@export var max_health := 6
@export var speed := 125.0
@export var revive_duration := 2.4
@export var downed_duration := 10.0

const DANGER_RADIUS := 150.0
const REVIVE_APPROACH_RADIUS := 46.0
const ALLY_SPACING_RADIUS := 30.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var current_health := 6
var is_downed := false
var is_survival_ghost := false
var movement_direction := Vector2.ZERO
var direction_timer := 0.0
var downed_timer := 0.0
var revive_progress := 0.0
var arena_bounds := Rect2(40, 40, 820, 520)
var decision_direction := Vector2.ZERO

func _enter_tree() -> void:
	set_multiplayer_authority(1)

func _ready() -> void:
	add_to_group("survival_allies")
	add_to_group("survival_bots")
	current_health = max_health
	var configured_bounds: Variant = get_meta("survival_bounds", arena_bounds)
	if configured_bounds is Rect2:
		arena_bounds = configured_bounds

func _physics_process(delta: float) -> void:
	update_ghost_visibility()
	if not multiplayer.is_server():
		update_bot_animation()
		return
	if is_survival_ghost:
		handle_ghost_motion(delta)
		return
	if is_downed:
		handle_downed(delta)
		return
	direction_timer -= delta
	if direction_timer <= 0.0:
		choose_direction()
	movement_direction = movement_direction.lerp(decision_direction, minf(1.0, delta * 9.0)).normalized()
	velocity = movement_direction * speed
	move_and_slide()
	clamp_to_arena()
	update_bot_animation()

func choose_direction() -> void:
	direction_timer = randf_range(0.10, 0.18)
	var avoidance := Vector2.ZERO
	var highest_threat := 0.0
	for hazard in get_tree().get_nodes_in_group("survival_hazards"):
		var hazard_node := hazard as Node2D
		if not hazard_node:
			continue
		var relative_position := global_position - hazard_node.global_position
		var hazard_speed: float = float(hazard_node.get("speed"))
		var hazard_velocity := Vector2.RIGHT.rotated(hazard_node.global_rotation) * hazard_speed
		var time_to_closest := clampf(relative_position.dot(hazard_velocity) / maxf(1.0, hazard_velocity.length_squared()), 0.0, 0.75)
		var future_offset := relative_position - hazard_velocity * time_to_closest
		var future_distance := future_offset.length()
		if future_distance >= DANGER_RADIUS:
			continue
		var threat := (1.0 - future_distance / DANGER_RADIUS) * (1.0 + (0.75 - time_to_closest))
		highest_threat = maxf(highest_threat, threat)
		var side_step := hazard_velocity.normalized().orthogonal()
		if side_step.dot(relative_position) < 0.0:
			side_step = -side_step
		avoidance += (future_offset.normalized() * 0.35 + side_step * 0.9) * threat

	var objective := choose_team_objective()
	var spacing := get_ally_spacing_direction()
	var center_pull := get_safe_center_pull()
	if highest_threat > 0.35:
		decision_direction = (avoidance * 1.8 + center_pull * 0.45 + spacing * 0.25).normalized()
	else:
		decision_direction = (objective + center_pull * 0.65 + spacing * 0.55).normalized()
	if decision_direction == Vector2.ZERO:
		decision_direction = Vector2.from_angle(randf_range(0.0, TAU))

func choose_team_objective() -> Vector2:
	var closest_downed: Node2D
	var closest_distance := INF
	for ally in get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("survival_allies"):
		var ally_node := ally as Node2D
		if not ally_node or ally_node == self or not bool(ally_node.get("is_downed")):
			continue
		var distance := global_position.distance_to(ally_node.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_downed = ally_node
	if closest_downed and closest_distance > REVIVE_APPROACH_RADIUS:
		return global_position.direction_to(closest_downed.global_position) * 1.25
	if closest_downed:
		return Vector2.ZERO
	var orbit_direction := global_position.direction_to(arena_bounds.get_center()).orthogonal()
	if str(name).hash() % 2 == 0:
		orbit_direction = -orbit_direction
	return orbit_direction * 0.55

func get_ally_spacing_direction() -> Vector2:
	var spacing := Vector2.ZERO
	for ally in get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("survival_allies"):
		var ally_node := ally as Node2D
		if not ally_node or ally_node == self:
			continue
		var offset := global_position - ally_node.global_position
		var distance := offset.length()
		if distance > 0.01 and distance < ALLY_SPACING_RADIUS:
			spacing += offset.normalized() * (1.0 - distance / ALLY_SPACING_RADIUS)
	return spacing

func get_safe_center_pull() -> Vector2:
	var inset_bounds := arena_bounds.grow(-54.0)
	if inset_bounds.has_point(global_position):
		return global_position.direction_to(arena_bounds.get_center()) * 0.08
	return global_position.direction_to(arena_bounds.get_center()) * 1.5

func handle_downed(delta: float) -> void:
	velocity = Vector2.ZERO
	downed_timer -= delta
	if has_nearby_helper():
		revive_progress += delta
	else:
		revive_progress = maxf(0.0, revive_progress - delta * 0.55)
	if revive_progress >= revive_duration:
		rpc("revive_bot_rpc")
	elif downed_timer <= 0.0:
		rpc("ghost_bot_rpc")

func handle_ghost_motion(delta: float) -> void:
	direction_timer -= delta
	if direction_timer <= 0.0:
		choose_direction()
	velocity = movement_direction * speed * 0.65
	global_position += velocity * delta
	clamp_to_arena()
	update_bot_animation()

func has_nearby_helper() -> bool:
	for ally in get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("survival_allies"):
		var ally_node := ally as Node2D
		if not ally_node or ally_node == self:
			continue
		if bool(ally_node.get("is_downed")) or bool(ally_node.get("is_survival_ghost")):
			continue
		if global_position.distance_to(ally_node.global_position) <= 52.0:
			return true
	return false

func take_damage(amount: int) -> void:
	if not multiplayer.is_server() or is_downed or is_survival_ghost:
		return
	current_health = maxi(0, current_health - amount)
	rpc("flash_bot_rpc")
	if current_health <= 0:
		rpc("down_bot_rpc")

@rpc("authority", "call_local", "reliable")
func down_bot_rpc() -> void:
	is_downed = true
	downed_timer = downed_duration
	revive_progress = 0.0
	velocity = Vector2.ZERO
	sprite.modulate = Color(1.0, 0.45, 0.22, 0.72)
	sprite.rotation = PI * 0.5
	if sprite.sprite_frames.has_animation("downed"):
		sprite.play("downed")

@rpc("authority", "call_local", "reliable")
func revive_bot_rpc() -> void:
	is_downed = false
	current_health = 3
	downed_timer = 0.0
	revive_progress = 0.0
	sprite.modulate = Color(0.45, 0.95, 1.0, 1.0)
	sprite.rotation = 0.0
	if sprite.sprite_frames.has_animation("Idle"):
		sprite.play("Idle")

@rpc("authority", "call_local", "reliable")
func ghost_bot_rpc() -> void:
	is_downed = false
	is_survival_ghost = true
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	sprite.modulate = Color(0.65, 0.85, 1.0, 0.24)
	sprite.rotation = 0.0
	update_ghost_visibility()

@rpc("authority", "call_local", "unreliable")
func flash_bot_rpc() -> void:
	var original_color := sprite.modulate
	sprite.modulate = Color.WHITE
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", original_color, 0.10)

func clamp_to_arena() -> void:
	global_position.x = clampf(global_position.x, arena_bounds.position.x, arena_bounds.end.x)
	global_position.y = clampf(global_position.y, arena_bounds.position.y, arena_bounds.end.y)

func update_bot_animation() -> void:
	if is_downed or is_survival_ghost:
		return
	if velocity.length_squared() > 16.0 and sprite.sprite_frames.has_animation("move"):
		sprite.play("move")
		sprite.flip_h = velocity.x < 0.0
	elif sprite.sprite_frames.has_animation("Idle"):
		sprite.play("Idle")

func update_ghost_visibility() -> void:
	if not sprite:
		return
	if not is_survival_ghost:
		sprite.visible = true
		return
	sprite.visible = local_survival_player_is_ghost()

func local_survival_player_is_ghost() -> bool:
	for player_node in get_tree().get_nodes_in_group("players"):
		var player := player_node as CharacterBody2D
		if player and player.is_multiplayer_authority():
			return bool(player.get("is_survival_ghost"))
	return false
