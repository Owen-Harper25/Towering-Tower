extends Node2D

const RUSHER_SCENE := preload("res://Scenes/standard_bullet_enemy.tscn")
const SNIPER_SCENE := preload("res://Scenes/sniper_bullet_enemy.tscn")
const TURRET_SCENE := preload("res://Scenes/turret_enemy.tscn")
const ASCENSION_BOSS_SCENE := preload("res://Scenes/ascension_popcorn_boss.tscn")
const BOONS := preload("res://Scripts/boon_catalog.gd")
const EXPEDITION := preload("res://Scripts/expedition_catalog.gd")
const TREE_ENVIRONMENT := preload("res://Scripts/alien_tree_environment.gd")
const CAPITAL_BOLD_FONT := preload("res://Assets/Capital Bold - Normal.ttf")
const CARD_FOIL_SHADER := preload("res://Shaders/card_foil.gdshader")
const CARD_DEAL_SFX := preload("res://SFX/oxidvideos-placing-playing-card-522514.mp3")
const CARD_FLIP_SFX := preload("res://SFX/oxidvideos-taking-playing-card-2-522516.mp3")
const CARD_HOVER_SFX := preload("res://SFX/click.mp3")
const CARD_SELECT_SFX := preload("res://SFX/confrimation.mp3")
const CODEX_OPEN_SFX := preload("res://SFX/freesound_community-menu-selection-102220.mp3")
const CODEX_CLOSE_SFX := preload("res://SFX/close.mp3")
const BOSS_PRESENTATION_PATHS: Array[String] = [
	"res://Scenes/tree_guardian_sap.tscn",
	"res://Scenes/tree_guardian_marrow.tscn",
	"res://Scenes/tree_guardian_choir.tscn",
	"res://Scenes/tree_guardian_prism.tscn",
	"res://Scenes/tree_guardian_apostle.tscn",
	"res://Scenes/tree_guardian_seraph.tscn",
]

@export var arena_bounds: Rect2 = Rect2(28, 30, 424, 220)
@export var time_between_waves: float = 2.5

var wave := 0
var wave_active := false
var next_wave_time := 0.0
var run_started := true
var enemy_state_sync_elapsed := 0.0
var next_enemy_id := 1
var last_boss_kind := -1
var boss_kind_bag: Array[int] = []
@onready var enemies: Node2D = $Enemies
var wave_banner: ColorRect
var wave_label: Label
var boon_draft_active := false
var boon_choices_by_peer: Dictionary = {}
var boon_draft_layer: CanvasLayer
var boon_debug_ui_only := false
var boon_book_overlay: CanvasLayer
var last_card_hover_sfx_time := -1.0
var boon_book_open := false
var boon_book_button: Button
var starting_boon_pending := false
var starting_boon_draft := false
var characteristic_level := 1
var characteristic_xp := 0
var pending_characteristic_draws := 0
var campaign_completed := false
var characteristic_label: Label
var characteristic_bar: ProgressBar
var environment: Node2D

func _ready() -> void:
	if bool(get_meta("boon_debug_ui_only", false)):
		boon_debug_ui_only = true
		return
	add_to_group("tower_arena")
	create_wave_banner()
	create_boon_book_button()
	create_characteristic_hud()
	create_expedition_environment()
	if multiplayer.is_server():
		next_wave_time = 1.2

func begin_starting_boon_draft() -> void:
	if not is_inside_tree() or not multiplayer.is_server() or not starting_boon_pending:
		return
	if get_expected_boon_peer_ids().is_empty():
		get_tree().create_timer(0.25, false).timeout.connect(begin_starting_boon_draft)
		return
	begin_boon_draft(true)

func _unhandled_input(event: InputEvent) -> void:
	if boon_book_open and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("Pause")):
		close_boon_book()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("Codex") and not boon_draft_active:
		if boon_book_open:
			close_boon_book()
		else:
			open_boon_book()
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if boon_book_open or boon_draft_active:
		var local_player := get_local_player()
		if local_player:
			local_player.set("ui_input_locked", false)
	set_single_player_menu_pause("codex", false)
	set_single_player_menu_pause("boon_draft", false)

func create_boon_book_button() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 13
	boon_book_button = Button.new()
	boon_book_button.name = "AscensionCodexButton"
	boon_book_button.text = "FIELD CODEX"
	boon_book_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	boon_book_button.tooltip_text = "VIEW RECOVERED CHARACTERISTICS"
	boon_book_button.icon = create_boon_book_texture()
	boon_book_button.expand_icon = false
	boon_book_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	boon_book_button.offset_left = -94.0
	boon_book_button.offset_top = -37.0
	boon_book_button.offset_right = -8.0
	boon_book_button.offset_bottom = -8.0
	boon_book_button.add_theme_font_override("font", CAPITAL_BOLD_FONT)
	boon_book_button.add_theme_font_size_override("font_size", 9)
	boon_book_button.pressed.connect(open_boon_book)
	layer.add_child(boon_book_button)
	add_child(layer)
	call_deferred("update_boon_book_button_count")

func update_boon_book_button_count() -> void:
	if not boon_book_button:
		return
	var local_player := get_local_player()
	var card_count := 0
	if local_player:
		var acquired_value: Variant = local_player.get("acquired_boons")
		if acquired_value is Array:
			card_count = (acquired_value as Array).size()
	boon_book_button.text = "CODEX  %d" % card_count if card_count > 0 else "FIELD CODEX"

