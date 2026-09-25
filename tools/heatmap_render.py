#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""heatmap_render.py

LD-08 (docs/research/03_level_design.md §2.8, dépend de FUN-05) : seconde
moitié de l'outil de heatmap — rasterise en PNG le manifeste JSON produit par
tools/heatmap.gd (grille de kills/morts calée sur les bounds réels de la
map). Numpy/Pillow purs (déjà des dépendances du dépôt, cf.
tools/textures/gen_textures.py) : aucun rendu 3D, aucune dépendance à Godot
ici, pour rester rapide et indépendant du moteur.

Produit 3 PNG top-down par grille : kills, morts, et leur différence
(kills − morts) — "Bungie calculait les heatmaps de kills et de morts de
Halo 3... la recherche compare aussi kills, morts et leur différence. La
carte différence montre les positions dominantes" (docs/research/
03_level_design.md §2.8).

Convention de grille (partagée avec heatmap.gd, cf. sa doc d'en-tête) :
`grid[row][col]`, col croît avec X, row croît avec Z, row 0 = bounds.min.z.
Ce script affiche row 0 EN BAS de l'image (Z croissant vers le haut, la
convention "vue du dessus, nord en haut" des feuilles de référence maps) —
une simple inversion verticale du tableau avant rasterisation.

Usage :
    python tools/heatmap_render.py <grid.json> [--out-dir=DIR] [--cell-px=28]

