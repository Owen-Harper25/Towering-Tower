extends Node2D

const BOT_SCENE := preload("res://Scenes/survival_bot.tscn")
const BULLET_SCENE := preload("res://Scenes/bullet.tscn")
const PARTICLE_TEXTURE := preload("res://Assets/plus particle.png")
const BOSS_DASH_SFX := preload("res://SFX/flap.mp3")
const BOSS_LAND_SFX := preload("res://SFX/kick.wav")
const BOSS_SCENES: Array[PackedScene] = [
	preload("res://Scenes/popcorn_boss_butterstorm.tscn"),
	preload("res://Scenes/popcorn_boss_flame.tscn"),
	preload("res://Scenes/popcorn_boss_magnetron.tscn"),
	preload("res://Scenes/popcorn_boss_helix.tscn"),
]

@export var arena_bounds := Rect2(170, 20, 560, 560)
@export var target_participant_count := 20
@export var boss_duration := 30.0
@export var intermission_duration := 5.0

@onready var bots: Node2D = $Bots
@onready var projectiles: Node2D = $Projectiles

var boss_visual: Node2D
var boss_label: Label
var boss_timer_label: Label
var participant_label: Label
var boss_bar_fill: ColorRect
var boss_index := 0
var boss_time_remaining := 0.0
var intermission_remaining := 0.0
var boss_active := false
var attack_timer := 0.0
var attack_rotation := 0.0
var bot_sync_elapsed := 0.0
var mode_sync_elapsed := 0.0
var next_bot_id := 1
var survival_team_size := 1
var survival_team_colors: Array[Color] = []
var initial_human_count := 1
var boss_position := Vector2.ZERO
var boss_network_position := Vector2.ZERO
var boss_move_target := Vector2.ZERO
var boss_move_timer := 0.0
var boss_dash_cooldown := 0.0
var boss_dash_pending := false
var boss_intro_remaining := 0.0

func _ready() -> void:
	add_to_group("survival_arena")
	create_boss_visual()
	create_mode_ui()
	queue_redraw()
	if multiplayer.is_server():
		get_tree().create_timer(0.75).timeout.connect(start_server_mode)

func can_players_join() -> bool:
	return false

func is_wave_active() -> bool:
	return false

func start_server_mode() -> void:
	if not is_inside_tree():
		return
	initial_human_count = maxi(1, get_human_players().size())
	survival_team_size = initial_human_count if initial_human_count > 1 else 1
	create_team_colors(ceili(float(target_participant_count) / float(survival_team_size)))
	rpc("configure_human_players_rpc", arena_bounds, survival_team_size, survival_team_colors[0])
	spawn_missing_bots()
	intermission_remaining = 2.5
	rpc("show_intermission_rpc", intermission_remaining, boss_index + 1)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		interpolate_remote_bots(delta)
		if boss_intro_remaining > 0.0:
			boss_intro_remaining -= delta
		else:
			interpolate_remote_boss(delta)
		return
	bot_sync_elapsed += delta
	if bot_sync_elapsed >= 0.08:
		bot_sync_elapsed = 0.0
		rpc("sync_bot_states_rpc", build_bot_states())
	mode_sync_elapsed += delta
	if boss_active:
		if boss_intro_remaining > 0.0:
			boss_intro_remaining -= delta
			if boss_intro_remaining <= 0.0:
				rpc("play_boss_landing_rpc", boss_position, get_boss_color(boss_index))
		else:
			update_boss_movement(delta)
			boss_time_remaining -= delta
			attack_timer -= delta
			if attack_timer <= 0.0:
				perform_boss_attack()
			if boss_time_remaining <= 0.0:
				finish_current_boss()
	elif intermission_remaining > 0.0:
		intermission_remaining -= delta
		if intermission_remaining <= 0.0:
			start_next_boss()
	if mode_sync_elapsed >= 0.12:
		mode_sync_elapsed = 0.0
		rpc("sync_mode_ui_rpc", boss_index, boss_time_remaining, boss_active, intermission_remaining, boss_position)

func start_next_boss() -> void:
	boss_index += 1
	boss_active = true
	boss_time_remaining = boss_duration + minf(float(boss_index - 1) * 2.0, 12.0)
	attack_timer = maxf(0.45, 1.15 / get_boss_aggression())
	attack_rotation = randf_range(0.0, TAU)
	boss_position = arena_bounds.get_center()
	boss_network_position = boss_position
	boss_move_target = random_boss_position()
	boss_move_timer = 0.5
	boss_dash_cooldown = maxf(1.8, 5.2 / get_boss_aggression())
	boss_dash_pending = false
	boss_intro_remaining = 0.82
	rpc("start_boss_rpc", boss_index, boss_time_remaining)

