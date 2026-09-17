extends "res://scripts/games/underwater_learning_preview.gd"

const PhonicsScript = preload("res://scripts/games/underwater_phonics_component.gd")

var _phonics_component: Node3D

func _ready() -> void:
	state["lessonMode"] = "PHONICS_A_SORT"
	state["phonics"] = {}
	state["controlMode"] = "UNDERWATER_SWIM_OVERRIDE"
	state["swimAnimation"] = "AVAILABLE"
	super._ready()

func _build_entry_gate() -> void:
	super._build_entry_gate()
	var sign := get_node_or_null("UnderwaterLearningEntryGate/UnderwaterLearningSign") as Label3D
	if sign != null:
		sign.text = "UNDERWATER LEARNING\nVOWEL TREASURE QUEST"

func _build_reef_world() -> void:
	super._build_reef_world()
	_remove_make10_assets()
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

func _build_phonics_component() -> void:
	_phonics_component = PhonicsScript.new() as Node3D
	if _phonics_component == null:
		_set_first_failure("PHONICS_COMPONENT", "INSTANTIATION_FAILED")
		return
	_phonics_component.name = "UnderwaterPhonicsComponent"
	_phonics_component.call("configure", _player)
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
