extends CharacterBody2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@export var speed: float = 100.0
@onready var camera_2d: Camera2D = $Camera2D

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	camera_2d.make_current()
	camera_2d.enabled = true
	print("Camera Enabled")

func _physics_process(_delta):
	#var min_x = -67
	#var max_x = 68
	#var min_y = -58
	#var max_y = 71
	
	#global_position.x = clamp(global_position.x, min_x, max_x)
	#global_position.y = clamp(global_position.y, min_y, max_y)
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
