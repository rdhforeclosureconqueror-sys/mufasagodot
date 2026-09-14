from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one match, found {count}\n--- needle ---\n{old}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


lobby = "scripts/pocketpt/pocketpt_lobby_client.gd"
replace_once(lobby,
'''var _last_state_received_at_ms := -1
var _last_state_sent_at_ms := -1
var _connection_generation := 0''',
'''var _last_state_received_at_ms := -1
var _last_state_sent_at_ms := -1
# Throttle the transport on ATTEMPTS, not acknowledgements. The physical Web
# failure proved socket.send() can succeed while JavaScriptBridge.eval() does
# not round-trip a boolean success value. An acknowledgement failure must never
# turn into an unbounded resend loop / STATE_RATE_LIMIT flood.
var _last_state_attempt_at_ms := -1
var _last_state_attempt_seq := 0
var _connection_generation := 0''')

replace_once(lobby,
'''if _connected and _snapshot_received and (_last_state_sent_at_ms < 0 or now_ms - _last_state_sent_at_ms >= HEARTBEAT_SEND_INTERVAL_MS):
		_send_local_state(now_ms)''',
'''if _connected and _snapshot_received and (_last_state_attempt_at_ms < 0 or now_ms - _last_state_attempt_at_ms >= HEARTBEAT_SEND_INTERVAL_MS):
		_send_local_state(now_ms)''')

replace_once(lobby,
'''if _last_state_sent_at_ms >= 0 and now_ms - _last_state_sent_at_ms < SEND_INTERVAL_MS:
		return false
	return _send_local_state(now_ms)''',
'''if _last_state_attempt_at_ms >= 0 and now_ms - _last_state_attempt_at_ms < SEND_INTERVAL_MS:
		return false
	return _send_local_state(now_ms)''')

replace_once(lobby,
'''func set_transport_ready_for_test(value: bool, last_send_ms: int = -1) -> void:
	_connected = value
	_snapshot_received = value
	_last_state_sent_at_ms = last_send_ms''',
'''func set_transport_ready_for_test(value: bool, last_send_ms: int = -1) -> void:
	_connected = value
	_snapshot_received = value
	_last_state_sent_at_ms = last_send_ms
	_last_state_attempt_at_ms = last_send_ms''')

replace_once(lobby,
'''func send_authoritative_sample_for_test(sample: Dictionary, now_ms: int) -> bool:
	return _maybe_send_authoritative_sample(sample, now_ms)''',
'''func send_authoritative_sample_for_test(sample: Dictionary, now_ms: int) -> bool:
	return _maybe_send_authoritative_sample(sample, now_ms)

func last_state_attempt_sequence_for_test() -> int:
	return _last_state_attempt_seq''')

replace_once(lobby,
'''_last_state_received_at_ms = -1
	_last_state_sent_at_ms = -1
	var member = payload.get("member")''',
'''_last_state_received_at_ms = -1
	_last_state_sent_at_ms = -1
	_last_state_attempt_at_ms = -1
	_last_state_attempt_seq = 0
	var member = payload.get("member")''')

replace_once(lobby,
'''		"message":
			var payload = JSON.parse_string(str(event.get("data", "")))
			if payload is Dictionary:
				_ingest_server_message(payload)
			else:
				_set_first_failure("STATE_RECEIVE", "INVALID_SERVER_JSON")
		"socket_error":''',
'''		"message":
			var payload = JSON.parse_string(str(event.get("data", "")))
			if payload is Dictionary:
				_ingest_server_message(payload)
			else:
				_set_first_failure("STATE_RECEIVE", "INVALID_SERVER_JSON")
		"state_send_result":
			_handle_state_send_result(event)
		"socket_error":''')

