extends Node2D

@onready var interact_label: Label = $InteractLabel
var current_interactions := []
var can_interact := true
var interact_cooldown := 0.4
var interact_buffer := false
var joystick_threshold := -0.9
var last_highlighted: Area2D = null


func _process(_delta: float) -> void:
	var joy_y = Input.get_action_strength("Up")

	if joy_y < joystick_threshold and !interact_buffer and can_interact:
		_interact_action()
		interact_buffer = true
	elif joy_y > -0.2:
		interact_buffer = false

	if current_interactions and can_interact:
		current_interactions.sort_custom(_sort_by_nearest)
		var focused = current_interactions[0]

		if focused != last_highlighted:
			if last_highlighted and last_highlighted.has_method("set_highlighted"):
				last_highlighted.set_highlighted(false)

			if focused.has_method("set_highlighted"):
				focused.set_highlighted(true)

			last_highlighted = focused

		if focused.is_interactable:
			interact_label.text = focused.interact_name
			interact_label.show()
	else:
		if last_highlighted and last_highlighted.has_method("set_highlighted"):
			last_highlighted.set_highlighted(false)
		last_highlighted = null
		interact_label.hide()



func _input(event: InputEvent) -> void:
	#if Global.buffer_inputs or Global.talking:
		#return
	if event.is_action_pressed("Interact") and can_interact:
		_interact_action()

func _sort_by_nearest(area1, area2):
	var area1_dis = global_position.distance_to(area1.global_position)
	var area2_dis = global_position.distance_to(area2.global_position)
	return area1_dis < area2_dis

func _on_interact_range_area_entered(area: Area2D) -> void:
	current_interactions.push_back(area)

func _on_interact_range_area_exited(area: Area2D) -> void:
	current_interactions.erase(area)

# ---- Interaction logic ----
func _interact_action() -> void:
	if not current_interactions or not can_interact:
		return

	can_interact = false
	interact_label.hide()

	await current_interactions[0].interact.call()

	# Cooldown before allowing another interaction
	await get_tree().create_timer(interact_cooldown).timeout
	can_interact = true
