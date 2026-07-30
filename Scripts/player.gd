extends CharacterBody2D

# --- Signals ---
signal health_changed(new_health: int, max_health: int)
signal player_died()
signal player_downed()
signal player_revived()

# --- Network & Identity ---
@export var player_name: String = "":
	set(value):
		player_name = value.to_upper()
		if character_name:
			character_name.text = player_name
			character_name.visible = not is_multiplayer_authority()
@onready var hud: CanvasLayer = get_node_or_null("/root/Main/HUD")


# --- Movement & Roll Configuration ---
@export_group("Movement Settings")
@export var input_dir: Vector2 = Vector2.ZERO
@export var speed: float = 180.0
@export var roll_speed: float = 330.0
@export var roll_duration: float = 0.30
@export var roll_iframe_duration: float = 0.28
@export var fire_cooldown: float = 0.16
@export var fall_recovery_time: float = 1.75
@export var fall_dash_speed: float = 420.0
@onready var shootsfx: AudioStreamPlayer2D = get_node_or_null("/root/Main/SFX/Shoot")
@onready var hurtsfx: AudioStreamPlayer2D = get_node_or_null("/root/Main/SFX/Hurt")
@onready var menusfx: AudioStreamPlayer2D = get_node_or_null("/root/Main/SFX/Menu")
@export var sync_velocity: Vector2 = Vector2.ZERO

# --- Health & Revive Settings ---
@export_group("Combat Settings")
@export var max_health: int = 6
@export var invincibility_duration: float = 1.0
@export var bullet_scene: PackedScene

# --- Nodes ---
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var camera: Camera2D = $Camera2D
@onready var character_name: Label = $CharacterName
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var muzzle: Node2D = $WeaponPivot/Muzzle
@onready var gun_body: Polygon2D = $WeaponPivot/GunBody
@onready var gun_accent: Polygon2D = $WeaponPivot/GunAccent

# --- Internal State ---
var current_health: int
var is_rolling: bool = false
var is_invulnerable: bool = false
var roll_direction: Vector2 = Vector2.DOWN
var aim_direction: Vector2 = Vector2.RIGHT
var next_shot_time := 0.0
var arena_bounds := Rect2(28, 30, 424, 220)
var is_falling := false
var fall_time_remaining := 0.0
var coins := 0
var weapon_is_drawn := false

# --- Downed & Revive State (Nightreign Style) ---
@export var is_downed: bool = false
var down_count: int = 0
var revive_hp_current: float = 0.0
var revive_hp_max: float = 0.0

# --- Death Timer Settings ---
@export var death_timer_max: float = 15.0      # Total time before player dies when downed
@export var pause_on_hit_duration: float = 1.5 # Seconds timer pauses when hit by an ally
@export var enemy_hit_death_time_penalty: float = 2.5

var death_timer_current: float = 0.0
var pause_timer: float = 0.0

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	max_health += MetaProgression.get_level("vitality") * 2
	fire_cooldown = maxf(0.07, fire_cooldown - MetaProgression.get_level("rapid_fire") * 0.015)
	current_health = max_health
	if is_multiplayer_authority():
		camera.make_current()
		camera.enabled = true
		player_name = Steam.getPersonaName()
		rpc("sync_name", player_name)
		
		if character_name:
			character_name.visible = false

		# Initialize HUD for local player
		if hud:
			hud.setup_hearts(max_health, current_health)
			health_changed.connect(hud.update_hearts)
	else:
		camera.enabled = false
		camera.process_mode = Node.PROCESS_MODE_DISABLED
		
		if character_name:
			character_name.visible = true

@rpc("any_peer", "call_local", "reliable")
func sync_name(new_name: String) -> void:
	player_name = new_name

