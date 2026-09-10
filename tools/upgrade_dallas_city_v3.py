import bpy
import math
import random
import os
from mathutils import Vector

random.seed(3030)

OUTPUT = r"C:\Users\pftgu\Documents\avlobytest\blender\downtown_dallas_city_v3.blend"

# ============================================================
# DALLAS CITY V3
# Street-level / open-world environment pass
# Loads V2 and upgrades it rather than rebuilding from zero.
# ============================================================

# ------------------------------------------------------------
# HELPERS
# ------------------------------------------------------------

def get_collection(name):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    return col

STREET_LEVEL = get_collection("STREET_LEVEL")
STOREFRONTS = get_collection("STOREFRONTS")
TRAFFIC = get_collection("TRAFFIC")
PARKING = get_collection("PARKING")
PROPS = get_collection("CITY_PROPS")
BACKGROUND = get_collection("BACKGROUND_CITY")
PYRAMID_SITE = get_collection("PYRAMID_SITE")

def move_to(obj, col):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    col.objects.link(obj)

def existing_mat(name):
    return bpy.data.materials.get(name)

ROAD = existing_mat("Asphalt")
SIDEWALK = existing_mat("Concrete_Sidewalk")
GLASS_DARK = existing_mat("Glass_Dark")
GLASS_BLUE = existing_mat("Glass_Blue")
CONCRETE_DARK = existing_mat("Concrete_Dark")
CONCRETE_LIGHT = existing_mat("Concrete_Light")
METAL_BLACK = existing_mat("Metal_Black")
GOLD = existing_mat("City_Gold")
WINDOW_WARM = existing_mat("Window_Warm")
WHITE_LINE = existing_mat("Road_Line_White")
YELLOW_LINE = existing_mat("Road_Line_Yellow")
RED = existing_mat("Accent_Red")
GREEN = existing_mat("Accent_Green")

def new_mat(name, color, metallic=0.0, roughness=0.5,
            emission=None, emission_strength=0.0):

    mat = bpy.data.materials.get(name)

    if mat:
        return mat

    mat = bpy.data.materials.new(name)
    mat.use_nodes = True

    bsdf = mat.node_tree.nodes.get("Principled BSDF")

    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness

    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength

    return mat

BRICK = new_mat(
    "Brick_Deep",
    (0.16, 0.045, 0.028),
    roughness=0.8
)

STONE = new_mat(
    "Urban_Stone",
    (0.26, 0.25, 0.23),
    roughness=0.68
)

STORE_GLASS = new_mat(
    "Storefront_Glass",
    (0.018, 0.055, 0.075),
    metallic=0.35,
    roughness=0.15
)

SIGN_RED = new_mat(
    "Sign_Red",
    (0.55, 0.008, 0.012),
    roughness=0.35,
    emission=(1.0, 0.015, 0.01),
    emission_strength=1.5
)

SIGN_GOLD = new_mat(
    "Sign_Gold",
    (0.65, 0.30, 0.025),
    metallic=0.7,
    roughness=0.2,
    emission=(1.0, 0.18, 0.02),
    emission_strength=1.2
)

CAR_RED = new_mat("Car_Red", (0.35, 0.012, 0.015), metallic=0.55, roughness=0.25)
CAR_BLUE = new_mat("Car_Blue", (0.015, 0.055, 0.16), metallic=0.55, roughness=0.25)
CAR_WHITE = new_mat("Car_White", (0.52, 0.52, 0.50), metallic=0.25, roughness=0.28)
CAR_BLACK = new_mat("Car_Black", (0.008, 0.01, 0.013), metallic=0.65, roughness=0.22)

def cube(name, loc, size, mat, col, bevel=0.0):
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
        mod = obj.modifiers.new("SoftEdges", "BEVEL")
        mod.width = bevel
        mod.segments = 2

    move_to(obj, col)

    return obj

# ============================================================
# 1. REMOVE RANDOM ROOFTOP SPIRES / MINI PYRAMIDS
# ============================================================

remove_names = []

for obj in bpy.data.objects:
    if "_Spire" in obj.name:
        remove_names.append(obj.name)

for name in remove_names:
    obj = bpy.data.objects.get(name)

    if obj:
        bpy.data.objects.remove(obj, do_unlink=True)

print("Removed rooftop spires:", len(remove_names))

