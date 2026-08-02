extends CharacterBody2D

const LOW_HEALTH_IRIS_SHADER := preload("res://Shaders/low_health_iris.gdshader")
const SURVIVAL_TEAM_MATERIAL := preload("res://Shaders/outlineshader.tres")
const SURVIVAL_DEATH_SFX := preload("res://SFX/game over.mp3")
const COSMETICS := preload("res://Scripts/cosmetic_catalog.gd")
const BOONS := preload("res://Scripts/boon_catalog.gd")

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
@export var bullet_spread_degrees: float = 2.25
@export var firing_recoil_force: float = 24.0
@export var weapon_kick_distance: float = 6.0
@export var fall_recovery_time: float = 1.75
@export var fall_dash_speed: float = 420.0
@export var fall_dash_duration: float = 0.34
@export var fall_drift_duration: float = 0.28
@export_group("Movement Trail Settings")
@export var walk_dust_interval := 0.14
@export var dash_trail_interval := 0.035
@export var walk_dust_lifetime := 0.24
@export var dash_trail_lifetime := 0.20
@export_group("Camera Settings")
@export var aim_camera_lead_distance: float = 22.0
@export var aim_camera_lead_smoothness: float = 7.0
@export var aim_camera_deadzone: float = 8.0
@onready var shootsfx: AudioStreamPlayer2D = get_node_or_null("/root/Main/SFX/Shoot")
@onready var hurtsfx: AudioStreamPlayer2D = get_node_or_null("/root/Main/SFX/Hurt")
@onready var menusfx: AudioStreamPlayer2D = get_node_or_null("/root/Main/SFX/Menu")
@export var sync_velocity: Vector2 = Vector2.ZERO
@export var sync_aim_direction: Vector2 = Vector2.RIGHT
@export var equipped_head_cosmetic := "":
	set(value):
		equipped_head_cosmetic = value
		if is_node_ready():
			apply_cosmetic_visuals()
@export var equipped_back_cosmetic := "":
	set(value):
		equipped_back_cosmetic = value
		if is_node_ready():
			apply_cosmetic_visuals()

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
@onready var cosmetic_head: Sprite2D = $CosmeticHead
@onready var cosmetic_back: Sprite2D = $CosmeticBack

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
var fall_dash_used := false
var fall_dash_active := false
var fall_dash_direction := Vector2.ZERO
var fall_drift_remaining := 0.0
var fall_drift_velocity := Vector2.ZERO
var coins := 0
var weapon_is_drawn := false
var firing_recoil_velocity := Vector2.ZERO
var weapon_recoil_offset := Vector2.ZERO
var is_teleporting := false
var teleport_visual_tween: Tween
var base_max_health := 0
var base_fire_cooldown := 0.0
var base_speed := 0.0
var base_roll_speed := 0.0
var base_invincibility_duration := 0.0
var base_fall_recovery_time := 0.0
var boon_damage_bonus := 0
var boon_health_bonus := 0
var boon_fire_rate_bonus := 0.0
var boon_move_speed_bonus := 0.0
var boon_bullet_speed_bonus := 0.0
var boon_knockback_bonus := 0.0
var boon_multishot_chance := 0.0
var boon_accuracy_bonus := 0.0
var boon_invulnerability_bonus := 0.0
var boon_fall_grace_bonus := 0.0
var boon_roll_speed_bonus := 0.0
var boon_critical_chance := 0.0
var acquired_boons: Array[String] = []
var ui_input_locked := false
var in_survival_mode := false
var is_survival_ghost := false
var survival_bounds := Rect2(170, 20, 560, 560)
var survival_revive_progress := 0.0
var survival_revive_sync_elapsed := 0.0
var original_collision_layer := 1
var original_collision_mask := 11
var survival_ghost_ui: CanvasLayer
@export var survival_revive_duration := 2.6
var survival_team_id := -1
var survival_team_size := 1
var survival_team_color := Color.WHITE
var original_sprite_material: Material

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
var low_health_iris_material: ShaderMaterial
var low_health_lowpass: AudioEffectLowPassFilter
var low_health_effect_tween: Tween
var low_health_iris_intensity := 0.0
var low_health_lowpass_cutoff := 20000.0
var survival_boss_shake_offset := Vector2.ZERO
var walk_dust_timer := 0.0
var dash_trail_timer := 0.0
var footstep_side := -1.0

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	original_collision_layer = collision_layer
	original_collision_mask = collision_mask
	original_sprite_material = sprite.material
	base_max_health = max_health
	base_fire_cooldown = fire_cooldown
	base_speed = speed
	base_roll_speed = roll_speed
	base_invincibility_duration = invincibility_duration
	base_fall_recovery_time = fall_recovery_time
	apply_cosmetic_visuals()
	apply_meta_upgrades(false)
	current_health = max_health
	if is_multiplayer_authority():
		MetaProgression.changed.connect(_on_meta_progression_changed)
		camera.make_current()
		camera.enabled = true
		player_name = Steam.getPersonaName()
		rpc("sync_name", player_name)
		sync_local_cosmetics()
		
		if character_name:
			character_name.visible = false

		# Initialize HUD for local player
		if hud:
			hud.setup_hearts(max_health, current_health)
			health_changed.connect(hud.update_hearts)
		create_low_health_iris()
		create_low_health_audio_filter()
		health_changed.connect(update_low_health_iris)
		update_low_health_iris(current_health, max_health)
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
	update_survival_ghost_visibility()
	update_cosmetic_motion(delta)
	update_movement_trails(delta)
	if is_teleporting:
		if is_multiplayer_authority():
			velocity = Vector2.ZERO
			sync_velocity = Vector2.ZERO
		update_weapon_aim()
		return
	if is_downed:
		if in_survival_mode and is_multiplayer_authority():
			handle_survival_proximity_revive(delta)
		handle_death_timer(delta) # Must run on remote peers so their local death timers tick down and redraw!
	if is_falling and not is_multiplayer_authority():
		update_remote_falling_animation(delta)
	if is_survival_ghost:
		if is_multiplayer_authority():
			handle_survival_ghost_movement(delta)
		update_animations()
		update_weapon_aim()
		update_aim_camera(delta)
		return

	# --- RUN ONLY ON MULTIPLAYER AUTHORITY ---
	if is_multiplayer_authority():
		if current_health <= 0 and not is_downed:
			return

		if is_falling:
			handle_falling(delta)
		elif ui_input_locked:
			velocity = Vector2.ZERO
		elif is_downed:
			handle_crawling_movement()
		elif not is_rolling:
			handle_movement_and_actions()
		else:
			handle_roll_physics()

		if not is_falling:
			velocity += firing_recoil_velocity
			firing_recoil_velocity = firing_recoil_velocity.move_toward(Vector2.ZERO, 520.0 * delta)
			sync_velocity = velocity
			move_and_slide()
			if in_survival_mode:
				clamp_to_survival_arena()
			elif not is_on_tower():
				rpc("start_falling_rpc", velocity)

	update_animations()
	update_weapon_aim()
	update_aim_camera(delta)

