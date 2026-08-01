extends Node

const HOVER_SCALE := Vector2(1.045, 1.045)
const PRESS_SCALE := Vector2(0.96, 0.96)
const NAVIGATION_SOUND := preload("res://SFX/select.wav")
const CONFIRM_SOUND := preload("res://SFX/Confirm.wav")

var navigation_player: AudioStreamPlayer
var confirm_player: AudioStreamPlayer
var last_navigation_sound_time := -1.0
var keyboard_navigation_active := false

func _ready() -> void:
	create_audio_players()
	get_tree().node_added.connect(_on_node_added)
	call_deferred("style_existing_buttons")

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
	if event is InputEventMouseMotion:
		keyboard_navigation_active = false
		clear_button_focus.call_deferred()
		return
	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		keyboard_navigation_active = true
		if not get_viewport().gui_get_focus_owner():
			var first_button := find_first_available_button(get_tree().root)
			if first_button:
				first_button.grab_focus()

func clear_button_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused is BaseButton:
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
	if not button or button.has_meta("tower_ui_juiced"):
		return
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
