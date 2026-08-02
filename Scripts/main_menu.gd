extends Control

const SETTINGS_PATH := "user://settings.cfg"
const CAPITAL_BOLD_FONT := preload("res://Assets/Capital Bold - Normal.ttf")
const REEL_BACKDROP := preload("res://Scripts/reel_menu_backdrop.gd")

@onready var solo_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/Solo
@onready var host_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/Host
@onready var settings_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/Settings
@onready var quit_button: Button = $CanvasLayer/MarginContainer/VBoxContainer/Quit
@onready var settings_panel: Control = $CanvasLayer/SettingsMenu
@onready var server_browser: Control = $"CanvasLayer/Server Browser"
@onready var lobby_back_button: Button = $"CanvasLayer/Server Browser/LobbyBackButton"
var runtime_context := false
var reel_buttons: Array[Button] = []
var reel_selected_button: Button
var reel_elapsed := 0.0
var reel_title: Label

func _ready() -> void:
	load_settings()
	solo_button.pressed.connect(_on_solo_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	build_settings_menu()
	settings_panel.hide()
	build_reel_menu_presentation()

func _process(delta: float) -> void:
	reel_elapsed += delta
	if reel_title:
		reel_title.modulate = Color(0.92, 0.96, 1.0).lerp(Color(0.72, 0.94, 1.0), 0.5 + sin(reel_elapsed * 1.4) * 0.5)
	if reel_selected_button and is_instance_valid(reel_selected_button):
		var pastel := Color.from_hsv(fmod(reel_elapsed * 0.065 + 0.48, 1.0), 0.34, 1.0)
		reel_selected_button.add_theme_color_override("font_color", pastel)
		reel_selected_button.add_theme_color_override("font_hover_color", pastel)
		reel_selected_button.add_theme_color_override("font_focus_color", pastel)

func build_reel_menu_presentation() -> void:
	add_to_group("reel_menu_active")
	var canvas := $CanvasLayer as CanvasLayer
	var backdrop := Control.new()
	backdrop.name = "ReelBackdrop"
	backdrop.set_script(REEL_BACKDROP)
	canvas.add_child(backdrop)
	canvas.move_child(backdrop, 0)
	var margin := $CanvasLayer/MarginContainer as MarginContainer
	margin.set_anchors_preset(Control.PRESET_CENTER)
	margin.offset_left = -110.0
	margin.offset_top = -124.0
	margin.offset_right = 110.0
	margin.offset_bottom = 124.0
	var menu_list := $CanvasLayer/MarginContainer/VBoxContainer as VBoxContainer
	menu_list.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_list.add_theme_constant_override("separation", 1)
	reel_title = menu_list.get_node("Label") as Label
	reel_title.text = "TOWERING\nTOWER"
	reel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reel_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reel_title.custom_minimum_size = Vector2(0.0, 58.0)
	reel_title.add_theme_font_override("font", CAPITAL_BOLD_FONT)
	reel_title.add_theme_font_size_override("font_size", 20)
	var spacer := menu_list.get_node("Control") as Control
	spacer.custom_minimum_size = Vector2(0.0, 5.0)
	reel_buttons = [
		host_button,
		$CanvasLayer/MarginContainer/VBoxContainer/JoinButton as Button,
		$CanvasLayer/MarginContainer/VBoxContainer/Friends as Button,
		settings_button,
		quit_button,
	]
	for button_index in range(reel_buttons.size()):
		configure_reel_button(reel_buttons[button_index], button_index)
	call_deferred("play_reel_menu_entrance")

func configure_reel_button(button: Button, button_index: int) -> void:
	button.set_meta("reel_menu_button", true)
	button.set_meta("reel_button_index", button_index)
	button.text = button.text.strip_edges().to_upper()
	button.custom_minimum_size = Vector2(210.0, 29.0)
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_font_override("font", CAPITAL_BOLD_FONT)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color(0.90, 0.92, 0.94))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	var empty_style := StyleBoxEmpty.new()
	for state_name in [&"normal", &"hover", &"focus", &"pressed", &"disabled"]:
		button.add_theme_stylebox_override(state_name, empty_style)
	var underline := ColorRect.new()
	underline.name = "ReelUnderline"
	underline.color = Color(0.52, 0.92, 1.0, 0.92)
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	underline.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	underline.offset_left = 0.0
	underline.offset_top = -3.0
	underline.offset_right = 0.0
	underline.offset_bottom = -1.0
	button.add_child(underline)
	button.set_meta("reel_underline", underline)
	var left_diamond := create_reel_diamond(Vector2(45.0, 14.5))
	var right_diamond := create_reel_diamond(Vector2(165.0, 14.5))
	button.add_child(left_diamond)
	button.add_child(right_diamond)
	button.set_meta("reel_left_diamond", left_diamond)
	button.set_meta("reel_right_diamond", right_diamond)
	button.mouse_entered.connect(func():
		UIJuice.play_navigation_sound()
		highlight_reel_button(button)
	)
	button.mouse_exited.connect(func():
		if not button.has_focus():
			clear_reel_button(button)
	)
	button.focus_entered.connect(func():
		UIJuice.play_navigation_sound()
		highlight_reel_button(button)
	)
	button.focus_exited.connect(func():
		if not button.is_hovered():
			clear_reel_button(button)
	)
	button.button_down.connect(func(): punch_reel_button(button, true))
	button.button_up.connect(func(): punch_reel_button(button, false))
	button.pressed.connect(UIJuice.play_confirm_sound)

