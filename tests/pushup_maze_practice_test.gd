extends SceneTree

const PlayerScript = preload("res://player.gd")
const MazeScript = preload("res://scripts/games/pushup_maze_practice.gd")

var failures: Array[String] = []
var player: GymPlayerController
var maze: PushUpMazePractice

func _initialize() -> void:
	var scene := Node3D.new()
	scene.name = "MazeTestScene"
	root.add_child(scene)
	current_scene = scene

	player = PlayerScript.new()
	player.name = "player"
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.5
	collision.shape = capsule
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
	scene.add_child(player)

	maze = MazeScript.new()
	scene.add_child(maze)
	call_deferred("_run")

func _run() -> void:
	var initial := maze.diagnostic_snapshot()
	_expect(bool(initial.get("mazeReady", false)), "maze structure reports ready")
	_expect(initial.get("controlMode") == "THUMB_TEST", "v1 remains thumb-only and does not pretend TensorFlow is connected")
	_expect(initial.get("bodyTracking") == "PENDING", "body tracking is explicitly deferred")
	_expect(int(initial.get("wallCount", 0)) == 8, "maze has four outer and four lane walls")
	_expect(int(initial.get("checkpointTotal", 0)) == 4, "maze exposes four ordered checkpoints")
	_expect(initial.get("firstFailure") == "NONE", "maze has no structural first failure")

	_expect(maze.start_practice_for_test(), "maze run starts")
	var active := maze.diagnostic_snapshot()
	_expect(active.get("status") == "ACTIVE", "maze enters active state")
	_expect(absf(float(active.get("timeRemaining", 0.0)) - 60.0) < 0.001, "maze starts at 60 seconds")
	_expect(player.global_position.distance_to(Vector3(-7.0, 0.76, -33.0)) < 0.001, "player teleports to deterministic maze start")

	_expect(maze.trigger_checkpoint_for_test(1), "checkpoint one accepted")
	_expect(not maze.trigger_checkpoint_for_test(3), "out-of-order checkpoint rejected")
	_expect(maze.trigger_checkpoint_for_test(2), "checkpoint two accepted")
	_expect(maze.trigger_checkpoint_for_test(3), "checkpoint three accepted")
	_expect(maze.trigger_checkpoint_for_test(4), "checkpoint four accepted")
	_expect(maze.finish_practice_for_test(), "finish accepts completed path")
	var finished := maze.diagnostic_snapshot()
	_expect(finished.get("status") == "FINISHED", "maze records completed status")
	_expect(finished.get("result") == "COMPLETE", "maze records complete result")
	_expect(finished.get("firstFailure") == "NONE", "normal run does not create a first failure")

	maze.register_pushup_rep_for_future_body_control()
	_expect(int(maze.diagnostic_snapshot().get("pushups", 0)) == 1, "future push-up hook is present without TensorFlow integration")

	if failures.is_empty():
		print("PUSHUP_MAZE_PRACTICE_TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PUSHUP_MAZE_PRACTICE_TEST: FAIL (%d)" % failures.size())
		quit(1)

func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