Écrit "<out_dir>/<map_id>_kills.png", "<out_dir>/<map_id>_deaths.png" et
"<out_dir>/<map_id>_diff.png" (out_dir par défaut : le dossier du fichier
d'entrée). Imprime `HEATMAP_PNG <type> <chemin>` par fichier puis
`HEATMAP_RENDER_DONE <n> fichiers -> <out_dir>`, ou `HEATMAP_RENDER_FAIL
<raison>` (code 1) sur une entrée invalide.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# --------------------------------------------------------------------------- palette
# Fond sombre volontaire (les cellules à 0 se fondent dedans — cf. `_apply_stops`
# dont le premier stop == BG_COLOR) plutôt qu'un blanc qui écraserait la lecture
# des zones réellement chaudes.
BG_COLOR = (18, 20, 24)
TEXT_COLOR = (222, 224, 228)
AXIS_COLOR = (150, 153, 160)
GRID_MINOR = (255, 255, 255, 46)
GRID_MAJOR = (255, 255, 255, 120)

# Dégradé séquentiel (kills/morts) : fond -> violet -> magenta -> orange ->
# jaune pâle, à la "hot"/"inferno" — le premier stop est EXACTEMENT BG_COLOR
# pour qu'une cellule à 0 kill disparaisse dans le fond.
HEAT_STOPS: list[tuple[float, tuple[int, int, int]]] = [
    (0.00, BG_COLOR),
    (0.15, (43, 20, 68)),
    (0.40, (124, 32, 93)),
    (0.65, (214, 62, 46)),
    (0.85, (247, 148, 32)),
    (1.00, (255, 236, 140)),
]

# Dégradé divergent (différence kills − morts) : bleu (morts dominantes) au
# neutre (== BG_COLOR, diff == 0) au rouge (kills dominants) — mêmes teintes
# que HEAT_STOPS aux extrêmes pour rester lisible à côté des deux autres PNG.
DIFF_NEG = (58, 122, 214)
DIFF_NEUTRAL = BG_COLOR
DIFF_POS = (224, 74, 51)

MARGIN_L, MARGIN_T, MARGIN_R, MARGIN_B = 76, 64, 32, 96
LEGEND_H = 16


def _apply_stops(t: np.ndarray, stops: list[tuple[float, tuple[int, int, int]]]) -> np.ndarray:
    """Interpole `t` (0..1) dans `stops` -> tableau RGB float (…,3), un canal à
    la fois (np.interp est 1D)."""
    positions = np.array([s[0] for s in stops])
    colors = np.array([s[1] for s in stops], dtype=float)
    out = np.empty(t.shape + (3,), dtype=float)
    flat_t = t.reshape(-1)
    for c in range(3):
        out.reshape(-1, 3)[:, c] = np.interp(flat_t, positions, colors[:, c])
    return out


def _sequential_rgb(values: np.ndarray, vmax: float) -> np.ndarray:
    t = np.clip(values / vmax, 0.0, 1.0) if vmax > 0 else np.zeros_like(values)
    return _apply_stops(t, HEAT_STOPS)


def _diverging_rgb(values: np.ndarray, vmax_abs: float) -> np.ndarray:
    if vmax_abs <= 0:
        return np.broadcast_to(np.array(DIFF_NEUTRAL, dtype=float), values.shape + (3,)).copy()
    t_pos = np.clip(values, 0, None) / vmax_abs
    t_neg = np.clip(-values, 0, None) / vmax_abs
    neutral = np.array(DIFF_NEUTRAL, dtype=float)
    pos = np.array(DIFF_POS, dtype=float)
    neg = np.array(DIFF_NEG, dtype=float)
    out = neutral + t_pos[..., None] * (pos - neutral) + t_neg[..., None] * (neg - neutral)
    return out


def _grid_to_image(rgb: np.ndarray, cell_px: int) -> Image.Image:
    """(grid_h, grid_w, 3) float 0..255 -> Image RGBA agrandie `cell_px`/cellule,
    row 0 (bounds.min.z) placée EN BAS (voir doc d'en-tête : inversion Z)."""
    big = np.repeat(np.repeat(rgb, cell_px, axis=0), cell_px, axis=1)
    big = big[::-1]  # row 0 (min z) -> bas de l'image
    return Image.fromarray(np.clip(big, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def _draw_grid_lines(img: Image.Image, grid_w: int, grid_h: int, cell_px: int, cell_size: float) -> Image.Image:
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    major_every = max(1, round(10.0 / cell_size))  # une ligne appuyée tous les ~10 m
    w_px, h_px = img.size
    for col in range(grid_w + 1):
        x = col * cell_px
        color = GRID_MAJOR if col % major_every == 0 else GRID_MINOR
        draw.line([(x, 0), (x, h_px)], fill=color, width=1)
    for row in range(grid_h + 1):
        y = row * cell_px
        color = GRID_MAJOR if row % major_every == 0 else GRID_MINOR
        draw.line([(0, y), (w_px, y)], fill=color, width=1)
    return Image.alpha_composite(img, overlay)


def _font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.load_default(size=size)


def _draw_legend(
    canvas: Image.Image,
    draw: ImageDraw.ImageDraw,
    x: int,
    y: int,
    w: int,
    stops: list[tuple[float, tuple[int, int, int]]],
    lo_label: str,
    hi_label: str,
) -> None:
    steps = max(w, 2)
    t = np.linspace(0.0, 1.0, steps)
    rgb = _apply_stops(t, stops)
    row = np.clip(rgb, 0, 255).astype(np.uint8).reshape(1, steps, 3)
    bar = Image.fromarray(np.repeat(row, LEGEND_H, axis=0), "RGB")
    canvas.paste(bar, (x, y))
    font = _font(13)
    draw.text((x, y + LEGEND_H + 2), lo_label, fill=AXIS_COLOR, font=font, anchor="la")
    draw.text((x + w, y + LEGEND_H + 2), hi_label, fill=AXIS_COLOR, font=font, anchor="ra")


def _render_panel(
    out_path: Path,
    title: str,
    grid_values: np.ndarray,
    grid_w: int,
    grid_h: int,
    cell_px: int,
    cell_size: float,
    diverging: bool,
    scale_max: float,
) -> None:
    if diverging:
        rgb = _diverging_rgb(grid_values, scale_max)
        legend_stops = [(0.0, DIFF_NEG), (0.5, DIFF_NEUTRAL), (1.0, DIFF_POS)]
        lo_label, hi_label = f"-{scale_max:.0f}", f"+{scale_max:.0f}"
    else:
        rgb = _sequential_rgb(grid_values, scale_max)
        legend_stops = HEAT_STOPS
        lo_label, hi_label = "0", f"{scale_max:.0f}"

    heat = _grid_to_image(rgb, cell_px)
    heat = _draw_grid_lines(heat, grid_w, grid_h, cell_px, cell_size)
    w_px, h_px = heat.size

    canvas_w = w_px + MARGIN_L + MARGIN_R
    canvas_h = h_px + MARGIN_T + MARGIN_B
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (*BG_COLOR, 255))
    canvas.paste(heat, (MARGIN_L, MARGIN_T), heat)
    draw = ImageDraw.Draw(canvas)

    draw.text((MARGIN_L, 18), title, fill=TEXT_COLOR, font=_font(20))

    major_every = max(1, round(10.0 / cell_size))
    small = _font(12)
    for col in range(0, grid_w + 1, major_every):
        x = MARGIN_L + col * cell_px
        draw.text((x, MARGIN_T + h_px + 6), f"{col * cell_size:.0f}m", fill=AXIS_COLOR, font=small, anchor="ma")
    for row in range(0, grid_h + 1, major_every):
        y = MARGIN_T + h_px - row * cell_px  # row 0 (min z) en bas -> voir _grid_to_image
        draw.text((MARGIN_L - 8, y), f"{row * cell_size:.0f}m", fill=AXIS_COLOR, font=small, anchor="rm")

    _draw_legend(canvas, draw, MARGIN_L, canvas_h - 34, min(220, w_px), legend_stops, lo_label, hi_label)

    canvas.convert("RGB").save(out_path)


def render(grid_path: Path, out_dir: Path, cell_px: int) -> list[Path]:
    data = json.loads(grid_path.read_text(encoding="utf-8"))
    for key in ("map_id", "cell_size", "grid_w", "grid_h", "kills", "deaths"):
        if key not in data:
            raise ValueError(f"champ manquant dans {grid_path} : {key}")

    map_id = str(data["map_id"])
    cell_size = float(data["cell_size"])
    grid_w = int(data["grid_w"])
    grid_h = int(data["grid_h"])
    kills = np.array(data["kills"], dtype=float)
    deaths = np.array(data["deaths"], dtype=float)
    if kills.shape != (grid_h, grid_w) or deaths.shape != (grid_h, grid_w):
        raise ValueError(
            f"forme de grille incohérente dans {grid_path} : "
            f"attendu ({grid_h}, {grid_w}), reçu kills={kills.shape} deaths={deaths.shape}"
        )
    diff = kills - deaths
    shared_max = max(float(kills.max(initial=0.0)), float(deaths.max(initial=0.0)), 1.0)
    diff_max = max(float(np.abs(diff).max(initial=0.0)), 1.0)

    out_dir.mkdir(parents=True, exist_ok=True)
    kill_count = int(data.get("kill_count", int(kills.sum())))
    death_count = int(data.get("death_count", int(deaths.sum())))

    panels = [
        # Tiret ASCII (pas "—"/"−") : la police par défaut de Pillow
        # (ImageFont.load_default) n'a pas ces glyphes et affiche un tofu.
        ("kills", f"{map_id} - kills ({kill_count})", kills, False, shared_max),
        ("deaths", f"{map_id} - morts ({death_count})", deaths, False, shared_max),
        ("diff", f"{map_id} - kills moins morts", diff, True, diff_max),
    ]
    written: list[Path] = []
    for suffix, title, values, diverging, scale_max in panels:
        out_path = out_dir / f"{map_id}_{suffix}.png"
        _render_panel(out_path, title, values, grid_w, grid_h, cell_px, cell_size, diverging, scale_max)
        written.append(out_path)
    return written


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Rasterise le manifeste de tools/heatmap.gd en 3 PNG (kills/morts/différence).")
    parser.add_argument("grid_json", type=Path, help="manifeste JSON écrit par tools/heatmap.gd")
    parser.add_argument("--out-dir", type=Path, default=None, help="dossier de sortie (défaut : dossier du manifeste)")
    parser.add_argument("--cell-px", type=int, default=28, help="pixels par cellule de grille (défaut 28)")
    args = parser.parse_args(argv[1:])

    if not args.grid_json.is_file():
        print(f"HEATMAP_RENDER_FAIL manifeste introuvable : {args.grid_json}", file=sys.stderr)
        return 1
    if args.cell_px <= 0:
        print("HEATMAP_RENDER_FAIL --cell-px doit être > 0", file=sys.stderr)
        return 1

    out_dir = args.out_dir if args.out_dir is not None else args.grid_json.resolve().parent

    try:
        written = render(args.grid_json, out_dir, args.cell_px)
    except (ValueError, KeyError, json.JSONDecodeError, OSError) as exc:
        print(f"HEATMAP_RENDER_FAIL {exc}", file=sys.stderr)
        return 1

    for suffix, path in zip(("kills", "deaths", "diff"), written):
        print(f"HEATMAP_PNG {suffix} {path}")
    print(f"HEATMAP_RENDER_DONE {len(written)} fichiers -> {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
