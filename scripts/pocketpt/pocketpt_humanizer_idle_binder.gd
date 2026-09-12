class_name PocketPTHumanizerIdleBinder
extends Node

const DONOR_LIBRARY_PATH := "res://addons/humanizer/data/animations/animations.glb"
const DONOR_PROFILE_PATH := "res://addons/humanizer/data/animations/apose_skeleton_profile.res"
const BONE_MAP_PATH := "res://resources/pocketpt/personalized_avatar_humanizer_bone_map.tres"
const IDLE_CLIP := &"Idle"
const REQUIRED_JOINTS := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]
const PROFILE_NAMES := {
	"Hips": &"Hips", "Spine": &"Spine", "Spine1": &"Chest", "Spine2": &"UpperChest", "Neck": &"Neck", "Head": &"Head",
	"LeftShoulder": &"LeftShoulder", "LeftArm": &"LeftUpperArm", "LeftForeArm": &"LeftLowerArm", "LeftHand": &"LeftHand",
	"RightShoulder": &"RightShoulder", "RightArm": &"RightUpperArm", "RightForeArm": &"RightLowerArm", "RightHand": &"RightHand",
	"LeftUpLeg": &"LeftUpperLeg", "LeftLeg": &"LeftLowerLeg", "LeftFoot": &"LeftFoot", "RightUpLeg": &"RightUpperLeg", "RightLeg": &"RightLowerLeg", "RightFoot": &"RightFoot",
}
const BOUNDARIES := ["BOOTSTRAP_MAPPING_PRESENT", "PERSONAL_AVATAR_MOUNTED", "PERSONAL_SKELETON_FOUND", "SAVED_MAP_SCHEMA_VALID", "SAVED_BONES_EXIST", "HUMANOID_PROFILE_RESOLVED", "PROFILE_NAME_TRANSLATION_RESOLVED", "GODOT_BONEMAP_CREATED", "IDLE_CLIP_RESOLVED", "RETARGET_BOUND", "CLIP_PLAYING"]

var diagnostics := {
	"BOOTSTRAP_MAPPING_PRESENT": false, "PERSONAL_AVATAR_MOUNTED": false, "PERSONAL_SKELETON_FOUND": false,
	"SAVED_MAP_SCHEMA_VALID": false, "SAVED_BONES_EXIST": false, "HUMANOID_PROFILE_RESOLVED": false,
	"PROFILE_NAME_TRANSLATION_RESOLVED": false, "GODOT_BONEMAP_CREATED": false, "IDLE_CLIP_RESOLVED": false,
	"RETARGET_BOUND": false, "CLIP_PLAYING": false, "FIRST_FAILURE": "BOOTSTRAP_MAPPING_PRESENT", "profile_id": "",
	"mapping_count": 0, "skeleton_path": "", "bone_map_path": BONE_MAP_PATH, "animation_player_path": "",
	"mapped_tracks": 0, "disabled_tracks": PackedStringArray(), "mapping_error": "",
}
var animation_player: AnimationPlayer
var _mapping_state: Dictionary = {}
var _mapping_profile: Dictionary = {}
var _avatar_root: Node3D

func bind(client: PocketPTGameClient, avatar_loader: PocketPTAvatarLoader) -> void:
	client.bootstrap_accepted.connect(_on_bootstrap_accepted)
	avatar_loader.avatar_mounted.connect(_on_avatar_mounted)
	if not client.bootstrap.is_empty(): _on_bootstrap_accepted(client.bootstrap)

func _process(_delta: float) -> void:
	if animation_player != null and is_instance_valid(animation_player):
		diagnostics["CLIP_PLAYING"] = animation_player.is_playing() and animation_player.current_animation == String(IDLE_CLIP)
	_update_first_failure()

func _on_bootstrap_accepted(payload: Dictionary) -> void:
	_mapping_state = payload.get("gymMappingState", {}) if payload.get("gymMappingState") is Dictionary else {}
	_mapping_profile = payload.get("gymMappingProfile", {}) if payload.get("gymMappingProfile") is Dictionary else {}
	diagnostics["BOOTSTRAP_MAPPING_PRESENT"] = str(_mapping_state.get("status", "")) == "AVAILABLE" and not _mapping_profile.is_empty()
	diagnostics["profile_id"] = str(_mapping_profile.get("profileId", ""))
	if _avatar_root != null and is_instance_valid(_avatar_root): _attempt_bind()
	else: _update_first_failure()

func _on_avatar_mounted(avatar_root: Node3D) -> void:
	_avatar_root = avatar_root
	diagnostics["PERSONAL_AVATAR_MOUNTED"] = avatar_root != null and is_instance_valid(avatar_root)
	_attempt_bind()

