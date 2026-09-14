extends RefCounted

const PROFILE_PATH := "res://resources/pocketpt/canonical_avatar_rest_profile.json"

static var _profile_cache: Dictionary = {}
static var _profile_error := ""

static func mount_library(source: AnimationLibrary, target_path: String, target_skeleton: Skeleton3D) -> Dictionary:
	if source == null:
		return _failure("SOURCE_LIBRARY_MISSING")
	if target_skeleton == null or not is_instance_valid(target_skeleton):
		return _failure("TARGET_SKELETON_MISSING")
	var profile := _load_profile()
	if profile.is_empty():
		return _failure(_profile_error if not _profile_error.is_empty() else "REST_PROFILE_MISSING")
	var bones = profile.get("bones")
	if not bones is Dictionary:
		return _failure("REST_PROFILE_BONES_MISSING")
	var mounted := AnimationLibrary.new()
	var adjusted_tracks := 0
	var adjusted_keys := 0
	for clip_name in source.get_animation_list():
		var source_clip := source.get_animation(clip_name)
		if source_clip == null:
			return _failure("SOURCE_CLIP_MISSING:%s" % String(clip_name))
		var clip := source_clip.duplicate(true) as Animation
		for track_index in clip.get_track_count():
			var old_path := str(clip.track_get_path(track_index))
			var separator := old_path.find(":")
			if separator < 0:
				continue
			var bone_name := old_path.substr(separator + 1)
			clip.track_set_path(track_index, NodePath(target_path + old_path.substr(separator)))
			if clip.track_get_type(track_index) != Animation.TYPE_ROTATION_3D:
				continue
			var source_record = bones.get(bone_name)
			if not source_record is Dictionary:
				return _failure("SOURCE_REST_BONE_MISSING:%s" % bone_name)
			var source_values = source_record.get("quaternion")
			if not source_values is Array or source_values.size() != 4:
				return _failure("SOURCE_REST_QUATERNION_INVALID:%s" % bone_name)
			var target_index := target_skeleton.find_bone(bone_name)
			if target_index < 0:
				return _failure("TARGET_REST_BONE_MISSING:%s" % bone_name)
			var source_rest := Quaternion(float(source_values[0]), float(source_values[1]), float(source_values[2]), float(source_values[3])).normalized()
			var target_rest := target_skeleton.get_bone_global_rest(target_index).basis.get_rotation_quaternion().normalized()
			var key_count := clip.track_get_key_count(track_index)
			for key_index in key_count:
				var value = clip.track_get_key_value(track_index, key_index)
				if typeof(value) != TYPE_QUATERNION:
					return _failure("ROTATION_KEY_INVALID:%s" % bone_name)
				var delta: Quaternion = value
				clip.track_set_key_value(track_index, key_index, retarget_rotation_delta(delta, source_rest, target_rest))
				adjusted_keys += 1
			adjusted_tracks += 1
		mounted.add_animation(clip_name, clip)
	return {
		"library": mounted,
		"error": "",
		"adjustedRotationTracks": adjusted_tracks,
		"adjustedRotationKeys": adjusted_keys,
	}

static func retarget_rotation_delta(delta: Quaternion, source_global_rest: Quaternion, target_global_rest: Quaternion) -> Quaternion:
	var source_rest := source_global_rest.normalized()
	var target_rest := target_global_rest.normalized()
	# Equivalent to the repo's Blender target-native bake:
	# T^-1 * S * delta * S^-1 * T
	return (target_rest.inverse() * source_rest * delta.normalized() * source_rest.inverse() * target_rest).normalized()

static func canonical_rest_for_bone(bone_name: String) -> Quaternion:
	var profile := _load_profile()
	if profile.is_empty():
		return Quaternion(0.0, 0.0, 0.0, 1.0)
	var bones = profile.get("bones")
	if not bones is Dictionary:
		return Quaternion(0.0, 0.0, 0.0, 1.0)
	var record = bones.get(bone_name)
	if not record is Dictionary:
		return Quaternion(0.0, 0.0, 0.0, 1.0)
	var values = record.get("quaternion")
	if not values is Array or values.size() != 4:
		return Quaternion(0.0, 0.0, 0.0, 1.0)
	return Quaternion(float(values[0]), float(values[1]), float(values[2]), float(values[3])).normalized()

static func profile_status() -> Dictionary:
	var profile := _load_profile()
	return {
		"ok": not profile.is_empty(),
		"error": _profile_error,
		"boneCount": int(profile.get("boneCount", 0)) if not profile.is_empty() else 0,
	}

static func _load_profile() -> Dictionary:
	if not _profile_cache.is_empty():
		return _profile_cache
	if not FileAccess.file_exists(PROFILE_PATH):
		_profile_error = "REST_PROFILE_MISSING"
		return {}
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if file == null:
		_profile_error = "REST_PROFILE_OPEN_FAILED"
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		_profile_error = "REST_PROFILE_INVALID_JSON"
		return {}
	if int(parsed.get("version", 0)) != 1:
		_profile_error = "REST_PROFILE_VERSION_UNSUPPORTED"
		return {}
	_profile_cache = parsed
	_profile_error = ""
	return _profile_cache

static func _failure(reason: String) -> Dictionary:
	return {
		"library": null,
		"error": reason,
		"adjustedRotationTracks": 0,
		"adjustedRotationKeys": 0,
	}
