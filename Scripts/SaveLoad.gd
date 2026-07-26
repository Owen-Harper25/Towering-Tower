extends Node

const save_location = "user://CrowManSaveFile.tres"

var SaveFileData: SaveDataResource = SaveDataResource.new()

func _ready() -> void:
	_load()

func _save():
	ResourceSaver.save(SaveFileData, save_location)

func _load():
	if FileAccess.file_exists(save_location):
		SaveFileData = ResourceLoader.load(save_location).duplicate(true)
