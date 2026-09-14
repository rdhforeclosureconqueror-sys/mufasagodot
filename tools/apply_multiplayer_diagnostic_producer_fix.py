from pathlib import Path

root = Path(__file__).resolve().parents[1]
lobby_path = root / "scripts/pocketpt/pocketpt_lobby_client.gd"
workflow_path = root / ".github/workflows/multiplayer-ci.yml"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"PATCH_BOUNDARY_{label}:{count}")
    return text.replace(old, new, 1)


lobby = lobby_path.read_text(encoding="utf-8")
lobby = replace_once(
    lobby,
    'const RECONNECT_DELAY_MS := 1200\n',
    'const RECONNECT_DELAY_MS := 1200\nconst DIAGNOSTIC_VERSION := 1\nconst DIAGNOSTIC_PUBLISH_INTERVAL_MS := 250\n',
    'CONSTANTS',
)
lobby = replace_once(
    lobby,
    'var _transport_sender_for_test: Callable = Callable()\n',
    'var _transport_sender_for_test: Callable = Callable()\nvar _diagnostic_browser_callback = null\nvar _diagnostic_request_id := ""\nvar _diagnostic_sequence := 0\nvar _diagnostic_next_send_at_ms := 0\nvar _diagnostic_ready_since_ms := -1\n',
    'FIELDS',
)
lobby = replace_once(
    lobby,
    '\tprocess_mode = Node.PROCESS_MODE_ALWAYS\n\tset_process(true)\n',
    '\tprocess_mode = Node.PROCESS_MODE_ALWAYS\n\tset_process(true)\n\t_install_multiplayer_diagnostic_receiver()\n',
    'BIND_RECEIVER',
)
lobby = replace_once(
    lobby,
    '\tif _last_state_received_at_ms >= 0:\n\t\tmultiplayer_state["lastStateAgeMs"] = maxi(0, now_ms - _last_state_received_at_ms)\n\nfunc _on_local_locomotion_sampled',
    '\tif _last_state_received_at_ms >= 0:\n\t\tmultiplayer_state["lastStateAgeMs"] = maxi(0, now_ms - _last_state_received_at_ms)\n\tif not _diagnostic_request_id.is_empty() and now_ms >= _diagnostic_next_send_at_ms:\n\t\t_report_multiplayer_diagnostic(now_ms)\n\nfunc _on_local_locomotion_sampled',
    'PROCESS_REPORT',
)
insert_before = 'func diagnostic_snapshot() -> Dictionary:\n'
producer = r'''func _install_multiplayer_diagnostic_receiver() -> void:
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

'''
lobby = replace_once(lobby, insert_before, producer + insert_before, 'PRODUCER')
lobby_path.write_text(lobby, encoding="utf-8")

workflow = workflow_path.read_text(encoding="utf-8")
workflow = replace_once(
    workflow,
    '      - "tests/pocketpt_multiplayer_sync_contract_test.gd"\n',
    '      - "tests/pocketpt_multiplayer_sync_contract_test.gd"\n      - "tests/pocketpt_multiplayer_diagnostic_payload_test.gd"\n',
    'WORKFLOW_PATH',
)
workflow = replace_once(
    workflow,
    '''      - name: Prove authoritative movement reaches outbound transport\n        shell: bash\n        run: |\n          set -euo pipefail\n          "$GODOT_BIN" --headless --path "$GITHUB_WORKSPACE" -s res://tests/pocketpt_multiplayer_sync_contract_test.gd\n\n''',
    '''      - name: Prove authoritative movement reaches outbound transport\n        shell: bash\n        run: |\n          set -euo pipefail\n          "$GODOT_BIN" --headless --path "$GITHUB_WORKSPACE" -s res://tests/pocketpt_multiplayer_sync_contract_test.gd\n\n      - name: Prove browser multiplayer diagnostic payload contract\n        shell: bash\n        run: |\n          set -euo pipefail\n          "$GODOT_BIN" --headless --path "$GITHUB_WORKSPACE" -s res://tests/pocketpt_multiplayer_diagnostic_payload_test.gd\n\n''',
    'WORKFLOW_TEST',
)
workflow_path.write_text(workflow, encoding="utf-8")

print("MULTIPLAYER_DIAGNOSTIC_PRODUCER_PATCH: PASS")
