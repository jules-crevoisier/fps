"""Wasteland v4 : données du blockout, mesures 2D et plan du dessus.

Source unique des coordonnées de docs/research/11_wasteland_v4_layout.md.
    python docs/research/img/wasteland_v4_plan.py             # mesures v4 + PNG
    python docs/research/img/wasteland_v4_plan.py --audit-v3  # mêmes mesures sur la v3
Modèle : grille 0,5 m, hauteur de sol par case. Chemins « navmesh » = marche
<= 0,5 m, sans saut ni chute (comme Recast, AGENT_MAX_CLIMB). Lignes de vue à
1,6 m au-dessus du sol de l'observateur ; fenêtres (allège 1,0-2,0 m) et portes
laissent passer la vue, couverts de 1,1 m non. Axes Godot : x ouest->est, z nord->sud.
"""
import heapq
import math
import re
import sys
from pathlib import Path

import numpy as np

RES = 0.5
SPRINT = 8.2
EYE = 1.6
HERE = Path(__file__).resolve().parent

# ----------------------------------------------------------------------------
#  Pièces (moitié ouest + centre). La moitié est = miroir x -> -x.
# ----------------------------------------------------------------------------
def box(n, x, z, y, role="cover", **kw):
    return dict(k="box", n=n, x=x, z=z, y=y, role=role, **kw)

def bld(n, x, z, h, floors=1, doors=(), windows=(), stair_side="N", **kw):
    return dict(k="bld", n=n, x=x, z=z, y=(0.0, h), floors=floors, doors=list(doors),
                windows=list(windows), stair_side=stair_side, **kw)

def door(side, off=0.0, w=1.6, floor=0):
    return dict(side=side, off=off, w=w, floor=floor)

def ramp(n, start, end, w, up=False):
    return dict(k="ramp", n=n, start=start, end=end, w=w, up=up)

def fence(n, a, b, h, base=0.0):
    return dict(k="fence", n=n, a=a, b=b, h=h, base=base)

def floor(n, x, z, top):
    return dict(k="floor", n=n, x=x, z=z, top=top)

WEST = [
    floor("G_PlateauW", (-44, -2), (-25, 12), 0.0),
    # Rangée nord
    bld("ForgeW", (-36, -29), (-25, -15), 3.6, doors=[door("S", 0, 2.0), door("W", 3)], windows=["W"]),
    bld("Hotel", (-26, -16), (-25, -19), 6.4, floors=2, stair_side="N", pp="PP1",
        doors=[door("S", -2.5), door("S", 2.5), door("W", -2.25, floor=1), door("E", -2.25, floor=1)],
        windows=["S"]),
    ramp("StairImpasseW", (-27.25, 0, -18.5), (-27.25, 3.2, -23.5), 1.5, up=True),
    box("PalierImpasseW", (-28, -26), (-25, -23.5), (3.0, 3.2), role="slab"),
    ramp("StairPassageW", (-15.25, 0, -18.5), (-15.25, 3.2, -23.5), 1.5, up=True),
    box("PalierPassageW", (-16, -14), (-25, -23.5), (3.0, 3.2), role="slab"),
    bld("MagasinW", (-13, -4), (-25, -19), 3.6, doors=[door("S", -3), door("S", 3), door("W", 1)]),
    # Grand-Rue (moitié ouest)
    box("CiterneFUEL", (-43, -39), (-15, -11), (0, 2.8), role="solid"),
    box("CaisseFUEL", (-37, -35), (-4, 0), (0, 2.2)),
    box("CharretteW", (-26, -23), (-13, -9.5), (0, 2.2)),
    box("AbreuvoirW1", (-31, -29), (-11.5, -10.5), (0, 1.1), role="low"),
    box("AbreuvoirW2", (-12, -10), (-17.5, -16.5), (0, 1.1), role="low"),
    box("CaissesW", (-20, -18.5), (-16, -14.5), (0, 1.1), role="low"),
    # Bloc central (lane intérieure)
    bld("EchoppesW", (-34, -20), (-9, 5), 3.6,
        doors=[door("W", -3), door("W", 3), door("N", -4), door("E", 0), door("S", 4)]),
    box("EchoppesMurW1", (-27.125, -26.875), (-9, -3), (0, 3.6), role="wall"),
    box("EchoppesMurW2", (-27.125, -26.875), (-1, 5), (0, 3.6), role="wall"),
    box("ComptoirW", (-31, -29), (0, 1), (0, 1.1), role="low"),
    bld("SaloonW", (-16, -8), (-11, 5), 6.4, floors=2, stair_side="S", pp="PP3",
        doors=[door("N", 0), door("W", -3), door("E", 4.5, 2.4), door("E", 0, floor=1), door("W", 0, floor=1)],
        windows=["N", "S"]),
    ramp("StairRuelleW", (-16.75, 0, 3), (-16.75, 3.2, -3), 1.5, up=True),
    box("BalconW", (-8, -6), (-9, -1), (2.95, 3.2), role="slab"),
    fence("RampeBalconW", (-6, -9), (-6, -1), 1.0, base=3.2),
    ramp("StairGalerieW", (-7, 0, -15), (-7, 3.2, -9), 1.5, up=True),
    box("TonneauxW", (-7.5, -5.5), (3, 5), (0, 2.0)),
    box("TraversesW", (-5, -3), (0.5, 2.5), (0, 2.0)),
    box("PileTraversesNW", (-6, -4), (-7.5, -6), (0, 2.0)),
    # Arrière-cours + bord du canyon
    box("RemiseW", (-30, -26), (5, 8.5), (0, 2.6)),
    fence("ClotureW", (-37, 6), (-33, 6), 1.1),
    box("CuveW", (-13, -10), (7.5, 12), (0, 2.4)),
    box("ChariotMineW", (-37, -34), (8.5, 12), (0, 2.2)),
    box("CaissesQuaiW", (-20, -18), (9, 11), (0, 2.0)),
    fence("ParapetW1", (-44, 11.9), (-41, 11.9), 1.1),
    fence("ParapetW2", (-38, 11.9), (-19, 11.9), 1.1),
    fence("ParapetW3", (-16, 11.9), (-2.5, 11.9), 1.1),
    # Canyon (sol -2)
    ramp("RampeCanyonW1", (-40, 0, 13), (-34, -2, 13), 2.0),
    ramp("RampeCanyonW2", (-18, 0, 13), (-12, -2, 13), 2.0),
    box("RocherS1W", (-31, -27), (15.5, 20), (-2, 1.8), role="rock"),
    box("RocherN1W", (-24, -21), (12, 16.5), (-2, 1.8), role="rock"),
    box("RocherS2W", (-10, -7), (15.5, 20), (-2, 1.8), role="rock"),
    box("RocherGueW", (-4, -2.5), (12, 16.5), (-2, 1.8), role="rock"),
]

