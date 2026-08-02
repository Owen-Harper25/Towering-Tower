extends Node2D

const RUSHER_SCENE := preload("res://Scenes/standard_bullet_enemy.tscn")
const SNIPER_SCENE := preload("res://Scenes/sniper_bullet_enemy.tscn")
const TURRET_SCENE := preload("res://Scenes/turret_enemy.tscn")
const ASCENSION_BOSS_SCENE := preload("res://Scenes/ascension_popcorn_boss.tscn")
const BOONS := preload("res://Scripts/boon_catalog.gd")
const BOSS_PRESENTATION_PATHS: Array[String] = [
	"res://Scenes/popcorn_boss_butterstorm.tscn",
	"res://Scenes/popcorn_boss_flame.tscn",
	"res://Scenes/popcorn_boss_magnetron.tscn",
	"res://Scenes/popcorn_boss_helix.tscn",
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
@onready var enemies: Node2D = $Enemies
var wave_banner: ColorRect
var wave_label: Label
var boon_draft_active := false
var boon_choices_by_peer: Dictionary = {}
var boon_draft_layer: CanvasLayer

func _ready() -> void:
	add_to_group("tower_arena")
	create_wave_banner()
	if multiplayer.is_server():
		next_wave_time = time_between_waves

func create_wave_banner() -> void:
	var banner_layer := CanvasLayer.new()
	banner_layer.layer = 11
	wave_banner = ColorRect.new()
	wave_banner.color = Color(0.04, 0.08, 0.16, 0.92)
	wave_banner.size = Vector2(176, 34)
	wave_banner.position = Vector2(get_viewport_rect().size.x - 184.0, -42.0)
	wave_label = Label.new()
	wave_label.position = Vector2(8, 7)
	wave_label.size = Vector2(160, 22)
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_banner.add_child(wave_label)
	banner_layer.add_child(wave_banner)
	add_child(banner_layer)
	update_wave_banner("PREPARE")

func update_wave_banner(status: String) -> void:
	if not wave_banner or not wave_label:
		return
	wave_label.text = "WAVE %d  %s" % [wave, status]
	var target_position := Vector2(get_viewport_rect().size.x - 184.0, 8.0)
	wave_banner.position = Vector2(target_position.x, -42.0)
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(wave_banner, "position", target_position, 0.35)

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
	if not multiplayer.is_server():
		interpolate_remote_enemies(delta)
		return
	enemy_state_sync_elapsed += delta
	if enemy_state_sync_elapsed >= 0.08:
		enemy_state_sync_elapsed = 0.0
		rpc("sync_enemy_states_rpc", build_enemy_states())

	if wave_active:
		if get_living_enemy_count() == 0:
			if wave % 5 == 0:
				begin_boon_draft()
				return
			rpc("sync_wave_state_rpc", wave, false)
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
	wave += 1
	rpc("sync_wave_state_rpc", wave, true)
	if wave % 5 == 0:
		spawn_boss()
		return
	var rusher_count: int = 2 + wave
	var sniper_count: int = 1 + floori(float(wave) * 0.5)
	var turret_count: int = maxi(0, floori(float(wave - 2) * 0.5))

	spawn_group(RUSHER_SCENE, rusher_count)
	spawn_group(SNIPER_SCENE, sniper_count)
	spawn_group(TURRET_SCENE, turret_count)

func begin_boon_draft() -> void:
	if not multiplayer.is_server() or boon_draft_active:
		return
	boon_draft_active = true
	boon_choices_by_peer.clear()
	rpc("sync_wave_state_rpc", wave, false)
	var boon_ids := BOONS.get_ids()
	boon_ids.shuffle()
	var options: Array[Dictionary] = []
	for option_index in range(mini(3, boon_ids.size())):
		options.append({"id": boon_ids[option_index], "rarity": BOONS.roll_rarity()})
	rpc("show_boon_draft_rpc", options)

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
	next_wave_time = time_between_waves
	rpc("finish_boon_draft_rpc")

@rpc("authority", "call_local", "reliable")
func show_boon_draft_rpc(options: Array[Dictionary]) -> void:
	boon_draft_active = true
	create_boon_draft_ui(options)

func create_boon_draft_ui(options: Array[Dictionary]) -> void:
	if boon_draft_layer and is_instance_valid(boon_draft_layer):
		boon_draft_layer.queue_free()
	boon_draft_layer = CanvasLayer.new()
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
	title.text = "CHOOSE AN ASCENSION BOON"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	layout.add_child(title)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 10)
	layout.add_child(cards)
	for option_index in range(options.size()):
		var option := options[option_index]
		create_boon_tarot_card(cards, str(option.get("id", "")), int(option.get("rarity", 0)), option_index)
	var hint := Label.new()
	hint.text = "THE NEXT FLOOR WAITS FOR EVERY PLAYER"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 9)
	layout.add_child(hint)
	add_child(boon_draft_layer)

