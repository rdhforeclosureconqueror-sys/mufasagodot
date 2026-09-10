import bpy
import math
import random
import os
from mathutils import Vector

# ============================================================
# UNLEASH DA BEAST
# DALLAS-INSPIRED CITY GENERATOR V2
#
# PURPOSE:
# - Build a more convincing downtown environment.
# - Preserve a huge development site for the future pyramid.
# - Create a Blender preview before anything goes into Godot.
# ============================================================

OUTPUT_BLEND = r"C:\Users\pftgu\Documents\avlobytest\blender\downtown_dallas_city_v2.blend"

random.seed(2026)

# ------------------------------------------------------------
# CLEAN
# ------------------------------------------------------------

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

for datablock in list(bpy.data.materials):
    bpy.data.materials.remove(datablock)

# ------------------------------------------------------------
# COLLECTION HELPERS
# ------------------------------------------------------------

def collection(name):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    return col

CITY        = collection("CITY")
ROADS       = collection("ROADS")
BUILDINGS   = collection("BUILDINGS")
LANDMARKS   = collection("LANDMARKS")
WINDOWS     = collection("WINDOW_LIGHTS")
STREET      = collection("STREET_DRESSING")
VEGETATION  = collection("VEGETATION")
PYRAMID     = collection("PYRAMID_SITE")
LIGHTING    = collection("LIGHTING")
CAMERAS     = collection("CAMERAS")

def move_to(obj, col):
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    col.objects.link(obj)

# ------------------------------------------------------------
# MATERIALS
# ------------------------------------------------------------

def mat(name, color, metallic=0.0, roughness=0.45,
        emission=None, emission_strength=0.0):

    m = bpy.data.materials.new(name)
    m.use_nodes = True

    bsdf = m.node_tree.nodes.get("Principled BSDF")

    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness

    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength

    return m


ROAD = mat(
    "Asphalt",
    (0.018, 0.021, 0.025),
    roughness=0.82
)

SIDEWALK = mat(
    "Concrete_Sidewalk",
    (0.22, 0.23, 0.24),
    roughness=0.72
)

PLAZA = mat(
    "Plaza_Stone",
    (0.33, 0.29, 0.23),
    roughness=0.62
)

GLASS_DARK = mat(
    "Glass_Dark",
    (0.015, 0.030, 0.050),
    metallic=0.50,
    roughness=0.18
)

GLASS_BLUE = mat(
    "Glass_Blue",
    (0.025, 0.095, 0.155),
    metallic=0.48,
    roughness=0.16
)

GLASS_GREEN = mat(
    "Glass_Green",
    (0.025, 0.11, 0.075),
    metallic=0.42,
    roughness=0.18
)

GLASS_BRONZE = mat(
    "Glass_Bronze",
    (0.14, 0.065, 0.025),
    metallic=0.40,
    roughness=0.20
)

CONCRETE_DARK = mat(
    "Concrete_Dark",
    (0.075, 0.080, 0.088),
    roughness=0.60
)

CONCRETE_LIGHT = mat(
    "Concrete_Light",
    (0.32, 0.33, 0.34),
    roughness=0.57
)

METAL_BLACK = mat(
    "Metal_Black",
    (0.012, 0.014, 0.017),
    metallic=0.72,
    roughness=0.27
)

GOLD = mat(
    "City_Gold",
    (0.72, 0.32, 0.035),
    metallic=0.90,
    roughness=0.16
)

WINDOW_WARM = mat(
    "Window_Warm",
    (0.18, 0.075, 0.018),
    roughness=0.25,
    emission=(1.0, 0.28, 0.055),
    emission_strength=4.0
)

WINDOW_COOL = mat(
    "Window_Cool",
    (0.015, 0.055, 0.12),
    roughness=0.22,
    emission=(0.04, 0.25, 0.80),
    emission_strength=2.1
)

WHITE_LINE = mat(
    "Road_Line_White",
    (0.75, 0.75, 0.70),
    roughness=0.45,
    emission=(0.40, 0.40, 0.34),
    emission_strength=0.25
)

YELLOW_LINE = mat(
    "Road_Line_Yellow",
    (0.88, 0.55, 0.045),
    roughness=0.40,
    emission=(0.60, 0.25, 0.02),
    emission_strength=0.30
)

TREE_TRUNK = mat(
    "Tree_Trunk",
    (0.09, 0.045, 0.02),
    roughness=0.85
)

TREE_GREEN = mat(
    "Tree_Green",
    (0.025, 0.18, 0.055),
    roughness=0.78
)

