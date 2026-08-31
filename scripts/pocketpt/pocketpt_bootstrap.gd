extends Node

var client: PocketPTGameClient
var debug_ui: PocketPTBridgeDebug

func _ready() -> void:
	name = "PocketPTBootstrap"
	client = PocketPTGameClient.new()
	client.name = "PocketPTGameClient"
	add_child(client)

	debug_ui = PocketPTBridgeDebug.new()
	debug_ui.name = "PocketPTBridgeDebug"
	add_child(debug_ui)
	debug_ui.bind_client(client)

	client.call_deferred("initialize")
