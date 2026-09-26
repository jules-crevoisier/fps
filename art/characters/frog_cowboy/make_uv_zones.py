"""Texture « zones » : peindre au pot, d'un clic par partie, dans l'éditeur d'image 2D.

Blender ne sait pas limiter le pinceau 2D aux faces sélectionnées. À la place, chaque île
UV est remplie d'une couleur unie (sans les triangles internes) et le vide entre les îles
est sombre : l'outil Fill de l'éditeur d'image (remplissage contigu) remplit une seule île.

    blender -b --factory-startup -P art/characters/frog_cowboy/make_uv_zones.py
"""
from pathlib import Path

import bmesh
import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "assets/incoming/tripo/frog_cowboy_rigged_notex.glb"
OUT = ROOT / "art/characters/frog_cowboy/frog_texture.png"
SIZE = 2048
BASE = (0.55, 0.80, 0.35)   # vert grenouille, même départ que frog_albedo.png
EMPTY = (0.10, 0.09, 0.12)  # vide entre les îles (jamais visible sur le modèle)
MARGIN = 0.75               # px : rasterisation conservatrice, aucun trou entre triangles

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SRC))
mesh = max((o for o in bpy.data.objects if o.type == "MESH" and o.data.uv_layers),
           key=lambda o: len(o.data.polygons))
me = mesh.data

# --- îles UV : faces reliées par une arête dont les deux UV coïncident ---
bm = bmesh.new()
bm.from_mesh(me)
uvl = bm.loops.layers.uv.active
parent = list(range(len(bm.faces)))


def find(i):
    while parent[i] != i:
        parent[i] = parent[parent[i]]
        i = parent[i]
    return i


def uv_of(face, vert):
    for loop in face.loops:
        if loop.vert is vert:
            return loop[uvl].uv
    return None


for e in bm.edges:
    if len(e.link_faces) != 2:
        continue
    f1, f2 = e.link_faces
    if all((uv_of(f1, v) - uv_of(f2, v)).length < 1e-5 for v in e.verts):
        parent[find(f1.index)] = find(f2.index)

roots = sorted({find(i) for i in range(len(parent))})
island_of_poly = {r: k + 1 for k, r in enumerate(roots)}
island = [island_of_poly[find(i)] for i in range(len(parent))]
bm.free()

# --- rasterisation (origine en bas à gauche, comme les pixels d'une image Blender) ---
me.calc_loop_triangles()
uv = me.uv_layers.active.data
label = np.zeros((SIZE, SIZE), np.int32)
overlap = 0
for t in me.loop_triangles:
    p = np.array([uv[i].uv[:] for i in t.loops]) * SIZE
    a, b, c = p
    area = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    if abs(area) < 1e-9:
        continue
    s = 1.0 if area > 0 else -1.0
    x0, y0 = np.maximum(np.floor(p.min(0) - 1).astype(int), 0)
    x1, y1 = np.minimum(np.ceil(p.max(0) + 1).astype(int), SIZE - 1)
    if x1 < x0 or y1 < y0:
        continue
    xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    inside = np.ones(xs.shape, bool)
    for e0, e1 in ((a, b), (b, c), (c, a)):
        d = e1 - e0
        n = np.hypot(d[0], d[1])
        if n < 1e-12:
            continue
        dist = s * (d[0] * (ys - e0[1]) - d[1] * (xs - e0[0])) / n
        inside &= dist >= -MARGIN
    k = island[t.polygon_index]
    win = label[y0:y1 + 1, x0:x1 + 1]
    overlap += int(np.count_nonzero(inside & (win != 0) & (win != k)))
    win[inside] = k

# Deux îles qui se touchent fusionneraient au pot : on les sépare d'un pixel de vide.
# Voisins droite, haut et diagonales : le pot de Blender peut se propager en diagonale.
touch = np.zeros_like(label, bool)
for dy, dx in ((0, 1), (1, 0), (1, 1), (1, -1)):
    ya, yb = slice(0, SIZE - dy), slice(dy, SIZE)
    xa, xb = (slice(0, SIZE - dx), slice(dx, SIZE)) if dx >= 0 else (slice(-dx, SIZE), slice(0, SIZE + dx))
    la, lb = label[ya, xa], label[yb, xb]
    touch[ya, xa] |= (la != 0) & (lb != 0) & (la != lb)
label[touch] = 0

img = np.empty((SIZE, SIZE, 4), np.float32)
img[:] = (*EMPTY, 1.0)
img[label != 0] = (*BASE, 1.0)

out = bpy.data.images.new("frog_texture", SIZE, SIZE, alpha=False)
out.pixels.foreach_set(img.ravel())
out.filepath_raw = str(OUT)
out.file_format = "PNG"
out.save()
print(f"UV_ZONES_OK {OUT} islands={len(roots)} touching_px={int(touch.sum())} overlap_px={overlap}")
