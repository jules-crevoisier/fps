"""Canyon Express (carte 2) : modèle 3D complet généré par script Blender.

Le décor est peint en couleurs plates ; le rendu toon/BD vient du shader Godot. Le script produit
aussi des volumes de collision simples et convexes.

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b -P tools/maps/build_canyon_express.py [-- --preview]

Cotes : art/maps/canyon_express/layout.json (v2). Sorties :
  assets/maps/canyon_express/canyon_express.glb           visuel fusionné par matériau + collisions
  reports/checkpoints/maps/canyon_express_blender_*.png   aperçus Workbench (avec --preview)

Conventions
- Toutes les cotes de ce fichier sont en axes GODOT (x est, y haut, z sud) ; G() convertit vers Blender.
- Collision : objets « COL_<surface>_<Nom>-convcolonly », un volume convexe chacun. La surface vaut
  rock, wood, metal ou clip. À l'import Godot, chacun devient un StaticBody3D sans maillage visible ;
  ImportedMapGeometry.gd pose la méta « surface » et le calque (clip = PLAYER_CLIP : bloque les
  joueurs, pas les balles).
- Visuel : tout le reste, fusionné en un objet par matériau « VIS_<matériau> ».
- Règles de circulation (layout.json) : rien de fin ni de bas dans un passage ; le décor qui dépasse
  des collisions reste sous 0,3 m ou au-dessus de 2,4 m.
"""
import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender", "lib"))
import toonkit as tk  # noqa: E402

L = json.load(open(os.path.join(ROOT, "art", "maps", "canyon_express", "layout.json"), encoding="utf-8"))
OUT_GLB = os.path.join(ROOT, "assets", "maps", "canyon_express", "canyon_express.glb")
OUT_PREV = os.path.join(ROOT, "reports", "checkpoints", "maps")
FONT_PATH = os.path.join(ROOT, "resources", "fonts", "Bangers-Regular.ttf")
PREVIEW = "--preview" in sys.argv

PAL = {
    "sand": "#E2A864", "sand_dirt": "#D0914E", "sand_light": "#EDC17E",
    "floor": "#C98A55", "creek": "#A86A44", "pebble": "#8E5536",
    "s_red": "#B8532F", "s_cream": "#E9B872", "s_orange": "#D97B3E", "s_dark": "#9E4428", "s_top": "#C0643A",
    "rock": "#C0643A", "boulder": "#A85A38",
    "wood": "#7A5236", "wood_light": "#A87248", "wood_dark": "#553522", "plank": "#94603A",
    "iron": "#3A3444", "rail": "#6A6078", "steel": "#9A94A6",
    "loco": "#2A2436", "loco_red": "#C8342A", "brass": "#D9A93A", "smokebox": "#1F1A28",
    "yellow_car": "#E0A526", "yellow_dark": "#B98318", "teal_car": "#2F8C8A", "teal_dark": "#226A68",
    "caboose": "#B5402F", "roof": "#5E5670",
    "glow": "#FFD166", "ink": "#1B1030", "paper": "#FFF4E0", "coal": "#2B2530",
    "tank": "#8B5A3C", "tank_roof": "#6B4A32",
    "station": "#C9A06A", "station_trim": "#E8392E", "station_roof": "#7A3B2E", "sign": "#FFCE1F", "window": "#2E8BFF",
    "cactus": "#5E9E4A", "cactus_dark": "#3F7A38", "bush": "#8FA84A",
    "crate": "#9C6B3E", "crate_dark": "#6B4A32", "barrel": "#8B5A3C", "cart": "#6E6A78", "rope": "#C9A26A",
}
CANYON_BANDS = [(-5.0, -4.4, "s_dark"), (-4.4, -3.2, "s_red"), (-3.2, -2.2, "s_orange"),
                (-2.2, -0.8, "s_cream"), (-0.8, 0.0, "s_red")]
HIGH_BANDS = [(-5.0, -4.4, "s_dark"), (-4.4, -3.2, "s_red"), (-3.2, -2.2, "s_orange"), (-2.2, -0.8, "s_cream"),
              (-0.8, 1.2, "s_red"), (1.2, 2.7, "s_orange"), (2.7, 3.6, "s_cream"), (3.6, 5.8, "s_red"),
              (5.8, 6.6, "s_cream"), (6.6, 9.0, "s_orange"), (9.0, 99.0, "s_red")]

VIS = []    # objets visuels (fusionnés par matériau à la fin)
COLS = []   # volumes de collision
_MATS = {}
_FONT = []


# ---------------------------------------------------------------------------
# Outils de base
# ---------------------------------------------------------------------------

def G(x, y, z):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return Vector((x, -z, y))


def _lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def M(name):
    """Matériau plat ; la couleur hex est sRGB -> facteur linéaire glTF -> albedo Godot identique."""
    if name not in _MATS:
        h = PAL[name].lstrip("#")
        _MATS[name] = tk.toon_material(name, tuple(_lin(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4)))
    return _MATS[name]


def _obj(name, bm, mats):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for m in mats:
        me.materials.append(M(m))
    return ob


def _hull_bm(pts):
    bm = bmesh.new()
    for p in pts:
        bm.verts.new(G(*p))
    res = bmesh.ops.convex_hull(bm, input=list(bm.verts))
    junk = list({g for g in res.get("geom_interior", []) + res.get("geom_unused", []) if isinstance(g, bmesh.types.BMVert)})
    if junk:
        bmesh.ops.delete(bm, geom=junk, context="VERTS")
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(0.5), verts=list(bm.verts), edges=list(bm.edges))
    return bm


def hull(name, pts, mat, bevel=0.0):
    ob = _obj(name, _hull_bm(pts), [mat])
    if bevel > 0:
        tk.add_bevel(ob, width=bevel, segments=1)
    VIS.append(ob)
    return ob


def box_pts(x0, x1, y0, y1, z0, z1):
    return [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]


def box(name, x0, x1, y0, y1, z0, z1, mat, bevel=0.03):
    return hull(name, box_pts(x0, x1, y0, y1, z0, z1), mat, bevel)


def col(name, surface, pts):
    ob = _obj(f"COL_{surface}_{name}-convcolonly", _hull_bm(pts), [])
    COLS.append(ob)
    return ob


def col_box(name, surface, x0, x1, y0, y1, z0, z1):
    return col(name, surface, box_pts(x0, x1, y0, y1, z0, z1))


def ring_pts(cx, cz, r, y0, y1, n=8):
    """Prisme à n côtés (collision d'un volume rond)."""
    pts = []
    for k in range(n):
        a = 2 * math.pi * (k + 0.5) / n
        for y in (y0, y1):
            pts.append((cx + r * math.cos(a), y, cz + r * math.sin(a)))
    return pts


def cyl(name, c, axis, r, length, mat, seg=12, r2=None, smooth=True, cap=True):
    """Cylindre / tronc de cône centré en c (Godot), axe 'x' | 'y' | 'z'."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=seg, radius1=r,
                          radius2=(r if r2 is None else r2), depth=length)
    if axis == "z":
        bmesh.ops.rotate(bm, verts=list(bm.verts), cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    elif axis == "x":
        bmesh.ops.rotate(bm, verts=list(bm.verts), cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "Y"))
    bmesh.ops.translate(bm, verts=list(bm.verts), vec=G(*c))
    for f in bm.faces:
        f.smooth = smooth and len(f.verts) == 4
    ob = _obj(name, bm, [mat])
    VIS.append(ob)
    return ob


def wobble(a, b, seed):
    return (0.6 * math.sin(a * 0.31 + seed * 1.37) + 0.4 * math.sin(a * 0.83 + b * 0.45 + seed * 2.9))


def band_of(y, bands):
    for y0, y1, m in bands:
        if y0 - 1e-4 <= y <= y1 + 1e-4:
            return m
    return bands[-1][2] if y > bands[-1][1] else bands[0][2]


def _face(bm, vs, mat_index, inward_bl=None):
    try:
        f = bm.faces.new(vs)
    except ValueError:
        return None
    f.material_index = mat_index
    f.normal_update()
    if inward_bl is not None and f.normal.dot(inward_bl) < 0:
        f.normal_flip()
    return f


def cliff(name, base, inward, rows, bands, seed=1, amp=0.25, top=None, cap=0.0, lip=0.1, amp_fn=None):
    """Paroi rocheuse stratifiée (visuel seul).

    base : [(x, z)] au pied ; inward : (nx, nz) vers le vide/l'espace jouable ; rows : [(y, retrait)]
    par y croissant (retrait > 0 = vers le vide) ; top(x, z) -> y max de la colonne (silhouette) ;
    cap : largeur du plateau sommital vers l'extérieur ; lip : corniche aux changements de strate."""
    nx, nz = inward
    inward_bl = Vector((nx, -nz, 0.0))
    mats = sorted({m for _, _, m in bands} | ({"s_top"} if cap else set()))
    mi = {m: k for k, m in enumerate(mats)}
    edges = {round(b[0], 3) for b in bands} | {round(b[1], 3) for b in bands}
    bm = bmesh.new()
    grid, ys = [], []
    for (x, z) in base:
        s = x * abs(nz) + z * abs(nx)
        ytop = top(x, z) if top else None
        colv, coly = [], []
        for j, (y, inset) in enumerate(rows):
            yy = min(y, ytop) if ytop is not None else y
            a = amp_fn(yy) if amp_fn else amp
            border = j == 0 or j == len(rows) - 1 or (ytop is not None and y >= ytop)
            d = inset if border else inset + a * wobble(s, yy * 1.7, seed)
            if round(y, 3) in edges and not border:
                d += lip
            colv.append(bm.verts.new(G(x + nx * d, yy, z + nz * d)))
            coly.append(yy)
        grid.append(colv)
        ys.append(coly)
    for i in range(len(grid) - 1):
        for j in range(len(rows) - 1):
            ymid = (ys[i][j] + ys[i][j + 1] + ys[i + 1][j] + ys[i + 1][j + 1]) / 4
            if ys[i][j + 1] - ys[i][j] < 1e-4 and ys[i + 1][j + 1] - ys[i + 1][j] < 1e-4:
                continue
            _face(bm, [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]], mi[band_of(ymid, bands)], inward_bl)
    if cap:
        outer = []
        for i, (x, z) in enumerate(base):
            v = grid[i][-1].co
            outer.append(bm.verts.new(Vector((v.x - nx * cap, v.y + nz * cap, v.z))))
        for i in range(len(grid) - 1):
            _face(bm, [grid[i][-1], grid[i + 1][-1], outer[i + 1], outer[i]], mi["s_top"], Vector((0, 0, 1)))
    ob = _obj(name, bm, mats)
    VIS.append(ob)
    return ob


