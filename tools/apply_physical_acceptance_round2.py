from pathlib import Path

root = Path(__file__).resolve().parents[1]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"PATCH_BOUNDARY_{label}:{count}")
    return text.replace(old, new, 1)

# --- Multiplayer: prevent a failed JavaScript return from turning a 12.5 Hz sender into a frame-rate flood. ---
lobby_path = root / "scripts/pocketpt/pocketpt_lobby_client.gd"
lobby = lobby_path.read_text(encoding="utf-8")
lobby = replace_once(
    lobby,
    'var _last_state_received_at_ms := -1\nvar _last_state_sent_at_ms := -1\nvar _connection_generation := 0',
    'var _last_state_received_at_ms := -1\nvar _last_state_sent_at_ms := -1\nvar _last_state_attempt_at_ms := -1\nvar _state_send_block_until_ms := 0\nvar _connection_generation := 0',
    "MP_VARS",
)
lobby = replace_once(
    lobby,
    'if _connected and _snapshot_received and (_last_state_sent_at_ms < 0 or now_ms - _last_state_sent_at_ms >= HEARTBEAT_SEND_INTERVAL_MS):\n\t\t_send_local_state(now_ms)',
    'var send_gate_ms := maxi(_last_state_sent_at_ms, _last_state_attempt_at_ms)\n\tif _connected and _snapshot_received and now_ms >= _state_send_block_until_ms and (send_gate_ms < 0 or now_ms - send_gate_ms >= HEARTBEAT_SEND_INTERVAL_MS):\n\t\t_send_local_state(now_ms)',
    "MP_HEARTBEAT_GATE",
)
lobby = replace_once(
    lobby,
    'func _maybe_send_authoritative_sample(_sample: Dictionary, now_ms: int) -> bool:\n\tif not _connected or not _snapshot_received:\n\t\treturn false\n\tif _last_state_sent_at_ms >= 0 and now_ms - _last_state_sent_at_ms < SEND_INTERVAL_MS:\n\t\treturn false\n\treturn _send_local_state(now_ms)',
    'func _maybe_send_authoritative_sample(_sample: Dictionary, now_ms: int) -> bool:\n\tif not _connected or not _snapshot_received:\n\t\treturn false\n\tif now_ms < _state_send_block_until_ms:\n\t\treturn false\n\tvar send_gate_ms := maxi(_last_state_sent_at_ms, _last_state_attempt_at_ms)\n\tif send_gate_ms >= 0 and now_ms - send_gate_ms < SEND_INTERVAL_MS:\n\t\treturn false\n\treturn _send_local_state(now_ms)',
    "MP_SAMPLE_GATE",
)
lobby = replace_once(
    lobby,
    'func set_transport_ready_for_test(value: bool, last_send_ms: int = -1) -> void:\n\t_connected = value\n\t_snapshot_received = value\n\t_last_state_sent_at_ms = last_send_ms',
    'func set_transport_ready_for_test(value: bool, last_send_ms: int = -1) -> void:\n\t_connected = value\n\t_snapshot_received = value\n\t_last_state_sent_at_ms = last_send_ms\n\t_last_state_attempt_at_ms = last_send_ms\n\t_state_send_block_until_ms = 0',
    "MP_TEST_READY",
)
lobby = replace_once(
    lobby,
    '\t_last_state_received_at_ms = -1\n\t_last_state_sent_at_ms = -1\n\tvar member = payload.get("member")',
    '\t_last_state_received_at_ms = -1\n\t_last_state_sent_at_ms = -1\n\t_last_state_attempt_at_ms = -1\n\t_state_send_block_until_ms = 0\n\tvar member = payload.get("member")',
    "MP_BOOTSTRAP_RESET",
)
lobby = replace_once(
    lobby,
    'if code == "STATE_RATE_LIMIT":\n\t\t_set_first_failure("STATE_SEND", code)\n\t\treturn false',
    'if code == "STATE_RATE_LIMIT":\n\t\t# The server limit is 30/s. Back off for a full window instead of retrying\n\t\t# every physics frame while a prior send result is uncertain.\n\t\tvar now_ms := Time.get_ticks_msec()\n\t\t_state_send_block_until_ms = now_ms + 1100\n\t\t_last_state_attempt_at_ms = now_ms\n\t\t_set_first_failure("STATE_SEND", code)\n\t\treturn false',
    "MP_RATE_BACKOFF",
)
lobby = replace_once(
    lobby,
    'func _send_local_state(sent_at_ms: int = -1) -> bool:\n\tif not _connected or not _snapshot_received or _player == null:\n\t\treturn false\n\tmultiplayer_state["stateSendAttempts"] = int(multiplayer_state.get("stateSendAttempts", 0)) + 1\n\tvar next_sequence := _local_sequence + 1',
    'func _send_local_state(sent_at_ms: int = -1) -> bool:\n\tif not _connected or not _snapshot_received or _player == null:\n\t\treturn false\n\tvar attempt_ms := sent_at_ms if sent_at_ms >= 0 else Time.get_ticks_msec()\n\t_last_state_attempt_at_ms = attempt_ms\n\tmultiplayer_state["stateSendAttempts"] = int(multiplayer_state.get("stateSendAttempts", 0)) + 1\n\tvar next_sequence := _local_sequence + 1',
    "MP_ATTEMPT_STAMP",
)
lobby = replace_once(
    lobby,
    'const socket = window.__pocketptGodotLobbySocket;\n\tif (!socket || socket.readyState !== WebSocket.OPEN) return false;\n\ttry {\n\t\tsocket.send(%s);\n\t\treturn true;\n\t} catch (_error) {\n\t\treturn false;\n\t}',
    'const socket = window.__pocketptGodotLobbySocket;\n\tif (!socket || socket.readyState !== WebSocket.OPEN) return "NOT_READY";\n\ttry {\n\t\tsocket.send(%s);\n\t\t// A string sentinel crosses JavaScriptBridge more reliably than depending\n\t\t// on boolean coercion for the Web export.\n\t\treturn "SENT";\n\t} catch (_error) {\n\t\treturn "FAILED";\n\t}',
    "MP_JS_SENTINEL",
)
lobby = replace_once(
    lobby,
    '\t\tsent = JavaScriptBridge.eval(script) == true\n\tif not sent:',
    '\t\tsent = str(JavaScriptBridge.eval(script)) == "SENT"\n\tif not sent:',
    "MP_SENTINEL_READ",
)
lobby = replace_once(
    lobby,
    '\t_local_sequence = next_sequence\n\t_last_state_sent_at_ms = sent_at_ms if sent_at_ms >= 0 else Time.get_ticks_msec()\n\tmultiplayer_state["lastStateSentSeq"] = _local_sequence\n\tmultiplayer_state["stateSendSuccesses"] = int(multiplayer_state.get("stateSendSuccesses", 0)) + 1\n\tmultiplayer_state["lastStateSendAtMs"] = _last_state_sent_at_ms',
    '\t_local_sequence = next_sequence\n\t_last_state_sent_at_ms = attempt_ms\n\t_state_send_block_until_ms = 0\n\tmultiplayer_state["lastStateSentSeq"] = _local_sequence\n\tmultiplayer_state["stateSendSuccesses"] = int(multiplayer_state.get("stateSendSuccesses", 0)) + 1\n\tmultiplayer_state["lastStateSendAtMs"] = _last_state_sent_at_ms\n\tmultiplayer_state["lastError"] = ""',
    "MP_SUCCESS_STATE",
)
lobby = replace_once(
    lobby,
    '\t_connected = false\n\t_snapshot_received = false\n\t_connect_in_flight = false\n\t_next_reconnect_at_ms = 0',
    '\t_connected = false\n\t_snapshot_received = false\n\t_connect_in_flight = false\n\t_next_reconnect_at_ms = 0\n\t_last_state_attempt_at_ms = -1\n\t_state_send_block_until_ms = 0',
    "MP_SHUTDOWN_RESET",
)
lobby_path.write_text(lobby, encoding="utf-8")

