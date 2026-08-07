extends Node

const HOVER_SCALE := Vector2(1.045, 1.045)
const PRESS_SCALE := Vector2(0.96, 0.96)
const NAVIGATION_SOUND := preload("res://SFX/freesound_community-menu-selection-102220.mp3")
const CONFIRM_SOUND := preload("res://SFX/confrimation.mp3")
const CURSOR_TEXTURE := preload("res://Assets/Cursor.png")
const CAPITAL_BOLD_FONT := preload("res://Assets/Capital Bold - Normal.ttf")
const CURSOR_SCALE := 2.5
const SWITCH_PRO_WINDOWS_MAPPING := "030000007e0500000920000000000000,Nintendo Switch Pro Controller,a:b1,b:b0,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b12,leftshoulder:b4,leftstick:b10,lefttrigger:b6,leftx:a0,lefty:a1,misc1:b13,rightshoulder:b5,rightstick:b11,righttrigger:b7,rightx:a2,righty:a3,start:b9,x:b3,y:b2,platform:Windows,"
const CONTROLLER_SOURCE_LOCK_MSEC := 600
const CONTROLLER_ACTIVITY_DEADZONE := 0.24

var navigation_player: AudioStreamPlayer
var confirm_player: AudioStreamPlayer
var last_navigation_sound_time := -1.0
var keyboard_navigation_active := false
var controller_input_active := false
var last_controller_input_msec: int = -10000
var cursor_sprite: Sprite2D
var cursor_layer: CanvasLayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	register_controller_mappings()
	configure_controller_actions()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	for device_id in Input.get_connected_joypads():
		_on_joy_connection_changed(device_id, true)
	create_scaled_cursor()
	create_audio_players()
	get_tree().node_added.connect(_on_node_added)
	call_deferred("style_existing_buttons")

func create_scaled_cursor() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	cursor_layer = CanvasLayer.new()
	cursor_layer.layer = 200
	cursor_sprite = Sprite2D.new()
	cursor_sprite.texture = CURSOR_TEXTURE
	cursor_sprite.centered = false
	cursor_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cursor_sprite.scale = Vector2.ONE * CURSOR_SCALE
	cursor_layer.add_child(cursor_sprite)
	add_child(cursor_layer)

func _process(_delta: float) -> void:
	if cursor_sprite:
		var hotspot := CURSOR_TEXTURE.get_size() * CURSOR_SCALE * 0.5
		var cursor_position := get_viewport().get_mouse_position() - hotspot
		cursor_sprite.position = cursor_position

func create_audio_players() -> void:
	navigation_player = AudioStreamPlayer.new()
	navigation_player.stream = NAVIGATION_SOUND
	navigation_player.bus = &"SFX"
	add_child(navigation_player)
	confirm_player = AudioStreamPlayer.new()
	confirm_player.stream = CONFIRM_SOUND
	confirm_player.bus = &"SFX"
	add_child(confirm_player)

func style_existing_buttons() -> void:
	for node in get_tree().get_nodes_in_group("ui_juiced"):
		setup_button(node as BaseButton)
	for node in get_tree().get_nodes_in_group("buttons"):
		setup_button(node as BaseButton)
	style_node_tree(get_tree().root)

func style_node_tree(node: Node) -> void:
	setup_button(node as BaseButton)
	for child in node.get_children():
		style_node_tree(child)

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		call_deferred("setup_button", node)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		# Steam Input and some Switch controller drivers can emit mouse motion for
		# the right stick. Do not let that synthetic motion clear menu focus or
		# switch aiming back to mouse while a controller is actively being used.
		if event is InputEventMouseMotion and should_ignore_emulated_mouse_motion():
			return
		controller_input_active = false
		keyboard_navigation_active = false
		set_cursor_visible(true)
		if event is InputEventMouseMotion or not (event as InputEventMouseButton).pressed:
			clear_button_focus.call_deferred()
		return
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > CONTROLLER_ACTIVITY_DEADZONE):
		note_controller_activity()
	elif event is InputEventKey and event.pressed:
		controller_input_active = false
	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		keyboard_navigation_active = true

func set_cursor_visible(visible: bool) -> void:
	if cursor_sprite:
		cursor_sprite.visible = visible

