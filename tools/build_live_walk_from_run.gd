extends SceneTree

const LIBRARY_PATH := "res://game/animations/player/player_locomotion_library.tres"
const CADENCE_STRETCH := 1.55

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var library := load(LIBRARY_PATH) as AnimationLibrary
	if library == null: return _fail("LIBRARY_MISSING")
	if not library.has_animation(&"Idle") or not library.has_animation(&"Walk") or not library.has_animation(&"Run"):
		return _fail("LOCOMOTION_SCHEMA")
	var idle_before := library.get_animation(&"Idle")
	var run := library.get_animation(&"Run")
	if run == null or run.get_track_count() == 0 or run.length <= 0.0: return _fail("RUN_INVALID")
	var walk := run.duplicate(true) as Animation
	if walk == null: return _fail("RUN_DUPLICATE")
	# Stretch the proven target-native Run gait into a slower locomotion cycle.
	# World translation still comes exclusively from CharacterBody3D at WALK speed.
	walk.length = run.length * CADENCE_STRETCH
	for track_index in walk.get_track_count():
		for key_index in range(walk.track_get_key_count(track_index) - 1, -1, -1):
			var old_time := walk.track_get_key_time(track_index, key_index)
			walk.track_set_key_time(track_index, key_index, old_time * CADENCE_STRETCH)
	walk.loop_mode = Animation.LOOP_LINEAR
	walk.resource_name = "Walk"
	library.remove_animation(&"Walk")
	if library.add_animation(&"Walk", walk) != OK: return _fail("WALK_ADD")
	if library.get_animation(&"Idle") != idle_before: return _fail("IDLE_CHANGED")
	if library.get_animation(&"Run") != run: return _fail("RUN_CHANGED")
	var save_error := ResourceSaver.save(library, LIBRARY_PATH)
	if save_error != OK: return _fail("SAVE_%s" % error_string(save_error))
	print("LIVE_WALK_BUILD: PASS source=player/Run stretch=%.2f run_length=%.3f walk_length=%.3f tracks=%d" % [CADENCE_STRETCH, run.length, walk.length, walk.get_track_count()])
	quit(0)

func _fail(reason: String) -> void:
	push_error("LIVE_WALK_BUILD: FAIL " + reason)
	quit(1)
