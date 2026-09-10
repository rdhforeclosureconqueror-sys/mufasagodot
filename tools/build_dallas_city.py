import bpy
import random
from mathutils import Vector

# ============================================================
# DALLAS-INSPIRED CITY GENERATOR V1
# ============================================================

OUTPUT_BLEND = r"C:\Users\pftgu\Documents\avlobytest\blender\downtown_dallas_city_v1.blend"

random.seed(42)

# -----------------------------
# Clean scene
# -----------------------------

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

# -----------------------------
# Helpers
# -----------------------------

def ensure_collection(name):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    return col

def move_to_collection(obj, collection):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    collection.objects.link(obj)

def make_mat(name, color, metallic=0.0, roughness=0.45):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat

    mat = bpy.data.materials.new(name)
    mat.use_nodes = True

    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness

    return mat

def cube(name, loc, scale, mat, collection):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    move_to_collection(obj, collection)
    return obj

# -----------------------------
# Collections
# -----------------------------

CITY = ensure_collection("DALLAS_CITY")
ROADS = ensure_collection("Roads")
SKYLINE = ensure_collection("Skyline")
MIDRISE = ensure_collection("Midrise")
LANDMARKS = ensure_collection("Landmarks")
PYRAMID_SITE = ensure_collection("PYRAMID_SITE")
LIGHTING = ensure_collection("Lighting")

# -----------------------------
# Materials
# -----------------------------

ROAD_MAT = make_mat("Road", (0.025, 0.025, 0.03), 0.0, 0.7)
SIDEWALK_MAT = make_mat("Sidewalk", (0.24, 0.24, 0.25), 0.0, 0.7)
GLASS_BLUE = make_mat("Glass_Blue", (0.035, 0.12, 0.20), 0.45, 0.2)
GLASS_DARK = make_mat("Glass_Dark", (0.015, 0.035, 0.06), 0.5, 0.18)
CONCRETE = make_mat("Concrete", (0.16, 0.17, 0.18), 0.0, 0.55)
WHITE = make_mat("White", (0.5, 0.5, 0.52), 0.0, 0.45)
GOLD = make_mat("Gold", (0.75, 0.38, 0.05), 0.85, 0.18)
PYRAMID_PROXY_MAT = make_mat("Pyramid_Proxy_Gold", (0.35, 0.18, 0.025), 0.65, 0.25)

# -----------------------------
# Ground / boulevard
# -----------------------------

cube(
    "CityGround",
    (0, 0, -1),
    (900, 900, 1),
    CONCRETE,
    CITY
)

cube(
    "MainBoulevard",
    (0, -220, 0.05),
    (45, 620, 0.1),
    ROAD_MAT,
    ROADS
)

cube(
    "BoulevardSidewalk_L",
    (-55, -220, 0.15),
    (10, 620, 0.15),
    SIDEWALK_MAT,
    ROADS
)

cube(
    "BoulevardSidewalk_R",
    (55, -220, 0.15),
    (10, 620, 0.15),
    SIDEWALK_MAT,
    ROADS
)

# -----------------------------
# Generic skyline
# -----------------------------

def make_tower(name, x, y, w, d, h, mat):
    return cube(
        name,
        (x, y, h / 2),
        (w / 2, d / 2, h / 2),
        mat,
        SKYLINE
    )

# Left skyline
for i in range(18):
    x = random.uniform(-430, -110)
    y = random.uniform(-180, 500)
    w = random.uniform(35, 80)
    d = random.uniform(35, 80)
    h = random.uniform(90, 230)

    mat = GLASS_BLUE if i % 2 == 0 else GLASS_DARK
    make_tower(f"Tower_L_{i:02d}", x, y, w, d, h, mat)

# Right skyline
for i in range(18):
    x = random.uniform(110, 430)
    y = random.uniform(-180, 500)
    w = random.uniform(35, 80)
    d = random.uniform(35, 80)
    h = random.uniform(90, 230)

    mat = GLASS_BLUE if i % 2 == 0 else GLASS_DARK
    make_tower(f"Tower_R_{i:02d}", x, y, w, d, h, mat)