func _attempt_bind() -> void:
	_reset_attempt_state()
	if not bool(diagnostics["BOOTSTRAP_MAPPING_PRESENT"]) or not bool(diagnostics["PERSONAL_AVATAR_MOUNTED"]): _update_first_failure(); return
	var skeletons := _avatar_root.find_children("*", "Skeleton3D", true, false)
	diagnostics["PERSONAL_SKELETON_FOUND"] = not skeletons.is_empty()
	if skeletons.is_empty(): _update_first_failure(); return
	var skeleton := skeletons[0] as Skeleton3D
	diagnostics["skeleton_path"] = str(skeleton.get_path())
	var canonical_map = _mapping_profile.get("canonicalMap")
	diagnostics["SAVED_MAP_SCHEMA_VALID"] = _validate_schema(canonical_map)
	if not bool(diagnostics["SAVED_MAP_SCHEMA_VALID"]): _update_first_failure(); return
	var saved_map: Dictionary = canonical_map
	for canonical in REQUIRED_JOINTS:
		if skeleton.find_bone(StringName(saved_map[canonical])) < 0:
			diagnostics["mapping_error"] = "SAVED_BONE_NOT_FOUND:%s=%s" % [canonical, saved_map[canonical]]; _update_first_failure(); return
	diagnostics["SAVED_BONES_EXIST"] = true
	var profile := load(DONOR_PROFILE_PATH) as SkeletonProfile
	diagnostics["HUMANOID_PROFILE_RESOLVED"] = profile != null
	if profile == null: _update_first_failure(); return
	for canonical in REQUIRED_JOINTS:
		if not PROFILE_NAMES.has(canonical) or profile.find_bone(PROFILE_NAMES[canonical]) < 0:
			diagnostics["mapping_error"] = "PROFILE_NAME_UNRESOLVED:%s" % canonical; _update_first_failure(); return
	diagnostics["PROFILE_NAME_TRANSLATION_RESOLVED"] = true
	var bone_map := BoneMap.new()
	bone_map.profile = profile
	for canonical in REQUIRED_JOINTS: bone_map.set_skeleton_bone_name(PROFILE_NAMES[canonical], StringName(saved_map[canonical]))
	diagnostics["mapping_count"] = REQUIRED_JOINTS.size()
	var save_error := ResourceSaver.save(bone_map, BONE_MAP_PATH)
	if save_error != OK and not OS.has_feature("web"):
		diagnostics["mapping_error"] = "BONEMAP_SAVE_FAILED:%s" % error_string(save_error); _update_first_failure(); return
	diagnostics["GODOT_BONEMAP_CREATED"] = true
	var donor_library := load(DONOR_LIBRARY_PATH) as AnimationLibrary
	diagnostics["IDLE_CLIP_RESOLVED"] = donor_library != null and donor_library.has_animation(IDLE_CLIP)
	if not bool(diagnostics["IDLE_CLIP_RESOLVED"]): _update_first_failure(); return
	# PR #796 proves bone identity and owner-reviewed source rest pose, but it does
	# not transport normalized rest transforms. MixaBridge's existing rest_fixer is
	# an editor import step; GLTFDocument.append_from_buffer() bypasses that step.
	# Renaming donor tracks here was visually proven unsafe, so do not pose the
	# personalized avatar until that same rest-fix is available to runtime imports.
	diagnostics["mapping_error"] = "RUNTIME_GLTF_RETARGET_IMPORT_STEP_UNAVAILABLE"
	_update_first_failure()

func _validate_schema(canonical_map: Variant) -> bool:
	if int(_mapping_state.get("schemaVersion", 0)) != 1 or int(_mapping_profile.get("schemaVersion", 0)) != 1: diagnostics["mapping_error"] = "SCHEMA_VERSION_UNSUPPORTED"; return false
	if str(_mapping_state.get("profileId", "")) != str(_mapping_profile.get("profileId", "")): diagnostics["mapping_error"] = "PROFILE_ID_MISMATCH"; return false
	if _mapping_profile.get("restPoseValid") != true or not canonical_map is Dictionary: diagnostics["mapping_error"] = "PROFILE_NOT_MEMBER_VALIDATED"; return false
	var saved_map: Dictionary = canonical_map
	if saved_map.size() != REQUIRED_JOINTS.size(): diagnostics["mapping_error"] = "CANONICAL_MAP_COUNT:%d" % saved_map.size(); return false
	var unique := {}
	for canonical in REQUIRED_JOINTS:
		var raw := str(saved_map.get(canonical, "")).strip_edges()
		if raw.is_empty() or unique.has(raw): diagnostics["mapping_error"] = "MISSING_OR_DUPLICATE:%s" % canonical; return false
		unique[raw] = true
	return true

func _reset_attempt_state() -> void:
	for boundary in BOUNDARIES:
		if boundary not in ["BOOTSTRAP_MAPPING_PRESENT", "PERSONAL_AVATAR_MOUNTED"]: diagnostics[boundary] = false
	diagnostics["mapping_error"] = ""; diagnostics["mapped_tracks"] = 0; diagnostics["disabled_tracks"] = PackedStringArray()

func _update_first_failure() -> void:
	for boundary in BOUNDARIES:
		if not bool(diagnostics[boundary]): diagnostics["FIRST_FAILURE"] = boundary; return
	diagnostics["FIRST_FAILURE"] = "NONE"
