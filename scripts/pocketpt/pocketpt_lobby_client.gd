class_name PocketPTLobbyClient
extends Node

signal multiplayer_state_changed(state: Dictionary)
signal remote_player_spawned(presence_id: String)
signal remote_player_despawned(presence_id: String)

const RemotePlayerScript = preload("res://scripts/pocketpt/pocketpt_remote_player.gd")
const PROTOCOL_VERSION := 1
const ROOM_ID := "lions_den"
const CONFIG_PATH := "/api/game/lobby/config"
const SEND_INTERVAL_SECONDS := 0.08
const SEND_INTERVAL_MS := 80
const HEARTBEAT_SEND_INTERVAL_MS := 500
const RECONNECT_DELAY_MS := 1200
const DIAGNOSTIC_VERSION := 1
const DIAGNOSTIC_PUBLISH_INTERVAL_MS := 250
const VALID_LOCOMOTION := ["IDLE", "WALK", "RUN", "STOP", "ACTION_OVERRIDE"]

var multiplayer_state: Dictionary = {
	"transport": "WEB_SOCKET",
	"wsUrl": "",
	"connectionState": "IDLE",
	"roomId": ROOM_ID,
	"selfPresenceId": "",
	"localMemberId": "",
	"roomPlayerCount": 0,
	"remotePlayerCount": 0,
	"remoteAvatarsLoaded": 0,
	"lastStateSentSeq": 0,
	"lastStateReceivedSeq": 0,
	"lastStateAgeMs": -1,
	"stateSendAttempts": 0,
	"stateSendSuccesses": 0,
	"stateReceiveCount": 0,
	"remoteMoveCount": 0,
	"connectionGeneration": 0,
	"lastStateSendAtMs": -1,
	"reconnectCount": 0,
	"firstFailure": "NONE",
	"lastError": ""
}

var _client: PocketPTGameClient
var _player: GymPlayerController
var _locomotion_animator: PocketPTLocomotionAnimator
var _remote_container: Node3D
var _remote_avatar_loader: PocketPTRemoteAvatarLoader
var _remote_players: Dictionary = {}
var _browser_callback = null
var _send_accumulator := 0.0
var _local_sequence := 0
var _connected := false
var _snapshot_received := false
var _connect_in_flight := false
var _allow_reconnect := true
var _intentional_close := false
var _next_reconnect_at_ms := 0
var _last_state_received_at_ms := -1
var _last_state_sent_at_ms := -1
# Throttle the transport on ATTEMPTS, not acknowledgements. The physical Web
# failure proved socket.send() can succeed while JavaScriptBridge.eval() does
# not round-trip a boolean success value. An acknowledgement failure must never
# turn into an unbounded resend loop / STATE_RATE_LIMIT flood.
var _last_state_attempt_at_ms := -1
var _last_state_attempt_seq := 0
var _connection_generation := 0
var _transport_sender_for_test: Callable = Callable()
var _diagnostic_browser_callback = null
var _diagnostic_request_id := ""
var _diagnostic_sequence := 0
var _diagnostic_next_send_at_ms := 0
var _diagnostic_ready_since_ms := -1

func bind(
	client: PocketPTGameClient,
	player: GymPlayerController,
	locomotion_animator: PocketPTLocomotionAnimator,
	remote_container: Node3D,
	remote_avatar_loader: PocketPTRemoteAvatarLoader
) -> void:
	_client = client
	_player = player
	_locomotion_animator = locomotion_animator
	_remote_container = remote_container
	_remote_avatar_loader = remote_avatar_loader
	if _client != null:
		_client.bootstrap_accepted.connect(_on_bootstrap_accepted)
		_client.session_ending.connect(_on_session_ending)
	if _remote_avatar_loader != null:
		_remote_avatar_loader.remote_avatar_mounted.connect(_on_remote_avatar_mounted)
		_remote_avatar_loader.remote_avatar_failed.connect(_on_remote_avatar_failed)
	if _player == null:
		_set_first_failure("LOCAL_PLAYER_BIND", "PLAYER_CONTROLLER_MISSING")
	else:
		# The local CharacterBody physics loop is already physically proven on phone.
		# Drive state publication from that authoritative physics sample instead of
		# relying solely on this optional Node's frame callback.
		if not _player.locomotion_sampled.is_connected(_on_local_locomotion_sampled):
			_player.locomotion_sampled.connect(_on_local_locomotion_sampled)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_install_multiplayer_diagnostic_receiver()

func _process(_delta: float) -> void:
	var now_ms := Time.get_ticks_msec()
	# A low-frequency heartbeat protects idle/facing state and also proves that
	# transport is alive if physics samples temporarily stop. Moving players are
	# published by _on_local_locomotion_sampled at the normal 12.5 Hz cap.
	if _connected and _snapshot_received and (_last_state_attempt_at_ms < 0 or now_ms - _last_state_attempt_at_ms >= HEARTBEAT_SEND_INTERVAL_MS):
		_send_local_state(now_ms)
	elif _allow_reconnect and not _connect_in_flight and _next_reconnect_at_ms > 0 and now_ms >= _next_reconnect_at_ms:
		_next_reconnect_at_ms = 0
		_start_browser_lobby(true)
	if _last_state_received_at_ms >= 0:
		multiplayer_state["lastStateAgeMs"] = maxi(0, now_ms - _last_state_received_at_ms)
	if not _diagnostic_request_id.is_empty() and now_ms >= _diagnostic_next_send_at_ms:
		_report_multiplayer_diagnostic(now_ms)