func configure_controller_actions() -> void:
	# Clear old project-level joypad events before adding the canonical layout.
	# Several of the legacy bindings overlapped (for example face buttons could
	# both dodge and shoot), which varied further with Nintendo button labels.
	var controlled_actions: Array[StringName] = [
		&"Up", &"Down", &"Left", &"Right",
		&"AimUp", &"AimDown", &"AimLeft", &"AimRight",
		&"Interact", &"DodgeRoll", &"Codex", &"Shoot", &"Pause",
		&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept", &"ui_cancel",
	]
	for action in controlled_actions:
		clear_controller_events(action)
	set_action_deadzone(&"Up", 0.22)
	set_action_deadzone(&"Down", 0.22)
	set_action_deadzone(&"Left", 0.22)
	set_action_deadzone(&"Right", 0.22)
	set_action_deadzone(&"AimUp", 0.24)
	set_action_deadzone(&"AimDown", 0.24)
	set_action_deadzone(&"AimLeft", 0.24)
	set_action_deadzone(&"AimRight", 0.24)
	set_action_deadzone(&"Shoot", 0.32)
	set_action_deadzone(&"ui_up", 0.42)
	set_action_deadzone(&"ui_down", 0.42)
	set_action_deadzone(&"ui_left", 0.42)
	set_action_deadzone(&"ui_right", 0.42)
	add_controller_axis(&"Up", JOY_AXIS_LEFT_Y, -1.0)
	add_controller_axis(&"Down", JOY_AXIS_LEFT_Y, 1.0)
	add_controller_axis(&"Left", JOY_AXIS_LEFT_X, -1.0)
	add_controller_axis(&"Right", JOY_AXIS_LEFT_X, 1.0)
	add_controller_button(&"Up", JOY_BUTTON_DPAD_UP)
	add_controller_button(&"Down", JOY_BUTTON_DPAD_DOWN)
	add_controller_button(&"Left", JOY_BUTTON_DPAD_LEFT)
	add_controller_button(&"Right", JOY_BUTTON_DPAD_RIGHT)
	add_controller_axis(&"AimUp", JOY_AXIS_RIGHT_Y, -1.0)
	add_controller_axis(&"AimDown", JOY_AXIS_RIGHT_Y, 1.0)
	add_controller_axis(&"AimLeft", JOY_AXIS_RIGHT_X, -1.0)
	add_controller_axis(&"AimRight", JOY_AXIS_RIGHT_X, 1.0)
	add_controller_button(&"Interact", JOY_BUTTON_A)
	add_controller_button(&"DodgeRoll", JOY_BUTTON_B)
	add_controller_button(&"Codex", JOY_BUTTON_Y)
	add_controller_axis(&"Shoot", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	add_controller_button(&"Shoot", JOY_BUTTON_RIGHT_SHOULDER)
	add_controller_button(&"Pause", JOY_BUTTON_START)
	add_controller_axis(&"ui_up", JOY_AXIS_LEFT_Y, -1.0)
	add_controller_axis(&"ui_down", JOY_AXIS_LEFT_Y, 1.0)
	add_controller_axis(&"ui_left", JOY_AXIS_LEFT_X, -1.0)
	add_controller_axis(&"ui_right", JOY_AXIS_LEFT_X, 1.0)
	add_controller_button(&"ui_up", JOY_BUTTON_DPAD_UP)
	add_controller_button(&"ui_down", JOY_BUTTON_DPAD_DOWN)
	add_controller_button(&"ui_left", JOY_BUTTON_DPAD_LEFT)
	add_controller_button(&"ui_right", JOY_BUTTON_DPAD_RIGHT)
	add_controller_button(&"ui_accept", JOY_BUTTON_A)
	add_controller_button(&"ui_cancel", JOY_BUTTON_B)

func clear_controller_events(action: StringName) -> void:
	ensure_input_action(action)
	for existing_event in InputMap.action_get_events(action):
		if existing_event is InputEventJoypadMotion or existing_event is InputEventJoypadButton:
			InputMap.action_erase_event(action, existing_event)

func set_action_deadzone(action: StringName, deadzone: float) -> void:
	ensure_input_action(action)
	InputMap.action_set_deadzone(action, deadzone)

func note_controller_activity() -> void:
	last_controller_input_msec = Time.get_ticks_msec()
	controller_input_active = true
	keyboard_navigation_active = true
	set_cursor_visible(false)

func get_controller_aim_vector() -> Vector2:
	var strongest_vector := Vector2.ZERO
	for device_id in Input.get_connected_joypads():
		var stick := Vector2(
			Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_X),
			Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_Y)
		)
		if stick.length_squared() > strongest_vector.length_squared():
			strongest_vector = stick
	# Keep an InputMap fallback for virtual controllers supplied by Steam Input.
	var mapped_stick := Input.get_vector("AimLeft", "AimRight", "AimUp", "AimDown", 0.0)
	if mapped_stick.length_squared() > strongest_vector.length_squared():
		strongest_vector = mapped_stick
	return strongest_vector.limit_length(1.0)

