extends SceneTree

const FlowScript = preload("res://scripts/pocketpt/pocketpt_phone_flow_live_mocap.gd")
const PlayerScript = preload("res://player.gd")
const LocomotionAnimatorScript = preload("res://scripts/pocketpt/pocketpt_locomotion_animator.gd")

var failures: Array[String] = []
var flow: PocketPTPhoneFlowLiveMocap
var player: GymPlayerController
var animator: PocketPTLocomotionAnimator
var skeleton: Skeleton3D
var avatar: Node3D

func _initialize() -> void:
	player = PlayerScript.new()
	var spring_arm := SpringArm3D.new()
	spring_arm.name = "SpringArm3D"
	player.add_child(spring_arm)
	var agent := NavigationAgent3D.new()
	agent.name = "NavigationAgent3D"
	player.add_child(agent)
	root.add_child(player)

	avatar = Node3D.new()
	root.add_child(avatar)
	skeleton = Skeleton3D.new()
	avatar.add_child(skeleton)
	for bone_name in FlowScript.REQUIRED_JOINTS:
		skeleton.add_bone(StringName(bone_name))

	animator = LocomotionAnimatorScript.new()
	root.add_child(animator)
	animator.animation_player = AnimationPlayer.new()
	animator.animation_player.name = "MocapTestAnimationPlayer"
	avatar.add_child(animator.animation_player)
	animator.animation_tree = AnimationTree.new()
	animator.animation_tree.name = "MocapTestAnimationTree"
	animator.animation_tree.root_node = NodePath("..")
	animator.animation_tree.anim_player = NodePath("../MocapTestAnimationPlayer")
	animator.animation_tree.tree_root = AnimationNodeStateMachine.new()
	avatar.add_child(animator.animation_tree)

	flow = FlowScript.new()
	root.add_child(flow)
	flow._player = player
	flow._locomotion_animator = animator
	flow._mocap_avatar_root = avatar
	flow._mocap_mapping_state = {"status": "AVAILABLE", "schemaVersion": 1, "profileId": "test-map"}
	var canonical := {}
	for bone_name in FlowScript.REQUIRED_JOINTS:
		canonical[bone_name] = bone_name
	flow._mocap_mapping_profile = {"schemaVersion": 1, "profileId": "test-map", "restPoseValid": true, "canonicalMap": canonical}
	_expect(flow._resolve_mocap_mapping(), "canonical personalized map resolves")
	call_deferred("_run")