func _on_local_locomotion_sampled(sample: Dictionary) -> void:
	_maybe_send_authoritative_sample(sample, Time.get_ticks_msec())

func _maybe_send_authoritative_sample(_sample: Dictionary, now_ms: int) -> bool:
	if not _connected or not _snapshot_received:
		return false
	if _last_state_attempt_at_ms >= 0 and now_ms - _last_state_attempt_at_ms < SEND_INTERVAL_MS:
		return false
	return _send_local_state(now_ms)

func _install_multiplayer_diagnostic_receiver() -> void:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return
	var window = JavaScriptBridge.get_interface("window")
	if window == null:
		return
	_diagnostic_browser_callback = JavaScriptBridge.create_callback(_on_multiplayer_diagnostic_browser_message)
	window.__pocketptMultiplayerDiagnosticCallback = _diagnostic_browser_callback
	JavaScriptBridge.eval("""
(() => {
	if (window.__pocketptMultiplayerDiagnosticRemove) window.__pocketptMultiplayerDiagnosticRemove();
	const handler = (event) => {
		if (event.source !== window.parent || event.origin !== window.location.origin) return;
		const data = event.data;
		if (!data || data.type !== "POCKETPT_GODOT_BRIDGE" || data.event !== "DIAGNOSTICS_REQUEST") return;
		const callback = window.__pocketptMultiplayerDiagnosticCallback;
		if (typeof callback !== "function") return;
		try { callback(JSON.stringify(data)); } catch (_error) {}
	};
	window.addEventListener("message", handler);
	window.__pocketptMultiplayerDiagnosticRemove = () => {
		window.removeEventListener("message", handler);
		delete window.__pocketptMultiplayerDiagnosticRemove;
	};
	return true;
})()
""")

func _on_multiplayer_diagnostic_browser_message(args: Array) -> void:
	if args.is_empty() or not args[0] is String:
		return
	var message = JSON.parse_string(args[0])
	if not message is Dictionary:
		return
	if message.get("type") != "POCKETPT_GODOT_BRIDGE" or str(message.get("event", "")) != "DIAGNOSTICS_REQUEST":
		return
	if int(message.get("protocolVersion", 0)) != PROTOCOL_VERSION or int(message.get("diagnosticVersion", 0)) != DIAGNOSTIC_VERSION:
		return
	var request_id := str(message.get("requestId", "")).strip_edges()
	if request_id.is_empty() or request_id.length() > 128:
		return
	_diagnostic_request_id = request_id
	_diagnostic_sequence = 0
	_diagnostic_ready_since_ms = -1
	_report_multiplayer_diagnostic(Time.get_ticks_msec())

func _report_multiplayer_diagnostic(now_ms: int) -> void:
	if _diagnostic_request_id.is_empty():
		return
	_diagnostic_sequence += 1
	var payload := _build_multiplayer_diagnostic_payload(now_ms, _diagnostic_request_id, _diagnostic_sequence)
	_diagnostic_next_send_at_ms = now_ms + DIAGNOSTIC_PUBLISH_INTERVAL_MS
	_post_multiplayer_diagnostic_to_parent(payload)

