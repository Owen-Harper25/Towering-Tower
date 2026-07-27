extends Node

signal host_created()
signal client_joined()

# 1. Changed to PUBLIC so Steam's requestLobbyList() can see it
const LOBBY_TYPE := Steam.LOBBY_TYPE_PUBLIC
const MAX_MEMBERS := 4

var peer: SteamMultiplayerPeer

func _ready() -> void:
	Steam.initRelayNetworkAccess()
	Steam.lobby_created.connect(on_lobby_created)
	Steam.lobby_joined.connect(on_lobby_joined)
	Steam.join_requested.connect(on_join_requested)

func _process(_delta: float) -> void:
	Steam.run_callbacks()

func host_lobby() -> void:
	Steam.createLobby(LOBBY_TYPE, MAX_MEMBERS)

func join_lobby(lobby_id: int) -> void:
	Steam.joinLobby(lobby_id)

func on_lobby_created(connect_res: int, lobby_id: int) -> void:
	if connect_res == 1 or connect_res == Steam.RESULT_OK:
		# Set lobby metadata so players can search for it
		var host_name: String = Steam.getPersonaName()
		Steam.setLobbyData(lobby_id, "name", host_name + "'s Tower")
		Steam.setLobbyData(lobby_id, "game", "ToweringTower")

		if peer:
			peer.close()
		peer = SteamMultiplayerPeer.new()
		peer.server_relay = true
		peer.create_host()
		multiplayer.multiplayer_peer = peer
		host_created.emit()

func on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		if Steam.getLobbyOwner(lobby_id) == Steam.getSteamID():
			return
		if peer:
			peer.close()
		peer = SteamMultiplayerPeer.new()
		peer.server_relay = true
		peer.create_client(Steam.getLobbyOwner(lobby_id))
		multiplayer.multiplayer_peer = peer
		
		client_joined.emit()

func on_join_requested(lobby_id: int, _steam_id: int) -> void:
	join_lobby(lobby_id)
