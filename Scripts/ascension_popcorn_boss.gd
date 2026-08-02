extends CharacterBody2D

const BULLET_SCENE := preload("res://Scenes/bullet.tscn")
const ATTACK_INDICATOR := preload("res://Scripts/boss_attack_indicator.gd")
const HIT_SFX := preload("res://SFX/cancel.wav")
const DEATH_SFX := preload("res://SFX/kick.wav")
const IMPACT_TEXTURE := preload("res://Assets/plus particle.png")

enum AttackType { SLIDE, RING, GATLING, DNA }
enum BossState { INTRO, IDLE, WINDUP, SLIDING, FIRING, DYING }

@export_group("Ascension Scaling")
@export var base_health := 360
@export var health_per_defeated_boss := 0.38
@export var base_aggression := 1.28
@export var aggression_per_defeated_boss := 0.24
@export var maximum_aggression := 3.25

var boss_kind := 0
var bosses_defeated := 0
var aggression := 1.0
var boss_display_name := "ASCENSION BOSS"
var boss_color := Color.WHITE
var max_health := 240
var current_health := 240
var state := BossState.INTRO
var current_attack := AttackType.RING
var attack_index := 0
var state_timer := 0.82
var shot_timer := 0.0
var attack_rotation := 0.0
var attack_direction := Vector2.RIGHT
var target_player: CharacterBody2D
var arena_bounds := Rect2(28, 30, 424, 220)
var landing_position := Vector2.ZERO
var presentation: Node2D
var health_bar_fill: ColorRect
var health_bar_label: Label
var is_enraged := false
var slide_hit_players: Dictionary = {}

func _enter_tree() -> void:
	set_multiplayer_authority(1)

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	landing_position = global_position
	var configured_bounds: Variant = get_meta("arena_bounds", arena_bounds)
	if configured_bounds is Rect2:
		arena_bounds = configured_bounds
	boss_kind = int(get_meta("boss_kind", 0))
	bosses_defeated = int(get_meta("bosses_defeated", 0))
	aggression = minf(maximum_aggression, base_aggression + float(bosses_defeated) * aggression_per_defeated_boss)
	create_presentation(str(get_meta("presentation_path", "")))
	create_health_bar()
	var player_count := maxi(1, get_active_players().size())
	max_health = roundi(float(base_health + boss_kind * 24) * (1.0 + float(bosses_defeated) * health_per_defeated_boss)) * player_count
	current_health = max_health
	var collision_shape := $CollisionShape2D as CollisionShape2D
	collision_shape.disabled = true
	if presentation and presentation.has_method("play_fall_entrance"):
		presentation.call("play_fall_entrance", Vector2.ZERO, aggression)
	if multiplayer.is_server():
		rpc("configure_encounter_rpc", max_health, aggression, boss_display_name, boss_color)

func create_presentation(scene_path: String) -> void:
	if scene_path.is_empty():
		return
	var packed: PackedScene = load(scene_path) as PackedScene
	if not packed:
		return
	presentation = packed.instantiate() as Node2D
	add_child(presentation)
	if presentation.has_method("get_boss_name"):
		boss_display_name = str(presentation.call("get_boss_name"))
	if presentation.has_method("get_boss_color"):
		var returned_color: Variant = presentation.call("get_boss_color")
		if returned_color is Color:
			boss_color = returned_color

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or state == BossState.DYING:
		return
	if state == BossState.INTRO:
		state_timer -= delta
		if state_timer <= 0.0:
			rpc("finish_intro_rpc")
		return
	find_target_player()
	if not target_player:
		velocity = Vector2.ZERO
		return
	match state:
		BossState.IDLE:
			handle_idle(delta)
		BossState.WINDUP:
			handle_windup(delta)
		BossState.SLIDING:
			handle_slide(delta)
		BossState.FIRING:
			handle_firing(delta)

