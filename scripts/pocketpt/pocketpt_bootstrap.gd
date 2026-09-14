extends Node

const AvatarLoaderScript = preload("res://scripts/pocketpt/pocketpt_avatar_loader.gd")
const PhoneFlowScript = preload("res://scripts/pocketpt/pocketpt_phone_flow.gd")
const LocomotionAnimatorScript = preload("res://scripts/pocketpt/pocketpt_locomotion_animator.gd")
const RemoteAvatarLoaderScript = preload("res://scripts/pocketpt/pocketpt_remote_avatar_loader.gd")
const LobbyClientScript = preload("res://scripts/pocketpt/pocketpt_lobby_client.gd")

var client: PocketPTGameClient
var debug_ui: PocketPTBridgeDebug
var avatar_loader: Node
var phone_flow: Node
var locomotion_animator: Node
var remote_players: Node3D
var remote_avatar_loader: Node
var lobby_client: Node
var practice_game: PushUpMazePractice

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
	practice_game = current_scene.get_node_or_null("PushUpMazePractice") as PushUpMazePractice
	if practice_game != null:
		debug_ui.bind_practice_game(practice_game)

	var visual_mount := current_scene.get_node_or_null("player/avataranchor") as Node3D
	var fallback_visual := current_scene.get_node_or_null("player/Sketchfab_Scene") as Node3D
	avatar_loader = AvatarLoaderScript.new()
	avatar_loader.name = "PocketPTAvatarLoader"
	add_child(avatar_loader)
	avatar_loader.bind(client, visual_mount, fallback_visual)
	debug_ui.bind_avatar_loader(avatar_loader)

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
