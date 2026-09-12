extends Node

const AvatarLoaderScript = preload("res://scripts/pocketpt/pocketpt_avatar_loader.gd")
const PhoneFlowScript = preload("res://scripts/pocketpt/pocketpt_phone_flow.gd")
const LocomotionAnimatorScript = preload("res://scripts/pocketpt/pocketpt_locomotion_animator.gd")

var client: PocketPTGameClient
var debug_ui: PocketPTBridgeDebug
var avatar_loader: Node
var phone_flow: Node
var locomotion_animator: Node

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
	var player := current_scene.get_node_or_null("player") as GymPlayerController
	if player != null:
		locomotion_animator = LocomotionAnimatorScript.new()
		locomotion_animator.name = "PocketPTLocomotionAnimator"
		add_child(locomotion_animator)
		locomotion_animator.bind(player, avatar_loader)
		phone_flow = PhoneFlowScript.new()
		phone_flow.name = "PocketPTPhoneFlow"
		add_child(phone_flow)
		phone_flow.bind(client, player, avatar_loader)
		debug_ui.bind_runtime(phone_flow, player)

	client.call_deferred("initialize")
