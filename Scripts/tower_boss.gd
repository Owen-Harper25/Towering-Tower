extends CharacterBody2D

const ATTACK_INDICATOR := preload("res://Scripts/boss_attack_indicator.gd")
const IMPACT_TEXTURE := preload("res://Assets/plus particle.png")

enum AttackType { SLIDE_BASH, BULLET_RING, GATLING }
enum BossState { IDLE, WINDUP, SLIDING, GATLING }

@export var max_health := 260
@export var bullet_scene: PackedScene
@export var move_speed := 54.0
@export var slide_speed := 390.0
@export var hit_sound: AudioStream
@export var death_sound: AudioStream

@onready var sprite: Sprite2D = $Sprite2D

var current_health := 0
var player_count := 1
var target_player: CharacterBody2D
var is_dying := false
var state := BossState.IDLE
var current_attack := AttackType.SLIDE_BASH
var attack_index := 0
var state_timer := 1.4
var shot_timer := 0.0
var attack_direction := Vector2.RIGHT
var slide_hit_players: Dictionary = {}
var is_enraged := false
var health_bar_fill: ColorRect
var health_bar_label: Label
var health_bar_tween: Tween

func _enter_tree() -> void:
	set_multiplayer_authority(1)

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	play_spawn_effects()
	create_health_bar()
	if multiplayer.is_server():
		player_count = maxi(1, get_active_players().size())
		max_health *= player_count
		current_health = max_health
		rpc("configure_encounter_rpc", max_health, player_count)
	else:
		current_health = max_health
		update_boss_health_rpc(current_health, max_health, false)
	rpc("set_boss_color_rpc", BossState.IDLE)

func play_spawn_effects() -> void:
	scale = Vector2.ZERO
	modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "scale", Vector2.ONE * 1.25, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.18)
	tween.chain().tween_property(self, "scale", Vector2.ONE, 0.14)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority() or is_dying:
		return
	find_target_player()
	if not target_player or not is_instance_valid(target_player):
		velocity = Vector2.ZERO
		return
	match state:
		BossState.IDLE:
			handle_idle(delta)
		BossState.WINDUP:
			handle_windup(delta)
		BossState.SLIDING:
			handle_slide(delta)
		BossState.GATLING:
			handle_gatling(delta)

func handle_idle(delta: float) -> void:
	var to_target := target_player.global_position - global_position
	if to_target.length() > 112.0:
		velocity = to_target.normalized() * move_speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	state_timer -= delta
	if state_timer <= 0.0:
		begin_next_attack()

func begin_next_attack() -> void:
	current_attack = attack_index % 3
	attack_index += 1
	attack_direction = (target_player.global_position - global_position).normalized()
	if attack_direction == Vector2.ZERO:
		attack_direction = Vector2.RIGHT
	state = BossState.WINDUP
	state_timer = 0.68 / get_attack_speed_multiplier()
	velocity = Vector2.ZERO
	rpc("set_boss_color_rpc", BossState.WINDUP)
	match current_attack:
		AttackType.SLIDE_BASH:
			rpc("show_telegraph_rpc", AttackType.SLIDE_BASH, global_position, attack_direction, 154.0, 0.68)
		AttackType.BULLET_RING:
			rpc("show_telegraph_rpc", AttackType.BULLET_RING, global_position, Vector2.RIGHT, 58.0, 0.68)
		AttackType.GATLING:
			rpc("show_telegraph_rpc", AttackType.GATLING, global_position, attack_direction, 170.0, 0.68)

func handle_windup(delta: float) -> void:
	state_timer -= delta
	if state_timer > 0.0:
		return
	match current_attack:
		AttackType.SLIDE_BASH:
			state = BossState.SLIDING
			state_timer = 0.46 / get_attack_speed_multiplier()
			slide_hit_players.clear()
			rpc("set_boss_color_rpc", BossState.SLIDING)
			rpc("spawn_boss_particles_rpc", global_position, Color(1.0, 0.20, 0.10), 12, 34.0, 0.95)
		AttackType.BULLET_RING:
			fire_ring()
			finish_attack()
		AttackType.GATLING:
			state = BossState.GATLING
			state_timer = 1.55
			shot_timer = 0.0
			rpc("set_boss_color_rpc", BossState.GATLING)

func handle_slide(delta: float) -> void:
	velocity = attack_direction * slide_speed
	move_and_slide()
	damage_players_hit_by_slide()
	state_timer -= delta
	if state_timer <= 0.0:
		finish_attack()

func handle_gatling(delta: float) -> void:
	velocity = Vector2.ZERO
	state_timer -= delta
	shot_timer -= delta
	if shot_timer <= 0.0:
		shot_timer = 0.13 / get_attack_speed_multiplier()
		for player in get_active_players():
			var aim := (player.global_position - global_position).normalized()
			var spread := randf_range(-0.075, 0.075)
			rpc("spawn_boss_bullet_rpc", global_position, aim.angle() + spread, 285.0)
			rpc("spawn_boss_particles_rpc", global_position + aim * 12.0, Color(1.0, 0.46, 0.08), 3, 12.0, 0.42)
	if state_timer <= 0.0:
		finish_attack()

