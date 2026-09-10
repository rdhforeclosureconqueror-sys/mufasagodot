#!/usr/bin/env python3
"""Create an original in-place walk candidate on a personal Avaturn avatar.

The source avatar is never modified. All appearance meshes, materials, images,
skinning, and the armature are retained. Imported actions are removed only from
the generated working copy before a new walk action is authored.
"""

import argparse
import json
import math
import sys
import traceback
from pathlib import Path

import bpy
from mathutils import Quaternion, Vector


ACTION_NAME = "pocketpt_personal_walk_in_place_v2"
FPS = 24
FIRST_FRAME = 1
LAST_FRAME = 25

ALIASES = {
    "hips": ["hips", "pelvis"],
    "spine": ["spine"],
    "spine1": ["spine1"],
    "left_thigh": ["leftupleg", "leftthigh"],
    "right_thigh": ["rightupleg", "rightthigh"],
    "left_shin": ["leftleg", "leftlowerleg", "leftshin"],
    "right_shin": ["rightleg", "rightlowerleg", "rightshin"],
    "left_foot": ["leftfoot"],
    "right_foot": ["rightfoot"],
    "left_arm": ["leftarm", "leftupperarm"],
    "right_arm": ["rightarm", "rightupperarm"],
    "left_forearm": ["leftforearm", "leftlowerarm"],
    "right_forearm": ["rightforearm", "rightlowerarm"],
}

REQUIRED = [
    "hips", "spine", "left_thigh", "right_thigh", "left_shin",
    "right_shin", "left_foot", "right_foot", "left_arm", "right_arm",
]


def normalized(value):
    return "".join(character for character in str(value).lower() if character.isalnum())


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--avatar", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--blend", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--force", action="store_true")
    return parser.parse_args(argv)


def clean_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


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


def choose_armature():
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError(json.dumps({
            "code": "ARMATURE_NOT_UNIQUE",
            "armatures": [obj.name for obj in armatures],
        }))
    return armatures[0]


def remove_known_auxiliary_meshes():
    removed = []
    for obj in list(bpy.context.scene.objects):
        if obj.type == "MESH" and normalized(obj.name) == "icosphere":
            removed.append(obj.name)
            bpy.data.objects.remove(obj, do_unlink=True)
    return removed


def resolve_bones(armature):
    by_normalized = {}
    for bone in armature.pose.bones:
        by_normalized.setdefault(normalized(bone.name), []).append(bone)

    resolved = {}
    ambiguous = {}
    for role, aliases in ALIASES.items():
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


def qz(degrees):
    return Quaternion((0.0, 0.0, 1.0), math.radians(degrees))


def key_rotation(bone, base, delta, frame):
    bone.rotation_mode = "QUATERNION"
    bone.rotation_quaternion = base @ delta
    bone.keyframe_insert("rotation_quaternion", frame=frame, group=bone.name)


def author_walk(armature, bones):
    bpy.context.view_layer.objects.active = armature
    armature.hide_set(False)
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="POSE")

    # Preserve every imported rest-pose basis. The generated motion is applied
    # as a delta instead of replacing Avaturn's bone orientations.
    base_rotations = {}
    for role, bone in bones.items():
        bone.rotation_mode = "QUATERNION"
        base_rotations[role] = bone.rotation_quaternion.copy()

    armature.animation_data_clear()
    for action in list(bpy.data.actions):
        if action.users == 0:
            bpy.data.actions.remove(action)
    armature.animation_data_create()
    action = bpy.data.actions.new(ACTION_NAME)
    armature.animation_data.action = action

    # frame, left thigh, right thigh, left knee, right knee,
    # arm swing, hip yaw, ankle counter-rotation
    poses = [
        (1,  -22,  22,  8, 32,   7, -2,  8),
        (7,    0,   0, 28, 10,   0,  0,  2),
        (13,  22, -22, 32,  8,  -7,  2,  8),
        (19,   0,   0, 10, 28,   0,  0,  2),
        (25, -22,  22,  8, 32,   7, -2,  8),
    ]

    for frame, lt, rt, lk, rk, arm_swing, hip_yaw, ankle in poses:
        key_rotation(bones["hips"], base_rotations["hips"], qz(hip_yaw), frame)
        key_rotation(bones["spine"], base_rotations["spine"], qz(-hip_yaw * 0.5), frame)
        key_rotation(bones["left_thigh"], base_rotations["left_thigh"], qx(lt), frame)
        key_rotation(bones["right_thigh"], base_rotations["right_thigh"], qx(rt), frame)
        key_rotation(bones["left_shin"], base_rotations["left_shin"], qx(-lk), frame)
        key_rotation(bones["right_shin"], base_rotations["right_shin"], qx(-rk), frame)
        key_rotation(bones["left_foot"], base_rotations["left_foot"], qx(ankle), frame)
        key_rotation(bones["right_foot"], base_rotations["right_foot"], qx(ankle), frame)

        # Avaturn starts in a T-pose. Rx lowers both upper arms; the Rz delta
        # adds opposite forward/back swing because the mirrored arm bones have
        # opposite rest orientations.
        arm_delta = qx(86) @ qz(arm_swing)
        key_rotation(bones["left_arm"], base_rotations["left_arm"], arm_delta, frame)
        key_rotation(bones["right_arm"], base_rotations["right_arm"], arm_delta, frame)
        if "left_forearm" in bones:
            key_rotation(
                bones["left_forearm"], base_rotations["left_forearm"], qx(-16), frame
            )
        if "right_forearm" in bones:
            key_rotation(
                bones["right_forearm"], base_rotations["right_forearm"], qx(-16), frame
            )

    bpy.ops.object.mode_set(mode="OBJECT")
    action.use_frame_range = True
    action.frame_start = FIRST_FRAME
    action.frame_end = LAST_FRAME
    for fcurve in action.fcurves:
        for keyframe in fcurve.keyframe_points:
            keyframe.interpolation = "BEZIER"
            keyframe.handle_left_type = "AUTO_CLAMPED"
            keyframe.handle_right_type = "AUTO_CLAMPED"
        fcurve.modifiers.new(type="CYCLES")
    return action


