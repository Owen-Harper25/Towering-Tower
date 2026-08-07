class_name TreeTraversalMap
extends CanvasLayer

signal transition_finished

@export var transition_duration := 1.35
@export var hold_duration := 0.38
@export var path_width := 3.0

@onready var shade: ColorRect = $Shade
@onready var map_panel: Control = $Shade/MapPanel
@onready var paths_root: Node2D = $Shade/MapPanel/BranchPaths
@onready var title_label: Label = $Shade/MapPanel/Title
@onready var destination_label: Label = $Shade/MapPanel/Destination
@onready var floor_label: Label = $Shade/MapPanel/Floor
@onready var open_sfx: AudioStreamPlayer = $MapOpenSFX
@onready var travel_sfx: AudioStreamPlayer = $TravelSFX
@onready var arrive_sfx: AudioStreamPlayer = $ArriveSFX

var active_tween: Tween
var active_follow: PathFollow2D

func get_total_duration() -> float:
	return transition_duration + hold_duration + 0.65

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	build_visible_paths()
	hide()

func build_visible_paths() -> void:
	for path_node in paths_root.get_children():
		var path := path_node as Path2D
		if not path or not path.curve:
			continue
		var line := Line2D.new()
		line.name = "RouteLine"
		line.width = path_width
		line.default_color = Color(0.24, 0.38, 0.58, 0.42)
		line.antialiased = false
		line.points = path.curve.get_baked_points()
		line.z_index = -1
		path.add_child(line)
		for marker_index in range(1, 11):
			var marker := Polygon2D.new()
			marker.name = "FloorMarker%02d" % marker_index
			marker.polygon = PackedVector2Array([Vector2(0, -2), Vector2(2, 0), Vector2(0, 2), Vector2(-2, 0)])
			marker.position = path.curve.sample_baked(path.curve.get_baked_length() * float(marker_index) / 10.0)
			marker.color = Color(0.35, 0.52, 0.68, 0.72)
			marker.z_index = 1
			path.add_child(marker)

func show_floor_transition(from_floor: int, to_floor: int, branch_index: int, floor_in_branch: int, branch_name: String, room_name: String, guardian_floor: bool) -> void:
	if active_tween and active_tween.is_valid():
		active_tween.kill()
	clear_active_follow()
	var paths := get_editable_paths()
	if paths.is_empty():
		transition_finished.emit()
		return
	var selected_index := clampi(branch_index, 0, paths.size() - 1)
	var selected_path := paths[selected_index]
	selected_path.set_meta("current_floor", floor_in_branch)
	set_path_highlight(selected_path)
	title_label.text = "AGENCY EXPEDITION MAP"
	destination_label.text = branch_name
	floor_label.text = "%s  //  %s" % ["GUARDIAN CONTACT" if guardian_floor else "FLOOR %d" % floor_in_branch, room_name]
	active_follow = PathFollow2D.new()
	active_follow.name = "AgentTraversalMarker"
	active_follow.loop = false
	active_follow.rotates = false
	selected_path.add_child(active_follow)
	var marker := create_agent_marker()
	active_follow.add_child(marker)
	var previous_ratio := clampf(float(maxi(0, floor_in_branch - 1)) / 10.0, 0.0, 1.0)
	var destination_ratio := clampf(float(floor_in_branch) / 10.0, 0.0, 1.0)
	if to_floor >= 51:
		previous_ratio = 0.0
		destination_ratio = 1.0
	active_follow.progress_ratio = previous_ratio
	show()
	open_sfx.play()
	travel_sfx.play()
	shade.modulate.a = 0.0
	map_panel.position.x = -34.0
	active_tween = create_tween()
	active_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	active_tween.set_parallel(true)
	active_tween.tween_property(shade, "modulate:a", 1.0, 0.18)
	active_tween.tween_property(map_panel, "position:x", 0.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	active_tween.tween_property(active_follow, "progress_ratio", destination_ratio, transition_duration).set_delay(0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	active_tween.tween_property(marker, "rotation", TAU, transition_duration).set_delay(0.20)
	active_tween.tween_property(marker, "scale", Vector2(1.35, 1.35), transition_duration * 0.45).set_delay(0.20).set_trans(Tween.TRANS_SINE)
	active_tween.chain().tween_interval(hold_duration)
	active_tween.chain().set_parallel(true)
	active_tween.tween_property(shade, "modulate:a", 0.0, 0.25)
	active_tween.tween_property(map_panel, "position:x", 26.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	active_tween.chain().tween_callback(finish_transition)

func get_editable_paths() -> Array[Path2D]:
	var paths: Array[Path2D] = []
	for child in paths_root.get_children():
		var path := child as Path2D
		if path:
			paths.append(path)
	return paths

func set_path_highlight(selected_path: Path2D) -> void:
	var paths := get_editable_paths()
	var selected_index := paths.find(selected_path)
	for path_index in range(paths.size()):
		var path := paths[path_index]
		var line := path.get_node_or_null("RouteLine") as Line2D
		if line:
			line.default_color = Color(0.52, 0.86, 1.0, 0.95) if path == selected_path else Color(0.38, 0.18, 0.26, 0.42) if path_index < selected_index else Color(0.19, 0.27, 0.42, 0.28)
			line.width = path_width + 1.0 if path == selected_path else path_width
		for child in path.get_children():
			if child is Polygon2D and child.name.begins_with("FloorMarker"):
				var marker_number := int(str(child.name).trim_prefix("FloorMarker"))
				var current_floor := int(path.get_meta("current_floor", 0)) if path == selected_path else 0
				child.color = Color("fff0a8") if path == selected_path and marker_number <= current_floor else Color(0.34, 0.58, 0.76, 0.82) if path == selected_path else Color(0.25, 0.30, 0.42, 0.35)

func create_agent_marker() -> Polygon2D:
	var marker := Polygon2D.new()
	marker.polygon = PackedVector2Array([Vector2(0, -6), Vector2(5, 0), Vector2(0, 6), Vector2(-5, 0)])
	marker.color = Color("fff0a8")
	marker.z_index = 4
	var core := Polygon2D.new()
	core.polygon = PackedVector2Array([Vector2(0, -2), Vector2(2, 0), Vector2(0, 2), Vector2(-2, 0)])
	core.color = Color("273452")
	marker.add_child(core)
	return marker

func finish_transition() -> void:
	arrive_sfx.play()
	hide()
	clear_active_follow()
	transition_finished.emit()

func clear_active_follow() -> void:
	if active_follow and is_instance_valid(active_follow):
		active_follow.queue_free()
	active_follow = null