# --- Multiplayer regression: a failed transport result must still respect the 80 ms attempt cap. ---
mp_test_path = root / "tests/pocketpt_multiplayer_test.gd"
mp_test = mp_test_path.read_text(encoding="utf-8")
mp_test = replace_once(
    mp_test,
    '\t_test_authoritative_sample_drives_transport()\n\t_test_snapshot_state_leave_reconnect_shape()',
    '\t_test_authoritative_sample_drives_transport()\n\t_test_failed_transport_attempt_is_still_rate_capped()\n\t_test_snapshot_state_leave_reconnect_shape()',
    "MP_TEST_CALL",
)
anchor = 'func _test_snapshot_state_leave_reconnect_shape() -> void:\n'
new_test = '''func _reject_state_packet(_payload: Dictionary) -> bool:\n\treturn false\n\nfunc _test_failed_transport_attempt_is_still_rate_capped() -> void:\n\tlobby.multiplayer_state["stateSendAttempts"] = 0\n\tlobby.multiplayer_state["stateSendSuccesses"] = 0\n\tlobby.set_transport_sender_for_test(_reject_state_packet)\n\tlobby.set_transport_ready_for_test(true, -1)\n\tvar sample := {"physicalMovementObserved": true, "actualHorizontalDisplacement": 0.04, "movementMode": "WALK"}\n\t_expect(not lobby.send_authoritative_sample_for_test(sample, 2000), "failed transport attempt reports failure")\n\t_expect(int(lobby.diagnostic_snapshot().get("stateSendAttempts", 0)) == 1, "first failed transport attempt is counted")\n\t_expect(not lobby.send_authoritative_sample_for_test(sample, 2001), "failed send does not retry on next physics frame")\n\t_expect(not lobby.send_authoritative_sample_for_test(sample, 2079), "failed send remains capped for full 80 ms window")\n\t_expect(int(lobby.diagnostic_snapshot().get("stateSendAttempts", 0)) == 1, "failed send cannot flood server before 80 ms")\n\t_expect(not lobby.send_authoritative_sample_for_test(sample, 2080), "next failed attempt becomes eligible at 80 ms")\n\t_expect(int(lobby.diagnostic_snapshot().get("stateSendAttempts", 0)) == 2, "only one additional attempt occurs at next eligible interval")\n\tlobby.set_transport_sender_for_test(Callable())\n\tlobby.set_transport_ready_for_test(false)\n\n'''
mp_test = replace_once(mp_test, anchor, new_test + anchor, "MP_TEST_BODY")
mp_test_path.write_text(mp_test, encoding="utf-8")

