"""Vérifie data/maps/wasteland_plan.json contre les exigences de conception (v6).

python check_plan.py [--md]   -> tableau de résultats (texte ou markdown)
Géométrie : volumes après miroir (fonctions de tools/maps/render_plan.py).
Lignes de vue : segments 3D œil->œil (1,6 m au-dessus du sol du niveau) contre des
boîtes bloquantes ; bâtiments = murs 0,25 m percés de leurs portes (2,4 m) et
fenêtres (allège 1,0, h 1,0), dalles d'étage, toit (demi-hauteur du versant).
"""
from __future__ import annotations

import importlib.util
import itertools
import math
import sys
from pathlib import Path

import numpy as np

ROOT = Path(r"C:/Users/srko/Desktop/fps")
spec = importlib.util.spec_from_file_location("rp", ROOT / "tools/maps/render_plan.py")
rp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rp)

plan = rp.load()
VOLS = rp.normalize(rp.expand(plan))
M = plan["metrics"]
EYE = M["player"]["eye"]
UP = plan["levels"]["upper"]
SPRINT = M["player"]["sprint"]
DOOR_W = {k: v["w"] for k, v in M["doors"].items()}
DOOR_H = M["doors"]["std"]["h"]
WIN = M["window"]
WT = M["wall_t"]
byid = {v["id"]: v for v in VOLS}
RESULTS: list[tuple[str, str, str]] = []


def res(name, ok, detail):
    RESULTS.append((name, "OK" if ok else "ÉCHEC", detail))


# ------------------------------------------------------------------ géométrie de base
def rect(v):
    if "x" in v:
        return (v["x"][0], v["x"][1], v["z"][0], v["z"][1])
    poly = rp.ramp_polygon(v)
    xs, zs = [p[0] for p in poly], [p[1] for p in poly]
    return (min(xs), max(xs), min(zs), max(zs))


def rdist(a, b):
    dx = max(a[0] - b[1], b[0] - a[1], 0.0)
    dz = max(a[2] - b[3], b[2] - a[3], 0.0)
    return math.hypot(dx, dz)


def roverlap_area(a, b):
    dx = min(a[1], b[1]) - max(a[0], b[0])
    dz = min(a[3], b[3]) - max(a[2], b[2])
    return dx * dz if dx > 1e-6 and dz > 1e-6 else 0.0


def seg_len(v):
    return math.dist((v["from"][0], v["from"][2]), (v["to"][0], v["to"][2]))


def opening_span(b, o, is_door):
    x0, x1 = b["x"]
    z0, z1 = b["z"]
    w = DOOR_W.get(o.get("type", "std"), 1.2) if is_door else WIN["w"]
    c = ((x0 + x1) / 2 if o["side"] in "NS" else (z0 + z1) / 2) + o.get("offset", 0.0)
    return c - w / 2, c + w / 2


def storey(b):
    return (b["y"][1] - b["y"][0]) / max(b.get("floors", 1), 1)


# ------------------------------------------------------------------ boîtes bloquantes (vue)
def blockers():
    out = []  # (xmin, ymin, zmin, xmax, ymax, zmax, id)
    for v in VOLS:
        k = v["kind"]
        if k in ("ramp", "barrier", "inv_wall", "clip"):
            continue
        if k == "building":
            out += building_boxes(v)
            continue
        if k == "stairs":
            (xa, ya, za), (xb, yb, zb) = v["from"], v["to"]
            poly = rp.ramp_polygon(v)
            xs, zs = [p[0] for p in poly], [p[1] for p in poly]
            n = 4
            for i in range(n):
                t0, t1 = i / n, (i + 1) / n
                if abs(xb - xa) > abs(zb - za):
                    xx = sorted([xa + (xb - xa) * t0, xa + (xb - xa) * t1])
                    zz = [min(zs), max(zs)]
                else:
                    zz = sorted([za + (zb - za) * t0, za + (zb - za) * t1])
                    xx = [min(xs), max(xs)]
                top = ya + (yb - ya) * ((t0 + t1) / 2 if yb > ya else 1 - (t0 + t1) / 2)
                out.append((xx[0], min(ya, yb), zz[0], xx[1], top, zz[1], v["id"]))
            continue
        if "x" not in v:
            continue
        y0, y1 = v["y"]
        if k == "slab" and v.get("solid_below"):
            y0 = min(y0, 0.0)
        out.append((v["x"][0], y0, v["z"][0], v["x"][1], y1, v["z"][1], v["id"]))
    return out