func update_aim_camera(delta: float) -> void:
	if not is_multiplayer_authority() or not camera or not camera.enabled:
		return
	var target_offset := Vector2.ZERO
	if UIJuice.controller_input_active:
		target_offset = aim_direction * aim_camera_lead_distance
	else:
		var mouse_offset := get_global_mouse_position() - global_position
		if mouse_offset.length() > aim_camera_deadzone:
			target_offset = mouse_offset.normalized() * aim_camera_lead_distance
	target_offset += survival_boss_shake_offset
	var blend := 1.0 - exp(-aim_camera_lead_smoothness * delta)
	camera.offset = camera.offset.lerp(target_offset, blend)

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
	if in_survival_mode:
		become_survival_ghost()
		return
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

	var controller_aim := Input.get_vector("AimLeft", "AimRight", "AimUp", "AimDown")
	if UIJuice.controller_input_active:
		if controller_aim.length_squared() > 0.04:
			aim_direction = controller_aim.normalized()
		elif aim_direction == Vector2.ZERO:
			aim_direction = input_dir if input_dir != Vector2.ZERO else Vector2.RIGHT
	else:
		aim_direction = (get_global_mouse_position() - global_position).normalized()
	sync_aim_direction = aim_direction

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
	if fall_drift_remaining > 0.0:
		fall_drift_remaining -= delta
		velocity = fall_drift_velocity
		fall_drift_velocity = fall_drift_velocity.move_toward(Vector2.ZERO, speed * 1.8 * delta)
	elif not fall_dash_active:
		velocity = Vector2.ZERO
		if Input.is_action_just_pressed("DodgeRoll") and not fall_dash_used:
			rpc("start_fall_recovery_dash_rpc", get_fall_recovery_direction())
	else:
		velocity = fall_dash_direction * fall_dash_speed

	move_and_slide()
	sync_velocity = velocity
	update_falling_visual()

	if is_on_tower():
		rpc("land_from_fall_rpc")
	elif fall_time_remaining <= 0.0:
		rpc("rescue_from_fall_rpc")

func update_remote_falling_animation(delta: float) -> void:
	fall_time_remaining = maxf(0.0, fall_time_remaining - delta)
	update_falling_visual()

func update_falling_visual() -> void:
	var fall_progress := 1.0 - fall_time_remaining / fall_recovery_time
	var clamped_progress := clampf(fall_progress, 0.0, 1.0)
	sprite.scale = Vector2.ONE * lerpf(1.0, 0.45, clamped_progress)
	sprite.modulate.a = lerpf(1.0, 0.25, clamped_progress)
	if character_name:
		character_name.modulate.a = sprite.modulate.a

@rpc("any_peer", "call_local", "reliable")
func start_falling_rpc(initial_velocity: Vector2) -> void:
	if is_falling or is_downed:
		return
	is_falling = true
	is_rolling = false
	fall_dash_used = false
	fall_dash_active = false
	fall_dash_direction = Vector2.ZERO
	fall_drift_remaining = fall_drift_duration
	fall_drift_velocity = initial_velocity
	fall_time_remaining = fall_recovery_time
	update_falling_visual()

func get_fall_recovery_direction() -> Vector2:
	var arena: Node = get_tree().get_first_node_in_group("tower_arena")
	var bounds: Rect2 = arena.get("arena_bounds") if arena else arena_bounds
	var center := bounds.get_center()
	var radii := bounds.size * 0.5
	var normalized_offset := (global_position - center) / radii
	if normalized_offset == Vector2.ZERO:
		return Vector2.UP
	var safe_target := center + (normalized_offset.normalized() * radii * 0.82)
	return (safe_target - global_position).normalized()

@rpc("any_peer", "call_local", "reliable")
func start_fall_recovery_dash_rpc(direction: Vector2) -> void:
	if not is_falling or fall_dash_used:
		return
	fall_dash_used = true
	fall_dash_active = true
	fall_dash_direction = direction.normalized()
	dash_trail_timer = 0.0
	spawn_dash_start_burst(fall_dash_direction)
	if sprite.sprite_frames.has_animation("roll"):
		sprite.play("roll")
	get_tree().create_timer(fall_dash_duration, false).timeout.connect(end_fall_recovery_dash)

func end_fall_recovery_dash() -> void:
	fall_dash_active = false
	velocity = Vector2.ZERO

