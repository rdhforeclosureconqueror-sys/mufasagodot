import bpy
import math
import os
import random
from mathutils import Vector

random.seed(6060)

OUTPUT = r"C:\Users\pftgu\Documents\avlobytest\blender\downtown_dallas_city_v6.blend"

# ============================================================
# DALLAS CITY V6
# FINAL EXTERIOR PASS
#
# Adds:
# - stronger building window/floor readability
# - future mural/billboard reservation surfaces
# - 1.75m scale reference
# - cinematic drone approach animation
# - pyramid transition marker
#
# Does NOT:
# - redesign city
# - improve cars
# - build final pyramid
# - change traffic system
# ============================================================

# ------------------------------------------------------------
# HELPERS
# ------------------------------------------------------------

def get_collection(name):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
    return c


WINDOWS = get_collection("V6_WINDOWS")
CINEMATIC = get_collection("V6_CINEMATIC")
SCALE = get_collection("V6_SCALE_REFERENCE")
ART_SURFACES = get_collection("V6_FUTURE_ART_SURFACES")


def move_to(obj, collection):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    collection.objects.link(obj)


def make_material(
    name,
    color,
    metallic=0.0,
    roughness=0.5,
    emission=None,
    emission_strength=0.0
):
    m = bpy.data.materials.get(name)

    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True

    bsdf = m.node_tree.nodes.get("Principled BSDF")

    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness

        if emission:
            bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
            bsdf.inputs["Emission Strength"].default_value = emission_strength

    return m


def cube(name, location, dimensions, material, collection):
    bpy.ops.mesh.primitive_cube_add(location=location)

    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions

    bpy.ops.object.transform_apply(
        location=False,
        rotation=False,
        scale=True
    )

    if material:
        obj.data.materials.append(material)

    move_to(obj, collection)
    return obj


# ------------------------------------------------------------
# MATERIALS
# ------------------------------------------------------------

WINDOW_DARK = make_material(
    "V6_Window_Dark",
    (0.008, 0.025, 0.045),
    metallic=0.45,
    roughness=0.18
)

WINDOW_BLUE = make_material(
    "V6_Window_Blue",
    (0.015, 0.075, 0.13),
    metallic=0.42,
    roughness=0.16
)

WINDOW_WARM = make_material(
    "V6_Window_Warm",
    (0.12, 0.055, 0.012),
    metallic=0.15,
    roughness=0.25,
    emission=(1.0, 0.28, 0.055),
    emission_strength=2.2
)

ART_PLACEHOLDER = make_material(
    "V6_Future_Art_Surface",
    (0.07, 0.07, 0.075),
    metallic=0.1,
    roughness=0.55
)

HUMAN_MAT = make_material(
    "V6_Human_Scale_Material",
    (0.40, 0.22, 0.11),
    metallic=0.0,
    roughness=0.7
)


# ============================================================
# 1. ADD CLEAR WINDOW/FLOOR BANDS
# ============================================================

# We are intentionally targeting the major tower objects.
# Background buildings stay cheap.

building_candidates = []

for obj in bpy.data.objects:

    if obj.type != "MESH":
        continue

    name = obj.name

    if (
        name.startswith("Downtown_")
        or name.startswith("Dallas_")
        or name.startswith("BackgroundTower_")
    ):
        # avoid already-generated decorative child meshes
        if (
            "Win" not in name
            and "Crown" not in name
            and "Mechanical" not in name
            and "Spire" not in name
        ):
            building_candidates.append(obj)


print("Buildings selected for V6 windows:", len(building_candidates))

window_count = 0

for idx, building in enumerate(building_candidates):

    width = building.dimensions.x
    depth = building.dimensions.y
    height = building.dimensions.z

    if height < 20:
        continue

    x = building.location.x
    y = building.location.y

    # Assume roughly 4.2m per visible floor.
    floor_height = 4.2

    max_floors = int(height / floor_height)

    # Performance guard:
    # only show up to ~28 readable bands per building.
    step = max(1, int(max_floors / 28))

    front_material = WINDOW_BLUE if idx % 3 else WINDOW_DARK

    for floor in range(2, max_floors, step):

        z = floor * floor_height

        if z >= height - 2:
            break

        # FRONT FACE
        mat = WINDOW_WARM if (floor + idx) % 6 == 0 else front_material

        cube(
            f"V6_WindowFront_{idx}_{floor}",
            (
                x,
                y - depth / 2 - 0.08,
                z
            ),
            (
                width * 0.78,
                0.12,
                1.25
            ),
            mat,
            WINDOWS
        )

        # SIDE FACE — only one side to keep cost reasonable
        cube(
            f"V6_WindowSide_{idx}_{floor}",
            (
                x + width / 2 + 0.08,
                y,
                z
            ),
            (
                0.12,
                depth * 0.72,
                1.25
            ),
            mat,
            WINDOWS
        )

        window_count += 2


