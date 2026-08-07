extends Area2D

enum LootType { COIN, HEALTH, CHARACTERISTIC }

@export var loot_type: LootType = LootType.COIN
@export var value := 1
@onready var sprite: Sprite2D = $Sprite2D
@onready var pickup_sfx: AudioStreamPlayer2D = $PickupSFX
var collected := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	set_deferred("monitoring", multiplayer.is_server())
	apply_visuals()
	var bob_tween := create_tween().set_loops()
	bob_tween.tween_property(sprite, "position:y", -3.0, 0.35).set_trans(Tween.TRANS_SINE)
	bob_tween.tween_property(sprite, "position:y", 3.0, 0.35).set_trans(Tween.TRANS_SINE)
	var spawn_tween := create_tween()
	scale = Vector2.ZERO
	spawn_tween.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func configure(type: int) -> void:
	loot_type = type as LootType
	if is_node_ready():
		apply_visuals()

func apply_visuals() -> void:
	match loot_type:
		LootType.COIN: sprite.modulate = Color(1.0, 0.82, 0.18)
		LootType.HEALTH: sprite.modulate = Color(0.3, 1.0, 0.45)
		LootType.CHARACTERISTIC:
			sprite.modulate = Color(0.40, 0.82, 1.0)
			sprite.scale = Vector2.ONE * 2.1

func _on_body_entered(body: Node2D) -> void:
	if collected or not multiplayer.is_server() or not body.is_in_group("players"):
		return
	collected = true
	var peer_id := body.get_multiplayer_authority()
	rpc("collect_loot_rpc", peer_id)

@rpc("authority", "call_local", "reliable")
func collect_loot_rpc(peer_id: int) -> void:
	if not collected:
		collected = true
	var body := find_player(peer_id)
	if body:
		match loot_type:
			LootType.COIN: body.call("collect_coins", value)
			LootType.HEALTH: body.call("heal", value)
			LootType.CHARACTERISTIC:
				if multiplayer.is_server():
					var arena := get_tree().get_first_node_in_group("tower_arena")
					if arena and arena.has_method("collect_characteristic"):
						arena.call("collect_characteristic", value)
	set_deferred("monitoring", false)
	hide()
	pickup_sfx.play()
	await pickup_sfx.finished
	queue_free()

func find_player(peer_id: int) -> CharacterBody2D:
	for player_node in get_tree().get_nodes_in_group("players"):
		var player := player_node as CharacterBody2D
		if player and player.get_multiplayer_authority() == peer_id:
			return player
	return null
