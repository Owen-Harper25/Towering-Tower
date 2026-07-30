extends Control

# Drag your main game scene into this export slot in the Inspector
#@export_file("*.tscn") var game_scene_path: String = "res://main.tscn"

@onready var solo_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/Solo
@onready var host_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/Host
@onready var settings_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/Settings
@onready var quit_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/Quit
@onready var settings_panel: Control = $CanvasLayer/SettingsMenu

func _ready() -> void:
	# Connect Button Signals
	solo_button.pressed.connect(_on_solo_pressed)
	host_button.pressed.connect(_on_host_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	settings_panel.hide()

# --- BUTTON ACTIONS ---

func _on_solo_pressed() -> void:
	# Load the main game scene in solo/offline mode
	# You can set a global flag in your Networking singleton if needed:
	# Networking.is_offline_mode = true
	#get_tree().change_scene_to_file(game_scene_path)
	pass
	
func _on_host_pressed() -> void:
	# Create Steam lobby via your Networking singleton, then switch scenes
	Networking.host_lobby()
	#get_tree().change_scene_to_file(game_scene_path)

func _on_settings_pressed() -> void:
	settings_panel.show()

func _on_quit_pressed() -> void:
	get_tree().quit()
	
func _on_music_slider_value_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(value))
