#!/usr/bin/env python3
"""Create an original, in-place PocketPT walk-cycle candidate in Blender.

Run with Blender, not system Python:
  blender --background --python pocketpt_blender_walk_v1.py -- \
    --avatar input.glb --output pocketpt_walk_v1.glb

The script never reads a reference animation. It adds a small authored walk
cycle to the supplied humanoid rig, exports a new GLB, and writes a JSON report.
It fails closed when required limb bones cannot be identified.
"""

import argparse
import json
import math
import os
import sys
import traceback
from pathlib import Path

import bpy
from mathutils import Quaternion, Vector


ACTION_NAME = "pocketpt_walk_in_place_v1"
FPS = 24
LAST_FRAME = 25


ALIASES = {
    "hips": ["hips", "pelvis"],
    "spine": ["spine", "spine1"],
    "left_thigh": ["leftupleg", "leftthigh", "thighl", "upperlegl"],
    "right_thigh": ["rightupleg", "rightthigh", "thighr", "upperlegr"],
    "left_shin": ["leftleg", "leftlowerleg", "leftshin", "calfl", "lowerlegl"],
    "right_shin": ["rightleg", "rightlowerleg", "rightshin", "calfr", "lowerlegr"],
    "left_foot": ["leftfoot", "footl"],
    "right_foot": ["rightfoot", "footr"],
    "left_arm": ["leftarm", "leftupperarm", "upperarml"],
    "right_arm": ["rightarm", "rightupperarm", "upperarmr"],
    "left_forearm": ["leftforearm", "leftlowerarm", "forearml", "lowerarml"],
    "right_forearm": ["rightforearm", "rightlowerarm", "forearmr", "lowerarmr"],
}

REQUIRED = [
    "hips", "left_thigh", "right_thigh", "left_shin", "right_shin",
    "left_foot", "right_foot", "left_arm", "right_arm",
]


def normalized(name):
    return "".join(ch for ch in str(name).lower() if ch.isalnum())


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--avatar", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--report")
    parser.add_argument("--blend")
    parser.add_argument("--force", action="store_true")
    return parser.parse_args(argv)


def clean_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.actions, bpy.data.armatures, bpy.data.meshes):
        for item in list(datablocks):
            if item.users == 0:
                datablocks.remove(item)


def import_avatar(path):
    suffix = path.suffix.lower()
    if suffix in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=str(path))
    elif suffix == ".fbx":
        if hasattr(bpy.ops.wm, "fbx_import"):
            bpy.ops.wm.fbx_import(filepath=str(path))
        else:
            bpy.ops.import_scene.fbx(filepath=str(path))
    else:
        raise RuntimeError(f"unsupported avatar format: {suffix}")

    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    if not armatures:
        raise RuntimeError("no Armature object found in avatar")
    return max(armatures, key=lambda obj: len(obj.data.bones))


def resolve_bones(armature):
    by_normalized = {}
    for bone in armature.pose.bones:
        by_normalized.setdefault(normalized(bone.name), []).append(bone)

    resolved = {}
    ambiguous = {}
    for role, aliases in ALIASES.items():
        # Aliases are ordered from most canonical to least canonical. Resolve
        # one alias at a time so `mixamorig:Spine` wins over Spine1/Spine2
        # instead of treating a healthy Mixamo spine chain as ambiguous.
        for alias in aliases:
            matches = []
            for key, bones in by_normalized.items():
                if key == alias or key.endswith(alias):
                    matches.extend(bones)
            unique = {bone.name: bone for bone in matches}
            if len(unique) == 1:
                resolved[role] = next(iter(unique.values()))
                break
            if len(unique) > 1:
                ambiguous[role] = sorted(unique)
                break
    missing = [role for role in REQUIRED if role not in resolved]
    if missing or ambiguous:
        raise RuntimeError(json.dumps({
            "code": "HUMANOID_BONE_MAPPING_FAILED",
            "missingRoles": missing,
            "ambiguousRoles": ambiguous,
            "availableBones": [bone.name for bone in armature.pose.bones],
        }))
    return resolved


def qx(degrees):
    return Quaternion((1.0, 0.0, 0.0), math.radians(degrees))


def qy(degrees):
    return Quaternion((0.0, 1.0, 0.0), math.radians(degrees))


