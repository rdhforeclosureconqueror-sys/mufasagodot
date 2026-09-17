class_name UnderwaterPhonicsComponent
extends Node3D

signal phonics_state_changed(state: Dictionary)

const VowelCatalog = preload("res://scripts/games/underwater_vowel_lesson_catalog.gd")

const SHORT_BOX_POSITION := Vector3(-4.2, 0.0, 20.0)
const LONG_BOX_POSITION := Vector3(4.2, 0.0, 20.0)
const HOLD_OFFSET := Vector3(0.0, 1.55, -0.85)

const RAINBOW_ROOT_POSITION := Vector3(0.0, 0.0, 20.8)
const RAINBOW_BASE_Y := 1.25
const RAINBOW_PEAK_Y := 4.85
const RAINBOW_SIDE_X := 6.0
const RAINBOW_CENTER_X := 0.55
const RAINBOW_SEGMENT_SIZE := 0.52

const RAINBOW_COLORS := [
	Color(1.0, 0.18, 0.22),
	Color(1.0, 0.46, 0.12),
	Color(1.0, 0.82, 0.12),
	Color(0.22, 0.92, 0.42),
	Color(0.18, 0.72, 1.0),
	Color(0.32, 0.38, 1.0),
	Color(0.72, 0.28, 1.0)
]

const WORD_SPAWN_POSITIONS := [
	Vector3(-12.0, 1.25, 13.0), Vector3(10.0, 1.25, 15.0),
	Vector3(-6.0, 1.25, 10.0), Vector3(13.0, 1.25, 7.0),
	Vector3(-12.0, 1.25, 4.0), Vector3(5.0, 1.25, 2.0),
	Vector3(-5.0, 1.25, -1.0), Vector3(11.0, 1.25, -5.0),
	Vector3(-13.0, 1.25, -8.0), Vector3(5.0, 1.25, -11.0),
	Vector3(-9.0, 1.25, -14.0), Vector3(12.0, 1.25, -17.0),
	Vector3(-4.0, 1.25, -20.0), Vector3(7.0, 1.25, -22.0),
	Vector3(-14.0, 1.25, 19.0), Vector3(14.0, 1.25, 18.0),
	Vector3(-2.0, 1.25, 14.0), Vector3(2.0, 1.25, 7.0),
	Vector3(-13.5, 1.25, -3.0), Vector3(0.0, 1.25, -16.0)
]

var state: Dictionary = {
	"lesson": "",
	"lessonMode": "",
	"lessonConfigVersion": 0,
	"vowel": "",
	"wallThemeId": "",
	"rainbowThemeId": "",
	"rainbowReady": false,
	"rainbowSegmentsPerSide": 0,
	"shortRainbowProgress": 0,
	"longRainbowProgress": 0,
	"rainbowComplete": false,
	"status": "READY",
	"totalWords": 0,
	"shortTarget": 0,
	"longTarget": 0,
	"shortSorted": 0,
	"longSorted": 0,
	"sortedTotal": 0,
	"mistakes": 0,
	"elapsedSeconds": 0.0,
	"oxygen": 100.0,
	"heldWord": "",
	"heldCategory": "",
	"feedback": "Find a lost word!",
	"lastEvent": "PHONICS_READY",
	"boxesReady": false,
	"firstFailure": "NONE"
}

var _player: Node3D
var _lesson_config: Dictionary = {}
var _word_cards: Dictionary = {}
var _held_card: Area3D
var _held_word: Dictionary = {}
var _round_running := false
var _rainbow_root: Node3D
var _short_rainbow_root: Node3D
var _long_rainbow_root: Node3D
var _rainbow_completion_glow: MeshInstance3D
var _hud_layer: CanvasLayer
var _title_label: Label
var _mission_label: Label
var _stats_label: Label
var _air_label: Label
var _held_label: Label
var _feedback_label: Label

func configure(player: Node3D, lesson_config: Dictionary = {}) -> void:
	_player = player

	if lesson_config.is_empty():
		_lesson_config = VowelCatalog.lesson(VowelCatalog.DEFAULT_VOWEL)
	else:
		_lesson_config = lesson_config.duplicate(true)

	_apply_lesson_state()

