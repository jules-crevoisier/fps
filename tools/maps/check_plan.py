"""Vérifie data/maps/wasteland_plan.json contre les exigences de conception (v7, carte asymétrique).

python tools/maps/check_plan.py [--md] [--dbg]   -> tableau de résultats (texte ou markdown)

Géométrie : volumes via tools/maps/render_plan.py (miroir si mirror.enabled, sinon W/C/E explicites).
Sol : surfaces « ground » et « platform » (dessus marchable), rampes interpolées.
Lignes de vue : segments 3D œil->œil (1,6 m au-dessus du sol du point) contre des boîtes
bloquantes ; bâtiments = murs 0,25 m percés de leurs portes (2,4 m) et fenêtres (allège 1,0,
h 1,0), dalles d'étage, toit (demi-hauteur du versant), rampes intérieures du Kit.

Règles v6 conservées : bâtiments traversants, étages (2 routes + reliés), réseau haut connexe,
écarts ≥ 3 m (2 m si serré voulu), pas de chevauchement, rampes ≥ 4 m + 3 m dégagés, place
≥ 280 m² (C1/C2 seulement + pièce centrale traversante), canyon ≥ 10 m, plafonds de vue par
couloir, apparitions invisibles depuis la moitié adverse, 3 sorties + premier contact 5–8 s.
Règles d'équilibre v7 (équipe 0 = ouest, équipe 1 = est) : temps de sprint apparition -> front
par couloir à ±10 % ; premier contact par couloir à ±10 % ; positions fortes surélevées en même
nombre, chacune avec ≥ 2 répliques visibles d'au moins 45° d'écart ; plus longue ligne de vue
interne à chaque moitié, par couloir, à ±15 % ; surface marchable par moitié à ±10 %.
"""
from __future__ import annotations

import importlib.util
import itertools
import math
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
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
SURF = ("ground", "platform")
byid = {v["id"]: v for v in VOLS}
RESULTS: list[tuple[str, str, str]] = []
DBG = "--dbg" in sys.argv


def res(name, ok, detail):
    RESULTS.append((name, "OK" if ok else "ÉCHEC", detail))


def ratio(a, b):
    lo, hi = min(a, b), max(a, b)
    return hi / lo if lo > 1e-9 else float("inf")


def pct(a, b):
    return f"{(ratio(a, b) - 1) * 100:.1f} %"


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


def half_of(x):
    return "W" if x < 0 else "E"


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
                top = ya + (yb - ya) * (t0 + t1) / 2
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
    for fl in range(1, b.get("floors", 1)):
        fy = y0 + fl * fh
        boxes.append((x0, fy - M["slab_t"], z0, x1, fy, z1, b["id"]))
    pitch = b.get("roof", {}).get("pitch_deg", M["roof"]["pitch_deg"])
    rise = min(M["roof"]["max_rise"], (z1 - z0) / 2 * math.tan(math.radians(pitch)))
    boxes.append((x0, y1, z0, x1, y1 + max(rise / 2, 0.05), z1, b["id"]))
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


BOXES = blockers() + kit_ramps()
BOX = np.array([b[:6] for b in BOXES], dtype=float)


def los(p, q, boxes=None):
    """p, q : (N,3) -> bool (N,) : vrai si aucune boîte ne coupe le segment."""
    boxes = BOX if boxes is None else boxes
    p = np.atleast_2d(p).astype(float)
    q = np.atleast_2d(q).astype(float)
    d = q - p
    vis = np.ones(len(p), dtype=bool)
    with np.errstate(divide="ignore", invalid="ignore"):
        inv = 1.0 / d
        par = d == 0
        for bx in boxes:
            t1 = (bx[:3] - p) * inv
            t2 = (bx[3:] - p) * inv
            tmin = np.where(par, -np.inf, np.minimum(t1, t2))
            tmax = np.where(par, np.inf, np.maximum(t1, t2))
            outside = par & ((p < bx[:3]) | (p > bx[3:]))
            enter = tmin.max(axis=1)
            leave = tmax.min(axis=1)
            hit = (leave >= np.maximum(enter, 0.0)) & (enter <= 1.0) & (leave > 1e-6) & ~outside.any(axis=1)
            vis &= ~hit
    return vis


