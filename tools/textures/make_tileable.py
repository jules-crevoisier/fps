"""tools/textures/make_tileable.py -- ART-79B

Raccorde et remplace les matieres peintes a la main : decoupe une case
(matiere) d'une planche 4K Tripo Studio (grille 2x2, voir
assets/incoming/tripo/textures/SOURCES.md), la rend RACCORDABLE (tileable)
par une coupe a erreur minimale (Efros-Freeman, programmation dynamique --
jamais un fondu croise), l'egalise doucement en basses frequences pour
eviter la repetition visible d'une tache, recale sa luminance moyenne sur
l'ancienne texture du meme nom (le look ART-70 a ete regle dessus), garantit
qu'aucun pixel ne porte une teinte des bandes reservees d'equipe
(docs/style/tokens.json "reserved", meme methode OKLCH que
tools/review/style_check.py::eval_reserved_hue_fraction -- jamais reechouee
en HSV approximatif), puis ecrit la sortie 1024^2 sRGB SOUS LE MEME NOM que
lit deja scripts/core/Cartoon.gd / tools/textures/gen_textures.py.

Pipeline par matiere (voir `process_material`) :
  1. detect_grid_2x2()   trouve la gouttiere (bande sombre) pres du centre de
                          la planche, sur chaque axe, avec ou sans liseré
                          d'encre au bord de chaque case, gouttiere a +/-3 %
                          du centre -- jamais une simple coupe a W/2 pile.
  2. crop + resize        cadre la case demandee (haut-gauche/haut-droite/
                          bas-gauche/bas-droite) et la ramene a 1024^2.
  3. make_seamless()      raccord horizontal PUIS vertical (bande de
                          recouvrement 10-15 %, coupe DP, pas de blend).
  4. soft_low_freq_equalize()  attenue de moitie la derive basse frequence
                          (taches qui se repeteraient une fois tuile).
  5. enforce_reserved_bands()  desature au vol tout pixel qui tomberait dans
                          une bande de teinte reservee -- garantie
                          structurelle, jamais un simple avertissement.
  6. recalibrate_luminance()   recale la luminance moyenne a +/-10 % de
                          l'ancienne texture du meme nom (si elle existe).
  7. ecriture PNG 1024^2 sRGB au chemin `output` de hand_painted.yaml.
     `*_grime.png` existants sont regeneres DEPUIS cette nouvelle albedo
     (zones sombres floutees), jamais du bruit -- voir `grime_from_albedo`.
     Aucun `.import` n'est touche (Godot les regenere a son prochain
     `--import`) et Cartoon.gd n'est jamais modifie par ce script.

Tant que les planches sources (assets/incoming/tripo/textures/
sheet_<A|B|C>_<a|b>.jpg) n'existent pas, chaque matiere imprime TILE_FAIL
"source manquante" (jamais un plantage) -- tools/textures/tests/
test_make_tileable.py exerce le pipeline entier sur des planches SYNTHETIQUES
generees par les tests, comme prevu par le contrat ART-79B.

Usage :
    python tools/textures/make_tileable.py --config tools/textures/hand_painted.yaml [--dry-run]

`--dry-run` : traite tout, imprime le rapport et ecrit la planche de
controle (assets/textures/painted/TILE_CHECK.png), mais n'ecrit AUCUNE
sortie finale (ni `assets/textures/painted/HAND_PAINTED.txt`) -- pour
verifier sans toucher au depot.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import yaml
from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = REPO_ROOT / "tools" / "textures" / "hand_painted.yaml"
HAND_PAINTED_LIST = REPO_ROOT / "assets" / "textures" / "painted" / "HAND_PAINTED.txt"
CONTROL_SHEET_PATH = REPO_ROOT / "assets" / "textures" / "painted" / "TILE_CHECK.png"
TOKENS_PATH = REPO_ROOT / "docs" / "style" / "tokens.json"

OUTPUT_SIZE = 1024
GRIME_SIZE = 512  # matches tools/textures/gen_textures.py's DETAIL_SIZE.
CELLS = ("top_left", "top_right", "bottom_left", "bottom_right")


# =============================================================================
# OKLab / OKLCH -- self-contained, same matrices/constants as
# tools/textures/gen_textures.py::oklab_l and
# tools/review/style_check.py::rgb01_to_oklab/oklab_to_oklch (no shared
# OKLab utility exists yet in the repo -- ART-03/ART-05 own that, out of
# this task's file list -- so this stays a small duplicate, same convention
# gen_textures.py already documents for itself).
# =============================================================================

_M1 = np.array([
    [0.4122214708, 0.5363325363, 0.0514459929],
    [0.2119034982, 0.6806995451, 0.1073969566],
    [0.0883024619, 0.2817188376, 0.6299787005],
])
_M2 = np.array([
    [0.2104542553, 0.7936177850, -0.0040720468],
    [1.9779984951, -2.4285922050, 0.4505937099],
    [0.0259040371, 0.7827717662, -0.8086757660],
])
_M1_INV = np.linalg.inv(_M1)
_M2_INV = np.linalg.inv(_M2)


def _srgb_to_linear(c: np.ndarray) -> np.ndarray:
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _linear_to_srgb(c: np.ndarray) -> np.ndarray:
    c = np.clip(c, 0.0, None)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1.0 / 2.4) - 0.055)


def rgb01_to_oklab(rgb: np.ndarray) -> np.ndarray:
    lin = _srgb_to_linear(np.asarray(rgb, dtype=np.float64))
    lms = lin @ _M1.T
    lms_ = np.cbrt(np.clip(lms, 0.0, None))
    return lms_ @ _M2.T


def oklab_to_rgb01(lab: np.ndarray) -> np.ndarray:
    lms_ = lab @ _M2_INV.T
    lms = lms_ ** 3
    lin = lms @ _M1_INV.T
    return np.clip(_linear_to_srgb(lin), 0.0, 1.0)


def oklab_to_oklch(lab: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    l_, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    c = np.sqrt(a ** 2 + b ** 2)
    h = np.degrees(np.arctan2(b, a)) % 360.0
    return l_, c, h


def load_reserved_tokens(tokens_path: Path = TOKENS_PATH) -> tuple[list[tuple[float, float]], float]:
    """`docs/style/tokens.json` `reserved.hue_bands_deg`/`reserved.
    chroma_threshold` -- same source of truth `tools/review/
    style_check.py`'s CHK-06 reads, so this script never drifts from the
    project's one reserved-band definition. Falls back to that file's
    current values if `tokens.json` is unreadable (never a hard crash for a
    safety gate)."""
    import json
    try:
        data = json.loads(tokens_path.read_text(encoding="utf-8"))
        bands = [tuple(b) for b in data["reserved"]["hue_bands_deg"]]
        threshold = float(data["reserved"]["chroma_threshold"])
        return bands, threshold
    except (OSError, KeyError, ValueError, TypeError):
        return [(300.0, 355.0), (105.0, 145.0)], 0.08


def enforce_reserved_bands(img01: np.ndarray, tokens_path: Path = TOKENS_PATH) -> tuple[np.ndarray, int]:
    """Structurally guarantees no pixel of `img01` (H,W,3 sRGB 0..1) carries
    a reserved-hue, high-chroma tint (docs/style/tokens.json "reserved" --
    enemy/ally highlight bands): any offending pixel is desaturated
    (pulled toward its own OKLab neutral axis, hue and lightness both
    UNCHANGED -- see `oklab_to_rgb01`) until its chroma sits at the
    threshold, never merely flagged. Returns (fixed_image, n_pixels_fixed)."""
    bands, threshold = load_reserved_tokens(tokens_path)
    lab = rgb01_to_oklab(img01)
    l_, c, h = oklab_to_oklch(lab)
    in_band = np.zeros(h.shape, dtype=bool)
    for lo, hi in bands:
        in_band |= (h >= lo) & (h <= hi)
    offending = in_band & (c > threshold)
    n_fixed = int(offending.sum())
    if n_fixed == 0:
        return img01, 0
    scale = np.ones_like(c)
    safe_c = np.maximum(c, 1e-9)
    scale = np.where(offending, threshold / safe_c, 1.0)
    a = lab[..., 1] * scale
    b = lab[..., 2] * scale
    fixed_lab = np.stack([l_, a, b], axis=-1)
    fixed_rgb = oklab_to_rgb01(fixed_lab)
    out = np.where(offending[..., None], fixed_rgb, img01)
    return np.clip(out, 0.0, 1.0), n_fixed


# =============================================================================
# Gouttiere / decoupe de la grille 2x2 (avec ou sans lisere d'encre, +/-3 %)
# =============================================================================

def _find_dark_band(profile: np.ndarray, center: int, margin: int, rel_margin: float = 0.05) -> tuple[int, int]:
    """Cherche, dans la fenetre [center-margin, center+margin), la bande
    sombre contigue autour du minimum de `profile` (luminance moyenne par
    ligne/colonne) -- la gouttiere pure quand il n'y a pas de lisere, ou la
    gouttiere ET le lisere FUSIONNES en une seule bande (le lisere touche
    la gouttiere par construction : c'est l'encre au bord de la case, contre
    le separateur noir) quand il y en a un. La fenetre reste centree sur le
    centre GEOMETRIQUE de la planche (jamais recentree sur le minimum
    absolu) : c'est ce qui tolere une gouttiere decalee jusqu'a `margin`
    (ART-79B : +/-3 %) sans deriver vers une autre tache sombre a
    l'interieur d'une case. Renvoie (start, end) exclusif."""
    lo = max(0, center - margin)
    hi = min(len(profile), center + margin)
    window = profile[lo:hi]
    idx_min = int(np.argmin(window)) + lo
    threshold = float(profile[idx_min]) + rel_margin
    start = idx_min
    while start - 1 >= lo and profile[start - 1] <= threshold:
        start -= 1
    end = idx_min
    while end + 1 < hi and profile[end + 1] <= threshold:
        end += 1
    return start, end + 1


def detect_grid_2x2(img01: np.ndarray, search_margin_frac: float = 0.08) -> dict[str, tuple[int, int, int, int]]:
    """Detecte la gouttiere verticale et horizontale d'une planche 2x2 et
    renvoie les 4 boites (y0, y1, x0, x1) de chaque case, plus les bandes de
    gouttiere elles-memes (`gutter_x`/`gutter_y`, pour diagnostic/tests).
    `search_margin_frac` (8 %) couvre confortablement le decalage de +/-3 %
    impose par le contrat plus la largeur de la gouttiere/du lisere."""
    h, w = img01.shape[0], img01.shape[1]
    lum = img01.mean(axis=-1)
    col_profile = lum.mean(axis=0)
    row_profile = lum.mean(axis=1)
    margin_x = max(4, int(round(w * search_margin_frac)))
    margin_y = max(4, int(round(h * search_margin_frac)))
    gx0, gx1 = _find_dark_band(col_profile, w // 2, margin_x)
    gy0, gy1 = _find_dark_band(row_profile, h // 2, margin_y)
    return {
        "top_left": (0, gy0, 0, gx0),
        "top_right": (0, gy0, gx1, w),
        "bottom_left": (gy1, h, 0, gx0),
        "bottom_right": (gy1, h, gx1, w),
        "gutter_x": (gx0, gx1),
        "gutter_y": (gy0, gy1),
    }


def crop_cell(img01: np.ndarray, box: tuple[int, int, int, int]) -> np.ndarray:
    y0, y1, x0, x1 = box
    return img01[y0:y1, x0:x1]


# =============================================================================
# Raccord (tileable) -- coupe a erreur minimale, DP, pas de fondu croise
# =============================================================================

def _min_error_path(diff: np.ndarray) -> np.ndarray:
    """Chemin (une position par ligne) qui minimise l'erreur cumulee, en ne
    pouvant se deplacer que de -1/0/+1 colonne d'une ligne a l'autre --
    coupe a erreur minimale classique (Efros & Freeman, "image quilting"),
    la ou une coupe droite couperait a travers un motif visible, celle-ci
    suit le grain de la matiere."""
    n, ov = diff.shape
    cost = diff.astype(np.float64).copy()
    back = np.zeros((n, ov), dtype=np.int64)
    idx = np.arange(ov)
    for y in range(1, n):
        prev = cost[y - 1]
        left = np.concatenate(([np.inf], prev[:-1]))
        right = np.concatenate((prev[1:], [np.inf]))
        stacked = np.stack([left, prev, right], axis=0)
        choice = np.argmin(stacked, axis=0)
        cost[y] = diff[y] + stacked[choice, idx]
        back[y] = idx + (choice - 1)
    path = np.zeros(n, dtype=np.int64)
    path[-1] = int(np.argmin(cost[-1]))
    for y in range(n - 2, -1, -1):
        path[y] = back[y + 1, path[y + 1]]
    return path


def _quilt_axis(img01: np.ndarray, axis: int, overlap_frac: float) -> np.ndarray:
    """Rend `img01` raccordable le long de `axis` (1 = colonnes/horizontal,
    0 = lignes/vertical) : `np.roll` par la moitie de l'etendue deplace le
    raccord (bord gauche/droit d'origine, qui NE correspond pas) au CENTRE
    du tableau -- le bord du tableau roule, lui, tombe alors exactement sur
    deux pixels d'origine ADJACENTS (donc deja continus, aucune coupe
    necessaire la). Le mauvais raccord, maintenant au centre, est repare par
    une coupe DP sur une bande de recouvrement `overlap_frac` (10-15 %) :
    `cand_before` (juste avant le centre) et `cand_after` (juste apres,
    LU EN MIROIR pour que son propre bord `[-1]` retombe exactement, valeur
    pour valeur, sur son voisin non touche `shifted[center]` -- continuite
    garantie a cette extremite de la bande, sans jamais fondre les deux
    candidats)."""
    work = img01 if axis == 1 else np.transpose(img01, (1, 0, 2))
    h, w = work.shape[0], work.shape[1]
    shift = w // 2
    shifted = np.roll(work, shift, axis=1)
    center = w // 2
    ov = max(4, int(round(w * overlap_frac)))
    ov = min(ov, center - 1, w - center - 1)
    cand_before = shifted[:, center - ov:center, :]
    cand_after = shifted[:, center:center + ov, :][:, ::-1, :]
    diff = np.sum((cand_before.astype(np.float64) - cand_after.astype(np.float64)) ** 2, axis=-1)
    path = _min_error_path(diff)
    cols = np.arange(ov)[None, :]
    use_before = cols < path[:, None]
    merged = np.where(use_before[..., None], cand_before, cand_after)
    out = shifted.copy()
    out[:, center - ov:center, :] = merged
    return out if axis == 1 else np.transpose(out, (1, 0, 2))


def make_seamless(img01: np.ndarray, overlap_frac: float) -> np.ndarray:
    """Raccord complet : horizontalement PUIS verticalement (contrat
    ART-79B), jamais l'inverse et jamais les deux a la fois."""
    out = _quilt_axis(img01, axis=1, overlap_frac=overlap_frac)
    out = _quilt_axis(out, axis=0, overlap_frac=overlap_frac)
    return out


