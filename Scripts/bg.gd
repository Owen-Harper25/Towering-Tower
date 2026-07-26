extends ColorRect

func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	var t = Time.get_ticks_msec() / 1000.0
	material.set_shader_parameter("time_val", t)
	material.set_shader_parameter("spin_time", t)
