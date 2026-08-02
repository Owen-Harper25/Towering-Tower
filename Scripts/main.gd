extends Node2D

const PLAYER = preload("uid://dflfyebeka06d")
const IRIS_TRANSITION_SHADER := preload("res://Shaders/iris_transition.gdshader")
const GAME_GRADE_SHADER := preload("res://Shaders/game_grade.gdshader")

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
const SURVIVAL_ARENA_SCENE := preload("res://Scenes/survival_arena.tscn")
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
var game_grade_material: ShaderMaterial
var post_process_tween: Tween
var game_grade_darkness := 0.985
var game_grade_glow := 0.025
var party_return_in_progress := false
var mode_transition_in_progress := false
var runtime_menu_open := false
var single_player_pause_reasons: Dictionary = {}

func _ready() -> void:
	# Keep global UI/input responsive while gameplay below Level Container is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	level_container.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("main")
	Networking.host_created.connect(on_host_created)
	Networking.client_joined.connect(on_client_joined)
	Networking.lobby_list_received.connect(_on_lobby_match_list)
	multiplayer.peer_connected.connect(spawn_player)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	menu_canvas_layer.show()
	create_scene_transition_overlay()
	create_game_post_process()
	
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
	close_runtime_menu()
	menu_canvas_layer.hide()
	if Networking.has_method("join_lobby"):
		Networking.join_lobby(lobby_id)

func on_host_created() -> void:
	spawn_player(multiplayer.get_unique_id())

func on_client_joined() -> void:
	close_runtime_menu()
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
	close_runtime_menu()
	menu_canvas_layer.hide()
	Networking.host_lobby()
	load_level(default_level_scene)

func _on_solo_pressed() -> void:
	close_runtime_menu()
	menu_canvas_layer.hide()
	var offline_peer = OfflineMultiplayerPeer.new()
	multiplayer.multiplayer_peer = offline_peer
	load_level(default_level_scene)
	spawn_player(1)

func _unhandled_input(event: InputEvent) -> void:
	if not current_level or not event.is_action_pressed("ui_cancel"):
		return
	if current_level.is_in_group("tower_arena") and bool(current_level.get("boon_book_open")):
		current_level.call("close_boon_book")
		get_viewport().set_input_as_handled()
		return
	if runtime_menu_open:
		close_runtime_menu()
	else:
		open_runtime_menu()
	get_viewport().set_input_as_handled()

func open_runtime_menu() -> void:
	runtime_menu_open = true
	menu_canvas_layer.show()
	main_menu.show()
	if main_menu.has_method("set_runtime_context"):
		main_menu.call("set_runtime_context", true, true)
	set_local_player_ui_locked(true)
	set_single_player_menu_paused("runtime_menu", true)

func close_runtime_menu() -> void:
	if not runtime_menu_open:
		set_single_player_menu_paused("runtime_menu", false)
		return
	runtime_menu_open = false
	var settings_panel := main_menu.get_node_or_null("CanvasLayer/SettingsMenu") as Control
	if settings_panel:
		settings_panel.hide()
	menu_canvas_layer.hide()
	set_local_player_ui_locked(false)
	set_single_player_menu_paused("runtime_menu", false)

func set_single_player_menu_paused(reason: String, should_pause: bool) -> void:
	if should_pause:
		if not is_offline_single_player_session():
			return
		single_player_pause_reasons[reason] = true
	else:
		single_player_pause_reasons.erase(reason)
	get_tree().paused = not single_player_pause_reasons.is_empty()

func is_offline_single_player_session() -> bool:
	return current_level != null and multiplayer.multiplayer_peer is OfflineMultiplayerPeer

func clear_single_player_menu_pauses() -> void:
	single_player_pause_reasons.clear()
	get_tree().paused = false

func set_local_player_ui_locked(locked: bool) -> void:
	for player in players:
		if is_instance_valid(player) and player.is_multiplayer_authority():
			player.set("ui_input_locked", locked)

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

func start_survival_from_lobby() -> void:
	if multiplayer.is_server():
		rpc("start_survival_rpc")
	else:
		rpc_id(1, "request_start_survival_rpc")

@rpc("any_peer", "reliable")
func request_start_survival_rpc() -> void:
	if multiplayer.is_server():
		rpc("start_survival_rpc")

