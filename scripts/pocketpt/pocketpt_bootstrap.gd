extends Node

const AvatarLoaderScript = preload("res://scripts/pocketpt/pocketpt_avatar_loader.gd")
const PhoneFlowScript = preload("res://scripts/pocketpt/pocketpt_phone_flow_live_mocap.gd")
const LocomotionAnimatorScript = preload("res://scripts/pocketpt/pocketpt_locomotion_animator.gd")
const REMOTE_AVATAR_LOADER_SCRIPT_PATH := "res://scripts/pocketpt/pocketpt_remote_avatar_loader.gd"
const LOBBY_CLIENT_SCRIPT_PATH := "res://scripts/pocketpt/pocketpt_lobby_client.gd"
const PRACTICE_GAME_SCRIPT_PATH := "res://scripts/games/pushup_maze_practice.gd"
const PRACTICE_DIAGNOSTIC_SCRIPT_PATH := "res://scripts/games/pushup_maze_diagnostic_bridge.gd"

var client: PocketPTGameClient
var debug_ui: PocketPTBridgeDebug
var avatar_loader: Node
var phone_flow: Node
var locomotion_animator: Node
var local_player: GymPlayerController
var remote_players: Node3D
var remote_avatar_loader: Node
var lobby_client: Node

var _optional_multiplayer_started := false
var _practice_runtime_started := false
var _practice_runtime_start_queued := false
var _practice_connection_state: Dictionary = {}
var _practice_avatar_state: Dictionary = {}

func _ready() -> void:
	name = "PocketPTBootstrap"
	_report_startup_stage("BOOTSTRAP_ENTERED", "PASS")

	# Critical startup path. Keep this sequence aligned with the last physically
	# proven personalized-avatar + controls runtime. Optional systems must never
	# stand between this path and PocketPTGameClient.initialize().
	client = PocketPTGameClient.new()
	client.name = "PocketPTGameClient"
	add_child(client)
	_report_startup_stage("CLIENT_CREATED", "PASS")

	debug_ui = PocketPTBridgeDebug.new()
	debug_ui.name = "PocketPTBridgeDebug"
	add_child(debug_ui)
	debug_ui.bind_client(client)
	_report_startup_stage("DEBUG_BOUND", "PASS")

	var current_scene := get_tree().current_scene
	if current_scene == null:
		_report_startup_stage("MAIN_SCENE_MISSING", "FAIL")
		push_error("PocketPT bootstrap requires an active main scene")
		return

	var visual_mount := current_scene.get_node_or_null("player/avataranchor") as Node3D
	var fallback_visual := current_scene.get_node_or_null("player/Sketchfab_Scene") as Node3D
	avatar_loader = AvatarLoaderScript.new()
	avatar_loader.name = "PocketPTAvatarLoader"
	add_child(avatar_loader)
	avatar_loader.bind(client, visual_mount, fallback_visual)
	debug_ui.bind_avatar_loader(avatar_loader)
	_report_startup_stage("AVATAR_LOADER_BOUND", "PASS")

	local_player = current_scene.get_node_or_null("player") as GymPlayerController
	if local_player != null:
		locomotion_animator = LocomotionAnimatorScript.new()
		locomotion_animator.name = "PocketPTLocomotionAnimator"
		add_child(locomotion_animator)
		locomotion_animator.bind(local_player, avatar_loader)

		phone_flow = PhoneFlowScript.new()
		phone_flow.name = "PocketPTPhoneFlow"
		add_child(phone_flow)
		phone_flow.bind(client, local_player, avatar_loader, locomotion_animator)
		debug_ui.bind_runtime(phone_flow, local_player)
		_report_startup_stage("LOCAL_RUNTIME_BOUND", "PASS")
	else:
		_report_startup_stage("LOCAL_PLAYER_MISSING", "FAIL")

	# FIRST-FAILURE PROTECTION: start the proven PocketPT client before loading
	# multiplayer or maze code. Production evidence showed the broken build never
	# issued Godot's own /api/game/bootstrap request, so nothing optional is
	# allowed to execute ahead of this call anymore.
	client.call_deferred("initialize")
	_report_startup_stage("CLIENT_INITIALIZE_QUEUED", "PASS")

	client.connection_state_changed.connect(_on_practice_connection_state_changed)
	avatar_loader.avatar_state_changed.connect(_on_practice_avatar_state_changed)
	_practice_connection_state = client.connection_state.duplicate(true)
	_practice_avatar_state = avatar_loader.avatar_state.duplicate(true)

	# Optional systems are deferred and dynamically loaded. A failure in either
	# multiplayer or maze code cannot prevent auth, READY, personal-avatar loading,
	# locomotion, or phone controls from starting.
	call_deferred("_initialize_optional_multiplayer")
	_report_startup_stage("OPTIONAL_MULTIPLAYER_QUEUED", "PASS")
	_queue_practice_runtime_if_ready()