def building_boxes(b):
    x0, x1 = b["x"]
    z0, z1 = b["z"]
    y0, y1 = b["y"]
    fh = storey(b)
    boxes = []
    for side in "NSWE":
        ops = []
        for o in b.get("doors", []):
            if o["side"] == side:
                a, c = opening_span(b, o, True)
                fy = y0 + o.get("floor", 0) * fh
                ops.append((a, c, fy, fy + DOOR_H))
        for o in b.get("windows", []):
            if o["side"] == side:
                a, c = opening_span(b, o, False)
                fy = y0 + o.get("floor", 0) * fh
                ops.append((a, c, fy + WIN["sill"], fy + WIN["sill"] + WIN["h"]))
        lo, hi = (x0, x1) if side in "NS" else (z0, z1)
        cuts = sorted({lo, hi, *[max(lo, min(hi, o[0])) for o in ops], *[max(lo, min(hi, o[1])) for o in ops]})
        for a, c in zip(cuts, cuts[1:]):
            if c - a < 1e-6:
                continue
            m = (a + c) / 2
            holes = sorted((o[2], o[3]) for o in ops if o[0] < m < o[1])
            ys, cur = [], y0
            for h0, h1 in holes:
                if h0 > cur:
                    ys.append((cur, h0))
                cur = max(cur, h1)
            if cur < y1:
                ys.append((cur, y1))
            for ya, yb in ys:
                if side == "N":
                    boxes.append((a, ya, z0, c, yb, z0 + WT, b["id"]))
                elif side == "S":
                    boxes.append((a, ya, z1 - WT, c, yb, z1, b["id"]))
                elif side == "W":
                    boxes.append((x0, ya, a, x0 + WT, yb, c, b["id"]))
                else:
                    boxes.append((x1 - WT, ya, a, x1, yb, c, b["id"]))
    for f in range(1, b.get("floors", 1)):
        fy = y0 + f * fh
        boxes.append((x0, fy - M["slab_t"], z0, x1, fy, z1, b["id"]))
    pitch = b.get("roof", {}).get("pitch_deg", M["roof"]["pitch_deg"])
    rise = min(M["roof"]["max_rise"], (z1 - z0) / 2 * math.tan(math.radians(pitch)))
    boxes.append((x0, y1, z0, x1, y1 + rise / 2, z1, b["id"]))
    return boxes


def kit_ramps():
    """Rampes intérieures posées par Kit.building2 (trémie 2 x min(6, prof-1,5) contre stair_side, rampe 1,6 m)."""
    out = []
    for b in VOLS:
        if b["kind"] != "building" or b.get("floors", 1) < 2:
            continue
        x0, x1 = b["x"]
        z0, z1 = b["z"]
        fh = storey(b)
        side = b.get("stair_side", "N")
        cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        hw = M["inner_stair"]["ramp_w"] / 2
        if side in "NS":
            d = min(M["inner_stair"]["hole_d"], z1 - z0 - M["inner_stair"]["landing_margin"])
            lo, hi = (z0, z0 + d) if side == "N" else (z1, z1 - d)
            for i in range(4):
                a, c = lo + (hi - lo) * i / 4, lo + (hi - lo) * (i + 1) / 4
                out.append((cx - hw, b["y"][0], min(a, c), cx + hw, b["y"][0] + fh * (i + 0.5) / 4, max(a, c), b["id"] + "/rampe"))
        else:
            d = min(M["inner_stair"]["hole_d"], x1 - x0 - M["inner_stair"]["landing_margin"])
            lo, hi = (x0, x0 + d) if side == "W" else (x1, x1 - d)
            for i in range(4):
                a, c = lo + (hi - lo) * i / 4, lo + (hi - lo) * (i + 1) / 4
                out.append((min(a, c), b["y"][0], cz - hw, max(a, c), b["y"][0] + fh * (i + 0.5) / 4, cz + hw, b["id"] + "/rampe"))
    return out