old_send = '''func _send_local_state(sent_at_ms: int = -1) -> bool:
	if not _connected or not _snapshot_received or _player == null:
		return false
	multiplayer_state["stateSendAttempts"] = int(multiplayer_state.get("stateSendAttempts", 0)) + 1
	var next_sequence := _local_sequence + 1
	var payload := _build_local_state(next_sequence)
	if payload.is_empty():
		_set_first_failure("STATE_SEND", "LOCAL_STATE_INVALID")
		return false
	var sent := false
	if _transport_sender_for_test.is_valid():
		sent = bool(_transport_sender_for_test.call(payload.duplicate(true)))
	else:
		if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
			return false
		var serialized_literal := JSON.stringify(JSON.stringify(payload))
		var script := """
(() => {
	const socket = window.__pocketptGodotLobbySocket;
	if (!socket || socket.readyState !== WebSocket.OPEN) return false;
	try {
		socket.send(%s);
		return true;
	} catch (_error) {
		return false;
	}
})()
""" % serialized_literal
		sent = JavaScriptBridge.eval(script) == true
	if not sent:
		_set_first_failure("STATE_SEND", "WEBSOCKET_SEND_FAILED")
		return false
	_local_sequence = next_sequence
	_last_state_sent_at_ms = sent_at_ms if sent_at_ms >= 0 else Time.get_ticks_msec()
	multiplayer_state["lastStateSentSeq"] = _local_sequence
	multiplayer_state["stateSendSuccesses"] = int(multiplayer_state.get("stateSendSuccesses", 0)) + 1
	multiplayer_state["lastStateSendAtMs"] = _last_state_sent_at_ms
	_publish()
	return true
'''
new_send = '''func _handle_state_send_result(event: Dictionary) -> void:
	var sequence := int(event.get("seq", 0))
	var ok := event.get("ok") == true
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
		_record_state_send_result(next_sequence, false, attempt_at_ms, "JAVASCRIPT_BRIDGE_UNAVAILABLE")
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
'''
replace_once(lobby, old_send, new_send)

# --- Retarget: animation rotation tracks are bone-pose/local-space deltas. ---
retarget = "scripts/pocketpt/pocketpt_animation_rest_retarget.gd"
replace_once(retarget,
'''var source_values = source_record.get("quaternion")
			if not source_values is Array or source_values.size() != 4:
				return _failure("SOURCE_REST_QUATERNION_INVALID:%s" % bone_name)''',
'''var source_values = source_record.get("localQuaternion")
			if not source_values is Array or source_values.size() != 4:
				return _failure("SOURCE_LOCAL_REST_QUATERNION_INVALID:%s" % bone_name)''')
replace_once(retarget,
'''var target_rest := target_skeleton.get_bone_global_rest(target_index).basis.get_rotation_quaternion().normalized()''',
'''# Animation TYPE_ROTATION_3D keys are bone-pose (bone-local/rest-relative)
			# rotations. Comparing them against global rest folds parent orientation
			# into the conversion and physically twists elbows around the wrong axis.
			var target_rest := target_skeleton.get_bone_rest(target_index).basis.get_rotation_quaternion().normalized()''')
replace_once(retarget,
'''static func retarget_rotation_delta(delta: Quaternion, source_global_rest: Quaternion, target_global_rest: Quaternion) -> Quaternion:
	var source_rest := source_global_rest.normalized()
	var target_rest := target_global_rest.normalized()''',
'''static func retarget_rotation_delta(delta: Quaternion, source_local_rest: Quaternion, target_local_rest: Quaternion) -> Quaternion:
	var source_rest := source_local_rest.normalized()
	var target_rest := target_local_rest.normalized()''')
replace_once(retarget,
'''var values = record.get("quaternion")''',
'''var values = record.get("localQuaternion")''')
replace_once(retarget,
'''if int(parsed.get("version", 0)) != 1:
		_profile_error = "REST_PROFILE_VERSION_UNSUPPORTED"''',
'''if int(parsed.get("version", 0)) != 2 or str(parsed.get("basisSpace", "")) != "BONE_LOCAL_REST":
		_profile_error = "REST_PROFILE_VERSION_UNSUPPORTED"''')