def rock(name, x0, x1, y0, h, z0, z1, seed, bands=None, mat="rock", sub=2, rough=0.16, sink=0.3,
         surface="rock", collide=True, flat=0.82):
    """Rocher facetté dans la boîte donnée, strates optionnelles ; collision = enveloppe convexe."""
    rng = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
    cx, cz, sx, sz = (x0 + x1) / 2, (z0 + z1) / 2, (x1 - x0) / 2, (z1 - z0) / 2
    pts = []
    for v in bm.verts:
        n = v.co.normalized() * (1.0 + rng.uniform(-rough, rough)) / (1.0 + rough)
        gx, gz = cx + n.x * sx, cz - n.y * sz
        t = (n.z + 1) / 2
        gy = y0 - sink + t * (h + sink)
        cap_y = y0 + h * flat
        if gy > cap_y:
            gy = cap_y + (gy - cap_y) * 0.35
        gy = max(gy, y0 - sink)
        v.co = G(gx, gy, gz)
        pts.append((gx, gy, gz))
    bands = bands or [(-99, 99, mat)]
    mats = sorted({m for _, _, m in bands})
    for f in bm.faces:
        ymid = sum(v.co.z for v in f.verts) / len(f.verts)
        f.material_index = mats.index(band_of(ymid, bands))
    ob = _obj(name, bm, mats)
    VIS.append(ob)
    if collide:
        col(name, surface, [p for p in pts if p[1] >= y0 - 0.05] + [(p[0], y0, p[2]) for p in pts if p[1] < y0])
    return ob


def text(name, s, size, center, facing, mat, max_w=None, depth=0.02):
    """Lettrage Bangers en relief, centré en `center`, lisible depuis `facing` ('+x' | '-x' | '+z' | '-z')."""
    if not _FONT:
        _FONT.append(bpy.data.fonts.load(FONT_PATH))
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = s
    cu.font = _FONT[0]
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.extrude = depth
    cu.resolution_u = 2
    tmp = bpy.data.objects.new(name + "_tmp", cu)
    bpy.context.scene.collection.objects.link(tmp)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp, do_unlink=True)
    xs = [v.co.x for v in me.vertices]
    if max_w and xs and max(xs) - min(xs) > max_w:
        me.transform(Matrix.Scale(max_w / (max(xs) - min(xs)), 4))
    rz = {"+z": 0, "-z": 180, "+x": 90, "-x": -90}[facing]
    me.transform(Matrix.Rotation(math.radians(rz), 4, "Z") @ Matrix.Rotation(math.radians(90), 4, "X"))
    me.transform(Matrix.Translation(G(*center)))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.clear()
    me.materials.append(M(mat))
    VIS.append(ob)
    return ob


def quad(name, pts, mat):
    bm = bmesh.new()
    vs = [bm.verts.new(G(*p)) for p in pts]
    _face(bm, vs, 0, Vector((0, 0, 1)))
    ob = _obj(name, bm, [mat])
    VIS.append(ob)
    return ob


def poly_patch(name, cx, cz, r, y, mat, seed, n=9):
    rng = random.Random(seed)
    pts = []
    for k in range(n):
        a = 2 * math.pi * k / n
        rr = r * rng.uniform(0.65, 1.0)
        pts.append((cx + rr * math.cos(a), y, cz + rr * math.sin(a) * rng.uniform(0.6, 1.0)))
    return quad(name, pts, mat)


# ---------------------------------------------------------------------------
# Terrain : rebords, fond, falaises du canyon, rampes, falaises périphériques
# ---------------------------------------------------------------------------

CY = L["canyon"]
Z_RIM, Z_FLOOR, FLOOR_Y = CY["z_rim"], CY["z_floor"], CY["floor_y"]
PH = L["bounds"]["playable_half"]
RB = L["ramp_band"]


def ramp_y(r, x):
    """Hauteur de la corniche r en x (palier à 0, puis pente 0 -> -5)."""
    xt, xb = r["x_top"], r["x_bottom"]
    lo, hi = min(r["landing"]), max(r["landing"])
    if lo <= x <= hi:
        return 0.0
    t = (x - xt) / (xb - xt)
    return max(FLOOR_Y, min(0.0, FLOOR_Y * t))


