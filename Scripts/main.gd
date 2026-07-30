extends Node2D

const PLAYER = preload("uid://dflfyebeka06d")
const IRIS_TRANSITION_SHADER := preload("res://Shaders/iris_transition.gdshader")

# --- UI References (Matching Exact Scene Tree) ---
@onready var menu_canvas_layer: CanvasLayer = $"CanvasLayer/Main Menu/CanvasLayer"
@onready var main_menu: Control = $"CanvasLayer/Main Menu"
@onready var server_browser: Control = $"CanvasLayer/Main Menu/CanvasLayer/Server Browser"
@onready var lobby_list_container: VBoxContainer = $"CanvasLayer/Main Menu/CanvasLayer/Server Browser/LobbyBrowser/ScrollContainer/LobbyListContainer"
@onready var refresh_button: Button = $"CanvasLayer/Main Menu/CanvasLayer/Server Browser/RefreshButton"
@onready var back_button: Button = $"CanvasLayer/Main Menu/CanvasLayer/Server Browser/LobbyBackButton"

# --- Audio & Display References ---
@onready var song_queue: Label = $"CanvasLayer/Song Text/Song Queue"
@onready var song_name_anim: AnimationPlayer = $"CanvasLayer/Song Text/Song Queue/SongName Anim"
@onready var break_timer: Timer = $Timers/MusicBreakTimer

# --- Level & Player References ---
@export var default_level_scene: PackedScene = preload("res://Scenes/lobby.tscn")
const ARENA_SCENE := preload("res://Scenes/arena.tscn")
@onready var level_container: Node = $"Level Container"
@onready var players_container: Node2D = $"Level Container/Players"

var players: Array[CharacterBody2D]
var background_songs = []
var current_song_index: int = 0
var music: bool = false
var current_loop_count: int = 0
@export var loops_per_song: int = 2
var current_level: Node = null
var transition_overlay: ColorRect
var transition_tween: Tween
var transition_material: ShaderMaterial

func _ready() -> void:
	add_to_group("main")
	Networking.host_created.connect(on_host_created)
	Networking.client_joined.connect(on_client_joined)
	Networking.lobby_list_received.connect(_on_lobby_match_list)
	multiplayer.peer_connected.connect(spawn_player)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	menu_canvas_layer.show()
	create_scene_transition_overlay()
	
	# Setup Music System
	background_songs = $Music.get_children()
	for i in background_songs:
		if i is AudioStreamPlayer2D or i is AudioStreamPlayer:
			i.bus = &"Music"
			i.finished.connect(on_song_fin)
	break_timer.timeout.connect(play_next_random_song)
	play_next_random_song()

# --- STEAM LOBBY BROWSER SYSTEM ---

func request_lobby_browser() -> void:
	# Clear current list UI entries
	for child in lobby_list_container.get_children():
		child.queue_free()

	print("Requesting active lobbies from Steam...")

	Networking.request_lobbies()

func _on_lobby_match_list(lobbies: Array) -> void:
	# Clear container again to ensure fresh list
	for child in lobby_list_container.get_children():
		child.queue_free()

	if lobbies.is_empty():
		var no_lobbies_label := Label.new()
		no_lobbies_label.text = "No public lobbies found."
		lobby_list_container.add_child(no_lobbies_label)
		return

	for lobby_id in lobbies:
		var lobby_name: String = Steam.getLobbyData(lobby_id, "name")
		var member_count: int = Steam.getNumLobbyMembers(lobby_id)
		var max_members: int = Steam.getLobbyMemberLimit(lobby_id)

		if lobby_name == "":
			lobby_name = "Lobby #" + str(lobby_id)

		var lobby_button := Button.new()
		lobby_button.text = "%s  |  Players: %d / %d" % [lobby_name, member_count, max_members]
		
		if member_count >= max_members:
			lobby_button.disabled = true

		lobby_button.pressed.connect(func(): join_lobby_by_id(lobby_id))
		lobby_list_container.add_child(lobby_button)

# --- SERVER BROWSER BUTTON HANDLERS ---

func _on_join_button_pressed() -> void:
	if server_browser:
		server_browser.show()
	request_lobby_browser()

func _on_refresh_button_pressed() -> void:
	request_lobby_browser()

func _on_lobby_back_button_pressed() -> void:
	if server_browser:
		server_browser.hide()

# --- JOIN & NETWORKING HANDLERS ---

func join_lobby_by_id(lobby_id: int) -> void:
	menu_canvas_layer.hide()
	if Networking.has_method("join_lobby"):
		Networking.join_lobby(lobby_id)

func on_host_created() -> void:
	spawn_player(multiplayer.get_unique_id())

func on_client_joined() -> void:
	menu_canvas_layer.hide()
	load_level(default_level_scene)

func spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if not current_level:
		load_level(default_level_scene)
	if current_level.has_method("can_players_join") and not current_level.can_players_join():
		return

	var new_player := PLAYER.instantiate() as CharacterBody2D
	new_player.name = str(peer_id)
	
	level_container.add_child(new_player, true)
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
	menu_canvas_layer.hide()
	Networking.host_lobby()
	load_level(default_level_scene)

func _on_solo_pressed() -> void:
	menu_canvas_layer.hide()
	var offline_peer = OfflineMultiplayerPeer.new()
	multiplayer.multiplayer_peer = offline_peer
	load_level(default_level_scene)
	spawn_player(1)

