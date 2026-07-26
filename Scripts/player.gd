extends CharacterBody2D

@export var player_name: String = "":
	set(value):
		player_name = value
		if character_name:
			character_name.text = value

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@export var speed: float = 100.0
@onready var camera: Camera2D = $Camera2D
@onready var character_name: Label = $CharacterName

func _enter_tree() -> void:
	# Set authority strictly inside _enter_tree based on peer_id node name
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	if is_multiplayer_authority():
		camera.make_current()
		camera.enabled = true
		
		# Set local player name and sync to all existing/future peers
		player_name = Steam.getPersonaName()
		rpc("sync_name", player_name)
	else:
		camera.enabled = false
		camera.process_mode = Node.PROCESS_MODE_DISABLED

# Sync name using call_local and reliable RPCs
@rpc("any_peer", "call_local", "reliable")
func sync_name(new_name: String) -> void:
	player_name = new_name

func _physics_process(_delta: float) -> void:
	# Ezcha Guide Rule: ONLY the authority processes movement input & physics
	if is_multiplayer_authority():
		var input_dir: Vector2 = Vector2.ZERO
		input_dir.x = Input.get_axis("Left", "Right")
		input_dir.y = Input.get_axis("Up", "Down")
		
		if input_dir != Vector2.ZERO:
			velocity = input_dir.normalized() * speed
		else:
			velocity = Vector2.ZERO
			
		move_and_slide()

	# Visual/Animation updates run locally on every client using synced velocity
	update_animations()

func update_animations() -> void:
	if velocity.length() > 0:
		sprite.play("move")
		if velocity.x < 0:
			sprite.flip_h = true
		elif velocity.x > 0:
			sprite.flip_h = false
	else:
		sprite.play("Idle")
