extends SceneTree

const PlayerScript = preload("res://player.gd")
const PoolScript = preload("res://scripts/games/learning_pool_preview.gd")

var failures: Array[String] = []
var player: GymPlayerController
var pool: LearningPoolPreview

func _initialize() -> void:
	var scene := Node3D.new()
	scene.name = "LearningPoolPreviewTestScene"
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

	pool = PoolScript.new()
	scene.add_child(pool)
	call_deferred("_run")

func _run() -> void:
	var initial := pool.diagnostic_snapshot()
	_expect(bool(initial.get("poolReady", false)), "pool structure reports ready")
	_expect(float(initial.get("poolWidthMeters", 0.0)) == 25.0, "pool width is Olympic 25 meters")
	_expect(float(initial.get("poolLengthMeters", 0.0)) == 50.0, "pool length is Olympic 50 meters")
	_expect(initial.get("controlMode") == "EXISTING_LOCOMOTION", "stage 1 reuses proven locomotion")
	_expect(initial.get("swimAnimation") == "PENDING", "stage 1 does not pretend swim animation exists")
	_expect(initial.get("firstFailure") == "NONE", "pool has no structural first failure")

	_expect(pool.enter_pool_for_test(), "player can enter learning pool preview")
	var active := pool.diagnostic_snapshot()
	_expect(active.get("status") == "IN_POOL", "pool enters active preview state")
	_expect(player.global_position.distance_to(Vector3(0.0, 0.76, -85.0)) < 0.001, "player teleports to deterministic pool spawn")

	_expect(pool.return_to_gym_for_test(), "player can return to gym")
	var returned := pool.diagnostic_snapshot()
	_expect(returned.get("status") == "IDLE", "pool resets to idle after return")
	_expect(player.global_position.distance_to(Vector3(0.0, 0.76, 3.0)) < 0.001, "player returns to deterministic gym position")
	_expect(returned.get("firstFailure") == "NONE", "normal pool preview creates no first failure")

	if failures.is_empty():
		print("LEARNING_POOL_PREVIEW_TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("LEARNING_POOL_PREVIEW_TEST: FAIL (%d)" % failures.size())
		quit(1)

func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