func _physics_process(delta: float) -> void:
	# --- RUN ON ALL PEERS ---
	if is_downed:
		handle_death_timer(delta) # Must run on remote peers so their local death timers tick down and redraw!

	# --- RUN ONLY ON MULTIPLAYER AUTHORITY ---
	if is_multiplayer_authority():
		if current_health <= 0 and not is_downed:
			return

		if is_falling:
			handle_falling(delta)
		elif is_downed:
			handle_crawling_movement()
		elif not is_rolling:
			handle_movement_and_actions()
		else:
			handle_roll_physics()

		if not is_falling:
			sync_velocity = velocity
			move_and_slide()
			if not is_on_tower():
				rpc("start_falling_rpc")

	update_animations()
	update_weapon_aim()

func handle_death_timer(delta: float) -> void:
	if pause_timer > 0.0:
		pause_timer -= delta
		queue_redraw() # Redraw to transition color back when pause ends
		return

	# Countdown to death on all clients
	death_timer_current -= delta
	queue_redraw()

	# Authority determines exact moment of death
	if is_multiplayer_authority() and death_timer_current <= 0.0:
		rpc("player_fully_died_rpc")

@rpc("any_peer", "call_local", "reliable")
func player_fully_died_rpc() -> void:
	is_downed = false
	sprite.play("death")
	player_died.emit()
	if is_multiplayer_authority():
		var main := get_tree().get_first_node_in_group("main")
		if main and main.has_method("return_party_to_lobby"):
			main.return_party_to_lobby()
	# Add any death despawn/spectate logic here

# --- Movement & Input Handling ---
func handle_movement_and_actions() -> void:
	input_dir = Vector2(
		Input.get_axis("Left", "Right"),
		Input.get_axis("Up", "Down")
	).normalized()

	aim_direction = (get_global_mouse_position() - global_position).normalized()

	if Input.is_action_just_pressed("DodgeRoll") and input_dir != Vector2.ZERO:
		rpc("start_dodge_roll_rpc", input_dir)
		return

	velocity = input_dir * speed

	if Input.is_action_pressed("Shoot"):
		shoot()

func handle_crawling_movement() -> void:
	input_dir = Vector2(
		Input.get_axis("Left", "Right"),
		Input.get_axis("Up", "Down")
	).normalized()
	
	# Slow crawl movement speed
	velocity = input_dir * (speed * 0.25)

func handle_falling(delta: float) -> void:
	fall_time_remaining -= delta
	input_dir = Vector2(
		Input.get_axis("Left", "Right"),
		Input.get_axis("Up", "Down")
	).normalized()
	velocity = input_dir * speed
	if Input.is_action_just_pressed("DodgeRoll") and input_dir != Vector2.ZERO:
		velocity = input_dir * fall_dash_speed

	move_and_slide()
	sync_velocity = velocity
	var fall_progress := 1.0 - fall_time_remaining / fall_recovery_time
	sprite.scale = Vector2.ONE * lerpf(1.0, 0.45, clampf(fall_progress, 0.0, 1.0))
	sprite.modulate.a = lerpf(1.0, 0.25, clampf(fall_progress, 0.0, 1.0))

	if is_on_tower():
		rpc("land_from_fall_rpc")
	elif fall_time_remaining <= 0.0:
		rpc("rescue_from_fall_rpc")

@rpc("any_peer", "call_local", "reliable")
func start_falling_rpc() -> void:
	if is_falling or is_downed:
		return
	is_falling = true
	is_rolling = false
	fall_time_remaining = fall_recovery_time

@rpc("any_peer", "call_local", "reliable")
func land_from_fall_rpc() -> void:
	is_falling = false
	fall_time_remaining = 0.0
	velocity = Vector2.ZERO
	sprite.scale = Vector2.ONE
	sprite.modulate.a = 1.0

@rpc("any_peer", "call_local", "reliable")
func rescue_from_fall_rpc() -> void:
	land_from_fall_rpc()
	global_position = find_safe_respawn_position()
	if is_multiplayer_authority():
		current_health = max(1, current_health - 2)
		health_changed.emit(current_health, max_health)
		rpc("start_invulnerability_rpc", invincibility_duration)

