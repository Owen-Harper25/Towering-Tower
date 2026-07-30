extends Node

signal host_created()
signal client_joined()
signal lobby_list_received(lobbies: Array)

# 1. Changed to PUBLIC so Steam's requestLobbyList() can see it
const LOBBY_TYPE := Steam.LOBBY_TYPE_PUBLIC
const MAX_MEMBERS := 4

var peer: SteamMultiplayerPeer
var active_lobby_id := 0

func _ready() -> void:
	Steam.initRelayNetworkAccess()
	Steam.lobby_created.connect(on_lobby_created)
	Steam.lobby_joined.connect(on_lobby_joined)
	Steam.join_requested.connect(on_join_requested)
	Steam.lobby_match_list.connect(_on_lobby_match_list)

func _process(_delta: float) -> void:
	Steam.run_callbacks()

func host_lobby() -> void:
	Steam.createLobby(LOBBY_TYPE, MAX_MEMBERS)

func join_lobby(lobby_id: int) -> void:
	Steam.joinLobby(lobby_id)

func request_lobbies() -> void:
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListFilterSlotsAvailable(1)
	Steam.addRequestLobbyListStringFilter("game", "ToweringTower", Steam.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()

func set_lobby_joinable(joinable: bool) -> void:
	if active_lobby_id != 0:
		Steam.setLobbyJoinable(active_lobby_id, joinable)

func on_lobby_created(connect_res: int, lobby_id: int) -> void:
	if connect_res != Steam.RESULT_OK:
		push_error("Steam lobby creation failed: %s" % connect_res)
		return

	active_lobby_id = lobby_id
	var host_name: String = Steam.getPersonaName()
	Steam.setLobbyData(lobby_id, "name", host_name + "'s Tower")
	Steam.setLobbyData(lobby_id, "game", "ToweringTower")
	Steam.setLobbyJoinable(lobby_id, true)

	if peer:
		peer.close()
	peer = SteamMultiplayerPeer.new()
	peer.server_relay = true
	peer.create_host()
	multiplayer.multiplayer_peer = peer
	host_created.emit()

func on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		push_error("Steam lobby join failed: %s" % response)
		return
	if Steam.getLobbyOwner(lobby_id) == Steam.getSteamID():
		return
	active_lobby_id = lobby_id
	if peer:
		peer.close()
	peer = SteamMultiplayerPeer.new()
	peer.server_relay = true
	peer.create_client(Steam.getLobbyOwner(lobby_id))
	multiplayer.multiplayer_peer = peer
	client_joined.emit()

func on_join_requested(lobby_id: int, _steam_id: int) -> void:
	join_lobby(lobby_id)

func _on_lobby_match_list(lobbies: Array) -> void:
	lobby_list_received.emit(lobbies)