func _build_multiplayer_diagnostic_payload(now_ms: int, request_id: String, sequence: int) -> Dictionary:
	var snapshot := diagnostic_snapshot()
	var normalized_connection := _normalized_diagnostic_connection(str(snapshot.get("connectionState", "IDLE")))
	if normalized_connection == "READY":
		if _diagnostic_ready_since_ms < 0:
			_diagnostic_ready_since_ms = now_ms
	else:
		_diagnostic_ready_since_ms = -1
	var room_ready_age: Variant = null
	if _diagnostic_ready_since_ms >= 0:
		room_ready_age = maxi(0, now_ms - _diagnostic_ready_since_ms)
	var last_state_age_value := int(snapshot.get("lastStateAgeMs", -1))
	var last_state_age: Variant = null if last_state_age_value < 0 else last_state_age_value
	var receive_count := maxi(0, int(snapshot.get("stateReceiveCount", 0)))
	var remote_move_count := maxi(0, int(snapshot.get("remoteMoveCount", 0)))
	var remote_movement_expected := _remote_movement_expected()
	return {
		"type": "POCKETPT_GODOT_BRIDGE",
		"event": "MULTIPLAYER_DIAGNOSTIC",
		"protocolVersion": PROTOCOL_VERSION,
		"diagnosticVersion": DIAGNOSTIC_VERSION,
		"requestId": request_id,
		"sequence": sequence,
		"multiplayer": {
			"connectionState": normalized_connection,
			"roomId": _safe_diagnostic_identifier(snapshot.get("roomId", ROOM_ID), ROOM_ID),
			"selfPresenceId": _safe_diagnostic_identifier(snapshot.get("selfPresenceId", ""), "NOT_REPORTED"),
			"localMemberId": _safe_diagnostic_identifier(snapshot.get("localMemberId", ""), "NOT_REPORTED"),
			"roomPlayerCount": maxi(0, int(snapshot.get("roomPlayerCount", 0))),
			"remotePlayerCount": maxi(0, int(snapshot.get("remotePlayerCount", 0))),
			"remoteAvatarsLoaded": maxi(0, int(snapshot.get("remoteAvatarsLoaded", 0))),
			"stateSendAttempts": maxi(0, int(snapshot.get("stateSendAttempts", 0))),
			"stateSendSuccesses": maxi(0, int(snapshot.get("stateSendSuccesses", 0))),
			"lastSentSeq": maxi(0, int(snapshot.get("lastStateSentSeq", 0))),
			"statePacketsReceived": receive_count,
			"lastReceivedSeq": maxi(0, int(snapshot.get("lastStateReceivedSeq", 0))),
			"lastStateAgeMs": last_state_age,
			"roomReadyAgeMs": room_ready_age,
			"remoteMovementApplies": receive_count,
			"reconnectCount": maxi(0, int(snapshot.get("reconnectCount", 0))),
			"connectionGeneration": maxi(0, int(snapshot.get("connectionGeneration", 0))),
			"snapshotReceived": normalized_connection == "READY" and not str(snapshot.get("selfPresenceId", "")).is_empty(),
			"localPhysicallyMoving": _player != null and _player.actual_horizontal_displacement > 0.0005,
			"remoteMovementExpected": remote_movement_expected,
			"oppositePlayerMoving": remote_movement_expected,
			"remoteTargetsApplied": receive_count,
			"remotePuppetMoves": remote_move_count,
			"lastError": _safe_diagnostic_identifier(snapshot.get("lastError", ""), "NONE")
		}
	}

func build_multiplayer_diagnostic_payload_for_test(now_ms: int, request_id: String = "test-request", sequence: int = 1) -> Dictionary:
	return _build_multiplayer_diagnostic_payload(now_ms, request_id, sequence)

func _normalized_diagnostic_connection(value: String) -> String:
	match value:
		"ACTIVE":
			return "READY"
		"CLOSED", "SESSION_ENDED":
			return "CLOSED"
		"SESSION_REPLACED":
			return "ERROR"
		_:
			return "CONNECTING"

func _remote_movement_expected() -> bool:
	for value in _remote_players.values():
		var remote := value as PocketPTRemotePlayer
		if remote == null or not is_instance_valid(remote):
			continue
		if remote.global_position.distance_to(remote.target_position) > 0.01:
			return true
		if remote.locomotion in ["WALK", "RUN"]:
			return true
	return false

func _safe_diagnostic_identifier(value: Variant, fallback: String) -> String:
	var raw := str(value).strip_edges()
	if raw.is_empty():
		return fallback
	var result := ""
	for index in raw.length():
		var code := raw.unicode_at(index)
		var character := raw.substr(index, 1)
		var allowed := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or character in ["_", ".", ":", "-"]
		result += character if allowed else "_"
	return result.left(128)

func _post_multiplayer_diagnostic_to_parent(payload: Dictionary) -> bool:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return false
	var serialized_literal := JSON.stringify(JSON.stringify(payload))
	return JavaScriptBridge.eval("""
(() => {
	try {
		if (window.parent === window || !window.location.origin) return false;
		window.parent.postMessage(JSON.parse(%s), window.location.origin);
		return true;
	} catch (_error) { return false; }
})()
""" % serialized_literal) == true

func _exit_tree() -> void:
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		JavaScriptBridge.eval("window.__pocketptMultiplayerDiagnosticRemove && window.__pocketptMultiplayerDiagnosticRemove();")

func diagnostic_snapshot() -> Dictionary:
	var snapshot := multiplayer_state.duplicate(true)
	snapshot["remotePlayerCount"] = _remote_players.size()
	snapshot["remoteAvatarsLoaded"] = _count_loaded_remote_avatars()
	if _last_state_received_at_ms >= 0:
		snapshot["lastStateAgeMs"] = maxi(0, Time.get_ticks_msec() - _last_state_received_at_ms)
	return snapshot

func accept_server_message_for_test(payload: Dictionary) -> bool:
	return _ingest_server_message(payload)

func build_local_state_for_test() -> Dictionary:
	return _build_local_state(_local_sequence + 1)

func remote_player_for_test(presence_id: String) -> PocketPTRemotePlayer:
	return _remote_players.get(presence_id) as PocketPTRemotePlayer

func set_transport_sender_for_test(sender: Callable) -> void:
	_transport_sender_for_test = sender

func set_transport_ready_for_test(value: bool, last_send_ms: int = -1) -> void:
	_connected = value
	_snapshot_received = value
	_last_state_sent_at_ms = last_send_ms
	_last_state_attempt_at_ms = last_send_ms

func send_authoritative_sample_for_test(sample: Dictionary, now_ms: int) -> bool:
	return _maybe_send_authoritative_sample(sample, now_ms)

func last_state_attempt_sequence_for_test() -> int:
	return _last_state_attempt_seq

