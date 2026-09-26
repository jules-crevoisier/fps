"""Rend le plan coté de Wasteland depuis data/maps/wasteland_plan.json (source unique).

Sorties (docs/maps/img/) : vue de dessus cotée, deux coupes, vue 3D axonométrique ;
plus docs/maps/wasteland_volumes.csv (tous les volumes après miroir). Le plan et la
carte générée lisent le même JSON : ils ne peuvent pas diverger.

    python tools/maps/render_plan.py
"""
from __future__ import annotations

import csv
import json
import math
import re
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import Polygon, Rectangle  # noqa: E402
from mpl_toolkits.mplot3d.art3d import Poly3DCollection  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
PLAN = ROOT / "data/maps/wasteland_plan.json"
OUT = ROOT / "docs/maps/img"


# ------------------------------------------------------------------ données
def load() -> dict:
    return json.loads(PLAN.read_text(encoding="utf-8"))


def mirror_id(vid: str) -> str:
    m = re.match(r"^(.*)W(\d*)$", vid)
    return f"{m.group(1)}E{m.group(2)}" if m else vid + "_E"


def mirrored(plan: dict) -> bool:
    """Carte symétrique (v1–v6) : la moitié W est reflétée. Carte asymétrique (v7+) :
    ``mirror.enabled = false``, chaque volume est posé tel quel (moitiés W, C, E explicites)."""
    return plan.get("mirror", {}).get("enabled", True)


def expand(plan: dict) -> list[dict]:
    """Volumes après miroir : chaque volume « half: W » reçoit son jumeau E (x négatif).
    Sans miroir (carte asymétrique), les volumes sont renvoyés tels quels."""
    if not mirrored(plan):
        return [json.loads(json.dumps(v)) for v in plan["volumes"]]
    swap = plan["mirror"]["side_swap"]
    neg = set(plan["mirror"]["negate_offset_on_sides"])
    out = []
    for v in plan["volumes"]:
        out.append(v)
        if v.get("half") != "W":
            continue
        e = json.loads(json.dumps(v))
        e["id"] = mirror_id(v["id"])
        e["half"] = "E"
        if "label_e" in v:
            e["label"] = v["label_e"]
        if "x" in v:
            e["x"] = [-v["x"][1], -v["x"][0]]
        for key in ("from", "to"):
            if key in v:
                e[key] = [-v[key][0], *v[key][1:]]
        for opening in ("doors", "windows"):
            for o in e.get(opening, []):
                o["side"] = swap.get(o["side"], o["side"])
                if o["side"] in neg:
                    o["offset"] = -o.get("offset", 0.0)
        out.append(e)
    return out


def normalize(vols: list[dict]) -> list[dict]:
    """Proto TDM : écarte les volumes réservés à d'autres modes ; un segment 2D
    (muret, garde-corps, mur invisible : from/to en [x, z] + y, h, t) devient une boîte."""
    out = []
    for v in vols:
        modes = v.get("modes")
        if modes and "tdm" not in modes:
            continue
        if "from" in v and len(v["from"]) == 2:
            (x0, z0), (x1, z1) = v["from"], v["to"]
            t = v.get("t", 0.2) / 2
            b = dict(v)
            b.pop("from"), b.pop("to")
            b["x"] = [min(x0, x1) - (t if x0 == x1 else 0), max(x0, x1) + (t if x0 == x1 else 0)]
            b["z"] = [min(z0, z1) - (t if z0 == z1 else 0), max(z0, z1) + (t if z0 == z1 else 0)]
            b["y"] = [v.get("y", 0.0), v.get("y", 0.0) + v.get("h", 1.0)]
            out.append(b)
        else:
            out.append(v)
    return out


def color_of(plan: dict, v: dict) -> tuple[str, float]:
    mats = plan["materials"]
    m = mats["by_kind"].get(v["kind"], "wall")
    return mats[m]["color"], mats[m].get("alpha", 0.95)


def ramp_polygon(v: dict) -> list[tuple[float, float]]:
    (x0, _, z0), (x1, _, z1) = v["from"], v["to"]
    dx, dz = x1 - x0, z1 - z0
    ln = math.hypot(dx, dz) or 1.0
    nx, nz = -dz / ln * v["w"] / 2, dx / ln * v["w"] / 2
    return [(x0 + nx, z0 + nz), (x1 + nx, z1 + nz), (x1 - nx, z1 - nz), (x0 - nx, z0 - nz)]