def blocker_of(p, q):
    """Premier volume qui coupe p->q (débogage)."""
    for i, bx in enumerate(BOX):
        if not los(p, q, bx[None])[0]:
            return BOXES[i][6]
    return None


# ------------------------------------------------------------------ sol / points
RAMPS_ = [v for v in VOLS if v["kind"] == "ramp"]
SURFS = [v for v in VOLS if v["kind"] in SURF]


def in_ramp(v, x, z):
    (xa, ya, za), (xb, yb, zb) = v["from"], v["to"]
    L = math.hypot(xb - xa, zb - za)
    ux, uz = (xb - xa) / L, (zb - za) / L
    t = ((x - xa) * ux + (z - za) * uz) / L
    s = -(x - xa) * uz + (z - za) * ux
    if -1e-6 <= t <= 1 + 1e-6 and abs(s) <= v["w"] / 2 + 1e-6:
        return ya + (yb - ya) * min(max(t, 0.0), 1.0)
    return None


def ground_y(x, z):
    """Hauteur du sol marchable en (x, z) : rampe si dedans, sinon dessus le plus haut des surfaces."""
    for v in RAMPS_:
        y = in_ramp(v, x, z)
        if y is not None:
            return y
    best = None
    for v in SURFS:
        if v["x"][0] <= x <= v["x"][1] and v["z"][0] <= z <= v["z"][1]:
            best = v["y"][1] if best is None else max(best, v["y"][1])
    return best


OBS_KINDS = ("building", "solid", "cover", "rock", "wall", "stairs", "boundary", "fence", "slab") + SURF


def occupied(x, z, level):
    for v in VOLS:
        k = v["kind"]
        if k not in OBS_KINDS:
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
        if k in SURF and hi <= level + 0.5:
            continue  # surface au niveau (ou plus bas) : pas un obstacle
        if hi <= level + 0.05 or lo >= level + 1.8:
            continue
        r = rect(v)
        if r[0] - 0.4 <= x <= r[1] + 0.4 and r[2] - 0.4 <= z <= r[3] + 0.4:
            return True
    return False


def in_rects(x, z, rects):
    return any(r["x"][0] <= x <= r["x"][1] and r["z"][0] <= z <= r["z"][1] for r in rects)


def region_points(reg, step=1.0):
    """Points œil (x, sol + 1,6, z) d'une région : rects (union) et niveaux de sol admis."""
    rects = reg.get("rects") or [{"x": reg["x"], "z": reg["z"]}]
    levels = reg.get("levels", [reg.get("level", 0.0)])
    xs = [r["x"][0] for r in rects] + [r["x"][1] for r in rects]
    zs = [r["z"][0] for r in rects] + [r["z"][1] for r in rects]
    pts = []
    for x in np.arange(min(xs) + step / 2, max(xs), step):
        for z in np.arange(min(zs) + step / 2, max(zs), step):
            if not in_rects(x, z, rects):
                continue
            gy = ground_y(x, z)
            if gy is None or not any(abs(gy - lv) < 0.05 for lv in levels) or occupied(x, z, gy):
                continue
            pts.append((x, gy + EYE, z))
    return np.array(pts)


def max_sight(pts, pair_mask=None):
    n = len(pts)
    if n < 2:
        return 0.0, None, None
    i, j = np.triu_indices(n, 1)
    if pair_mask is not None:
        keep = pair_mask(pts[i], pts[j])
        i, j = i[keep], j[keep]
    dd = np.linalg.norm(pts[i][:, [0, 2]] - pts[j][:, [0, 2]], axis=1)
    order = np.argsort(-dd)
    for s in range(0, len(order), 20000):
        idx = order[s:s + 20000]
        vis = los(pts[i[idx]], pts[j[idx]])
        if vis.any():
            k = idx[vis][0]
            return dd[k], pts[i[k]], pts[j[k]]
    return 0.0, None, None


