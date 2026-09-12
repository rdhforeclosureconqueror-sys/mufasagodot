import bpy
import math
from mathutils import Vector, Matrix
from pathlib import Path

TARGET_NAME = "RASHAD_TARGET_ARMATURE"
DONOR_NAME = "WALK_DONOR_ARMATURE"
ACTION_NAME = "PocketPT_Walk_Corrected"
BLEND_OUT = Path(r"C:\Users\pftgu\Documents\avlobytest\blender\characters\rashad1\rashad1_walk_corrected.blend")
GLB_OUT = Path(r"C:\Users\pftgu\Documents\avlobytest\assets\animations\player\rashad_walk_corrected.glb")
PREVIEW_DIR = Path(r"C:\Users\pftgu\Documents\avlobytest\build\rashad_walk_blender_preview")

target = bpy.data.objects[TARGET_NAME]
donor = bpy.data.objects[DONOR_NAME]
source_action = donor.animation_data.action
if source_action is None:
    raise RuntimeError("WALK_DONOR_ACTION_MISSING")

base_names = [
    "Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
    "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
    "RightShoulder", "RightArm", "RightForeArm", "RightHand",
    "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot",
]
finger_stems = ("LeftHandThumb", "LeftHandIndex", "LeftHandMiddle", "LeftHandRing", "LeftHandPinky",
                "RightHandThumb", "RightHandIndex", "RightHandMiddle", "RightHandRing", "RightHandPinky")
finger_names = [f"{stem}{index}" for stem in finger_stems for index in (1, 2, 3)]
mapping = {}
for target_name in base_names + finger_names:
    donor_name = "mixamorig:" + target_name
    if target_name in target.data.bones and donor_name in donor.data.bones:
        mapping[target_name] = donor_name
missing = [name for name in base_names if name not in mapping]
if missing:
    raise RuntimeError("REQUIRED_MAPPING_MISSING:" + ",".join(missing))

if target.animation_data is None:
    target.animation_data_create()
action = bpy.data.actions.get(ACTION_NAME)
if action:
    bpy.data.actions.remove(action)
action = bpy.data.actions.new(ACTION_NAME)
action.use_fake_user = True
target.animation_data.action = action

scene = bpy.context.scene
start, end = (int(round(v)) for v in source_action.frame_range)
scene.frame_start, scene.frame_end = start, end

# Convert a donor pose-basis delta into the corresponding target bone-rest axes.
# The conjugation is the rest-aware part: no donor local Euler/quaternion is
# copied directly onto Rashad.
for frame in range(start, end + 1):
    scene.frame_set(frame)
    bpy.context.view_layer.update()
    for target_name, donor_name in mapping.items():
        dp = donor.pose.bones[donor_name]
        tp = target.pose.bones[target_name]
        d_rest_matrix = donor.matrix_world @ donor.data.bones[donor_name].matrix_local
        t_rest_matrix = target.matrix_world @ target.data.bones[target_name].matrix_local
        d_rest = d_rest_matrix.to_quaternion()
        t_rest = t_rest_matrix.to_quaternion()
        donor_delta = dp.matrix_basis.to_quaternion()
        target_delta = t_rest.inverted() @ d_rest @ donor_delta @ d_rest.inverted() @ t_rest
        target_delta.normalize()
        tp.rotation_mode = 'QUATERNION'
        tp.rotation_quaternion = target_delta
        tp.scale = Vector((1.0, 1.0, 1.0))
        tp.location = Vector((0.0, 0.0, 0.0))
        if target_name == "Hips":
            # A fully locked target hips translation avoids axis-conversion
            # leakage and keeps all world displacement with CharacterBody3D.
            tp.location = Vector((0.0, 0.0, 0.0))
        tp.keyframe_insert("rotation_quaternion", frame=frame, group=target_name)
        if target_name == "Hips":
            tp.keyframe_insert("location", frame=frame, group=target_name)

for fc in list(action.fcurves):
    if fc.data_path.endswith(".scale"):
        action.fcurves.remove(fc)

# Linear keys preserve the donor samples; cyclic extrapolation closes the loop.
for fc in action.fcurves:
    for kp in fc.keyframe_points:
        kp.interpolation = 'LINEAR'
    cycle = fc.modifiers.new('CYCLES')
    cycle.mode_before = 'REPEAT'
    cycle.mode_after = 'REPEAT'

target.animation_data.action = action
donor.hide_viewport = True
donor.hide_render = True
for obj in bpy.data.objects:
    if obj.type == 'MESH':
        bound_to_target = any(m.type == 'ARMATURE' and m.object == target for m in obj.modifiers)
        obj.hide_viewport = not bound_to_target
        obj.hide_render = not bound_to_target
target.hide_viewport = False
target.hide_render = False

BLEND_OUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))

# Export only Rashad's original meshes and armature with the corrected active action.
bpy.ops.object.select_all(action='DESELECT')
target.select_set(True)
for obj in bpy.data.objects:
    if obj.type == 'MESH' and any(m.type == 'ARMATURE' and m.object == target for m in obj.modifiers):
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
bpy.context.view_layer.objects.active = target
GLB_OUT.parent.mkdir(parents=True, exist_ok=True)
if donor.animation_data:
    donor.animation_data.action = None
if target.animation_data:
    for track in list(target.animation_data.nla_tracks):
        target.animation_data.nla_tracks.remove(track)
bpy.ops.export_scene.gltf(
    filepath=str(GLB_OUT), export_format='GLB', use_selection=True,
    export_animations=True, export_animation_mode='ACTIVE_ACTIONS',
    export_force_sampling=False, export_frame_range=True,
    export_skins=True, export_morph=True,
)

# Four-angle cycle contact sheets are rendered as individual frames for inspection.
PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
scene.render.engine = 'BLENDER_WORKBENCH'
scene.render.resolution_x = 512
scene.render.resolution_y = 512
scene.render.resolution_percentage = 100
scene.display.shading.light = 'STUDIO'
scene.display.shading.show_shadows = True
scene.display.shading.show_cavity = True
scene.render.image_settings.file_format = 'PNG'

camera = bpy.data.objects.get("PocketPT_Retarget_Preview_Camera")
if camera is None:
    camera_data = bpy.data.cameras.new("PocketPT_Retarget_Preview_Camera")
    camera = bpy.data.objects.new("PocketPT_Retarget_Preview_Camera", camera_data)
    scene.collection.objects.link(camera)
scene.camera = camera
camera.data.lens = 55

def point_camera(location, target_point=Vector((0.0, 0.0, 1.0))):
    camera.location = Vector(location)
    camera.rotation_euler = (target_point - camera.location).to_track_quat('-Z', 'Y').to_euler()

views = {
    "front": (0.0, -3.4, 1.15),
    "side": (3.4, 0.0, 1.15),
    "back": (0.0, 3.4, 1.15),
    "overhead": (0.01, -0.8, 4.2),
}
sample_frames = [start, start + 5, start + 10, start + 15, start + 20, end]
for view_name, location in views.items():
    point_camera(location)
    for frame in sample_frames:
        scene.frame_set(frame)
        scene.render.filepath = str(PREVIEW_DIR / f"{view_name}_{frame:03d}.png")
        bpy.ops.render.render(write_still=True)

print("WALK_RETARGET PASS", "ACTION", action.name, "CURVES", len(action.fcurves), "MAPPED", len(mapping))
print("BLEND", BLEND_OUT)
print("GLB", GLB_OUT)
