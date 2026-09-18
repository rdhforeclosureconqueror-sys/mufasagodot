class_name PushUpMazeDiagnosticBridge
extends Node

const UNDERWATER_PREVIEW_SCRIPT_PATH := "res://scripts/games/underwater_vowel_treasure_preview.gd"

var _practice_game: PushUpMazePractice
var _phone_flow: Node
var _last_signature := ""
var _underwater_preview: Node
var _underwater_mount_attempts := 0
var _underwater_mount_last_reason := "NOT_ATTEMPTED"

func _ready() -> void:
	name = "PushUpMazeDiagnosticBridge"
	set_process(true)
	call_deferred("_mount_underwater_learning_preview")

func _process(_delta: float) -> void:
	_resolve_dependencies()
	# The bridge can become ready before the scene/player is fully observable on
	# slower Web/mobile startup. Keep retrying until the portal/world is mounted;
	# the old one-shot deferred call could silently return and never try again.
	if _underwater_preview == null or not is_instance_valid(_underwater_preview):
		_mount_underwater_learning_preview()
	_report_if_needed()

func bind_for_test(practice_game: PushUpMazePractice, phone_flow: Node) -> void:
	_practice_game = practice_game
	_phone_flow = phone_flow
	_last_signature = ""

func report_for_test() -> bool:
	return _report_if_needed()

func _mount_underwater_learning_preview() -> void:
	_underwater_mount_attempts += 1
	if _underwater_preview != null and is_instance_valid(_underwater_preview):
		return
	var scene := get_tree().current_scene
	if scene == null:
		_underwater_mount_last_reason = "SCENE_NOT_READY"
		return
	if scene.get_node_or_null("player") == null:
		_underwater_mount_last_reason = "PLAYER_NOT_READY"
		return
	if scene.get_node_or_null("UnderwaterLearningPreview") != null:
		_underwater_preview = scene.get_node("UnderwaterLearningPreview")
		_underwater_mount_last_reason = "EXISTING_PREVIEW_FOUND"
		return
	var preview_script := load(UNDERWATER_PREVIEW_SCRIPT_PATH) as GDScript
	if preview_script == null:
		_underwater_mount_last_reason = "SCRIPT_LOAD_FAILED"
		push_error("Underwater learning preview script could not be loaded")
		return
	_underwater_preview = preview_script.new() as Node
	if _underwater_preview == null:
		_underwater_mount_last_reason = "INSTANTIATE_FAILED"
		push_error("Underwater learning preview could not be instantiated")
		return
	_underwater_preview.name = "UnderwaterLearningPreview"
	scene.add_child(_underwater_preview)
	_underwater_mount_last_reason = "MOUNTED"

func _resolve_dependencies() -> void:
	if _practice_game == null or not is_instance_valid(_practice_game):
		var scene := get_tree().current_scene
		if scene != null:
			_practice_game = scene.get_node_or_null("PushUpMazePractice") as PushUpMazePractice
	if _phone_flow == null or not is_instance_valid(_phone_flow):
		var scene := get_tree().current_scene
		if scene != null:
			_phone_flow = scene.get_node_or_null("PocketPTBootstrap/PocketPTPhoneFlow")

func _report_if_needed() -> bool:
	if _practice_game == null or not is_instance_valid(_practice_game):
		return false
	if _phone_flow == null or not is_instance_valid(_phone_flow) or not _phone_flow.has_method("_report_diagnostic"):
		return false
	var request_id := str(_phone_flow.get("_diagnostic_request_id"))
	if request_id.is_empty():
		return false
	var snapshot := _practice_game.diagnostic_snapshot()
	var status := _diagnostic_status(snapshot)
	var reason := _diagnostic_reason(snapshot)
	var signature := "%s|%s|%s|%s|%s" % [
		request_id,
		status,
		str(snapshot.get("status", "IDLE")),
		str(snapshot.get("checkpoint", 0)),
		str(snapshot.get("firstFailure", "NONE"))
	]
	if signature == _last_signature:
		return false
	var details := {
		"practiceMode": "PUSHUP_MAZE",
		"practiceStatus": str(snapshot.get("status", "IDLE")),
		"mazeReady": bool(snapshot.get("mazeReady", false)),
		"mazeCheckpoint": int(snapshot.get("checkpoint", 0)),
		"mazeCheckpointTotal": int(snapshot.get("checkpointTotal", 0)),
		"mazeFirstFailure": str(snapshot.get("firstFailure", "NONE")),
		"underwaterPreviewMounted": _underwater_preview != null and is_instance_valid(_underwater_preview),
		"underwaterMountAttempts": _underwater_mount_attempts,
		"underwaterMountLastReason": _underwater_mount_last_reason
	}
	_phone_flow.call("_report_diagnostic", "CHALLENGE_STATE", status, reason, details)
	_last_signature = signature
	return true

func _diagnostic_status(snapshot: Dictionary) -> String:
	if str(snapshot.get("firstFailure", "NONE")) != "NONE":
		return "FAIL"
	match str(snapshot.get("status", "IDLE")):
		"ACTIVE": return "RUNNING"
		"FINISHED": return "PASS" if str(snapshot.get("result", "NONE")) == "COMPLETE" else "FAIL"
		"FAILED": return "FAIL"
		"IDLE": return "WAITING" if bool(snapshot.get("mazeReady", false)) else "NOT_CONNECTED"
		_: return "NOT_CONNECTED"

func _diagnostic_reason(snapshot: Dictionary) -> String:
	var first_failure := str(snapshot.get("firstFailure", "NONE"))
	if first_failure != "NONE":
		return first_failure
	return str(snapshot.get("lastEvent", "NONE"))
