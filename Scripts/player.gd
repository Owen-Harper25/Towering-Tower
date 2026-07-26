extends CharacterBody2D

# --- Signals ---
signal health_changed(new_health: int, max_health: int)
signal player_died()
signal player_downed()
signal player_revived()

# --- Network & Identity ---
@export var player_name: String = "":
	set(value):
		player_name = value
		if character_name:
			character_name.text = value

# --- Movement & Roll Configuration ---
@export_group("Movement Settings")
@export var input_dir: Vector2 = Vector2.ZERO
@export var speed: float = 120.0
@export var roll_speed: float = 220.0
@export var roll_duration: float = 0.45
@export var roll_iframe_duration: float = 0.35
@onready var shootsfx: AudioStreamPlayer2D = get_node_or_null("/root/Main/Audio/Shoot")
@onready var hurtsfx: AudioStreamPlayer2D = get_node_or_null("/root/Main/Audio/Hurt")
@onready var menusfx: AudioStreamPlayer2D = get_node_or_null("/root/Main/Audio/Menu")

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

# --- Internal State ---
var current_health: int
var is_rolling: bool = false
var is_invulnerable: bool = false
var roll_direction: Vector2 = Vector2.DOWN
var aim_direction: Vector2 = Vector2.RIGHT

# --- Downed & Revive State (Nightreign Style) ---
@export var is_downed: bool = false
var down_count: int = 0
var revive_hp_current: float = 0.0
var revive_hp_max: float = 0.0

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	current_health = max_health
	
	if is_multiplayer_authority():
		camera.make_current()
		camera.enabled = true
		player_name = Steam.getPersonaName()
		rpc("sync_name", player_name)
	else:
		camera.enabled = false
		camera.process_mode = Node.PROCESS_MODE_DISABLED

@rpc("any_peer", "call_local", "reliable")
func sync_name(new_name: String) -> void:
	player_name = new_name

func _physics_process(_delta: float) -> void:
	if is_multiplayer_authority():
		if current_health <= 0 and not is_downed:
			return

		# Downed Movement (Slow Crawl)
		if is_downed:
			handle_crawling_movement()
		elif not is_rolling:
			handle_movement_and_actions()
		else:
			handle_roll_physics()

		move_and_slide()

	update_animations()
	update_weapon_aim()

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

	if Input.is_action_just_pressed("Shoot"):
		shoot()

func handle_crawling_movement() -> void:
	var input_dir := Vector2(
		Input.get_axis("Left", "Right"),
		Input.get_axis("Up", "Down")
	).normalized()
	
	# Slow crawl movement speed
	velocity = input_dir * (speed * 0.25)

# --- Dodge Roll System ---
@rpc("any_peer", "call_local", "reliable")
func start_dodge_roll_rpc(dir: Vector2) -> void:
	if is_downed:
		return
	is_rolling = true
	is_invulnerable = true
	roll_direction = dir
	if menusfx: menusfx.play()
	
	if sprite.sprite_frames.has_animation("roll"):
		sprite.play("roll")

	var iframe_timer = get_tree().create_timer(roll_iframe_duration)
	iframe_timer.timeout.connect(func(): is_invulnerable = false)
	
	var roll_timer = get_tree().create_timer(roll_duration)
	roll_timer.timeout.connect(func(): is_rolling = false)

func handle_roll_physics() -> void:
	velocity = roll_direction * roll_speed

# --- Weapon & Shooting System ---
func update_weapon_aim() -> void:
	if weapon_pivot:
		weapon_pivot.visible = not is_downed
		var target_angle = aim_direction.angle() if is_multiplayer_authority() else velocity.angle()
		weapon_pivot.rotation = target_angle

func shoot() -> void:
	if is_downed or not bullet_scene:
		return
		
	var spawn_pos = muzzle.global_position if muzzle else global_position
	var fire_angle = aim_direction.angle()
	
	rpc("spawn_bullet_rpc", spawn_pos, fire_angle, multiplayer.get_unique_id())

@rpc("any_peer", "call_local", "reliable")
func spawn_bullet_rpc(spawn_pos: Vector2, angle: float, shooter: int) -> void:
	if bullet_scene:
		var bullet = bullet_scene.instantiate() as Area2D
		bullet.global_position = spawn_pos
		bullet.rotation = angle
		if shootsfx: shootsfx.play()
		
		if "shooter_id" in bullet:
			bullet.shooter_id = shooter
			
		get_parent().add_child(bullet)

# --- Health, Downed & Revive Mechanics ---
func take_damage(amount: int) -> void:
	if not is_multiplayer_authority() or is_invulnerable:
		return

	if is_downed:
		return # Downed player doesn't take standard damage

	current_health -= amount
	current_health = max(0, current_health)
	health_changed.emit(current_health, max_health)
	if hurtsfx: hurtsfx.play()
	
	start_invulnerability(invincibility_duration)

	if current_health <= 0:
		rpc("enter_downed_state_rpc")

@rpc("any_peer", "call_local", "reliable")
func enter_downed_state_rpc() -> void:
	is_downed = true
	down_count += 1
	
	# Scaling Revive HP requirements (1st down = 30 hit points, 2nd down = 60, 3rd+ = 120)
	match down_count:
		1:
			revive_hp_max = 30.0
		2:
			revive_hp_max = 60.0
		_:
			revive_hp_max = 120.0
			
	revive_hp_current = revive_hp_max
	player_downed.emit()
	
	if sprite.sprite_frames.has_animation("downed"):
		sprite.play("downed")

# Called when an ally attacks a downed player to revive them
@rpc("any_peer", "call_local", "reliable")
func receive_revive_hit_rpc(amount: float) -> void:
	if not is_downed:
		return

	revive_hp_current -= amount
	
	# Flashing visual feedback when struck by ally
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(0.3, 1.0, 0.3), 0.05) # Green flash
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.05)

	if revive_hp_current <= 0:
		revive_player()

func revive_player() -> void:
	is_downed = false
	current_health = int(max_health * 0.5) # Revive with 50% max HP
	health_changed.emit(current_health, max_health)
	player_revived.emit()
	
	if sprite.sprite_frames.has_animation("Idle"):
		sprite.play("Idle")

func start_invulnerability(duration: float) -> void:
	is_invulnerable = true
	var tween = create_tween().set_loops(int(duration / 0.1))
	tween.tween_property(sprite, "modulate:a", 0.3, 0.05)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.05)
	
	get_tree().create_timer(duration).timeout.connect(func():
		is_invulnerable = false
		sprite.modulate.a = 1.0
	)

# --- Visuals & Animations ---
func update_animations() -> void:
	if is_downed:
		if sprite.animation != "downed" and sprite.sprite_frames.has_animation("downed"):
			sprite.play("downed")
		return

	if is_rolling:
		return

	if velocity.length() > 0.1:
		if sprite.animation != "move":
			sprite.play("move")
		if velocity.x != 0:
			sprite.flip_h = (velocity.x < 0)
	else:
		if sprite.animation != "Idle":
			sprite.play("Idle")
