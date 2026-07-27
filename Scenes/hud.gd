extends CanvasLayer

@onready var heart_container: HBoxContainer = $Control/HeartContainer
@export var heart_gui_scene: PackedScene

func setup_hearts(max_health: int, current_health: int) -> void:
	for child in heart_container.get_children():
		child.queue_free()

	# 1 Heart Container = 2 HP
	var total_hearts := int(ceil(max_health / 2.0))

	for i in range(total_hearts):
		var heart = heart_gui_scene.instantiate()
		heart_container.add_child(heart)

	update_hearts(current_health)

func update_hearts(current_health: int) -> void:
	var hearts = heart_container.get_children()
	
	for i in range(hearts.size()):
		var heart = hearts[i]
		var heart_value = (i + 1) * 2

		if current_health >= heart_value:
			heart.set_heart_state(heart.HeartState.FULL)
		elif current_health == heart_value - 1:
			heart.set_heart_state(heart.HeartState.HALF)
		else:
			heart.set_heart_state(heart.HeartState.EMPTY)
