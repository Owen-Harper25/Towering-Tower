extends CanvasLayer

@onready var heart_container: HBoxContainer = $Control/HeartContainer
@onready var coin_label: Label = $Control/CoinLabel
var coin_label_tween: Tween

func _ready() -> void:
	coin_label.modulate.a = 0.0
	coin_label.hide()
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

func update_hearts(current_health: int, _max_health: int = 0) -> void:
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

func update_coins(amount: int) -> void:
	coin_label.text = "COINS: %d" % amount
	show_coins_temporarily()

func show_coins_temporarily() -> void:
	if coin_label_tween and coin_label_tween.is_valid():
		coin_label_tween.kill()
	coin_label.show()
	coin_label.modulate.a = 0.0
	coin_label_tween = create_tween()
	coin_label_tween.tween_property(coin_label, "modulate:a", 1.0, 0.16)
	coin_label_tween.tween_interval(1.5)
	coin_label_tween.tween_property(coin_label, "modulate:a", 0.0, 0.28)
	coin_label_tween.tween_callback(coin_label.hide)

func set_coins_visible(visible: bool) -> void:
	if visible:
		show_coins_temporarily()
	elif coin_label_tween and coin_label_tween.is_valid():
		coin_label_tween.kill()
		coin_label.hide()