def fmt_pt(p):
    return f"({p[0]:.1f}, {p[1] - EYE:.1f}, {p[2]:.1f})"


# ------------------------------------------------------------------ 1. empreinte
bx, bz = plan["bounds"]["x"], plan["bounds"]["z"]
W, D = bx[1] - bx[0], bz[1] - bz[0]
res("Empreinte 4v4 (70–85 × 45–55 m)", 70 <= W <= 85 and 45 <= D <= 55, f"{W:g} × {D:g} m = {W * D:g} m²")
res("Carte asymétrique (aucun volume reflété)", not rp.mirrored(plan),
    f"{sum(1 for v in VOLS if v.get('half') == 'W')} volumes W, {sum(1 for v in VOLS if v.get('half') == 'E')} E, "
    f"{sum(1 for v in VOLS if v.get('half') == 'C')} C")

# ------------------------------------------------------------------ 2. bâtiments traversants
blds = [v for v in VOLS if v["kind"] == "building"]
bad, det = [], []
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
        if abs(top[1] - UP) < 0.05 and r[0] - 0.3 <= top[0] <= r[1] + 0.3 and r[2] - 0.3 <= top[2] <= r[3] + 0.3:
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
    det.append(f"{b['id']} {own}")
    if not ok:
        bad.append(b["id"])
res("Étages : ≥ 2 routes + relié à un autre espace haut", not bad,
    ("en défaut : " + ", ".join(bad) + " ; ") * bool(bad) + "entrées d'étage : " + ", ".join(det))
net = comp(next(iter(nodes)))
acc_all = sorted({a for n in net for a in ground_access[n]})
res("Réseau haut ouest + centre + est connexe", len(net) == len(nodes),
    f"{len(net)}/{len(nodes)} espaces hauts dans un seul réseau, {len(acc_all)} accès depuis le sol"
    + ("" if len(net) == len(nodes) else " ; hors réseau : " + ", ".join(sorted(set(nodes) - net))))


# ------------------------------------------------------------------ 4. écarts
def vbottom(v):
    if v["kind"] == "stairs":
        return min(v["from"][1], v["to"][1])
    return v["y"][0] if "y" in v else None


def obstacles(level):
    """Obstacles au sol du niveau : volumes posés à ce niveau + surfaces qui le dominent (paroi)."""
    obs = []
    for v in VOLS:
        k = v["kind"]
        if k in ("ramp", "barrier", "inv_wall", "clip", "landmark"):
            continue
        if k == "slab" and not v.get("solid_below"):
            continue
        if k == "fence" and v.get("class") == "rail":
            continue
        lo = vbottom(v)
        if lo is None:
            continue
        if k in SURF:
            if v["y"][1] >= level + 0.5 and lo <= level + 0.3:
                obs.append((v["id"], rect(v), v))
            continue
        if k == "boundary" or abs(lo - level) <= 0.3:
            obs.append((v["id"], rect(v), v))
    return obs


def gap_mid(a0, a1, b0, b1):
    """Milieu de l'écart entre deux intervalles (ou de leur recouvrement)."""
    if a1 < b0:
        return (a1 + b0) / 2
    if b1 < a0:
        return (b1 + a0) / 2
    return (max(a0, b0) + min(a1, b1)) / 2