def seam_score(img01: np.ndarray) -> tuple[float, float]:
    """(edge, interior) : `edge` = ecart moyen entre la derniere et la
    premiere colonne, et entre la derniere et la premiere rangee (moyenne
    des deux) -- ce que le raccord de tuilage montre reellement.
    `interior` = ecart moyen entre colonnes voisines interieures, et entre
    rangees voisines interieures, meme moyenne -- l'echelle de reference a
    laquelle comparer `edge` (contrat : `edge <= 1.5 * interior`)."""
    img = img01.astype(np.float64)
    col_edge = np.abs(img[:, 0, :] - img[:, -1, :]).mean()
    row_edge = np.abs(img[0, :, :] - img[-1, :, :]).mean()
    edge = 0.5 * (float(col_edge) + float(row_edge))
    col_interior = np.abs(img[:, 1:-1, :] - img[:, 2:, :]).mean()
    row_interior = np.abs(img[1:-1, :, :] - img[2:, :, :]).mean()
    interior = 0.5 * (float(col_interior) + float(row_interior))
    return edge, interior


def is_seam_ok(img01: np.ndarray, tolerance: float = 1.5) -> tuple[bool, float, float]:
    edge, interior = seam_score(img01)
    ok = edge <= tolerance * interior + 1e-6
    return ok, edge, interior