# -----------------------------
# Dallas-inspired hero towers
# -----------------------------

make_tower("Dallas_Glass_Hero_01", -180, 160, 80, 80, 290, GLASS_BLUE)
make_tower("Dallas_Glass_Hero_02", 175, 230, 75, 75, 305, GLASS_DARK)
make_tower("Dallas_Stepped_Tower", -270, 260, 95, 95, 250, WHITE)

# -----------------------------
# Reunion-Tower-inspired landmark
# -----------------------------

bpy.ops.mesh.primitive_cylinder_add(
    vertices=24,
    radius=10,
    depth=140,
    location=(300, 100, 70)
)

reunion_stem = bpy.context.object
reunion_stem.name = "Reunion_Inspired_Stem"
reunion_stem.data.materials.append(CONCRETE)
move_to_collection(reunion_stem, LANDMARKS)

bpy.ops.mesh.primitive_uv_sphere_add(
    segments=32,
    ring_count=16,
    radius=30,
    location=(300, 100, 155)
)

reunion_ball = bpy.context.object
reunion_ball.name = "Reunion_Inspired_Sphere"
reunion_ball.data.materials.append(GOLD)
move_to_collection(reunion_ball, LANDMARKS)

# -----------------------------
# PYRAMID SITE
# -----------------------------

PYRAMID_BASE = 360
PYRAMID_HEIGHT = 430

half = PYRAMID_BASE / 2

verts = [
    (-half, -half, 0),
    (half, -half, 0),
    (half, half, 0),
    (-half, half, 0),
    (0, 0, PYRAMID_HEIGHT),
]

faces = [
    (0, 1, 2, 3),
    (0, 1, 4),
    (1, 2, 4),
    (2, 3, 4),
    (3, 0, 4),
]

mesh = bpy.data.meshes.new("Pyramid_Proxy_Mesh")
mesh.from_pydata(verts, [], faces)
mesh.update()

pyramid = bpy.data.objects.new("Pyramid_Proxy", mesh)
PYRAMID_SITE.objects.link(pyramid)
pyramid.data.materials.append(PYRAMID_PROXY_MAT)

pyramid.location = (0, 500, 0)

# Pyramid anchor
anchor = bpy.data.objects.new("Pyramid_Anchor", None)
anchor.empty_display_type = "ARROWS"
anchor.empty_display_size = 25
anchor.location = (0, 500, 0)
PYRAMID_SITE.objects.link(anchor)

# Entrance axis marker
axis = bpy.data.objects.new("Pyramid_Entrance_Axis", None)
axis.empty_display_type = "SINGLE_ARROW"
axis.empty_display_size = 30
axis.location = (0, 330, 0)
PYRAMID_SITE.objects.link(axis)

# -----------------------------
# Preview camera
# -----------------------------

bpy.ops.object.camera_add(location=(0, -760, 185))
camera = bpy.context.object
camera.name = "City_Preview_Camera"

target = Vector((0, 250, 130))
direction = target - camera.location

camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
camera.data.lens = 42

bpy.context.scene.camera = camera

# -----------------------------
# Sun
# -----------------------------

bpy.ops.object.light_add(
    type="SUN",
    location=(200, -300, 600)
)

sun = bpy.context.object
sun.name = "Golden_Hour_Sun"
sun.data.energy = 3.0
sun.rotation_euler = (0.55, -0.35, -0.45)

move_to_collection(sun, LIGHTING)

# -----------------------------
# World color
# -----------------------------

bpy.context.scene.world.color = (0.035, 0.05, 0.09)

# -----------------------------
# Save .blend
# -----------------------------

import os
os.makedirs(os.path.dirname(OUTPUT_BLEND), exist_ok=True)

bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND)

print("")
print("======================================")
print("DALLAS CITY V1 CREATED")
print("======================================")
print(f"Saved: {OUTPUT_BLEND}")
print(f"Pyramid site: base {PYRAMID_BASE}m, height {PYRAMID_HEIGHT}m")
print("Open the .blend normally to preview.")