LEVELS = sorted({plan["levels"]["canyon"], plan["levels"]["ground"], plan["levels"].get("dock", 0.0)})
TIGHT_OK = set()  # paires volontairement serrées (2–3 m)
fails, tight, overlaps = [], [], []
minimum = (99, "")
for level in LEVELS:
    obs = obstacles(level)
    for (ia, ra, va), (ib, rb, vb) in itertools.combinations(obs, 2):
        g = rdist(ra, rb)
        if g < 1e-6:
            a = roverlap_area(ra, rb)
            kinds = {va["kind"], vb["kind"]}
            if a > 0.01 and not (kinds <= {"building", "wall"}) and not (kinds <= set(SURF)) \
                    and not ("stairs" in kinds and "slab" in kinds):
                overlaps.append(f"{ia}/{ib} ({a:.2f} m² au niveau {level:g})")
            continue
        if va["kind"] in SURF and vb["kind"] in SURF:
            continue  # deux parois de sol : l'écart est un passage mesuré par le canyon
        mx = gap_mid(ra[0], ra[1], rb[0], rb[1])
        mz = gap_mid(ra[2], ra[3], rb[2], rb[3])
        gm = ground_y(mx, mz)
        if gm is None or abs(gm - level) > 0.3:
            continue  # l'écart n'est pas un passage à ce niveau (sol plus haut, ou vide)
        if g < minimum[0]:
            minimum = (g, f"{ia} ↔ {ib}")
        if g < 2.0:
            fails.append(f"{ia} ↔ {ib} {g:.2f} m")
        elif g < 3.0:
            (tight if frozenset((ia, ib)) in TIGHT_OK else fails).append(f"{ia} ↔ {ib} {g:.2f} m")
res("Écart libre ≥ 3 m entre obstacles (2 m si serré voulu)", not fails,
    ("; ".join(fails[:14]) + (" …" if len(fails) > 14 else "")) if fails else
    f"plus petit écart {minimum[0]:.2f} m ({minimum[1]}) ; serrés voulus : {len(tight)} ; niveaux {LEVELS}")
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
        if v["kind"] == "stairs" and py > max(ya, yb) - 0.05:
            continue  # palier haut : c'est l'espace desservi
        cx, cz = px + sgn * ux * 1.5, pz + sgn * uz * 1.5
        hx = abs(ux) * 1.5 + abs(uz) * w / 2
        hz = abs(uz) * 1.5 + abs(ux) * w / 2
        zone = (cx - hx + 0.01, cx + hx - 0.01, cz - hz + 0.01, cz + hz - 0.01)
        for (io, ro, vo) in obstacles(py):
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
    "; ".join(det) or f"{len(ramps)} rampes l = " + ", ".join(sorted({f'{v['w']:g}' for v in ramps})) + " m ; "
    f"{sum(1 for v in VOLS if v['kind'] == 'stairs')} escaliers")

# ------------------------------------------------------------------ 6. place
pz = plan["plaza"]
prs = [(r["x"][0], r["x"][1], r["z"][0], r["z"][1]) for r in pz.get("rects", [])] or \
      [(pz["x"][0], pz["x"][1], pz["z"][0], pz["z"][1])]
area = sum((r[1] - r[0]) * (r[3] - r[2]) for r in prs) - sum(
    roverlap_area(a, b) for a, b in itertools.combinations(prs, 2))
bad = []
cov = 0.0
for v in VOLS:
    if v["kind"] in ("ground", "boundary", "ramp", "landmark") or (v["kind"] == "slab" and not v.get("solid_below")):
        continue
    if v["kind"] == "fence" and v.get("class") == "rail":
        continue
    o = sum(roverlap_area(rect(v), r) for r in prs)
    if o <= 0 or v["id"] == pz["centerpiece"]:
        continue
    if v["kind"] == "cover" and v.get("class") in ("C1", "C2"):
        cov += o
        continue
    bad.append(v["id"])
cp = byid[pz["centerpiece"]]
cps = {d["side"] for d in cp["doors"]}
through = ("N" in cps and "S" in cps) or ("W" in cps and "E" in cps)
cpa = sum(roverlap_area(rect(cp), r) for r in prs)
open_area = area - cov - cpa
res("Place ≥ 280 m² ouverte, couverts C1/C2 seulement, pièce centrale traversante",
    not bad and through and open_area >= 280,
    f"{len(prs)} rectangles, {area:.0f} m² dont {open_area:.0f} m² libres ; centre {cp['id']} portes "
    f"{''.join(sorted(cps))}" + (" ; intrus : " + ", ".join(bad) if bad else ""))

# ------------------------------------------------------------------ 7. canyon
CAN = plan["levels"]["canyon"]


def canyon_floor(x, z):
    for v in RAMPS_:
        if in_ramp(v, x, z) is not None:
            return False
    tops = [v["y"][1] for v in VOLS if v["kind"] == "ground" and v["x"][0] <= x <= v["x"][1]
            and v["z"][0] <= z <= v["z"][1]]
    return bool(tops) and max(tops) <= CAN + 0.05