# =============================================================================
# Egalisation douce des basses frequences (50 %) -- evite la repetition
# visible d'une tache une fois la texture tuilee.
# =============================================================================

def _circular_blur(a: np.ndarray, sigma: float) -> np.ndarray:
    """Flou gaussien PERIODIQUE (multiplication dans le domaine frequentiel
    -- une multiplication FFT est une convolution CIRCULAIRE) : seul un flou
    qui boucle exactement a la meme facon a du sens ici, puisque l'image est
    deja rendue raccordable par `make_seamless` avant cet appel. Meme
    technique que tools/textures/gen_textures.py::circular_blur (duplique,
    meme raison que l'OKLab plus haut : pas d'utilitaire partage)."""
    h, w = a.shape
    fy = np.fft.fftfreq(h)
    fx = np.fft.fftfreq(w)
    gy = np.exp(-2.0 * (np.pi ** 2) * (max(sigma, 1e-3) ** 2) * (fy ** 2))
    gx = np.exp(-2.0 * (np.pi ** 2) * (max(sigma, 1e-3) ** 2) * (fx ** 2))
    kernel = np.outer(gy, gx)
    return np.real(np.fft.ifft2(np.fft.fft2(a) * kernel))


def soft_low_freq_equalize(img01: np.ndarray, amount: float = 0.5, sigma_frac: float = 0.125) -> np.ndarray:
    """Reduit de `amount` (50 %) l'ecart a la moyenne du canal de luminance
    BASSE FREQUENCE (flou de large rayon) -- une tache large qui se
    repeterait de facon voyante une fois la texture tuilee est ainsi
    attenuee de moitie, sans toucher le detail fin (grain, fibres)."""
    h, w = img01.shape[0], img01.shape[1]
    val = img01.mean(axis=-1)
    low = _circular_blur(val, sigma=max(h, w) * sigma_frac)
    mean_val = float(low.mean())
    low_corrected = low - amount * (low - mean_val)
    gain = np.where(low > 1e-6, low_corrected / np.maximum(low, 1e-6), 1.0)
    return np.clip(img01 * gain[..., None], 0.0, 1.0)