replace_once(retarget,
'''"boneCount": int(profile.get("boneCount", 0)) if not profile.is_empty() else 0,
	}''',
'''"boneCount": int(profile.get("boneCount", 0)) if not profile.is_empty() else 0,
		"basisSpace": str(profile.get("basisSpace", "")) if not profile.is_empty() else "",
	}''')

# --- Stronger tests: cap failed attempts and prove local-rest basis against the actual source rig. ---
test_mp = "tests/pocketpt_multiplayer_test.gd"
replace_once(test_mp,
'''	_test_authoritative_sample_drives_transport()
	_test_snapshot_state_leave_reconnect_shape()''',
'''	_test_authoritative_sample_drives_transport()
	_test_failed_transport_attempts_stay_rate_capped()
	_test_snapshot_state_leave_reconnect_shape()''')
replace_once(test_mp,
'''func _test_snapshot_state_leave_reconnect_shape() -> void:''',
'''func _reject_state_packet(_payload: Dictionary) -> bool:
	return false

func _test_failed_transport_attempts_stay_rate_capped() -> void:
	lobby.set_transport_sender_for_test(_reject_state_packet)
	lobby.set_transport_ready_for_test(true, -1)
	player.global_position = Vector3(2.5, 0.76, -1.0)
	animator.current_state = &"WALK"
	var sample := {"physicalMovementObserved": true, "actualHorizontalDisplacement": 0.04, "movementMode": "WALK"}
	var before_attempts := int(lobby.diagnostic_snapshot().get("stateSendAttempts", 0))
	_expect(not lobby.send_authoritative_sample_for_test(sample, 2000), "failed transport attempt reports failure")
	_expect(not lobby.send_authoritative_sample_for_test(sample, 2001), "failed acknowledgement still activates 80 ms attempt cap")
	_expect(not lobby.send_authoritative_sample_for_test(sample, 2079), "attempt cap survives repeated locomotion samples")
	_expect(not lobby.send_authoritative_sample_for_test(sample, 2080), "next capped transport attempt can fail without flooding")
	var after_attempts := int(lobby.diagnostic_snapshot().get("stateSendAttempts", 0))
	_expect(after_attempts - before_attempts == 2, "80 ms attempt cap limits a failing bridge to 12.5 Hz")
	_expect(lobby.last_state_attempt_sequence_for_test() >= 2, "attempt sequence advances independently from acknowledgements")
	lobby.set_transport_sender_for_test(Callable())
	lobby.set_transport_ready_for_test(false)
	# Deliberate failure belongs only to this regression.
	lobby.multiplayer_state["firstFailure"] = "NONE"
	lobby.multiplayer_state["lastError"] = ""

func _test_snapshot_state_leave_reconnect_shape() -> void:''')

retarget_test = "tests/pocketpt_animation_rest_retarget_test.gd"
replace_once(retarget_test,
'''const RestRetarget = preload("res://scripts/pocketpt/pocketpt_animation_rest_retarget.gd")''',
'''const RestRetarget = preload("res://scripts/pocketpt/pocketpt_animation_rest_retarget.gd")
const SOURCE_AVATAR_PATH := "res://assets/characters/pocketpt/source/rashad1.glb"''')
replace_once(retarget_test,
'''	_test_profile()
	_test_rotation_conversion()''',
'''	_test_profile()
	_test_profile_matches_actual_source_local_rest()
	_test_rotation_conversion()''')
replace_once(retarget_test,
'''	_expect(int(status.get("boneCount", 0)) >= 50, "canonical rest profile contains full humanoid skeleton")''',
'''	_expect(int(status.get("boneCount", 0)) >= 50, "canonical rest profile contains full humanoid skeleton")
	_expect(str(status.get("basisSpace", "")) == "BONE_LOCAL_REST", "canonical profile explicitly records bone-local rest space")''')
