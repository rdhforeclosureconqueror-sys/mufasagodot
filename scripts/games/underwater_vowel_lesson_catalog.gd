class_name UnderwaterVowelLessonCatalog
extends RefCounted

const CONFIG_VERSION := 1
const DEFAULT_VOWEL := "A"
const SHARED_RAINBOW_THEME := "shared_rainbow_v1"

static func lesson(vowel: String = DEFAULT_VOWEL) -> Dictionary:
	var normalized := vowel.strip_edges().to_upper()

	match normalized:
		"A":
			return _build_lesson(
				"A",
				["cap", "tap", "mad", "can", "hat", "map", "rat", "jam", "bat", "plan"],
				["cape", "tape", "made", "cane", "late", "name", "rake", "game", "bake", "plane"]
			)
		"E":
			return _build_lesson(
				"E",
				["bed", "red", "hen", "pen", "ten", "jet", "web", "leg", "net", "pet"],
				["tree", "seed", "feet", "green", "sheep", "beach", "team", "leaf", "queen", "wheel"]
			)
		"I":
			return _build_lesson(
				"I",
				["pig", "sit", "pin", "lip", "fish", "milk", "kick", "hill", "ship", "win"],
				["bike", "kite", "time", "line", "five", "ride", "nine", "dime", "pine", "smile"]
			)
		"O":
			return _build_lesson(
				"O",
				["hot", "hop", "fox", "log", "pot", "top", "rock", "sock", "frog", "clock"],
				["home", "bone", "rope", "nose", "note", "rose", "cone", "hope", "boat", "coat"]
			)
		"U":
			return _build_lesson(
				"U",
				["sun", "cup", "bug", "run", "tub", "mud", "rug", "bus", "nut", "duck"],
				["cube", "tube", "mule", "cute", "tune", "flute", "huge", "use", "dune", "fuse"]
			)
		_:
			return {}

static func supported_vowels() -> Array[String]:
	return ["A", "E", "I", "O", "U"]

static func is_supported(vowel: String) -> bool:
	return vowel.strip_edges().to_upper() in supported_vowels()

static func _build_lesson(vowel: String, short_words: Array, long_words: Array) -> Dictionary:
	var normalized := vowel.to_upper()

	return {
		"configVersion": CONFIG_VERSION,
		"vowel": normalized,
		"lesson": "PHONICS_%s_LONG_SHORT" % normalized,
		"lessonMode": "PHONICS_%s_SORT" % normalized,
		"title": "VOWEL TREASURE QUEST",
		"shortLabel": "SHORT %s" % normalized,
		"longLabel": "LONG %s" % normalized,
		"shortWords": short_words.duplicate(),
		"longWords": long_words.duplicate(),
		"wallThemeId": "underwater_vowel_%s_pending_art" % normalized.to_lower(),
		"wallArt": {
			"left": "",
			"right": "",
			"far": "",
			"near": ""
		},
		"rainbowThemeId": SHARED_RAINBOW_THEME,
		"shortTarget": short_words.size(),
		"longTarget": long_words.size()
	}