func practice_runtime_gate_for_test(connection: Dictionary, avatar: Dictionary, web_runtime: bool = true) -> bool:
	return _practice_runtime_gate(connection, avatar, web_runtime)

func _initialize_optional_multiplayer() -> void:
	if _optional_multiplayer_started:
		return
	_optional_multiplayer_started = true
	_report_startup_stage("OPTIONAL_MULTIPLAYER_ENTERED", "PASS")

	var current_scene := get_tree().current_scene
	if current_scene == null or local_player == null or locomotion_animator == null:
		_report_startup_stage("OPTIONAL_MULTIPLAYER_SKIPPED", "FAIL")
		return

	var remote_loader_script := load(REMOTE_AVATAR_LOADER_SCRIPT_PATH) as GDScript
	var lobby_script := load(LOBBY_CLIENT_SCRIPT_PATH) as GDScript
	if remote_loader_script == null or lobby_script == null:
		_report_startup_stage("OPTIONAL_MULTIPLAYER_SCRIPT_LOAD", "FAIL")
		push_error("PocketPT optional multiplayer scripts could not be loaded")
		return

	remote_players = current_scene.get_node_or_null("RemotePlayers") as Node3D
	if remote_players == null:
		remote_players = Node3D.new()
		remote_players.name = "RemotePlayers"
		current_scene.add_child(remote_players)

	remote_avatar_loader = remote_loader_script.new() as Node
	if remote_avatar_loader == null:
		_report_startup_stage("REMOTE_AVATAR_LOADER_CREATE", "FAIL")
		return
	remote_avatar_loader.name = "PocketPTRemoteAvatarLoader"
	add_child(remote_avatar_loader)

	lobby_client = lobby_script.new() as Node
	if lobby_client == null:
		_report_startup_stage("LOBBY_CLIENT_CREATE", "FAIL")
		return
	lobby_client.name = "PocketPTLobbyClient"
	add_child(lobby_client)
	lobby_client.bind(client, local_player, locomotion_animator, remote_players, remote_avatar_loader)
	debug_ui.bind_multiplayer(lobby_client)
	_report_startup_stage("OPTIONAL_MULTIPLAYER_BOUND", "PASS")

func _on_practice_connection_state_changed(state: Dictionary) -> void:
	_practice_connection_state = state.duplicate(true)
	if str(state.get("status", "")) == "CONNECTING":
		_report_startup_stage("INNER_BOOTSTRAP_STARTED", "PASS")
	elif str(state.get("status", "")) == "CONNECTED":
		_report_startup_stage("INNER_BOOTSTRAP_ACCEPTED", "PASS")
	elif str(state.get("status", "")) == "READY" and bool(state.get("parent_handshake", false)):
		_report_startup_stage("READY_SENT", "PASS")
	elif str(state.get("status", "")) == "ERROR":
		_report_startup_stage("CORE_CLIENT_ERROR", "FAIL")
	_queue_practice_runtime_if_ready()

func _on_practice_avatar_state_changed(state: Dictionary) -> void:
	_practice_avatar_state = state.duplicate(true)
	match str(state.get("status", "")):
		"LOADING":
			_report_startup_stage("AVATAR_LOADING", "PASS")
		"MOUNTED":
			_report_startup_stage("AVATAR_MOUNTED", "PASS")
		"FALLBACK":
			_report_startup_stage("AVATAR_FALLBACK", "PASS")
		"ERROR":
			_report_startup_stage("AVATAR_ERROR", "FAIL")
	_queue_practice_runtime_if_ready()

