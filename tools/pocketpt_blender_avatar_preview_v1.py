#!/usr/bin/env python3
"""Import a PocketPT avatar into Blender without changing its rig or pose.

Run with Blender:
  blender --background --python pocketpt_blender_avatar_preview_v1.py -- \
    --avatar canonical-avatar.glb --blend pocketpt-avatar-preview.blend \
    --report pocketpt-avatar-preview-report.json --force
"""

import argparse
import json
import sys
import traceback
from pathlib import Path

import bpy
from mathutils import Vector


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--avatar", required=True)
    parser.add_argument("--blend", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--force", action="store_true")
    return parser.parse_args(argv)


def clean_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        if collection.users == 0:
            bpy.data.collections.remove(collection)


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


def world_bounds(objects):
    points = []
    for obj in objects:
        if obj.type != "MESH":
            continue
        points.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    if not points:
        return None
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
    blend = Path(args.blend).expanduser().resolve()
    report = Path(args.report).expanduser().resolve()

    if not avatar.is_file():
        raise RuntimeError(f"avatar not found: {avatar}")
    if not args.force:
        for target in (blend, report):
            if target.exists():
                raise RuntimeError(
                    f"refusing to overwrite existing file without --force: {target}"
                )

    blend.parent.mkdir(parents=True, exist_ok=True)
    report.parent.mkdir(parents=True, exist_ok=True)
    clean_scene()
    import_avatar(avatar)

    objects = list(bpy.context.scene.objects)
    meshes = [obj for obj in objects if obj.type == "MESH"]
    armatures = [obj for obj in objects if obj.type == "ARMATURE"]
    if not meshes:
        raise RuntimeError("avatar import created no mesh objects")

    # Preserve imported transforms, pose, skinning, and animations exactly.
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 1
    bpy.context.scene.frame_set(1)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes + armatures:
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = armatures[0] if armatures else meshes[0]

    result = {
        "status": "IMPORTED_UNTOUCHED_REQUIRES_VISUAL_REVIEW",
        "avatar": str(avatar),
        "blend": str(blend),
        "objectCount": len(objects),
        "meshCount": len(meshes),
        "armatureCount": len(armatures),
        "meshNames": [obj.name for obj in meshes],
        "armatures": [
            {
                "name": obj.name,
                "boneCount": len(obj.data.bones),
                "bones": [bone.name for bone in obj.data.bones],
            }
            for obj in armatures
        ],
        "worldBounds": world_bounds(objects),
        "poseModified": False,
        "animationAdded": False,
    }
    report.write_text(json.dumps(result, indent=2), encoding="utf-8")
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    print("POCKETPT_AVATAR_PREVIEW_OK " + json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("POCKETPT_AVATAR_PREVIEW_FAILED " + str(exc), file=sys.stderr)
        traceback.print_exc()
        sys.exit(1)
