class_name LoreNpc
extends Node2D

@export var speaker_name := "AGENCY RESEARCHER"
@export_multiline var lore_text := "NO FIELD NOTES RECOVERED."

func get_lore_title() -> String:
	return speaker_name.to_upper()

func get_lore_text() -> String:
	return lore_text.to_upper()