func finish_current_boss() -> void:
	boss_active = false
	boss_time_remaining = 0.0
	intermission_remaining = intermission_duration
	var reward := 1 + floori(float(boss_index - 1) / 3.0)
	rpc("finish_boss_rpc", boss_index, reward, intermission_remaining)

func perform_boss_attack() -> void:
	var boss_type := (boss_index - 1) % BOSS_SCENES.size()
	var difficulty_speed := get_boss_aggression()
	var attack_variant := randi_range(0, 2)
	match boss_type:
		0:
			attack_timer = maxf(0.38, 1.35 / difficulty_speed)
			if attack_variant == 0: fire_butter_ring(difficulty_speed)
			elif attack_variant == 1: fire_spiral_burst(difficulty_speed)
			else: fire_targeted_fans(difficulty_speed, Color(1.0, 0.82, 0.18))
		1:
			attack_timer = maxf(0.48, 1.48 / difficulty_speed)
			if attack_variant == 0: fire_flame_wall(difficulty_speed)
			elif attack_variant == 1: fire_vertical_flame_wall(difficulty_speed)
			else: fire_corner_crossfire(difficulty_speed)
		2:
			attack_timer = maxf(0.28, 0.82 / difficulty_speed)
			if attack_variant == 0: fire_magnetron_volley(difficulty_speed)
			elif attack_variant == 1: fire_rotating_spokes(difficulty_speed)
			else: fire_targeted_fans(difficulty_speed, Color(0.78, 0.32, 1.0))
		3:
			attack_timer = maxf(0.30, 0.92 / difficulty_speed)
			if attack_variant == 0: fire_dna_helix(difficulty_speed)
			elif attack_variant == 1: fire_concentric_circles(difficulty_speed)
			else: fire_rotating_spokes(difficulty_speed)

func fire_butter_ring(difficulty_speed: float) -> void:
	var projectile_count := mini(30, 16 + boss_index)
	attack_rotation += 0.19
	for index in range(projectile_count):
		var angle := attack_rotation + TAU * float(index) / float(projectile_count)
		rpc("spawn_survival_bullet_rpc", boss_position, angle, 130.0 * difficulty_speed, Color(1.0, 0.82, 0.18))
	rpc("play_boss_burst_rpc", boss_position, Color(1.0, 0.82, 0.18), 18)

func fire_flame_wall(difficulty_speed: float) -> void:
	var from_left := randi() % 2 == 0
	var columns := 12
	var gap_start := randi_range(2, columns - 4)
	for index in range(columns):
		if index == gap_start or index == gap_start + 1:
			continue
		var y := arena_bounds.position.y + 22.0 + float(index) * (arena_bounds.size.y - 44.0) / float(columns - 1)
		var spawn_position := Vector2(arena_bounds.position.x - 18.0 if from_left else arena_bounds.end.x + 18.0, y)
		var angle := 0.0 if from_left else PI
		rpc("spawn_survival_bullet_rpc", spawn_position, angle, 170.0 * difficulty_speed, Color(1.0, 0.22, 0.08))
	rpc("play_boss_burst_rpc", Vector2(arena_bounds.position.x if from_left else arena_bounds.end.x, arena_bounds.get_center().y), Color(1.0, 0.22, 0.08), 14)

func fire_magnetron_volley(difficulty_speed: float) -> void:
	var targets := get_active_participants()
	for target in targets:
		var direction := (target.global_position - boss_position).normalized()
		if direction == Vector2.ZERO:
			direction = Vector2.RIGHT
		var spread := randf_range(-0.11, 0.11)
		rpc("spawn_survival_bullet_rpc", boss_position, direction.angle() + spread, 178.0 * difficulty_speed, Color(0.78, 0.32, 1.0))
	attack_rotation += 0.43
	for spoke in range(3):
		rpc("spawn_survival_bullet_rpc", boss_position, attack_rotation + TAU * float(spoke) / 3.0, 122.0 * difficulty_speed, Color(0.42, 0.78, 1.0))
	rpc("play_boss_burst_rpc", boss_position, Color(0.72, 0.30, 1.0), 10)

