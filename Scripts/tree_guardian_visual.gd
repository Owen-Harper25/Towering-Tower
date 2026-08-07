class_name TreeGuardianVisual
extends Node2D

const IMPACT_TEXTURE := preload("res://Assets/plus particle.png")

@export var guardian_kind := 0
@export var guardian_name := "THE SAP-BEARER"
@export var base_color := Color("4e8fb8")
@export var accent_color := Color("9fdcff")

var hit_tween: Tween

func _ready() -> void:
	queue_redraw()

func get_boss_name() -> String:
	return guardian_name

func get_boss_color() -> Color:
	return base_color

func play_fall_entrance(landing_position: Vector2, aggression: float = 1.0) -> void:
	position = landing_position - Vector2(0.0, 240.0)
	rotation = -0.22
	scale = Vector2.ONE * 0.62
	modulate.a = 0.0
	var duration := maxf(0.44, 0.76 / maxf(1.0, aggression * 0.45))
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "position", landing_position, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "rotation", 0.0, duration)
	tween.tween_property(self, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, duration * 0.45)

func play_hit_squash() -> void:
	if hit_tween and hit_tween.is_valid():
		hit_tween.kill()
	hit_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hit_tween.tween_property(self, "scale", Vector2(0.70, 1.34), 0.045)
	hit_tween.tween_property(self, "scale", Vector2(1.08, 0.94), 0.075)
	hit_tween.tween_property(self, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK)

func _draw() -> void:
	match guardian_kind:
		0: draw_sap_bearer()
		1: draw_marrow_stag()
		2: draw_teeth_choir()
		3: draw_prism_widow()
		4: draw_hollow_apostle()
		_: draw_nest_seraph()

func draw_sap_bearer() -> void:
	draw_polygon(PackedVector2Array([Vector2(-18, 15), Vector2(-13, -13), Vector2(-4, -21), Vector2(10, -17), Vector2(19, 3), Vector2(13, 19)]), PackedColorArray([base_color]))
	draw_circle(Vector2(-7, -4), 3.0, accent_color)
	draw_circle(Vector2(7, -5), 3.0, accent_color)
	draw_line(Vector2(-14, 8), Vector2(-25, 18), base_color.lightened(0.18), 5.0)
	draw_line(Vector2(13, 8), Vector2(25, 18), base_color.lightened(0.18), 5.0)

func draw_marrow_stag() -> void:
	draw_polygon(PackedVector2Array([Vector2(-15, 17), Vector2(-13, -10), Vector2(-6, -18), Vector2(7, -18), Vector2(15, -7), Vector2(13, 17)]), PackedColorArray([base_color]))
	draw_line(Vector2(-8, -15), Vector2(-18, -29), accent_color, 4.0)
	draw_line(Vector2(-17, -28), Vector2(-25, -23), accent_color, 3.0)
	draw_line(Vector2(7, -15), Vector2(18, -29), accent_color, 4.0)
	draw_line(Vector2(17, -28), Vector2(25, -23), accent_color, 3.0)
	draw_circle(Vector2.ZERO, 4.0, Color("202039"))

func draw_teeth_choir() -> void:
	draw_circle(Vector2.ZERO, 21.0, base_color)
	draw_circle(Vector2.ZERO, 13.0, Color("281226"))
	for tooth_index in range(10):
		var angle := TAU * float(tooth_index) / 10.0
		var tooth := Vector2.from_angle(angle) * 15.0
		draw_circle(tooth, 2.8, accent_color)
	draw_circle(Vector2.ZERO, 3.0, accent_color)

func draw_prism_widow() -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(0, -24), Vector2(18, -3), Vector2(10, 21), Vector2(-10, 21), Vector2(-18, -3)]), base_color)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -14), Vector2(9, 0), Vector2(0, 15), Vector2(-9, 0)]), accent_color)
	for side in [-1.0, 1.0]:
		for leg_index in range(3):
			var y := -6.0 + float(leg_index) * 8.0
			draw_line(Vector2(side * 12.0, y), Vector2(side * (27.0 - float(leg_index) * 2.0), y + 7.0), base_color.lightened(0.2), 3.0)

func draw_hollow_apostle() -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(0, -27), Vector2(18, -5), Vector2(14, 22), Vector2(-14, 22), Vector2(-18, -5)]), base_color)
	draw_circle(Vector2(0, -5), 8.0, Color("090812"))
	draw_circle(Vector2(0, -5), 2.5, accent_color)
	draw_line(Vector2(-13, 15), Vector2(-25, 25), base_color, 5.0)
	draw_line(Vector2(13, 15), Vector2(25, 25), base_color, 5.0)

func draw_nest_seraph() -> void:
	for wing_index in range(6):
		var angle := TAU * float(wing_index) / 6.0
		var direction := Vector2.from_angle(angle)
		var side := direction.rotated(PI * 0.5)
		draw_colored_polygon(PackedVector2Array([side * 4.0, direction * 31.0, direction * 22.0 - side * 7.0]), base_color.lightened(float(wing_index % 2) * 0.12))
	draw_circle(Vector2.ZERO, 15.0, accent_color)
	draw_circle(Vector2.ZERO, 9.0, Color("171328"))
	draw_circle(Vector2.ZERO, 3.0, Color("e5b94f"))
	for eye_index in range(8):
		var eye_angle := TAU * float(eye_index) / 8.0
		draw_circle(Vector2.from_angle(eye_angle) * 11.5, 1.7, Color.WHITE)
