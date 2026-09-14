extends SceneTree

const PlayerScript = preload("res://player.gd")
const LobbyScript = preload("res://scripts/pocketpt/pocketpt_lobby_client.gd")
const RemoteAvatarLoaderScript = preload("res://scripts/pocketpt/pocketpt_remote_avatar_loader.gd")
const LocomotionAnimatorScript = preload("res://scripts/pocketpt/pocketpt_locomotion_animator.gd")

var failures: Array[String] = []
var player: GymPlayerController
var client: PocketPTGameClient
var animator: PocketPTLocomotionAnimator
var lobby: PocketPTLobbyClient
var remote_container: Node3D
var remote_loader: PocketPTRemoteAvatarLoader

func _initialize() -> void:
	player = PlayerScript.new()
	player.name = "player"
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	player.add_child(collision)
	var spring_arm := SpringArm3D.new()
	spring_arm.name = "SpringArm3D"
	player.add_child(spring_arm)
	var agent := NavigationAgent3D.new()
	agent.name = "NavigationAgent3D"
	player.add_child(agent)
	var avatar_anchor := Node3D.new()
	avatar_anchor.name = "avataranchor"
	player.add_child(avatar_anchor)
	root.add_child(player)

	client = PocketPTGameClient.new()
	root.add_child(client)
	animator = LocomotionAnimatorScript.new()
	root.add_child(animator)
	remote_container = Node3D.new()
	remote_container.name = "RemotePlayers"
	root.add_child(remote_container)
	remote_loader = RemoteAvatarLoaderScript.new()
	root.add_child(remote_loader)
	lobby = LobbyScript.new()
	root.add_child(lobby)
	lobby.bind(client, player, animator, remote_container, remote_loader)
	call_deferred("_run")