func _ready() -> void:
	name = "UnderwaterPhonicsComponent"

	if _lesson_config.is_empty():
		_lesson_config = VowelCatalog.lesson(VowelCatalog.DEFAULT_VOWEL)
		_apply_lesson_state()

	_build_sort_boxes()
	_build_rainbow_progress()
	_build_word_cards()
	_build_hud()
	_validate_structure()
	set_process(true)
	_update_hud()
	_publish()

func _process(delta: float) -> void:
	if _round_running and str(state.get("status", "READY")) == "ACTIVE":
		state["elapsedSeconds"] = float(state.get("elapsedSeconds", 0.0)) + delta

	if _held_card != null and is_instance_valid(_held_card) and _player != null and is_instance_valid(_player):
		var orientation := _player.global_transform.basis.orthonormalized()
		_held_card.global_position = _player.global_position + orientation * HOLD_OFFSET

	_update_hud()

func diagnostic_snapshot() -> Dictionary:
	return state.duplicate(true)

func lesson_config_snapshot() -> Dictionary:
	return _lesson_config.duplicate(true)

func start_round() -> void:
	if str(state.get("status", "READY")) == "COMPLETE":
		return

	state["status"] = "ACTIVE"
	state["feedback"] = "Find a word, carry it back, and choose %s or %s!" % [_short_label(), _long_label()]
	state["lastEvent"] = "PHONICS_ROUND_STARTED"
	_round_running = true

	if _hud_layer != null:
		_hud_layer.visible = true

	_update_hud()
	_publish()

func pause_round() -> void:
	_round_running = false

	if str(state.get("status", "READY")) == "ACTIVE":
		state["status"] = "PAUSED"
		state["lastEvent"] = "PHONICS_ROUND_PAUSED"

	if _hud_layer != null:
		_hud_layer.visible = false

	_publish()

func set_oxygen(value: float) -> void:
	state["oxygen"] = clampf(value, 0.0, 100.0)

func _apply_lesson_state() -> void:
	var short_words := _short_words()
	var long_words := _long_words()

	state["lesson"] = str(_lesson_config.get("lesson", ""))
	state["lessonMode"] = str(_lesson_config.get("lessonMode", ""))
	state["lessonConfigVersion"] = int(_lesson_config.get("configVersion", 0))
	state["vowel"] = str(_lesson_config.get("vowel", ""))
	state["wallThemeId"] = str(_lesson_config.get("wallThemeId", ""))
	state["rainbowThemeId"] = str(_lesson_config.get("rainbowThemeId", ""))
	state["shortTarget"] = int(_lesson_config.get("shortTarget", short_words.size()))
	state["longTarget"] = int(_lesson_config.get("longTarget", long_words.size()))
	state["totalWords"] = short_words.size() + long_words.size()
	state["rainbowSegmentsPerSide"] = maxi(
		int(state.get("shortTarget", 0)),
		int(state.get("longTarget", 0))
	)
	state["shortRainbowProgress"] = 0
	state["longRainbowProgress"] = 0
	state["rainbowComplete"] = false
	state["rainbowReady"] = false

func _build_rainbow_progress() -> void:
	_rainbow_root = Node3D.new()
	_rainbow_root.name = "VowelRainbowProgress"
	_rainbow_root.position = RAINBOW_ROOT_POSITION
	add_child(_rainbow_root)

	_short_rainbow_root = Node3D.new()
	_short_rainbow_root.name = "ShortRainbowProgress"
	_rainbow_root.add_child(_short_rainbow_root)

	_long_rainbow_root = Node3D.new()
	_long_rainbow_root.name = "LongRainbowProgress"
	_rainbow_root.add_child(_long_rainbow_root)

	var short_count := int(state.get("shortTarget", 0))
	var long_count := int(state.get("longTarget", 0))

	_build_rainbow_side(_short_rainbow_root, "ShortRainbowSegment", short_count, true)
	_build_rainbow_side(_long_rainbow_root, "LongRainbowSegment", long_count, false)

	_rainbow_completion_glow = MeshInstance3D.new()
	_rainbow_completion_glow.name = "RainbowCompletionGlow"

	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 0.48
	glow_mesh.height = 0.96
	glow_mesh.material = _material(
		Color(1.0, 0.88, 0.36),
		Color(1.0, 0.62, 0.12),
		4.0
	)

	_rainbow_completion_glow.mesh = glow_mesh
	_rainbow_completion_glow.position = Vector3(0.0, RAINBOW_PEAK_Y + 0.25, 0.0)
	_rainbow_completion_glow.visible = false
	_rainbow_root.add_child(_rainbow_completion_glow)

	state["rainbowReady"] = (
		_short_rainbow_root.get_child_count() == short_count
		and _long_rainbow_root.get_child_count() == long_count
	)

	_sync_rainbow_visuals()

