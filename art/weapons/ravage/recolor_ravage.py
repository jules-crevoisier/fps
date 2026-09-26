"""Retexture du Ravage : nouvelle palette (acier bruni, noyer, laiton), détails conservés.

    blender -b --factory-startup -P art/weapons/ravage/recolor_ravage.py

Chaque pixel est rattaché (en douceur) aux couleurs dominantes de la texture d'origine, puis
repeint avec la couleur cible correspondante en gardant sa luminosité relative (usure, reflets
peints). Corrige aussi les repères Muzzle/Foregrip, qui étaient ~19 cm sous le canon.
"""
from pathlib import Path

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
GLB = ROOT / "assets/models/weapons/ravage.glb"

# Couleur d'origine (mesurée, k-moyennes) -> couleur cible.
PALETTE = [
    ("#4d5966", "#3c3f46"),  # métal gris-bleu -> acier bruni
    ("#47525f", "#363940"),
    ("#37424f", "#2a2c31"),
    ("#eae2cd", "#9a6538"),  # crosse crème -> noyer
    ("#af2a23", "#7a4524"),  # garde-main rouge -> noyer foncé
    ("#7b3b3c", "#4e2c18"),
    ("#b6b4ab", "#c9a24b"),  # plaque -> laiton
]
SIGMA = 0.004  # douceur du rattachement (distance RGB au carré)


def _rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(GLB))
img = next(i for i in bpy.data.images if i.size[0] > 0)
w, h = img.size
px = np.empty(w * h * 4, np.float32)
img.pixels.foreach_get(px)
px = px.reshape(-1, 4)
rgb = px[:, :3]
# `Image.pixels` d'une image 8 bits renvoie les valeurs stockées (sRGB, non linéarisées) :
# palette comparée et repeinte en sRGB.
src = np.stack([_rgb(a) for a, _ in PALETTE])
dst = np.stack([_rgb(b) for _, b in PALETTE])
out = np.zeros_like(rgb)
wsum = np.zeros((rgb.shape[0], 1), np.float32)
lum = rgb @ np.array([0.2126, 0.7152, 0.0722], np.float32)
d_all = np.stack([((rgb - s) ** 2).sum(1) for s in src], 1)
d_min = d_all.min(1, keepdims=True)
for i, (s, t) in enumerate(zip(src, dst)):
    wgt = np.exp(-(d_all[:, i:i + 1] - d_min) / SIGMA)
    ratio = np.clip(lum / max(float(s @ np.array([0.2126, 0.7152, 0.0722])), 1e-4), 0.55, 1.6)[:, None]
    out += wgt * np.clip(t * ratio, 0.0, 1.0)
    wsum += wgt
px[:, :3] = out / wsum
img.pixels.foreach_set(px.ravel())
img.pack()

# Repères : bouche du canon et garde-main (mesurés sur le maillage).
bpy.data.objects["Muzzle"].location = (0.0, 0.63, 0.255)
bpy.data.objects["Foregrip"].location = (0.0, 0.30, 0.215)

for ob in bpy.data.objects:
    ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(GLB), export_format="GLB", use_selection=True,
                          export_animations=False, export_image_format="AUTO")
print("RAVAGE_RECOLOR_OK", GLB)
