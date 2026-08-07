extends CharacterBody2D

const BULLET_SCENE := preload("res://Scenes/bullet.tscn")
const ATTACK_INDICATOR := preload("res://Scripts/boss_attack_indicator.gd")
const HIT_SFX := preload("res://SFX/cancel.wav")
const DEATH_SFX := preload("res://SFX/kick.wav")
const IMPACT_TEXTURE := preload("res://Assets/plus particle.png")

enum AttackType { SLIDE, RING, GATLING, DNA, SPIRAL, FAN, WALL, CROSS, BUTTER_CIRCLES, FIRE_LANES, MAGNET_SPREAD, TRI_DNA }
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
var signature_attack_bag: Array[int] = []
var last_attack := -1
var signature_step := 0

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
	var desired_distance := 76.0 if boss_kind == 0 else 104.0 if boss_kind == 4 else 128.0
	velocity = to_target.normalized() * 58.0 * aggression if to_target.length() > desired_distance else Vector2.ZERO
	move_and_slide()
	clamp_to_arena()
	state_timer -= delta
	if state_timer <= 0.0:
		begin_next_attack()

func begin_next_attack() -> void:
	if signature_attack_bag.is_empty():
		refill_signature_attack_bag()
	current_attack = signature_attack_bag.pop_front() as AttackType
	last_attack = current_attack
	attack_index += 1
	attack_direction = global_position.direction_to(target_player.global_position)
	if attack_direction == Vector2.ZERO:
		attack_direction = Vector2.RIGHT
	state = BossState.WINDUP
	state_timer = maxf(0.18, 0.54 / aggression)
	velocity = Vector2.ZERO
	rpc("show_attack_telegraph_rpc", current_attack, global_position, attack_direction, state_timer)

func refill_signature_attack_bag() -> void:
	var attack_decks: Array[Array] = [
		[AttackType.BUTTER_CIRCLES, AttackType.BUTTER_CIRCLES, AttackType.SPIRAL, AttackType.RING, AttackType.FAN],
		[AttackType.FIRE_LANES, AttackType.FIRE_LANES, AttackType.WALL, AttackType.FAN, AttackType.SLIDE],
		[AttackType.MAGNET_SPREAD, AttackType.MAGNET_SPREAD, AttackType.CROSS, AttackType.SPIRAL, AttackType.GATLING],
		[AttackType.TRI_DNA, AttackType.TRI_DNA, AttackType.DNA, AttackType.RING, AttackType.SPIRAL],
		[AttackType.SLIDE, AttackType.CROSS, AttackType.FIRE_LANES, AttackType.GATLING, AttackType.RING],
		[AttackType.TRI_DNA, AttackType.RING, AttackType.FAN, AttackType.CROSS, AttackType.SPIRAL, AttackType.GATLING],
	]
	var deck: Array = attack_decks[clampi(boss_kind, 0, attack_decks.size() - 1)].duplicate()
	deck.shuffle()
	if deck.size() > 1 and int(deck[0]) == last_attack:
		var swap_index := randi_range(1, deck.size() - 1)
		var first_attack: Variant = deck[0]
		deck[0] = deck[swap_index]
		deck[swap_index] = first_attack
	signature_attack_bag.clear()
	for attack_variant in deck:
		signature_attack_bag.append(int(attack_variant))

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
		AttackType.WALL:
			fire_flame_wall()
			finish_attack()
		AttackType.GATLING, AttackType.DNA, AttackType.SPIRAL, AttackType.FAN, AttackType.CROSS, AttackType.BUTTER_CIRCLES, AttackType.FIRE_LANES, AttackType.MAGNET_SPREAD, AttackType.TRI_DNA:
			state = BossState.FIRING
			state_timer = get_firing_attack_duration()
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
		match current_attack:
			AttackType.DNA:
				shot_timer = maxf(0.055, 0.13 / aggression)
				fire_dna_pair()
			AttackType.SPIRAL:
				shot_timer = maxf(0.06, 0.15 / aggression)
				fire_rotating_spiral()
			AttackType.FAN:
				shot_timer = maxf(0.16, 0.38 / aggression)
				fire_targeted_fans()
			AttackType.CROSS:
				shot_timer = maxf(0.09, 0.22 / aggression)
				fire_magnetic_cross()
			AttackType.BUTTER_CIRCLES:
				shot_timer = maxf(0.16, 0.34 / aggression)
				fire_butter_circles()
			AttackType.FIRE_LANES:
				shot_timer = maxf(0.28, 0.62 / aggression)
				fire_flame_lanes()
			AttackType.MAGNET_SPREAD:
				shot_timer = maxf(0.18, 0.40 / aggression)
				fire_magnet_spread()
			AttackType.TRI_DNA:
				shot_timer = maxf(0.07, 0.15 / aggression)
				fire_tri_dna()
			_:
				shot_timer = maxf(0.060, 0.14 / aggression)
				fire_gatling_shots()
	if state_timer <= 0.0:
		finish_attack()

