class_name PushUpMazePractice
extends Node3D

signal practice_state_changed(state: Dictionary)

const COURSE_SECONDS := 60.0
const MAZE_ORIGIN := Vector3(0.0, 0.0, -40.0)
const MAZE_START_LOCAL := Vector3(-7.0, 0.76, 7.0)
const MAZE_FINISH_LOCAL := Vector3(-7.0, 0.76, -8.1)
const GYM_ENTRY_POSITION := Vector3(-6.2, 0.10, -4.8)
const GYM_RETURN_POSITION := Vector3(-4.1, 0.76, -4.6)
const REQUIRED_CHECKPOINTS := 4

var state: Dictionary = {
	"mazeReady": false,
	"status": "IDLE",
	"controlMode": "THUMB_TEST",
	"bodyTracking": "PENDING",
	"timeRemaining": COURSE_SECONDS,
	"checkpoint": 0,
	"checkpointTotal": REQUIRED_CHECKPOINTS,
	"pushups": 0,
	"wallCount": 0,
	"lastEvent": "NONE",
	"result": "NONE",
	"firstFailure": "NONE"
}

var _player: GymPlayerController
var _maze_root: Node3D
var _entry_area: Area3D
var _finish_area: Area3D
var _hud_layer: CanvasLayer
var _hud_label: Label
var _visited_checkpoints: Dictionary = {}
var _return_delay := -1.0

func _ready() -> void:
	name = "PushUpMazePractice"
	_player = _resolve_player()
	_build_entry_gate()
	_build_maze()
	_build_hud()
	_validate_structure()
	set_process(true)
	_publish()

func _process(delta: float) -> void:
	if str(state.get("status", "IDLE")) == "ACTIVE":
		state["timeRemaining"] = maxf(0.0, float(state.get("timeRemaining", COURSE_SECONDS)) - delta)
		if _player == null or not is_instance_valid(_player):
			_set_first_failure("MAZE_PLAYER_BIND", "PLAYER_MISSING_DURING_RUN")
			_finish_run(false, "PLAYER_MISSING")
		elif _player.global_position.y < -4.0:
			_set_first_failure("MAZE_PLAYER_FELL", "PLAYER_BELOW_COURSE")
			_finish_run(false, "FELL")
		elif float(state["timeRemaining"]) <= 0.0:
			_finish_run(false, "TIME_UP")
		_update_hud()
	elif _return_delay >= 0.0:
		_return_delay -= delta
		if _return_delay <= 0.0:
			_return_to_gym()

func diagnostic_snapshot() -> Dictionary:
	return state.duplicate(true)

func start_practice_for_test() -> bool:
	return _start_run()

func trigger_checkpoint_for_test(checkpoint_id: int) -> bool:
	return _record_checkpoint(checkpoint_id)

func finish_practice_for_test() -> bool:
	if int(state.get("checkpoint", 0)) < REQUIRED_CHECKPOINTS:
		return false
	_finish_run(true, "COMPLETE")
	return true

func register_pushup_rep_for_future_body_control() -> void:
	# Intentionally not connected to TensorFlow yet. This is only the future game hook.
	state["pushups"] = int(state.get("pushups", 0)) + 1
	state["lastEvent"] = "PUSHUP_REP_HOOK"
	_publish()

func _resolve_player() -> GymPlayerController:
	var current_scene := get_tree().current_scene
	if current_scene != null:
		var current_player := current_scene.get_node_or_null("player") as GymPlayerController
		if current_player != null:
			return current_player
	return get_tree().root.find_child("player", true, false) as GymPlayerController