func handle_idle(delta: float) -> void:
	var to_target := target_player.global_position - global_position
	var desired_distance := 82.0 if boss_kind == 0 else 128.0
	velocity = to_target.normalized() * 58.0 * aggression if to_target.length() > desired_distance else Vector2.ZERO
	move_and_slide()
	clamp_to_arena()
	state_timer -= delta
	if state_timer <= 0.0:
		begin_next_attack()

func begin_next_attack() -> void:
	if boss_kind == 3 and attack_index % 2 == 0:
		current_attack = AttackType.DNA
	else:
		current_attack = posmod(boss_kind + attack_index, 3) as AttackType
	attack_index += 1
	attack_direction = global_position.direction_to(target_player.global_position)
	if attack_direction == Vector2.ZERO:
		attack_direction = Vector2.RIGHT
	state = BossState.WINDUP
	state_timer = maxf(0.18, 0.54 / aggression)
	velocity = Vector2.ZERO
	rpc("show_attack_telegraph_rpc", current_attack, global_position, attack_direction, state_timer)

func handle_windup(delta: float) -> void:
	state_timer -= delta
	if state_timer > 0.0:
		return
	match current_attack:
		AttackType.SLIDE:
			state = BossState.SLIDING
			state_timer = 0.42
			slide_hit_players.clear()
		AttackType.RING:
			fire_circular_volley()
			finish_attack()
		AttackType.GATLING, AttackType.DNA:
			state = BossState.FIRING
			state_timer = 1.35 if current_attack == AttackType.GATLING else 1.65
			shot_timer = 0.0

func handle_slide(delta: float) -> void:
	velocity = attack_direction * 345.0 * minf(aggression, 2.15)
	move_and_slide()
	damage_slide_collisions()
	clamp_to_arena()
	state_timer -= delta
	if state_timer <= 0.0:
		finish_attack()

func handle_firing(delta: float) -> void:
	velocity = Vector2.ZERO
	state_timer -= delta
	shot_timer -= delta
	if shot_timer <= 0.0:
		if current_attack == AttackType.DNA:
			shot_timer = maxf(0.055, 0.13 / aggression)
			fire_dna_pair()
		else:
			shot_timer = maxf(0.060, 0.14 / aggression)
			fire_gatling_shots()
	if state_timer <= 0.0:
		finish_attack()

func finish_attack() -> void:
	state = BossState.IDLE
	state_timer = maxf(0.26, 0.86 / aggression)
	velocity = Vector2.ZERO

func fire_circular_volley() -> void:
	var ring_count := 1 + mini(2, floori(float(bosses_defeated) / 2.0))
	for ring_index in range(ring_count):
		var bullet_count := 14 + mini(12, bosses_defeated * 2) + ring_index * 4
		var ring_speed := (152.0 + float(ring_index) * 40.0) * minf(aggression, 2.2)
		for bullet_index in range(bullet_count):
			var angle := attack_rotation + TAU * float(bullet_index) / float(bullet_count)
			rpc("spawn_bullet_rpc", global_position, angle, ring_speed, boss_color)
	attack_rotation += 0.21
	rpc("spawn_particles_rpc", global_position, boss_color, 18)

func fire_gatling_shots() -> void:
	for player in get_active_players():
		var aim := global_position.direction_to(player.global_position)
		var spread := randf_range(-0.10, 0.10)
		rpc("spawn_bullet_rpc", global_position, aim.angle() + spread, 248.0 * minf(aggression, 2.15), boss_color)

func fire_dna_pair() -> void:
	attack_rotation += 0.34
	var speed_value := 164.0 * minf(aggression, 2.2)
	rpc("spawn_bullet_rpc", global_position, attack_rotation, speed_value, Color(0.08, 0.96, 0.74))
	rpc("spawn_bullet_rpc", global_position, attack_rotation + PI, speed_value, Color(1.0, 0.22, 0.70))
	if attack_index % 3 == 0:
		rpc("spawn_bullet_rpc", global_position, attack_rotation + PI * 0.5, speed_value * 0.72, Color(0.72, 0.94, 1.0))
		rpc("spawn_bullet_rpc", global_position, attack_rotation - PI * 0.5, speed_value * 0.72, Color(0.72, 0.94, 1.0))