@rpc("any_peer", "call_local", "reliable")
func land_from_fall_rpc() -> void:
	is_falling = false
	fall_dash_active = false
	fall_dash_used = false
	fall_dash_direction = Vector2.ZERO
	fall_drift_remaining = 0.0
	fall_drift_velocity = Vector2.ZERO
	fall_time_remaining = 0.0
	velocity = Vector2.ZERO
	sprite.scale = Vector2.ONE
	sprite.modulate.a = 1.0
	if character_name:
		character_name.modulate.a = 1.0

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
	set_character_facing_from_direction(roll_direction)
	dash_trail_timer = 0.0
	spawn_dash_start_burst(dir)
	
	# Temporarily disable enemy bullet collision layer (e.g., Layer 3)
	var original_mask = collision_mask
	set_collision_mask_value(4, false)
	if menusfx: menusfx.play()
	
	if sprite.sprite_frames.has_animation("roll"):
		sprite.play("roll")

	var iframe_timer = get_tree().create_timer(roll_iframe_duration, false)
	iframe_timer.timeout.connect(func(): is_invulnerable = false)
	
	var roll_timer = get_tree().create_timer(roll_duration, false)
	roll_timer.timeout.connect(func(): 
		is_rolling = false
		collision_mask = original_mask # Restore normal collision
	)

func handle_roll_physics() -> void:
	velocity = roll_direction * roll_speed

func update_movement_trails(delta: float) -> void:
	if is_downed or is_survival_ghost or (is_falling and not fall_dash_active) or not sprite.visible:
		walk_dust_timer = 0.0
		dash_trail_timer = 0.0
		return
	var visual_velocity := sync_velocity
	if is_multiplayer_authority():
		visual_velocity = velocity
	var is_dashing := is_rolling or fall_dash_active
	if is_dashing:
		dash_trail_timer -= delta
		if dash_trail_timer <= 0.0:
			dash_trail_timer = dash_trail_interval
			var dash_direction := visual_velocity.normalized()
			if dash_direction == Vector2.ZERO:
				dash_direction = roll_direction
			spawn_dash_trail_particle(dash_direction)
		walk_dust_timer = 0.0
		return
	dash_trail_timer = 0.0
	if visual_velocity.length_squared() < speed * speed * 0.08:
		walk_dust_timer = minf(walk_dust_timer, walk_dust_interval * 0.5)
		return
	walk_dust_timer -= delta
	if walk_dust_timer <= 0.0:
		var speed_ratio := clampf(visual_velocity.length() / maxf(1.0, speed), 0.65, 1.35)
		walk_dust_timer = walk_dust_interval / speed_ratio
		spawn_walk_dust(visual_velocity.normalized())

func spawn_walk_dust(move_direction: Vector2) -> void:
	if not is_inside_tree() or not get_parent():
		return
	footstep_side *= -1.0
	var sideways := move_direction.orthogonal() * footstep_side
	var spawn_position := global_position - move_direction * 6.0 + sideways * 3.2 + Vector2(0.0, 5.0)
	for _puff_index in range(2):
		var dust := create_pixel_dust(get_movement_trail_color(0.34), randf_range(1.4, 2.4))
		get_parent().add_child(dust)
		dust.global_position = spawn_position + Vector2(randf_range(-2.0, 2.0), randf_range(-1.0, 1.5))
		dust.rotation = randf_range(-0.35, 0.35)
		var drift := -move_direction * randf_range(3.0, 7.0) + sideways * randf_range(0.5, 2.5)
		var dust_tween := dust.create_tween().set_parallel()
		dust_tween.tween_property(dust, "global_position", dust.global_position + drift, walk_dust_lifetime)
		dust_tween.tween_property(dust, "scale", dust.scale * randf_range(1.45, 1.85), walk_dust_lifetime).set_trans(Tween.TRANS_SINE)
		dust_tween.tween_property(dust, "modulate:a", 0.0, walk_dust_lifetime)
		dust_tween.finished.connect(dust.queue_free)

