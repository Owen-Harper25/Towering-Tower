class_name CosmeticCatalog
extends RefCounted

const ITEMS := {
	"red_cape": {
		"name": "CRIMSON CAPE",
		"slot": "back",
		"cost": 35,
		"texture": "res://Assets/Cosmetics/red_cape.svg",
	},
	"royal_cape": {
		"name": "ROYAL CAPE",
		"slot": "back",
		"cost": 60,
		"texture": "res://Assets/Cosmetics/royal_cape.svg",
	},
	"gold_crown": {
		"name": "GOLD CROWN",
		"slot": "head",
		"cost": 50,
		"texture": "res://Assets/Cosmetics/gold_crown.svg",
	},
	"wizard_hat": {
		"name": "WIZARD HAT",
		"slot": "head",
		"cost": 45,
		"texture": "res://Assets/Cosmetics/wizard_hat.svg",
	},
	"top_hat": {
		"name": "TOP HAT",
		"slot": "head",
		"cost": 40,
		"texture": "res://Assets/Cosmetics/top_hat.svg",
	},
}

static func get_ids() -> Array[String]:
	var ids: Array[String] = []
	for cosmetic_id in ITEMS:
		ids.append(str(cosmetic_id))
	return ids

static func get_item(cosmetic_id: String) -> Dictionary:
	var item: Variant = ITEMS.get(cosmetic_id, {})
	return item if item is Dictionary else {}

static func get_display_name(cosmetic_id: String) -> String:
	return str(get_item(cosmetic_id).get("name", cosmetic_id.to_upper()))

static func get_slot(cosmetic_id: String) -> String:
	return str(get_item(cosmetic_id).get("slot", ""))

static func get_cost(cosmetic_id: String) -> int:
	return int(get_item(cosmetic_id).get("cost", 0))

static func get_texture_path(cosmetic_id: String) -> String:
	return str(get_item(cosmetic_id).get("texture", ""))