widths = []
for x in np.arange(bx[0] + 0.25, bx[1], 0.5):
    run, best = 0, 0
    for z in np.arange(bz[0] + 0.125, bz[1], 0.25):
        run = run + 1 if canyon_floor(x, z) else 0
        best = max(best, run)
    widths.append((best * 0.25, x))
wmin = min(widths)
wmin_w = min(w for w in widths if w[1] < 0)
wmin_e = min(w for w in widths if w[1] > 0)
cobs = [(v["id"], rect(v)) for v in VOLS if v["kind"] in ("rock", "cover") and vbottom(v) is not None
        and vbottom(v) <= CAN + 0.1]
nn = []
for ia, ra in cobs:
    d = min(rdist(ra, rb) for ib, rb in cobs if ib != ia)
    nn.append((ia, d))
spacing_ok = all(5.0 - 1e-6 <= d <= 8.0 + 1e-6 for _, d in nn)
can_ramps = [v for v in ramps if max(v["from"][1], v["to"][1]) > -0.1 and min(v["from"][1], v["to"][1]) < CAN + 0.1]
rw = [v for v in can_ramps if v["from"][0] < 0]
re_ = [v for v in can_ramps if v["from"][0] > 0]
res("Canyon ≥ 10 m paroi à paroi, rochers/couverts espacés de 5–8 m, ≥ 2 rampes larges par moitié",
    wmin[0] >= 10 and spacing_ok and len(rw) >= 2 and len(re_) >= 2,
    f"largeur min O {wmin_w[0]:g} m, E {wmin_e[0]:g} m ; plus proche voisin {min(d for _, d in nn):.1f}–"
    f"{max(d for _, d in nn):.1f} m ({', '.join(i for i, d in nn if not 5 - 1e-6 <= d <= 8 + 1e-6) or 'tous dans 5–8'})"
    f" ; rampes O : "
    f"{', '.join(v['id'] for v in rw)} ; E : {', '.join(v['id'] for v in re_)}")

# ------------------------------------------------------------------ 8. lignes de vue par couloir
SIGHT = {}
for reg in plan["sight_regions"]:
    pts = region_points(reg)
    d, a, b = max_sight(pts)
    res(f"Vue max « {reg['id']} » ≤ {reg['cap']:g} m", d <= reg["cap"] + 1e-6,
        f"{d:.1f} m ({len(pts)} points) entre {fmt_pt(a)} et {fmt_pt(b)}" if a is not None else "aucune")
    per = {}
    for h, sel in (("W", lambda p, q: (p[:, 0] < 0) & (q[:, 0] < 0)), ("E", lambda p, q: (p[:, 0] > 0) & (q[:, 0] > 0))):
        dh, ah, bh = max_sight(pts, sel)
        per[h] = (dh, ah, bh)
    SIGHT[reg["id"]] = per

# apparitions : aucune vue vers la moitié adverse
upper_pts = {"W": [], "E": []}
for k, (t, s) in nodes.items():
    r = rect(s)
    for x in np.arange(r[0] + 0.5, r[1], 1.5):
        for z in np.arange(r[2] + 0.5, r[3], 1.5):
            upper_pts[half_of(x)].append((x, UP + EYE, z))
all_ground = {"W": region_points({"rects": [{"x": [bx[0], -2.0], "z": bz}], "levels": LEVELS}, 1.5),
              "E": region_points({"rects": [{"x": [2.0, bx[1]], "z": bz}], "levels": LEVELS}, 1.5)}