def build_terrain():
    # sols (visuel) : rebords à 0, fond à -5 (débordent sous les falaises)
    for s, nm in ((-1, "N"), (1, "S")):
        z0, z1 = sorted((s * Z_RIM, s * (PH + 1)))
        quad(f"Rim{nm}", [(-PH - 1, 0, z0), (PH + 1, 0, z0), (PH + 1, 0, z1), (-PH - 1, 0, z1)], "sand")
        col_box(f"Rim{nm}", "rock", -44, 44, -8, 0, *sorted((s * Z_RIM, s * 44)))
    cuts = sorted({-PH - 1, PH + 1} | {v for r in L["ramps"] for v in (min(r["landing"]), r["x_bottom"])})
    for k, (xa, xb) in enumerate(zip(cuts[:-1], cuts[1:])):
        under_ramp = any(min(r["landing"]) <= (xa + xb) / 2 <= r["x_bottom"] for r in L["ramps"])
        zf = RB["z_inner"] if under_ramp else Z_RIM
        quad(f"CanyonFloor{k}", [(xa, FLOOR_Y, -zf), (xb, FLOOR_Y, -zf), (xb, FLOOR_Y, zf), (xa, FLOOR_Y, zf)], "floor")
    col_box("CanyonFloor", "rock", -44, 44, FLOOR_Y - 3, FLOOR_Y, -Z_RIM, Z_RIM)
    # lit de ruisseau asséché qui serpente au fond + cailloux (sous 0,2 m : décor seul)
    pts_l, pts_r = [], []
    for k in range(0, 71):
        x = -PH - 1 + k
        zc = 1.6 * math.sin(x * 0.19 + 0.8) + 0.6 * math.sin(x * 0.53)
        w = 1.1 + 0.35 * math.sin(x * 0.37 + 2.0)
        pts_l.append((x, FLOOR_Y + 0.02, zc - w))
        pts_r.append((x, FLOOR_Y + 0.02, zc + w))
    bm = bmesh.new()
    vl = [bm.verts.new(G(*p)) for p in pts_l]
    vr = [bm.verts.new(G(*p)) for p in pts_r]
    for k in range(len(vl) - 1):
        _face(bm, [vl[k], vl[k + 1], vr[k + 1], vr[k]], 0, Vector((0, 0, 1)))
    VIS.append(_obj("Creek", bm, ["creek"]))
    rng = random.Random(11)
    for k in range(70):
        x = rng.uniform(-PH, PH)
        z = 1.6 * math.sin(x * 0.19 + 0.8) + 0.6 * math.sin(x * 0.53) + rng.uniform(-1.8, 1.8)
        r = rng.uniform(0.08, 0.2)
        rock(f"Pebble{k}", x - r, x + r, FLOOR_Y, r * 0.9, z - r, z + r, 100 + k, mat="pebble", sub=1,
             sink=0.02, collide=False)
    # taches de terre battue sur les rebords (décor au ras du sol)
    for k, (cx, cz, r) in enumerate(((-22, -26, 4), (-6, -16, 3.5), (14, -27, 4.5), (24, -12, 3), (-28, -12, 3),
                                     (-20, 27, 4), (6, 17, 3.5), (-8, 29, 4), (22, 26, 4.5), (28, 11, 3),
                                     (-3, -30, 3), (3, 30, 3))):
        poly_patch(f"Dirt{k}", cx, cz, r, 0.02, "sand_dirt" if k % 3 else "sand_light", 40 + k)

    # falaises du canyon : raides (|z| 9 -> 8 sur 5 m), strates, sur toute la longueur
    rows = [(y, (-y / 5.0) * (Z_RIM - Z_FLOOR)) for y in (-5.0, -4.4, -3.8, -3.2, -2.7, -2.2, -1.5, -0.8, -0.35, 0.0)]
    xs = [-PH - 1 + 0.5 * k for k in range(0, int((2 * PH + 2) / 0.5) + 1)]
    for s, nm in ((-1, "N"), (1, "S")):
        cliff(f"CanyonWall{nm}", [(x, s * Z_RIM) for x in xs], (0, -s), rows, CANYON_BANDS, seed=3 + s,
              amp_fn=lambda y: 0.22 * min(1.0, -y / 0.6))
        # collision : coin rocheux (face raide), la corniche des rampes le recouvre là où elle existe
        col(f"CanyonWall{nm}", "rock", [(x, y, z) for x in (-44, 44) for (y, z) in
                                        ((0, s * Z_RIM), (FLOOR_Y, s * Z_RIM), (FLOOR_Y, s * Z_FLOOR))])

    # rampes = corniches de 5 m le long des falaises (palier au niveau du rebord puis pente 14°)
    for r in L["ramps"]:
        s = -1 if r["side"] == "north" else 1
        zo, zi = s * RB["z_outer"], s * RB["z_inner"]
        lo, hi = min(r["landing"]), max(r["landing"])
        xt, xb = r["x_top"], r["x_bottom"]
        x_from, x_to = (lo, xb) if xb > xt else (xb, hi)
        # collision : palier + pente (deux convexes)
        col(f"{r['name']}Landing", "rock", box_pts(lo, hi, FLOOR_Y, 0, *sorted((zo, zi))))
        col(f"{r['name']}Slope", "rock", [(xt, 0, zo), (xt, 0, zi), (xb, FLOOR_Y, zo), (xb, FLOOR_Y, zi),
                                          (xt, FLOOR_Y, zo), (xt, FLOOR_Y, zi)])
        # dessus : chemin de terre battue, bandes de roulement plus sombres
        steps = [x_from + k * 0.5 for k in range(int((x_to - x_from) / 0.5) + 1)]
        bm = bmesh.new()
        a = [bm.verts.new(G(x, ramp_y(r, x), zo)) for x in steps]
        b = [bm.verts.new(G(x, ramp_y(r, x), zi)) for x in steps]
        for k in range(len(steps) - 1):
            _face(bm, [a[k], a[k + 1], b[k + 1], b[k]], 0, Vector((0, 0, 1)))
        VIS.append(_obj(f"{r['name']}Top", bm, ["sand_dirt"]))
        for off in (1.5, 3.3):
            zz = s * (RB["z_inner"] + off)
            bm = bmesh.new()
            a = [bm.verts.new(G(x, ramp_y(r, x) + 0.025, zz - 0.3)) for x in steps]
            b = [bm.verts.new(G(x, ramp_y(r, x) + 0.025, zz + 0.3)) for x in steps]
            for k in range(len(steps) - 1):
                _face(bm, [a[k], a[k + 1], b[k + 1], b[k]], 0, Vector((0, 0, 1)))
            VIS.append(_obj(f"{r['name']}Rut{off}", bm, ["creek"]))
        # flanc côté vide (strates) et bout du palier s'il donne sur le canyon
        rows_f = [(y, 0.0) for y in (-5.0, -4.4, -3.8, -3.2, -2.7, -2.2, -1.5, -0.8, 0.0)]
        cliff(f"{r['name']}Face", [(x, zi) for x in steps], (0, -s), rows_f, CANYON_BANDS, seed=7,
              top=lambda x, z, r=r: ramp_y(r, x), amp=0.08, lip=0.06)
        end_x = lo if xb > xt else hi
        if abs(end_x) < PH - 0.5:
            nx = -1 if xb > xt else 1
            zs = [zo + (zi - zo) * k / 10 for k in range(11)]
            cliff(f"{r['name']}End", [(end_x, z) for z in zs], (nx, 0), rows_f, CANYON_BANDS, seed=8, amp=0.08, lip=0.06)

    # éboulis qui ferment le canyon aux deux bouts
    for sx, nm in ((1, "E"), (-1, "O")):
        col(f"Slide{nm}", "rock", [(sx * x, y, z) for z in (-Z_RIM, Z_RIM) for (x, y) in
                                   ((PH - 2.5, FLOOR_Y), (PH, FLOOR_Y), (PH, -2.5), (PH - 1.0, -2.5))])
        for k in range(9):
            z = -7.5 + k * 1.9
            h = 1.6 + 0.9 * math.sin(k * 1.7)
            rock(f"Slide{nm}{k}", *sorted((sx * (PH - 2.4), sx * (PH + 0.4))), FLOOR_Y, h, z - 1.3, z + 1.3,
                 200 + k + (50 if sx < 0 else 0), mat="boulder", sub=1, collide=False)

    # falaises périphériques (visuel) + murs de collision
    def sil(seed, base=8.5):
        def f(x, z):
            raw = base + 2.6 * math.sin((x + z) * 0.11 + seed) + 1.2 * math.sin((x - z) * 0.29 + 2 * seed)
            return 1.5 * round(raw / 1.5)
        return f
    def bluff(f):   # promontoire au-dessus des tunnels (jamais plus bas que la bouche + 3 m)
        return lambda x, z: max(f(x, z), 9.5 - 0.3 * max(0.0, abs(x) - 4.0))
    up_rows = [(y, -0.1 * max(y, 0.0)) for y in (-5.0, -4.4, -3.2, -2.2, -0.8, 0.0, 0.6, 1.2, 2.0, 2.7, 3.6, 4.6,
                                                 5.8, 6.6, 7.8, 9.0, 10.5, 12.0, 13.5)]
    amp_up = lambda y: 0.1 if y < 0.4 else 0.35
    ew_base = [-PH - 1 + 0.5 * k for k in range(0, int((2 * PH + 2) / 0.5) + 1)]
    for sx, nm in ((1, "E"), (-1, "O")):
        cliff(f"Perim{nm}", [(sx * PH, z) for z in ew_base], (-sx, 0), up_rows, HIGH_BANDS, seed=20 + sx,
              top=sil(1.3 + sx), cap=30.0, amp_fn=amp_up)
        col_box(f"Perim{nm}", "rock", *sorted((sx * PH, sx * 44)), -8, 16, -44, 44)
    for sz, nm in ((-1, "N"), (1, "S")):
        t = L["tunnels"][0 if sz < 0 else 1]
        hw = t["width"] / 2
        rows0 = [rw for rw in up_rows if rw[0] >= 0]
        for side, xr in (("W", (-PH - 1, -hw)), ("E", (hw, PH + 1))):
            n = int((xr[1] - xr[0]) / 0.5)
            cliff(f"Perim{nm}{side}", [(xr[0] + (xr[1] - xr[0]) * k / n, sz * PH) for k in range(n + 1)], (0, -sz),
                  rows0, HIGH_BANDS, seed=30 + sz, top=bluff(sil(0.4 - sz)), cap=30.0, amp_fn=amp_up)
            col_box(f"Perim{nm}{side}", "rock", *(sorted((-44, -hw)) if side == "W" else sorted((hw, 44))), -8, 16,
                    *sorted((sz * PH, sz * 44)))
        lint = [rw for rw in rows0 if rw[0] >= t["height"] + 0.6]
        lint = [(t["height"] + 0.6, -0.1 * (t["height"] + 0.6))] + lint
        cliff(f"Perim{nm}Lintel", [(-hw + 0.5 * k, sz * PH) for k in range(int(2 * hw / 0.5) + 1)], (0, -sz), lint,
              HIGH_BANDS, seed=31, top=bluff(sil(0.4 - sz)), cap=30.0, amp=0.25)
        # tunnel : bouche boisée, intérieur noir, fond et plafond en collision
        build_tunnel(t, sz)


def build_tunnel(t, sz):
    hw, h, zm = t["width"] / 2, t["height"], sz * PH
    zb = sz * (PH + t["depth"] + 5)
    bm = _hull_bm(box_pts(-hw, hw, -0.03, h + 0.6, *sorted((zm, zb))))
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if abs(f.calc_center_median().y + zm) < 1e-3], context="FACES")
    for f in bm.faces:
        f.normal_flip()
    VIS.append(_obj(f"Tunnel{sz}", bm, ["ink"]))
    col_box(f"TunnelBack{sz}", "rock", -hw, hw, -8, 16, *sorted((sz * (PH + t["depth"] - 2), sz * 44)))
    col_box(f"TunnelTop{sz}", "rock", -hw, hw, h, 16, *sorted((zm, sz * 44)))
    zf0, zf1 = sorted((zm - sz * 0.35, zm + sz * 0.25))
    for x in (-1, 1):
        box(f"PortalPost{sz}{x}", x * hw - 0.35, x * hw + 0.35, 0, h + 0.4, zf0, zf1, "wood_dark", 0.04)
        hull(f"PortalKnee{sz}{x}", [(x * (hw - 0.35), h - 1.1, zf0), (x * (hw - 0.35), h - 1.1, zf1),
                                    (x * (hw - 0.35), h, zf0), (x * (hw - 0.35), h, zf1),
                                    (x * (hw - 1.3), h, zf0), (x * (hw - 1.3), h, zf1)], "wood_dark")
    box(f"PortalBeam{sz}", -hw - 0.7, hw + 0.7, h - 0.1, h + 0.7, zf0, zf1, "wood_dark", 0.04)
    zb0, zb1 = sorted((zm - sz * 0.45, zm - sz * 0.38))
    box(f"PortalSign{sz}", -2.1, 2.1, h + 0.85, h + 1.75, zb0, zb1, "sign", 0.02)
    text(f"PortalText{sz}", t["name"].replace("Tunnel", "TUNNEL "), 0.7,
         (0, h + 1.3, zm - sz * 0.49), "-z" if sz > 0 else "+z", "ink", max_w=3.7)


