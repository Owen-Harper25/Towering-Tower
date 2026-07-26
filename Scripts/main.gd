extends Node2D

const PLAYER = preload("uid://dflfyebeka06d")

var players: Array[CharacterBody2D]

func _ready() -> void:
	Networking.host_created.connect(on_host_created)
	# Connect peer signal once in _ready
	multiplayer.peer_connected.connect(spawn_player)

func on_host_created() -> void:
	spawn_player(multiplayer.get_unique_id())
	
func spawn_player(peer_id: int) -> void:
	var new_player := PLAYER.instantiate() as CharacterBody2D
	new_player.name = str(peer_id)
	# Only add to $Arena/Players (matching MultiplayerSpawner path)
	$Arena/Players.add_child(new_player)
	initialize_player(new_player)
	
func initialize_player(player: CharacterBody2D) -> void:
	player.position = $SpawnPoint.position
	for other in players:
		player.add_collision_exception_with(other)
	players.append(player)

func _on_host_pressed() -> void:
	Networking.host_lobby()

func _on_multiplayer_spawner_spawned(node: Node) -> void:
	if node is CharacterBody2D:
		initialize_player(node)