func fire_spiral_burst(difficulty_speed: float) -> void:
	attack_rotation += 0.34
	for arm in range(4):
		for step in range(3):
			var angle := attack_rotation + TAU * float(arm) / 4.0 + float(step) * 0.12
			rpc("spawn_survival_bullet_rpc", boss_position, angle, (105.0 + float(step) * 24.0) * difficulty_speed, Color(1.0, 0.68, 0.12))
	rpc("play_boss_burst_rpc", boss_position, Color(1.0, 0.68, 0.12), 12)

func fire_targeted_fans(difficulty_speed: float, color: Color) -> void:
	for target in get_active_participants():
		var base_angle := boss_position.direction_to(target.global_position).angle()
		for fan_index in range(-1, 2):
			rpc("spawn_survival_bullet_rpc", boss_position, base_angle + float(fan_index) * 0.16, 150.0 * difficulty_speed, color)
	rpc("play_boss_burst_rpc", boss_position, color, 14)

func fire_vertical_flame_wall(difficulty_speed: float) -> void:
	var from_top := randi() % 2 == 0
	var columns := 16
	var gap_start := randi_range(2, columns - 4)
	for index in range(columns):
		if index == gap_start or index == gap_start + 1:
			continue
		var x := arena_bounds.position.x + 22.0 + float(index) * (arena_bounds.size.x - 44.0) / float(columns - 1)
		var spawn_position := Vector2(x, arena_bounds.position.y - 18.0 if from_top else arena_bounds.end.y + 18.0)
		var angle := PI * 0.5 if from_top else -PI * 0.5
		rpc("spawn_survival_bullet_rpc", spawn_position, angle, 145.0 * difficulty_speed, Color(1.0, 0.28, 0.08))

func fire_corner_crossfire(difficulty_speed: float) -> void:
	var corners: Array[Vector2] = [arena_bounds.position, Vector2(arena_bounds.end.x, arena_bounds.position.y), arena_bounds.end, Vector2(arena_bounds.position.x, arena_bounds.end.y)]
	for corner in corners:
		var base_angle := corner.direction_to(arena_bounds.get_center()).angle()
		for spread_index in range(-2, 3):
			rpc("spawn_survival_bullet_rpc", corner, base_angle + float(spread_index) * 0.12, 138.0 * difficulty_speed, Color(1.0, 0.22, 0.08))

func fire_rotating_spokes(difficulty_speed: float) -> void:
	attack_rotation += 0.29
	var spoke_count := mini(10, 5 + floori(float(boss_index) / 2.0))
	for spoke in range(spoke_count):
		var angle := attack_rotation + TAU * float(spoke) / float(spoke_count)
		rpc("spawn_survival_bullet_rpc", boss_position, angle, 116.0 * difficulty_speed, Color(0.42, 0.78, 1.0))
	rpc("play_boss_burst_rpc", boss_position, Color(0.42, 0.78, 1.0), spoke_count)

func fire_dna_helix(difficulty_speed: float) -> void:
	attack_rotation += 0.38
	for helix_step in range(7):
		var phase := attack_rotation + float(helix_step) * 0.22
		var radial_speed := (104.0 + float(helix_step) * 9.0) * difficulty_speed
		rpc("spawn_survival_bullet_rpc", boss_position, phase, radial_speed, Color(0.08, 0.96, 0.74))
		rpc("spawn_survival_bullet_rpc", boss_position, phase + PI, radial_speed, Color(1.0, 0.22, 0.70))
		if helix_step % 2 == 0:
			rpc("spawn_survival_bullet_rpc", boss_position, phase + PI * 0.5, radial_speed * 0.78, Color(0.72, 0.94, 1.0))
			rpc("spawn_survival_bullet_rpc", boss_position, phase - PI * 0.5, radial_speed * 0.78, Color(0.72, 0.94, 1.0))
	rpc("play_boss_burst_rpc", boss_position, Color(0.12, 0.95, 0.72), 18)