# ============================================================
# 2. STREET-LEVEL BUILDING PODIUMS
# ============================================================

# These fill the huge empty areas beneath the skyscrapers.
# They create storefront-scale architecture around the boulevard.

podium_specs = [
    (-145, -430, 105, 90, 22),
    (145, -430, 105, 90, 22),

    (-145, -260, 100, 105, 25),
    (145, -260, 100, 105, 25),

    (-150, -85, 110, 105, 28),
    (150, -85, 110, 105, 28),

    (-145, 95, 105, 110, 26),
    (145, 95, 105, 110, 26),

    (-150, 280, 115, 110, 30),
    (150, 280, 115, 110, 30),

    (-150, 460, 115, 105, 28),
    (150, 460, 115, 105, 28),
]

for i, (x, y, w, d, h) in enumerate(podium_specs):

    base_mat = BRICK if i % 3 == 0 else STONE

    cube(
        f"StreetPodium_{i:02d}",
        (x, y, h / 2),
        (w, d, h),
        base_mat,
        STREET_LEVEL,
        bevel=1.2
    )

    # large street-facing glass facade
    facing_x = -1 if x > 0 else 1

    glass_x = x + facing_x * (w / 2 + 0.25)

    cube(
        f"StreetPodiumGlass_{i:02d}",
        (glass_x, y, 8),
        (0.4, d * 0.78, 11),
        STORE_GLASS,
        STOREFRONTS
    )

    # upper glass strip
    cube(
        f"StreetPodiumUpperGlass_{i:02d}",
        (glass_x, y, 18),
        (0.42, d * 0.62, 3.2),
        WINDOW_WARM,
        STOREFRONTS
    )

# ============================================================
# 3. STOREFRONT STRIPS
# ============================================================

for side in (-1, 1):

    x = side * 91

    for i, y in enumerate(range(-480, 520, 80)):

        width = 35
        depth = 52
        height = random.choice([11, 13, 15])

        material = BRICK if i % 2 == 0 else CONCRETE_DARK

        cube(
            f"Store_{side}_{i}",
            (x, y, height / 2),
            (width, depth, height),
            material,
            STOREFRONTS,
            bevel=0.8
        )

        storefront_x = x - side * (width / 2 + 0.25)

        cube(
            f"StoreGlass_{side}_{i}",
            (storefront_x, y, 5),
            (0.35, depth * 0.72, 7),
            STORE_GLASS,
            STOREFRONTS
        )

        # awning
        cube(
            f"StoreAwning_{side}_{i}",
            (
                storefront_x - side * 2.0,
                y,
                9.3
            ),
            (4.0, depth * 0.62, 0.6),
            RED if i % 3 == 0 else METAL_BLACK,
            STOREFRONTS
        )

        # sign
        cube(
            f"StoreSign_{side}_{i}",
            (
                storefront_x - side * 0.6,
                y,
                11.5
            ),
            (0.3, depth * 0.35, 1.8),
            SIGN_GOLD if i % 2 == 0 else SIGN_RED,
            STOREFRONTS
        )

# ============================================================
# 4. PARKING GARAGES
# ============================================================

garage_positions = [
    (-355, -300),
    (355, -260),
    (-365, 150),
    (365, 180),
]

for i, (x, y) in enumerate(garage_positions):

    floors = 5
    floor_h = 5.0
    h = floors * floor_h

    cube(
        f"ParkingGarage_{i}",
        (x, y, h / 2),
        (125, 105, h),
        CONCRETE_DARK,
        PARKING,
        bevel=1.2
    )

    # Horizontal openings
    for floor in range(floors):

        z = floor * floor_h + 3

        for side in (-1, 1):

            cube(
                f"GarageOpening_{i}_{floor}_{side}",
                (
                    x + side * 63,
                    y,
                    z
                ),
                (0.4, 82, 2.1),
                METAL_BLACK,
                PARKING
            )

# ============================================================
# 5. SIMPLE CARS
# ============================================================

car_materials = [
    CAR_RED,
    CAR_BLUE,
    CAR_WHITE,
    CAR_BLACK
]

def car(name, x, y, rotation=0.0, material=None):

    if material is None:
        material = random.choice(car_materials)

    body = cube(
        name,
        (x, y, 1.25),
        (4.6, 9.5, 2.3),
        material,
        TRAFFIC,
        bevel=0.7
    )

    body.rotation_euler.z = math.radians(rotation)

    cabin = cube(
        name + "_Cabin",
        (x, y, 2.8),
        (3.7, 5.3, 1.5),
        STORE_GLASS,
        TRAFFIC,
        bevel=0.5
    )

    cabin.rotation_euler.z = math.radians(rotation)

