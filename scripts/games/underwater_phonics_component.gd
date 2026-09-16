class_name UnderwaterPhonicsComponent
extends Node3D

signal phonics_state_changed(state: Dictionary)

const VOWEL := "A"
const SHORT_WORDS := ["cap", "tap", "mad", "can", "hat", "map", "rat", "jam", "bat", "plan"]
const LONG_WORDS := ["cape", "tape", "made", "cane", "late", "name", "rake", "game", "bake", "plane"]
const SHORT_BOX_POSITION := Vector3(-4.2, 0.0, 20.0)
const LONG_BOX_POSITION := Vector3(4.2, 0.0, 20.0)
const HOLD_OFFSET := Vector3(0.0, 1.55, -0.85)
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
	Vector3(-10.0, 1.25, -3.0), Vector3(0.0, 1.25, -16.0)
]

var state: Dictionary = {
	"lesson": "PHONICS_A_LONG_SHORT",
	"vowel": VOWEL,
	"status": "READY",
	"totalWords": 20,
	"shortTarget": 10,
	"longTarget": 10,
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
var _word_cards: Dictionary = {}
var _held_card: Area3D
var _held_word: Dictionary = {}
var _round_running := false
var _hud_layer: CanvasLayer
var _title_label: Label
var _mission_label: Label
var _stats_label: Label
var _air_label: Label
var _held_label: Label
var _feedback_label: Label

func configure(player: Node3D) -> void:
	_player = player

func _ready() -> void:
	name = "UnderwaterPhonicsComponent"
	_build_sort_boxes()
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

func start_round() -> void:
	if str(state.get("status", "READY")) == "COMPLETE":
		return
	state["status"] = "ACTIVE"
	state["feedback"] = "Find a word, carry it back, and choose SHORT A or LONG A!"
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

func _build_sort_boxes() -> void:
	_build_sort_box("ShortASortBox", SHORT_BOX_POSITION, "SHORT A", "SHORT")
	_build_sort_box("LongASortBox", LONG_BOX_POSITION, "LONG A", "LONG")
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
	var position_index := 0
	for index in range(SHORT_WORDS.size()):
		_spawn_word_card(str(SHORT_WORDS[index]), "SHORT", WORD_SPAWN_POSITIONS[position_index])
		position_index += 1
		_spawn_word_card(str(LONG_WORDS[index]), "LONG", WORD_SPAWN_POSITIONS[position_index])
		position_index += 1

func _spawn_word_card(word: String, category: String, local_position: Vector3) -> void:
	var card := Area3D.new()
	var card_id := "%s_%s" % [category, word.to_upper()]
	card.name = "PhonicsWord_%s" % card_id
	card.position = local_position
	add_child(card)

	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.9, 0.95, 0.12)
	mesh.material = _card_material()
	visual.mesh = mesh
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
	state["feedback"] = "You found %s! Carry it to the SHORT A or LONG A box." % word.to_upper()
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
	state["feedback"] = "%s! %s A sound!" % [word.to_upper(), category]
	state["lastEvent"] = "PHONICS_SORT_CORRECT_%s_%s" % [category, word.to_upper()]
	state["heldWord"] = ""
	state["heldCategory"] = ""
	_held_word = {}

	var completed_card := _held_card
	_held_card = null
	if completed_card != null and is_instance_valid(completed_card):
		completed_card.queue_free()

	if int(state.get("sortedTotal", 0)) >= int(state.get("totalWords", 20)):
		_round_running = false
		state["status"] = "COMPLETE"
		state["feedback"] = "ALL 20 WORDS FOUND! Time %s • Mistakes %d" % [
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
	panel.custom_minimum_size = Vector2(760, 236)
	_hud_layer.add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.01, 0.035, 0.09, 0.94)
	style.border_color = Color(0.95, 0.72, 0.12)
	style.set_border_width_all(3)
	style.set_corner_radius_all(18)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", style)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	panel.add_child(stack)

	_title_label = _hud_label("VOWEL TREASURE QUEST", 28, Color(1.0, 0.83, 0.20))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_title_label)

	_mission_label = _hud_label("SHORT A  vs  LONG A  •  Find • Carry • Sort", 19, Color(0.62, 0.93, 1.0))
	_mission_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_mission_label)

	_stats_label = _hud_label("", 21, Color.WHITE)
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_stats_label)

	_air_label = _hud_label("", 20, Color(0.42, 0.95, 1.0))
	_air_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_air_label)

	_held_label = _hud_label("", 23, Color(1.0, 0.92, 0.46))
	_held_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_held_label)

	_feedback_label = _hud_label("", 18, Color(0.80, 1.0, 0.72))
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
	_stats_label.text = "SHORT A  %d/10     LONG A  %d/10     FOUND  %d/20     TIME  %s" % [
		int(state.get("shortSorted", 0)),
		int(state.get("longSorted", 0)),
		int(state.get("sortedTotal", 0)),
		elapsed
	]
	var oxygen := int(round(float(state.get("oxygen", 100.0))))
	var air_blocks := int(floor(float(oxygen) / 10.0))
	var air_meter := ""
	for index in range(10):
		air_meter += "●" if index < air_blocks else "○"
	_air_label.text = "AIR  %d%%   %s" % [oxygen, air_meter]
	var held := str(state.get("heldWord", ""))
	_held_label.text = "CARRYING: %s" % (held if not held.is_empty() else "—")
	_feedback_label.text = str(state.get("feedback", ""))

func _validate_structure() -> void:
	if _player == null:
		_set_first_failure("PHONICS_PLAYER", "PLAYER_NOT_CONFIGURED")
	elif not bool(state.get("boxesReady", false)):
		_set_first_failure("PHONICS_BOXES", "SORT_BOXES_MISSING")
	elif _word_cards.size() != 20:
		_set_first_failure("PHONICS_WORDS", "EXPECTED_20_WORD_CARDS_GOT_%d" % _word_cards.size())
	elif SHORT_WORDS.size() != 10 or LONG_WORDS.size() != 10:
		_set_first_failure("PHONICS_CONTENT", "EXPECTED_10_SHORT_AND_10_LONG")

func _set_first_failure(stage: String, reason: String) -> void:
	if str(state.get("firstFailure", "NONE")) != "NONE":
		return
	state["firstFailure"] = "%s:%s" % [stage, reason]
	push_error("UNDERWATER_PHONICS_FIRST_FAILURE %s" % str(state["firstFailure"]))
	_publish()

func _format_time(seconds: float) -> String:
	var total_seconds := maxi(0, int(floor(seconds)))
	var minutes := total_seconds / 60
	var remainder := total_seconds % 60
	return "%02d:%02d" % [minutes, remainder]

func _card_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.07, 0.18, 0.34)
	material.roughness = 0.45
	material.emission_enabled = true
	material.emission = Color(0.03, 0.18, 0.30)
	material.emission_energy_multiplier = 0.65
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
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
