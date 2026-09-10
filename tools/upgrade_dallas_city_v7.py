import bpy
import os
from mathutils import Vector

OUTPUT = r"C:\Users\pftgu\Documents\avlobytest\blender\downtown_dallas_city_v7.blend"

# ============================================================
# DALLAS CITY V7
# CINEMATIC DRONE INTRO ONLY
#
# V6B visual world is preserved.
# This pass adds:
# - one drone flight path
# - one cinematic camera
# - one tracking target
# - one pyramid transition marker
#
# No city redesign.
# No new windows.
# No car changes.
# No tree changes.
# ============================================================


def get_collection(name):
    c = bpy.data.collections.get(name)

    if c is None:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)

    return c


CINEMATIC = get_collection("V7_CINEMATIC")


# ============================================================
# 1. FIND PYRAMID DESTINATION
# ============================================================

anchor = bpy.data.objects.get("PYRAMID_ANCHOR")

if anchor:
    pyramid = anchor.location.copy()
    print("Using existing PYRAMID_ANCHOR:", tuple(pyramid))
else:
    # fallback from earlier world layout
    pyramid = Vector((0, 800, 0))
    print("PYRAMID_ANCHOR not found. Using fallback:", tuple(pyramid))


# ============================================================
# 2. TRANSITION MARKER
# ============================================================

transition = bpy.data.objects.get("PYRAMID_TRANSITION_POINT")

if transition is None:
    transition = bpy.data.objects.new(
        "PYRAMID_TRANSITION_POINT",
        None
    )
    CINEMATIC.objects.link(transition)

transition.empty_display_type = "SPHERE"
transition.empty_display_size = 10

transition.location = (
    pyramid.x,
    pyramid.y - 180,
    55
)


# ============================================================
# 3. CAMERA TRACK TARGET
# ============================================================

target = bpy.data.objects.get("V7_DRONE_TARGET")

if target is None:
    target = bpy.data.objects.new(
        "V7_DRONE_TARGET",
        None
    )
    CINEMATIC.objects.link(target)

target.empty_display_type = "SPHERE"
target.empty_display_size = 5

# Start by aiming generally into downtown.
target.location = (
    pyramid.x,
    pyramid.y - 40,
    120
)


# ============================================================
# 4. CREATE DRONE PATH
# ============================================================

curve_data = bpy.data.curves.new(
    "V7_Drone_Path_Curve",
    type="CURVE"
)

curve_data.dimensions = "3D"
curve_data.resolution_u = 32

spline = curve_data.splines.new("BEZIER")
spline.bezier_points.add(5)

# Six points:
# far aerial -> city reveal -> downtown -> lower -> destination.
points = [
    (-720, -1050, 460),
    (-520, -760, 390),
    (-300, -430, 315),
    (-140, -80, 245),
    (-40, 360, 165),
    (pyramid.x, pyramid.y - 210, 90)
]

for bp, co in zip(spline.bezier_points, points):
    bp.co = co
    bp.handle_left_type = "AUTO"
    bp.handle_right_type = "AUTO"


path = bpy.data.objects.new(
    "V7_DALLAS_DRONE_PATH",
    curve_data
)

CINEMATIC.objects.link(path)


# ============================================================
# 5. CREATE CAMERA
# ============================================================

bpy.ops.object.camera_add(
    location=points[0]
)

camera = bpy.context.object
camera.name = "V7_DALLAS_DRONE_CAMERA"
camera.data.lens = 46
camera.data.sensor_width = 36

# move to cinematic collection
for c in list(camera.users_collection):
    c.objects.unlink(camera)

CINEMATIC.objects.link(camera)


# ============================================================
# 6. FOLLOW PATH
# ============================================================

follow = camera.constraints.new(
    type="FOLLOW_PATH"
)

follow.target = path
follow.use_fixed_location = True
follow.forward_axis = "FORWARD_X"
follow.up_axis = "UP_Z"


# ============================================================
# 7. TRACK DESTINATION
# ============================================================

track = camera.constraints.new(
    type="TRACK_TO"
)

track.target = target
track.track_axis = "TRACK_NEGATIVE_Z"
track.up_axis = "UP_Y"


# ============================================================
# 8. ANIMATE CAMERA
# ============================================================

scene = bpy.context.scene

scene.render.fps = 30
scene.frame_start = 1
scene.frame_end = 360

# 12 second cinematic
follow.offset_factor = 0.0
follow.keyframe_insert(
    data_path="offset_factor",
    frame=1
)

follow.offset_factor = 1.0
follow.keyframe_insert(
    data_path="offset_factor",
    frame=360
)

# Make movement smoother
if camera.animation_data and camera.animation_data.action:
    for fc in camera.animation_data.action.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"


# ============================================================
# 9. ANIMATE TARGET SLIGHTLY
# ============================================================

# This lets the camera begin by appreciating the city
# and gradually focus more directly on the destination.

target.location = (
    0,
    -50,
    160
)

target.keyframe_insert(
    data_path="location",
    frame=1
)

target.location = (
    0,
    300,
    150
)

target.keyframe_insert(
    data_path="location",
    frame=180
)

target.location = (
    pyramid.x,
    pyramid.y,
    110
)

target.keyframe_insert(
    data_path="location",
    frame=360
)

if target.animation_data and target.animation_data.action:
    for fc in target.animation_data.action.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"


# ============================================================
# 10. MAKE THIS THE ACTIVE CAMERA
# ============================================================

scene.camera = camera


# ============================================================
# 11. CINEMATIC SETTINGS
# ============================================================

scene.render.engine = "BLENDER_EEVEE_NEXT"

scene.render.resolution_x = 1600
scene.render.resolution_y = 900
scene.render.resolution_percentage = 75

try:
    scene.view_settings.look = "AgX - Medium High Contrast"
except:
    pass


# ============================================================
# 12. SAVE V7
# ============================================================

os.makedirs(
    os.path.dirname(OUTPUT),
    exist_ok=True
)

bpy.ops.wm.save_as_mainfile(
    filepath=OUTPUT
)

print("")
print("================================================")
print("DALLAS CITY V7 COMPLETE")
print("================================================")
print("")
print("V6B remains untouched.")
print("")
print("CAMERA:")
print("V7_DALLAS_DRONE_CAMERA")
print("")
print("PATH:")
print("V7_DALLAS_DRONE_PATH")
print("")
print("DURATION:")
print("12 seconds")
print("360 frames @ 30fps")
print("")
print("TRANSITION POINT:")
print(tuple(transition.location))
print("")
print("Saved:")
print(OUTPUT)
print("")
print("NEXT:")
print("Open V7.")
print("Press NUMPAD 0.")
print("Press SPACE to preview.")
print("================================================")