CENTER = [
    floor("G_PlateauC", (-2, 2), (-25, 8), 0.0),
    floor("G_Canyon", (-44, 44), (12, 20), -2.0),
    box("Poste", (-4, 4), (-25, -16), (0, 6.4), role="solid"),
    box("Diligence", (-3, 3), (-16, -11), (0, 3.4), role="solid"),
    bld("Wagon", (-6, 6), (-2.5, 0.5), 3.4, pp="PP5",
        doors=[door("W"), door("E"), door("S", -3), door("S", 3)], windows=["N"]),
    ramp("Descente", (0, 0, 8), (0, -2, 13), 4.0),
    box("Pompe", (-1.5, 1.5), (5, 7.5), (0, 2.4), role="solid"),
    box("MuretGouletO", (-2.5, -2.0), (7.5, 12), (0, 2.0), role="wall"),
    box("MuretGouletE", (2.0, 2.5), (7.5, 12), (0, 2.0), role="wall"),
    box("PiedChateauNO", (-2.0, -1.6), (3.8, 4.2), (0, 8), role="leg"),
    box("PiedChateauNE", (1.6, 2.0), (3.8, 4.2), (0, 8), role="leg"),
    box("PiedChateauSO", (-2.0, -1.6), (6.8, 7.2), (0, 8), role="leg"),
    box("PiedChateauSE", (1.6, 2.0), (6.8, 7.2), (0, 8), role="leg"),
]

RENAME = {"Hotel": "Banque", "CiterneFUEL": "CiterneGAS", "G_PlateauW": "G_PlateauE"}

def _mirror(p):
    q = dict(p)
    q["n"] = RENAME.get(p["n"], re.sub(r"W(\d?)$", r"E\1", p["n"]))
    if "x" in p:
        q["x"] = (-p["x"][1], -p["x"][0])
    if p["k"] == "ramp":
        q["start"] = (-p["start"][0],) + tuple(p["start"][1:])
        q["end"] = (-p["end"][0],) + tuple(p["end"][1:])
    if p["k"] == "fence":
        q["a"] = (-p["a"][0], p["a"][1])
        q["b"] = (-p["b"][0], p["b"][1])
    if p["k"] == "bld":
        swap = {"W": "E", "E": "W", "N": "N", "S": "S"}
        q["doors"] = [dict(d, side=swap[d["side"]], off=(-d["off"] if d["side"] in "NS" else d["off"])) for d in p["doors"]]
        q["windows"] = [swap[s] for s in p["windows"]]
        q["stair_side"] = swap[p["stair_side"]]
        if "pp" in p:
            q["pp"] = {"PP1": "PP2", "PP3": "PP4"}[p["pp"]]
    return q

V4_PIECES = WEST + CENTER + [_mirror(p) for p in WEST]

def _mx(pts):
    return pts + [(-x, z) for (x, z) in pts]

V4 = dict(
    name="v4", bounds=(-44.0, 44.0, -25.0, 20.0), pieces=V4_PIECES, canyon_z=12.0,
    spawns={0: [(-41, -8), (-41, -4), (-41, 0), (-41, 4)], 1: [(41, -8), (41, -4), (41, 0), (41, 4)]},
    tdm=_mx([(-41, -20), (-38.5, -17), (-41, -8), (-41, -2), (-41, 4), (-39, 7.5), (-42, 15.5),
             (-42, 18.5), (-31, -5), (-24, 1), (-32.5, -21), (-23, 8.5)]),
    hp={"P1": ((0, -1), (14, 5)), "P2": ((-8.5, -22), (8.5, 5.5)), "P3": ((15, 17), (6, 5))},
    snd={"A": ((21, -22), (8, 4)), "B": ((21, 8.5), (6, 5))},
    duel_spawns=[(-18, 8.5), (18, 8.5), (-11, -14), (11, -14)],
    duel_zone=((0, -6), (6, 4)),
    pp={"PP1": (-21, -19.8), "PP2": (21, -19.8), "PP3": (-7, -5), "PP4": (7, -5), "PP5": (0, -1)},
    # Couloirs de lane (pour les mesures de ligne de vue) : (x0, x1, z0, z1)
    lanes={"Grand-Rue": (-38, 38, -19, -11), "Intérieurs": ["EchoppesW", "EchoppesE", "SaloonW", "SaloonE", "Wagon"],
           "Place": (-8, 8, -11, 5), "Arrière-cours": (-44, 44, 5, 12), "Canyon": (-44, 44, 12, 20)},
    fronts=[(-8, -14), (-8, -4), (-6, 16)],
    routes={"Grand-Rue": [(-41, -2), (-37, -13), (-6, -13), (-5, -10), (5, -10), (6, -13), (37, -13), (41, -2)],
            "Intérieurs": [(-41, -2), (-34, -5), (-20, -2), (-8, -3), (0, -5), (8, -3), (20, -2), (34, -5), (41, -2)],
            "Canyon": [(-41, -2), (-40, 11), (-37, 13), (-12, 14), (-5, 18), (5, 18), (12, 14), (37, 13), (40, 11), (41, -2)]},
)

# ----------------------------------------------------------------------------
#  Lecture de la v3 (scripts/levels/maps/layouts/wasteland.gd)
# ----------------------------------------------------------------------------
def _gd_to_py(s):
    s = re.sub(r"Vector[23]\(", "(", s)
    s = re.sub(r"Cartoon\.\w+", "None", s)
    s = re.sub(r"Color\(\"[0-9a-fA-F]+\"\)", "None", s)
    s = s.replace("true", "True").replace("false", "False").replace("PI", str(math.pi))
    return eval(s)

