import bpy
import os
import math
from mathutils import Vector

OUTPUT = r"C:\Users\pftgu\Documents\avlobytest\blender\downtown_dallas_city_v6b.blend"

# ============================================================
# DALLAS CITY V6B
# OPTIMIZED WINDOW / FACADE PASS
#
# GOAL:
# Make buildings read as multi-story structures
# WITHOUT creating thousands of individual window objects.
#
# Strategy:
# - One facade mesh per face
# - Grid geometry combined into one object
# - Reuse a very small material set
# - Only major/visible buildings get detailed treatment
# ============================================================


# ------------------------------------------------------------
# COLLECTION
# ------------------------------------------------------------

def get_collection(name):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
    return c


WINDOWS = get_collection("V6B_OPTIMIZED_WINDOWS")


# ------------------------------------------------------------
# MATERIALS
# ------------------------------------------------------------

def make_material(name, base_color, metallic=0.0, roughness=0.4, emission=None, strength=0.0):
    m = bpy.data.materials.get(name)

    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True

    bsdf = m.node_tree.nodes.get("Principled BSDF")

    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*base_color, 1.0)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness

        if emission:
            bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
            bsdf.inputs["Emission Strength"].default_value = strength

    return m


MAT_DARK = make_material(
    "V6B_Window_Dark",
    (0.008, 0.02, 0.035),
    metallic=0.35,
    roughness=0.20
)

MAT_BLUE = make_material(
    "V6B_Window_Blue",
    (0.01, 0.055, 0.10),
    metallic=0.40,
    roughness=0.18
)

MAT_WARM = make_material(
    "V6B_Window_Warm",
    (0.12, 0.045, 0.008),
    metallic=0.10,
    roughness=0.25,
    emission=(1.0, 0.22, 0.03),
    strength=1.6
)


# ------------------------------------------------------------
# MOVE OBJECT TO COLLECTION
# ------------------------------------------------------------

def move_to(obj, collection):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    collection.objects.link(obj)


# ------------------------------------------------------------
# BUILD ONE COMBINED WINDOW GRID MESH
# ------------------------------------------------------------

def create_window_grid(
    name,
    center,
    face_width,
    face_height,
    horizontal_axis,
    vertical_axis,
    outward_offset,
    columns,
    rows,
    building_center,
    material_mode=0
):
    """
    Creates ALL windows for one building face as ONE mesh object.
    """

    verts = []
    faces = []
    mats = []

    # spacing
    margin_x = face_width * 0.08
    margin_z = face_height * 0.08

    usable_w = face_width - margin_x * 2
    usable_h = face_height - margin_z * 2

    cell_w = usable_w / max(columns, 1)
    cell_h = usable_h / max(rows, 1)

    win_w = cell_w * 0.60
    win_h = cell_h * 0.48

    # Build quads
    for r in range(rows):

        z_offset = -usable_h / 2 + cell_h * (r + 0.5)

        for c in range(columns):

            # Skip some windows intentionally
            # to avoid perfectly uniform "spreadsheet building"
            if (r + c + material_mode) % 9 == 0:
                continue

            x_offset = -usable_w / 2 + cell_w * (c + 0.5)

            center_point = (
                Vector(center)
                + Vector(horizontal_axis) * x_offset
                + Vector(vertical_axis) * z_offset
                + Vector(outward_offset)
            )

            h = Vector(horizontal_axis) * (win_w / 2)
            v = Vector(vertical_axis) * (win_h / 2)

            base = len(verts)

            verts.extend([
                center_point - h - v,
                center_point + h - v,
                center_point + h + v,
                center_point - h + v
            ])

            faces.append((base, base + 1, base + 2, base + 3))

            # Alternate material slots
            if (r * 3 + c + material_mode) % 11 == 0:
                mats.append(2)
            elif material_mode % 2 == 0:
                mats.append(0)
            else:
                mats.append(1)

    if not verts:
        return None

    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)

    WINDOWS.objects.link(obj)

    obj.data.materials.append(MAT_DARK)
    obj.data.materials.append(MAT_BLUE)
    obj.data.materials.append(MAT_WARM)

    for i, poly in enumerate(obj.data.polygons):
        if i < len(mats):
            poly.material_index = mats[i]

    return obj