func fire_concentric_circles(difficulty_speed: float) -> void:
	attack_rotation += 0.17
	for ring_index in range(3):
		var projectile_count := 10 + ring_index * 4
		var ring_speed := (92.0 + float(ring_index) * 38.0) * difficulty_speed
		for bullet_index in range(projectile_count):
			var angle := attack_rotation * (1.0 if ring_index % 2 == 0 else -1.0) + TAU * float(bullet_index) / float(projectile_count)
			var color := Color(0.10, 0.92, 0.72) if ring_index % 2 == 0 else Color(1.0, 0.24, 0.72)
			rpc("spawn_survival_bullet_rpc", boss_position, angle, ring_speed, color)
	rpc("play_boss_burst_rpc", boss_position, Color(0.90, 0.34, 0.82), 22)

func get_active_participants() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for participant in get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("survival_bots"):
		var participant_node := participant as Node2D
		if not participant_node:
			continue
		if bool(participant_node.get("is_downed")) or bool(participant_node.get("is_survival_ghost")):
			continue
		result.append(participant_node)
	return result

func get_human_players() -> Array[CharacterBody2D]:
	var human_players: Array[CharacterBody2D] = []
	for candidate in get_tree().get_nodes_in_group("players"):
		var player := candidate as CharacterBody2D
		if player:
			human_players.append(player)
	return human_players

func spawn_missing_bots() -> void:
	var human_count := get_human_players().size()
	var bots_needed := maxi(0, target_participant_count - human_count)
	for index in range(bots_needed):
		var angle := TAU * float(index) / float(maxi(1, bots_needed))
		var spawn_position := arena_bounds.get_center() + Vector2.from_angle(angle) * randf_range(90.0, 190.0)
		var bot_id := "SurvivalBot_%d" % next_bot_id
		var team_id := floori(float(human_count + index) / float(survival_team_size))
		var team_color := survival_team_colors[mini(team_id, survival_team_colors.size() - 1)]
		next_bot_id += 1
		rpc("spawn_bot_rpc", bot_id, spawn_position, arena_bounds, team_id, survival_team_size, team_color)

func create_team_colors(team_count: int) -> void:
	var palette: Array[Color] = [
		Color("4fc3f7"), Color("ff6b6b"), Color("7ee081"), Color("c792ea"),
		Color("ffd166"), Color("ff8fab"), Color("64dfdf"), Color("f8961e"),
		Color("90be6d"), Color("b8c0ff"), Color("f15bb5"), Color("43aa8b"),
		Color("e9c46a"), Color("a8dadc"), Color("ff99c8"), Color("9b5de5"),
		Color("00bbf9"), Color("f9844a"), Color("80ed99"), Color("fee440")
	]
	palette.shuffle()
	survival_team_colors.clear()
	for index in range(team_count):
		survival_team_colors.append(palette[index % palette.size()])

@rpc("authority", "call_local", "reliable")
func spawn_bot_rpc(bot_id: String, spawn_position: Vector2, bounds: Rect2, team_id: int, team_size: int, team_color: Color) -> void:
	if bots.get_node_or_null(bot_id):
		return
	var bot := BOT_SCENE.instantiate() as CharacterBody2D
	bot.name = bot_id
	bot.position = spawn_position
	bot.set_meta("survival_bounds", bounds)
	bots.add_child(bot)
	bot.call("configure_team", team_id, team_size, team_color)

func build_bot_states() -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for child in bots.get_children():
		var bot := child as CharacterBody2D
		if not bot:
			continue
		states.append({"id": bot.name, "position": bot.global_position, "velocity": bot.velocity})
	return states

@rpc("authority", "call_remote", "unreliable")
func sync_bot_states_rpc(states: Array[Dictionary]) -> void:
	for state_data in states:
		var bot := bots.get_node_or_null(str(state_data.get("id", ""))) as CharacterBody2D
		if not bot:
			continue
		var target_position: Vector2 = state_data.get("position", bot.global_position)
		var target_velocity: Vector2 = state_data.get("velocity", Vector2.ZERO)
		bot.set_meta("network_target_position", target_position)
		bot.set_meta("network_target_velocity", target_velocity)

func interpolate_remote_bots(delta: float) -> void:
	var blend := 1.0 - exp(-15.0 * delta)
	for child in bots.get_children():
		var bot := child as CharacterBody2D
		if not bot or not bot.has_meta("network_target_position"):
			continue
		var target_position: Vector2 = bot.get_meta("network_target_position")
		var target_velocity: Vector2 = bot.get_meta("network_target_velocity", Vector2.ZERO)
		bot.global_position = bot.global_position.lerp(target_position + target_velocity * 0.05, blend)
		bot.velocity = target_velocity

