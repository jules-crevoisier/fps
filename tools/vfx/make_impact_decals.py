"""Textures d'impacts de balles façon BD (direction « Planche ») : trou encré, éclats, fissures.

    python tools/vfx/make_impact_decals.py
Sorties (RGBA 256 px, fond transparent) dans assets/vfx/impact/ :
  - bullet_hole_concrete_{1,2,3}.png : cratère papier écaillé cerclé d'encre + trou noir + fissures ;
  - bullet_hole_metal_{1,2,3}.png : trou poinçonné, collerette de métal arraché en étoile, reflet vif ;
  - impact_puff.png : petit nuage de poussière BD (à animer en sprite : grossit puis s'efface) ;
  - impact_spark.png : étincelle en étoile (impacts sur métal).
Les couleurs viennent des jetons UI (encre #1B1030, papier #FFF4E0, jaune #FFCE1F).
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "vfx", "impact")
S = 256          # taille finale
SS = 4           # suréchantillonnage (anticrénelage)
INK = (27, 16, 48, 255)
PAPER = (255, 244, 224, 255)
CHIP = (232, 217, 189, 255)
YELLOW = (255, 206, 31, 255)
os.makedirs(OUT, exist_ok=True)


def blob(rng, cx, cy, r, n=22, jitter=0.25):
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n + rng.uniform(-0.08, 0.08)
        rr = r * (1 + rng.uniform(-jitter, jitter))
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    return pts


def star(rng, cx, cy, r_out, r_in, n, jitter=0.2, rot=0.0):
    pts = []
    for i in range(n * 2):
        a = rot + math.pi * i / n
        r = (r_out if i % 2 == 0 else r_in) * (1 + rng.uniform(-jitter, jitter))
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def finish(img):
    return img.resize((S, S), Image.LANCZOS)


def concrete(seed):
    rng = np.random.default_rng(seed)
    W = S * SS
    c = W / 2
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    stroke = 3.2 * SS
    # fissures radiales (encre), sous le cratère
    for _ in range(int(rng.integers(5, 8))):
        a = rng.uniform(0, 2 * math.pi)
        r0, r1 = W * 0.18, W * rng.uniform(0.36, 0.48)
        mid = (r0 + r1) / 2
        a2 = a + rng.uniform(-0.25, 0.25)
        d.line([(c + math.cos(a) * r0, c + math.sin(a) * r0), (c + math.cos(a2) * mid, c + math.sin(a2) * mid),
                (c + math.cos(a2 + rng.uniform(-0.2, 0.2)) * r1, c + math.sin(a2) * r1)], fill=INK, width=int(2.2 * SS))
    # cratère écaillé : papier clair cerclé d'encre
    crater = blob(rng, c, c, W * 0.30, 18, 0.28)
    d.polygon(crater, fill=INK)
    inner = [(c + (x - c) * 0.9, c + (y - c) * 0.9) for x, y in crater]
    d.polygon(inner, fill=CHIP)
    # ombre intérieure (demi-lune) pour le relief
    d.pieslice([c - W * 0.2, c - W * 0.2, c + W * 0.2, c + W * 0.2], 200, 380, fill=(190, 172, 146, 255))
    # trou central noir
    d.polygon(blob(rng, c, c, W * 0.12, 14, 0.3), fill=INK)
    # éclats de débris autour
    for _ in range(int(rng.integers(6, 11))):
        a = rng.uniform(0, 2 * math.pi)
        rr = W * rng.uniform(0.33, 0.45)
        x, y = c + math.cos(a) * rr, c + math.sin(a) * rr
        s = W * rng.uniform(0.012, 0.028)
        d.polygon(blob(rng, x, y, s, 6, 0.4), fill=INK)
    return finish(img)


def metal(seed):
    rng = np.random.default_rng(seed)
    W = S * SS
    c = W / 2
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rot = rng.uniform(0, math.pi)
    # collerette arrachée en étoile : encre puis gris-bleu métal
    petals = star(rng, c, c, W * 0.30, W * 0.16, int(rng.integers(6, 9)), 0.25, rot)
    d.polygon(petals, fill=INK)
    inner = [(c + (x - c) * 0.84, c + (y - c) * 0.84) for x, y in petals]
    d.polygon(inner, fill=(148, 160, 182, 255))
    # reflet vif (métal chauffé) puis trou
    d.ellipse([c - W * 0.13, c - W * 0.13, c + W * 0.13, c + W * 0.13], fill=PAPER)
    d.ellipse([c - W * 0.1, c - W * 0.1, c + W * 0.1, c + W * 0.1], fill=INK)
    # points de trame (esprit comics) autour
    for _ in range(18):
        a = rng.uniform(0, 2 * math.pi)
        rr = W * rng.uniform(0.33, 0.46)
        x, y = c + math.cos(a) * rr, c + math.sin(a) * rr
        s = W * rng.uniform(0.008, 0.016)
        d.ellipse([x - s, y - s, x + s, y + s], fill=INK)
    return finish(img)


def puff():
    rng = np.random.default_rng(7)
    W = S * SS
    c = W / 2
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    lobes = [(c + math.cos(a) * W * 0.18, c + math.sin(a) * W * 0.16, W * rng.uniform(0.14, 0.19))
             for a in np.linspace(0, 2 * math.pi, 7, endpoint=False)]
    lobes.append((c, c, W * 0.22))
    stroke = 4 * SS
    for x, y, r in lobes:                      # contour encre
        d.ellipse([x - r - stroke, y - r - stroke, x + r + stroke, y + r + stroke], fill=INK)
    for x, y, r in lobes:                      # remplissage papier
        d.ellipse([x - r, y - r, x + r, y + r], fill=CHIP)
    for x, y, r in lobes:                      # reflet
        d.ellipse([x - r * 0.55, y - r * 0.75, x + r * 0.25, y - r * 0.05], fill=PAPER)
    return finish(img)


def spark():
    rng = np.random.default_rng(11)
    W = S * SS
    c = W / 2
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pts = star(rng, c, c, W * 0.46, W * 0.12, 8, 0.25, 0.3)
    d.polygon(pts, fill=INK)
    d.polygon([(c + (x - c) * 0.8, c + (y - c) * 0.8) for x, y in pts], fill=YELLOW)
    d.polygon([(c + (x - c) * 0.45, c + (y - c) * 0.45) for x, y in pts], fill=PAPER)
    return finish(img)


for k in range(3):
    concrete(100 + k).save(os.path.join(OUT, f"bullet_hole_concrete_{k + 1}.png"))
    metal(200 + k).save(os.path.join(OUT, f"bullet_hole_metal_{k + 1}.png"))
puff().save(os.path.join(OUT, "impact_puff.png"))
spark().save(os.path.join(OUT, "impact_spark.png"))
print("ok", sorted(os.listdir(OUT)))