def dims(v: dict) -> str:
    if "x" in v:
        w = v["x"][1] - v["x"][0]
        d = v["z"][1] - v["z"][0]
        h = v["y"][1] - v["y"][0]
        return f"{w:g}×{d:g} h{h:g}"
    if "from" in v:
        ln = math.dist((v["from"][0], v["from"][2]), (v["to"][0], v["to"][2]))
        rise = v["to"][1] - v["from"][1]
        return f"L{ln:g} l{v['w']:g} Δ{rise:+g}"
    return ""


# ------------------------------------------------------------------ vue de dessus
def draw_top(plan: dict, vols: list[dict]) -> Path:
    bx, bz = plan["bounds"]["x"], plan["bounds"]["z"]
    fig, ax = plt.subplots(figsize=(30, 17), dpi=110)
    ax.set_facecolor("#F4F1EA")
    # grille 1 m / 5 m
    for x in range(int(bx[0]) - 2, int(bx[1]) + 3):
        ax.axvline(x, color="#DAD4C7", lw=0.8 if x % 5 == 0 else 0.25, zorder=0)
    for z in range(int(bz[0]) - 2, int(bz[1]) + 3):
        ax.axhline(z, color="#DAD4C7", lw=0.8 if z % 5 == 0 else 0.25, zorder=0)
    # couloirs (une ou plusieurs zones par couloir : la carte asymétrique a des couloirs coudés)
    for lane in plan["lanes"]:
        regs = lane.get("regions") or [lane["region"]]
        for i, r in enumerate(regs):
            ax.add_patch(Rectangle((r["x"][0], r["z"][0]), r["x"][1] - r["x"][0], r["z"][1] - r["z"][0],
                                   fill=False, ec=lane["color"], lw=3, ls="--", zorder=1))
            if i == 0:
                ax.text(r["x"][0] + 0.3, r["z"][0] + 0.4, f"{lane['label']} ({lane['range']})",
                        color=lane["color"], fontsize=13, weight="bold", zorder=6, va="top")
    # volumes, du plus bas au plus haut
    order = {"ground": 0, "boundary": 1, "platform": 2, "slab": 2, "building": 3, "wall": 3, "solid": 3, "landmark": 3,
             "rock": 4, "fence": 4, "cover": 5, "barrier": 5, "stairs": 6, "ramp": 6, "inv_wall": 7, "clip": 7}
    for v in sorted(vols, key=lambda v: order.get(v["kind"], 5)):
        col, alpha = color_of(plan, v)
        if "from" in v:
            ax.add_patch(Polygon(ramp_polygon(v), closed=True, fc=col, ec="#2B2723", lw=1.2, alpha=alpha, zorder=4))
            cx = (v["from"][0] + v["to"][0]) / 2
            cz = (v["from"][2] + v["to"][2]) / 2
        else:
            x0, x1 = v["x"]
            z0, z1 = v["z"]
            ls = ":" if v["kind"] in ("inv_wall", "clip", "barrier") else "-"
            gfc = "#E9E3D6" if v["y"][1] >= -0.5 else "#D3C6AE"  # sol : plateau clair, canyon plus sombre
            ax.add_patch(Rectangle((x0, z0), x1 - x0, z1 - z0, fc=col if v["kind"] != "ground" else gfc,
                                   ec="#2B2723", lw=1.4 if v["kind"] == "building" else 0.9, ls=ls,
                                   alpha=alpha if v["kind"] != "ground" else 1.0, zorder=order.get(v["kind"], 5)))
            cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
            for d in v.get("doors", []):
                _draw_opening(ax, v, d, "#FFFFFF", 5)
            for w in v.get("windows", []):
                _draw_opening(ax, v, w, "#7FB7E0", 3)
        tiny = "x" in v and (v["x"][1] - v["x"][0]) * (v["z"][1] - v["z"][0]) < 0.5
        if v["kind"] not in ("ground", "boundary") and not tiny:
            ax.text(cx, cz, f"{v['id']}\n{dims(v)}", ha="center", va="center", fontsize=7.5, zorder=9,
                    color="#1D1A17", weight="bold" if v["kind"] == "building" else "normal")
    # repères
    mk = plan["markers"]
    for s in mk.get("team_spawns", []):
        for pos, team in _mirrored_points(s, plan):
            ax.plot(pos[0], pos[2], marker="^", ms=14, color="#2F6FD0" if team == 0 else "#D0308A", zorder=10)
    for s in mk.get("tdm_spawns", []):
        for pos, _ in _mirrored_points(s, plan):
            ax.plot(pos[0], pos[2], marker="o", ms=5, color="#555", zorder=10)
    # routes de sprint (équipe 0 bleu, équipe 1 rose) et front partagé de chaque couloir
    if not mirrored(plan):
        for lane in plan["lanes"]:
            for key, col in (("route_w", "#2F6FD0"), ("route_e", "#D0308A")):
                pts = lane.get(key)
                if pts:
                    ax.plot([p[0] for p in pts], [p[1] for p in pts], color=col, lw=1.6, ls="-", alpha=0.75,
                            zorder=11, marker=".", ms=4)
            if lane.get("front"):
                f = lane["front"]
                ax.plot(f[0], f[2], marker="X", ms=15, color=lane["color"], mec="#1D1A17", zorder=12)
        # positions fortes (étoile) : bleu équipe 0, rose équipe 1, gris centre
        for pp in mk.get("strong_positions", []):
            t = pp.get("team")
            col = "#2F6FD0" if t == 0 else "#D0308A" if t == 1 else "#777"
            p = pp["pos"]
            ax.plot(p[0], p[2], marker="*", ms=22, color=col, mec="#1D1A17", zorder=12)
            ax.text(p[0] + 0.6, p[2] - 0.6, pp["id"], fontsize=10, weight="bold", color=col, zorder=12)
        for txt, x, col in (("OUEST — la Ville (équipe 0)", bx[0] + 1, "#2F6FD0"),
                            ("EST — la Gare de fret et la Mine (équipe 1)", bx[1] - 1, "#D0308A")):
            ax.text(x, bz[1] + 1.4, txt, fontsize=16, weight="bold", color=col, zorder=12,
                    ha="left" if x < 0 else "right", va="center")
    ax.set_xlim(bx[0] - 2, bx[1] + 2)
    ax.set_ylim(bz[1] + 2, bz[0] - 2)  # nord en haut (z négatif = nord)
    ax.set_aspect("equal")
    ax.set_xlabel("x (m) — ouest ← → est", fontsize=12)
    ax.set_ylabel("z (m) — nord ↑", fontsize=12)
    ax.set_title("Wasteland — plan coté (vue de dessus, grille 1 m / 5 m) — ▲ bleu/rose : apparitions d'équipe, "
                 "• : apparitions TDM, ★ : positions fortes, X : fronts, traits : routes de sprint — "
                 "cotes : largeur×profondeur h hauteur", fontsize=15)
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / "wasteland_plan_top.png"
    fig.savefig(path, bbox_inches="tight")
    plt.close(fig)
    return path