def load_v3(path):
    txt = Path(path).read_text(encoding="utf-8")
    pieces = []
    for m in re.finditer(r"A\.call\((\{.*?\})\)\s*$", txt, re.M | re.S):
        body = m.group(1)
        if "%" in body:
            continue
        try:
            d = _gd_to_py(body)
        except Exception:
            continue
        t, n = d.get("type"), d.get("name")
        if t in ("box", "building2") and not d.get("visual_only"):
            (px, py, pz), (sx, sy, sz) = d["pos"], d["size"]
            x, z, y = (px - sx / 2, px + sx / 2), (pz - sz / 2, pz + sz / 2), (py - sy / 2, py + sy / 2)
            if n in ("Ground", "RavinFloor"):
                pieces.append(floor(n, x, z, y[1]))
            elif t == "box":
                pieces.append(box(n, x, z, y, role="cover" if y[1] < 6 else "solid"))
            else:
                doors = [door(dd["side"], dd.get("offset", 0.0), dd.get("w", 1.6), dd.get("floor", 0)) for dd in d.get("doors", [])]
                p = bld(n, x, z, y[1] - y[0], floors=d.get("floors", 1), doors=doors, windows=d.get("windows", []),
                        stair_side=d.get("stair_side", "N"), roof_access=d.get("roof_access", False))
                pieces.append(p)
        elif t in ("stairs", "ramp"):
            up = d["end"][1] > d["start"][1] and d["start"][1] >= 0
            pieces.append(ramp(n, d["start"], d["end"], d["width"], up=up if t == "stairs" else d["end"][1] > 0.5))
        elif t == "fence":
            a, b = d["start"], d["end"]
            pieces.append(fence(n, (a[0], a[2]), (b[0], b[2]), d["height"], base=a[1]))
    for rx in [-30.0, -20.0, -2.0, 20.0, 27.0]:
        pieces.append(ramp("RavinRamp%d" % rx, (rx, 0, 9.0), (rx, -1.2, 12.0), 3.0))
    return dict(
        name="v3", bounds=(-40.0, 40.0, -25.0, 18.0), pieces=pieces, canyon_z=9.0,
        spawns={0: [(-36.5, -1), (-36.5, 1), (-38.5, -1), (-38.5, 1)], 1: [(36.5, -1), (36.5, 1), (38.5, -1), (38.5, 1)]},
        hp={"A": ((-13, 1), (6, 6)), "B": ((0.5, -8.5), (6, 6)), "C": ((14, 6), (6, 6))},
        snd={"A": ((19, -21), (8, 6)), "B": ((13, 7), (6, 6))},
        pp={"PF1": (-30, -7.5), "PF2": (-10.5, -7.5), "PF3": (1.5, -11.5), "PF4": (19, -21), "PF5": (26.5, -7)},
        lanes={"Crête": (-30, 30, -24, -10), "Grand-Rue": (-36, 36, -5, 9), "Ravin": (-37, 37, 9, 18)},
        routes={"Crête": [(-36.5, -1), (-29, -12.25), (-2, -12.25), (4, -19), (10, -12), (25, -12), (36.5, -1)],
                "Grand-Rue": [(-36.5, -1), (-18, -2), (-3, 3), (4, 3), (19, 0), (36.5, -1)],
                "Ravin": [(-36.5, -1), (-30, 8), (-30, 12), (0, 13), (27, 12), (27, 8), (36.5, -1)]},
    )

