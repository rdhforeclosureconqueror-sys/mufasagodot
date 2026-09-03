extends SceneTree

const FlowScript = preload("res://scripts/pocketpt/pocketpt_phone_flow.gd")
const PlayerScript = preload("res://player.gd")

var player: GymPlayerController
var flow: PocketPTPhoneFlow
var arrived := false

func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(10.0, 0.2, 10.0)
	floor_collision.shape = floor_shape
	floor_collision.position.y = -0.1
	floor.add_child(floor_collision)
	world.add_child(floor)
	player = PlayerScript.new()
	var spring_arm := SpringArm3D.new()
	spring_arm.name = "SpringArm3D"
	player.add_child(spring_arm)
	var player_collision := CollisionShape3D.new()
	var player_shape := CapsuleShape3D.new()
	player_shape.height = 1.5
	player_collision.shape = player_shape
	player.add_child(player_collision)
	player.position = Vector3(0.0, 0.75, 0.0)
	player.speed = 3.0
	world.add_child(player)
	flow = FlowScript.new()
	world.add_child(flow)
	flow._player = player
	player.route_finished.connect(flow._on_route_finished)
	var target := Marker3D.new()
	target.position = Vector3(2.0, 0.75, 0.0)
	world.add_child(target)
	flow._mat_target = target
	player.route_finished.connect(func(value: bool): arrived = value)
	call_deferred("_run")

func _run() -> void:
	var request := _message("ARENA_FLOW_REQUEST", 1)
	request["experience"] = "PUSH_UP_ARENA"
	flow.ingest_message_for_test(request)
	flow.ingest_message_for_test(_control(2, "GYM_NAVIGATION", "SET_CONTEXT"))
	if not flow.ingest_message_for_test(_control(3, "GYM_NAVIGATION", "GO_TO_MAT")):
		return _finish(false, "GO_TO_MAT was rejected")
	for frame in range(240):
		await physics_frame
		if arrived:
			break
	var distance := Vector2(player.global_position.x - 2.0, player.global_position.z).length()
	if not arrived or distance > player.mat_arrival_distance + 0.05:
		return _finish(false, "player did not physically arrive; distance=%f" % distance)
	if int(flow.state["outgoing_sequence"]) != 2 or not str(flow.state["pending_command"]).is_empty():
		return _finish(false, "AT_MAT acknowledgement state was not completed")
	_finish(true, "")

func _message(event_name: String, sequence: int) -> Dictionary:
	return {"type": "POCKETPT_GODOT_BRIDGE", "protocolVersion": 1, "event": event_name, "flowVersion": 1, "requestId": "runtime-flow", "sequence": sequence}

func _control(sequence: int, context: String, action: String) -> Dictionary:
	var message := _message("CONTROL_INTENT", sequence)
	message.merge({"context": context, "action": action})
	return message

func _finish(ok: bool, reason: String) -> void:
	if ok:
		print("POCKETPT_PHONE_FLOW_RUNTIME_TEST: PASS")
		quit(0)
	else:
		push_error(reason)
		print("POCKETPT_PHONE_FLOW_RUNTIME_TEST: FAIL")
		quit(1)
