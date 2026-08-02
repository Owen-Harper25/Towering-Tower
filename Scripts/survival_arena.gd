extends Node2D

const BOT_SCENE := preload("res://Scenes/survival_bot.tscn")
const BULLET_SCENE := preload("res://Scenes/bullet.tscn")
const BOSS_TEXTURE := preload("res://icon.svg")
const PARTICLE_TEXTURE := preload("res://Assets/plus particle.png")

@export var arena_bounds := Rect2(40, 40, 820, 520)
@export var target_participant_count := 20
@export var boss_duration := 30.0
@export var intermission_duration := 5.0

@onready var bots: Node2D = $Bots
@onready var projectiles: Node2D = $Projectiles

var boss_visual: Sprite2D
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
	rpc("configure_human_players_rpc", arena_bounds)
	spawn_missing_bots()
	intermission_remaining = 2.5
	rpc("show_intermission_rpc", intermission_remaining, boss_index + 1)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		interpolate_remote_bots(delta)
		return
	bot_sync_elapsed += delta
	if bot_sync_elapsed >= 0.08:
		bot_sync_elapsed = 0.0
		rpc("sync_bot_states_rpc", build_bot_states())
	mode_sync_elapsed += delta
	if boss_active:
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
		rpc("sync_mode_ui_rpc", boss_index, boss_time_remaining, boss_active, intermission_remaining)

func start_next_boss() -> void:
	boss_index += 1
	boss_active = true
	boss_time_remaining = boss_duration + minf(float(boss_index - 1) * 2.0, 12.0)
	attack_timer = 1.2
	attack_rotation = randf_range(0.0, TAU)
	rpc("start_boss_rpc", boss_index, boss_time_remaining)

func finish_current_boss() -> void:
	boss_active = false
	boss_time_remaining = 0.0
	intermission_remaining = intermission_duration
	var reward := 1 + floori(float(boss_index - 1) / 3.0)
	rpc("finish_boss_rpc", boss_index, reward, intermission_remaining)

func perform_boss_attack() -> void:
	var boss_type := (boss_index - 1) % 3
	var difficulty_speed := 1.0 + minf(float(boss_index - 1) * 0.055, 0.65)
	match boss_type:
		0:
			attack_timer = maxf(0.62, 1.42 / difficulty_speed)
			fire_butter_ring(difficulty_speed)
		1:
			attack_timer = maxf(0.82, 1.62 / difficulty_speed)
			fire_flame_wall(difficulty_speed)
		2:
			attack_timer = maxf(0.42, 0.86 / difficulty_speed)
			fire_magnetron_volley(difficulty_speed)

func fire_butter_ring(difficulty_speed: float) -> void:
	var projectile_count := mini(30, 16 + boss_index)
	attack_rotation += 0.19
	for index in range(projectile_count):
		var angle := attack_rotation + TAU * float(index) / float(projectile_count)
		rpc("spawn_survival_bullet_rpc", arena_bounds.get_center(), angle, 145.0 * difficulty_speed, Color(1.0, 0.82, 0.18))
	rpc("play_boss_burst_rpc", arena_bounds.get_center(), Color(1.0, 0.82, 0.18), 18)

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
		var direction := (target.global_position - arena_bounds.get_center()).normalized()
		if direction == Vector2.ZERO:
			direction = Vector2.RIGHT
		var spread := randf_range(-0.11, 0.11)
		rpc("spawn_survival_bullet_rpc", arena_bounds.get_center(), direction.angle() + spread, 205.0 * difficulty_speed, Color(0.78, 0.32, 1.0))
	attack_rotation += 0.43
	for spoke in range(3):
		rpc("spawn_survival_bullet_rpc", arena_bounds.get_center(), attack_rotation + TAU * float(spoke) / 3.0, 135.0 * difficulty_speed, Color(0.42, 0.78, 1.0))
	rpc("play_boss_burst_rpc", arena_bounds.get_center(), Color(0.72, 0.30, 1.0), 10)

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

func spawn_missing_bots() -> void:
	var human_count := get_tree().get_nodes_in_group("players").size()
	var bots_needed := maxi(0, target_participant_count - human_count)
	for index in range(bots_needed):
		var angle := TAU * float(index) / float(maxi(1, bots_needed))
		var spawn_position := arena_bounds.get_center() + Vector2.from_angle(angle) * randf_range(90.0, 190.0)
		var bot_id := "SurvivalBot_%d" % next_bot_id
		next_bot_id += 1
		rpc("spawn_bot_rpc", bot_id, spawn_position, arena_bounds)

@rpc("authority", "call_local", "reliable")
func spawn_bot_rpc(bot_id: String, spawn_position: Vector2, bounds: Rect2) -> void:
	if bots.get_node_or_null(bot_id):
		return
	var bot := BOT_SCENE.instantiate() as CharacterBody2D
	bot.name = bot_id
	bot.position = spawn_position
	bot.set_meta("survival_bounds", bounds)
	bots.add_child(bot)

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