# ----------------------------------------------------------------------------
#  Grille : sol, obstacles de marche, obstacles de vue
# ----------------------------------------------------------------------------
class Grid:
    def __init__(self, m):
        self.m = m
        x0, x1, z0, z1 = m["bounds"]
        self.x0, self.z0 = x0, z0
        self.nx, self.nz = int(round((x1 - x0) / RES)), int(round((z1 - z0) / RES))
        xs = x0 + (np.arange(self.nx) + 0.5) * RES
        zs = z0 + (np.arange(self.nz) + 0.5) * RES
        self.X, self.Z = np.meshgrid(xs, zs, indexing="ij")
        self.floor = np.full((self.nx, self.nz), np.nan)
        self.walk_block = np.zeros((self.nx, self.nz), bool)
        self.solids = []  # (mask, ylo, yhi)
        for p in m["pieces"]:
            if p["k"] == "floor":
                mk = self._rect(p["x"], p["z"])
                self.floor[mk] = np.fmax(self.floor[mk], p["top"])
        base = np.nan_to_num(self.floor, nan=-99)
        self.base = base.copy()
        for p in m["pieces"]:
            getattr(self, "_add_" + p["k"])(p)
        self.void = np.isnan(self.floor)
        self.walk_block |= self.void
        self.floor = np.nan_to_num(self.floor, nan=-99)

    def _rect(self, x, z):
        return (self.X > x[0]) & (self.X < x[1]) & (self.Z > z[0]) & (self.Z < z[1])

    def _add_floor(self, p):
        pass

    def _solid(self, mk, ylo, yhi):
        self.solids.append(("box", mk, ylo, yhi))
        rel_lo, rel_hi = ylo - self.base, yhi - self.base
        blocking = mk & (rel_lo < 1.8) & (rel_hi > 0.5)
        self.walk_block |= blocking
        step = mk & (rel_hi <= 0.5) & (rel_hi > 0)
        self.floor[step] = np.fmax(self.floor[step], yhi)

    def _add_box(self, p):
        self._solid(self._rect(p["x"], p["z"]), p["y"][0], p["y"][1])

    def _add_fence(self, p):
        (ax, az), (bx, bz) = p["a"], p["b"]
        L = max(math.hypot(bx - ax, bz - az), 1e-6)
        t = np.clip(((self.X - ax) * (bx - ax) + (self.Z - az) * (bz - az)) / L ** 2, 0, 1)
        d = np.hypot(self.X - (ax + t * (bx - ax)), self.Z - (az + t * (bz - az)))
        self._solid(d < RES * 0.51, p["base"], p["base"] + p["h"])

    def _add_ramp(self, p):
        (sx, sy, sz), (ex, ey, ez) = p["start"], p["end"]
        L = math.hypot(ex - sx, ez - sz)
        ux, uz = (ex - sx) / L, (ez - sz) / L
        along = (self.X - sx) * ux + (self.Z - sz) * uz
        side = -(self.X - sx) * uz + (self.Z - sz) * ux
        mk = (along >= 0) & (along <= L) & (np.abs(side) <= p["w"] / 2)
        h = sy + np.clip(along / L, 0, 1) * (ey - sy)
        if p["up"]:  # escalier montant : obstacle au sol tant qu'on ne passe pas dessous
            rel = h - self.base
            self.walk_block |= mk & (rel > 0.5) & (rel < 2.1)
            self.solids.append(("ramp", mk & (h > 0.5), h))
        else:
            self.floor[mk] = h[mk]

    def _add_bld(self, p):
        x, z, (y0, y1) = p["x"], p["z"], p["y"]
        inside = self._rect(x, z)
        ring = inside & ~self._rect((x[0] + RES, x[1] - RES), (z[0] + RES, z[1] - RES))
        door_mk = np.zeros_like(ring)
        win_mk = np.zeros_like(ring)
        cx, cz = (x[0] + x[1]) / 2, (z[0] + z[1]) / 2
        sides = {"N": (self.Z < z[0] + RES, self.X, cx), "S": (self.Z > z[1] - RES, self.X, cx),
                 "W": (self.X < x[0] + RES, self.Z, cz), "E": (self.X > x[1] - RES, self.Z, cz)}
        for s, (edge, coord, mid) in sides.items():
            ds = [d for d in p["doors"] if d["side"] == s and d["floor"] == 0]
            for d in ds:
                c = mid + d["off"]
                door_mk |= ring & edge & (np.abs(coord - c) < d["w"] / 2)
            if not ds and s in p["windows"]:
                lo, hi = (x if s in "NS" else z)
                n = max(1, int((hi - lo) // 3))
                for i in range(n):
                    c = lo + (i + 0.5) / n * (hi - lo)
                    win_mk |= ring & edge & (np.abs(coord - c) < 0.6)
        wall = ring & ~door_mk
        self.walk_block |= wall
        self.solids.append(("box", wall & ~win_mk, y0, y1))
        self.solids.append(("window", win_mk, y0, y1))

    def eye_block(self, level):
        """Masque des cases qui coupent la vue d'un observateur au sol `level`."""
        eye = level + EYE
        blk = (self.floor >= eye) | self.void
        for s in self.solids:
            if s[0] == "ramp":
                _, mk, h = s
                blk |= mk & (h - 0.3 <= eye) & (h >= eye)
            elif s[0] == "window":  # mur percé d'une fenêtre : vue libre entre 1,0 et 2,0 m
                _, mk, lo, hi = s
                if lo <= eye <= hi and not (lo + 1.0 < eye < lo + 2.0):
                    blk |= mk
            else:
                _, mk, lo, hi = s
                if lo <= eye <= hi:
                    blk |= mk
        return blk

    def cell(self, x, z):
        return int((x - self.x0) / RES), int((z - self.z0) / RES)

    def pos(self, i, j):
        return self.x0 + (i + 0.5) * RES, self.z0 + (j + 0.5) * RES

    def dist_from(self, x, z, climb=0.5):
        """Dijkstra 8-connexe ; montée et descente <= `climb` (navmesh)."""
        free = ~self.walk_block
        D = np.full((self.nx, self.nz), np.inf)
        si, sj = self._nearest_free(*self.cell(x, z))
        D[si, sj] = 0.0
        pq = [(0.0, si, sj)]
        steps = [(1, 0, 1.0), (-1, 0, 1.0), (0, 1, 1.0), (0, -1, 1.0),
                 (1, 1, 1.4142), (1, -1, 1.4142), (-1, 1, 1.4142), (-1, -1, 1.4142)]
        fl = self.floor
        while pq:
            d, i, j = heapq.heappop(pq)
            if d > D[i, j]:
                continue
            for di, dj, c in steps:
                a, b = i + di, j + dj
                if not (0 <= a < self.nx and 0 <= b < self.nz) or not free[a, b]:
                    continue
                if di and dj and not (free[i + di, j] and free[i, j + dj]):
                    continue
                if abs(fl[a, b] - fl[i, j]) > climb:
                    continue
                nd = d + c * RES
                if nd < D[a, b]:
                    D[a, b] = nd
                    heapq.heappush(pq, (nd, a, b))
        return D

    def _nearest_free(self, i, j):
        free = ~self.walk_block
        for r in range(0, 12):
            for a in range(i - r, i + r + 1):
                for b in range(j - r, j + r + 1):
                    if 0 <= a < self.nx and 0 <= b < self.nz and free[a, b]:
                        return a, b
        return i, j

    def path_len(self, a, b):
        D = self.dist_from(*a)
        return D[self._nearest_free(*self.cell(*b))]

    def los(self, a, b, blk):
        (ax, az), (bx, bz) = a, b
        n = int(math.hypot(bx - ax, bz - az) / (RES * 0.5)) + 1
        for t in np.linspace(0.0, 1.0, n)[1:-1]:
            i, j = self.cell(ax + t * (bx - ax), az + t * (bz - az))
            if blk[i, j]:
                return False
        return True

    def lane_los(self, rect, level, step=1.0, ndir=72):
        """Plus longue vue au sol depuis les cases praticables d'un couloir
        (rectangle x0, x1, z0, z1 ou liste de noms de bâtiments)."""
        blk = self.eye_block(level)
        inside = None
        if isinstance(rect, list):
            ps = [p for p in self.m["pieces"] if p["n"] in rect]
            inside = np.zeros_like(blk)
            for p in ps:
                inside |= self._rect(p["x"], p["z"])
            x0, x1 = min(p["x"][0] for p in ps), max(p["x"][1] for p in ps)
            z0, z1 = min(p["z"][0] for p in ps), max(p["z"][1] for p in ps)
        else:
            x0, x1, z0, z1 = rect
        best, best_seg = 0.0, None
        vals = []
        ang = np.linspace(0, 2 * math.pi, ndir, endpoint=False)
        dirs = np.stack([np.cos(ang), np.sin(ang)], 1)
        rs = np.arange(0.5, 90, 0.25)
        same = (~self.walk_block) & (np.abs(self.floor - level) < 0.3)
        for x in np.arange(x0 + 0.25, x1, step):
            for z in np.arange(z0 + 0.25, z1, step):
                i, j = self.cell(x, z)
                if not (0 <= i < self.nx and 0 <= j < self.nz) or not same[i, j]:
                    continue
                if inside is not None and not inside[i, j]:
                    continue
                px = x + dirs[:, :1] * rs[None, :]
                pz = z + dirs[:, 1:] * rs[None, :]
                a = np.floor((px - self.x0) / RES).astype(int)
                b = np.floor((pz - self.z0) / RES).astype(int)
                out = (a < 0) | (a >= self.nx) | (b < 0) | (b >= self.nz)
                a, b = np.clip(a, 0, self.nx - 1), np.clip(b, 0, self.nz - 1)
                stop = out | blk[a, b]
                first = np.where(stop.any(1), stop.argmax(1), len(rs))
                ok = same[a, b] & (np.arange(len(rs))[None, :] < first[:, None])
                last = np.where(ok.any(1), rs[ok.shape[1] - 1 - np.argmax(ok[:, ::-1], 1)], 0.0)
                k = int(np.argmax(last))
                vals.append(float(last[k]))
                if last[k] > best:
                    best = float(last[k])
                    best_seg = ((x, z), (x + dirs[k, 0] * best, z + dirs[k, 1] * best))
        return best, (float(np.percentile(vals, 90)) if vals else 0.0), best_seg


def height_map(g):
    """Dessus du volume le plus haut par case (bâtiment = emprise pleine jusqu'au toit)."""
    H = g.floor.copy()
    for p in g.m["pieces"]:
        if p["k"] == "bld" or (p["k"] == "box" and p["role"] not in ("slab", "leg")):
            mk = g._rect(p["x"], p["z"])
            H[mk] = np.maximum(H[mk], p["y"][1])
        elif p["k"] == "ramp" and p["up"]:
            (sx, sy, sz), (ex, ey, ez) = p["start"], p["end"]
            mk = g._rect((min(sx, ex) - p["w"] / 2, max(sx, ex) + p["w"] / 2) if abs(ex - sx) > 0.1 else (sx - p["w"] / 2, sx + p["w"] / 2),
                         (min(sz, ez) - p["w"] / 2, max(sz, ez) + p["w"] / 2) if abs(ez - sz) > 0.1 else (sz - p["w"] / 2, sz + p["w"] / 2))
            H[mk] = np.maximum(H[mk], max(sy, ey) * 0.5)
    return H


def pp_view(g, H, origins, eye_y, keep):
    """Plus longue vue plongeante depuis une position forte vers un torse (sol + 1,0 m)."""
    best, seg = 0.0, None
    tgt = (~g.walk_block) & (g.floor > -3)
    ti, tj = np.nonzero(tgt)
    tx, tz = g.x0 + (ti + 0.5) * RES, g.z0 + (tj + 0.5) * RES
    ty = g.floor[ti, tj] + 1.0
    for (ox, oz) in origins:
        sel = keep(tx, tz)
        d = np.hypot(tx - ox, tz - oz)
        n = 240
        ts = np.linspace(0.02, 0.98, n)[None, :]
        px = ox + (tx[sel, None] - ox) * ts
        pz = oz + (tz[sel, None] - oz) * ts
        py = eye_y + (ty[sel, None] - eye_y) * ts
        a = np.clip(((px - g.x0) / RES).astype(int), 0, g.nx - 1)
        b = np.clip(((pz - g.z0) / RES).astype(int), 0, g.nz - 1)
        near = np.hypot(px - ox, pz - oz) < 1.0
        vis = ~((H[a, b] > py) & ~near).any(1)
        if vis.any():
            k = np.argmax(np.where(vis, d[sel], 0))
            if d[sel][k] > best:
                best, seg = float(d[sel][k]), ((ox, oz), (float(tx[sel][k]), float(tz[sel][k])))
    return round(best, 1), seg


def _polyline_path(g, pts, climb=0.5):
    total = 0.0
    for a, b in zip(pts, pts[1:]):
        total += g.path_len(a, b) if climb else 0
    return total


def first_contact(g, route_a, route_b):
    """Deux coureurs à 8,2 m/s, l'un sur route_a depuis l'ouest, l'autre sur route_b
    depuis l'est ; renvoie l'instant du premier contact visuel (s)."""
    def sample(route):
        pts = []
        for a, b in zip(route, route[1:]):
            n = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / 0.5))
            for t in range(n):
                pts.append((a[0] + (b[0] - a[0]) * t / n, a[1] + (b[1] - a[1]) * t / n))
        return pts
    pa, pb = sample(route_a), sample(route_b[::-1])
    levels = {}
    for k in range(min(len(pa), len(pb))):
        a, b = pa[k], pb[k]
        la = g.floor[g.cell(*a)]
        lb = g.floor[g.cell(*b)]
        lvl = round(min(la, lb) * 4) / 4
        if lvl not in levels:
            levels[lvl] = g.eye_block(lvl)
        if g.los(a, b, levels[lvl]):
            return k * 0.5 / SPRINT
    return float("inf")


