extends CharacterBody2D

const LOOT_PICKUP := preload("res://Scenes/loot_pickup.tscn")

# --- Signals & Export Settings ---
@export_group("Movement Settings")
@export var speed: float = 85.0             # Snipers move slower
@export var preferred_distance: float = 300.0 # Stays far away from player

@export_group("Combat Settings")
@export var max_health: int = 8             # Fragile compared to standard enemy
@export var attack_cooldown: float = 2.2    # Longer interval between shots
@export var projectile_speed: float = 220.0 # Must match the bullet scene's speed
@export_range(0.0, 1.0) var coin_drop_chance := 1.0
@export_range(0.0, 1.0) var characteristic_drop_chance := 0.78
@export_range(0.0, 1.0) var health_drop_chance := 0.25
@export var bullet_scene: PackedScene
@export var hit_sound: AudioStream

@onready var sprite: Sprite2D = $Sprite2D
@onready var shoot_timer: Timer = get_node_or_null("ShootTimer")

var target_player: CharacterBody2D = null
var current_health: int
var is_dying: bool = false
var hit_sfx_player: AudioStreamPlayer2D
var knockback_velocity := Vector2.ZERO
var hit_squash_tween: Tween

func _enter_tree() -> void:
	set_multiplayer_authority(1)

func _ready() -> void:
	add_to_group("enemies")
	current_health = max_health
	
	# Setup audio player for hit sound
	hit_sfx_player = AudioStreamPlayer2D.new()
	hit_sfx_player.name = "HitSFXPlayer"
	if hit_sound:
		hit_sfx_player.stream = hit_sound
	add_child(hit_sfx_player)

	setup_shoot_timer()
	play_spawn_effects()

func play_spawn_effects() -> void:
	scale = Vector2.ZERO
	modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "scale", Vector2.ONE * 1.18, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.12)
	tween.chain().tween_property(self, "scale", Vector2.ONE, 0.10)

func setup_shoot_timer() -> void:
	if not shoot_timer:
		shoot_timer = Timer.new()
		shoot_timer.name = "ShootTimer"
		add_child(shoot_timer)

	shoot_timer.wait_time = attack_cooldown
	shoot_timer.timeout.connect(_on_shoot_timer_timeout)
	shoot_timer.start()

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority() or is_dying:
		return

	find_target_player()

	if target_player and is_instance_valid(target_player):
		var distance = global_position.distance_to(target_player.global_position)
		var direction = (target_player.global_position - global_position).normalized()

		# Sniper Positioning Logic: Back up if too close, approach if too far
		if distance < preferred_distance - 40.0:
			velocity = -direction * speed + knockback_velocity # Back away
		elif distance > preferred_distance + 40.0:
			velocity = direction * speed + knockback_velocity  # Move closer
		else:
			velocity = knockback_velocity # Hold position

		if sprite:
			sprite.flip_h = (direction.x < 0)
	else:
		velocity = knockback_velocity

	move_and_slide()
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 900.0 * delta)
	if not is_on_tower(24.0):
		fall_into_clouds()

func apply_knockback(force: Vector2) -> void:
	if not is_dying:
		knockback_velocity += force

func fall_into_clouds() -> void:
	if is_dying:
		return
	drop_loot_at_arena_edge()
	rpc("fall_into_clouds_rpc")

@rpc("authority", "call_local", "reliable")
func fall_into_clouds_rpc() -> void:
	if is_dying:
		return
	is_dying = true
	velocity = Vector2.ZERO
	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.45)
	tween.tween_property(self, "modulate:a", 0.0, 0.45)
	tween.finished.connect(queue_free)

func get_arena_bounds() -> Rect2:
	var bounds: Variant = get_meta("arena_bounds", Rect2(28, 30, 424, 220))
	return bounds if bounds is Rect2 else Rect2(28, 30, 424, 220)

func is_on_tower(edge_padding: float) -> bool:
	var bounds := get_arena_bounds()
	var radii := bounds.size * 0.5 + Vector2(edge_padding, edge_padding)
	var normalized_offset := (global_position - bounds.get_center()) / radii
	return normalized_offset.length_squared() <= 1.0

func find_target_player() -> void:
	if target_player and is_instance_valid(target_player):
		return

	var players = get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return

	var closest_dist: float = INF
	for p in players:
		if p is CharacterBody2D:
			var d = global_position.distance_to(p.global_position)
			if d < closest_dist:
				closest_dist = d
				target_player = p

func _on_shoot_timer_timeout() -> void:
	if not is_multiplayer_authority() or is_dying:
		return

	if not target_player or not is_instance_valid(target_player):
		return

	var fire_dir = get_intercept_direction(target_player)
	rpc("spawn_sniper_bullet_rpc", global_position, fire_dir.angle())

