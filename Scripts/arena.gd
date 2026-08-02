extends Node2D

const RUSHER_SCENE := preload("res://Scenes/standard_bullet_enemy.tscn")
const SNIPER_SCENE := preload("res://Scenes/sniper_bullet_enemy.tscn")
const TURRET_SCENE := preload("res://Scenes/turret_enemy.tscn")
const ASCENSION_BOSS_SCENE := preload("res://Scenes/ascension_popcorn_boss.tscn")
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
			rpc("sync_wave_state_rpc", wave, false)
			next_wave_time = time_between_waves
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