BOX = np.array([b[:6] for b in blockers() + kit_ramps()], dtype=float)


def los(p, q):
    """p, q : (N,3) -> bool (N,) : vrai si aucune boîte ne coupe le segment."""
    p = np.atleast_2d(p).astype(float)
    q = np.atleast_2d(q).astype(float)
    d = q - p
    vis = np.ones(len(p), dtype=bool)
    with np.errstate(divide="ignore", invalid="ignore"):
        inv = 1.0 / d
        for bx in BOX:
            t1 = (bx[:3] - p) * inv
            t2 = (bx[3:] - p) * inv
            tmin = np.where(np.isnan(t1), -np.inf, np.minimum(t1, t2))
            tmax = np.where(np.isnan(t1), np.inf, np.maximum(t1, t2))
            par = d == 0
            outside = par & ((p < bx[:3]) | (p > bx[3:]))
            tmin = np.where(par, -np.inf, tmin)
            tmax = np.where(par, np.inf, tmax)
            enter = tmin.max(axis=1)
            leave = tmax.min(axis=1)
            hit = (leave >= np.maximum(enter, 0.0)) & (enter <= 1.0) & (leave > 1e-6) & ~outside.any(axis=1)
            vis &= ~hit
    return vis


# ------------------------------------------------------------------ sol / points
NOTCH = [rect(v) for v in VOLS if v["kind"] == "ramp"]
GROUND_OBS_KINDS = ("building", "solid", "cover", "rock", "wall", "stairs", "boundary")


def ground_y(x, z):
    for r in NOTCH:
        if r[0] <= x <= r[1] and r[2] <= z <= r[3]:
            return -2.0 * (z - r[2]) / (r[3] - r[2])
    return -2.0 if z > 13.0 else 0.0


def occupied(x, z, level):
    for v in VOLS:
        k = v["kind"]
        if k not in GROUND_OBS_KINDS + ("fence", "slab"):
            continue
        if k == "slab" and not v.get("solid_below"):
            continue
        if k == "fence" and v.get("class") == "rail":
            continue
        if k == "stairs":
            lo, hi = min(v["from"][1], v["to"][1]), max(v["from"][1], v["to"][1])
        else:
            lo, hi = v["y"]
            if k == "slab":
                lo = min(lo, 0.0)
        if hi <= level + 0.05 or lo >= level + 1.8:
            continue
        r = rect(v)
        if r[0] - 0.4 <= x <= r[1] + 0.4 and r[2] - 0.4 <= z <= r[3] + 0.4:
            return True
    return False


def region_points(reg, step=1.0):
    pts = []
    lvl = reg["level"]
    for x in np.arange(reg["x"][0] + 0.5, reg["x"][1], step):
        for z in np.arange(reg["z"][0] + 0.5, reg["z"][1], step):
            gy = ground_y(x, z)
            if abs(gy - lvl) > 0.05 or occupied(x, z, lvl):
                continue
            pts.append((x, lvl + EYE, z))
    return np.array(pts)


def max_sight(pts, mask_pairs=None):
    n = len(pts)
    i, j = np.triu_indices(n, 1)
    dd = np.linalg.norm(pts[i][:, [0, 2]] - pts[j][:, [0, 2]], axis=1)
    order = np.argsort(-dd)
    for s in range(0, len(order), 20000):
        idx = order[s:s + 20000]
        vis = los(pts[i[idx]], pts[j[idx]])
        if vis.any():
            k = idx[vis][0]
            return dd[k], pts[i[k]], pts[j[k]]
    return 0.0, None, None


# ------------------------------------------------------------------ 1. empreinte
bx, bz = plan["bounds"]["x"], plan["bounds"]["z"]
W, D = bx[1] - bx[0], bz[1] - bz[0]
res("Empreinte 4v4 (70–85 × 45–55 m)", 70 <= W <= 85 and 45 <= D <= 55, f"{W:g} × {D:g} m = {W * D:g} m²")