PYRAMID_PROXY = mat(
    "Pyramid_Development_Proxy",
    (0.70, 0.49, 0.18),
    metallic=0.25,
    roughness=0.35
)

RED = mat(
    "Accent_Red",
    (0.40, 0.005, 0.008),
    roughness=0.35
)

GREEN = mat(
    "Accent_Green",
    (0.006, 0.25, 0.035),
    roughness=0.35
)

# ------------------------------------------------------------
# BASIC GEOMETRY
# ------------------------------------------------------------

def cube(name, location, size, material, col, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(location=location)
    ob = bpy.context.object
    ob.name = name
    ob.dimensions = size

    bpy.ops.object.transform_apply(
        location=False,
        rotation=False,
        scale=True
    )

    if material:
        ob.data.materials.append(material)

    if bevel > 0:
        mod = ob.modifiers.new("EdgeSoftening", "BEVEL")
        mod.width = bevel
        mod.segments = 2

    move_to(ob, col)
    return ob


# ------------------------------------------------------------
# CITY BASE
# ------------------------------------------------------------

CITY_WIDTH = 1800
CITY_DEPTH = 2000

cube(
    "CityBase",
    (0, 250, -2),
    (CITY_WIDTH, CITY_DEPTH, 4),
    CONCRETE_DARK,
    CITY
)

# ------------------------------------------------------------
# PRIMARY BOULEVARD
# ------------------------------------------------------------

# Camera is south; pyramid is north.

BOULEVARD_WIDTH = 72
BOULEVARD_LENGTH = 1550

cube(
    "Unleash_Boulevard",
    (0, 150, 0.10),
    (BOULEVARD_WIDTH, BOULEVARD_LENGTH, 0.20),
    ROAD,
    ROADS
)

cube(
    "Boulevard_Sidewalk_L",
    (-48, 150, 0.18),
    (20, BOULEVARD_LENGTH, 0.36),
    SIDEWALK,
    ROADS
)

cube(
    "Boulevard_Sidewalk_R",
    (48, 150, 0.18),
    (20, BOULEVARD_LENGTH, 0.36),
    SIDEWALK,
    ROADS
)

# Median
cube(
    "Boulevard_Median",
    (0, 150, 0.28),
    (5, BOULEVARD_LENGTH, 0.56),
    PLAZA,
    ROADS
)

# Lane markings
for x in (-18, 18):
    cube(
        f"LaneLine_{x}",
        (x, 150, 0.24),
        (0.6, BOULEVARD_LENGTH, 0.05),
        WHITE_LINE,
        ROADS
    )

for x in (-3, 3):
    cube(
        f"MedianLine_{x}",
        (x, 150, 0.31),
        (0.4, BOULEVARD_LENGTH, 0.05),
        YELLOW_LINE,
        ROADS
    )

# ------------------------------------------------------------
# CROSS STREETS
# ------------------------------------------------------------

cross_streets = [-420, -170, 90, 350, 610]

for idx, y in enumerate(cross_streets):
    cube(
        f"CrossStreet_{idx}",
        (0, y, 0.11),
        (1300, 54, 0.22),
        ROAD,
        ROADS
    )

    # crosswalks across boulevard
    for stripe in range(-5, 6):
        cube(
            f"Crosswalk_{idx}_{stripe}",
            (
                stripe * 5.5,
                y - 29,
                0.27
            ),
            (3.2, 12, 0.04),
            WHITE_LINE,
            ROADS
        )

# ------------------------------------------------------------
# BUILDING SYSTEM
# ------------------------------------------------------------

building_materials = [
    GLASS_DARK,
    GLASS_BLUE,
    GLASS_GREEN,
    GLASS_BRONZE,
    CONCRETE_DARK,
    CONCRETE_LIGHT,
]

def add_window_bands(ob, width, depth, height, warm=True):

    material = WINDOW_WARM if warm else WINDOW_COOL

    floors = max(3, int(height / 17))

    # Keep performance reasonable:
    # one thin luminous band per several floors.
    spacing = height / (floors + 1)

    for floor in range(2, floors, 2):
        z = floor * spacing

        # front
        cube(
            f"{ob.name}_WinF_{floor}",
            (
                ob.location.x,
                ob.location.y - depth/2 - 0.15,
                z
            ),
            (
                width * 0.78,
                0.20,
                1.2
            ),
            material,
            WINDOWS
        )

        # rear
        cube(
            f"{ob.name}_WinB_{floor}",
            (
                ob.location.x,
                ob.location.y + depth/2 + 0.15,
                z
            ),
            (
                width * 0.78,
                0.20,
                1.2
            ),
            material,
            WINDOWS
        )


def tower(name, x, y, width, depth, height,
          material=None,
          crown="none",
          window_lights=True):

    if material is None:
        material = random.choice(building_materials)

    ob = cube(
        name,
        (x, y, height / 2),
        (width, depth, height),
        material,
        BUILDINGS,
        bevel=min(width, depth) * 0.025
    )

    if window_lights:
        add_window_bands(
            ob,
            width,
            depth,
            height,
            warm=random.random() > 0.35
        )

    roof_z = height

    if crown == "gold":
        cube(
            f"{name}_GoldCrown",
            (x, y, roof_z + 5),
            (width * 0.88, depth * 0.88, 10),
            GOLD,
            BUILDINGS,
            bevel=1
        )

    elif crown == "step":
        cube(
            f"{name}_Crown1",
            (x, y, roof_z + 6),
            (width * 0.76, depth * 0.76, 12),
            material,
            BUILDINGS
        )

        cube(
            f"{name}_Crown2",
            (x, y, roof_z + 15),
            (width * 0.50, depth * 0.50, 8),
            GOLD,
            BUILDINGS
        )

    elif crown == "spire":
        bpy.ops.mesh.primitive_cone_add(
            vertices=4,
            radius1=min(width, depth) * 0.30,
            radius2=0,
            depth=32,
            location=(x, y, roof_z + 16)
        )

        spire = bpy.context.object
        spire.name = f"{name}_Spire"
        spire.data.materials.append(GOLD)
        move_to(spire, BUILDINGS)

    # rooftop mechanical box
    if random.random() > 0.45:
        cube(
            f"{name}_Mechanical",
            (
                x + width * 0.12,
                y - depth * 0.08,
                roof_z + 4
            ),
            (
                width * 0.30,
                depth * 0.35,
                8
            ),
            METAL_BLACK,
            BUILDINGS
        )

    return ob


# ------------------------------------------------------------
# DELIBERATE DOWNTOWN BLOCKS
# ------------------------------------------------------------

# Pyramid reserved at north.
PYRAMID_Y = 780
RESERVE_RADIUS = 310

# Building rows.
x_slots = [
    -480, -375, -275, -175,
     175, 275, 375, 480
]

y_slots = [
    -400,
    -240,
    -70,
    110,
    290,
    470
]

index = 0

for y in y_slots:
    for x in x_slots:

        distance_to_site = math.sqrt(
            x*x + (y-PYRAMID_Y)*(y-PYRAMID_Y)
        )

        if distance_to_site < RESERVE_RADIUS:
            continue

        index += 1

        # Towers closer to core are taller.
        core_factor = max(
            0.0,
            1.0 - abs(x)/550.0
        )

        base_h = 75 + core_factor * 120
        h = base_h + random.uniform(-25, 90)

        width = random.uniform(45, 82)
        depth = random.uniform(44, 76)

        crown = random.choice(
            ["none", "none", "step", "spire", "gold"]
        )

        tower(
            f"Downtown_{index:03d}",
            x + random.uniform(-18, 18),
            y + random.uniform(-14, 14),
            width,
            depth,
            h,
            crown=crown
        )

# ------------------------------------------------------------
# HERO DALLAS-INSPIRED TOWERS
# ------------------------------------------------------------

# Green outlined tower concept.
hero_green = tower(
    "Dallas_Green_Tower",
    -235,
    230,
    76,
    76,
    335,
    GLASS_DARK,
    crown="step"
)

# Green luminous edge strips
for xoff in (-36, 36):
    cube(
        f"GreenTowerEdge_{xoff}",
        (-235 + xoff, 230 - 38.2, 168),
        (2.0, 0.5, 330),
        GREEN,
        WINDOWS
    )

# Tall polished tower
tower(
    "Dallas_Silver_Tower",
    240,
    165,
    72,
    72,
    315,
    GLASS_BLUE,
    crown="gold"
)

# Angular landmark
tower(
    "Dallas_Angular_Base",
    -340,
    45,
    88,
    74,
    205,
    GLASS_GREEN,
    crown="spire"
)

# Twin crown tower
tower(
    "Dallas_Twin_Crown_A",
    350,
    320,
    62,
    62,
    245,
    GLASS_DARK,
    crown="step"
)

tower(
    "Dallas_Twin_Crown_B",
    415,
    320,
    58,
    58,
    225,
    GLASS_DARK,
    crown="step"
)

# ------------------------------------------------------------
# REUNION-TOWER-INSPIRED LANDMARK
# ------------------------------------------------------------

REUNION_X = -410
REUNION_Y = -100

bpy.ops.mesh.primitive_cylinder_add(
    vertices=20,
    radius=12,
    depth=175,
    location=(REUNION_X, REUNION_Y, 87.5)
)

stem = bpy.context.object
stem.name = "Reunion_Inspired_Stem"
stem.data.materials.append(CONCRETE_DARK)
move_to(stem, LANDMARKS)

# sphere shell
bpy.ops.mesh.primitive_ico_sphere_add(
    subdivisions=3,
    radius=36,
    location=(REUNION_X, REUNION_Y, 200)
)

ball = bpy.context.object
ball.name = "Reunion_Inspired_Geodesic_Sphere"
ball.data.materials.append(GLASS_DARK)
move_to(ball, LANDMARKS)

# luminous node points around sphere
for lat in range(-2, 3):
    z = 200 + lat * 11

    radius = math.sqrt(
        max(0, 36*36 - (lat*11)*(lat*11))
    )

    count = 12

    for i in range(count):
        ang = i * math.tau / count

        x = REUNION_X + math.cos(ang) * radius
        y = REUNION_Y + math.sin(ang) * radius

        bpy.ops.mesh.primitive_uv_sphere_add(
            segments=8,
            ring_count=4,
            radius=1.5,
            location=(x, y, z)
        )

        lightnode = bpy.context.object
        lightnode.name = "ReunionLight"
        lightnode.data.materials.append(WINDOW_WARM)
        move_to(lightnode, WINDOWS)

# ------------------------------------------------------------
# PYRAMID DEVELOPMENT SITE
# ------------------------------------------------------------

# Plaza: deliberately huge.
cube(
    "Pyramid_Development_Plaza",
    (0, PYRAMID_Y, 0.5),
    (610, 610, 1),
    PLAZA,
    PYRAMID
)

PYRAMID_BASE = 410
PYRAMID_HEIGHT = 465

half = PYRAMID_BASE / 2

verts = [
    (-half, -half, 0),
    ( half, -half, 0),
    ( half,  half, 0),
    (-half,  half, 0),
    (0, 0, PYRAMID_HEIGHT)
]

faces = [
    (0,1,2,3),
    (0,1,4),
    (1,2,4),
    (2,3,4),
    (3,0,4)
]

mesh = bpy.data.meshes.new("PyramidProxyMesh")
mesh.from_pydata(verts, [], faces)
mesh.update()

proxy = bpy.data.objects.new(
    "PYRAMID_PROXY_REPLACE_LATER",
    mesh
)

PYRAMID.objects.link(proxy)
proxy.location = (0, PYRAMID_Y, 0)
proxy.data.materials.append(PYRAMID_PROXY)

# Anchor used later for hero asset replacement.
anchor = bpy.data.objects.new(
    "PYRAMID_ANCHOR",
    None
)

anchor.empty_display_type = "ARROWS"
anchor.empty_display_size = 30
anchor.location = (0, PYRAMID_Y, 0)
PYRAMID.objects.link(anchor)

# Processional entrance axis.
cube(
    "Pyramid_Processional_Axis",
    (0, 615, 0.8),
    (90, 330, 1.6),
    CONCRETE_LIGHT,
    PYRAMID
)

# Pan-African plaza markers
for x, m in [
    (-125, RED),
    (0, METAL_BLACK),
    (125, GREEN)
]:
    cube(
        f"PyramidBannerMarker_{x}",
        (x, 575, 12),
        (7, 7, 24),
        m,
        PYRAMID
    )

# ------------------------------------------------------------
# TREES
# ------------------------------------------------------------

def tree(name, x, y, scale=1.0):

    bpy.ops.mesh.primitive_cylinder_add(
        vertices=8,
        radius=1.4 * scale,
        depth=8 * scale,
        location=(x, y, 4 * scale)
    )

    trunk = bpy.context.object
    trunk.name = name + "_Trunk"
    trunk.data.materials.append(TREE_TRUNK)
    move_to(trunk, VEGETATION)

    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=2,
        radius=6 * scale,
        location=(x, y, 12 * scale)
    )

    leaves = bpy.context.object
    leaves.name = name + "_Leaves"
    leaves.data.materials.append(TREE_GREEN)
    move_to(leaves, VEGETATION)


