class_name ExpeditionRoomNode
extends Node

enum LayoutType { OPEN, SPLIT, RING, NARROW, NEST }

@export var display_name := "ROOT CHAMBER"
@export var layout_type: LayoutType = LayoutType.OPEN
@export_group("Encounter Composition")
@export var rusher_bonus := 0
@export var sniper_bonus := 0
@export var turret_bonus := 0
@export_range(0.5, 2.0, 0.05) var enemy_health_multiplier := 1.0
@export_range(0.5, 2.0, 0.05) var enemy_speed_multiplier := 1.0
@export_range(0.25, 2.0, 0.05) var characteristic_drop_multiplier := 1.0

func to_dictionary() -> Dictionary:
	return {
		"name": display_name,
		"layout": layout_type,
		"rusher_bonus": rusher_bonus,
		"sniper_bonus": sniper_bonus,
		"turret_bonus": turret_bonus,
		"health_multiplier": enemy_health_multiplier,
		"speed_multiplier": enemy_speed_multiplier,
		"drop_multiplier": characteristic_drop_multiplier,
	}