# ------------------------------------------------------------------ 2. bâtiments traversants
blds = [v for v in VOLS if v["kind"] == "building"]
bad = []
det = []
for b in blds:
    sides = {d["side"] for d in b.get("doors", []) if d.get("floor", 0) == 0}
    det.append(f"{b['id']} {''.join(sorted(sides))}")
    if len(sides) < 2:
        bad.append(b["id"])
res("Bâtiments : ≥ 2 entrées RDC sur côtés différents", not bad,
    ("manquant : " + ", ".join(bad) + " ; ") if bad else "" + "; ".join(det))
bad = [b["id"] for b in blds if b.get("floors", 1) >= 2 and any(
    d["side"] == b.get("stair_side", "N") and d.get("floor", 0) == 0 for d in b.get("doors", []))]
res("Trémie (stair_side) sur un côté sans porte RDC", not bad, ", ".join(bad) or "toutes conformes")

# ------------------------------------------------------------------ 3. étages : graphe
nodes = {}
for b in blds:
    if b.get("floors", 1) >= 2:
        nodes[f"{b['id']}/étage"] = ("bld", b)
for v in VOLS:
    if v["kind"] == "slab" and abs(v["y"][1] - UP) < 0.05:
        nodes[v["id"]] = ("slab", v)
edges = set()
ground_access = {k: [] for k in nodes}


def door_seg(b, d):
    a, c = opening_span(b, d, True)
    x0, x1 = b["x"]
    z0, z1 = b["z"]
    s = d["side"]
    if s == "N":
        return (a, c, z0, z0)
    if s == "S":
        return (a, c, z1, z1)
    if s == "W":
        return (x0, x0, a, c)
    return (x1, x1, a, c)


for kb, (tb, b) in nodes.items():
    if tb != "bld":
        continue
    ground_access[kb].append(f"rampe intérieure {b['id']}")
    for d in b.get("doors", []):
        if d.get("floor", 0) != 1:
            continue
        ds = door_seg(b, d)
        for ks, (ts, s) in nodes.items():
            if ks == kb:
                continue
            if ts == "slab":
                r = rect(s)
                if rdist(r, ds) < 0.05 and (min(r[1], ds[1]) - max(r[0], ds[0]) > 0.5 or min(r[3], ds[3]) - max(r[2], ds[2]) > 0.5):
                    edges.add(frozenset((kb, ks)))
            else:
                for d2 in s.get("doors", []):
                    if d2.get("floor", 0) == 1 and rdist(door_seg(s, d2), ds) < 0.3:
                        edges.add(frozenset((kb, ks)))
slabs = [k for k, (t, _) in nodes.items() if t == "slab"]
for a, c in itertools.combinations(slabs, 2):
    if rdist(rect(nodes[a][1]), rect(nodes[c][1])) < 0.05:
        edges.add(frozenset((a, c)))
for v in VOLS:
    if v["kind"] != "stairs":
        continue
    top = v["to"] if v["to"][1] > v["from"][1] else v["from"]
    for k, (t, s) in nodes.items():
        r = rect(s)
        if r[0] - 0.3 <= top[0] <= r[1] + 0.3 and r[2] - 0.3 <= top[2] <= r[3] + 0.3:
            ground_access[k].append(v["id"])


def comp(start):
    seen, st = {start}, [start]
    while st:
        n = st.pop()
        for e in edges:
            if n in e:
                (o,) = e - {n}
                if o not in seen:
                    seen.add(o)
                    st.append(o)
    return seen


bad, det = [], []
for k, (t, b) in nodes.items():
    if t != "bld":
        continue
    c = comp(k)
    acc = sorted({a for n in c for a in ground_access[n]})
    own = len(ground_access[k]) + sum(1 for e in edges if k in e)
    ok = len(acc) >= 2 and own >= 2 and len(c) >= 2
    det.append(f"{b['id']} : {own} entrées d'étage, {len(acc)} accès depuis le sol dans son réseau, relié à {len(c) - 1} espace(s)")
    if not ok:
        bad.append(b["id"])
