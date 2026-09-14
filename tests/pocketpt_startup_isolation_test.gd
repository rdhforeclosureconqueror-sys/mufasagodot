extends SceneTree

const BootstrapScript = preload("res://scripts/pocketpt/pocketpt_bootstrap.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var bootstrap = BootstrapScript.new()

	_expect(
		not bootstrap.practice_runtime_gate_for_test(
			{"status": "CONNECTED", "parent_handshake": false},
			{"status": "MOUNTED"},
			true
		),
		"maze must not start before the parent READY handshake"
	)
	_expect(
		not bootstrap.practice_runtime_gate_for_test(
			{"status": "READY", "parent_handshake": true},
			{"status": "LOADING"},
			true
		),
		"maze must not start while a personal avatar is still loading"
	)
	_expect(
		bootstrap.practice_runtime_gate_for_test(
			{"status": "READY", "parent_handshake": true},
			{"status": "MOUNTED"},
			true
		),
		"maze may start after READY plus personal avatar mount"
	)
	_expect(
		bootstrap.practice_runtime_gate_for_test(
			{"status": "READY", "parent_handshake": true},
			{"status": "FALLBACK"},
			true
		),
		"maze may start after READY plus an intentional fallback decision"
	)
	_expect(
		bootstrap.practice_runtime_gate_for_test(
			{"status": "READY", "parent_handshake": true},
			{"status": "ERROR"},
			true
		),
		"maze may start after READY plus a settled avatar error so diagnostics remain reachable"
	)
	_expect(
		bootstrap.practice_runtime_gate_for_test({}, {}, false),
		"desktop/editor runtime keeps the maze available without the Web handshake"
	)

	var main_scene := FileAccess.get_file_as_string("res://Main.tscn")
	_expect(not main_scene.contains("[node name=\"PushUpMazePractice\""), "maze practice must not be a static Main.tscn startup node")
	_expect(not main_scene.contains("[node name=\"PushUpMazeDiagnosticBridge\""), "maze diagnostics must not be a static Main.tscn startup node")
	_expect(main_scene.contains("[node name=\"PocketPTBootstrap\""), "PocketPT bootstrap remains in the startup scene")

	bootstrap.free()
	if failures.is_empty():
		print("POCKETPT_STARTUP_ISOLATION_TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("POCKETPT_STARTUP_ISOLATION_TEST: FAIL (%d)" % failures.size())
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