func _build_rainbow_side(parent: Node3D, prefix: String, count: int, is_short_side: bool) -> void:
	if count <= 0:
		return

	for index in range(count):
		var t := float(index + 1) / float(count)
		var segment := MeshInstance3D.new()
		segment.name = "%s_%02d" % [prefix, index + 1]

		var sphere := SphereMesh.new()
		sphere.radius = RAINBOW_SEGMENT_SIZE
		sphere.height = RAINBOW_SEGMENT_SIZE * 2.0

		var color := _rainbow_color(index)
		sphere.material = _material(color * 0.72, color, 2.35)
		segment.mesh = sphere

		var x := 0.0
		if is_short_side:
			x = lerpf(-RAINBOW_SIDE_X, -RAINBOW_CENTER_X, t)
		else:
			x = lerpf(RAINBOW_SIDE_X, RAINBOW_CENTER_X, t)

		var y := RAINBOW_BASE_Y + sin(t * PI * 0.5) * (RAINBOW_PEAK_Y - RAINBOW_BASE_Y)
		segment.position = Vector3(x, y, 0.0)
		segment.visible = false
		parent.add_child(segment)

func _rainbow_color(index: int) -> Color:
	if RAINBOW_COLORS.is_empty():
		return Color.WHITE

	return RAINBOW_COLORS[index % RAINBOW_COLORS.size()]

func _advance_rainbow(category: String) -> void:
	if category == "SHORT":
		state["shortRainbowProgress"] = mini(
			int(state.get("shortRainbowProgress", 0)) + 1,
			int(state.get("shortTarget", 0))
		)
	elif category == "LONG":
		state["longRainbowProgress"] = mini(
			int(state.get("longRainbowProgress", 0)) + 1,
			int(state.get("longTarget", 0))
		)

	_sync_rainbow_visuals()

	var short_done := int(state.get("shortRainbowProgress", 0)) >= int(state.get("shortTarget", 0))
	var long_done := int(state.get("longRainbowProgress", 0)) >= int(state.get("longTarget", 0))

	if short_done and long_done:
		_trigger_rainbow_completion()

func _sync_rainbow_visuals() -> void:
	_set_rainbow_side_visibility(
		_short_rainbow_root,
		int(state.get("shortRainbowProgress", 0))
	)

	_set_rainbow_side_visibility(
		_long_rainbow_root,
		int(state.get("longRainbowProgress", 0))
	)

	if _rainbow_completion_glow != null and is_instance_valid(_rainbow_completion_glow):
		_rainbow_completion_glow.visible = bool(state.get("rainbowComplete", false))

func _set_rainbow_side_visibility(parent: Node3D, visible_count: int) -> void:
	if parent == null or not is_instance_valid(parent):
		return

	for index in range(parent.get_child_count()):
		var child := parent.get_child(index)

		if child is GeometryInstance3D:
			(child as GeometryInstance3D).visible = index < visible_count

func _trigger_rainbow_completion() -> void:
	if bool(state.get("rainbowComplete", false)):
		return

	state["rainbowComplete"] = true

	if _rainbow_completion_glow != null and is_instance_valid(_rainbow_completion_glow):
		_rainbow_completion_glow.visible = true

	state["lastEvent"] = "PHONICS_RAINBOW_COMPLETE"

func _visible_rainbow_segments(parent: Node3D) -> int:
	if parent == null or not is_instance_valid(parent):
		return 0

	var count := 0

	for child in parent.get_children():
		if child is GeometryInstance3D and (child as GeometryInstance3D).visible:
			count += 1

	return count