func create_boon_book_texture() -> ImageTexture:
	var image := Image.create_empty(18, 14, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(2, 12):
		for x in range(1, 9):
			image.set_pixel(x, y, Color("6f2448"))
		for x in range(9, 17):
			image.set_pixel(x, y, Color("8c3153"))
	for y in range(3, 11):
		image.set_pixel(8, y, Color("e8c77c"))
		image.set_pixel(9, y, Color("f5dc99"))
	for x in range(2, 16):
		image.set_pixel(x, 1, Color("f3dda3"))
		image.set_pixel(x, 12, Color("c89d55"))
	image.set_pixel(4, 6, Color("ffd45c"))
	image.set_pixel(5, 5, Color("ffd45c"))
	image.set_pixel(5, 7, Color("ffd45c"))
	image.set_pixel(6, 6, Color("ffd45c"))
	return ImageTexture.create_from_image(image)

func open_boon_book() -> void:
	if boon_book_open or boon_draft_active:
		return
	var local_player := get_local_player()
	if not local_player:
		return
	boon_book_open = true
	play_card_sfx(CODEX_OPEN_SFX, -5.0)
	update_boon_book_button_count()
	local_player.set("ui_input_locked", true)
	create_boon_book_overlay(local_player.get("acquired_boons"))
	set_single_player_menu_pause("codex", true)

func close_boon_book() -> void:
	var was_open := boon_book_open
	boon_book_open = false
	if boon_book_overlay and is_instance_valid(boon_book_overlay):
		boon_book_overlay.queue_free()
	boon_book_overlay = null
	var local_player := get_local_player()
	if local_player:
		local_player.set("ui_input_locked", false)
	if was_open:
		play_card_sfx(CODEX_CLOSE_SFX, -5.0)
	set_single_player_menu_pause("codex", false)

func set_single_player_menu_pause(reason: String, should_pause: bool) -> void:
	var main_nodes := get_tree().get_nodes_in_group("main")
	if main_nodes.is_empty():
		return
	var main_node := main_nodes[0]
	if main_node.has_method("set_single_player_menu_paused"):
		main_node.call("set_single_player_menu_paused", reason, should_pause)

func get_local_player() -> CharacterBody2D:
	for player_node in get_tree().get_nodes_in_group("players"):
		var player := player_node as CharacterBody2D
		if player and player.is_multiplayer_authority():
			return player
	return null

func create_boon_book_overlay(acquired_value: Variant) -> void:
	boon_book_overlay = CanvasLayer.new()
	boon_book_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	boon_book_overlay.layer = 74
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.012, 0.035, 0.90)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	boon_book_overlay.add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -224.0
	panel.offset_top = -119.0
	panel.offset_right = 224.0
	panel.offset_bottom = 119.0
	panel.add_theme_stylebox_override("panel", create_boon_card_style(Color("d7b45b"), Color(0.12, 0.055, 0.12, 0.98), 3))
	shade.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	panel.add_child(content)
	var title := Label.new()
	title.text = "FIELD CHARACTERISTIC CODEX"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", CAPITAL_BOLD_FONT)
	title.add_theme_font_size_override("font_size", 15)
	content.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "TRAITS RECOVERED FROM THE TREE"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.86, 0.72, 0.45)
	subtitle.add_theme_font_override("font", CAPITAL_BOLD_FONT)
	subtitle.add_theme_font_size_override("font_size", 8)
	content.add_child(subtitle)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	var acquired: Array = acquired_value if acquired_value is Array else []
	if acquired.is_empty():
		var empty_label := Label.new()
		empty_label.text = "NO CARDS YET\nDEFEAT AN ASCENSION BOSS TO DRAW ONE"
		empty_label.custom_minimum_size = Vector2(410.0, 120.0)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_override("font", CAPITAL_BOLD_FONT)
		empty_label.add_theme_font_size_override("font_size", 9)
		grid.add_child(empty_label)
	else:
		var card_index := 0
		for card_value in acquired:
			var card_parts := str(card_value).split(":", false, 1)
			if card_parts.is_empty():
				continue
			var boon_id := str(card_parts[0])
			var rarity := int(card_parts[1]) if card_parts.size() > 1 else 0
			create_boon_book_card(grid, boon_id, rarity, card_index)
			card_index += 1
	var close_button := Button.new()
	close_button.set_meta("custom_card_animation", true)
	close_button.text = "CLOSE  [ESC]"
	close_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	close_button.custom_minimum_size = Vector2(0.0, 25.0)
	close_button.add_theme_font_override("font", CAPITAL_BOLD_FONT)
	close_button.add_theme_font_size_override("font_size", 9)
	close_button.pressed.connect(close_boon_book)
	content.add_child(close_button)
	add_child(boon_book_overlay)
	if UIJuice.keyboard_navigation_active:
		close_button.call_deferred("grab_focus")

