from pathlib import Path

root = Path(__file__).resolve().parents[1]
lobby_path = root / "scripts/pocketpt/pocketpt_lobby_client.gd"
test_path = root / "tests/pocketpt_multiplayer_test.gd"
debug_path = root / "scripts/pocketpt/pocketpt_bridge_debug.gd"

lobby = lobby_path.read_text(encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f"PATCH_BOUNDARY_MISSING:{label}")
    if text.count(old) != 1:
        raise RuntimeError(f"PATCH_BOUNDARY_AMBIGUOUS:{label}:{text.count(old)}")
    return text.replace(old, new, 1)

lobby = replace_once(
    lobby,
    'const SEND_INTERVAL_SECONDS := 0.08\nconst RECONNECT_DELAY_MS := 1200',
    'const SEND_INTERVAL_SECONDS := 0.08\nconst SEND_INTERVAL_MS := 80\nconst HEARTBEAT_SEND_INTERVAL_MS := 500\nconst RECONNECT_DELAY_MS := 1200',
    'send_constants',
)

lobby = replace_once(
    lobby,
    '\t"lastStateSentSeq": 0,\n\t"lastStateReceivedSeq": 0,\n\t"lastStateAgeMs": -1,\n\t"reconnectCount": 0,',
    '\t"lastStateSentSeq": 0,\n\t"lastStateReceivedSeq": 0,\n\t"lastStateAgeMs": -1,\n\t"stateSendAttempts": 0,\n\t"stateSendSuccesses": 0,\n\t"stateReceiveCount": 0,\n\t"remoteMoveCount": 0,\n\t"connectionGeneration": 0,\n\t"lastStateSendAtMs": -1,\n\t"reconnectCount": 0,',
    'diagnostic_fields',
)

lobby = replace_once(
    lobby,
    'var _last_state_received_at_ms := -1\n',
    'var _last_state_received_at_ms := -1\nvar _last_state_sent_at_ms := -1\nvar _connection_generation := 0\nvar _transport_sender_for_test: Callable = Callable()\n',
    'runtime_fields',
)

lobby = replace_once(
    lobby,
    '\tif _player == null:\n\t\t_set_first_failure("LOCAL_PLAYER_BIND", "PLAYER_CONTROLLER_MISSING")\n\nfunc _process(delta: float) -> void:\n\tif _connected and _snapshot_received:\n\t\t_send_accumulator += delta\n\t\tif _send_accumulator >= SEND_INTERVAL_SECONDS:\n\t\t\t_send_accumulator = fmod(_send_accumulator, SEND_INTERVAL_SECONDS)\n\t\t\t_send_local_state()\n\telif _allow_reconnect and not _connect_in_flight and _next_reconnect_at_ms > 0 and Time.get_ticks_msec() >= _next_reconnect_at_ms:\n\t\t_next_reconnect_at_ms = 0\n\t\t_start_browser_lobby(true)\n\tif _last_state_received_at_ms >= 0:\n\t\tmultiplayer_state["lastStateAgeMs"] = maxi(0, Time.get_ticks_msec() - _last_state_received_at_ms)\n',
    '\tif _player == null:\n\t\t_set_first_failure("LOCAL_PLAYER_BIND", "PLAYER_CONTROLLER_MISSING")\n\telse:\n\t\t# The local CharacterBody physics loop is already physically proven on phone.\n\t\t# Drive state publication from that authoritative physics sample instead of\n\t\t# relying solely on this optional Node\'s frame callback.\n\t\tif not _player.locomotion_sampled.is_connected(_on_local_locomotion_sampled):\n\t\t\t_player.locomotion_sampled.connect(_on_local_locomotion_sampled)\n\tprocess_mode = Node.PROCESS_MODE_ALWAYS\n\tset_process(true)\n\nfunc _process(_delta: float) -> void:\n\tvar now_ms := Time.get_ticks_msec()\n\t# A low-frequency heartbeat protects idle/facing state and also proves that\n\t# transport is alive if physics samples temporarily stop. Moving players are\n\t# published by _on_local_locomotion_sampled at the normal 12.5 Hz cap.\n\tif _connected and _snapshot_received and (_last_state_sent_at_ms < 0 or now_ms - _last_state_sent_at_ms >= HEARTBEAT_SEND_INTERVAL_MS):\n\t\t_send_local_state(now_ms)\n\telif _allow_reconnect and not _connect_in_flight and _next_reconnect_at_ms > 0 and now_ms >= _next_reconnect_at_ms:\n\t\t_next_reconnect_at_ms = 0\n\t\t_start_browser_lobby(true)\n\tif _last_state_received_at_ms >= 0:\n\t\tmultiplayer_state["lastStateAgeMs"] = maxi(0, now_ms - _last_state_received_at_ms)\n\nfunc _on_local_locomotion_sampled(sample: Dictionary) -> void:\n\t_maybe_send_authoritative_sample(sample, Time.get_ticks_msec())\n\nfunc _maybe_send_authoritative_sample(_sample: Dictionary, now_ms: int) -> bool:\n\tif not _connected or not _snapshot_received:\n\t\treturn false\n\tif _last_state_sent_at_ms >= 0 and now_ms - _last_state_sent_at_ms < SEND_INTERVAL_MS:\n\t\treturn false\n\treturn _send_local_state(now_ms)\n',
    'process_and_physics_send',
)