func set_connection_generation_for_test(value: int) -> void:
	_connection_generation = maxi(0, value)
	multiplayer_state["connectionGeneration"] = _connection_generation

func accept_browser_event_for_test(event: Dictionary) -> void:
	_on_browser_lobby_event([JSON.stringify(event)])

func _on_bootstrap_accepted(payload: Dictionary) -> void:
	_shutdown_connection(false)
	_clear_remote_players()
	_local_sequence = 0
	_send_accumulator = 0.0
	_allow_reconnect = true
	_intentional_close = false
	_next_reconnect_at_ms = 0
	_last_state_received_at_ms = -1
	_last_state_sent_at_ms = -1
	_last_state_attempt_at_ms = -1
	_last_state_attempt_seq = 0
	var member = payload.get("member")
	if not member is Dictionary or str(member.get("id", "")).strip_edges().is_empty():
		_set_first_failure("BOOTSTRAP", "MEMBER_MISSING")
		return
	multiplayer_state["localMemberId"] = str(member.get("id", ""))
	multiplayer_state["connectionState"] = "BOOTSTRAP_READY"
	multiplayer_state["firstFailure"] = "NONE"
	multiplayer_state["lastError"] = ""
	multiplayer_state["selfPresenceId"] = ""
	multiplayer_state["roomPlayerCount"] = 0
	multiplayer_state["remotePlayerCount"] = 0
	multiplayer_state["remoteAvatarsLoaded"] = 0
	multiplayer_state["lastStateSentSeq"] = 0
	multiplayer_state["lastStateReceivedSeq"] = 0
	multiplayer_state["lastStateAgeMs"] = -1
	multiplayer_state["stateSendAttempts"] = 0
	multiplayer_state["stateSendSuccesses"] = 0
	multiplayer_state["stateReceiveCount"] = 0
	multiplayer_state["remoteMoveCount"] = 0
	multiplayer_state["lastStateSendAtMs"] = -1
	_publish()
	if not OS.has_feature("web"):
		multiplayer_state["transport"] = "WEB_ONLY"
		multiplayer_state["connectionState"] = "DESKTOP_DISABLED"
		_publish()
		return
	_start_browser_lobby(false)

func _start_browser_lobby(is_reconnect: bool) -> void:
	if _connect_in_flight or _connected:
		return
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		_set_first_failure("LOBBY_CONFIG", "JAVASCRIPT_BRIDGE_UNAVAILABLE")
		return
	var window = JavaScriptBridge.get_interface("window")
	if window == null:
		_set_first_failure("LOBBY_CONFIG", "WINDOW_UNAVAILABLE")
		return
	_connect_in_flight = true
	_connection_generation += 1
	multiplayer_state["connectionGeneration"] = _connection_generation
	if is_reconnect:
		multiplayer_state["reconnectCount"] = int(multiplayer_state.get("reconnectCount", 0)) + 1
	multiplayer_state["connectionState"] = "FETCHING_CONFIG"
	_publish()
	_browser_callback = JavaScriptBridge.create_callback(_on_browser_lobby_event)
	window.__pocketptGodotLobbyCallback = _browser_callback
	var config_literal := JSON.stringify(CONFIG_PATH)
	var script := """
(() => {
	const callback = window.__pocketptGodotLobbyCallback;
	const generation = %d;
	if (typeof callback !== "function") return false;
	const send = (value) => callback(JSON.stringify(Object.assign({generation}, value)));
	fetch(%s, {
		method: "GET",
		credentials: "same-origin",
		cache: "no-store",
		headers: {"Accept": "application/json"}
	})
	.then(async (response) => {
		const body = await response.text();
		let parsed = null;
		try { parsed = JSON.parse(body); } catch (_error) {}
		if (!response.ok || !parsed || parsed.ok !== true || !parsed.data) {
			send({kind: "config_error", status: response.status, body});
			return;
		}
		const config = parsed.data;
		const path = String(config.websocketPath || "");
		if (!path.startsWith("/")) {
			send({kind: "config_error", status: 0, errorCode: "LOBBY_WS_PATH_INVALID"});
			return;
		}
		const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
		const wsUrl = protocol + "//" + window.location.host + path;
		send({kind: "config", config, wsUrl});
		try {
			if (window.__pocketptGodotLobbySocket) {
				try { window.__pocketptGodotLobbySocket.close(1000, "Replacing lobby socket"); } catch (_error) {}
			}
			const socket = new WebSocket(wsUrl);
			window.__pocketptGodotLobbySocket = socket;
			socket.addEventListener("open", () => send({kind: "open"}));
			socket.addEventListener("message", (event) => send({kind: "message", data: String(event.data || "")}));
			socket.addEventListener("close", (event) => send({kind: "close", code: event.code, reason: event.reason || ""}));
			socket.addEventListener("error", () => send({kind: "socket_error"}));
		} catch (_error) {
			send({kind: "socket_error"});
		}
	})
	.catch(() => send({kind: "config_error", status: 0, errorCode: "LOBBY_CONFIG_REQUEST_FAILED"}));
	return true;
})()
""" % [_connection_generation, config_literal]
	if JavaScriptBridge.eval(script) != true:
		_connect_in_flight = false
		_set_first_failure("LOBBY_CONFIG", "LOBBY_CONFIG_REQUEST_FAILED")