# ---------------------------------------------------------------------------
# Voie ferrée, pont à chevalets, passerelle
# ---------------------------------------------------------------------------

def build_rail():
    g = L["rail"]["gauge"] / 2
    z0, z1 = L["rail"]["z"]
    br = L["bridge"]
    for s in (-1, 1):
        box(f"Rail{s}", s * g - 0.05, s * g + 0.05, 0.12, 0.24, z0, z1, "rail", 0.0)
    z = z0 + 0.4
    k = 0
    while z < z1:
        box(f"Sleeper{k}", -1.25, 1.25, 0.0, 0.12, z - 0.13, z + 0.13, "wood_dark", 0.02)
        z += 0.85
        k += 1
    for s in (-1, 1):   # ballast au sol (pas sur le pont)
        za, zb = (z0, br["z"][0]) if s < 0 else (br["z"][1], z1)
        hull(f"Ballast{s}", [(-1.7, 0.0, za), (1.7, 0.0, za), (-1.4, 0.06, za), (1.4, 0.06, za),
                             (-1.7, 0.0, zb), (1.7, 0.0, zb), (-1.4, 0.06, zb), (1.4, 0.06, zb)], "creek")


def build_bridge():
    br = L["bridge"]
    x0, x1 = br["x"]
    z0, z1 = br["z"]
    col_box("BridgeDeck", "wood", x0, x1, -br["deck_thickness"], 0, z0, z1)
    box("BridgeDeck", x0 + 0.1, x1 - 0.1, -br["deck_thickness"], -0.05, z0, z1, "wood_dark", 0.0)
    z = z0
    k = 0
    while z < z1 - 1e-3:
        box(f"BridgePlank{k}", x0, x1, -0.06, 0.03, z + 0.02, min(z + 0.5, z1) - 0.02, "plank" if k % 2 else "wood", 0.0)
        z += 0.5
        k += 1
    for s in (-1, 1):
        box(f"Stringer{s}", s * (abs(x0) - 0.1) - 0.2, s * (abs(x0) - 0.1) + 0.2, -1.05, -0.3, z0, z1, "wood_dark", 0.03)
    # parapets pleins en planches (couverture), chapeau + poteaux
    pz0, pz1 = br["parapet_z"]
    for s in (-1, 1):
        xa = s * (abs(x0) - 0.35)
        col_box(f"Parapet{s}", "wood", *sorted((xa, s * abs(x0))), 0, br["parapet_h"] + 0.1, pz0, pz1)
        box(f"Parapet{s}", *sorted((xa + s * 0.05, s * (abs(x0) - 0.02))), 0, br["parapet_h"], pz0, pz1, "plank", 0.02)
        box(f"ParapetCap{s}", *sorted((xa - s * 0.03, s * abs(x0) + s * 0.05)), br["parapet_h"], br["parapet_h"] + 0.12,
            pz0 - 0.1, pz1 + 0.1, "wood_dark", 0.02)
        z = pz0
        while z <= pz1 + 1e-3:
            box(f"ParapetPost{s}_{z}", *sorted((xa - s * 0.05, s * abs(x0) + s * 0.08)), 0, br["parapet_h"] + 0.18,
                z - 0.14, z + 0.14, "wood_dark", 0.02)
            z += 3.0
    # chevalets : piles pleines (collision) + croisillons au-dessus de y=-2,6 (décor)
    py = FLOOR_Y
    for pz in br["piers"]["z"]:
        for px in br["piers"]["x"]:
            box(f"PierFoot{px}{pz}", px - 0.65, px + 0.65, py, py + 0.6, pz - 0.65, pz + 0.65, "s_cream", 0.06)
            box(f"Pier{px}{pz}", px - 0.5, px + 0.5, py + 0.6, -0.8, pz - 0.5, pz + 0.5, "wood_dark", 0.05)
            col_box(f"PierFoot{px}{pz}", "rock", px - 0.65, px + 0.65, py, py + 0.6, pz - 0.65, pz + 0.65)
            col_box(f"Pier{px}{pz}", "wood", px - 0.5, px + 0.5, py + 0.6, -0.8, pz - 0.5, pz + 0.5)
        box(f"PierCap{pz}", x0 + 0.2, x1 - 0.2, -1.15, -0.8, pz - 0.3, pz + 0.3, "wood", 0.03)
        for sgn in (-1, 1):
            beam(f"Brace{pz}{sgn}", (sgn * 5.0, -1.0, pz), (-sgn * 5.0, -2.6, pz), 0.14, "wood")
    for px in br["piers"]["x"]:
        for (za, zb) in ((-2.5, 2.5), (2.5, -2.5)):
            beam(f"BraceL{px}{za}", (px, -1.0, za), (px, -2.6, zb), 0.12, "wood")
        for sz in (-1, 1):   # jambes de force contre la falaise
            beam(f"Strut{px}{sz}", (px, -1.0, sz * 2.9), (px, -2.6, sz * 8.9), 0.16, "wood_dark")
    for s in (-1, 1):   # culées en pierre
        hull(f"Abut{s}", box_pts(x0 - 0.3, x1 + 0.3, -1.7, -0.05, *sorted((s * 8.9, s * 9.9))), "s_cream", 0.06)


def beam(name, a, b, r, mat):
    """Poutre carrée de a à b (Godot)."""
    va, vb = Vector(a), Vector(b)
    d = (vb - va).normalized()
    up = Vector((0, 1, 0)) if abs(d.y) < 0.9 else Vector((1, 0, 0))
    u = d.cross(up).normalized() * r
    w = d.cross(u).normalized() * r
    pts = [tuple(p + su * u + sw * w) for p in (va, vb) for su in (-1, 1) for sw in (-1, 1)]
    return hull(name, pts, mat)


def build_footbridge():
    fb = L["footbridge"]
    x, hw = fb["x"], fb["width"] / 2
    z0, z1 = fb["z"]
    col_box("Footbridge", "wood", x - hw, x + hw, -0.3, 0, z0, z1)
    z = z0
    k = 0
    while z < z1 - 1e-3:
        box(f"FbPlank{k}", x - hw, x + hw, -0.25, 0.03, z + 0.03, min(z + 0.45, z1) - 0.03,
            "plank" if k % 3 else "wood_light", 0.02)
        z += 0.45
        k += 1
    for s in (-1, 1):
        box(f"FbStringer{s}", x + s * hw - 0.12, x + s * hw + 0.12, -0.55, -0.2, z0, z1, "wood_dark", 0.03)
        xp = x + s * (hw + 0.12)
        col_box(f"FbRail{s}", "clip", *sorted((x + s * hw, x + s * (hw + 0.12))), 0, fb["rail_h"] + 0.1, z0 + 1, z1 - 1)
        posts = [z0 + 1 + 3 * k for k in range(int((z1 - z0 - 2) / 3) + 1)]
        for pz in posts:
            box(f"FbPost{s}{pz}", xp - 0.1, xp + 0.1, -0.6, fb["rail_h"] + 0.15, pz - 0.1, pz + 0.1, "wood_dark", 0.02)
        for hy in (fb["rail_h"], fb["rail_h"] - 0.45):
            for a, b in zip(posts[:-1], posts[1:]):
                m = (a + b) / 2
                beam(f"Rope{s}{a}{hy}a", (xp, hy, a), (xp, hy - 0.1, m), 0.03, "rope")
                beam(f"Rope{s}{a}{hy}b", (xp, hy - 0.1, m), (xp, hy, b), 0.03, "rope")
        for sz in (-1, 1):   # grands poteaux d'ancrage sur les rebords + haubans
            zz = sz * (abs(z0) + 0.4)
            box(f"FbAnchor{s}{sz}", xp - 0.18, xp + 0.18, 0, 2.3, zz - 0.18, zz + 0.18, "wood_dark", 0.03)
            beam(f"FbCable{s}{sz}", (xp, 2.2, zz), (xp, fb["rail_h"] + 0.1, sz * 3.0), 0.04, "rope")


# ---------------------------------------------------------------------------
# Train
# ---------------------------------------------------------------------------

def wheels(name, z0, z1, r=0.4, xw=1.58, mat="iron"):
    for zc in (z0 + 1.05, z1 - 1.05):
        for dz in (-0.5, 0.5):
            for s in (-1, 1):
                cyl(f"{name}W{zc}{dz}{s}", (s * xw, r - 0.05, zc + dz), "x", r, 0.16, mat, seg=14)
                cyl(f"{name}H{zc}{dz}{s}", (s * (xw + 0.1), r - 0.05, zc + dz), "x", r * 0.32, 0.05, "steel", seg=8)
        for s in (-1, 1):
            box(f"{name}Frame{zc}{s}", s * 1.66 - 0.04, s * 1.66 + 0.04, r - 0.2, r + 0.05, zc - 0.85, zc + 0.85, "iron", 0.02)