lobby = replace_once(
    lobby,
    'func remote_player_for_test(presence_id: String) -> PocketPTRemotePlayer:\n\treturn _remote_players.get(presence_id) as PocketPTRemotePlayer\n',
    'func remote_player_for_test(presence_id: String) -> PocketPTRemotePlayer:\n\treturn _remote_players.get(presence_id) as PocketPTRemotePlayer\n\nfunc set_transport_sender_for_test(sender: Callable) -> void:\n\t_transport_sender_for_test = sender\n\nfunc set_transport_ready_for_test(value: bool, last_send_ms: int = -1) -> void:\n\t_connected = value\n\t_snapshot_received = value\n\t_last_state_sent_at_ms = last_send_ms\n\nfunc send_authoritative_sample_for_test(sample: Dictionary, now_ms: int) -> bool:\n\treturn _maybe_send_authoritative_sample(sample, now_ms)\n\nfunc set_connection_generation_for_test(value: int) -> void:\n\t_connection_generation = maxi(0, value)\n\tmultiplayer_state["connectionGeneration"] = _connection_generation\n\nfunc accept_browser_event_for_test(event: Dictionary) -> void:\n\t_on_browser_lobby_event([JSON.stringify(event)])\n',
    'test_seams',
)

lobby = replace_once(
    lobby,
    '\t_last_state_received_at_ms = -1\n\tvar member = payload.get("member")',
    '\t_last_state_received_at_ms = -1\n\t_last_state_sent_at_ms = -1\n\tvar member = payload.get("member")',
    'bootstrap_send_clock_reset',
)

lobby = replace_once(
    lobby,
    '\tmultiplayer_state["lastStateReceivedSeq"] = 0\n\tmultiplayer_state["lastStateAgeMs"] = -1\n\t_publish()',
    '\tmultiplayer_state["lastStateReceivedSeq"] = 0\n\tmultiplayer_state["lastStateAgeMs"] = -1\n\tmultiplayer_state["stateSendAttempts"] = 0\n\tmultiplayer_state["stateSendSuccesses"] = 0\n\tmultiplayer_state["stateReceiveCount"] = 0\n\tmultiplayer_state["remoteMoveCount"] = 0\n\tmultiplayer_state["lastStateSendAtMs"] = -1\n\t_publish()',
    'bootstrap_diagnostics_reset',
)

lobby = replace_once(
    lobby,
    '\t_connect_in_flight = true\n\tif is_reconnect:',
    '\t_connect_in_flight = true\n\t_connection_generation += 1\n\tmultiplayer_state["connectionGeneration"] = _connection_generation\n\tif is_reconnect:',
    'generation_increment',
)

lobby = replace_once(
    lobby,
    '\tvar config_literal := JSON.stringify(CONFIG_PATH)\n\tvar script := """\n(() => {\n\tconst callback = window.__pocketptGodotLobbyCallback;\n\tif (typeof callback !== "function") return false;\n\tconst send = (value) => callback(JSON.stringify(value));\n\tfetch(%s, {',
    '\tvar config_literal := JSON.stringify(CONFIG_PATH)\n\tvar script := """\n(() => {\n\tconst callback = window.__pocketptGodotLobbyCallback;\n\tconst generation = %d;\n\tif (typeof callback !== "function") return false;\n\tconst send = (value) => callback(JSON.stringify(Object.assign({generation}, value)));\n\tfetch(%s, {',
    'browser_generation_payload',
)

lobby = replace_once(
    lobby,
    '})()\n""" % config_literal\n',
    '})()\n""" % [_connection_generation, config_literal]\n',
    'browser_generation_format',
)

