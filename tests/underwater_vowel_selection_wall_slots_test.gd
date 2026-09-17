extends SceneTree

const PlayerScript = preload("res://player.gd")
const PreviewScript = preload("res://scripts/games/underwater_vowel_treasure_preview.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var scene := Node3D.new()
	scene.name = "UnderwaterVowelSelectionWallSlotsTestScene"
	root.add_child(scene)
	current_scene = scene

	var player: GymPlayerController = PlayerScript.new()
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

	var preview = PreviewScript.new()
	preview.active_vowel = "E"
	scene.add_child(preview)

	call_deferred("_run", preview)

func _run(preview: Node3D) -> void:
	var initial: Dictionary = preview.call("diagnostic_snapshot")

	_expect(initial.get("firstFailure") == "NONE", "E preview starts with no first failure")
	_expect(initial.get("vowel") == "E", "active_vowel property selects E")
	_expect(initial.get("lessonMode") == "PHONICS_E_SORT", "E selection switches lesson mode")
	_expect(initial.get("wallThemeId") == "underwater_vowel_e_pending_art", "E selection switches wall theme id")
	_expect(initial.get("rainbowThemeId") == "shared_rainbow_v1", "E keeps shared rainbow")
	_expect(initial.get("vowelSelectionSource") == "ACTIVE_PROPERTY", "native test records property selection source")
	_expect(bool(initial.get("wallSlotsReady", false)), "E preview wall slots are ready")
	_expect(int(initial.get("wallSlotCount", 0)) == 4, "E preview has four replaceable wall-art slots")
	_expect(not bool(initial.get("wallArtApplied", true)), "E wall slots stay hidden until approved art exists")

	for slot in ["Far", "Near", "Left", "Right"]:
		var node = preview.get_node_or_null("UnderwaterLearningReef/VowelWallArt%s" % slot)
		_expect(node != null, "E %s wall slot exists" % slot)

	var phonics := preview.get_node_or_null("UnderwaterLearningReef/UnderwaterPhonicsComponent")
	_expect(phonics != null, "E phonics component mounts in the same reef")

	if phonics != null:
		var phonics_state: Dictionary = phonics.call("diagnostic_snapshot")
		_expect(phonics_state.get("vowel") == "E", "mounted phonics engine receives E config")
		_expect(phonics.get_node_or_null("ShortESortBox") != null, "E short target is generated")
		_expect(phonics.get_node_or_null("LongESortBox") != null, "E long target is generated")
		_expect(phonics.get_node_or_null("PhonicsWord_SHORT_BED") != null, "E short word BED exists")
		_expect(phonics.get_node_or_null("PhonicsWord_LONG_TREE") != null, "E long word TREE exists")
		_expect(phonics.get_node_or_null("VowelRainbowProgress") != null, "E uses shared rainbow progress")

	if failures.is_empty():
		print("UNDERWATER_VOWEL_SELECTION_WALL_SLOTS_TEST: PASS vowel=E slots=4")
		quit(0)
		return

	for failure in failures:
		push_error(failure)

	print("UNDERWATER_VOWEL_SELECTION_WALL_SLOTS_TEST: FAIL (%d)" % failures.size())
	quit(1)

func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)