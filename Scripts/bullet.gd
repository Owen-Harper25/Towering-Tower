extends Area2D

@export var speed: float = 400.0
@export var damage: int = 1
@export var lifetime: float = 3.0

var shooter_id: int = -1 # Used to prevent hitting the player who shot it

func _ready() -> void:
	# Connect collision signals
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	# Automatically despawn after lifetime seconds
	var timer = get_tree().create_timer(lifetime)
	timer.timeout.connect(queue_free)

func _physics_process(delta: float) -> void:
	# Move forward in the direction the bullet is facing/rotated
	var direction = Vector2.RIGHT.rotated(rotation)
	position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	# Ignore colliding with the player who fired this bullet
	if body.name == str(shooter_id):
		return

	# Handle hitting another CharacterBody2D / Player
	if body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()
		return

	# Hit a tilemap, wall, or solid obstacle
	if body is TileMapLayer or body is TileMap or body is StaticBody2D:
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	# Optional: Destroy bullet if it hits another bullet or hit_box area
	if area.owner and area.owner.name == str(shooter_id):
		return
		
	if area.has_method("take_damage"):
		area.take_damage(damage)
		queue_free()