# =============================================================================
# Recalage de luminance (+/-10 % de l'ancienne texture du meme nom)
# =============================================================================

def read_old_mean_luminance(output_path: Path) -> float | None:
    if not output_path.exists():
        return None
    img = Image.open(output_path).convert("RGB")
    arr = np.asarray(img).astype(np.float64) / 255.0
    return float(arr.mean())


def recalibrate_luminance(img01: np.ndarray, old_mean: float | None, tolerance: float = 0.10) -> np.ndarray:
    """Recale la luminance moyenne de `img01` a +/-`tolerance` de
    `old_mean` -- seulement si elle en sort ; la variation naturelle de la
    photo source n'est pas ecrasee au-dela de ce necessaire (le look ART-70
    a ete regle sur l'ancienne texture, contrat ART-79B)."""
    if old_mean is None or old_mean <= 1e-6:
        return img01
    cur = float(img01.mean())
    if cur <= 1e-6:
        return img01
    lo, hi = old_mean * (1.0 - tolerance), old_mean * (1.0 + tolerance)
    if lo <= cur <= hi:
        return img01
    target = hi if cur > hi else lo
    scale = target / cur
    return np.clip(img01 * scale, 0.0, 1.0)


# =============================================================================
# Grime -- regenere depuis la NOUVELLE albedo (zones sombres floutees),
# jamais du bruit.
# =============================================================================

