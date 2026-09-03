extends SceneTree

const FlowScript = preload("res://scripts/pocketpt/pocketpt_phone_flow.gd")
const PlayerScript = preload("res://player.gd")

var failures: Array[String] = []
var player: GymPlayerController
var flow: PocketPTPhoneFlow
var mat: Marker3D

func _initialize() -> void:
	player = PlayerScript.new()
	var spring_arm := SpringArm3D.new()
	spring_arm.name = "SpringArm3D"
	player.add_child(spring_arm)
	root.add_child(player)
	flow = FlowScript.new()
	root.add_child(flow)
	flow._player = player
	mat = Marker3D.new()
	mat.position = Vector3(2.0, 0.0, 0.0)
	root.add_child(mat)
	flow._mat_target = mat
	call_deferred("_run")

func _run() -> void:
	var request := _message("ARENA_FLOW_REQUEST", 1)
	request["experience"] = "PUSH_UP_ARENA"
	_expect(flow.ingest_message_for_test(request), "valid flow request accepted")
	_expect(flow.state["request_id"] == "test-flow", "request scope stored")
	_expect(flow.state["incoming_sequence"] == 1, "incoming request sequence stored")
	_expect(flow.state["outgoing_sequence"] == 1, "capability response uses independent outgoing sequence")
	_expect(flow.capabilities() == {"contextLock": true, "touchNavigation": true, "matApproach": true, "pushUpTransition": false}, "truthful capabilities")
	_expect(not flow.ingest_message_for_test(request), "duplicate request does not reset channel")

	var set_context := _control(2, "LOCKED", "SET_CONTEXT")
	_expect(flow.ingest_message_for_test(set_context), "locked context accepted")
	var locked_move := _control(3, "LOCKED", "MOVE_LEFT")
	locked_move.merge({"validForMs": 300, "intensity": 1.0})
	_expect(not flow.ingest_message_for_test(locked_move), "movement rejected while locked")
	set_context = _control(3, "GYM_NAVIGATION", "SET_CONTEXT")
	_expect(flow.ingest_message_for_test(set_context), "gym context accepted")
	var move := _control(4, "GYM_NAVIGATION", "MOVE_FORWARD")
	move.merge({"validForMs": 300, "intensity": 0.75})
	_expect(flow.ingest_message_for_test(move), "valid movement lease accepted")
	_expect(player._remote_lease_deadline_ms > Time.get_ticks_msec(), "movement lease installed")
	_expect(not flow.ingest_message_for_test(move), "stale sequence rejected")
	flow.expire_navigation_for_test()
	_expect(player._remote_lease_deadline_ms == 0 and player._remote_direction == Vector2.ZERO, "expired lease stops remote movement")

	var route := _control(5, "GYM_NAVIGATION", "GO_TO_MAT")
	_expect(flow.ingest_message_for_test(route), "go-to-mat accepted")
	_expect(player.is_route_active(), "go-to-mat uses controller route")
	var stop := _control(6, "CAMERA_SETUP", "STOP")
	_expect(flow.ingest_message_for_test(stop), "STOP accepted independent of context")
	_expect(not player.is_route_active(), "STOP cancels route")
	_expect(str(flow.state["pending_command"]).is_empty(), "STOP clears pending navigation acknowledgement")

	var bad_version := _message("ARENA_FLOW_REQUEST", 1)
	bad_version["protocolVersion"] = 2
	_expect(not flow.ingest_message_for_test(bad_version), "wrong protocol rejected")
	var wrong_source_scope := _control(7, "GYM_NAVIGATION", "MOVE_LEFT")
	wrong_source_scope["requestId"] = "stale-flow"
	wrong_source_scope.merge({"validForMs": 300, "intensity": 1.0})
	_expect(not flow.ingest_message_for_test(wrong_source_scope), "stale request scope rejected")
	var push_up := _control(7, "GYM_NAVIGATION", "PUSH_UP_START")
	_expect(not flow.ingest_message_for_test(push_up), "unsupported push-up transition is not acknowledged")
	var client := PocketPTGameClient.new()
	root.add_child(client)
	flow._client = client
	client.connection_state_changed.connect(flow._on_connection_state_changed)
	player.set_navigation_context("GYM_NAVIGATION")
	player.start_route(Vector3(4.0, 0.0, 0.0))
	flow._on_bootstrap_accepted({"session": {"expiresAt": "2000-01-01T00:00:00Z"}})
	flow._process(0.0)
	_expect(not bool(flow.state["connected"]) and not player.is_route_active(), "expired session disconnects and stops movement")

	player.queue_free()
	flow.queue_free()
	mat.queue_free()
	client.queue_free()
	if failures.is_empty():
		print("POCKETPT_PHONE_FLOW_TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("POCKETPT_PHONE_FLOW_TEST: FAIL (%d)" % failures.size())
		quit(1)

func _message(event_name: String, sequence: int) -> Dictionary:
	return {"type": "POCKETPT_GODOT_BRIDGE", "protocolVersion": 1, "event": event_name, "flowVersion": 1, "requestId": "test-flow", "sequence": sequence}

func _control(sequence: int, context: String, action: String) -> Dictionary:
	var message := _message("CONTROL_INTENT", sequence)
	message.merge({"context": context, "action": action})
	return message

func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
