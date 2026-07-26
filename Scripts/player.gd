extends CharacterBody2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@export var speed: float = 100.0
@onready var camera: Camera2D = $Camera2D

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	if is_multiplayer_authority():
		camera.make_current()
		camera.enabled = true
	else:
		camera.enabled = false
		camera.process_mode = Node.PROCESS_MODE_DISABLED

func _physics_process(_delta: float) -> void:
	if is_multiplayer_authority():
		var input_dir: Vector2 = Vector2.ZERO
		input_dir.x = Input.get_axis("Left", "Right")
		input_dir.y = Input.get_axis("Up", "Down")

		if input_dir != Vector2.ZERO:
			velocity = input_dir.normalized() * speed
			sprite.play("move")
			
			if input_dir.x < 0:
				sprite.flip_h = true
			elif input_dir.x > 0:
				sprite.flip_h = false
		else:
			velocity = Vector2.ZERO
			sprite.play("Idle")

		move_and_slide()