det, total = [], 0
for team, enemy in ((0, "E"), (1, "W")):
    sp = [s["pos"] for s in plan["markers"]["team_spawns"] if s.get("team", 0) == team]
    far = np.vstack([all_ground[enemy], np.array(upper_pts[enemy])])
    seen, closest = 0, None
    for p in sp:
        s = np.array([p[0], p[1] + EYE, p[2]])
        vis = los(np.repeat(s[None], len(far), 0), far)
        seen += int(vis.sum())
        if vis.any():
            dd = np.linalg.norm(far[vis][:, [0, 2]] - s[[0, 2]], axis=1)
            k = int(np.argmin(dd))
            if closest is None or dd[k] < closest[0]:
                closest = (dd[k], far[vis][k], s)
            if DBG:
                for q in far[vis][:25]:
                    print(f"  apparition {team} {np.round(s, 1)} -> {np.round(q, 1)}")
    total += seen
    det.append(f"équipe {team} : " + ("aucune ligne" if not seen else
                                      f"{seen} lignes, la plus courte {closest[0]:.1f} m vers {fmt_pt(closest[1])}"))
res("Apparitions : aucune vue sur la moitié adverse (|x| > 2)", total == 0, " ; ".join(det))


# ------------------------------------------------------------------ 9. sorties, fronts, premier contact
def route_pts(pts2):
    out = []
    for x, z in pts2:
        gy = ground_y(x, z)
        out.append((x, 0.0 if gy is None else gy, z))
    return out


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


def route_clear(route):
    """Chaque segment de route au sol ne traverse aucun obstacle plein (hors portes : tolérance 0,3 m)."""
    bad_ = []
    for a, b in zip(route, route[1:]):
        L = math.dist((a[0], a[2]), (b[0], b[2]))
        for s in np.arange(0.5, L, 0.5):
            t = s / L
            x, z = a[0] + (b[0] - a[0]) * t, a[2] + (b[2] - a[2]) * t
            gy = ground_y(x, z)
            if gy is None:
                bad_.append(f"hors sol ({x:.1f}, {z:.1f})")
                break
            for v in VOLS:
                if v["kind"] not in ("solid", "cover", "rock", "wall", "boundary") and not (
                        v["kind"] in SURF and v["y"][1] > gy + 0.5) and not (
                        v["kind"] == "fence" and v.get("class") != "rail"):
                    continue
                lo_, hi_ = v["y"] if "y" in v else (0, 0)
                if hi_ <= gy + 0.05 or lo_ >= gy + 1.8:
                    continue
                r = rect(v)
                if r[0] + 0.05 < x < r[1] - 0.05 and r[2] + 0.05 < z < r[3] - 0.05:
                    bad_.append(f"{v['id']} ({x:.1f}, {z:.1f})")
                    break
            if bad_:
                break
    return bad_


lanes = plan["lanes"]
R0 = {ln["id"]: route_pts(ln["route_w"]) for ln in lanes}
R1 = {ln["id"]: route_pts(ln.get("route_e") or [(-x, z) for x, z in ln["route_w"]]) for ln in lanes}
blocked = []
for ln in lanes:
    for key, rr in (("route_w", R0[ln["id"]]), ("route_e", R1[ln["id"]])):
        b_ = route_clear(rr)
        if b_:
            blocked.append(f"{ln['id']}/{key} : {b_[0]}")
res("Routes de sprint praticables (aucun obstacle plein traversé)", not blocked, "; ".join(blocked) or "6 routes libres")

first = {}
for ia, ib in itertools.product(R0, R1):
    ra, rb = R0[ia], R1[ib]
    t_hit, run = None, 0
    for step in range(0, 131):
        t = step * 0.1
        pa = at(ra, t * SPRINT)
        pb = at(rb, t * SPRINT)
        if los(np.array([[pa[0], pa[1] + EYE, pa[2]]]), np.array([[pb[0], pb[1] + EYE, pb[2]]]))[0]:
            run += 1
            if run == 5:  # vue tenue 0,5 s = contact (un aperçu par une porte ne compte pas)
                t_hit = round(t - 0.4, 1)
                break
        else:
            run = 0
    first[(ia, ib)] = t_hit
    if DBG and t_hit is not None:
        print("  contact", ia, ib, t_hit, np.round(pa, 1), np.round(pb, 1))

BAL = {}
det, ok_exit, ok_contact = [], True, True
for team, RR, key in ((0, R0, "route_w"), (1, R1, "route_e")):
    ex = {tuple(ln[key][1]) for ln in lanes}
    if len(ex) != len(lanes):
        ok_exit = False