func find_safe_respawn_position() -> Vector2:
	var center := arena_bounds.get_center()
	var candidates: Array[Vector2] = [
		center,
		center + Vector2(64, 0),
		center + Vector2(-64, 0),
		center + Vector2(0, 48),
		center + Vector2(0, -48),
	]
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemies")
	for candidate in candidates:
		var is_clear := true
		for enemy_node in enemies:
			var enemy := enemy_node as Node2D
			if is_instance_valid(enemy) and candidate.distance_to(enemy.global_position) < 52.0:
				is_clear = false
				break
		if is_clear:
			return candidate
	return center

func is_on_tower() -> bool:
	if get_tree().get_first_node_in_group("safe_lobby"):
		return true
	var arena: Node = get_tree().get_first_node_in_group("tower_arena")
	if arena and arena.has_method("is_on_tower"):
		var is_safe: bool = arena.call("is_on_tower", global_position)
		return is_safe
	var normalized_offset := (global_position - arena_bounds.get_center()) / (arena_bounds.size * 0.5)
	return normalized_offset.length_squared() <= 1.0

# --- Dodge Roll System ---
@rpc("any_peer", "call_local", "reliable")
func start_dodge_roll_rpc(dir: Vector2) -> void:
	if is_downed:
		return
	is_rolling = true
	is_invulnerable = true
	roll_direction = dir
	
	# Temporarily disable enemy bullet collision layer (e.g., Layer 3)
	var original_mask = collision_mask
	set_collision_mask_value(4, false) # Assume Layer 3 = Enemy Bullets
	set_collision_mask_value(3, false) # Assume Layer 3 = Enemy Bullets
	if menusfx: menusfx.play()
	
	if sprite.sprite_frames.has_animation("roll"):
		sprite.play("roll")

	var iframe_timer = get_tree().create_timer(roll_iframe_duration)
	iframe_timer.timeout.connect(func(): is_invulnerable = false)
	
	var roll_timer = get_tree().create_timer(roll_duration)
	roll_timer.timeout.connect(func(): 
		is_rolling = false
		collision_mask = original_mask # Restore normal collision
	)

func handle_roll_physics() -> void:
	velocity = roll_direction * roll_speed

# --- Weapon & Shooting System ---
func update_weapon_aim() -> void:
	if weapon_pivot:
		set_weapon_drawn(not is_downed and not is_falling and not is_rolling and is_wave_active())
		var weapon_direction := aim_direction if is_multiplayer_authority() else sync_velocity.normalized()
		if weapon_direction == Vector2.ZERO:
			weapon_direction = Vector2.RIGHT
		var hover_offset := weapon_direction * 16.0 + Vector2(0.0, sin(Time.get_ticks_msec() * 0.006) * 2.0)
		weapon_pivot.position = weapon_pivot.position.lerp(hover_offset, 0.24)
		var target_angle = weapon_direction.angle()
		weapon_pivot.rotation = target_angle
		var vertical_flip := -1.0 if weapon_direction.x < 0.0 else 1.0
		gun_body.scale.y = vertical_flip
		gun_accent.scale.y = vertical_flip

func is_wave_active() -> bool:
	if get_tree().get_first_node_in_group("safe_lobby"):
		return false
	var arena: Node = get_tree().get_first_node_in_group("tower_arena")
	if arena and arena.has_method("is_wave_active"):
		var active: bool = arena.call("is_wave_active")
		return active
	return true

func set_weapon_drawn(should_draw: bool) -> void:
	if weapon_is_drawn == should_draw:
		return
	weapon_is_drawn = should_draw
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if should_draw:
		weapon_pivot.visible = true
		weapon_pivot.scale = Vector2.ZERO
		tween.tween_property(weapon_pivot, "scale", Vector2.ONE, 0.16)
	else:
		tween.tween_property(weapon_pivot, "scale", Vector2.ZERO, 0.10)
		tween.tween_callback(func():
			if not weapon_is_drawn:
				weapon_pivot.visible = false
		)

