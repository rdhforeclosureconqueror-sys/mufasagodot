extends "res://scripts/games/underwater_learning_preview.gd"

const PhonicsScript = preload("res://scripts/games/underwater_phonics_component.gd")
const VowelCatalog = preload("res://scripts/games/underwater_vowel_lesson_catalog.gd")

var active_vowel := VowelCatalog.DEFAULT_VOWEL
var _lesson_config: Dictionary = {}
var _vowel_selection_source := "ACTIVE_PROPERTY"
var _phonics_component: Node3D

func _ready() -> void:
	var selected_vowel := _resolve_active_vowel()
	_lesson_config = VowelCatalog.lesson(selected_vowel)

	if _lesson_config.is_empty():
		_vowel_selection_source = "DEFAULT_FALLBACK"
		_lesson_config = VowelCatalog.lesson(VowelCatalog.DEFAULT_VOWEL)

	state["lessonMode"] = str(_lesson_config.get("lessonMode", ""))
	state["vowel"] = str(_lesson_config.get("vowel", ""))
	state["lessonConfigVersion"] = int(_lesson_config.get("configVersion", 0))
	state["wallThemeId"] = str(_lesson_config.get("wallThemeId", ""))
	state["rainbowThemeId"] = str(_lesson_config.get("rainbowThemeId", ""))
	state["vowelSelectionSource"] = _vowel_selection_source
	state["wallSlotsReady"] = false
	state["wallSlotCount"] = 0
	state["wallArtApplied"] = false
	state["phonics"] = {}
	state["controlMode"] = "UNDERWATER_SWIM_OVERRIDE"
	state["swimAnimation"] = "AVAILABLE"

	super._ready()

func _resolve_active_vowel() -> String:
	var requested := active_vowel.strip_edges().to_upper()
	_vowel_selection_source = "ACTIVE_PROPERTY"

	if OS.has_feature("web"):
		var web_value = JavaScriptBridge.eval(
			"(new URLSearchParams(window.location.search).get('vowel') || '').toUpperCase()",
			true
		)

		var web_vowel := str(web_value).strip_edges().to_upper()

		if not web_vowel.is_empty():
			requested = web_vowel
			_vowel_selection_source = "WEB_QUERY"

	if VowelCatalog.is_supported(requested):
		return requested

	_vowel_selection_source = "DEFAULT_FALLBACK"
	return VowelCatalog.DEFAULT_VOWEL

func _build_entry_gate() -> void:
	super._build_entry_gate()
	var sign := get_node_or_null("UnderwaterLearningEntryGate/UnderwaterLearningSign") as Label3D
	if sign != null:
		sign.text = "UNDERWATER LEARNING\nVOWEL TREASURE QUEST"

func _build_reef_world() -> void:
	super._build_reef_world()
	_remove_make10_assets()
	_build_vowel_wall_slots()
	_build_phonics_component()
	var title := _reef_root.get_node_or_null("ReefTitle") as Label3D
	if title != null:
		title.text = "VOWEL TREASURE REEF\nFIND • CARRY • SORT THE LOST WORDS"

func _build_hud() -> void:
	super._build_hud()
	if _hud_layer != null:
		_hud_layer.visible = false

func _validate_structure() -> void:
	if _player == null:
		_set_first_failure("REEF_PLAYER_BIND", "PLAYER_NOT_FOUND")
	elif _reef_root == null:
		_set_first_failure("REEF_BUILD", "REEF_ROOT_MISSING")
	elif _entry_area == null:
		_set_first_failure("REEF_ENTRY", "ENTRY_TRIGGER_MISSING")
	elif _return_area == null:
		_set_first_failure("REEF_RETURN", "RETURN_TRIGGER_MISSING")
	elif _phonics_component == null or not is_instance_valid(_phonics_component):
		_set_first_failure("PHONICS_COMPONENT", "COMPONENT_MISSING")
	else:
		var phonics: Dictionary = _phonics_component.call("diagnostic_snapshot")
		if str(phonics.get("firstFailure", "NONE")) != "NONE":
			_set_first_failure("PHONICS_COMPONENT", str(phonics.get("firstFailure", "UNKNOWN")))
		elif int(phonics.get("totalWords", 0)) != 20:
			_set_first_failure("PHONICS_CONTENT", "EXPECTED_20_WORDS")
		elif int(phonics.get("shortTarget", 0)) != 10 or int(phonics.get("longTarget", 0)) != 10:
			_set_first_failure("PHONICS_CONTENT", "EXPECTED_10_SHORT_AND_10_LONG")
		else:
			state["reefReady"] = true
			state["phonics"] = phonics

func _enter_reef() -> bool:
	var entered := super._enter_reef()

	if not entered:
		return false

	_set_swim_override(true)

	if _hud_layer != null:
		_hud_layer.visible = false
	if _phonics_component != null and is_instance_valid(_phonics_component):
		_phonics_component.call("set_oxygen", float(state.get("oxygen", OXYGEN_MAX)))
		_phonics_component.call("start_round")
		state["phonics"] = _phonics_component.call("diagnostic_snapshot")
		state["lastEvent"] = "PHONICS_REEF_ENTERED"
		_publish()
	return true

func _return_to_gym() -> void:
	if _phonics_component != null and is_instance_valid(_phonics_component):
		_phonics_component.call("pause_round")

	_set_swim_override(false)

	super._return_to_gym()
	if _hud_layer != null:
		_hud_layer.visible = false

