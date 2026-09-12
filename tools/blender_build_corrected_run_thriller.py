import bpy
import math
from mathutils import Vector
from pathlib import Path

ROOT = Path(r"C:\Users\pftgu\Documents\avlobytest")
MASTER = ROOT / "blender/characters/rashad1/rashad1_animation_master.blend"
RUN_SOURCE = ROOT / "addons/humanizer/data/animations/animations.glb"
THRILLER_SOURCE = ROOT / "addons/humanizer/data/animations/Input/Thriller Part 1.fbx"
PREVIEW_ROOT = ROOT / "build/rashad_action_blender_preview"

PROFILE_TO_TARGET = {
    "Hips":"Hips", "Spine":"Spine", "Chest":"Spine1", "UpperChest":"Spine2", "Neck":"Neck", "Head":"Head",
    "LeftShoulder":"LeftShoulder", "LeftUpperArm":"LeftArm", "LeftLowerArm":"LeftForeArm", "LeftHand":"LeftHand",
    "RightShoulder":"RightShoulder", "RightUpperArm":"RightArm", "RightLowerArm":"RightForeArm", "RightHand":"RightHand",
    "LeftUpperLeg":"LeftUpLeg", "LeftLowerLeg":"LeftLeg", "LeftFoot":"LeftFoot", "LeftToes":"LeftToeBase",
    "RightUpperLeg":"RightUpLeg", "RightLowerLeg":"RightLeg", "RightFoot":"RightFoot", "RightToes":"RightToeBase",
}
for side in ("Left", "Right"):
    for finger in ("Thumb", "Index", "Middle", "Ring", "Little"):
        target_finger = "Pinky" if finger == "Little" else finger
        for index, suffix in enumerate(("Metacarpal", "Proximal", "Intermediate", "Distal")):
            if finger == "Thumb":
                if suffix == "Intermediate": continue
                source_index = {"Metacarpal":1, "Proximal":2, "Distal":3}[suffix]
            else:
                if suffix == "Metacarpal": continue
                source_index = {"Proximal":1, "Intermediate":2, "Distal":3}[suffix]
            PROFILE_TO_TARGET[f"{side}{finger}{suffix}"] = f"{side}Hand{target_finger}{source_index}"

def clear_target_pose(target):
    for pb in target.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)

def bake(target, donor, donor_action, mapping, action_name):
    bpy.context.scene.render.fps = 30
    bpy.context.scene.render.fps_base = 1.0
    donor.animation_data.action = donor_action
    clear_target_pose(target)
    action = bpy.data.actions.get(action_name)
    if action: bpy.data.actions.remove(action)
    action = bpy.data.actions.new(action_name)
    action.use_fake_user = True
    if target.animation_data is None: target.animation_data_create()
    target.animation_data.action = action
    start = math.floor(donor_action.frame_range[0]); end = math.ceil(donor_action.frame_range[1])
    bpy.context.scene.frame_start, bpy.context.scene.frame_end = start, end
    for frame in range(start, end + 1):
        bpy.context.scene.frame_set(frame); bpy.context.view_layer.update()
        for target_name, donor_name in mapping.items():
            dp = donor.pose.bones[donor_name]; tp = target.pose.bones[target_name]
            d_rest = (donor.matrix_world @ donor.data.bones[donor_name].matrix_local).to_quaternion()
            t_rest = (target.matrix_world @ target.data.bones[target_name].matrix_local).to_quaternion()
            delta = dp.matrix_basis.to_quaternion()
            target_delta = t_rest.inverted() @ d_rest @ delta @ d_rest.inverted() @ t_rest
            target_delta.normalize()
            tp.rotation_quaternion = target_delta
            tp.location = Vector((0, 0, 0)); tp.scale = Vector((1, 1, 1))
            tp.keyframe_insert("rotation_quaternion", frame=frame, group=target_name)
            if target_name == "Hips": tp.keyframe_insert("location", frame=frame, group=target_name)
    for fc in action.fcurves:
        for kp in fc.keyframe_points: kp.interpolation = 'LINEAR'
    return action, start, end

def hide_donors(target):
    for obj in bpy.context.scene.objects:
        bound = obj.type == 'MESH' and any(m.type == 'ARMATURE' and m.object == target for m in obj.modifiers)
        visible = obj == target or bound
        obj.hide_viewport = not visible; obj.hide_render = not visible