func finish_attack() -> void:
	state = BossState.IDLE
	state_timer = maxf(0.26, 0.86 / aggression)
	velocity = Vector2.ZERO

func get_firing_attack_duration() -> float:
	match current_attack:
		AttackType.GATLING: return 1.35
		AttackType.FAN: return 1.25
		AttackType.CROSS: return 1.55
		AttackType.FIRE_LANES: return 1.85
		AttackType.BUTTER_CIRCLES, AttackType.MAGNET_SPREAD: return 1.55
		AttackType.TRI_DNA: return 1.75
		_: return 1.68

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

func fire_rotating_spiral() -> void:
	attack_rotation += 0.23 + 0.025 * float(boss_kind)
	var spoke_count := 3 if boss_kind != 3 else 4
	for spoke_index in range(spoke_count):
		var angle := attack_rotation + TAU * float(spoke_index) / float(spoke_count)
		var color := boss_color.lerp(Color.WHITE, 0.18 + 0.12 * float(spoke_index % 2))
		rpc("spawn_bullet_rpc", global_position, angle, 176.0 * minf(aggression, 2.25), color)

func fire_targeted_fans() -> void:
	for player in get_active_players():
		var center_angle := global_position.direction_to(player.global_position).angle()
		for spread_index in range(-2, 3):
			var angle := center_angle + float(spread_index) * 0.105
			rpc("spawn_bullet_rpc", global_position, angle, 218.0 * minf(aggression, 2.2), boss_color)

func fire_flame_wall() -> void:
	var target_angle := attack_direction.angle()
	var bullet_count := 19 + mini(8, bosses_defeated * 2)
	var safe_gap := randi_range(4, bullet_count - 5)
	for bullet_index in range(bullet_count):
		if absi(bullet_index - safe_gap) <= 1:
			continue
		var lateral := (float(bullet_index) - float(bullet_count) * 0.5) * 0.055
		rpc("spawn_bullet_rpc", global_position, target_angle + lateral, 190.0 * minf(aggression, 2.15), Color(1.0, 0.27, 0.06))
	rpc("spawn_particles_rpc", global_position, Color(1.0, 0.32, 0.06), 20)

func fire_magnetic_cross() -> void:
	attack_rotation += 0.16
	var spoke_count := 8 if is_enraged else 4
	for spoke_index in range(spoke_count):
		var angle := attack_rotation + TAU * float(spoke_index) / float(spoke_count)
		var alternating_speed := 142.0 if spoke_index % 2 == 0 else 208.0
		rpc("spawn_bullet_rpc", global_position, angle, alternating_speed * minf(aggression, 2.2), Color(0.35, 0.82, 1.0))