replace_once(retarget_test,
'''func _test_rotation_conversion() -> void:''',
'''func _test_profile_matches_actual_source_local_rest() -> void:
	var packed := load(SOURCE_AVATAR_PATH) as PackedScene
	_expect(packed != null, "actual Rashad source avatar fixture loads")
	if packed == null:
		return
	var instance := packed.instantiate() as Node3D
	root.add_child(instance)
	var skeletons := instance.find_children("*", "Skeleton3D", true, false)
	_expect(not skeletons.is_empty(), "actual Rashad source skeleton exists")
	if skeletons.is_empty():
		instance.queue_free()
		return
	var skeleton := skeletons[0] as Skeleton3D
	for bone_name in ["LeftArm", "LeftForeArm", "RightArm", "RightForeArm"]:
		var index := skeleton.find_bone(bone_name)
		_expect(index >= 0, "%s exists in source skeleton" % bone_name)
		if index < 0:
			continue
		var actual_local := skeleton.get_bone_rest(index).basis.get_rotation_quaternion().normalized()
		var profiled_local := RestRetarget.canonical_rest_for_bone(bone_name)
		_expect(_same_rotation(actual_local, profiled_local), "%s profile stores LOCAL rest, not global rest" % bone_name)
	instance.queue_free()

func _test_rotation_conversion() -> void:''')
replace_once(retarget_test,
'''	var converted := RestRetarget.retarget_rotation_delta(delta, source_rest, target_rest)
	_expect(not _same_rotation(converted, delta), "different rest bases convert rotation axis")
	var round_trip := RestRetarget.retarget_rotation_delta(converted, target_rest, source_rest)''',
'''	var converted := RestRetarget.retarget_rotation_delta(delta, source_rest, target_rest)
	_expect(not _same_rotation(converted, delta), "different local rest bases convert rotation axis")
	# Anatomical flexion lives in the parent-bone coordinate frame. The converted
	# delta must preserve that parent-space rotation axis across different bone rolls.
	var source_parent_space := source_rest * delta * source_rest.inverse()
	var target_parent_space := target_rest * converted * target_rest.inverse()
	_expect(_same_rotation(source_parent_space, target_parent_space), "retarget preserves elbow flexion plane in parent space")
	var round_trip := RestRetarget.retarget_rotation_delta(converted, target_rest, source_rest)''')

# Make the permanent CI regenerate the profile from the actual source asset and
# fail if the committed profile drifts back to global-space data.
ci = ".github/workflows/avatar-rest-retarget-ci.yml"
replace_once(ci,
'''      - "resources/pocketpt/canonical_avatar_rest_profile.json"
      - "tests/pocketpt_animation_rest_retarget_test.gd"''',
'''      - "resources/pocketpt/canonical_avatar_rest_profile.json"
      - "tools/generate_canonical_rest_profile.gd"
      - "tests/pocketpt_animation_rest_retarget_test.gd"''')
replace_once(ci,
'''      - name: Parse retarget runtime
        shell: bash''',
'''      - name: Verify canonical profile is generated from bone-local source rests
        shell: bash
        run: |
          set -euo pipefail
          cp resources/pocketpt/canonical_avatar_rest_profile.json /tmp/canonical-avatar-rest-profile.json
          "$GODOT_BIN" --headless --path "$GITHUB_WORKSPACE" -s res://tools/generate_canonical_rest_profile.gd
          cmp -s /tmp/canonical-avatar-rest-profile.json resources/pocketpt/canonical_avatar_rest_profile.json || {
            echo "Canonical rest profile drifted from the actual source skeleton" >&2
            diff -u /tmp/canonical-avatar-rest-profile.json resources/pocketpt/canonical_avatar_rest_profile.json || true
            exit 1
          }

      - name: Parse retarget runtime
        shell: bash''')

print("PHYSICAL_ACCEPTANCE_ROUND2_PATCH: PASS")
