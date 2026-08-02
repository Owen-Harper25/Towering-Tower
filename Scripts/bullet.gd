extends Area2D

const IMPACT_TEXTURE := preload("res://Assets/plus particle.png")

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
	var timer = get_tree().create_timer(lifetime, false)
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
	if body.has_method("is_dodging_bullets") and body.is_dodging_bullets():
		return
		
	if body.has_method("try_receive_enemy_hit") and body.try_receive_enemy_hit(damage):
		spawn_impact_particles(Color(1.0, 0.25, 0.2))
		queue_free()
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
		spawn_impact_particles(Color(1.0, 0.38, 0.18))
	if body.has_method("apply_knockback"):
		body.apply_knockback(Vector2.RIGHT.rotated(rotation) * knockback_force)
	
	queue_free()

func _on_area_entered(area: Area2D) -> void:
	# Optional: Destroy bullet if it hits another bullet or hit_box area
	if area.owner and area.owner.name == str(shooter_id):
		return
		
	if area.has_method("take_damage"):
		area.take_damage(damage)
		spawn_impact_particles(Color(1.0, 0.38, 0.18))
		queue_free()

func spawn_impact_particles(color: Color) -> void:
	var parent := get_parent()
	if not parent:
		return
	var burst := Node2D.new()
	burst.global_position = global_position
	parent.add_child(burst)
	for index in range(6):
		var particle := Sprite2D.new()
		particle.texture = IMPACT_TEXTURE
		particle.modulate = color
		particle.scale = Vector2.ONE * randf_range(0.45, 0.85)
		burst.add_child(particle)
		var direction := Vector2.from_angle(randf_range(0.0, TAU))
		var tween := burst.create_tween().set_parallel()
		tween.tween_property(particle, "position", direction * randf_range(8.0, 18.0), 0.15)
		tween.tween_property(particle, "scale", Vector2.ZERO, 0.15)
		tween.tween_property(particle, "modulate:a", 0.0, 0.15)
	get_tree().create_timer(0.17).timeout.connect(burst.queue_free)
