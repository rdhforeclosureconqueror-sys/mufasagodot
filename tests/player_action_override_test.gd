extends SceneTree

const ACTION_LIBRARY := "res://game/animations/player/player_action_library.tres"
const PREVIEW := "res://scenes/characters/rashad1_locomotion_preview.tscn"
const AnimatorScript = preload("res://scripts/pocketpt/pocketpt_locomotion_animator.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var actions := load(ACTION_LIBRARY) as AnimationLibrary
	if actions == null or not actions.has_animation(&"ThrillerPart1"): return _fail("ACTION_LIBRARY")
	var thriller := actions.get_animation(&"ThrillerPart1")
	if thriller.loop_mode != Animation.LOOP_NONE: return _fail("THRILLER_LOOP")
	if absf(thriller.length - 29.8667) > 0.1: return _fail("THRILLER_DURATION")
	var hips_origin := Vector2.ZERO
	var hips_seen := false
	for track_index in thriller.get_track_count():
		if thriller.track_get_type(track_index) == Animation.TYPE_SCALE_3D: return _fail("THRILLER_SCALE")
		if str(thriller.track_get_path(track_index)).ends_with(":Hips") and thriller.track_get_type(track_index) == Animation.TYPE_POSITION_3D:
			for key_index in thriller.track_get_key_count(track_index):
				var value: Vector3 = thriller.track_get_key_value(track_index, key_index)
				if not hips_seen: hips_origin = Vector2(value.x, value.z); hips_seen = true
				elif Vector2(value.x, value.z).distance_to(hips_origin) > 0.0001: return _fail("THRILLER_ROOT_MOTION")
	# A target-native clip may omit hip translation entirely; that is the strongest
	# in-place policy. If present, the loop above requires its horizontal component
	# to remain locked.
	var preview := (load(PREVIEW) as PackedScene).instantiate()
	root.add_child(preview); await process_frame
	preview.play_thriller(); await process_frame
	if preview.animation_tree.active: return _fail("PREVIEW_TREE_NOT_OVERRIDDEN")
	if preview.animation_player.current_animation != &"action/ThrillerPart1": return _fail("PREVIEW_ACTION_NOT_PLAYING")
	preview.animation_player.seek(thriller.length - 0.01, true)
	preview.animation_player.advance(0.02); await process_frame
	if not preview.animation_tree.active or preview.playback.get_current_node() != &"IDLE": return _fail("PREVIEW_RETURN_IDLE")
	preview.queue_free(); await process_frame

	var wrapper := Node3D.new(); root.add_child(wrapper)
	var avatar := (load("res://assets/characters/pocketpt/source/rashad1.glb") as PackedScene).instantiate(); wrapper.add_child(avatar)
	var animator: Node = AnimatorScript.new(); root.add_child(animator); animator._on_avatar_mounted(wrapper)
	if not animator.request_action(&"action/ThrillerPart1"): return _fail("RUNTIME_REQUEST")
	if not animator.action_override_active or animator.animation_tree.active: return _fail("RUNTIME_OVERRIDE")
	animator.animation_player.seek(thriller.length - 0.01, true)
	animator.animation_player.advance(0.02); await process_frame
	if animator.action_override_active or not animator.animation_tree.active or animator.current_state != &"IDLE": return _fail("RUNTIME_RETURN_IDLE")
	print("PLAYER_ACTION_OVERRIDE_TEST: PASS semantic=action/ThrillerPart1 duration=%.3f root_motion=IN_PLACE return=IDLE" % thriller.length)
	quit(0)

func _fail(boundary: String) -> void:
	push_error("PLAYER_ACTION_OVERRIDE_TEST: FAIL " + boundary)
	quit(1)
