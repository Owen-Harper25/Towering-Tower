extends CharacterBody2D

const SURVIVAL_TEAM_MATERIAL := preload("res://Shaders/outlineshader.tres")

@export var max_health := 6
@export var speed := 125.0
@export var revive_duration := 2.4
@export var downed_duration := 10.0
@export var emergency_dash_speed_multiplier := 2.55
@export var emergency_dash_duration := 0.24
@export var emergency_dash_cooldown_min := 1.8
@export var emergency_dash_cooldown_max := 2.8

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
var arena_bounds := Rect2(170, 20, 560, 560)
var decision_direction := Vector2.ZERO
var survival_team_id := -1
var survival_team_size := 1
var survival_team_color := Color.WHITE
var emergency_dash_remaining := 0.0
var emergency_dash_cooldown := 0.0
var emergency_dash_direction := Vector2.ZERO

func _enter_tree() -> void:
	set_multiplayer_authority(1)

func _ready() -> void:
	add_to_group("survival_allies")
	add_to_group("survival_bots")
	current_health = max_health
	var configured_bounds: Variant = get_meta("survival_bounds", arena_bounds)
	if configured_bounds is Rect2:
		arena_bounds = configured_bounds
	sprite.material = SURVIVAL_TEAM_MATERIAL.duplicate()
	apply_team_visuals()

func configure_team(team_id: int, team_size: int, team_color: Color) -> void:
	survival_team_id = team_id
	survival_team_size = team_size
	survival_team_color = team_color
	if is_node_ready():
		apply_team_visuals()

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
	emergency_dash_cooldown = maxf(0.0, emergency_dash_cooldown - delta)
	if emergency_dash_remaining > 0.0:
		emergency_dash_remaining -= delta
		velocity = emergency_dash_direction * speed * emergency_dash_speed_multiplier
		move_and_slide()
		clamp_to_arena()
		update_bot_animation()
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
	if highest_threat > 0.92 and emergency_dash_cooldown <= 0.0:
		begin_emergency_dash((avoidance * 1.4 + center_pull * 0.75).normalized())
		return
	if highest_threat > 0.35:
		decision_direction = (avoidance * 1.65 + center_pull * 0.85 + spacing * 0.25).normalized()
	else:
		decision_direction = (objective + center_pull * 1.05 + spacing * 0.55).normalized()
	if decision_direction == Vector2.ZERO:
		decision_direction = Vector2.from_angle(randf_range(0.0, TAU))

func begin_emergency_dash(dash_direction: Vector2) -> void:
	if dash_direction == Vector2.ZERO:
		dash_direction = global_position.direction_to(arena_bounds.get_center())
	emergency_dash_direction = dash_direction.normalized()
	emergency_dash_remaining = emergency_dash_duration
	emergency_dash_cooldown = randf_range(emergency_dash_cooldown_min, emergency_dash_cooldown_max)
	movement_direction = emergency_dash_direction
	decision_direction = emergency_dash_direction
	rpc("play_emergency_dash_rpc", emergency_dash_direction)

@rpc("authority", "call_local", "reliable")
func play_emergency_dash_rpc(dash_direction: Vector2) -> void:
	if not sprite:
		return
	emergency_dash_remaining = emergency_dash_duration
	sprite.flip_h = dash_direction.x < 0.0
	sprite.scale = Vector2(1.38, 0.68)
	var dash_tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	dash_tween.tween_property(sprite, "scale", Vector2.ONE, emergency_dash_duration)

func is_dodging_bullets() -> bool:
	return emergency_dash_remaining > 0.0

