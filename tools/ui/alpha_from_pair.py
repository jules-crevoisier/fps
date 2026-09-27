"""Détourage exact à partir de deux rendus identiques sur fond noir et sur fond blanc
(tools/ui/render_ui_assets.gd) : alpha = 1 - (blanc - noir), couleur = noir / alpha. Recadre au
contenu (marge en px) et écrit <sujet>.png (RGBA) à côté.

    python tools/ui/alpha_from_pair.py [dossier] [--margin 12]
"""
import glob
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
args = [a for a in sys.argv[1:] if not a.startswith("--")]
DIR = args[0] if args else os.path.join(ROOT, "reports", "ui", "assets")
MARGIN = int(sys.argv[sys.argv.index("--margin") + 1]) if "--margin" in sys.argv else 12

for black_path in sorted(glob.glob(os.path.join(DIR, "*_black.png"))):
    name = os.path.basename(black_path)[: -len("_black.png")]
    white_path = os.path.join(DIR, f"{name}_white.png")
    if not os.path.exists(white_path):
        continue
    b = np.asarray(Image.open(black_path).convert("RGB"), dtype=np.float32) / 255.0
    w = np.asarray(Image.open(white_path).convert("RGB"), dtype=np.float32) / 255.0
    alpha = np.clip(1.0 - (w - b).mean(axis=2), 0.0, 1.0)
    color = np.where(alpha[..., None] > 1e-3, b / np.maximum(alpha[..., None], 1e-3), 0.0)
    rgba = np.dstack([np.clip(color, 0.0, 1.0), alpha])
    img = Image.fromarray((rgba * 255.0 + 0.5).astype(np.uint8), "RGBA")
    ys, xs = np.nonzero(alpha > 0.02)
    if len(xs):
        img = img.crop((max(xs.min() - MARGIN, 0), max(ys.min() - MARGIN, 0),
                        min(xs.max() + MARGIN + 1, img.width), min(ys.max() + MARGIN + 1, img.height)))
    out = os.path.join(DIR, f"{name}.png")
    img.save(out)
    print("RGBA", out, img.size)
