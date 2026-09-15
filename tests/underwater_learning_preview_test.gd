extends SceneTree

const PlayerScript = preload("res://player.gd")
const PreviewScript = preload("res://scripts/games/underwater_learning_preview.gd")

var failures: Array[String] = []
var player: GymPlayerController
var preview: UnderwaterLearningPreview

func _initialize() -> void:
	var scene := Node3D.new()
	scene.name = "UnderwaterLearningPreviewTestScene"
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

	preview = PreviewScript.new()
	scene.add_child(preview)
	call_deferred("_run")

func _run() -> void:
	var initial := preview.diagnostic_snapshot()
	_expect(bool(initial.get("reefReady", false)), "underwater reef structure reports ready")
	_expect(initial.get("controlMode") == "EXISTING_LOCOMOTION", "preview reuses proven avatar locomotion until swim clips arrive")
	_expect(initial.get("swimAnimation") == "PENDING", "preview does not pretend swim animation exists")
	_expect(int(initial.get("roundTotal", 0)) == 11, "make-ten sequence covers all partners 0 through 10 including reversals")
	_expect(initial.get("firstFailure") == "NONE", "reef starts with no structural first failure")
	_expect(preview.get_node_or_null("UnderwaterLearningEntryGate") != null, "gym portal is created dynamically")
	_expect(preview.get_node_or_null("UnderwaterLearningReef/NumberPearl_01") != null, "number pearl one exists")
	_expect(preview.get_node_or_null("UnderwaterLearningReef/NumberPearl_09") != null, "number pearl nine exists")

	_expect(preview.enter_preview_for_test(), "player can enter underwater learning preview")
	var active := preview.diagnostic_snapshot()
	_expect(active.get("status") == "ACTIVE", "reef enters active state")
	_expect(player.global_position.distance_to(Vector3(0.0, 0.76, -103.0)) < 0.001, "same player teleports to deterministic reef spawn")

	var wrong_orb := preview.get_node_or_null("UnderwaterLearningReef/NumberPearl_02") as Area3D
	preview._on_number_pearl_entered(player, 2, wrong_orb)
	_expect(int(preview.diagnostic_snapshot().get("treasure", 0)) == 0, "wrong make-ten partner does not award treasure")

	var correct_orb := preview.get_node_or_null("UnderwaterLearningReef/NumberPearl_01") as Area3D
	preview._on_number_pearl_entered(player, 1, correct_orb)
	var answered := preview.diagnostic_snapshot()
	_expect(int(answered.get("treasure", 0)) == 1, "9 plus 1 awards first treasure")
	_expect(int(answered.get("roundIndex", 0)) == 1, "correct answer advances to reversed 1 plus 9 round")

	preview._return_to_gym()
	var returned := preview.diagnostic_snapshot()
	_expect(returned.get("status") == "IDLE", "preview resets to idle after return")
	_expect(player.global_position.distance_to(Vector3(4.2, 0.76, -4.0)) < 0.001, "same player returns to gym position")
	_expect(returned.get("firstFailure") == "NONE", "normal preview creates no first failure")

	if failures.is_empty():
		print("UNDERWATER_LEARNING_PREVIEW_TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("UNDERWATER_LEARNING_PREVIEW_TEST: FAIL (%d)" % failures.size())
		quit(1)

func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