def set_rotation(bone, quaternion, frame):
    bone.rotation_mode = "QUATERNION"
    bone.rotation_quaternion = quaternion
    bone.keyframe_insert("rotation_quaternion", frame=frame, group=bone.name)


def author_walk(armature, bones):
    # Authored, conservative angles for a first visual candidate. This is an
    # in-place cycle: the game controller, not the animation, owns translation.
    poses = [
        # frame, L thigh, R thigh, L knee, R knee, L arm, R arm, hip yaw
        (1,  -24,  24,  8, 34,  22, -22, -2),
        (7,    0,   0, 30,  8,   0,   0,  0),
        (13,  24, -24, 34,  8, -22,  22,  2),
        (19,   0,   0,  8, 30,   0,   0,  0),
        (25, -24,  24,  8, 34,  22, -22, -2),
    ]

    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="POSE")
    for pose_bone in armature.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.rotation_quaternion = Quaternion()

    armature.animation_data_clear()
    armature.animation_data_create()
    action = bpy.data.actions.new(ACTION_NAME)
    armature.animation_data.action = action

    for frame, lt, rt, lk, rk, la, ra, hip_yaw in poses:
        set_rotation(bones["hips"], qy(hip_yaw), frame)
        set_rotation(bones["left_thigh"], qx(lt), frame)
        set_rotation(bones["right_thigh"], qx(rt), frame)
        set_rotation(bones["left_shin"], qx(-lk), frame)
        set_rotation(bones["right_shin"], qx(-rk), frame)
        set_rotation(bones["left_arm"], qx(la), frame)
        set_rotation(bones["right_arm"], qx(ra), frame)
        if "left_forearm" in bones:
            set_rotation(bones["left_forearm"], qx(-8), frame)
        if "right_forearm" in bones:
            set_rotation(bones["right_forearm"], qx(-8), frame)

    bpy.ops.object.mode_set(mode="OBJECT")
    action.frame_range = (1, LAST_FRAME)
    action.use_frame_range = True
    action.frame_start = 1
    action.frame_end = LAST_FRAME

    # Linear interpolation gives a predictable first proof. A later visual
    # pass can tune F-curves without changing the motion contract.
    for fcurve in action.fcurves:
        for key in fcurve.keyframe_points:
            key.interpolation = "BEZIER"
            key.handle_left_type = "AUTO_CLAMPED"
            key.handle_right_type = "AUTO_CLAMPED"
    return action


def export_glb(output):
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = LAST_FRAME
    bpy.context.scene.render.fps = FPS
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        export_animations=True,
        export_skins=True,
        export_morph=True,
        export_yup=True,
    )


def main():
    args = parse_args()
    avatar = Path(args.avatar).expanduser().resolve()
    output = Path(args.output).expanduser().resolve()
    report = Path(args.report).expanduser().resolve() if args.report else output.with_suffix(".report.json")
    blend = Path(args.blend).expanduser().resolve() if args.blend else output.with_suffix(".blend")

    if not avatar.is_file():
        raise RuntimeError(f"avatar not found: {avatar}")
    if not args.force:
        for target in (output, report, blend):
            if target.exists():
                raise RuntimeError(f"refusing to overwrite existing file without --force: {target}")

    output.parent.mkdir(parents=True, exist_ok=True)
    clean_scene()
    armature = import_avatar(avatar)
    bones = resolve_bones(armature)
    action = author_walk(armature, bones)
    bpy.context.scene.render.fps = FPS
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    export_glb(output)

    result = {
        "status": "CANDIDATE_REQUIRES_VISUAL_REVIEW",
        "generator": "pocketpt_blender_walk_v1.py",
        "sourceAnimation": None,
        "avatar": str(avatar),
        "output": str(output),
        "blend": str(blend),
        "action": action.name,
        "fps": FPS,
        "frameRange": [1, LAST_FRAME],
        "durationSeconds": (LAST_FRAME - 1) / FPS,
        "inPlace": True,
        "boneMapping": {role: bone.name for role, bone in bones.items()},
        "limitations": [
            "first authored gait candidate, not human-validated natural motion",
            "no inverse-kinematics foot lock in v1",
            "Godot must synchronize playback speed with controller velocity",
        ],
    }
    report.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print("POCKETPT_WALK_BUILD_OK " + json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("POCKETPT_WALK_BUILD_FAILED " + str(exc), file=sys.stderr)
        traceback.print_exc()
        sys.exit(1)
