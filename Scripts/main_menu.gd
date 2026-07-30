extends Control

const SETTINGS_PATH := "user://settings.cfg"

@onready var solo_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/Solo
@onready var host_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/Host
@onready var settings_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/Settings
@onready var quit_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/Quit
@onready var settings_panel: Control = $CanvasLayer/SettingsMenu

func _ready() -> void:
	load_settings()
	solo_button.pressed.connect(_on_solo_pressed)
	host_button.pressed.connect(_on_host_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	build_settings_menu()
	settings_panel.hide()

# --- BUTTON ACTIONS ---

func _on_solo_pressed() -> void:
	pass
	
func _on_host_pressed() -> void:
	Networking.host_lobby()

func _on_settings_pressed() -> void:
	settings_panel.visible = not settings_panel.visible
	if settings_panel.visible:
		layout_settings_menu()

func _unhandled_input(event: InputEvent) -> void:
	if settings_panel.visible and event.is_action_pressed("ui_cancel"):
		close_settings()
		get_viewport().set_input_as_handled()

func close_settings() -> void:
	settings_panel.hide()
	settings_button.grab_focus()

func _on_quit_pressed() -> void:
	get_tree().quit()
	
func build_settings_menu() -> void:
	for child in settings_panel.get_children():
		child.queue_free()

	settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.04, 0.06, 0.12, 0.94)
	backdrop.size = Vector2(260, 246)
	settings_panel.add_child(backdrop)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.size = Vector2(228, 220)
	content.add_theme_constant_override("separation", 5)
	settings_panel.add_child(content)

	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	add_volume_slider(content, "MASTER", "Master")
	add_volume_slider(content, "MUSIC", "Music")
	add_volume_slider(content, "SFX", "SFX")

	var resolution_label := Label.new()
	resolution_label.text = "RESOLUTION"
	content.add_child(resolution_label)
	var resolution_options := OptionButton.new()
	resolution_options.add_item("480 x 270", 0)
	resolution_options.add_item("960 x 540", 1)
	resolution_options.add_item("1280 x 720", 2)
	resolution_options.add_item("1920 x 1080", 3)
	resolution_options.item_selected.connect(_on_resolution_selected)
	content.add_child(resolution_options)

	var fullscreen_button := CheckButton.new()
	fullscreen_button.text = "FULLSCREEN"
	fullscreen_button.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen_button.toggled.connect(_on_fullscreen_toggled)
	content.add_child(fullscreen_button)

	var vsync_button := CheckButton.new()
	vsync_button.text = "VSYNC"
	vsync_button.button_pressed = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	vsync_button.toggled.connect(_on_vsync_toggled)
	content.add_child(vsync_button)

	var close_button := Button.new()
	close_button.text = "BACK / CANCEL"
	close_button.pressed.connect(close_settings)
	content.add_child(close_button)
	layout_settings_menu()

func layout_settings_menu() -> void:
	if not is_instance_valid(settings_panel):
		return
	settings_panel.position = Vector2.ZERO
	settings_panel.size = get_viewport_rect().size
	var backdrop := settings_panel.get_node_or_null("Backdrop") as ColorRect
	var content := settings_panel.get_node_or_null("Content") as VBoxContainer
	if not backdrop or not content:
		return
	backdrop.position = (settings_panel.size - backdrop.size) * 0.5
	content.position = backdrop.position + Vector2(16, 12)

func add_volume_slider(container: VBoxContainer, label_text: String, bus_name: String) -> void:
	var label := Label.new()
	label.text = label_text
	container.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	var bus_index := AudioServer.get_bus_index(bus_name)
	slider.value = db_to_linear(AudioServer.get_bus_volume_db(bus_index))
	slider.value_changed.connect(func(value: float): set_bus_volume(bus_name, value))
	container.add_child(slider)

func set_bus_volume(bus_name: String, value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus_name), linear_to_db(maxf(value, 0.001)))
	save_settings()

func _on_resolution_selected(index: int) -> void:
	var resolutions := [Vector2i(480, 270), Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]
	DisplayServer.window_set_size(resolutions[index])
	save_settings()

func _on_fullscreen_toggled(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
	save_settings()

func _on_vsync_toggled(enabled: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED)
	save_settings()

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")))
	config.set_value("audio", "music", AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")))
	config.set_value("audio", "sfx", AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")))
	config.set_value("display", "fullscreen", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	config.set_value("display", "vsync", DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED)
	config.save(SETTINGS_PATH)

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), config.get_value("audio", "master", 0.0))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), config.get_value("audio", "music", 0.0))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), config.get_value("audio", "sfx", 0.0))
	var fullscreen: bool = config.get_value("display", "fullscreen", false)
	var vsync: bool = config.get_value("display", "vsync", true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
