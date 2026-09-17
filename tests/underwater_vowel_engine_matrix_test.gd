extends SceneTree

const PhonicsScript = preload("res://scripts/games/underwater_phonics_component.gd")
const VowelCatalog = preload("res://scripts/games/underwater_vowel_lesson_catalog.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for vowel in VowelCatalog.supported_vowels():
		_test_vowel(vowel)

	if failures.is_empty():
		print("UNDERWATER_VOWEL_ENGINE_MATRIX_TEST: PASS vowels=A,E,I,O,U")
		quit(0)
		return

	for failure in failures:
		push_error(failure)

	print("UNDERWATER_VOWEL_ENGINE_MATRIX_TEST: FAIL (%d)" % failures.size())
	quit(1)

func _test_vowel(vowel: String) -> void:
	var config := VowelCatalog.lesson(vowel)
	var short_words := config.get("shortWords", []) as Array
	var long_words := config.get("longWords", []) as Array

	var player := Node3D.new()
	player.name = "player_%s" % vowel
	root.add_child(player)

	var component = PhonicsScript.new()
	component.call("configure", player, config)
	root.add_child(component)

	var snapshot: Dictionary = component.call("diagnostic_snapshot")

	_expect(snapshot.get("firstFailure") == "NONE", "%s engine starts with no first failure" % vowel)
	_expect(snapshot.get("vowel") == vowel, "%s engine publishes active vowel" % vowel)
	_expect(snapshot.get("lesson") == "PHONICS_%s_LONG_SHORT" % vowel, "%s engine publishes lesson id" % vowel)
	_expect(int(snapshot.get("totalWords", 0)) == 20, "%s engine creates twenty words" % vowel)
	_expect(int(snapshot.get("shortTarget", 0)) == 10, "%s engine has ten short targets" % vowel)
	_expect(int(snapshot.get("longTarget", 0)) == 10, "%s engine has ten long targets" % vowel)
	_expect(snapshot.get("wallThemeId") == "underwater_vowel_%s_pending_art" % vowel.to_lower(), "%s engine receives wall theme hook" % vowel)
	_expect(snapshot.get("rainbowThemeId") == "shared_rainbow_v1", "%s engine receives rainbow theme hook" % vowel)
	_expect(bool(snapshot.get("rainbowReady", false)), "%s rainbow progress reports ready" % vowel)
	_expect(int(snapshot.get("rainbowSegmentsPerSide", 0)) == 10, "%s rainbow has ten progress steps per side" % vowel)
	_expect(int(snapshot.get("shortRainbowProgress", -1)) == 0, "%s short rainbow starts empty" % vowel)
	_expect(int(snapshot.get("longRainbowProgress", -1)) == 0, "%s long rainbow starts empty" % vowel)
	_expect(not bool(snapshot.get("rainbowComplete", true)), "%s rainbow starts incomplete" % vowel)

	_expect(component.get_node_or_null("VowelRainbowProgress") != null, "%s shared rainbow root exists" % vowel)
	_expect(component.get_node_or_null("VowelRainbowProgress/ShortRainbowProgress") != null, "%s short rainbow side exists" % vowel)
	_expect(component.get_node_or_null("VowelRainbowProgress/LongRainbowProgress") != null, "%s long rainbow side exists" % vowel)
	_expect(component.get_node_or_null("Short%sSortBox" % vowel) != null, "%s short sort target is generated" % vowel)
	_expect(component.get_node_or_null("Long%sSortBox" % vowel) != null, "%s long sort target is generated" % vowel)
	_expect(_count_word_cards(component) == 20, "%s creates twenty word cards" % vowel)

	if not short_words.is_empty():
		var short_name := "PhonicsWord_SHORT_%s" % str(short_words[0]).to_upper()
		_expect(component.get_node_or_null(short_name) != null, "%s first short word card exists" % vowel)

	if not long_words.is_empty():
		var long_name := "PhonicsWord_LONG_%s" % str(long_words[0]).to_upper()
		_expect(component.get_node_or_null(long_name) != null, "%s first long word card exists" % vowel)

	component.call("start_round")
	_expect(component.call("diagnostic_snapshot").get("status") == "ACTIVE", "%s round starts" % vowel)

	if not short_words.is_empty():
		var word := str(short_words[0])
		var card := component.get_node_or_null("PhonicsWord_SHORT_%s" % word.to_upper()) as Area3D

		if card != null:
			component.call("_on_word_body_entered", player, word, "SHORT", card)
			component.call("_on_sort_box_entered", player, "SHORT")

			var scored: Dictionary = component.call("diagnostic_snapshot")
			var rainbow_visual: Dictionary = component.call("rainbow_visual_snapshot")
			_expect(int(scored.get("shortSorted", 0)) == 1, "%s correct short sort scores" % vowel)
			_expect(int(scored.get("sortedTotal", 0)) == 1, "%s total score advances" % vowel)
			_expect(int(scored.get("shortRainbowProgress", 0)) == 1, "%s short answer advances rainbow by one" % vowel)
			_expect(int(rainbow_visual.get("shortVisible", 0)) == 1, "%s one short rainbow segment becomes visible" % vowel)
			_expect(int(rainbow_visual.get("longVisible", 0)) == 0, "%s long rainbow remains empty" % vowel)

	component.free()
	player.free()

func _count_word_cards(component: Node) -> int:
	var count := 0

	for child in component.get_children():
		if String(child.name).begins_with("PhonicsWord_"):
			count += 1

	return count

func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)