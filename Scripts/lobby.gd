extends Node2D

const COSMETICS := preload("res://Scripts/cosmetic_catalog.gd")

@onready var shop_interactable: Area2D = $ShopKeeper/Interactable
@onready var tree_interactable: Area2D = $SkillTree/Interactable
@onready var teleporter_interactable: Area2D = $Teleporter/Interactable
@onready var survival_interactable: Area2D = $SurvivalTeleporter/Interactable
@onready var mirror_interactable: Area2D = $WardrobeMirror/Interactable

var panel: Panel
var panel_content: VBoxContainer
var overlay_root: Control
var requested_panel_size := Vector2(300.0, 224.0)

func _ready() -> void:
	add_to_group("safe_lobby")
	configure_interactable(shop_interactable, "E - TALK WITH TOWER MERCHANT", open_shop)
	configure_interactable(tree_interactable, "E - RUNE TREE", open_skill_tree)
	configure_interactable(teleporter_interactable, "E - ENTER THE TOWER", enter_tower)
	configure_interactable(survival_interactable, "E - KERNEL SURVIVAL", enter_survival)
	configure_interactable(mirror_interactable, "E - CHANGE OUTFIT", open_wardrobe)
	create_overlay()

func configure_interactable(interactable: Area2D, prompt: String, action: Callable) -> void:
	interactable.interact_name = prompt
	interactable.interact = action

func create_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	overlay_root = Control.new()
	overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay_root)
	panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.hide()
	overlay_root.add_child(panel)
	panel_content = VBoxContainer.new()
	panel_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_content.offset_left = 14.0
	panel_content.offset_top = 12.0
	panel_content.offset_right = -14.0
	panel_content.offset_bottom = -12.0
	panel_content.add_theme_constant_override("separation", 6)
	panel.add_child(panel_content)
	add_child(layer)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	set_panel_size(requested_panel_size)

func clear_panel() -> void:
	for child in panel_content.get_children():
		panel_content.remove_child(child)
		child.queue_free()

func set_panel_size(new_size: Vector2) -> void:
	requested_panel_size = new_size
	var viewport_size := get_viewport_rect().size
	var safe_size := Vector2(
		minf(new_size.x, maxf(260.0, viewport_size.x - 24.0)),
		minf(new_size.y, maxf(180.0, viewport_size.y - 24.0))
	)
	panel.offset_left = -safe_size.x * 0.5
	panel.offset_top = -safe_size.y * 0.5
	panel.offset_right = safe_size.x * 0.5
	panel.offset_bottom = safe_size.y * 0.5

func _on_viewport_size_changed() -> void:
	if panel:
		set_panel_size(requested_panel_size)

func add_title(text: String) -> void:
	var title := Label.new()
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(0.0, 24.0)
	panel_content.add_child(title)

func add_close_button() -> void:
	var close_button := Button.new()
	close_button.text = "LEAVE"
	close_button.custom_minimum_size = Vector2(0.0, 28.0)
	close_button.pressed.connect(func(): panel.hide())
	panel_content.add_child(close_button)

func open_shop() -> void:
	clear_panel()
	set_panel_size(Vector2(420.0, 340.0))
	add_title("THE TOWER MERCHANT")
	var text := Label.new()
	text.text = "Permanent outfits. Purchased with Tower Coins."
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(0.0, 38.0)
	panel_content.add_child(text)
	var balance := Label.new()
	balance.text = "TOWER COINS: %d   KERNELS: %d" % [MetaProgression.currency, MetaProgression.kernel_currency]
	balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	balance.custom_minimum_size = Vector2(0.0, 22.0)
	panel_content.add_child(balance)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 72.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_content.add_child(scroll)
	var shop_grid := GridContainer.new()
	shop_grid.columns = 2
	shop_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_grid.add_theme_constant_override("h_separation", 6)
	shop_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(shop_grid)
	for cosmetic_id in COSMETICS.get_ids():
		add_cosmetic_shop_button(shop_grid, cosmetic_id)
	add_close_button()
	panel.show()

func add_cosmetic_shop_button(grid: GridContainer, cosmetic_id: String) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(184.0, 58.0)
	button.expand_icon = false
	button.icon = load(COSMETICS.get_texture_path(cosmetic_id)) as Texture2D
	var owned := MetaProgression.owns_cosmetic(cosmetic_id)
	button.text = "%s\n%s" % [COSMETICS.get_display_name(cosmetic_id), "OWNED" if owned else "%d GOLD" % COSMETICS.get_cost(cosmetic_id)]
	button.disabled = owned or MetaProgression.currency < COSMETICS.get_cost(cosmetic_id)
	button.pressed.connect(func():
		if MetaProgression.purchase_cosmetic(cosmetic_id):
			open_shop()
	)
	grid.add_child(button)

