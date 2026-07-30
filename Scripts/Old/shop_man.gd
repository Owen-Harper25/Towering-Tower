extends CharacterBody2D
@onready var signman: Sprite2D = $Sign
@onready var interactable: Area2D = $Interactable
@export var speed: float = 40.0
var target_x: float
var is_arrived: bool = false
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var timer: Timer = $Timer
@onready var idle_timer: Timer = $Idle_Timer
var is_exiting = false

func _ready() -> void:
	interactable.interact = _on_interact
	var cam = get_viewport().get_camera_2d()
	if cam:
		target_x = cam.get_screen_center_position().x
	else:
		target_x = get_viewport_rect().size.x / 2
	var initial_wait = randf_range(10.0, 25.0)
	idle_timer.start(initial_wait)

func _process(delta: float) -> void:
	if is_arrived:
		return
		
	var direction = 1 if target_x > global_position.x else -1
	animated_sprite_2d.flip_h = (direction == -1)
	global_position.x += direction * speed * delta
	animated_sprite_2d.play("walk")
	
	if abs(global_position.x - target_x) < 5.0:
		if is_exiting:
			queue_free()
		else:
			is_arrived = true
			play_idle()
			animation_player.play("sit")
		
func play_idle():
	animated_sprite_2d.play("signless")
	
func set_target(new_target_pos: Vector2):
	target_x = new_target_pos.x
	is_arrived = false
	is_exiting = false

func exit_screen():
	is_exiting = true
	is_arrived = false
	
	var viewport_width = get_viewport_rect().size.x
	if global_position.x > viewport_width / 2:
		target_x = global_position.x + viewport_width
	else:
		target_x = global_position.x - viewport_width

func _on_timer_timeout() -> void:
	animated_sprite_2d.play("walk")

func _on_idle_timer_timeout() -> void:
	signman.visible = false
	exit_screen()
	
func _on_interact() -> void:
	print("Talking")
	
