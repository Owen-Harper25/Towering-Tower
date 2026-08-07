class_name CharacteristicHud
extends CanvasLayer

@export var fill_tween_duration := 0.28
@export var flash_tween_duration := 0.32
@export var flash_color := Color(1.22, 1.22, 1.22, 1.0)

@onready var panel: Panel = $Panel
@onready var reservoir_label: Label = $Panel/ReservoirLabel
@onready var rank_label: Label = $Panel/RankLabel
@onready var progress_bar: ProgressBar = $Panel/ProgressBar

var active_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func set_values(level_value: int, xp_value: int, threshold: int, animate: bool = true) -> void:
	var safe_threshold := maxi(1, threshold)
	reservoir_label.text = "SOUL RESERVOIR  %d/%d" % [xp_value, safe_threshold]
	rank_label.text = "LV.%02d" % level_value
	progress_bar.max_value = float(safe_threshold)
	if active_tween and active_tween.is_valid():
		active_tween.kill()
	if not animate:
		progress_bar.value = float(xp_value)
		panel.modulate = Color.WHITE
		return
	active_tween = create_tween().set_parallel()
	active_tween.tween_property(progress_bar, "value", float(xp_value), fill_tween_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	panel.modulate = flash_color
	active_tween.tween_property(panel, "modulate", Color.WHITE, flash_tween_duration)