func should_ignore_emulated_mouse_motion() -> bool:
	if Time.get_ticks_msec() - last_controller_input_msec <= CONTROLLER_SOURCE_LOCK_MSEC:
		return true
	for device_id in Input.get_connected_joypads():
		var left_stick := Vector2(
			Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y)
		)
		var right_stick := Vector2(
			Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_X),
			Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_Y)
		)
		if maxf(left_stick.length(), right_stick.length()) > CONTROLLER_ACTIVITY_DEADZONE:
			return true
	return false

func register_controller_mappings() -> void:
	# Godot 4.5+ uses SDL 3, but registering the official USB mapping here also
	# covers Windows machines whose bundled database does not identify Switch Pro.
	Input.add_joy_mapping(SWITCH_PRO_WINDOWS_MAPPING, true)

func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if not connected:
		print("[Controller] Disconnected device ", device_id)
		return
	print(
		"[Controller] Connected device ", device_id,
		": ", Input.get_joy_name(device_id),
		" | GUID: ", Input.get_joy_guid(device_id),
		" | info: ", Input.get_joy_info(device_id)
	)

func add_controller_axis(action: StringName, axis_index: int, axis_value: float) -> void:
	ensure_input_action(action)
	for existing_event in InputMap.action_get_events(action):
		if existing_event is InputEventJoypadMotion:
			var existing_motion := existing_event as InputEventJoypadMotion
			if int(existing_motion.axis) == axis_index and is_equal_approx(existing_motion.axis_value, axis_value):
				return
	var motion := InputEventJoypadMotion.new()
	motion.device = -1
	motion.axis = axis_index as JoyAxis
	motion.axis_value = axis_value
	InputMap.action_add_event(action, motion)

func add_controller_button(action: StringName, button_index: int) -> void:
	ensure_input_action(action)
	for existing_event in InputMap.action_get_events(action):
		if existing_event is InputEventJoypadButton and int((existing_event as InputEventJoypadButton).button_index) == button_index:
			return
	var button := InputEventJoypadButton.new()
	button.device = -1
	button.button_index = button_index as JoyButton
	InputMap.action_add_event(action, button)

func ensure_input_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.22)

func clear_button_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()

func find_first_available_button(node: Node) -> BaseButton:
	var button := node as BaseButton
	if button and button.visible and not button.disabled:
		return button
	for child in node.get_children():
		var found := find_first_available_button(child)
		if found:
			return found
	return null

func setup_button(button: BaseButton) -> void:
	if not button or button.has_meta("tower_ui_juiced") or button.has_meta("reel_menu_button") or button.has_meta("custom_card_animation"):
		return
	# The press animation scales the Control itself. Trigger immediately so a
	# smaller transformed hitbox cannot invalidate an otherwise good click.
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	# Keep all text buttons consistent, including controls created at runtime.
	if button is Button:
		var text_button := button as Button
		text_button.text = text_button.text.to_upper()
		text_button.add_theme_font_override("font", CAPITAL_BOLD_FONT)
	button.set_meta("tower_ui_juiced", true)
	button.pivot_offset = button.size * 0.5
	button.resized.connect(func(): button.pivot_offset = button.size * 0.5)
	button.mouse_entered.connect(func():
		play_navigation_sound()
		animate_button(button, HOVER_SCALE, 0.08)
	)
	button.mouse_exited.connect(func(): animate_button(button, Vector2.ONE, 0.08))
	button.button_down.connect(func(): animate_button(button, PRESS_SCALE, 0.045))
	button.button_up.connect(func(): animate_button(button, HOVER_SCALE if button.is_hovered() else Vector2.ONE, 0.08))
	button.focus_entered.connect(func():
		play_navigation_sound()
		animate_button(button, HOVER_SCALE, 0.08)
	)
	button.focus_exited.connect(func(): animate_button(button, Vector2.ONE, 0.08))
	button.pressed.connect(play_confirm_sound)

func animate_button(button: BaseButton, target_scale: Vector2, duration: float) -> void:
	if not is_instance_valid(button):
		return
	var tween := button.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", target_scale, duration)

func play_navigation_sound() -> void:
	var current_time := Time.get_ticks_msec() * 0.001
	if current_time - last_navigation_sound_time < 0.07:
		return
	last_navigation_sound_time = current_time
	if navigation_player:
		navigation_player.play()

func play_confirm_sound() -> void:
	if confirm_player:
		confirm_player.play()
