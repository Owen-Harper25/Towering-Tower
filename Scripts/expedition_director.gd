class_name ExpeditionDirector
extends Node

@export var ordinary_branch_count := 5
@export var default_floors_per_branch := 10

func get_branch_nodes() -> Array[ExpeditionBranchNode]:
	var definitions: Array[ExpeditionBranchNode] = []
	for child in get_children():
		var definition := child as ExpeditionBranchNode
		if definition:
			definitions.append(definition)
	return definitions

func get_final_floor() -> int:
	var total := 0
	var definitions := get_branch_nodes()
	for index in range(mini(ordinary_branch_count, definitions.size())):
		total += maxi(1, definitions[index].floor_count)
	return total + 1

func get_branch_index(floor_number: int) -> int:
	var definitions := get_branch_nodes()
	if definitions.is_empty():
		return 0
	if floor_number >= get_final_floor():
		return mini(ordinary_branch_count, definitions.size() - 1)
	var remaining := maxi(1, floor_number)
	for index in range(mini(ordinary_branch_count, definitions.size())):
		var count := maxi(1, definitions[index].floor_count)
		if remaining <= count:
			return index
		remaining -= count
	return maxi(0, mini(ordinary_branch_count - 1, definitions.size() - 1))

func get_floor_in_branch(floor_number: int) -> int:
	if floor_number >= get_final_floor():
		return 1
	var definitions := get_branch_nodes()
	var remaining := maxi(1, floor_number)
	for index in range(mini(ordinary_branch_count, definitions.size())):
		var count := maxi(1, definitions[index].floor_count)
		if remaining <= count:
			return remaining
		remaining -= count
	return 1

func get_branch(floor_number: int) -> Dictionary:
	var definitions := get_branch_nodes()
	if definitions.is_empty():
		return {}
	return definitions[clampi(get_branch_index(floor_number), 0, definitions.size() - 1)].to_dictionary()

func get_room_name(floor_number: int) -> String:
	return str(get_room_definition(floor_number).get("name", "UNKNOWN CHAMBER"))

func get_room_definition(floor_number: int) -> Dictionary:
	var definitions := get_branch_nodes()
	if definitions.is_empty():
		return {"name": "UNKNOWN CHAMBER"}
	var branch := definitions[clampi(get_branch_index(floor_number), 0, definitions.size() - 1)]
	var room_nodes: Array[Node] = branch.get_room_nodes()
	if not room_nodes.is_empty():
		var selected_room: Node = room_nodes[(get_floor_in_branch(floor_number) - 1) % room_nodes.size()]
		return selected_room.call("to_dictionary") as Dictionary
	var fallback_names := branch.room_names
	if fallback_names.is_empty():
		return {"name": "UNKNOWN CHAMBER"}
	return {"name": fallback_names[(get_floor_in_branch(floor_number) - 1) % fallback_names.size()]}

func is_guardian_floor(floor_number: int) -> bool:
	if floor_number == get_final_floor():
		return true
	var branch_index := get_branch_index(floor_number)
	var definitions := get_branch_nodes()
	if branch_index >= definitions.size():
		return false
	return get_floor_in_branch(floor_number) == definitions[branch_index].floor_count

func is_final_floor(floor_number: int) -> bool:
	return floor_number == get_final_floor()

func get_guardian_path(floor_number: int) -> String:
	return str(get_branch(floor_number).get("guardian_path", ""))

func get_characteristic_threshold(level: int) -> int:
	return 6 + maxi(0, level - 1) * 4