func _run() -> void:
	_test_remote_avatar_contract()
	_test_local_final_state()
	_test_snapshot_state_leave_reconnect_shape()

	if failures.is_empty():
		print("POCKETPT_MULTIPLAYER_TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("POCKETPT_MULTIPLAYER_TEST: FAIL (%d)" % failures.size())
		quit(1)

func _test_remote_avatar_contract() -> void:
	var version := "0123456789abcdef0123456789abcdef"
	var valid := {
		"avatarId": "avatar-b",
		"profileVersion": version,
		"format": "glb",
		"assetUrl": "/api/game/lobby/players/presence-b/avatar?version=" + version
	}
	_expect(remote_loader.validate_remote_descriptor(valid).is_empty(), "same-room lobby avatar descriptor accepted")
	var wrong_path := valid.duplicate(true)
	wrong_path["assetUrl"] = "/api/game/avatar/asset?version=" + version
	_expect(remote_loader.validate_remote_descriptor(wrong_path) == "REMOTE_AVATAR_URL_INVALID", "local avatar endpoint cannot masquerade as remote avatar endpoint")
	var wrong_version := valid.duplicate(true)
	wrong_version["assetUrl"] = "/api/game/lobby/players/presence-b/avatar?version=ffffffffffffffffffffffffffffffff"
	_expect(remote_loader.validate_remote_descriptor(wrong_version) == "REMOTE_AVATAR_URL_INVALID", "remote avatar URL version must match descriptor")

func _test_local_final_state() -> void:
	player.global_position = Vector3(1.25, 0.76, -3.5)
	player.global_rotation.y = 0.2
	player.avatar_anchor.rotation.y = 0.3
	player.actual_horizontal_displacement = 0.01
	animator.current_state = &"WALK"
	var state := lobby.build_local_state_for_test()
	_expect(state.get("type") == "PLAYER_STATE", "local network packet uses PLAYER_STATE contract")
	_expect(int(state.get("seq", 0)) == 1, "local state starts after server's initial seq zero")
	var position = state.get("position")
	_expect(position is Array and position.size() == 3, "local state publishes 3D final transform")
	if position is Array and position.size() == 3:
		_expect(absf(float(position[0]) - 1.25) < 0.0001 and absf(float(position[1]) - 0.76) < 0.0001 and absf(float(position[2]) + 3.5) < 0.0001, "network position comes from final CharacterBody global position")
	_expect(absf(float(state.get("yaw", 0.0)) - 0.5) < 0.0001, "network yaw includes controller plus visual-facing yaw")
	_expect(state.get("locomotion") == "WALK", "network locomotion comes from proven local animator")

func _test_snapshot_state_leave_reconnect_shape() -> void:
	var self_player := _player_record("self-presence", "member-a", "Player A", [1.0, 0.76, 1.0], 0.0, "IDLE", 0)
	var remote_player := _player_record("remote-presence", "member-b", "Player B", [4.0, 0.76, 2.0], 0.4, "WALK", 0)
	var snapshot := {
		"type": "ROOM_SNAPSHOT",
		"protocolVersion": 1,
		"roomId": "lions_den",
		"selfPresenceId": "self-presence",
		"players": [self_player, remote_player]
	}
	_expect(lobby.accept_server_message_for_test(snapshot), "room snapshot accepted")
	var diagnostics := lobby.diagnostic_snapshot()
	_expect(diagnostics.get("selfPresenceId") == "self-presence", "self presence bound from authoritative snapshot")
	_expect(int(diagnostics.get("roomPlayerCount", 0)) == 2, "room snapshot counts both players")
	_expect(int(diagnostics.get("remotePlayerCount", 0)) == 1, "local player is not spawned as a remote clone")
	var remote := lobby.remote_player_for_test("remote-presence")
	_expect(remote != null, "remote player puppet spawned")
	if remote == null:
		return
	_expect(remote.member_id == "member-b", "remote identity is server-stamped member identity")
	_expect(remote.last_sequence == 0, "initial remote state sequence accepted")
	_expect(remote.global_position.distance_to(Vector3(4.0, 0.76, 2.0)) < 0.0001, "snapshot snaps remote to authoritative initial position")

	var stale := {
		"type": "PLAYER_STATE", "protocolVersion": 1, "roomId": "lions_den",
		"presenceId": "remote-presence", "memberId": "member-b",
		"state": {"seq": 0, "position": [99.0, 0.76, 99.0], "yaw": 2.0, "locomotion": "RUN"}
	}
	_expect(lobby.accept_server_message_for_test(stale), "stale network packet is safely ignored")
	_expect(remote.target_position.distance_to(Vector3(4.0, 0.76, 2.0)) < 0.0001, "stale sequence cannot move remote avatar")

	var newer := {
		"type": "PLAYER_STATE", "protocolVersion": 1, "roomId": "lions_den",
		"presenceId": "remote-presence", "memberId": "member-b",
		"state": {"seq": 1, "position": [8.0, 0.76, 2.0], "yaw": 1.0, "locomotion": "RUN"}
	}
	_expect(lobby.accept_server_message_for_test(newer), "newer network state accepted")
	_expect(remote.last_sequence == 1 and remote.target_position.distance_to(Vector3(8.0, 0.76, 2.0)) < 0.0001, "new state updates remote target and sequence")
	var before := remote.global_position
	remote._process(0.04)
	_expect(remote.global_position.x > before.x and remote.global_position.x < remote.target_position.x, "remote transform interpolates instead of teleporting")

	var leave := {"type": "PLAYER_LEFT", "protocolVersion": 1, "roomId": "lions_den", "presenceId": "remote-presence", "reason": "DISCONNECTED"}
	_expect(lobby.accept_server_message_for_test(leave), "PLAYER_LEFT accepted")
	_expect(lobby.remote_player_for_test("remote-presence") == null, "PLAYER_LEFT despawns remote puppet")
	_expect(int(lobby.diagnostic_snapshot().get("remotePlayerCount", 0)) == 0, "remote count returns to zero after leave")

	var rejoined := _player_record("remote-presence-2", "member-b", "Player B", [2.0, 0.76, 5.0], -0.5, "IDLE", 0)
	var join := {"type": "PLAYER_JOINED", "protocolVersion": 1, "roomId": "lions_den", "player": rejoined}
	_expect(lobby.accept_server_message_for_test(join), "reconnected player join accepted")
	_expect(lobby.remote_player_for_test("remote-presence-2") != null, "reconnect creates one new authoritative presence")
	_expect(lobby.remote_player_for_test("remote-presence") == null, "old presence is not resurrected as a ghost")
	_expect(int(lobby.diagnostic_snapshot().get("remotePlayerCount", 0)) == 1, "reconnect leaves exactly one remote player")

func _player_record(presence_id: String, member_id: String, display_name: String, position: Array, yaw: float, locomotion: String, seq: int) -> Dictionary:
	return {
		"presenceId": presence_id,
		"member": {"id": member_id, "displayName": display_name},
		"avatar": null,
		"state": {"position": position, "yaw": yaw, "locomotion": locomotion, "seq": seq}
	}

func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
