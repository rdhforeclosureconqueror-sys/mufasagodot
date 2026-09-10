import bpy
import math
import os
import random
from mathutils import Vector

random.seed(5050)

OUTPUT = r"C:\Users\pftgu\Documents\avlobytest\blender\downtown_dallas_city_v5.blend"

# ============================================================
# DALLAS CITY V5
# PLAYABLE STREET SCALE PASS
# ============================================================

def get_collection(name):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
    return c

PLAYER = get_collection("V5_PLAYER_SCALE")
PEDESTRIANS = get_collection("V5_PEDESTRIANS")
STREET = get_collection("V5_STREET_DETAIL")
SIGNS = get_collection("V5_SIGNS")
TRAFFIC = get_collection("V5_EXTRA_TRAFFIC")
CAMERAS = get_collection("V5_CAMERAS")

def move_to(obj, collection):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    collection.objects.link(obj)

def material(name, color, metallic=0.0, roughness=0.5, emission=None, strength=0.0):
    m = bpy.data.materials.get(name)

    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True

    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness

    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength

    return m

def cube(name, loc, size, mat, collection, bevel=0):
    bpy.ops.mesh.primitive_cube_add(location=loc)

    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size

    bpy.ops.object.transform_apply(
        location=False,
        rotation=False,
        scale=True
    )

    if mat:
        obj.data.materials.append(mat)

    if bevel > 0:
        modifier = obj.modifiers.new("Bevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2

    move_to(obj, collection)

    return obj

# ============================================================
# MATERIALS
# ============================================================

BLACK = material("V5_Black", (0.015, 0.018, 0.022), 0.45, 0.3)
GRAY = material("V5_Gray", (0.25, 0.27, 0.29), 0.1, 0.5)
SKIN = material("V5_Mannequin", (0.42, 0.26, 0.14), 0.0, 0.65)
RED = material("V5_Red", (0.45, 0.01, 0.015), 0.2, 0.3)
BLUE = material("V5_Blue", (0.015, 0.08, 0.28), 0.25, 0.3)
GREEN = material("V5_Green", (0.01, 0.22, 0.05), 0.15, 0.35)
WHITE = material("V5_White", (0.70, 0.70, 0.68), 0.05, 0.4)
GOLD = material(
    "V5_Gold",
    (0.70, 0.34, 0.03),
    0.6,
    0.22,
    emission=(1.0, 0.22, 0.02),
    strength=0.8
)

STORE_GLASS = bpy.data.materials.get("Storefront_Glass")
if STORE_GLASS is None:
    STORE_GLASS = material("Storefront_Glass", (0.02, 0.06, 0.09), 0.35, 0.15)

# ============================================================
# 1. DISABLE GIANT PYRAMID PROXY
# ============================================================

for obj in list(bpy.data.objects):
    if "PYRAMID_PROXY" in obj.name.upper():
        obj.hide_viewport = True
        obj.hide_render = True
        print("Disabled pyramid proxy:", obj.name)

# Preserve PYRAMID_ANCHOR if present.

# ============================================================
# 2. PLAYER START
# ============================================================

player_start = bpy.data.objects.new("PLAYER_START", None)
player_start.empty_display_type = "ARROWS"
player_start.empty_display_size = 2.2
player_start.location = (-46, -360, 0)
PLAYER.objects.link(player_start)

# ============================================================
# 3. HUMAN-SCALE MANNEQUIN
# ============================================================

def make_person(name, x, y, height=1.75, color=SKIN):

    root = bpy.data.objects.new(name, None)
    root.location = (x, y, 0)
    PLAYER.objects.link(root)

    # legs
    for side in (-1, 1):
        cube(
            f"{name}_Leg_{side}",
            (x + side*0.15, y, 0.48),
            (0.20, 0.25, 0.92),
            color,
            PLAYER,
            0.05
        ).parent = root

    # torso
    cube(
        f"{name}_Torso",
        (x, y, 1.12),
        (0.55, 0.32, 0.74),
        color,
        PLAYER,
        0.08
    ).parent = root

    # arms
    for side in (-1, 1):
        cube(
            f"{name}_Arm_{side}",
            (x + side*0.39, y, 1.10),
            (0.16, 0.20, 0.70),
            color,
            PLAYER,
            0.05
        ).parent = root

    # head
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=16,
        ring_count=8,
        radius=0.18,
        location=(x, y, 1.64)
    )

    head = bpy.context.object
    head.name = f"{name}_Head"
    head.data.materials.append(color)
    head.parent = root
    move_to(head, PLAYER)

    return root

