#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/ui/tests/test_slice_icon_sheets.py

Tests pytest de tools/ui/slice_icon_sheets.py (UX-21) : repérage de la grille
par détection des gouttières (ligne fine planche 1, double bordure planche 2),
détourage du fond anthracite en alpha (remplissage depuis les BORDS, jamais un
point fixe supposé fond -- un picto peut aller jusqu'au bord de sa case, voir
TestRealSheetCorners), redimensionnement 128 sans liseré noir.

La géométrie et le détourage sont d'abord prouvés sur des planches DE SYNTHÈSE
(déterministes, rapides, aucune dépendance aux vraies planches). Une suite
d'intégration tourne en plus sur les deux VRAIES planches Tripo
(assets/incoming/tripo/icons/*.png, déjà dans le dépôt) pour verrouiller les
30 icônes réellement livrées -- elle échoue proprement (`pytest.skip`) si ces
fichiers venaient à manquer.

Lancer :
    python -m pytest tools/ui/tests/test_slice_icon_sheets.py -q
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

TOOLS_UI = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_UI))

import slice_icon_sheets as sis  # noqa: E402

REPO_ROOT = TOOLS_UI.parents[1]
REAL_SHEETS = tuple(REPO_ROOT / spec.path for spec in sis.SHEETS)


# =============================================================================
# Planches de synthèse -- fond anthracite bruité, gouttières noires, un picto
# simple (disque crème cerclé d'encre) bien centré et marge dans chaque case.
# =============================================================================

BG = (52, 52, 52)
INK = (8, 7, 6)
CREAM = (230, 225, 214)


def _paint_padded_icon(arr: np.ndarray, cx: int, cy: int, r: int) -> None:
    """Un picto "normal" : disque crème cerclé d'encre, bonne marge de fond
    autour (contrairement aux 2 cas réels étudiés à la main dans
    TestRealSheetCorners, dont le picto va jusqu'au bord de sa case)."""
    yy, xx = np.ogrid[: arr.shape[0], : arr.shape[1]]
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    arr[(dist <= r) & (dist > r - 5)] = INK
    arr[dist <= r - 5] = CREAM


def _paint_edge_bleeding_icon(arr: np.ndarray, x0: int, y0: int, x1: int, y1: int) -> None:
    """Un picto qui va jusqu'au bord SUPÉRIEUR de sa case (comme la fumée de
    Rideau/Guet ou le rideau de Voile/Roseau sur la vraie planche 2) : fond
    normal en bas, contenu crème plein depuis y0 jusqu'à mi-hauteur."""
    mid = (y0 + y1) // 2
    arr[y0:mid, x0:x1] = CREAM
    arr[mid - 3:mid, x0:x1] = INK  # une frange d'encre marque la limite du picto.


def _make_single_gutter_sheet(size: int = 800, grid: int = 4, gutter: int = 6, seed: int = 0) -> np.ndarray:
    """Planche façon planche 1 : UNE fine ligne de gouttière noire entre les
    cases (pas de bordure propre à chaque case)."""
    rng = np.random.default_rng(seed)
    arr = np.clip(np.array(BG, dtype=np.int16) + rng.integers(-2, 3, size=(size, size, 3)), 0, 255).astype(np.uint8)
    cell = size // grid
    for row in range(grid):
        for col in range(grid):
            cx, cy = col * cell + cell // 2, row * cell + cell // 2
            _paint_padded_icon(arr, cx, cy, r=cell // 3)
    for i in range(1, grid):
        pos = i * cell
        arr[:, pos - gutter // 2: pos + gutter // 2] = 0
        arr[pos - gutter // 2: pos + gutter // 2, :] = 0
    return arr


def _make_double_border_sheet(size: int = 1024, grid: int = 4, border: int = 4, inset_frac: float = 0.02, seed: int = 0) -> np.ndarray:
    """Planche façon planche 2 : chaque case porte SA PROPRE bordure noire
    (inset du bord de la case), laissant un mince interstice de fond entre
    deux cases voisines -- jamais une case à part entière (filtré par
    `MIN_SEGMENT_FRACTION`)."""
    rng = np.random.default_rng(seed)
    arr = np.clip(np.array(BG, dtype=np.int16) + rng.integers(-2, 3, size=(size, size, 3)), 0, 255).astype(np.uint8)
    cell = size // grid
    inset = max(2, int(cell * inset_frac))
    for row in range(grid):
        for col in range(grid):
            x0, y0 = col * cell + inset, row * cell + inset
            x1, y1 = (col + 1) * cell - inset, (row + 1) * cell - inset
            arr[y0:y0 + border, x0:x1] = 0
            arr[y1 - border:y1, x0:x1] = 0
            arr[y0:y1, x0:x0 + border] = 0
            arr[y0:y1, x1 - border:x1] = 0
            cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
            _paint_padded_icon(arr, cx, cy, r=(x1 - x0) // 3)
    return arr


# =============================================================================
# Détection de la grille (gouttières)
# =============================================================================

class TestGutterDetection:
    def test_single_gutter_sheet_yields_sixteen_non_overlapping_cells(self) -> None:
        arr = _make_single_gutter_sheet(size=800, grid=4, gutter=6, seed=1)
        boxes = sis.detect_cells(Image.fromarray(arr, mode="RGB"))
        assert len(boxes) == 16
        cell = 800 // 4
        for idx, (x0, y0, x1, y1) in enumerate(boxes):
            row, col = divmod(idx, 4)
            # chaque boîte doit rester à l'intérieur de SA case géométrique
            # (jamais déborder dans la case voisine ni dans la gouttière).
            assert col * cell <= x0 < x1 < (col + 1) * cell
            assert row * cell <= y0 < y1 < (row + 1) * cell
            assert (x1 - x0) > cell * 0.7  # la gouttière ne mange presque rien.
            assert (y1 - y0) > cell * 0.7

    def test_double_border_sheet_ignores_the_thin_interstice_between_cells(self) -> None:
        arr = _make_double_border_sheet(size=1024, grid=4, seed=2)
        boxes = sis.detect_cells(Image.fromarray(arr, mode="RGB"))
        assert len(boxes) == 16
        cell = 1024 // 4
        for idx, (x0, y0, x1, y1) in enumerate(boxes):
            row, col = divmod(idx, 4)
            assert col * cell <= x0 < x1 < (col + 1) * cell
            assert row * cell <= y0 < y1 < (row + 1) * cell
            assert (x1 - x0) > cell * 0.5
            assert (y1 - y0) > cell * 0.5

    def test_wrong_expected_count_raises_instead_of_silently_mis_slicing(self) -> None:
        arr = _make_single_gutter_sheet(size=800, grid=4, seed=3)
        black = np.asarray(Image.fromarray(arr, mode="RGB").convert("RGB"), dtype=np.int16).max(axis=2) <= sis.GUTTER_BLACK_MAX
        with pytest.raises(ValueError):
            sis.find_axis_segments(black, axis=0, length=800, count=5)


# =============================================================================
# Détourage -- remplissage depuis les bords, jamais l'encre, jamais un point
# fixe supposé fond (régression directe du bug corrigé pendant cette tâche).
# =============================================================================

class TestBackgroundRemoval:
    def _padded_cell(self, seed: int = 10) -> tuple[Image.Image, tuple[int, int, int]]:
        size = 220
        rng = np.random.default_rng(seed)
        arr = np.clip(np.array(BG, dtype=np.int16) + rng.integers(-2, 3, size=(size, size, 3)), 0, 255).astype(np.uint8)
        _paint_padded_icon(arr, size // 2, size // 2, r=size // 3)
        return Image.fromarray(arr, mode="RGB"), BG

    def test_padded_icon_gets_fully_transparent_corners(self) -> None:
        cell, bg = self._padded_cell()
        out = sis.remove_background(cell, bg)
        arr = np.array(out)
        w, h = out.size
        for x, y in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
            assert arr[y, x, 3] == 0, f"coin ({x},{y}) pas transparent"

    def test_ink_ring_is_never_erased(self) -> None:
        cell, bg = self._padded_cell(seed=11)
        src = np.array(cell.convert("RGB"))
        out = np.array(sis.remove_background(cell, bg))
        is_ink = np.all(np.abs(src.astype(int) - np.array(INK)) <= 6, axis=-1)
        assert is_ink.sum() > 50, "le picto de synthèse doit contenir un anneau d'encre notable"
        assert np.all(out[..., 3][is_ink] == 255), "un pixel d'encre a été rendu transparent"

    def test_cream_fill_is_never_erased(self) -> None:
        cell, bg = self._padded_cell(seed=12)
        src = np.array(cell.convert("RGB"))
        out = np.array(sis.remove_background(cell, bg))
        is_cream = np.all(np.abs(src.astype(int) - np.array(CREAM)) <= 6, axis=-1)
        assert is_cream.sum() > 200
        assert np.all(out[..., 3][is_cream] == 255)

    def test_content_touching_one_edge_is_preserved_background_elsewhere_is_still_removed(self) -> None:
        """Régression directe du bug corrigé pendant UX-21 : un ancien
        détourage semé depuis quelques COINS fixes lisait, à tort, la couleur
        du picto comme "le fond" dès qu'un picto touchait ce coin -- il
        mangeait alors le picto par endroits (bordure irrégulière `speckle`).
        Le remplissage doit être semé UNIQUEMENT depuis les pixels de BORD
        déjà proches de la référence de fond (globale, par planche)."""
        size = 200
        arr = np.tile(np.array(BG, dtype=np.uint8), (size, size, 1))
        _paint_edge_bleeding_icon(arr, 0, 0, size, size)
        cell = Image.fromarray(arr, mode="RGB")

        out = np.array(sis.remove_background(cell, BG))
        # Haut de la case (le picto) : jamais transparent, quelle que soit sa
        # couleur -- y compris les pixels crème, très différents du fond.
        assert np.all(out[0:5, :, 3] == 255), "le picto qui va jusqu'au bord a été mangé par le détourage"
        # Bas de la case (fond réel, jamais repeint par le picto) : bien
        # détouré malgré le picto voisin qui occupe le haut de la case.
        assert np.all(out[-5:, :, 3] == 0), "le fond réel, plus bas dans la case, n'a pas été détouré"

    def test_background_reference_is_the_sheet_wide_median_not_a_single_corner(self) -> None:
        """Une case dont AUCUN coin n'est du fond (picto qui déborde des 4
        coins) doit quand même être détourée correctement dès lors que la
        référence de fond vient de toute la planche, jamais d'un coin de
        cette case précise."""
        sheet = _make_single_gutter_sheet(size=400, grid=2, seed=20)
        bg = sis.sheet_background_color(Image.fromarray(sheet, mode="RGB"))
        assert all(abs(c - b) <= 6 for c, b in zip(BG, bg)), f"référence de fond inattendue : {bg}"


# =============================================================================
# Redimensionnement -- pas de liseré noir (alpha prémultiplié)
# =============================================================================

class TestResizeIcon:
    def test_no_black_fringe_on_downscale(self) -> None:
        size = 256
        arr = np.zeros((size, size, 4), dtype=np.uint8)
        arr[..., :3] = CREAM
        yy, xx = np.ogrid[:size, :size]
        dist = np.sqrt((xx - size / 2) ** 2 + (yy - size / 2) ** 2)
        arr[..., 3] = np.clip(255 - (dist - size * 0.3) * 8, 0, 255).astype(np.uint8)
        rgba = Image.fromarray(arr, mode="RGBA")

        small = sis.resize_icon(rgba, size=32)
        out = np.array(small)
        translucent = (out[..., 3] > 40) & (out[..., 3] < 220)
        assert translucent.sum() > 0, "le test suppose une frange semi-transparente après réduction"
        # Sans prémultiplication, le RGB (0,0,0) des pixels transparents
        # voisins assombrit ces pixels de bord vers le noir -- ici la
        # luminosité doit rester proche de CREAM, jamais s'effondrer.
        assert out[..., :3][translucent].mean() > 150, "liseré noir détecté au redimensionnement"


# =============================================================================
# Nommage et bout en bout (planche de synthèse -> fichiers)
# =============================================================================

class TestNamingAndEndToEnd:
    def test_cell_icon_names_order(self) -> None:
        spec = sis.SheetSpec(Path("unused.png"), ("vif", "choc", "vanne"))
        names = sis.cell_icon_names(spec)
        assert names == [
            "vif_passive", "vif_c", "vif_q", "vif_e", "vif_x",
            "choc_passive", "choc_c", "choc_q", "choc_e", "choc_x",
            "vanne_passive", "vanne_c", "vanne_q", "vanne_e", "vanne_x",
        ]

    def test_slice_sheet_writes_fifteen_named_128_pngs_and_skips_cell_sixteen(self, tmp_path: Path) -> None:
        arr = _make_single_gutter_sheet(size=800, grid=4, seed=30)
        sheet_path = tmp_path / "sheet.png"
        Image.fromarray(arr, mode="RGB").save(sheet_path)
        out_dir = tmp_path / "out"
        out_dir.mkdir()

        spec = sis.SheetSpec(sheet_path, ("vif", "choc", "vanne"))
        written = sis.slice_sheet(spec, out_dir)

        assert len(written) == 15
        expected_names = set(sis.cell_icon_names(spec))
        assert {p.stem for p in written} == expected_names
        for p in written:
            img = Image.open(p)
            assert img.size == (sis.ICON_SIZE, sis.ICON_SIZE)
            assert img.mode == "RGBA"
        # la case 16 (dernière case de la planche) n'a jamais de fichier.
        assert not (out_dir / "vanne_16.png").exists()


# =============================================================================
# Intégration -- les VRAIES planches Tripo du dépôt (assets/incoming/tripo/
# icons/*.png), déjà livrées pour cette tâche.
# =============================================================================

def _require_real_sheets() -> None:
    missing = [p for p in REAL_SHEETS if not p.exists()]
    if missing:
        pytest.skip(f"planches Tripo manquantes : {missing}")


class TestRealSheets:
    def test_detects_a_full_4x4_grid_on_both_sheets(self) -> None:
        _require_real_sheets()
        for path in REAL_SHEETS:
            boxes = sis.detect_cells(Image.open(path))
            assert len(boxes) == 16, path

    def test_slice_all_produces_thirty_correctly_named_128_rgba_icons(self, tmp_path: Path) -> None:
        _require_real_sheets()
        written = sis.slice_all(output_dir=tmp_path, repo_root=REPO_ROOT)
        assert len(written) == 30
        names = {p.stem for p in written}
        expected = {
            f"{agent}_{slot}"
            for spec in sis.SHEETS for agent in spec.agents for slot in sis.SLOT_ORDER
        }
        assert names == expected
        for p in written:
            img = Image.open(p)
            assert img.size == (sis.ICON_SIZE, sis.ICON_SIZE)
            assert img.mode == "RGBA"

    def test_ink_is_never_erased_on_either_real_sheet(self) -> None:
        """La preuve rigoureuse de "encre préservée" (critère d'acceptation
        UX-21) : tout pixel quasi noir de la case SOURCE reste opaque après
        détourage, planche entière, aucune exception."""
        _require_real_sheets()
        for spec in sis.SHEETS:
            sheet_path = REPO_ROOT / spec.path
            image = Image.open(sheet_path)
            boxes = sis.detect_cells(image)
            bg = sis.sheet_background_color(image)
            m = sis.CELL_CROP_MARGIN
            for x0, y0, x1, y1 in boxes:
                cell = image.crop((x0 + m, y0 + m, x1 + 1 - m, y1 + 1 - m))
                src = np.asarray(cell.convert("RGB"), dtype=np.int16)
                is_ink = src.max(axis=2) <= 25
                if not is_ink.any():
                    continue
                out = np.array(sis.remove_background(cell, bg))
                erased = is_ink & (out[..., 3] == 0)
                assert not erased.any(), f"{sheet_path.name} : {erased.sum()} pixel(s) d'encre effacé(s)"


class TestRealSheetCorners:
    """Sur les 30 icônes réelles, la quasi-totalité a une bonne marge de fond
    (coins transparents), sauf DEUX planches Tripo dont le picto va jusqu'au
    bord de sa case par construction (fumée de Rideau/Guet, rideau de Voile/
    Roseau) -- prouvé ici pixel par pixel, jamais supposé."""

    KNOWN_EDGE_BLEEDING = {"guet_c", "roseau_q"}

    def _icon_arrays(self) -> dict[str, np.ndarray]:
        _require_real_sheets()
        out: dict[str, np.ndarray] = {}
        for spec in sis.SHEETS:
            sheet_path = REPO_ROOT / spec.path
            image = Image.open(sheet_path)
            boxes = sis.detect_cells(image)
            bg = sis.sheet_background_color(image)
            m = sis.CELL_CROP_MARGIN
            for name, (x0, y0, x1, y1) in zip(sis.cell_icon_names(spec), boxes):
                cell = image.crop((x0 + m, y0 + m, x1 + 1 - m, y1 + 1 - m))
                out[name] = np.array(sis.remove_background(cell, bg))
        return out

    def test_at_least_twenty_eight_of_thirty_icons_have_fully_transparent_corners(self) -> None:
        icons = self._icon_arrays()
        fully_transparent = 0
        for name, arr in icons.items():
            h, w = arr.shape[:2]
            corners = [arr[0, 0], arr[0, w - 1], arr[h - 1, 0], arr[h - 1, w - 1]]
            if all(c[3] == 0 for c in corners):
                fully_transparent += 1
        assert fully_transparent >= 28, (
            f"seulement {fully_transparent}/30 icônes ont leurs 4 coins transparents "
            f"(exceptions connues : {sorted(self.KNOWN_EDGE_BLEEDING)})"
        )

    def test_the_two_known_exceptions_are_real_painted_content_not_leftover_background(self) -> None:
        """Preuve, pas hypothèse : le(s) coin(s) non transparents de ces deux
        icônes sont loin de la couleur de fond de leur planche -- c'est donc
        du picto réel (fumée/rideau qui déborde), jamais du fond oublié par
        un détourage défaillant."""
        icons = self._icon_arrays()
        for spec in sis.SHEETS:
            bg = sis.sheet_background_color(Image.open(REPO_ROOT / spec.path))
            for name in sis.cell_icon_names(spec):
                if name not in self.KNOWN_EDGE_BLEEDING:
                    continue
                arr = icons[name]
                h, w = arr.shape[:2]
                corners = [arr[0, 0], arr[0, w - 1], arr[h - 1, 0], arr[h - 1, w - 1]]
                opaque_corners = [c for c in corners if c[3] > 0]
                assert opaque_corners, f"{name} est cité comme exception mais a bien ses 4 coins transparents"
                for c in opaque_corners:
                    dist = sum(abs(int(c[i]) - bg[i]) for i in range(3))
                    assert dist > sis.BG_FLOOD_THRESHOLD, (
                        f"{name} : coin opaque {tuple(c)} trop proche du fond {bg} "
                        "-- ce serait alors un vrai bug de détourage, pas du picto"
                    )


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
