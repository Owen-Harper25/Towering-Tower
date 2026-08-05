extends Node

const COSMETICS := preload("res://Scripts/cosmetic_catalog.gd")

signal changed

const CLOUD_SAVE_DIRECTORY := "user://steam_cloud"
const SAVE_PATH := CLOUD_SAVE_DIRECTORY + "/meta_progression.cfg"
const LEGACY_SAVE_PATH := "user://meta_progression.cfg"

var currency := 0
var kernel_currency := 0
var unlocked_cosmetics: Array[String] = []
var equipped_head_cosmetic := ""
var equipped_back_cosmetic := ""
var upgrades := {
	"damage": 0,
	"vitality": 0,
	"rapid_fire": 0,
}

const UPGRADE_COSTS := {
	"damage": 12,
	"vitality": 10,
	"rapid_fire": 14,
}
const MAX_LEVEL := 5

func _ready() -> void:
	ensure_cloud_save_directory()
	load_progression()

func ensure_cloud_save_directory() -> void:
	var absolute_path := ProjectSettings.globalize_path(CLOUD_SAVE_DIRECTORY)
	var error := DirAccess.make_dir_recursive_absolute(absolute_path)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("Could not create Steam Cloud save directory: %s" % error_string(error))

func get_level(upgrade_id: String) -> int:
	return int(upgrades.get(upgrade_id, 0))

func get_cost(upgrade_id: String) -> int:
	return int(UPGRADE_COSTS.get(upgrade_id, 0)) * (get_level(upgrade_id) + 1)

func add_currency(amount: int) -> void:
	if amount <= 0:
		return
	currency += amount
	save_progression()
	changed.emit()

func add_kernel_currency(amount: int) -> void:
	if amount <= 0:
		return
	kernel_currency += amount
	save_progression()
	changed.emit()

func purchase(upgrade_id: String) -> bool:
	if not upgrades.has(upgrade_id) or get_level(upgrade_id) >= MAX_LEVEL:
		return false
	var cost := get_cost(upgrade_id)
	if currency < cost:
		return false
	currency -= cost
	upgrades[upgrade_id] = get_level(upgrade_id) + 1
	save_progression()
	changed.emit()
	return true

func owns_cosmetic(cosmetic_id: String) -> bool:
	return unlocked_cosmetics.has(cosmetic_id)

func purchase_cosmetic(cosmetic_id: String) -> bool:
	if owns_cosmetic(cosmetic_id) or COSMETICS.get_item(cosmetic_id).is_empty():
		return false
	var cost := COSMETICS.get_cost(cosmetic_id)
	if currency < cost:
		return false
	currency -= cost
	unlocked_cosmetics.append(cosmetic_id)
	save_progression()
	changed.emit()
	return true

func equip_cosmetic(cosmetic_id: String) -> bool:
	if not owns_cosmetic(cosmetic_id):
		return false
	match COSMETICS.get_slot(cosmetic_id):
		"head": equipped_head_cosmetic = cosmetic_id
		"back": equipped_back_cosmetic = cosmetic_id
		_: return false
	save_progression()
	changed.emit()
	return true

func unequip_cosmetic_slot(slot: String) -> void:
	match slot:
		"head": equipped_head_cosmetic = ""
		"back": equipped_back_cosmetic = ""
		_: return
	save_progression()
	changed.emit()

func clear_equipped_cosmetics() -> void:
	equipped_head_cosmetic = ""
	equipped_back_cosmetic = ""
	save_progression()
	changed.emit()

func save_progression() -> void:
	ensure_cloud_save_directory()
	var config := ConfigFile.new()
	config.set_value("progression", "currency", currency)
	config.set_value("progression", "kernel_currency", kernel_currency)
	config.set_value("cosmetics", "unlocked", unlocked_cosmetics)
	config.set_value("cosmetics", "equipped_head", equipped_head_cosmetic)
	config.set_value("cosmetics", "equipped_back", equipped_back_cosmetic)
	for upgrade_id in upgrades:
		config.set_value("upgrades", upgrade_id, get_level(upgrade_id))
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_error("Could not save metaprogression: %s" % error_string(error))

func load_progression() -> void:
	var config := ConfigFile.new()
	var load_path := SAVE_PATH
	var migrated_legacy_save := false
	if not FileAccess.file_exists(SAVE_PATH) and FileAccess.file_exists(LEGACY_SAVE_PATH):
		load_path = LEGACY_SAVE_PATH
		migrated_legacy_save = true
	if config.load(load_path) != OK:
		return
	currency = int(config.get_value("progression", "currency", 0))
	kernel_currency = int(config.get_value("progression", "kernel_currency", 0))
	unlocked_cosmetics.clear()
	var saved_cosmetics: Variant = config.get_value("cosmetics", "unlocked", [])
	if saved_cosmetics is Array or saved_cosmetics is PackedStringArray:
		for cosmetic_id in saved_cosmetics:
			var id := str(cosmetic_id)
			if COSMETICS.ITEMS.has(id) and not unlocked_cosmetics.has(id):
				unlocked_cosmetics.append(id)
	equipped_head_cosmetic = str(config.get_value("cosmetics", "equipped_head", ""))
	equipped_back_cosmetic = str(config.get_value("cosmetics", "equipped_back", ""))
	if not owns_cosmetic(equipped_head_cosmetic):
		equipped_head_cosmetic = ""
	if not owns_cosmetic(equipped_back_cosmetic):
		equipped_back_cosmetic = ""
	for upgrade_id in upgrades:
		upgrades[upgrade_id] = int(config.get_value("upgrades", upgrade_id, 0))
	if migrated_legacy_save:
		# Keep the old file as a recovery backup and write the active copy into the
		# dedicated directory configured for Steam Auto-Cloud.
		save_progression()
