from pathlib import Path

root = Path(__file__).resolve().parents[1]
local_path = root / "scripts/pocketpt/pocketpt_locomotion_animator.gd"
remote_path = root / "scripts/pocketpt/pocketpt_remote_player.gd"
export_path = root / "export_presets.cfg"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"PATCH_BOUNDARY_{label}:{count}")
    return text.replace(old, new, 1)

local = local_path.read_text(encoding="utf-8")
local = replace_once(
    local,
    'const TREE_PATH := "res://game/animations/player/player_locomotion_tree.tres"\n',
    'const TREE_PATH := "res://game/animations/player/player_locomotion_tree.tres"\nconst RestRetarget = preload("res://scripts/pocketpt/pocketpt_animation_rest_retarget.gd")\n',
    'LOCAL_CONST',
)
local = replace_once(
    local,
    'var _walk_displacement_seen := false\n',
    'var _walk_displacement_seen := false\nvar _rest_retarget_tracks := 0\nvar _rest_retarget_keys := 0\n',
    'LOCAL_FIELDS',
)
local = replace_once(
    local,
    '\t_walk_displacement_seen = false\n\tvar skeletons := avatar_root.find_children("*", "Skeleton3D", true, false)',
    '\t_walk_displacement_seen = false\n\t_rest_retarget_tracks = 0\n\t_rest_retarget_keys = 0\n\tvar skeletons := avatar_root.find_children("*", "Skeleton3D", true, false)',
    'LOCAL_RESET',
)
local = replace_once(
    local,
    '''\tvar target_path := str(avatar_root.get_path_to(skeleton))\n\tvar mounted_library := _mount_library(source_library, target_path)\n\tvar mounted_actions := _mount_library(source_actions, target_path)\n\tanimation_player = AnimationPlayer.new(); animation_player.name = "PocketPTLocomotionPlayer"; avatar_root.add_child(animation_player)\n''',
    '''\tvar target_path := str(avatar_root.get_path_to(skeleton))\n\tvar locomotion_result := RestRetarget.mount_library(source_library, target_path, skeleton)\n\tvar action_result := RestRetarget.mount_library(source_actions, target_path, skeleton)\n\tvar retarget_error := str(locomotion_result.get("error", ""))\n\tif retarget_error.is_empty():\n\t\tretarget_error = str(action_result.get("error", ""))\n\tif not retarget_error.is_empty():\n\t\tbinding_error = "ANIMATION_REST_RETARGET_FAILED:%s" % retarget_error\n\t\truntime_evidence_changed.emit()\n\t\treturn\n\tvar mounted_library = locomotion_result.get("library") as AnimationLibrary\n\tvar mounted_actions = action_result.get("library") as AnimationLibrary\n\tif mounted_library == null or mounted_actions == null:\n\t\tbinding_error = "ANIMATION_REST_RETARGET_FAILED:LIBRARY_MISSING"\n\t\truntime_evidence_changed.emit()\n\t\treturn\n\t_rest_retarget_tracks = int(locomotion_result.get("adjustedRotationTracks", 0)) + int(action_result.get("adjustedRotationTracks", 0))\n\t_rest_retarget_keys = int(locomotion_result.get("adjustedRotationKeys", 0)) + int(action_result.get("adjustedRotationKeys", 0))\n\tanimation_player = AnimationPlayer.new(); animation_player.name = "PocketPTLocomotionPlayer"; avatar_root.add_child(animation_player)\n''',
    'LOCAL_MOUNT',
)
old_mount = '''func _mount_library(source: AnimationLibrary, target_path: String) -> AnimationLibrary:\n\tvar mounted := AnimationLibrary.new()\n\tfor clip_name in source.get_animation_list():\n\t\tvar clip := source.get_animation(clip_name).duplicate(true) as Animation\n\t\tfor track_index in clip.get_track_count():\n\t\t\tvar old_path := str(clip.track_get_path(track_index))\n\t\t\tvar separator := old_path.find(":")\n\t\t\tif separator >= 0: clip.track_set_path(track_index, NodePath(target_path + old_path.substr(separator)))\n\t\tmounted.add_animation(clip_name, clip)\n\treturn mounted\n\n'''
local = replace_once(local, old_mount, '', 'LOCAL_OLD_MOUNT')
local = replace_once(
    local,
    '\t\t"currentClip": clip,\n\t\t"physicalMovementObserved": sample.get("physicalMovementObserved", false),\n',
    '\t\t"currentClip": clip,\n\t\t"physicalMovementObserved": sample.get("physicalMovementObserved", false),\n\t\t"restRetargetStatus": "PASS",\n\t\t"restRetargetRotationTracks": _rest_retarget_tracks,\n\t\t"restRetargetRotationKeys": _rest_retarget_keys,\n',
    'LOCAL_DIAGNOSTICS',
)
local_path.write_text(local, encoding="utf-8")