for y in range(-520, 610, 65):
    tree(
        f"BoulevardTreeL_{y}",
        -61,
        y,
        random.uniform(0.80, 1.15)
    )

    tree(
        f"BoulevardTreeR_{y}",
        61,
        y,
        random.uniform(0.80, 1.15)
    )

# ------------------------------------------------------------
# STREET LIGHTS
# ------------------------------------------------------------

def streetlight(name, x, y):

    bpy.ops.mesh.primitive_cylinder_add(
        vertices=10,
        radius=0.55,
        depth=11,
        location=(x, y, 5.5)
    )

    pole = bpy.context.object
    pole.name = name + "_Pole"
    pole.data.materials.append(METAL_BLACK)
    move_to(pole, STREET)

    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=12,
        ring_count=6,
        radius=1.1,
        location=(x, y, 11.5)
    )

    lamp = bpy.context.object
    lamp.name = name + "_Lamp"
    lamp.data.materials.append(WINDOW_WARM)
    move_to(lamp, STREET)


for y in range(-500, 610, 85):
    streetlight(f"LightL_{y}", -72, y)
    streetlight(f"LightR_{y}", 72, y)

# ------------------------------------------------------------
# CAMERA
# ------------------------------------------------------------

bpy.ops.object.camera_add(
    location=(0, -810, 145)
)

