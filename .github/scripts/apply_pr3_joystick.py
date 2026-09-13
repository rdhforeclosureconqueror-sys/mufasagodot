from pathlib import Path

p = Path('scripts/pocketpt/pocketpt_phone_flow.gd')
s = p.read_text()
old = '''\treturn {
\t\t"contextLock": true,
\t\t"touchNavigation": true,
\t\t"matApproach": _mat_target != null and is_instance_valid(_mat_target) and _player != null and _player.navigation_ready(),
\t\t"pushUpTransition": _has_push_up_transitions()
\t}
'''
new = '''\treturn {
\t\t"contextLock": true,
\t\t"touchNavigation": true,
\t\t"vectorNavigation": true,
\t\t"matApproach": _mat_target != null and is_instance_valid(_mat_target) and _player != null and _player.navigation_ready(),
\t\t"pushUpTransition": _has_push_up_transitions()
\t}
'''
if old not in s:
    raise SystemExit('FIRST FAILURE: capabilities block not found')
s = s.replace(old, new, 1)
marker = '''\tif action in DIRECTIONS:
\t\tvar valid_for = message.get("validForMs")
'''
block = '''\tif action == "MOVE_VECTOR":
\t\tvar valid_for = message.get("validForMs")
\t\tvar x_value = message.get("x")
\t\tvar y_value = message.get("y")
\t\tif not _exact_bounded_number(valid_for, 1.0, 300.0) or not _exact_bounded_number(x_value, -1.0, 1.0) or not _exact_bounded_number(y_value, -1.0, 1.0):
\t\t\treturn false
\t\tvar movement_vector := Vector2(float(x_value), float(y_value))
\t\tif movement_vector.length_squared() <= 0.0025:
\t\t\treturn false
\t\tmovement_vector = movement_vector.normalized()
\t\tif not _player.set_remote_intent(movement_vector, int(valid_for), action):
\t\t\treturn false
\t\t_clear_navigation_command()
\t\t_requested_motion_action = action
\t\tstate["last_action"] = action
\t\tstate["incoming_sequence"] = sequence
\t\t_publish()
\t\treturn true
'''
if marker not in s:
    raise SystemExit('FIRST FAILURE: directional marker not found')
p.write_text(s.replace(marker, block + marker, 1))

p = Path('tests/pocketpt_phone_flow_test.gd')
t = p.read_text()
t = t.replace('{"contextLock": true, "touchNavigation": true, "matApproach": false, "pushUpTransition": false}', '{"contextLock": true, "touchNavigation": true, "vectorNavigation": true, "matApproach": false, "pushUpTransition": false}')
old = '''\tflow.expire_navigation_for_test()
\t_expect(player._remote_lease_deadline_ms == 0 and player._remote_direction == Vector2.ZERO, "expired lease stops remote movement")

\tvar route := _control(6, "GYM_NAVIGATION", "GO_TO_MAT")
'''
new = '''\tflow.expire_navigation_for_test()
\t_expect(player._remote_lease_deadline_ms == 0 and player._remote_direction == Vector2.ZERO, "expired lease stops remote movement")

\tflow.state["pending_command"] = "GO_TO_MAT"
\tflow._pending_reply_to = 5
\tvar joystick := _control(6, "GYM_NAVIGATION", "MOVE_VECTOR")
\tjoystick.merge({"validForMs": 300, "x": 0.6, "y": -0.8})
\t_expect(flow.ingest_message_for_test(joystick), "360 joystick movement vector accepted")
\t_expect(player._remote_direction.distance_to(Vector2(0.6, -0.8)) < 0.0001, "joystick preserves diagonal direction")
\t_expect(str(flow.state["pending_command"]).is_empty() and flow._pending_reply_to == 0, "joystick takeover clears stale GO_TO_MAT acknowledgement")
\tvar invalid_joystick := _control(7, "GYM_NAVIGATION", "MOVE_VECTOR")
\tinvalid_joystick.merge({"validForMs": 300, "x": 1.5, "y": 0.0})
\t_expect(not flow.ingest_message_for_test(invalid_joystick), "out-of-range joystick vector rejected")
\tflow.expire_navigation_for_test()

\tvar route := _control(7, "GYM_NAVIGATION", "GO_TO_MAT")
'''
if old not in t:
    raise SystemExit('FIRST FAILURE: phone-flow test insertion point not found')
t = t.replace(old, new, 1)
t = t.replace('var stop := _control(7, "CAMERA_SETUP", "STOP")', 'var stop := _control(8, "CAMERA_SETUP", "STOP")', 1)
t = t.replace('var wrong_source_scope := _control(8, "GYM_NAVIGATION", "MOVE_LEFT")', 'var wrong_source_scope := _control(9, "GYM_NAVIGATION", "MOVE_LEFT")', 1)
t = t.replace('var push_up := _control(8, "GYM_NAVIGATION", "PUSH_UP_START")', 'var push_up := _control(9, "GYM_NAVIGATION", "PUSH_UP_START")', 1)
p.write_text(t)
print('PR3_JOYSTICK_PATCH: PASS')