func interpolate_remote_boss(delta: float) -> void:
	if not boss_visual or not boss_active or boss_dash_pending:
		return
	var blend := 1.0 - exp(-12.0 * delta)
	boss_visual.position = boss_visual.position.lerp(boss_network_position, blend)

func get_boss_aggression() -> float:
	return 1.0 + minf(float(maxi(0, boss_index - 1)) * 0.14, 1.8)

func update_boss_movement(delta: float) -> void:
	if boss_dash_pending:
		return
	var aggression := get_boss_aggression()
	boss_move_timer -= delta
	boss_dash_cooldown -= delta
	if boss_move_timer <= 0.0 or boss_position.distance_to(boss_move_target) < 16.0:
		boss_move_target = random_boss_position()
		boss_move_timer = randf_range(0.65, 1.35) / aggression
	boss_position = boss_position.move_toward(boss_move_target, 48.0 * aggression * delta)
	boss_network_position = boss_position
	if boss_visual:
		boss_visual.position = boss_position
	if boss_dash_cooldown <= 0.0:
		begin_boss_dash()

func random_boss_position() -> Vector2:
	var movement_radius := minf(arena_bounds.size.x, arena_bounds.size.y) * 0.5 - 90.0
	return arena_bounds.get_center() + Vector2.from_angle(randf_range(0.0, TAU)) * sqrt(randf()) * movement_radius

func begin_boss_dash() -> void:
	var targets := get_active_participants()
	if targets.is_empty():
		boss_dash_cooldown = 2.0
		return
	boss_dash_pending = true
	var target: Node2D = targets.pick_random()
	var dash_direction := boss_position.direction_to(target.global_position)
	if dash_direction == Vector2.ZERO:
		dash_direction = Vector2.RIGHT
	var dash_target := target.global_position + dash_direction * 72.0
	var arena_center := arena_bounds.get_center()
	var dash_radius := minf(arena_bounds.size.x, arena_bounds.size.y) * 0.5 - 34.0
	var dash_offset := dash_target - arena_center
	if dash_offset.length_squared() > dash_radius * dash_radius:
		dash_target = arena_center + dash_offset.normalized() * dash_radius
	var dash_start := boss_position
	rpc("telegraph_boss_dash_rpc", dash_start, dash_target, get_boss_color(boss_index))
	get_tree().create_timer(maxf(0.20, 0.42 / get_boss_aggression())).timeout.connect(func():
		if is_inside_tree() and boss_active:
			execute_boss_dash(dash_start, dash_target)
	)

func execute_boss_dash(dash_start: Vector2, dash_target: Vector2) -> void:
	boss_position = dash_target
	boss_network_position = dash_target
	boss_dash_pending = false
	boss_dash_cooldown = maxf(1.65, 5.0 / get_boss_aggression())
	rpc("execute_boss_dash_rpc", dash_start, dash_target, get_boss_color(boss_index))
	for participant in get_active_participants():
		var closest_point := Geometry2D.get_closest_point_to_segment(participant.global_position, dash_start, dash_target)
		if participant.global_position.distance_to(closest_point) > 38.0:
			continue
		if participant.has_method("receive_boss_bash_rpc"):
			var knockback := dash_start.direction_to(dash_target) * 150.0
			participant.rpc_id(participant.get_multiplayer_authority(), "receive_boss_bash_rpc", 1, knockback)
	for trail_index in range(6):
		var trail_position := dash_start.lerp(dash_target, float(trail_index + 1) / 7.0)
		var trail_angle := dash_start.direction_to(dash_target).angle() + PI * 0.5
		rpc("spawn_survival_bullet_rpc", trail_position, trail_angle, 92.0 * get_boss_aggression(), get_boss_color(boss_index))
		rpc("spawn_survival_bullet_rpc", trail_position, trail_angle + PI, 92.0 * get_boss_aggression(), get_boss_color(boss_index))

@rpc("authority", "call_local", "reliable")
func telegraph_boss_dash_rpc(dash_start: Vector2, dash_target: Vector2, color: Color) -> void:
	boss_dash_pending = true
	var warning_line := Line2D.new()
	warning_line.points = PackedVector2Array([dash_start, dash_target])
	warning_line.width = 8.0
	warning_line.default_color = Color(1.0, 0.88, 0.16, 0.72)
	warning_line.z_index = 8
	add_child(warning_line)
	var warning_tween := create_tween().set_parallel()
	warning_tween.tween_property(warning_line, "width", 2.0, 0.36)
	warning_tween.tween_property(warning_line, "default_color", Color(color.r, color.g, color.b, 0.15), 0.36)
	warning_tween.finished.connect(warning_line.queue_free)