def _mirrored_points(s: dict, plan: dict):
    pos, team = s["pos"], s.get("team", 0)
    yield pos, team
    if s.get("half") == "W" and mirrored(plan):
        yield [-pos[0], pos[1], pos[2]], 1 - team


def _draw_opening(ax, v: dict, o: dict, color: str, lw: float) -> None:
    x0, x1 = v["x"]
    z0, z1 = v["z"]
    kind = o.get("type", "std")
    w = 1.2 if "type" not in o else {"std": 1.2, "M": 1.6, "L": 2.4}.get(kind, 1.2)
    off = o.get("offset", 0.0)
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    side = o["side"]
    if side in ("N", "S"):
        z = z0 if side == "N" else z1
        ax.plot([cx + off - w / 2, cx + off + w / 2], [z, z], color=color, lw=lw, zorder=8, solid_capstyle="butt")
    else:
        x = x0 if side == "W" else x1
        ax.plot([x, x], [cz + off - w / 2, cz + off + w / 2], color=color, lw=lw, zorder=8, solid_capstyle="butt")


# ------------------------------------------------------------------ coupes
def draw_section(plan: dict, vols: list[dict], axis: str, at: float, name: str, title: str) -> Path:
    fig, ax = plt.subplots(figsize=(30, 7), dpi=110)
    ax.set_facecolor("#F4F1EA")
    for v in vols:
        if "x" not in v:
            continue
        lo, hi = (v["x"] if axis == "x" else v["z"])
        if not (lo <= at <= hi):
            continue
        a0, a1 = (v["z"] if axis == "x" else v["x"])
        y0, y1 = v["y"]
        col, alpha = color_of(plan, v)
        ax.add_patch(Rectangle((a0, y0), a1 - a0, y1 - y0, fc=col, ec="#2B2723", lw=1, alpha=alpha))
        if v["kind"] not in ("ground",):
            ax.text((a0 + a1) / 2, y1 + 0.15, f"{v['id']} h{y1 - y0:g}", ha="center", fontsize=8, rotation=0)
    for yl, lab in ((plan["levels"]["canyon"], "canyon −2"), (0.0, "sol 0"), (plan["levels"]["upper"], "étage 3,2")):
        ax.axhline(yl, color="#999", lw=0.8, ls="--")
        ax.text(ax.get_xlim()[0], yl, lab, fontsize=9, va="bottom")
    rng = plan["bounds"]["z"] if axis == "x" else plan["bounds"]["x"]
    ax.set_xlim(rng[0] - 1, rng[1] + 1)
    ax.set_ylim(-3, 16)
    ax.set_aspect("equal")
    ax.set_xlabel(("z (m) nord → sud" if axis == "x" else "x (m) ouest → est"))
    ax.set_ylabel("y (m)")
    ax.set_title(title, fontsize=14)
    path = OUT / name
    fig.savefig(path, bbox_inches="tight")
    plt.close(fig)
    return path


