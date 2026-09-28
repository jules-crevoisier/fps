"""Plan (vue de dessus) + COUPE de Canyon Express depuis art/maps/canyon_express/layout.json.

    python tools/maps/plan_canyon_express.py
Sortie : reports/checkpoints/maps/canyon_express_plan.png
"""
import json
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
L = json.load(open(os.path.join(ROOT, "art", "maps", "canyon_express", "layout.json"), encoding="utf-8"))
OUT = os.path.join(ROOT, "reports", "checkpoints", "maps")
os.makedirs(OUT, exist_ok=True)
INK, PAPER = (27, 16, 48), (255, 244, 224)
BANG = os.path.join(ROOT, "resources", "fonts", "Bangers-Regular.ttf")
FB = lambda s: ImageFont.truetype(BANG, s)
F = lambda s: ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", s)
hexc = lambda h: tuple(int(h.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
PX, HALF, M = 17, L["bounds"]["half"], 70
TOP = int(2 * HALF * PX)
SEC_H = 250
W, H = TOP + 2 * M, TOP + 2 * M + SEC_H + 120
img = Image.new("RGB", (W, H), PAPER)
d = ImageDraw.Draw(img)
pal = L["palette"]


def P(x, z):
    return (M + (x + HALF) * PX, M + 60 + (z + HALF) * PX)


def rect(x0, x1, z0, z1, fill, w=3, outline=INK):
    a, b = P(x0, z0), P(x1, z1)
    d.rectangle([a[0], a[1], b[0], b[1]], fill=fill, outline=outline if w else None, width=w)


def label(x, z, t, size=24, fill=PAPER, dy=0):
    tw = d.textlength(t, font=FB(size))
    px, pz = P(x, z)
    d.text((px - tw / 2, pz - size / 2 + dy), t, fill=fill, font=FB(size), stroke_width=3, stroke_fill=INK)


d.text((M, 18), f"{L['name'].upper()} — plan + coupe (carte 2, 4v4, 68×68 m)", fill=INK, font=FB(44))
# falaises périphériques + rebords
rect(-HALF, HALF, -HALF, HALF, (170, 80, 45), w=0)
ph = L["bounds"]["playable_half"]
rect(-ph, ph, -ph, ph, hexc(pal["rim"]), w=3)
# canyon : parois (strates) + fond
cy = L["canyon"]
strata = [hexc(c) for c in pal["strata"]]
for side in (-1, 1):
    zr, zf = side * cy["z_rim"], side * cy["z_floor"]
    for i in range(4):
        z0 = zr + (zf - zr) * i / 4
        z1 = zr + (zf - zr) * (i + 1) / 4
        rect(-ph, ph, min(z0, z1), max(z0, z1), strata[i], w=0)
rect(-ph, ph, -cy["z_floor"], cy["z_floor"], hexc(pal["canyon_floor"]), w=0)
for zz in (-cy["z_rim"], cy["z_rim"]):
    d.line([P(-ph, zz), P(ph, zz)], fill=INK, width=4)
# rampes
rb = L["ramp_band"]
for r in L["ramps"]:
    s = -1 if r["side"] == "north" else 1
    z0, z1 = s * rb["z_outer"], s * rb["z_inner"]
    rect(min(r["landing"]), max(r["landing"]), min(z0, z1), max(z0, z1), hexc(pal["rim"]), w=3)
    rect(r["x_top"], r["x_bottom"], min(z0, z1), max(z0, z1), (236, 200, 150), w=3)
    for k in range(1, 8):
        x = r["x_top"] + (r["x_bottom"] - r["x_top"]) * k / 8
        d.line([P(x, z0), P(x, z1)], fill=(170, 120, 80), width=2)
    px, pz = P((r["x_top"] + r["x_bottom"]) / 2, (z0 + z1) / 2)
    d.text((px - 50, pz - 12), "RAMPE 0 -> -5 m", fill=INK, font=F(15))
# passerelle
fb = L["footbridge"]
rect(fb["x"] - fb["width"] / 2, fb["x"] + fb["width"] / 2, fb["z"][0], fb["z"][1], hexc(pal["bridge_wood"]), w=3)
for z in range(int(fb["z"][0]), int(fb["z"][1]) + 1, 1):
    d.line([P(fb["x"] - fb["width"] / 2, z), P(fb["x"] + fb["width"] / 2, z)], fill=INK, width=1)
# pont + piles
br = L["bridge"]
rect(br["x"][0], br["x"][1], br["z"][0], br["z"][1], hexc(pal["bridge_wood"]), w=4)
for px_ in br["piers"]["x"]:
    for pz_ in br["piers"]["z"]:
        rect(px_ - 0.5, px_ + 0.5, pz_ - 0.5, pz_ + 0.5, (80, 55, 40), w=2)
# rail
d.line([P(0, -HALF), P(0, HALF)], fill=hexc(pal["rail"]), width=10)
for z in range(-34, 35, 2):
    d.line([P(-1.6, z), P(1.6, z)], fill=hexc(pal["sleeper"]), width=4)
# train
for c in L["train"]:
    if c["kind"] in ("gap",):
        continue
    col = hexc(c.get("color", "#3A3444"))
    rect(-1.5, 1.5, c["z"][0], c["z"][1], col, w=3)
    if c["kind"] == "boxcar":
        for sx in (-1.5, 1.5):
            d.line([P(sx, c["door"][0]), P(sx, c["door"][1])], fill=PAPER, width=6)
    if c["kind"] == "locomotive":
        a, b = P(-1.3, c["z"][0] + 0.6), P(1.3, c["z"][1] - 3.2)
        d.ellipse([a[0], a[1], b[0], b[1]], fill=(60, 50, 72), outline=hexc(c["brass"]), width=3)
        label(0, (c["z"][0] + c["z"][1]) / 2, "LOCO", 22)
    if c["kind"] == "boxcar":
        label(0, (c["z"][0] + c["z"][1]) / 2, "<>", 22)
# tunnels
for t in L["tunnels"]:
    x0, x1 = -t["width"] / 2, t["width"] / 2
    z = t["z"]
    a, b = P(x0, z - 1.2), P(x1, z + 1.2)
    d.rectangle([a[0], a[1], b[0], b[1]], fill=INK)
    label(0, z + (3.2 if z < 0 else -3.2), t["name"].replace("Tunnel", "TUNNEL "), 22)
# blocs
for b in L["blocks"]:
    col = hexc(b["color"])
    if b["kind"] in ("water_tower", "hoodoo", "barrels"):
        a, c2 = P(b["x"][0], b["z"][0]), P(b["x"][1], b["z"][1])
        d.ellipse([a[0], a[1], c2[0], c2[1]], fill=col, outline=INK, width=3)
    else:
        rect(b["x"][0], b["x"][1], b["z"][0], b["z"][1], col, w=3)
    if b["kind"] in ("water_tower", "station", "hoodoo"):
        label((b["x"][0] + b["x"][1]) / 2, (b["z"][0] + b["z"][1]) / 2, b["name"], 18)
# apparitions
for team, col, lab in (("team1", (255, 46, 154), "APPARITION B"), ("team0", (46, 139, 255), "APPARITION A")):
    s = L["spawns"][team]
    for gx in s["x_groups"]:
        a, b2 = P(gx[0], s["z"][0]), P(gx[1], s["z"][1])
        d.rectangle([a[0], a[1], b2[0], b2[1]], outline=col, width=5)
        d.text((a[0] + 6, a[1] + 4), lab, fill=col, font=FB(20), stroke_width=2, stroke_fill=INK)
# allées
label(L["footbridge"]["x"], -30.5, "PASSERELLE", 30)
label(0, -12.5 - 0.0, "", 10)
label(22, -30.5, "CANYON", 30)
label(L["footbridge"]["x"], 0, "PONT", 20)
label(26, 0, "FOND DU CANYON  -5 m", 22)
# ---------------- COUPE (x = 0, le long du rail), échelle 1:1
sy = M + 60 + TOP + 40
d.text((M, sy), "COUPE le long du rail (x = 0), même échelle que le plan", fill=INK, font=F(20))
base = sy + 170          # y = 0 (rebord)
SKY = (168, 214, 255)


def S(z, y):
    return (M + (z + HALF) * PX, base - y * PX)


d.rectangle([S(-HALF, 7)[0], S(-HALF, 7)[1], S(HALF, 0)[0], S(HALF, 0)[1]], fill=SKY)
cz, cf = cy["z_rim"], cy["z_floor"]
ground = [(-HALF, 0), (-cz, 0), (-cf, -5), (cf, -5), (cz, 0), (HALF, 0), (HALF, -7), (-HALF, -7)]
d.polygon([S(z, y) for z, y in ground], fill=hexc(pal["rim"]))
d.polygon([S(-cz, 0), S(-cf, -5), S(cf, -5), S(cz, 0)], fill=SKY)
for i, col in enumerate(strata):            # strates des parois
    y0, y1 = -5 * i / 4, -5 * (i + 1) / 4
    for sgn in (-1, 1):
        za = sgn * (cz + (cf - cz) * i / 4)
        zb = sgn * (cz + (cf - cz) * (i + 1) / 4)
        d.polygon([S(sgn * HALF * 0 + za, y0), S(zb, y1), S(sgn * (cz + 1.2), y1), S(sgn * (cz + 1.2), y0)], fill=col)
d.polygon([S(-cf, -5), S(cf, -5), S(cf, -7), S(-cf, -7)], fill=hexc(pal["canyon_floor"]))
d.line([S(z, y) for z, y in ground[:6]], fill=INK, width=4)
# pont : tablier + chevalets
d.rectangle([S(-10, 0)[0], S(-10, 0)[1], S(10, -0.8)[0], S(10, -0.8)[1]], fill=hexc(pal["bridge_wood"]), outline=INK, width=2)
for pz_ in L["bridge"]["piers"]["z"]:
    d.rectangle([S(pz_ - 0.5, -0.8)[0], S(pz_ - 0.5, -0.8)[1], S(pz_ + 0.5, -5)[0], S(pz_ + 0.5, -5)[1]], fill=(80, 55, 40), outline=INK, width=2)
for a_, b_ in ((-9, -2.5), (-2.5, 2.5), (2.5, 9)):
    d.line([S(a_, -0.8), S(b_, -4.2)], fill=(80, 55, 40), width=3)
    d.line([S(b_, -0.8), S(a_, -4.2)], fill=(80, 55, 40), width=3)
for c in L["train"]:
    if c["kind"] in ("gap",):
        continue
    h = c.get("h", 1.2)
    a, b = S(c["z"][0], h), S(c["z"][1], 0)
    d.rectangle([a[0], a[1], b[0], b[1]], fill=hexc(c.get("color", "#3A3444")), outline=INK, width=2)
    if c["kind"] == "boxcar":
        a, b = S(c["door"][0], 2.4), S(c["door"][1], 0.25)
        d.rectangle([a[0], a[1], b[0], b[1]], fill=INK)
# tunnels : falaise + bouche
for t in L["tunnels"]:
    sgn = -1 if t["z"] < 0 else 1
    a, b = S(sgn * HALF, 7), S(sgn * (HALF - 2), 0)
    d.rectangle([min(a[0], b[0]), a[1], max(a[0], b[0]), b[1]], fill=(170, 80, 45), outline=INK, width=2)
    a, b = S(sgn * HALF, 5), S(sgn * (HALF - 2), 0)
    d.rectangle([min(a[0], b[0]), a[1], max(a[0], b[0]), b[1]], fill=INK)
# repères
fig_z = -29.0
d.rectangle([S(fig_z - 0.3, 1.8)[0], S(fig_z - 0.3, 1.8)[1], S(fig_z + 0.3, 0)[0], S(fig_z + 0.3, 0)[1]], fill=(46, 139, 255), outline=INK, width=2)
d.text((S(fig_z + 0.6, 1.8)[0], S(0, 1.8)[1]), "joueur 1,8 m", fill=INK, font=F(15))
for y, t in ((0, "0 m  rebords + pont"), (-5, "-5 m  fond du canyon")):
    d.text((S(HALF, y)[0] + 6, S(0, y)[1] - 10), "", fill=INK, font=F(15))
d.text((S(24.5, 0)[0], S(0, 0)[1] + 8), "0 m : rebords, pont, train", fill=INK, font=F(15))
d.text((S(10.5, -5)[0], S(0, -5)[1] - 20), "<- -5 m : fond du canyon", fill=INK, font=F(15))
d.text((M, base + 7 * PX + 14), "Règles : aucune marche (rampes 14°), passages ≥ 4 m, interstices fermés ou ≥ 2 m, décor fin au-dessus de 2,4 m ; "
       "on peut sauter du pont dans le canyon.", fill=INK, font=F(17))
out = os.path.join(OUT, "canyon_express_plan.png")
img.save(out)
print("plan", out, img.size)