lobby = replace_once(
    lobby,
    '\tvar event = JSON.parse_string(args[0])\n\tif not event is Dictionary:\n\t\treturn\n\tmatch str(event.get("kind", "")):',
    '\tvar event = JSON.parse_string(args[0])\n\tif not event is Dictionary:\n\t\treturn\n\t# Ignore late events from a socket that was replaced by a newer reconnect.\n\t# Without this generation guard an old close event can freeze the newly\n\t# connected room while leaving its already-mounted remote avatar visible.\n\tif int(event.get("generation", -1)) != _connection_generation:\n\t\treturn\n\tmatch str(event.get("kind", "")):',
    'event_generation_guard',
)

lobby = replace_once(
    lobby,
    '\tmultiplayer_state["connectionState"] = "CLOSED"\n\tmultiplayer_state["lastError"] = "%d %s" % [code, reason]\n\t_publish()',
    '\tmultiplayer_state["connectionState"] = "CLOSED"\n\tmultiplayer_state["lastError"] = "%d %s" % [code, reason]\n\t_last_state_received_at_ms = -1\n\tmultiplayer_state["lastStateAgeMs"] = -1\n\t# A dead transport must never leave a frozen avatar that looks live. The\n\t# authoritative reconnect snapshot will respawn current presences.\n\t_clear_remote_players()\n\tmultiplayer_state["selfPresenceId"] = ""\n\tmultiplayer_state["roomPlayerCount"] = 0\n\t_publish()',
    'close_clears_stale_remotes',
)

lobby = replace_once(
    lobby,
    '\t_last_state_received_at_ms = Time.get_ticks_msec()\n\tmultiplayer_state["lastStateReceivedSeq"] = maxi(int(multiplayer_state.get("lastStateReceivedSeq", 0)), remote.last_sequence)\n',
    '\t_last_state_received_at_ms = Time.get_ticks_msec()\n\tmultiplayer_state["stateReceiveCount"] = int(multiplayer_state.get("stateReceiveCount", 0)) + 1\n\tmultiplayer_state["lastStateReceivedSeq"] = maxi(int(multiplayer_state.get("lastStateReceivedSeq", 0)), remote.last_sequence)\n',
    'receive_counter',
)

lobby = replace_once(
    lobby,
    'func _on_remote_moved(_presence_id: String) -> void:\n\t# Movement itself is visual evidence for the final REMOTE_MOVE stage; diagnostics derive this from state age/count.\n\tpass\n\nfunc _send_local_state() -> bool:\n\tif not _connected or not _snapshot_received or _player == null:\n\t\treturn false\n',
    'func _on_remote_moved(_presence_id: String) -> void:\n\tmultiplayer_state["remoteMoveCount"] = int(multiplayer_state.get("remoteMoveCount", 0)) + 1\n\nfunc _send_local_state(sent_at_ms: int = -1) -> bool:\n\tif not _connected or not _snapshot_received or _player == null:\n\t\treturn false\n\tmultiplayer_state["stateSendAttempts"] = int(multiplayer_state.get("stateSendAttempts", 0)) + 1\n',
    'send_signature_and_move_counter',
)

old_transport = '''\tif not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):\n\t\treturn false\n\tvar serialized_literal := JSON.stringify(JSON.stringify(payload))\n\tvar script := """\n(() => {\n\tconst socket = window.__pocketptGodotLobbySocket;\n\tif (!socket || socket.readyState !== WebSocket.OPEN) return false;\n\ttry {\n\t\tsocket.send(%s);\n\t\treturn true;\n\t} catch (_error) {\n\t\treturn false;\n\t}\n})()\n""" % serialized_literal\n\tif JavaScriptBridge.eval(script) != true:\n\t\t_set_first_failure("STATE_SEND", "WEBSOCKET_SEND_FAILED")\n\t\treturn false\n\t_local_sequence = next_sequence\n\tmultiplayer_state["lastStateSentSeq"] = _local_sequence\n\t_publish()\n\treturn true\n'''
new_transport = '''\tvar sent := false\n\tif _transport_sender_for_test.is_valid():\n\t\tsent = bool(_transport_sender_for_test.call(payload.duplicate(true)))\n\telse:\n\t\tif not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):\n\t\t\treturn false\n\t\tvar serialized_literal := JSON.stringify(JSON.stringify(payload))\n\t\tvar script := """\n(() => {\n\tconst socket = window.__pocketptGodotLobbySocket;\n\tif (!socket || socket.readyState !== WebSocket.OPEN) return false;\n\ttry {\n\t\tsocket.send(%s);\n\t\treturn true;\n\t} catch (_error) {\n\t\treturn false;\n\t}\n})()\n""" % serialized_literal\n\t\tsent = JavaScriptBridge.eval(script) == true\n\tif not sent:\n\t\t_set_first_failure("STATE_SEND", "WEBSOCKET_SEND_FAILED")\n\t\treturn false\n\t_local_sequence = next_sequence\n\t_last_state_sent_at_ms = sent_at_ms if sent_at_ms >= 0 else Time.get_ticks_msec()\n\tmultiplayer_state["lastStateSentSeq"] = _local_sequence\n\tmultiplayer_state["stateSendSuccesses"] = int(multiplayer_state.get("stateSendSuccesses", 0)) + 1\n\tmultiplayer_state["lastStateSendAtMs"] = _last_state_sent_at_ms\n\t_publish()\n\treturn true\n'''
lobby = replace_once(lobby, old_transport, new_transport, 'transport_send')

