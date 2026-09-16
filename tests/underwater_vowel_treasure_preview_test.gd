extends SceneTree

const PlayerScript = preload("res://player.gd")
const PreviewScript = preload("res://scripts/games/underwater_vowel_treasure_preview.gd")

var failures: Array[String] = []
var player: GymPlayerController
var preview: Node3D

func _initialize() -> void:
	var scene := Node3D.new()
	scene.name = "UnderwaterVowelTreasurePreviewTestScene"
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
	var initial: Dictionary = preview.call("diagnostic_snapshot")
	_expect(bool(initial.get("reefReady", false)), "vowel treasure reef reports ready")
	_expect(initial.get("lessonMode") == "PHONICS_A_SORT", "vowel treasure wrapper selects phonics lesson mode")
	_expect(initial.get("controlMode") == "EXISTING_LOCOMOTION", "phonics preview preserves existing avatar locomotion")
	_expect(initial.get("swimAnimation") == "PENDING", "phonics preview does not pretend a swim animation exists")
	_expect(initial.get("firstFailure") == "NONE", "vowel treasure preview starts with no structural first failure")
	_expect(preview.get_node_or_null("UnderwaterLearningEntryGate") != null, "existing gym-to-reef portal is preserved")
	_expect(preview.get_node_or_null("UnderwaterLearningReef/AIR1") != null, "existing safe air bubble one is preserved")
	_expect(preview.get_node_or_null("UnderwaterLearningReef/AIR2") != null, "existing safe air bubble two is preserved")
	_expect(preview.get_node_or_null("UnderwaterLearningReef/AIR3") != null, "existing safe air bubble three is preserved")
	_expect(preview.get_node_or_null("UnderwaterLearningReef/UnderwaterUnicorn") != null, "existing unicorn visual is preserved")
	_expect(preview.get_node_or_null("UnderwaterLearningReef/NumberPearl_01") == null, "make-ten number pearls are removed from active phonics lesson")
	_expect(preview.get_node_or_null("UnderwaterLearningReef/Make10TreasureChest") == null, "make-ten treasure chest is removed from active phonics lesson")

	var phonics := preview.get_node_or_null("UnderwaterLearningReef/UnderwaterPhonicsComponent")
	_expect(phonics != null, "phonics component is mounted inside the existing reef")
	if phonics != null:
		var phonics_initial: Dictionary = phonics.call("diagnostic_snapshot")
		_expect(int(phonics_initial.get("totalWords", 0)) == 20, "phonics reef scatters twenty words")
		_expect(int(phonics_initial.get("shortTarget", 0)) == 10, "phonics reef has ten short-A words")
		_expect(int(phonics_initial.get("longTarget", 0)) == 10, "phonics reef has ten long-A words")
		_expect(phonics_initial.get("firstFailure") == "NONE", "phonics component has no structural first failure")
		_expect(phonics.get_node_or_null("ShortASortBox") != null, "short-A collection box exists")
		_expect(phonics.get_node_or_null("LongASortBox") != null, "long-A collection box exists")

	_expect(bool(preview.call("enter_preview_for_test")), "player can enter vowel treasure reef")
	_expect(player.global_position.distance_to(Vector3(0.0, 0.76, -103.0)) < 0.001, "same player teleports to deterministic reef spawn")

	if phonics != null:
		var active: Dictionary = phonics.call("diagnostic_snapshot")
		_expect(active.get("status") == "ACTIVE", "entering reef starts phonics timer")
		var cap_card := phonics.get_node_or_null("PhonicsWord_SHORT_CAP") as Area3D
		_expect(cap_card != null, "CAP lost-word card exists")
		if cap_card != null:
			phonics.call("_on_word_body_entered", player, "cap", "SHORT", cap_card)
			phonics.call("_on_sort_box_entered", player, "SHORT")
			var scored: Dictionary = phonics.call("diagnostic_snapshot")
			_expect(int(scored.get("shortSorted", 0)) == 1, "carrying CAP to short-A box scores one word")
			_expect(int(scored.get("sortedTotal", 0)) == 1, "correct sort advances total vowel score")

	preview.call("_return_to_gym")
	_expect(player.global_position.distance_to(Vector3(4.2, 0.76, -4.0)) < 0.001, "same player returns to gym position")
	if phonics != null:
		_expect(phonics.call("diagnostic_snapshot").get("status") == "PAUSED", "returning to gym pauses phonics timer")
	_expect(preview.call("diagnostic_snapshot").get("firstFailure") == "NONE", "normal vowel treasure flow creates no first failure")

	if failures.is_empty():
		print("UNDERWATER_VOWEL_TREASURE_PREVIEW_TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("UNDERWATER_VOWEL_TREASURE_PREVIEW_TEST: FAIL (%d)" % failures.size())
		quit(1)

func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