func _practice_runtime_gate(connection: Dictionary, avatar: Dictionary, web_runtime: bool) -> bool:
	if not web_runtime:
		return true
	if str(connection.get("status", "")) != "READY" or not bool(connection.get("parent_handshake", false)):
		return false
	return str(avatar.get("status", "")) in ["MOUNTED", "FALLBACK", "ERROR"]

func _queue_practice_runtime_if_ready() -> void:
	if _practice_runtime_started or _practice_runtime_start_queued:
		return
	if not _practice_runtime_gate(_practice_connection_state, _practice_avatar_state, OS.has_feature("web")):
		return
	_practice_runtime_start_queued = true
	call_deferred("_start_practice_runtime")

func _start_practice_runtime() -> void:
	_practice_runtime_start_queued = false
	if _practice_runtime_started:
		return
	if not _practice_runtime_gate(_practice_connection_state, _practice_avatar_state, OS.has_feature("web")):
		return
	var current_scene := get_tree().current_scene
	if current_scene == null:
		push_error("PocketPT practice runtime requires an active main scene")
		return

	var practice_game := current_scene.get_node_or_null("PushUpMazePractice")
	if practice_game == null:
		var practice_script := load(PRACTICE_GAME_SCRIPT_PATH) as GDScript
		if practice_script == null:
			push_error("PocketPT practice runtime could not load maze script")
			return
		practice_game = practice_script.new() as Node3D
		if practice_game == null:
			push_error("PocketPT practice runtime could not instantiate maze")
			return
		practice_game.name = "PushUpMazePractice"
		current_scene.add_child(practice_game)

	if current_scene.get_node_or_null("PushUpMazeDiagnosticBridge") == null:
		var diagnostic_script := load(PRACTICE_DIAGNOSTIC_SCRIPT_PATH) as GDScript
		if diagnostic_script == null:
			push_error("PocketPT practice runtime could not load maze diagnostic bridge")
			return
		var diagnostic_bridge := diagnostic_script.new() as Node
		if diagnostic_bridge == null:
			push_error("PocketPT practice runtime could not instantiate maze diagnostic bridge")
			return
		diagnostic_bridge.name = "PushUpMazeDiagnosticBridge"
		current_scene.add_child(diagnostic_bridge)

	_practice_runtime_started = true
	_report_startup_stage("PRACTICE_RUNTIME_STARTED", "PASS")

func _report_startup_stage(stage: String, status: String) -> void:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return
	var window = JavaScriptBridge.get_interface("window")
	if window == null:
		return
	var safe_stage := stage if stage in [
		"BOOTSTRAP_ENTERED", "CLIENT_CREATED", "DEBUG_BOUND", "MAIN_SCENE_MISSING",
		"AVATAR_LOADER_BOUND", "LOCAL_RUNTIME_BOUND", "LOCAL_PLAYER_MISSING",
		"CLIENT_INITIALIZE_QUEUED", "OPTIONAL_MULTIPLAYER_QUEUED", "OPTIONAL_MULTIPLAYER_ENTERED",
		"OPTIONAL_MULTIPLAYER_SKIPPED", "OPTIONAL_MULTIPLAYER_SCRIPT_LOAD", "REMOTE_AVATAR_LOADER_CREATE",
		"LOBBY_CLIENT_CREATE", "OPTIONAL_MULTIPLAYER_BOUND", "INNER_BOOTSTRAP_STARTED",
		"INNER_BOOTSTRAP_ACCEPTED", "READY_SENT", "CORE_CLIENT_ERROR", "AVATAR_LOADING",
		"AVATAR_MOUNTED", "AVATAR_FALLBACK", "AVATAR_ERROR", "PRACTICE_RUNTIME_STARTED"
	] else "UNKNOWN_STAGE"
	var safe_status := status if status in ["PASS", "FAIL"] else "PASS"
	var payload := {
		"type": "POCKETPT_GODOT_BRIDGE",
		"event": "STARTUP_STAGE",
		"protocolVersion": 1,
		"stage": safe_stage,
		"status": safe_status
	}
	var serialized_literal := JSON.stringify(JSON.stringify(payload))
	var script := """
(() => {
	try {
		if (window.parent === window || !window.location.origin) return false;
		window.parent.postMessage(JSON.parse(%s), window.location.origin);
		return true;
	} catch (_error) {
		return false;
	}
})()
""" % serialized_literal
	JavaScriptBridge.eval(script)