def measure(m):
    g = Grid(m)
    out = {}
    walk = (~g.walk_block).sum() * RES * RES
    out["aire_praticable_m2"] = round(float(walk))
    x0, x1, z0, z1 = m["bounds"]
    out["emprise"] = f"{x1 - x0:.0f} x {z1 - z0:.0f} m"
    sp_w = tuple(np.mean(m["spawns"][0], axis=0))
    sp_e = tuple(np.mean(m["spawns"][1], axis=0))
    Dw = g.dist_from(*sp_w)
    De = g.dist_from(*sp_e)
    def at(D, p):
        return float(D[g._nearest_free(*g.cell(*p))])
    out["spawn_O_spawn_E_m"] = round(at(Dw, sp_e), 1)
    for k, (c, _) in m["hp"].items():
        out[f"spawnO->{k}_m"] = round(at(Dw, c), 1)
        out[f"spawnE->{k}_m"] = round(at(De, c), 1)
    keys = list(m["hp"].keys())
    for a, b in zip(keys, keys[1:] + keys[:1]):
        out[f"rotation_{a}->{b}_m"] = round(g.path_len(m["hp"][a][0], m["hp"][b][0]), 1)
    for k, (c, _) in m["snd"].items():
        out[f"SnD_att->{k}_m"] = round(at(Dw, c), 1)
        out[f"SnD_def->{k}_m"] = round(at(De, c), 1)
    out["SnD_A<->B_m"] = round(g.path_len(m["snd"]["A"][0], m["snd"]["B"][0]), 1)
    names = list(m["routes"].keys())
    contacts = {}
    for a in names:
        for b in names:
            contacts[f"{a}/{b}"] = round(first_contact(g, m["routes"][a], m["routes"][b]), 2)
    out["contact_s"] = contacts
    fronts = m.get("fronts", [])
    if fronts:
        secs = []
        Ds = [g.dist_from(*f) for f in fronts] + [g.dist_from(-f[0], f[1]) for f in fronts]
        for (x, z) in m["tdm"]:
            own = Ds[:len(fronts)] if x < 0 else Ds[len(fronts):]
            secs.append(min(float(D[g._nearest_free(*g.cell(x, z))]) for D in own) / SPRINT)
        out["spawn_neutre->front_s (médiane, max)"] = (round(float(np.median(secs)), 1), round(max(secs), 1))
    n_obs = 0
    for p in m["pieces"]:
        if p["k"] in ("box", "bld") and p.get("role") not in ("slab", "leg", "wall"):
            area = (p["x"][1] - p["x"][0]) * (p["z"][1] - p["z"][0])
            if p["y"][1] - p["y"][0] >= 1.4 and area < 200 and p["y"][1] > 0.5:
                n_obs += 1
    out["volumes_pleins_en_jeu"] = n_obs
    if m["name"] == "v4":
        H = height_map(g)
        out["vue_max_PP1_fenetres_S"] = pp_view(g, H, [(-24.3, -18.8), (-21, -18.8), (-17.7, -18.8)], 4.8, lambda x, z: z > -18.8)
        out["vue_max_PP3_balcon"] = pp_view(g, H, [(-6.5, -8), (-6.5, -5), (-6.5, -2)], 4.8, lambda x, z: x > -6.4)
        out["vue_max_PP5_wagon_portes"] = pp_view(g, H, [(-6.3, -1), (6.3, -1)], 1.6, lambda x, z: np.abs(x) > 6.2)
    out["batiments"] = sum(1 for p in m["pieces"] if p["k"] == "bld")
    out["batiments_2_niveaux"] = sum(1 for p in m["pieces"] if p["k"] == "bld" and p.get("floors", 1) >= 2)
    for lane, rect in m["lanes"].items():
        level = -2.0 if lane == "Canyon" else (-1.2 if lane == "Ravin" else 0.0)
        best, p90, seg = g.lane_los(rect, level)
        out[f"vue_max_{lane}"] = (round(best, 1), round(p90, 1), tuple(tuple(round(v, 1) for v in s) for s in seg) if seg else None)
    return g, out


