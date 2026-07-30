extends Node2D

const RUSHER_SCENE := preload("res://Scenes/standard_bullet_enemy.tscn")
const SNIPER_SCENE := preload("res://Scenes/sniper_bullet_enemy.tscn")
const TURRET_SCENE := preload("res://Scenes/turret_enemy.tscn")

@export var arena_bounds: Rect2 = Rect2(28, 30, 424, 220)
@export var time_between_waves: float = 2.5

var wave := 0
var wave_active := false
var next_wave_time := 0.0
@onready var enemies: Node2D = $Enemies
var wave_banner: ColorRect
var wave_label: Label

func _ready() -> void:
	add_to_group("tower_arena")
	create_debug_controls()
	create_wave_banner()
	if multiplayer.is_server():
		next_wave_time = time_between_waves

func create_debug_controls() -> void:
	var debug_layer := CanvasLayer.new()
	debug_layer.layer = 10
	var next_wave_button := Button.new()
	next_wave_button.text = "DEBUG: NEXT WAVE"
	next_wave_button.position = Vector2(8, 8)
	next_wave_button.tooltip_text = "Clear the current wave and spawn the next one."
	next_wave_button.pressed.connect(_on_next_wave_button_pressed)
	debug_layer.add_child(next_wave_button)
	add_child(debug_layer)

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

func _on_next_wave_button_pressed() -> void:
	if multiplayer.is_server():
		rpc("advance_wave_debug_rpc")
	else:
		rpc_id(1, "request_next_wave_debug_rpc")

@rpc("any_peer", "reliable")
func request_next_wave_debug_rpc() -> void:
	if multiplayer.is_server():
		rpc("advance_wave_debug_rpc")

@rpc("authority", "call_local", "reliable")
func advance_wave_debug_rpc() -> void:
	for enemy in enemies.get_children():
		enemy.queue_free()
	wave_active = false
	next_wave_time = 0.0
	start_wave()

func is_on_tower(world_position: Vector2, edge_padding: float = 0.0) -> bool:
	var ellipse_center := arena_bounds.get_center()
	var radii := arena_bounds.size * 0.5 - Vector2(edge_padding, edge_padding)
	if radii.x <= 0.0 or radii.y <= 0.0:
		return false
	var normalized_offset := (world_position - ellipse_center) / radii
	return normalized_offset.length_squared() <= 1.0

func is_wave_active() -> bool:
	return wave_active

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if wave_active:
		if enemies.get_child_count() == 0:
			rpc("sync_wave_state_rpc", wave, false)
			next_wave_time = time_between_waves
		return

	next_wave_time -= delta
	if next_wave_time <= 0.0:
		start_wave()

func start_wave() -> void:
	wave += 1
	rpc("sync_wave_state_rpc", wave, true)
	var rusher_count: int = 2 + wave
	var sniper_count: int = 1 + wave / 2
	var turret_count: int = maxi(0, (wave - 2) / 2)

	spawn_group(RUSHER_SCENE, rusher_count)
	spawn_group(SNIPER_SCENE, sniper_count)
	spawn_group(TURRET_SCENE, turret_count)

@rpc("authority", "call_local", "reliable")
func sync_wave_state_rpc(new_wave: int, active: bool) -> void:
	wave = new_wave
	wave_active = active
	update_wave_banner("INCOMING" if active else "CLEAR")

func spawn_group(scene: PackedScene, count: int) -> void:
	for index in range(count):
		var angle: float = TAU * float(index) / float(maxi(count, 1)) + randf_range(-0.18, 0.18)
		var spawn_position: Vector2 = arena_bounds.get_center() + Vector2.from_angle(angle) * 250.0
		spawn_position.x = clampf(spawn_position.x, arena_bounds.position.x, arena_bounds.end.x)
		spawn_position.y = clampf(spawn_position.y, arena_bounds.position.y, arena_bounds.end.y)
		rpc("spawn_enemy", scene.resource_path, spawn_position)

@rpc("authority", "call_local", "reliable")
func spawn_enemy(scene_path: String, spawn_position: Vector2) -> void:
	var scene := load(scene_path) as PackedScene
	if not scene:
		return
	var enemy := scene.instantiate() as CharacterBody2D
	if not enemy:
		return
	enemy.global_position = spawn_position
	enemy.set_meta("arena_bounds", arena_bounds)
	enemies.add_child(enemy)