func get_intercept_direction(target: CharacterBody2D) -> Vector2:
	var offset := target.global_position - global_position
	# sync_velocity is replicated by the player scene, unlike CharacterBody2D.velocity.
	var target_velocity: Vector2 = target.get("sync_velocity")
	var a := target_velocity.length_squared() - projectile_speed * projectile_speed
	var b := 2.0 * offset.dot(target_velocity)
	var c := offset.length_squared()
	var time_to_hit := 0.0

	if is_zero_approx(a):
		if not is_zero_approx(b):
			time_to_hit = -c / b
	else:
		var discriminant := b * b - 4.0 * a * c
		if discriminant >= 0.0:
			var sqrt_discriminant := sqrt(discriminant)
			var first_time := (-b - sqrt_discriminant) / (2.0 * a)
			var second_time := (-b + sqrt_discriminant) / (2.0 * a)
			if first_time > 0.0 and second_time > 0.0:
				time_to_hit = min(first_time, second_time)
			else:
				time_to_hit = max(first_time, second_time)

	# If the player is moving too fast to intercept, aim directly at them instead.
	var aim_position := target.global_position + target_velocity * time_to_hit if time_to_hit > 0.0 else target.global_position
	return (aim_position - global_position).normalized()

@rpc("any_peer", "call_local", "reliable")
func spawn_sniper_bullet_rpc(spawn_pos: Vector2, angle: float) -> void:
	if bullet_scene:
		var bullet = bullet_scene.instantiate() as Node2D
		bullet.global_position = spawn_pos
		bullet.rotation = angle
		get_parent().add_child(bullet)

# --- COMBAT, SHADER & SFX HANDLERS ---

func take_damage(amount: int) -> void:
	if not is_multiplayer_authority() or is_dying:
		return

	current_health -= amount
	rpc("play_hit_effects_rpc")

	if current_health <= 0:
		drop_loot()
		rpc("die_with_dissolve_rpc")

func drop_loot() -> void:
	if randf() <= coin_drop_chance:
		rpc("spawn_loot_rpc", get_safe_loot_position(global_position), 0, "%s_Coin" % name)
	if randf() <= health_drop_chance:
		rpc("spawn_loot_rpc", get_safe_loot_position(global_position + Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))), 1, "%s_Health" % name)
	if randf() <= characteristic_drop_chance:
		rpc("spawn_loot_rpc", get_safe_loot_position(global_position + Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))), 2, "%s_Characteristic" % name)

func drop_loot_at_arena_edge() -> void:
	var drop_position := get_safe_loot_position(global_position)
	if randf() <= coin_drop_chance:
		rpc("spawn_loot_rpc", drop_position, 0, "%s_Coin" % name)
	if randf() <= health_drop_chance:
		rpc("spawn_loot_rpc", drop_position + Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0)), 1, "%s_Health" % name)
	if randf() <= characteristic_drop_chance:
		rpc("spawn_loot_rpc", drop_position, 2, "%s_Characteristic" % name)

func get_safe_loot_position(requested_position: Vector2) -> Vector2:
	var bounds := get_arena_bounds()
	var center := bounds.get_center()
	var radii := bounds.size * 0.5 - Vector2(18.0, 18.0)
	var offset := requested_position - center
	if offset == Vector2.ZERO:
		return center
	var distance_scale := sqrt((offset.x * offset.x) / (radii.x * radii.x) + (offset.y * offset.y) / (radii.y * radii.y))
	if distance_scale > 1.0:
		offset /= distance_scale
	return center + offset

@rpc("authority", "call_local", "reliable")
func spawn_loot_rpc(drop_position: Vector2, loot_type: int, loot_id: String) -> void:
	call_deferred("spawn_loot_deferred", drop_position, loot_type, loot_id)

func spawn_loot_deferred(drop_position: Vector2, loot_type: int, loot_id: String) -> void:
	if get_parent().get_node_or_null(loot_id):
		return
	var loot := LOOT_PICKUP.instantiate() as Node2D
	loot.name = loot_id
	loot.global_position = drop_position
	loot.call("configure", loot_type)
	get_parent().add_child(loot)

@rpc("any_peer", "call_local", "reliable")
func play_hit_effects_rpc() -> void:
	if hit_sfx_player and hit_sfx_player.stream:
		hit_sfx_player.play()

	# Trigger Shader Flash on the Sprite
	if sprite and sprite.material is ShaderMaterial:
		var mat = sprite.material as ShaderMaterial
		mat.set_shader_parameter("enabled", true)
		
		# Turn off flash after 0.12 seconds
		get_tree().create_timer(0.12).timeout.connect(func():
			if is_instance_valid(mat):
				mat.set_shader_parameter("enabled", false)
		)
	play_hit_squash()

func play_hit_squash() -> void:
	if not sprite:
		return
	if hit_squash_tween and hit_squash_tween.is_valid():
		hit_squash_tween.kill()
	hit_squash_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hit_squash_tween.tween_property(sprite, "scale", Vector2(0.70, 1.36), 0.035)
	hit_squash_tween.tween_property(sprite, "scale", Vector2(1.09, 0.93), 0.065)
	hit_squash_tween.tween_property(sprite, "scale", Vector2.ONE, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

@rpc("any_peer", "call_local", "reliable")
func die_with_dissolve_rpc() -> void:
	is_dying = true
	velocity = Vector2.ZERO
	
	var col = get_node_or_null("CollisionShape2D")
	if col:
		col.set_deferred("disabled", true)

	if sprite and sprite.material is ShaderMaterial:
		var mat = sprite.material as ShaderMaterial
		var tween = create_tween()
		mat.set_shader_parameter("dissolve_value", 1.0)
		tween.tween_property(mat, "shader_parameter/dissolve_value", 0.0, 0.8)
		tween.finished.connect(func(): queue_free())
	else:
		queue_free()