# ------------------------------------------------------------------ vue 3D
def _box_faces(x0, x1, y0, y1, z0, z1):
    # matplotlib 3D : (x, y, z) = (x monde, z monde, y monde) pour avoir la hauteur en haut
    p = [(x0, z0, y0), (x1, z0, y0), (x1, z1, y0), (x0, z1, y0),
         (x0, z0, y1), (x1, z0, y1), (x1, z1, y1), (x0, z1, y1)]
    idx = [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (2, 3, 7, 6), (1, 2, 6, 5), (0, 3, 7, 4)]
    return [[p[i] for i in f] for f in idx]


def draw_axo(plan: dict, vols: list[dict]) -> Path:
    fig = plt.figure(figsize=(24, 14), dpi=100)
    ax = fig.add_subplot(111, projection="3d")
    # Le tri en profondeur de mplot3d ne gère pas les grandes dalles : le sol et les
    # falaises de bord sont tracés en contours, seuls les volumes sont pleins.
    for v in vols:
        if v["kind"] in ("ground", "boundary") and "x" in v:
            x0, x1 = v["x"]
            z0, z1 = v["z"]
            y = v["y"][1]
            ax.plot([x0, x1, x1, x0, x0], [z0, z0, z1, z1, z0], [y, y, y, y, y], color="#8C8475", lw=0.8)
    for v in vols:
        if v["kind"] in ("inv_wall", "clip", "barrier", "ground", "boundary"):
            continue
        col, _ = color_of(plan, v)
        if "x" in v:
            faces = _box_faces(v["x"][0], v["x"][1], v["y"][0], v["y"][1], v["z"][0], v["z"][1])
        else:
            poly = ramp_polygon(v)
            y0, y1 = v["from"][1], v["to"][1]
            top = [(poly[0][0], poly[0][1], y0), (poly[1][0], poly[1][1], y1),
                   (poly[2][0], poly[2][1], y1), (poly[3][0], poly[3][1], y0)]
            faces = [top]
        ax.add_collection3d(Poly3DCollection(faces, facecolors=col, edgecolors="#2B2723", linewidths=0.3,
                                             alpha=0.95))
    bx, bz = plan["bounds"]["x"], plan["bounds"]["z"]
    ax.set_xlim(bx[0], bx[1])
    ax.set_ylim(bz[1], bz[0])
    ax.set_zlim(-3, 20)
    ax.set_box_aspect((bx[1] - bx[0], bz[1] - bz[0], 23))
    ax.view_init(elev=38, azim=-62)
    ax.set_title("Wasteland — vue 3D des volumes (greybox)", fontsize=15)
    ax.set_axis_off()
    path = OUT / "wasteland_plan_3d.png"
    fig.savefig(path, bbox_inches="tight")
    plt.close(fig)
    return path