def grime_from_albedo(albedo01: np.ndarray, blur_sigma_frac: float = 0.03, size: int = GRIME_SIZE) -> np.ndarray:
    lum = albedo01.mean(axis=-1)
    inv = 1.0 - lum
    inv = inv - inv.min()
    m = inv.max()
    if m > 1e-9:
        inv = inv / m
    h, w = inv.shape
    blurred = _circular_blur(inv, sigma=max(h, w) * blur_sigma_frac)
    mask = np.clip(blurred, 0.0, 1.0)
    if (h, w) != (size, size):
        img = Image.fromarray((mask * 255.0 + 0.5).astype(np.uint8), mode="L")
        img = img.resize((size, size), Image.LANCZOS)
        mask = np.asarray(img).astype(np.float64) / 255.0
    return mask


# =============================================================================
# E/S image
# =============================================================================

def load_rgb01(path: Path) -> np.ndarray:
    img = Image.open(path).convert("RGB")
    return np.asarray(img).astype(np.float64) / 255.0


def resize01(img01: np.ndarray, size: int) -> np.ndarray:
    h, w = img01.shape[0], img01.shape[1]
    if (h, w) == (size, size):
        return img01
    pil = Image.fromarray((np.clip(img01, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), mode="RGB")
    pil = pil.resize((size, size), Image.LANCZOS)
    return np.asarray(pil).astype(np.float64) / 255.0


def save_png01(img01: np.ndarray, path: Path, mode: str = "RGB") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    arr = (np.clip(img01, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    Image.fromarray(arr, mode=mode).save(path)


# =============================================================================
# Config (hand_painted.yaml)
# =============================================================================

def load_config(config_path: Path) -> dict:
    data = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    return data


def _sheet_path(sheets_root: Path, sheet: str, variant: str) -> Path:
    return sheets_root / f"sheet_{sheet}_{variant}.jpg"


# =============================================================================
# Pipeline par matiere
# =============================================================================

class MaterialResult:
    def __init__(self, kind: str) -> None:
        self.kind = kind
        self.ok = False
        self.reason = ""
        self.final01: np.ndarray | None = None
        self.output_path: Path | None = None
        self.grime_path: Path | None = None
        self.grime01: np.ndarray | None = None
        self.edge = 0.0
        self.interior = 0.0
        self.reserved_fixed = 0


def process_material(name: str, spec: dict, sheets_root: Path, overlap_frac: float) -> MaterialResult:
    result = MaterialResult(name)
    sheet = spec["sheet"]
    variant = spec["variant"]
    cell = spec["cell"]
    output_path = REPO_ROOT / spec["output"]
    result.output_path = output_path
    grime_rel = spec.get("grime_output")
    if grime_rel:
        result.grime_path = REPO_ROOT / grime_rel

    sheet_path = _sheet_path(sheets_root, sheet, variant)
    if not sheet_path.exists():
        shown = sheet_path.relative_to(REPO_ROOT) if sheet_path.is_relative_to(REPO_ROOT) else sheet_path
        result.reason = f"source manquante ({shown})"
        return result

    sheet01 = load_rgb01(sheet_path)
    grid = detect_grid_2x2(sheet01)
    if cell not in CELLS:
        result.reason = f"case inconnue: {cell!r}"
        return result
    box = grid[cell]
    if box[1] - box[0] < 8 or box[3] - box[2] < 8:
        result.reason = f"decoupe degenerescente (gouttiere non trouvee) {box}"
        return result
    crop = crop_cell(sheet01, box)
    crop = resize01(crop, OUTPUT_SIZE)

    tiled = make_seamless(crop, overlap_frac)
    tiled = soft_low_freq_equalize(tiled, amount=0.5)
    tiled, n_fixed = enforce_reserved_bands(tiled)
    result.reserved_fixed = n_fixed
    old_mean = read_old_mean_luminance(output_path)
    tiled = recalibrate_luminance(tiled, old_mean)

    ok, edge, interior = is_seam_ok(tiled)
    result.edge, result.interior = edge, interior
    result.final01 = tiled
    if not ok:
        result.reason = f"raccord insuffisant (edge={edge:.4f} > 1.5*interior={interior:.4f})"
        return result

    if result.grime_path is not None:
        result.grime01 = grime_from_albedo(tiled)

    result.ok = True
    return result


# =============================================================================
# Planche de controle (mosaique 2x2 par matiere)
# =============================================================================

def _tile_2x2_preview(img01: np.ndarray, half: int = 256) -> np.ndarray:
    small = resize01(img01, half)
    top = np.concatenate([small, small], axis=1)
    return np.concatenate([top, top], axis=0)


def build_control_sheet(results: list[MaterialResult], cell_px: int = 512, cols: int = 4) -> Image.Image:
    n = len(results)
    rows = (n + cols - 1) // cols
    label_h = 28
    sheet = Image.new("RGB", (cols * cell_px, rows * (cell_px + label_h)), (40, 40, 40))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.load_default()
    except OSError:
        font = None
    for i, res in enumerate(results):
        col, row = i % cols, i // cols
        x0, y0 = col * cell_px, row * (cell_px + label_h)
        if res.final01 is not None:
            mosaic01 = _tile_2x2_preview(res.final01, half=cell_px // 2)
            tile_img = Image.fromarray((np.clip(mosaic01, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), mode="RGB")
        else:
            tile_img = Image.new("RGB", (cell_px, cell_px), (96, 96, 96))
        sheet.paste(tile_img, (x0, y0 + label_h))
        status = "TILE_OK" if res.ok else "TILE_FAIL"
        label = f"{res.kind}  {status}"
        draw.rectangle([x0, y0, x0 + cell_px, y0 + label_h], fill=(20, 20, 20))
        draw.text((x0 + 4, y0 + 6), label, fill=(230, 230, 230), font=font)
    return sheet


# =============================================================================
# HAND_PAINTED.txt (protection consommee par gen_textures.py)
# =============================================================================

def _read_hand_painted_list(path: Path) -> list[str]:
    if not path.exists():
        return []
    lines = []
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            lines.append(stripped)
    return lines


def write_hand_painted_list(path: Path, new_paths: list[str]) -> None:
    existing = set(_read_hand_painted_list(path))
    merged = sorted(existing | set(new_paths))
    header = (
        "# assets/textures/painted/HAND_PAINTED.txt\n"
        "#\n"
        "# ART-79B -- un chemin (relatif a la racine du depot) par ligne, un par\n"
        "# fichier que tools/textures/make_tileable.py a remplace par une texture\n"
        "# peinte a la main (planches Tripo Studio raccordees). Genere/mis a jour\n"
        "# par make_tileable.py -- ne pas editer a la main.\n"
        "#\n"
        "# tools/textures/gen_textures.py lit cette liste et ne (re)genere JAMAIS\n"
        "# un fichier qui y figure (incident 2026-09-24 : un rerun avait deja\n"
        "# efface des textures peintes a la main).\n"
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(header + "\n".join(merged) + ("\n" if merged else ""), encoding="utf-8", newline="\n")


# =============================================================================
# CLI
# =============================================================================

def run(config_path: Path, dry_run: bool) -> int:
    config = load_config(config_path)
    sheets_root_raw = config.get("sheets_root", "assets/incoming/tripo/textures")
    sheets_root = Path(sheets_root_raw)
    if not sheets_root.is_absolute():
        sheets_root = REPO_ROOT / sheets_root_raw
    overlap_frac = float(config.get("overlap_frac", 0.12))
    materials: dict[str, dict] = config["materials"]

    results: list[MaterialResult] = []
    for name, spec in materials.items():
        res = process_material(name, spec, sheets_root, overlap_frac)
        results.append(res)
        if res.ok:
            print(f"TILE_OK {name}  edge={res.edge:.4f} interior={res.interior:.4f} "
                  f"reserved_fixed={res.reserved_fixed}px")
        else:
            print(f"TILE_FAIL {name}  {res.reason}")

    sheet = build_control_sheet(results)
    CONTROL_SHEET_PATH.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(CONTROL_SHEET_PATH)
    print(f"Planche de controle ecrite -> {CONTROL_SHEET_PATH.relative_to(REPO_ROOT)}")

    n_ok = sum(1 for r in results if r.ok)
    print(f"\n{n_ok}/{len(results)} matiere(s) OK")

    if dry_run:
        print("--dry-run : aucune sortie finale ecrite (albedo/grime/HAND_PAINTED.txt).")
        return 0 if n_ok == len(results) else 1

    written_rel: list[str] = []
    for res in results:
        if not res.ok:
            continue
        assert res.final01 is not None and res.output_path is not None
        save_png01(res.final01, res.output_path)
        print(f"  wrote {res.output_path.relative_to(REPO_ROOT)}")
        written_rel.append(res.output_path.relative_to(REPO_ROOT).as_posix())
        if res.grime_path is not None and res.grime01 is not None:
            save_png01(res.grime01, res.grime_path, mode="L")
            print(f"  wrote {res.grime_path.relative_to(REPO_ROOT)}")
            written_rel.append(res.grime_path.relative_to(REPO_ROOT).as_posix())

    if written_rel:
        write_hand_painted_list(HAND_PAINTED_LIST, written_rel)
        print(f"  updated {HAND_PAINTED_LIST.relative_to(REPO_ROOT)} ({len(written_rel)} fichier(s) proteges)")

    return 0 if n_ok == len(results) else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    return run(args.config, args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
