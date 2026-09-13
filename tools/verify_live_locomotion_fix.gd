extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var locomotion := load("res://game/animations/player/player_locomotion_library.tres") as AnimationLibrary
	if locomotion == null: return _fail("LOCOMOTION_LIBRARY_MISSING")
	for name in [&"Idle", &"Walk", &"Run"]:
		if not locomotion.has_animation(name): return _fail("MISSING_%s" % String(name).to_upper())
	var walk := locomotion.get_animation(&"Walk")
	var animated_tracks := 0
	for track_index in walk.get_track_count():
		if walk.track_get_key_count(track_index) > 1 and walk.track_get_type(track_index) in [Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D]: animated_tracks += 1
	if walk.get_track_count() < 10 or animated_tracks < 10: return _fail("WALK_NOT_ANIMATED tracks=%d animated=%d" % [walk.get_track_count(), animated_tracks])
	var actions := load("res://game/animations/player/player_action_library.tres") as AnimationLibrary
	if actions == null: return _fail("ACTION_LIBRARY_MISSING")
	print("ACTION_KEYS: ", actions.get_animation_list())
	if not actions.has_animation(&"ThrillerPart1"): return _fail("THRILLER_LIBRARY_KEY_MISSING")
	var thriller := actions.get_animation(&"ThrillerPart1")
	if thriller.get_track_count() < 10: return _fail("THRILLER_TRACKS_%d" % thriller.get_track_count())
	print("LIVE_LOCOMOTION_FIX: PASS walk_tracks=%d walk_animated_tracks=%d thriller_tracks=%d" % [walk.get_track_count(), animated_tracks, thriller.get_track_count()])
	quit(0)

func _fail(reason: String) -> void:
	push_error("LIVE_LOCOMOTION_FIX: FAIL " + reason)
	quit(1)
