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

func _ready() -> void:
	if multiplayer.is_server():
		next_wave_time = time_between_waves

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if wave_active:
		if enemies.get_child_count() == 0:
			wave_active = false
			next_wave_time = time_between_waves
		return

	next_wave_time -= delta
	if next_wave_time <= 0.0:
		start_wave()

func start_wave() -> void:
	wave += 1
	wave_active = true
	var rusher_count: int = 2 + wave
	var sniper_count: int = 1 + wave / 2
	var turret_count: int = maxi(0, (wave - 2) / 2)

	spawn_group(RUSHER_SCENE, rusher_count)
	spawn_group(SNIPER_SCENE, sniper_count)
	spawn_group(TURRET_SCENE, turret_count)

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
