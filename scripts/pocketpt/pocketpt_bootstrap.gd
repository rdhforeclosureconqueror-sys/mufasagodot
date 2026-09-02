extends Node

const AvatarLoaderScript = preload("res://scripts/pocketpt/pocketpt_avatar_loader.gd")

var client: PocketPTGameClient
var debug_ui: PocketPTBridgeDebug
var avatar_loader: Node

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
	var visual_mount := current_scene.get_node_or_null("player/avataranchor") as Node3D
	var fallback_visual := current_scene.get_node_or_null("player/Sketchfab_Scene") as Node3D
	avatar_loader = AvatarLoaderScript.new()
	avatar_loader.name = "PocketPTAvatarLoader"
	add_child(avatar_loader)
	avatar_loader.bind(client, visual_mount, fallback_visual)
	debug_ui.bind_avatar_loader(avatar_loader)

	client.call_deferred("initialize")