func create_boon_book_card(parent: GridContainer, boon_id: String, rarity: int, display_index: int) -> void:
	var rarity_color := BOONS.get_rarity_color(rarity)
	var paper_color := Color(0.90, 0.84, 0.68).lerp(rarity_color, 0.08)
	var card := Button.new()
	card.set_meta("custom_card_animation", true)
	card.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	card.custom_minimum_size = Vector2(98.0, 126.0)
	card.focus_mode = Control.FOCUS_NONE
	card.disabled = true
	card.add_theme_stylebox_override("normal", create_boon_card_style(rarity_color, paper_color, 3))
	card.add_theme_stylebox_override("hover", create_boon_card_style(rarity_color.lightened(0.20), paper_color.lightened(0.06), 4))
	card.add_theme_stylebox_override("pressed", create_boon_card_style(rarity_color, paper_color, 3))
	card.add_theme_stylebox_override("disabled", create_boon_card_style(rarity_color, paper_color, 3))
	var base_rotation := deg_to_rad(float((display_index % 3) - 1) * 1.2)
	card.rotation = base_rotation
	card.set_meta("base_rotation", base_rotation)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 7.0
	content.offset_top = 5.0
	content.offset_right = -7.0
	content.offset_bottom = -5.0
	content.add_theme_constant_override("separation", 2)
	card.add_child(content)
	card.set_meta("card_content", content)
	var rarity_label := Label.new()
	rarity_label.text = BOONS.get_rarity_name(rarity)
	rarity_label.modulate = rarity_color
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_label.add_theme_font_override("font", CAPITAL_BOLD_FONT)
	rarity_label.add_theme_font_size_override("font_size", 7)
	content.add_child(rarity_label)
	var icon := TextureRect.new()
	icon.texture = create_boon_pixel_icon(BOONS.get_sigil(boon_id), rarity_color)
	icon.custom_minimum_size = Vector2(0.0, 38.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	content.add_child(icon)
	var name_label := Label.new()
	name_label.text = BOONS.get_display_name(boon_id)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_override("font", CAPITAL_BOLD_FONT)
	name_label.add_theme_font_size_override("font_size", 7)
	name_label.add_theme_color_override("font_color", Color(0.13, 0.055, 0.13))
	content.add_child(name_label)
	var description := Label.new()
	description.text = BOONS.get_description(boon_id, rarity).to_upper()
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description.add_theme_font_override("font", CAPITAL_BOLD_FONT)
	description.add_theme_font_size_override("font_size", 6)
	description.add_theme_color_override("font_color", Color(0.18, 0.08, 0.16))
	content.add_child(description)
	add_card_foil(card, rarity)
	var card_back := create_card_back_overlay(card, rarity_color)
	card.mouse_entered.connect(func():
		play_card_hover_sfx()
		animate_codex_card_hover(card, true)
	)
	card.mouse_exited.connect(func(): animate_codex_card_hover(card, false))
	parent.add_child(card)
	card.call_deferred("set_pivot_offset", card.custom_minimum_size * 0.5)
	call_deferred("deal_codex_card", card, parent, display_index, card_back, rarity_color)

func animate_codex_card_hover(card: Button, raised: bool) -> void:
	if not is_instance_valid(card) or card.disabled:
		return
	if card.has_meta("codex_wobble_tween"):
		var old_wobble: Variant = card.get_meta("codex_wobble_tween")
		if old_wobble is Tween and old_wobble.is_valid():
			old_wobble.kill()
	card.z_index = 20 if raised else 0
	var base_rotation := float(card.get_meta("base_rotation", 0.0))
	var scale_tween := card.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(card, "scale", Vector2.ONE * (1.10 if raised else 1.0), 0.14)
	if not raised:
		scale_tween.parallel().tween_property(card, "rotation", base_rotation, 0.14)
		return
	var wobble := card.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	wobble.tween_property(card, "rotation", base_rotation + 0.035, 0.34)
	wobble.tween_property(card, "rotation", base_rotation - 0.035, 0.68)
	wobble.tween_property(card, "rotation", base_rotation, 0.34)
	card.set_meta("codex_wobble_tween", wobble)

func add_card_foil(card: Control, rarity: int) -> void:
	if rarity < BOONS.Rarity.EPIC:
		return
	var foil := ColorRect.new()
	foil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	foil.offset_left = 3.0
	foil.offset_top = 3.0
	foil.offset_right = -3.0
	foil.offset_bottom = -3.0
	var foil_material := ShaderMaterial.new()
	foil_material.shader = CARD_FOIL_SHADER
	foil_material.set_shader_parameter("intensity", 1.0 if rarity == BOONS.Rarity.LEGENDARY else 0.58)
	foil.material = foil_material
	card.add_child(foil)

func create_card_back_overlay(card: Control, accent: Color) -> PanelContainer:
	var back := PanelContainer.new()
	back.name = "CardBack"
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.add_theme_stylebox_override("panel", create_boon_card_style(accent.lightened(0.18), Color("24142f"), 4))
	var back_layout := VBoxContainer.new()
	back_layout.alignment = BoxContainer.ALIGNMENT_CENTER
	back_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(back_layout)
	var top_mark := Label.new()
	top_mark.text = "◆"
	top_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_mark.modulate = accent.lightened(0.28)
	top_mark.add_theme_font_size_override("font_size", 12)
	back_layout.add_child(top_mark)
	var book_icon := TextureRect.new()
	book_icon.texture = create_boon_book_texture()
	book_icon.custom_minimum_size = Vector2(0.0, 42.0)
	book_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	book_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	book_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	back_layout.add_child(book_icon)
	var back_title := Label.new()
	back_title.text = "CHARACTERISTIC"
	back_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back_title.add_theme_font_override("font", CAPITAL_BOLD_FONT)
	back_title.add_theme_font_size_override("font_size", 7)
	back_title.modulate = Color(0.94, 0.88, 1.0)
	back_layout.add_child(back_title)
	card.add_child(back)
	return back

func create_wave_banner() -> void:
	var banner_layer := CanvasLayer.new()
	banner_layer.layer = 11
	wave_banner = ColorRect.new()
	wave_banner.color = Color(0.04, 0.08, 0.16, 0.92)
	wave_banner.size = Vector2(224, 42)
	wave_banner.position = Vector2(get_viewport_rect().size.x - 232.0, -50.0)
	wave_label = Label.new()
	wave_label.position = Vector2(8, 5)
	wave_label.size = Vector2(208, 32)
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wave_label.add_theme_font_override("font", CAPITAL_BOLD_FONT)
	wave_label.add_theme_font_size_override("font_size", 8)
	wave_banner.add_child(wave_label)
	banner_layer.add_child(wave_banner)
	add_child(banner_layer)
	update_wave_banner("PREPARE")

func update_wave_banner(status: String) -> void:
	if not wave_banner or not wave_label:
		return
	var branch: Dictionary = EXPEDITION.get_branch(maxi(1, wave))
	var floor_text := "FINAL NEST" if EXPEDITION.is_final_floor(wave) else "FLOOR %d/10" % EXPEDITION.get_floor_in_branch(maxi(1, wave))
	wave_label.text = "%s  //  %s\n%s  %s" % [str(branch.get("short_name", "EXPEDITION")), floor_text, EXPEDITION.get_room_name(maxi(1, wave)), status]
	wave_banner.color = (branch.get("dark", Color("101425")) as Color).lightened(0.04)
	var target_position := Vector2(get_viewport_rect().size.x - 232.0, 8.0)
	wave_banner.position = Vector2(target_position.x, -50.0)
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(wave_banner, "position", target_position, 0.35)

func create_expedition_environment() -> void:
	for legacy_name in ["Ground", "Parallax2D2", "Parallax2D", "Parallax2D3", "Tower"]:
		var legacy_visual := get_node_or_null(legacy_name) as CanvasItem
		if legacy_visual:
			legacy_visual.hide()
	environment = TREE_ENVIRONMENT.new() as Node2D
	add_child(environment)
	update_expedition_environment(maxi(1, wave))

func update_expedition_environment(floor_number: int) -> void:
	if not environment or not environment.has_method("configure"):
		return
	var context_value := TREE_ENVIRONMENT.Context.CROWN_NEST if EXPEDITION.is_final_floor(floor_number) else TREE_ENVIRONMENT.Context.EXPEDITION
	var visual_data: Dictionary = EXPEDITION.get_branch(floor_number).duplicate()
	visual_data["arena_bounds"] = arena_bounds
	environment.call("configure", context_value, visual_data, floor_number)

func create_characteristic_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 12
	var panel := ColorRect.new()
	panel.color = Color(0.025, 0.04, 0.075, 0.90)
	panel.position = Vector2(8.0, 8.0)
	panel.size = Vector2(154.0, 32.0)
	characteristic_label = Label.new()
	characteristic_label.position = Vector2(7.0, 3.0)
	characteristic_label.size = Vector2(140.0, 12.0)
	characteristic_label.add_theme_font_override("font", CAPITAL_BOLD_FONT)
	characteristic_label.add_theme_font_size_override("font_size", 7)
	panel.add_child(characteristic_label)
	characteristic_bar = ProgressBar.new()
	characteristic_bar.position = Vector2(7.0, 18.0)
	characteristic_bar.size = Vector2(140.0, 7.0)
	characteristic_bar.show_percentage = false
	panel.add_child(characteristic_bar)
	layer.add_child(panel)
	add_child(layer)
	update_characteristic_hud()

func update_characteristic_hud() -> void:
	if not characteristic_label or not characteristic_bar:
		return
	var threshold: int = EXPEDITION.get_characteristic_threshold(characteristic_level)
	characteristic_label.text = "SOUL CHARACTERISTICS  LV.%d  %d/%d" % [characteristic_level, characteristic_xp, threshold]
	characteristic_bar.max_value = float(threshold)
	characteristic_bar.value = float(characteristic_xp)

func collect_characteristic(amount: int) -> void:
	if not multiplayer.is_server() or campaign_completed or amount <= 0:
		return
	characteristic_xp += amount
	var threshold: int = EXPEDITION.get_characteristic_threshold(characteristic_level)
	while characteristic_xp >= threshold:
		characteristic_xp -= threshold
		characteristic_level += 1
		pending_characteristic_draws += 1
		threshold = EXPEDITION.get_characteristic_threshold(characteristic_level)
	rpc("sync_characteristics_rpc", characteristic_level, characteristic_xp, pending_characteristic_draws)

func return_soul_to_tree() -> void:
	if not multiplayer.is_server():
		return
	characteristic_level = 1
	characteristic_xp = 0
	pending_characteristic_draws = 0
	rpc("sync_characteristics_rpc", characteristic_level, characteristic_xp, pending_characteristic_draws)

@rpc("authority", "call_local", "reliable")
func sync_characteristics_rpc(level_value: int, xp_value: int, pending_draws: int) -> void:
	characteristic_level = level_value
	characteristic_xp = xp_value
	pending_characteristic_draws = pending_draws
	update_characteristic_hud()

func is_on_tower(world_position: Vector2, edge_padding: float = 0.0) -> bool:
	var ellipse_center := arena_bounds.get_center()
	var radii := arena_bounds.size * 0.5 - Vector2(edge_padding, edge_padding)
	if radii.x <= 0.0 or radii.y <= 0.0:
		return false
	var normalized_offset := (world_position - ellipse_center) / radii
	return normalized_offset.length_squared() <= 1.0

func is_wave_active() -> bool:
	return wave_active

func can_players_join() -> bool:
	return false

func _physics_process(delta: float) -> void:
	if boon_debug_ui_only:
		return
	if not multiplayer.is_server():
		interpolate_remote_enemies(delta)
		return
	enemy_state_sync_elapsed += delta
	if enemy_state_sync_elapsed >= 0.08:
		enemy_state_sync_elapsed = 0.0
		rpc("sync_enemy_states_rpc", build_enemy_states())

	if wave_active:
		if get_living_enemy_count() == 0:
			if EXPEDITION.is_final_floor(wave):
				complete_expedition()
				return
			if EXPEDITION.is_guardian_floor(wave):
				rpc("announce_severed_branch_rpc", str(EXPEDITION.get_branch(wave).get("name", "UNKNOWN BRANCH")))
			rpc("sync_wave_state_rpc", wave, false)
			if pending_characteristic_draws > 0:
				begin_boon_draft(false)
				return
			next_wave_time = time_between_waves
			return
		return
	if boon_draft_active:
		check_boon_draft_completion()
		return

	next_wave_time -= delta
	if next_wave_time <= 0.0:
		start_wave()

func start_wave() -> void:
	if wave >= EXPEDITION.FINAL_FLOOR:
		return
	wave += 1
	rpc("sync_wave_state_rpc", wave, true)
	if EXPEDITION.is_guardian_floor(wave):
		spawn_boss()
		return
	var branch_index: int = EXPEDITION.get_branch_index(wave)
	var floor_in_branch: int = EXPEDITION.get_floor_in_branch(wave)
	var rusher_count: int = 2 + floori(float(floor_in_branch) * 0.55) + branch_index
	var sniper_count: int = maxi(0, floori(float(floor_in_branch + branch_index) * 0.32))
	var turret_count: int = maxi(0, floori(float(floor_in_branch - 2) * 0.24) + floori(float(branch_index) * 0.5))
	match (floor_in_branch - 1) % 3:
		0: rusher_count += 2
		1: turret_count += 2
		2: sniper_count += 2

	spawn_group(RUSHER_SCENE, rusher_count)
	spawn_group(SNIPER_SCENE, sniper_count)
	spawn_group(TURRET_SCENE, turret_count)

func begin_boon_draft(is_starting_draw: bool = false) -> void:
	if not multiplayer.is_server() or boon_draft_active:
		return
	boon_draft_active = true
	starting_boon_draft = is_starting_draw
	boon_choices_by_peer.clear()
	rpc("sync_wave_state_rpc", wave, false)
	var boon_ids := BOONS.get_ids()
	boon_ids.shuffle()
	var options: Array[Dictionary] = []
	for option_index in range(mini(3, boon_ids.size())):
		options.append({"id": boon_ids[option_index], "rarity": BOONS.roll_rarity()})
	rpc("show_boon_draft_rpc", options, is_starting_draw)

func get_expected_boon_peer_ids() -> Array[int]:
	var peer_ids: Array[int] = []
	for player_node in get_tree().get_nodes_in_group("players"):
		var player := player_node as CharacterBody2D
		if not player:
			continue
		var peer_id := player.get_multiplayer_authority()
		if peer_id > 0 and not peer_ids.has(peer_id):
			peer_ids.append(peer_id)
	return peer_ids

func check_boon_draft_completion() -> void:
	if not multiplayer.is_server() or not boon_draft_active:
		return
	var expected_peers := get_expected_boon_peer_ids()
	if expected_peers.is_empty():
		return
	for peer_id in expected_peers:
		if not boon_choices_by_peer.has(peer_id):
			return
	boon_draft_active = false
	starting_boon_pending = false
	starting_boon_draft = false
	pending_characteristic_draws = maxi(0, pending_characteristic_draws - 1)
	rpc("sync_characteristics_rpc", characteristic_level, characteristic_xp, pending_characteristic_draws)
	if pending_characteristic_draws > 0:
		next_wave_time = INF
		get_tree().create_timer(0.28, false).timeout.connect(func(): begin_boon_draft(false))
	else:
		next_wave_time = time_between_waves
	rpc("finish_boon_draft_rpc")

@rpc("authority", "call_local", "reliable")
func show_boon_draft_rpc(options: Array[Dictionary], is_starting_draw: bool = false) -> void:
	boon_draft_active = true
	starting_boon_draft = is_starting_draw
	var local_player := get_local_player()
	if local_player:
		local_player.set("ui_input_locked", true)
	create_boon_draft_ui(options, is_starting_draw)
	set_single_player_menu_pause("boon_draft", true)

func create_boon_draft_ui(options: Array[Dictionary], is_starting_draw: bool = false) -> void:
	if boon_draft_layer and is_instance_valid(boon_draft_layer):
		boon_draft_layer.queue_free()
	boon_draft_layer = CanvasLayer.new()
	boon_draft_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	boon_draft_layer.layer = 75
	var shade := ColorRect.new()
	shade.color = Color(0.045, 0.018, 0.075, 0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	boon_draft_layer.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 7)
	center.add_child(layout)
	var title := Label.new()
	title.text = "SELECT A RECOVERED CHARACTERISTIC"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", CAPITAL_BOLD_FONT)
	title.add_theme_font_size_override("font_size", 14)
	layout.add_child(title)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 8)
	layout.add_child(cards)
	for option_index in range(options.size()):
		var option := options[option_index]
		create_boon_tarot_card(cards, str(option.get("id", "")), int(option.get("rarity", 0)), option_index)
	var hint := Label.new()
	hint.text = "THE EXPEDITION WAITS FOR EVERY AGENT"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_override("font", CAPITAL_BOLD_FONT)
	hint.add_theme_font_size_override("font_size", 9)
	layout.add_child(hint)
	add_child(boon_draft_layer)

