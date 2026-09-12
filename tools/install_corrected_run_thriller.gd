extends SceneTree

const RUN_SOURCE := "res://assets/animations/player/rashad_run_target_native.glb"
const THRILLER_SOURCE := "res://assets/animations/player/rashad_thriller_part1_target_native.glb"
const LOCOMOTION_LIBRARY := "res://game/animations/player/player_locomotion_library.tres"
const ACTION_LIBRARY := "res://game/animations/player/player_action_library.tres"
const TARGET_SKELETON := "Avatar/Armature/Skeleton3D"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var locomotion := load(LOCOMOTION_LIBRARY) as AnimationLibrary
	if locomotion == null: return _fail("LOCOMOTION_LIBRARY")
	for required in [&"Idle", &"Walk", &"Run"]:
		if not locomotion.has_animation(required): return _fail("LOCOMOTION_SCHEMA_%s" % required)
	var idle_before := locomotion.get_animation(&"Idle")
	var walk_before := locomotion.get_animation(&"Walk")
	var run := _extract_target_native(RUN_SOURCE, true)
	if run == null: return
	run.resource_name = "Run"
	locomotion.remove_animation(&"Run")
	if locomotion.add_animation(&"Run", run) != OK: return _fail("RUN_REPLACE")
	if locomotion.get_animation(&"Idle") != idle_before: return _fail("IDLE_CHANGED")
	if locomotion.get_animation(&"Walk") != walk_before: return _fail("WALK_CHANGED")
	if ResourceSaver.save(locomotion, LOCOMOTION_LIBRARY) != OK: return _fail("RUN_LIBRARY_SAVE")

	var thriller := _extract_target_native(THRILLER_SOURCE, false)
	if thriller == null: return
	thriller.resource_name = "ThrillerPart1"
	var actions := AnimationLibrary.new()
	if actions.add_animation(&"ThrillerPart1", thriller) != OK: return _fail("THRILLER_ADD")
	if ResourceSaver.save(actions, ACTION_LIBRARY) != OK: return _fail("ACTION_LIBRARY_SAVE")
	print("RUN_THRILLER_INSTALL: PASS run_tracks=%d run_length=%.3f thriller_tracks=%d thriller_length=%.3f idle_unchanged=true walk_unchanged=true" % [run.get_track_count(), run.length, thriller.get_track_count(), thriller.length])
	quit(0)

func _extract_target_native(path: String, loop: bool) -> Animation:
	var scene := load(path) as PackedScene
	if scene == null:
		_fail("SOURCE_LOAD_%s" % path)
		return null
	var root := scene.instantiate()
	var players := root.find_children("*", "AnimationPlayer", true, false)
	if players.size() != 1:
		root.free(); _fail("ANIMATION_PLAYER_%s" % path); return null
	var found: Array[Animation] = []
	var player := players[0] as AnimationPlayer
	for library_name in player.get_animation_library_list():
		var library := player.get_animation_library(library_name)
		for clip_name in library.get_animation_list():
			if clip_name != &"RESET": found.append(library.get_animation(clip_name))
	if found.size() != 1:
		root.free(); _fail("CLIP_COUNT_%s_%d" % [path, found.size()]); return null
	var animation := found[0].duplicate(true) as Animation
	root.free()
	for track_index in range(animation.get_track_count() - 1, -1, -1):
		if animation.track_get_type(track_index) == Animation.TYPE_SCALE_3D:
			animation.remove_track(track_index)
			continue
		var old_path := str(animation.track_get_path(track_index))
		var separator := old_path.find(":")
		if separator < 0:
			animation.remove_track(track_index)
			continue
		animation.track_set_path(track_index, NodePath(TARGET_SKELETON + old_path.substr(separator)))
		if old_path.ends_with(":Hips") and animation.track_get_type(track_index) == Animation.TYPE_POSITION_3D and animation.track_get_key_count(track_index) > 0:
			var origin: Vector3 = animation.track_get_key_value(track_index, 0)
			for key_index in animation.track_get_key_count(track_index):
				var value: Vector3 = animation.track_get_key_value(track_index, key_index)
				value.x = origin.x; value.z = origin.z
				animation.track_set_key_value(track_index, key_index, value)
	animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return animation

func _fail(boundary: String) -> void:
	push_error("RUN_THRILLER_INSTALL: FAIL " + boundary)
	quit(1)