lobby = replace_once(
    lobby,
    'func _shutdown_connection(close_browser_socket: bool) -> void:\n\t_connected = false',
    'func _shutdown_connection(close_browser_socket: bool) -> void:\n\t# Invalidate every outstanding browser event before replacing/closing the socket.\n\t_connection_generation += 1\n\tmultiplayer_state["connectionGeneration"] = _connection_generation\n\t_connected = false',
    'shutdown_generation',
)

lobby_path.write_text(lobby, encoding="utf-8")

# Extend the existing regression to exercise the physically missing link: the
# authoritative CharacterBody locomotion signal must schedule outbound state.
test = test_path.read_text(encoding="utf-8")
test = replace_once(
    test,
    '\t_test_local_final_state()\n\t_test_snapshot_state_leave_reconnect_shape()\n',
    '\t_test_local_final_state()\n\t_test_authoritative_sample_drives_transport()\n\t_test_snapshot_state_leave_reconnect_shape()\n\t_test_stale_socket_events_cannot_freeze_live_room()\n',
    'test_run_list',
)

test = replace_once(
    test,
    'var remote_loader: PocketPTRemoteAvatarLoader\n',
    'var remote_loader: PocketPTRemoteAvatarLoader\nvar captured_state_packets: Array[Dictionary] = []\n',
    'test_capture_field',
)

insert_before = 'func _test_snapshot_state_leave_reconnect_shape() -> void:\n'
new_tests = '''func _capture_state_packet(payload: Dictionary) -> bool:\n\tcaptured_state_packets.append(payload.duplicate(true))\n\treturn true\n\nfunc _test_authoritative_sample_drives_transport() -> void:\n\tcaptured_state_packets.clear()\n\tlobby.set_transport_sender_for_test(_capture_state_packet)\n\tlobby.set_transport_ready_for_test(true, 1000)\n\tplayer.global_position = Vector3(2.0, 0.76, -1.0)\n\tanimator.current_state = &"WALK"\n\tvar sample := {"physicalMovementObserved": true, "actualHorizontalDisplacement": 0.04, "movementMode": "WALK"}\n\t_expect(not lobby.send_authoritative_sample_for_test(sample, 1079), "authoritative state send remains capped below 80 ms")\n\t_expect(lobby.send_authoritative_sample_for_test(sample, 1080), "authoritative CharacterBody sample drives state publication at 12.5 Hz")\n\t_expect(captured_state_packets.size() == 1, "one outbound packet emitted for one eligible authoritative sample")\n\tif captured_state_packets.size() == 1:\n\t\tvar packet := captured_state_packets[0]\n\t\t_expect(packet.get("type") == "PLAYER_STATE", "authoritative sample emits PLAYER_STATE")\n\t\t_expect(packet.get("locomotion") == "WALK", "authoritative sample carries current locomotion")\n\t\tvar pos = packet.get("position")\n\t\t_expect(pos is Array and absf(float(pos[0]) - 2.0) < 0.0001, "authoritative sample carries live CharacterBody transform")\n\tvar diagnostics := lobby.diagnostic_snapshot()\n\t_expect(int(diagnostics.get("stateSendAttempts", 0)) >= 1, "state send attempts are observable")\n\t_expect(int(diagnostics.get("stateSendSuccesses", 0)) >= 1, "state send successes are observable")\n\tlobby.set_transport_sender_for_test(Callable())\n\tlobby.set_transport_ready_for_test(false)\n\n'''
if insert_before not in test:
    raise RuntimeError('PATCH_BOUNDARY_MISSING:test_insert')