func spawn_dash_start_burst(dash_direction: Vector2) -> void:
	if not is_inside_tree() or not get_parent():
		return
	for _burst_index in range(7):
		var spread_direction := (-dash_direction).rotated(randf_range(-0.8, 0.8))
		var dust := create_pixel_dust(get_movement_trail_color(0.52), randf_range(1.8, 3.2))
		get_parent().add_child(dust)
		dust.global_position = global_position - dash_direction * 5.0 + Vector2(randf_range(-3.0, 3.0), randf_range(-2.0, 3.0))
		var burst_distance := randf_range(10.0, 24.0)
		var burst_tween := dust.create_tween().set_parallel()
		burst_tween.tween_property(dust, "global_position", dust.global_position + spread_direction * burst_distance, dash_trail_lifetime * 1.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		burst_tween.tween_property(dust, "scale", Vector2.ZERO, dash_trail_lifetime * 1.25)
		burst_tween.tween_property(dust, "modulate:a", 0.0, dash_trail_lifetime * 1.25)
		burst_tween.finished.connect(dust.queue_free)

func spawn_dash_trail_particle(dash_direction: Vector2) -> void:
	if not is_inside_tree() or not get_parent():
		return
	var current_frame_texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if current_frame_texture:
		var afterimage := Sprite2D.new()
		afterimage.texture = current_frame_texture
		afterimage.flip_h = sprite.flip_h
		get_parent().add_child(afterimage)
		afterimage.global_position = global_position
		afterimage.rotation = sprite.global_rotation
		afterimage.scale = sprite.scale
		afterimage.z_index = z_index - 1
		afterimage.modulate = get_movement_trail_color(0.22)
		var image_tween := afterimage.create_tween().set_parallel()
		image_tween.tween_property(afterimage, "global_position", afterimage.global_position - dash_direction * 7.0, dash_trail_lifetime)
		image_tween.tween_property(afterimage, "scale", afterimage.scale * Vector2(1.18, 0.82), dash_trail_lifetime)
		image_tween.tween_property(afterimage, "modulate:a", 0.0, dash_trail_lifetime)
		image_tween.finished.connect(afterimage.queue_free)
	var streak := Polygon2D.new()
	streak.polygon = PackedVector2Array([Vector2(-13.0, -1.1), Vector2(3.0, -2.0), Vector2(6.0, 0.0), Vector2(3.0, 2.0), Vector2(-13.0, 1.1)])
	streak.color = get_movement_trail_color(0.38)
	get_parent().add_child(streak)
	streak.global_position = global_position - dash_direction * 4.0 + Vector2(0.0, 4.0)
	streak.global_rotation = dash_direction.angle()
	streak.z_index = z_index - 1
	var streak_tween := streak.create_tween().set_parallel()
	streak_tween.tween_property(streak, "scale", Vector2(0.25, 0.55), dash_trail_lifetime)
	streak_tween.tween_property(streak, "modulate:a", 0.0, dash_trail_lifetime)
	streak_tween.finished.connect(streak.queue_free)

func create_pixel_dust(color: Color, size: float) -> Polygon2D:
	var dust := Polygon2D.new()
	dust.polygon = PackedVector2Array([
		Vector2(-size, -size * 0.55), Vector2(0.0, -size),
		Vector2(size, -size * 0.55), Vector2(size, size * 0.55),
		Vector2(0.0, size), Vector2(-size, size * 0.55)
	])
	dust.color = color
	dust.z_index = z_index - 1
	return dust

func get_movement_trail_color(alpha: float) -> Color:
	var base_color := Color(0.78, 0.70, 0.74, alpha)
	if in_survival_mode:
		base_color = Color(
			lerpf(survival_team_color.r, 0.82, 0.55),
			lerpf(survival_team_color.g, 0.76, 0.55),
			lerpf(survival_team_color.b, 0.84, 0.55),
			alpha
		)
	return base_color

# --- Weapon & Shooting System ---
func update_weapon_aim() -> void:
	if weapon_pivot:
		if in_survival_mode:
			force_hide_survival_weapon()
			return
		set_weapon_drawn(not is_downed and not is_falling and not is_rolling and is_wave_active())
		var weapon_direction := sync_aim_direction
		if weapon_direction == Vector2.ZERO:
			weapon_direction = Vector2.RIGHT
		weapon_recoil_offset = weapon_recoil_offset.lerp(Vector2.ZERO, 0.28)
		var hover_offset := weapon_direction * 16.0 + weapon_recoil_offset + Vector2(0.0, sin(Time.get_ticks_msec() * 0.006) * 2.0)
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

func force_hide_survival_weapon() -> void:
	weapon_is_drawn = false
	weapon_recoil_offset = Vector2.ZERO
	if weapon_pivot:
		weapon_pivot.visible = false
		weapon_pivot.scale = Vector2.ZERO

func shoot() -> void:
	if in_survival_mode or is_downed or not is_wave_active() or not bullet_scene or Time.get_ticks_msec() / 1000.0 < next_shot_time:
		return
	next_shot_time = Time.get_ticks_msec() / 1000.0 + fire_cooldown
		
	var spawn_pos = muzzle.global_position if muzzle else global_position
	var adjusted_spread := bullet_spread_degrees * maxf(0.18, 1.0 - boon_accuracy_bonus)
	var spread_radians := deg_to_rad(randf_range(-adjusted_spread, adjusted_spread))
	var fire_angle := aim_direction.angle() + spread_radians
	firing_recoil_velocity -= aim_direction * firing_recoil_force
	rpc("play_firing_feedback_rpc", aim_direction)

	var bullet_damage := 2 + MetaProgression.get_level("damage") + boon_damage_bonus
	if randf() < boon_critical_chance:
		bullet_damage *= 2
	rpc("spawn_bullet_rpc", spawn_pos, fire_angle, multiplayer.get_unique_id(), bullet_damage, 1.0 + boon_bullet_speed_bonus, 1.0 + boon_knockback_bonus)
	if randf() < boon_multishot_chance:
		var echo_angle := fire_angle + deg_to_rad(5.0 if randf() > 0.5 else -5.0)
		rpc("spawn_bullet_rpc", spawn_pos, echo_angle, multiplayer.get_unique_id(), bullet_damage, 1.0 + boon_bullet_speed_bonus, 1.0 + boon_knockback_bonus)

@rpc("any_peer", "call_local", "unreliable")
func play_firing_feedback_rpc(fire_direction: Vector2) -> void:
	if not sprite or is_falling or is_downed:
		return
	weapon_recoil_offset = -fire_direction * weapon_kick_distance
	if muzzle:
		var recoil_tween := create_tween()
		muzzle.scale = Vector2.ONE * 1.45
		recoil_tween.tween_property(muzzle, "scale", Vector2.ONE, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var horizontal_weight := absf(fire_direction.x)
	var vertical_weight := absf(fire_direction.y)
	var firing_scale := Vector2(
		1.0 + horizontal_weight * 0.11 - vertical_weight * 0.06,
		1.0 + vertical_weight * 0.11 - horizontal_weight * 0.06
	)
	sprite.scale = firing_scale
	var squash_tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	squash_tween.tween_property(sprite, "scale", Vector2.ONE, 0.12)

@rpc("any_peer", "call_local", "reliable")
func spawn_bullet_rpc(spawn_pos: Vector2, angle: float, shooter: int, bullet_damage: int, speed_multiplier: float = 1.0, knockback_multiplier: float = 1.0) -> void:
	if bullet_scene:
		var bullet = bullet_scene.instantiate() as Area2D
		bullet.global_position = spawn_pos
		bullet.rotation = angle
		bullet.set("damage", bullet_damage)
		bullet.set("speed", float(bullet.get("speed")) * speed_multiplier)
		bullet.set("knockback_force", float(bullet.get("knockback_force")) * knockback_multiplier)
		if shootsfx: shootsfx.play()
		
		if "shooter_id" in bullet:
			bullet.shooter_id = shooter
			
		get_parent().add_child(bullet)

func _on_meta_progression_changed() -> void:
	if not is_multiplayer_authority():
		return
	sync_local_cosmetics()
	if not in_survival_mode:
		apply_meta_upgrades(true)

func sync_local_cosmetics() -> void:
	if not is_multiplayer_authority():
		return
	rpc("sync_cosmetics_rpc", MetaProgression.equipped_head_cosmetic, MetaProgression.equipped_back_cosmetic)

@rpc("any_peer", "call_local", "reliable")
func sync_cosmetics_rpc(head_cosmetic: String, back_cosmetic: String) -> void:
	equipped_head_cosmetic = head_cosmetic
	equipped_back_cosmetic = back_cosmetic
	apply_cosmetic_visuals()

func apply_cosmetic_visuals() -> void:
	if not cosmetic_head or not cosmetic_back:
		return
	cosmetic_head.texture = load_cosmetic_texture(equipped_head_cosmetic)
	cosmetic_back.texture = load_cosmetic_texture(equipped_back_cosmetic)
	cosmetic_head.visible = cosmetic_head.texture != null and sprite.visible
	cosmetic_back.visible = cosmetic_back.texture != null and sprite.visible

func load_cosmetic_texture(cosmetic_id: String) -> Texture2D:
	if cosmetic_id.is_empty():
		return null
	var texture_path := COSMETICS.get_texture_path(cosmetic_id)
	if texture_path.is_empty():
		return null
	return load(texture_path) as Texture2D

func update_cosmetic_motion(delta: float) -> void:
	if not cosmetic_head or not cosmetic_back:
		return
	var visible_with_player := sprite.visible
	cosmetic_head.visible = cosmetic_head.texture != null and visible_with_player
	cosmetic_back.visible = cosmetic_back.texture != null and visible_with_player
	cosmetic_head.flip_h = sprite.flip_h
	# Cape artwork trails in the opposite direction from the character art.
	cosmetic_back.flip_h = not sprite.flip_h
	cosmetic_head.modulate.a = sprite.modulate.a
	cosmetic_back.modulate.a = sprite.modulate.a
	if is_teleporting:
		return
	var bob := sin(Time.get_ticks_msec() * 0.009) * minf(1.0, sync_velocity.length() / maxf(1.0, speed))
	cosmetic_head.position.y = lerpf(cosmetic_head.position.y, -12.0 + bob, minf(1.0, delta * 14.0))
	var cape_target_rotation := clampf(-sync_velocity.x / 720.0, -0.24, 0.24)
	cosmetic_back.rotation = lerp_angle(cosmetic_back.rotation, cape_target_rotation, minf(1.0, delta * 9.0))

func play_teleport_departure_visual() -> void:
	if is_teleporting:
		return
	is_teleporting = true
	set_weapon_drawn(false)
	if teleport_visual_tween and teleport_visual_tween.is_valid():
		teleport_visual_tween.kill()
	teleport_visual_tween = create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	teleport_visual_tween.tween_property(sprite, "position:y", sprite.position.y - 24.0, 0.24)
	teleport_visual_tween.tween_property(sprite, "scale", Vector2(0.28, 1.45), 0.18)
	teleport_visual_tween.tween_property(sprite, "modulate:a", 0.0, 0.22).set_delay(0.04)
	teleport_visual_tween.tween_property(cosmetic_head, "position:y", cosmetic_head.position.y - 24.0, 0.24)
	teleport_visual_tween.tween_property(cosmetic_back, "position:y", cosmetic_back.position.y - 24.0, 0.24)
	teleport_visual_tween.tween_property(cosmetic_head, "modulate:a", 0.0, 0.22).set_delay(0.04)
	teleport_visual_tween.tween_property(cosmetic_back, "modulate:a", 0.0, 0.22).set_delay(0.04)

func reset_teleport_visual() -> void:
	if teleport_visual_tween and teleport_visual_tween.is_valid():
		teleport_visual_tween.kill()
	is_teleporting = false
	sprite.position = Vector2.ZERO
	sprite.scale = Vector2.ONE
	sprite.modulate.a = 1.0
	cosmetic_head.position = Vector2(0.0, -12.0)
	cosmetic_back.position = Vector2(0.0, 2.0)
	cosmetic_head.scale = Vector2.ONE * 0.5
	cosmetic_back.scale = Vector2.ONE * 0.5
	cosmetic_head.modulate.a = 1.0
	cosmetic_back.modulate.a = 1.0

func apply_meta_upgrades(heal_from_new_vitality: bool) -> void:
	var previous_max_health := max_health
	max_health = base_max_health + MetaProgression.get_level("vitality") * 2 + boon_health_bonus
	var meta_fire_cooldown := base_fire_cooldown - MetaProgression.get_level("rapid_fire") * 0.015
	fire_cooldown = maxf(0.045, meta_fire_cooldown * (1.0 - minf(0.72, boon_fire_rate_bonus)))
	speed = base_speed * (1.0 + boon_move_speed_bonus)
	roll_speed = base_roll_speed * (1.0 + boon_roll_speed_bonus)
	invincibility_duration = base_invincibility_duration + boon_invulnerability_bonus
	fall_recovery_time = base_fall_recovery_time + boon_fall_grace_bonus
	if not heal_from_new_vitality or current_health <= 0:
		return
	var gained_health := maxi(0, max_health - previous_max_health)
	current_health = mini(max_health, current_health + gained_health)
	health_changed.emit(current_health, max_health)

func apply_ascension_boon(boon_id: String, rarity: int) -> void:
	if not is_multiplayer_authority() or BOONS.get_boon(boon_id).is_empty():
		return
	var value := BOONS.get_value(boon_id, rarity)
	match BOONS.get_effect(boon_id):
		"damage": boon_damage_bonus += maxi(1, roundi(value))
		"fire_rate": boon_fire_rate_bonus += value
		"move_speed": boon_move_speed_bonus += value
		"max_health": boon_health_bonus += maxi(1, roundi(value))
		"bullet_speed": boon_bullet_speed_bonus += value
		"knockback": boon_knockback_bonus += value
		"multishot": boon_multishot_chance += value
		"accuracy": boon_accuracy_bonus += value
		"invulnerability": boon_invulnerability_bonus += value
		"fall_grace": boon_fall_grace_bonus += value
		"roll_speed": boon_roll_speed_bonus += value
		"critical": boon_critical_chance += value
	acquired_boons.append("%s:%d" % [boon_id, rarity])
	apply_meta_upgrades(true)

func clear_ascension_boons() -> void:
	boon_damage_bonus = 0
	boon_health_bonus = 0
	boon_fire_rate_bonus = 0.0
	boon_move_speed_bonus = 0.0
	boon_bullet_speed_bonus = 0.0
	boon_knockback_bonus = 0.0
	boon_multishot_chance = 0.0
	boon_accuracy_bonus = 0.0
	boon_invulnerability_bonus = 0.0
	boon_fall_grace_bonus = 0.0
	boon_roll_speed_bonus = 0.0
	boon_critical_chance = 0.0
	acquired_boons.clear()
	apply_meta_upgrades(false)

func enter_survival_mode(bounds: Rect2, spawn_position: Vector2, team_id: int = 0, team_size: int = 1, team_color: Color = Color.WHITE) -> void:
	in_survival_mode = true
	is_survival_ghost = false
	survival_team_id = team_id
	survival_team_size = team_size
	survival_team_color = team_color
	survival_bounds = bounds
	survival_revive_progress = 0.0
	is_downed = false
	is_falling = false
	is_rolling = false
	is_invulnerable = false
	down_count = 0
	death_timer_current = 0.0
	pause_timer = 0.0
	max_health = 6
	current_health = 6
	global_position = spawn_position
	velocity = Vector2.ZERO
	sync_velocity = Vector2.ZERO
	collision_layer = original_collision_layer
	collision_mask = original_collision_mask
	set_collision_mask_value(1, false)
	sprite.scale = Vector2.ONE
	sprite.material = SURVIVAL_TEAM_MATERIAL.duplicate()
	sprite.modulate = get_survival_display_color()
	set_survival_outline(false)
	force_hide_survival_weapon()
	update_survival_ghost_visibility()
	if hud and is_multiplayer_authority():
		hud.setup_hearts(max_health, current_health)
	health_changed.emit(current_health, max_health)
	queue_redraw()

func exit_survival_mode() -> void:
	in_survival_mode = false
	is_survival_ghost = false
	survival_team_id = -1
	survival_team_size = 1
	survival_team_color = Color.WHITE
	survival_revive_progress = 0.0
	collision_layer = original_collision_layer
	collision_mask = original_collision_mask
	sprite.scale = Vector2.ONE
	sprite.modulate = Color.WHITE
	sprite.material = original_sprite_material
	sprite.visible = true
	if character_name:
		character_name.visible = not is_multiplayer_authority()
	if survival_ghost_ui and is_instance_valid(survival_ghost_ui):
		survival_ghost_ui.queue_free()
	survival_ghost_ui = null
	apply_meta_upgrades(false)
	current_health = max_health
	if hud and is_multiplayer_authority():
		hud.setup_hearts(max_health, current_health)
	health_changed.emit(current_health, max_health)

func handle_survival_proximity_revive(delta: float) -> void:
	revive_hp_max = survival_revive_duration
	if survival_team_size <= 1:
		survival_revive_progress = 0.0
		revive_hp_current = revive_hp_max
		queue_redraw()
		return
	var helper_nearby := has_nearby_survival_teammate()
	if helper_nearby:
		revive_hp_current = maxf(0.0, revive_hp_current - delta)
		pause_timer = maxf(pause_timer, 0.22)
	else:
		revive_hp_current = minf(revive_hp_max, revive_hp_current + delta * 0.45)
	survival_revive_progress = revive_hp_max - revive_hp_current
	queue_redraw()
	survival_revive_sync_elapsed += delta
	if survival_revive_sync_elapsed >= 0.10:
		survival_revive_sync_elapsed = 0.0
		rpc("sync_survival_revive_visual_rpc", survival_revive_progress, helper_nearby, death_timer_current)
	if revive_hp_current <= 0.0:
		survival_revive_progress = 0.0
		rpc("sync_revive_player_rpc")

func has_nearby_survival_teammate() -> bool:
	for ally in get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("survival_allies"):
		var ally_node := ally as Node2D
		if not ally_node or ally_node == self:
			continue
		if int(ally_node.get("survival_team_id")) != survival_team_id:
			continue
		if bool(ally_node.get("is_downed")) or bool(ally_node.get("is_survival_ghost")):
			continue
		if global_position.distance_to(ally_node.global_position) <= 52.0:
			return true
	return false

@rpc("any_peer", "call_remote", "reliable")
func sync_survival_revive_visual_rpc(progress: float, helper_nearby: bool, death_time_remaining: float) -> void:
	if not in_survival_mode or not is_downed:
		return
	survival_revive_progress = progress
	revive_hp_max = survival_revive_duration
	revive_hp_current = maxf(0.0, survival_revive_duration - progress)
	death_timer_current = clampf(death_time_remaining, 0.0, death_timer_max)
	if helper_nearby:
		pause_timer = maxf(pause_timer, 0.22)
	queue_redraw()

func handle_survival_ghost_movement(delta: float) -> void:
	input_dir = Vector2(
		Input.get_axis("Left", "Right"),
		Input.get_axis("Up", "Down")
	).normalized()
	velocity = input_dir * speed * 0.72
	sync_velocity = velocity
	global_position += velocity * delta
	clamp_to_survival_arena()

func clamp_to_survival_arena() -> void:
	var arena_center := survival_bounds.get_center()
	var playable_radius := minf(survival_bounds.size.x, survival_bounds.size.y) * 0.5 - 10.0
	var center_offset := global_position - arena_center
	if center_offset.length_squared() > playable_radius * playable_radius:
		global_position = arena_center + center_offset.normalized() * playable_radius

func become_survival_ghost() -> void:
	is_downed = false
	is_survival_ghost = true
	is_rolling = false
	is_invulnerable = false
	velocity = Vector2.ZERO
	sync_velocity = Vector2.ZERO
	death_timer_current = 0.0
	pause_timer = 0.0
	collision_layer = 0
	collision_mask = 0
	sprite.scale = Vector2.ONE
	sprite.modulate = Color(survival_team_color.r, survival_team_color.g, survival_team_color.b, 0.28)
	force_hide_survival_weapon()
	update_survival_ghost_visibility()
	update_low_health_iris(max_health, max_health)
	if is_multiplayer_authority():
		create_survival_ghost_ui()
	play_survival_death_sound()
	queue_redraw()

func update_survival_ghost_visibility() -> void:
	if not in_survival_mode:
		return
	var should_be_visible := true
	if is_survival_ghost:
		should_be_visible = is_multiplayer_authority() or local_survival_player_is_ghost()
	if sprite:
		sprite.visible = should_be_visible
	if character_name:
		character_name.visible = should_be_visible and not is_multiplayer_authority()
	set_survival_outline(should_be_visible and not is_multiplayer_authority() and local_survival_player_is_teammate())
	if in_survival_mode:
		force_hide_survival_weapon()

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

func set_survival_outline(outline_visible: bool) -> void:
	if not sprite or not (sprite.material is ShaderMaterial):
		return
	var team_material := sprite.material as ShaderMaterial
	team_material.set_shader_parameter("outline_enabled", outline_visible)
	team_material.set_shader_parameter("outline_colour", survival_team_color.lightened(0.35))
	team_material.set_shader_parameter("outline_thickness", 2.0)

func get_survival_display_color() -> Color:
	return Color(
		lerpf(survival_team_color.r, 1.0, 0.32),
		lerpf(survival_team_color.g, 1.0, 0.32),
		lerpf(survival_team_color.b, 1.0, 0.32),
		1.0
	)

func play_survival_death_sound() -> void:
	var death_audio := AudioStreamPlayer2D.new()
	death_audio.stream = SURVIVAL_DEATH_SFX
	death_audio.bus = &"SFX"
	death_audio.pitch_scale = randf_range(0.72, 0.88)
	get_parent().add_child(death_audio)
	death_audio.global_position = global_position
	death_audio.finished.connect(death_audio.queue_free)
	death_audio.play()

func create_survival_ghost_ui() -> void:
	if survival_ghost_ui and is_instance_valid(survival_ghost_ui):
		return
	survival_ghost_ui = CanvasLayer.new()
	survival_ghost_ui.layer = 46
	var panel := ColorRect.new()
	panel.color = Color(0.12, 0.015, 0.04, 0.90)
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.position = Vector2(-145.0, -58.0)
	panel.size = Vector2(290.0, 48.0)
	survival_ghost_ui.add_child(panel)
	var label := Label.new()
	label.text = "YOU POPPED! GHOST MODE"
	label.position = Vector2(8.0, 4.0)
	label.size = Vector2(160.0, 34.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	var leave_button := Button.new()
	leave_button.text = "RETURN PARTY"
	leave_button.position = Vector2(170.0, 8.0)
	leave_button.size = Vector2(112.0, 32.0)
	leave_button.pressed.connect(func():
		var main := get_tree().get_first_node_in_group("main")
		if main and main.has_method("leave_survival_mode"):
			main.call("leave_survival_mode")
	)
	panel.add_child(leave_button)
	add_child(survival_ghost_ui)
	if UIJuice.keyboard_navigation_active:
		leave_button.call_deferred("grab_focus")

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
	play_hit_screen_shake()
	
	# RPC the invulnerability visually across all peers
	rpc("start_invulnerability_rpc", invincibility_duration)

	if current_health <= 0:
		rpc("enter_downed_state_rpc")

@rpc("any_peer", "call_local", "reliable")
func receive_boss_bash_rpc(damage: int, knockback: Vector2) -> void:
	if not is_multiplayer_authority():
		return
	take_damage(damage)
	if not is_downed:
		velocity += knockback

func heal(amount: int) -> void:
	if is_downed:
		if is_multiplayer_authority():
			rpc("revive_from_health_pickup_rpc")
		return
	if current_health >= max_health:
		return
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

@rpc("any_peer", "call_local", "reliable")
func revive_from_health_pickup_rpc() -> void:
	if not is_downed:
		return
	is_downed = false
	death_timer_current = 0.0
	pause_timer = 0.0
	current_health = 1
	if in_survival_mode:
		sprite.modulate = get_survival_display_color()
	health_changed.emit(current_health, max_health)
	player_revived.emit()
	if sprite.sprite_frames.has_animation("Idle"):
		sprite.play("Idle")
	queue_redraw()

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
	
	if in_survival_mode:
		survival_revive_progress = 0.0
		revive_hp_max = survival_revive_duration
	else:
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

	revive_hp_current = maxf(0.0, revive_hp_current - amount)
	if in_survival_mode:
		revive_hp_max = survival_revive_duration
		survival_revive_progress = revive_hp_max - revive_hp_current
	pause_timer = pause_on_hit_duration # Set pause timer locally across all clients
	queue_redraw()

	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(0.3, 1.0, 0.3), 0.05)
	tween.tween_property(sprite, "modulate", get_survival_display_color() if in_survival_mode else Color.WHITE, 0.05)

	# Authority validates when player gets fully revived
	if is_multiplayer_authority():
		if in_survival_mode:
			rpc("sync_survival_revive_visual_rpc", survival_revive_progress, true, death_timer_current)
		if revive_hp_current <= 0.0:
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
	# An ally's recent revive shot grants a brief protection window.
	if pause_timer > 0.0:
		return
	pause_timer = 0.0
	death_timer_current = maxf(0.0, death_timer_current - penalty)
	if is_multiplayer_authority():
		play_hit_screen_shake()
	queue_redraw()
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1.0, 0.28, 0.28), 0.06)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.08)

