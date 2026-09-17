extends SceneTree

const VowelCatalog = preload("res://scripts/games/underwater_vowel_lesson_catalog.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var vowels := ["A", "E", "I", "O", "U"]
	var wall_themes: Dictionary = {}

	_expect(VowelCatalog.supported_vowels() == vowels, "catalog exposes all five vowels in order")
	_expect(VowelCatalog.is_supported("a"), "lowercase A lookup is supported")
	_expect(VowelCatalog.is_supported("e"), "lowercase E lookup is supported")
	_expect(VowelCatalog.is_supported("i"), "lowercase I lookup is supported")
	_expect(VowelCatalog.is_supported("o"), "lowercase O lookup is supported")
	_expect(VowelCatalog.is_supported("u"), "lowercase U lookup is supported")
	_expect(not VowelCatalog.is_supported("Y"), "unsupported vowel is rejected")

	for vowel in vowels:
		var lesson := VowelCatalog.lesson(vowel)
		var short_words := lesson.get("shortWords", []) as Array
		var long_words := lesson.get("longWords", []) as Array
		var wall_theme := str(lesson.get("wallThemeId", ""))

		_expect(str(lesson.get("vowel", "")) == vowel, "%s config publishes vowel" % vowel)
		_expect(str(lesson.get("lesson", "")) == "PHONICS_%s_LONG_SHORT" % vowel, "%s lesson id is generated" % vowel)
		_expect(str(lesson.get("lessonMode", "")) == "PHONICS_%s_SORT" % vowel, "%s lesson mode is generated" % vowel)
		_expect(str(lesson.get("shortLabel", "")) == "SHORT %s" % vowel, "%s short label is generated" % vowel)
		_expect(str(lesson.get("longLabel", "")) == "LONG %s" % vowel, "%s long label is generated" % vowel)
		_expect(short_words.size() == 10, "%s has ten short-vowel words" % vowel)
		_expect(long_words.size() == 10, "%s has ten long-vowel words" % vowel)
		_expect(int(lesson.get("shortTarget", 0)) == 10, "%s short target matches word bank" % vowel)
		_expect(int(lesson.get("longTarget", 0)) == 10, "%s long target matches word bank" % vowel)
		_expect(wall_theme == "underwater_vowel_%s_pending_art" % vowel.to_lower(), "%s has its own pending wall theme" % vowel)
		_expect(str(lesson.get("rainbowThemeId", "")) == "shared_rainbow_v1", "%s uses the shared rainbow theme" % vowel)

		wall_themes[wall_theme] = true

	_expect(wall_themes.size() == 5, "all five vowels reserve unique wall themes")
	_expect(VowelCatalog.lesson("Z").is_empty(), "unsupported vowel returns empty config")

	var changed := VowelCatalog.lesson("A")
	changed["vowel"] = "BROKEN"
	(changed.get("shortWords", []) as Array)[0] = "broken"

	var fresh := VowelCatalog.lesson("A")
	_expect(fresh.get("vowel") == "A", "lesson calls return independent dictionaries")
	_expect((fresh.get("shortWords", []) as Array)[0] == "cap", "lesson calls return independent word arrays")

	if failures.is_empty():
		print("UNDERWATER_VOWEL_LESSON_CATALOG_TEST: PASS")
		quit(0)
		return

	for failure in failures:
		push_error(failure)

	print("UNDERWATER_VOWEL_LESSON_CATALOG_TEST: FAIL (%d)" % failures.size())
	quit(1)

func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)