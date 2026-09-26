"""Exporte la grenouille cowboy peinte vers le jeu, sans toucher au .blend source.

    blender -b art/characters/frog_cowboy/<fichier>.blend -P art/characters/frog_cowboy/export_frog.py

- texture de couleur -> art/characters/frog_cowboy/frog_cowboy_albedo.png (même si elle est
  seulement emballée dans le .blend) ;
- armature + maillage peint (sans les Icosphere d'affichage d'os, caméra, lumière) ->
  assets/models/characters/frog_cowboy.glb, texture incluse, rig Mixamo inchangé.
Le .blend n'est jamais réenregistré : les changements faits ici restent en mémoire.
"""
import sys
from pathlib import Path

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/blender"))
from lib.uv_mask import pad_edges, unpainted_rim, uv_coverage  # noqa: E402
sys.path.insert(0, str(Path(__file__).resolve().parent / "anim"))
from library import build_library  # noqa: E402
ALBEDO = ROOT / "art/characters/frog_cowboy/frog_cowboy_albedo.png"
GLB = ROOT / "assets/models/characters/frog_cowboy.glb"

skinned = [o for o in bpy.data.objects
           if o.type == "MESH" and o.parent and o.parent.type == "ARMATURE" and o.data.uv_layers]
mesh = max(skinned, key=lambda o: len(o.data.polygons))
arm = mesh.parent

# Texture de base : le nœud image branché sur la Base Color du Principled BSDF.
mat = mesh.active_material
bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
link = bsdf.inputs["Base Color"].links[0]
img = link.from_node.image

# Débordement de 8 px autour des îles UV (pas de liseré du fond sur les coutures).
w, h = img.size
px = np.empty(w * h * img.channels, np.float32)
img.pixels.foreach_get(px)
px = px.reshape(h, w, img.channels)
covered = uv_coverage(mesh.data, w, h)
# Fond blanc de l'image d'origine resté au bord des îles : repeint par le débordement.
covered &= ~unpainted_rim(px, covered, background=(1.0, 1.0, 1.0, 1.0), rim_px=3)
img.pixels.foreach_set(pad_edges(px, covered, iterations=8).ravel())

img.filepath_raw = str(ALBEDO)
img.file_format = "PNG"
img.save()

# Le .blend peut être enregistré en mode peinture : mode objet obligatoire pour l'export.
bpy.context.view_layer.objects.active = mesh
if mesh.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")
# Une armature masquée dans la vue n'est ni sélectionnable ni exportée : on la
# réaffiche (en mémoire seulement), sinon le .glb sort sans squelette.
for ob in (mesh, arm):
    ob.hide_viewport = False
    ob.hide_set(False)
for ob in bpy.data.objects:
    ob.select_set(ob in (mesh, arm))
bpy.context.view_layer.objects.active = arm
assert arm.select_get() and mesh.select_get(), "armature ou maillage non sélectionnable"

# Animations générées par script (anim/) + os WeaponGrip, directement sur ce rig.
clips = build_library(arm)
for ob in bpy.data.objects:
    ob.select_set(ob in (mesh, arm))
bpy.context.view_layer.objects.active = arm

GLB.parent.mkdir(parents=True, exist_ok=True)
# Options passées explicitement : un opérateur Blender réutilise sinon les dernières
# valeurs mémorisées (un export précédent sans skin faisait perdre le rig).
bpy.ops.export_scene.gltf(
    filepath=str(GLB),
    export_format="GLB",
    use_selection=True,
    export_skins=True,
    export_apply=False,
    export_animations=True,
    export_animation_mode="ACTIONS",
    export_force_sampling=True,
)
print(f"FROG_EXPORT_OK mesh={mesh.name} bones={len(arm.data.bones)} clips={len(clips)} "
      f"polys={len(mesh.data.polygons)} texture={img.size[0]}x{img.size[1]} -> {GLB}")
