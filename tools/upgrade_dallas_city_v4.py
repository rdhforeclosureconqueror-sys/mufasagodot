import bpy
import os
import math
import random
from mathutils import Vector

random.seed(44)

OUTPUT = r"C:\Users\pftgu\Documents\avlobytest\blender\downtown_dallas_city_v4.blend"

# ============================================================
# HELPERS
# ============================================================

def get_mat(name, color, metallic=0.0, roughness=0.5):
    mat = bpy.data.materials.get(name)

    if not mat:
        mat = bpy.data.materials.new(name)

    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True

    bsdf = mat.node_tree.nodes.get("Principled BSDF")

    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness

    return mat


def collection(name):
    c = bpy.data.collections.get(name)

    if not c:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)

    return c


def move_to(obj, coll):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)

    coll.objects.link(obj)


def cube(name, location, scale, material, coll):
    bpy.ops.mesh.primitive_cube_add(location=location)

    obj = bpy.context.object
    obj.name = name
    obj.scale = (
        scale[0] / 2,
        scale[1] / 2,
        scale[2] / 2
    )

    bpy.ops.object.transform_apply(
        location=False,
        rotation=False,
        scale=True
    )

    if material:
        obj.data.materials.append(material)

    move_to(obj, coll)

    return obj


# ============================================================
# COLLECTIONS
# ============================================================

V4 = collection("V4_CITY_BLOCK_UPGRADE")
STREETS = collection("V4_SIDE_STREETS")
CARS = collection("V4_TRAFFIC")
DETAIL = collection("V4_STREET_DETAIL")
LANDMARK = collection("V4_LANDMARK_UPGRADE")


# ============================================================
# MATERIALS
# ============================================================

ASPHALT = get_mat(
    "V4_Asphalt",
    (0.018, 0.022, 0.028),
    0.0,
    0.78
)

CONCRETE = get_mat(
    "V4_Concrete",
    (0.28, 0.30, 0.31),
    0.0,
    0.72
)

LANE_WHITE = get_mat(
    "V4_LaneWhite",
    (0.92, 0.92, 0.88),
    0.0,
    0.4
)

LANE_YELLOW = get_mat(
    "V4_LaneYellow",
    (0.95, 0.58, 0.05),
    0.0,
    0.35
)

CAR_BLACK = get_mat(
    "V4_CarBlack",
    (0.015, 0.018, 0.022),
    0.65,
    0.20
)

GLASS = get_mat(
    "V4_CarGlass",
    (0.025, 0.08, 0.11),
    0.45,
    0.12
)

RED = get_mat("V4_CarRed", (0.42, 0.018, 0.012), 0.25, 0.25)
BLUE = get_mat("V4_CarBlue", (0.015, 0.10, 0.32), 0.25, 0.25)
WHITE = get_mat("V4_CarWhite", (0.72, 0.72, 0.69), 0.15, 0.25)
GREEN = get_mat("V4_CarGreen", (0.015, 0.26, 0.08), 0.20, 0.25)
GOLD = get_mat("V4_Gold", (0.65, 0.32, 0.035), 0.65, 0.24)


# ============================================================
# 1. CREATE REAL CROSS STREETS
# ============================================================

# Main boulevard runs roughly along Y.
# These roads cross it and visually divide downtown into blocks.

cross_y = [-430, -285, -140, 20, 180, 340, 500]

for i, y in enumerate(cross_y):

    cube(
        f"V4_CrossStreet_{i}",
        (0, y, 0.16),
        (650, 22, 0.32),
        ASPHALT,
        STREETS
    )

    # lane divider segments
    for x in range(-300, 301, 24):

        if abs(x) < 40:
            continue

        cube(
            f"V4_CrossLane_{i}_{x}",
            (x, y, 0.35),
            (9, 0.45, 0.08),
            LANE_WHITE,
            STREETS
        )


# ============================================================
# 2. PARALLEL SIDE STREETS
# ============================================================

side_x = [-235, -145, 145, 235]

for i, x in enumerate(side_x):

    cube(
        f"V4_ParallelStreet_{i}",
        (x, 30, 0.17),
        (18, 1100, 0.34),
        ASPHALT,
        STREETS
    )

    for y in range(-500, 551, 28):

        cube(
            f"V4_ParallelLane_{i}_{y}",
            (x, y, 0.38),
            (0.45, 10, 0.08),
            LANE_WHITE,
            STREETS
        )


# ============================================================
# 3. INTERSECTION CROSSWALKS
# ============================================================

for y in cross_y:

    # Main boulevard crossings
    for x in range(-32, 33, 7):

        cube(
            f"V4_Crosswalk_Main_{y}_{x}",
            (x, y - 8, 0.46),
            (3.4, 7.5, 0.07),
            LANE_WHITE,
            DETAIL
        )

    # Side street crossings
    for sx in side_x:

        for offset in range(-8, 9, 4):

            cube(
                f"V4_Crosswalk_{sx}_{y}_{offset}",
                (sx + offset, y, 0.46),
                (1.8, 7, 0.07),
                LANE_WHITE,
                DETAIL
            )


# ============================================================
# 4. IMPROVED MID-DETAIL CAR
# ============================================================