def build_boxcar(c, idx):
    z0, z1 = c["z"]
    fy, h = c["floor_y"], c["h"]
    d0, d1 = c["door"]
    body, dark = ("yellow_car", "yellow_dark") if c["color"] == "#E0A526" else ("teal_car", "teal_dark")
    n = f"Box{idx}"
    col_box(f"{n}Floor", "wood", -1.5, 1.5, 0, fy, z0, z1)
    box(f"{n}Under", -1.35, 1.35, 0.0, fy, z0 + 0.3, z1 - 0.3, "iron", 0.02)
    box(f"{n}FloorTop", -1.3, 1.3, fy - 0.04, fy, z0 + 0.2, z1 - 0.2, "plank", 0.0)
    wall_top = h - 0.3
    for s in (-1, 1):
        xa, xb = sorted((s * 1.3, s * 1.5))
        for za, zb in ((z0, d0), (d1, z1)):
            box(f"{n}Side{s}{za}", xa, xb, fy, wall_top, za, zb, body, 0.02)
            col_box(f"{n}Side{s}{za}", "wood", xa, xb, fy, wall_top, za, zb)
        box(f"{n}Lintel{s}", xa, xb, 2.9, wall_top, d0, d1, body, 0.02)
        col_box(f"{n}Lintel{s}", "wood", xa, xb, 2.9, wall_top, d0, d1)
        # porte coulissante ouverte, rail de porte, ferrures
        pd0, pd1 = d1 + 0.05, min(d1 + (d1 - d0), z1 - 0.1)
        box(f"{n}Door{s}", *sorted((s * 1.5, s * 1.58)), fy + 0.1, 2.85, pd0, pd1, dark, 0.02)
        box(f"{n}DoorRail{s}", *sorted((s * 1.5, s * 1.6)), 2.9, 3.0, d0 - 0.2, z1 - 0.1, "iron", 0.01)
        for zz in (z0 + 0.12, d0 - 0.12, d1 + 0.12, z1 - 0.12):
            box(f"{n}Strap{s}{zz}", *sorted((s * 1.5, s * 1.56)), fy, wall_top, zz - 0.06, zz + 0.06, "iron", 0.0)
        # lettrage peint sur les deux panneaux
        for (za, zb), word in zip(((z0, d0), (d1, z1)), c["lettering"]):
            text(f"{n}Txt{s}{za}", word, 0.55, (s * 1.535, 2.05, (za + zb) / 2), "+x" if s > 0 else "-x", "paper",
                 max_w=(zb - za) - 0.45)
        # petite rampe de porte (0,35 m sur 1,1 m)
        ramp = [(s * 1.5, 0, d0 + 0.1), (s * 1.5, fy, d0 + 0.1), (s * 2.6, 0, d0 + 0.1),
                (s * 1.5, 0, d1 - 0.1), (s * 1.5, fy, d1 - 0.1), (s * 2.6, 0, d1 - 0.1)]
        hull(f"{n}Ramp{s}", ramp, "wood_light")
        col(f"{n}Ramp{s}", "wood", ramp)
    for zz, nm in ((z0, "A"), (z1, "B")):
        za, zb = sorted((zz, zz - 0.2 if zz == z1 else zz + 0.2))
        box(f"{n}End{nm}", -1.5, 1.5, fy, wall_top, za, zb, body, 0.02)
        col_box(f"{n}End{nm}", "wood", -1.5, 1.5, fy, wall_top, za, zb)
    roof = [(x, y, z) for z in (z0 - 0.12, z1 + 0.12) for (x, y) in ((-1.66, wall_top), (1.66, wall_top),
                                                                      (-1.66, wall_top + 0.12), (1.66, wall_top + 0.12),
                                                                      (0, h))]
    hull(f"{n}Roof", roof, "roof", 0.02)
    col(f"{n}Roof", "wood", roof)
    box(f"{n}Walk", -0.3, 0.3, h - 0.02, h + 0.06, z0 - 0.1, z1 + 0.1, "wood_dark", 0.0)
    wheels(n, z0, z1)


def build_flatcar(c, idx):
    z0, z1 = c["z"]
    h = c["h"]
    n = f"Flat{idx}"
    col_box(n, "wood", -1.5, 1.5, 0, h, z0, z1)
    box(f"{n}Under", -1.3, 1.3, 0.0, h - 0.45, z0 + 0.25, z1 - 0.25, "iron", 0.02)
    box(f"{n}Sill", -1.5, 1.5, h - 0.45, h - 0.2, z0, z1, "iron", 0.03)
    for k in range(6):
        za = z0 + (z1 - z0) * k / 6
        box(f"{n}Deck{k}", -1.5, 1.5, h - 0.2, h, za + 0.02, za + (z1 - z0) / 6 - 0.02, "plank" if k % 2 else "wood", 0.02)
    wheels(n, z0, z1)
    if c["load"] == "crates":
        for k, (xa, xb, za, zb) in enumerate(((-1.4, 0.0, z0 + 0.3, z0 + 1.8), (-0.1, 1.4, z1 - 1.9, z1 - 0.4))):
            crate(f"{n}Crate{k}", xa, xb, h, h + 1.3, za, zb)
    else:
        top = h + 1.55
        for k, (lx, ly) in enumerate(((-0.86, h + 0.43), (0.0, h + 0.43), (0.86, h + 0.43), (-0.43, h + 1.15), (0.43, h + 1.15))):
            cyl(f"{n}Log{k}", (lx, ly, (z0 + z1) / 2), "z", 0.42, (z1 - z0) - 0.5, "wood", seg=10)
            for sz in (-1, 1):
                cyl(f"{n}LogEnd{k}{sz}", (lx, ly, (z0 + z1) / 2 + sz * ((z1 - z0) / 2 - 0.25)), "z", 0.36, 0.03,
                    "wood_light", seg=10, smooth=False)
        for zz in (z0 + 0.5, (z0 + z1) / 2, z1 - 0.5):
            for s in (-1, 1):
                box(f"{n}Stake{zz}{s}", s * 1.42 - 0.07, s * 1.42 + 0.07, h, top, zz - 0.07, zz + 0.07, "wood_dark", 0.0)
        col(f"{n}Logs", "wood", [(x, y, z) for z in (z0 + 0.25, z1 - 0.25)
                                 for (x, y) in ((-1.3, h), (1.3, h), (-0.85, h + 1.57), (0.85, h + 1.57))])


def crate(name, x0, x1, y0, y1, z0, z1, collide=True):
    box(name, x0, x1, y0, y1, z0, z1, "crate", 0.04)
    for (xa, za) in ((x0, z0), (x0, z1), (x1, z0), (x1, z1)):
        box(f"{name}E{xa}{za}", xa - 0.06, xa + 0.06, y0, y1, za - 0.06, za + 0.06, "crate_dark", 0.01)
    for yy in ((y0, y1) if y0 < 0.9 else (y1,)):
        box(f"{name}R{yy}", x0 - 0.04, x1 + 0.04, yy - 0.06, yy + 0.06, z0 - 0.04, z1 + 0.04, "crate_dark", 0.01)
    if collide:
        col_box(name, "wood", x0, x1, y0, y1, z0, z1)


def build_coupler(c, idx):
    z0, z1 = c["z"]
    col_box(f"Coupler{idx}", "metal", -1.5, 1.5, 0, c["h"], z0, z1)
    box(f"Coupler{idx}", -1.45, 1.45, 0.0, c["h"] - 0.05, z0 - 0.05, z1 + 0.05, "iron", 0.03)
    box(f"CouplerKnuckle{idx}", -0.3, 0.3, 0.45, 0.8, z0 - 0.15, z1 + 0.15, "steel", 0.03)


