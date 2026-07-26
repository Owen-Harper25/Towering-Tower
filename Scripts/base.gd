extends Node2D

#Timers
@onready var bird_timer: Timer = $Timers/Bird_Timer
@onready var seasons_timer: Timer = $Timers/Seasons_Timer
@onready var event_timer: Timer = $Timers/Event_Timer
@onready var break_timer: Timer = $Timers/MusicBreakTimer
@onready var auto_save: Timer = $Timers/AutoSave

#Scenes
@onready var player: CharacterBody2D = $Player
@export var crow_scene: PackedScene
@export var robin_scene: PackedScene
@export var apple_scene: PackedScene
@export var banana_scene: PackedScene
@onready var top_layer: ColorRect = $TopLayer
@onready var count: Label = $Count
@onready var type: Label = $Type
@onready var grading_node: ColorRect = $"Post Processing"
@onready var song_queue: Label = $"Song Text/Song Queue"
@onready var song_name_anim: AnimationPlayer = $"Song Text/Song Queue/SongName Anim"
@onready var volume_img: Sprite2D = $"Volume Img"
@onready var volume_img_2: Sprite2D = $"Volume Img2"
@export var shop_man_scene: PackedScene
@onready var shop_timer: Timer = $Timers/Shop_Timer

#Seasons
@export var flower_scenes: Array[PackedScene]
@export var grass_scenes: Array[PackedScene]
@export var foliage_count: int = 25
enum Season { WINTER, SPRING, SUMMER, FALL }
var current_season = Season.WINTER

#Other
var apple_count = 0
var banana_count = 0
var coin_count = 0
var background_songs = []
var current_song_index: int = 0
var music: bool = false
var current_loop_count: int = 0
@export var loops_per_song: int = 2

func _ready() -> void:
	#apple_count = SaveLoad.SaveFileData.apple_count
	#current_season = SaveLoad.SaveFileData.current_season -1
	#banana_count = SaveLoad.SaveFileData.banana_count 
	#coin_count = SaveLoad.SaveFileData.coin_count
	#if "player_position" in SaveLoad.SaveFileData and SaveLoad.SaveFileData.player_position != Vector2.ZERO:
		#player.global_position = SaveLoad.SaveFileData.player_position
	scedule_next_spawn()
	schedule_shop_spawn()
	seasons_timer.timeout.connect(self._on_seasons_timer_timeout)
	count.text = str(apple_count)
	change_season()
	var initial_wait = randf_range(300.0, 600.0)
	seasons_timer.start(initial_wait)
	background_songs = $Audio.get_children()
	for i in background_songs:
		if i is AudioStreamPlayer2D or i is AudioStreamPlayer:
			i.finished.connect(on_song_fin)
	break_timer.timeout.connect(play_next_random_song)
	play_next_random_song()
	
func spawn_shop_man():
	if not shop_man_scene: 
		print("Warning: No Shop Man scene assigned!")
		return
		
	var shop_man = shop_man_scene.instantiate()
	add_child(shop_man)
	
	var viewport_size = get_viewport_rect().size
	var cam = get_viewport().get_camera_2d()
	
	var spawn_x: float
	var spawn_y: float
	
	if cam:
		var cam_pos = cam.get_screen_center_position()
		# Determine if he spawns left (-1) or right (1)
		var side = 1 if randf() > 0.5 else -1
			
		spawn_x = cam_pos.x + (side * (viewport_size.x / 2 + 100))
		spawn_y = cam_pos.y + randf_range(-viewport_size.y * 0.2, viewport_size.y * 0.2)
	else:
		spawn_x = viewport_size.x + 100
		spawn_y = viewport_size.y / 2

	shop_man.global_position = Vector2(spawn_x, spawn_y)
	
	if shop_man.has_method("set_target"):
		shop_man.set_target(cam.get_screen_center_position() if cam else Vector2.ZERO)

	schedule_shop_spawn()
func schedule_shop_spawn():
	var wait_time = randf_range(120.0, 240.0)
	shop_timer.start(wait_time)
func _on_shop_timer_timeout() -> void:
	spawn_shop_man()

