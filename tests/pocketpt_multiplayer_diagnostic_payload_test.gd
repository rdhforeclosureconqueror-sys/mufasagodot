extends SceneTree

const LobbyScript = preload("res://scripts/pocketpt/pocketpt_lobby_client.gd")
const PlayerScript = preload("res://player.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var root_node := Node3D.new()
	get_root().add_child(root_node)
	var player := PlayerScript.new() as GymPlayerController
	root_node.add_child(player)
	var remote_container := Node3D.new()
	root_node.add_child(remote_container)
	var lobby := LobbyScript.new() as PocketPTLobbyClient
	root_node.add_child(lobby)
	lobby.bind(null, player, null, remote_container, null)
	lobby.multiplayer_state["connectionState"] = "ACTIVE"
	lobby.multiplayer_state["roomId"] = "lions_den"
	lobby.multiplayer_state["selfPresenceId"] = "presence-a"
	lobby.multiplayer_state["localMemberId"] = "member-a"
	lobby.multiplayer_state["roomPlayerCount"] = 2
	lobby.multiplayer_state["remotePlayerCount"] = 1
	lobby.multiplayer_state["remoteAvatarsLoaded"] = 1
	lobby.multiplayer_state["stateSendAttempts"] = 12
	lobby.multiplayer_state["stateSendSuccesses"] = 12
	lobby.multiplayer_state["lastStateSentSeq"] = 12
	lobby.multiplayer_state["stateReceiveCount"] = 9
	lobby.multiplayer_state["lastStateReceivedSeq"] = 9
	lobby.multiplayer_state["lastStateAgeMs"] = 40
	lobby.multiplayer_state["remoteMoveCount"] = 7
	lobby.multiplayer_state["connectionGeneration"] = 3
	lobby.multiplayer_state["reconnectCount"] = 1
	player.actual_horizontal_displacement = 0.04

	var first := lobby.build_multiplayer_diagnostic_payload_for_test(1000, "launch-1", 1)
	var first_mp = first.get("multiplayer")
	_expect(first.get("event") == "MULTIPLAYER_DIAGNOSTIC", "event contract")
	_expect(first.get("requestId") == "launch-1", "launch correlation")
	_expect(int(first.get("sequence", 0)) == 1, "sequence contract")
	_expect(first_mp is Dictionary, "multiplayer payload exists")
	if first_mp is Dictionary:
		_expect(first_mp.get("connectionState") == "READY", "ACTIVE normalizes to READY")
		_expect(first_mp.get("snapshotReceived") == true, "authoritative snapshot evidence")
		_expect(int(first_mp.get("roomPlayerCount", 0)) == 2, "room player count")
		_expect(int(first_mp.get("remotePlayerCount", 0)) == 1, "remote player count")
		_expect(int(first_mp.get("stateSendSuccesses", 0)) == 12, "send success mapping")
		_expect(int(first_mp.get("statePacketsReceived", 0)) == 9, "receive count mapping")
		_expect(int(first_mp.get("remoteTargetsApplied", 0)) == 9, "accepted remote states are applied-target evidence")
		_expect(int(first_mp.get("remotePuppetMoves", 0)) == 7, "remote interpolation movement mapping")
		_expect(first_mp.get("localPhysicallyMoving") == true, "local physical movement evidence")
		_expect(int(first_mp.get("roomReadyAgeMs", -1)) == 0, "ready age begins at zero")

	var second := lobby.build_multiplayer_diagnostic_payload_for_test(2800, "launch-1", 2)
	var second_mp = second.get("multiplayer")
	if second_mp is Dictionary:
		_expect(int(second_mp.get("roomReadyAgeMs", -1)) == 1800, "ready age advances for receive-stall diagnosis")

	root_node.queue_free()
	call_deferred("_finish")

func _expect(value: bool, label: String) -> void:
	if not value:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("POCKETPT_MULTIPLAYER_DIAGNOSTIC_PAYLOAD: PASS")
		quit(0)
		return
	for failure in failures:
		push_error("POCKETPT_MULTIPLAYER_DIAGNOSTIC_PAYLOAD: %s" % failure)
	quit(1)