func finish_attack() -> void:
	state = BossState.IDLE
	state_timer = 1.15 / get_attack_speed_multiplier()
	velocity = Vector2.ZERO
	rpc("set_boss_color_rpc", BossState.IDLE)

func damage_players_hit_by_slide() -> void:
	for collision_index in range(get_slide_collision_count()):
		var collision := get_slide_collision(collision_index)
		var hit_player := collision.get_collider() as CharacterBody2D
		if not hit_player or not hit_player.has_method("receive_boss_bash_rpc"):
			continue
		var player_id := hit_player.get_multiplayer_authority()
		if slide_hit_players.has(player_id):
			continue
		slide_hit_players[player_id] = true
		var knockback := attack_direction * 230.0
		if player_id == multiplayer.get_unique_id():
			hit_player.call("receive_boss_bash_rpc", 2, knockback)
		else:
			hit_player.rpc_id(player_id, "receive_boss_bash_rpc", 2, knockback)

func fire_ring() -> void:
	rpc("spawn_boss_particles_rpc", global_position, Color(1.0, 0.78, 0.10), 18, 42.0, 0.82)
	for index in range(18):
		var angle := TAU * float(index) / 18.0
		rpc("spawn_boss_bullet_rpc", global_position, angle, 175.0)

func find_target_player() -> void:
	var closest_distance := INF
	target_player = null
	for player in get_tree().get_nodes_in_group("players"):
		var candidate := player as CharacterBody2D
		if not candidate:
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < closest_distance:
			closest_distance = distance
			target_player = candidate

func get_active_players() -> Array[CharacterBody2D]:
	var active_players: Array[CharacterBody2D] = []
	for player in get_tree().get_nodes_in_group("players"):
		var candidate := player as CharacterBody2D
		if candidate and is_instance_valid(candidate):
			active_players.append(candidate)
	return active_players

func get_attack_speed_multiplier() -> float:
	return 1.45 if is_enraged else 1.0

@rpc("authority", "call_local", "reliable")
func show_telegraph_rpc(attack_type: int, origin: Vector2, direction: Vector2, size_value: float, duration: float) -> void:
	var indicator := ATTACK_INDICATOR.new() as Node2D
	indicator.global_position = origin
	indicator.rotation = direction.angle()
	match attack_type:
		AttackType.SLIDE_BASH:
			indicator.call("configure", 0, size_value, 0.0, 34.0, duration)
		AttackType.BULLET_RING:
			indicator.call("configure", 1, 0.0, size_value, 0.0, duration)
		AttackType.GATLING:
			indicator.call("configure", 2, size_value, 0.0, 22.0, duration)
	get_parent().add_child(indicator)

@rpc("authority", "call_local", "reliable")
func set_boss_color_rpc(new_state: int) -> void:
	if not sprite:
		return
	match new_state:
		BossState.IDLE:
			sprite.modulate = Color(0.88, 0.18, 0.62) if is_enraged else Color(0.45, 0.72, 1.0)
		BossState.WINDUP:
			sprite.modulate = Color(1.0, 0.26, 0.54) if is_enraged else Color(1.0, 0.78, 0.18)
		BossState.SLIDING:
			sprite.modulate = Color(1.0, 0.08, 0.20) if is_enraged else Color(1.0, 0.25, 0.18)
		BossState.GATLING:
			sprite.modulate = Color(1.0, 0.12, 0.45) if is_enraged else Color(1.0, 0.42, 0.08)

@rpc("authority", "call_local", "reliable")
func spawn_boss_bullet_rpc(spawn_position: Vector2, angle: float, projectile_speed: float) -> void:
	if not bullet_scene:
		return
	var bullet := bullet_scene.instantiate() as Node2D
	bullet.global_position = spawn_position
	bullet.rotation = angle
	bullet.set("speed", projectile_speed)
	bullet.set("knockback_force", 72.0)
	bullet.set("shooter", self)
	get_parent().add_child(bullet)

func take_damage(amount: int) -> void:
	if not is_multiplayer_authority() or is_dying:
		return
	current_health -= amount
	rpc("update_boss_health_rpc", current_health, max_health, is_enraged)
	rpc("play_boss_hit_feedback_rpc")
	if not is_enraged and current_health > 0 and current_health <= max_health / 2:
		is_enraged = true
		rpc("enter_rage_rpc")
		rpc("update_boss_health_rpc", current_health, max_health, true)
		rpc("set_boss_color_rpc", state)
	if current_health <= 0:
		rpc("die_rpc")