camera = bpy.context.object
camera.name = "Cinematic_Dallas_Approach_Camera"

target = Vector((0, 470, 155))
direction = target - camera.location

camera.rotation_euler = direction.to_track_quat(
    "-Z",
    "Y"
).to_euler()

camera.data.lens = 48
camera.data.sensor_width = 36

bpy.context.scene.camera = camera
move_to(camera, CAMERAS)

# Second aerial preview
bpy.ops.object.camera_add(
    location=(720, -550, 520)
)

aerial = bpy.context.object
aerial.name = "Aerial_Preview_Camera"

direction = Vector((0, 270, 130)) - aerial.location
aerial.rotation_euler = direction.to_track_quat(
    "-Z",
    "Y"
).to_euler()

aerial.data.lens = 52
move_to(aerial, CAMERAS)

# ------------------------------------------------------------
# SUNSET LIGHTING
# ------------------------------------------------------------

bpy.ops.object.light_add(
    type="SUN",
    location=(400, -450, 700)
)

sun = bpy.context.object
sun.name = "Golden_Hour_Sun"
sun.data.energy = 2.3
sun.data.angle = math.radians(6)

sun.rotation_euler = (
    math.radians(48),
    math.radians(-20),
    math.radians(-32)
)

sun.data.color = (
    1.0,
    0.48,
    0.20
)