func rainbow_visual_snapshot() -> Dictionary:
	return {
		"shortVisible": _visible_rainbow_segments(_short_rainbow_root),
		"longVisible": _visible_rainbow_segments(_long_rainbow_root),
		"completionVisible": (
			_rainbow_completion_glow != null
			and is_instance_valid(_rainbow_completion_glow)
			and _rainbow_completion_glow.visible
		)
	}

func _build_sort_boxes() -> void:
	var vowel := _vowel()

	_build_sort_box(
		"Short%sSortBox" % vowel,
		SHORT_BOX_POSITION,
		_short_label(),
		"SHORT"
	)

	_build_sort_box(
		"Long%sSortBox" % vowel,
		LONG_BOX_POSITION,
		_long_label(),
		"LONG"
	)

	state["boxesReady"] = true

func _build_sort_box(node_name: String, local_position: Vector3, title: String, category: String) -> void:
	var box := Area3D.new()
	box.name = node_name
	box.position = local_position
	add_child(box)

	var visual := MeshInstance3D.new()
	visual.name = "%sVisual" % node_name

	var mesh := BoxMesh.new()
	mesh.size = Vector3(3.2, 1.15, 2.1)

	var box_color := Color(0.02, 0.52, 0.78) if category == "SHORT" else Color(0.72, 0.32, 0.92)
	mesh.material = _material(box_color * 0.45, box_color, 1.8)
	visual.mesh = mesh
	visual.position.y = 0.58
	box.add_child(visual)

	var label := Label3D.new()
	label.name = "%sLabel" % node_name
	label.text = "%s\nDROP WORDS HERE" % title
	label.position = Vector3(0.0, 1.65, 0.0)
	label.font_size = 58
	label.outline_size = 10
	label.modulate = Color.WHITE
	label.outline_modulate = Color(0.0, 0.03, 0.06)
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	box.add_child(label)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.6, 2.2, 2.5)
	collision.shape = shape
	collision.position.y = 1.0
	box.add_child(collision)

	box.body_entered.connect(_on_sort_box_entered.bind(category))

func _build_word_cards() -> void:
	var short_words := _short_words()
	var long_words := _long_words()
	var position_index := 0
	var pair_count := mini(short_words.size(), long_words.size())

	for index in range(pair_count):
		_spawn_word_card(str(short_words[index]), "SHORT", WORD_SPAWN_POSITIONS[position_index])
		position_index += 1

		_spawn_word_card(str(long_words[index]), "LONG", WORD_SPAWN_POSITIONS[position_index])
		position_index += 1

func _spawn_word_card(word: String, category: String, local_position: Vector3) -> void:
	var card := Area3D.new()
	var card_id := "%s_%s" % [category, word.to_upper()]
	card.name = "PhonicsWord_%s" % card_id
	card.position = local_position
	add_child(card)

	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.9, 0.95, 0.05)
	mesh.material = _card_material()
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	card.add_child(visual)

	var label := Label3D.new()
	label.name = "WordLabel"
	label.text = word.to_upper()
	label.position = Vector3(0.0, 0.02, 0.08)
	label.font_size = 88
	label.outline_size = 12
	label.modulate = Color(1.0, 0.95, 0.48)
	label.outline_modulate = Color(0.0, 0.04, 0.08)
	label.pixel_size = 0.0044
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	card.add_child(label)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.05, 1.15, 0.8)
	collision.shape = shape
	card.add_child(collision)

	card.body_entered.connect(_on_word_body_entered.bind(word, category, card))
	_word_cards[card_id] = card

func _on_word_body_entered(body: Node, word: String, category: String, card: Area3D) -> void:
	if body != _player:
		return

	if str(state.get("status", "READY")) != "ACTIVE":
		return

	if _held_card != null and is_instance_valid(_held_card):
		state["feedback"] = "You are already carrying %s. Sort it first!" % str(state.get("heldWord", "WORD"))
		state["lastEvent"] = "PHONICS_PICKUP_BLOCKED_ALREADY_HOLDING"
		_publish()
		return

	if card == null or not is_instance_valid(card):
		return

	_held_card = card
	_held_word = {"word": word, "category": category}
	card.monitoring = false
	state["heldWord"] = word.to_upper()
	state["heldCategory"] = category
	state["feedback"] = "You found %s! Carry it to the %s or %s box." % [word.to_upper(), _short_label(), _long_label()]
	state["lastEvent"] = "PHONICS_WORD_PICKED_%s" % word.to_upper()
	_publish()