@rpc("authority", "call_local", "reliable")
func execute_boss_dash_rpc(dash_start: Vector2, dash_target: Vector2, color: Color) -> void:
	boss_dash_pending = false
	boss_network_position = dash_target
	if boss_visual:
		boss_visual.position = dash_target
	play_boss_burst(dash_start, color, 12)
	play_boss_burst(dash_target, color, 20)
	var dash_audio := AudioStreamPlayer2D.new()
	dash_audio.stream = BOSS_DASH_SFX
	dash_audio.bus = &"SFX"
	dash_audio.pitch_scale = randf_range(0.82, 1.05)
	dash_audio.position = dash_target
	add_child(dash_audio)
	dash_audio.finished.connect(dash_audio.queue_free)
	dash_audio.play()
	for player_node in get_tree().get_nodes_in_group("players"):
		var player := player_node as CharacterBody2D
		if player and player.is_multiplayer_authority() and player.has_method("play_survival_boss_shake"):
			player.call("play_survival_boss_shake", 6.5 + minf(float(boss_index), 5.0) * 0.45)

@rpc("authority", "call_local", "reliable")
func play_boss_landing_rpc(landing_position: Vector2, color: Color) -> void:
	play_boss_burst(landing_position, color, 28)
	var landing_audio := AudioStreamPlayer2D.new()
	landing_audio.stream = BOSS_LAND_SFX
	landing_audio.bus = &"SFX"
	landing_audio.volume_db = -3.0
	add_child(landing_audio)
	landing_audio.global_position = landing_position
	landing_audio.finished.connect(landing_audio.queue_free)
	landing_audio.play()
	for player_node in get_tree().get_nodes_in_group("players"):
		var player := player_node as CharacterBody2D
		if player and player.is_multiplayer_authority() and player.has_method("play_survival_boss_shake"):
			player.call("play_survival_boss_shake", 8.5)

@rpc("authority", "call_local", "reliable")
func configure_human_players_rpc(bounds: Rect2, team_size: int, team_color: Color) -> void:
	survival_team_size = team_size
	var human_players := get_human_players()
	human_players.sort_custom(func(a: Node, b: Node): return a.name.naturalnocasecmp_to(b.name) < 0)
	for index in range(human_players.size()):
		var player := human_players[index] as CharacterBody2D
		if not player:
			continue
		var angle := TAU * float(index) / float(maxi(1, human_players.size()))
		var spawn_position := bounds.get_center() + Vector2.from_angle(angle) * 72.0
		player.call("enter_survival_mode", bounds, spawn_position, 0, team_size, team_color)

@rpc("authority", "call_local", "reliable")
func spawn_survival_bullet_rpc(spawn_position: Vector2, angle: float, projectile_speed: float, color: Color) -> void:
	var bullet := BULLET_SCENE.instantiate() as Area2D
	bullet.position = spawn_position
	bullet.rotation = angle
	bullet.set("speed", projectile_speed)
	bullet.set("damage", 1)
	bullet.set("lifetime", 7.0)
	bullet.set("knockback_force", 28.0)
	var bullet_sprite := bullet.get_node_or_null("Sprite2D") as Sprite2D
	if bullet_sprite:
		bullet_sprite.modulate = color
	bullet.add_to_group("survival_hazards")
	projectiles.add_child(bullet)

@rpc("authority", "call_local", "reliable")
func start_boss_rpc(new_boss_index: int, duration: float) -> void:
	boss_index = new_boss_index
	boss_active = true
	boss_time_remaining = duration
	boss_intro_remaining = 0.82
	boss_position = arena_bounds.get_center()
	boss_network_position = boss_position
	set_active_boss_visual(new_boss_index)
	if boss_visual.has_method("play_fall_entrance"):
		boss_visual.call("play_fall_entrance", boss_position, get_boss_aggression())
	update_mode_ui()