def build_locomotive(c):
    z0, z1 = c["z"]
    col_box("LocoBase", "metal", -1.8, 1.8, 0, 1.45, z0 + 1.0, z1)
    col("LocoBoiler", "metal", [(x, y + 2.05, z) for z in (z0 + 0.75, 1.8) for (x, y) in
                                [(1.1 * math.cos(a), 1.1 * math.sin(a)) for a in (i * math.pi / 4 for i in range(8))]])
    col_box("LocoCab", "metal", -1.5, 1.5, 1.45, c["h"], 1.8, z1)
    col_box("LocoStack", "metal", -0.5, 0.5, 3.0, 4.5, -2.8, -1.8)
    pilot = [(-1.3, 0.05, z0 + 1.0), (1.3, 0.05, z0 + 1.0), (-1.3, 1.05, z0 + 1.0), (1.3, 1.05, z0 + 1.0),
             (-0.25, 0.05, z0 - 0.2), (0.25, 0.05, z0 - 0.2), (-0.25, 0.35, z0 - 0.1), (0.25, 0.35, z0 - 0.1)]
    col("LocoPilot", "metal", pilot)
    hull("LocoPilot", pilot, "loco_red", 0.03)
    for k in range(5):   # barreaux du chasse-bestiaux
        x = -1.0 + k * 0.5
        beam(f"PilotBar{k}", (x, 1.0, z0 + 0.95), (x * 0.25, 0.12, z0 - 0.12), 0.035, "iron")
    box("LocoFrame", -1.3, 1.3, 0.3, 1.12, z0 + 0.6, z1 - 0.1, "iron", 0.03)
    for s in (-1, 1):
        box(f"LocoBoard{s}", *sorted((s * 1.05, s * 1.5)), 1.12, 1.22, z0 + 1.05, 1.8, "loco_red", 0.02)
        box(f"LocoBoardEdge{s}", *sorted((s * 1.5, s * 1.54)), 1.0, 1.24, z0 + 1.05, 1.8, "brass", 0.0)
    # chaudière, boîte à fumée, bandes laiton
    cyl("Boiler", (0, 2.05, (z0 + 1.1 + 1.8) / 2), "z", 1.05, 1.8 - (z0 + 1.1), "loco", seg=20)
    cyl("Smokebox", (0, 2.05, z0 + 0.95), "z", 1.1, 0.35, "smokebox", seg=20)
    cyl("SmokeDoor", (0, 2.05, z0 + 0.74), "z", 0.85, 0.08, "iron", seg=20)
    cyl("NumberPlate", (0, 2.05, z0 + 0.68), "z", 0.36, 0.05, "brass", seg=16, smooth=False)
    text("LocoNumber", "7", 0.5, (0, 2.05, z0 + 0.64), "-z", "ink")
    for zb in (z0 + 1.8, -0.8, 0.7):
        cyl(f"BoilerBand{zb}", (0, 2.05, zb), "z", 1.08, 0.1, "brass", seg=20)
    # cheminée « diamant », dômes, cloche, phare
    cyl("StackBase", (0, 3.35, -2.3), "y", 0.3, 0.7, "loco", seg=12)
    cyl("StackFlare", (0, 3.95, -2.3), "y", 0.3, 0.6, "loco", seg=12, r2=0.75)
    cyl("StackTop", (0, 4.35, -2.3), "y", 0.75, 0.22, "iron", seg=12)
    cyl("StackBand", (0, 3.68, -2.3), "y", 0.34, 0.1, "loco_red", seg=12)
    cyl("SteamDome", (0, 3.15, -0.6), "y", 0.42, 0.55, "brass", seg=14)
    cyl("SteamDomeTop", (0, 3.5, -0.6), "y", 0.42, 0.18, "brass", seg=14, r2=0.22)
    cyl("SandDome", (0, 3.1, 0.9), "y", 0.34, 0.45, "brass", seg=14)
    cyl("SandDomeTop", (0, 3.38, 0.9), "y", 0.34, 0.14, "brass", seg=14, r2=0.18)
    cyl("Bell", (0, 3.25, 0.15), "y", 0.12, 0.35, "brass", seg=10, r2=0.24)
    box("Headlamp", -0.38, 0.38, 3.1, 3.72, z0 + 0.8, z0 + 1.35, "iron", 0.03)
    cyl("HeadlampLens", (0, 3.41, z0 + 0.78), "z", 0.22, 0.05, "glow", seg=14, smooth=False)
    # cabine
    box("Cab", -1.5, 1.5, 1.22, 3.5, 1.8, z1 - 0.05, "loco_red", 0.03)
    roof = [(x, y, z) for z in (1.6, z1 + 0.15) for (x, y) in ((-1.75, 3.5), (1.75, 3.5), (-1.75, 3.62), (1.75, 3.62),
                                                                (0, c["h"]))]
    hull("CabRoof", roof, "loco", 0.02)
    for s in (-1, 1):
        for za, zb in ((2.15, 2.95), (3.3, 4.1)):
            box(f"CabWin{s}{za}", *sorted((s * 1.5, s * 1.53)), 2.3, 3.1, za, zb, "ink", 0.0)
            box(f"CabWinFrame{s}{za}", *sorted((s * 1.49, s * 1.52)), 2.22, 3.18, za - 0.08, zb + 0.08, "brass", 0.0)
        text(f"CabNum{s}", "Nº 7", 0.42, (s * 1.535, 1.75, 3.1), "+x" if s > 0 else "-x", "brass", max_w=1.4)
        box(f"CabFrontWin{s}", *sorted((s * 0.9, s * 1.35)), 2.85, 3.3, 1.76, 1.8, "ink", 0.0)
    # roues motrices rouges, bielles, bogie avant, roue arrière
    for zc in (-1.9, -0.35, 1.2):
        for s in (-1, 1):
            cyl(f"Driver{zc}{s}", (s * 1.61, 0.72, zc), "x", 0.72, 0.18, "iron", seg=20)
            cyl(f"DriverFace{zc}{s}", (s * 1.71, 0.72, zc), "x", 0.6, 0.03, "loco_red", seg=20, smooth=False)
            cyl(f"DriverHub{zc}{s}", (s * 1.75, 0.72, zc), "x", 0.2, 0.06, "brass", seg=10)
    for s in (-1, 1):
        box(f"SideRod{s}", *sorted((s * 1.76, s * 1.82)), 0.62, 0.78, -1.95, 1.25, "steel", 0.01)
        cyl(f"Cylinder{s}", (s * 1.35, 0.85, -2.75), "z", 0.36, 0.9, "loco", seg=14)
        for zc in (-2.95, -2.35):
            cyl(f"Lead{zc}{s}", (s * 1.58, 0.38, zc), "x", 0.38, 0.16, "iron", seg=12)
        cyl(f"Trail{s}", (s * 1.58, 0.45, 3.6), "x", 0.45, 0.16, "iron", seg=12)


def build_tender(c):
    z0, z1 = c["z"]
    h = c["h"]
    col_box("Tender", "metal", -1.65, 1.65, 0, h, z0, z1)
    box("TenderBody", -1.5, 1.5, 0.35, h - 0.35, z0 + 0.1, z1 - 0.05, "loco", 0.04)
    box("TenderTrim", -1.56, 1.56, h - 0.45, h - 0.3, z0 + 0.05, z1, "loco_red", 0.02)
    box("TenderUnder", -1.35, 1.35, 0.0, 0.35, z0 + 0.3, z1 - 0.3, "iron", 0.02)
    rock("Coal", -1.35, 1.35, h - 0.35, 0.7, z0 + 0.25, z0 + 2.6, 77, mat="coal", sub=2, rough=0.25, sink=0.1, collide=False)
    box("TenderHatch", -0.55, 0.55, h - 0.35, h - 0.15, z1 - 1.2, z1 - 0.3, "iron", 0.03)
    for s in (-1, 1):
        cyl(f"TenderBadge{s}", (s * 1.52, 1.45, (z0 + z1) / 2), "x", 0.5, 0.04, "brass", seg=18, smooth=False)
        text(f"TenderTxt{s}", "C.E.", 0.42, (s * 1.555, 1.45, (z0 + z1) / 2), "+x" if s > 0 else "-x", "ink", max_w=0.8)
    wheels("Tender", z0, z1)


def build_caboose(c):
    z0, z1 = c["z"]
    h = c["h"]
    col_box("Caboose", "wood", -1.6, 1.6, 0, h - 0.2, z0, z1)
    box("CabooseUnder", -1.35, 1.35, 0.0, 0.45, z0 + 0.3, z1 - 0.3, "iron", 0.02)
    box("CabooseDeck", -1.5, 1.5, 0.35, 0.5, z0, z1, "wood_dark", 0.02)
    box("CabooseBody", -1.5, 1.5, 0.5, h - 0.45, z0 + 0.6, z1 - 0.6, "caboose", 0.03)
    roof = [(x, y, z) for z in (z0 + 0.35, z1 - 0.35) for (x, y) in ((-1.68, h - 0.45), (1.68, h - 0.45),
                                                                      (-1.68, h - 0.33), (1.68, h - 0.33), (0, h - 0.2))]
    hull("CabooseRoof", roof, "roof", 0.02)
    zc = (z0 + z1) / 2
    box("Cupola", -0.9, 0.9, h - 0.3, h + 0.6, zc - 0.9, zc + 0.9, "caboose", 0.03)
    hull("CupolaRoof", [(x, y, z) for z in (zc - 1.05, zc + 1.05) for (x, y) in ((-1.05, h + 0.6), (1.05, h + 0.6),
                                                                                  (-1.05, h + 0.7), (1.05, h + 0.7), (0, h + 0.85))], "roof", 0.02)
    for s in (-1, 1):
        box(f"CupolaWin{s}", *sorted((s * 0.9, s * 0.93)), h - 0.05, h + 0.4, zc - 0.55, zc + 0.55, "glow", 0.0)
        for zw in (z0 + 1.3, z1 - 1.3):
            box(f"CabooseWin{s}{zw}", *sorted((s * 1.5, s * 1.53)), 1.7, 2.4, zw - 0.35, zw + 0.35, "glow", 0.0)
            box(f"CabooseWinF{s}{zw}", *sorted((s * 1.49, s * 1.52)), 1.62, 2.48, zw - 0.43, zw + 0.43, "paper", 0.0)
        text(f"CabooseTxt{s}", "99", 0.6, (s * 1.535, 1.2, zc), "+x" if s > 0 else "-x", "paper", max_w=1.2)
        for zz in (z0 + 0.05, z1 - 0.05):   # garde-corps des plateformes (dans le volume de collision)
            box(f"CabooseRail{s}{zz}", *sorted((s * 1.35, s * 1.45)), 0.5, 1.5, zz - 0.04, zz + 0.04, "iron", 0.0)
        box(f"CabooseRailTop{s}", *sorted((s * 1.35, s * 1.45)), 1.45, 1.55, z0, z1, "iron", 0.0)
    cyl("CabooseStove", (0.6, h + 0.2, z1 - 1.2), "y", 0.12, 0.9, "iron", seg=8)
    cyl("CabooseLamp", (-1.2, 2.9, z0 + 0.1), "y", 0.14, 0.35, "loco_red", seg=8)
    wheels("Caboose", z0, z1)