@rpc("authority", "call_local", "reliable")
func start_survival_rpc() -> void:
	if mode_transition_in_progress or (current_level and current_level.is_in_group("survival_arena")):
		return
	mode_transition_in_progress = true
	party_return_in_progress = false
	if multiplayer.is_server() and Networking.has_method("set_lobby_joinable"):
		Networking.set_lobby_joinable(false)
	play_party_teleport_effect()
	load_level(SURVIVAL_ARENA_SCENE)
	finish_mode_teleport_after_load(true)

func leave_survival_mode() -> void:
	# Leaving Popcorn returns the connected party through the host. A guest must
	# never close its Steam peer here or it will create a separate offline lobby.
	return_party_to_lobby()

@rpc("any_peer", "reliable")
func request_start_combat_rpc() -> void:
	if multiplayer.is_server():
		rpc("start_combat_rpc")

@rpc("authority", "call_local", "reliable")
func start_combat_rpc() -> void:
	if mode_transition_in_progress or (current_level and current_level.is_in_group("tower_arena")):
		return
	mode_transition_in_progress = true
	if multiplayer.is_server() and Networking.has_method("set_lobby_joinable"):
		Networking.set_lobby_joinable(false)
	play_party_teleport_effect()
	load_level(ARENA_SCENE)
	finish_mode_teleport_after_load(false)

func finish_mode_teleport_after_load(use_survival_spawn_ring: bool) -> void:
	get_tree().create_timer(0.26).timeout.connect(func():
		if use_survival_spawn_ring:
			position_party_in_survival_spawn_ring()
		for player in players:
			if not is_instance_valid(player):
				continue
			if not use_survival_spawn_ring:
				player.global_position = Vector2(240.0, 136.0)
			if player.has_method("reset_teleport_visual"):
				player.call("reset_teleport_visual")
		mode_transition_in_progress = false
	)

func position_party_in_survival_spawn_ring() -> void:
	var valid_players: Array[CharacterBody2D] = []
	for player in players:
		if is_instance_valid(player):
			valid_players.append(player)
	valid_players.sort_custom(func(a: Node, b: Node): return a.name.naturalnocasecmp_to(b.name) < 0)
	var arena_center := Vector2(450.0, 300.0)
	for player_index in range(valid_players.size()):
		var angle := TAU * float(player_index) / float(maxi(1, valid_players.size()))
		valid_players[player_index].global_position = arena_center + Vector2.from_angle(angle) * 72.0

func play_party_teleport_effect() -> void:
	var effect_layer := CanvasLayer.new()
	effect_layer.layer = 110
	add_child(effect_layer)
	var canvas_transform := get_viewport().get_canvas_transform()
	var beam_height := get_viewport_rect().size.y + 96.0
	for player in players:
		if not is_instance_valid(player):
			continue
		if player.has_method("play_teleport_departure_visual"):
			player.call("play_teleport_departure_visual")
		create_teleport_beam(effect_layer, canvas_transform * player.global_position, beam_height)
	get_tree().create_timer(0.62).timeout.connect(effect_layer.queue_free)

