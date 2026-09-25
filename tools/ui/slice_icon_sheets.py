#!/usr/bin/env python3
"""Découpe les planches d'icônes de capacités Tripo (UX-21).

Deux planches 4x4 (1024x1024, cases séparées par une fine gouttière noire,
pictogramme crème à encre noire sur fond anthracite) génèrent 30 PNG 128x128
au fond détouré en alpha : `assets/ui/icons/abilities/<agent>_<slot>.png`.

Chaque planche porte 3 agents x 5 cases (passif, C, Q, E signature, X ultime,
dans l'ordre des colonnes de docs/AGENTS.md), la 16e case de chaque planche
est ignorée. La découpe repère les cases par détection des gouttières noires
(jamais une grille fixe supposée) ; le détourage remplit le fond depuis les
coins de chaque case avec un seuil de couleur, sans jamais toucher l'encre
noire des traits.

Usage : `python tools/ui/slice_icon_sheets.py` depuis la racine du dépôt.
"""

from __future__ import annotations

import argparse
from collections import deque
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

# ---------------------------------------------------------------------------
# Constantes de découpe
# ---------------------------------------------------------------------------

GRID_SIZE = 4  # planche 4x4 (16 cases, 15 utilisées, la 16e est ignorée)
ICON_SIZE = 128

# Détection des gouttières : un pixel "de gouttière" est quasi noir (encre).
GUTTER_BLACK_MAX = 35            # luminance max (0-255) pour compter comme encre
GUTTER_ROW_COL_FRACTION = 0.85   # fraction d'une ligne/colonne qui doit l'être
GUTTER_MERGE_GAP = 3             # px : fusionne deux bandes noires quasi jointives
MIN_SEGMENT_FRACTION = 0.10      # écarte les interstices résiduels entre bordures
# doublées (planche 2 : chaque case a sa propre bordure, il reste un mince fond
# entre deux cases voisines -- ce n'est pas une case, on le filtre par taille).

# Détourage : remplissage du fond depuis les BORDS de chaque case (jamais
# quelques coins supposés fond -- un picto peut aller jusqu'au bord, ex. la
# fumée de Rideau/Guet touche le haut de sa case : y semer un point fixe y
# lirait la couleur de la fumée comme "le fond" et mangerait le picto).
BG_FLOOD_THRESHOLD = 42   # tolérance de couleur (somme des écarts par canal)
CELL_CROP_MARGIN = 4      # px : recul depuis la boîte détectée avant découpe,
# pour ne jamais capturer la frange anti-crénelée de la gouttière (un pixel
# de transition gouttière -> fond n'est ni assez noir pour être compté comme
# gouttière au repérage, ni assez proche du fond pour être rempli au seuil).

# Ordre des 5 cases par agent (docs/AGENTS.md : Passif, C, Q, E signature, X ultime).
SLOT_ORDER = ("passive", "c", "q", "e", "x")


@dataclass(frozen=True)
class SheetSpec:
    """Une planche source : son chemin et ses 3 agents, dans l'ordre des cases."""

    path: Path
    agents: tuple[str, str, str]


# Planches générées le 2026-09-25 (voir docs/tasks -- tâche UX-21).
SHEETS: tuple[SheetSpec, ...] = (
    SheetSpec(
        Path("assets/incoming/tripo/icons/icons_sheet_1_vif_choc_vanne.png"),
        ("vif", "choc", "vanne"),
    ),
    SheetSpec(
        Path("assets/incoming/tripo/icons/icons_sheet_2_guet_roseau_verrou.png"),
        ("guet", "roseau", "verrou"),
    ),
)

DEFAULT_OUTPUT_DIR = Path("assets/ui/icons/abilities")


# ---------------------------------------------------------------------------
# Détection de la grille (gouttières)
# ---------------------------------------------------------------------------


def _merge_bands(indices: list[int], merge_gap: int) -> list[tuple[int, int]]:
    """Regroupe une liste d'indices triés en bandes (start, end) contiguës,
    en tolérant un écart d'au plus `merge_gap` px entre deux indices."""
    if not indices:
        return []
    bands: list[tuple[int, int]] = []
    start = prev = indices[0]
    for idx in indices[1:]:
        if idx - prev <= merge_gap:
            prev = idx
            continue
        bands.append((start, prev))
        start = prev = idx
    bands.append((start, prev))
    return bands


