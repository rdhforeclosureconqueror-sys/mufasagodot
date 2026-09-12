import bpy
from pathlib import Path

run_path = r"C:\Users\pftgu\Documents\avlobytest\addons\humanizer\data\animations\animations.glb"
thriller_path = r"C:\Users\pftgu\Documents\avlobytest\addons\humanizer\data\animations\Input\Thriller Part 1.fbx"

def report(label):
    print("---", label, "---")
    for obj in bpy.context.scene.objects:
        if obj.type == 'ARMATURE':
            print("ARMATURE", obj.name, "BONES", len(obj.data.bones), "ACTION", obj.animation_data.action.name if obj.animation_data and obj.animation_data.action else None, "TRANSFORM", tuple(round(v, 5) for row in obj.matrix_world for v in row))
            print("BONE_NAMES", [b.name for b in obj.data.bones])
    for action in bpy.data.actions:
        print("ACTION", action.name, "RANGE", tuple(action.frame_range), "CURVES", len(action.fcurves))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=run_path)
report("RUN_GLTF")
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=thriller_path, use_anim=True, automatic_bone_orientation=False)
report("THRILLER_FBX")
