"""Plan vu de dessus d'une carte à partir de son layout.json (art/maps/<id>/layout.json) : relief,
rue, bâtiments, props, apparitions, allées, échelle. Sert à valider la disposition AVANT la 3D.

    python tools/maps/plan_map.py rio_seco
Sortie : reports/checkpoints/maps/<id>_plan.png
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MID = sys.argv[1] if len(sys.argv) > 1 else "rio_seco"
L = json.load(open(os.path.join(ROOT, "art", "maps", MID, "layout.json"), encoding="utf-8"))
OUT = os.path.join(ROOT, "reports", "checkpoints", "maps")
os.makedirs(OUT, exist_ok=True)

PX = 18                      # pixels par mètre
HALF = L["bounds"]["half"]
M = 90                       # marge (légende)
W = int(2 * HALF * PX) + 2 * M
INK = (27, 16, 48)
PAPER = (255, 244, 224)
F = lambda s: ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", s)
BANG = os.path.join(ROOT, "resources", "fonts", "Bangers-Regular.ttf")
FB = lambda s: ImageFont.truetype(BANG, s)


def P(x, z):
    return (M + (x + HALF) * PX, M + (z + HALF) * PX)


def rect(d, x0, x1, z0, z1, fill, outline=INK, w=3):
    a, b = P(x0, z0), P(x1, z1)
    d.rectangle([a[0], a[1], b[0], b[1]], fill=fill, outline=outline, width=w)


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


img = Image.new("RGB", (W, W + 120), PAPER)
d = ImageDraw.Draw(img)
pal = {k: hexc(v) for k, v in L["palette"].items()}
# falaises (hors jeu)
rect(d, -HALF, HALF, -HALF, HALF, pal["cliff"], w=0)
ph = L["bounds"]["playable_half"]
rect(d, -ph, ph, -ph, ph, pal["sand"])
# rue
st = L["street"]
rect(d, st["x"][0], st["x"][1], st["z"][0], st["z"][1], pal["street"], outline=None, w=0)
# ravin : lit (sombre) + berges (hachures claires)
rv = L["terrain"]["ravine"]
zf, ze = rv["z_full"], rv["z_end"]
rect(d, rv["x_top"][0], rv["x_top"][1], -ze, ze, (214, 170, 118), outline=None, w=0)
rect(d, rv["x_bottom"][0], rv["x_bottom"][1], -zf, zf, pal["riverbed"], outline=None, w=0)
for z in range(int(-zf), int(zf) + 1, 3):   # fissures du lit asséché
    a, b = P(rv["x_bottom"][0] + 1, z), P(rv["x_bottom"][1] - 1, z + 1.2)
    d.line([a, b], fill=INK, width=2)
# mesa : plateau + rampes
ms = L["mesa"]
rect(d, ms["x"][0], ms["x"][1], ms["z_top"][0], ms["z_top"][1], pal["mesa_top"])
for zs, ze2 in ((ms["z_top"][1], ms["ramp_to"]), (-ms["ramp_to"], ms["z_top"][0])):
    rect(d, ms["x"][0], ms["x"][1], zs, ze2, (232, 196, 140), outline=INK, w=2)
    for k in range(1, 5):   # traits de pente
        z = zs + (ze2 - zs) * k / 5
        d.line([P(ms["x"][0] + 1, z), P(ms["x"][1] - 1, z)], fill=(170, 120, 80), width=2)
d.line([P(ms["x"][0], ms["z_top"][0]), P(ms["x"][0], ms["z_top"][1])], fill=INK, width=7)   # falaise franche
# bâtiments
for b in L["buildings"]:
    rect(d, b["x"][0], b["x"][1], b["z"][0], b["z"][1], hexc(b["color"]), w=4)
    cx, cz = (b["x"][0] + b["x"][1]) / 2, (b["z"][0] + b["z"][1]) / 2
    t = b["name"]
    tw = d.textlength(t, font=FB(26))
    d.text((P(cx, cz)[0] - tw / 2, P(cx, cz)[1] - 16), t, fill=PAPER, font=FB(26), stroke_width=3, stroke_fill=INK)
    d.text((P(cx, cz)[0] - 16, P(cx, cz)[1] + 12), f"{b['h']:.1f} m", fill=INK, font=F(15))
# props
for p in L["props"]:
    c = hexc(p["color"])
    if p["kind"] == "water_tower":
        x, z = p["x"], p["z"]
        r = p["tank_r"]
        a, b2 = P(x - r, z - r), P(x + r, z + r)
        d.ellipse([a[0], a[1], b2[0], b2[1]], fill=(160, 110, 70), outline=INK, width=3)
        rect(d, x - p["base"][0] / 2, x + p["base"][0] / 2, z - p["base"][2] / 2, z + p["base"][2] / 2, c, w=3)
        d.text((P(x, z)[0] - 60, P(x, z)[1] + r * PX + 4), "CHÂTEAU D'EAU", fill=INK, font=F(15))
    elif p["kind"] == "cactus":
        x, z = P(p["x"], p["z"])
        d.ellipse([x - 9, z - 9, x + 9, z + 9], fill=c, outline=INK, width=2)
    else:
        sx, sz = p["size"][0], p["size"][2]
        rect(d, p["x"] - sx / 2, p["x"] + sx / 2, p["z"] - sz / 2, p["z"] + sz / 2, c, w=2)
# apparitions
for team, col, lab in (("team0", (46, 139, 255), "APPARITION A"), ("team1", (255, 46, 154), "APPARITION B")):
    s = L["spawns"][team]
    a, b2 = P(s["x"][0], s["z"][0]), P(s["x"][1], s["z"][1])
    d.rectangle([a[0], a[1], b2[0], b2[1]], outline=col, width=5)
    d.text((a[0] + 8, a[1] + 6), lab, fill=col, font=FB(26), stroke_width=2, stroke_fill=INK)
# étiquettes d'allées
for x, lab, sub in ((-25, "RAVIN", "-2 m, berges douces"), (0, "RUE", "allée centre"), (27, "MESA", "+2,5 m, rampes 14°")):
    px, pz = P(x, -HALF + 1.5)
    tw = d.textlength(lab, font=FB(34))
    d.text((px - tw / 2, pz), lab, fill=PAPER, font=FB(34), stroke_width=3, stroke_fill=INK)
    sw = d.textlength(sub, font=F(16))
    d.text((px - sw / 2, pz + 40), sub, fill=PAPER, font=F(16), stroke_width=2, stroke_fill=INK)
d.text(P(16.6, -2), "ruelle sous la mesa", fill=INK, font=F(14))
# échelle + titre
d.line([(M, W - M + 30), (M + 10 * PX, W - M + 30)], fill=INK, width=5)
d.text((M, W - M + 38), "10 m", fill=INK, font=F(18))
d.text((M, 20), f"{L['name'].upper()} — plan (carte 2, 4v4, {2 * ph:.0f}×{2 * ph:.0f} m)", fill=INK, font=FB(40))
d.text((M, W + 30), "Règles : aucune marche (rampes ≤ 16°), passages ≥ 4 m, rien à hauteur de hanche dans les passages, "
       "décor fin au-dessus de 2,4 m.", fill=INK, font=F(17))
d.text((M, W + 58), "Symétrie nord/sud : chaque équipe a les mêmes accès au ravin, à la rue et à la mesa.", fill=INK, font=F(17))
out = os.path.join(OUT, f"{MID}_plan.png")
img.save(out)
print("plan", out, img.size)
