extends Node2D

const PLAYER = preload("uid://dflfyebeka06d")

var players: Array[CharacterBody2D]
@onready var players_container: Node2D = $Arena/Players
@onready var song_queue: Label = $"CanvasLayer/Song Text/Song Queue"
@onready var song_name_anim: AnimationPlayer = $"CanvasLayer/Song Text/Song Queue/SongName Anim"
var background_songs = []
var current_song_index: int = 0
var music: bool = false
var current_loop_count: int = 0
@export var loops_per_song: int = 2
@onready var break_timer: Timer = $Timers/MusicBreakTimer

func _ready() -> void:
	Networking.host_created.connect(on_host_created)
	multiplayer.peer_connected.connect(spawn_player)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	background_songs = $Audio.get_children()
	for i in background_songs:
		if i is AudioStreamPlayer2D or i is AudioStreamPlayer:
			i.finished.connect(on_song_fin)
	break_timer.timeout.connect(play_next_random_song)
	play_next_random_song()
	
func on_host_created() -> void:
	spawn_player(multiplayer.get_unique_id())
	
func spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var new_player := PLAYER.instantiate() as CharacterBody2D
	
	new_player.name = str(peer_id)
	
	$Arena/Players.add_child(new_player, true)
	initialize_player(new_player)
	
func initialize_player(player: CharacterBody2D) -> void:
	player.position = $SpawnPoint.position
	
	players = players.filter(func(p): return is_instance_valid(p))
	
	for other in players:
		if is_instance_valid(other) and other != player:
			player.add_collision_exception_with(other)
			other.add_collision_exception_with(player)
			
	if not players.has(player):
		players.append(player)

func _on_host_pressed() -> void:
	Networking.host_lobby()

func _on_multiplayer_spawner_spawned(node: Node) -> void:
	if node is CharacterBody2D:
		initialize_player(node)
		
func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return

	var player_node = players_container.get_node_or_null(str(id))
	if player_node:
		if players.has(player_node):
			players.erase(player_node)
			
		player_node.queue_free()
		
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
		#volume_img_2.visible = true
		#volume_img.visible = false
		
	elif not music == true:
		background_songs[current_song_index].play()
		music = true
		#volume_img_2.visible = false
		#volume_img.visible = true