def find_axis_segments(
    black_mask: np.ndarray,
    axis: int,
    length: int,
    count: int,
) -> list[tuple[int, int]]:
    """Repère les `count` cases d'un axe (lignes ou colonnes) à partir des
    bandes quasi noires (gouttières) : une fine ligne unique entre deux cases
    (planche 1), ou une double bordure avec un interstice de fond entre deux
    cases (planche 2). Renvoie les segments (start, end) inclusifs, triés,
    en ignorant les interstices trop étroits pour être une case.

    Lève `ValueError` si le nombre de cases détectées ne vaut pas `count` :
    mieux vaut échouer que découper une planche mal repérée en silence.
    """
    frac = black_mask.mean(axis=axis)
    black_idx = [i for i in range(length) if frac[i] >= GUTTER_ROW_COL_FRACTION]
    bands = _merge_bands(black_idx, GUTTER_MERGE_GAP)

    segments: list[tuple[int, int]] = []
    prev_end = -1
    for band_start, band_end in (*bands, (length, length)):
        seg_start, seg_end = prev_end + 1, band_start - 1
        if seg_end - seg_start + 1 >= length * MIN_SEGMENT_FRACTION:
            segments.append((seg_start, seg_end))
        prev_end = band_end

    if len(segments) != count:
        raise ValueError(
            f"{count} cases attendues sur cet axe, {len(segments)} détectées "
            f"(bandes de gouttière : {bands}) -- planche mal repérée."
        )
    return segments


def detect_cells(
    image: Image.Image, grid_size: int = GRID_SIZE
) -> list[tuple[int, int, int, int]]:
    """Renvoie les `grid_size`² boîtes (x0, y0, x1, y1) inclusives des cases
    de la planche, ligne par ligne (comme dans les notes de la tâche UX-21),
    gouttières exclues."""
    arr = np.asarray(image.convert("RGB"), dtype=np.int16)
    black = arr.max(axis=2) <= GUTTER_BLACK_MAX
    h, w = black.shape

    col_segments = find_axis_segments(black, axis=0, length=w, count=grid_size)
    row_segments = find_axis_segments(black, axis=1, length=h, count=grid_size)

    cells: list[tuple[int, int, int, int]] = []
    for y0, y1 in row_segments:
        for x0, x1 in col_segments:
            cells.append((x0, y0, x1, y1))
    return cells


# ---------------------------------------------------------------------------
# Détourage (fond anthracite -> alpha)
# ---------------------------------------------------------------------------


def sheet_background_color(image: Image.Image) -> tuple[int, int, int]:
    """Couleur de référence du fond anthracite d'UNE planche entière : la
    médiane par canal sur toute l'image. Le fond couvre largement la
    majorité des pixels (16 cases, chacune bien plus de fond que de picto),
    donc la médiane globale est robuste même si un picto touche localement
    le bord de sa case (ex. la fumée de Rideau) -- un seuillage par case
    prendrait alors, à tort, la couleur du picto comme "le fond" de cette case."""
    arr = np.asarray(image.convert("RGB"), dtype=np.int16)
    med = np.median(arr.reshape(-1, 3), axis=0)
    return int(med[0]), int(med[1]), int(med[2])


def remove_background(
    cell: Image.Image,
    background_rgb: tuple[int, int, int],
    threshold: int = BG_FLOOD_THRESHOLD,
) -> Image.Image:
    """Détoure le fond anthracite en alpha : remplissage depuis les BORDS de
    la case, jamais depuis un point fixe supposé fond (un picto peut aller
    jusqu'au bord de sa case). Seuls les pixels de bord déjà proches de
    `background_rgb` amorcent le remplissage ; il se propage ensuite, de
    proche en proche (4-connexité), aux seuls pixels eux aussi proches de
    `background_rgb` -- jamais à l'encre noire des traits ni aux teintes du
    picto, qui en sont loin par construction (§0 : fond anthracite ~(51,51,51),
    encre proche de 0, crème/orange loin au-dessus de 150)."""
    rgba = cell.convert("RGBA")
    arr = np.array(rgba)
    h, w = arr.shape[:2]
    rgb = arr[..., :3].astype(np.int32)
    diff = np.abs(rgb - np.array(background_rgb, dtype=np.int32)).sum(axis=2)
    is_bg_color = diff <= threshold

    border = np.zeros((h, w), dtype=bool)
    border[0, :] = border[-1, :] = True
    border[:, 0] = border[:, -1] = True
    seed_mask = is_bg_color & border

    visited = seed_mask.copy()
    queue: deque[tuple[int, int]] = deque(zip(*np.nonzero(seed_mask)))
    while queue:
        y, x = queue.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx] and is_bg_color[ny, nx]:
                visited[ny, nx] = True
                queue.append((ny, nx))

    out = arr.copy()
    out[visited, 3] = 0
    return Image.fromarray(out, mode="RGBA")