func create_health_bar() -> void:
	var health_layer := CanvasLayer.new()
	health_layer.layer = 40
	var container := Control.new()
	container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	container.position = Vector2(-130.0, 10.0)
	container.size = Vector2(260.0, 26.0)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backing := ColorRect.new()
	backing.color = Color(0.035, 0.02, 0.07, 0.92)
	backing.position = Vector2(0.0, 12.0)
	backing.size = Vector2(260.0, 12.0)
	container.add_child(backing)
	health_bar_fill = ColorRect.new()
	health_bar_fill.color = Color(0.32, 0.78, 1.0, 1.0)
	health_bar_fill.position = Vector2(2.0, 14.0)
	health_bar_fill.size = Vector2(256.0, 8.0)
	container.add_child(health_bar_fill)
	health_bar_label = Label.new()
	health_bar_label.position = Vector2(0.0, -2.0)
	health_bar_label.size = Vector2(260.0, 14.0)
	health_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health_bar_label.add_theme_font_size_override("font_size", 10)
	container.add_child(health_bar_label)
	health_layer.add_child(container)
	add_child(health_layer)

@rpc("authority", "call_local", "reliable")
func configure_encounter_rpc(health_maximum: int, team_size: int) -> void:
	max_health = health_maximum
	player_count = team_size
	current_health = health_maximum
	update_boss_health_rpc(current_health, max_health, false)

@rpc("authority", "call_local", "reliable")
func update_boss_health_rpc(new_health: int, health_maximum: int, enraged: bool) -> void:
	is_enraged = enraged
	if not health_bar_fill or not health_bar_label or health_maximum <= 0:
		return
	var health_ratio := clampf(float(new_health) / float(health_maximum), 0.0, 1.0)
	var target_width := 256.0 * health_ratio
	if health_bar_tween and health_bar_tween.is_valid():
		health_bar_tween.kill()
	health_bar_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	health_bar_tween.tween_property(health_bar_fill, "size:x", target_width, 0.18)
	health_bar_fill.color = Color(1.0, 0.16, 0.52) if enraged else Color(0.32, 0.78, 1.0)
	health_bar_label.text = "TOWER WARDEN  //  ENRAGED" if enraged else "TOWER WARDEN"

@rpc("authority", "call_local", "reliable")
func play_boss_hit_feedback_rpc() -> void:
	play_one_shot(hit_sound, global_position, -7.0)
	spawn_boss_particles(global_position, Color(0.75, 0.92, 1.0), 7, 19.0, 0.50)
	var hit_tween := create_tween()
	hit_tween.tween_property(self, "scale", Vector2.ONE * 1.12, 0.05)
	hit_tween.tween_property(self, "scale", Vector2.ONE, 0.10)

@rpc("authority", "call_local", "reliable")
func enter_rage_rpc() -> void:
	is_enraged = true
	spawn_boss_particles(global_position, Color(1.0, 0.10, 0.48), 24, 54.0, 1.10)
	var rage_tween := create_tween()
	rage_tween.tween_property(self, "scale", Vector2.ONE * 1.22, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rage_tween.tween_property(self, "scale", Vector2.ONE, 0.18)

@rpc("authority", "call_local", "reliable")
func spawn_boss_particles_rpc(origin: Vector2, color: Color, count: int, distance: float, particle_scale: float) -> void:
	spawn_boss_particles(origin, color, count, distance, particle_scale)

func spawn_boss_particles(origin: Vector2, color: Color, count: int, distance: float, particle_scale: float) -> void:
	var burst := Node2D.new()
	burst.global_position = origin
	get_parent().add_child(burst)
	for index in range(count):
		var particle := Sprite2D.new()
		particle.texture = IMPACT_TEXTURE
		particle.modulate = color
		particle.scale = Vector2.ONE * particle_scale * randf_range(0.65, 1.15)
		burst.add_child(particle)
		var direction := Vector2.from_angle(randf_range(0.0, TAU))
		var tween := burst.create_tween().set_parallel()
		tween.tween_property(particle, "position", direction * randf_range(distance * 0.45, distance), 0.23)
		tween.tween_property(particle, "scale", Vector2.ZERO, 0.23)
		tween.tween_property(particle, "modulate:a", 0.0, 0.23)
	get_tree().create_timer(0.25).timeout.connect(burst.queue_free)

func play_one_shot(stream: AudioStream, sound_position: Vector2, volume: float = 0.0) -> void:
	if not stream:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = volume
	player.global_position = sound_position
	get_parent().add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

@rpc("authority", "call_local", "reliable")
func die_rpc() -> void:
	if is_dying:
		return
	is_dying = true
	velocity = Vector2.ZERO
	play_one_shot(death_sound, global_position, -2.0)
	spawn_boss_particles(global_position, Color(1.0, 0.20, 0.12), 32, 70.0, 1.25)
	if health_bar_label:
		health_bar_label.text = "TOWER WARDEN  //  DEFEATED"
	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.42)
	tween.tween_property(self, "modulate:a", 0.0, 0.42)
	tween.finished.connect(queue_free)