func damage_slide_collisions() -> void:
	for collision_index in range(get_slide_collision_count()):
		var collision := get_slide_collision(collision_index)
		var player := collision.get_collider() as CharacterBody2D
		if not player or not player.has_method("receive_boss_bash_rpc"):
			continue
		var player_id := player.get_multiplayer_authority()
		if slide_hit_players.has(player_id):
			continue
		slide_hit_players[player_id] = true
		player.rpc_id(player_id, "receive_boss_bash_rpc", 2, attack_direction * 210.0)

func find_target_player() -> void:
	target_player = null
	var closest_distance := INF
	for player in get_active_players():
		var distance := global_position.distance_to(player.global_position)
		if distance < closest_distance:
			closest_distance = distance
			target_player = player

func get_active_players() -> Array[CharacterBody2D]:
	var players: Array[CharacterBody2D] = []
	for player_node in get_tree().get_nodes_in_group("players"):
		var player := player_node as CharacterBody2D
		if player and not bool(player.get("is_downed")):
			players.append(player)
	return players

func clamp_to_arena() -> void:
	global_position.x = clampf(global_position.x, arena_bounds.position.x + 22.0, arena_bounds.end.x - 22.0)
	global_position.y = clampf(global_position.y, arena_bounds.position.y + 22.0, arena_bounds.end.y - 22.0)

func take_damage(amount: int) -> void:
	if not multiplayer.is_server() or state == BossState.INTRO or state == BossState.DYING:
		return
	current_health = maxi(0, current_health - amount)
	if not is_enraged and current_health <= floori(float(max_health) * 0.5):
		is_enraged = true
		aggression = minf(maximum_aggression * 1.12, aggression * 1.38)
	rpc("sync_health_rpc", current_health, max_health, is_enraged)
	rpc("play_hit_rpc", global_position)
	if current_health <= 0:
		rpc("die_rpc")

@rpc("authority", "call_local", "reliable")
func configure_encounter_rpc(health_maximum: int, aggression_value: float, display_name: String, color: Color) -> void:
	max_health = health_maximum
	current_health = health_maximum
	aggression = aggression_value
	boss_display_name = display_name
	boss_color = color
	update_health_bar()

@rpc("authority", "call_local", "reliable")
func finish_intro_rpc() -> void:
	state = BossState.IDLE
	state_timer = maxf(0.30, 0.78 / aggression)
	($CollisionShape2D as CollisionShape2D).set_deferred("disabled", false)
	play_sound(DEATH_SFX, global_position, -4.0)
	spawn_particles(global_position, boss_color, 24)
	for player_node in get_tree().get_nodes_in_group("players"):
		var player := player_node as CharacterBody2D
		if player and player.is_multiplayer_authority() and player.has_method("play_survival_boss_shake"):
			player.call("play_survival_boss_shake", 8.0)

@rpc("authority", "call_local", "reliable")
func show_attack_telegraph_rpc(attack_type: int, origin: Vector2, direction: Vector2, duration: float) -> void:
	var indicator := ATTACK_INDICATOR.new() as Node2D
	indicator.global_position = origin
	indicator.rotation = direction.angle()
	var indicator_kind := 0 if attack_type == AttackType.SLIDE else 2 if attack_type == AttackType.GATLING else 1
	indicator.call("configure", indicator_kind, 170.0, 62.0, 30.0, duration)
	get_parent().add_child(indicator)

@rpc("authority", "call_local", "reliable")
func spawn_bullet_rpc(spawn_position: Vector2, angle: float, projectile_speed: float, color: Color) -> void:
	var bullet := BULLET_SCENE.instantiate() as Area2D
	bullet.global_position = spawn_position
	bullet.rotation = angle
	bullet.set("speed", projectile_speed)
	bullet.set("damage", 1)
	bullet.set("knockback_force", 62.0)
	bullet.set("shooter", self)
	var bullet_sprite := bullet.get_node_or_null("Sprite2D") as Sprite2D
	if bullet_sprite:
		bullet_sprite.modulate = color
	get_parent().add_child(bullet)