for ln in lanes:
    i = ln["id"]
    L0, L1 = rlen(R0[i]), rlen(R1[i])
    same = first[(i, i)]
    c0 = min((first[(i, o)] for o in R1 if first[(i, o)] is not None), default=None)
    c1 = min((first[(o, i)] for o in R0 if first[(o, i)] is not None), default=None)
    BAL[i] = dict(L0=L0, L1=L1, same=same, c0=c0, c1=c1)
    fr = ln.get("front")
    if fr and (math.dist((R0[i][-1][0], R0[i][-1][2]), (fr[0], fr[2])) > 0.01 or
               math.dist((R1[i][-1][0], R1[i][-1][2]), (fr[0], fr[2])) > 0.01):
        ok_exit = False
    for c in (c0, c1):
        if c is None or not (5.0 <= c <= 8.0 + 1e-6):
            ok_contact = False
    det.append(f"{ln['label']} : contact même couloir {same if same is not None else '>13'} s ; "
               f"premier contact O {c0 if c0 is not None else '>13'} s / E {c1 if c1 is not None else '>13'} s")
res("3 sorties d'apparition distinctes par équipe, routes vers un front partagé", ok_exit,
    " ; ".join(f"{ln['id']} : O {tuple(ln['route_w'][1])} / E {tuple(ln['route_e'][1])}" for ln in lanes))
res("Premier contact 5–8 s au sprint (chaque équipe, chaque couloir)", ok_contact, " | ".join(det))

# ------------------------------------------------------------------ 10. ÉQUILIBRE
# a) temps de sprint apparition -> front
det, ok = [], True
for ln in lanes:
    b = BAL[ln["id"]]
    r = ratio(b["L0"], b["L1"])
    ok &= r <= 1.10 + 1e-9
    det.append(f"{ln['id']} : O {b['L0']:.1f} m ({b['L0'] / SPRINT:.2f} s) / E {b['L1']:.1f} m "
               f"({b['L1'] / SPRINT:.2f} s) → écart {pct(b['L0'], b['L1'])}")
res("ÉQUILIBRE — sprint apparition → front, par couloir, O/E à ±10 %", ok, " | ".join(det))

# b) premier contact par couloir
det, ok = [], True
for ln in lanes:
    b = BAL[ln["id"]]
    if b["c0"] is None or b["c1"] is None:
        ok = False
        det.append(f"{ln['id']} : pas de contact")
        continue
    ok &= ratio(b["c0"], b["c1"]) <= 1.10 + 1e-9
    det.append(f"{ln['id']} : O {b['c0']} s / E {b['c1']} s → écart {pct(b['c0'], b['c1'])}")
res("ÉQUILIBRE — premier contact par couloir, O/E à ±10 %", ok, " | ".join(det))

# c) positions fortes surélevées
LANE_LV = {ln["id"]: ln["level"] for ln in lanes}
pps = plan["markers"].get("strong_positions", [])
cnt = {0: 0, 1: 0}
det, ok = [], True
for pp in pps:
    if not pp.get("elevated"):
        continue
    p = pp["pos"]
    rise = p[1] - LANE_LV[pp["lane"]]
    eye = np.array([p[0], p[1] + EYE, p[2]])
    vis_c = []
    for c in pp.get("counters", []):
        q = np.array([c["pos"][0], c["pos"][1] + EYE, c["pos"][2]])
        v_ = bool(los(eye[None], q[None])[0])
        if v_:
            vis_c.append(math.atan2(q[2] - eye[2], q[0] - eye[0]))
        elif DBG:
            print(f"  {pp['id']} : réplique « {c['label']} » masquée par {blocker_of(eye[None], q[None])}")
    spread = 0.0
    for a, c in itertools.combinations(vis_c, 2):
        dd = abs(math.degrees(a - c)) % 360
        spread = max(spread, min(dd, 360 - dd))
    acc_ok = all(a in byid for a in pp.get("access", [])) and len(pp.get("access", [])) >= 2
    good = rise >= 1.0 - 1e-6 and len(vis_c) >= 2 and spread >= 45 and acc_ok
    if pp.get("team") in (0, 1):
        cnt[pp["team"]] += 1
    ok &= good
    det.append(f"{pp['id']} {pp['label']} (équipe {pp.get('team', 'C') if pp.get('team') is not None else 'C'}, "
               f"+{rise:g} m) : {len(vis_c)}/{len(pp.get('counters', []))} répliques visibles, écart {spread:.0f}°, "
               f"{len(pp.get('access', []))} accès" + ("" if good else " ✗"))
