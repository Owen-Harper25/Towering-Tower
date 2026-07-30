extends CharacterBody2D

# --- Signals & Export Settings ---
@export_group("Movement Settings")
@export var speed: float = 80.0
@export var stopping_distance: float = 120.0

@export_group("Combat Settings")
@export var max_health: int = 15
@export var attack_cooldown: float = 1.5
@export var bullet_scene: PackedScene
@export var hit_sound: AudioStream

# --- Internal References ---
@onready var sprite: Sprite2D = $Sprite2D
@onready var shoot_timer: Timer = get_node_or_null("ShootTimer")

var target_player: CharacterBody2D = null
var current_health: int
var is_dying: bool = false
var hit_sfx_player: AudioStreamPlayer2D

func _enter_tree() -> void:
	set_multiplayer_authority(1)

func _ready() -> void:
	current_health = max_health
	
	# Setup dynamic audio player for hit sound
	hit_sfx_player = AudioStreamPlayer2D.new()
	hit_sfx_player.name = "HitSFXPlayer"
	if hit_sound:
		hit_sfx_player.stream = hit_sound
	add_child(hit_sfx_player)

	setup_shoot_timer()

func setup_shoot_timer() -> void:
	if not shoot_timer:
		shoot_timer = Timer.new()
		shoot_timer.name = "ShootTimer"
		add_child(shoot_timer)

	shoot_timer.wait_time = attack_cooldown
	shoot_timer.timeout.connect(_on_shoot_timer_timeout)
	shoot_timer.start()

func _physics_process(_delta: float) -> void:
	if not is_multiplayer_authority() or is_dying:
		return

	find_target_player()

	if target_player and is_instance_valid(target_player):
		var distance = global_position.distance_to(target_player.global_position)
		var direction = (target_player.global_position - global_position).normalized()

		if distance > stopping_distance:
			velocity = direction * speed
		else:
			velocity = Vector2.ZERO

		if sprite:
			sprite.flip_h = (direction.x < 0)
	else:
		velocity = Vector2.ZERO

	move_and_slide()

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

	var fire_dir = (target_player.global_position - global_position).normalized()
	rpc("spawn_enemy_bullet_rpc", global_position, fire_dir.angle())

@rpc("any_peer", "call_local", "reliable")
func spawn_enemy_bullet_rpc(spawn_pos: Vector2, angle: float) -> void:
	if bullet_scene:
		var bullet = bullet_scene.instantiate()
		bullet.global_position = spawn_pos
		bullet.rotation = angle
		
		# Set shooter reference if your bullet script supports it
		if "shooter" in bullet:
			bullet.shooter = self

		get_parent().add_child(bullet)

# --- COMBAT, SHADER & SFX HANDLERS ---

func take_damage(amount: int) -> void:
	if is_dying:
		return

	current_health -= amount
	rpc("play_hit_effects_rpc")

	if current_health <= 0:
		rpc("die_with_dissolve_rpc")

@rpc("any_peer", "call_local", "reliable")
func play_hit_effects_rpc() -> void:
	if hit_sfx_player and hit_sfx_player.stream:
		hit_sfx_player.play()

	# Trigger Shader Flash
	if sprite and sprite.material is ShaderMaterial:
		var mat = sprite.material as ShaderMaterial
		mat.set_shader_parameter("enabled", true)
		
		# Turn off flash after 0.15 seconds
		get_tree().create_timer(0.15).timeout.connect(func():
			if is_instance_valid(mat):
				mat.set_shader_parameter("enabled", false)
		)
@rpc("any_peer", "call_local", "reliable")
func die_with_dissolve_rpc() -> void:
	is_dying = true
	velocity = Vector2.ZERO
	
	# Disable collision box immediately on death
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
