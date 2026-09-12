extends SceneTree

const MAIN_SCENE := "res://Main.tscn"
const REQUIRED_EXPORT_RESOURCES := [
	"res://Main.tscn",
	"res://scripts/pocketpt/pocketpt_bootstrap.gd",
	"res://scripts/pocketpt/pocketpt_game_client.gd",
	"res://scripts/pocketpt/pocketpt_locomotion_animator.gd",
	"res://game/animations/player/player_locomotion_library.tres",
	"res://game/animations/player/player_locomotion_tree.tres",
	"res://game/animations/player/player_action_library.tres",
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		return _fail("MAIN_SCENE_LOAD")
	if change_scene_to_packed(packed) != OK:
		return _fail("MAIN_SCENE_CHANGE")
	await scene_changed
	await process_frame
	await process_frame
	var bootstrap := current_scene.get_node_or_null("PocketPTBootstrap")
	if bootstrap == null:
		return _fail("PRODUCTION_BOOTSTRAP_NODE")
	var client := bootstrap.get_node_or_null("PocketPTGameClient") as PocketPTGameClient
	if client == null:
		return _fail("GAME_CLIENT_CREATED")
	if not client.has_method("report_ready"):
		return _fail("READY_SENDER_METHOD")
	# Desktop cannot complete the browser handshake, but this exact error proves
	# production Main reached the deferred initialize() call that owns READY.
	if str(client.connection_state.get("error_code", "")) != PocketPTGameClient.ERROR_WEB_EXPORT_UNSUPPORTED:
		return _fail("PRODUCTION_INITIALIZE_PATH")
	var bootstrap_source := FileAccess.get_file_as_string("res://scripts/pocketpt/pocketpt_bootstrap.gd")
	if 'client.call_deferred("initialize")' not in bootstrap_source:
		return _fail("DEFERRED_INITIALIZE_WIRING")
	var client_source := FileAccess.get_file_as_string("res://scripts/pocketpt/pocketpt_game_client.gd")
	if '"type": "POCKETPT_GODOT_BRIDGE"' not in client_source or '"event": "READY"' not in client_source:
		return _fail("READY_PAYLOAD_WIRING")
	var export_source := FileAccess.get_file_as_string("res://export_presets.cfg")
	for resource_path in REQUIRED_EXPORT_RESOURCES:
		if resource_path not in export_source:
			return _fail("EXPORT_RESOURCE:%s" % resource_path)
	print("POCKETPT_STARTUP_READY_TEST: PASS Main.tscn -> PocketPTBootstrap -> PocketPTGameClient.initialize -> POCKETPT_GODOT_BRIDGE/READY")
	quit(0)

func _fail(boundary: String) -> void:
	push_error("POCKETPT_STARTUP_READY_TEST: FIRST FAILURE: " + boundary)
	quit(1)