test = test.replace(insert_before, new_tests + insert_before, 1)

append_before = 'func _player_record('
new_generation_test = '''func _test_stale_socket_events_cannot_freeze_live_room() -> void:\n\t# Rebuild one remote puppet, then prove a late close event from an older\n\t# JavaScript socket generation cannot clear/freeze the active room.\n\tvar remote_record := _player_record("generation-remote", "member-c", "Player C", [3.0, 0.76, 3.0], 0.0, "IDLE", 0)\n\tvar snapshot := _json_round_trip({"type":"ROOM_SNAPSHOT", "protocolVersion":1, "roomId":"lions_den", "selfPresenceId":"generation-self", "players":[_player_record("generation-self", "member-a", "Player A", [0.0,0.76,0.0],0.0,"IDLE",0), remote_record]})\n\t_expect(lobby.accept_server_message_for_test(snapshot), "generation test snapshot accepted")\n\t_expect(lobby.remote_player_for_test("generation-remote") != null, "generation test remote spawned")\n\tlobby.set_connection_generation_for_test(9)\n\tlobby.accept_browser_event_for_test({"generation":8, "kind":"close", "code":1000, "reason":"old socket"})\n\t_expect(lobby.remote_player_for_test("generation-remote") != null, "late close from replaced socket is ignored")\n\tlobby.accept_browser_event_for_test({"generation":9, "kind":"close", "code":1006, "reason":"network lost"})\n\t_expect(lobby.remote_player_for_test("generation-remote") == null, "current socket close removes stale frozen remote")\n\t_expect(int(lobby.diagnostic_snapshot().get("roomPlayerCount", -1)) == 0, "dead transport no longer presents a live room count")\n\n'''
if append_before not in test:
    raise RuntimeError('PATCH_BOUNDARY_MISSING:generation_test_insert')
test = test.replace(append_before, new_generation_test + append_before, 1)
test_path.write_text(test, encoding="utf-8")

# Surface the new evidence in the one existing consolidated diagnostics panel.
debug = debug_path.read_text(encoding="utf-8")ndebug_old = '''LAST STATE SENT SEQ: %s\nLAST STATE RECEIVED SEQ: %s\nLAST STATE AGE MS: %s\nRECONNECT COUNT: %s\n\nFIRST FAILURE: %s""" % ['''
debug_new = '''LAST STATE SENT SEQ: %s\nLAST STATE RECEIVED SEQ: %s\nLAST STATE AGE MS: %s\nSTATE SEND ATTEMPTS: %s\nSTATE SEND SUCCESSES: %s\nSTATE RECEIVE COUNT: %s\nREMOTE MOVE COUNT: %s\nCONNECTION GENERATION: %s\nRECONNECT COUNT: %s\n\nFIRST FAILURE: %s""" % ['''
if ndebug_old not in debug:
    raise RuntimeError('PATCH_BOUNDARY_MISSING:debug_text')
debug = debug.replace(ndebug_old, debug_new, 1)
old_args = '''\t\tstr(multiplayer.get("lastStateSentSeq", 0)), str(multiplayer.get("lastStateReceivedSeq", 0)), str(multiplayer.get("lastStateAgeMs", -1)),\n\t\tstr(multiplayer.get("reconnectCount", 0)), first_failure,\n'''
new_args = '''\t\tstr(multiplayer.get("lastStateSentSeq", 0)), str(multiplayer.get("lastStateReceivedSeq", 0)), str(multiplayer.get("lastStateAgeMs", -1)),\n\t\tstr(multiplayer.get("stateSendAttempts", 0)), str(multiplayer.get("stateSendSuccesses", 0)), str(multiplayer.get("stateReceiveCount", 0)),\n\t\tstr(multiplayer.get("remoteMoveCount", 0)), str(multiplayer.get("connectionGeneration", 0)),\n\t\tstr(multiplayer.get("reconnectCount", 0)), first_failure,\n'''
if old_args not in debug:
    raise RuntimeError('PATCH_BOUNDARY_MISSING:debug_args')
debug = debug.replace(old_args, new_args, 1)
debug_path.write_text(debug, encoding="utf-8")

print('LIVE_MULTIPLAYER_SYNC_PATCH: PASS')
