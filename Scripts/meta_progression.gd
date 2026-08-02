extends Node

const COSMETICS := preload("res://Scripts/cosmetic_catalog.gd")

signal changed

const SAVE_PATH := "user://meta_progression.cfg"

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
	load_progression()

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
	var config := ConfigFile.new()
	config.set_value("progression", "currency", currency)
	config.set_value("progression", "kernel_currency", kernel_currency)
	config.set_value("cosmetics", "unlocked", unlocked_cosmetics)
	config.set_value("cosmetics", "equipped_head", equipped_head_cosmetic)
	config.set_value("cosmetics", "equipped_back", equipped_back_cosmetic)
	for upgrade_id in upgrades:
		config.set_value("upgrades", upgrade_id, get_level(upgrade_id))
	config.save(SAVE_PATH)

func load_progression() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
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