avatar = make_person(
    "PLAYER_SCALE_MANNEQUIN",
    -46,
    -360,
    1.75
)

# ============================================================
# 4. PEDESTRIANS
# ============================================================

ped_colors = [RED, BLUE, GREEN, WHITE, SKIN]

for i in range(16):
    side = -1 if i % 2 == 0 else 1

    x = side * random.uniform(55, 72)
    y = random.uniform(-430, 450)

    person = make_person(
        f"Pedestrian_{i:02d}",
        x,
        y,
        random.uniform(1.62, 1.90),
        random.choice(ped_colors)
    )

    move_to(person, PEDESTRIANS)

# ============================================================
# 5. BETTER STOREFRONT DOORS
# ============================================================

# Add visible doors and sign panels to street-facing low-rise buildings.

store_candidates = [
    obj for obj in bpy.data.objects
    if (
        "Store_" in obj.name
        or "StreetPodium_" in obj.name
    )
    and obj.type == "MESH"
]

for index, obj in enumerate(store_candidates[:30]):

    x = obj.location.x
    y = obj.location.y

    side = -1 if x > 0 else 1

    width = max(obj.dimensions.x, 6)

    front_x = x + side * (width/2 + 0.25)

    # Door
    cube(
        f"V5_Door_{index}",
        (front_x, y, 1.25),
        (0.25, 2.2, 2.5),
        STORE_GLASS,
        STREET
    )

    # Sign panel
    cube(
        f"V5_SignPanel_{index}",
        (front_x + side*0.12, y, 3.8),
        (0.28, 5.5, 1.0),
        GOLD if index % 3 == 0 else RED,
        SIGNS
    )

# ============================================================
# 6. INTERSECTION STREET SIGNS
# ============================================================

cross_y = [-430, -285, -140, 20, 180, 340, 500]

for i, y in enumerate(cross_y):

    x = -58

    # pole
    cube(
        f"V5_StreetSignPole_{i}",
        (x, y, 3.5),
        (0.18, 0.18, 7.0),
        BLACK,
        SIGNS
    )

    # horizontal sign
    cube(
        f"V5_StreetSign_Main_{i}",
        (x, y, 6.5),
        (5.6, 0.18, 0.8),
        GREEN,
        SIGNS
    )

    # perpendicular sign
    sign2 = cube(
        f"V5_StreetSign_Cross_{i}",
        (x, y, 7.4),
        (5.0, 0.18, 0.7),
        BLUE,
        SIGNS
    )

    sign2.rotation_euler.z = math.radians(90)

# ============================================================
# 7. HYDRANTS
# ============================================================

for i, y in enumerate(range(-400, 430, 100)):

    side = -1 if i % 2 == 0 else 1
    x = side * 62

    bpy.ops.mesh.primitive_cylinder_add(
        vertices=12,
        radius=0.25,
        depth=0.7,
        location=(x, y, 0.35)
    )

    hydrant = bpy.context.object
    hydrant.name = f"V5_Hydrant_{i}"
    hydrant.data.materials.append(RED)
    move_to(hydrant, STREET)

# ============================================================
# 8. MAILBOX / UTILITY BOXES
# ============================================================

for i, y in enumerate([-330, -100, 120, 320]):

    cube(
        f"V5_UtilityBox_{i}",
        (70, y, 0.65),
        (1.2, 0.8, 1.3),
        GRAY,
        STREET,
        0.08
    )

# ============================================================
# 9. PARKED CARS ALONG CURBS
# ============================================================

car_colors = [RED, BLUE, GREEN, WHITE]

def make_parked_car(name, x, y, color, rotation=0):

    root = bpy.data.objects.new(name, None)
    root.location = (x, y, 0)
    root.rotation_euler.z = math.radians(rotation)
    TRAFFIC.objects.link(root)

    body = cube(
        name + "_Body",
        (x, y, 0.70),
        (1.9, 4.2, 0.85),
        color,
        TRAFFIC,
        0.22
    )

    cabin = cube(
        name + "_Cabin",
        (x, y, 1.20),
        (1.55, 2.15, 0.72),
        STORE_GLASS,
        TRAFFIC,
        0.18
    )

    body.parent = root
    cabin.parent = root

    for side_x in (-0.95, 0.95):
        for wheel_y in (-1.25, 1.25):

            bpy.ops.mesh.primitive_cylinder_add(
                vertices=12,
                radius=0.35,
                depth=0.24,
                location=(x + side_x, y + wheel_y, 0.40),
                rotation=(math.radians(90), 0, 0)
            )

            wheel = bpy.context.object
            wheel.name = name + "_Wheel"
            wheel.data.materials.append(BLACK)
            wheel.parent = root
            move_to(wheel, TRAFFIC)

    return root