func create_boon_tarot_card(parent: HBoxContainer, boon_id: String, rarity: int, display_index: int) -> void:
	var rarity_color := BOONS.get_rarity_color(rarity)
	var paper_color := Color(0.93, 0.88, 0.72).lerp(rarity_color, 0.10)
	var ink_color := Color(0.12, 0.055, 0.16)
	var card := Button.new()
	card.set_meta("custom_card_animation", true)
	card.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	card.custom_minimum_size = Vector2(126.0, 174.0)
	card.focus_mode = Control.FOCUS_ALL
	card.disabled = true
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("normal", create_boon_card_style(rarity_color.darkened(0.10), paper_color, 4))
	card.add_theme_stylebox_override("hover", create_boon_card_style(rarity_color.lightened(0.18), paper_color.lightened(0.08), 6))
	card.add_theme_stylebox_override("focus", create_boon_card_style(Color.WHITE, paper_color.lightened(0.08), 6))
	card.add_theme_stylebox_override("pressed", create_boon_card_style(rarity_color, paper_color.darkened(0.08), 7))
	card.add_theme_stylebox_override("disabled", create_boon_card_style(rarity_color.darkened(0.10), paper_color, 4))
	var card_tilts := [-2.4, 1.3, -1.6]
	var base_rotation := deg_to_rad(float(card_tilts[display_index % card_tilts.size()]))
	card.rotation = base_rotation
	card.set_meta("base_rotation", base_rotation)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 7.0
	content.offset_top = 5.0
	content.offset_right = -7.0
	content.offset_bottom = -5.0
	content.add_theme_constant_override("separation", 2)
	card.add_child(content)
	card.set_meta("card_content", content)
	var rarity_label := Label.new()
	rarity_label.text = BOONS.get_rarity_name(rarity)
	rarity_label.modulate = rarity_color
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_label.add_theme_font_override("font", CAPITAL_BOLD_FONT)
	rarity_label.add_theme_font_size_override("font_size", 8)
	rarity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(rarity_label)
	var icon := TextureRect.new()
	icon.texture = create_boon_pixel_icon(BOONS.get_sigil(boon_id), rarity_color)
	icon.custom_minimum_size = Vector2(0.0, 42.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon)
	var name_label := Label.new()
	name_label.text = BOONS.get_display_name(boon_id)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(0.0, 24.0)
	name_label.add_theme_font_override("font", CAPITAL_BOLD_FONT)
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", ink_color)
	name_label.add_theme_color_override("font_outline_color", paper_color.darkened(0.12))
	name_label.add_theme_constant_override("outline_size", 1)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(name_label)
	var divider := HSeparator.new()
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(divider)
	var description := Label.new()
	description.text = BOONS.get_description(boon_id, rarity).to_upper()
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description.add_theme_font_override("font", CAPITAL_BOLD_FONT)
	description.add_theme_font_size_override("font_size", 7)
	description.add_theme_color_override("font_color", ink_color.lightened(0.08))
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(description)
	add_card_foil(card, rarity)
	var card_back := create_card_back_overlay(card, rarity_color)
	card.pressed.connect(func(): select_local_boon(boon_id, rarity))
	card.mouse_entered.connect(func():
		play_card_hover_sfx()
		animate_boon_card(card, true)
	)
	card.mouse_exited.connect(func(): animate_boon_card(card, false))
	card.focus_entered.connect(func():
		play_card_hover_sfx()
		animate_boon_card(card, true)
	)
	card.focus_exited.connect(func(): animate_boon_card(card, false))
	card.gui_input.connect(func(event: InputEvent): update_boon_card_mouse_tilt(card, event))
	parent.add_child(card)
	card.call_deferred("set_pivot_offset", card.custom_minimum_size * 0.5)
	call_deferred("deal_draft_card", card, parent, display_index, card_back, rarity_color)