func create_boon_tarot_card(parent: HBoxContainer, boon_id: String, rarity: int, display_index: int) -> void:
	var rarity_color := BOONS.get_rarity_color(rarity)
	var paper_color := Color(0.93, 0.88, 0.72).lerp(rarity_color, 0.10)
	var ink_color := Color(0.12, 0.055, 0.16)
	var card := Button.new()
	card.custom_minimum_size = Vector2(172.0, 192.0)
	card.focus_mode = Control.FOCUS_ALL
	card.add_theme_stylebox_override("normal", create_boon_card_style(rarity_color.darkened(0.10), paper_color, 4))
	card.add_theme_stylebox_override("hover", create_boon_card_style(rarity_color.lightened(0.18), paper_color.lightened(0.08), 6))
	card.add_theme_stylebox_override("focus", create_boon_card_style(Color.WHITE, paper_color.lightened(0.08), 6))
	card.add_theme_stylebox_override("pressed", create_boon_card_style(rarity_color, paper_color.darkened(0.08), 7))
	var card_tilts := [-2.4, 1.3, -1.6]
	var base_rotation := deg_to_rad(float(card_tilts[display_index % card_tilts.size()]))
	card.rotation = base_rotation
	card.set_meta("base_rotation", base_rotation)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 9.0
	content.offset_top = 7.0
	content.offset_right = -9.0
	content.offset_bottom = -7.0
	content.add_theme_constant_override("separation", 3)
	card.add_child(content)
	var rarity_label := Label.new()
	rarity_label.text = BOONS.get_rarity_name(rarity)
	rarity_label.modulate = rarity_color
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_label.add_theme_font_size_override("font_size", 9)
	rarity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(rarity_label)
	var icon := TextureRect.new()
	icon.texture = create_boon_pixel_icon(BOONS.get_sigil(boon_id), rarity_color)
	icon.custom_minimum_size = Vector2(0.0, 58.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon)
	var name_label := Label.new()
	name_label.text = BOONS.get_display_name(boon_id)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", ink_color)
	name_label.add_theme_color_override("font_outline_color", paper_color.darkened(0.12))
	name_label.add_theme_constant_override("outline_size", 1)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(name_label)
	var divider := HSeparator.new()
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(divider)
	var description := Label.new()
	description.text = BOONS.get_description(boon_id, rarity)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description.add_theme_font_size_override("font_size", 9)
	description.add_theme_color_override("font_color", ink_color.lightened(0.08))
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(description)
	var choose := Label.new()
	choose.text = "[ CHOOSE ]"
	choose.modulate = rarity_color
	choose.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	choose.add_theme_font_size_override("font_size", 9)
	choose.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(choose)
	card.pressed.connect(func(): select_local_boon(boon_id, rarity))
	card.mouse_entered.connect(func(): animate_boon_card(card, true))
	card.mouse_exited.connect(func(): animate_boon_card(card, false))
	card.focus_entered.connect(func(): animate_boon_card(card, true))
	card.focus_exited.connect(func(): animate_boon_card(card, false))
	parent.add_child(card)
	card.call_deferred("set_pivot_offset", card.custom_minimum_size * 0.5)

func animate_boon_card(card: Button, raised: bool) -> void:
	if not is_instance_valid(card):
		return
	var previous_tween: Variant = card.get_meta("hover_tween", null)
	if previous_tween is Tween and previous_tween.is_valid():
		previous_tween.kill()
	card.z_index = 8 if raised else 0
	var target_rotation := 0.0 if raised else float(card.get_meta("base_rotation", 0.0))
	var target_scale := Vector2.ONE * 1.065 if raised else Vector2.ONE
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation", target_rotation, 0.13)
	tween.tween_property(card, "scale", target_scale, 0.13)
	card.set_meta("hover_tween", tween)

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
	var local_peer_id := multiplayer.get_unique_id()
	for player_node in get_tree().get_nodes_in_group("players"):
		var player := player_node as CharacterBody2D
		if player and player.is_multiplayer_authority() and player.has_method("apply_ascension_boon"):
			player.call("apply_ascension_boon", boon_id, rarity)
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
	if boon_draft_layer and is_instance_valid(boon_draft_layer):
		boon_draft_layer.queue_free()

@rpc("authority", "call_local", "reliable")
func sync_wave_state_rpc(new_wave: int, active: bool) -> void:
	wave = new_wave
	wave_active = active
	update_wave_banner("BOSS" if active and new_wave % 5 == 0 else "INCOMING" if active else "CLEAR")

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
	var boss_kind := randi_range(0, BOSS_PRESENTATION_PATHS.size() - 1)
	if BOSS_PRESENTATION_PATHS.size() > 1 and boss_kind == last_boss_kind:
		boss_kind = (boss_kind + randi_range(1, BOSS_PRESENTATION_PATHS.size() - 1)) % BOSS_PRESENTATION_PATHS.size()
	last_boss_kind = boss_kind
	var bosses_defeated := maxi(0, floori(float(wave) / 5.0) - 1)
	next_enemy_id += 1
	rpc("spawn_ascension_boss_rpc", BOSS_PRESENTATION_PATHS[boss_kind], spawn_position, enemy_id, boss_kind, bosses_defeated)

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
	enemies.add_child(enemy)

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
