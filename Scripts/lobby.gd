extends Node2D

@onready var shop_interactable: Area2D = $ShopKeeper/Interactable
@onready var tree_interactable: Area2D = $SkillTree/Interactable
@onready var teleporter_interactable: Area2D = $Teleporter/Interactable

var panel: Panel
var panel_content: VBoxContainer

func _ready() -> void:
	add_to_group("safe_lobby")
	configure_interactable(shop_interactable, "E - TALK WITH TOWER MERCHANT", open_shop)
	configure_interactable(tree_interactable, "E - RUNE TREE", open_skill_tree)
	configure_interactable(teleporter_interactable, "E - ENTER THE TOWER", enter_tower)
	create_overlay()

func configure_interactable(interactable: Area2D, prompt: String, action: Callable) -> void:
	interactable.interact_name = prompt
	interactable.interact = action

func create_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 15
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	panel = Panel.new()
	panel.size = Vector2(266, 184)
	panel.position = (get_viewport_rect().size - panel.size) * 0.5
	panel.hide()
	root.add_child(panel)
	panel_content = VBoxContainer.new()
	panel_content.position = Vector2(14, 12)
	panel_content.size = Vector2(238, 158)
	panel_content.add_theme_constant_override("separation", 6)
	panel.add_child(panel_content)
	add_child(layer)

func clear_panel() -> void:
	for child in panel_content.get_children():
		child.queue_free()

func add_title(text: String) -> void:
	var title := Label.new()
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel_content.add_child(title)

func add_close_button() -> void:
	var close_button := Button.new()
	close_button.text = "LEAVE"
	close_button.pressed.connect(func(): panel.hide())
	panel_content.add_child(close_button)

func open_shop() -> void:
	clear_panel()
	add_title("THE TOWER MERCHANT")
	var text := Label.new()
	text.text = "Coins from runs become permanent Tower Coins."
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_content.add_child(text)
	var balance := Label.new()
	balance.text = "TOWER COINS: %d" % MetaProgression.currency
	balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel_content.add_child(balance)
	add_close_button()
	panel.show()

func open_skill_tree() -> void:
	clear_panel()
	add_title("RUNE TREE")
	var balance := Label.new()
	balance.name = "Balance"
	balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel_content.add_child(balance)
	for upgrade_id in ["damage", "vitality", "rapid_fire"]:
		add_upgrade_button(upgrade_id)
	add_close_button()
	panel.show()
	refresh_skill_tree()

func add_upgrade_button(upgrade_id: String) -> void:
	var button := Button.new()
	button.name = upgrade_id
	button.pressed.connect(func():
		if MetaProgression.purchase(upgrade_id):
			refresh_skill_tree()
	)
	panel_content.add_child(button)

func refresh_skill_tree() -> void:
	if not panel or not panel.visible:
		return
	var balance := panel_content.get_node_or_null("Balance") as Label
	if balance:
		balance.text = "TOWER COINS: %d" % MetaProgression.currency
	for child in panel_content.get_children():
		var button := child as Button
		if not button or button.name == "":
			continue
		var upgrade_id: String = str(button.name)
		if not ["damage", "vitality", "rapid_fire"].has(upgrade_id):
			continue
		var level := MetaProgression.get_level(upgrade_id)
		var at_max := level >= MetaProgression.MAX_LEVEL
		button.text = "%s  Lv.%d  %s" % [upgrade_title(upgrade_id), level, "MAX" if at_max else "%d coins" % MetaProgression.get_cost(upgrade_id)]
		button.disabled = at_max or MetaProgression.currency < MetaProgression.get_cost(upgrade_id)

func upgrade_title(upgrade_id: String) -> String:
	match upgrade_id:
		"damage": return "SHARP ROUNDS"
		"vitality": return "REINFORCED HEARTS"
		_: return "QUICK DRAW"

func enter_tower() -> void:
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("start_combat_from_lobby"):
		main.start_combat_from_lobby()
