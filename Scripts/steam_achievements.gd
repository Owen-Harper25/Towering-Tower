extends Node

signal achievement_unlocked(api_name: String)

const FIRST_DEPLOYMENT := "ACH_FIRST_DEPLOYMENT"
const BRANCH_SEVERED := "ACH_BRANCH_SEVERED"
const FIVE_BRANCHES := "ACH_FIVE_BRANCHES"
const CROWN_REACHED := "ACH_CROWN_REACHED"
const WORLD_SAVED := "ACH_WORLD_SAVED"
const TEN_CHARACTERISTICS := "ACH_TEN_CHARACTERISTICS"
const ROOTS_TRAINING := "ACH_ROOTS_TRAINING"
const ROOTS_VETERAN := "ACH_ROOTS_VETERAN"

var steam_available := false
var session_unlocked: Dictionary = {}
var pending_unlocks: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("initialize")

func initialize() -> void:
	steam_available = Engine.has_singleton("Steam") and Steam.has_method("setAchievement") and Steam.has_method("storeStats")
	if not steam_available:
		return
	var stats_callback := Callable(self, "_on_user_stats_received")
	if Steam.has_signal("user_stats_received") and not Steam.is_connected("user_stats_received", stats_callback):
		Steam.connect("user_stats_received", stats_callback)
	if Steam.has_method("requestUserStats") and Steam.has_method("getSteamID"):
		Steam.call("requestUserStats", int(Steam.call("getSteamID")))
	flush_pending_unlocks()

func _on_user_stats_received(_game_id: int, _result: int, _user_id: int) -> void:
	flush_pending_unlocks()

func unlock(api_name: String) -> bool:
	if api_name.is_empty() or session_unlocked.has(api_name):
		return false
	if not steam_available:
		if not pending_unlocks.has(api_name):
			pending_unlocks.append(api_name)
		return false
	var achievement_set := bool(Steam.call("setAchievement", api_name))
	if not achievement_set:
		if not pending_unlocks.has(api_name):
			pending_unlocks.append(api_name)
		return false
	var stats_stored := bool(Steam.call("storeStats"))
	if not stats_stored:
		if not pending_unlocks.has(api_name):
			pending_unlocks.append(api_name)
		return false
	session_unlocked[api_name] = true
	pending_unlocks.erase(api_name)
	achievement_unlocked.emit(api_name)
	return true

func flush_pending_unlocks() -> void:
	if not steam_available:
		return
	var queued: Array[String] = pending_unlocks.duplicate()
	for api_name in queued:
		unlock(api_name)
