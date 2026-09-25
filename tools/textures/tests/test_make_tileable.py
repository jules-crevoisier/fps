#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/textures/tests/test_make_tileable.py

Tests pytest de tools/textures/make_tileable.py (ART-79B), et de la
protection qu'il ajoute a tools/textures/gen_textures.py. Aucun des deux ne
depend de Godot/Blender : tout se teste sur des IMAGES DE SYNTHESE, comme le
contrat ART-79B le prevoit explicitement tant que les planches Tripo 4K
(assets/incoming/tripo/textures/sheet_<A|B|C>_<a|b>.jpg) ne sont pas
arrivees -- ce fichier ne lit ni n'ecrit jamais un fichier du depot reel hors
de `tmp_path` (les constantes de chemin de `make_tileable`/`gen_textures`
sont monkeypatchees vers un faux depot le temps du test).

Lancer :
    python -m pytest tools/textures/tests/test_make_tileable.py -q
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest
from PIL import Image
from scipy.ndimage import gaussian_filter

TOOLS_TEXTURES = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_TEXTURES))

import make_tileable as mt  # noqa: E402
import gen_textures as gt  # noqa: E402


# =============================================================================
# Fixtures de synthese -- un "materiau" plausible : variation basse frequence
# multi-octave (comme tools/textures/gen_textures.py::make_terrain) + grain
# fin de peinture, JAMAIS deja raccordable par construction (aucune des deux
# n'est periodique).
# =============================================================================

def _paint_like(shape: tuple[int, int], seed: int, base_rgb: tuple[float, float, float]) -> np.ndarray:
    h, w = shape
    rng = np.random.default_rng(seed)
    img = np.ones((h, w, 3)) * np.array(base_rgb)
    for sigma_frac, amp in ((0.25, 0.035), (0.12, 0.02), (0.05, 0.012)):
        noise = rng.normal(size=(h, w))
        noise = gaussian_filter(noise, sigma=max(h, w) * sigma_frac, mode="nearest")
        std = noise.std()
        if std > 1e-9:
            noise = (noise - noise.mean()) / std
        img += noise[..., None] * amp
    img += (rng.random((h, w, 1)) - 0.5) * 0.02
    return np.clip(img, 0.02, 0.98)


