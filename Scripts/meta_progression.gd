extends Node

signal changed

const SAVE_PATH := "user://meta_progression.cfg"

var currency := 0
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

func save_progression() -> void:
	var config := ConfigFile.new()
	config.set_value("progression", "currency", currency)
	for upgrade_id in upgrades:
		config.set_value("upgrades", upgrade_id, get_level(upgrade_id))
	config.save(SAVE_PATH)

func load_progression() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	currency = int(config.get_value("progression", "currency", 0))
	for upgrade_id in upgrades:
		upgrades[upgrade_id] = int(config.get_value("upgrades", upgrade_id, 0))
