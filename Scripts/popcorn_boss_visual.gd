extends Node2D

const IMPACT_TEXTURE := preload("res://Assets/plus particle.png")

@export var boss_kind := 0
@export var boss_name := "BUTTERSTORM"
@export var base_color := Color(1.0, 0.78, 0.18)
@export var accent_color := Color(1.0, 0.95, 0.58)

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	sprite.modulate = base_color

func get_boss_kind() -> int:
	return boss_kind

func get_boss_name() -> String:
	return boss_name

func get_boss_color() -> Color:
	return base_color

func play_fall_entrance(landing_position: Vector2, aggression: float = 1.0) -> void:
	show()
	position = landing_position - Vector2(0.0, 240.0)
	rotation = -0.18
	scale = Vector2.ONE * 0.72
	modulate.a = 0.0
	var fall_duration := maxf(0.42, 0.72 / maxf(1.0, aggression * 0.45))
	var fall_tween := create_tween().set_parallel()
	fall_tween.tween_property(self, "position", landing_position, fall_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall_tween.tween_property(self, "rotation", 0.0, fall_duration)
	fall_tween.tween_property(self, "modulate:a", 1.0, fall_duration * 0.45)
	fall_tween.tween_property(self, "scale", Vector2.ONE, fall_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	fall_tween.finished.connect(func():
		spawn_landing_burst()
		var squash := create_tween()
		squash.tween_property(self, "scale", Vector2(1.22, 0.76), 0.055)
		squash.tween_property(self, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)

func spawn_landing_burst() -> void:
	var parent_node := get_parent()
	if not parent_node:
		return
	var burst := Node2D.new()
	parent_node.add_child(burst)
	burst.global_position = global_position
	for particle_index in range(18):
		var particle := Sprite2D.new()
		particle.texture = IMPACT_TEXTURE
		particle.modulate = base_color.lerp(accent_color, randf())
		particle.scale = Vector2.ONE * randf_range(0.55, 1.15)
		burst.add_child(particle)
		var direction := Vector2.from_angle(TAU * float(particle_index) / 18.0 + randf_range(-0.12, 0.12))
		var particle_tween := burst.create_tween().set_parallel()
		particle_tween.tween_property(particle, "position", direction * randf_range(28.0, 58.0), 0.28)
		particle_tween.tween_property(particle, "scale", Vector2.ZERO, 0.28)
		particle_tween.tween_property(particle, "modulate:a", 0.0, 0.28)
	get_tree().create_timer(0.32).timeout.connect(burst.queue_free)
