import bpy
from pathlib import Path

path = r"C:\Users\pftgu\Documents\avlobytest\assets\animations\player\rashad_walk_corrected.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)
armatures = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE']
if len(armatures) != 1:
    raise RuntimeError(f"ARMATURE_COUNT:{len(armatures)}")
armature = armatures[0]
if armature.name != "RASHAD_TARGET_ARMATURE":
    raise RuntimeError(f"ARMATURE_NAME:{armature.name}")
if len(armature.data.bones) != 52:
    raise RuntimeError(f"BONE_COUNT:{len(armature.data.bones)}")
actions = list(bpy.data.actions)
print("IMPORTED_ACTIONS", [a.name for a in actions])
corrected = next((a for a in actions if "PocketPT_Walk_Corrected" in a.name), actions[0] if len(actions) == 1 else None)
if corrected is None:
    raise RuntimeError("CORRECTED_ACTION_MISSING")
scale_curves = [fc for fc in corrected.fcurves if fc.data_path.endswith('.scale')]
if scale_curves:
    raise RuntimeError(f"SCALE_CURVES:{len(scale_curves)}")
hips_curves = {fc.array_index: fc for fc in corrected.fcurves if fc.data_path == 'pose.bones["Hips"].location'}
horizontal = []
if len(hips_curves) == 3:
    for frame in range(int(corrected.frame_range[0]), int(corrected.frame_range[1]) + 1):
        local = __import__('mathutils').Vector(tuple(hips_curves[i].evaluate(frame) for i in range(3)))
        world_delta = armature.matrix_world.to_3x3() @ (armature.data.bones['Hips'].matrix_local.to_3x3() @ local)
        horizontal.append((world_delta.x, world_delta.y))
horizontal_drift = max((max(v[i] for v in horizontal) - min(v[i] for v in horizontal) for i in (0, 1)), default=0.0)
print("HORIZONTAL_DRIFT", horizontal_drift)
if horizontal_drift > 1e-4:
    raise RuntimeError("HIPS_HORIZONTAL_ROOT_MOTION")
print("GLB_VALIDATION PASS", "ARMATURE", armature.name, "BONES", len(armature.data.bones), "ACTION", corrected.name, "CURVES", len(corrected.fcurves), "SCALE_CURVES", len(scale_curves))