func deal_draft_card(card: Button, parent: HBoxContainer, display_index: int, card_back: PanelContainer, rarity_color: Color) -> void:
	await get_tree().process_frame
	if not is_instance_valid(card) or not is_instance_valid(parent):
		return
	var target_position := card.position
	var deck_position := Vector2(parent.size.x * 0.5 - card.size.x * 0.5, target_position.y + 24.0)
	deal_card_from_stack(card, target_position, deck_position, display_index, card_back, rarity_color, float(card.get_meta("base_rotation", 0.0)))

func deal_codex_card(card: Button, parent: GridContainer, display_index: int, card_back: PanelContainer, rarity_color: Color) -> void:
	await get_tree().process_frame
	if not is_instance_valid(card) or not is_instance_valid(parent):
		return
	var target_position := card.position
	var deck_position := Vector2(parent.size.x * 0.5 - card.size.x * 0.5, 12.0)
	deal_card_from_stack(card, target_position, deck_position, display_index, card_back, rarity_color, float(card.get_meta("base_rotation", 0.0)))

func deal_card_from_stack(card: Button, target_position: Vector2, deck_position: Vector2, display_index: int, card_back: PanelContainer, rarity_color: Color, target_rotation: float) -> void:
	card.disabled = true
	card.z_index = 40 - display_index
	card.position = deck_position + Vector2(float(display_index % 3) * 1.5, float(display_index % 4) * -1.0)
	card.rotation = -0.08 + float(display_index % 5) * 0.025
	card.scale = Vector2.ONE * 0.74
	card.modulate.a = 0.0
	var deal_delay := float(display_index) * 0.085
	get_tree().create_timer(deal_delay).timeout.connect(func():
		if is_instance_valid(card):
			play_card_sfx(CARD_DEAL_SFX, -7.0, 0.94 + float(display_index % 5) * 0.025)
	)
	var deal_tween := card.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	deal_tween.tween_property(card, "position", target_position, 0.34).set_delay(deal_delay)
	deal_tween.tween_property(card, "rotation", target_rotation, 0.34).set_delay(deal_delay)
	deal_tween.tween_property(card, "scale", Vector2.ONE, 0.34).set_delay(deal_delay)
	deal_tween.tween_property(card, "modulate:a", 1.0, 0.16).set_delay(deal_delay)
	deal_tween.finished.connect(func(): flip_dealt_card(card, card_back, rarity_color))