def build_train():
    for idx, c in enumerate(L["train"]):
        k = c["kind"]
        if k == "boxcar":
            build_boxcar(c, idx)
        elif k == "flatcar":
            build_flatcar(c, idx)
        elif k == "coupler":
            build_coupler(c, idx)
        elif k == "locomotive":
            build_locomotive(c)
        elif k == "tender":
            build_tender(c)
        elif k == "caboose":
            build_caboose(c)


# ---------------------------------------------------------------------------
# Blocs du rebord et du fond
# ---------------------------------------------------------------------------

def build_water_tower(b):
    x0, x1 = b["x"]
    z0, z1 = b["z"]
    cx, cz, h = (x0 + x1) / 2, (z0 + z1) / 2, b["h"]
    col_box("WaterBase", "wood", x0, x1, 0, h, z0, z1)
    box("WaterStone", x0 - 0.05, x1 + 0.05, 0, 1.1, z0 - 0.05, z1 + 0.05, "s_cream", 0.06)
    box("WaterTimber", x0, x1, 1.1, h, z0, z1, "wood", 0.04)
    for xa in (x0, x1):
        for za in (z0, z1):
            box(f"WaterCorner{xa}{za}", xa - 0.14, xa + 0.14, 1.1, h, za - 0.14, za + 0.14, "wood_dark", 0.02)
    for k in range(1, 8):
        xa = x0 + (x1 - x0) * k / 8
        za = z0 + (z1 - z0) * k / 8
        box(f"WaterPlankX{k}", xa - 0.03, xa + 0.03, 1.1, h, z0 - 0.03, z1 + 0.03, "wood_dark", 0.0)
        box(f"WaterPlankZ{k}", x0 - 0.03, x1 + 0.03, 1.1, h, za - 0.03, za + 0.03, "wood_dark", 0.0)
    box("WaterDeck", x0 - 0.4, x1 + 0.4, h, h + 0.2, z0 - 0.4, z1 + 0.4, "wood_dark", 0.03)
    r = b["tank_r"]
    cyl("Tank", (cx, h + 0.2 + 1.8, cz), "y", r, 3.6, "tank", seg=20)
    col("Tank", "wood", ring_pts(cx, cz, r, h + 0.2, h + 3.8, 10))
    for yy in (h + 0.7, h + 2.0, h + 3.3):
        cyl(f"TankHoop{yy}", (cx, yy, cz), "y", r + 0.05, 0.14, "iron", seg=20)
    cyl("TankRoof", (cx, h + 4.45, cz), "y", r + 0.3, 1.3, "tank_roof", seg=20, r2=0.25, smooth=False)
    cyl("TankFinial", (cx, h + 5.2, cz), "y", 0.18, 0.3, "brass", seg=8)
    # bec verseur tourné vers la voie
    cyl("Spout", (cx + r + 0.9, h + 2.6, cz), "x", 0.28, 1.8, "iron", seg=10)
    beam("SpoutDrop", (cx + r + 1.7, h + 2.6, cz), (cx + r + 2.4, h + 1.4, cz), 0.16, "iron")
    for yy in (0.4, 1.0, 1.6, 2.2, 2.8):   # échelle plaquée
        box(f"Ladder{yy}", x1 + 0.02, x1 + 0.08, yy - 0.04, yy + 0.04, cz - 0.4, cz + 0.4, "wood_dark", 0.0)
    text("WaterTxt", "EAU", 1.1, (cx + r + 0.03, h + 2.0, cz), "+x", "paper", max_w=1.9)


def build_station(b):
    x0, x1 = b["x"]
    z0, z1 = b["z"]
    h = b["h"]
    col_box("Station", "wood", x0, x1, 0, h, z0, z1)
    box("StationBase", x0 - 0.06, x1 + 0.06, 0, 0.55, z0 - 0.06, z1 + 0.06, "s_red", 0.04)
    box("StationWalls", x0, x1, 0.55, h, z0, z1, "station", 0.04)
    for (xa, za) in ((x0, z0), (x0, z1), (x1, z0), (x1, z1)):
        box(f"StationCorner{xa}{za}", xa - 0.12, xa + 0.12, 0.55, h, za - 0.12, za + 0.12, "station_trim", 0.02)
    box("StationEave", x0 - 0.15, x1 + 0.15, h - 0.2, h, z0 - 0.15, z1 + 0.15, "station_trim", 0.02)
    xm = (x0 + x1) / 2
    roof = [(x, y, z) for z in (z0 - 0.5, z1 + 0.5) for (x, y) in ((x0 - 0.5, h - 0.1), (x1 + 0.5, h - 0.1), (xm, h + 1.9))]
    hull("StationRoof", roof, "station_roof", 0.04)
    col("StationRoof", "wood", roof)
    box("StationChimney", xm - 1.6, xm - 0.9, h + 0.8, h + 2.6, z0 + 1.0, z0 + 1.7, "s_red", 0.03)
    # façade côté voie (x1) : porte, fenêtres, enseigne, auvent en porte-à-faux (pas de poteau)
    fx = x1 + 0.02
    box("StationDoor", x1, fx + 0.03, 0.55, 2.7, (z0 + z1) / 2 - 0.65, (z0 + z1) / 2 + 0.65, "wood_dark", 0.0)
    for zw in (z0 + 1.1, z1 - 1.1):
        box(f"StationWin{zw}", x1, fx + 0.03, 1.2, 2.5, zw - 0.55, zw + 0.55, "window", 0.0)
        box(f"StationWinF{zw}", x1, fx + 0.01, 1.1, 2.6, zw - 0.65, zw + 0.65, "paper", 0.0)
    for zz, fz in ((z0, "-z"), (z1, "+z")):
        s = -1 if fz == "-z" else 1
        box(f"StationSideWin{zz}", x0 + 1.8, x0 + 3.2, 1.2, 2.5, *sorted((zz, zz + s * 0.05)), "window", 0.0)
    box("StationSign", x1 + 0.02, x1 + 0.12, h - 1.05, h - 0.3, z0 + 0.4, z1 - 0.4, "sign", 0.02)
    text("StationTxt", "CANYON EXPRESS", 0.55, (x1 + 0.14, h - 0.67, (z0 + z1) / 2), "+x", "ink", max_w=(z1 - z0) - 1.2)
    aw = [(x, y, z) for z in (z0 + 0.3, z1 - 0.3) for (x, y) in ((x1, 3.45), (x1, 3.6), (x1 + 2.4, 2.95), (x1 + 2.4, 3.08))]
    hull("StationAwning", aw, "station_roof", 0.02)
    for zz in (z0 + 0.8, (z0 + z1) / 2, z1 - 0.8):
        beam(f"AwningBracket{zz}", (x1 + 0.05, 2.55, zz), (x1 + 1.5, 3.2, zz), 0.07, "wood_dark")
    text("GareTxt", "GARE", 0.8, ((x0 + x1) / 2, 3.1, z1 + 0.05), "+z", "station_roof", max_w=3.5)


def build_hoodoo(b, idx):
    x0, x1 = b["x"]
    z0, z1 = b["z"]
    cx, cz, h = (x0 + x1) / 2, (z0 + z1) / 2, b["h"]
    bands = [(-9, 1.0, "s_dark"), (1.0, 2.2, "s_red"), (2.2, 3.3, "s_cream"), (3.3, 4.8, "s_orange"),
             (4.8, 5.6, "s_cream"), (5.6, 99, "s_red")]
    rock(f"Hoodoo{idx}Base", x0, x1, 0, 2.6, z0, z1, 300 + idx, bands=bands, sub=2, rough=0.12, collide=False)
    col(f"Hoodoo{idx}", "rock", ring_pts(cx, cz, 1.95, 0, 2.3, 10) + ring_pts(cx, cz, 1.45, 2.3, 4.9, 10))
    parts = ((2.2, 4.9, 1.5, 1.05), (4.8, 6.3, 0.95, 0.7), (6.2, h, 1.75, 1.6))
    for k, (ya, yb, ra, rb) in enumerate(parts):
        ob = cyl(f"Hoodoo{idx}P{k}", (cx, (ya + yb) / 2, cz), "y", ra, yb - ya, "s_orange", seg=9, r2=rb, smooth=False)
        rng = random.Random(400 + idx * 10 + k)
        me = ob.data
        for v in me.vertices:
            v.co.x += rng.uniform(-0.12, 0.12)
            v.co.y += rng.uniform(-0.12, 0.12)
        me.materials.clear()
        for m in sorted({m for _, _, m in bands}):
            me.materials.append(M(m))
        names = [m.name for m in me.materials]
        for p in me.polygons:
            ymid = sum(me.vertices[i].co.z for i in p.vertices) / len(p.vertices)
            p.material_index = names.index(band_of(ymid, bands))