func spawn_foliage():
	var cam = get_viewport().get_camera_2d()
	var spawn_origin: Vector2
	var view_size: Vector2
	
	if cam:
		view_size = get_viewport_rect().size / cam.zoom
		spawn_origin = cam.get_screen_center_position() - (view_size / 2)
	else:
		view_size = get_viewport_rect().size
		spawn_origin = Vector2.ZERO
		
	for i in range(foliage_count):
		var list = flower_scenes if randf() > 0.5 else grass_scenes
		if list.is_empty(): continue
		
		var instance = list.pick_random().instantiate()
		add_child(instance)
		instance.add_to_group("foliage")
		if instance.material is ShaderMaterial:
			instance.material = instance.material.duplicate()
			instance.material.set_shader_parameter("dissolve_value", 0.0)
			
			var t = create_tween()
			t.tween_interval(randf_range(0.1, 0.5)) 
			t.tween_property(instance.material, "shader_parameter/dissolve_value", 1.0, 1.5)
			
		var rx = spawn_origin.x + randf_range(view_size.x * 0.15, view_size.x * 0.85)
		var ry = spawn_origin.y + randf_range(view_size.y * 0.20, view_size.y * 0.80)
		instance.global_position = Vector2(rx, ry).snapped(Vector2(1,1))
func trigger_foliage_dissolve():
	for foliage in get_tree().get_nodes_in_group("foliage"):
		if foliage.material is ShaderMaterial:
			var t = create_tween()
			t.tween_interval(randf_range(0.0, 1.0))
			t.tween_property(foliage.material, "shader_parameter/dissolve_value", 0.0, 2.0)
			t.finished.connect(foliage.queue_free)
func apple_count_changed():
	apple_count += 1
	count.text = str(apple_count)
	spawn_next.call_deferred()
func banana_count_changed():
	banana_count += 1
	count.text = str(banana_count)
	spawn_next.call_deferred()
func change_season():
	current_season = (current_season + 1) as Season
	if current_season > Season.FALL:
		current_season = Season.WINTER
		
	var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	var top_color : Color
	var ground_color : Color
	var target_vibrancy : float = 1.0
	var grading_color : Vector3
	var target_brightness : float = 1.0
	var swirl_color1 : Color
	var swirl_color2 : Color
	var swirl_color3 : Color
	
	match current_season:
		Season.WINTER:
			top_color = Color("ffffffff")
			ground_color = Color("5094efff")
			grading_color = Vector3(0.85, 0.9, 1.1)
			target_vibrancy = 0.5
			target_brightness = 1.2
			swirl_color1 = Color("5094efff")
			swirl_color2 = Color("eaeaeaff")
			swirl_color3 = Color("d0f3fcff")
			
		Season.SPRING:
			top_color = Color("82c072ff")
			ground_color = Color("94b072ff")
			grading_color = Vector3(1.0, 1.0, 0.9)
			target_vibrancy = 1.2
			target_brightness = 1
			swirl_color1 = Color("52a3e9ff")
			swirl_color2 = Color("10a4ffff")
			swirl_color3 = Color("ffffffff")
			spawn_foliage()
			
		Season.SUMMER:
			top_color = Color("d0e295ff")
			ground_color = Color("c6ca67ff")
			grading_color = Vector3(1.1, 1.05, 0.8)
			target_vibrancy = 1.1
			target_brightness = 0.95
			swirl_color1 = Color("ffb874ff")
			swirl_color2 = Color("FFCAA4")
			swirl_color3 = Color("FFE9AE")
		Season.FALL:
			top_color = Color("7a1220ff")
			ground_color = Color("e5374aff")
			grading_color = Vector3(1.2, 0.9, 0.8)
			target_vibrancy = 0.5
			target_brightness = 1.0
			swirl_color1 = Color("FFE6EE")
			swirl_color2 = Color("FEDCDB")
			swirl_color3 = Color("f16f80ff")
			trigger_foliage_dissolve()
	
	var swirl_bg = $ColorRect
	if swirl_bg:
		swirl_bg.material.set_shader_parameter("colour_1", swirl_color1)
		swirl_bg.material.set_shader_parameter("colour_2", swirl_color2)
		swirl_bg.material.set_shader_parameter("colour_3", swirl_color3)
		var tween_bg = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		# Use "modulate" to tint the existing swirl texture/shader
		tween_bg.tween_property(swirl_bg, "modulate", swirl_color1, 3.0)
		tween_bg.tween_property(swirl_bg, "modulate", swirl_color2, 3.0)
		tween_bg.tween_property(swirl_bg, "modulate", swirl_color3, 3.0)
		
	if grading_node:
		var mat = grading_node.material as ShaderMaterial
		var tween2 = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		# Animate the tint
		tween2.tween_property(mat, "shader_parameter/color_shift", grading_color, 3.0)
		# Animate the vibrancy
		tween2.parallel().tween_property(mat, "shader_parameter/vibrancy", target_vibrancy, 3.0)
		tween2.parallel().tween_property(mat, "shader_parameter/brightness", target_brightness, 3.0)
		
	var snow_node = $Snow
	var wind_node = $Wind
	var leaf_node = $Leaf
	var snow_layer = get_node("TopLayer")
	var ice_layer = get_node("BaseLayer")

	if snow_layer and ice_layer:
		tween.tween_property(snow_layer, "color", top_color, 3.0)
		tween.parallel().tween_property(ice_layer, "color", ground_color, 3.0)
	else:
		print("ERROR: Could not find ColorRect nodes!")
	
	if snow_node:
		if current_season == Season.WINTER:
			snow_node.emitting = true
			leaf_node.emitting = false
			wind_node.emitting = true
			top_layer.fade_speed = 0.5
		if current_season == Season.SPRING:
			snow_node.emitting = false
			leaf_node.emitting = false
			top_layer.fade_speed = 0.7
		if current_season == Season.SUMMER:
			snow_node.emitting = false
			leaf_node.emitting = false
			top_layer.fade_speed = 0.7
		if current_season == Season.FALL:
			snow_node.emitting = false
			wind_node.emitting = true
			leaf_node.emitting = true
			top_layer.fade_speed = 0.6
