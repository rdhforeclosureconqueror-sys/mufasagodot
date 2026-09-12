import bpy

for name in ("RASHAD_TARGET_ARMATURE", "WALK_DONOR_ARMATURE"):
    obj = bpy.data.objects.get(name)
    print(f"OBJECT {name}: {obj.type if obj else 'MISSING'}")
    if not obj:
        continue
    print("TRANSFORM", obj.matrix_world)
    print("BONES", len(obj.data.bones), [b.name for b in obj.data.bones])
    action = obj.animation_data.action if obj.animation_data else None
    print("ACTION", action.name if action else "NONE", "RANGE", tuple(action.frame_range) if action else None)
    if action:
        print("CURVES", len(action.fcurves), sorted({fc.data_path for fc in action.fcurves})[:30])

for obj in bpy.data.objects:
    if obj.type == 'MESH':
        armatures = [m.object.name for m in obj.modifiers if m.type == 'ARMATURE' and m.object]
        print("MESH", obj.name, "ARMATURES", armatures, "HIDDEN", obj.hide_viewport, obj.hide_render)