@rpc("authority", "call_local", "reliable")
func sync_health_rpc(health: int, health_maximum: int, enraged: bool) -> void:
	current_health = health
	max_health = health_maximum
	is_enraged = enraged
	update_health_bar()

func create_health_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	var panel := ColorRect.new()
	panel.color = Color(0.025, 0.015, 0.05, 0.94)
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(-145.0, 9.0)
	panel.size = Vector2(290.0, 30.0)
	layer.add_child(panel)
	health_bar_label = Label.new()
	health_bar_label.position = Vector2(5.0, 1.0)
	health_bar_label.size = Vector2(280.0, 14.0)
	health_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health_bar_label.add_theme_font_size_override("font_size", 10)
	panel.add_child(health_bar_label)
	var backing := ColorRect.new()
	backing.color = Color(0.12, 0.05, 0.15)
	backing.position = Vector2(7.0, 18.0)
	backing.size = Vector2(276.0, 8.0)
	panel.add_child(backing)
	health_bar_fill = ColorRect.new()
	health_bar_fill.position = backing.position
	health_bar_fill.size = backing.size
	panel.add_child(health_bar_fill)
	add_child(layer)
	update_health_bar()

func update_health_bar() -> void:
	if not health_bar_fill or max_health <= 0:
		return
	health_bar_fill.size.x = 276.0 * clampf(float(current_health) / float(max_health), 0.0, 1.0)
	health_bar_fill.color = Color(1.0, 0.18, 0.42) if is_enraged else boss_color
	health_bar_label.text = "%s  //  ENRAGED" % boss_display_name if is_enraged else boss_display_name

@rpc("authority", "call_local", "unreliable")
func play_hit_rpc(origin: Vector2) -> void:
	play_sound(HIT_SFX, origin, -8.0)
	spawn_particles(origin, boss_color.lightened(0.32), 7)

@rpc("authority", "call_local", "reliable")
func spawn_particles_rpc(origin: Vector2, color: Color, count: int) -> void:
	spawn_particles(origin, color, count)

func spawn_particles(origin: Vector2, color: Color, count: int) -> void:
	var burst := Node2D.new()
	get_parent().add_child(burst)
	burst.global_position = origin
	for particle_index in range(count):
		var particle := Sprite2D.new()
		particle.texture = IMPACT_TEXTURE
		particle.modulate = color
		burst.add_child(particle)
		var direction := Vector2.from_angle(TAU * float(particle_index) / float(maxi(1, count)) + randf_range(-0.18, 0.18))
		var tween := burst.create_tween().set_parallel()
		tween.tween_property(particle, "position", direction * randf_range(18.0, 52.0), 0.26)
		tween.tween_property(particle, "scale", Vector2.ZERO, 0.26)
		tween.tween_property(particle, "modulate:a", 0.0, 0.26)
	get_tree().create_timer(0.30).timeout.connect(burst.queue_free)

func play_sound(stream: AudioStream, origin: Vector2, volume: float) -> void:
	var audio := AudioStreamPlayer2D.new()
	audio.stream = stream
	audio.bus = &"SFX"
	audio.volume_db = volume
	get_parent().add_child(audio)
	audio.global_position = origin
	audio.finished.connect(audio.queue_free)
	audio.play()

@rpc("authority", "call_local", "reliable")
func die_rpc() -> void:
	if state == BossState.DYING:
		return
	state = BossState.DYING
	velocity = Vector2.ZERO
	($CollisionShape2D as CollisionShape2D).set_deferred("disabled", true)
	play_sound(DEATH_SFX, global_position, -2.0)
	spawn_particles(global_position, boss_color, 36)
	if health_bar_label:
		health_bar_label.text = "%s  //  DEFEATED" % boss_display_name
	var death_tween := create_tween().set_parallel()
	death_tween.tween_property(self, "scale", Vector2.ZERO, 0.46).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	death_tween.tween_property(self, "modulate:a", 0.0, 0.46)
	death_tween.finished.connect(queue_free)