func scedule_next_spawn():
	var wait_time = randf_range(10.0, 30.0)
	$Timers/Bird_Timer.start(wait_time)
func spawn_next():
	var next_fruit = randi_range(0, 49)
	var instance: Node2D
	
	if next_fruit <= 47:
		if not apple_scene: return
		instance = apple_scene.instantiate()
		type.text = "APPLE"
		type.label_settings.font_color = Color.FIREBRICK
		count.text = str(apple_count)
	else:
		if not banana_scene: return
		instance = banana_scene.instantiate()
		type.text = "BANANA"
		type.label_settings.font_color = Color.GOLD
		count.text = str(banana_count)

	add_child(instance)
	instance.add_to_group("fruit")

	var viewport_size = get_viewport_rect().size
	var cam = get_viewport().get_camera_2d()
	var spawn_pos: Vector2

	if cam:
		var cam_pos = cam.get_screen_center_position()
		var top_left = cam_pos - (viewport_size / 2)
		spawn_pos.x = top_left.x + randf_range(viewport_size.x * 0.2, viewport_size.x * 0.8)
		spawn_pos.y = top_left.y + randf_range(viewport_size.y * 0.2, viewport_size.y * 0.8)
	else:
		spawn_pos.x = randf_range(viewport_size.x * 0.2, viewport_size.x * 0.8)
		spawn_pos.y = randf_range(viewport_size.y * 0.2, viewport_size.y * 0.8)
	
	instance.global_position = spawn_pos
func spawn_crow():
	if not crow_scene: return
		
	var crow = crow_scene.instantiate()
	add_child(crow)
	
	var viewport_size = get_viewport_rect().size
	var cam = get_viewport().get_camera_2d()
	
	var spawn_x: float
	var spawn_y: float
	
	if cam:
		var cam_left_edge = cam.get_screen_center_position().x - (viewport_size.x / 2)
		spawn_x = cam_left_edge - 150 # Start 150 pixels outside the left edge
		
		var cam_top_edge = cam.get_screen_center_position().y - (viewport_size.y / 2)
		spawn_y = cam_top_edge + randf_range(viewport_size.y * 0.2, viewport_size.y * 0.8)
	else:
		# Fallback if there is no camera
		spawn_x = -150
		spawn_y = randf_range(viewport_size.y * 0.1, viewport_size.y * 0.9)
	
	crow.global_position = Vector2(spawn_x, spawn_y)
	
	if "speed" in crow:
		crow.speed = randf_range(60.0, 90.0)