for i in range(12):

    side = -1 if i % 2 == 0 else 1

    make_parked_car(
        f"V5_Parked_{i}",
        side * 82,
        -390 + i * 68,
        car_colors[i % len(car_colors)],
        0
    )

# ============================================================
# 10. CROSS-STREET MOVING CARS
# ============================================================

moving_roots = []

for i, y in enumerate([-285, 20, 340]):

    car = make_parked_car(
        f"V5_CrossMoving_{i}",
        -220,
        y,
        car_colors[(i+1) % len(car_colors)],
        90
    )

    moving_roots.append((car, y))

for i, (car, y) in enumerate(moving_roots):

    start_frame = 1 + i * 30
    end_frame = 220 + i * 10

    car.location.x = -260
    car.keyframe_insert(
        data_path="location",
        frame=start_frame
    )

    car.location.x = 260
    car.keyframe_insert(
        data_path="location",
        frame=end_frame
    )

    if car.animation_data and car.animation_data.action:

        for fc in car.animation_data.action.fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = "LINEAR"

# ============================================================
# 11. TRUE EYE-LEVEL CAMERA
# ============================================================

bpy.ops.object.camera_add(
    location=(-46, -355, 1.65)
)

eye_cam = bpy.context.object
eye_cam.name = "V5_EYE_LEVEL_CAMERA"

eye_target = Vector((-40, 80, 1.65))
eye_direction = eye_target - eye_cam.location

eye_cam.rotation_euler = eye_direction.to_track_quat(
    "-Z",
    "Y"
).to_euler()

eye_cam.data.lens = 38

move_to(eye_cam, CAMERAS)

# ============================================================
# 12. THIRD-PERSON PLAYER CAMERA
# ============================================================

bpy.ops.object.camera_add(
    location=(-46, -365, 3.2)
)

third_cam = bpy.context.object
third_cam.name = "V5_THIRD_PERSON_CAMERA"

third_target = Vector((-46, -355, 1.2))
direction = third_target - third_cam.location

third_cam.rotation_euler = direction.to_track_quat(
    "-Z",
    "Y"
).to_euler()

third_cam.data.lens = 42

move_to(third_cam, CAMERAS)

# ============================================================
# 13. PEDESTRIAN WALK CAMERA
# ============================================================

bpy.ops.object.camera_add(
    location=(-60, -250, 1.70)
)

walk_cam = bpy.context.object
walk_cam.name = "V5_SIDEWALK_WALK_CAMERA"

walk_target = Vector((-60, 180, 1.70))
direction = walk_target - walk_cam.location

walk_cam.rotation_euler = direction.to_track_quat(
    "-Z",
    "Y"
).to_euler()

walk_cam.data.lens = 34

move_to(walk_cam, CAMERAS)

# Make third-person default camera.
bpy.context.scene.camera = third_cam

# ============================================================
# 14. SAVE
# ============================================================

scene = bpy.context.scene
scene.frame_start = 1
scene.frame_end = 250
scene.render.engine = "BLENDER_EEVEE_NEXT"

os.makedirs(
    os.path.dirname(OUTPUT),
    exist_ok=True
)

bpy.ops.wm.save_as_mainfile(
    filepath=OUTPUT
)

print("")
print("================================================")
print("DALLAS CITY V5 COMPLETE")
print("================================================")
print("")
print("V4 remains untouched.")
print("")
print("ADDED:")
print("- PLAYER_START")
print("- 1.75m scale mannequin")
print("- pedestrians")
print("- storefront doors")
print("- storefront sign panels")
print("- street signs")
print("- hydrants")
print("- utility boxes")
print("- parked cars")
print("- extra cross-street moving cars")
print("- eye-level camera")
print("- third-person player camera")
print("- sidewalk camera")
print("- pyramid proxy hidden")
print("")
print("DEFAULT CAMERA:")
print("V5_THIRD_PERSON_CAMERA")
print("")
print("Saved:")
print(OUTPUT)
print("================================================")
