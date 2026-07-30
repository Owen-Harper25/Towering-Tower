extends Area2D

@export var speed: float = 220.0
@export var damage: int = 1
@export var lifetime: float = 2.5
@export var knockback_force: float = 55.0

var shooter_id: int = -1 # Used to prevent hitting the player who shot it

func _ready() -> void:
	# Connect collision signals
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	# Automatically despawn after lifetime seconds
	var timer = get_tree().create_timer(lifetime)
	timer.timeout.connect(queue_free)
	var base_scale := scale
	scale = Vector2.ZERO
	var spawn_tween := create_tween()
	spawn_tween.tween_property(self, "scale", base_scale * 1.4, 0.05)
	spawn_tween.tween_property(self, "scale", base_scale, 0.06)

func _physics_process(delta: float) -> void:
	# Move forward in the direction the bullet is facing/rotated
	var direction = Vector2.RIGHT.rotated(rotation)
	position += direction * speed * delta

# Inside bullet.gd body entered handler
# In bullet.gd
var shooter: Node = null

func _on_body_entered(body: Node2D) -> void:
	# Ignore the enemy that spawned this bullet
	if body == shooter:
		return
		
	if body.has_method("try_receive_enemy_hit") and body.try_receive_enemy_hit(damage):
		queue_free()
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
	if body.has_method("apply_knockback"):
		body.apply_knockback(Vector2.RIGHT.rotated(rotation) * knockback_force)
	
	queue_free()

func _on_area_entered(area: Area2D) -> void:
	# Optional: Destroy bullet if it hits another bullet or hit_box area
	if area.owner and area.owner.name == str(shooter_id):
		return
		
	if area.has_method("take_damage"):
		area.take_damage(damage)
		queue_free()