def build_blocks():
    for i, b in enumerate(L["blocks"]):
        k = b["kind"]
        x0, x1 = b["x"]
        z0, z1 = b["z"]
        y0 = b.get("y", 0.0)
        tag = f"B{i}"
        if k == "water_tower":
            build_water_tower(b)
        elif k == "station":
            build_station(b)
        elif k == "hoodoo":
            build_hoodoo(b, i)
        elif k in ("rock", "boulder"):
            bands = [(-9, y0 + 0.6, "s_dark"), (y0 + 0.6, y0 + 1.3, "s_red"), (y0 + 1.3, 99, "s_orange")]
            rock(tag, x0, x1, y0, b["h"], z0, z1, 500 + i, bands=bands, sub=2)
        elif k == "crates":
            if b["h"] > 2:
                n = 4
                w = (x1 - x0) / n
                for c in range(n):
                    crate(f"{tag}c{c}", x0 + c * w + 0.03, x0 + (c + 1) * w - 0.03, 0, 1.2, z0, z1, collide=False)
                col_box(f"{tag}Low", "wood", x0, x1, 0, 1.2, z0, z1)
                for c, (xa, xb) in enumerate(((x0 + 0.4, x0 + 1.9), (x0 + 2.25, x0 + 3.75), (x1 - 1.9, x1 - 0.4))):
                    crate(f"{tag}t{c}", xa, xb, 1.2, 2.4, z0 + 0.3, z1 - 0.3)
            else:
                xm = (x0 + x1) / 2
                crate(f"{tag}a", x0, xm - 0.03, 0, b["h"], z0, z1, collide=False)
                crate(f"{tag}b", xm + 0.03, x1, 0, b["h"] - 0.2, z0 + 0.1, z1 - 0.1, collide=False)
                col_box(tag, "wood", x0, x1, 0, b["h"], z0, z1)
        elif k == "barrels":
            pts = []
            for c, (bx, bz) in enumerate(((x0 + 0.72, z0 + 0.65), (x1 - 0.72, z0 + 0.65), (x0 + 0.72, z1 - 0.65),
                                           (x1 - 0.72, z1 - 0.65))):
                cyl(f"{tag}Barrel{c}", (bx, b["h"] / 2, bz), "y", 0.6, b["h"], "barrel", seg=14)
                for yy in (0.2, b["h"] / 2, b["h"] - 0.2):
                    cyl(f"{tag}Hoop{c}{yy}", (bx, yy, bz), "y", 0.63, 0.07, "iron", seg=14)
                pts += ring_pts(bx, bz, 0.6, 0, b["h"], 8)
            col(tag, "wood", pts)
        elif k == "ore_cart":
            body = [(x0 + 0.2, y0, z0 + 0.1), (x0 + 0.2, y0, z1 - 0.1), (x0 + 0.2, y0 + 1.55, z0 + 0.1),
                    (x0 + 0.2, y0 + 1.55, z1 - 0.1), (x1 - 0.4, y0 + 0.2, z0 + 0.4), (x1 - 0.4, y0 + 0.2, z1 - 0.4),
                    (x1 - 0.4, y0 + 1.3, z0 + 0.4), (x1 - 0.4, y0 + 1.3, z1 - 0.4)]
            hull(f"{tag}Body", body, "cart", 0.05)
            col(tag, "metal", body)
            box(f"{tag}Mouth", x0 + 0.17, x0 + 0.2, y0 + 0.12, y0 + 1.43, z0 + 0.22, z1 - 0.22, "ink", 0.0)
            for (yy, zz) in ((y0 + 0.4, z0 + 0.7), (y0 + 1.1, z0 + 0.7), (y0 + 0.4, z1 - 0.7), (y0 + 1.1, z1 - 0.7)):
                cyl(f"{tag}Wheel{yy}{zz}", (x1 - 0.25, yy, zz), "x", 0.28, 0.12, "iron", seg=12)
            for c in range(7):
                rng = random.Random(600 + c)
                ox, oz = x0 - rng.uniform(0.2, 1.4), rng.uniform(z0, z1)
                rock(f"{tag}Ore{c}", ox - 0.2, ox + 0.2, y0, 0.25, oz - 0.2, oz + 0.2, 610 + c, mat="coal", sub=1,
                     sink=0.05, collide=False)


def build_greenery():
    """Cactus (collision fine = coins hors des allées) et buissons bas (décor seul)."""
    for k, (x, z, hh) in enumerate(((-31.5, -31.0, 3.4), (31.0, -31.5, 2.8), (-31.0, 31.5, 3.0), (31.5, 30.5, 3.6),
                                    (-30.5, -12.5, 2.6), (30.5, 12.0, 2.5))):
        cyl(f"Cactus{k}", (x, hh / 2, z), "y", 0.36, hh, "cactus", seg=10)
        cyl(f"CactusTop{k}", (x, hh + 0.12, z), "y", 0.36, 0.25, "cactus", seg=10, r2=0.15)
        for s, ya, yb in ((1, hh * 0.45, hh * 0.8), (-1, hh * 0.55, hh * 0.9)):
            cyl(f"CactusArmH{k}{s}", (x + s * 0.55, ya, z), "x", 0.2, 0.8, "cactus_dark", seg=8)
            cyl(f"CactusArmV{k}{s}", (x + s * 0.85, (ya + yb) / 2, z), "y", 0.2, yb - ya, "cactus_dark", seg=8)
        col(f"Cactus{k}", "wood", ring_pts(x, z, 0.4, 0, hh, 8))
    rng = random.Random(21)
    for k in range(26):
        side = rng.choice(((1, 0), (-1, 0), (0, 1), (0, -1)))
        t = rng.uniform(-30, 30)
        x = side[0] * 33.2 if side[0] else t
        z = side[1] * 33.2 if side[1] else t
        if abs(x) < 5 and abs(z) > 30:
            continue
        if abs(z) < 10:
            continue
        r = rng.uniform(0.35, 0.7)
        rock(f"Bush{k}", x - r, x + r, 0, r * 0.9, z - r, z + r, 700 + k, mat="bush", sub=1, rough=0.3, sink=0.1,
             collide=False)


def build_background():
    """Buttes lointaines « pièce montée » : une strate par étage, chaque étage un peu plus étroit
    (corniches horizontales nettes, lisibles en BD) ; pied très bas pour ne jamais flotter."""
    spots = ((-160, -95, 46, 78), (-55, -185, 38, 64), (80, -175, 50, 86), (185, -60, 40, 58), (165, 100, 52, 90),
             (40, 190, 36, 70), (-100, 165, 44, 62), (-200, 45, 34, 54))
    tiers = (("s_dark", 0.0, 0.22, 1.00), ("s_orange", 0.22, 0.40, 0.93), ("s_cream", 0.40, 0.52, 0.88),
             ("s_red", 0.52, 0.80, 0.84), ("s_cream", 0.80, 0.88, 0.76), ("s_red", 0.88, 1.00, 0.72))
    for k, (cx, cz, r, hh) in enumerate(spots):
        n = 12
        radii = [r * (0.78 + 0.22 * math.sin(i * 1.9 + k * 0.7)) for i in range(n)]
        for t, (mat, f0, f1, sc) in enumerate(tiers):
            y0 = -40.0 if t == 0 else hh * f0
            y1 = hh * f1
            pts = []
            for i in range(n):
                a = 2 * math.pi * i / n
                for y in (y0, y1):
                    rr = radii[i] * sc * (1.06 if y == y0 and t > 0 else 1.0)
                    pts.append((cx + rr * math.cos(a), y, cz + rr * math.sin(a)))
            hull(f"Mesa{k}T{t}", pts, mat)


# ---------------------------------------------------------------------------
# Export + aperçus
# ---------------------------------------------------------------------------

def join_by_material():
    groups = {}
    for ob in VIS:
        key = ob.data.materials[0].name if ob.data.materials else "none"
        groups.setdefault(key, []).append(ob)
    out = []
    for key, obs in sorted(groups.items()):
        ob = tk.join(obs)
        ob.name = f"VIS_{key}"
        ob.data.name = f"VIS_{key}"
        out.append(ob)
    return out


def preview(vis):
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_WORKBENCH"
    except TypeError as e:
        print("PREVIEW_SKIP", e)
        return
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_cavity = True
    sh.show_object_outline = True
    sh.object_outline_color = (0.1, 0.06, 0.19)
    if scene.world is None:
        scene.world = bpy.data.worlds.new("PrevWorld")
    scene.world.color = (0.45, 0.68, 0.95)
    for ob in COLS:
        ob.hide_render = True
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    scene.render.film_transparent = False
    cam_data = bpy.data.cameras.new("PrevCam")
    cam_data.lens = 24
    cam_data.clip_end = 800
    cam = bpy.data.objects.new("PrevCam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    shots = (("aerial", (46, 40, 52), (0, -3, 0)), ("spawn_n", (10, 1.7, -29.5), (1, 0.5, 0)),
             ("canyon", (24, -3.3, 2.5), (-6, -2.8, -0.5)), ("walkway", (3.8, 1.7, -12), (3.2, 1.0, 14)),
             ("west", (-26, 1.7, -24), (-14, -1, 4)))
    for nm, eye, tgt in shots:
        cam.location = G(*eye)
        d = G(*tgt) - G(*eye)
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(OUT_PREV, f"canyon_express_blender_{nm}.png")
        bpy.ops.render.render(write_still=True)
        print("PREVIEW_OK", scene.render.filepath)


def main():
    tk.reset_scene()
    build_terrain()
    build_rail()
    build_bridge()
    build_footbridge()
    build_train()
    build_blocks()
    build_greenery()
    build_background()
    vis = join_by_material()
    tris = tk.tri_count(vis)
    print(f"CANYON_STATS visuels={len(vis)} tris={tris} collisions={len(COLS)}")
    tk.export_glb(OUT_GLB, vis + COLS, write_report=False)
    if PREVIEW:
        preview(vis)


main()