move_to(sun, LIGHTING)

# Area fill
bpy.ops.object.light_add(
    type="AREA",
    location=(0, -100, 420)
)

fill = bpy.context.object
fill.name = "Sky_Fill"
fill.data.energy = 1400
fill.data.shape = "DISK"
fill.data.size = 700
fill.data.color = (
    0.18,
    0.30,
    0.55
)

fill.rotation_euler = (
    math.radians(25),
    0,
    0
)

move_to(fill, LIGHTING)

# ------------------------------------------------------------
# WORLD / SKY
# ------------------------------------------------------------

world = bpy.context.scene.world
world.use_nodes = True

nodes = world.node_tree.nodes

background = nodes.get("Background")
background.inputs["Color"].default_value = (
    0.018,
    0.027,
    0.055,
    1
)

background.inputs["Strength"].default_value = 0.22

# ------------------------------------------------------------
# RENDER SETTINGS
# ------------------------------------------------------------

scene = bpy.context.scene

scene.render.engine = "BLENDER_EEVEE_NEXT"

scene.render.resolution_x = 1600
scene.render.resolution_y = 900
scene.render.resolution_percentage = 75

scene.render.image_settings.file_format = "PNG"

scene.render.filepath = (
    r"C:\Users\pftgu\Documents\avlobytest\blender"
    r"\downtown_dallas_city_v2_preview.png"
)

# Color management
scene.view_settings.look = "AgX - Medium High Contrast"

# ------------------------------------------------------------
# SAVE
# ------------------------------------------------------------

os.makedirs(
    os.path.dirname(OUTPUT_BLEND),
    exist_ok=True
)

bpy.ops.wm.save_as_mainfile(
    filepath=OUTPUT_BLEND
)

print("")
print("================================================")
print("UNLEASH DA BEAST - DALLAS CITY V2 COMPLETE")
print("================================================")
print("")
print("Saved:")
print(OUTPUT_BLEND)
print("")
print("Pyramid proxy:")
print(f"  Base:   {PYRAMID_BASE} m")
print(f"  Height: {PYRAMID_HEIGHT} m")
print("")
print("The proxy is NOT final pyramid art.")
print("PYRAMID_ANCHOR is preserved for later replacement.")
print("")
print("Open the .blend in Blender and switch to:")
print("  Material Preview")
print("or")
print("  Rendered View")
print("")
print("Camera:")
print("  Cinematic_Dallas_Approach_Camera")
print("")
print("V1 remains untouched.")
print("================================================")