func _on_sort_box_entered(body: Node, target_category: String) -> void:
	if body != _player:
		return

	if str(state.get("status", "READY")) != "ACTIVE":
		return

	if _held_card == null or not is_instance_valid(_held_card) or _held_word.is_empty():
		state["feedback"] = "Find a lost word first!"
		state["lastEvent"] = "PHONICS_EMPTY_SORT_BOX_ENTRY"
		_publish()
		return

	var word := str(_held_word.get("word", ""))
	var actual_category := str(_held_word.get("category", ""))

	if actual_category != target_category:
		state["mistakes"] = int(state.get("mistakes", 0)) + 1
		state["feedback"] = "Try the other chest. Listen to %s again." % word.to_upper()
		state["lastEvent"] = "PHONICS_SORT_WRONG_%s_TO_%s" % [word.to_upper(), target_category]
		_publish()
		return

	_complete_correct_sort(word, actual_category)

func _complete_correct_sort(word: String, category: String) -> void:
	if category == "SHORT":
		state["shortSorted"] = int(state.get("shortSorted", 0)) + 1
	else:
		state["longSorted"] = int(state.get("longSorted", 0)) + 1

	state["sortedTotal"] = int(state.get("shortSorted", 0)) + int(state.get("longSorted", 0))
	_advance_rainbow(category)
	state["feedback"] = "%s! %s %s sound!" % [word.to_upper(), category, _vowel()]
	state["lastEvent"] = "PHONICS_SORT_CORRECT_%s_%s" % [category, word.to_upper()]
	state["heldWord"] = ""
	state["heldCategory"] = ""
	_held_word = {}

	var completed_card := _held_card
	_held_card = null

	if completed_card != null and is_instance_valid(completed_card):
		completed_card.queue_free()

	if int(state.get("sortedTotal", 0)) >= int(state.get("totalWords", 0)):
		_round_running = false
		state["status"] = "COMPLETE"
		state["feedback"] = "ALL %d WORDS FOUND! Time %s \u2022 Mistakes %d" % [
			int(state.get("totalWords", 0)),
			_format_time(float(state.get("elapsedSeconds", 0.0))),
			int(state.get("mistakes", 0))
		]
		state["lastEvent"] = "PHONICS_VOWEL_TREASURE_COMPLETE"

	_publish()

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "VowelTreasureHUD"
	_hud_layer.layer = 46
	add_child(_hud_layer)

	var panel := PanelContainer.new()
	panel.name = "VowelTreasurePanel"
	panel.position = Vector2(18, 18)
	panel.custom_minimum_size = Vector2(650, 190)
	_hud_layer.add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.10, 0.18, 0.58)
	style.border_color = Color(0.24, 0.92, 1.0, 0.92)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", style)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	panel.add_child(stack)

	_title_label = _hud_label(str(_lesson_config.get("title", "VOWEL TREASURE QUEST")), 24, Color(1.0, 0.82, 0.24))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_title_label)

	_mission_label = _hud_label(
		"%s  vs  %s  \u2022  Find \u2022 Carry \u2022 Sort" % [_short_label(), _long_label()],
		17,
		Color(0.42, 0.94, 1.0)
	)
	_mission_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_mission_label)

	_stats_label = _hud_label("", 18, Color(1.0, 0.91, 0.52))
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_stats_label)

	_air_label = _hud_label("", 18, Color(0.35, 0.96, 1.0))
	_air_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_air_label)

	_held_label = _hud_label("", 20, Color(1.0, 0.62, 0.92))
	_held_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_held_label)

	_feedback_label = _hud_label("", 16, Color(0.72, 1.0, 0.68))
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_feedback_label)

	_hud_layer.visible = false