res("Étages : ≥ 2 routes + relié à un autre espace haut", not bad, "; ".join(det))
net = comp(next(iter(nodes)))
res("Réseau haut ouest+centre+est connexe", len(net) == len(nodes),
    f"{len(net)}/{len(nodes)} espaces hauts dans un seul réseau")

# ------------------------------------------------------------------ 4. écarts
def obstacles(level):
    obs = []
    for v in VOLS:
        k = v["kind"]
        if k in ("ground", "ramp", "barrier", "inv_wall", "clip"):
            continue
        if k == "slab" and not v.get("solid_below"):
            continue
        if k == "landmark":
            continue
        if k == "stairs":
            lo = min(v["from"][1], v["to"][1])
        elif "y" in v:
            lo = v["y"][0]
        else:
            continue
        if abs(lo - level) > 0.3 and not (k == "boundary"):
            continue
        if k == "fence" and v.get("class") == "rail":
            continue
        obs.append((v["id"], rect(v), v))
    if level < -1:
        for v in VOLS:  # bord du plateau vu depuis la carrière
            if v["kind"] == "ground" and v["y"][1] == 0.0 and v["z"][1] >= 12.9:
                obs.append((v["id"], rect(v), v))
    return obs


TIGHT_OK = set()  # paires volontairement serrées (2–3 m)
fails, tight, overlaps = [], [], []
minimum = (99, "")
for level in (0.0, -2.0):
    obs = obstacles(level)
    for (ia, ra, va), (ib, rb, vb) in itertools.combinations(obs, 2):
        g = rdist(ra, rb)
        if g < 1e-6:
            a = roverlap_area(ra, rb)
            if a > 0.01 and not ({va["kind"], vb["kind"]} <= {"building", "wall"}) and not (
                    "stairs" in (va["kind"], vb["kind"]) and "slab" in (va["kind"], vb["kind"])):
                overlaps.append(f"{ia}/{ib} ({a:.2f} m²)")
            continue
        if g < minimum[0]:
            minimum = (g, f"{ia} ↔ {ib}")
        if g < 2.0:
            fails.append(f"{ia} ↔ {ib} {g:.2f} m")
        elif g < 3.0:
            (tight if frozenset((ia, ib)) in TIGHT_OK else fails).append(f"{ia} ↔ {ib} {g:.2f} m")
res("Écart libre ≥ 3 m entre obstacles (2 m si serré voulu)", not fails,
    ("; ".join(fails[:12]) + (" …" if len(fails) > 12 else "")) if fails else
    f"plus petit écart {minimum[0]:.2f} m ({minimum[1]}) ; serrés voulus : {len(tight)}")
res("Aucun volume qui se chevauche", not overlaps, "; ".join(overlaps[:10]) or "aucun")

# ------------------------------------------------------------------ 5. rampes / escaliers
bad, det = [], []
for v in VOLS:
    if v["kind"] not in ("ramp", "stairs"):
        continue
    w = v["w"]
    need_w = 4.0 if v["kind"] == "ramp" else M["stair"]["width_min"]
    (xa, ya, za), (xb, yb, zb) = v["from"], v["to"]
    L = seg_len(v)
    ux, uz = (xb - xa) / L, (zb - za) / L
    ok = w >= need_w - 1e-6
    for (px, py, pz), sgn in (((xa, ya, za), -1), ((xb, yb, zb), 1)):
        # zone de 3 m dans le prolongement (seulement au niveau bas pour un escalier : au palier haut, espace haut)
        if v["kind"] == "stairs" and py > 0.5:
            continue
        cx, cz = px + sgn * ux * 1.5, pz + sgn * uz * 1.5
        hx = abs(ux) * 1.5 + abs(uz) * w / 2
        hz = abs(uz) * 1.5 + abs(ux) * w / 2
        zone = (cx - hx + 0.01, cx + hx - 0.01, cz - hz + 0.01, cz + hz - 0.01)
        for (io, ro, vo) in obstacles(0.0 if py > -1 else -2.0):
            if io == v["id"]:
                continue
            if roverlap_area(zone, ro) > 0:
                ok = False
                det.append(f"{v['id']} : bout encombré par {io}")
                break
    if not ok:
        bad.append(v["id"])
