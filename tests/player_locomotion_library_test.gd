extends SceneTree

const LIBRARY_PATH := "res://game/animations/player/player_locomotion_library.tres"
const TREE_PATH := "res://game/animations/player/player_locomotion_tree.tres"
const PREVIEW_PATH := "res://scenes/characters/rashad1_locomotion_preview.tscn"
const AnimatorScript = preload("res://scripts/pocketpt/pocketpt_locomotion_animator.gd")

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var library := load(LIBRARY_PATH) as AnimationLibrary
	var machine := load(TREE_PATH) as AnimationNodeStateMachine
	var preview_scene := load(PREVIEW_PATH) as PackedScene
	if library == null or machine == null or preview_scene == null: return _fail("RESOURCES")
	for clip_name in [&"Idle", &"Walk", &"Run"]:
		if not library.has_animation(clip_name): return _fail("CLIP_%s" % clip_name)
		var clip := library.get_animation(clip_name)
		if clip.loop_mode != Animation.LOOP_LINEAR: return _fail("LOOP_%s" % clip_name)
		var hips_xz := Vector2.ZERO
		var hips_seen := false
		for track_index in clip.get_track_count():
			if str(clip.track_get_path(track_index)).get_slice(":", 0) == ".": return _fail("WORLD_ROOT_TRACK_%s" % clip_name)
			if str(clip.track_get_path(track_index)).ends_with(":Hips") and clip.track_get_type(track_index) == Animation.TYPE_POSITION_3D:
				for key_index in clip.track_get_key_count(track_index):
					var value: Vector3 = clip.track_get_key_value(track_index, key_index)
					if not hips_seen: hips_xz = Vector2(value.x, value.z); hips_seen = true
					elif clip_name != &"Idle" and Vector2(value.x, value.z).distance_to(hips_xz) > 0.0001: return _fail("ROOT_MOTION_%s" % clip_name)
		if clip_name == &"Idle" and not hips_seen: return _fail("HIPS_TRACK_%s" % clip_name)
	var preview := preview_scene.instantiate(); root.add_child(preview)
	await process_frame
	var tree := preview.get_node("AnimationTree") as AnimationTree
	var playback := tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	for state in [&"IDLE", &"WALK", &"RUN", &"WALK", &"IDLE"]:
		playback.travel(state)
		for frame in 20:
			tree.advance(0.05)
			await process_frame
		if playback.get_current_node() != state: return _fail("STATE_%s" % state)
	preview.queue_free(); await process_frame
	var wrapper := Node3D.new(); root.add_child(wrapper)
	var avatar := (load("res://assets/characters/pocketpt/source/rashad1.glb") as PackedScene).instantiate(); wrapper.add_child(avatar)
	var animator: Node = AnimatorScript.new(); root.add_child(animator); animator._on_avatar_mounted(wrapper)
	animator._on_locomotion_sampled({"actualHorizontalDisplacement":0.0, "movementMode":"WALK"})
	if animator.current_state != &"IDLE": return _fail("RUNTIME_IDLE")
	animator._on_locomotion_sampled({"actualHorizontalDisplacement":0.08, "movementMode":"WALK"})
	if animator.current_state != &"WALK": return _fail("RUNTIME_WALK")
	animator._on_locomotion_sampled({"actualHorizontalDisplacement":0.13, "movementMode":"RUN"})
	if animator.current_state != &"RUN": return _fail("RUNTIME_RUN")
	animator._on_locomotion_sampled({"actualHorizontalDisplacement":0.0, "movementMode":"RUN"})
	if animator.current_state != &"IDLE": return _fail("RUNTIME_STOP_IDLE")
	print("PLAYER_LOCOMOTION_TEST: PASS clips=player/Idle,player/Walk,player/Run root_motion=IN_PLACE transitions=IDLE-WALK-RUN")
	quit(0)

func _fail(boundary: String) -> void:
	push_error("PLAYER_LOCOMOTION_TEST: FAIL " + boundary); quit(1)