func shoot() -> void:
	if is_downed or not is_wave_active() or not bullet_scene or Time.get_ticks_msec() / 1000.0 < next_shot_time:
		return
	next_shot_time = Time.get_ticks_msec() / 1000.0 + fire_cooldown
		
	var spawn_pos = muzzle.global_position if muzzle else global_position
	var fire_angle = aim_direction.angle()
	if muzzle:
		var recoil_tween := create_tween()
		muzzle.scale = Vector2.ONE * 1.45
		recoil_tween.tween_property(muzzle, "scale", Vector2.ONE, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	rpc("spawn_bullet_rpc", spawn_pos, fire_angle, multiplayer.get_unique_id())

@rpc("any_peer", "call_local", "reliable")
func spawn_bullet_rpc(spawn_pos: Vector2, angle: float, shooter: int) -> void:
	if bullet_scene:
		var bullet = bullet_scene.instantiate() as Area2D
		bullet.global_position = spawn_pos
		bullet.rotation = angle
		bullet.set("damage", 2 + MetaProgression.get_level("damage"))
		if shootsfx: shootsfx.play()
		
		if "shooter_id" in bullet:
			bullet.shooter_id = shooter
			
		get_parent().add_child(bullet)

# --- Health, Downed & Revive Mechanics ---
func take_damage(amount: int) -> void:
	if not is_multiplayer_authority() or is_invulnerable:
		return

	if is_downed:
		return

	current_health -= amount
	current_health = max(0, current_health)
	health_changed.emit(current_health, max_health)
	if hurtsfx: hurtsfx.play()
	
	# RPC the invulnerability visually across all peers
	rpc("start_invulnerability_rpc", invincibility_duration)

	if current_health <= 0:
		rpc("enter_downed_state_rpc")

func heal(amount: int) -> void:
	if is_downed or current_health >= max_health:
		return
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

func collect_coins(amount: int) -> void:
	coins += amount
	if is_multiplayer_authority():
		MetaProgression.add_currency(amount)
	if hud and hud.has_method("update_coins"):
		hud.update_coins(coins)

@rpc("any_peer", "call_local", "reliable")
func enter_downed_state_rpc() -> void:
	is_downed = true
	down_count += 1
	death_timer_current = death_timer_max
	pause_timer = 0.0
	
	match down_count:
		1: revive_hp_max = 30.0
		2: revive_hp_max = 60.0
		_: revive_hp_max = 120.0
			
	revive_hp_current = revive_hp_max
	player_downed.emit()
	
	if sprite.sprite_frames.has_animation("downed"):
		sprite.play("downed")

	queue_redraw()

# Called when an ally attacks a downed player to revive them
func try_receive_revive_hit(amount: float) -> bool:
	if not is_downed or not is_multiplayer_authority():
		return false
	rpc("receive_revive_hit_rpc", amount)
	return true

@rpc("any_peer", "call_local", "reliable")
func receive_revive_hit_rpc(amount: float) -> void:
	if not is_downed:
		return

	revive_hp_current -= amount
	pause_timer = pause_on_hit_duration # Set pause timer locally across all clients
	queue_redraw()

	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(0.3, 1.0, 0.3), 0.05)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.05)

	# Authority validates when player gets fully revived
	if is_multiplayer_authority() and revive_hp_current <= 0:
		rpc("sync_revive_player_rpc")

func try_receive_enemy_hit(damage: int) -> bool:
	if not is_downed or not is_multiplayer_authority():
		return false
	var penalty := enemy_hit_death_time_penalty * maxf(1.0, float(damage))
	rpc("receive_enemy_hit_rpc", penalty)
	return true

@rpc("any_peer", "call_local", "reliable")
func receive_enemy_hit_rpc(penalty: float) -> void:
	if not is_downed:
		return
	pause_timer = 0.0
	death_timer_current = maxf(0.0, death_timer_current - penalty)
	queue_redraw()
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1.0, 0.28, 0.28), 0.06)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.08)
@rpc("any_peer", "call_local", "reliable")

func sync_revive_player_rpc() -> void:
	revive_player()

func revive_player() -> void:
	is_downed = false
	current_health = int(max_health * 0.5)
	health_changed.emit(current_health, max_health)
	player_revived.emit()
	
	if sprite.sprite_frames.has_animation("Idle"):
		sprite.play("Idle")

	queue_redraw()