remote = remote_path.read_text(encoding="utf-8")
remote = replace_once(
    remote,
    'const TREE_PATH := "res://game/animations/player/player_locomotion_tree.tres"\n',
    'const TREE_PATH := "res://game/animations/player/player_locomotion_tree.tres"\nconst RestRetarget = preload("res://scripts/pocketpt/pocketpt_animation_rest_retarget.gd")\n',
    'REMOTE_CONST',
)
remote = replace_once(
    remote,
    '''\tvar target_path := str(avatar_root.get_path_to(skeleton))\n\tvar mounted_library := _mount_library(source_library, target_path)\n\tvar mounted_actions := _mount_library(source_actions, target_path)\n\t_animation_player = AnimationPlayer.new()\n''',
    '''\tvar target_path := str(avatar_root.get_path_to(skeleton))\n\tvar locomotion_result := RestRetarget.mount_library(source_library, target_path, skeleton)\n\tvar action_result := RestRetarget.mount_library(source_actions, target_path, skeleton)\n\tvar retarget_error := str(locomotion_result.get("error", ""))\n\tif retarget_error.is_empty():\n\t\tretarget_error = str(action_result.get("error", ""))\n\tif not retarget_error.is_empty():\n\t\tanimation_binding_error = "REMOTE_REST_RETARGET_FAILED:%s" % retarget_error\n\t\treturn false\n\tvar mounted_library = locomotion_result.get("library") as AnimationLibrary\n\tvar mounted_actions = action_result.get("library") as AnimationLibrary\n\tif mounted_library == null or mounted_actions == null:\n\t\tanimation_binding_error = "REMOTE_REST_RETARGET_FAILED:LIBRARY_MISSING"\n\t\treturn false\n\t_animation_player = AnimationPlayer.new()\n''',
    'REMOTE_MOUNT',
)
old_remote_mount = '''func _mount_library(source: AnimationLibrary, target_path: String) -> AnimationLibrary:\n\tvar mounted := AnimationLibrary.new()\n\tfor clip_name in source.get_animation_list():\n\t\tvar clip := source.get_animation(clip_name).duplicate(true) as Animation\n\t\tfor track_index in clip.get_track_count():\n\t\t\tvar old_path := str(clip.track_get_path(track_index))\n\t\t\tvar separator := old_path.find(":")\n\t\t\tif separator >= 0:\n\t\t\t\tclip.track_set_path(track_index, NodePath(target_path + old_path.substr(separator)))\n\t\tmounted.add_animation(clip_name, clip)\n\treturn mounted\n\n'''
remote = replace_once(remote, old_remote_mount, '', 'REMOTE_OLD_MOUNT')
remote_path.write_text(remote, encoding="utf-8")

preset = export_path.read_text(encoding="utf-8")
preset = replace_once(
    preset,
    '"res://scripts/pocketpt/pocketpt_locomotion_animator.gd", "res://scripts/pocketpt/pocketpt_remote_avatar_loader.gd"',
    '"res://scripts/pocketpt/pocketpt_locomotion_animator.gd", "res://scripts/pocketpt/pocketpt_animation_rest_retarget.gd", "res://resources/pocketpt/canonical_avatar_rest_profile.json", "res://scripts/pocketpt/pocketpt_remote_avatar_loader.gd"',
    'EXPORT_ALLOWLIST',
)
export_path.write_text(preset, encoding="utf-8")

print("AVATAR_REST_RETARGET_PATCH: PASS")