func choose_team_objective() -> Vector2:
	var closest_downed: Node2D
	var closest_distance := INF
	for ally in get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("survival_allies"):
		var ally_node := ally as Node2D
		if not ally_node or ally_node == self or not bool(ally_node.get("is_downed")):
			continue
		if survival_team_size <= 1 or int(ally_node.get("survival_team_id")) != survival_team_id:
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
	var arena_center := arena_bounds.get_center()
	var arena_radius := minf(arena_bounds.size.x, arena_bounds.size.y) * 0.5
	var distance_ratio := global_position.distance_to(arena_center) / maxf(1.0, arena_radius)
	if distance_ratio < 0.48:
		return global_position.direction_to(arena_center) * 0.12
	var pull_strength := remap(clampf(distance_ratio, 0.48, 1.0), 0.48, 1.0, 0.38, 2.35)
	return global_position.direction_to(arena_center) * pull_strength

func handle_downed(delta: float) -> void:
	velocity = Vector2.ZERO
	downed_timer -= delta
	if survival_team_size > 1 and has_nearby_helper():
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
		if survival_team_size <= 1 or int(ally_node.get("survival_team_id")) != survival_team_id:
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
func receive_boss_bash_rpc(damage: int, knockback: Vector2) -> void:
	take_damage(damage)
	if not is_downed:
		velocity += knockback

@rpc("authority", "call_local", "reliable")
func down_bot_rpc() -> void:
	is_downed = true
	downed_timer = downed_duration
	revive_progress = 0.0
	velocity = Vector2.ZERO
	sprite.modulate = get_team_display_color().lerp(Color(1.0, 0.35, 0.16, 0.78), 0.52)
	sprite.rotation = PI * 0.5
	if sprite.sprite_frames.has_animation("downed"):
		sprite.play("downed")

@rpc("authority", "call_local", "reliable")
func revive_bot_rpc() -> void:
	is_downed = false
	current_health = 3
	downed_timer = 0.0
	revive_progress = 0.0
	sprite.modulate = get_team_display_color()
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
	sprite.modulate = Color(survival_team_color.r, survival_team_color.g, survival_team_color.b, 0.24)
	sprite.rotation = 0.0
	update_ghost_visibility()

@rpc("authority", "call_local", "unreliable")
func flash_bot_rpc() -> void:
	var original_color := sprite.modulate
	sprite.modulate = Color.WHITE
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", original_color, 0.10)

func clamp_to_arena() -> void:
	var arena_center := arena_bounds.get_center()
	var playable_radius := minf(arena_bounds.size.x, arena_bounds.size.y) * 0.5 - 10.0
	var center_offset := global_position - arena_center
	if center_offset.length_squared() > playable_radius * playable_radius:
		global_position = arena_center + center_offset.normalized() * playable_radius

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
	else:
		sprite.visible = local_survival_player_is_ghost()
	set_team_outline(sprite.visible and local_survival_player_is_teammate())

func local_survival_player_is_ghost() -> bool:
	for player_node in get_tree().get_nodes_in_group("players"):
		var player := player_node as CharacterBody2D
		if player and player.is_multiplayer_authority():
			return bool(player.get("is_survival_ghost"))
	return false

func local_survival_player_is_teammate() -> bool:
	if survival_team_size <= 1:
		return false
	for player_node in get_tree().get_nodes_in_group("players"):
		var player := player_node as CharacterBody2D
		if player and player.is_multiplayer_authority():
			return int(player.get("survival_team_id")) == survival_team_id
	return false

func apply_team_visuals() -> void:
	if not sprite:
		return
	sprite.modulate = get_team_display_color()
	set_team_outline(local_survival_player_is_teammate())

func set_team_outline(outline_visible: bool) -> void:
	if not sprite or not (sprite.material is ShaderMaterial):
		return
	var team_material := sprite.material as ShaderMaterial
	team_material.set_shader_parameter("outline_enabled", outline_visible)
	team_material.set_shader_parameter("outline_colour", survival_team_color.lightened(0.35))
	team_material.set_shader_parameter("outline_thickness", 2.0)

func get_team_display_color() -> Color:
	return Color(
		lerpf(survival_team_color.r, 1.0, 0.32),
		lerpf(survival_team_color.g, 1.0, 0.32),
		lerpf(survival_team_color.b, 1.0, 0.32),
		1.0
	)
