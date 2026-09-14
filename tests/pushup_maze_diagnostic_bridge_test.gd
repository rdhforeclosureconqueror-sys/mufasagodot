extends SceneTree

const MazeScript = preload("res://scripts/games/pushup_maze_practice.gd")
const BridgeScript = preload("res://scripts/games/pushup_maze_diagnostic_bridge.gd")

class FakePhoneFlow:
	extends Node
	var _diagnostic_request_id := "maze-diagnostic-test"
	var reports: Array[Dictionary] = []
	func _report_diagnostic(stage: String, status: String, reason_code := "", details: Dictionary = {}) -> void:
		reports.append({"stage": stage, "status": status, "reasonCode": reason_code, "details": details.duplicate(true)})

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var maze := MazeScript.new() as PushUpMazePractice
	var flow := FakePhoneFlow.new()
	var bridge := BridgeScript.new() as PushUpMazeDiagnosticBridge
	bridge.bind_for_test(maze, flow)

	maze.state["mazeReady"] = true
	maze.state["status"] = "IDLE"
	maze.state["firstFailure"] = "NONE"
	_expect(bridge.report_for_test(), "idle ready maze reports")
	_expect(flow.reports.size() == 1, "first maze diagnostic emitted once")
	_expect(flow.reports[0].stage == "CHALLENGE_STATE" and flow.reports[0].status == "WAITING", "maze reuses existing consolidated CHALLENGE_STATE lane")
	_expect(flow.reports[0].details.get("practiceMode") == "PUSHUP_MAZE", "diagnostic identifies push-up maze practice mode")
	_expect(not bridge.report_for_test(), "unchanged maze state does not spam diagnostics")

	maze.state["status"] = "ACTIVE"
	maze.state["checkpoint"] = 1
	maze.state["lastEvent"] = "CHECKPOINT_1"
	_expect(bridge.report_for_test(), "active maze change reports")
	_expect(flow.reports[-1].status == "RUNNING", "active maze maps to running challenge state")
	_expect(int(flow.reports[-1].details.get("mazeCheckpoint", 0)) == 1, "checkpoint evidence is attached")

	maze.state["firstFailure"] = "MAZE_PLAYER_FELL:PLAYER_BELOW_COURSE"
	maze.state["status"] = "FAILED"
	_expect(bridge.report_for_test(), "maze first failure reports")
	_expect(flow.reports[-1].status == "FAIL", "maze first failure marks consolidated challenge state failed")
	_expect(flow.reports[-1].details.get("mazeFirstFailure") == "MAZE_PLAYER_FELL:PLAYER_BELOW_COURSE", "specific maze first failure travels with diagnostic evidence")

	maze.state["firstFailure"] = "NONE"
	maze.state["status"] = "FINISHED"
	maze.state["result"] = "COMPLETE"
	maze.state["checkpoint"] = 4
	_expect(bridge.report_for_test(), "completed maze reports")
	_expect(flow.reports[-1].status == "PASS", "completed maze maps to pass")

	flow._diagnostic_request_id = ""
	maze.state["status"] = "ACTIVE"
	_expect(not bridge.report_for_test(), "maze does not emit outside an active diagnostics request")

	if failures.is_empty():
		print("PUSHUP_MAZE_DIAGNOSTIC_BRIDGE_TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PUSHUP_MAZE_DIAGNOSTIC_BRIDGE_TEST: FAIL (%d)" % failures.size())
		quit(1)

func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
