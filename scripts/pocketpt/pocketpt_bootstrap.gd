extends Node

const AvatarLoaderScript = preload("res://scripts/pocketpt/pocketpt_avatar_loader.gd")
const PhoneFlowScript = preload("res://scripts/pocketpt/pocketpt_phone_flow.gd")
const LocomotionAnimatorScript = preload("res://scripts/pocketpt/pocketpt_locomotion_animator.gd")
const RemoteAvatarLoaderScript = preload("res://scripts/pocketpt/pocketpt_remote_avatar_loader.gd")
const LobbyClientScript = preload("res://scripts/pocketpt/pocketpt_lobby_client.gd")
const PRACTICE_GAME_SCRIPT_PATH := "res://scripts/games/pushup_maze_practice.gd"
const PRACTICE_DIAGNOSTIC_SCRIPT_PATH := "res://scripts/games/pushup_maze_diagnostic_bridge.gd"

var client: PocketPTGameClient
var debug_ui: PocketPTBridgeDebug
var avatar_loader: Node
var phone_flow: Node
var locomotion_animator: Node
var remote_players: Node3D
var remote_avatar_loader: Node
var lobby_client: Node

var _practice_runtime_started := false
var _practice_runtime_start_queued := false
var _practice_connection_state: Dictionary = {}
var _practice_avatar_state: Dictionary = {}

func _ready() -> void:
	name = "PocketPTBootstrap"
	client = PocketPTGameClient.new()
	client.name = "PocketPTGameClient"
	add_child(client)

	debug_ui = PocketPTBridgeDebug.new()
	debug_ui.name = "PocketPTBridgeDebug"
	add_child(debug_ui)
	debug_ui.bind_client(client)

	var current_scene := get_tree().current_scene
	if current_scene == null:
		push_error("PocketPT bootstrap requires an active main scene")
		return
	var visual_mount := current_scene.get_node_or_null("player/avataranchor") as Node3D
	var fallback_visual := current_scene.get_node_or_null("player/Sketchfab_Scene") as Node3D
	avatar_loader = AvatarLoaderScript.new()
	avatar_loader.name = "PocketPTAvatarLoader"
	add_child(avatar_loader)
	avatar_loader.bind(client, visual_mount, fallback_visual)
	debug_ui.bind_avatar_loader(avatar_loader)

	client.connection_state_changed.connect(_on_practice_connection_state_changed)
	avatar_loader.avatar_state_changed.connect(_on_practice_avatar_state_changed)
	_practice_connection_state = client.connection_state.duplicate(true)
	_practice_avatar_state = avatar_loader.avatar_state.duplicate(true)

	remote_players = current_scene.get_node_or_null("RemotePlayers") as Node3D
	if remote_players == null:
		remote_players = Node3D.new()
		remote_players.name = "RemotePlayers"
		current_scene.add_child(remote_players)
	remote_avatar_loader = RemoteAvatarLoaderScript.new()
	remote_avatar_loader.name = "PocketPTRemoteAvatarLoader"
	add_child(remote_avatar_loader)

	var player := current_scene.get_node_or_null("player") as GymPlayerController
	if player != null:
		locomotion_animator = LocomotionAnimatorScript.new()
		locomotion_animator.name = "PocketPTLocomotionAnimator"
		add_child(locomotion_animator)
		locomotion_animator.bind(player, avatar_loader)
		phone_flow = PhoneFlowScript.new()
		phone_flow.name = "PocketPTPhoneFlow"
		add_child(phone_flow)
		phone_flow.bind(client, player, avatar_loader, locomotion_animator)
		debug_ui.bind_runtime(phone_flow, player)

		lobby_client = LobbyClientScript.new()
		lobby_client.name = "PocketPTLobbyClient"
		add_child(lobby_client)
		lobby_client.bind(client, player, locomotion_animator, remote_players, remote_avatar_loader)
		debug_ui.bind_multiplayer(lobby_client)

	client.call_deferred("initialize")
	_queue_practice_runtime_if_ready()

func practice_runtime_gate_for_test(connection: Dictionary, avatar: Dictionary, web_runtime: bool = true) -> bool:
	return _practice_runtime_gate(connection, avatar, web_runtime)

func _on_practice_connection_state_changed(state: Dictionary) -> void:
	_practice_connection_state = state.duplicate(true)
	_queue_practice_runtime_if_ready()

func _on_practice_avatar_state_changed(state: Dictionary) -> void:
	_practice_avatar_state = state.duplicate(true)
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
