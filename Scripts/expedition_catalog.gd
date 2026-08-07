class_name ExpeditionCatalog
extends RefCounted

const FLOORS_PER_BRANCH := 10
const BRANCH_COUNT := 5
const FINAL_FLOOR := FLOORS_PER_BRANCH * BRANCH_COUNT + 1

const BRANCHES: Array[Dictionary] = [
	{
		"name": "THE WEEPING ROOT",
		"short_name": "WEEPING ROOT",
		"boss": "THE SAP-BEARER",
		"color": Color("4e8fb8"),
		"dark": Color("101a35"),
		"accent": Color("9fdcff"),
		"rooms": ["SPLIT ROOT", "SPORE HOLLOW", "SUNKEN VEIN"],
		"brief": "A drowned limb where the Tree first learned to imitate blood."
	},
	{
		"name": "THE OSSIFIED BOUGH",
		"short_name": "OSSIFIED BOUGH",
		"boss": "MARROW STAG",
		"color": Color("d8d5bd"),
		"dark": Color("29243f"),
		"accent": Color("f4eece"),
		"rooms": ["BONE ORCHARD", "HUSK GALLERY", "CALCIUM KNOT"],
		"brief": "A pale branch armored in the memories of everything it consumed."
	},
	{
		"name": "THE VERMILION VEIN",
		"short_name": "VERMILION VEIN",
		"boss": "CHOIR OF TEETH",
		"color": Color("bd4c61"),
		"dark": Color("321528"),
		"accent": Color("ff9a83"),
		"rooms": ["PULSE CHAMBER", "RED NURSERY", "THORN ARTERY"],
		"brief": "Warm wood pulses here, manufacturing predators from stolen instinct."
	},
	{
		"name": "THE AZURE CROWN",
		"short_name": "AZURE CROWN",
		"boss": "THE PRISM WIDOW",
		"color": Color("526bd4"),
		"dark": Color("151535"),
		"accent": Color("74e4e8"),
		"rooms": ["CRYSTAL SYNAPSE", "STAR-SAP WELL", "PRISM SCAR"],
		"brief": "Crystallized characteristics think in chorus beneath its bark."
	},
	{
		"name": "THE ECLIPSED LIMB",
		"short_name": "ECLIPSED LIMB",
		"boss": "THE HOLLOW APOSTLE",
		"color": Color("76529c"),
		"dark": Color("100d20"),
		"accent": Color("cba6ff"),
		"rooms": ["BLIND CANOPY", "NULL KNOT", "MOURNING RING"],
		"brief": "The oldest branch. Even agency instruments refuse to remember it."
	},
]

const FINAL_BRANCH: Dictionary = {
	"name": "THE CROWN NEST",
	"short_name": "CROWN NEST",
	"boss": "SERAPH OF THE LAST NEST",
	"color": Color("e8cf85"),
	"dark": Color("171328"),
	"accent": Color("fff4c2"),
	"rooms": ["THE LAST ASCENT"],
	"brief": "At the peak, something with too many wings is waiting to hatch."
}

static func get_branch_index(floor_number: int) -> int:
	if floor_number >= FINAL_FLOOR:
		return BRANCH_COUNT
	return clampi((maxi(1, floor_number) - 1) / FLOORS_PER_BRANCH, 0, BRANCH_COUNT - 1)

static func get_branch(floor_number: int) -> Dictionary:
	var branch_index := get_branch_index(floor_number)
	if branch_index >= BRANCH_COUNT:
		return FINAL_BRANCH
	return BRANCHES[branch_index]

static func get_floor_in_branch(floor_number: int) -> int:
	if floor_number >= FINAL_FLOOR:
		return 1
	return ((maxi(1, floor_number) - 1) % FLOORS_PER_BRANCH) + 1

static func is_guardian_floor(floor_number: int) -> bool:
	return floor_number == FINAL_FLOOR or (floor_number > 0 and floor_number % FLOORS_PER_BRANCH == 0)

static func is_final_floor(floor_number: int) -> bool:
	return floor_number == FINAL_FLOOR

static func get_room_name(floor_number: int) -> String:
	var branch := get_branch(floor_number)
	var rooms: Array = branch.get("rooms", ["UNKNOWN CHAMBER"])
	if rooms.is_empty():
		return "UNKNOWN CHAMBER"
	return str(rooms[(get_floor_in_branch(floor_number) - 1) % rooms.size()])

static func get_characteristic_threshold(level: int) -> int:
	return 6 + maxi(0, level - 1) * 4
