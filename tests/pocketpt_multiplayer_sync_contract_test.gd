extends SceneTree

const LobbyScript = preload("res://scripts/pocketpt/pocketpt_lobby_client.gd")
const PlayerScript = preload("res://player.gd")
const AnimatorScript = preload("res://scripts/pocketpt/pocketpt_locomotion_animator.gd")

var failures: Array[String] = []
var packets: Array[Dictionary] = []

func _initialize() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var player := PlayerScript.new() as GymPlayerController
	root.add_child(player)
	var animator := AnimatorScript.new() as PocketPTLocomotionAnimator
	root.add_child(animator)
	var remote_container := Node3D.new()
	root.add_child(remote_container)
	var lobby := LobbyScript.new() as PocketPTLobbyClient
	root.add_child(lobby)
	lobby.bind(null, player, animator, remote_container, null)
	lobby.set_transport_sender_for_test(_capture)
	lobby.set_transport_ready_for_test(true, 1000)
	player.global_position = Vector3(4.0, 0.76, -2.0)
	animator.current_state = &"RUN"
	_expect(not lobby.send_authoritative_sample_for_test({"movementMode":"RUN"}, 1079), "send remains capped below 80ms")
	_expect(lobby.send_authoritative_sample_for_test({"movementMode":"RUN"}, 1080), "authoritative movement publishes at 12.5Hz boundary")
	_expect(packets.size() == 1, "one eligible sample produces one packet")
	if packets.size() == 1:
		var packet := packets[0]
		_expect(packet.get("type") == "PLAYER_STATE", "packet type")
		_expect(packet.get("locomotion") == "RUN", "packet locomotion")
		var pos = packet.get("position")
		_expect(pos is Array and pos.size() == 3 and absf(float(pos[0]) - 4.0) < 0.001 and absf(float(pos[2]) + 2.0) < 0.001, "packet carries final local transform")
	var d := lobby.diagnostic_snapshot()
	_expect(int(d.get("lastStateSentSeq", 0)) == 1, "sent sequence advances")
	_expect(int(d.get("stateSendSuccesses", 0)) == 1, "send success is observable")
	root.queue_free()
	call_deferred("_finish")

func _capture(payload: Dictionary) -> bool:
	packets.append(payload.duplicate(true))
	return true

func _expect(value: bool, label: String) -> void:
	if not value:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("POCKETPT_MULTIPLAYER_SYNC_CONTRACT: PASS")
		quit(0)
		return
	for failure in failures:
		push_error("POCKETPT_MULTIPLAYER_SYNC_CONTRACT: %s" % failure)
	quit(1)
