extends SceneTree

const LIBRARY_PATH := "res://game/animations/player/player_locomotion_library.tres"
const GAIT_BONES := [&"LeftArm", &"RightArm", &"LeftUpLeg", &"RightUpLeg", &"LeftLeg", &"RightLeg"]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var library := load(LIBRARY_PATH) as AnimationLibrary
	if library == null or not library.has_animation(&"Walk") or not library.has_animation(&"Run"):
		return _fail("LOCOMOTION_MISSING")
	var walk := library.get_animation(&"Walk")
	var run := library.get_animation(&"Run")
	var run_peak := _peak_gait_rotation(run)
	var walk_peak := _peak_gait_rotation(walk)
	print("WALK_QUALITY run_peak_deg=%.3f walk_peak_deg=%.3f run_length=%.3f walk_length=%.3f" % [rad_to_deg(run_peak), rad_to_deg(walk_peak), run.length, walk.length])
	if rad_to_deg(run_peak) < 10.0: return _fail("RUN_REFERENCE_NOT_DYNAMIC")
	if walk_peak < run_peak * 0.90: return _fail("WALK_GAIT_TOO_STATIC")
	if walk.length < run.length * 1.40: return _fail("WALK_CADENCE_NOT_SLOWER")
	if walk.loop_mode != Animation.LOOP_LINEAR: return _fail("WALK_NOT_LOOPING")
	if _hips_xz_span(walk) > 0.0001: return _fail("WALK_ROOT_MOTION_XZ")
	print("PLAYER_WALK_QUALITY_TEST: PASS visible_gait slower_cadence in_place")
	quit(0)

func _peak_gait_rotation(clip: Animation) -> float:
	var peak := 0.0
	for bone_name in GAIT_BONES:
		for track_index in clip.get_track_count():
			if clip.track_get_type(track_index) != Animation.TYPE_ROTATION_3D: continue
			if not str(clip.track_get_path(track_index)).ends_with(":" + String(bone_name)): continue
			if clip.track_get_key_count(track_index) < 2: continue
			var first: Quaternion = clip.track_get_key_value(track_index, 0)
			for key_index in clip.track_get_key_count(track_index):
				var value: Quaternion = clip.track_get_key_value(track_index, key_index)
				peak = maxf(peak, first.angle_to(value))
	return peak

func _hips_xz_span(clip: Animation) -> float:
	for track_index in clip.get_track_count():
		if clip.track_get_type(track_index) != Animation.TYPE_POSITION_3D: continue
		if not str(clip.track_get_path(track_index)).ends_with(":Hips"): continue
		if clip.track_get_key_count(track_index) < 2: return 0.0
		var first: Vector3 = clip.track_get_key_value(track_index, 0)
		var peak := 0.0
		for key_index in clip.track_get_key_count(track_index):
			var value: Vector3 = clip.track_get_key_value(track_index, key_index)
			peak = maxf(peak, Vector2(value.x, value.z).distance_to(Vector2(first.x, first.z)))
		return peak
	return 0.0

func _fail(reason: String) -> void:
	push_error("PLAYER_WALK_QUALITY_TEST: FAIL " + reason)
	quit(1)