func flip_dealt_card(card: Button, card_back: PanelContainer, rarity_color: Color) -> void:
	if not is_instance_valid(card) or not is_instance_valid(card_back):
		return
	play_card_sfx(CARD_FLIP_SFX, -5.0, randf_range(0.97, 1.04))
	var flip_tween := card.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	flip_tween.tween_property(card, "scale:x", 0.0, 0.105)
	flip_tween.tween_callback(card_back.hide)
	flip_tween.tween_callback(func(): spawn_card_reveal_sparkles(card, rarity_color))
	flip_tween.tween_property(card, "scale:x", 1.0, 0.17).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	flip_tween.tween_callback(func(): enable_revealed_card(card))
	flip_tween.tween_property(card, "scale", Vector2(1.04, 1.04), 0.07)
	flip_tween.tween_property(card, "scale", Vector2.ONE, 0.09)

func enable_revealed_card(card: Button) -> void:
	if not is_instance_valid(card):
		return
	card.disabled = false
	card.z_index = 0
	if UIJuice.keyboard_navigation_active and not get_viewport().gui_get_focus_owner():
		card.grab_focus()

func spawn_card_reveal_sparkles(card: Control, rarity_color: Color) -> void:
	for sparkle_index in range(10):
		var sparkle := Polygon2D.new()
		var radius := 1.2 + float(sparkle_index % 3) * 0.55
		sparkle.polygon = PackedVector2Array([
			Vector2(0.0, -radius), Vector2(radius, 0.0),
			Vector2(0.0, radius), Vector2(-radius, 0.0),
		])
		sparkle.position = card.size * 0.5
		sparkle.color = rarity_color.lightened(0.18 + float(sparkle_index % 2) * 0.20)
		card.add_child(sparkle)
		var direction := Vector2.from_angle(TAU * float(sparkle_index) / 10.0)
		var sparkle_tween := sparkle.create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		sparkle_tween.tween_property(sparkle, "position", sparkle.position + direction * randf_range(20.0, 42.0), 0.28)
		sparkle_tween.tween_property(sparkle, "scale", Vector2.ZERO, 0.28)
		sparkle_tween.tween_property(sparkle, "modulate:a", 0.0, 0.28)
		sparkle_tween.finished.connect(sparkle.queue_free)

func play_card_hover_sfx() -> void:
	var current_time := Time.get_ticks_msec() * 0.001
	if current_time - last_card_hover_sfx_time < 0.065:
		return
	last_card_hover_sfx_time = current_time
	play_card_sfx(CARD_HOVER_SFX, -10.0, randf_range(0.98, 1.06))

func play_card_sfx(stream: AudioStream, volume_db: float, pitch: float = 1.0) -> void:
	if not stream or not is_inside_tree():
		return
	var audio := AudioStreamPlayer.new()
	audio.stream = stream
	audio.bus = &"SFX"
	audio.volume_db = volume_db
	audio.pitch_scale = pitch
	add_child(audio)
	audio.finished.connect(audio.queue_free)
	audio.play()

func animate_boon_card(card: Button, raised: bool) -> void:
	if not is_instance_valid(card):
		return
	var previous_tween: Variant = card.get_meta("hover_tween") if card.has_meta("hover_tween") else null
	if previous_tween is Tween and previous_tween.is_valid():
		previous_tween.kill()
	card.z_index = 8 if raised else 0
	var target_rotation := 0.0 if raised else float(card.get_meta("base_rotation", 0.0))
	var target_scale := Vector2.ONE * 1.065 if raised else Vector2.ONE
	var tween := card.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation", target_rotation, 0.13)
	tween.tween_property(card, "scale", target_scale, 0.13)
	set_boon_card_content_parallax(card, Vector2.ZERO)
	card.set_meta("hover_tween", tween)

func update_boon_card_mouse_tilt(card: Button, event: InputEvent) -> void:
	if not (event is InputEventMouseMotion) or card.size.x <= 0.0 or card.size.y <= 0.0:
		return
	if card.has_meta("hover_tween"):
		var hover_tween: Variant = card.get_meta("hover_tween")
		if hover_tween is Tween and hover_tween.is_valid():
			hover_tween.kill()
	card.z_index = 8
	var mouse_motion := event as InputEventMouseMotion
	var normalized := mouse_motion.position / card.size - Vector2(0.5, 0.5)
	card.rotation = normalized.x * 0.11
	card.scale = Vector2(
		1.065 - absf(normalized.y) * 0.018,
		1.065 - absf(normalized.x) * 0.012
	)
	set_boon_card_content_parallax(card, normalized * Vector2(5.0, 3.0))

func set_boon_card_content_parallax(card: Button, offset: Vector2) -> void:
	if not card.has_meta("card_content"):
		return
	var content := card.get_meta("card_content") as Control
	if not is_instance_valid(content):
		return
	content.offset_left = 7.0 + offset.x
	content.offset_top = 5.0 + offset.y
	content.offset_right = -7.0 + offset.x
	content.offset_bottom = -5.0 + offset.y

func show_debug_boon_draft() -> void:
	boon_debug_ui_only = true
	var boon_ids := BOONS.get_ids()
	boon_ids.shuffle()
	var options: Array[Dictionary] = []
	for option_index in range(mini(3, boon_ids.size())):
		options.append({"id": boon_ids[option_index], "rarity": BOONS.roll_rarity()})
	create_boon_draft_ui(options)