print("V6 window bands created:", window_count)


# ============================================================
# 2. RESERVE A FEW FUTURE ART / BILLBOARD FACADES
# ============================================================

# These are simple blank panels.
# We are NOT adding artwork yet.

art_candidates = building_candidates[:8]

for i, building in enumerate(art_candidates):

    width = building.dimensions.x
    depth = building.dimensions.y
    height = building.dimensions.z

    if height < 35:
        continue

    x = building.location.x
    y = building.location.y

    panel_w = max(8, min(width * 0.45, 22))
    panel_h = max(7, min(height * 0.14, 18))

    panel = cube(
        f"V6_FUTURE_ART_PANEL_{i}",
        (
            x,
            y - depth / 2 - 0.16,
            height * 0.42
        ),
        (
            panel_w,
            0.10,
            panel_h
        ),
        ART_PLACEHOLDER,
        ART_SURFACES
    )

    panel.hide_render = False


# ============================================================
# 3. HUMAN SCALE REFERENCE — EXACTLY 1.75m
# ============================================================

# Simple mannequin from Z=0 to Z=1.75.

human_root = bpy.data.objects.new(
    "HUMAN_SCALE_REFERENCE_1_75M",
    None
)

human_root.location = (-58, -315, 0)
SCALE.objects.link(human_root)


# legs: ground to 0.85
for side in (-1, 1):

    leg = cube(
        f"HumanScale_Leg_{side}",
        (
            -58 + side * 0.10,
            -315,
            0.425
        ),
        (
            0.14,
            0.18,
            0.85
        ),
        HUMAN_MAT,
        SCALE
    )

    leg.parent = human_root


# torso
torso = cube(
    "HumanScale_Torso",
    (-58, -315, 1.12),
    (0.44, 0.26, 0.54),
    HUMAN_MAT,
    SCALE
)

torso.parent = human_root


# arms
for side in (-1, 1):

    arm = cube(
        f"HumanScale_Arm_{side}",
        (
            -58 + side * 0.31,
            -315,
            1.15
        ),
        (
            0.12,
            0.15,
            0.62
        ),
        HUMAN_MAT,
        SCALE
    )

    arm.parent = human_root


# head center chosen so top reaches exactly 1.75m
HEAD_RADIUS = 0.16
HEAD_CENTER_Z = 1.75 - HEAD_RADIUS

bpy.ops.mesh.primitive_uv_sphere_add(
    segments=16,
    ring_count=8,
    radius=HEAD_RADIUS,
    location=(-58, -315, HEAD_CENTER_Z)
)

head = bpy.context.object
head.name = "HumanScale_Head"
head.data.materials.append(HUMAN_MAT)
head.parent = human_root
move_to(head, SCALE)


# ============================================================
# 4. PYRAMID TARGET / TRANSITION POINT
# ============================================================

anchor = bpy.data.objects.get("PYRAMID_ANCHOR")

if anchor:
    pyramid_target_location = anchor.location.copy()
else:
    # fallback based on previous versions
    pyramid_target_location = Vector((0, 800, 0))


transition = bpy.data.objects.get("PYRAMID_TRANSITION_POINT")

if transition is None:
    transition = bpy.data.objects.new(
        "PYRAMID_TRANSITION_POINT",
        None
    )
    CINEMATIC.objects.link(transition)

transition.empty_display_type = "SPHERE"
transition.empty_display_size = 12
transition.location = (
    pyramid_target_location.x,
    pyramid_target_location.y - 230,
    45
)


# Target for camera tracking
camera_target = bpy.data.objects.get("DRONE_CAMERA_TARGET")