def _make_synthetic_sheet(
    size: int = 1024,
    gutter_frac: float = 0.02,
    offset_frac: float = 0.0,
    liseré: bool = False,
    seed0: int = 1,
) -> tuple[np.ndarray, dict]:
    """Planche 2x2 synthetique : 4 materiaux distincts, gouttiere noire (avec
    ou sans lisere d'encre au bord de chaque case), decalee de `offset_frac`
    par rapport au centre geometrique -- reproduit exactement ce que
    SOURCES.md decrit ("gouttiere noire, parfois un lisere d'encre au bord
    de chaque case")."""
    gutter = max(2, int(size * gutter_frac))
    offset = int(size * offset_frac)
    center = size // 2 + offset
    cells = {
        "top_left": _paint_like((center, center), seed0 + 0, (0.55, 0.35, 0.20)),
        "top_right": _paint_like((center, size - center), seed0 + 1, (0.45, 0.50, 0.55)),
        "bottom_left": _paint_like((size - center, center), seed0 + 2, (0.60, 0.30, 0.15)),
        "bottom_right": _paint_like((size - center, size - center), seed0 + 3, (0.30, 0.30, 0.32)),
    }
    sheet = np.zeros((size, size, 3))
    sheet[0:center, 0:center] = cells["top_left"]
    sheet[0:center, center:size] = cells["top_right"]
    sheet[center:size, 0:center] = cells["bottom_left"]
    sheet[center:size, center:size] = cells["bottom_right"]

    gx0, gx1 = center - gutter // 2, center + gutter // 2
    gy0, gy1 = center - gutter // 2, center + gutter // 2
    sheet[:, gx0:gx1] = 0.0
    sheet[gy0:gy1, :] = 0.0
    if liseré:
        b = max(1, gutter // 3)
        sheet[:, gx0 - b:gx0] *= 0.15
        sheet[:, gx1:gx1 + b] *= 0.15
        sheet[gy0 - b:gy0, :] *= 0.15
        sheet[gy1:gy1 + b, :] *= 0.15
    meta = {"gutter_x": (gx0, gx1), "gutter_y": (gy0, gy1), "center": center}
    return np.clip(sheet, 0.0, 1.0), meta


def _save_jpeg(img01: np.ndarray, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    arr = (np.clip(img01, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    Image.fromarray(arr, mode="RGB").save(path, quality=95)


# =============================================================================
# Detection de gouttiere / decoupe -- avec et sans lisere, +/-3 % du centre
# =============================================================================

class TestGutterDetection:
    @pytest.mark.parametrize("offset_frac", [0.0, 0.03, -0.03])
    @pytest.mark.parametrize("liseré", [False, True])
    def test_detects_gutter_within_tolerance(self, offset_frac: float, liseré: bool) -> None:
        sheet, meta = _make_synthetic_sheet(offset_frac=offset_frac, liseré=liseré, seed0=10)
        grid = mt.detect_grid_2x2(sheet)
        gx0, gx1 = grid["gutter_x"]
        gy0, gy1 = grid["gutter_y"]
        exp_gx0, exp_gx1 = meta["gutter_x"]
        exp_gy0, exp_gy1 = meta["gutter_y"]
        # Le CENTRE de la bande detectee doit tomber a quelques pixels du
        # centre reel de la gouttiere synthetique, que la fenetre de
        # recherche ait ou non a corriger un decalage de +/-3 % et qu'il y
        # ait ou non un lisere fusionne dedans.
        assert abs((gx0 + gx1) - (exp_gx0 + exp_gx1)) <= 8
        assert abs((gy0 + gy1) - (exp_gy0 + exp_gy1)) <= 8

    def test_cells_are_non_degenerate_and_exclude_the_gutter(self) -> None:
        sheet, meta = _make_synthetic_sheet(offset_frac=0.03, liseré=True, seed0=20)
        grid = mt.detect_grid_2x2(sheet)
        gx0, gx1 = grid["gutter_x"]
        gy0, gy1 = grid["gutter_y"]
        for cell in mt.CELLS:
            y0, y1, x0, x1 = grid[cell]
            assert y1 - y0 > sheet.shape[0] * 0.3
            assert x1 - x0 > sheet.shape[1] * 0.3
            # aucune case ne doit deborder dans la bande de gouttiere detectee.
            assert x1 <= gx0 or x0 >= gx1
            assert y1 <= gy0 or y0 >= gy1


# =============================================================================
# Raccord (tileable) -- 12 cas, ecart de bord <= 1.5x ecart interieur
# =============================================================================

class TestSeamQuality:
    @pytest.mark.parametrize("i", list(range(12)))
    def test_seamless_within_tolerance(self, i: int) -> None:
        shape = (300 + i * 5, 320 + i * 3)
        crop = _paint_like(shape, seed=100 + i, base_rgb=(0.3 + 0.05 * (i % 5), 0.4, 0.5 - 0.02 * i))
        crop = mt.resize01(crop, mt.OUTPUT_SIZE)
        tiled = mt.make_seamless(crop, overlap_frac=0.12)
        tiled = mt.soft_low_freq_equalize(tiled, amount=0.5)
        ok, edge, interior = mt.is_seam_ok(tiled)
        assert ok, f"case {i}: edge={edge:.5f} > 1.5*interior={1.5 * interior:.5f}"

    def test_is_not_a_cross_fade(self) -> None:
        """Chaque pixel de la bande reparee doit provenir INTEGRALEMENT
        d'un des deux candidats (coupe dure), jamais d'une moyenne ponderee
        des deux -- sinon ce serait le fondu croise que le contrat interdit."""
        shape = (256, 256)
        crop = _paint_like(shape, seed=7, base_rgb=(0.5, 0.4, 0.3))
        crop = mt.resize01(crop, 512)
        work = crop
        h, w = work.shape[0], work.shape[1]
        shift = w // 2
        shifted = np.roll(work, shift, axis=1)
        center = w // 2
        ov = max(4, int(round(w * 0.12)))
        ov = min(ov, center - 1, w - center - 1)
        cand_before = shifted[:, center - ov:center, :]
        cand_after = shifted[:, center:center + ov, :][:, ::-1, :]
        result = mt._quilt_axis(work, axis=1, overlap_frac=0.12)
        band = result[:, center - ov:center, :]
        is_before = np.all(np.isclose(band, cand_before, atol=1e-9), axis=-1)
        is_after = np.all(np.isclose(band, cand_after, atol=1e-9), axis=-1)
        assert np.all(is_before | is_after), "un pixel de la bande ne correspond exactement a AUCUN des deux candidats -- fondu detecte"


# =============================================================================
# Aucune teinte des bandes reservees d'equipe
# =============================================================================

class TestReservedBands:
    def test_removes_magenta_band_tint(self) -> None:
        img = np.tile(np.array([0.6, 0.3, 0.4]), (64, 64, 1))
        img[10:30, 10:30] = np.array([1.0, 0.0, 0.8])  # rose/magenta sature, bande [300,355]
        fixed, n_fixed = mt.enforce_reserved_bands(img)
        assert n_fixed > 0
        self._assert_clean(fixed)

    def test_removes_citron_band_tint(self) -> None:
        img = np.tile(np.array([0.4, 0.5, 0.3]), (64, 64, 1))
        img[10:30, 10:30] = np.array([0.75, 1.0, 0.05])  # citron/lime sature, bande [105,145]
        fixed, n_fixed = mt.enforce_reserved_bands(img)
        assert n_fixed > 0
        self._assert_clean(fixed)

    def test_leaves_ordinary_material_hues_untouched(self) -> None:
        """Rouille, bois, sable, beton -- aucun de ces tons ne doit etre
        touche (pas de faux positif sur une teinte normale de matiere)."""
        rust = np.tile(np.array([0.71, 0.34, 0.16]), (32, 32, 1))
        wood = np.tile(np.array([0.61, 0.42, 0.26]), (32, 32, 1))
        for img in (rust, wood):
            fixed, n_fixed = mt.enforce_reserved_bands(img)
            assert n_fixed == 0
            assert np.allclose(fixed, img, atol=1e-6)

    @staticmethod
    def _assert_clean(img01: np.ndarray) -> None:
        lab = mt.rgb01_to_oklab(img01)
        _, c, h = mt.oklab_to_oklch(lab)
        bands, threshold = mt.load_reserved_tokens()
        in_band = np.zeros(h.shape, dtype=bool)
        for lo, hi in bands:
            in_band |= (h >= lo) & (h <= hi)
        assert not np.any(in_band & (c > threshold))


# =============================================================================
# gen_textures.py ne modifie jamais un fichier de HAND_PAINTED.txt
# =============================================================================

class TestGenTexturesProtection:
    def test_rerun_never_touches_protected_files(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        out_terrain = tmp_path / "assets" / "textures" / "painted"
        out_terrain.mkdir(parents=True)
        hand_painted_list = out_terrain / "HAND_PAINTED.txt"
        monkeypatch.setattr(gt, "REPO_ROOT", tmp_path)
        monkeypatch.setattr(gt, "OUT_TERRAIN", out_terrain)
        monkeypatch.setattr(gt, "HAND_PAINTED_LIST", hand_painted_list)

        protected_albedo = out_terrain / "material_wood_planks_albedo.png"
        protected_grime = out_terrain / "material_wood_planks_grime.png"
        sentinel = b"HAND-PAINTED-SENTINEL-BYTES-NOT-PROCEDURAL"
        protected_albedo.write_bytes(sentinel)
        protected_grime.write_bytes(sentinel)
        hand_painted_list.write_text(
            "assets/textures/painted/material_wood_planks_albedo.png\n"
            "assets/textures/painted/material_wood_planks_grime.png\n",
            encoding="utf-8",
        )

        protected = gt._load_hand_painted_protected()
        assert protected_albedo.resolve() in protected
        assert protected_grime.resolve() in protected

        written = gt._write_material_textures(protected)
        assert protected_albedo not in written
        assert protected_grime not in written
        assert protected_albedo.read_bytes() == sentinel
        assert protected_grime.read_bytes() == sentinel

        # un autre materiau, non protege, DOIT etre (re)genere normalement.
        rust_albedo = out_terrain / "material_rust_albedo.png"
        assert rust_albedo.exists()
        assert rust_albedo in written

    def test_protected_terrain_file_is_skipped_too(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        out_terrain = tmp_path / "assets" / "textures" / "painted"
        out_terrain.mkdir(parents=True)
        hand_painted_list = out_terrain / "HAND_PAINTED.txt"
        monkeypatch.setattr(gt, "REPO_ROOT", tmp_path)
        monkeypatch.setattr(gt, "OUT_TERRAIN", out_terrain)
        monkeypatch.setattr(gt, "HAND_PAINTED_LIST", hand_painted_list)

        protected_terrain = out_terrain / "terrain_sable_albedo.png"
        sentinel = b"HAND-PAINTED-TERRAIN-SENTINEL"
        protected_terrain.write_bytes(sentinel)
        hand_painted_list.write_text("assets/textures/painted/terrain_sable_albedo.png\n", encoding="utf-8")

        protected = gt._load_hand_painted_protected()
        terrain_files = gt._write_terrains(protected)
        assert protected_terrain not in terrain_files
        assert protected_terrain.read_bytes() == sentinel
        # un autre terrain, non protege, doit etre genere.
        assert (out_terrain / "terrain_pont_albedo.png").exists()

    def test_missing_list_protects_nothing(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(gt, "HAND_PAINTED_LIST", tmp_path / "does_not_exist.txt")
        assert gt._load_hand_painted_protected() == set()


# =============================================================================
# hand_painted.yaml -- schema et choix de variante verrouilles par le lead
# =============================================================================

class TestHandPaintedConfig:
    def test_locks_the_leads_variant_choice(self) -> None:
        config = mt.load_config(mt.DEFAULT_CONFIG)
        materials = config["materials"]
        assert len(materials) == 12
        expected = {
            "wood_planks": ("A", "a", "top_left"),
            "corrugated_metal": ("A", "b", "top_right"),
            "rust": ("A", "a", "bottom_left"),
            "painted_metal": ("A", "a", "bottom_right"),
            "terrain_sable": ("B", "a", "top_left"),
            "terrain_terre_battue": ("B", "a", "top_right"),
            "sand_dirt": ("B", "b", "bottom_left"),
            "cracked_concrete": ("B", "a", "bottom_right"),
            "wl_rock_strata": ("C", "a", "top_left"),
            "wl_plaster": ("C", "b", "top_right"),
            "asphalt": ("C", "a", "bottom_left"),
            "container_paint": ("C", "b", "bottom_right"),
        }
        for kind, (sheet, variant, cell) in expected.items():
            spec = materials[kind]
            assert (spec["sheet"], spec["variant"], spec["cell"]) == (sheet, variant, cell), kind

    def test_grime_only_for_kinds_with_an_existing_mask(self) -> None:
        config = mt.load_config(mt.DEFAULT_CONFIG)
        materials = config["materials"]
        with_grime = {name for name, spec in materials.items() if spec.get("grime_output")}
        assert with_grime == {
            "wood_planks", "corrugated_metal", "painted_metal", "cracked_concrete", "container_paint",
        }


# =============================================================================
# Bout en bout -- commande unique sur des planches synthetiques (dans un faux
# depot temporaire : rien n'ecrit jamais dans le vrai assets/textures/).
# =============================================================================

class TestEndToEndOnSyntheticSheets:
    @pytest.fixture()
    def fake_repo(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
        monkeypatch.setattr(mt, "REPO_ROOT", tmp_path)
        monkeypatch.setattr(mt, "HAND_PAINTED_LIST", tmp_path / "assets/textures/painted/HAND_PAINTED.txt")
        monkeypatch.setattr(mt, "CONTROL_SHEET_PATH", tmp_path / "assets/textures/painted/TILE_CHECK.png")
        # tokens.json reste le VRAI fichier du depot (lecture seule, source
        # de verite unique pour les bandes reservees) -- seule la lecture
        # des sources et l'ecriture des sorties passent par le faux depot.
        sheets_dir = tmp_path / "assets" / "incoming" / "tripo" / "textures"
        seed = 0
        for sheet in ("A", "B", "C"):
            for variant in ("a", "b"):
                seed += 1
                img, _ = _make_synthetic_sheet(liseré=(variant == "b"), seed0=seed * 10)
                _save_jpeg(img, sheets_dir / f"sheet_{sheet}_{variant}.jpg")
        return tmp_path

    def test_run_processes_all_twelve_materials(self, fake_repo: Path, capsys: pytest.CaptureFixture) -> None:
        rc = mt.run(mt.DEFAULT_CONFIG, dry_run=False)
        out = capsys.readouterr().out
        assert rc == 0, out
        assert out.count("TILE_OK") == 12
        assert "TILE_FAIL" not in out

        config = mt.load_config(mt.DEFAULT_CONFIG)
        for spec in config["materials"].values():
            out_path = fake_repo / spec["output"]
            assert out_path.exists(), out_path
            img = Image.open(out_path)
            assert img.size == (mt.OUTPUT_SIZE, mt.OUTPUT_SIZE)
            if spec.get("grime_output"):
                grime_path = fake_repo / spec["grime_output"]
                assert grime_path.exists()

        assert mt.CONTROL_SHEET_PATH.exists()

        hand_painted = mt.HAND_PAINTED_LIST.read_text(encoding="utf-8")
        n_expected = len(config["materials"]) + sum(
            1 for spec in config["materials"].values() if spec.get("grime_output")
        )
        listed = [ln for ln in hand_painted.splitlines() if ln and not ln.startswith("#")]
        assert len(listed) == n_expected

    def test_dry_run_writes_nothing_but_the_control_sheet(self, fake_repo: Path) -> None:
        rc = mt.run(mt.DEFAULT_CONFIG, dry_run=True)
        assert rc == 0
        assert mt.CONTROL_SHEET_PATH.exists()
        assert not mt.HAND_PAINTED_LIST.exists()
        config = mt.load_config(mt.DEFAULT_CONFIG)
        for spec in config["materials"].values():
            assert not (fake_repo / spec["output"]).exists()

    def test_missing_sources_report_tile_fail_without_crashing(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture,
    ) -> None:
        monkeypatch.setattr(mt, "REPO_ROOT", tmp_path)
        monkeypatch.setattr(mt, "HAND_PAINTED_LIST", tmp_path / "assets/textures/painted/HAND_PAINTED.txt")
        monkeypatch.setattr(mt, "CONTROL_SHEET_PATH", tmp_path / "assets/textures/painted/TILE_CHECK.png")
        rc = mt.run(mt.DEFAULT_CONFIG, dry_run=False)
        out = capsys.readouterr().out
        assert rc == 1
        assert out.count("TILE_FAIL") == 12
        assert "source manquante" in out
        assert mt.CONTROL_SHEET_PATH.exists()
        assert not mt.HAND_PAINTED_LIST.exists()


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