func spawn_robin():
	if not robin_scene: return
		
	var robin = robin_scene.instantiate()
	add_child(robin)
	
	var viewport_size = get_viewport_rect().size
	var cam = get_viewport().get_camera_2d()
	
	var spawn_x: float
	var spawn_y: float
	
	if cam:
		var cam_left_edge = cam.get_screen_center_position().x - (viewport_size.x / 2)
		spawn_x = cam_left_edge - 150 # Start 150 pixels outside the left edge
		
		var cam_top_edge = cam.get_screen_center_position().y - (viewport_size.y / 2)
		spawn_y = cam_top_edge + randf_range(viewport_size.y * 0.2, viewport_size.y * 0.8)
	else:
		# Fallback if there is no camera
		spawn_x = -150
		spawn_y = randf_range(viewport_size.y * 0.1, viewport_size.y * 0.9)
	
	robin.global_position = Vector2(spawn_x, spawn_y)
	
	if "speed" in robin:
		robin.speed = randf_range(60.0, 90.0)
func _on_bird_timer_timeout() -> void:
	var spawns = randi_range(0, 1)
	if spawns == 0:
		spawn_crow()
	if spawns == 1:
		spawn_robin()
	scedule_next_spawn()
func coin_count_changed():
	pass
func _on_button_pressed() -> void:
	change_season()
func on_song_fin():
	current_loop_count += 1
	if current_loop_count < loops_per_song:
		background_songs[current_song_index].play()
		print("Looping: ", background_songs[current_song_index].name, " (", current_loop_count + 1, "/", loops_per_song, ")")
	else:
		fade_out_and_next()
func fade_out_and_next():
	var song = background_songs[current_song_index]
	var fade_tween = create_tween()
	fade_tween.tween_property(song, "volume_db", -80.0, 3.0)
	fade_tween.finished.connect(func():
		song.stop()
		var wait_time = randf_range(3.0, 5.0)
		break_timer.start(wait_time)
	)
func play_next_random_song():
	var next_song = randi() % background_songs.size()
	while next_song == current_song_index and background_songs.size() > 1:
		next_song = randi() % background_songs.size()
	
	current_song_index = next_song
	current_loop_count = 0
	
	var song = background_songs[current_song_index]
	song.volume_db = 0
	song.play()
	
	print("Playing: ", song.name)
	song_queue.text = "Now Playing: " + str(song.name)
	song_name_anim.play("new_song")
func _on_button_2_pressed() -> void:
	background_songs[current_song_index].stop()
	on_song_fin()
func _on_mute_pressed() -> void:
	#print(music)
	if music == true:
		music = false
		background_songs[current_song_index].stop()
		volume_img_2.visible = true
		volume_img.visible = false
		
	elif not music == true:
		background_songs[current_song_index].play()
		music = true
		volume_img_2.visible = false
		volume_img.visible = true
func _on_seasons_timer_timeout() -> void:
	change_season()
	var next_wait = randf_range(300.0, 600.0)
	seasons_timer.start(next_wait)
	print("Season changed. Next change in: ", next_wait / 60.0, " minutes.")
func _on_button_3_pressed() -> void:
	spawn_shop_man()


#func _on_save_pressed() -> void:
	#save_game()

#func save_game():
	#SaveLoad.SaveFileData.apple_count = apple_count
	#SaveLoad.SaveFileData.current_season = current_season
	#SaveLoad.SaveFileData.banana_count = banana_count
	#SaveLoad.SaveFileData.coin_count = coin_count
	#SaveLoad.SaveFileData.flower_scenes = flower_scenes
	#SaveLoad.SaveFileData.grass_scenes = grass_scenes
	#SaveLoad.SaveFileData.player_position = player.global_position
	#SaveLoad._save()

#
#func _on_auto_save_timeout() -> void:
	#auto_save.start()
	#save_game()
