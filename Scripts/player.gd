extends CharacterBody2D

# --- Signals ---
signal health_changed(new_health: int, max_health: int)
signal player_died()

# --- Network & Identity ---
@export var player_name: String = "":
	set(value):
		player_name = value
		if character_name:
			character_name.text = value

# --- Movement & Roll Configuration ---
@export_group("Movement Settings")
@export var speed: float = 120.0
@export var roll_speed: float = 220.0
@export var roll_duration: float = 0.45
@export var roll_iframe_duration: float = 0.35

# --- Health Settings ---
@export_group("Combat Settings")
@export var max_health: int = 6
@export var invincibility_duration: float = 1.0
@export var bullet_scene: PackedScene

# --- Nodes ---
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var camera: Camera2D = $Camera2D
@onready var character_name: Label = $CharacterName
@onready var weapon_pivot: Node2D = $WeaponPivot # Add a Node2D pivot at player center
@onready var muzzle: Node2D = $WeaponPivot/Muzzle # Add a Marker2D child for bullet spawn point

# --- Internal State ---
var current_health: int
var is_rolling: bool = false
var is_invulnerable: bool = false
var roll_direction: Vector2 = Vector2.DOWN
var aim_direction: Vector2 = Vector2.RIGHT

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
	# ONLY the authority handles inputs, physics, and actions
	if is_multiplayer_authority():
		if current_health <= 0:
			return

		if not is_rolling:
			handle_movement_and_actions()
		else:
			handle_roll_physics()

		move_and_slide()

	# Visuals update locally on ALL clients based on synced state/velocity
	update_animations()
	update_weapon_aim()

# --- Movement & Input Handling ---
func handle_movement_and_actions() -> void:
	var input_dir := Vector2(
		Input.get_axis("Left", "Right"),
		Input.get_axis("Up", "Down")
	).normalized()

	# Aiming towards mouse
	aim_direction = (get_global_mouse_position() - global_position).normalized()

	# Dodge Roll Trigger
	if Input.is_action_just_pressed("DodgeRoll") and input_dir != Vector2.ZERO:
		start_dodge_roll(input_dir)
		return

	# Standard Movement
	velocity = input_dir * speed

	# Shooting Input
	if Input.is_action_just_pressed("Shoot"):
		shoot()

# --- Dodge Roll System ---
func start_dodge_roll(dir: Vector2) -> void:
	is_rolling = true
	is_invulnerable = true
	roll_direction = dir
	
	# Play dodge animation locally / broadcast
	if sprite.sprite_frames.has_animation("roll"):
		sprite.play("roll")

	# Invincibility frame timer (invincible for the first portion of the roll)
	var iframe_timer = get_tree().create_timer(roll_iframe_duration)
	iframe_timer.timeout.connect(func(): is_invulnerable = false)

	# Roll finish timer
	var roll_timer = get_tree().create_timer(roll_duration)
	roll_timer.timeout.connect(func(): is_rolling = false)

func handle_roll_physics() -> void:
	velocity = roll_direction * roll_speed

# --- Weapon & Shooting System ---
func update_weapon_aim() -> void:
	if weapon_pivot:
		# Point the weapon towards the aim direction or mouse
		var target_angle = aim_direction.angle() if is_multiplayer_authority() else velocity.angle()
		weapon_pivot.rotation = target_angle

func shoot() -> void:
	if not bullet_scene:
		push_warning("No bullet_scene assigned to Player!")
		return
		
	var spawn_pos = muzzle.global_position if muzzle else global_position
	var fire_angle = aim_direction.angle()
	
	# Spawn bullet over network using RPC
	rpc("spawn_bullet_rpc", spawn_pos, fire_angle)

@rpc("any_peer", "call_local", "reliable")
func spawn_bullet_rpc(spawn_pos: Vector2, angle: float) -> void:
	if bullet_scene:
		var bullet = bullet_scene.instantiate() as Node2D
		bullet.global_position = spawn_pos
		bullet.rotation = angle
		# Assumes bullet script sets ownership/damage or handles its own motion
		get_parent().add_child(bullet)

# --- Health & Damage System ---
func take_damage(amount: int) -> void:
	# Damage checks should be verified on authority/server
	if not is_multiplayer_authority() or is_invulnerable or current_health <= 0:
		return

	current_health -= amount
	current_health = max(0, current_health)
	health_changed.emit(current_health, max_health)

	# Trigger Invincibility Frames
	start_invulnerability(invincibility_duration)

	if current_health <= 0:
		die()

func start_invulnerability(duration: float) -> void:
	is_invulnerable = true
	
	# Flashing effect
	var tween = create_tween().set_loops(int(duration / 0.1))
	tween.tween_property(sprite, "modulate:a", 0.3, 0.05)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.05)
	
	get_tree().create_timer(duration).timeout.connect(func():
		is_invulnerable = false
		sprite.modulate.a = 1.0
	)

func die() -> void:
	velocity = Vector2.ZERO
	player_died.emit()
	if sprite.sprite_frames.has_animation("death"):
		sprite.play("death")

# --- Visuals & Animations ---
func update_animations() -> void:
	if current_health <= 0 or is_rolling:
		return

	if velocity.length() > 0:
		sprite.play("move")
		if velocity.x < 0:
			sprite.flip_h = true
		elif velocity.x > 0:
			sprite.flip_h = false
	else:
		sprite.play("Idle")