@rpc("authority", "call_local", "reliable")
func finish_boss_rpc(finished_boss_index: int, reward: int, next_time: float) -> void:
	boss_index = finished_boss_index
	boss_active = false
	boss_dash_pending = false
	intermission_remaining = next_time
	clear_projectiles()
	play_boss_burst(boss_position, get_boss_color(boss_index), 34)
	var tween := create_tween().set_parallel()
	tween.tween_property(boss_visual, "scale", Vector2.ZERO, 0.42)
	tween.tween_property(boss_visual, "modulate:a", 0.0, 0.42)
	tween.finished.connect(func():
		boss_visual.hide()
		boss_visual.modulate.a = 1.0
	)
	if award_local_kernel_currency(reward):
		show_kernel_reward(reward)
	update_mode_ui()

func award_local_kernel_currency(amount: int) -> bool:
	for player_node in get_tree().get_nodes_in_group("players"):
		var player := player_node as CharacterBody2D
		if player and player.is_multiplayer_authority() and not bool(player.get("is_survival_ghost")):
			MetaProgression.add_kernel_currency(amount)
			return true
	return false

func show_kernel_reward(amount: int) -> void:
	var label := Label.new()
	label.text = "+%d KERNEL%s" % [amount, "" if amount == 1 else "S"]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = arena_bounds.get_center() - Vector2(75.0, 12.0)
	label.size = Vector2(150.0, 24.0)
	label.add_theme_font_size_override("font_size", 16)
	add_child(label)
	var tween := create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 42.0, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.35)
	tween.finished.connect(label.queue_free)

@rpc("authority", "call_local", "unreliable")
func sync_mode_ui_rpc(new_boss_index: int, time_remaining: float, active: bool, break_remaining: float, synced_boss_position: Vector2) -> void:
	boss_index = new_boss_index
	boss_time_remaining = time_remaining
	boss_active = active
	intermission_remaining = break_remaining
	boss_network_position = synced_boss_position
	update_mode_ui()

@rpc("authority", "call_local", "reliable")
func show_intermission_rpc(time_remaining: float, next_boss: int) -> void:
	intermission_remaining = time_remaining
	boss_index = next_boss - 1
	boss_active = false
	update_mode_ui()

func create_boss_visual() -> void:
	set_active_boss_visual(1)
	boss_visual.hide()

func set_active_boss_visual(index: int) -> void:
	if boss_visual and is_instance_valid(boss_visual):
		boss_visual.queue_free()
	var scene_index := posmod(index - 1, BOSS_SCENES.size())
	boss_visual = BOSS_SCENES[scene_index].instantiate() as Node2D
	boss_visual.position = arena_bounds.get_center()
	boss_visual.z_index = 6
	add_child(boss_visual)

func create_mode_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 35
	var panel := ColorRect.new()
	panel.color = Color(0.025, 0.02, 0.055, 0.92)
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(-155.0, 8.0)
	panel.size = Vector2(310.0, 38.0)
	layer.add_child(panel)
	boss_label = Label.new()
	boss_label.position = Vector2(8.0, 2.0)
	boss_label.size = Vector2(210.0, 17.0)
	panel.add_child(boss_label)
	boss_timer_label = Label.new()
	boss_timer_label.position = Vector2(222.0, 2.0)
	boss_timer_label.size = Vector2(80.0, 17.0)
	boss_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(boss_timer_label)
	var bar_back := ColorRect.new()
	bar_back.color = Color(0.12, 0.08, 0.16, 1.0)
	bar_back.position = Vector2(8.0, 23.0)
	bar_back.size = Vector2(294.0, 8.0)
	panel.add_child(bar_back)
	boss_bar_fill = ColorRect.new()
	boss_bar_fill.color = Color(1.0, 0.72, 0.20, 1.0)
	boss_bar_fill.position = Vector2(8.0, 23.0)
	boss_bar_fill.size = Vector2(294.0, 8.0)
	panel.add_child(boss_bar_fill)
	participant_label = Label.new()
	participant_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	participant_label.position = Vector2(-218.0, 49.0)
	participant_label.size = Vector2(210.0, 18.0)
	participant_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layer.add_child(participant_label)
	add_child(layer)
	update_mode_ui()