func _on_browser_lobby_event(args: Array) -> void:
	if args.is_empty() or not args[0] is String:
		return
	var event = JSON.parse_string(args[0])
	if not event is Dictionary:
		return
	# Ignore late events from a socket that was replaced by a newer reconnect.
	# Without this generation guard an old close event can freeze the newly
	# connected room while leaving its already-mounted remote avatar visible.
	if int(event.get("generation", -1)) != _connection_generation:
		return
	match str(event.get("kind", "")):
		"config":
			_handle_config_event(event)
		"config_error":
			_connect_in_flight = false
			var status := int(event.get("status", 0))
			if status == 401 and _client != null:
				_allow_reconnect = false
				_client.invalidate_session("ARENA_SESSION_INVALID")
			else:
				_set_first_failure("LOBBY_CONFIG", str(event.get("errorCode", "HTTP_%d" % status)))
				_schedule_reconnect()
		"open":
			_connect_in_flight = false
			_connected = true
			_snapshot_received = false
			multiplayer_state["connectionState"] = "CONNECTED_WAITING_SNAPSHOT"
			_publish()
		"message":
			var payload = JSON.parse_string(str(event.get("data", "")))
			if payload is Dictionary:
				_ingest_server_message(payload)
			else:
				_set_first_failure("STATE_RECEIVE", "INVALID_SERVER_JSON")
		"state_send_result":
			_handle_state_send_result(event)
		"socket_error":
			if not _connected:
				_connect_in_flight = false
				_set_first_failure("WS_CONNECT", "SOCKET_ERROR")
		"close":
			_handle_socket_close(int(event.get("code", 0)), str(event.get("reason", "")))

func _handle_config_event(event: Dictionary) -> void:
	var config = event.get("config")
	if not config is Dictionary:
		_connect_in_flight = false
		_set_first_failure("LOBBY_CONFIG", "CONFIG_INVALID")
		return
	if int(config.get("protocolVersion", 0)) != PROTOCOL_VERSION or str(config.get("roomId", "")) != ROOM_ID:
		_connect_in_flight = false
		_set_first_failure("LOBBY_CONFIG", "CONFIG_CONTRACT_MISMATCH")
		return
	if str(config.get("websocketPath", "")) != "/api/game/lobby/ws":
		_connect_in_flight = false
		_set_first_failure("LOBBY_CONFIG", "CONFIG_WS_PATH_MISMATCH")
		return
	multiplayer_state["wsUrl"] = str(event.get("wsUrl", ""))
	multiplayer_state["connectionState"] = "WS_CONNECTING"
	_publish()

func _handle_socket_close(code: int, reason: String) -> void:
	_connected = false
	_snapshot_received = false
	_connect_in_flight = false
	multiplayer_state["connectionState"] = "CLOSED"
	multiplayer_state["lastError"] = "%d %s" % [code, reason]
	_last_state_received_at_ms = -1
	multiplayer_state["lastStateAgeMs"] = -1
	# A dead transport must never leave a frozen avatar that looks live. The
	# authoritative reconnect snapshot will respawn current presences.
	_clear_remote_players()
	multiplayer_state["selfPresenceId"] = ""
	multiplayer_state["roomPlayerCount"] = 0
	_publish()
	if _intentional_close:
		return
	if code == 4001:
		_allow_reconnect = false
		multiplayer_state["connectionState"] = "SESSION_REPLACED"
		multiplayer_state["lastError"] = "SESSION_REPLACED"
		_publish()
		return
	if code in [4003, 4004]:
		_allow_reconnect = false
		if _client != null:
			_client.invalidate_session("ARENA_SESSION_INVALID" if code == 4004 else "ARENA_SESSION_EXPIRED")
		return
	_schedule_reconnect()

func _ingest_server_message(payload: Dictionary) -> bool:
	var message_type := str(payload.get("type", ""))
	if message_type.is_empty():
		_set_first_failure("STATE_RECEIVE", "MESSAGE_TYPE_MISSING")
		return false
	if message_type != "ERROR":
		if int(payload.get("protocolVersion", 0)) != PROTOCOL_VERSION or str(payload.get("roomId", "")) != ROOM_ID:
			_set_first_failure("STATE_RECEIVE", "SERVER_CONTRACT_MISMATCH")
			return false
	match message_type:
		"ROOM_SNAPSHOT":
			return _handle_room_snapshot(payload)
		"PLAYER_JOINED":
			var player_record = payload.get("player")
			if not player_record is Dictionary:
				_set_first_failure("REMOTE_PLAYER_SPAWN", "PLAYER_RECORD_INVALID")
				return false
			if not _spawn_or_update_remote(player_record, true):
				return false
			_update_room_counts_from_known()
			return true
		"PLAYER_STATE":
			return _handle_player_state(payload)
		"PLAYER_LEFT":
			var presence_id := str(payload.get("presenceId", ""))
			if presence_id.is_empty():
				_set_first_failure("LEAVE_DESPAWN", "PRESENCE_ID_MISSING")
				return false
			_despawn_remote(presence_id)
			_update_room_counts_from_known()
			return true
		"SESSION_REPLACED":
			_allow_reconnect = false
			multiplayer_state["connectionState"] = "SESSION_REPLACED"
			multiplayer_state["lastError"] = "SESSION_REPLACED"
			_publish()
			return true
		"ERROR":
			return _handle_server_error(payload)
		_:
			_set_first_failure("STATE_RECEIVE", "UNSUPPORTED_MESSAGE_%s" % message_type)
			return false