func fire_butter_circles() -> void:
	signature_step += 1
	attack_rotation += 0.19
	var ring_count := 2 if is_enraged else 1
	for ring_index in range(ring_count):
		var bullet_count := 12 + ring_index * 6
		var ring_offset := attack_rotation + float(ring_index) * PI / float(bullet_count)
		for bullet_index in range(bullet_count):
			var angle := ring_offset + TAU * float(bullet_index) / float(bullet_count)
			var speed_value := (138.0 + float(ring_index) * 52.0) * minf(aggression, 2.2)
			var butter_color := Color(1.0, 0.86, 0.20) if bullet_index % 2 == 0 else Color(1.0, 0.67, 0.08)
			rpc("spawn_bullet_rpc", global_position, angle, speed_value, butter_color)
	if signature_step % 2 == 0:
		rpc("spawn_particles_rpc", global_position, Color(1.0, 0.82, 0.16), 14)

func fire_flame_lanes() -> void:
	signature_step += 1
	var vertical := signature_step % 2 == 0
	var lane_count := 7
	var safe_lane := randi_range(1, lane_count - 2)
	for lane_index in range(lane_count):
		if lane_index == safe_lane:
			continue
		var lane_ratio := float(lane_index + 1) / float(lane_count + 1)
		if vertical:
			var x_position := lerpf(arena_bounds.position.x, arena_bounds.end.x, lane_ratio)
			rpc("spawn_bullet_rpc", Vector2(x_position, arena_bounds.position.y - 10.0), PI * 0.5, 148.0 * minf(aggression, 2.15), Color(1.0, 0.24, 0.04))
			rpc("spawn_bullet_rpc", Vector2(x_position, arena_bounds.end.y + 10.0), -PI * 0.5, 148.0 * minf(aggression, 2.15), Color(1.0, 0.58, 0.06))
		else:
			var y_position := lerpf(arena_bounds.position.y, arena_bounds.end.y, lane_ratio)
			rpc("spawn_bullet_rpc", Vector2(arena_bounds.position.x - 10.0, y_position), 0.0, 148.0 * minf(aggression, 2.15), Color(1.0, 0.24, 0.04))
			rpc("spawn_bullet_rpc", Vector2(arena_bounds.end.x + 10.0, y_position), PI, 148.0 * minf(aggression, 2.15), Color(1.0, 0.58, 0.06))

func fire_magnet_spread() -> void:
	signature_step += 1
	for player in get_active_players():
		var center_angle := global_position.direction_to(player.global_position).angle()
		var spread_step := 0.075 + 0.012 * float(signature_step % 3)
		for spread_index in range(-4, 5):
			var speed_value := (178.0 + float(absi(spread_index)) * 12.0) * minf(aggression, 2.2)
			var magnetic_color := Color(0.28, 0.84, 1.0) if spread_index % 2 == 0 else Color(0.72, 0.30, 1.0)
			rpc("spawn_bullet_rpc", global_position, center_angle + float(spread_index) * spread_step, speed_value, magnetic_color)

func fire_tri_dna() -> void:
	signature_step += 1
	attack_rotation += 0.27
	var speed_value := 158.0 * minf(aggression, 2.2)
	for arm_index in range(3):
		var arm_angle := attack_rotation + TAU * float(arm_index) / 3.0
		rpc("spawn_bullet_rpc", global_position, arm_angle, speed_value, Color(0.08, 0.96, 0.74))
		rpc("spawn_bullet_rpc", global_position, arm_angle + 0.16, speed_value * 0.92, Color(1.0, 0.22, 0.70))
		if signature_step % 3 == 0:
			rpc("spawn_bullet_rpc", global_position, arm_angle - 0.16, speed_value * 0.72, Color(0.72, 0.94, 1.0))

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
	var indicator_kind := 0 if attack_type == AttackType.SLIDE else 2 if attack_type in [AttackType.GATLING, AttackType.FAN, AttackType.WALL, AttackType.MAGNET_SPREAD] else 1
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
	if presentation and presentation.has_method("play_hit_squash"):
		presentation.call("play_hit_squash")

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