def bounds(meshes):
    points = [
        obj.matrix_world @ Vector(corner)
        for obj in meshes
        for corner in obj.bound_box
    ]
    mins = [min(point[i] for point in points) for i in range(3)]
    maxs = [max(point[i] for point in points) for i in range(3)]
    return {
        "min": [round(value, 6) for value in mins],
        "max": [round(value, 6) for value in maxs],
        "size": [round(maxs[i] - mins[i], 6) for i in range(3)],
    }


def main():
    args = parse_args()
    avatar = Path(args.avatar).expanduser().resolve()
    output = Path(args.output).expanduser().resolve()
    blend = Path(args.blend).expanduser().resolve()
    report = Path(args.report).expanduser().resolve()

    if not avatar.is_file():
        raise RuntimeError(f"avatar not found: {avatar}")
    if not args.force:
        for target in (output, blend, report):
            if target.exists():
                raise RuntimeError(
                    f"refusing to overwrite existing file without --force: {target}"
                )
    for target in (output, blend, report):
        target.parent.mkdir(parents=True, exist_ok=True)

    clean_scene()
    import_avatar(avatar)
    removed_auxiliary_objects = remove_known_auxiliary_meshes()
    armature = choose_armature()
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("personal avatar import created no mesh objects")
    surviving_auxiliary = [
        obj.name for obj in meshes if normalized(obj.name) == "icosphere"
    ]
    if surviving_auxiliary:
        raise RuntimeError(json.dumps({
            "code": "AUXILIARY_MESH_SURVIVED",
            "objects": surviving_auxiliary,
        }))
    imported_actions = [action.name for action in bpy.data.actions]
    bones = resolve_bones(armature)
    action = author_walk(armature, bones)

    bpy.context.scene.frame_start = FIRST_FRAME
    bpy.context.scene.frame_end = LAST_FRAME
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.frame_set(FIRST_FRAME)

    # Export all personal appearance meshes plus the armature, and nothing else.
    bpy.ops.object.select_all(action="DESELECT")
    armature.hide_set(False)
    armature.select_set(True)
    for mesh in meshes:
        mesh.hide_set(False)
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_skins=True,
        export_morph=True,
        export_yup=True,
    )

    # Review opens cleanly on the personal avatar, without visible rig shapes.
    bpy.ops.object.select_all(action="DESELECT")
    armature.hide_set(True)
    for mesh in meshes:
        mesh.hide_set(False)
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]

    result = {
        "status": "PERSONAL_WALK_V2_ARM_REFINEMENT_REQUIRES_VISUAL_REVIEW",
        "source": str(avatar),
        "output": str(output),
        "blend": str(blend),
        "meshCount": len(meshes),
        "meshNames": [mesh.name for mesh in meshes],
        "materialCount": len(bpy.data.materials),
        "imageCount": len(bpy.data.images),
        "armature": armature.name,
        "boneCount": len(armature.data.bones),
        "removedAuxiliaryObjects": removed_auxiliary_objects,
        "removedImportedActions": imported_actions,
        "action": action.name,
        "fps": FPS,
        "frameRange": [FIRST_FRAME, LAST_FRAME],
        "durationSeconds": (LAST_FRAME - FIRST_FRAME) / FPS,
        "inPlace": True,
        "boneMapping": {role: bone.name for role, bone in bones.items()},
        "bounds": bounds(meshes),
        "limitations": [
            "v2 preserves approved leg cycle and narrows arm swing",
            "no inverse-kinematics foot lock in v1",
            "requires visual approval before Godot integration",
        ],
    }
    report.write_text(json.dumps(result, indent=2), encoding="utf-8")
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    print("POCKETPT_PERSONAL_WALK_OK " + json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("POCKETPT_PERSONAL_WALK_FAILED " + str(exc), file=sys.stderr)
        traceback.print_exc()
        sys.exit(1)