def _unpremultiply(rgb_premult: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    out = np.zeros_like(rgb_premult)
    mask = (alpha > 0)[..., 0]
    out[mask] = rgb_premult[mask] / alpha[mask]
    return out


def resize_icon(rgba: Image.Image, size: int = ICON_SIZE) -> Image.Image:
    """Redimensionne en conservant la transparence sans liseré noir : alpha
    prémultiplié avant le rééchantillonnage Lanczos, puis divisé -- sinon le
    RGB (0,0,0) des pixels transparents assombrit les bords à la réduction."""
    arr = np.asarray(rgba, dtype=np.float64)
    rgb = arr[..., :3]
    alpha = arr[..., 3:4] / 255.0
    premult = (rgb * alpha).astype(np.uint8)
    alpha8 = (alpha[..., 0] * 255).astype(np.uint8)

    premult_img = Image.fromarray(premult, mode="RGB").resize(
        (size, size), Image.LANCZOS
    )
    alpha_img = Image.fromarray(alpha8, mode="L").resize((size, size), Image.LANCZOS)

    premult_r = np.asarray(premult_img, dtype=np.float64)
    alpha_r = np.asarray(alpha_img, dtype=np.float64)[..., None] / 255.0
    rgb_out = np.clip(_unpremultiply(premult_r, alpha_r), 0, 255).astype(np.uint8)

    out = np.dstack([rgb_out, np.asarray(alpha_img, dtype=np.uint8)])
    return Image.fromarray(out, mode="RGBA")


# ---------------------------------------------------------------------------
# Découpe d'une planche
# ---------------------------------------------------------------------------


def cell_icon_names(spec: SheetSpec) -> list[str]:
    """Les 15 noms `<agent>_<slot>` d'une planche, dans l'ordre des cases
    (case 16 exclue) -- utilisé par la découpe et par les tests."""
    return [
        f"{agent}_{slot}"
        for agent in spec.agents
        for slot in SLOT_ORDER
    ]


def slice_sheet(spec: SheetSpec, output_dir: Path) -> list[Path]:
    """Découpe une planche en icônes PNG 128x128 détourées, écrites dans
    `output_dir`. Renvoie les chemins écrits (15 par planche)."""
    image = Image.open(spec.path)
    boxes = detect_cells(image)  # 16 boîtes, ligne par ligne
    background_rgb = sheet_background_color(image)

    written: list[Path] = []
    names = cell_icon_names(spec)
    for name, (x0, y0, x1, y1) in zip(names, boxes):  # boxes[15] (case 16) ignorée
        m = CELL_CROP_MARGIN
        cell = image.crop((x0 + m, y0 + m, x1 + 1 - m, y1 + 1 - m))
        cutout = remove_background(cell, background_rgb)
        icon = resize_icon(cutout)
        out_path = output_dir / f"{name}.png"
        icon.save(out_path)
        written.append(out_path)
    return written


def slice_all(
    output_dir: Path = DEFAULT_OUTPUT_DIR,
    repo_root: Path = Path("."),
    sheets: tuple[SheetSpec, ...] = SHEETS,
) -> list[Path]:
    resolved_out = repo_root / output_dir
    resolved_out.mkdir(parents=True, exist_ok=True)

    written: list[Path] = []
    for spec in sheets:
        resolved_spec = SheetSpec(repo_root / spec.path, spec.agents)
        written += slice_sheet(resolved_spec, resolved_out)
    return written


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help="dossier de sortie, relatif à --repo-root",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path("."),
        help="racine du dépôt (contient assets/incoming/...)",
    )
    args = parser.parse_args()

    written = slice_all(output_dir=args.output_dir, repo_root=args.repo_root)
    print(f"{len(written)} icônes écrites dans {args.repo_root / args.output_dir}")


if __name__ == "__main__":
    main()