func create_teleport_beam(parent: CanvasLayer, screen_position: Vector2, beam_height: float) -> void:
	var beam_root := Node2D.new()
	beam_root.position = screen_position
	beam_root.scale = Vector2(0.04, 1.0)
	parent.add_child(beam_root)
	var glow := Polygon2D.new()
	glow.polygon = PackedVector2Array([
		Vector2(-16.0, -beam_height), Vector2(16.0, -beam_height),
		Vector2(10.0, 12.0), Vector2(-10.0, 12.0),
	])
	glow.color = Color(0.82, 0.94, 1.0, 0.34)
	beam_root.add_child(glow)
	var core := Polygon2D.new()
	core.polygon = PackedVector2Array([
		Vector2(-5.0, -beam_height), Vector2(5.0, -beam_height),
		Vector2(3.0, 10.0), Vector2(-3.0, 10.0),
	])
	core.color = Color(1.0, 1.0, 1.0, 0.96)
	beam_root.add_child(core)
	var floor_flash := Polygon2D.new()
	floor_flash.polygon = PackedVector2Array([
		Vector2(0.0, -7.0), Vector2(22.0, 0.0), Vector2(0.0, 7.0), Vector2(-22.0, 0.0),
	])
	floor_flash.color = Color(0.92, 0.98, 1.0, 0.88)
	beam_root.add_child(floor_flash)
	for particle_index in range(12):
		var mote := Polygon2D.new()
		var mote_size := randf_range(1.0, 2.4)
		mote.polygon = PackedVector2Array([
			Vector2(-mote_size, -mote_size), Vector2(mote_size, -mote_size),
			Vector2(mote_size, mote_size), Vector2(-mote_size, mote_size),
		])
		mote.color = Color(1.0, 1.0, 1.0, randf_range(0.55, 0.95))
		mote.position = Vector2(randf_range(-13.0, 13.0), randf_range(-3.0, 12.0))
		beam_root.add_child(mote)
		var mote_tween := create_tween().set_parallel()
		mote_tween.tween_property(mote, "position:y", randf_range(-80.0, -34.0), randf_range(0.24, 0.42)).set_delay(randf_range(0.02, 0.12))
		mote_tween.tween_property(mote, "modulate:a", 0.0, 0.24).set_delay(0.14)
	var beam_tween := create_tween()
	beam_tween.tween_property(beam_root, "scale", Vector2.ONE, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	beam_tween.tween_interval(0.16)
	beam_tween.tween_property(beam_root, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func return_party_to_lobby() -> void:
	if multiplayer.is_server():
		broadcast_party_return_to_lobby()
	else:
		rpc_id(1, "request_return_party_to_lobby_rpc")

@rpc("any_peer", "reliable")
func request_return_party_to_lobby_rpc() -> void:
	if multiplayer.is_server():
		broadcast_party_return_to_lobby()

func broadcast_party_return_to_lobby() -> void:
	if not multiplayer.is_server() or party_return_in_progress:
		return
	if not current_level or not (current_level.is_in_group("survival_arena") or current_level.is_in_group("tower_arena")):
		return
	party_return_in_progress = true
	rpc("return_party_to_lobby_rpc")

@rpc("authority", "call_local", "reliable")
func return_party_to_lobby_rpc() -> void:
	if party_return_in_progress and current_level and current_level.is_in_group("safe_lobby"):
		return
	party_return_in_progress = true
	if multiplayer.is_server() and Networking.has_method("set_lobby_joinable"):
		Networking.set_lobby_joinable(true)
	load_level(default_level_scene)
	for player in players:
		if is_instance_valid(player):
			player.global_position = Vector2(240, 136)
			player.call("reset_for_lobby_rpc")
	get_tree().create_timer(0.8).timeout.connect(func(): party_return_in_progress = false)

# --- LEVEL SWITCHING SYSTEM ---

func load_level(level_scene: PackedScene) -> void:
	clear_single_player_menu_pauses()
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
	update_game_post_process(current_level.is_in_group("tower_arena") or current_level.is_in_group("survival_arena"))
	
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

func create_game_post_process() -> void:
	var grade_layer := CanvasLayer.new()
	grade_layer.layer = 10
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_grade_material = ShaderMaterial.new()
	game_grade_material.shader = GAME_GRADE_SHADER
	game_grade_material.set_shader_parameter("darkness", game_grade_darkness)
	game_grade_material.set_shader_parameter("glow_strength", game_grade_glow)
	overlay.material = game_grade_material
	grade_layer.add_child(overlay)
	add_child(grade_layer)

func update_game_post_process(in_combat: bool) -> void:
	if not game_grade_material:
		return
	var target_darkness := 0.92 if in_combat else 0.985
	var target_glow := 0.10 if in_combat else 0.025
	if post_process_tween and post_process_tween.is_valid():
		post_process_tween.kill()
	post_process_tween = create_tween().set_parallel()
	post_process_tween.tween_method(set_game_grade_darkness, game_grade_darkness, target_darkness, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	post_process_tween.tween_method(set_game_grade_glow, game_grade_glow, target_glow, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func set_game_grade_darkness(value: float) -> void:
	game_grade_darkness = value
	if game_grade_material:
		game_grade_material.set_shader_parameter("darkness", value)

func set_game_grade_glow(value: float) -> void:
	game_grade_glow = value
	if game_grade_material:
		game_grade_material.set_shader_parameter("glow_strength", value)

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