func _handle_room_snapshot(payload: Dictionary) -> bool:
	var self_presence_id := str(payload.get("selfPresenceId", ""))
	var players = payload.get("players")
	if self_presence_id.is_empty() or not players is Array:
		_set_first_failure("ROOM_SNAPSHOT", "SNAPSHOT_INVALID")
		return false
	multiplayer_state["selfPresenceId"] = self_presence_id
	var present_remote_ids: Dictionary = {}
	for value in players:
		if not value is Dictionary:
			continue
		var record: Dictionary = value
		var presence_id := str(record.get("presenceId", ""))
		if presence_id == self_presence_id:
			continue
		if _spawn_or_update_remote(record, true):
			present_remote_ids[presence_id] = true
	for existing_id in _remote_players.keys():
		if not present_remote_ids.has(existing_id):
			_despawn_remote(str(existing_id))
	_snapshot_received = true
	_connected = true
	multiplayer_state["connectionState"] = "ACTIVE"
	multiplayer_state["roomPlayerCount"] = players.size()
	multiplayer_state["remotePlayerCount"] = _remote_players.size()
	multiplayer_state["remoteAvatarsLoaded"] = _count_loaded_remote_avatars()
	_publish()
	_send_local_state()
	return true

func _handle_player_state(payload: Dictionary) -> bool:
	var presence_id := str(payload.get("presenceId", ""))
	if presence_id.is_empty() or presence_id == str(multiplayer_state.get("selfPresenceId", "")):
		return false
	var remote := _remote_players.get(presence_id) as PocketPTRemotePlayer
	if remote == null:
		_set_first_failure("STATE_RECEIVE", "REMOTE_PRESENCE_UNKNOWN")
		return false
	var state = payload.get("state")
	if not state is Dictionary:
		_set_first_failure("STATE_RECEIVE", "REMOTE_STATE_INVALID")
		return false
	if not remote.apply_network_state(state):
		# Stale sequence numbers are expected to be ignored and are not a pipeline failure.
		if typeof(state.get("seq")) == TYPE_INT and int(state.get("seq")) <= remote.last_sequence:
			return true
		_set_first_failure("STATE_RECEIVE", "REMOTE_STATE_REJECTED")
		return false
	_last_state_received_at_ms = Time.get_ticks_msec()
	multiplayer_state["stateReceiveCount"] = int(multiplayer_state.get("stateReceiveCount", 0)) + 1
	multiplayer_state["lastStateReceivedSeq"] = maxi(int(multiplayer_state.get("lastStateReceivedSeq", 0)), remote.last_sequence)
	multiplayer_state["lastStateAgeMs"] = 0
	_publish()
	return true

func _spawn_or_update_remote(player_record: Dictionary, snap: bool) -> bool:
	var presence_id := str(player_record.get("presenceId", ""))
	if presence_id.is_empty():
		_set_first_failure("REMOTE_PLAYER_SPAWN", "PRESENCE_ID_MISSING")
		return false
	if presence_id == str(multiplayer_state.get("selfPresenceId", "")):
		return true
	var existing := _remote_players.get(presence_id) as PocketPTRemotePlayer
	if existing != null:
		var state = player_record.get("state")
		if state is Dictionary:
			existing.apply_network_state(state)
		return true
	if _remote_container == null or not is_instance_valid(_remote_container):
		_set_first_failure("REMOTE_PLAYER_SPAWN", "REMOTE_CONTAINER_MISSING")
		return false
	var remote := RemotePlayerScript.new() as PocketPTRemotePlayer
	remote.name = "Remote_%s" % _safe_node_name(presence_id)
	_remote_container.add_child(remote)
	if not remote.configure(player_record):
		remote.queue_free()
		_set_first_failure("REMOTE_PLAYER_SPAWN", "PLAYER_RECORD_INVALID")
		return false
	_remote_players[presence_id] = remote
	remote.remote_moved.connect(_on_remote_moved)
	remote_player_spawned.emit(presence_id)
	var avatar = player_record.get("avatar")
	if avatar is Dictionary and _remote_avatar_loader != null:
		if not _remote_avatar_loader.request_avatar(presence_id, remote.member_id, avatar, remote.visual_anchor):
			_set_first_failure("REMOTE_AVATAR_LOAD", "REMOTE_AVATAR_REQUEST_REJECTED")
	multiplayer_state["remotePlayerCount"] = _remote_players.size()
	_publish()
	return true

