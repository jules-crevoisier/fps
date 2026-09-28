"""Icônes d'interface tirées des VRAIS modèles (rendus détourés de tools/ui/render_ui_assets.gd) :
silhouette pleine couleur papier + contour encre épais, style BD (fil des éliminations, HUD,
inventaire). Écrit aussi la minimap stylisée de Shipment et le portrait de Verrou.

    python tools/ui/make_icons.py
Entrées : reports/ui/assets/*.png, reports/checkpoints/look/ui_map_top.png
Sorties : reports/ui/icons/<nom>_sil.png, minimap_shipment.png, portrait_verrou.png
"""
import os

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS = os.path.join(ROOT, "reports", "ui", "assets")
OUT = os.path.join(ROOT, "reports", "ui", "icons")
INK = (27, 16, 48)       # toon_style.json outline.color #1B1030
PAPER = (255, 244, 224)  # palette.paper #FFF4E0
os.makedirs(OUT, exist_ok=True)


def silhouette(name, height=160, stroke=7):
    src = Image.open(os.path.join(ASSETS, f"{name}.png"))
    a = src.getchannel("A")
    a = a.point(lambda v: 255 if v > 90 else 0)
    w = round(src.width * height / src.height)
    a = a.resize((w, height), Image.LANCZOS).point(lambda v: 255 if v > 127 else 0)
    pad = stroke + 2
    canvas = Image.new("L", (w + pad * 2, height + pad * 2), 0)
    canvas.paste(a, (pad, pad))
    outer = canvas.filter(ImageFilter.MaxFilter(stroke * 2 + 1)).filter(ImageFilter.GaussianBlur(0.6))
    fill = canvas.filter(ImageFilter.GaussianBlur(0.6))
    img = Image.new("RGBA", canvas.size, INK + (0,))
    img.putalpha(outer)
    paper = Image.new("RGBA", canvas.size, PAPER + (255,))
    paper.putalpha(fill)
    img.alpha_composite(paper)
    img.save(os.path.join(OUT, f"{name}_sil.png"))
    print("icône", name, img.size)


def sticker(name, height=160, stroke=6):
    """Rendu couleur réel, cerclé d'encre (autocollant BD) : grenades lisibles par leur couleur."""
    src = Image.open(os.path.join(ASSETS, f"{name}.png"))
    w = round(src.width * height / src.height)
    src = src.resize((w, height), Image.LANCZOS)
    pad = stroke + 2
    canvas = Image.new("RGBA", (w + pad * 2, height + pad * 2), (0, 0, 0, 0))
    canvas.paste(src, (pad, pad))
    a = canvas.getchannel("A").point(lambda v: 255 if v > 90 else 0)
    outer = a.filter(ImageFilter.MaxFilter(stroke * 2 + 1)).filter(ImageFilter.GaussianBlur(0.6))
    img = Image.new("RGBA", canvas.size, INK + (0,))
    img.putalpha(outer)
    img.alpha_composite(canvas)
    img.save(os.path.join(OUT, f"{name}_sticker.png"))
    print("autocollant", name, img.size)


for n, h in (("revolver", 120), ("ravage", 110), ("frag", 120), ("flash", 120), ("smoke", 120),
             # Tâche "quatre armes v2" (2026-09-28) : les 4 nouvelles armes peintes.
             ("rafale", 110), ("fracas", 110), ("verdict", 110), ("aiguille", 110)):
    silhouette(n, h)
    sticker(n, h * 2)

# Minimap : sol/murs (peu saturés) -> encre violette, conteneurs gardent leur couleur, saturés.
top = Image.open(os.path.join(ROOT, "reports", "checkpoints", "look", "ui_map_top.png")).convert("RGB")
side = min(top.size)
top = top.crop(((top.width - side) // 2, 0, (top.width - side) // 2 + side, side))
m = 0.035
top = top.crop((int(side * m), int(side * m), int(side * (1 - m)), int(side * (1 - m)))).resize((512, 512), Image.LANCZOS)
rgb = np.asarray(top, dtype=np.float32) / 255.0
mx, mn = rgb.max(axis=2), rgb.min(axis=2)
sat = (mx - mn) / np.maximum(mx, 1e-3)
floor = np.array([0x2B, 0x22, 0x44], np.float32) / 255.0
wall = np.array([0x4A, 0x3F, 0x6E], np.float32) / 255.0
boost = np.clip((rgb - rgb.mean(axis=2, keepdims=True)) * 1.6 + rgb.mean(axis=2, keepdims=True) * 1.15, 0, 1)
out = np.where(sat[..., None] > 0.16, boost, np.where(mx[..., None] > 0.5, wall, floor))
Image.fromarray((out * 255).astype(np.uint8)).save(os.path.join(OUT, "minimap_shipment.png"))
print("minimap ok")

# Portrait de Verrou (tête, depuis le rendu en pied au repos)
frog = Image.open(os.path.join(ASSETS, "frog.png"))
ys, xs = np.nonzero(np.asarray(frog.getchannel("A")) > 20)
top_y = ys.min()
head = frog.crop((int(frog.width * 0.22), top_y, int(frog.width * 0.82), top_y + int(frog.height * 0.34)))
head.save(os.path.join(OUT, "portrait_verrou.png"))
print("portrait", head.size)