func _build_entry_gate() -> void:
	var gate := Node3D.new()
	gate.name = "PushUpMazePracticeGate"
	add_child(gate)
	gate.position = GYM_ENTRY_POSITION

	var pad_material := _material(Color(0.05, 0.09, 0.12), Color(0.0, 0.72, 1.0), 2.5)
	var pad := MeshInstance3D.new()
	pad.name = "PracticeGatePad"
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 1.25
	pad_mesh.bottom_radius = 1.25
	pad_mesh.height = 0.08
	pad_mesh.material = pad_material
	pad.mesh = pad_mesh
	gate.add_child(pad)

	var sign := Label3D.new()
	sign.name = "PracticeMazeSign"
	sign.text = "PUSH-UP PRACTICE\nMAZE"
	sign.position = Vector3(0.0, 2.0, 0.0)
	sign.font_size = 72
	sign.outline_size = 10
	sign.modulate = Color.WHITE
	sign.outline_modulate = Color(0.01, 0.02, 0.03)
	sign.pixel_size = 0.0045
	gate.add_child(sign)

	_entry_area = Area3D.new()
	_entry_area.name = "PracticeMazeEntryArea"
	var entry_collision := CollisionShape3D.new()
	var entry_shape := CylinderShape3D.new()
	entry_shape.radius = 1.15
	entry_shape.height = 1.8
	entry_collision.shape = entry_shape
	entry_collision.position.y = 0.9
	_entry_area.add_child(entry_collision)
	gate.add_child(_entry_area)
	_entry_area.body_entered.connect(_on_entry_body_entered)