func play_hit_screen_shake() -> void:
	if not is_multiplayer_authority() or not camera:
		return
	var shake := create_tween()
	shake.tween_property(camera, "offset", Vector2(randf_range(-4.0, 4.0), randf_range(-3.0, 3.0)), 0.035)
	shake.tween_property(camera, "offset", Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0)), 0.045)
	shake.tween_property(camera, "offset", Vector2.ZERO, 0.07)

func play_survival_boss_shake(intensity: float = 5.0) -> void:
	if not is_multiplayer_authority() or not camera:
		return
	var shake := create_tween()
	for pulse in range(4):
		var falloff := 1.0 - float(pulse) * 0.18
		shake.tween_property(self, "survival_boss_shake_offset", Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity)) * falloff, 0.035)
	shake.tween_property(self, "survival_boss_shake_offset", Vector2.ZERO, 0.07)

func is_dodging_bullets() -> bool:
	return is_rolling and is_invulnerable

func create_low_health_iris() -> void:
	var iris_layer := CanvasLayer.new()
	iris_layer.layer = 20
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	low_health_iris_material = ShaderMaterial.new()
	low_health_iris_material.shader = LOW_HEALTH_IRIS_SHADER
	overlay.material = low_health_iris_material
	iris_layer.add_child(overlay)
	add_child(iris_layer)