func _despawn_remote(presence_id: String) -> void:
	var remote := _remote_players.get(presence_id) as PocketPTRemotePlayer
	if remote == null:
		return
	if _remote_avatar_loader != null:
		_remote_avatar_loader.cancel_presence(presence_id)
	_remote_players.erase(presence_id)
	remote.queue_free()
	remote_player_despawned.emit(presence_id)
	multiplayer_state["remotePlayerCount"] = _remote_players.size()
	multiplayer_state["remoteAvatarsLoaded"] = _count_loaded_remote_avatars()
	_publish()

func _on_remote_avatar_mounted(presence_id: String, avatar_root: Node3D) -> void:
	var remote := _remote_players.get(presence_id) as PocketPTRemotePlayer
	if remote == null:
		if is_instance_valid(avatar_root):
			avatar_root.queue_free()
		return
	if not remote.bind_avatar_root(avatar_root):
		_set_first_failure("REMOTE_AVATAR_LOAD", remote.animation_binding_error)
		return
	multiplayer_state["remoteAvatarsLoaded"] = _count_loaded_remote_avatars()
	_publish()

func _on_remote_avatar_failed(presence_id: String, error_code: String) -> void:
	_set_first_failure("REMOTE_AVATAR_LOAD", "%s:%s" % [presence_id, error_code])
	if error_code == "ARENA_SESSION_INVALID" and _client != null:
		_allow_reconnect = false
		_client.invalidate_session("ARENA_SESSION_INVALID")

func _on_remote_moved(_presence_id: String) -> void:
	multiplayer_state["remoteMoveCount"] = int(multiplayer_state.get("remoteMoveCount", 0)) + 1

func _handle_state_send_result(event: Dictionary) -> void:
	var sequence := int(event.get("seq", 0))
	var ok: bool = event.get("ok") == true
	var error_code := str(event.get("errorCode", "WEBSOCKET_SEND_FAILED"))
	_record_state_send_result(sequence, ok, Time.get_ticks_msec(), error_code)

func _record_state_send_result(sequence: int, success: bool, acknowledged_at_ms: int, error_code: String = "") -> bool:
	if sequence <= 0 or sequence > _last_state_attempt_seq:
		return false
	if not success:
		_set_first_failure("STATE_SEND", error_code if not error_code.is_empty() else "WEBSOCKET_SEND_FAILED")
		return false
	# Browser callbacks can arrive out of order. Only the newest acknowledged
	# sequence advances authoritative diagnostics; duplicate/late acks are safe.
	if sequence <= _local_sequence:
		return true
	_local_sequence = sequence
	_last_state_sent_at_ms = acknowledged_at_ms
	multiplayer_state["lastStateSentSeq"] = _local_sequence
	multiplayer_state["stateSendSuccesses"] = int(multiplayer_state.get("stateSendSuccesses", 0)) + 1
	multiplayer_state["lastStateSendAtMs"] = _last_state_sent_at_ms
	_publish()
	return true

func _send_local_state(sent_at_ms: int = -1) -> bool:
	if not _connected or not _snapshot_received or _player == null:
		return false
	var attempt_at_ms := sent_at_ms if sent_at_ms >= 0 else Time.get_ticks_msec()
	# Rate-limit attempts before crossing JavaScriptBridge. This is deliberately
	# independent from acknowledgement success so a broken callback can never
	# produce thousands of socket.send() calls per second.
	if _last_state_attempt_at_ms >= 0 and attempt_at_ms - _last_state_attempt_at_ms < SEND_INTERVAL_MS:
		return false
	var next_sequence := _last_state_attempt_seq + 1
	var payload := _build_local_state(next_sequence)
	if payload.is_empty():
		_set_first_failure("STATE_SEND", "LOCAL_STATE_INVALID")
		return false
	_last_state_attempt_at_ms = attempt_at_ms
	_last_state_attempt_seq = next_sequence
	multiplayer_state["stateSendAttempts"] = int(multiplayer_state.get("stateSendAttempts", 0)) + 1
	if _transport_sender_for_test.is_valid():
		var sent := bool(_transport_sender_for_test.call(payload.duplicate(true)))
		return _record_state_send_result(next_sequence, sent, attempt_at_ms, "WEBSOCKET_SEND_FAILED")
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		# Desktop/headless has no browser transport. This is expected and must not
		# contaminate snapshot/receive diagnostics with a Web-only failure.
		return false
	var serialized_literal := JSON.stringify(JSON.stringify(payload))
	var script := """
(() => {
	const socket = window.__pocketptGodotLobbySocket;
	const callback = window.__pocketptGodotLobbyCallback;
	const generation = %d;
	const seq = %d;
	const report = (ok, errorCode = "") => {
		if (typeof callback !== "function") return;
		try { callback(JSON.stringify({generation, kind: "state_send_result", seq, ok, errorCode})); } catch (_error) {}
	};
	if (!socket || socket.readyState !== WebSocket.OPEN) {
		report(false, "SOCKET_NOT_OPEN");
		return "POCKETPT_SEND_RESULT_REPORTED";
	}
	try {
		socket.send(%s);
		report(true, "");
	} catch (_error) {
		report(false, "WEBSOCKET_SEND_FAILED");
	}
	return "POCKETPT_SEND_RESULT_REPORTED";
})()
""" % [_connection_generation, next_sequence, serialized_literal]
	var bridge_result = JavaScriptBridge.eval(script)
	# The callback is the send-success authority. The sentinel only detects a
	# script that failed before it could report. Never use JS boolean coercion as
	# transport truth again; that was the physical STATE_RATE_LIMIT regression.
	if str(bridge_result) != "POCKETPT_SEND_RESULT_REPORTED" and _local_sequence < next_sequence:
		_record_state_send_result(next_sequence, false, attempt_at_ms, "JAVASCRIPT_SEND_SCRIPT_FAILED")
		return false
	return true

