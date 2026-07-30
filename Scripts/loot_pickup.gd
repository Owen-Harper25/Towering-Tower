extends Area2D

enum LootType { COIN, HEALTH }

@export var loot_type: LootType = LootType.COIN
@export var value := 1
@onready var sprite: Sprite2D = $Sprite2D
@onready var pickup_sfx: AudioStreamPlayer2D = $PickupSFX
var collected := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	apply_visuals()
	var bob_tween := create_tween().set_loops()
	bob_tween.tween_property(sprite, "position:y", -3.0, 0.35).set_trans(Tween.TRANS_SINE)
	bob_tween.tween_property(sprite, "position:y", 3.0, 0.35).set_trans(Tween.TRANS_SINE)
	var spawn_tween := create_tween()
	scale = Vector2.ZERO
	spawn_tween.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func configure(type: LootType) -> void:
	loot_type = type
	if is_node_ready():
		apply_visuals()

func apply_visuals() -> void:
	if loot_type == LootType.COIN:
		sprite.modulate = Color(1.0, 0.82, 0.18)
	else:
		sprite.modulate = Color(0.3, 1.0, 0.45)

func _on_body_entered(body: Node2D) -> void:
	if collected or not body.is_in_group("players"):
		return
	collected = true
	if loot_type == LootType.COIN:
		body.call("collect_coins", value)
	else:
		body.call("heal", value)
	set_deferred("monitoring", false)
	hide()
	pickup_sfx.play()
	await pickup_sfx.finished
	queue_free()