func update_mode_ui() -> void:
	if not boss_label:
		return
	var mode_name := "SOLO" if survival_team_size <= 1 else "TEAMS OF %d" % survival_team_size
	participant_label.text = "%d / %d  %s" % [get_active_participants().size(), target_participant_count, mode_name]
	if boss_active:
		boss_label.text = "BOSS %d  //  %s" % [boss_index, get_boss_name(boss_index)]
		boss_timer_label.text = "%04.1f" % maxf(0.0, boss_time_remaining)
		var duration := boss_duration + minf(float(boss_index - 1) * 2.0, 12.0)
		boss_bar_fill.size.x = 294.0 * clampf(boss_time_remaining / duration, 0.0, 1.0)
		boss_bar_fill.color = get_boss_color(boss_index)
	else:
		boss_label.text = "NEXT BOSS %d" % (boss_index + 1)
		boss_timer_label.text = "%04.1f" % maxf(0.0, intermission_remaining)
		boss_bar_fill.size.x = 294.0 * clampf(intermission_remaining / maxf(0.01, intermission_duration), 0.0, 1.0)
		boss_bar_fill.color = Color(0.30, 0.86, 1.0)

func get_boss_name(index: int) -> String:
	match posmod(index - 1, BOSS_SCENES.size()):
		0: return "BUTTERSTORM"
		1: return "THE POPPING FLAME"
		2: return "MAGNETRON PRIME"
		_: return "HELIX SOVEREIGN"

func get_boss_color(index: int) -> Color:
	match posmod(index - 1, BOSS_SCENES.size()):
		0: return Color(1.0, 0.78, 0.18)
		1: return Color(1.0, 0.20, 0.08)
		2: return Color(0.66, 0.28, 1.0)
		_: return Color(0.10, 0.92, 0.72)

@rpc("authority", "call_local", "unreliable")
func play_boss_burst_rpc(origin: Vector2, color: Color, count: int) -> void:
	play_boss_burst(origin, color, count)

func play_boss_burst(origin: Vector2, color: Color, count: int) -> void:
	var burst := Node2D.new()
	burst.position = origin
	add_child(burst)
	for index in range(count):
		var particle := Sprite2D.new()
		particle.texture = PARTICLE_TEXTURE
		particle.modulate = color
		particle.scale = Vector2.ONE * randf_range(0.65, 1.25)
		burst.add_child(particle)
		var direction := Vector2.from_angle(randf_range(0.0, TAU))
		var tween := burst.create_tween().set_parallel()
		tween.tween_property(particle, "position", direction * randf_range(18.0, 62.0), 0.32)
		tween.tween_property(particle, "scale", Vector2.ZERO, 0.32)
		tween.tween_property(particle, "modulate:a", 0.0, 0.32)
	get_tree().create_timer(0.35).timeout.connect(burst.queue_free)

func clear_projectiles() -> void:
	for projectile in projectiles.get_children():
		projectile.queue_free()

func _draw() -> void:
	var arena_center := arena_bounds.get_center()
	var arena_radius := minf(arena_bounds.size.x, arena_bounds.size.y) * 0.5
	# The offset silhouette and rim make this read as the top of a tall round tower.
	draw_circle(arena_center + Vector2(0.0, 38.0), arena_radius + 7.0, Color(0.035, 0.022, 0.065, 1.0))
	draw_circle(arena_center, arena_radius + 10.0, Color(0.62, 0.32, 0.12, 1.0))
	draw_circle(arena_center, arena_radius, Color(0.13, 0.075, 0.17, 1.0))
	var grid_color := Color(0.48, 0.22, 0.50, 0.24)
	for x_offset in range(-int(arena_radius), int(arena_radius) + 1, 56):
		var half_chord := sqrt(maxf(0.0, arena_radius * arena_radius - float(x_offset * x_offset)))
		draw_line(arena_center + Vector2(float(x_offset), -half_chord), arena_center + Vector2(float(x_offset), half_chord), grid_color, 1.0)
	for y_offset in range(-int(arena_radius), int(arena_radius) + 1, 56):
		var half_chord := sqrt(maxf(0.0, arena_radius * arena_radius - float(y_offset * y_offset)))
		draw_line(arena_center + Vector2(-half_chord, float(y_offset)), arena_center + Vector2(half_chord, float(y_offset)), grid_color, 1.0)
	draw_arc(arena_center, arena_radius, 0.0, TAU, 96, Color(1.0, 0.69, 0.20, 0.92), 5.0)
	draw_arc(arena_center, arena_radius - 12.0, 0.0, TAU, 96, Color(1.0, 0.69, 0.20, 0.18), 2.0)
	draw_circle(arena_center, 72.0, Color(0.32, 0.12, 0.38, 0.42))
	draw_arc(arena_center, 72.0, 0.0, TAU, 64, Color(1.0, 0.66, 0.16, 0.75), 3.0)