for i, y in enumerate(range(-500, 520, 90)):

    if i % 2 == 0:
        car(
            f"TrafficNorth_{i}",
            -17,
            y,
            0
        )

    if i % 3 == 0:
        car(
            f"TrafficSouth_{i}",
            17,
            y + 35,
            0
        )

# parked cars along side roads
for i in range(16):

    side = -1 if i % 2 == 0 else 1

    car(
        f"ParkedCar_{i}",
        side * random.uniform(115, 230),
        random.uniform(-450, 470),
        random.choice([0, 90]),
        random.choice(car_materials)
    )

# ============================================================
# 6. TRAFFIC LIGHTS
# ============================================================

def traffic_light(name, x, y, rotation=0):

    pole = cube(
        name + "_Pole",
        (x, y, 7),
        (0.7, 0.7, 14),
        METAL_BLACK,
        PROPS
    )

    arm = cube(
        name + "_Arm",
        (x, y, 13),
        (16, 0.6, 0.6),
        METAL_BLACK,
        PROPS
    )

    arm.rotation_euler.z = math.radians(rotation)

    housing = cube(
        name + "_Housing",
        (x + 6, y, 12),
        (2.0, 1.5, 5.2),
        METAL_BLACK,
        PROPS,
        bevel=0.2
    )

    for zi, mat in [
        (13.3, SIGN_RED),
        (12.0, GOLD),
        (10.7, GREEN)
    ]:
        bpy.ops.mesh.primitive_uv_sphere_add(
            segments=10,
            ring_count=6,
            radius=0.45,
            location=(x + 7.05, y - 0.8, zi)
        )

        light = bpy.context.object
        light.name = name + "_Signal"
        light.data.materials.append(mat)
        move_to(light, PROPS)

for i, y in enumerate([-420, -170, 90, 350, 610]):

    traffic_light(
        f"TrafficLightL_{i}",
        -62,
        y - 32,
        0
    )

    traffic_light(
        f"TrafficLightR_{i}",
        62,
        y + 32,
        180
    )

# ============================================================
# 7. BENCHES / BINS / STREET PROPS
# ============================================================

for i, y in enumerate(range(-450, 500, 100)):

    for side in (-1, 1):

        x = side * 72

        cube(
            f"BenchSeat_{side}_{i}",
            (x, y, 1.2),
            (2.0, 7.0, 0.5),
            METAL_BLACK,
            PROPS,
            bevel=0.2
        )

        cube(
            f"BenchBack_{side}_{i}",
            (
                x + side * 0.9,
                y,
                2.3
            ),
            (0.35, 7.0, 2.2),
            METAL_BLACK,
            PROPS
        )

        # trash bin
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=12,
            radius=1.1,
            depth=2.8,
            location=(x, y + 9, 1.4)
        )

        bin_obj = bpy.context.object
        bin_obj.name = f"TrashBin_{side}_{i}"
        bin_obj.data.materials.append(METAL_BLACK)
        move_to(bin_obj, PROPS)

# ============================================================
# 8. BUS SHELTERS
# ============================================================

for i, y in enumerate([-310, 210]):

    x = 78

    cube(
        f"BusShelterRoof_{i}",
        (x, y, 4.8),
        (8, 18, 0.5),
        METAL_BLACK,
        PROPS
    )

    cube(
        f"BusShelterGlass_{i}",
        (x + 3.7, y, 2.5),
        (0.3, 16, 5),
        STORE_GLASS,
        PROPS
    )

# ============================================================
# 9. SIDE-STREET LOW RISE INFILL
# ============================================================

infill_count = 0

for side in (-1, 1):

    for x_offset in (185, 260, 335):

        x = side * x_offset

        for y in range(-430, 500, 140):

            infill_count += 1

            width = random.uniform(45, 75)
            depth = random.uniform(55, 90)
            height = random.uniform(20, 55)

            mat = random.choice(
                [BRICK, STONE, CONCRETE_DARK, CONCRETE_LIGHT]
            )

            cube(
                f"Infill_{infill_count}",
                (x, y, height / 2),
                (width, depth, height),
                mat,
                STREET_LEVEL,
                bevel=1.0
            )

            # window ribbon
            cube(
                f"InfillWindow_{infill_count}",
                (
                    x - side * (width/2 + 0.2),
                    y,
                    min(height * 0.55, 18)
                ),
                (
                    0.35,
                    depth * 0.65,
                    3.2
                ),
                WINDOW_WARM,
                STREET_LEVEL
            )