# ----------------------------------------------------------------------------
#  Figure
# ----------------------------------------------------------------------------
C = dict(bg="#f3ede2", plateau="#e8dcc6", canyon="#c9b69a", ink="#2b2724", ink2="#6b635a",
         b1="#b9a584", b2="#8a6f55", cover="#6f6258", low="#b3a79a", rock="#9c8671",
         blue="#2a78d6", red="#e34948", lane1="#eb6834", lane2="#1baf7a", lane3="#4a3aa7",
         hp="#eda100", snd="#e87ba4")


def draw(m, g, out_png):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Rectangle, Polygon
    plt.rcParams["font.family"] = ["Segoe UI", "Segoe UI Symbol", "DejaVu Sans"]
    x0, x1, z0, z1 = m["bounds"]
    fig, ax = plt.subplots(figsize=(17, 10.2), dpi=110)
    fig.patch.set_facecolor(C["bg"])
    ax.set_facecolor(C["bg"])
    ax.add_patch(Rectangle((x0, z0), x1 - x0, 12 - z0, fc=C["plateau"], ec="none", zorder=0))
    ax.add_patch(Rectangle((x0, 12), x1 - x0, z1 - 12, fc=C["canyon"], ec="none", zorder=0))
    ax.add_patch(Rectangle((-2, 8), 4, 4, fc=C["canyon"], ec="none", zorder=0))
    for zz in np.arange(z0, z1 + 0.1, 4):
        ax.plot([x0, x1], [zz, zz], color="#d6c9b2", lw=0.4, zorder=0.5)
    for xx in np.arange(x0, x1 + 0.1, 4):
        ax.plot([xx, xx], [z0, z1], color="#d6c9b2", lw=0.4, zorder=0.5)
    ax.add_patch(Rectangle((x0, z0), x1 - x0, z1 - z0, fc="none", ec=C["ink"], lw=2.2, zorder=6))
    ax.text(0, z0 - 1.2, "FALAISE NORD (mesa)  ·  au-delà, hors-jeu : GRUE (NO) et DERRICK (NE), repères de rang 1",
            ha="center", va="bottom", fontsize=9, color=C["ink2"])
    ax.text(0, z1 + 0.8, "PAROI SUD DU CANYON (mesa)", ha="center", va="top", fontsize=9, color=C["ink2"])
    ax.text(-38, z0 - 1.2, "GRUE ▲", ha="center", va="bottom", fontsize=9, color=C["ink"], weight="bold")
    ax.text(26, z0 - 1.2, "▲ DERRICK", ha="center", va="bottom", fontsize=9, color=C["ink"], weight="bold")

    for p in m["pieces"]:
        if p["k"] == "bld":
            two = p.get("floors", 1) >= 2
            ax.add_patch(Rectangle((p["x"][0], p["z"][0]), p["x"][1] - p["x"][0], p["z"][1] - p["z"][0],
                                   fc=C["b2"] if two else C["b1"], ec=C["ink"], lw=1.3, zorder=2,
                                   hatch="////" if two else None))
            cx, cz = (p["x"][0] + p["x"][1]) / 2, (p["z"][0] + p["z"][1]) / 2
            for d in p["doors"]:
                s, off, w = d["side"], d["off"], d["w"]
                if s in "NS":
                    zz = p["z"][0] if s == "N" else p["z"][1]
                    seg = ([cx + off - w / 2, cx + off + w / 2], [zz, zz])
                else:
                    xx = p["x"][0] if s == "W" else p["x"][1]
                    seg = ([xx, xx], [cz + off - w / 2, cz + off + w / 2])
                ax.plot(*seg, color=C["bg"] if d["floor"] == 0 else "#ffffff", lw=3.2 if d["floor"] == 0 else 1.6,
                        zorder=3, solid_capstyle="butt", ls="-" if d["floor"] == 0 else (0, (1, 1)))
        elif p["k"] == "box" and p["role"] != "slab":
            fc = {"low": C["low"], "rock": C["rock"], "leg": C["ink"], "wall": C["ink"]}.get(p["role"], C["cover"])
            ax.add_patch(Rectangle((p["x"][0], p["z"][0]), p["x"][1] - p["x"][0], p["z"][1] - p["z"][0],
                                   fc=fc, ec=C["ink"], lw=0.6, zorder=2.5))
        elif p["k"] == "box" and p["role"] == "slab":
            ax.add_patch(Rectangle((p["x"][0], p["z"][0]), p["x"][1] - p["x"][0], p["z"][1] - p["z"][0],
                                   fc="none", ec=C["ink"], lw=0.8, ls=(0, (2, 1)), zorder=2.6))
        elif p["k"] == "ramp":
            (sx, _, sz), (ex, _, ez), w = p["start"], p["end"], p["w"]
            if abs(ex - sx) > abs(ez - sz):
                r = Rectangle((min(sx, ex), sz - w / 2), abs(ex - sx), w)
            else:
                r = Rectangle((sx - w / 2, min(sz, ez)), w, abs(ez - sz))
            r.set(fc="#efe6d4", ec=C["ink"], lw=0.7, hatch="---", zorder=2.7)
            ax.add_patch(r)
            ax.annotate("", xy=(ex, ez), xytext=(sx, sz), zorder=2.8,
                        arrowprops=dict(arrowstyle="-|>", color=C["ink"], lw=0.8, mutation_scale=8))
        elif p["k"] == "fence":
            ax.plot([p["a"][0], p["b"][0]], [p["a"][1], p["b"][1]], color=C["ink2"], lw=1.4, zorder=2.5)

    labels = {"ForgeW": "Forge O", "ForgeE": "Forge E", "Hotel": "HÔTEL", "Banque": "BANQUE", "MagasinW": "Magasin O",
              "MagasinE": "Magasin E", "Poste": "Poste", "Diligence": "Diligence", "EchoppesW": "ÉCHOPPES O",
              "EchoppesE": "ÉCHOPPES E", "SaloonW": "SALOON O", "SaloonE": "SALOON E", "Wagon": "LE WAGON",
              "RemiseW": "Remise", "RemiseE": "Remise", "CiterneFUEL": "Citerne\nFUEL", "CiterneGAS": "Citerne\nGAS",
              "Rocher": "Rocher"}
    for p in m["pieces"]:
        if p["n"] in labels:
            cx, cz = (p["x"][0] + p["x"][1]) / 2, (p["z"][0] + p["z"][1]) / 2
            if p["n"] in ("Hotel", "Banque"):
                cz = p["z"][0] + 1.6
            if p["n"] == "Wagon":
                cx = -3.2
            ax.text(cx, cz, labels[p["n"]], ha="center", va="center", fontsize=8.5, weight="bold", color="#ffffff" if p.get("floors", 1) >= 2 or p["n"] in ("Poste", "Diligence") else C["ink"], zorder=7,
                    bbox=dict(boxstyle="round,pad=0.15", fc=C["b2"], ec="none", alpha=0.85) if p.get("floors", 1) >= 2 else None)
    ax.text(-18, -4, "Ruelle O", rotation=90, ha="center", va="center", fontsize=8, color=C["ink2"], zorder=7)
    ax.text(18, -4, "Ruelle E", rotation=90, ha="center", va="center", fontsize=8, color=C["ink2"], zorder=7)
    ax.text(0, 10, "Descente", ha="center", va="center", fontsize=8, color=C["ink"], zorder=7)
    ax.text(5.6, 7.3, "Château d'eau\n+ pompe", ha="center", va="center", fontsize=7.5, color=C["ink2"], zorder=7)
    ax.text(-39, -22, "Pylône FUEL", ha="center", fontsize=8, color=C["blue"], weight="bold", zorder=7)
    ax.text(39, -22, "Enseigne GAS", ha="center", fontsize=8, color=C["red"], weight="bold", zorder=7)

    # Lanes
    lane_c = {"Grand-Rue": C["lane1"], "Intérieurs": C["lane2"], "Canyon": C["lane3"]}
    lane_lbl = {"Grand-Rue": ((-35.5, -17.4), "1 · GRAND-RUE : vue ≤ 41 m"),
                "Intérieurs": ((-33.5, 3.6), "2 · INTÉRIEURS : salles ≤ 18 m"),
                "Canyon": ((-43.5, 19.4), "3 · CANYON (sol −2 m) : flanc serré, vue ≤ 24 m")}
    for name, pts in m["routes"].items():
        xs, zs = zip(*pts)
        ax.plot(xs, zs, color=lane_c[name], lw=3.2, alpha=0.9, zorder=4, solid_capstyle="round")
        (lx, lz), t = lane_lbl[name]
        ax.text(lx, lz, t, fontsize=9.5, weight="bold", color=lane_c[name], zorder=8,
                bbox=dict(boxstyle="round,pad=0.25", fc=C["bg"], ec=lane_c[name], lw=1))
    # Lignes de vue mesurées (les plus longues, voir measure())
    sight = [((-43.9, -8.3), (-4.8, -18.8), "40 m (sol)"), ((-21, -18.8), (-15.25, 19.75), "PP1 : 39 m"),
             ((-6.5, -8), (28.75, -17.75), "PP3 : 37 m"), ((-26.8, 18.2), (-4.1, 12.2), "24 m")]
    for (a, b, t) in sight:
        ax.plot([a[0], b[0]], [a[1], b[1]], color=C["ink"], lw=1.3, ls=(0, (5, 2.5)), zorder=5.2)
        mx, mz = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
        ax.text(mx, mz, t, fontsize=8, color=C["ink"], ha="center", va="center", zorder=8,
                bbox=dict(boxstyle="round,pad=0.12", fc="#ffffff", ec=C["ink"], lw=0.6))
    # Zones
    for k, ((cx, cz), (sx, sz)) in m["hp"].items():
        ax.add_patch(Rectangle((cx - sx / 2, cz - sz / 2), sx, sz, fc=C["hp"], alpha=0.25, ec=C["hp"], lw=2, zorder=4.5))
        ax.text(cx - sx / 2 + 0.3, cz - sz / 2 + 0.3, "HP " + k, fontsize=9, weight="bold", color="#6b4800", va="top", zorder=8,
                bbox=dict(boxstyle="round,pad=0.12", fc="#fff3d6", ec=C["hp"], lw=0.8))
    for k, ((cx, cz), (sx, sz)) in m["snd"].items():
        ax.add_patch(Rectangle((cx - sx / 2, cz - sz / 2), sx, sz, fc="none", ec=C["snd"], lw=2.4, ls=(0, (3, 1.5)), zorder=4.6))
        ax.text(cx - sx / 2 + 0.3, cz + sz / 2 - 0.3, "SnD " + k, fontsize=9.5, weight="bold", color="#9c2458", ha="left", va="bottom", zorder=8,
                bbox=dict(boxstyle="round,pad=0.12", fc="#fde8f0", ec=C["snd"], lw=0.8))
    # Zone de duel
    duel = [(-13, -19), (13, -19), (13, -11), (16, -11), (16, -9), (20, -9), (20, 20), (-20, 20), (-20, -9), (-16, -9), (-16, -11), (-13, -11)]
    ax.add_patch(Polygon(duel, closed=True, fc="none", ec=C["ink"], lw=1.6, ls=(0, (6, 3)), zorder=5.5))
    ax.text(-19.6, 19.6, "DUEL 1v1 / DUO 2v2 (40 × 39 m)", fontsize=8.5, color=C["ink"], va="bottom", zorder=8, weight="bold")
    (dcx, dcz), (dsx, dsz) = m["duel_zone"]
    ax.add_patch(Rectangle((dcx - dsx / 2, dcz - dsz / 2), dsx, dsz, fc="none", ec=C["ink"], lw=1, ls=":", zorder=5))
    ax.text(dcx, dcz, "zone duel", ha="center", va="center", fontsize=7, color=C["ink"], zorder=8)
    for (x, z) in m["duel_spawns"]:
        ax.plot(x, z, marker="D", ms=6, mfc="#ffffff", mec=C["ink"], zorder=9)
    # Spawns
    for (x, z) in m["tdm"]:
        ax.plot(x, z, marker="o", ms=5, mfc="#ffffff", mec=C["ink2"], mew=1, zorder=8.5)
    for team, col in ((0, C["blue"]), (1, C["red"])):
        for (x, z) in m["spawns"][team]:
            ax.plot(x, z, marker=">" if team == 0 else "<", ms=10, mfc=col, mec="#ffffff", zorder=9)
    ax.text(-43.3, -2, "SPAWN BLEU · dépôt FUEL", rotation=90, ha="center", va="center", fontsize=8.5, color=C["blue"], weight="bold", zorder=9)
    ax.text(43.3, -2, "SPAWN ROUGE · cour GAS", rotation=270, ha="center", va="center", fontsize=8.5, color=C["red"], weight="bold", zorder=9)
    for k, (x, z) in m["pp"].items():
        ax.plot(x, z, marker="*", ms=15, mfc=C["ink"], mec="#ffffff", zorder=9)
        ax.text(x + 0.9, z + 0.4, k, fontsize=9, weight="bold", color=C["ink"], zorder=9)
    # Légende
    from matplotlib.lines import Line2D
    from matplotlib.patches import Patch
    hs = [Patch(fc=C["b1"], ec=C["ink"], label="bâtiment 1 niveau (toit hors-jeu)"),
          Patch(fc=C["b2"], ec=C["ink"], hatch="////", label="bâtiment 2 niveaux (étage = position forte)"),
          Patch(fc=C["cover"], ec=C["ink"], label="couvert plein ≥ 2,0 m"),
          Patch(fc=C["low"], ec=C["ink"], label="couvert bas 1,1 m"),
          Patch(fc=C["rock"], ec=C["ink"], label="aiguille rocheuse (canyon, 3,8 m)"),
          Patch(fc="#efe6d4", ec=C["ink"], hatch="---", label="escalier / rampe (flèche = sens de pente)"),
          Line2D([], [], color=C["ink2"], lw=1.4, label="parapet 1,1 m (on saute par-dessus)"),
          Line2D([], [], color=C["ink"], lw=1.3, ls=(0, (5, 2.5)), label="plus longue ligne de vue (mesurée)"),
          Line2D([], [], color=C["lane1"], lw=3, label="lane 1 : Grand-Rue"),
          Line2D([], [], color=C["lane2"], lw=3, label="lane 2 : Intérieurs"),
          Line2D([], [], color=C["lane3"], lw=3, label="lane 3 : Canyon"),
          Patch(fc=C["hp"], alpha=0.35, ec=C["hp"], label="zone Hardpoint P1 à P3"),
          Patch(fc="none", ec=C["snd"], ls="--", lw=2, label="site SnD A / B"),
          Line2D([], [], color=C["ink"], lw=1.6, ls=(0, (6, 3)), label="limite Duel / Duo"),
          Line2D([], [], ls="", marker="*", ms=13, mfc=C["ink"], mec="#ffffff", label="position forte PP1 à PP5"),
          Line2D([], [], ls="", marker=">", ms=9, mfc=C["blue"], mec="#ffffff", label="spawn d'équipe (bleu / rouge)"),
          Line2D([], [], ls="", marker="o", ms=6, mfc="#ffffff", mec=C["ink2"], label="spawn neutre TDM/HP (24)"),
          Line2D([], [], ls="", marker="D", ms=6, mfc="#ffffff", mec=C["ink"], label="spawn Duel / Duo")]
    leg = ax.legend(handles=hs, loc="upper center", bbox_to_anchor=(0.5, -0.005), ncol=4, fontsize=8.5,
                    frameon=False, handlelength=2.2, columnspacing=1.6)
    for t in leg.get_texts():
        t.set_color(C["ink"])
    ax.set_title("Wasteland v4 : plan de blockout (88 × 45 m, 4v4 · HP · SnD · Duel)", fontsize=15, weight="bold",
                 color=C["ink"], loc="left", pad=30)
    ax.text(x0, z0 - 4.1, "grille 4 m · nord en haut (z négatif) · symétrie miroir x → −x (sauf décor) · mesures : wasteland_v4_plan.py",
            fontsize=9, color=C["ink2"], va="bottom")
    ax.set_xlim(x0 - 1, x1 + 1)
    ax.set_ylim(z1 + 1.5, z0 - 4.6)
    ax.set_aspect("equal")
    ax.axis("off")
    fig.tight_layout()
    fig.savefig(out_png, facecolor=C["bg"], bbox_inches="tight", pad_inches=0.3)


if __name__ == "__main__":
    if "--audit-v3" in sys.argv:
        root = HERE.parents[2]
        mm = load_v3(root / "scripts/levels/maps/layouts/wasteland.gd")
    else:
        mm = V4
    grid, res = measure(mm)
    for k, v in res.items():
        print(f"{k}: {v}")
    if mm is V4:
        draw(V4, grid, HERE / "wasteland_v4_plan.png")
        print("PNG:", HERE / "wasteland_v4_plan.png")