# --- Arm retarget: animation tracks are local bone pose rotations, so use local rest bases. ---
retarget_path = root / "scripts/pocketpt/pocketpt_animation_rest_retarget.gd"
retarget = retarget_path.read_text(encoding="utf-8")
retarget = replace_once(
    retarget,
    '''\t\t\tvar source_rest := Quaternion(float(source_values[0]), float(source_values[1]), float(source_values[2]), float(source_values[3])).normalized()\n\t\t\tvar target_rest := target_skeleton.get_bone_global_rest(target_index).basis.get_rotation_quaternion().normalized()\n\t\t\tvar key_count := clip.track_get_key_count(track_index)''',
    '''\t\t\tvar source_global_rest := Quaternion(float(source_values[0]), float(source_values[1]), float(source_values[2]), float(source_values[3])).normalized()\n\t\t\t# Animation Skeleton3D bone tracks store local pose rotation deltas. The\n\t\t\t# previous repair compared global rests, which compounds parent rotation\n\t\t\t# into the elbow/forearm axis. Derive the canonical local rest from the\n\t\t\t# target hierarchy and compare it to the target bone's local rest.\n\t\t\tvar source_rest := source_global_rest\n\t\t\tvar target_parent_index := target_skeleton.get_bone_parent(target_index)\n\t\t\tif target_parent_index >= 0:\n\t\t\t\tvar parent_name := target_skeleton.get_bone_name(target_parent_index)\n\t\t\t\tvar parent_record = bones.get(parent_name)\n\t\t\t\tif not parent_record is Dictionary:\n\t\t\t\t\treturn _failure("SOURCE_PARENT_REST_BONE_MISSING:%s" % parent_name)\n\t\t\t\tvar parent_values = parent_record.get("quaternion")\n\t\t\t\tif not parent_values is Array or parent_values.size() != 4:\n\t\t\t\t\treturn _failure("SOURCE_PARENT_REST_QUATERNION_INVALID:%s" % parent_name)\n\t\t\t\tvar parent_global_rest := Quaternion(float(parent_values[0]), float(parent_values[1]), float(parent_values[2]), float(parent_values[3])).normalized()\n\t\t\t\tsource_rest = (parent_global_rest.inverse() * source_global_rest).normalized()\n\t\t\tvar target_rest := target_skeleton.get_bone_rest(target_index).basis.get_rotation_quaternion().normalized()\n\t\t\tvar key_count := clip.track_get_key_count(track_index)''',
    "ARM_LOCAL_REST",
)
retarget = replace_once(
    retarget,
    '''static func retarget_rotation_delta(delta: Quaternion, source_global_rest: Quaternion, target_global_rest: Quaternion) -> Quaternion:\n\tvar source_rest := source_global_rest.normalized()\n\tvar target_rest := target_global_rest.normalized()\n\t# Equivalent to the repo's Blender target-native bake:\n\t# T^-1 * S * delta * S^-1 * T\n\treturn (target_rest.inverse() * source_rest * delta.normalized() * source_rest.inverse() * target_rest).normalized()''',
    '''static func retarget_rotation_delta(delta: Quaternion, source_local_rest: Quaternion, target_local_rest: Quaternion) -> Quaternion:\n\tvar source_rest := source_local_rest.normalized()\n\tvar target_rest := target_local_rest.normalized()\n\t# Bone animation rotations are local pose deltas. Convert the delta axis from\n\t# canonical local rest space into the personalized bone's local rest space.\n\t# T^-1 * S * delta * S^-1 * T\n\treturn (target_rest.inverse() * source_rest * delta.normalized() * source_rest.inverse() * target_rest).normalized()''',
    "ARM_LOCAL_COMMENT",
)
retarget_path.write_text(retarget, encoding="utf-8")