def export_target(target, glb_path):
    bpy.ops.object.select_all(action='DESELECT'); target.select_set(True)
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH' and any(m.type == 'ARMATURE' and m.object == target for m in obj.modifiers): obj.select_set(True)
    bpy.context.view_layer.objects.active = target
    for obj in bpy.context.scene.objects:
        if obj.type == 'ARMATURE' and obj != target and obj.animation_data: obj.animation_data.action = None
    if target.animation_data:
        for track in list(target.animation_data.nla_tracks): target.animation_data.nla_tracks.remove(track)
    active_action = target.animation_data.action
    target.animation_data.action = None
    nla_track = target.animation_data.nla_tracks.new()
    nla_track.name = active_action.name
    nla_track.strips.new(active_action.name, int(active_action.frame_range[0]), active_action)
    glb_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(glb_path), export_format='GLB', use_selection=True, export_animations=True,
        export_animation_mode='NLA_TRACKS', export_force_sampling=True, export_frame_range=True,
        export_skins=True, export_morph=True)

def render_preview(target, label, start, end):
    scene = bpy.context.scene; scene.render.engine = 'BLENDER_WORKBENCH'
    scene.render.resolution_x = 420; scene.render.resolution_y = 420; scene.render.resolution_percentage = 100
    scene.display.shading.light = 'STUDIO'; scene.display.shading.show_shadows = True; scene.display.shading.show_cavity = True
    scene.render.image_settings.file_format = 'PNG'
    camera_data = bpy.data.cameras.new("PocketPT_Action_Preview_Camera")
    camera = bpy.data.objects.new("PocketPT_Action_Preview_Camera", camera_data); scene.collection.objects.link(camera); scene.camera = camera; camera.data.lens = 55
    views = {"front":(0,-3.4,1.15), "side":(3.4,0,1.15), "back":(0,3.4,1.15), "overhead":(0.01,-0.8,4.2)}
    samples = sorted(set(round(start + (end-start)*v/5) for v in range(6)))
    out = PREVIEW_ROOT / label; out.mkdir(parents=True, exist_ok=True)
    for view, location in views.items():
        camera.location = location; camera.rotation_euler = (Vector((0,0,1)) - camera.location).to_track_quat('-Z','Y').to_euler()
        for frame in samples:
            scene.frame_set(frame); scene.render.filepath = str(out / f"{view}_{frame:04d}.png"); bpy.ops.render.render(write_still=True)

def process_run():
    bpy.ops.wm.open_mainfile(filepath=str(MASTER)); target = bpy.data.objects["RASHAD_TARGET_ARMATURE"]
    before = set(bpy.data.objects); bpy.ops.import_scene.gltf(filepath=str(RUN_SOURCE)); imported = [o for o in bpy.data.objects if o not in before]
    donor = next(o for o in imported if o.type == 'ARMATURE')
    donor_action = next(a for a in bpy.data.actions if "Run-loop" in a.name)
    mapping = {name: "mixamorig:"+name for name in target.pose.bones.keys() if "mixamorig:"+name in donor.pose.bones}
    if len(mapping) < 20: raise RuntimeError(f"RUN_MAPPING_INCOMPLETE:{len(mapping)}")
    action, start, end = bake(target, donor, donor_action, mapping, "PocketPT_Run_Corrected")
    hide_donors(target); blend = ROOT / "blender/characters/rashad1/rashad1_run_corrected.blend"; bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    render_preview(target, "run", start, end); export_target(target, ROOT / "assets/animations/player/rashad_run_corrected.glb")
    print("RUN_CORRECTED", len(mapping), len(action.fcurves), start, end)

def process_thriller():
    bpy.ops.wm.open_mainfile(filepath=str(MASTER)); target = bpy.data.objects["RASHAD_TARGET_ARMATURE"]
    before = set(bpy.data.objects); bpy.ops.import_scene.fbx(filepath=str(THRILLER_SOURCE), use_anim=True, automatic_bone_orientation=False); imported = [o for o in bpy.data.objects if o not in before]
    donor = next(o for o in imported if o.type == 'ARMATURE'); donor_action = donor.animation_data.action
    mapping = {name: "mixamorig:"+name for name in target.pose.bones.keys() if "mixamorig:"+name in donor.pose.bones}
    if len(mapping) < 20: raise RuntimeError(f"THRILLER_MAPPING_INCOMPLETE:{len(mapping)}")
    action, start, end = bake(target, donor, donor_action, mapping, "PocketPT_Thriller_Part1")
    hide_donors(target); blend = ROOT / "blender/characters/rashad1/rashad1_thriller_part1_corrected.blend"; bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    render_preview(target, "thriller", start, end); export_target(target, ROOT / "assets/animations/player/rashad_thriller_part1_corrected.glb")
    print("THRILLER_CORRECTED", len(mapping), len(action.fcurves), start, end)

process_run()
process_thriller()