@rpc("any_peer", "call_local", "reliable")
func reset_for_lobby_rpc() -> void:
	is_downed = false
	is_falling = false
	is_rolling = false
	death_timer_current = 0.0
	pause_timer = 0.0
	revive_hp_current = 0.0
	current_health = max_health
	if sprite.sprite_frames.has_animation("Idle"):
		sprite.play("Idle")
	health_changed.emit(current_health, max_health)
	queue_redraw()

@rpc("any_peer", "call_local", "reliable")
func start_invulnerability_rpc(duration: float) -> void:
	is_invulnerable = true
	var original_enemy_mask := get_collision_mask_value(2)
	set_collision_mask_value(2, false)
	
	if not sprite or not (sprite.material is ShaderMaterial):
		get_tree().create_timer(duration).timeout.connect(func(): is_invulnerable = false)
		return

	var mat = sprite.material as ShaderMaterial
	
	# Quick initial hit flash (0.15s)
	mat.set_shader_parameter("enabled", true)
	get_tree().create_timer(0.15).timeout.connect(func():
		if is_instance_valid(mat):
			mat.set_shader_parameter("enabled", false)
	)

	# Optional: Continuous alpha pulsing while invulnerable
	var tween = create_tween().set_loops(int(duration / 0.1))
	tween.tween_property(sprite, "modulate:a", 0.3, 0.05)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.05)

	get_tree().create_timer(duration).timeout.connect(func():
		is_invulnerable = false
		set_collision_mask_value(2, original_enemy_mask)
		if tween and tween.is_running():
			tween.kill()
		if sprite:
			sprite.modulate.a = 1.0
			if sprite.material is ShaderMaterial:
				(sprite.material as ShaderMaterial).set_shader_parameter("enabled", false)
	)

# --- Visuals & Animations ---
func update_animations() -> void:
	if is_downed:
		if sprite.animation != "downed" and sprite.sprite_frames.has_animation("downed"):
			sprite.play("downed")
		return

	if is_rolling:
		return

	# Use sync_velocity so all remote peers see the correct walking/facing animation
	if sync_velocity.length() > 0.1:
		if sprite.animation != "move":
			sprite.play("move")
		if sync_velocity.x != 0:
			sprite.flip_h = (sync_velocity.x < 0)
	else:
		if sprite.animation != "Idle":
			sprite.play("Idle")

func _draw() -> void:
	if not is_downed or revive_hp_max <= 0:
		return

	# --- 1. Outer Ring: Revive Progress ---
	var outer_radius := 24.0
	var outer_thickness := 3.0
	var outer_bg := Color(0.2, 0.2, 0.2, 0.6)
	var outer_fill := Color(0.2, 0.8, 1.0, 0.9) # Cyan/blue

	draw_arc(Vector2.ZERO, outer_radius, 0, TAU, 32, outer_bg, outer_thickness)

	var revive_progress: float = clamp(1.0 - (revive_hp_current / revive_hp_max), 0.0, 1.0)
	if revive_progress > 0.0:
		var start_angle: float = -PI / 2.0
		var end_angle: float = start_angle + (revive_progress * TAU)
		draw_arc(Vector2.ZERO, outer_radius, start_angle, end_angle, 32, outer_fill, outer_thickness + 1.0)

	# --- 2. Inner Ring: Death Timer ---
	var inner_radius := 16.0
	var inner_thickness := 2.5
	var inner_bg := Color(0.1, 0.1, 0.1, 0.5)
	
	# Color turns yellow while paused on hit, red while ticking down
	var inner_fill := Color(1.0, 0.8, 0.2, 0.9) if pause_timer > 0 else Color(1.0, 0.25, 0.25, 0.9)

	draw_arc(Vector2.ZERO, inner_radius, 0, TAU, 32, inner_bg, inner_thickness)

	var death_progress: float = clamp(death_timer_current / death_timer_max, 0.0, 1.0)
	if death_progress > 0.0:
		var start_angle: float = -PI / 2.0
		var end_angle: float = start_angle + (death_progress * TAU)
		draw_arc(Vector2.ZERO, inner_radius, start_angle, end_angle, 32, inner_fill, inner_thickness)
		