func _build_local_state(sequence: int) -> Dictionary:
	if _player == null or sequence <= 0:
		return {}
	var yaw := _player.global_rotation.y
	if _player.fallback_visual != null and is_instance_valid(_player.fallback_visual) and _player.fallback_visual.visible:
		yaw += _player.fallback_visual.rotation.y
	elif _player.avatar_anchor != null and is_instance_valid(_player.avatar_anchor):
		yaw += _player.avatar_anchor.rotation.y
	yaw = wrapf(yaw, -PI, PI)
	var locomotion := "IDLE"
	if _locomotion_animator != null:
		locomotion = String(_locomotion_animator.current_state).to_upper()
	elif _player.actual_horizontal_displacement > 0.0005:
		locomotion = _player.locomotion_mode_name()
	if locomotion not in VALID_LOCOMOTION:
		locomotion = "IDLE"
	return {
		"type": "PLAYER_STATE",
		"seq": sequence,
		"position": [_player.global_position.x, _player.global_position.y, _player.global_position.z],
		"yaw": yaw,
		"locomotion": locomotion
	}

func _handle_server_error(payload: Dictionary) -> bool:
	var code := str(payload.get("code", "LOBBY_ERROR"))
	multiplayer_state["lastError"] = code
	_publish()
	if code in ["ARENA_SESSION_INVALID", "ARENA_SESSION_EXPIRED"]:
		_allow_reconnect = false
		if _client != null:
			_client.invalidate_session(code)
		return true
	if code == "STATE_RATE_LIMIT":
		_set_first_failure("STATE_SEND", code)
		return false
	_set_first_failure("STATE_RECEIVE", code)
	return false

func _schedule_reconnect() -> void:
	if not _allow_reconnect or _intentional_close:
		return
	_next_reconnect_at_ms = Time.get_ticks_msec() + RECONNECT_DELAY_MS
	multiplayer_state["connectionState"] = "RECONNECT_WAIT"
	_publish()

func _update_room_counts_from_known() -> void:
	multiplayer_state["remotePlayerCount"] = _remote_players.size()
	multiplayer_state["remoteAvatarsLoaded"] = _count_loaded_remote_avatars()
	multiplayer_state["roomPlayerCount"] = _remote_players.size() + (1 if not str(multiplayer_state.get("selfPresenceId", "")).is_empty() else 0)
	_publish()

func _count_loaded_remote_avatars() -> int:
	var count := 0
	for value in _remote_players.values():
		var remote := value as PocketPTRemotePlayer
		if remote != null and remote.avatar_loaded:
			count += 1
	return count

func _clear_remote_players() -> void:
	for presence_id in _remote_players.keys():
		if _remote_avatar_loader != null:
			_remote_avatar_loader.cancel_presence(str(presence_id))
		var remote := _remote_players[presence_id] as PocketPTRemotePlayer
		if remote != null and is_instance_valid(remote):
			remote.queue_free()
	_remote_players.clear()
	multiplayer_state["remotePlayerCount"] = 0
	multiplayer_state["remoteAvatarsLoaded"] = 0

func _on_session_ending() -> void:
	_allow_reconnect = false
	_intentional_close = true
	_shutdown_connection(true)
	_clear_remote_players()
	multiplayer_state["connectionState"] = "SESSION_ENDED"
	multiplayer_state["roomPlayerCount"] = 0
	multiplayer_state["selfPresenceId"] = ""
	_publish()

func _shutdown_connection(close_browser_socket: bool) -> void:
	# Invalidate every outstanding browser event before replacing/closing the socket.
	_connection_generation += 1
	multiplayer_state["connectionGeneration"] = _connection_generation
	_connected = false
	_snapshot_received = false
	_connect_in_flight = false
	_next_reconnect_at_ms = 0
	if close_browser_socket and OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var script := """
(() => {
	const socket = window.__pocketptGodotLobbySocket;
	window.__pocketptGodotLobbySocket = null;
	if (!socket) return true;
	try { socket.close(1000, "Arena session ending"); } catch (_error) {}
	return true;
})()
"""
		JavaScriptBridge.eval(script)

func _set_first_failure(stage: String, reason: String) -> void:
	if str(multiplayer_state.get("firstFailure", "NONE")) == "NONE":
		multiplayer_state["firstFailure"] = stage if reason.is_empty() else "%s:%s" % [stage, reason]
	multiplayer_state["lastError"] = reason
	_publish()

func _safe_node_name(value: String) -> String:
	var result := ""
	for character in value:
		result += character if character.is_valid_identifier() and character != " " else "_"
	return result.left(48)

func _publish() -> void:
	multiplayer_state_changed.emit(diagnostic_snapshot())