func _on_multiplayer_spawner_spawned(node: Node) -> void:
	if node is CharacterBody2D:
		initialize_player(node)

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return

	var player_node = level_container.get_node_or_null(str(id))
	if not player_node and current_level:
		player_node = current_level.get_node_or_null(str(id))

	if player_node:
		if players.has(player_node):
			players.erase(player_node)
		player_node.queue_free()

func start_combat_from_lobby() -> void:
	if multiplayer.is_server():
		rpc("start_combat_rpc")
	else:
		rpc_id(1, "request_start_combat_rpc")

@rpc("any_peer", "reliable")
func request_start_combat_rpc() -> void:
	if multiplayer.is_server():
		rpc("start_combat_rpc")

@rpc("authority", "call_local", "reliable")
func start_combat_rpc() -> void:
	if current_level and current_level.is_in_group("tower_arena"):
		return
	if multiplayer.is_server() and Networking.has_method("set_lobby_joinable"):
		Networking.set_lobby_joinable(false)
	load_level(ARENA_SCENE)
	for player in players:
		if is_instance_valid(player):
			player.global_position = Vector2(240, 136)

func return_party_to_lobby() -> void:
	if multiplayer.is_server():
		rpc("return_party_to_lobby_rpc")
	else:
		rpc_id(1, "request_return_party_to_lobby_rpc")

@rpc("any_peer", "reliable")
func request_return_party_to_lobby_rpc() -> void:
	if multiplayer.is_server():
		rpc("return_party_to_lobby_rpc")

@rpc("authority", "call_local", "reliable")
func return_party_to_lobby_rpc() -> void:
	if multiplayer.is_server() and Networking.has_method("set_lobby_joinable"):
		Networking.set_lobby_joinable(true)
	load_level(default_level_scene)
	for player in players:
		if is_instance_valid(player):
			player.global_position = Vector2(240, 136)
			player.rpc("reset_for_lobby_rpc")

# --- LEVEL SWITCHING SYSTEM ---

func load_level(level_scene: PackedScene) -> void:
	if current_level and transition_overlay:
		transition_to_level(level_scene)
		return
	perform_load_level(level_scene)
	play_scene_transition()

func perform_load_level(level_scene: PackedScene) -> void:
	if current_level:
		current_level.queue_free()
		current_level = null
		
	current_level = level_scene.instantiate()
	level_container.add_child(current_level)
	
	if current_level.has_node("SpawnPoint"):
		$SpawnPoint.global_position = current_level.get_node("SpawnPoint").global_position

func create_scene_transition_overlay() -> void:
	var transition_layer := CanvasLayer.new()
	transition_layer.layer = 100
	transition_overlay = ColorRect.new()
	transition_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	transition_material = ShaderMaterial.new()
	transition_material.shader = IRIS_TRANSITION_SHADER
	transition_overlay.material = transition_material
	transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transition_overlay.hide()
	transition_layer.add_child(transition_overlay)
	add_child(transition_layer)

func play_scene_transition() -> void:
	if not transition_overlay:
		return
	if transition_tween and transition_tween.is_valid():
		transition_tween.kill()
	transition_overlay.show()
	set_iris_radius(0.0)
	transition_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	transition_tween.tween_method(set_iris_radius, 0.0, 1.6, 0.32)
	transition_tween.tween_callback(transition_overlay.hide)

func transition_to_level(level_scene: PackedScene) -> void:
	if transition_tween and transition_tween.is_valid():
		transition_tween.kill()
	transition_overlay.show()
	set_iris_radius(1.6)
	transition_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	transition_tween.tween_method(set_iris_radius, 1.6, 0.0, 0.22)
	transition_tween.tween_callback(func(): perform_load_level(level_scene))
	transition_tween.tween_method(set_iris_radius, 0.0, 1.6, 0.30)
	transition_tween.tween_callback(transition_overlay.hide)

func set_iris_radius(radius: float) -> void:
	if transition_material:
		transition_material.set_shader_parameter("iris_radius", radius)

func change_level_networked(new_level_path: String) -> void:
	if not multiplayer.is_server():
		return
	rpc("sync_level_change", new_level_path)

@rpc("call_local", "reliable")
func sync_level_change(level_path: String) -> void:
	var next_level_scene = load(level_path) as PackedScene
	if next_level_scene:
		load_level(next_level_scene)

# --- MUSIC & MISC HANDLERS ---

func on_song_fin():
	current_loop_count += 1
	if current_loop_count < loops_per_song:
		background_songs[current_song_index].play()
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
	
	song_queue.text = "Now Playing: " + str(song.name)
	song_name_anim.play("new_song")

func _on_button_2_pressed() -> void:
	background_songs[current_song_index].stop()
	on_song_fin()

func _on_mute_pressed() -> void:
	if music:
		music = false
		background_songs[current_song_index].stop()
	else:
		background_songs[current_song_index].play()
		music = true

func _on_friends_pressed() -> void:
	if Steam:
		Steam.activateGameOverlay("Friends")

func join_friend_game(friend_steam_id: int) -> void:
	# Query Steam for the lobby your friend is currently sitting in
	var lobby_id: int = Steam.getFriendCoplayGame(friend_steam_id)
	
	if lobby_id != 0:
		print("Found friend's lobby! Joining: ", lobby_id)
		join_lobby_by_id(lobby_id)
	else:
		print("Friend is not currently in a joinable lobby.")
