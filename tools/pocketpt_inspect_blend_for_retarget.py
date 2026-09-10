#!/usr/bin/env python3
"""Read-only inspection of a Blender scene before animation retargeting."""

import argparse
import json
import sys
import traceback
from pathlib import Path

import bpy


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", required=True)
    return parser.parse_args(argv)


def action_summary(action):
    return {
        "name": action.name,
        "frameRange": [float(action.frame_range[0]), float(action.frame_range[1])],
        "fcurveCount": len(action.fcurves),
        "groups": [group.name for group in action.groups],
        "users": action.users,
    }


def armature_summary(obj):
    animation_data = obj.animation_data
    nla_tracks = []
    if animation_data:
        for track in animation_data.nla_tracks:
            nla_tracks.append({
                "name": track.name,
                "mute": track.mute,
                "strips": [
                    {
                        "name": strip.name,
                        "action": strip.action.name if strip.action else None,
                        "frameStart": float(strip.frame_start),
                        "frameEnd": float(strip.frame_end),
                    }
                    for strip in track.strips
                ],
            })
    return {
        "name": obj.name,
        "boneCount": len(obj.data.bones),
        "bones": [bone.name for bone in obj.data.bones],
        "activeAction": (
            animation_data.action.name
            if animation_data and animation_data.action
            else None
        ),
        "nlaTracks": nla_tracks,
        "location": [float(value) for value in obj.location],
        "rotationMode": obj.rotation_mode,
        "scale": [float(value) for value in obj.scale],
    }


def mesh_summary(obj):
    return {
        "name": obj.name,
        "parent": obj.parent.name if obj.parent else None,
        "armatureModifiers": [
            modifier.object.name
            for modifier in obj.modifiers
            if modifier.type == "ARMATURE" and modifier.object is not None
        ],
        "vertexGroupCount": len(obj.vertex_groups),
        "materialSlots": len(obj.material_slots),
    }


def main():
    args = parse_args()
    report = Path(args.report).expanduser().resolve()
    report.parent.mkdir(parents=True, exist_ok=True)

    objects = list(bpy.context.scene.objects)
    armatures = [obj for obj in objects if obj.type == "ARMATURE"]
    meshes = [obj for obj in objects if obj.type == "MESH"]
    actions = list(bpy.data.actions)

    result = {
        "status": "READ_ONLY_INSPECTION_COMPLETE",
        "blend": bpy.data.filepath,
        "scene": bpy.context.scene.name,
        "sceneFrameRange": [
            bpy.context.scene.frame_start,
            bpy.context.scene.frame_end,
        ],
        "objectCount": len(objects),
        "objects": [
            {
                "name": obj.name,
                "type": obj.type,
                "parent": obj.parent.name if obj.parent else None,
                "hiddenViewport": obj.hide_get(),
                "hiddenRender": obj.hide_render,
            }
            for obj in objects
        ],
        "armatureCount": len(armatures),
        "armatures": [armature_summary(obj) for obj in armatures],
        "meshCount": len(meshes),
        "meshes": [mesh_summary(obj) for obj in meshes],
        "actionCount": len(actions),
        "actions": [action_summary(action) for action in actions],
    }

    report.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print("POCKETPT_RETARGET_INSPECTION_OK " + json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("POCKETPT_RETARGET_INSPECTION_FAILED " + str(exc), file=sys.stderr)
        traceback.print_exc()
        sys.exit(1)