func open_wardrobe() -> void:
	clear_panel()
	set_panel_size(Vector2(440.0, 350.0))
	add_title("WARDROBE MIRROR")
	var instructions := Label.new()
	instructions.text = "SELECT AN UNLOCKED COSMETIC TO EQUIP IT."
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.custom_minimum_size = Vector2(0.0, 20.0)
	panel_content.add_child(instructions)
	var inventory_scroll := ScrollContainer.new()
	inventory_scroll.custom_minimum_size = Vector2(0.0, 72.0)
	inventory_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_content.add_child(inventory_scroll)
	var inventory_grid := GridContainer.new()
	inventory_grid.columns = 3
	inventory_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_grid.add_theme_constant_override("h_separation", 6)
	inventory_grid.add_theme_constant_override("v_separation", 6)
	inventory_scroll.add_child(inventory_grid)
	if MetaProgression.unlocked_cosmetics.is_empty():
		var empty_label := Label.new()
		empty_label.text = "THE MERCHANT HAS COSMETICS FOR SALE."
		empty_label.custom_minimum_size = Vector2(390.0, 70.0)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inventory_grid.add_child(empty_label)
	else:
		for cosmetic_id in MetaProgression.unlocked_cosmetics:
			add_wardrobe_button(inventory_grid, cosmetic_id)
	var clear_button := Button.new()
	clear_button.text = "CLEAR OUTFIT"
	clear_button.custom_minimum_size = Vector2(0.0, 27.0)
	clear_button.pressed.connect(func():
		MetaProgression.clear_equipped_cosmetics()
		open_wardrobe()
	)
	panel_content.add_child(clear_button)
	add_close_button()
	panel.show()

func add_wardrobe_button(grid: GridContainer, cosmetic_id: String) -> void:
	var slot := COSMETICS.get_slot(cosmetic_id)
	var equipped := cosmetic_id == MetaProgression.equipped_head_cosmetic or cosmetic_id == MetaProgression.equipped_back_cosmetic
	var button := Button.new()
	button.custom_minimum_size = Vector2(126.0, 76.0)
	button.expand_icon = false
	button.icon = load(COSMETICS.get_texture_path(cosmetic_id)) as Texture2D
	button.text = "%s\n%s" % [COSMETICS.get_display_name(cosmetic_id), "EQUIPPED" if equipped else slot.to_upper()]
	button.pressed.connect(func():
		if equipped:
			MetaProgression.unequip_cosmetic_slot(slot)
		else:
			MetaProgression.equip_cosmetic(cosmetic_id)
		open_wardrobe()
	)
	grid.add_child(button)

func open_skill_tree() -> void:
	clear_panel()
	add_title("RUNE TREE")
	var balance := Label.new()
	balance.name = "Balance"
	balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	balance.custom_minimum_size = Vector2(0.0, 22.0)
	panel_content.add_child(balance)
	for upgrade_id in ["damage", "vitality", "rapid_fire"]:
		add_upgrade_button(upgrade_id)
	add_close_button()
	panel.show()
	refresh_skill_tree()

func add_upgrade_button(upgrade_id: String) -> void:
	var button := Button.new()
	button.name = upgrade_id
	button.custom_minimum_size = Vector2(0.0, 28.0)
	button.pressed.connect(func():
		if MetaProgression.purchase(upgrade_id):
			apply_upgrades_to_local_player()
			refresh_skill_tree()
	)
	panel_content.add_child(button)

func apply_upgrades_to_local_player() -> void:
	for player_node in get_tree().get_nodes_in_group("players"):
		var player := player_node as CharacterBody2D
		if player and player.is_multiplayer_authority() and player.has_method("apply_meta_upgrades"):
			player.call("apply_meta_upgrades", true)
			return

func refresh_skill_tree() -> void:
	if not panel or not panel.visible:
		return
	var balance := panel_content.get_node_or_null("Balance") as Label
	if balance:
		balance.text = "TOWER COINS: %d   KERNELS: %d" % [MetaProgression.currency, MetaProgression.kernel_currency]
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

func enter_survival() -> void:
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("start_survival_from_lobby"):
		main.start_survival_from_lobby()
