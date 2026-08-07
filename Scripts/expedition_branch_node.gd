class_name ExpeditionBranchNode
extends Node

@export_group("Identity")
@export var display_name := "UNNAMED BRANCH"
@export var short_name := "BRANCH"
@export_multiline var briefing := ""
@export var guardian_name := "UNKNOWN GUARDIAN"

@export_group("Encounter")
@export var floor_count := 10
@export var room_names: Array[String] = ["ROOT CHAMBER"]
@export var guardian_scene: PackedScene
@export_range(0, 5, 1) var attack_profile := 0

@export_group("Art Direction")
@export var base_color := Color("4e8fb8")
@export var dark_color := Color("101a35")
@export var accent_color := Color("9fdcff")
@export var map_path_node := NodePath()

func to_dictionary() -> Dictionary:
	var editable_rooms: Array[Node] = get_room_nodes()
	var resolved_room_names: Array[String] = []
	for room in editable_rooms:
		resolved_room_names.append(str(room.get("display_name")))
	if resolved_room_names.is_empty():
		resolved_room_names = room_names.duplicate()
	return {
		"name": display_name,
		"short_name": short_name,
		"boss": guardian_name,
		"brief": briefing,
		"rooms": resolved_room_names,
		"color": base_color,
		"dark": dark_color,
		"accent": accent_color,
		"floor_count": floor_count,
		"attack_profile": attack_profile,
		"guardian_path": guardian_scene.resource_path if guardian_scene else "",
		"map_path": map_path_node,
	}

func get_room_nodes() -> Array[Node]:
	var rooms: Array[Node] = []
	var room_root := get_node_or_null("Rooms")
	if not room_root:
		return rooms
	for child in room_root.get_children():
		if child.has_method("to_dictionary") and "display_name" in child:
			rooms.append(child)
	return rooms
