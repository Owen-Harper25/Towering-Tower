extends CharacterBody2D

@export var max_health := 6
@export var speed := 125.0
@export var revive_duration := 2.4
@export var downed_duration := 10.0

@onready var sprite: Sprite2D = $Sprite2D

var current_health := 6
var is_downed := false
var is_survival_ghost := false
var movement_direction := Vector2.ZERO
var direction_timer := 0.0
var downed_timer := 0.0
var revive_progress := 0.0
var arena_bounds := Rect2(40, 40, 820, 520)

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
	if not multiplayer.is_server():
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
	var center_pull := (arena_bounds.get_center() - global_position).normalized()
	var normalized_offset := (global_position - arena_bounds.get_center()) / (arena_bounds.size * 0.5)
	if normalized_offset.length_squared() > 0.72:
		movement_direction = movement_direction.lerp(center_pull, 0.12).normalized()
	velocity = movement_direction * speed
	move_and_slide()
	clamp_to_arena()

func choose_direction() -> void:
	direction_timer = randf_range(0.55, 1.3)
	var danger_direction := Vector2.ZERO
	var closest_distance := INF
	for hazard in get_tree().get_nodes_in_group("survival_hazards"):
		var hazard_node := hazard as Node2D
		if not hazard_node:
			continue
		var distance := global_position.distance_to(hazard_node.global_position)
		if distance < closest_distance:
			closest_distance = distance
			danger_direction = (global_position - hazard_node.global_position).normalized()
	if closest_distance < 105.0:
		movement_direction = danger_direction.rotated(randf_range(-0.45, 0.45)).normalized()
	else:
		movement_direction = Vector2.from_angle(randf_range(0.0, TAU))

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

@rpc("authority", "call_local", "reliable")
func revive_bot_rpc() -> void:
	is_downed = false
	current_health = 3
	downed_timer = 0.0
	revive_progress = 0.0
	sprite.modulate = Color(0.45, 0.95, 1.0, 1.0)
	sprite.rotation = 0.0

@rpc("authority", "call_local", "reliable")
func ghost_bot_rpc() -> void:
	is_downed = false
	is_survival_ghost = true
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	sprite.modulate = Color(0.65, 0.85, 1.0, 0.24)
	sprite.rotation = 0.0

@rpc("authority", "call_local", "unreliable")
func flash_bot_rpc() -> void:
	var original_color := sprite.modulate
	sprite.modulate = Color.WHITE
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", original_color, 0.10)

func clamp_to_arena() -> void:
	global_position.x = clampf(global_position.x, arena_bounds.position.x, arena_bounds.end.x)
	global_position.y = clampf(global_position.y, arena_bounds.position.y, arena_bounds.end.y)
