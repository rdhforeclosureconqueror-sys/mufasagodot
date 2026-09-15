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
	_expect(not main_scene.contains("[node name=\"LearningPoolPreview\""), "learning pool must not be a static Main.tscn startup node")
	_expect(not main_scene.contains("[node name=\"UnderwaterLearningWorld\""), "underwater learning world must not be a static Main.tscn startup node")
	_expect(not main_scene.contains("path=\"res://scripts/games/"), "Main.tscn must not statically wire scripts/games; game worlds load only after avatar readiness")
	_expect(not main_scene.contains("path=\"res://scenes/games/"), "Main.tscn must not statically wire scenes/games; game worlds load only after avatar readiness")
	_expect(main_scene.contains("[node name=\"PocketPTBootstrap\""), "PocketPT bootstrap remains in the startup scene")

	var bootstrap_source := FileAccess.get_file_as_string("res://scripts/pocketpt/pocketpt_bootstrap.gd")
	var initialize_index := bootstrap_source.find("client.call_deferred(\"initialize\")")
	var remote_loader_index := bootstrap_source.find("load(REMOTE_AVATAR_LOADER_SCRIPT_PATH)")
	var lobby_loader_index := bootstrap_source.find("load(LOBBY_CLIENT_SCRIPT_PATH)")
	_expect(initialize_index >= 0, "PocketPT core client initialize call must exist")
	_expect(remote_loader_index > initialize_index, "remote avatar runtime must load only after core initialize is queued")
	_expect(lobby_loader_index > initialize_index, "lobby runtime must load only after core initialize is queued")
	_expect(not bootstrap_source.contains("preload(\"res://scripts/pocketpt/pocketpt_remote_avatar_loader.gd\")"), "remote avatar code must not preload into the critical startup path")
	_expect(not bootstrap_source.contains("preload(\"res://scripts/pocketpt/pocketpt_lobby_client.gd\")"), "lobby code must not preload into the critical startup path")
	_expect(bootstrap_source.contains("CLIENT_INITIALIZE_QUEUED"), "pre-READY startup telemetry must include core initialize evidence")
	_expect(bootstrap_source.contains("INNER_BOOTSTRAP_STARTED"), "pre-READY startup telemetry must expose inner bootstrap start")
	_expect(bootstrap_source.contains("READY_SENT"), "pre-READY startup telemetry must expose READY send")

	var debug_source := FileAccess.get_file_as_string("res://scripts/pocketpt/pocketpt_bridge_debug.gd")
	_expect(not debug_source.contains(": PocketPTLobbyClient"), "critical debug script must not hard-type the optional lobby client")
	_expect(debug_source.contains("var lobby_client: Node"), "debug bridge must hold multiplayer through a generic optional Node reference")
	_expect(debug_source.contains("has_method(\"diagnostic_snapshot\")"), "debug bridge must guard optional multiplayer diagnostics dynamically")

	var main_source := FileAccess.get_file_as_string("res://main.gd")
	_expect(main_source.contains("MAIN_SCENE_READY"), "main scene must report before PocketPT bootstrap so pre-bootstrap failures are visible")

	var export_presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	for deferred_path in [
		"res://scripts/pocketpt/pocketpt_remote_avatar_loader.gd",
		"res://scripts/pocketpt/pocketpt_lobby_client.gd",
		"res://scripts/pocketpt/pocketpt_remote_player.gd",
		"res://scripts/games/pushup_maze_practice.gd",
		"res://scripts/games/pushup_maze_diagnostic_bridge.gd"
	]:
		_expect(export_presets.contains("\"%s\"" % deferred_path), "Web export must include deferred runtime: %s" % deferred_path)

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