func create_reel_diamond(position_value: Vector2) -> Polygon2D:
	var diamond := Polygon2D.new()
	diamond.polygon = PackedVector2Array([
		Vector2(0.0, -2.4), Vector2(2.4, 0.0),
		Vector2(0.0, 2.4), Vector2(-2.4, 0.0),
	])
	diamond.position = position_value
	diamond.color = Color(0.62, 0.92, 1.0)
	diamond.modulate.a = 0.0
	return diamond

func play_reel_menu_entrance() -> void:
	# Let the VBox finish reflowing after runtime-only buttons change visibility.
	# Reusing the boot-menu positions here caused the in-game menu to overlap.
	await get_tree().process_frame
	for button_index in range(reel_buttons.size()):
		var button := reel_buttons[button_index]
		if not is_instance_valid(button) or not button.visible:
			continue
		button.set_meta("reel_base_position", button.position)
		button.position.x += 22.0
		button.scale = Vector2(0.84, 0.84)
		button.modulate.a = 0.0
		var tween := button.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(button, "position:x", float((button.get_meta("reel_base_position") as Vector2).x), 0.30).set_delay(float(button_index) * 0.055)
		tween.tween_property(button, "scale", Vector2.ONE, 0.30).set_delay(float(button_index) * 0.055)
		tween.tween_property(button, "modulate:a", 1.0, 0.18).set_delay(float(button_index) * 0.055)

func highlight_reel_button(button: Button) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	reel_selected_button = button
	for menu_button in reel_buttons:
		if not is_instance_valid(menu_button) or not menu_button.visible:
			continue
		var selected := menu_button == button
		animate_reel_button_state(menu_button, selected, 1.0 if selected else 0.28)

func clear_reel_button(button: Button) -> void:
	if reel_selected_button != button:
		return
	reel_selected_button = null
	for menu_button in reel_buttons:
		if not is_instance_valid(menu_button):
			continue
		menu_button.add_theme_color_override("font_color", Color(0.90, 0.92, 0.94))
		animate_reel_button_state(menu_button, false, 1.0)