@rpc("authority", "call_local", "reliable")
func configure_human_players_rpc(bounds: Rect2) -> void:
	var human_players := get_tree().get_nodes_in_group("players")
	human_players.sort_custom(func(a: Node, b: Node): return a.name.naturalnocasecmp_to(b.name) < 0)
	for index in range(human_players.size()):
		var player := human_players[index] as CharacterBody2D
		if not player:
			continue
		var angle := TAU * float(index) / float(maxi(1, human_players.size()))
		var spawn_position := bounds.get_center() + Vector2.from_angle(angle) * 72.0
		player.call("enter_survival_mode", bounds, spawn_position)

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
	boss_visual.show()
	boss_visual.modulate = get_boss_color(new_boss_index)
	boss_visual.scale = Vector2.ZERO
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(boss_visual, "scale", Vector2.ONE * 0.55, 0.35)
	update_mode_ui()

@rpc("authority", "call_local", "reliable")
func finish_boss_rpc(finished_boss_index: int, reward: int, next_time: float) -> void:
	boss_index = finished_boss_index
	boss_active = false
	intermission_remaining = next_time
	clear_projectiles()
	play_boss_burst(arena_bounds.get_center(), get_boss_color(boss_index), 34)
	var tween := create_tween().set_parallel()
	tween.tween_property(boss_visual, "scale", Vector2.ZERO, 0.42)
	tween.tween_property(boss_visual, "modulate:a", 0.0, 0.42)
	tween.finished.connect(func():
		boss_visual.hide()
		boss_visual.modulate.a = 1.0
	)
	award_local_kernel_currency(reward)
	show_kernel_reward(reward)
	update_mode_ui()

func award_local_kernel_currency(amount: int) -> void:
	for player_node in get_tree().get_nodes_in_group("players"):
		var player := player_node as CharacterBody2D
		if player and player.is_multiplayer_authority():
			MetaProgression.add_kernel_currency(amount)
			return

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
func sync_mode_ui_rpc(new_boss_index: int, time_remaining: float, active: bool, break_remaining: float) -> void:
	boss_index = new_boss_index
	boss_time_remaining = time_remaining
	boss_active = active
	intermission_remaining = break_remaining
	update_mode_ui()

@rpc("authority", "call_local", "reliable")
func show_intermission_rpc(time_remaining: float, next_boss: int) -> void:
	intermission_remaining = time_remaining
	boss_index = next_boss - 1
	boss_active = false
	update_mode_ui()

func create_boss_visual() -> void:
	boss_visual = Sprite2D.new()
	boss_visual.texture = BOSS_TEXTURE
	boss_visual.position = arena_bounds.get_center()
	boss_visual.scale = Vector2.ONE * 0.55
	boss_visual.hide()
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
	participant_label.position = Vector2(-118.0, 49.0)
	participant_label.size = Vector2(110.0, 18.0)
	participant_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layer.add_child(participant_label)
	add_child(layer)
	update_mode_ui()

func update_mode_ui() -> void:
	if not boss_label:
		return
	participant_label.text = "%d / %d SURVIVORS" % [get_active_participants().size(), target_participant_count]
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
	match (index - 1) % 3:
		0: return "BUTTERSTORM"
		1: return "THE POPPING FLAME"
		_: return "MAGNETRON PRIME"

func get_boss_color(index: int) -> Color:
	match (index - 1) % 3:
		0: return Color(1.0, 0.78, 0.18)
		1: return Color(1.0, 0.20, 0.08)
		_: return Color(0.66, 0.28, 1.0)

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
	draw_rect(arena_bounds.grow(70.0), Color(0.055, 0.035, 0.095, 1.0), true)
	draw_rect(arena_bounds, Color(0.13, 0.075, 0.17, 1.0), true)
	for x in range(int(arena_bounds.position.x), int(arena_bounds.end.x), 64):
		draw_line(Vector2(x, arena_bounds.position.y), Vector2(x, arena_bounds.end.y), Color(0.36, 0.16, 0.38, 0.22), 1.0)
	for y in range(int(arena_bounds.position.y), int(arena_bounds.end.y), 64):
		draw_line(Vector2(arena_bounds.position.x, y), Vector2(arena_bounds.end.x, y), Color(0.36, 0.16, 0.38, 0.22), 1.0)
	draw_rect(arena_bounds, Color(1.0, 0.69, 0.20, 0.82), false, 4.0)
	draw_circle(arena_bounds.get_center(), 72.0, Color(0.32, 0.12, 0.38, 0.42))
	draw_arc(arena_bounds.get_center(), 72.0, 0.0, TAU, 64, Color(1.0, 0.66, 0.16, 0.75), 3.0)