func _hud_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _update_hud() -> void:
	if _stats_label == null:
		return

	var elapsed := _format_time(float(state.get("elapsedSeconds", 0.0)))
	_stats_label.text = "%s  %d/%d     %s  %d/%d     FOUND  %d/%d     TIME  %s" % [
		_short_label(),
		int(state.get("shortSorted", 0)),
		int(state.get("shortTarget", 0)),
		_long_label(),
		int(state.get("longSorted", 0)),
		int(state.get("longTarget", 0)),
		int(state.get("sortedTotal", 0)),
		int(state.get("totalWords", 0)),
		elapsed
	]

	var oxygen := int(round(float(state.get("oxygen", 100.0))))
	var air_blocks := int(floor(float(oxygen) / 10.0))
	var air_meter := ""

	for index in range(10):
		air_meter += "\u25cf" if index < air_blocks else "\u25cb"

	_air_label.text = "AIR  %d%%   %s" % [oxygen, air_meter]

	var held := str(state.get("heldWord", ""))
	_held_label.text = "CARRYING: %s" % (held if not held.is_empty() else "-")
	_feedback_label.text = str(state.get("feedback", ""))

func _validate_structure() -> void:
	var short_words := _short_words()
	var long_words := _long_words()
	var expected_total := short_words.size() + long_words.size()

	if _player == null:
		_set_first_failure("PHONICS_PLAYER", "PLAYER_NOT_CONFIGURED")
	elif _lesson_config.is_empty():
		_set_first_failure("PHONICS_CONFIG", "LESSON_CONFIG_MISSING")
	elif _vowel().is_empty():
		_set_first_failure("PHONICS_CONFIG", "VOWEL_MISSING")
	elif short_words.is_empty() or long_words.is_empty():
		_set_first_failure("PHONICS_CONTENT", "WORD_BANK_EMPTY")
	elif short_words.size() != int(state.get("shortTarget", 0)):
		_set_first_failure("PHONICS_CONTENT", "SHORT_TARGET_MISMATCH")
	elif long_words.size() != int(state.get("longTarget", 0)):
		_set_first_failure("PHONICS_CONTENT", "LONG_TARGET_MISMATCH")
	elif expected_total > WORD_SPAWN_POSITIONS.size():
		_set_first_failure("PHONICS_CONTENT", "TOO_MANY_WORDS_FOR_SPAWN_SLOTS")
	elif not bool(state.get("boxesReady", false)):
		_set_first_failure("PHONICS_BOXES", "SORT_BOXES_MISSING")
	elif not bool(state.get("rainbowReady", false)):
		_set_first_failure("PHONICS_RAINBOW", "RAINBOW_PROGRESS_MISSING")
	elif _word_cards.size() != expected_total:
		_set_first_failure("PHONICS_WORDS", "EXPECTED_%d_WORD_CARDS_GOT_%d" % [expected_total, _word_cards.size()])

func _set_first_failure(stage: String, reason: String) -> void:
	if str(state.get("firstFailure", "NONE")) != "NONE":
		return

	state["firstFailure"] = "%s:%s" % [stage, reason]
	push_error("UNDERWATER_PHONICS_FIRST_FAILURE %s" % str(state["firstFailure"]))
	_publish()

func _vowel() -> String:
	return str(_lesson_config.get("vowel", "")).to_upper()

func _short_words() -> Array:
	var value = _lesson_config.get("shortWords", [])
	return value if value is Array else []

func _long_words() -> Array:
	var value = _lesson_config.get("longWords", [])
	return value if value is Array else []

func _short_label() -> String:
	return str(_lesson_config.get("shortLabel", "SHORT %s" % _vowel()))

func _long_label() -> String:
	return str(_lesson_config.get("longLabel", "LONG %s" % _vowel()))

func _format_time(seconds: float) -> String:
	var total_seconds := maxi(0, int(floor(seconds)))
	var minutes := total_seconds / 60
	var remainder := total_seconds % 60
	return "%02d:%02d" % [minutes, remainder]

func _card_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()

	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.05, 0.26, 0.46, 0.42)
	material.roughness = 0.28
	material.emission_enabled = true
	material.emission = Color(0.02, 0.16, 0.30)
	material.emission_energy_multiplier = 0.45
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED

	return material

func _material(albedo: Color, emission: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = 0.58

	if emission != Color.BLACK and emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy

	return material

func _publish() -> void:
	phonics_state_changed.emit(diagnostic_snapshot())