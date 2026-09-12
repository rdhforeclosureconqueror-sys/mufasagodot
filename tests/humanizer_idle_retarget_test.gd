extends SceneTree

const ClientScript = preload("res://scripts/pocketpt/pocketpt_game_client.gd")
const LoaderScript = preload("res://scripts/pocketpt/pocketpt_avatar_loader.gd")
const BinderScript = preload("res://scripts/pocketpt/pocketpt_humanizer_idle_binder.gd")
const PERSONAL_AVATAR_PATH := "res://blender/private-reference/personal-avatar.glb"

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var mount := Node3D.new(); root.add_child(mount)
	var client := ClientScript.new(); root.add_child(client)
	var loader := LoaderScript.new(); root.add_child(loader); loader._visual_mount = mount
	var binder := BinderScript.new(); root.add_child(binder); binder.bind(client, loader)
	client.bootstrap_accepted.emit(_bootstrap())
	var bytes := FileAccess.get_file_as_bytes(PERSONAL_AVATAR_PATH)
	loader.import_buffer_for_test(bytes, "personal-test", {"avatarId": "personal-test", "profileVersion": "0123456789abcdef0123456789abcdef"})
	await process_frame; await process_frame
	var result: Dictionary = binder.diagnostics
	print("HUMANIZER_IDLE_DIAGNOSTICS: ", result)
	if str(result.get("FIRST_FAILURE", "")) != "RETARGET_BOUND" or str(result.get("mapping_error", "")) != "RUNTIME_GLTF_RETARGET_IMPORT_STEP_UNAVAILABLE":
		push_error("Unexpected first failure: %s (%s)" % [result.get("FIRST_FAILURE"), result.get("mapping_error")]); quit(1); return
	if int(result.get("mapping_count", 0)) != 20 or not ResourceLoader.exists(BinderScript.BONE_MAP_PATH):
		push_error("Saved BoneMap evidence missing"); quit(1); return
	if binder.animation_player != null or bool(result.get("CLIP_PLAYING", false)):
		push_error("Unsafe direct-track playback was requested"); quit(1); return
	print("HUMANIZER_IDLE_SAVED_MAPPING_SAFETY_TEST: PASS")
	quit(0)

func _bootstrap() -> Dictionary:
	var names := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]
	var canonical := {}
	for bone in names: canonical[bone] = bone
	return {
		"gymMappingState": {"status": "AVAILABLE", "schemaVersion": 1, "profileId": "personalized-gym-map-v1"},
		"gymMappingProfile": {"schemaVersion": 1, "profileId": "personalized-gym-map-v1", "avatarId": "personal-test", "skeletonProfile": "avaturn", "canonicalMap": canonical, "restPoseValid": true},
	}