func _run() -> void:
	var request := _message("ARENA_FLOW_REQUEST", 1)
	request["experience"] = "PUSH_UP_ARENA"
	_expect(flow.ingest_message_for_test(request), "arena flow request accepted")
	var caps := flow.capabilities()
	_expect(caps.get("touchNavigation") == true, "joystick capability remains available")
	_expect(caps.get("liveMocap") == true and caps.get("restRelativePose") == true, "LIVE_MOCAP capabilities are truthful")

	var acquire := _mocap_message("LIVE_MOCAP_ACQUIRE", 2, "mocap-test")
	acquire.merge({"restBaseReady": true, "trackingState": "TRACKING"})
	_expect(flow.ingest_message_for_test(acquire), "valid LIVE_MOCAP acquire accepted")
	_expect(flow._mocap_active, "LIVE_MOCAP owns pose after acquire")
	_expect(not animator.animation_tree.active, "locomotion animation tree releases bone ownership")
	_expect(not flow.ingest_message_for_test(acquire), "duplicate bridge sequence rejected")

	var frame := _mocap_message("LIVE_MOCAP_FRAME", 3, "mocap-test")
	frame.merge({
		"frameSequence": 1,
		"sourceTimestamp": 1000,
		"restBaseReady": true,
		"trackingState": "TRACKING",
		"joints": {
			"LeftArm": _joint([0.0, 0.0, 0.0998334, 0.9950042]),
			"LeftForeArm": _joint([0.0, 0.0, 0.0499792, 0.9987503]),
			"RightArm": _joint([0.0, 0.0, -0.0998334, 0.9950042]),
			"RightForeArm": _joint([0.0, 0.0, -0.0499792, 0.9987503])
		}
	})
	_expect(flow.ingest_message_for_test(frame), "valid processed mocap frame accepted")
	_expect(flow._mocap_frames_applied == 1, "mocap frame counted once")
	var left_arm_index := skeleton.find_bone(&"LeftArm")
	_expect(not skeleton.get_bone_pose_rotation(left_arm_index).is_equal_approx(Quaternion.IDENTITY), "rest-relative rotation reaches mapped personalized bone")

	var stale_frame := frame.duplicate(true)
	stale_frame["sequence"] = 4
	_expect(not flow.ingest_message_for_test(stale_frame), "stale mocap frame sequence rejected")
	var malformed := frame.duplicate(true)
	malformed["sequence"] = 4
	malformed["frameSequence"] = 2
	malformed["joints"]["LeftArm"]["rotation"] = [0.0, 0.0, 0.0]
	_expect(not flow.ingest_message_for_test(malformed), "malformed rotation rejected without advancing bridge sequence")

	var frame_two := frame.duplicate(true)
	frame_two["sequence"] = 4
	frame_two["frameSequence"] = 2
	frame_two["joints"]["LeftArm"]["rotation"] = [0.0, 0.0, 0.1494381, 0.9887711]
	_expect(flow.ingest_message_for_test(frame_two), "next valid frame accepted after rejected packets")

	var wrong_release := _mocap_message("LIVE_MOCAP_RELEASE", 5, "old-session")
	_expect(not flow.ingest_message_for_test(wrong_release), "old mocap session cannot release current owner")
	var release := _mocap_message("LIVE_MOCAP_RELEASE", 5, "mocap-test")
	release["reason"] = "TEST_COMPLETE"
	_expect(flow.ingest_message_for_test(release), "current mocap session releases cleanly")
	_expect(not flow._mocap_active, "LIVE_MOCAP ownership cleared")
	_expect(skeleton.get_bone_pose_rotation(left_arm_index).is_equal_approx(Quaternion.IDENTITY), "touched bones restore to rest pose")

	var reacquire := _mocap_message("LIVE_MOCAP_ACQUIRE", 6, "timeout-test")
	reacquire.merge({"restBaseReady": true, "trackingState": "TRACKING"})
	_expect(flow.ingest_message_for_test(reacquire), "second mocap session can acquire after release")
	var last_frame_ticks := flow._mocap_last_frame_ticks
	_expect(not flow._check_mocap_timeout(last_frame_ticks + FlowScript.MOCAP_TIMEOUT_MS), "timeout boundary remains active through configured window")
	_expect(flow._check_mocap_timeout(last_frame_ticks + FlowScript.MOCAP_TIMEOUT_MS + 1), "stale live pose stream timeout fires deterministically")
	_expect(not flow._mocap_active, "stale live pose stream releases automatically")

	flow.queue_free()
	player.queue_free()
	avatar.queue_free()
	animator.queue_free()
	if failures.is_empty():
		print("POCKETPT_LIVE_MOCAP_TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("POCKETPT_LIVE_MOCAP_TEST: FAIL (%d)" % failures.size())
		quit(1)

func _message(event_name: String, sequence: int) -> Dictionary:
	return {"type": "POCKETPT_GODOT_BRIDGE", "protocolVersion": 1, "event": event_name, "flowVersion": 1, "requestId": "test-flow", "sequence": sequence}

func _mocap_message(event_name: String, sequence: int, session_id: String) -> Dictionary:
	var message := _message(event_name, sequence)
	message.merge({"mocapVersion": 1, "mocapSessionId": session_id})
	return message

func _joint(rotation: Array) -> Dictionary:
	return {"rotation": rotation, "confidence": 0.95, "valid": true}

func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
