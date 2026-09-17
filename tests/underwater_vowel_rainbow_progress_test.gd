extends SceneTree

const PhonicsScript = preload("res://scripts/games/underwater_phonics_component.gd")
const VowelCatalog = preload("res://scripts/games/underwater_vowel_lesson_catalog.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var player := Node3D.new()
	player.name = "player"
	root.add_child(player)

	var component = PhonicsScript.new()
	component.call("configure", player, VowelCatalog.lesson("A"))
	root.add_child(component)

	var initial: Dictionary = component.call("diagnostic_snapshot")
	var visual_initial: Dictionary = component.call("rainbow_visual_snapshot")

	_expect(bool(initial.get("rainbowReady", false)), "rainbow reports ready")
	_expect(int(initial.get("rainbowSegmentsPerSide", 0)) == 10, "rainbow uses ten progress segments per side")
	_expect(int(initial.get("shortRainbowProgress", -1)) == 0, "short rainbow starts at zero")
	_expect(int(initial.get("longRainbowProgress", -1)) == 0, "long rainbow starts at zero")
	_expect(not bool(initial.get("rainbowComplete", true)), "rainbow starts incomplete")
	_expect(int(visual_initial.get("shortVisible", -1)) == 0, "short rainbow starts visually hidden")
	_expect(int(visual_initial.get("longVisible", -1)) == 0, "long rainbow starts visually hidden")
	_expect(not bool(visual_initial.get("completionVisible", true)), "completion glow starts hidden")

	for index in range(10):
		component.call("_complete_correct_sort", "short_%02d" % index, "SHORT")

	var short_done: Dictionary = component.call("diagnostic_snapshot")
	var short_visual: Dictionary = component.call("rainbow_visual_snapshot")

	_expect(int(short_done.get("shortRainbowProgress", 0)) == 10, "ten short answers complete short side")
	_expect(int(short_done.get("longRainbowProgress", 0)) == 0, "long side remains empty after short answers")
	_expect(not bool(short_done.get("rainbowComplete", true)), "one completed side does not finish full rainbow")
	_expect(int(short_visual.get("shortVisible", 0)) == 10, "all short rainbow segments become visible")
	_expect(int(short_visual.get("longVisible", 0)) == 0, "long rainbow stays hidden")
	_expect(not bool(short_visual.get("completionVisible", true)), "completion glow waits for both sides")

	for index in range(10):
		component.call("_complete_correct_sort", "long_%02d" % index, "LONG")

	var complete: Dictionary = component.call("diagnostic_snapshot")
	var complete_visual: Dictionary = component.call("rainbow_visual_snapshot")

	_expect(int(complete.get("shortRainbowProgress", 0)) == 10, "short side remains complete")
	_expect(int(complete.get("longRainbowProgress", 0)) == 10, "ten long answers complete long side")
	_expect(bool(complete.get("rainbowComplete", false)), "both completed sides finish rainbow")
	_expect(int(complete_visual.get("shortVisible", 0)) == 10, "short rainbow remains fully visible")
	_expect(int(complete_visual.get("longVisible", 0)) == 10, "long rainbow becomes fully visible")
	_expect(bool(complete_visual.get("completionVisible", false)), "center completion glow appears")
	_expect(complete.get("status") == "COMPLETE", "twenty correct sorts complete the lesson")
	_expect(int(complete.get("sortedTotal", 0)) == 20, "completion records twenty sorted words")

	if failures.is_empty():
		print("UNDERWATER_VOWEL_RAINBOW_PROGRESS_TEST: PASS")
		quit(0)
		return

	for failure in failures:
		push_error(failure)

	print("UNDERWATER_VOWEL_RAINBOW_PROGRESS_TEST: FAIL (%d)" % failures.size())
	quit(1)

func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)