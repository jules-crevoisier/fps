#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""style_check.py

Scoreur automatique de la checklist de style (docs/STYLE_BIBLE.md §11,
CHK-01 à CHK-47), tâche ART-03. Lit `docs/style/tokens.json` (bloc `checks`
pour les seuils, `reserved`/`color`/`agents`/`maps`/... pour les valeurs de
référence) et note chaque contrôle PASS / WARN / FAIL sur :

  - les captures de la revue (`map_shots/`, `ui_shots/`, `character_shots/`,
    `viewmodel_fp/`) et les masques (`style_masks/`, tools/review/
    style_masks.gd) d'un dossier de run de `run_review.ps1`
    (reports/review/<horodatage>/) ;
  - les fichiers d'asset du dépôt (textures peintes, shaders, scripts core) ;
  - les jetons eux-mêmes (couleurs d'agent, simulation daltonisme).

Un contrôle dont l'ENTRÉE nécessaire est absente (capture pas encore
produite par la tâche qui la fournit, outil pas encore livré) est noté
WARN avec `measured: false` et un détail « non mesuré : ... » — §11.1 : « ce
qui n'est pas mesuré est un WARN », jamais un FAIL par défaut. Un contrôle
n'est jamais mesuré à moitié en secret : soit `measured` est vrai et le
statut vient d'un calcul réel sur des pixels/fichiers, soit `measured` est
faux et le statut est WARN.

Usage :
    python tools/review/style_check.py <run_dir> [--tokens PATH] [--out PATH]
    python tools/review/style_check.py --self-test

Écrit "<run_dir>/style_check.json" (sauf --out) :
    {"generated_at", "tokens_version", "run_dir",
     "checks": {"CHK-01": {"status", "detail", "blocking", "measured"}, ...},
     "score": {"pass": N, "total": 47, "text": "N/47", "fraction": N/47},
     "warn_count", "blocking_fail_count", "gate": "PASS"|"WARN"|"FAIL"}
et imprime `STYLE_CHECK_SCORE N/47 gate=<GATE>`.

`--self-test` ne touche à rien du dépôt : il fabrique des images de synthèse
dans un dossier temporaire et vérifie CHK-02, CHK-06, CHK-18 et CHK-32
(contrat ART-03) plus quelques évaluateurs additionnels, puis quitte 0/1 —
c'est la commande de vérification de cette tâche.

Tâche OPS-11 (comble les trous signalés par ART-02/ART-07) : CHK-09 (paire
d'échantillons sol ombre/soleil), CHK-10 (largeur de trait de silhouette à
30 m) et CHK-11 (absence de double trait pli/silhouette) sont désormais
mesurés depuis `look_probe.json["maps"]` (`tools/look_probe.gd`, agrégés sur
les 8 cartes par `resolve_ground_silhouette_checks`) plutôt que codés en dur
« non mesuré » — voir `eval_ground_shadow_pair`/`eval_silhouette_width`/
`eval_double_line` pour les seuils exacts (tokens.json `checks.CHK-09/10/11`).

Tâche OPS-13 (ART-30/ART-31) : `find_glyph_components` séparait mal deux
exigences opposées derrière un seul seuil (`safe_ink_tolerance`) — protéger
du fond `charbon` (confusable avec l'encre, ΔE ~0.03) VS couvrir le halo
anticrénelé d'un vrai glyphe (posé sur `papier`, ΔE ~1.46) — resserrer ce
seuil pour (a) casse (b) : les glyphes se fragmentent en composantes de
quelques pixels (CHK-32 mesure 2 px, CHK-33 un contraste de 1,00 sur des
captures pourtant lisibles). Résolu en séparant les deux seuils
(`exclude_rgbs`/`exclude_tol`, exclusion étroite, indépendante de `tol`,
large). CHK-37 (états hover/focus/pressed/disabled, `lint_theme_states` sur
`resources/ui/ui_theme.tres`) et CHK-13 (masses de nuages,
`find_cloud_components`/`eval_cloud_masses` sur les vues aériennes) sont
désormais mesurés au lieu d'un « non mesuré » inconditionnel.

Correction (retour du vérificateur, tâche OPS-13, 24/09) : le fix ART-31
n'était câblé QUE sur l'appel `ink` de `resolve_ui_shots` — `papier`/
`papier_dim` (texte clair sur fond charbon) gardaient `tol=0.16` sans
exclusion. `safe_ink_tolerance` est généralisée en `safe_color_tolerance`
(n'importe quelle couleur cible) et appliquée aux trois appels. Par ailleurs
`eval_glyph_heights`/`eval_min_contrast_pairs` agrégeaient par un strict
`min()` sur TOUTES les composantes de TOUTES les captures : une seule
composante parasite (bord anticrénelé, glitch — statistiquement inévitable
sur des dizaines de captures réelles) faisait retomber tout le VERDICT sur la
signature du bug d'origine, quelle que soit la qualité du fix de détection.
Les deux évaluateurs tolèrent désormais une fraction minoritaire
(`pass_fraction`, comme CHK-10/CHK-18 dans ce même fichier) sans jamais
cacher le pire cas réel du détail. Vérifié sur les VRAIES captures de
`reports/review/20260924-204557/ui_shots/` (pas seulement des fixtures de
synthèse) : le gate CHK-32/33 y reste FAIL, mais le détail rapporte
désormais une fraction de réussite réelle (~10-20 %) au lieu de la seule
valeur dégénérée `2.0 px`/`1.00` — cette interface a réellement une grande
proportion d'éléments de la taille/du contraste d'un glyphe qui ne sont pas
du texte lisible (icônes, portraits, bords anticrénelés d'éléments décoratifs
dans les tons `papier`/`papier_dim`/`ink`) ; distinguer du texte réel de ce
bruit demanderait une heuristique de FORME (alignement en ligne de base,
régularité du trait), hors périmètre de ce correctif ciblé.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:  # pragma: no cover — Pillow est une dépendance du dépôt (report.py l'utilise déjà).
    HAS_PIL = False

try:
    from scipy import ndimage
    HAS_SCIPY = True
except ImportError:  # pragma: no cover — scipy est installé dans cet environnement (voir tools/review/report.py sibling deps).
    HAS_SCIPY = False

REPO_ROOT = Path(__file__).resolve().parents[2]  # tools/review/style_check.py -> tools -> racine
DEFAULT_TOKENS_PATH = REPO_ROOT / "docs" / "style" / "tokens.json"

ALL_CHECK_IDS = [f"CHK-{i:02d}" for i in range(1, 48)]
STATUS_RANK = {"PASS": 0, "WARN": 1, "FAIL": 2}


def worse(a: str, b: str) -> str:
    return a if STATUS_RANK[a] >= STATUS_RANK[b] else b


# =============================================================================
#  Résultat d'un contrôle
# =============================================================================

@dataclass
class Finding:
    status: str            # PASS | WARN | FAIL
    detail: str
    measured: bool = True
    data: dict = field(default_factory=dict)

    @staticmethod
    def unmeasured(reason: str) -> "Finding":
        return Finding("WARN", f"non mesuré : {reason}", measured=False)


# =============================================================================
#  Couleur : sRGB -> OKLab/OKLCH, luminance WCAG, simulation daltonisme
#  (Machado/Oliveira/Fairchild 2009, sévérité 1.0 — docs/STYLE_BIBLE.md §11.1).
#  Convention de ce module : ΔE_OK = 100 × distance euclidienne en OKLab —
#  c'est cette échelle (pas la distance brute, typiquement < 0.5) qui rend
#  les seuils de tokens.json (ex. CHK-18 min_delta_e_ok=20) comparables à une
#  ΔE perceptuelle usuelle ; documenté ici une fois pour tout le fichier.
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

# Matrices Machado/Oliveira/Fairchild 2009, sévérité 1.0, appliquées
# directement sur le triplet sRGB gamma (0..1) — convention pragmatique la
# plus répandue pour ce genre de gate (ex. bibliothèques de simulation CVD en
# ligne), documentée ici plutôt que la variante "linéarisée" du papier
# original : suffisant pour classer PASS/WARN/FAIL, pas pour un rendu
# scientifique.
_CVD_MATRICES = {
    "protan": np.array([
        [0.152286, 1.052583, -0.204868],
        [0.114503, 0.786281, 0.099216],
        [-0.003882, -0.048116, 1.051998],
    ]),
    "deutan": np.array([
        [0.367322, 0.860646, -0.227968],
        [0.280085, 0.672501, 0.047413],
        [-0.011820, 0.042940, 0.968881],
    ]),
    "tritan": np.array([
        [1.255528, -0.076749, -0.178779],
        [-0.078411, 0.930809, 0.147602],
        [0.004733, 0.691367, 0.303900],
    ]),
}


def hex_to_rgb01(hexstr: str) -> tuple[float, float, float]:
    h = hexstr.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))  # type: ignore[return-value]


def srgb_to_linear(c: np.ndarray) -> np.ndarray:
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def rgb01_to_oklab(rgb: np.ndarray) -> np.ndarray:
    """rgb : (...,3) sRGB 0..1 -> (...,3) OKLab (L,a,b)."""
    lin = srgb_to_linear(np.asarray(rgb, dtype=np.float64))
    lms = lin @ _M1.T
    lms_ = np.cbrt(np.clip(lms, 0.0, None))
    return lms_ @ _M2.T


def oklab_to_oklch(lab: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    l_ = lab[..., 0]
    a = lab[..., 1]
    b = lab[..., 2]
    c = np.sqrt(a ** 2 + b ** 2)
    h = np.degrees(np.arctan2(b, a)) % 360.0
    return l_, c, h


def rgb01_to_oklch(rgb) -> tuple[float, float, float]:
    lab = rgb01_to_oklab(np.array(rgb, dtype=np.float64))
    l_, c, h = oklab_to_oklch(lab)
    return float(l_), float(c), float(h)


def relative_luminance(rgb) -> float:
    lin = srgb_to_linear(np.array(rgb, dtype=np.float64))
    return float(0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2])