func create_low_health_audio_filter() -> void:
	var master_bus_index := AudioServer.get_bus_index("Master")
	if master_bus_index < 0:
		return
	low_health_lowpass = AudioEffectLowPassFilter.new()
	low_health_lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(master_bus_index, low_health_lowpass)

func update_low_health_iris(health: int, health_maximum: int) -> void:
	if not low_health_iris_material or health_maximum <= 0:
		return
	var missing_health_ratio := 1.0 - clampf(float(health) / float(health_maximum), 0.0, 1.0)
	# The warning should remain very subtle above half health, then build smoothly.
	var target_intensity := pow(maxf(0.0, missing_health_ratio - 0.35) / 0.65, 1.45)
	var target_cutoff := lerpf(20000.0, 1200.0, pow(target_intensity, 1.15))
	if low_health_effect_tween and low_health_effect_tween.is_valid():
		low_health_effect_tween.kill()
	low_health_effect_tween = create_tween().set_parallel()
	low_health_effect_tween.tween_method(set_low_health_iris_intensity, low_health_iris_intensity, target_intensity, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	low_health_effect_tween.tween_method(set_low_health_audio_cutoff, low_health_lowpass_cutoff, target_cutoff, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func set_low_health_iris_intensity(value: float) -> void:
	low_health_iris_intensity = value
	if low_health_iris_material:
		low_health_iris_material.set_shader_parameter("intensity", value)

func set_low_health_audio_cutoff(value: float) -> void:
	low_health_lowpass_cutoff = value
	if low_health_lowpass:
		low_health_lowpass.cutoff_hz = value
@rpc("any_peer", "call_local", "reliable")

func sync_revive_player_rpc() -> void:
	revive_player()

func revive_player() -> void:
	is_downed = false
	survival_revive_progress = 0.0
	revive_hp_current = 0.0
	current_health = int(max_health * 0.5)
	if in_survival_mode:
		sprite.modulate = get_survival_display_color()
	health_changed.emit(current_health, max_health)
	player_revived.emit()
	
	if sprite.sprite_frames.has_animation("Idle"):
		sprite.play("Idle")

	queue_redraw()

@rpc("any_peer", "call_local", "reliable")
func reset_for_lobby_rpc() -> void:
	if in_survival_mode or is_survival_ghost:
		exit_survival_mode()
	is_downed = false
	is_falling = false
	is_rolling = false
	death_timer_current = 0.0
	pause_timer = 0.0
	revive_hp_current = 0.0
	clear_ascension_boons()
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
		get_tree().create_timer(duration, false).timeout.connect(func(): is_invulnerable = false)
		return

	var mat = sprite.material as ShaderMaterial
	
	# Quick initial hit flash (0.15s)
	mat.set_shader_parameter("enabled", true)
	get_tree().create_timer(0.15, false).timeout.connect(func():
		if is_instance_valid(mat):
			mat.set_shader_parameter("enabled", false)
	)

	# Optional: Continuous alpha pulsing while invulnerable
	var tween = create_tween().set_loops(int(duration / 0.1))
	tween.tween_property(sprite, "modulate:a", 0.3, 0.05)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.05)

	get_tree().create_timer(duration, false).timeout.connect(func():
		is_invulnerable = false
		set_collision_mask_value(2, original_enemy_mask)
		if tween and tween.is_running():
			tween.kill()
		if sprite and not is_survival_ghost:
			sprite.modulate.a = 1.0
			if sprite.material is ShaderMaterial:
				(sprite.material as ShaderMaterial).set_shader_parameter("enabled", false)
	)

# --- Visuals & Animations ---
func update_animations() -> void:
	if is_survival_ghost:
		if sync_velocity.length() > 0.1 and sprite.sprite_frames.has_animation("move"):
			sprite.play("move")
			set_character_facing_from_direction(sync_velocity)
		elif sprite.sprite_frames.has_animation("Idle"):
			sprite.play("Idle")
		return
	if is_downed:
		if sprite.animation != "downed" and sprite.sprite_frames.has_animation("downed"):
			sprite.play("downed")
		return
	if is_falling:
		if fall_dash_active and sprite.sprite_frames.has_animation("roll"):
			sprite.play("roll")
			set_character_facing_from_direction(fall_dash_direction)
		elif sprite.sprite_frames.has_animation("Idle"):
			sprite.play("Idle")
		return

	if is_rolling:
		set_character_facing_from_direction(roll_direction)
		return

	# Animation speed follows movement, but combat facing follows aim. This prevents
	# firing recoil (which pushes opposite the aim) from turning the player around.
	if sync_velocity.length() > 0.1:
		if sprite.animation != "move":
			sprite.play("move")
	else:
		if sprite.animation != "Idle":
			sprite.play("Idle")
	var facing_direction := sync_velocity if in_survival_mode else sync_aim_direction
	set_character_facing_from_direction(facing_direction)

func set_character_facing_from_direction(direction: Vector2) -> void:
	if absf(direction.x) > 0.01:
		sprite.flip_h = direction.x < 0.0

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
		