func _build_maze() -> void:
	_maze_root = Node3D.new()
	_maze_root.name = "PushUpMazeCourse"
	_maze_root.position = MAZE_ORIGIN
	add_child(_maze_root)

	var floor_material := _material(Color(0.025, 0.03, 0.04), Color(0.0, 0.0, 0.0), 0.0)
	var wall_material := _material(Color(0.08, 0.10, 0.13), Color(0.0, 0.55, 0.95), 0.45)
	var accent_material := _material(Color(0.12, 0.025, 0.025), Color(0.95, 0.05, 0.05), 1.7)

	_static_box("MazeFloor", Vector3(19.0, 0.24, 19.0), Vector3(0.0, -0.12, 0.0), floor_material, _maze_root, false)

	# Outer boundary.
	_wall("OuterNorth", Vector3(19.0, 2.8, 0.35), Vector3(0.0, 1.4, 9.0), wall_material)
	_wall("OuterSouth", Vector3(19.0, 2.8, 0.35), Vector3(0.0, 1.4, -9.0), wall_material)
	_wall("OuterWest", Vector3(0.35, 2.8, 18.0), Vector3(-9.0, 1.4, 0.0), wall_material)
	_wall("OuterEast", Vector3(0.35, 2.8, 18.0), Vector3(9.0, 1.4, 0.0), wall_material)

	# Four alternating walls form a deterministic snake maze. Later, body tracking only needs LEFT/RIGHT decisions.
	_wall("LaneWall1", Vector3(14.0, 2.4, 0.35), Vector3(-2.0, 1.2, 5.0), wall_material)
	_wall("LaneWall2", Vector3(14.0, 2.4, 0.35), Vector3(2.0, 1.2, 1.0), wall_material)
	_wall("LaneWall3", Vector3(14.0, 2.4, 0.35), Vector3(-2.0, 1.2, -3.0), wall_material)
	_wall("LaneWall4", Vector3(14.0, 2.4, 0.35), Vector3(2.0, 1.2, -7.0), wall_material)

	_add_floor_marker("START", MAZE_START_LOCAL + Vector3(0.0, -0.72, 0.0), Color(0.0, 0.65, 1.0))
	_add_floor_marker("FINISH", MAZE_FINISH_LOCAL + Vector3(0.0, -0.72, 0.0), Color(1.0, 0.10, 0.08))

	_add_checkpoint(1, Vector3(7.0, 0.9, 4.0))
	_add_checkpoint(2, Vector3(-7.0, 0.9, 0.0))
	_add_checkpoint(3, Vector3(7.0, 0.9, -4.0))
	_add_checkpoint(4, Vector3(-7.0, 0.9, -7.7))
	_add_finish_area()

	var course_label := Label3D.new()
	course_label.name = "MazeTitle"
	course_label.text = "60 SECOND PUSH-UP MAZE\nTHUMB CONTROL TEST"
	course_label.position = Vector3(0.0, 4.1, 8.4)
	course_label.font_size = 68
	course_label.outline_size = 10
	course_label.modulate = Color.WHITE
	course_label.pixel_size = 0.004
	_maze_root.add_child(course_label)

	for light_position in [Vector3(-6.0, 5.5, 5.0), Vector3(6.0, 5.5, 1.0), Vector3(-6.0, 5.5, -4.5)]:
		var light := OmniLight3D.new()
		light.position = light_position
		light.light_color = Color(0.72, 0.86, 1.0)
		light.light_energy = 1.4
		light.omni_range = 13.0
		_maze_root.add_child(light)

	var finish_beacon := MeshInstance3D.new()
	finish_beacon.name = "FinishBeacon"
	var beacon_mesh := BoxMesh.new()
	beacon_mesh.size = Vector3(2.8, 0.10, 1.3)
	beacon_mesh.material = accent_material
	finish_beacon.mesh = beacon_mesh
	finish_beacon.position = MAZE_FINISH_LOCAL + Vector3(0.0, -0.68, 0.0)
	_maze_root.add_child(finish_beacon)

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "PushUpMazeHUD"
	_hud_layer.layer = 40
	add_child(_hud_layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.custom_minimum_size = Vector2(330, 112)
	_hud_layer.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.01, 0.018, 0.028, 0.88)
	style.border_color = Color(0.0, 0.65, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	_hud_label = Label.new()
	_hud_label.add_theme_font_size_override("font_size", 17)
	_hud_label.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(_hud_label)
	_hud_layer.visible = false
	_update_hud()

func _material(albedo: Color, emission: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = 0.68
	if emission != Color.BLACK and emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	return material

func _static_box(node_name: String, size: Vector3, pos: Vector3, material: Material, parent: Node3D, count_as_wall: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	parent.add_child(body)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	if count_as_wall:
		state["wallCount"] = int(state.get("wallCount", 0)) + 1
	return body

func _wall(node_name: String, size: Vector3, pos: Vector3, material: Material) -> void:
	_static_box(node_name, size, pos, material, _maze_root, true)

func _add_floor_marker(text_value: String, local_position: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text_value
	label.position = local_position + Vector3(0.0, 0.05, 0.0)
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	label.font_size = 84
	label.modulate = color
	label.pixel_size = 0.004
	_maze_root.add_child(label)

func _add_checkpoint(checkpoint_id: int, local_position: Vector3) -> void:
	var area := Area3D.new()
	area.name = "Checkpoint%d" % checkpoint_id
	area.position = local_position
	area.set_meta("checkpoint_id", checkpoint_id)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.3, 1.8, 1.1)
	collision.shape = shape
	area.add_child(collision)
	_maze_root.add_child(area)
	area.body_entered.connect(_on_checkpoint_body_entered.bind(checkpoint_id))

func _add_finish_area() -> void:
	_finish_area = Area3D.new()
	_finish_area.name = "PracticeMazeFinishArea"
	_finish_area.position = MAZE_FINISH_LOCAL
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 1.8, 1.5)
	collision.shape = shape
	_finish_area.add_child(collision)
	_maze_root.add_child(_finish_area)
	_finish_area.body_entered.connect(_on_finish_body_entered)

func _validate_structure() -> void:
	if _player == null:
		_set_first_failure("MAZE_PLAYER_BIND", "PLAYER_NOT_FOUND")
	elif _maze_root == null:
		_set_first_failure("MAZE_BUILD", "MAZE_ROOT_MISSING")
	elif int(state.get("wallCount", 0)) < 8:
		_set_first_failure("MAZE_BUILD", "WALL_COUNT_INVALID")
	elif _entry_area == null:
		_set_first_failure("MAZE_ENTRY", "ENTRY_TRIGGER_MISSING")
	elif _finish_area == null:
		_set_first_failure("MAZE_FINISH", "FINISH_TRIGGER_MISSING")
	else:
		state["mazeReady"] = true

func _on_entry_body_entered(body: Node) -> void:
	if body == _player and str(state.get("status", "IDLE")) == "IDLE":
		_start_run()

func _start_run() -> bool:
	if not bool(state.get("mazeReady", false)) or _player == null or not is_instance_valid(_player):
		_set_first_failure("MAZE_START", "STRUCTURE_NOT_READY")
		return false
	_visited_checkpoints.clear()
	state["status"] = "ACTIVE"
	state["timeRemaining"] = COURSE_SECONDS
	state["checkpoint"] = 0
	state["pushups"] = 0
	state["result"] = "NONE"
	state["lastEvent"] = "RUN_STARTED"
	_return_delay = -1.0
	_player.stop_navigation()
	_player.global_position = _maze_root.global_position + MAZE_START_LOCAL
	_player.global_rotation = Vector3.ZERO
	_hud_layer.visible = true
	_update_hud()
	_publish()
	return true

func _on_checkpoint_body_entered(body: Node, checkpoint_id: int) -> void:
	if body == _player:
		_record_checkpoint(checkpoint_id)

func _record_checkpoint(checkpoint_id: int) -> bool:
	if str(state.get("status", "IDLE")) != "ACTIVE":
		return false
	var expected := int(state.get("checkpoint", 0)) + 1
	if checkpoint_id != expected or _visited_checkpoints.has(checkpoint_id):
		return false
	_visited_checkpoints[checkpoint_id] = true
	state["checkpoint"] = checkpoint_id
	state["lastEvent"] = "CHECKPOINT_%d" % checkpoint_id
	_update_hud()
	_publish()
	return true

func _on_finish_body_entered(body: Node) -> void:
	if body != _player or str(state.get("status", "IDLE")) != "ACTIVE":
		return
	if int(state.get("checkpoint", 0)) < REQUIRED_CHECKPOINTS:
		state["lastEvent"] = "FINISH_LOCKED_CHECKPOINTS"
		_publish()
		return
	_finish_run(true, "COMPLETE")

func _finish_run(completed: bool, reason: String) -> void:
	if str(state.get("status", "IDLE")) != "ACTIVE":
		return
	state["status"] = "FINISHED" if completed else "FAILED"
	state["result"] = reason
	state["lastEvent"] = "RUN_%s" % reason
	_player.stop_navigation() if _player != null and is_instance_valid(_player) else null
	_return_delay = 3.0
	_update_hud()
	_publish()

func _return_to_gym() -> void:
	_return_delay = -1.0
	if _player != null and is_instance_valid(_player):
		_player.global_position = GYM_RETURN_POSITION
		_player.global_rotation = Vector3.ZERO
	state["status"] = "IDLE"
	state["lastEvent"] = "RETURNED_TO_GYM"
	_hud_layer.visible = false
	_publish()

func _update_hud() -> void:
	if _hud_label == null:
		return
	_hud_label.text = "PUSH-UP MAZE — THUMB TEST\nTIME: %05.1f   CHECKPOINT: %d/%d\nSTATUS: %s   BODY CONTROL: LATER" % [
		float(state.get("timeRemaining", COURSE_SECONDS)),
		int(state.get("checkpoint", 0)),
		REQUIRED_CHECKPOINTS,
		str(state.get("status", "IDLE"))
	]

func _set_first_failure(stage: String, reason: String) -> void:
	if str(state.get("firstFailure", "NONE")) == "NONE":
		state["firstFailure"] = stage if reason.is_empty() else "%s:%s" % [stage, reason]
	state["lastEvent"] = reason
	_publish()

func _publish() -> void:
	practice_state_changed.emit(diagnostic_snapshot())
