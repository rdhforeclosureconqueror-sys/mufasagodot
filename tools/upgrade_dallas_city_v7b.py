import bpy
import os
from mathutils import Vector

OUTPUT = r"C:\Users\pftgu\Documents\avlobytest\blender\downtown_dallas_city_v7b.blend"

scene = bpy.context.scene

cam = bpy.data.objects.get("V7_DALLAS_DRONE_CAMERA")
path = bpy.data.objects.get("V7_DALLAS_DRONE_PATH")
target = bpy.data.objects.get("V7_DRONE_TARGET")
transition = bpy.data.objects.get("PYRAMID_TRANSITION_POINT")

if cam is None:
    raise RuntimeError("Missing camera: V7_DALLAS_DRONE_CAMERA")

if path is None:
    raise RuntimeError("Missing path: V7_DALLAS_DRONE_PATH")

if target is None:
    raise RuntimeError("Missing target: V7_DRONE_TARGET")

if transition is None:
    raise RuntimeError("Missing transition marker: PYRAMID_TRANSITION_POINT")


# ============================================================
# 1. EXTEND TIMELINE
# ============================================================

scene.render.fps = 30
scene.frame_start = 1
scene.frame_end = 500


# ============================================================
# 2. TIGHTEN DRONE PATH
# Make the final approach lower and closer.
# ============================================================

curve = path.data
spline = curve.splines[0]
pts = spline.bezier_points

# We expect 6 bezier points from the original V7 script.
if len(pts) < 6:
    raise RuntimeError(f"Expected at least 6 bezier points, found {len(pts)}")

pyr = transition.location.copy()

new_points = [
    Vector((-720, -1050, 460)),
    Vector((-520, -760, 390)),
    Vector((-300, -430, 315)),
    Vector((pyr.x - 180, pyr.y - 420, 235)),
    Vector((pyr.x - 70,  pyr.y - 170, 130)),
    Vector((pyr.x,       pyr.y - 35,   68)),
]

for bp, co in zip(pts[:6], new_points):
    bp.co = co
    bp.handle_left_type = "AUTO"
    bp.handle_right_type = "AUTO"


# ============================================================
# 3. CAMERA SETTINGS
# Slightly tighter lens for a stronger approach shot.
# ============================================================

cam.data.lens = 52
scene.camera = cam


# ============================================================
# 4. FIND CONSTRAINTS
# ============================================================

follow = None
track = None

for c in cam.constraints:
    if c.type == "FOLLOW_PATH":
        follow = c
    elif c.type == "TRACK_TO":
        track = c

if follow is None:
    raise RuntimeError("Camera missing FOLLOW_PATH constraint")

if track is None:
    raise RuntimeError("Camera missing TRACK_TO constraint")


# ============================================================
# 5. CLEAR OLD ANIMATION KEYS
# ============================================================

cam.animation_data_clear()
target.animation_data_clear()


# ============================================================
# 6. RE-ANIMATE CAMERA
# ============================================================

follow.offset_factor = 0.0
follow.keyframe_insert(data_path="offset_factor", frame=1)

follow.offset_factor = 1.0
follow.keyframe_insert(data_path="offset_factor", frame=500)


# ============================================================
# 7. RE-ANIMATE TARGET
# This makes the camera appreciate the skyline,
# then lock in more directly on the destination.
# ============================================================

target.location = (0, -60, 170)
target.keyframe_insert(data_path="location", frame=1)

target.location = (0, 260, 145)
target.keyframe_insert(data_path="location", frame=260)

target.location = (pyr.x, pyr.y + 10, 85)
target.keyframe_insert(data_path="location", frame=500)


# ============================================================
# 8. SMOOTH INTERPOLATION
# ============================================================

if cam.animation_data and cam.animation_data.action:
    for fc in cam.animation_data.action.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"

if target.animation_data and target.animation_data.action:
    for fc in target.animation_data.action.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"


# ============================================================
# 9. SAVE
# ============================================================

os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=OUTPUT)

print("")
print("================================================")
print("DALLAS CITY V7B COMPLETE")
print("================================================")
print("Extended cinematic to 500 frames.")
print("Final approach pushed lower and closer.")
print("Saved:")
print(OUTPUT)
print("================================================")
