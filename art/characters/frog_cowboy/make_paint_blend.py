"""Prépare frog_cowboy_paint.blend : modèle importé, texture frog_albedo prête à peindre.

    blender -b --factory-startup -P art/characters/frog_cowboy/make_paint_blend.py
"""
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "assets/incoming/tripo/frog_cowboy_rigged_notex.glb"
OUT_DIR = ROOT / "art/characters/frog_cowboy"
IMG_PATH = OUT_DIR / "frog_albedo.png"
BLEND = OUT_DIR / "frog_cowboy_paint.blend"
SIZE = 2048

# scène vide
for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob, do_unlink=True)

bpy.ops.import_scene.gltf(filepath=str(SRC))

meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.data.uv_layers]
mesh = max(meshes, key=lambda o: len(o.data.polygons))
mesh.name = "FrogCowboy"

# Objets d'affichage des os (Icosphere, collection glTF_not_exported) : cachés
for ob in bpy.data.objects:
    if ob.type == "MESH" and ob is not mesh:
        ob.hide_set(True)
        ob.hide_render = True

# Image de peinture, enregistrée sur disque (sinon perdue à la fermeture)
img = bpy.data.images.new("frog_albedo", SIZE, SIZE, alpha=False)
img.generated_color = (0.55, 0.8, 0.35, 1.0)  # vert grenouille de départ
img.filepath_raw = str(IMG_PATH)
img.file_format = "PNG"
img.save()

mat = mesh.active_material
if mat is None:
    mat = bpy.data.materials.new("FrogCowboy")
    mesh.data.materials.append(mat)
mat.use_nodes = True
nt = mat.node_tree
bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = img
tex.location = (bsdf.location.x - 350, bsdf.location.y)
nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
nt.nodes.active = tex  # emplacement de peinture actif

# Mode de peinture : l'image du matériau
ts = bpy.context.scene.tool_settings
ts.image_paint.mode = "MATERIAL"

# Toutes les vues 3D en Material Preview (texture visible sur le modèle)
for screen in bpy.data.screens:
    for area in screen.areas:
        for space in area.spaces:
            if space.type == "VIEW_3D":
                space.shading.type = "MATERIAL"
            if space.type == "IMAGE_EDITOR":
                space.image = img

bpy.context.view_layer.objects.active = mesh
for ob in bpy.data.objects:
    ob.select_set(ob is mesh)

bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print("PAINT_BLEND_OK", BLEND, "image", IMG_PATH)