if camera_target is None:
    camera_target = bpy.data.objects.new(
        "DRONE_CAMERA_TARGET",
        None
    )
    CINEMATIC.objects.link(camera_target)

camera_target.empty_display_type = "SPHERE"
camera_target.empty_display_size = 5

camera_target.location = (
    pyramid_target_location.x,
    pyramid_target_location.y,
    145
)


# ============================================================
# 5. DRONE FLIGHT PATH
# ============================================================

curve_data = bpy.data.curves.new(
    "Dallas_Drone_Approach_Path",
    type="CURVE"
)

curve_data.dimensions = "3D"
curve_data.resolution_u = 24

spline = curve_data.splines.new("BEZIER")
spline.bezier_points.add(4)

# Five cinematic control points.
points = [
    (-650, -900, 420),   # far aerial establishing
    (-350, -520, 330),   # approach skyline
    (-130, -120, 245),   # downtown
    (0, 320, 175),       # descend toward destination
    (
        pyramid_target_location.x,
        pyramid_target_location.y - 260,
        90
    )                    # final approach
]

for bp, co in zip(spline.bezier_points, points):

    bp.co = co
    bp.handle_left_type = "AUTO"
    bp.handle_right_type = "AUTO"


path = bpy.data.objects.new(
    "Dallas_Drone_Approach_Path",
    curve_data
)

CINEMATIC.objects.link(path)


# ============================================================
# 6. DRONE CAMERA
# ============================================================

bpy.ops.object.camera_add(
    location=points[0]
)

camera = bpy.context.object
camera.name = "DALLAS_DRONE_INTRO_CAMERA"
camera.data.lens = 42
camera.data.sensor_width = 36

move_to(camera, CINEMATIC)


# Follow path
follow = camera.constraints.new(type="FOLLOW_PATH")
follow.target = path
follow.use_fixed_location = True
follow.forward_axis = "FORWARD_X"
follow.up_axis = "UP_Z"


# Track toward pyramid
track = camera.constraints.new(type="TRACK_TO")
track.target = camera_target
track.track_axis = "TRACK_NEGATIVE_Z"
track.up_axis = "UP_Y"


# ============================================================
# 7. ANIMATE CAMERA
# ============================================================

scene = bpy.context.scene

scene.render.fps = 30

INTRO_START = 1
INTRO_END = 360  # 12 seconds at 30fps

scene.frame_start = INTRO_START
scene.frame_end = INTRO_END

follow.offset_factor = 0.0
follow.keyframe_insert(
    data_path="offset_factor",
    frame=INTRO_START
)

follow.offset_factor = 1.0
follow.keyframe_insert(
    data_path="offset_factor",
    frame=INTRO_END
)


# Smooth interpolation
if camera.animation_data and camera.animation_data.action:

    for fc in camera.animation_data.action.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"


scene.camera = camera


# ============================================================
# 8. VALIDATION CAMERA
# ============================================================

bpy.ops.object.camera_add(
    location=(-65, -325, 2.8)
)

scale_cam = bpy.context.object
scale_cam.name = "V6_HUMAN_SCALE_VALIDATION_CAMERA"

target = Vector((-58, -315, 1.0))
direction = target - scale_cam.location

scale_cam.rotation_euler = direction.to_track_quat(
    "-Z",
    "Y"
).to_euler()

scale_cam.data.lens = 48

move_to(scale_cam, SCALE)


# ============================================================
# 9. RENDER SETTINGS
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
# 10. SAVE V6
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
print("DALLAS CITY V6 COMPLETE")
print("================================================")
print("")
print("V5 remains untouched.")
print("")
print("WINDOW BANDS CREATED:")
print(window_count)
print("")
print("DRONE CAMERA:")
print("DALLAS_DRONE_INTRO_CAMERA")
print("")
print("DRONE DURATION:")
print("12 seconds / 360 frames @ 30fps")
print("")
print("PYRAMID TRANSITION POINT:")
print(tuple(transition.location))
print("")
print("HUMAN SCALE:")
print("1.75 meters")
print("")
print("Saved:")
print(OUTPUT)
print("")
print("NEXT:")
print("Open V6 in Blender.")
print("Press NUMPAD 0 for drone camera.")
print("Press SPACE to play the cinematic.")
print("================================================")
