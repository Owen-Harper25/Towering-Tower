class_name BoonCatalog
extends RefCounted

enum Rarity { COMMON, UNCOMMON, EPIC, LEGENDARY }

const RARITY_NAMES := ["COMMON", "UNCOMMON", "EPIC", "LEGENDARY"]
const RARITY_COLORS := [
	Color("a7adb7"), Color("4aa8ff"), Color("ad62ff"), Color("ff9b32"),
]
const RARITY_MULTIPLIERS := [1.0, 1.5, 2.25, 3.5]

const BOONS := {
	"iron_sun": {"name": "IRON SUN", "effect": "damage", "base": 1.0, "text": "+%s bullet damage", "sigil": 0},
	"swift_hour": {"name": "SWIFT HOUR", "effect": "fire_rate", "base": 0.07, "text": "%s%% faster firing", "sigil": 1},
	"winged_road": {"name": "WINGED ROAD", "effect": "move_speed", "base": 0.07, "text": "%s%% movement speed", "sigil": 2},
	"tower_heart": {"name": "TOWER HEART", "effect": "max_health", "base": 2.0, "text": "+%s maximum health", "sigil": 3},
	"gale_chamber": {"name": "GALE CHAMBER", "effect": "bullet_speed", "base": 0.10, "text": "%s%% bullet speed", "sigil": 4},
	"falling_star": {"name": "FALLING STAR", "effect": "knockback", "base": 0.16, "text": "%s%% bullet knockback", "sigil": 5},
	"twinned_fate": {"name": "TWINNED FATE", "effect": "multishot", "base": 0.10, "text": "%s%% echo-shot chance", "sigil": 6},
	"still_eye": {"name": "THE STILL EYE", "effect": "accuracy", "base": 0.16, "text": "%s%% tighter spread", "sigil": 7},
	"silver_guard": {"name": "SILVER GUARD", "effect": "invulnerability", "base": 0.10, "text": "+%ss invulnerability", "sigil": 8},
	"returning_comet": {"name": "RETURNING COMET", "effect": "fall_grace", "base": 0.18, "text": "+%ss fall grace", "sigil": 9},
	"chariot": {"name": "THE CHARIOT", "effect": "roll_speed", "base": 0.09, "text": "%s%% dodge speed", "sigil": 10},
	"crooked_moon": {"name": "CROOKED MOON", "effect": "critical", "base": 0.06, "text": "%s%% critical chance", "sigil": 11},
	"hungry_edge": {"name": "THE HUNGRY EDGE", "effect": "melee_damage", "base": 0.16, "text": "%s%% soul-blade damage", "sigil": 12, "requires": "melee"},
	"long_reach": {"name": "THE LONG REACH", "effect": "melee_range", "base": 0.12, "text": "%s%% soul-blade reach", "sigil": 13, "requires": "melee"},
	"quick_silver": {"name": "QUICKSILVER RITE", "effect": "melee_speed", "base": 0.10, "text": "%s%% faster soul-blade strikes", "sigil": 14, "requires": "melee"},
}

static func get_ids() -> Array[String]:
	var ids: Array[String] = []
	for boon_id in BOONS:
		ids.append(str(boon_id))
	return ids

static func get_ids_for_weapon(is_melee: bool) -> Array[String]:
	var ids: Array[String] = []
	for boon_id in BOONS:
		var boon := get_boon(str(boon_id))
		if str(boon.get("requires", "")) == "melee" and not is_melee:
			continue
		ids.append(str(boon_id))
	return ids

static func get_boon(boon_id: String) -> Dictionary:
	var boon: Variant = BOONS.get(boon_id, {})
	return boon if boon is Dictionary else {}

static func get_display_name(boon_id: String) -> String:
	return str(get_boon(boon_id).get("name", boon_id.to_upper()))

static func get_effect(boon_id: String) -> String:
	return str(get_boon(boon_id).get("effect", ""))

static func get_sigil(boon_id: String) -> int:
	return int(get_boon(boon_id).get("sigil", 0))

static func get_value(boon_id: String, rarity: int) -> float:
	var safe_rarity := clampi(rarity, Rarity.COMMON, Rarity.LEGENDARY)
	return float(get_boon(boon_id).get("base", 0.0)) * RARITY_MULTIPLIERS[safe_rarity]

static func get_rarity_name(rarity: int) -> String:
	return RARITY_NAMES[clampi(rarity, Rarity.COMMON, Rarity.LEGENDARY)]

static func get_rarity_color(rarity: int) -> Color:
	return RARITY_COLORS[clampi(rarity, Rarity.COMMON, Rarity.LEGENDARY)]

static func get_description(boon_id: String, rarity: int) -> String:
	var boon := get_boon(boon_id)
	var value := get_value(boon_id, rarity)
	var effect := get_effect(boon_id)
	var shown_value: String
	if effect in ["damage", "max_health"]:
		shown_value = str(maxi(1, roundi(value)))
	elif effect in ["invulnerability", "fall_grace"]:
		shown_value = "%.2f" % value
	else:
		shown_value = str(roundi(value * 100.0))
	return str(boon.get("text", "%s")) % shown_value

static func roll_rarity() -> int:
	var roll := randf()
	if roll < 0.04:
		return Rarity.LEGENDARY
	if roll < 0.17:
		return Rarity.EPIC
	if roll < 0.45:
		return Rarity.UNCOMMON
	return Rarity.COMMON
