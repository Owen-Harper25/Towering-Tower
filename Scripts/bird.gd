extends CharacterBody2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var caw_player: AudioStreamPlayer2D = $CawPlayer
@onready var flap_player: AudioStreamPlayer2D = $FlapPlayer
@onready var bird: Area2D = $Bird
@export var coin_scene: PackedScene
@export var speed: float = 60.0

enum State { FLY_IN, IDLE, TUCKER, SLEEP, ALERTED, FLEE }
var current_state = State.FLY_IN
var landing_x_pct: float = 0.0

func _ready():
	landing_x_pct = randf_range(20.0, 150.0)
	change_state(State.FLY_IN)
	bird.set_collision_mask_value(1, false)

func _physics_process(_delta):
	match current_state:
		State.FLY_IN:
			velocity = Vector2(speed, 0)
			move_and_slide()
			if not flap_player.playing: play_random_flap()
			var cam = get_viewport().get_camera_2d()
			var screen_left = cam.get_screen_center_position().x - 96
			var relative_x = global_position.x - screen_left
			if relative_x >= landing_x_pct:
				global_position.x = screen_left + landing_x_pct
				change_state(State.IDLE)
				
		State.FLEE:
			velocity = Vector2(speed * 2, -speed * 2)
			move_and_slide()
			if not flap_player.playing:
				play_random_flap()

func change_state(new_state):
	if current_state == new_state and new_state != State.FLY_IN:
		return
		
	current_state = new_state
	
	match current_state:
		State.FLY_IN:
			sprite.play("fly")
			
		State.IDLE:
			bird.set_collision_mask_value(1, true)
			velocity = Vector2.ZERO
			sprite.play("Idle")
			start_random_cawing()

			await get_tree().create_timer(20.0).timeout
			if current_state == State.IDLE:
				change_state(State.TUCKER)
			
		State.TUCKER:
			sprite.play("tucker")
			await get_tree().create_timer(3.0).timeout
			if current_state == State.TUCKER:
				change_state(State.SLEEP)
			
		State.SLEEP:
			sprite.play("Sleep")
			
		State.ALERTED:
			velocity = Vector2.ZERO
			sprite.play("alerted")
			play_caw(0.0) 
			await get_tree().create_timer(0.3).timeout
			change_state(State.FLEE)
			
		State.FLEE:
			bird.set_collision_mask_value(1, false)
			sprite.play("fly")
			await get_tree().create_timer(3.0).timeout
			queue_free()

func play_caw(start_time: float):
	if caw_player:
		caw_player.play(start_time)
		await get_tree().create_timer(1.2).timeout
		caw_player.stop()

func play_random_flap():
	if flap_player:
		var flaps = [0.0, 0.4, 0.8]
		flap_player.play(flaps.pick_random())
		
func start_random_cawing():
	while current_state == State.IDLE:
		await get_tree().create_timer(randf_range(4.0, 6.0)).timeout
		
		if current_state == State.IDLE:
			var caw_starts = [0.0, 9.4, 11.5, 21.4, 23]
			play_caw(caw_starts.pick_random())
			
func _on_bird_body_entered(body):
	if body.name == "Player" and current_state != State.FLEE:
		bird.set_collision_mask_value(1, false)
		change_state(State.ALERTED)
		var coin_chance = randi_range(0, 4)
		print(coin_chance)
		if coin_chance == 4:
			var coin = coin_scene.instantiate()
			var main_level = get_tree().current_scene
			main_level.add_child.call_deferred(coin)
			coin.global_position = global_position
		else: pass