ramps = [v for v in VOLS if v["kind"] == "ramp"]
res("Rampes ≥ 4 m de large, 3 m dégagés aux deux bouts (escaliers : pied dégagé 3 m)", not bad,
    "; ".join(det) or f"{len(ramps)} rampes l = " + ", ".join(sorted({f'{v['w']:g}' for v in ramps})) + " m")

# ------------------------------------------------------------------ 6. place
pz = plan["plaza"]
pr = (pz["x"][0], pz["x"][1], pz["z"][0], pz["z"][1])
inside = [v for v in VOLS if v["kind"] not in ("ground", "slab", "landmark") and "x" in v or v["kind"] == "fence"]
bad = []
for v in VOLS:
    if v["kind"] in ("ground", "boundary", "ramp", "landmark") or (v["kind"] == "slab" and not v.get("solid_below")):
        continue
    if v["kind"] == "fence" and v.get("class") == "rail":
        continue
    if roverlap_area(rect(v), pr) <= 0:
        continue
    if v["id"] == pz["centerpiece"]:
        continue
    if v["kind"] == "cover" and v.get("class") in ("C1", "C2"):
        continue
    bad.append(v["id"])
cp = byid[pz["centerpiece"]]
cps = {d["side"] for d in cp["doors"]}
through = ("N" in cps and "S" in cps) or ("W" in cps and "E" in cps)
res("Place ≥ 20 × 14 m, couverts C1/C2 seulement, pièce centrale traversante",
    not bad and through and (pr[1] - pr[0]) >= 20 and (pr[3] - pr[2]) >= 14,
    f"{pr[1] - pr[0]:g} × {pr[3] - pr[2]:g} m ; centre {cp['id']} portes {''.join(sorted(cps))}"
    + (" ; intrus : " + ", ".join(bad) if bad else ""))

# ------------------------------------------------------------------ 7. carrière
cz = [v for v in VOLS if v["id"] == "G_Carriere"][0]
width = cz["z"][1] - cz["z"][0]
cobs = [(v["id"], rect(v)) for v in VOLS if v["kind"] in ("rock", "cover") and v["y"][0] <= -1.9]
nn = []
for ia, ra in cobs:
    d = min(rdist(ra, rb) for ib, rb in cobs if ib != ia)
    nn.append((ia, d))
spacing_ok = all(5.0 - 1e-6 <= d <= 8.0 + 1e-6 for _, d in nn)
half_ramps = [v for v in ramps if v["from"][0] < 0 and -30 < v["from"][0]]
res("Carrière ≥ 10 m, couverts espacés 5–8 m, 2 rampes larges/moitié vers le centre",
    width >= 10 and spacing_ok and len(half_ramps) >= 2,
    f"largeur {width:g} m ; plus proche voisin : " + ", ".join(f"{i} {d:.1f}" for i, d in nn)
    + f" ; rampes moitié O vers le centre : {', '.join(v['id'] for v in half_ramps)}")

# ------------------------------------------------------------------ 8. lignes de vue
for reg in plan["sight_regions"]:
    pts = region_points(reg)
    d, a, b = max_sight(pts)
    res(f"Vue max « {reg['id']} » ≤ {reg['cap']:g} m", d <= reg["cap"] + 1e-6,
        f"{d:.1f} m ({len(pts)} points) entre ({a[0]:.1f}, {a[2]:.1f}) et ({b[0]:.1f}, {b[2]:.1f})" if a is not None else "aucune")

# apparitions : aucune vue vers la moitié adverse
sp = [s["pos"] for s in plan["markers"]["team_spawns"]]
spts = np.array([(p[0], p[1] + EYE, p[2]) for p in sp])
far = []
for reg in ({"level": 0.0, "x": [2.0, 42.0], "z": [-25.0, 13.0]}, {"level": -2.0, "x": [2.0, 42.0], "z": [13.0, 25.0]}):
    far.append(region_points(reg, 1.5))