# --- Arm regression: use a parent+child hierarchy so global/local confusion cannot pass. ---
arm_test_path = root / "tests/pocketpt_animation_rest_retarget_test.gd"
arm_test = arm_test_path.read_text(encoding="utf-8")
old_library_test = '''func _test_library_mount() -> void:\n\tvar source_rest := RestRetarget.canonical_rest_for_bone("LeftForeArm")\n\tvar target_rest := (Quaternion(Vector3(0.0, 1.0, 0.0), 0.42) * source_rest).normalized()\n\tvar skeleton := Skeleton3D.new()\n\tskeleton.add_bone("LeftForeArm")\n\tskeleton.set_bone_rest(0, Transform3D(Basis(target_rest), Vector3.ZERO))\n\tvar source := AnimationLibrary.new()\n\tvar clip := Animation.new()\n\tvar track := clip.add_track(Animation.TYPE_ROTATION_3D)\n\tclip.track_set_path(track, NodePath("Canonical:LeftForeArm"))\n\tvar delta := Quaternion(Vector3(1.0, 0.0, 0.0), 0.35).normalized()\n\tclip.rotation_track_insert_key(track, 0.0, delta)\n\tsource.add_animation(&"Probe", clip)\n\tvar result := RestRetarget.mount_library(source, "TargetSkeleton", skeleton)\n\t_expect(str(result.get("error", "")).is_empty(), "synthetic library mounts without retarget error")\n\t_expect(int(result.get("adjustedRotationTracks", 0)) == 1, "one synthetic rotation track adjusted")\n\t_expect(int(result.get("adjustedRotationKeys", 0)) == 1, "one synthetic rotation key adjusted")\n\tvar mounted = result.get("library") as AnimationLibrary\n\t_expect(mounted != null and mounted.has_animation(&"Probe"), "mounted retarget library returned")\n\tif mounted == null or not mounted.has_animation(&"Probe"):\n\t\treturn\n\tvar mounted_clip := mounted.get_animation(&"Probe")\n\t_expect(str(mounted_clip.track_get_path(0)) == "TargetSkeleton:LeftForeArm", "track path points at personalized skeleton")\n\tvar actual: Quaternion = mounted_clip.track_get_key_value(0, 0)\n\tvar expected := RestRetarget.retarget_rotation_delta(delta, source_rest, target_rest)\n\t_expect(_same_rotation(actual, expected), "mounted key uses rest-space converted rotation")\n'''
new_library_test = '''func _test_library_mount() -> void:\n\tvar source_parent_global := RestRetarget.canonical_rest_for_bone("LeftArm")\n\tvar source_child_global := RestRetarget.canonical_rest_for_bone("LeftForeArm")\n\tvar source_child_local := (source_parent_global.inverse() * source_child_global).normalized()\n\tvar target_parent_local := (Quaternion(Vector3(0.0, 0.0, 1.0), 0.63) * source_parent_global).normalized()\n\tvar target_child_local := (Quaternion(Vector3(0.0, 1.0, 0.0), 0.42) * source_child_local).normalized()\n\tvar skeleton := Skeleton3D.new()\n\tskeleton.add_bone("LeftArm")\n\tskeleton.set_bone_rest(0, Transform3D(Basis(target_parent_local), Vector3.ZERO))\n\tskeleton.add_bone("LeftForeArm")\n\tskeleton.set_bone_parent(1, 0)\n\tskeleton.set_bone_rest(1, Transform3D(Basis(target_child_local), Vector3.ZERO))\n\tvar source := AnimationLibrary.new()\n\tvar clip := Animation.new()\n\tvar track := clip.add_track(Animation.TYPE_ROTATION_3D)\n\tclip.track_set_path(track, NodePath("Canonical:LeftForeArm"))\n\tvar delta := Quaternion(Vector3(1.0, 0.0, 0.0), 0.35).normalized()\n\tclip.rotation_track_insert_key(track, 0.0, delta)\n\tsource.add_animation(&"Probe", clip)\n\tvar result := RestRetarget.mount_library(source, "TargetSkeleton", skeleton)\n\t_expect(str(result.get("error", "")).is_empty(), "parented synthetic library mounts without retarget error")\n\t_expect(int(result.get("adjustedRotationTracks", 0)) == 1, "one synthetic rotation track adjusted")\n\t_expect(int(result.get("adjustedRotationKeys", 0)) == 1, "one synthetic rotation key adjusted")\n\tvar mounted = result.get("library") as AnimationLibrary\n\t_expect(mounted != null and mounted.has_animation(&"Probe"), "mounted retarget library returned")\n\tif mounted == null or not mounted.has_animation(&"Probe"):\n\t\treturn\n\tvar mounted_clip := mounted.get_animation(&"Probe")\n\t_expect(str(mounted_clip.track_get_path(0)) == "TargetSkeleton:LeftForeArm", "track path points at personalized skeleton")\n\tvar actual: Quaternion = mounted_clip.track_get_key_value(0, 0)\n\tvar expected := RestRetarget.retarget_rotation_delta(delta, source_child_local, target_child_local)\n\t_expect(_same_rotation(actual, expected), "mounted key uses parent-local rest-space conversion")\n\tvar wrong_global_target := (target_parent_local * target_child_local).normalized()\n\tvar wrong_global := RestRetarget.retarget_rotation_delta(delta, source_child_global, wrong_global_target)\n\t_expect(not _same_rotation(actual, wrong_global), "parent rotation is not compounded into child elbow axis")\n'''
arm_test = replace_once(arm_test, old_library_test, new_library_test, "ARM_PARENTED_TEST")
arm_test_path.write_text(arm_test, encoding="utf-8")

print("PHYSICAL_ACCEPTANCE_ROUND2_PATCH: PASS")