def wcag_contrast(rgb1, rgb2) -> float:
    l1, l2 = relative_luminance(rgb1), relative_luminance(rgb2)
    lo, hi = min(l1, l2), max(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def delta_e_ok(rgb1, rgb2) -> float:
    lab1 = rgb01_to_oklab(np.array(rgb1, dtype=np.float64))
    lab2 = rgb01_to_oklab(np.array(rgb2, dtype=np.float64))
    return float(100.0 * np.linalg.norm(lab1 - lab2))


def simulate_cvd(rgb, kind: str) -> tuple[float, float, float]:
    """Simule protan/deutan/tritan (Machado 2009, sévérité 1.0) sur un
    triplet sRGB 0..1 — voir la note de convention en tête de section."""
    m = _CVD_MATRICES[kind]
    out = m @ np.array(rgb, dtype=np.float64)
    return tuple(np.clip(out, 0.0, 1.0).tolist())  # type: ignore[return-value]


def hue_in_bands(h_deg: float, bands: list[list[float]]) -> bool:
    return any(lo <= h_deg <= hi for lo, hi in bands)


def safe_color_tolerance(target_rgb: tuple[float, float, float], neighbor_rgbs: list[tuple[float, float, float]], default: float = 0.16) -> float:
    """Généralisation de `safe_ink_tolerance` : rayon d'EXCLUSION à utiliser
    en `exclude_tol` (avec `exclude_rgbs=neighbor_rgbs`) autour de `target_rgb`
    pour retrancher étroitement un voisin confusable connu, SANS rétrécir la
    tolérance d'INCLUSION (`tol`) elle-même — c'est `find_glyph_components`
    qui applique cette distinction (voir sa docstring, fix ART-31). On prend
    la moitié de la distance au voisin le plus proche, strictement en-deçà :
    assez étroit pour ne jamais mordre sur l'anti-aliasing d'un aplat de la
    couleur cible elle-même (distance exacte, 0), assez large pour retrancher
    le voisin confusable ET son propre halo anticrénelé."""
    if not neighbor_rgbs:
        return default
    target = np.array(target_rgb)
    min_dist = min(float(np.linalg.norm(target - np.array(n))) for n in neighbor_rgbs)
    return min(default, min_dist * 0.5)


def safe_ink_tolerance(tokens: dict, default: float = 0.16) -> float:
    """Tolérance de correspondance couleur pour détecter un pixel « encre »
    (`find_glyph_components`, CHK-32/33) SANS confondre les fonds neutres
    charbon (`bg`/`panel`/`panel_hi`), très proches de `ink` dans cette
    palette « neutres réchauffés » (STYLE_BIBLE v3 §8.2 : h ~ 55-60° pour les
    quatre — voir tokens.json `color.ink.role` : « the only near-black »,
    mais pas le seul SOMBRE). Une tolérance fixe de 0.16 (pensée pour une
    palette où encre et fond seraient loin en couleur) confond `charbon.bg`
    (distance ~0.027 à `ink`) et même `charbon.panel_hi` (~0.113) avec de
    l'encre : tout le FOND des pages/panneaux se classe alors comme
    « glyphe », ce qui rend CHK-32 (hauteur) et CHK-33 (contraste)
    incohérents (mesure = le fond lui-même, pas du texte — Retour QA ART-30
    24/09 16h04, `min_height_px_1080=2.0`/`contraste=1.00`). On prend la
    moitié de la distance au voisin charbon le plus proche — strictement
    en-deçà, tout en couvrant l'anti-aliasing d'un aplat d'encre réel (couleur
    exacte, distance 0). Cas particulier de `safe_color_tolerance` conservé
    tel quel (signature/comportement inchangés) pour ne pas perturber les
    appelants existants."""
    try:
        ink = hex_to_rgb01(tokens["color"]["ink"]["hex"])
        neighbors = [
            hex_to_rgb01(tokens["color"]["charbon"]["bg"]["hex"]),
            hex_to_rgb01(tokens["color"]["charbon"]["panel"]["hex"]),
            hex_to_rgb01(tokens["color"]["charbon"]["panel_hi"]["hex"]),
        ]
    except (KeyError, TypeError):
        return default
    return safe_color_tolerance(ink, neighbors, default)


# =============================================================================
#  Jetons (docs/style/tokens.json)
# =============================================================================

def load_tokens(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def chk_cfg(tokens: dict, chk_id: str) -> dict:
    return tokens.get("checks", {}).get(chk_id, {})


def is_blocking(tokens: dict, chk_id: str) -> bool:
    return bool(chk_cfg(tokens, chk_id).get("blocking", True))


# =============================================================================
#  Images : chargement, échantillonnage, composantes connexes
# =============================================================================

def load_image_rgb01(path: Path) -> np.ndarray | None:
    if not HAS_PIL or not path.is_file():
        return None
    try:
        img = Image.open(path).convert("RGB")
    except Exception:
        return None
    return np.asarray(img, dtype=np.float64) / 255.0  # (H,W,3)


def load_mask_bool(path: Path) -> np.ndarray | None:
    """Masque noir/blanc (style_masks.gd, fp_shots.gd...) -> bool (H,W),
    True = pixel « inclus » (blanc)."""
    if not HAS_PIL or not path.is_file():
        return None
    try:
        img = Image.open(path).convert("L")
    except Exception:
        return None
    return (np.asarray(img, dtype=np.uint8) > 127)


def mean_rgb_in_rect(rgb: np.ndarray, rect_px: tuple[int, int, int, int]) -> tuple[float, float, float]:
    x0, y0, x1, y1 = rect_px
    h, w = rgb.shape[0], rgb.shape[1]
    x0, x1 = max(0, min(x0, w)), max(0, min(x1, w))
    y0, y1 = max(0, min(y0, h)), max(0, min(y1, h))
    if x1 <= x0 or y1 <= y0:
        return (0.0, 0.0, 0.0)
    crop = rgb[y0:y1, x0:x1]
    return tuple(crop.reshape(-1, 3).mean(axis=0).tolist())  # type: ignore[return-value]


def ring_background_rgb(rgb: np.ndarray, bbox: tuple[int, int, int, int], pad: int) -> tuple[float, float, float] | None:
    """Couleur de fond MOYENNE autour d'un glyphe détecté
    (`find_glyph_components`), pour CHK-33 (contraste texte/fond). Agrandit le
    rectangle dans les DEUX dimensions (pas seulement en hauteur, sur les
    MÊMES colonnes que le glyphe) ET EXCLUT la bbox du glyphe elle-même de la
    moyenne : sans ça, un glyphe étroit dont le padding ne déborde pas de ses
    propres colonnes (l'ancien calcul) se retrouve comparé en partie à
    LUI-MÊME — `fg` ~= `bg`, contraste ~= 1.0, FAIL non représentatif du vrai
    contraste texte/fond (Retour QA ART-30 24/09 16h04, contraste mesuré à
    1.00). Renvoie `None` si l'anneau ne contient aucun pixel (bbox couvrant
    toute l'image)."""
    y0, y1, x0, x1 = bbox
    h, w = rgb.shape[0], rgb.shape[1]
    by0, by1 = max(0, y0 - pad), min(h, y1 + pad)
    bx0, bx1 = max(0, x0 - pad), min(w, x1 + pad)
    if by1 <= by0 or bx1 <= bx0:
        return None
    region = rgb[by0:by1, bx0:bx1]
    mask = np.ones(region.shape[:2], dtype=bool)
    mask[y0 - by0:y1 - by0, x0 - bx0:x1 - bx0] = False
    ring = region[mask]
    if ring.size == 0:
        return None
    return tuple(ring.reshape(-1, 3).mean(axis=0).tolist())  # type: ignore[return-value]


def resize_mask_to(mask: np.ndarray, shape_hw: tuple[int, int]) -> np.ndarray:
    if mask.shape == shape_hw:
        return mask
    img = Image.fromarray((mask.astype(np.uint8)) * 255, mode="L")
    img = img.resize((shape_hw[1], shape_hw[0]), Image.NEAREST)
    return np.asarray(img) > 127


def find_glyph_components(
    rgb: np.ndarray,
    ink_rgb: tuple[float, float, float],
    tol: float = 0.16,
    min_height_px: int = 2,
    max_height_frac: float = 0.5,
    max_width_frac: float = 0.9,
    exclude_rgbs: list[tuple[float, float, float]] | None = None,
    exclude_tol: float = 0.0,
) -> list[dict]:
    """Composantes connexes de pixels « couleur encre » dans `rgb`, filtrées
    pour ressembler à des glyphes de texte plutôt qu'à un bandeau/bord
    (largeur < `max_width_frac` × largeur image). Retourne une liste de
    {"height_px","width_px","area_px","bbox": (y0,y1,x0,x1)} — CHK-32/33
    (taille et contraste de texte) ; `area_px` (nombre de pixels RÉELS de la
    composante, pas juste hauteur×largeur de la bbox) sert aussi à CHK-13
    (masses de nuages), qui réutilise cette même primitive de composantes
    connexes.

    `exclude_rgbs` / `exclude_tol` — régression ART-31 sur le fix ART-30
    (Retour QA 24/09 16h04) : `tol` seul ne peut pas à la fois (a) rester
    ASSEZ LARGE pour couvrir le halo anticrénelé d'un vrai glyphe (l'encre de
    CETTE palette est posée sur un fond CLAIR — `papier` —, à ΔE ~1.46 : un
    pixel de bord à 90 % de couverture d'encre est déjà à ~0.15 de l'encre
    pure) et (b) rester ASSEZ ÉTROIT pour ne jamais confondre un aplat de
    fond `charbon` avec de l'encre (`charbon.bg` n'est qu'à ~0.027 de
    l'encre dans cette palette « neutres réchauffés » — voir
    `safe_ink_tolerance`). Un seuil UNIQUE resserré pour (b)
    (`safe_ink_tolerance`, tâche ART-30) protège bien du fond MAIS coupe
    aussi le halo réel en fragments de quelques pixels : c'est exactement le
    bug signalé par ART-31 (CHK-32 mesure 2 px, CHK-33 un contraste de 1,00
    sur des captures pourtant lisibles — la composante mesurée est un
    FRAGMENT du glyphe, entouré du MÊME glyphe côté « fond »). En séparant
    les deux exigences — `tol` reste large (couvre le halo), `exclude_rgbs`/
    `exclude_tol` (typiquement `safe_ink_tolerance`, réutilisé ici comme
    rayon d'EXCLUSION plutôt que d'inclusion) retranche étroitement les
    confusables connus — un pixel de halo à 90 % d'encre (loin de tout
    `charbon`) reste inclus, tandis qu'un aplat de fond `charbon.panel_hi`
    (loin de l'encre PURE mais dans le rayon d'exclusion) reste exclu, sans
    dépendre d'un compromis unique impossible entre les deux."""
    if not HAS_SCIPY:
        return []
    h, w = rgb.shape[0], rgb.shape[1]
    dist = np.linalg.norm(rgb - np.array(ink_rgb), axis=-1)
    mask = dist <= tol
    if exclude_rgbs and exclude_tol > 0:
        for other in exclude_rgbs:
            d_other = np.linalg.norm(rgb - np.array(other), axis=-1)
            mask &= d_other > exclude_tol
    if not mask.any():
        return []
    labeled, n = ndimage.label(mask, structure=np.ones((3, 3)))
    out = []
    for label_id, sl in enumerate(ndimage.find_objects(labeled), start=1):
        if sl is None:
            continue
        rows, cols = sl
        height = rows.stop - rows.start
        width = cols.stop - cols.start
        if height < min_height_px or height > h * max_height_frac:
            continue
        if width > w * max_width_frac:
            continue
        area = int((labeled[sl] == label_id).sum())
        out.append({
            "height_px": float(height), "width_px": float(width), "area_px": area,
            "bbox": (rows.start, rows.stop, cols.start, cols.stop),
        })
    return out


# =============================================================================
#  Évaluateurs purs (unit-testables sans dépendre d'un run_dir réel)
# =============================================================================

def eval_pixel_fraction_range(
    rgb: np.ndarray,
    included: np.ndarray,
    l_range: tuple[float, float],
    frac_range: tuple[float, float] | None = None,
    frac_max: float | None = None,
) -> tuple[str, float, int, int]:
    """Fraction de pixels INCLUS dont la luminance OKLab tombe dans `l_range`
    ([lo,hi)) — CHK-02 (boue) / CHK-03 (encre dosée). Renvoie
    (status, fraction, count_in_range, count_included)."""
    l_, _, _ = oklab_to_oklch(rgb01_to_oklab(rgb))
    lo, hi = l_range
    in_range = (l_ >= lo) & (l_ < hi) & included
    total = int(included.sum())
    count = int(in_range.sum())
    frac = (count / total) if total > 0 else 0.0
    if frac_max is not None:
        status = "PASS" if frac <= frac_max else "FAIL"
    elif frac_range is not None:
        status = "PASS" if frac_range[0] <= frac <= frac_range[1] else "FAIL"
    else:
        status = "WARN"
    return status, frac, count, total


def eval_reserved_hue_fraction(rgb: np.ndarray, included: np.ndarray, tokens: dict) -> tuple[str, float]:
    """CHK-06 : fraction de pixels INCLUS (décor) dont la chroma dépasse le
    seuil réservé ET dont la teinte tombe dans une bande réservée."""
    lab = rgb01_to_oklab(rgb)
    _, c, h = oklab_to_oklch(lab)
    bands = tokens["reserved"]["hue_bands_deg"]
    thresh = tokens["reserved"]["chroma_threshold"]
    in_band = np.zeros(c.shape, dtype=bool)
    for lo, hi in bands:
        in_band |= (h >= lo) & (h <= hi)
    reserved_px = in_band & (c > thresh) & included
    total = int(included.sum())
    frac = (float(reserved_px.sum()) / total) if total > 0 else 0.0
    cfg = chk_cfg(tokens, "CHK-06")
    status = "PASS" if frac <= cfg.get("reserved_pixel_max_fraction", 0.001) else "FAIL"
    return status, frac


def eval_exclusive_enemy_colors(rgb: np.ndarray, included: np.ndarray, tokens: dict) -> tuple[str, float]:
    """CHK-21 : aucun pixel INCLUS (hors ennemi/HUD ennemi) ne doit être
    perceptuellement proche (ΔE_OK < seuil) du Magenta ou du Citron
    réservés."""
    cfg = chk_cfg(tokens, "CHK-21")
    max_delta = cfg.get("exclusive_delta_e_ok", 10)
    reserved = tokens["reserved"]["enemy_highlight"]
    lab = rgb01_to_oklab(rgb)
    worst_frac = 0.0
    total = int(included.sum())
    if total == 0:
        return "WARN", 0.0
    for entry in reserved.values():
        target_lab = rgb01_to_oklab(np.array(hex_to_rgb01(entry["hex"])))
        dist = 100.0 * np.linalg.norm(lab - target_lab, axis=-1)
        close = (dist < max_delta) & included
        frac = float(close.sum()) / total
        worst_frac = max(worst_frac, frac)
    status = "PASS" if worst_frac == 0.0 else "FAIL"
    return status, worst_frac


def _masked_values(channel: np.ndarray, included_2d: np.ndarray | None) -> np.ndarray:
    """`channel` (H,W) restreint aux pixels INCLUS (True), ou tel quel si
    aucun masque n'est fourni. Ne renvoie jamais un tableau vide en silence :
    l'appelant reçoit un tableau de taille 0, à tester explicitement."""
    if included_2d is None:
        return channel.reshape(-1)
    return channel[included_2d]


def eval_ground_stats(rgb: np.ndarray, tokens: dict, included: np.ndarray | None = None) -> tuple[str, dict]:
    """CHK-04 : médiane de L et 95e centile de C sur le tiers inférieur de
    l'image (« sol »), hors pixels HUD/personnages si `included` est fourni
    (voir `combined_included_mask` — sans lui, approximation image entière)."""
    h = rgb.shape[0]
    ground_slice = slice(int(h * 2 / 3), None)
    lab = rgb01_to_oklab(rgb[ground_slice, :, :])
    l_, c, _ = oklab_to_oklch(lab)
    ground_included = included[ground_slice, :] if included is not None else None
    l_vals = _masked_values(l_, ground_included)
    c_vals = _masked_values(c, ground_included)
    if l_vals.size == 0:
        return "WARN", {"reason": "aucun pixel de sol inclus (masque HUD/personnages couvre toute la bande)"}
    med_l = float(np.median(l_vals))
    p95_c = float(np.percentile(c_vals, 95))
    cfg = chk_cfg(tokens, "CHK-04")
    lo, hi = cfg.get("ground_median_L", [0.60, 0.78])
    c_max = cfg.get("ground_C_max", 0.10)
    status = "PASS" if (lo <= med_l <= hi and p95_c <= c_max) else "FAIL"
    return status, {"ground_median_L": med_l, "ground_p95_C": p95_c}


def eval_chroma_hierarchy(rgb: np.ndarray, tokens: dict, included: np.ndarray | None = None) -> tuple[str, dict]:
    """CHK-05 : chroma au 95e centile, sol (tiers inférieur) vs décor (reste),
    plus le plafond dur `decor_C_hard_max` — mêmes pixels HUD/personnages
    exclus que `eval_ground_stats` quand `included` est fourni."""
    h = rgb.shape[0]
    ground_slice = slice(int(h * 2 / 3), None)
    decor_slice = slice(None, int(h * 2 / 3))
    _, c_ground_full, _ = oklab_to_oklch(rgb01_to_oklab(rgb[ground_slice, :, :]))
    _, c_decor_full, _ = oklab_to_oklch(rgb01_to_oklab(rgb[decor_slice, :, :]))
    ground_included = included[ground_slice, :] if included is not None else None
    decor_included = included[decor_slice, :] if included is not None else None
    c_ground = _masked_values(c_ground_full, ground_included)
    c_decor = _masked_values(c_decor_full, decor_included)
    if c_ground.size == 0 or c_decor.size == 0:
        return "WARN", {"reason": "aucun pixel sol/décor inclus (masque HUD/personnages trop couvrant)"}
    p95_ground = float(np.percentile(c_ground, 95))
    p95_decor = float(np.percentile(c_decor, 95))
    hard_max_decor = float(np.max(c_decor))
    cfg = chk_cfg(tokens, "CHK-05")
    ok = (
        p95_ground <= cfg.get("p95_C_ground", 0.10)
        and p95_decor <= cfg.get("p95_C_decor", 0.20)
        and hard_max_decor <= cfg.get("decor_C_hard_max", 0.21)
    )
    status = "PASS" if ok else "FAIL"
    return status, {"p95_C_ground": p95_ground, "p95_C_decor": p95_decor, "decor_C_max": hard_max_decor}


def eval_horizon_closed(rgb: np.ndarray, tokens: dict, ground_hex_candidates: list[str]) -> tuple[str, float]:
    """CHK-12 : dans une vue aérienne, aucun pixel de la bande basse ne doit
    ressembler à un fond de scène "vide sous l'horizon" (fond de caméra visible
    à travers un trou de géométrie) — approximé en cherchant, dans le dixième
    inférieur de l'image, des pixels quasi identiques à la couleur de fond de
    scène par défaut (gris neutre `Environment.background_color` type) ET très
    différents de toutes les couleurs de sol candidates de la carte."""
    band = rgb[int(rgb.shape[0] * 0.9):, :, :]
    flat = band.reshape(-1, 3)
    void_gray = np.array([0.0, 0.0, 0.0])  # fond de scène par défaut (Environment.BG_COLOR non configuré = noir)
    close_to_void = np.linalg.norm(flat - void_gray, axis=-1) < 0.02
    frac = float(close_to_void.mean()) if flat.size else 0.0
    cfg = chk_cfg(tokens, "CHK-12")
    status = "PASS" if frac <= cfg.get("below_horizon_void_fraction", 0.0) + 1e-9 else "FAIL"
    return status, frac


def sky_region_mask(rgb: np.ndarray, tokens: dict) -> np.ndarray:
    """Masque « ciel » générique — zénith OU horizon d'après les enveloppes
    OKLab de `tokens.world.value_structure.sky_zenith`/`sky_horizon`
    (luminosité/chroma, comme `eval_ground_stats`/`eval_chroma_hierarchy`
    pour sol/décor), INDÉPENDANT de la teinte exacte d'une carte précise —
    une vue aérienne ne porte pas forcément le nom de sa carte dans son nom
    de fichier de façon fiable. Sert de base à CHK-13 (masses de nuages) :
    restreint la recherche de nuages au ciel et fournit les bornes verticales
    utilisées pour l'approximation d'élévation (`eval_cloud_masses`)."""
    l_, c, _ = oklab_to_oklch(rgb01_to_oklab(rgb))
    vs = tokens.get("world", {}).get("value_structure", {})
    zl = vs.get("sky_zenith", {}).get("L", [0.52, 0.65])
    zc = vs.get("sky_zenith", {}).get("C", [0.1, 0.17])
    hl = vs.get("sky_horizon", {}).get("L", [0.82, 0.93])
    hc_max = vs.get("sky_horizon", {}).get("C_max", 0.08)
    zenith = (l_ >= zl[0]) & (l_ <= zl[1]) & (c >= zc[0]) & (c <= zc[1])
    horizon = (l_ >= hl[0]) & (l_ <= hl[1]) & (c <= hc_max)
    return zenith | horizon


def find_cloud_components(
    rgb: np.ndarray, tokens: dict, row_bounds: tuple[int, int] | None = None, tol: float = 0.10,
) -> list[dict]:
    """Composantes connexes « masse de nuage » (connectivité 8, réutilise la
    même primitive que `find_glyph_components`) : pixels proches de
    `shader.ink_sky.cloud_lit`/`cloud_shade` (les deux teintes que le shader
    ciel utilise réellement pour peindre les nuages). `tol=0.10` reste sous
    l'écart mesuré entre ces deux teintes et l'horizon le plus pâle des 8
    cartes (≥ 0,17, `docs/style/tokens.json` `maps.*.sky_horizon`) : jamais
    de confusion nuage/horizon.

    `row_bounds` (lignes où `sky_region_mask` a détecté du ciel « nu »,
    PAS une restriction pixel à pixel) : un nuage lui-même est PLUS CLAIR/
    différent du ciel nu par construction (`cloud_lit` L≈0,98, hors de
    l'enveloppe OKLab `sky_horizon` L∈[0,82;0,93]) — un ET pixel-à-pixel avec
    `sky_region_mask` exclurait donc TOUT nuage réel. Restreindre par bande
    de LIGNES (le ciel nu détecté au-dessus/au-dessous/à côté d'un nuage
    borne la bande verticale où chercher) écarte un pâle aplat de décor
    ailleurs dans l'image sans jamais exclure un vrai nuage."""
    if not HAS_SCIPY:
        return []
    ink_sky = tokens.get("shader", {}).get("ink_sky", {})
    targets = [hex_to_rgb01(v) for v in (ink_sky.get("cloud_lit"), ink_sky.get("cloud_shade")) if v]
    if not targets:
        return []
    h, w = rgb.shape[0], rgb.shape[1]
    mask = np.zeros((h, w), dtype=bool)
    for tgt in targets:
        mask |= np.linalg.norm(rgb - np.array(tgt), axis=-1) <= tol
    if row_bounds is not None:
        top, bottom = row_bounds
        row_mask = np.zeros(h, dtype=bool)
        row_mask[max(0, top):min(h, bottom)] = True
        mask &= row_mask[:, None]
    if not mask.any():
        return []
    labeled, n = ndimage.label(mask, structure=np.ones((3, 3)))
    out = []
    for label_id, sl in enumerate(ndimage.find_objects(labeled), start=1):
        if sl is None:
            continue
        rows, cols = sl
        area = int((labeled[sl] == label_id).sum())
        out.append({
            "height_px": float(rows.stop - rows.start), "width_px": float(cols.stop - cols.start),
            "area_px": area, "bbox": (rows.start, rows.stop, cols.start, cols.stop),
        })
    return out


def eval_cloud_masses(
    components: list[dict], img_shape: tuple[int, int], tokens: dict,
    sky_row_bounds: tuple[int, int],
) -> tuple[str, dict]:
    """CHK-13 : 3 à 5 masses de nuages ≥ 1 % de l'écran PAR DEMI-CIEL (moitié
    gauche/droite de l'image), aucune masse sous `cloud_min_elev_deg`
    d'élévation. `sky_row_bounds = (haut, bas)` (lignes de pixels du ciel
    détecté par `sky_region_mask`) sert à approximer l'élévation : cette
    fonction pure ne connaît ni le FOV ni l'inclinaison de la caméra
    (absents des captures PNG), donc l'élévation d'une masse est estimée
    LINÉAIREMENT entre 0° à la ligne la plus basse du ciel détecté (horizon)
    et 90° à la ligne la plus haute — approximation documentée, cohérente
    avec les autres heuristiques géométriques de ce fichier
    (`eval_horizon_closed`), et sans conséquence de gate puisque
    `tokens.checks.CHK-13.blocking = false`."""
    cfg = chk_cfg(tokens, "CHK-13")
    lo, hi = cfg.get("cloud_masses_per_half_sky", [3, 5])
    min_area_frac = cfg.get("cloud_min_area", 0.01)
    min_elev_deg = cfg.get("cloud_min_elev_deg", 6)
    h, w = img_shape
    total_area = float(h * w)
    if total_area <= 0:
        return "WARN", {"reason": "image vide"}

    top_row, bottom_row = sky_row_bounds
    span = max(1, bottom_row - top_row)

    def elevation_deg(row: float) -> float:
        frac_from_bottom = 1.0 - ((row - top_row) / span)
        return max(0.0, min(90.0, frac_from_bottom * 90.0))

    halves: dict[str, list[dict]] = {"left": [], "right": []}
    below_min_elev = []
    for comp in components:
        area_frac = comp["area_px"] / total_area
        if area_frac < min_area_frac:
            continue
        y0, y1, x0, x1 = comp["bbox"]
        cx = (x0 + x1) / 2.0
        side = "left" if cx < w / 2.0 else "right"
        halves[side].append(comp)
        elev = elevation_deg(y1)  # bas de la bbox = élévation la plus basse couverte par la masse
        if elev < min_elev_deg:
            below_min_elev.append({"bbox": comp["bbox"], "elevation_deg": elev})

    counts = {side: len(cs) for side, cs in halves.items()}
    counts_ok = all(lo <= counts[side] <= hi for side in ("left", "right"))
    status = "PASS" if (counts_ok and not below_min_elev) else "FAIL"
    return status, {"counts_per_half": counts, "below_min_elevation": below_min_elev}


def eval_cvd_recommendation(tokens: dict) -> tuple[str, dict]:
    """CHK-19 : pour chaque option de surbrillance ennemie recommandée par
    type de daltonisme, ΔE_OK simulé doit rester ≥ seuil contre TOUTES les
    couleurs de décor connues des jetons (maps.*.materials + ground)."""
    cfg = chk_cfg(tokens, "CHK-19")
    min_delta = cfg.get("min_delta_e_ok_cvd_recommended", 9)
    recommended = cfg.get("recommended", {})
    reserved = tokens["reserved"]["enemy_highlight"]

    decor_hexes: set[str] = set()
    for m in tokens.get("maps", {}).values():
        decor_hexes.add(m.get("ground", "#808080"))
        decor_hexes.update(m.get("materials", {}).values())

    worst = math.inf
    worst_detail = ""
    for cvd_kind, option_name in recommended.items():
        entry = reserved.get(option_name)
        if entry is None:
            continue
        highlight_rgb = hex_to_rgb01(entry["hex"])
        sim_highlight = simulate_cvd(highlight_rgb, cvd_kind)
        for hexval in decor_hexes:
            sim_decor = simulate_cvd(hex_to_rgb01(hexval), cvd_kind)
            d = delta_e_ok(sim_highlight, sim_decor)
            if d < worst:
                worst = d
                worst_detail = f"{cvd_kind}/{option_name} vs {hexval}"
    if worst is math.inf:
        return "WARN", {"reason": "aucune couleur de décor dans tokens.maps"}
    status = "PASS" if worst >= min_delta else "FAIL"
    return status, {"min_delta_e_ok": worst, "worst_pair": worst_detail}


def eval_ground_shadow_pair(entry: dict, tokens: dict) -> tuple[str, dict]:
    """CHK-09 : paire d'échantillons sol ombre/soleil d'UNE carte, telle que
    mesurée par tools/look_probe.gd (tâche OPS-11, comble le trou signalé par
    ART-02 : « CHK-09 non mesuré »). `entry` est un élément de
    look_probe.json["maps"] ; PASS seulement si les trois bornes de
    tokens.checks.CHK-09 sont toutes respectées : le ratio d'ombre (comme
    CHK-01, mais sur le SOL, normale horizontale réelle — jamais la face
    idéalement orientée du cube-témoin), un plancher de luminance absolue
    pour l'ombre (`shadow_min_L` : une ombre qui ne serait plus du tout la
    même matière, juste noircie) et un écart de teinte OKLCH toléré entre les
    deux échantillons (`shadow_hue_tolerance_deg` : l'ombre reste
    perceptiblement la MÊME surface, jamais une couleur différente)."""
    cfg = chk_cfg(tokens, "CHK-09")
    lo, hi = cfg.get("shadow_ratio", [0.62, 0.70])
    min_l = cfg.get("shadow_min_L", 0.30)
    hue_tol = cfg.get("shadow_hue_tolerance_deg", 45)
    ratio = entry.get("ground_shadow_ratio")
    shadow_l = entry.get("ground_shadow_L")
    hue_delta = entry.get("ground_hue_delta_deg")
    if ratio is None or shadow_l is None or hue_delta is None:
        return "WARN", {"reason": "champs ground_shadow_ratio/ground_shadow_L/ground_hue_delta_deg absents pour cette carte"}
    ok = (lo <= ratio <= hi) and (shadow_l >= min_l) and (hue_delta <= hue_tol)
    return ("PASS" if ok else "FAIL"), {
        "ground_shadow_ratio": ratio, "ground_shadow_L": shadow_l, "ground_hue_delta_deg": hue_delta,
    }


def eval_silhouette_width(entry: dict, tokens: dict) -> tuple[str, dict]:
    """CHK-10 : largeur de trait de silhouette (décor) mesurée à 30 m sur
    l'objet de calibration d'arête de tools/look_probe.gd (tâche OPS-11,
    comble le trou signalé par ART-07). PASS seulement si la largeur MINIMALE
    observée sur le pourtour atteint `outline_min_px_at_30m` ET si la
    fraction de points du pourtour qui l'atteignent dépasse
    `perimeter_fraction` — un seul point sous le seuil ne doit pas, à lui
    seul, faire échouer un pourtour par ailleurs conforme (tokens.json
    documente explicitement cette tolérance de 10 %)."""
    cfg = chk_cfg(tokens, "CHK-10")
    min_px = cfg.get("outline_min_px_at_30m", 2)
    min_fraction = cfg.get("perimeter_fraction", 0.90)
    min_w = entry.get("silhouette_min_width_px")
    frac = entry.get("silhouette_pass_fraction")
    if min_w is None or frac is None:
        return "WARN", {"reason": "champs silhouette_min_width_px/silhouette_pass_fraction absents pour cette carte"}
    ok = min_w >= min_px and frac >= min_fraction
    return ("PASS" if ok else "FAIL"), {"silhouette_min_width_px": min_w, "silhouette_pass_fraction": frac}


def eval_double_line(entry: dict, tokens: dict) -> tuple[str, dict]:
    """CHK-11 : absence de double trait (pli + silhouette non fusionnés) sur
    une vue de trois-quarts rasante de l'objet de calibration d'arête de
    tools/look_probe.gd (tâche OPS-11). `double_line_detected` (déjà
    calculé par look_probe.gd contre son propre miroir local de
    `double_line_min_len_px`/`double_line_gap_px` — non bloquant, voir
    tokens.checks.CHK-11.blocking : une divergence entre ce miroir et
    tokens.json resterait un WARN, jamais un FAIL silencieux d'un gate
    bloquant) : PASS si aucune carte ne le signale."""
    detected = entry.get("double_line_detected")
    span = entry.get("double_line_span_px")
    if detected is None:
        return "WARN", {"reason": "champ double_line_detected absent pour cette carte"}
    return ("FAIL" if detected else "PASS"), {"double_line_detected": detected, "double_line_span_px": span}


def eval_enemy_contrast_samples(samples: list[dict], tokens: dict, ink_rgb: tuple[float, float, float]) -> tuple[str, dict]:
    """CHK-18 : pour chaque échantillon {"distance_m", "highlight_rgb",
    "background_rgbs": [...]}, calcule max(WCAG(surbrillance,fond),
    WCAG(encre,fond)) et ΔE_OK(surbrillance,fond) pour CHAQUE paire
    (distance, fond). Seuils : contraste ≥ 3:1 dans ≥95 % des paires, ΔE_OK
    ≥ 20 dans 100 % des paires."""
    cfg = chk_cfg(tokens, "CHK-18")
    min_contrast = cfg.get("min_contrast", 3.0)
    pass_fraction = cfg.get("pass_fraction", 0.95)
    min_delta = cfg.get("min_delta_e_ok", 20)

    pairs = 0
    contrast_pass = 0
    delta_fail = 0
    worst_delta = math.inf
    for s in samples:
        hl = s["highlight_rgb"]
        for bg in s.get("background_rgbs", []):
            pairs += 1
            contrast = max(wcag_contrast(hl, bg), wcag_contrast(ink_rgb, bg))
            if contrast >= min_contrast:
                contrast_pass += 1
            d = delta_e_ok(hl, bg)
            worst_delta = min(worst_delta, d)
            if d < min_delta:
                delta_fail += 1
    if pairs == 0:
        return "WARN", {"reason": "aucun échantillon"}
    contrast_frac = contrast_pass / pairs
    ok = (contrast_frac >= pass_fraction) and (delta_fail == 0)
    status = "PASS" if ok else "FAIL"
    return status, {
        "pairs": pairs, "contrast_pass_fraction": contrast_frac,
        "delta_fail_count": delta_fail, "worst_delta_e_ok": (worst_delta if worst_delta is not math.inf else None),
    }


def eval_glyph_heights(heights_by_res: dict[str, list[float]], tokens: dict) -> tuple[str, dict]:
    """CHK-32 : hauteur minimale des glyphes (px) par résolution ; seuils
    tokens.checks.CHK-32 (min_px_1080/min_px_720).

    Retour du vérificateur (tâche OPS-13) : un strict `min()` sur TOUTES les
    composantes de TOUTES les captures fait retomber le VERDICT sur une seule
    composante parasite de quelques px (bord anticrénelé, glitch de rendu —
    voir `find_glyph_components`/`ring_background_rgb`), quelle que soit la
    qualité du fix ciblé sur la détection elle-même : à l'échelle d'un run
    réel (des dizaines de captures, des milliers de composantes), une
    composante dégénérée isolée est statistiquement inévitable et ne dit rien
    de la lisibilité RÉELLE de l'interface. Comme `eval_silhouette_width`
    (CHK-10) et `eval_enemy_contrast_samples` (CHK-18) dans ce même fichier,
    le VERDICT tolère une fraction minoritaire d'échantillons sous le seuil
    (`pass_fraction`, tokens.checks.CHK-32.pass_fraction, 0.95 par défaut) —
    le pire cas RÉEL (`min_height_px_*`) reste rapporté tel quel pour le
    diagnostic, jamais lissé ni caché : seul le critère PASS/FAIL change,
    pas la mesure elle-même."""
    cfg = chk_cfg(tokens, "CHK-32")
    thresholds = {"1080": cfg.get("min_px_1080", 21), "720": cfg.get("min_px_720", 14)}
    pass_fraction = cfg.get("pass_fraction", 0.95)
    if not any(heights_by_res.get(k) for k in thresholds):
        return "WARN", {"reason": "aucune hauteur de glyphe mesurée"}
    status = "PASS"
    detail: dict[str, Any] = {}
    for res, min_px in thresholds.items():
        heights = heights_by_res.get(res) or []
        if not heights:
            continue
        worst = min(heights)
        detail[f"min_height_px_{res}"] = worst
        ok_count = sum(1 for h in heights if h >= min_px)
        frac = ok_count / len(heights)
        detail[f"pass_fraction_{res}"] = frac
        detail[f"sample_count_{res}"] = len(heights)
        if frac < pass_fraction:
            status = "FAIL"
    return status, detail


def eval_min_contrast_pairs(pairs: list[tuple[tuple, tuple]], min_ratio: float, pass_fraction: float = 1.0) -> tuple[str, dict]:
    """CHK-33 (et autres seuils WCAG génériques) : contraste texte/fond sur
    une liste de paires (fg_rgb, bg_rgb).

    Retour du vérificateur (tâche OPS-13) : comme `eval_glyph_heights`, le
    VERDICT ne repose plus sur un strict `min()` de toutes les paires — une
    seule paire dégénérée (fg≈bg, contraste≈1.0 : le fond mesuré est en
    réalité un fragment du MÊME glyphe, voir `ring_background_rgb`) ne doit
    plus, à elle seule, faire échouer la mesure sur des captures par ailleurs
    lisibles. `pass_fraction=1.0` par défaut préserve EXACTEMENT le
    comportement historique (tout appelant qui ne le précise pas garde le
    strict `min()` d'avant) ; l'appelant CHK-33 passe explicitement une
    tolérance (tokens.checks.CHK-33.pass_fraction, 0.95 par défaut). Le pire
    contraste RÉEL (`worst_contrast`) reste rapporté pour le diagnostic."""
    if not pairs:
        return "WARN", {"worst_contrast": 0.0, "pass_fraction": 0.0, "pairs": 0}
    contrasts = [wcag_contrast(fg, bg) for fg, bg in pairs]
    worst = min(contrasts)
    ok_count = sum(1 for c in contrasts if c >= min_ratio)
    frac = ok_count / len(contrasts)
    status = "PASS" if frac >= pass_fraction else "FAIL"
    return status, {"worst_contrast": worst, "pass_fraction": frac, "pairs": len(contrasts)}


def non_agent_reference_colors(tokens: dict) -> list[tuple[float, float, float]]:
    """Couleurs-jetons NON spécifiques à un agent mais réutilisées PARTOUT
    dans l'UI (pinceau/marque, jeu) — CHK-40 : une clé d'agent peut tomber,
    par coïncidence de teinte, tout près d'un jeton universel qui s'affiche
    sur CHAQUE écran (bandeau, boutons, glyphe allié/ennemi) sans aucun
    rapport avec cet agent (ex. `choc` #BE2D25 contre `pinceau.brush`
    #C8242C : distance ~0.0595, sous l'ancien seuil 0.06 — Retour QA ART-30
    24/09 16h04, « couleur d'agent détectée dans le HUD » sur des écrans sans
    aucun élément propre à `choc`). Voir `agent_key_leak_mask`."""
    out: list[tuple[float, float, float]] = []
    color = tokens.get("color", {})
    for group, keys in (
        ("pinceau", ("brush", "pressed", "bullet")),
        ("game", ("ally", "enemy_magenta", "enemy_citron", "objective", "headshot")),
    ):
        for k in keys:
            entry = color.get(group, {}).get(k)
            if entry and "hex" in entry:
                out.append(hex_to_rgb01(entry["hex"]))
    return out


def agent_key_leak_mask(
    rgb: np.ndarray,
    agent_key_rgb: tuple[float, float, float],
    other_reference_colors: list[tuple[float, float, float]],
    threshold: float = 0.06,
) -> np.ndarray:
    """CHK-40 : masque des pixels dont CETTE clé d'agent est la classification
    la plus proche parmi (sa propre clé, les clés des autres agents, les
    jetons non-agents réutilisés partout — `non_agent_reference_colors`). Un
    pixel proche à la fois de `agent_key_rgb` ET d'un jeton universel (ex.
    `pinceau.brush`) n'est PAS une fuite : ce jeton s'affiche sur CHAQUE écran
    par conception, c'est une explication au moins aussi valable — le compter
    ferait FAIL en permanence dès qu'un agent a une clé proche de la marque,
    sans rapport avec un vrai bug HUD."""
    key = np.array(agent_key_rgb)
    dist_key = np.linalg.norm(rgb - key, axis=-1)
    candidate = dist_key < threshold
    if not candidate.any() or not other_reference_colors:
        return candidate
    best_other = np.full(dist_key.shape, np.inf)
    for other in other_reference_colors:
        d = np.linalg.norm(rgb - np.array(other), axis=-1)
        best_other = np.minimum(best_other, d)
    # Fuite seulement si CETTE clé reste (au moins) la meilleure explication.
    return candidate & (dist_key <= best_other + 1e-9)


# =============================================================================
#  Lints statiques (fichiers du dépôt, sans capture)
# =============================================================================

_HEX_RE = re.compile(r"#([0-9a-fA-F]{6})\b")


def _reserved_violations(hexes: set[str], tokens: dict) -> list[str]:
    bands = tokens["reserved"]["hue_bands_deg"]
    thresh = tokens["reserved"]["chroma_threshold"]
    allowed = {v["hex"].lower() for v in tokens["reserved"]["enemy_highlight"].values()}
    bad = []
    for hx in hexes:
        if hx.lower() in allowed:
            continue
        _, c, h = rgb01_to_oklch(hex_to_rgb01(hx))
        if c > thresh and hue_in_bands(h, bands):
            bad.append(hx)
    return bad


def lint_reserved_colors_in_data(tokens: dict, repo_root: Path) -> tuple[str, dict]:
    """CHK-07 : aucune couleur de `tokens.json` (hors `reserved`),
    `Cartoon._MAP_PALETTES`, `gen_textures.py` ou des couleurs-clés
    d'AgentDatabase.gd (l'appel `_agent(..., Color("hex"))`) ne doit tomber
    dans une bande réservée."""
    hexes: set[str] = set()

    def _walk(node):
        if isinstance(node, str) and re.fullmatch(r"#?[0-9a-fA-F]{6}", node.lstrip("#")) and node.startswith("#"):
            hexes.add(node)
        elif isinstance(node, dict):
            for k, v in node.items():
                if k == "reserved":
                    continue
                _walk(v)
        elif isinstance(node, list):
            for v in node:
                _walk(v)

    tokens_copy = {k: v for k, v in tokens.items() if k != "reserved"}
    _walk(tokens_copy)

    violations: dict[str, list[str]] = {}
    tok_bad = _reserved_violations(hexes, tokens)
    if tok_bad:
        violations["tokens.json"] = tok_bad

    cartoon_path = repo_root / "scripts" / "core" / "Cartoon.gd"
    if cartoon_path.is_file():
        text = cartoon_path.read_text(encoding="utf-8", errors="ignore")
        m = re.search(r"_MAP_PALETTES\s*:\s*Dictionary\s*=\s*\{(.*?)\n\}", text, re.DOTALL)
        block = m.group(1) if m else text
        cartoon_hexes = {f"#{h}" for h in re.findall(r'"#?([0-9a-fA-F]{6})"', block)}
        bad = _reserved_violations(cartoon_hexes, tokens)
        if bad:
            violations["Cartoon._MAP_PALETTES"] = bad

    gen_textures = repo_root / "tools" / "textures" / "gen_textures.py"
    if gen_textures.is_file():
        text = gen_textures.read_text(encoding="utf-8", errors="ignore")
        gt_hexes = {f"#{h}" for h in _HEX_RE.findall(text)}
        bad = _reserved_violations(gt_hexes, tokens)
        if bad:
            violations["gen_textures.py"] = bad

    agent_db = repo_root / "scripts" / "agents" / "AgentDatabase.gd"
    if agent_db.is_file():
        text = agent_db.read_text(encoding="utf-8", errors="ignore")
        # Couleur-clé d'agent : argument `Color("hex")` dans un appel `_agent(...)`
        # (voir AgentDatabase.gd::_agent) — ignore délibérément les autres
        # `Color(...)` du fichier (icônes d'aptitude, etc., pas des couleurs
        # de base monde/personnage/cosmétique au sens de la règle `reserved`).
        agent_hexes = {f"#{h}" for h in re.findall(r'_agent\([^)]*Color\("([0-9a-fA-F]{6})"\)', text, re.DOTALL)}
        bad = _reserved_violations(agent_hexes, tokens)
        if bad:
            violations["AgentDatabase._agent(color=...)"] = bad

    if violations:
        return "FAIL", {"violations": violations}
    return "PASS", {"scanned_hex_count": len(hexes)}


def lint_albedo_textures(repo_root: Path, tokens: dict) -> tuple[str, dict]:
    """CHK-08 : `assets/textures/painted/*_albedo.png` (et trim-sheets) sans
    encre (0 pixel L<0.25, sauf `rubber*`) et sans bruit fbm résiduel
    (écart-type de L après flou gaussien 2px ≤ seuil)."""
    cfg = chk_cfg(tokens, "CHK-08")
    min_l = cfg.get("albedo_min_L", 0.25)
    std_max = cfg.get("albedo_L_std_after_blur2px_max", 0.04)
    exempt_prefixes = tuple(p.rstrip("*") for p in cfg.get("exempt", []))

    paths = sorted((repo_root / "assets" / "textures" / "painted").glob("*_albedo.png"))
    paths += sorted((repo_root / "assets" / "textures" / "trim").glob("*.png"))
    if not paths:
        return "WARN", {"reason": "aucune texture peinte trouvée (ART-04 pas encore livrée ?)"}

    if not HAS_SCIPY:
        return "WARN", {"reason": "scipy indisponible pour le flou gaussien"}

    violations = []
    for p in paths:
        if any(p.name.startswith(pref) for pref in exempt_prefixes):
            continue
        rgb = load_image_rgb01(p)
        if rgb is None:
            continue
        l_, _, _ = oklab_to_oklch(rgb01_to_oklab(rgb))
        dark_frac = float((l_ < min_l).mean())
        blurred = ndimage.gaussian_filter(l_, sigma=2.0 / 3.0)  # ~2px (sigma≈px/3, approximation usuelle)
        std_after_blur = float(blurred.std())
        if dark_frac > 0.0 or std_after_blur > std_max:
            violations.append({"file": p.name, "dark_fraction": dark_frac, "std_after_blur": std_after_blur})
    status = "PASS" if not violations else "FAIL"
    return status, {"checked": len(paths), "violations": violations[:20]}


def lint_agent_key_colors(tokens: dict) -> tuple[str, dict]:
    """CHK-26 : couleur-clé de chaque agent hors bandes réservées, texte
    d'autocollant ≥ 4.5:1 sur la clé."""
    cfg = chk_cfg(tokens, "CHK-26")
    min_contrast = cfg.get("text_on_key_min_contrast", 4.5)
    bands = tokens["reserved"]["hue_bands_deg"]
    thresh = tokens["reserved"]["chroma_threshold"]
    ink = hex_to_rgb01(tokens["color"]["ink"]["hex"])
    papier = hex_to_rgb01(tokens["color"]["papier"]["text"]["hex"])

    violations = []
    for agent_id, agent in tokens.get("agents", {}).items():
        key_rgb = hex_to_rgb01(agent["key"])
        _, c, h = rgb01_to_oklch(key_rgb)
        if c > thresh and hue_in_bands(h, bands):
            violations.append(f"{agent_id} : couleur-clé {agent['key']} dans une bande réservée")
            continue
        text_on = agent.get("text_on_key")
        text_rgb = ink if text_on == "ink" else papier
        contrast = wcag_contrast(text_rgb, key_rgb)
        if contrast < min_contrast:
            violations.append(f"{agent_id} : contraste texte/clé {contrast:.2f} < {min_contrast}")
    status = "PASS" if not violations else "FAIL"
    return status, {"violations": violations}


_SHADER_UNIFORM_RE = re.compile(r"uniform\s+\w+\s+(\w+)\s*(?::\s*[\w_]+\s*)?=\s*([\-\w.]+)")


def lint_shader_defaults(repo_root: Path, tokens: dict) -> tuple[str, dict]:
    """CHK-27 : `paint_grain_strength = 0`, `band_count = 2` dans
    `assets/shaders/ink_toon.gdshader` (valeurs par défaut des `uniform`)."""
    path = repo_root / "assets" / "shaders" / "ink_toon.gdshader"
    if not path.is_file():
        return "WARN", {"reason": "ink_toon.gdshader introuvable"}
    text = path.read_text(encoding="utf-8", errors="ignore")
    defaults = {m.group(1): m.group(2) for m in _SHADER_UNIFORM_RE.finditer(text)}
    expected = tokens.get("shader", {}).get("ink_toon", {}).get("world", {})
    violations = []
    for key in ("paint_grain_strength", "band_count"):
        if key not in defaults:
            continue
        try:
            actual = float(defaults[key])
        except ValueError:
            continue
        want = expected.get(key)
        if want is not None and abs(actual - float(want)) > 1e-6:
            violations.append(f"{key} = {actual} (attendu {want})")
    status = "PASS" if not violations else "FAIL"
    return status, {"found_uniforms": defaults, "violations": violations}


_FONT_RESOURCE_RE = re.compile(r'res://resources/fonts/([\w.\-]+)\.ttf')


def lint_fonts(repo_root: Path, tokens: dict) -> tuple[str, dict]:
    """CHK-39 : seules des polices Barlow(Condensed/SemiCondensed) et Bangers
    sont référencées ; les fichiers `fonts_removed` de tokens.json ne le sont
    plus."""
    cfg = chk_cfg(tokens, "CHK-39")
    allowed_prefixes = tuple(cfg.get("allowed_font_prefixes", []))
    removed = set(tokens.get("type", {}).get("fonts_removed", []))
    referenced: set[str] = set()
    for ext in ("*.gd", "*.tscn", "*.tres"):
        for p in repo_root.rglob(ext):
            if "addons" in p.parts or ".godot" in p.parts:
                continue
            try:
                text = p.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            for m in _FONT_RESOURCE_RE.finditer(text):
                referenced.add(m.group(0).rsplit("/", 1)[-1])
    if not referenced:
        return "WARN", {"reason": "aucune police référencée trouvée (scan .gd/.tscn/.tres)"}
    disallowed = [f for f in referenced if not any(f.startswith(pref) for pref in allowed_prefixes)]
    reintroduced = [f for f in referenced if f in removed]
    violations = disallowed + reintroduced
    status = "PASS" if not violations else "FAIL"
    return status, {"referenced": sorted(referenced), "violations": violations}


_SLANT_DEG_RE = re.compile(r"const\s+SLANT_DEG\s*:=\s*([\-0-9.]+)")
_ITALIC_SLANT_RE = re.compile(r"const\s+_ITALIC_SLANT\s*:=\s*([\-0-9.]+)")
_SHADOW_OFFSET_RE = re.compile(
    r"const\s+(SHADOW_HARD_OFFSET|SHADOW_HARD_SMALL_OFFSET)\s*:=\s*Vector2\(\s*([\-0-9.]+)\s*,\s*([\-0-9.]+)\s*\)"
)
_SHADOW_SIZE_RE = re.compile(r"\.shadow_size\s*=\s*([\-0-9.]+)")


def lint_geometry(repo_root: Path, tokens: dict) -> tuple[str, dict]:
    """CHK-38 : géométrie de `scripts/ui/Comic.gd` — une seule inclinaison
    (`SLANT_DEG` = `tokens.shape.slant_deg`, `_ITALIC_SLANT` = tan(SLANT_DEG)
    = `tokens.shape.slant_shear`/`checks.CHK-38.italic_shear`, STYLE_BIBLE v3
    §8.1 règle 5) et ombres DURES (`SHADOW_HARD_OFFSET`/`SHADOW_HARD_SMALL_OFFSET`
    = `tokens.shape.shadow.hard(_small).offset`, jamais de
    `StyleBoxFlat.shadow_size` > `shadow_blur_max` — le relief vient
    uniquement du décalage opaque, jamais d'un flou natif, STYLE_BIBLE v3
    §8.2 "shadow.hard")."""
    cfg = chk_cfg(tokens, "CHK-38")
    path = repo_root / "scripts" / "ui" / "Comic.gd"
    if not path.is_file():
        return "WARN", {"reason": "scripts/ui/Comic.gd introuvable"}
    text = path.read_text(encoding="utf-8", errors="ignore")

    tol_deg = float(cfg.get("slant_tolerance_deg", 0.5))
    expected_deg = float(cfg.get("slant_deg", 12))
    expected_shear = float(cfg.get("italic_shear", 0.2126))
    shadow_blur_max = float(cfg.get("shadow_blur_max", 0))
    shadow_tokens = tokens.get("shape", {}).get("shadow", {})

    violations: list[str] = []

    m_deg = _SLANT_DEG_RE.search(text)
    deg: float | None = None
    if m_deg is None:
        violations.append("SLANT_DEG introuvable")
    else:
        deg = float(m_deg.group(1))
        if abs(deg - expected_deg) > tol_deg:
            violations.append(f"SLANT_DEG = {deg} (attendu {expected_deg} +/- {tol_deg})")

    m_shear = _ITALIC_SLANT_RE.search(text)
    if m_shear is None:
        violations.append("_ITALIC_SLANT introuvable")
    else:
        shear = float(m_shear.group(1))
        if abs(shear - expected_shear) > 1e-3:
            violations.append(f"_ITALIC_SLANT = {shear} (attendu {expected_shear} en repli, STYLE_BIBLE v3 §8.1)")
        if deg is not None:
            expected_from_deg = math.tan(math.radians(deg))
            if abs(shear - expected_from_deg) > 1e-3:
                violations.append(
                    f"_ITALIC_SLANT = {shear} incohérent avec tan(SLANT_DEG={deg}°) = {expected_from_deg:.4f}"
                    " (une seule inclinaison pour les formes et le cisaillement synthétique)"
                )

    found_offsets = {m.group(1): (float(m.group(2)), float(m.group(3))) for m in _SHADOW_OFFSET_RE.finditer(text)}
    offset_map = {
        "SHADOW_HARD_OFFSET": tuple(float(v) for v in shadow_tokens.get("hard", {}).get("offset", [6, 6])),
        "SHADOW_HARD_SMALL_OFFSET": tuple(float(v) for v in shadow_tokens.get("hard_small", {}).get("offset", [3, 3])),
    }
    for name, expected in offset_map.items():
        found = found_offsets.get(name)
        if found is None:
            violations.append(f"{name} introuvable")
        elif found != expected:
            violations.append(f"{name} = {found} (attendu {expected})")

    for m in _SHADOW_SIZE_RE.finditer(text):
        val = float(m.group(1))
        if val > shadow_blur_max:
            violations.append(
                f"shadow_size = {val} > {shadow_blur_max} (ombre floutée native interdite, CHK-38 exige un décalage opaque)"
            )

    status = "PASS" if not violations else "FAIL"
    return status, {
        "slant_deg_found": deg,
        "italic_slant_found": float(m_shear.group(1)) if m_shear else None,
        "shadow_offsets_found": {k: list(v) for k, v in found_offsets.items()},
        "violations": violations,
    }


_THEME_PROPERTY_RE = re.compile(r"^(\w+)/(\w+)/(\w+)\s*=", re.MULTILINE)

# Types de contrôle purement décoratifs (jamais interactifs) : exclus de
# CHK-37 même s'ils apparaissent dans le thème (`Panel`/`PanelContainer`
# servent de fond de carte/panneau, `Label` n'a ni survol ni focus ni état
# désactivé propre).
_THEME_NON_INTERACTIVE = {
    "Panel", "PanelContainer", "Label", "RichTextLabel",
    "TextureRect", "ColorRect", "Separator", "HSeparator", "VSeparator",
}


def parse_theme_control_keys(theme_text: str) -> dict[str, list[str]]:
    """Extrait, de la section `[resource]` d'un `Theme` .tres (format Godot 4
    — propriétés `ControlType/categorie/cle = valeur`, ex.
    `Button/styles/hover = SubResource(...)`), les clés de propriété par type
    de contrôle, TOUTES catégories confondues (`styles`, `colors`, `icons`,
    `fonts`, `constants`...). La catégorie est ignorée à dessein : dans cette
    palette, un même état (`hover`, `pressed`...) s'exprime tantôt par un
    StyleBox dédié (`Button/styles/hover`), tantôt par une simple couleur de
    police (`CheckBox/colors/font_hover_color`, un contrôle qui n'a AUCUN
    style de fond) — voir `_covers_state`, qui fait le tri par contenu de clé
    plutôt que par catégorie."""
    if "[resource]" in theme_text:
        theme_text = theme_text.rsplit("[resource]", 1)[1]
    out: dict[str, list[str]] = {}
    for m in _THEME_PROPERTY_RE.finditer(theme_text):
        control, _category, key = m.group(1), m.group(2), m.group(3)
        out.setdefault(control, []).append(key)
    return out


def _covers_state(key: str, state: str) -> bool:
    """Une clé de thème (`hover`, `font_hover_color`, `pressed_mirrored`,
    `hover_pressed`, `grabber_disabled`...) « couvre » `state` si ce mot
    apparaît tel quel parmi ses segments séparés par `_` — SAUF sous
    `clear_button*` : l'icône du petit bouton d'effacement de `LineEdit` est
    un sous-élément DÉCORATIF, pas un état du contrôle entier (sans cette
    exclusion, `clear_button_color_pressed` ferait passer à tort
    `LineEdit`/`pressed`, qui n'a en réalité aucun retour visuel pressé)."""
    if key.startswith("clear_button"):
        return False
    return state in key.split("_")


def eval_theme_states(control_keys: dict[str, list[str]], tokens: dict) -> tuple[str, dict]:
    """CHK-37 (volet « styles complets ») : chaque contrôle interactif du
    thème (toute entrée hors `_THEME_NON_INTERACTIVE`) doit couvrir `hover`,
    `focus`, `pressed` et `disabled` (tokens.checks.CHK-37.required_styles),
    par un StyleBox OU une couleur dédiés (`_covers_state`). Un type de
    contrôle absent du thème n'est PAS mis en cause ici (il n'a simplement
    pas encore été personnalisé — question distincte de « ses états sont-ils
    complets »).

    Ne mesure PAS le second volet de CHK-37 (« chaque contrôle désactivé
    expose une raison non vide », `disabled_reason_required`), qui nécessite
    un parcours des scènes .tscn (quels contrôles sont réellement
    `disabled = true` en jeu, avec quelle infobulle/libellé) — hors de
    portée d'un lint statique du seul fichier de thème ; voir la clé `note`
    du détail renvoyé."""
    cfg = tokens.get("checks", {}).get("CHK-37", {})
    required = cfg.get("required_styles", ["hover", "focus", "pressed", "disabled"])
    in_scope = {c: keys for c, keys in control_keys.items() if c not in _THEME_NON_INTERACTIVE}
    if not in_scope:
        return "WARN", {"reason": "aucun contrôle interactif trouvé dans le thème"}
    violations: dict[str, list[str]] = {}
    for control, keys in in_scope.items():
        missing = [s for s in required if not any(_covers_state(k, s) for k in keys)]
        if missing:
            violations[control] = missing
    status = "PASS" if not violations else "FAIL"
    return status, {
        "controls_checked": sorted(in_scope.keys()),
        "violations": violations,
        "note": "volet « raison non vide sur contrôle désactivé » non mesuré (nécessite un parcours de scènes .tscn, hors de portée du lint de thème seul)",
    }


def lint_theme_states(repo_root: Path, tokens: dict) -> tuple[str, dict]:
    """CHK-37 : lit `resources/ui/ui_theme.tres` et applique
    `eval_theme_states`. Toujours mesurable dès que le fichier de thème
    existe — comme `lint_geometry`/`lint_fonts`, indépendant d'un run_dir de
    captures."""
    path = repo_root / "resources" / "ui" / "ui_theme.tres"
    if not path.is_file():
        return "WARN", {"reason": "resources/ui/ui_theme.tres introuvable"}
    text = path.read_text(encoding="utf-8", errors="ignore")
    control_keys = parse_theme_control_keys(text)
    return eval_theme_states(control_keys, tokens)


_TWEEN_DURATION_RE = re.compile(r"tween_property\([^)]*?,\s*([0-9]*\.?[0-9]+)\s*\)")


def lint_tween_durations(repo_root: Path, tokens: dict) -> tuple[str, dict]:
    """CHK-41 : durées de `tween_property(...)` dans `scripts/ui/` et
    `scripts/core/` — hors bande [90ms,1200ms] (tween ou rafale confondus,
    voir note) considéré suspect. Heuristique regex, non exhaustive : ne fait
    jamais FAIL sur une valeur simplement ambiguë, seulement sur une durée
    manifestement aberrante (>3s ou <0.02s)."""
    durations: list[tuple[str, float]] = []
    for base in ("scripts/ui", "scripts/core"):
        d = repo_root / base
        if not d.is_dir():
            continue
        for p in d.rglob("*.gd"):
            try:
                text = p.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            for m in _TWEEN_DURATION_RE.finditer(text):
                try:
                    durations.append((p.name, float(m.group(1))))
                except ValueError:
                    pass
    if not durations:
        return "WARN", {"reason": "aucun tween_property(...) trouvé sous scripts/ui|core (UiFx.gd pas encore livré ?)"}
    aberrant = [(f, d) for f, d in durations if d > 3.0 or d < 0.02]
    status = "FAIL" if aberrant else "PASS"
    return status, {"count": len(durations), "aberrant": aberrant[:20]}


# =============================================================================
#  Découverte des captures d'un run_dir + assemblage des 47 contrôles
# =============================================================================

class Context:
    def __init__(self, run_dir: Path | None, tokens: dict, repo_root: Path):
        self.run_dir = run_dir
        self.tokens = tokens
        self.repo_root = repo_root
        self._image_cache: dict[Path, np.ndarray | None] = {}

    def image(self, path: Path) -> np.ndarray | None:
        if path not in self._image_cache:
            self._image_cache[path] = load_image_rgb01(path)
        return self._image_cache[path]

    def map_shots_dir(self) -> Path | None:
        return self._maybe(self.run_dir / "map_shots") if self.run_dir else None

    def ui_shots_dir(self) -> Path | None:
        return self._maybe(self.run_dir / "ui_shots") if self.run_dir else None

    def char_ingame_dir(self) -> Path | None:
        return self._maybe(self.run_dir / "character_shots" / "ingame") if self.run_dir else None

    def fp_dir(self) -> Path | None:
        return self._maybe(self.run_dir / "viewmodel_fp" / "fp") if self.run_dir else None

    def perf_bench_json(self) -> dict | None:
        return self._load_json(self.run_dir / "perf_bench" / "perf.json") if self.run_dir else None

    def look_probe_json(self) -> dict | None:
        if not self.run_dir:
            return None
        return self._load_json(self.run_dir / "look_probe" / "look_probe.json") or self._load_json(self.run_dir / "look_probe.json")

    def style_masks_json(self) -> dict | None:
        return self._load_json(self.run_dir / "style_masks" / "style_masks.json") if self.run_dir else None

    def fp_shots_json(self) -> dict | None:
        return self._load_json(self.run_dir / "viewmodel_fp" / "fp" / "fp_shots.json") if self.run_dir else None

    @staticmethod
    def _maybe(p: Path) -> Path | None:
        return p if p.is_dir() else None

    @staticmethod
    def _load_json(p: Path) -> dict | None:
        try:
            return json.loads(p.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError):
            return None

    def map_shot_files(self, kind: str) -> list[Path]:
        """`kind` : "player" (spawn/centre/eye*) ou "aerial" (aerial_*)."""
        d = self.map_shots_dir()
        if d is None:
            return []
        out = []
        for p in sorted(d.glob("*.png")):
            stem = p.stem
            is_aerial = "_aerial_" in stem or stem.endswith("_top")
            if kind == "aerial" and is_aerial:
                out.append(p)
            elif kind == "player" and not is_aerial:
                out.append(p)
        return out


def combined_included_mask(ctx: Context, img_shape: tuple[int, int], style_masks: dict | None) -> np.ndarray:
    """Masque « inclus » = tout SAUF HUD/personnages, pour les vues de
    map_shots (caméra externe). Sans style_masks (pas encore produit dans ce
    run), retombe sur « tout inclus » — approximation documentée dans le
    détail de chaque contrôle appelant."""
    included = np.ones(img_shape, dtype=bool)
    if not style_masks:
        return included
    for entry in style_masks.get("hud", []):
        m = load_mask_bool(Path(entry["path"]))
        if m is not None:
            m = resize_mask_to(m, img_shape)
            included &= ~m
    return included


def resolve_ground_silhouette_checks(lp: dict | None, tokens: dict) -> dict[str, Finding]:
    """CHK-09/CHK-10/CHK-11 (tâche OPS-11) : agrège, sur les 8 cartes de
    `lp["maps"]` (tools/look_probe.gd), le PIRE statut par contrôle — même
    politique que CHK-02..06/21 sur map_shots (`worse`, un seul FAIL suffit).
    Chaque contrôle retombe individuellement en « non mesuré » si ses champs
    ne sont présents sur AUCUNE carte (ex. un look_probe.json produit par une
    version antérieure de tools/look_probe.gd, avant OPS-11) — jamais un FAIL
    sur une donnée absente."""
    out: dict[str, Finding] = {}
    if lp is None or not lp.get("maps"):
        reason = "look_probe.json absent (tools/look_probe.gd, ART-01/OPS-11, pas encore livré ou pas lancé sur ce run)"
        out["CHK-09"] = Finding.unmeasured(reason)
        out["CHK-10"] = Finding.unmeasured(reason)
        out["CHK-11"] = Finding.unmeasured(reason)
        return out

    maps = lp["maps"]

    def _aggregate(chk_id: str, has_field: str, evaluator) -> Finding:
        if not any(m.get(has_field) is not None for m in maps):
            return Finding.unmeasured(
                f"look_probe.json ne contient pas encore '{has_field}' (version de tools/look_probe.gd antérieure à la tâche OPS-11)"
            )
        worst = "PASS"
        details = []
        for m in maps:
            s, d = evaluator(m, tokens)
            worst = worse(worst, s)
            details.append({"map_id": m.get("map_id"), "status": s, **d})
        return Finding(worst, f"{len(maps)} carte(s) évaluée(s)", data={"per_map": details})

    out["CHK-09"] = _aggregate("CHK-09", "ground_shadow_ratio", eval_ground_shadow_pair)
    out["CHK-10"] = _aggregate("CHK-10", "silhouette_min_width_px", eval_silhouette_width)
    out["CHK-11"] = _aggregate("CHK-11", "double_line_detected", eval_double_line)
    return out


def ink_mask_from_image(rgb: np.ndarray, tokens: dict) -> np.ndarray:
    """§11.1 : masque encre = pixels L<0.25, approximé ici en niveau OKLab
    (pas d'épaisseur ≤6px imposée — cette variante sert seulement à EXCLURE
    les traits d'encre des calculs de "boue"/"sol", pas à mesurer CHK-03
    elle-même, qui a son propre seuil)."""
    l_, _, _ = oklab_to_oklch(rgb01_to_oklab(rgb))
    return l_ < tokens.get("world", {}).get("value_structure", {}).get("ink_L", 0.20)


def resolve_all(ctx: Context) -> dict[str, Finding]:
    t = ctx.tokens
    out: dict[str, Finding] = {}

    # ---- CHK-01 : sonde WYSIWYG (tools/look_probe.gd, ART-01) -------------
    lp = ctx.look_probe_json()
    if lp is None:
        out["CHK-01"] = Finding.unmeasured("look_probe.json absent (tools/look_probe.gd, ART-01, pas encore livré)")
    else:
        cfg = chk_cfg(t, "CHK-01")
        lit_l = lp.get("lit_L")
        shadow_ratio = lp.get("shadow_ratio")
        lo, hi = cfg.get("probe_lit_L", [0.72, 0.78])
        slo, shi = cfg.get("probe_shadow_ratio", [0.62, 0.70])
        ok = lit_l is not None and lo <= lit_l <= hi and shadow_ratio is not None and slo <= shadow_ratio <= shi
        out["CHK-01"] = Finding("PASS" if ok else "FAIL", f"lit_L={lit_l} shadow_ratio={shadow_ratio}")

    # ---- CHK-09, CHK-10, CHK-11 : sol ombre/soleil + trait de silhouette
    # (tools/look_probe.gd, tâche OPS-11) -- même source (`lp`) que CHK-01,
    # sur les 8 cartes plutôt qu'une seule mesure globale.
    out.update(resolve_ground_silhouette_checks(lp, t))

    # ---- CHK-02..06, 21 : vues joueur de map_shots -------------------------
    player_shots = ctx.map_shot_files("player")
    style_masks = ctx.style_masks_json()
    if not player_shots:
        reason = "map_shots/ absent ou vide (étape non lancée ou -Quick)"
        for chk in ("CHK-02", "CHK-03", "CHK-04", "CHK-05", "CHK-06", "CHK-21"):
            out[chk] = Finding.unmeasured(reason)
    else:
        worst = {"CHK-02": "PASS", "CHK-03": "PASS", "CHK-04": "PASS", "CHK-05": "PASS", "CHK-06": "PASS", "CHK-21": "PASS"}
        detail_acc: dict[str, list] = {k: [] for k in worst}
        mask_used = False
        for p in player_shots:
            rgb = ctx.image(p)
            if rgb is None:
                continue
            included = combined_included_mask(ctx, rgb.shape[:2], style_masks)
            if style_masks:
                mask_used = True
            ink = ink_mask_from_image(rgb, t)
            included_no_ink = included & ~ink

            cfg02 = chk_cfg(t, "CHK-02")
            s, frac, _, _ = eval_pixel_fraction_range(rgb, included_no_ink, tuple(cfg02.get("mud_L", [0.25, 0.33])), frac_max=cfg02.get("max_fraction", 0.05))
            worst["CHK-02"] = worse(worst["CHK-02"], s)
            detail_acc["CHK-02"].append({"file": p.name, "fraction": frac})

            cfg03 = chk_cfg(t, "CHK-03")
            s3, frac3, _, _ = eval_pixel_fraction_range(rgb, included, tuple([0.0, cfg03.get("ink_L_max", 0.25)]), frac_range=tuple(cfg03.get("fraction", [0.02, 0.09])))
            worst["CHK-03"] = worse(worst["CHK-03"], s3)
            detail_acc["CHK-03"].append({"file": p.name, "fraction": frac3})

            s4, d4 = eval_ground_stats(rgb, t, included=included)
            worst["CHK-04"] = worse(worst["CHK-04"], s4)
            detail_acc["CHK-04"].append({"file": p.name, **d4})

            s5, d5 = eval_chroma_hierarchy(rgb, t, included=included)
            worst["CHK-05"] = worse(worst["CHK-05"], s5)
            detail_acc["CHK-05"].append({"file": p.name, **d5})

            s6, frac6 = eval_reserved_hue_fraction(rgb, included_no_ink, t)
            worst["CHK-06"] = worse(worst["CHK-06"], s6)
            detail_acc["CHK-06"].append({"file": p.name, "fraction": frac6})

            s21, frac21 = eval_exclusive_enemy_colors(rgb, included, t)
            worst["CHK-21"] = worse(worst["CHK-21"], s21)
            detail_acc["CHK-21"].append({"file": p.name, "fraction": frac21})

        approx_note = "" if mask_used else " (approximation : masque HUD/personnages indisponible, image entière évaluée)"
        for chk in worst:
            out[chk] = Finding(worst[chk], f"{len(player_shots)} vue(s) map_shots évaluée(s){approx_note}", data={"per_file": detail_acc[chk][:20]})

    # ---- CHK-07 : lint statique (toujours mesurable) -----------------------
    s7, d7 = lint_reserved_colors_in_data(t, ctx.repo_root)
    out["CHK-07"] = Finding(s7, json.dumps(d7, ensure_ascii=False)[:400], data=d7)

    # ---- CHK-08 : lint des albédos -----------------------------------------
    s8, d8 = lint_albedo_textures(ctx.repo_root, t)
    measured8 = "reason" not in d8
    out["CHK-08"] = Finding(s8 if measured8 else "WARN", (d8.get("reason") or f"{d8.get('checked', 0)} fichier(s), {len(d8.get('violations', []))} violation(s)"), measured=measured8, data=d8)

    # ---- CHK-12, CHK-13 : vues aériennes -----------------------------------
    aerial_shots = ctx.map_shot_files("aerial")
    if not aerial_shots:
        out["CHK-12"] = Finding.unmeasured("aucune vue aérienne dans map_shots/")
        out["CHK-13"] = Finding.unmeasured("aucune vue aérienne dans map_shots/")
    else:
        worst12 = "PASS"
        details12 = []
        worst13 = "PASS"
        details13 = []
        any13measured = False
        for p in aerial_shots:
            rgb = ctx.image(p)
            if rgb is None:
                continue
            s, frac = eval_horizon_closed(rgb, t, [])
            worst12 = worse(worst12, s)
            details12.append({"file": p.name, "void_fraction": frac})

            sky_mask = sky_region_mask(rgb, t)
            if not sky_mask.any():
                # Vue sans ciel visible (ex. "top", nadir pur) : hors
                # périmètre de CHK-13, pas de fausse alerte.
                continue
            sky_rows = np.where(sky_mask.any(axis=1))[0]
            bounds = (int(sky_rows.min()), int(sky_rows.max()) + 1)
            comps = find_cloud_components(rgb, t, row_bounds=bounds)
            s13, d13 = eval_cloud_masses(comps, rgb.shape[:2], t, sky_row_bounds=bounds)
            any13measured = True
            worst13 = worse(worst13, s13)
            details13.append({"file": p.name, **d13})
        out["CHK-12"] = Finding(worst12, f"{len(aerial_shots)} vue(s) aérienne(s)", data={"per_file": details12})
        out["CHK-13"] = Finding(
            worst13 if any13measured else "WARN",
            f"{len(details13)} vue(s) avec ciel détecté" if any13measured else "aucune vue aérienne avec ciel détecté (vues nadir uniquement, ou palette hors enveloppe world.value_structure.sky_*)",
            measured=any13measured, data={"per_file": details13},
        )

    # ---- CHK-14..17 : décor / scène ----------------------------------------
    out["CHK-14"] = Finding.unmeasured("repères visibles depuis une grille : raycasts (ART-23 à ART-26) pas encore livrés")
    out["CHK-15"] = Finding.unmeasured("hauteurs de couvert : nécessite la géométrie réelle des props (check_asset.py / PropCatalog n'expose pas les dimensions)")
    out["CHK-16"] = Finding.unmeasured("props flottants : scan de scène (check_asset.py CHK-16 le fait sur l'asset isolé, pas en placement carte)")
    out["CHK-17"] = Finding.unmeasured("props humanoïdes parasites : scan de scène non implémenté")

    # ---- CHK-18, CHK-20, CHK-22 : échantillons de bord (char_ingame_shots + style_masks) ----
    sm = ctx.style_masks_json()
    edge_samples_path = (ctx.char_ingame_dir() / "enemy_edge_samples.json") if ctx.char_ingame_dir() else None
    edge_samples = Context._load_json(edge_samples_path) if edge_samples_path else None
    ink_rgb = hex_to_rgb01(t["color"]["ink"]["hex"])
    if edge_samples and edge_samples.get("samples"):
        s18, d18 = eval_enemy_contrast_samples(edge_samples["samples"], t, ink_rgb)
        out["CHK-18"] = Finding(s18, json.dumps(d18)[:300], data=d18)
    else:
        out["CHK-18"] = Finding.unmeasured("échantillons de bord (ennemi × 3 fonds × 4 distances) absents — char_ingame_shots ne les fournit pas encore")
    out["CHK-20"] = Finding.unmeasured("largeur de contour ennemi à 40 m : nécessite les échantillons de bord ci-dessus")
    out["CHK-22"] = Finding.unmeasured("taille en pixels à distance connue : nécessite les échantillons de bord ci-dessus (indicatif, non bloquant)")

    # ---- CHK-19 : simulation daltonisme (toujours mesurable depuis les jetons) ----
    s19, d19 = eval_cvd_recommendation(t)
    out["CHK-19"] = Finding(s19, json.dumps(d19)[:300], data=d19)

    # ---- CHK-23..25 : gabarit / budgets personnage (check_asset.py) -------
    for chk in ("CHK-23", "CHK-24", "CHK-25"):
        out[chk] = Finding.unmeasured("mesure sur le GLB : tools/blender/check_asset.py (ART-10), pas de sortie JSON dans ce run")

    # ---- CHK-26 : couleurs d'agent (toujours mesurable depuis les jetons) --
    s26, d26 = lint_agent_key_colors(t)
    out["CHK-26"] = Finding(s26, json.dumps(d26)[:300], data=d26)

    # ---- CHK-27 : shading personnage (lint shader) -------------------------
    s27, d27 = lint_shader_defaults(ctx.repo_root, t)
    measured27 = "reason" not in d27
    out["CHK-27"] = Finding(s27 if measured27 else "WARN", str(d27.get("reason") or d27.get("violations")), measured=measured27, data=d27)

    # ---- CHK-28..30 : viewmodel à la hanche (fp_shots.json + masques) ------
    resolve_fp_shots(ctx, out)

    # ---- CHK-31 : armes distinctes (viewmodel_shots.gd) --------------------
    out["CHK-31"] = Finding.unmeasured("IoU de silhouettes d'armes : tools/blender/viewmodel_shots.gd ne produit pas de masques/JSON")

    # ---- CHK-32..41 : interface (ui_shots) ---------------------------------
    resolve_ui_shots(ctx, out)

    # ---- CHK-42..45 : VFX -----------------------------------------------
    out["CHK-42"] = Finding.unmeasured("flash de bouche en rafale : capture dédiée non produite par fp_shots.gd")
    out["CHK-43"] = Finding.unmeasured("opacité de fumée : sonde de capacités non implémentée")
    out["CHK-44"] = Finding.unmeasured("anneau d'équipe visible : gameplay_probe ne capture pas d'image")
    out["CHK-45"] = Finding.unmeasured("zéro sang : lint des effets non implémenté (risque de faux positifs sur les teintes peau/cuir légitimes, écarté volontairement — voir le contrat)")

    # ---- CHK-46, CHK-47 : perf/mémoire (perf_bench.json) -------------------
    resolve_perf(ctx, out)

    return out


def resolve_fp_shots(ctx: Context, out: dict[str, Finding]) -> None:
    t = ctx.tokens
    data = ctx.fp_shots_json()
    fp_dir = ctx.fp_dir()
    if not data or not fp_dir:
        for chk in ("CHK-28", "CHK-29", "CHK-30"):
            out[chk] = Finding.unmeasured("fp_shots.json absent (viewmodel_fp/fp/ — étape viewmodel_fp_shots non lancée)")
        return

    cfg28 = chk_cfg(t, "CHK-28")
    cfg29 = chk_cfg(t, "CHK-29")
    cfg30 = chk_cfg(t, "CHK-30")
    coverage_by_cat = t.get("viewmodel", {}).get("coverage_hip", {})
    cat_labels = ["sidearm", "smg", "rifle", "shotgun", "sniper", "heavy"]
    center_frac = cfg28.get("center_zone", 0.20)
    muzzle_x_range = cfg30.get("muzzle_hip", {}).get("x") if isinstance(cfg30.get("muzzle_hip"), dict) else t.get("viewmodel", {}).get("muzzle_hip", {}).get("x", [0.58, 0.64])
    muzzle_y_range = t.get("viewmodel", {}).get("muzzle_hip", {}).get("y", [0.56, 0.64])

    st28, st29, st30 = "PASS", "PASS", "PASS"
    n28 = n29 = n30 = 0
    details = []
    for w in data.get("weapons", []):
        if not w.get("model_found"):
            continue
        name = w.get("name")
        mask_path = fp_dir / f"{name}_mask.png"
        mask = load_mask_bool(mask_path)
        if mask is None:
            continue
        h, w_px = mask.shape
        half = center_frac / 2.0
        x0, x1 = int((0.5 - half) * w_px), int((0.5 + half) * w_px)
        y0, y1 = int((0.5 - half) * h), int((0.5 + half) * h)
        center_nonblack = int(mask[y0:y1, x0:x1].sum())
        coverage = float(mask.sum()) / (h * w_px) * 100.0
        n28 += 1
        chk28_ok = center_nonblack == 0
        if not chk28_ok:
            st28 = "FAIL"
        cat = w.get("category")
        label = cat_labels[cat] if isinstance(cat, int) and 0 <= cat < len(cat_labels) else None
        lo_hi = coverage_by_cat.get(label) if label else None
        if lo_hi:
            n29 += 1
            # coverage_hip (tokens.json) est une fraction 0-1 ; `coverage` est en %.
            if not (lo_hi[0] <= coverage / 100.0 <= lo_hi[1]):
                st29 = "FAIL"
        muzzle = w.get("muzzle_screen")
        if muzzle and len(muzzle) == 2:
            n30 += 1
            mx, my = muzzle
            if not (muzzle_x_range[0] <= mx <= muzzle_x_range[1] and muzzle_y_range[0] <= my <= muzzle_y_range[1]):
                st30 = "WARN"
        details.append({"name": name, "coverage_pct": coverage, "center_nonblack_px": center_nonblack})

    out["CHK-28"] = Finding(st28 if n28 else "WARN", f"{n28} arme(s) évaluée(s)" if n28 else "aucun masque exploitable", measured=n28 > 0, data={"weapons": details[:20]})
    out["CHK-29"] = Finding(st29 if n29 else "WARN", f"{n29} arme(s) avec catégorie connue" if n29 else "aucune catégorie exploitable", measured=n29 > 0)
    out["CHK-30"] = Finding(st30 if n30 else "WARN", f"{n30} arme(s) avec canon localisé" if n30 else "aucune position de canon", measured=n30 > 0)


def resolve_ui_shots(ctx: Context, out: dict[str, Finding]) -> None:
    t = ctx.tokens

    # CHK-37 (états de thème), CHK-38 (géométrie Comic.gd), CHK-39 (polices
    # référencées) et CHK-41 (durées de tween) sont des lints STATIQUES de
    # scripts/ressources du dépôt — indépendants des captures ui_shots, donc
    # calculés INCONDITIONNELLEMENT (jamais gagnés par le retour anticipé
    # ci-dessous quand ui_shots/ est absent, ex. -Quick).
    s41, d41 = lint_tween_durations(ctx.repo_root, t)
    measured41 = "reason" not in d41
    out["CHK-41"] = Finding(s41 if measured41 else "WARN", str(d41.get("reason") or f"{d41.get('count')} tween(s), {len(d41.get('aberrant', []))} aberrant(s)"), measured=measured41, data=d41)

    s39, d39 = lint_fonts(ctx.repo_root, t)
    out["CHK-39"] = Finding(s39, json.dumps(d39)[:300] if "reason" not in d39 else d39["reason"], measured="reason" not in d39, data=d39)

    s38, d38 = lint_geometry(ctx.repo_root, t)
    measured38 = "reason" not in d38
    out["CHK-38"] = Finding(s38 if measured38 else "WARN", str(d38.get("reason") or d38.get("violations") or "inclinaison et ombres dures conformes"), measured=measured38, data=d38)

    # CHK-37 (volet « styles ») : lint statique de resources/ui/ui_theme.tres,
    # lui aussi indépendant d'ui_shots (voir CHK-38/39/41 ci-dessus).
    s37, d37 = lint_theme_states(ctx.repo_root, t)
    measured37 = "reason" not in d37
    out["CHK-37"] = Finding(
        s37 if measured37 else "WARN",
        str(d37.get("reason") or d37.get("violations") or "tous les contrôles interactifs couvrent hover/focus/pressed/disabled"),
        measured=measured37, data=d37,
    )

    d = ctx.ui_shots_dir()
    if d is None:
        for chk in ("CHK-32", "CHK-33", "CHK-34", "CHK-35", "CHK-36", "CHK-40"):
            out[chk] = Finding.unmeasured("ui_shots/ absent (étape ui_shots non lancée ou -Quick)")
        return

    # Texte réel : « papier » (primaire, texte clair sur fond charbon sombre —
    # tokens.json `color.papier.text.role` = "primary text...") ET « encre »
    # (secondaire, "text on light fills" — un autocollant/fond clair). Ne
    # scanner QUE l'encre (comme avant) rate la quasi-totalité du texte réel
    # de cette UI v3 sombre, qui est en clair sur fond sombre. La détection de
    # l'encre garde une tolérance LARGE (couvre son halo anticrénelé, posé sur
    # un fond clair très différent) et exclut ÉTROITEMENT les aplats charbon
    # confusables via `exclude_rgbs`/`exclude_tol` (voir la docstring de
    # `find_glyph_components`, fix ART-31 sur la régression du fix ART-30).
    ink_rgb = hex_to_rgb01(t["color"]["ink"]["hex"])
    papier_rgb = hex_to_rgb01(t["color"]["papier"]["text"]["hex"])
    papier_dim_rgb = hex_to_rgb01(t["color"]["papier"]["dim"]["hex"])
    # Rayon d'EXCLUSION étroit (pas d'inclusion, voir `find_glyph_components`
    # ci-dessus) : protège des aplats `charbon` confusables sans rétrécir la
    # tolérance d'inclusion elle-même (fix ART-31). Retour du vérificateur
    # (tâche OPS-13) : appliqué UNIQUEMENT à `ink` jusqu'ici — `papier`/
    # `papier_dim` (texte clair sur fond charbon, exactement le cas visé par
    # le critère d'acceptation) gardaient `tol=0.16` par défaut SANS AUCUNE
    # exclusion, aussi exposés que `ink` l'était avant le fix ART-31 à un
    # aplat charbon confusable classé « glyphe ». On calcule le rayon
    # d'exclusion et la liste de voisins PROPRES À CHAQUE couleur cible (pas
    # une seule tolérance partagée) via `safe_color_tolerance` : la distance
    # ink<->charbon (~0.03-0.11) n'a rien à voir avec papier<->charbon
    # (~0.8-1.5 dans cette palette), un seuil unique serait soit trop large
    # pour l'un, soit sans effet pour l'autre.
    charbon_neighbors = [
        hex_to_rgb01(t["color"]["charbon"][k]["hex"])
        for k in ("bg", "panel", "panel_hi")
        if k in t.get("color", {}).get("charbon", {})
    ]
    ink_exclude_tol = safe_color_tolerance(ink_rgb, charbon_neighbors)
    papier_exclude_tol = safe_color_tolerance(papier_rgb, charbon_neighbors)
    papier_dim_exclude_tol = safe_color_tolerance(papier_dim_rgb, charbon_neighbors)

    agent_keys = {agent_id: hex_to_rgb01(agent["key"]) for agent_id, agent in t.get("agents", {}).items() if "key" in agent}
    universal_ref_colors = non_agent_reference_colors(t)

    heights_by_res: dict[str, list[float]] = {"1080": [], "720": []}
    contrast_pairs: list[tuple] = []
    leaking_agents: set[str] = set()
    checked_files = 0
    for p in sorted(d.glob("*.png")):
        m = re.search(r"_(\d+)x(\d+)$", p.stem)
        if not m:
            continue
        w_px, h_px = int(m.group(1)), int(m.group(2))
        res_key = "1080" if h_px >= 1000 else "720"
        rgb = ctx.image(p)
        if rgb is None:
            continue
        checked_files += 1
        comps = (
            find_glyph_components(rgb, ink_rgb, exclude_rgbs=charbon_neighbors, exclude_tol=ink_exclude_tol)
            + find_glyph_components(rgb, papier_rgb, exclude_rgbs=charbon_neighbors, exclude_tol=papier_exclude_tol)
            + find_glyph_components(rgb, papier_dim_rgb, exclude_rgbs=charbon_neighbors, exclude_tol=papier_dim_exclude_tol)
        )
        for comp in comps:
            heights_by_res[res_key].append(comp["height_px"])
            y0, y1, x0, x1 = comp["bbox"]
            pad = max(3, (y1 - y0))
            bg = ring_background_rgb(rgb, comp["bbox"], pad)
            if bg is None:
                continue
            fg = tuple(rgb[y0:y1, x0:x1].reshape(-1, 3).mean(axis=0).tolist())
            contrast_pairs.append((fg, bg))
        for agent_id, key_rgb in agent_keys.items():
            other_refs = [v for aid, v in agent_keys.items() if aid != agent_id] + universal_ref_colors
            leak_mask = agent_key_leak_mask(rgb, key_rgb, other_refs)
            if leak_mask.mean() > 0.001:
                leaking_agents.add(agent_id)

    if checked_files == 0:
        for chk in ("CHK-32", "CHK-33", "CHK-40"):
            out[chk] = Finding.unmeasured("aucune capture ui_shots exploitable (nom de fichier inattendu ou image illisible)")
    else:
        s32, d32 = eval_glyph_heights(heights_by_res, t)
        out["CHK-32"] = Finding(s32, json.dumps(d32)[:300], measured="reason" not in d32, data=d32)

        cfg33 = chk_cfg(t, "CHK-33")
        s33, d33 = eval_min_contrast_pairs(
            contrast_pairs, cfg33.get("min_contrast", 4.5), pass_fraction=cfg33.get("pass_fraction", 0.95),
        )
        out["CHK-33"] = Finding(
            s33 if contrast_pairs else "WARN",
            (
                f"pire contraste texte/fond mesuré = {d33['worst_contrast']:.2f} "
                f"({d33['pass_fraction'] * 100:.1f}% des {d33['pairs']} paire(s) >= seuil)"
            ) if contrast_pairs else "aucun glyphe détecté",
            measured=bool(contrast_pairs), data=d33,
        )

        out["CHK-40"] = Finding(
            "FAIL" if leaking_agents else "PASS",
            f"couleur(s) d'agent détectée(s) dans le HUD, non expliquée(s) par un jeton universel : {sorted(leaking_agents)}" if leaking_agents else f"{checked_files} capture(s), aucune couleur d'agent détectée",
            data={"leaking_agents": sorted(leaking_agents)},
        )

    out["CHK-34"] = Finding.unmeasured("marges de sécurité : nécessite le masque HUD par rectangle (style_masks.gd) apparié à chaque écran ui_shots — pas encore recoupé")
    out["CHK-35"] = Finding.unmeasured("zone centrale hud_center : le groupe de nœuds \"hud_center\" n'existe pas encore dans le code UI")
    out["CHK-36"] = Finding.unmeasured("discipline du pinceau : nécessite un parcours de l'arbre de nœuds, pas seulement les pixels")
    # CHK-37 : voir le calcul inconditionnel en tête de fonction (lint de
    # resources/ui/ui_theme.tres, indépendant d'ui_shots) — jamais recalculé
    # ici.
    # CHK-38/CHK-39/CHK-41 : voir le calcul inconditionnel en tête de
    # fonction — jamais recalculés ici (ne dépendent pas d'ui_shots).


def resolve_perf(ctx: Context, out: dict[str, Finding]) -> None:
    t = ctx.tokens
    perf = ctx.perf_bench_json()
    if not perf or not perf.get("maps"):
        out["CHK-46"] = Finding.unmeasured("perf_bench/perf.json absent (étape perf_bench non lancée ou -Quick)")
        out["CHK-47"] = Finding.unmeasured("perf_bench/perf.json absent")
        return
    cfg46 = chk_cfg(t, "CHK-46")
    status46 = "PASS"
    for m in perf["maps"]:
        if m.get("avg_fps", 0) < cfg46.get("fps_avg_min", 144):
            status46 = worse(status46, "FAIL")
        if m.get("low_1pct_fps", 0) < cfg46.get("fps_1pct_low_min", 100):
            status46 = worse(status46, "FAIL")
        if m.get("draw_calls_avg", 0) > cfg46.get("draw_calls_max", 1500):
            status46 = worse(status46, "FAIL")
        if m.get("primitives_avg", 0) > cfg46.get("tris_max", 2_500_000):
            status46 = worse(status46, "FAIL")
    out["CHK-46"] = Finding(status46, f"{len(perf['maps'])} carte(s) évaluée(s)", data={"maps": perf["maps"]})

    cfg47 = chk_cfg(t, "CHK-47")
    vram_values = [m.get("video_mem_mb") for m in perf["maps"] if m.get("video_mem_mb") is not None and m.get("video_mem_mb") >= 0]
    if not vram_values:
        out["CHK-47"] = Finding.unmeasured("moniteur mémoire vidéo indisponible dans ce build (video_mem_mb=-1) ; pool de décalques non mesuré")
    else:
        status47 = "PASS" if max(vram_values) <= cfg47.get("texture_vram_mb_max", 256) else "FAIL"
        out["CHK-47"] = Finding(status47, f"max VRAM texture ≈ {max(vram_values):.0f} Mo (pool de décalques non mesuré)")


# =============================================================================
#  Assemblage du rapport
# =============================================================================

def build_report(run_dir: Path | None, tokens_path: Path) -> dict:
    tokens = load_tokens(tokens_path)
    ctx = Context(run_dir, tokens, REPO_ROOT)
    findings = resolve_all(ctx)

    checks_out = {}
    warn_count = 0
    blocking_fail_count = 0
    pass_count = 0
    for chk_id in ALL_CHECK_IDS:
        f = findings.get(chk_id) or Finding.unmeasured("contrôle non implémenté")
        blocking = is_blocking(tokens, chk_id)
        checks_out[chk_id] = {
            "status": f.status, "detail": f.detail, "blocking": blocking, "measured": f.measured,
        }
        if f.status == "PASS":
            pass_count += 1
        elif f.status == "WARN":
            warn_count += 1
        elif f.status == "FAIL" and blocking:
            blocking_fail_count += 1

    total = len(ALL_CHECK_IDS)
    release = tokens.get("checks", {}).get("release_rule", {})
    gate = "PASS"
    if blocking_fail_count > release.get("blocking_fail_max", 0):
        gate = "FAIL"
    elif warn_count > release.get("warn_max", 3):
        gate = "WARN"

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "tokens_version": tokens.get("meta", {}).get("version"),
        "run_dir": str(run_dir) if run_dir else None,
        "checks": checks_out,
        "score": {"pass": pass_count, "total": total, "text": f"{pass_count}/{total}", "fraction": pass_count / total},
        "warn_count": warn_count,
        "blocking_fail_count": blocking_fail_count,
        "gate": gate,
    }


# =============================================================================
#  Auto-test (images de synthèse) — commande de vérification du contrat ART-03
# =============================================================================

def _assert(cond: bool, msg: str) -> None:
    if not cond:
        raise AssertionError(msg)


def _make_image(w: int, h: int, bg_rgb01: tuple[float, float, float]) -> np.ndarray:
    arr = np.empty((h, w, 3), dtype=np.float64)
    arr[..., 0], arr[..., 1], arr[..., 2] = bg_rgb01
    return arr


def _paint_rect(arr: np.ndarray, rgb01: tuple[float, float, float], rect: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = rect
    arr[y0:y1, x0:x1] = rgb01


def self_test() -> bool:
    tokens = load_tokens(DEFAULT_TOKENS_PATH)
    failures: list[str] = []

    def check(name: str, cond: bool, extra: str = ""):
        if cond:
            print(f"  ok   {name}")
        else:
            print(f"  FAIL {name} {extra}")
            failures.append(name)

    # ---- CHK-02 : pas de boue -----------------------------------------
    cfg02 = chk_cfg(tokens, "CHK-02")
    bg = (0.75, 0.60, 0.40)          # aplat propre, hors bande boue
    mud = (0.18, 0.17, 0.16)        # gris-brun terne, OKLab L≈0.29, plein dans [0.25,0.33)
    img_pass = _make_image(100, 100, bg)
    _paint_rect(img_pass, mud, (0, 0, 20, 100))   # 20% de boue -> sous 5%? non : 20% > 5% -> doit FAIL
    included = np.ones((100, 100), dtype=bool)
    status, frac, _, _ = eval_pixel_fraction_range(img_pass, included, tuple(cfg02["mud_L"]), frac_max=cfg02["max_fraction"])
    check("CHK-02 détecte une boue excessive (FAIL attendu)", status == "FAIL", f"frac={frac}")

    img_clean = _make_image(100, 100, bg)
    _paint_rect(img_clean, mud, (0, 0, 3, 100))    # 3% de boue -> sous 5% -> PASS
    status2, frac2, _, _ = eval_pixel_fraction_range(img_clean, included, tuple(cfg02["mud_L"]), frac_max=cfg02["max_fraction"])
    check("CHK-02 accepte une trace de boue sous le seuil (PASS attendu)", status2 == "PASS", f"frac={frac2}")

    # ---- CHK-06 : teintes réservées -------------------------------------
    clean_decor = (0.70, 0.45, 0.30)  # orange chaud, hors bandes réservées
    reserved_magenta = hex_to_rgb01(tokens["reserved"]["enemy_highlight"]["magenta"]["hex"])
    img_leak = _make_image(100, 100, clean_decor)
    _paint_rect(img_leak, reserved_magenta, (40, 40, 60, 60))  # 4% -> largement > 0.1%
    status6, frac6 = eval_reserved_hue_fraction(img_leak, included, tokens)
    check("CHK-06 détecte une fuite de teinte réservée (FAIL attendu)", status6 == "FAIL", f"frac={frac6}")

    img_ok = _make_image(100, 100, clean_decor)
    status6b, frac6b = eval_reserved_hue_fraction(img_ok, included, tokens)
    check("CHK-06 accepte un décor sans teinte réservée (PASS attendu)", status6b == "PASS", f"frac={frac6b}")

    # ---- CHK-18 : contraste ennemi (échantillons) -----------------------
    ink_rgb = hex_to_rgb01(tokens["color"]["ink"]["hex"])
    magenta = reserved_magenta
    good_samples = [
        {"distance_m": d, "highlight_rgb": magenta, "background_rgbs": [(0.5, 0.5, 0.5), (0.3, 0.6, 0.3), (0.6, 0.4, 0.2)]}
        for d in (10, 20, 30, 40)
    ]
    s18, d18 = eval_enemy_contrast_samples(good_samples, tokens, ink_rgb)
    check("CHK-18 accepte des fonds bien contrastés (PASS attendu)", s18 == "PASS", str(d18))

    bad_samples = [
        {"distance_m": d, "highlight_rgb": magenta, "background_rgbs": [magenta, magenta, magenta]}
        for d in (10, 20, 30, 40)
    ]
    s18b, d18b = eval_enemy_contrast_samples(bad_samples, tokens, ink_rgb)
    check("CHK-18 rejette un fond quasi identique à la surbrillance (FAIL attendu)", s18b == "FAIL", str(d18b))

    # ---- CHK-32 : taille de texte, sur une VRAIE image de synthèse -------
    if HAS_PIL and HAS_SCIPY:
        papier = hex_to_rgb01(tokens["color"]["papier"]["text"]["hex"])
        w, h = 400, 200
        canvas = _make_image(w, h, papier)
        # 3 "glyphes" (rectangles pleine encre) de hauteurs connues, assez
        # espacés pour rester des composantes connexes séparées, assez
        # étroits pour ne pas être filtrés comme un bandeau.
        heights_px = [25, 30, 22]
        x = 20
        for hh in heights_px:
            _paint_rect(canvas, ink_rgb, (x, 20, x + 10, 20 + hh))
            x += 40
        comps = find_glyph_components(canvas, ink_rgb)
        found_heights = sorted(c["height_px"] for c in comps)
        check(
            "CHK-32 mesure la hauteur des glyphes sur une image de synthèse",
            found_heights == sorted(float(v) for v in heights_px),
            f"trouvé={found_heights} attendu={sorted(heights_px)}",
        )
        s32, d32 = eval_glyph_heights({"1080": found_heights, "720": []}, tokens)
        check("CHK-32 : PASS quand tous les glyphes dépassent le seuil 1080p (21px)", s32 == "PASS", str(d32))

        canvas_small = _make_image(w, h, papier)
        _paint_rect(canvas_small, ink_rgb, (20, 20, 30, 20 + 12))  # 12px < 21px
        comps_small = find_glyph_components(canvas_small, ink_rgb)
        s32b, d32b = eval_glyph_heights({"1080": [c["height_px"] for c in comps_small], "720": []}, tokens)
        check("CHK-32 : FAIL quand un glyphe est sous le seuil 1080p", s32b == "FAIL", str(d32b))

        # ---- Retour QA ART-30 24/09 16h04 : régressions ------------------
        # (1) `safe_ink_tolerance` : un fond `charbon.panel_hi` ne doit plus
        # se classer comme « encre » — sans ce garde-fou, tol=0.16 confond
        # les deux (distance ~0.113) et CHK-32/33 mesurent le FOND, pas du
        # texte (`min_height_px_1080=2.0`, contraste=1.00 sur le run réel).
        panel_hi = hex_to_rgb01(tokens["color"]["charbon"]["panel_hi"]["hex"])
        canvas_bg = _make_image(60, 60, papier)
        _paint_rect(canvas_bg, panel_hi, (20, 20, 30, 40))  # petit aplat de FOND, pas de texte
        ink_tol = safe_ink_tolerance(tokens)
        comps_bg = find_glyph_components(canvas_bg, ink_rgb, tol=ink_tol)
        check(
            "safe_ink_tolerance : un aplat panel_hi n'est plus classé comme de l'encre",
            len(comps_bg) == 0,
            f"tol={ink_tol} composantes={comps_bg}",
        )
        old_tol_comps = find_glyph_components(canvas_bg, ink_rgb, tol=0.16)
        check(
            "safe_ink_tolerance : documente bien le bug (tol=0.16 le confondait)",
            len(old_tol_comps) > 0,
            f"composantes={old_tol_comps}",
        )

        # (2) `ring_background_rgb` : deux glyphes ENCRE collés l'un à
        # l'autre sur fond papier ne doivent pas se mesurer l'un l'autre
        # comme « fond » (contraste ~1.0, faux FAIL) — le fond réel (papier)
        # doit rester détecté malgré la proximité.
        canvas_pair = _make_image(80, 40, papier)
        _paint_rect(canvas_pair, ink_rgb, (10, 10, 18, 30))
        _paint_rect(canvas_pair, ink_rgb, (20, 10, 28, 30))  # collé à 2px du premier
        comps_pair = find_glyph_components(canvas_pair, ink_rgb)
        check("ring_background_rgb : les 2 glyphes collés restent 2 composantes", len(comps_pair) == 2, str(comps_pair))
        worst_pair_contrast = math.inf
        for comp in comps_pair:
            bg_ring = ring_background_rgb(canvas_pair, comp["bbox"], max(3, comp["bbox"][1] - comp["bbox"][0]))
            check(f"ring_background_rgb : fond mesurable autour de {comp['bbox']}", bg_ring is not None)
            if bg_ring is not None:
                fg = tuple(canvas_pair[comp["bbox"][0]:comp["bbox"][1], comp["bbox"][2]:comp["bbox"][3]].reshape(-1, 3).mean(axis=0).tolist())
                worst_pair_contrast = min(worst_pair_contrast, wcag_contrast(fg, bg_ring))
        check(
            "ring_background_rgb : contraste réel (papier/encre) retrouvé, pas ~1.0 (glyphe contre lui-même)",
            worst_pair_contrast > 4.5,
            f"worst={worst_pair_contrast}",
        )

        # ---- Retour QA ART-31 24/09 : régression du fix ART-30 -----------
        # `safe_ink_tolerance` protège du fond MAIS coupe aussi le halo
        # anticrénelé d'un vrai glyphe (posé sur `papier`, ΔE ~1.46 — un
        # pixel à 92 % de couverture d'encre est déjà à ~0.117 de l'encre
        # pure, largement hors de la sphère étroite ~0.013). Glyphe
        # synthétique « persiennes » : 30 lignes, motif [encre pure, encre
        # pure, mélange à 92 %] répété 10 fois — sous l'ANCIEN tol unique
        # étroit, seules les paires de lignes pures passent (les lignes de
        # mélange, elles, non), fragmentant le glyphe en composantes de 2 px
        # exactement le symptôme rapporté (CHK-32 mesure 2 px, CHK-33 un
        # contraste de 1,00 — le "fond" mesuré autour d'un fragment de 2 px
        # est en réalité le RESTE DU MÊME GLYPHE).
        # frac=0.05 : assez loin de l'encre pure pour échouer sous l'ANCIEN
        # tol étroit (~0.013), mais aussi assez loin des trois neutres
        # charbon (>= 0.036, marge confirmée empiriquement) pour ne PAS se
        # faire retrancher par `exclude_tol` sous le fix — un choix naïf
        # (ex. 8 %) atterrit par coïncidence à ~0.006 de `charbon.panel_hi`.
        blend92 = tuple((0.95 * np.array(ink_rgb) + 0.05 * np.array(papier)).tolist())
        canvas_aa = _make_image(60, 80, papier)
        glyph_x0, glyph_x1, glyph_y0 = 20, 30, 10
        for cycle in range(10):
            base = glyph_y0 + cycle * 3
            _paint_rect(canvas_aa, ink_rgb, (glyph_x0, base, glyph_x1, base + 2))
            _paint_rect(canvas_aa, blend92, (glyph_x0, base + 2, glyph_x1, base + 3))
        old_tol = safe_ink_tolerance(tokens)
        comps_old = find_glyph_components(canvas_aa, ink_rgb, tol=old_tol)
        check(
            "ART-31 : reproduit la fragmentation (tol unique étroit -> composantes de 2 px, jamais 30)",
            len(comps_old) > 1 and all(c["height_px"] < 5 for c in comps_old),
            f"composantes={comps_old}",
        )
        charbon_neighbors = [
            hex_to_rgb01(tokens["color"]["charbon"][k]["hex"]) for k in ("bg", "panel", "panel_hi")
        ]
        comps_fixed = find_glyph_components(
            canvas_aa, ink_rgb, tol=0.16, exclude_rgbs=charbon_neighbors, exclude_tol=old_tol,
        )
        check(
            "ART-31 : corrigé (tol large + exclude_rgbs/exclude_tol) -> UNE seule composante de hauteur plausible",
            len(comps_fixed) == 1 and comps_fixed[0]["height_px"] >= 29,
            f"composantes={comps_fixed}",
        )
        if len(comps_fixed) == 1:
            bg_fixed = ring_background_rgb(canvas_aa, comps_fixed[0]["bbox"], pad=6)
            fg_fixed = tuple(
                canvas_aa[comps_fixed[0]["bbox"][0]:comps_fixed[0]["bbox"][1], comps_fixed[0]["bbox"][2]:comps_fixed[0]["bbox"][3]]
                .reshape(-1, 3).mean(axis=0).tolist()
            )
            contrast_fixed = wcag_contrast(fg_fixed, bg_fixed) if bg_fixed is not None else 0.0
            check(
                "ART-31 : contraste corrigé plausible (pas ~1,00 — texte contre lui-même)",
                contrast_fixed >= 7.0,
                f"contraste={contrast_fixed}",
            )
        # La correction ne doit PAS réintroduire le bug ART-30 d'origine :
        # un aplat de fond charbon (aucun texte) reste exclu même avec `tol`
        # large, grâce à `exclude_rgbs`/`exclude_tol`.
        comps_bg_fixed = find_glyph_components(
            canvas_bg, ink_rgb, tol=0.16, exclude_rgbs=charbon_neighbors, exclude_tol=old_tol,
        )
        check(
            "ART-31 : ne réintroduit pas ART-30 (aplat panel_hi toujours exclu avec tol large + exclude_rgbs)",
            len(comps_bg_fixed) == 0,
            f"composantes={comps_bg_fixed}",
        )

        # ---- Retour du vérificateur (tâche OPS-13, 24/09) : le fix ART-31
        # (exclude_rgbs/exclude_tol) n'était appliqué QU'À l'appel `ink` dans
        # `resolve_ui_shots` ; `papier`/`papier_dim` (texte clair sur fond
        # charbon, exactement le cas visé par le critère d'acceptation)
        # gardaient tol=0.16 SANS AUCUNE exclusion. Dans CETTE palette,
        # `papier`/`papier_dim` sont trop loin de `charbon` (>= 0.8) pour
        # qu'un fond charbon réel les confonde jamais — `safe_color_tolerance`
        # y retombe donc sur `default` (0.16), sans le rétrécir. La
        # généralisation se vérifie avec un voisin SYNTHÉTIQUE délibérément
        # proche (comme `charbon.panel_hi` l'est de `ink` dans la palette
        # réelle) : `safe_color_tolerance` doit alors resserrer le rayon
        # d'exclusion pour N'IMPORTE QUELLE couleur cible, pas seulement
        # `ink`. -------------------------------------------------------
        dim = hex_to_rgb01(tokens["color"]["papier"]["dim"]["hex"])
        for label, target in (("papier", papier), ("papier_dim", dim)):
            close_neighbor = tuple((0.9 * np.array(target) + 0.1 * np.array(ink_rgb)).tolist())  # à ~0.1x|target-ink| de target
            tol_generic = safe_color_tolerance(target, [close_neighbor])
            check(
                f"safe_color_tolerance({label}) resserre le rayon face à un voisin synthétique proche, comme safe_ink_tolerance(ink)",
                0.0 < tol_generic < 0.16,
                f"tol={tol_generic}",
            )
            # Fond = `ink` (loin de `papier`/`papier_dim`, >= 1.0 dans cette
            # palette) : le fond lui-même ne doit JAMAIS matcher `target`,
            # sans quoi le rectangle fusionnerait avec tout le canvas et
            # serait filtré par `max_width_frac`/`max_height_frac` (bandeau),
            # ce qui ne testerait rien sur l'exclusion elle-même.
            canvas_confusable = _make_image(60, 60, ink_rgb)
            _paint_rect(canvas_confusable, close_neighbor, (20, 20, 30, 40))
            naive = find_glyph_components(canvas_confusable, target, tol=0.16)
            check(
                f"OPS-13 : sans exclusion, un aplat synthétique proche se classe comme « {label} » (documente le trou avant fix)",
                len(naive) > 0,
                f"composantes sans exclusion={naive}",
            )
            fixed = find_glyph_components(
                canvas_confusable, target, tol=0.16, exclude_rgbs=[close_neighbor], exclude_tol=tol_generic,
            )
            check(
                f"OPS-13 : avec exclude_rgbs/exclude_tol (safe_color_tolerance), l'aplat confusable n'est plus classé « {label} »",
                len(fixed) == 0,
                f"composantes={fixed}",
            )

        # ---- Vérification de la CÂBLAGE : `resolve_ui_shots` doit bien
        # transmettre exclude_rgbs/exclude_tol aux TROIS appels (ink, papier,
        # papier_dim), pas seulement à `ink` — reproduit le trou signalé par
        # le vérificateur avec un tokens.json où `charbon.panel_hi` a été
        # rapproché de `papier.dim` (scénario impossible dans la palette
        # réelle actuelle, mais qui DOIT rester protégé si la palette change).
        tokens_confusable = json.loads(json.dumps(tokens))  # copie profonde
        tokens_confusable["color"]["charbon"]["panel_hi"]["hex"] = "#" + "".join(f"{int(round(c * 255)):02x}" for c in close_neighbor)
        with tempfile.TemporaryDirectory(prefix="style_check_ops13_") as tmp_ui:
            ui_dir = Path(tmp_ui) / "ui_shots"
            ui_dir.mkdir()
            canvas_hud = _make_image(120, 100, papier)
            _paint_rect(canvas_hud, hex_to_rgb01(tokens_confusable["color"]["charbon"]["panel_hi"]["hex"]), (40, 40, 60, 70))
            Image.fromarray((np.clip(canvas_hud, 0, 1) * 255).astype(np.uint8)).save(ui_dir / "hud_120x100.png")
            ctx_confusable = Context(Path(tmp_ui), tokens_confusable, REPO_ROOT)
            out_confusable: dict[str, Finding] = {}
            resolve_ui_shots(ctx_confusable, out_confusable)
            check(
                "OPS-13 : resolve_ui_shots applique bien l'exclusion à papier_dim aussi (aplat panel_hi confusable non mesuré comme glyphe)",
                "reason" in out_confusable["CHK-32"].data,
                f"CHK-32={out_confusable['CHK-32']}",
            )

        # ---- Retour du vérificateur (tâche OPS-13, 24/09) : agrégation
        # CHK-32/33 robuste à une MINORITÉ de composantes parasites --------
        # `eval_glyph_heights`/`eval_min_contrast_pairs` agrégeaient par un
        # strict min() sur TOUTES les composantes de TOUTES les captures :
        # une seule composante parasite de 2 px (bord anticrénelé, glitch —
        # inévitable statistiquement sur des dizaines de captures réelles)
        # fait retomber tout le VERDICT sur la signature du bug d'origine
        # (min_height_px=2.0, contraste=1.00), quelle que soit la qualité du
        # fix de détection ci-dessus. Le fix tolère une fraction minoritaire
        # (`pass_fraction`) sans jamais cacher le pire cas réel du détail.
        good_heights = [25.0] * 97 + [2.0, 2.0, 2.0]  # 3/100 = 3 % de parasites, sous pass_fraction=0.95
        s32_robust, d32_robust = eval_glyph_heights({"1080": good_heights, "720": []}, tokens)
        check(
            "OPS-13 : CHK-32 reste PASS avec 3% de fragments parasites de 2px (minorité tolérée)",
            s32_robust == "PASS" and d32_robust["min_height_px_1080"] == 2.0,
            str(d32_robust),
        )
        bad_heights = [25.0] * 70 + [2.0] * 30  # 30% sous le seuil : ce n'est plus une minorité, doit FAIL
        s32_majority, d32_majority = eval_glyph_heights({"1080": bad_heights, "720": []}, tokens)
        check(
            "OPS-13 : CHK-32 FAIL quand une part significative (30%) des glyphes est sous le seuil",
            s32_majority == "FAIL",
            str(d32_majority),
        )

        good_pair = (tuple(papier), tuple(hex_to_rgb01(tokens["color"]["charbon"]["bg"]["hex"])))
        degenerate_pair = ((0.5, 0.5, 0.5), (0.5, 0.5, 0.5))  # fg == bg, contraste == 1.0 (fond contaminé par lui-même)
        pairs_robust = [good_pair] * 97 + [degenerate_pair] * 3
        s33_robust, d33_robust = eval_min_contrast_pairs(pairs_robust, chk_cfg(tokens, "CHK-33").get("min_contrast", 4.5), pass_fraction=0.95)
        check(
            "OPS-13 : CHK-33 reste PASS avec 3% de paires dégénérées (fg==bg, minorité tolérée)",
            s33_robust == "PASS" and d33_robust["worst_contrast"] == 1.0,
            str(d33_robust),
        )
        pairs_majority = [good_pair] * 70 + [degenerate_pair] * 30
        s33_majority, d33_majority = eval_min_contrast_pairs(pairs_majority, chk_cfg(tokens, "CHK-33").get("min_contrast", 4.5), pass_fraction=0.95)
        check(
            "OPS-13 : CHK-33 FAIL quand une part significative (30%) des paires est dégénérée",
            s33_majority == "FAIL",
            str(d33_majority),
        )
        s33_legacy, d33_legacy = eval_min_contrast_pairs(pairs_robust, chk_cfg(tokens, "CHK-33").get("min_contrast", 4.5))
        check(
            "OPS-13 : eval_min_contrast_pairs sans pass_fraction explicite garde le strict min() historique (pass_fraction=1.0)",
            s33_legacy == "FAIL",
            str(d33_legacy),
        )
    else:
        print("  skip CHK-32 (Pillow/scipy indisponible)")

    # ---- Retour QA ART-30 24/09 16h04 : CHK-40 ne doit plus confondre une
    # clé d'agent avec un jeton universel (bandeau/bouton) qui lui ressemble
    # par coïncidence et s'affiche sur CHAQUE écran, quel que soit l'agent
    # réellement joué ---------------------------------------------------
    brush_rgb = hex_to_rgb01(tokens["color"]["pinceau"]["brush"]["hex"])
    canvas_brand = _make_image(40, 40, brush_rgb)
    universal_refs = non_agent_reference_colors(tokens)
    for agent_id, agent in tokens.get("agents", {}).items():
        key_rgb = hex_to_rgb01(agent["key"])
        other_keys = [hex_to_rgb01(a["key"]) for aid, a in tokens["agents"].items() if aid != agent_id]
        leak = agent_key_leak_mask(canvas_brand, key_rgb, other_keys + universal_refs)
        if leak.mean() > 0.001:
            check(f"CHK-40 : un aplat pinceau.brush n'est pas imputé à l'agent {agent_id}", False, f"agent {agent_id} clé={agent['key']}")
    # Un pixel qui n'est PROCHE d'aucun jeton universel reste une vraie fuite.
    some_agent = next(iter(tokens.get("agents", {}).values()))
    exact_key_rgb = hex_to_rgb01(some_agent["key"])
    canvas_leak = _make_image(40, 40, exact_key_rgb)
    other_keys_only = [hex_to_rgb01(a["key"]) for a in list(tokens["agents"].values())[1:]]
    real_leak = agent_key_leak_mask(canvas_leak, exact_key_rgb, other_keys_only + universal_refs)
    check("CHK-40 : une vraie clé d'agent (aplat exact, sans jeton universel proche) reste détectée", bool(real_leak.mean() > 0.001), f"mean={real_leak.mean()}")

    # ---- CHK-19 : simulation daltonisme, toujours mesurable -------------
    s19, d19 = eval_cvd_recommendation(tokens)
    check("CHK-19 est mesurable depuis les jetons seuls", s19 in ("PASS", "FAIL"), str(d19))

    # ---- CHK-09/10/11 (tâche OPS-11) : mesures tools/look_probe.gd ------
    cfg09 = chk_cfg(tokens, "CHK-09")
    good_ground = {
        "map_id": "wasteland",
        "ground_shadow_ratio": sum(cfg09.get("shadow_ratio", [0.62, 0.70])) / 2.0,
        "ground_shadow_L": cfg09.get("shadow_min_L", 0.30) + 0.1,
        "ground_hue_delta_deg": 5.0,
    }
    s09, d09 = eval_ground_shadow_pair(good_ground, tokens)
    check("CHK-09 accepte un ratio/L/teinte d'ombre dans les bornes (PASS attendu)", s09 == "PASS", str(d09))

    bad_ground = dict(good_ground, ground_shadow_ratio=0.20)  # bien en-dessous de [0.62, 0.70]
    s09b, d09b = eval_ground_shadow_pair(bad_ground, tokens)
    check("CHK-09 rejette un ratio d'ombre hors bornes (FAIL attendu)", s09b == "FAIL", str(d09b))

    s09c, d09c = eval_ground_shadow_pair({"map_id": "x"}, tokens)
    check("CHK-09 sans champs ground_* est non mesuré (WARN attendu)", s09c == "WARN", str(d09c))

    cfg10 = chk_cfg(tokens, "CHK-10")
    good_sil = {"map_id": "wasteland", "silhouette_min_width_px": cfg10.get("outline_min_px_at_30m", 2) + 1, "silhouette_pass_fraction": 1.0}
    s10, d10 = eval_silhouette_width(good_sil, tokens)
    check("CHK-10 accepte une largeur/fraction au-dessus des seuils (PASS attendu)", s10 == "PASS", str(d10))

    bad_sil = dict(good_sil, silhouette_pass_fraction=0.5)  # bien en-dessous de perimeter_fraction (0.90)
    s10b, d10b = eval_silhouette_width(bad_sil, tokens)
    check("CHK-10 rejette une fraction de pourtour insuffisante (FAIL attendu)", s10b == "FAIL", str(d10b))

    s11, d11 = eval_double_line({"map_id": "wasteland", "double_line_detected": False, "double_line_span_px": 0.0}, tokens)
    check("CHK-11 accepte l'absence de double trait (PASS attendu)", s11 == "PASS", str(d11))
    s11b, d11b = eval_double_line({"map_id": "wasteland", "double_line_detected": True, "double_line_span_px": 40.0}, tokens)
    check("CHK-11 rejette un double trait détecté (FAIL attendu)", s11b == "FAIL", str(d11b))

    # `resolve_ground_silhouette_checks` : pire statut retenu sur 8 cartes,
    # jamais un FAIL quand le champ est absent de TOUTES les cartes.
    lp_mixed = {"maps": [good_ground | good_sil | {"double_line_detected": False, "double_line_span_px": 0.0}, bad_ground | good_sil | {"double_line_detected": False, "double_line_span_px": 0.0}]}
    agg = resolve_ground_silhouette_checks(lp_mixed, tokens)
    check("resolve_ground_silhouette_checks : une seule carte en FAIL fait échouer CHK-09 (pire statut)", agg["CHK-09"].status == "FAIL", str(agg["CHK-09"]))
    check("resolve_ground_silhouette_checks : CHK-10 reste PASS quand les 2 cartes passent", agg["CHK-10"].status == "PASS", str(agg["CHK-10"]))
    agg_absent = resolve_ground_silhouette_checks({"maps": [{"map_id": "wasteland"}]}, tokens)
    check("resolve_ground_silhouette_checks : champ absent de toutes les cartes -> non mesuré, jamais FAIL", not agg_absent["CHK-09"].measured and agg_absent["CHK-09"].status == "WARN", str(agg_absent["CHK-09"]))
    agg_none = resolve_ground_silhouette_checks(None, tokens)
    check("resolve_ground_silhouette_checks : look_probe.json absent -> les 3 contrôles sont WARN non mesuré", all(not agg_none[c].measured for c in ("CHK-09", "CHK-10", "CHK-11")), str(agg_none))

    # ---- CHK-07 : lint statique ne doit jamais planter ------------------
    s7, d7 = lint_reserved_colors_in_data(tokens, REPO_ROOT)
    check("CHK-07 s'exécute sans exception", s7 in ("PASS", "FAIL"), str(d7)[:200])

    # ---- CHK-37 (tâche OPS-13) : lint des états de thème ----------------
    good_theme = (
        "[resource]\n"
        "Button/styles/normal = SubResource(\"A\")\n"
        "Button/styles/hover = SubResource(\"A\")\n"
        "Button/styles/pressed = SubResource(\"A\")\n"
        "Button/styles/disabled = SubResource(\"A\")\n"
        "Button/styles/focus = SubResource(\"A\")\n"
    )
    keys_good = parse_theme_control_keys(good_theme)
    check("parse_theme_control_keys : extrait bien Button avec ses 4 états", set(keys_good.get("Button", [])) >= {"hover", "pressed", "disabled", "focus"}, str(keys_good))
    s37_good, d37_good = eval_theme_states(keys_good, tokens)
    check("CHK-37 : PASS quand un contrôle couvre les 4 états requis", s37_good == "PASS", str(d37_good))

    bad_theme = good_theme + "BadWidget/styles/normal = SubResource(\"B\")\n"
    keys_bad = parse_theme_control_keys(bad_theme)
    s37_bad, d37_bad = eval_theme_states(keys_bad, tokens)
    check("CHK-37 : FAIL quand un contrôle ne couvre aucun des 4 états", s37_bad == "FAIL" and "BadWidget" in d37_bad["violations"], str(d37_bad))

    check("_covers_state : clear_button_color_pressed ne compte pas comme un état 'pressed' du contrôle", not _covers_state("clear_button_color_pressed", "pressed"))
    check("_covers_state : font_hover_color couvre 'hover'", _covers_state("font_hover_color", "hover"))

    only_panel_theme = "[resource]\nPanel/styles/panel = SubResource(\"A\")\n"
    s37_panel, d37_panel = eval_theme_states(parse_theme_control_keys(only_panel_theme), tokens)
    check("CHK-37 : un contrôle non interactif (Panel) seul -> non mesuré (aucun contrôle interactif)", s37_panel == "WARN" and not d37_panel.get("violations"), str(d37_panel))

    s37_real, d37_real = lint_theme_states(REPO_ROOT, tokens)
    check("CHK-37 : le lint sur le vrai resources/ui/ui_theme.tres s'exécute et mesure de vrais contrôles", s37_real in ("PASS", "FAIL") and "reason" not in d37_real, str(d37_real)[:300])

    # ---- CHK-13 (tâche OPS-13) : masses de nuages -----------------------
    sky_rgb = hex_to_rgb01(tokens["maps"]["wasteland"]["sky_horizon"])
    ground_rgb = (0.75, 0.60, 0.40)  # hors des deux enveloppes ciel (zénith/horizon), cf. tokens
    cloud_rgb = hex_to_rgb01(tokens["shader"]["ink_sky"]["cloud_lit"])
    img_w, img_h = 300, 200
    sky_split = 120
    canvas_sky = _make_image(img_w, img_h, ground_rgb)
    _paint_rect(canvas_sky, sky_rgb, (0, 0, img_w, sky_split))
    check("sky_region_mask : détecte le ciel peint et pas le sol", bool(sky_region_mask(canvas_sky, tokens)[0, 0]) and not bool(sky_region_mask(canvas_sky, tokens)[sky_split + 10, 0]))

    def _paint_clouds(canvas, xs, y0=30, y1=50):
        for x in xs:
            _paint_rect(canvas, cloud_rgb, (x, y0, x + 40, y1))

    canvas_ok = canvas_sky.copy()
    _paint_clouds(canvas_ok, [10, 60, 110])          # 3 masses, moitié gauche (x<150)
    _paint_clouds(canvas_ok, [160, 210, 260])        # 3 masses, moitié droite
    comps_ok = find_cloud_components(canvas_ok, tokens, row_bounds=(0, sky_split))
    s13_ok, d13_ok = eval_cloud_masses(comps_ok, canvas_ok.shape[:2], tokens, sky_row_bounds=(0, sky_split))
    check("CHK-13 : PASS avec 3 masses par demi-ciel, toutes au-dessus de l'élévation minimale", s13_ok == "PASS", str(d13_ok))

    canvas_few = canvas_sky.copy()
    _paint_clouds(canvas_few, [10, 60])               # seulement 2 à gauche : hors [3,5]
    _paint_clouds(canvas_few, [160, 210, 260])
    comps_few = find_cloud_components(canvas_few, tokens, row_bounds=(0, sky_split))
    s13_few, d13_few = eval_cloud_masses(comps_few, canvas_few.shape[:2], tokens, sky_row_bounds=(0, sky_split))
    check("CHK-13 : FAIL quand un demi-ciel a moins de 3 masses", s13_few == "FAIL" and d13_few["counts_per_half"]["left"] == 2, str(d13_few))

    canvas_low = canvas_sky.copy()
    _paint_clouds(canvas_low, [10, 60, 110])
    _paint_clouds(canvas_low, [160, 210, 260])
    # Masse collée à l'horizon (élévation ~0°) — assez grande (40x20=800px
    # >= 1 % de l'écran, cf. cloud_min_area) pour ne pas être écartée par le
    # filtre d'aire AVANT même d'atteindre le test d'élévation.
    _paint_rect(canvas_low, cloud_rgb, (200, sky_split - 20, 240, sky_split))
    comps_low = find_cloud_components(canvas_low, tokens, row_bounds=(0, sky_split))
    s13_low, d13_low = eval_cloud_masses(comps_low, canvas_low.shape[:2], tokens, sky_row_bounds=(0, sky_split))
    check("CHK-13 : FAIL quand une masse est sous l'élévation minimale (collée à l'horizon)", s13_low == "FAIL" and d13_low["below_min_elevation"], str(d13_low))

    canvas_no_sky = _make_image(img_w, img_h, ground_rgb)  # aucune masse de ciel : la vue ne montre pas le ciel
    check("sky_region_mask : rien détecté sur une vue sans ciel (ex. nadir pur)", not sky_region_mask(canvas_no_sky, tokens).any())

    # ---- build_report bout en bout, sans run_dir (tout WARN sauf lints) --
    report = build_report(None, DEFAULT_TOKENS_PATH)
    check("build_report(None, ...) couvre les 47 contrôles", len(report["checks"]) == 47, str(len(report["checks"])))
    check("build_report(None, ...) ne lève jamais une capture inexistante en FAIL", report["blocking_fail_count"] == sum(
        1 for c in report["checks"].values() if c["status"] == "FAIL" and c["blocking"] and c["measured"]
    ), "un FAIL non mesuré ne devrait jamais exister")

    # ---- --self-test avec un run_dir réel (dossier temporaire, images de synthèse) ----
    with tempfile.TemporaryDirectory(prefix="style_check_selftest_") as tmp:
        run_dir = Path(tmp)
        (run_dir / "map_shots").mkdir()
        img = Image.fromarray((np.clip(img_clean, 0, 1) * 255).astype(np.uint8))
        img.save(run_dir / "map_shots" / "wasteland_centre_map.png")
        Image.fromarray((np.clip(canvas_ok, 0, 1) * 255).astype(np.uint8)).save(
            run_dir / "map_shots" / "wasteland_aerial_nw.png"
        )
        rep2 = build_report(run_dir, DEFAULT_TOKENS_PATH)
        check("build_report(run_dir, ...) exploite une vraie capture map_shots", rep2["checks"]["CHK-02"]["measured"] is True, str(rep2["checks"]["CHK-02"]))
        check("build_report(run_dir, ...) mesure CHK-13 depuis une vraie vue aérienne", rep2["checks"]["CHK-13"]["measured"] is True, str(rep2["checks"]["CHK-13"]))

    if failures:
        print(f"\n{len(failures)} assertion(s) en échec : {failures}")
        return False
    print("\nSTYLE_CHECK_SELFTEST_OK")
    return True


# =============================================================================
#  CLI
# =============================================================================

def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Scoreur de la checklist de style (docs/STYLE_BIBLE.md §11).")
    parser.add_argument("run_dir", nargs="?", help="dossier de run de run_review.ps1 (reports/review/<horodatage>/)")
    parser.add_argument("--tokens", default=str(DEFAULT_TOKENS_PATH), help="chemin de docs/style/tokens.json")
    parser.add_argument("--out", default=None, help="chemin du style_check.json à écrire (défaut : <run_dir>/style_check.json)")
    parser.add_argument("--self-test", action="store_true", help="auto-test sur images de synthèse, n'écrit rien")
    args = parser.parse_args(argv[1:])

    if args.self_test:
        ok = self_test()
        return 0 if ok else 1

    if not args.run_dir:
        parser.print_usage(sys.stderr)
        print("erreur : <run_dir> requis (ou --self-test)", file=sys.stderr)
        return 2

    run_dir = Path(args.run_dir)
    tokens_path = Path(args.tokens)
    try:
        report = build_report(run_dir, tokens_path)
    except Exception as exc:  # noqa: BLE001 — un rapport doit toujours pouvoir être tenté à nouveau, jamais un crash muet.
        print(f"STYLE_CHECK_FAIL {exc!r}", file=sys.stderr)
        return 1

    out_path = Path(args.out) if args.out else (run_dir / "style_check.json")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"STYLE_CHECK_SCORE {report['score']['text']} gate={report['gate']} -> {out_path}")
    return 0 if report["gate"] != "FAIL" else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