far = np.vstack(far)
up_pts = []
for k, (t, s) in nodes.items():
    r = rect(s)
    if r[0] > 2:
        for x in np.arange(r[0] + 0.5, r[1], 1.5):
            for z in np.arange(r[2] + 0.5, r[3], 1.5):
                up_pts.append((x, UP + EYE, z))
far = np.vstack([far, np.array(up_pts)])
seen = 0
closest = None
for s in spts:
    vis = los(np.repeat(s[None], len(far), 0), far)
    seen += int(vis.sum())
    if vis.any():
        dd = np.linalg.norm(far[vis][:, [0, 2]] - s[[0, 2]], axis=1)
        k = int(np.argmin(dd))
        cand = (dd[k], far[vis][k])
        closest = cand if closest is None or cand[0] < closest[0] else closest
        if "--dbg" in sys.argv:
            for q in far[vis][:40]:
                print("  spawn", s[[0, 2]], "->", np.round(q, 1))
res("Apparitions : aucune vue sur la moitié adverse (x > 2)", seen == 0,
    "aucune ligne" if seen == 0 else f"{seen} lignes ; la plus courte {closest[0]:.1f} m vers ({closest[1][0]:.1f}, {closest[1][1] - EYE:.1f}, {closest[1][2]:.1f})")

# ------------------------------------------------------------------ 9. sorties et premier contact
def route_pts(lane):
    pts = []
    for x, z in lane["route_w"]:
        pts.append((x, ground_y(x, z), z))
    return pts


def at(route, s):
    acc = 0.0
    for a, b in zip(route, route[1:]):
        L = math.dist((a[0], a[2]), (b[0], b[2]))
        if acc + L >= s:
            t = (s - acc) / L if L else 0
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)
        acc += L
    return route[-1]


def rlen(route):
    return sum(math.dist((a[0], a[2]), (b[0], b[2])) for a, b in zip(route, route[1:]))


lanes = plan["lanes"]
R = {ln["id"]: route_pts(ln) for ln in lanes}
first = {}
lines = []
for ia, ib in itertools.product(R, R):
    ra, rb = R[ia], R[ib]
    t_hit = None
    run = 0
    for step in range(0, 131):
        t = step * 0.1
        pa = at(ra, t * SPRINT)
        pb = at(rb, t * SPRINT)
        pb = (-pb[0], pb[1], pb[2])
        if los(np.array([[pa[0], pa[1] + EYE, pa[2]]]), np.array([[pb[0], pb[1] + EYE, pb[2]]]))[0]:
            run += 1
            if run == 5:  # vue tenue 0,5 s = contact (un aperçu par une porte ne compte pas)
                t_hit = round(t - 0.4, 1)
                break
        else:
            run = 0
    first[(ia, ib)] = t_hit
    if "--dbg" in sys.argv and t_hit is not None:
        print("  contact", ia, ib, t_hit, np.round(pa, 1), np.round(pb, 1))
exits = {ln["id"]: tuple(ln["route_w"][1]) for ln in lanes}
det = []
ok = True
for ln in lanes:
    L = rlen(R[ln["id"]])
    t_same = first[(ln["id"], ln["id"])]
    t_any = min((first[(ln["id"], o)] for o in R if first[(ln["id"], o)] is not None), default=None)
    det.append(f"{ln['label']} : route {L:.1f} m ({L / SPRINT:.1f} s) ; contact même couloir {t_same if t_same is not None else '>12'} s ; "
               f"tout couloir {t_any if t_any is not None else '>12'} s")
    if t_any is None or not (5.0 <= t_any <= 8.0 + 1e-6):
        ok = False
res("3 sorties d'apparition distinctes → 3 couloirs ; premier contact 5–8 s au sprint",
    ok and len(set(exits.values())) == 3, " | ".join(det))

# ------------------------------------------------------------------ sortie
md = "--md" in sys.argv
if md:
    print("| Contrôle | Résultat | Détail |")
    print("|---|---|---|")
    for n, r, d in RESULTS:
        print(f"| {n} | {r} | {d} |")
else:
    for n, r, d in RESULTS:
        print(f"[{r}] {n}\n      {d}")