def write_csv(vols: list[dict]) -> Path:
    path = ROOT / "docs/maps/wasteland_volumes.csv"
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["id", "kind", "label", "x0", "x1", "z0", "z1", "y0", "y1", "largeur", "profondeur", "hauteur",
                    "etages", "portes", "fenetres"])
        for v in vols:
            if "x" in v:
                w.writerow([v["id"], v["kind"], v.get("label", ""), *v["x"], *v["z"], *v["y"],
                            round(v["x"][1] - v["x"][0], 2), round(v["z"][1] - v["z"][0], 2),
                            round(v["y"][1] - v["y"][0], 2), v.get("floors", ""),
                            len(v.get("doors", [])), len(v.get("windows", []))])
            else:
                w.writerow([v["id"], v["kind"], v.get("label", ""), v["from"][0], v["to"][0], v["from"][2],
                            v["to"][2], v["from"][1], v["to"][1], v.get("w", ""), "", "", "", "", ""])
    return path



# ------------------------------------------------------------------ document
def _fmt(x: float) -> str:
    return f"{x:g}".replace(".", ",")


def write_doc(plan: dict, vols: list[dict]) -> Path:
    m = plan["metrics"]
    pl = m["player"]
    NL = "\n"
    L: list[str] = []
    L.append("# Wasteland — plan coté (greybox)" + NL)
    L.append("Document GÉNÉRÉ par `python tools/maps/render_plan.py` depuis la source unique "
             "`data/maps/wasteland_plan.json` : ne pas l'éditer à la main (modifier le JSON puis relancer). "
             "La carte en jeu est construite depuis le même JSON." + NL)
    L.append("Axes : x ouest→est, z nord→sud (z négatif = nord), y vertical ; unités en mètres ; "
             f"bornes x {_fmt(plan['bounds']['x'][0])}…{_fmt(plan['bounds']['x'][1])}, "
             f"z {_fmt(plan['bounds']['z'][0])}…{_fmt(plan['bounds']['z'][1])} ; "
             + ("moitié ouest décrite, moitié est = miroir en x (suffixe W → E)." if mirrored(plan) else
                "carte ASYMÉTRIQUE : moitiés ouest (W), centre (C) et est (E) décrites explicitement, sans miroir.")
             + NL)
    for img, alt in (("wasteland_plan_top.png", "Vue de dessus"), ("wasteland_plan_3d.png", "Vue 3D"),
                     ("wasteland_coupe_ns.png", "Coupe nord-sud"), ("wasteland_coupe_oe.png", "Coupe ouest-est"),
                     ("wasteland_coupe_sud.png", "Coupe du canyon")):
        L.append(f"![{alt}](img/{img})" + NL)
    L.append("## Métriques" + NL)
    L.append("| Élément | Valeur |")
    L.append("|---|---|")
    L.append(f"| Joueur | rayon {_fmt(pl['radius'])}, hauteur {_fmt(pl['height'])} (accroupi {_fmt(pl['crouch_height'])}), "
             f"yeux {_fmt(pl['eye'])} ; marche {_fmt(pl['walk'])} m/s, sprint {_fmt(pl['sprint'])} m/s ; "
             f"marche franchissable {_fmt(pl['step_up'])} ; stun de chute dès {_fmt(pl['fall_stun_min'])} |")
    L.append(f"| Niveaux | canyon {_fmt(plan['levels']['canyon'])}, sol {_fmt(plan['levels']['ground'])}, "
             f"étage {_fmt(plan['levels']['upper'])} |")
    L.append(f"| Portes | std {_fmt(m['doors']['std']['w'])}×{_fmt(m['doors']['std']['h'])}, "
             f"M {_fmt(m['doors']['M']['w'])}, L {_fmt(m['doors']['L']['w'])} |")
    L.append(f"| Fenêtres | {_fmt(m['window']['w'])}×{_fmt(m['window']['h'])}, allège {_fmt(m['window']['sill'])} |")
    L.append(f"| Couverts | C1 {_fmt(m['cover']['C1'])} (accroupi), C2 {_fmt(m['cover']['C2'])} (debout), "
             f"C3 {_fmt(m['cover']['C3'])} (plein) |")
    st = m["stair"]
    L.append(f"| Escaliers | marche {_fmt(st['step_rise'])}/{_fmt(st['step_run'])}, volée {_fmt(st['flight_rise'])} "
             f"sur {_fmt(st['flight_run'])}, largeur ≥ {_fmt(st['width_min'])} |")
    L.append(f"| Étage / murs | hauteur d'étage {_fmt(m['storey'])}, murs {_fmt(m['wall_t'])}, dalles {_fmt(m['slab_t'])} |")
    L.append(f"| Toits | pente {_fmt(m['roof']['pitch_deg'])}°, volume anti-joueur jusqu'à {_fmt(m['roof']['clip_h'])} |")
    L.append("")
    L.append("## Couloirs" + NL)
    L.append("| Couloir | Portée | Niveau | Zone x | Zone z | Largeurs |")
    L.append("|---|---|---|---|---|---|")
    for ln in plan["lanes"]:
        regs = ln.get("regions") or [ln["region"]]
        widths = " ; ".join(f"{w['what']} {_fmt(w['w'])}" for w in ln.get("widths", []))
        zx = " + ".join(f"{_fmt(r['x'][0])}…{_fmt(r['x'][1])}" for r in regs)
        zz = " + ".join(f"{_fmt(r['z'][0])}…{_fmt(r['z'][1])}" for r in regs)
        L.append(f"| {ln['label']} | {ln['range']} | {_fmt(ln['level'])} | {zx} | {zz} | {widths} |")
    L.append("")

    def table(title: str, kinds: tuple[str, ...]) -> None:
        rows = [v for v in vols if v["kind"] in kinds]
        if not rows:
            return
        L.append(f"## {title}" + NL)
        L.append("| Id | Nom | x | z | y | L×P×H | Étages | Portes | Fenêtres |")
        L.append("|---|---|---|---|---|---|---|---|---|")
        for v in rows:
            if "x" in v:
                doors = ", ".join(f"{d['side']}{d.get('floor', 0)} {d.get('type', 'std')} @{_fmt(d.get('offset', 0))}"
                                  for d in v.get("doors", []))
                wins = ", ".join(f"{w['side']}{w.get('floor', 0)} @{_fmt(w.get('offset', 0))}"
                                 for w in v.get("windows", []))
                L.append(f"| {v['id']} | {v.get('label', '')} | {_fmt(v['x'][0])}…{_fmt(v['x'][1])} | "
                         f"{_fmt(v['z'][0])}…{_fmt(v['z'][1])} | {_fmt(v['y'][0])}…{_fmt(v['y'][1])} | {dims(v)} | "
                         f"{v.get('floors', '')} | {doors} | {wins} |")
            else:
                L.append(f"| {v['id']} | {v.get('label', '')} | {_fmt(v['from'][0])}→{_fmt(v['to'][0])} | "
                         f"{_fmt(v['from'][2])}→{_fmt(v['to'][2])} | {_fmt(v['from'][1])}→{_fmt(v['to'][1])} | "
                         f"{dims(v)} | | | |")
        L.append("")

    table("Bâtiments", ("building",))
    table("Volumes pleins et repères", ("solid", "landmark", "wall"))
    table("Dalles et paliers", ("slab",))
    table("Escaliers et rampes", ("stairs", "ramp"))
    table("Couverts, murets, rochers", ("cover", "fence", "rock"))
    table("Limites et murs invisibles", ("boundary", "barrier", "inv_wall", "clip"))
    L.append("## Apparitions" + NL)
    L.append("| Équipe | Position | Regard |")
    L.append("|---|---|---|")
    for sp in plan["markers"].get("team_spawns", []):
        for pos, team in _mirrored_points(sp, plan):
            L.append(f"| {team} | ({_fmt(pos[0])}, {_fmt(pos[1])}, {_fmt(pos[2])}) | {sp.get('look', '')} |")
    L.append("")
    path = ROOT / "docs/maps/WASTELAND_PLAN.md"
    path.write_text(NL.join(L) + NL, encoding="utf-8")
    return path



def main() -> None:
    plan = load()
    vols = normalize(expand(plan))
    paths = [draw_top(plan, vols),
             draw_section(plan, vols, "x", 0.0, "wasteland_coupe_ns.png",
                          "Coupe nord–sud par le Wagon (x = 0)"),
             draw_section(plan, vols, "z", -14.0, "wasteland_coupe_oe.png",
                          "Coupe ouest–est le long de la Grand-Rue et des Voies (z = −14)"),
             draw_section(plan, vols, "z", 16.0, "wasteland_coupe_sud.png",
                          "Coupe ouest–est dans le Ravin et la Tranchée de la mine (z = 16)"),
             draw_axo(plan, vols),
             write_csv(vols),
             write_doc(plan, vols)]
    print(f"{len(vols)} volumes après miroir")
    for p in paths:
        print("OK", p.relative_to(ROOT))


if __name__ == "__main__":
    main()