# ============================================================
# 10. DISTANT SKYLINE
# ============================================================

# Cheap background masses create depth behind downtown.

for i in range(34):

    side = -1 if i < 17 else 1

    x = side * random.uniform(470, 780)
    y = random.uniform(50, 730)

    w = random.uniform(35, 90)
    d = random.uniform(35, 90)
    h = random.uniform(55, 190)

    cube(
        f"BackgroundTower_{i}",
        (x, y, h / 2),
        (w, d, h),
        random.choice([
            GLASS_DARK,
            GLASS_BLUE,
            CONCRETE_DARK
        ]),
        BACKGROUND,
        bevel=1.0
    )

# ============================================================
# 11. PYRAMID DESTINATION PROXY
# ============================================================

# Rebuild the placeholder as ONE dominant landmark.

old_proxy = bpy.data.objects.get("PYRAMID_PROXY_REPLACE_LATER")

if old_proxy:
    bpy.data.objects.remove(old_proxy, do_unlink=True)

PYRAMID_Y = 800
PYRAMID_BASE = 430
PYRAMID_HEIGHT = 540

half = PYRAMID_BASE / 2

verts = [
    (-half, -half, 0),
    ( half, -half, 0),
    ( half,  half, 0),
    (-half,  half, 0),
    (0, 0, PYRAMID_HEIGHT)
]

faces = [
    (0, 1, 2, 3),
    (0, 1, 4),
    (1, 2, 4),
    (2, 3, 4),
    (3, 0, 4)
]

mesh = bpy.data.meshes.new("V3_PyramidProxyMesh")
mesh.from_pydata(verts, [], faces)
mesh.update()

proxy = bpy.data.objects.new(
    "PYRAMID_PROXY_REPLACE_LATER",
    mesh
)

PYRAMID_SITE.objects.link(proxy)
proxy.location = (0, PYRAMID_Y, 0)

proxy_mat = bpy.data.materials.get("Pyramid_Development_Proxy")

if proxy_mat:
    proxy.data.materials.append(proxy_mat)

# Preserve / move anchor.
anchor = bpy.data.objects.get("PYRAMID_ANCHOR")

if anchor:
    anchor.location = (0, PYRAMID_Y, 0)

# ============================================================
# 12. CAMERA - STREET LEVEL
# ============================================================

cam = bpy.data.objects.get("Cinematic_Dallas_Approach_Camera")

if cam:

    cam.location = (0, -760, 32)

    target = Vector((0, 700, 170))
    direction = target - cam.location

    cam.rotation_euler = direction.to_track_quat(
        "-Z",
        "Y"
    ).to_euler()

    cam.data.lens = 42

    bpy.context.scene.camera = cam

# ============================================================
# 13. SECOND CAMERA - PEDESTRIAN VIEW
# ============================================================

bpy.ops.object.camera_add(
    location=(-38, -390, 8)
)

walk_cam = bpy.context.object
walk_cam.name = "Street_Level_Walk_Camera"

target = Vector((0, 620, 85))
direction = target - walk_cam.location

walk_cam.rotation_euler = direction.to_track_quat(
    "-Z",
    "Y"
).to_euler()

walk_cam.data.lens = 35

move_to(walk_cam, PROPS)

# ============================================================
# 14. SAVE V3
# ============================================================

bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT"

os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)

bpy.ops.wm.save_as_mainfile(
    filepath=OUTPUT
)

print("")
print("================================================")
print("DALLAS CITY V3 COMPLETE")
print("================================================")
print("V2 remains untouched.")
print("")
print("Added:")
print("- street-level podiums")
print("- storefronts")
print("- parking garages")
print("- cars")
print("- traffic lights")
print("- bus shelters")
print("- benches and bins")
print("- low-rise urban infill")
print("- distant skyline")
print("- improved street-level camera")
print("- larger pyramid destination proxy")
print("- rooftop spires removed")
print("")
print("Saved:")
print(OUTPUT)
print("================================================")
