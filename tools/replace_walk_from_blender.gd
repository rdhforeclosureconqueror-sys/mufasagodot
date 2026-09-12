extends SceneTree

const SOURCE_PATH := "res://assets/animations/player/rashad_walk_corrected.glb"
const LIBRARY_PATH := "res://game/animations/player/player_locomotion_library.tres"
const TARGET_SKELETON_PATH := "Avatar/Armature/Skeleton3D"

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var source_scene := load(SOURCE_PATH) as PackedScene
	var library := load(LIBRARY_PATH) as AnimationLibrary
	if source_scene == null or library == null: return _fail("INPUT_RESOURCE")
	if not library.has_animation(&"Idle") or not library.has_animation(&"Run") or not library.has_animation(&"Walk"): return _fail("LOCOMOTION_LIBRARY_SCHEMA")
	var idle_before := library.get_animation(&"Idle")
	var run_before := library.get_animation(&"Run")
	var source_root := source_scene.instantiate()
	var players := source_root.find_children("*", "AnimationPlayer", true, false)
	if players.size() != 1: return _fail("CORRECTED_ANIMATION_PLAYER")
	var source_player := players[0] as AnimationPlayer
	var corrected: Animation
	for library_name in source_player.get_animation_library_list():
		var source_library := source_player.get_animation_library(library_name)
		for clip_name in source_library.get_animation_list():
			if corrected != null: return _fail("CORRECTED_CLIP_AMBIGUOUS")
			corrected = source_library.get_animation(clip_name).duplicate(true)
	if corrected == null: return _fail("CORRECTED_CLIP_MISSING")
	for track_index in corrected.get_track_count():
		var path := str(corrected.track_get_path(track_index))
		var separator := path.find(":")
		if separator < 0: return _fail("NON_SKELETON_TRACK")
		if corrected.track_get_type(track_index) == Animation.TYPE_SCALE_3D: return _fail("SCALE_TRACK")
		corrected.track_set_path(track_index, NodePath(TARGET_SKELETON_PATH + path.substr(separator)))
		if path.ends_with(":Hips") and corrected.track_get_type(track_index) == Animation.TYPE_POSITION_3D and corrected.track_get_key_count(track_index) > 0:
			var origin: Vector3 = corrected.track_get_key_value(track_index, 0)
			for key_index in corrected.track_get_key_count(track_index):
				var position: Vector3 = corrected.track_get_key_value(track_index, key_index)
				position.x = origin.x; position.z = origin.z
				corrected.track_set_key_value(track_index, key_index, position)
	corrected.loop_mode = Animation.LOOP_LINEAR
	corrected.resource_name = "Walk"
	library.remove_animation(&"Walk")
	if library.add_animation(&"Walk", corrected) != OK: return _fail("LIBRARY_REPLACE")
	if library.get_animation(&"Idle") != idle_before or library.get_animation(&"Run") != run_before: return _fail("IDLE_OR_RUN_CHANGED")
	var error := ResourceSaver.save(library, LIBRARY_PATH)
	if error != OK: return _fail("SAVE:%s" % error_string(error))
	print("CORRECTED_WALK_REPLACE: PASS source_clip=Animation semantic=player/Walk tracks=%d length=%.3f idle_unchanged=true run_unchanged=true" % [corrected.get_track_count(), corrected.length])
	quit(0)

func _fail(boundary: String) -> void:
	push_error("CORRECTED_WALK_REPLACE: FAIL " + boundary); quit(1)