# ------------------------------------------------------------
# FIND MAJOR BUILDINGS
# ------------------------------------------------------------

candidates = []

for obj in bpy.data.objects:

    if obj.type != "MESH":
        continue

    name = obj.name.lower()

    # Skip obvious props
    skip_words = [
        "window",
        "car",
        "wheel",
        "tree",
        "road",
        "lane",
        "crosswalk",
        "light",
        "sign",
        "bench",
        "hydrant",
        "sidewalk",
        "awning",
        "door",
        "store",
        "roof",
        "sphere",
        "reunion",
        "pyramid",
        "human"
    ]

    if any(word in name for word in skip_words):
        continue

    # Major building test
    if (
        obj.dimensions.z >= 22
        and obj.dimensions.x >= 8
        and obj.dimensions.y >= 8
    ):
        candidates.append(obj)


# Sort tallest first
candidates.sort(
    key=lambda o: o.dimensions.z,
    reverse=True
)

# Performance limit:
# only enhance the 40 most visually important buildings.
candidates = candidates[:40]

print("V6B major buildings selected:", len(candidates))


# ------------------------------------------------------------
# CREATE 1-2 FACADE OBJECTS PER BUILDING
# ------------------------------------------------------------

facade_count = 0
window_estimate = 0

for idx, building in enumerate(candidates):

    x, y, z = building.location

    width = building.dimensions.x
    depth = building.dimensions.y
    height = building.dimensions.z

    # Assume building origin near its center.
    center_z = z

    # Moderate grid density
    rows = max(5, min(24, int(height / 4.0)))
    cols_front = max(3, min(10, int(width / 5.0)))
    cols_side = max(3, min(10, int(depth / 5.0)))

    # FRONT FACE
    front_center = (
        x,
        y - depth / 2,
        center_z
    )

    front = create_window_grid(
        name=f"V6B_FacadeFront_{idx:02d}",
        center=front_center,
        face_width=width,
        face_height=height,
        horizontal_axis=(1, 0, 0),
        vertical_axis=(0, 0, 1),
        outward_offset=(0, -0.08, 0),
        columns=cols_front,
        rows=rows,
        building_center=(x, y, z),
        material_mode=idx
    )

    if front:
        facade_count += 1
        window_estimate += rows * cols_front

    # SIDE FACE
    # Only add side windows to every other building.
    # This halves object count while keeping depth.
    if idx % 2 == 0:

        side_center = (
            x + width / 2,
            y,
            center_z
        )

        side = create_window_grid(
            name=f"V6B_FacadeSide_{idx:02d}",
            center=side_center,
            face_width=depth,
            face_height=height,
            horizontal_axis=(0, 1, 0),
            vertical_axis=(0, 0, 1),
            outward_offset=(0.08, 0, 0),
            columns=cols_side,
            rows=rows,
            building_center=(x, y, z),
            material_mode=idx + 1
        )

        if side:
            facade_count += 1
            window_estimate += rows * cols_side


print("V6B facade objects created:", facade_count)
print("Approx visible window count:", window_estimate)


# ------------------------------------------------------------
# SAVE
# ------------------------------------------------------------

scene = bpy.context.scene
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
print("DALLAS CITY V6B COMPLETE")
print("================================================")
print("")
print("V5 remains untouched.")
print("")
print("MAJOR BUILDINGS ENHANCED:")
print(len(candidates))
print("")
print("FACADE OBJECTS CREATED:")
print(facade_count)
print("")
print("IMPORTANT:")
print("Windows are combined into facade meshes.")
print("They are NOT thousands of separate Blender objects.")
print("")
print("Saved:")
print(OUTPUT)
print("================================================")
