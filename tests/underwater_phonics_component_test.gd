extends SceneTree

const PhonicsScript = preload("res://scripts/games/underwater_phonics_component.gd")

var failures: Array[String] = []
var player: Node3D
var component: Node3D

func _initialize() -> void:
	var scene := Node3D.new()
	scene.name = "UnderwaterPhonicsComponentTestScene"
	root.add_child(scene)
	current_scene = scene

	player = Node3D.new()
	player.name = "player"
	scene.add_child(player)

	component = PhonicsScript.new()
	component.configure(player)
	scene.add_child(component)
	call_deferred("_run")

func _run() -> void:
	var initial: Dictionary = component.diagnostic_snapshot()
	_expect(initial.get("lesson") == "PHONICS_A_LONG_SHORT", "phonics lesson is long-A versus short-A")
	_expect(int(initial.get("totalWords", 0)) == 20, "phonics lesson contains twenty words")
	_expect(int(initial.get("shortTarget", 0)) == 10, "phonics lesson contains ten short-A targets")
	_expect(int(initial.get("longTarget", 0)) == 10, "phonics lesson contains ten long-A targets")
	_expect(bool(initial.get("boxesReady", false)), "both vowel sorting boxes report ready")
	_expect(initial.get("firstFailure") == "NONE", "phonics component starts with no structural first failure")
	_expect(component.get_node_or_null("ShortASortBox") != null, "short-A sorting box exists")
	_expect(component.get_node_or_null("LongASortBox") != null, "long-A sorting box exists")
	_expect(_count_word_cards() == 20, "twenty lost-word cards are scattered in the reef")

	component.start_round()
	_expect(component.diagnostic_snapshot().get("status") == "ACTIVE", "phonics timer starts when the round starts")

	var cap_card := component.get_node_or_null("PhonicsWord_SHORT_CAP") as Area3D
	_expect(cap_card != null, "short-A CAP card exists")
	if cap_card != null:
		component._on_word_body_entered(player, "cap", "SHORT", cap_card)
		var carrying: Dictionary = component.diagnostic_snapshot()
		_expect(carrying.get("heldWord") == "CAP", "touching a word card picks it up")

		component._on_sort_box_entered(player, "LONG")
		var wrong: Dictionary = component.diagnostic_snapshot()
		_expect(int(wrong.get("mistakes", 0)) == 1, "wrong vowel box records one mistake")
		_expect(int(wrong.get("sortedTotal", 0)) == 0, "wrong vowel box does not score the word")
		_expect(wrong.get("heldWord") == "CAP", "wrong sort keeps the word in hand for another try")

		component._on_sort_box_entered(player, "SHORT")
		var correct: Dictionary = component.diagnostic_snapshot()
		_expect(int(correct.get("shortSorted", 0)) == 1, "correct short-A box scores CAP")
		_expect(int(correct.get("sortedTotal", 0)) == 1, "correct sort advances total found count")
		_expect(correct.get("heldWord") == "", "correct sort clears carried word")

	component.set_oxygen(42.0)
	_expect(absf(float(component.diagnostic_snapshot().get("oxygen", 0.0)) - 42.0) < 0.001, "phonics HUD accepts oxygen from underwater world")

	component._process(1.25)
	_expect(float(component.diagnostic_snapshot().get("elapsedSeconds", 0.0)) >= 1.0, "active round tracks elapsed time")
	component.pause_round()
	_expect(component.diagnostic_snapshot().get("status") == "PAUSED", "leaving reef pauses phonics round")

	if failures.is_empty():
		print("UNDERWATER_PHONICS_COMPONENT_TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("UNDERWATER_PHONICS_COMPONENT_TEST: FAIL (%d)" % failures.size())
		quit(1)

func _count_word_cards() -> int:
	var count := 0
	for child in component.get_children():
		if String(child.name).begins_with("PhonicsWord_"):
			count += 1
	return count

func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
