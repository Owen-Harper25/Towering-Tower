extends Node

const CLOUD_SAVE_DIRECTORY := "user://steam_cloud"
const save_location := CLOUD_SAVE_DIRECTORY + "/CrowManSaveFile.tres"
const legacy_save_location := "user://CrowManSaveFile.tres"

var SaveFileData: SaveDataResource = SaveDataResource.new()

func _ready() -> void:
	ensure_cloud_save_directory()
	_load()

func ensure_cloud_save_directory() -> void:
	var absolute_path := ProjectSettings.globalize_path(CLOUD_SAVE_DIRECTORY)
	var error := DirAccess.make_dir_recursive_absolute(absolute_path)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("Could not create Steam Cloud save directory: %s" % error_string(error))

func _save() -> void:
	ensure_cloud_save_directory()
	var error := ResourceSaver.save(SaveFileData, save_location)
	if error != OK:
		push_error("Could not save game data: %s" % error_string(error))

func _load() -> void:
	var load_path := save_location
	var migrated_legacy_save := false
	if not FileAccess.file_exists(save_location) and FileAccess.file_exists(legacy_save_location):
		load_path = legacy_save_location
		migrated_legacy_save = true
	if FileAccess.file_exists(load_path):
		var loaded_resource := ResourceLoader.load(load_path) as SaveDataResource
		if loaded_resource:
			SaveFileData = loaded_resource.duplicate(true)
			if migrated_legacy_save:
				_save()