func create_boon_card_style(border_color: Color, fill_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.shadow_color = Color(0.015, 0.005, 0.025, 0.78)
	style.shadow_size = 7
	style.shadow_offset = Vector2(3.0, 5.0)
	return style

func create_boon_pixel_icon(sigil: int, color: Color) -> ImageTexture:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var pale := color.lightened(0.38)
	for pixel_index in range(8):
		paint_icon_pixel(image, 15 + (pixel_index % 2), 4 + pixel_index * 3, 2, pale)
	match sigil % 6:
		0:
			paint_icon_pixel(image, 10, 10, 12, color)
			paint_icon_pixel(image, 13, 7, 6, pale)
		1:
			paint_icon_pixel(image, 9, 6, 14, 3, color)
			paint_icon_pixel(image, 12, 10, 8, 12, pale)
			paint_icon_pixel(image, 9, 23, 14, 3, color)
		2:
			paint_icon_pixel(image, 4, 10, 10, 5, color)
			paint_icon_pixel(image, 18, 10, 10, 5, color)
			paint_icon_pixel(image, 12, 14, 8, 11, pale)
		3:
			paint_icon_pixel(image, 7, 9, 8, 8, color)
			paint_icon_pixel(image, 17, 9, 8, 8, color)
			paint_icon_pixel(image, 10, 15, 12, 8, pale)
		4:
			paint_icon_pixel(image, 5, 8, 20, 4, color)
			paint_icon_pixel(image, 9, 14, 18, 4, pale)
			paint_icon_pixel(image, 5, 20, 20, 4, color)
		_:
			paint_icon_pixel(image, 13, 4, 6, 24, color)
			paint_icon_pixel(image, 5, 13, 22, 6, pale)
	return ImageTexture.create_from_image(image)

func paint_icon_pixel(image: Image, x: int, y: int, width: int, height_or_color: Variant, optional_color: Color = Color.WHITE) -> void:
	var height := width
	var color := optional_color
	if height_or_color is Color:
		color = height_or_color
	else:
		height = int(height_or_color)
	for px in range(x, mini(32, x + width)):
		for py in range(y, mini(32, y + height)):
			if px >= 0 and py >= 0:
				image.set_pixel(px, py, color)

func select_local_boon(boon_id: String, rarity: int) -> void:
	play_card_sfx(CARD_SELECT_SFX, -3.0, 1.0 + float(rarity) * 0.025)
	if boon_debug_ui_only:
		if boon_draft_layer and is_instance_valid(boon_draft_layer):
			boon_draft_layer.queue_free()
		return
	var local_peer_id := multiplayer.get_unique_id()
	for player_node in get_tree().get_nodes_in_group("players"):
		var player := player_node as CharacterBody2D
		if player and player.is_multiplayer_authority() and player.has_method("apply_ascension_boon"):
			player.call("apply_ascension_boon", boon_id, rarity)
			update_boon_book_button_count()
			break
	if boon_draft_layer and is_instance_valid(boon_draft_layer):
		boon_draft_layer.queue_free()
	if multiplayer.is_server():
		register_boon_choice(local_peer_id, boon_id, rarity)
	else:
		rpc_id(1, "submit_boon_choice_rpc", local_peer_id, boon_id, rarity)

@rpc("any_peer", "reliable")
func submit_boon_choice_rpc(peer_id: int, boon_id: String, rarity: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != peer_id or not BOONS.BOONS.has(boon_id):
		return
	register_boon_choice(peer_id, boon_id, rarity)

func register_boon_choice(peer_id: int, boon_id: String, rarity: int) -> void:
	if not boon_draft_active or boon_choices_by_peer.has(peer_id):
		return
	boon_choices_by_peer[peer_id] = {"id": boon_id, "rarity": clampi(rarity, 0, 3)}
	check_boon_draft_completion()

@rpc("authority", "call_local", "reliable")
func finish_boon_draft_rpc() -> void:
	boon_draft_active = false
	starting_boon_pending = false
	starting_boon_draft = false
	if boon_draft_layer and is_instance_valid(boon_draft_layer):
		boon_draft_layer.queue_free()
	var local_player := get_local_player()
	if local_player:
		local_player.set("ui_input_locked", false)
	set_single_player_menu_pause("boon_draft", false)

@rpc("authority", "call_local", "reliable")
func sync_wave_state_rpc(new_wave: int, active: bool) -> void:
	wave = new_wave
	wave_active = active
	update_expedition_environment(maxi(1, new_wave))
	update_wave_banner("GUARDIAN" if active and EXPEDITION.is_guardian_floor(new_wave) else "CONTACT" if active else "SECURED")

func spawn_group(scene: PackedScene, count: int) -> void:
	for index in range(count):
		var angle: float = TAU * float(index) / float(maxi(count, 1)) + randf_range(-0.18, 0.18)
		var spawn_position: Vector2 = arena_bounds.get_center() + Vector2.from_angle(angle) * 250.0
		spawn_position.x = clampf(spawn_position.x, arena_bounds.position.x, arena_bounds.end.x)
		spawn_position.y = clampf(spawn_position.y, arena_bounds.position.y, arena_bounds.end.y)
		var enemy_id := "Enemy_%d" % next_enemy_id
		next_enemy_id += 1
		rpc("spawn_enemy", scene.resource_path, spawn_position, enemy_id)

func spawn_boss() -> void:
	var spawn_position := arena_bounds.get_center()
	var enemy_id := "Enemy_%d" % next_enemy_id
	var boss_kind: int = EXPEDITION.BRANCH_COUNT if EXPEDITION.is_final_floor(wave) else EXPEDITION.get_branch_index(wave)
	last_boss_kind = boss_kind
	var bosses_defeated := boss_kind
	next_enemy_id += 1
	rpc("spawn_ascension_boss_rpc", BOSS_PRESENTATION_PATHS[boss_kind], spawn_position, enemy_id, boss_kind, bosses_defeated)

func complete_expedition() -> void:
	if campaign_completed or not multiplayer.is_server():
		return
	campaign_completed = true
	rpc("sync_wave_state_rpc", wave, false)
	rpc("show_expedition_complete_rpc")
	get_tree().create_timer(4.2, false).timeout.connect(func():
		var main := get_tree().get_first_node_in_group("main")
		if main and main.has_method("return_party_to_lobby"):
			main.call("return_party_to_lobby")
	)

@rpc("authority", "call_local", "reliable")
func show_expedition_complete_rpc() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.018, 0.04, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(shade)
	var message := Label.new()
	message.text = "THE LAST NEST IS SILENT\nTHE WORLD HAS BEEN GIVEN BACK"
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	message.add_theme_font_override("font", CAPITAL_BOLD_FONT)
	message.add_theme_font_size_override("font_size", 17)
	message.modulate = Color("fff4c2")
	shade.add_child(message)
	add_child(layer)

@rpc("authority", "call_local", "reliable")
func announce_severed_branch_rpc(branch_name: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	var message := Label.new()
	message.text = "%s\nSEVERED — THE TREE IS RETREATING" % branch_name
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message.position = Vector2(70.0, 104.0)
	message.size = Vector2(340.0, 58.0)
	message.add_theme_font_override("font", CAPITAL_BOLD_FONT)
	message.add_theme_font_size_override("font_size", 12)
	message.modulate = Color("d8f2ff")
	message.modulate.a = 0.0
	layer.add_child(message)
	add_child(layer)
	var tween := message.create_tween()
	tween.tween_property(message, "modulate:a", 1.0, 0.12)
	tween.tween_interval(1.1)
	tween.tween_property(message, "modulate:a", 0.0, 0.42)
	tween.finished.connect(layer.queue_free)

@rpc("authority", "call_local", "reliable")
func spawn_ascension_boss_rpc(presentation_path: String, spawn_position: Vector2, enemy_id: String, boss_kind: int, bosses_defeated: int) -> void:
	create_ascension_boss_instance(presentation_path, spawn_position, enemy_id, boss_kind, bosses_defeated)

func create_ascension_boss_instance(presentation_path: String, spawn_position: Vector2, enemy_id: String, boss_kind: int, bosses_defeated: int) -> void:
	if enemies.get_node_or_null(enemy_id):
		return
	var boss := ASCENSION_BOSS_SCENE.instantiate() as CharacterBody2D
	boss.name = enemy_id
	boss.global_position = spawn_position
	boss.set_meta("arena_bounds", arena_bounds)
	boss.set_meta("presentation_path", presentation_path)
	boss.set_meta("boss_kind", boss_kind)
	boss.set_meta("bosses_defeated", bosses_defeated)
	enemies.add_child(boss)

func get_living_enemy_count() -> int:
	var count := 0
	for child in enemies.get_children():
		if child.is_in_group("enemies"):
			count += 1
	return count

@rpc("authority", "call_local", "reliable")
func spawn_enemy(scene_path: String, spawn_position: Vector2, enemy_id: String) -> void:
	create_enemy_instance(scene_path, spawn_position, enemy_id)

func create_enemy_instance(scene_path: String, spawn_position: Vector2, enemy_id: String) -> void:
	var existing_enemy := enemies.get_node_or_null(enemy_id)
	if existing_enemy:
		existing_enemy.global_position = spawn_position
		return
	var scene := load(scene_path) as PackedScene
	if not scene:
		return
	var enemy := scene.instantiate() as CharacterBody2D
	if not enemy:
		return
	enemy.name = enemy_id
	enemy.global_position = spawn_position
	enemy.set_meta("arena_bounds", arena_bounds)
	enemy.set_meta("expedition_branch", EXPEDITION.get_branch_index(maxi(1, wave)))
	enemies.add_child(enemy)
	decorate_expedition_enemy(enemy, EXPEDITION.get_branch_index(maxi(1, wave)))

func decorate_expedition_enemy(enemy: CharacterBody2D, branch_index: int) -> void:
	var branch: Dictionary = EXPEDITION.BRANCHES[clampi(branch_index, 0, EXPEDITION.BRANCH_COUNT - 1)]
	var branch_color: Color = branch.get("color", Color.WHITE)
	var accent_color: Color = branch.get("accent", Color.WHITE)
	var sprite := enemy.get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.modulate = Color.WHITE.lerp(branch_color, 0.42)
	var crystal := Polygon2D.new()
	crystal.name = "CharacteristicGrowth"
	crystal.polygon = PackedVector2Array([Vector2(0.0, -8.0), Vector2(4.0, -1.0), Vector2(0.0, 4.0), Vector2(-4.0, -1.0)])
	crystal.color = accent_color
	crystal.position = Vector2(0.0, -12.0)
	crystal.z_index = 3
	enemy.add_child(crystal)
	if "max_health" in enemy:
		var scaled_health := roundi(float(enemy.get("max_health")) * (1.0 + float(branch_index) * 0.22))
		enemy.set("max_health", scaled_health)
		enemy.set("current_health", scaled_health)
	if "speed" in enemy and float(enemy.get("speed")) > 0.0:
		var branch_speed_multipliers: Array[float] = [1.0, 0.88, 1.18, 1.06, 1.24]
		var speed_multiplier: float = branch_speed_multipliers[clampi(branch_index, 0, 4)]
		enemy.set("speed", float(enemy.get("speed")) * speed_multiplier)

func build_enemy_states() -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for child in enemies.get_children():
		var enemy := child as CharacterBody2D
		if not enemy or not enemy.is_in_group("enemies"):
			continue
		states.append({
			"id": enemy.name,
			"scene": enemy.scene_file_path,
			"position": enemy.global_position,
			"velocity": enemy.velocity,
			"flip_h": (enemy.get_node_or_null("Sprite2D") as Sprite2D).flip_h if enemy.get_node_or_null("Sprite2D") else false,
			"presentation_path": str(enemy.get_meta("presentation_path", "")),
			"boss_kind": int(enemy.get_meta("boss_kind", 0)),
			"bosses_defeated": int(enemy.get_meta("bosses_defeated", 0)),
		})
	return states

@rpc("authority", "call_remote", "unreliable")
func sync_enemy_states_rpc(states: Array[Dictionary]) -> void:
	var active_ids: Dictionary = {}
	for state in states:
		var enemy_id: String = str(state.get("id", ""))
		if enemy_id.is_empty():
			continue
		active_ids[enemy_id] = true
		var enemy := enemies.get_node_or_null(enemy_id) as CharacterBody2D
		if not enemy:
			var scene_path := str(state.get("scene", ""))
			if scene_path == ASCENSION_BOSS_SCENE.resource_path:
				create_ascension_boss_instance(
					str(state.get("presentation_path", BOSS_PRESENTATION_PATHS[0])),
					state.get("position", Vector2.ZERO),
					enemy_id,
					int(state.get("boss_kind", 0)),
					int(state.get("bosses_defeated", 0))
				)
			else:
				create_enemy_instance(scene_path, state.get("position", Vector2.ZERO), enemy_id)
			enemy = enemies.get_node_or_null(enemy_id) as CharacterBody2D
		if not enemy:
			continue
		var target_position: Vector2 = state.get("position", enemy.global_position)
		var target_velocity: Vector2 = state.get("velocity", Vector2.ZERO)
		if not enemy.has_meta("network_target_position"):
			enemy.global_position = target_position
		enemy.set_meta("network_target_position", target_position)
		enemy.set_meta("network_target_velocity", target_velocity)
		enemy.velocity = target_velocity
		var enemy_sprite := enemy.get_node_or_null("Sprite2D") as Sprite2D
		if enemy_sprite:
			enemy_sprite.flip_h = bool(state.get("flip_h", false))
	for child in enemies.get_children():
		var enemy := child as CharacterBody2D
		if enemy and enemy.is_in_group("enemies") and not active_ids.has(enemy.name):
			enemy.queue_free()

func interpolate_remote_enemies(delta: float) -> void:
	var blend := 1.0 - exp(-16.0 * delta)
	for child in enemies.get_children():
		var enemy := child as CharacterBody2D
		if not enemy or not enemy.has_meta("network_target_position"):
			continue
		var target_position: Vector2 = enemy.get_meta("network_target_position")
		var target_velocity: Vector2 = enemy.get_meta("network_target_velocity", Vector2.ZERO)
		var predicted_position := target_position + target_velocity * 0.055
		enemy.global_position = enemy.global_position.lerp(predicted_position, blend)
		enemy.velocity = target_velocity