func _update_hud() -> void:
	if _phonics_component == null or not is_instance_valid(_phonics_component):
		return
	_phonics_component.call("set_oxygen", float(state.get("oxygen", OXYGEN_MAX)))

func _build_vowel_wall_slots() -> void:
	var wall_art_value = _lesson_config.get("wallArt", {})
	var wall_art: Dictionary = wall_art_value if wall_art_value is Dictionary else {}

	var applied_count := 0

	applied_count += _build_vowel_wall_slot(
		"VowelWallArtFar",
		Vector3(0.0, 3.45, -25.58),
		Vector2(31.5, 5.4),
		Vector3.ZERO,
		str(wall_art.get("far", ""))
	)

	applied_count += _build_vowel_wall_slot(
		"VowelWallArtNear",
		Vector3(0.0, 3.45, 25.58),
		Vector2(31.5, 5.4),
		Vector3(0.0, 180.0, 0.0),
		str(wall_art.get("near", ""))
	)

	applied_count += _build_vowel_wall_slot(
		"VowelWallArtLeft",
		Vector3(-16.58, 3.45, 0.0),
		Vector2(50.5, 5.4),
		Vector3(0.0, 90.0, 0.0),
		str(wall_art.get("left", ""))
	)

	applied_count += _build_vowel_wall_slot(
		"VowelWallArtRight",
		Vector3(16.58, 3.45, 0.0),
		Vector2(50.5, 5.4),
		Vector3(0.0, -90.0, 0.0),
		str(wall_art.get("right", ""))
	)

	state["wallSlotCount"] = 4
	state["wallSlotsReady"] = (
		_reef_root.get_node_or_null("VowelWallArtFar") != null
		and _reef_root.get_node_or_null("VowelWallArtNear") != null
		and _reef_root.get_node_or_null("VowelWallArtLeft") != null
		and _reef_root.get_node_or_null("VowelWallArtRight") != null
	)
	state["wallArtApplied"] = applied_count > 0

func _build_vowel_wall_slot(
	node_name: String,
	local_position: Vector3,
	panel_size: Vector2,
	rotation_degrees_value: Vector3,
	texture_path: String
) -> int:
	var panel := MeshInstance3D.new()
	panel.name = node_name
	panel.position = local_position
	panel.rotation_degrees = rotation_degrees_value

	var quad := QuadMesh.new()
	quad.size = panel_size

	var material := StandardMaterial3D.new()
	material.roughness = 0.42
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var applied := 0
	var normalized_path := texture_path.strip_edges()

	if not normalized_path.is_empty() and ResourceLoader.exists(normalized_path):
		var texture = load(normalized_path)

		if texture is Texture2D:
			material.albedo_texture = texture as Texture2D
			material.albedo_color = Color.WHITE
			material.emission_enabled = true
			material.emission_texture = texture as Texture2D
			material.emission = Color(0.32, 0.32, 0.32)
			material.emission_energy_multiplier = 0.28
			panel.visible = true
			applied = 1
		else:
			panel.visible = false
	else:
		# Slots exist now, but stay invisible until approved art paths are supplied.
		material.albedo_color = Color(0.08, 0.18, 0.24, 0.0)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		panel.visible = false

	quad.material = material
	panel.mesh = quad
	_reef_root.add_child(panel)

	return applied

func _build_phonics_component() -> void:
	_phonics_component = PhonicsScript.new() as Node3D
	if _phonics_component == null:
		_set_first_failure("PHONICS_COMPONENT", "INSTANTIATION_FAILED")
		return
	_phonics_component.name = "UnderwaterPhonicsComponent"
	_phonics_component.call("configure", _player, _lesson_config)
	_phonics_component.connect("phonics_state_changed", Callable(self, "_on_phonics_state_changed"))
	_reef_root.add_child(_phonics_component)

func _remove_make10_assets() -> void:
	for value in _number_orbs.keys():
		var orb = _number_orbs[value]
		if orb != null and is_instance_valid(orb):
			if orb.get_parent() != null:
				orb.get_parent().remove_child(orb)
			orb.queue_free()
	_number_orbs.clear()

	var chest := _reef_root.get_node_or_null("Make10TreasureChest")
	if chest != null:
		_reef_root.remove_child(chest)
		chest.queue_free()

func _set_swim_override(enabled: bool) -> bool:
	var animator := get_tree().root.find_child(
		"PocketPTLocomotionAnimator",
		true,
		false
	)

	if animator == null:
		state["swimAnimation"] = "AVAILABLE"
		return false

	if enabled:
		var activated := bool(
			animator.call(
				"set_environment_locomotion_override",
				&"Swimming"
			)
		)

		state["swimAnimation"] = "ACTIVE" if activated else "AVAILABLE"

		if activated:
			state["lastEvent"] = "UNDERWATER_SWIM_ACTIVE"

		return activated

	animator.call("clear_environment_locomotion_override")
	state["swimAnimation"] = "AVAILABLE"

	return true

func _on_phonics_state_changed(snapshot: Dictionary) -> void:
	state["phonics"] = snapshot.duplicate(true)
	var phonics_event := str(snapshot.get("lastEvent", "NONE"))
	if phonics_event != "NONE":
		state["lastEvent"] = phonics_event
	_publish()