res("ÉQUILIBRE — positions fortes surélevées : même nombre par équipe, chacune ≥ 2 répliques (≥ 45°) et ≥ 2 accès",
    ok and cnt[0] == cnt[1], f"équipe 0 : {cnt[0]}, équipe 1 : {cnt[1]} — " + " ; ".join(det))

# d) plus longue ligne de vue interne à chaque moitié, par couloir
det, ok = [], True
for rid, per in SIGHT.items():
    dw, de = per["W"][0], per["E"][0]
    r = ratio(dw, de)
    ok &= r <= 1.15 + 1e-9
    det.append(f"{rid} : O {dw:.1f} m / E {de:.1f} m → écart {pct(dw, de)}")
    if DBG:
        for h in "WE":
            d_, a_, b_ = per[h]
            if a_ is not None:
                print(f"  vue {rid} {h} {d_:.1f} {fmt_pt(a_)} -> {fmt_pt(b_)}")
res("ÉQUILIBRE — plus longue ligne de vue interne à chaque moitié, par couloir, à ±15 %", ok, " | ".join(det))

# e) surface marchable par moitié (sol, étages, dalles, plateformes)
STEP = 0.5
BLOCK = ("solid", "cover", "rock", "wall", "boundary")
area_h = {"W": 0.0, "E": 0.0}
for x in np.arange(bx[0] + STEP / 2, bx[1], STEP):
    for z in np.arange(bz[0] + STEP / 2, bz[1], STEP):
        gy = ground_y(x, z)
        if gy is None:
            continue
        blocked_ = False
        for v in VOLS:
            if v["kind"] not in BLOCK and not (v["kind"] == "fence" and v.get("class") != "rail"):
                continue
            if v["y"][1] <= gy + 0.05 or v["y"][0] >= gy + 1.8:
                continue
            r = rect(v)
            if r[0] <= x <= r[1] and r[2] <= z <= r[3]:
                blocked_ = True
                break
        if not blocked_:
            area_h[half_of(x)] += STEP * STEP
up_area = {"W": 0.0, "E": 0.0}
for k, (t, s) in nodes.items():
    r = rect(s)
    n_up = (s.get("floors", 1) - 1) if t == "bld" else 1
    for x in np.arange(r[0] + STEP / 2, r[1], STEP):
        up_area[half_of(x)] += STEP * (r[3] - r[2]) * n_up
tot = {h: area_h[h] + up_area[h] for h in "WE"}
res("ÉQUILIBRE — surface marchable par moitié à ±10 %", ratio(tot["W"], tot["E"]) <= 1.10,
    f"O {tot['W']:.0f} m² (sol {area_h['W']:.0f} + haut {up_area['W']:.0f}) / E {tot['E']:.0f} m² "
    f"(sol {area_h['E']:.0f} + haut {up_area['E']:.0f}) → écart {pct(tot['W'], tot['E'])}")

# ------------------------------------------------------------------ sortie
if "--md" in sys.argv:
    print("| Contrôle | Résultat | Détail |")
    print("|---|---|---|")
    for n, r, d in RESULTS:
        print(f"| {n.replace('|', chr(92) + '|')} | {r} | {d.replace('|', chr(92) + '|')} |")
else:
    for n, r, d in RESULTS:
        print(f"[{r}] {n}\n      {d}")
    print(f"\n{sum(1 for _, r, _ in RESULTS if r == 'OK')}/{len(RESULTS)} contrôles OK")
