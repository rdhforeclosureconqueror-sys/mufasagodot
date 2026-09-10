#!/usr/bin/env python3
"""Build a clean rigged PocketPT reference avatar for later animation work.

This script is intentionally not an animation generator. It keeps one named
human mesh and its armature, removes auxiliary scene objects from the working
copy, exports a clean rigged GLB, and saves a review-ready Blender file with the
armature hidden in the viewport.
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
    parser.add_argument("--visual-name", default="Ch18")
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


def select_single_visual(name):
    exact = [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.name == name]
    if len(exact) != 1:
        raise RuntimeError(json.dumps({
            "code": "VISUAL_MESH_NOT_UNIQUE",
            "requested": name,
            "matches": [obj.name for obj in exact],
            "availableMeshes": [
                obj.name for obj in bpy.context.scene.objects if obj.type == "MESH"
            ],
        }))
    return exact[0]


def select_single_armature(visual):
    modifier_armatures = [
        modifier.object
        for modifier in visual.modifiers
        if modifier.type == "ARMATURE" and modifier.object is not None
    ]
    unique = {obj.name: obj for obj in modifier_armatures}
    if len(unique) == 1:
        return next(iter(unique.values()))

    scene_armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    if len(scene_armatures) == 1:
        return scene_armatures[0]
    raise RuntimeError(json.dumps({
        "code": "ARMATURE_NOT_UNIQUE",
        "modifierArmatures": sorted(unique),
        "sceneArmatures": [obj.name for obj in scene_armatures],
    }))


def mesh_bounds(obj):
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
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
    visual = select_single_visual(args.visual_name)
    armature = select_single_armature(visual)

    original_objects = list(bpy.context.scene.objects)
    removed_objects = []
    for obj in original_objects:
        if obj not in (visual, armature):
            removed_objects.append({"name": obj.name, "type": obj.type})
            bpy.data.objects.remove(obj, do_unlink=True)

    # This is a neutral reusable base. Later generators add their own actions.
    armature.animation_data_clear()
    for action in list(bpy.data.actions):
        if action.users == 0:
            bpy.data.actions.remove(action)

    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 1
    bpy.context.scene.frame_set(1)

    # Export exactly the body mesh and rig. No helper geometry or animation.
    bpy.ops.object.select_all(action="DESELECT")
    visual.hide_set(False)
    armature.hide_set(False)
    visual.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        use_selection=True,
        export_animations=False,
        export_skins=True,
        export_morph=True,
        export_yup=True,
    )

    # The rig remains in the file but is hidden so the review opens cleanly.
    bpy.ops.object.select_all(action="DESELECT")
    armature.hide_set(True)
    armature.hide_render = False
    visual.hide_set(False)
    visual.hide_render = False
    visual.select_set(True)
    bpy.context.view_layer.objects.active = visual

    result = {
        "status": "CLEAN_RIGGED_AVATAR_REQUIRES_VISUAL_REVIEW",
        "source": str(avatar),
        "output": str(output),
        "blend": str(blend),
        "visual": visual.name,
        "armature": armature.name,
        "boneCount": len(armature.data.bones),
        "removedObjects": removed_objects,
        "remainingObjects": [
            {"name": obj.name, "type": obj.type}
            for obj in bpy.context.scene.objects
        ],
        "visualBounds": mesh_bounds(visual),
        "armatureHiddenForReview": True,
        "animationCount": 0,
    }
    report.write_text(json.dumps(result, indent=2), encoding="utf-8")
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    print("POCKETPT_CLEAN_AVATAR_OK " + json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("POCKETPT_CLEAN_AVATAR_FAILED " + str(exc), file=sys.stderr)
        traceback.print_exc()
        sys.exit(1)