def make_car(name, x, y, material, rotation=0):

    root = bpy.data.objects.new(name, None)
    CARS.objects.link(root)

    root.location = (x, y, 0.65)
    root.rotation_euler[2] = math.radians(rotation)

    body = cube(
        name + "_Body",
        (x, y, 1.05),
        (4.6, 8.8, 1.35),
        material,
        CARS
    )

    roof = cube(
        name + "_Cabin",
        (x, y + 0.25, 2.0),
        (3.8, 4.7, 1.25),
        material,
        CARS
    )

    windshield = cube(
        name + "_Glass",
        (x, y - 1.4, 2.15),
        (3.45, 0.18, 0.72),
        GLASS,
        CARS
    )

    # Wheels
    wheel_positions = [
        (-2.25, -2.5),
        ( 2.25, -2.5),
        (-2.25,  2.5),
        ( 2.25,  2.5)
    ]

    for n, (wx, wy) in enumerate(wheel_positions):

        bpy.ops.mesh.primitive_cylinder_add(
            vertices=12,
            radius=0.72,
            depth=0.48,
            location=(x + wx, y + wy, 0.75),
            rotation=(math.radians(90), 0, 0)
        )

        wheel = bpy.context.object
        wheel.name = f"{name}_Wheel_{n}"
        wheel.data.materials.append(CAR_BLACK)
        move_to(wheel, CARS)

        wheel.parent = root

    for obj in (body, roof, windshield):
        obj.parent = root

    return root


# ============================================================
# 5. ADD TRAFFIC
# ============================================================

car_materials = [RED, BLUE, WHITE, GREEN]

cars = []

# Main boulevard traffic
for i, y in enumerate(range(-470, 480, 105)):

    x = -10 if i % 2 == 0 else 11

    car = make_car(
        f"V4_MainTraffic_{i}",
        x,
        y,
        car_materials[i % len(car_materials)]
    )

    cars.append((car, "Y", y))


# Cross-street traffic
for i, y in enumerate([-285, 20, 340]):

    for j, x in enumerate([-250, -175, 175, 250]):

        car = make_car(
            f"V4_CrossTraffic_{i}_{j}",
            x,
            y + (4 if j % 2 else -4),
            car_materials[(i+j) % len(car_materials)],
            90
        )

        cars.append((car, "X", x))


# ============================================================
# 6. ANIMATE TRAFFIC
# ============================================================

scene = bpy.context.scene
scene.frame_start = 1
scene.frame_end = 250

for index, (car, axis, start) in enumerate(cars):

    phase = index * 17

    if axis == "Y":

        car.location.y = start
        car.keyframe_insert(
            data_path="location",
            frame=1
        )

        car.location.y = start + 650
        car.keyframe_insert(
            data_path="location",
            frame=250
        )

    else:

        car.location.x = start
        car.keyframe_insert(
            data_path="location",
            frame=1
        )

        direction = 520 if start < 0 else -520

        car.location.x = start + direction
        car.keyframe_insert(
            data_path="location",
            frame=250
        )

    if car.animation_data and car.animation_data.action:

        action = car.animation_data.action

        for fc in action.fcurves:

            for kp in fc.keyframe_points:
                kp.interpolation = "LINEAR"


# ============================================================
# 7. ENLARGE REUNION-TOWER-STYLE LANDMARK
# ============================================================

# Search for likely sphere objects rather than assuming one exact name.

sphere_candidates = []

for obj in bpy.data.objects:

    n = obj.name.lower()

    if (
        "reunion" in n
        or "sphere" in n
        or "tower_ball" in n
    ):
        if obj.type == "MESH":
            sphere_candidates.append(obj)


# If we find the existing landmark, enlarge the most likely sphere.
if sphere_candidates:

    target = max(
        sphere_candidates,
        key=lambda o: max(o.dimensions)
    )

    target.scale *= 1.48

    print("Enlarged landmark sphere:", target.name)

else:

    print("Existing landmark sphere not confidently identified.")
    print("Leaving V3 geometry untouched.")


# ============================================================
# 8. CREATE A SECOND, BETTER STREET CAMERA
# ============================================================

bpy.ops.object.camera_add(
    location=(-18, -455, 7.2)
)

cam = bpy.context.object
cam.name = "V4_GTA_Street_Camera"

target = Vector((0, 410, 42))
direction = target - cam.location

cam.rotation_euler = direction.to_track_quat(
    "-Z",
    "Y"
).to_euler()

cam.data.lens = 32
cam.data.sensor_width = 36

move_to(cam, V4)

bpy.context.scene.camera = cam


# ============================================================
# 9. RENDER / VIEW SETTINGS
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
# 10. SAVE
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
print("DALLAS CITY V4 COMPLETE")
print("================================================")
print("")
print("V3 remains untouched.")
print("")
print("V4 ADDED:")
print("- cross streets")
print("- parallel streets")
print("- real city-block structure")
print("- intersection crosswalks")
print("- upgraded cars")
print("- four wheels per car")
print("- cabins and windshields")
print("- moving traffic")
print("- enlarged landmark sphere when detected")
print("- GTA-style street camera")
print("")
print("Saved:")
print(OUTPUT)
print("")
print("Open V4 and press NUMPAD 0 for camera view.")
print("Press SPACE to watch traffic move.")
print("================================================")
