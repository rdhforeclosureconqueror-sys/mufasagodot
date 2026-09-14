extends SceneTree

const RestRetarget = preload("res://scripts/pocketpt/pocketpt_animation_rest_retarget.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_test_profile()
	_test_rotation_conversion()
	_test_library_mount()
	if failures.is_empty():
		print("POCKETPT_ANIMATION_REST_RETARGET_TEST: PASS")
		quit(0)
		return
	for failure in failures:
		push_error("POCKETPT_ANIMATION_REST_RETARGET_TEST: %s" % failure)
	quit(1)

func _test_profile() -> void:
	var status := RestRetarget.profile_status()
	_expect(bool(status.get("ok", false)), "canonical rest profile loads")
	_expect(int(status.get("boneCount", 0)) >= 50, "canonical rest profile contains full humanoid skeleton")
	for bone_name in ["LeftArm", "LeftForeArm", "RightArm", "RightForeArm"]:
		var q := RestRetarget.canonical_rest_for_bone(bone_name)
		_expect(absf(q.dot(Quaternion(0.0, 0.0, 0.0, 1.0))) < 0.999, "%s has explicit non-identity canonical rest basis" % bone_name)

func _test_rotation_conversion() -> void:
	var source_rest := RestRetarget.canonical_rest_for_bone("LeftForeArm")
	var delta := Quaternion(Vector3(1.0, 0.0, 0.0), 0.55).normalized()
	var unchanged := RestRetarget.retarget_rotation_delta(delta, source_rest, source_rest)
	_expect(_same_rotation(unchanged, delta), "matching rest bases preserve rotation delta")
	var target_rest := (Quaternion(Vector3(0.0, 1.0, 0.0), 0.72) * source_rest).normalized()
	var converted := RestRetarget.retarget_rotation_delta(delta, source_rest, target_rest)
	_expect(not _same_rotation(converted, delta), "different rest bases convert rotation axis")
	var round_trip := RestRetarget.retarget_rotation_delta(converted, target_rest, source_rest)
	_expect(_same_rotation(round_trip, delta), "rest-space conversion is reversible")

func _test_library_mount() -> void:
	var source_rest := RestRetarget.canonical_rest_for_bone("LeftForeArm")
	var target_rest := (Quaternion(Vector3(0.0, 1.0, 0.0), 0.42) * source_rest).normalized()
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("LeftForeArm")
	skeleton.set_bone_rest(0, Transform3D(Basis(target_rest), Vector3.ZERO))
	var source := AnimationLibrary.new()
	var clip := Animation.new()
	var track := clip.add_track(Animation.TYPE_ROTATION_3D)
	clip.track_set_path(track, NodePath("Canonical:LeftForeArm"))
	var delta := Quaternion(Vector3(1.0, 0.0, 0.0), 0.35).normalized()
	clip.rotation_track_insert_key(track, 0.0, delta)
	source.add_animation(&"Probe", clip)
	var result := RestRetarget.mount_library(source, "TargetSkeleton", skeleton)
	_expect(str(result.get("error", "")).is_empty(), "synthetic library mounts without retarget error")
	_expect(int(result.get("adjustedRotationTracks", 0)) == 1, "one synthetic rotation track adjusted")
	_expect(int(result.get("adjustedRotationKeys", 0)) == 1, "one synthetic rotation key adjusted")
	var mounted = result.get("library") as AnimationLibrary
	_expect(mounted != null and mounted.has_animation(&"Probe"), "mounted retarget library returned")
	if mounted == null or not mounted.has_animation(&"Probe"):
		return
	var mounted_clip := mounted.get_animation(&"Probe")
	_expect(str(mounted_clip.track_get_path(0)) == "TargetSkeleton:LeftForeArm", "track path points at personalized skeleton")
	var actual: Quaternion = mounted_clip.track_get_key_value(0, 0)
	var expected := RestRetarget.retarget_rotation_delta(delta, source_rest, target_rest)
	_expect(_same_rotation(actual, expected), "mounted key uses rest-space converted rotation")

func _same_rotation(a: Quaternion, b: Quaternion) -> bool:
	return absf(a.normalized().dot(b.normalized())) > 0.99999

func _expect(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