func animate_reel_button_state(button: Button, selected: bool, alpha: float) -> void:
	if not button.has_meta("reel_base_position"):
		button.set_meta("reel_base_position", button.position)
	var previous_tween: Variant = button.get_meta("reel_state_tween") if button.has_meta("reel_state_tween") else null
	if previous_tween is Tween and previous_tween.is_valid():
		previous_tween.kill()
	var base_position := button.get_meta("reel_base_position") as Vector2
	var tween := button.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE * (1.13 if selected else 0.96 if alpha < 1.0 else 1.0), 0.12)
	tween.tween_property(button, "position:x", base_position.x + (8.0 if selected else 0.0), 0.12)
	tween.tween_property(button, "modulate:a", alpha, 0.12)
	var underline := button.get_meta("reel_underline") as ColorRect
	var line_half_width := minf(62.0, 13.0 + float(button.text.length()) * 3.6) if selected else 0.0
	tween.tween_property(underline, "offset_left", -line_half_width, 0.15)
	tween.tween_property(underline, "offset_right", line_half_width, 0.15)
	var left_diamond := button.get_meta("reel_left_diamond") as Polygon2D
	var right_diamond := button.get_meta("reel_right_diamond") as Polygon2D
	tween.tween_property(left_diamond, "modulate:a", 1.0 if selected else 0.0, 0.10)
	tween.tween_property(right_diamond, "modulate:a", 1.0 if selected else 0.0, 0.10)
	tween.tween_property(left_diamond, "position:x", 37.0 if selected else 45.0, 0.12)
	tween.tween_property(right_diamond, "position:x", 173.0 if selected else 165.0, 0.12)
	button.set_meta("reel_state_tween", tween)

func punch_reel_button(button: Button, pressed: bool) -> void:
	if not is_instance_valid(button):
		return
	var tween := button.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE * (0.91 if pressed else 1.13), 0.075)

# --- BUTTON ACTIONS ---

func _on_solo_pressed() -> void:
	pass
	
func _on_host_pressed() -> void:
	Networking.host_lobby()

func _on_settings_pressed() -> void:
	settings_panel.visible = not settings_panel.visible
	if settings_panel.visible:
		layout_settings_menu()
		if UIJuice.keyboard_navigation_active:
			call_deferred("focus_first_settings_control")

func set_runtime_context(active: bool, network_active: bool) -> void:
	runtime_context = active
	host_button.visible = not network_active
	if not active:
		host_button.show()
	if reel_title:
		reel_title.text = "PAUSED" if active else "TOWERING\nTOWER"
		reel_title.custom_minimum_size.y = 40.0 if active else 58.0
	settings_panel.hide()
	var browser := $CanvasLayer.get_node_or_null("Server Browser") as Control
	if browser:
		browser.hide()
	call_deferred("play_reel_menu_entrance")
	if UIJuice.keyboard_navigation_active:
		call_deferred("focus_first_visible_reel_button")

func _input(event: InputEvent) -> void:
	if not visible:
		return
	var navigation_event := event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")
	if not navigation_event and not (event is InputEventJoypadButton):
		return
	if settings_panel.visible:
		call_deferred("focus_first_settings_control")
		return
	if server_browser and server_browser.visible:
		call_deferred("focus_server_browser")
	else:
		call_deferred("focus_first_visible_reel_button")

func focus_server_browser() -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner and server_browser and server_browser.is_ancestor_of(focus_owner) and focus_owner.is_visible_in_tree():
		return
	if lobby_back_button and lobby_back_button.is_visible_in_tree():
		lobby_back_button.grab_focus()

func focus_first_visible_reel_button() -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner and is_ancestor_of(focus_owner) and focus_owner.is_visible_in_tree():
		return
	for button in reel_buttons:
		if is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled:
			button.grab_focus()
			return

func _unhandled_input(event: InputEvent) -> void:
	if settings_panel.visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("Pause")):
		close_settings()
		get_viewport().set_input_as_handled()
		return
	if server_browser and server_browser.visible and event.is_action_pressed("ui_cancel"):
		server_browser.hide()
		if UIJuice.keyboard_navigation_active:
			($CanvasLayer/MarginContainer/VBoxContainer/JoinButton as Button).grab_focus()
		get_viewport().set_input_as_handled()

func close_settings() -> void:
	settings_panel.hide()
	if UIJuice.keyboard_navigation_active:
		settings_button.grab_focus()

func focus_first_settings_control() -> void:
	for node in settings_panel.find_children("*", "Control", true, false):
		var control := node as Control
		if control and control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE:
			control.grab_focus()
			return

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
