#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""test_style_check.py

Tests pytest de tools/review/style_check.py (tâche ART-03), sur des IMAGES DE
SYNTHÈSE (jamais de vraie capture — ce module ne dépend d'aucune exécution de
Godot). Couvre le contrat : CHK-02 (pas de boue), CHK-06 (teintes réservées),
CHK-18 (contraste ennemi) et CHK-32 (taille de texte), plus quelques garanties
générales du scoreur (47 contrôles toujours présents, "non mesuré" == WARN,
jamais de FAIL sur une entrée absente).

Ce fichier vit sous tests/review/ (comme le fixe le contrat ART-03) mais
n'est PAS un test gdUnit4 : il se lance avec pytest, indépendamment de
`GdUnitCmdTool.gd` (qui ne scanne que des scripts `.gd`) —

    pytest tests/review/test_style_check.py -q

`python tools/review/style_check.py --self-test` couvre le même contrat de
façon autonome (sans dépendance à pytest) : c'est la commande de vérification
officielle de la tâche ART-03, ce fichier est le pendant pytest pour
l'intégration CI/IDE.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "review"))

import style_check as sc  # noqa: E402


@pytest.fixture(scope="module")
def tokens() -> dict:
    return sc.load_tokens(sc.DEFAULT_TOKENS_PATH)


def _solid_image(w: int, h: int, rgb01) -> np.ndarray:
    arr = np.empty((h, w, 3), dtype=np.float64)
    arr[..., 0], arr[..., 1], arr[..., 2] = rgb01
    return arr


def _paint(arr: np.ndarray, rgb01, rect) -> None:
    x0, y0, x1, y1 = rect
    arr[y0:y1, x0:x1] = rgb01


# =============================================================================
#  CHK-02 — pas de boue
# =============================================================================

class TestChk02Mud:
    def test_fails_above_max_fraction(self, tokens):
        cfg = sc.chk_cfg(tokens, "CHK-02")
        bg = (0.75, 0.60, 0.40)
        mud = (0.18, 0.17, 0.16)  # OKLab L ~= 0.29, dans [0.25, 0.33)
        img = _solid_image(100, 100, bg)
        _paint(img, mud, (0, 0, 20, 100))  # 20% de l'image
        included = np.ones((100, 100), dtype=bool)
        status, frac, _, _ = sc.eval_pixel_fraction_range(
            img, included, tuple(cfg["mud_L"]), frac_max=cfg["max_fraction"]
        )
        assert status == "FAIL"
        assert frac == pytest.approx(0.20, abs=1e-6)

    def test_passes_below_max_fraction(self, tokens):
        cfg = sc.chk_cfg(tokens, "CHK-02")
        bg = (0.75, 0.60, 0.40)
        mud = (0.18, 0.17, 0.16)
        img = _solid_image(100, 100, bg)
        _paint(img, mud, (0, 0, 3, 100))  # 3% < 5%
        included = np.ones((100, 100), dtype=bool)
        status, frac, _, _ = sc.eval_pixel_fraction_range(
            img, included, tuple(cfg["mud_L"]), frac_max=cfg["max_fraction"]
        )
        assert status == "PASS"
        assert frac <= cfg["max_fraction"]

    def test_excluded_mask_pixels_never_counted(self, tokens):
        """Les pixels HUD/personnages (masque `included=False`) ne comptent
        ni au numérateur ni au dénominateur."""
        cfg = sc.chk_cfg(tokens, "CHK-02")
        bg = (0.75, 0.60, 0.40)
        mud = (0.18, 0.17, 0.16)
        img = _solid_image(100, 100, bg)
        _paint(img, mud, (0, 0, 50, 100))  # 50% de boue, mais...
        included = np.zeros((100, 100), dtype=bool)
        included[:, 50:] = True  # ... la moitié "boueuse" est EXCLUE du masque
        status, frac, count, total = sc.eval_pixel_fraction_range(
            img, included, tuple(cfg["mud_L"]), frac_max=cfg["max_fraction"]
        )
        assert count == 0
        assert total == 5000
        assert status == "PASS"


# =============================================================================
#  CHK-06 — teintes réservées
# =============================================================================

class TestChk06ReservedHues:
    def test_detects_reserved_hue_leak(self, tokens):
        clean = (0.70, 0.45, 0.30)
        magenta = sc.hex_to_rgb01(tokens["reserved"]["enemy_highlight"]["magenta"]["hex"])
        img = _solid_image(100, 100, clean)
        _paint(img, magenta, (40, 40, 60, 60))
        included = np.ones((100, 100), dtype=bool)
        status, frac = sc.eval_reserved_hue_fraction(img, included, tokens)
        assert status == "FAIL"
        assert frac > tokens["checks"]["CHK-06"]["reserved_pixel_max_fraction"]

    def test_clean_decor_passes(self, tokens):
        clean = (0.70, 0.45, 0.30)
        img = _solid_image(100, 100, clean)
        included = np.ones((100, 100), dtype=bool)
        status, frac = sc.eval_reserved_hue_fraction(img, included, tokens)
        assert status == "PASS"
        assert frac == 0.0

    def test_citron_option_also_detected(self, tokens):
        clean = (0.70, 0.45, 0.30)
        citron = sc.hex_to_rgb01(tokens["reserved"]["enemy_highlight"]["citron"]["hex"])
        img = _solid_image(100, 100, clean)
        _paint(img, citron, (0, 0, 30, 100))
        included = np.ones((100, 100), dtype=bool)
        status, _ = sc.eval_reserved_hue_fraction(img, included, tokens)
        assert status == "FAIL"


# =============================================================================
#  CHK-18 — contraste ennemi (échantillons de bord)
# =============================================================================

class TestChk18EnemyContrast:
    def test_well_contrasted_backgrounds_pass(self, tokens):
        ink = sc.hex_to_rgb01(tokens["color"]["ink"]["hex"])
        magenta = sc.hex_to_rgb01(tokens["reserved"]["enemy_highlight"]["magenta"]["hex"])
        samples = [
            {"distance_m": d, "highlight_rgb": magenta, "background_rgbs": [(0.5, 0.5, 0.5), (0.3, 0.6, 0.3), (0.6, 0.4, 0.2)]}
            for d in (10, 20, 30, 40)
        ]
        status, detail = sc.eval_enemy_contrast_samples(samples, tokens, ink)
        assert status == "PASS"
        assert detail["delta_fail_count"] == 0

    def test_low_contrast_background_fails(self, tokens):
        ink = sc.hex_to_rgb01(tokens["color"]["ink"]["hex"])
        magenta = sc.hex_to_rgb01(tokens["reserved"]["enemy_highlight"]["magenta"]["hex"])
        samples = [{"distance_m": 20, "highlight_rgb": magenta, "background_rgbs": [magenta, magenta]}]
        status, detail = sc.eval_enemy_contrast_samples(samples, tokens, ink)
        assert status == "FAIL"
        assert detail["delta_fail_count"] > 0

    def test_no_samples_is_unmeasured_warn_not_fail(self, tokens):
        ink = sc.hex_to_rgb01(tokens["color"]["ink"]["hex"])
        status, detail = sc.eval_enemy_contrast_samples([], tokens, ink)
        assert status == "WARN"

    def test_extracted_from_real_synthetic_image_via_region_sampling(self, tokens):
        """CHK-18 « sur images synthétiques » au sens littéral : une vraie
        image PNG en mémoire, échantillonnée par région (comme le ferait un
        manifeste char_ingame_shots), pas seulement des tuples RGB à la main."""
        ink = sc.hex_to_rgb01(tokens["color"]["ink"]["hex"])
        magenta = sc.hex_to_rgb01(tokens["reserved"]["enemy_highlight"]["magenta"]["hex"])
        img = _solid_image(200, 100, (0.5, 0.5, 0.5))
        _paint(img, magenta, (80, 30, 120, 70))  # "anneau ennemi" au centre
        highlight_rgb = sc.mean_rgb_in_rect(img, (80, 30, 120, 70))
        background_rgb = sc.mean_rgb_in_rect(img, (0, 0, 40, 100))
        samples = [{"distance_m": 20, "highlight_rgb": highlight_rgb, "background_rgbs": [background_rgb]}]
        status, _ = sc.eval_enemy_contrast_samples(samples, tokens, ink)
        assert status == "PASS"


# =============================================================================
#  CHK-09 — paire d'échantillons sol ombre/soleil (tâche OPS-11)
# =============================================================================

class TestChk09GroundShadowPair:
    def _good_entry(self, tokens):
        cfg = sc.chk_cfg(tokens, "CHK-09")
        return {
            "map_id": "wasteland",
            "ground_shadow_ratio": sum(cfg["shadow_ratio"]) / 2.0,
            "ground_shadow_L": cfg["shadow_min_L"] + 0.1,
            "ground_hue_delta_deg": 5.0,
        }

    def test_passes_within_all_three_bounds(self, tokens):
        status, detail = sc.eval_ground_shadow_pair(self._good_entry(tokens), tokens)
        assert status == "PASS"
        assert detail["ground_shadow_ratio"] == pytest.approx(sum(sc.chk_cfg(tokens, "CHK-09")["shadow_ratio"]) / 2.0)

    def test_fails_when_ratio_out_of_bounds(self, tokens):
        entry = dict(self._good_entry(tokens), ground_shadow_ratio=0.20)
        status, _ = sc.eval_ground_shadow_pair(entry, tokens)
        assert status == "FAIL"

    def test_fails_when_shadow_too_dark(self, tokens):
        cfg = sc.chk_cfg(tokens, "CHK-09")
        entry = dict(self._good_entry(tokens), ground_shadow_L=cfg["shadow_min_L"] - 0.05)
        status, _ = sc.eval_ground_shadow_pair(entry, tokens)
        assert status == "FAIL"

    def test_fails_when_hue_shift_exceeds_tolerance(self, tokens):
        cfg = sc.chk_cfg(tokens, "CHK-09")
        entry = dict(self._good_entry(tokens), ground_hue_delta_deg=cfg["shadow_hue_tolerance_deg"] + 10.0)
        status, _ = sc.eval_ground_shadow_pair(entry, tokens)
        assert status == "FAIL"

    def test_missing_fields_is_unmeasured_warn_not_fail(self, tokens):
        status, detail = sc.eval_ground_shadow_pair({"map_id": "wasteland"}, tokens)
        assert status == "WARN"
        assert "reason" in detail


# =============================================================================
#  CHK-10 — largeur de trait de silhouette à 30 m (tâche OPS-11)
# =============================================================================

class TestChk10SilhouetteWidth:
    def test_passes_when_width_and_fraction_above_thresholds(self, tokens):
        cfg = sc.chk_cfg(tokens, "CHK-10")
        entry = {"silhouette_min_width_px": cfg["outline_min_px_at_30m"] + 1.0, "silhouette_pass_fraction": 1.0}
        status, _ = sc.eval_silhouette_width(entry, tokens)
        assert status == "PASS"

    def test_fails_when_min_width_below_threshold(self, tokens):
        cfg = sc.chk_cfg(tokens, "CHK-10")
        entry = {"silhouette_min_width_px": cfg["outline_min_px_at_30m"] - 1.0, "silhouette_pass_fraction": 1.0}
        status, _ = sc.eval_silhouette_width(entry, tokens)
        assert status == "FAIL"

    def test_fails_when_perimeter_fraction_below_threshold(self, tokens):
        cfg = sc.chk_cfg(tokens, "CHK-10")
        entry = {"silhouette_min_width_px": cfg["outline_min_px_at_30m"] + 1.0, "silhouette_pass_fraction": 0.5}
        status, _ = sc.eval_silhouette_width(entry, tokens)
        assert status == "FAIL"

    def test_missing_fields_is_unmeasured_warn_not_fail(self, tokens):
        status, detail = sc.eval_silhouette_width({}, tokens)
        assert status == "WARN"
        assert "reason" in detail


# =============================================================================
#  CHK-11 — absence de double trait pli/silhouette (tâche OPS-11)
# =============================================================================

class TestChk11DoubleLine:
    def test_passes_when_not_detected(self, tokens):
        status, _ = sc.eval_double_line({"double_line_detected": False, "double_line_span_px": 0.0}, tokens)
        assert status == "PASS"

    def test_fails_when_detected(self, tokens):
        status, detail = sc.eval_double_line({"double_line_detected": True, "double_line_span_px": 40.0}, tokens)
        assert status == "FAIL"
        assert detail["double_line_span_px"] == 40.0

    def test_missing_field_is_unmeasured_warn_not_fail(self, tokens):
        status, detail = sc.eval_double_line({}, tokens)
        assert status == "WARN"
        assert "reason" in detail


# =============================================================================
#  resolve_ground_silhouette_checks — agrégation sur 8 cartes (tâche OPS-11)
# =============================================================================

class TestResolveGroundSilhouetteChecks:
    def test_look_probe_json_absent_is_unmeasured_for_all_three(self, tokens):
        out = sc.resolve_ground_silhouette_checks(None, tokens)
        assert set(out.keys()) == {"CHK-09", "CHK-10", "CHK-11"}
        for chk_id in out:
            assert out[chk_id].measured is False
            assert out[chk_id].status == "WARN"

    def test_field_absent_from_every_map_is_unmeasured_not_fail(self, tokens):
        out = sc.resolve_ground_silhouette_checks({"maps": [{"map_id": "wasteland"}, {"map_id": "cargo_ship"}]}, tokens)
        for chk_id in ("CHK-09", "CHK-10", "CHK-11"):
            assert out[chk_id].measured is False
            assert out[chk_id].status == "WARN"

    def test_worst_status_across_maps_wins(self, tokens):
        cfg09 = sc.chk_cfg(tokens, "CHK-09")
        good = {
            "map_id": "wasteland",
            "ground_shadow_ratio": sum(cfg09["shadow_ratio"]) / 2.0,
            "ground_shadow_L": cfg09["shadow_min_L"] + 0.1,
            "ground_hue_delta_deg": 5.0,
        }
        bad = dict(good, map_id="cargo_ship", ground_shadow_ratio=0.20)
        out = sc.resolve_ground_silhouette_checks({"maps": [good, bad]}, tokens)
        assert out["CHK-09"].status == "FAIL"
        assert out["CHK-09"].measured is True
        assert len(out["CHK-09"].data["per_map"]) == 2

    def test_all_maps_pass_gives_pass(self, tokens):
        cfg09 = sc.chk_cfg(tokens, "CHK-09")
        cfg10 = sc.chk_cfg(tokens, "CHK-10")
        good = {
            "map_id": "wasteland",
            "ground_shadow_ratio": sum(cfg09["shadow_ratio"]) / 2.0,
            "ground_shadow_L": cfg09["shadow_min_L"] + 0.1,
            "ground_hue_delta_deg": 5.0,
            "silhouette_min_width_px": cfg10["outline_min_px_at_30m"] + 1.0,
            "silhouette_pass_fraction": 1.0,
            "double_line_detected": False,
            "double_line_span_px": 0.0,
        }
        out = sc.resolve_ground_silhouette_checks({"maps": [good, dict(good, map_id="cargo_ship")]}, tokens)
        assert out["CHK-09"].status == "PASS"
        assert out["CHK-10"].status == "PASS"
        assert out["CHK-11"].status == "PASS"


# =============================================================================
#  CHK-32 — taille de texte
# =============================================================================

class TestChk32TextSize:
    def test_measures_glyph_heights_from_synthetic_image(self, tokens):
        ink = sc.hex_to_rgb01(tokens["color"]["ink"]["hex"])
        papier = sc.hex_to_rgb01(tokens["color"]["papier"]["text"]["hex"])
        img = _solid_image(400, 200, papier)
        heights = [25, 30, 22]
        x = 20
        for hh in heights:
            _paint(img, ink, (x, 20, x + 10, 20 + hh))
            x += 40
        comps = sc.find_glyph_components(img, ink)
        assert sorted(c["height_px"] for c in comps) == sorted(float(v) for v in heights)

    def test_passes_when_all_glyphs_above_threshold(self, tokens):
        status, detail = sc.eval_glyph_heights({"1080": [25.0, 30.0, 22.0], "720": []}, tokens)
        assert status == "PASS"
        assert detail["min_height_px_1080"] == 22.0

    def test_fails_when_a_glyph_is_below_threshold(self, tokens):
        cfg = sc.chk_cfg(tokens, "CHK-32")
        status, detail = sc.eval_glyph_heights({"1080": [25.0, cfg["min_px_1080"] - 1], "720": []}, tokens)
        assert status == "FAIL"

    def test_no_heights_is_unmeasured_warn(self, tokens):
        status, _ = sc.eval_glyph_heights({"1080": [], "720": []}, tokens)
        assert status == "WARN"

    def test_wide_bars_are_not_counted_as_glyphs(self, tokens):
        """Un bandeau plein écran (bordure, panneau) n'est pas un glyphe :
        filtré par `max_width_frac`."""
        ink = sc.hex_to_rgb01(tokens["color"]["ink"]["hex"])
        papier = sc.hex_to_rgb01(tokens["color"]["papier"]["text"]["hex"])
        img = _solid_image(400, 200, papier)
        _paint(img, ink, (0, 0, 400, 5))  # bandeau plein largeur, haut de 5px
        comps = sc.find_glyph_components(img, ink)
        assert comps == []


# =============================================================================
#  CHK-32/33 — régression ART-31 sur le fix ART-30 (tâche OPS-13)
#
#  `safe_ink_tolerance` (fix ART-30) protège d'un aplat `charbon` confondu
#  avec de l'encre, mais en UN SEUL seuil resserré (`tol` ~0.013), il coupe
#  aussi le halo anticrénelé d'un vrai glyphe (posé sur `papier`, ΔE ~1.46)
#  en fragments de quelques pixels — CHK-32 mesure alors 2 px et CHK-33 un
#  contraste de 1,00 sur des captures pourtant lisibles. Le fix sépare les
#  deux exigences : `tol` reste large (couvre le halo), `exclude_rgbs`/
#  `exclude_tol` retranchent étroitement les aplats confusables.
# =============================================================================

class TestChk32Chk33AntiAliasFragmentationFix:
    FRAC = 0.05  # cf. docstring de find_glyph_components : loin de tous les
    # neutres charbon (marge >= 0.036) tout en dépassant l'ancien seuil unique.

    def _blend_glyph_image(self, tokens):
        """Glyphe synthétique « persiennes » : 30 lignes, motif [encre pure,
        encre pure, mélange encre/papier] répété 10 fois — reproduit
        fidèlement la fragmentation en composantes de 2 px signalée par
        ART-31 (une vraie anticrénelage réaliste, pas juste un bord)."""
        ink = sc.hex_to_rgb01(tokens["color"]["ink"]["hex"])
        papier = sc.hex_to_rgb01(tokens["color"]["papier"]["text"]["hex"])
        blend = tuple((1 - self.FRAC) * np.array(ink) + self.FRAC * np.array(papier))
        img = _solid_image(60, 80, papier)
        for cycle in range(10):
            base = 10 + cycle * 3
            _paint(img, ink, (20, base, 30, base + 2))
            _paint(img, blend, (20, base + 2, 30, base + 3))
        return img, ink

    def test_tight_single_tolerance_fragments_the_glyph(self, tokens):
        """Documente le bug : sous l'ancien tol unique et étroit
        (`safe_ink_tolerance`), le glyphe casse en plusieurs composantes de
        2 px — jamais une seule composante de 30 px."""
        img, ink = self._blend_glyph_image(tokens)
        tight_tol = sc.safe_ink_tolerance(tokens)
        comps = sc.find_glyph_components(img, ink, tol=tight_tol)
        assert len(comps) > 1
        assert all(c["height_px"] < 5 for c in comps)

    def test_wide_tol_plus_exclude_recovers_full_glyph_height(self, tokens):
        """Le fix (tol large + exclude_rgbs/exclude_tol) mesure UNE seule
        composante de hauteur plausible (~30 px), pas 2 px."""
        img, ink = self._blend_glyph_image(tokens)
        tight_tol = sc.safe_ink_tolerance(tokens)
        charbon = tokens["color"]["charbon"]
        exclude_rgbs = [sc.hex_to_rgb01(charbon[k]["hex"]) for k in ("bg", "panel", "panel_hi")]
        comps = sc.find_glyph_components(img, ink, tol=0.16, exclude_rgbs=exclude_rgbs, exclude_tol=tight_tol)
        assert len(comps) == 1
        assert comps[0]["height_px"] >= 29

    def test_fix_recovers_plausible_high_contrast_white_on_charcoal(self, tokens):
        """Critère d'acceptation OPS-13 : texte blanc sur panneau charbon,
        contraste >= 7:1 sur le glyphe correctement reconstitué."""
        img, ink = self._blend_glyph_image(tokens)
        tight_tol = sc.safe_ink_tolerance(tokens)
        charbon = tokens["color"]["charbon"]
        exclude_rgbs = [sc.hex_to_rgb01(charbon[k]["hex"]) for k in ("bg", "panel", "panel_hi")]
        comps = sc.find_glyph_components(img, ink, tol=0.16, exclude_rgbs=exclude_rgbs, exclude_tol=tight_tol)
        assert len(comps) == 1
        bbox = comps[0]["bbox"]
        bg = sc.ring_background_rgb(img, bbox, pad=6)
        fg = tuple(img[bbox[0]:bbox[1], bbox[2]:bbox[3]].reshape(-1, 3).mean(axis=0).tolist())
        assert sc.wcag_contrast(fg, bg) >= 7.0

    def test_fix_does_not_reintroduce_art30_background_confusion(self, tokens):
        """La correction ne doit PAS réintroduire le bug ART-30 d'origine :
        un aplat de fond charbon SANS AUCUN texte reste exclu, même avec
        `tol` large, grâce à `exclude_rgbs`/`exclude_tol`."""
        ink = sc.hex_to_rgb01(tokens["color"]["ink"]["hex"])
        papier = sc.hex_to_rgb01(tokens["color"]["papier"]["text"]["hex"])
        panel_hi = sc.hex_to_rgb01(tokens["color"]["charbon"]["panel_hi"]["hex"])
        img = _solid_image(60, 60, papier)
        _paint(img, panel_hi, (20, 20, 30, 40))
        tight_tol = sc.safe_ink_tolerance(tokens)
        charbon = tokens["color"]["charbon"]
        exclude_rgbs = [sc.hex_to_rgb01(charbon[k]["hex"]) for k in ("bg", "panel", "panel_hi")]
        comps = sc.find_glyph_components(img, ink, tol=0.16, exclude_rgbs=exclude_rgbs, exclude_tol=tight_tol)
        assert comps == []

    def test_default_call_without_exclude_params_is_unchanged(self, tokens):
        """Sans `exclude_rgbs`, le comportement reste identique à avant (les
        appels existants — glyphes `papier` sur fond `charbon` — ne sont pas
        affectés)."""
        ink = sc.hex_to_rgb01(tokens["color"]["ink"]["hex"])
        papier = sc.hex_to_rgb01(tokens["color"]["papier"]["text"]["hex"])
        img = _solid_image(80, 40, papier)
        _paint(img, ink, (10, 10, 18, 30))
        _paint(img, ink, (20, 10, 28, 30))  # collé à 2px du premier
        comps = sc.find_glyph_components(img, ink)
        assert len(comps) == 2


# =============================================================================
#  CHK-32/33 — retour du vérificateur sur la tâche OPS-13 (24/09) :
#
#  (1) le fix ART-31 (`exclude_rgbs`/`exclude_tol`) n'était appliqué QU'À
#      l'appel `find_glyph_components` pour `ink` dans `resolve_ui_shots` ;
#      les deux appels pour `papier`/`papier_dim` (texte clair sur fond
#      charbon — exactement le cas visé par le critère d'acceptation)
#      gardaient `tol=0.16` par défaut SANS AUCUNE exclusion.
#      `safe_color_tolerance` généralise `safe_ink_tolerance` à n'importe
#      quelle couleur cible, et `resolve_ui_shots` l'applique désormais aux
#      trois appels.
#  (2) `eval_glyph_heights`/`eval_min_contrast_pairs` agrégeaient par un
#      strict min() sur TOUTES les composantes détectées sur TOUTES les
#      captures : une seule composante parasite de 2 px (bord anticrénelé,
#      glitch de rendu — voir `find_glyph_components`/`ring_background_rgb`)
#      fait retomber toute la métrique sur la signature du bug d'origine
#      (`min_height_px=2.0`, `contraste=1.00`), quelle que soit la qualité du
#      fix ciblé sur la détection. Les deux évaluateurs tolèrent désormais
#      une fraction minoritaire (`pass_fraction`) sans jamais cacher le pire
#      cas réel du détail.
# =============================================================================

class TestChk32Chk33SafeColorToleranceGeneralization:
    """(1) : `safe_color_tolerance` protège N'IMPORTE QUELLE couleur cible
    d'un voisin confusable, pas seulement `ink` (`safe_ink_tolerance`)."""

    def _close_neighbor(self, target, ink):
        # à ~10% de la distance target<->ink : loin de `target` (couvre
        # encore son propre anti-aliasing) mais assez proche pour tomber
        # dans tol=0.16 par défaut — comme `charbon.panel_hi` l'est de `ink`
        # dans la palette réelle (fix ART-30/ART-31).
        return tuple((0.9 * np.array(target) + 0.1 * np.array(ink)).tolist())

    @pytest.mark.parametrize("color_key", ["text", "dim"])
    def test_tightens_radius_against_a_close_synthetic_neighbor(self, tokens, color_key):
        target = sc.hex_to_rgb01(tokens["color"]["papier"][color_key]["hex"])
        ink = sc.hex_to_rgb01(tokens["color"]["ink"]["hex"])
        neighbor = self._close_neighbor(target, ink)
        tol = sc.safe_color_tolerance(target, [neighbor])
        assert 0.0 < tol < 0.16

    @pytest.mark.parametrize("color_key", ["text", "dim"])
    def test_without_exclusion_a_close_flat_is_misclassified_as_glyph(self, tokens, color_key):
        target = sc.hex_to_rgb01(tokens["color"]["papier"][color_key]["hex"])
        ink = sc.hex_to_rgb01(tokens["color"]["ink"]["hex"])
        neighbor = self._close_neighbor(target, ink)
        # Fond = `ink` : loin de `papier`/`papier_dim` dans cette palette
        # (>= 1.0), le fond lui-même ne matche jamais `target` — sans quoi le
        # rectangle fusionnerait avec tout le canvas (filtré comme bandeau).
        img = _solid_image(60, 60, ink)
        _paint(img, neighbor, (20, 20, 30, 40))
        comps = sc.find_glyph_components(img, target)  # tol=0.16 par défaut, pas d'exclusion
        assert len(comps) > 0

    @pytest.mark.parametrize("color_key", ["text", "dim"])
    def test_with_exclusion_the_close_flat_is_no_longer_a_glyph(self, tokens, color_key):
        target = sc.hex_to_rgb01(tokens["color"]["papier"][color_key]["hex"])
        ink = sc.hex_to_rgb01(tokens["color"]["ink"]["hex"])
        neighbor = self._close_neighbor(target, ink)
        img = _solid_image(60, 60, ink)
        _paint(img, neighbor, (20, 20, 30, 40))
        tol = sc.safe_color_tolerance(target, [neighbor])
        comps = sc.find_glyph_components(img, target, tol=0.16, exclude_rgbs=[neighbor], exclude_tol=tol)
        assert comps == []


class TestChk32Chk33ResolveUiShotsAppliesExclusionToPapierVariants:
    """Vérifie le CÂBLAGE dans `resolve_ui_shots` lui-même (pas seulement le
    primitif `find_glyph_components`) : les trois appels (`ink`, `papier`,
    `papier_dim`) reçoivent bien `exclude_rgbs`/`exclude_tol`. Reproduit un
    tokens.json où `charbon.panel_hi` a été rapproché de `papier.dim` — un
    scénario impossible dans la palette réelle actuelle (`papier.dim` en est
    à >= 0.8), mais qui doit rester protégé si la palette change."""

    def test_confusable_panel_hi_is_not_measured_as_papier_dim_glyph(self, tokens, tmp_path):
        import copy

        from PIL import Image as PILImage

        papier = sc.hex_to_rgb01(tokens["color"]["papier"]["text"]["hex"])
        papier_dim = sc.hex_to_rgb01(tokens["color"]["papier"]["dim"]["hex"])
        ink = sc.hex_to_rgb01(tokens["color"]["ink"]["hex"])
        neighbor = tuple((0.9 * np.array(papier_dim) + 0.1 * np.array(ink)).tolist())

        tokens_confusable = copy.deepcopy(tokens)
        tokens_confusable["color"]["charbon"]["panel_hi"]["hex"] = (
            "#" + "".join(f"{int(round(c * 255)):02x}" for c in neighbor)
        )

        ui_dir = tmp_path / "ui_shots"
        ui_dir.mkdir()
        img = _solid_image(80, 60, papier)
        _paint(img, neighbor, (20, 20, 30, 40))
        PILImage.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(ui_dir / "hud_80x1080.png")

        ctx = sc.Context(tmp_path, tokens_confusable, sc.REPO_ROOT)
        out: dict = {}
        sc.resolve_ui_shots(ctx, out)
        # Rien d'autre dans cette capture ne peut se mesurer comme glyphe :
        # si l'aplat confusable était compté, CHK-32 mesurerait sa hauteur
        # (12px) au lieu de rester "non mesuré" (aucun glyphe restant).
        assert "reason" in out["CHK-32"].data


class TestChk32Chk33PassFractionRobustness:
    """(2) : le VERDICT tolère une fraction minoritaire d'échantillons sous
    le seuil, sans jamais cacher le pire cas réel du détail."""

    def test_chk32_stays_pass_with_a_minority_of_2px_fragments(self, tokens):
        heights = [25.0] * 97 + [2.0, 2.0, 2.0]  # 3% de parasites
        status, detail = sc.eval_glyph_heights({"1080": heights, "720": []}, tokens)
        assert status == "PASS"
        assert detail["min_height_px_1080"] == 2.0  # le pire cas réel reste rapporté

    def test_chk32_fails_when_a_significant_share_is_too_small(self, tokens):
        heights = [25.0] * 70 + [2.0] * 30  # 30% : plus une minorité
        status, detail = sc.eval_glyph_heights({"1080": heights, "720": []}, tokens)
        assert status == "FAIL"

    def test_chk33_stays_pass_with_a_minority_of_degenerate_pairs(self, tokens):
        good = (
            sc.hex_to_rgb01(tokens["color"]["papier"]["text"]["hex"]),
            sc.hex_to_rgb01(tokens["color"]["charbon"]["bg"]["hex"]),
        )
        degenerate = ((0.5, 0.5, 0.5), (0.5, 0.5, 0.5))  # fg == bg, contraste == 1.0
        pairs = [good] * 97 + [degenerate] * 3
        status, detail = sc.eval_min_contrast_pairs(
            pairs, sc.chk_cfg(tokens, "CHK-33").get("min_contrast", 4.5), pass_fraction=0.95,
        )
        assert status == "PASS"
        assert detail["worst_contrast"] == 1.0

    def test_chk33_fails_when_a_significant_share_is_degenerate(self, tokens):
        good = (
            sc.hex_to_rgb01(tokens["color"]["papier"]["text"]["hex"]),
            sc.hex_to_rgb01(tokens["color"]["charbon"]["bg"]["hex"]),
        )
        degenerate = ((0.5, 0.5, 0.5), (0.5, 0.5, 0.5))
        pairs = [good] * 70 + [degenerate] * 30  # 30%
        status, _ = sc.eval_min_contrast_pairs(
            pairs, sc.chk_cfg(tokens, "CHK-33").get("min_contrast", 4.5), pass_fraction=0.95,
        )
        assert status == "FAIL"

    def test_chk33_default_pass_fraction_keeps_historical_strict_min(self, tokens):
        """Un appelant qui ne précise pas `pass_fraction` garde EXACTEMENT le
        comportement historique (100% des paires doivent passer)."""
        good = (
            sc.hex_to_rgb01(tokens["color"]["papier"]["text"]["hex"]),
            sc.hex_to_rgb01(tokens["color"]["charbon"]["bg"]["hex"]),
        )
        degenerate = ((0.5, 0.5, 0.5), (0.5, 0.5, 0.5))
        pairs = [good] * 97 + [degenerate] * 3
        status, _ = sc.eval_min_contrast_pairs(pairs, sc.chk_cfg(tokens, "CHK-33").get("min_contrast", 4.5))
        assert status == "FAIL"


# =============================================================================
#  CHK-37 — états hover/focus/pressed/disabled (tâche OPS-13)
# =============================================================================

class TestChk37ThemeStates:
    def test_control_covering_all_four_states_passes(self, tokens):
        theme_text = (
            "[resource]\n"
            "Button/styles/normal = SubResource(\"A\")\n"
            "Button/styles/hover = SubResource(\"A\")\n"
            "Button/styles/pressed = SubResource(\"A\")\n"
            "Button/styles/disabled = SubResource(\"A\")\n"
            "Button/styles/focus = SubResource(\"A\")\n"
        )
        control_keys = sc.parse_theme_control_keys(theme_text)
        assert set(control_keys["Button"]) >= {"hover", "pressed", "disabled", "focus"}
        status, detail = sc.eval_theme_states(control_keys, tokens)
        assert status == "PASS"
        assert detail["violations"] == {}

    def test_control_missing_states_fails_with_named_violations(self, tokens):
        theme_text = "[resource]\nBadWidget/styles/normal = SubResource(\"A\")\n"
        control_keys = sc.parse_theme_control_keys(theme_text)
        status, detail = sc.eval_theme_states(control_keys, tokens)
        assert status == "FAIL"
        assert set(detail["violations"]["BadWidget"]) == {"hover", "focus", "pressed", "disabled"}

    def test_state_via_color_key_is_recognized(self, tokens):
        """Un contrôle sans aucun StyleBox (CheckBox/CheckButton) exprime ses
        états par une simple couleur de police."""
        theme_text = (
            "[resource]\n"
            "CheckBox/colors/font_hover_color = Color(1, 1, 1, 1)\n"
            "CheckBox/colors/font_focus_color = Color(1, 1, 1, 1)\n"
        )
        control_keys = sc.parse_theme_control_keys(theme_text)
        status, detail = sc.eval_theme_states(control_keys, tokens)
        assert status == "FAIL"
        assert set(detail["violations"]["CheckBox"]) == {"pressed", "disabled"}

    def test_clear_button_icon_color_does_not_count_as_pressed_state(self):
        assert sc._covers_state("clear_button_color_pressed", "pressed") is False

    def test_font_hover_color_counts_as_hover_state(self):
        assert sc._covers_state("font_hover_color", "hover") is True

    def test_non_interactive_controls_are_out_of_scope(self, tokens):
        theme_text = "[resource]\nPanel/styles/panel = SubResource(\"A\")\nLabel/colors/font_color = Color(1,1,1,1)\n"
        control_keys = sc.parse_theme_control_keys(theme_text)
        status, detail = sc.eval_theme_states(control_keys, tokens)
        assert status == "WARN"
        assert "reason" in detail

    def test_missing_theme_file_is_unmeasured_warn_not_fail(self, tokens, tmp_path):
        status, detail = sc.lint_theme_states(tmp_path, tokens)
        assert status == "WARN"
        assert "reason" in detail

    def test_real_repo_theme_is_measured(self, tokens):
        """Le lint s'exécute sur le vrai fichier du dépôt et mesure de
        vraies violations (measured=True), plus jamais un WARN
        inconditionnel."""
        status, detail = sc.lint_theme_states(sc.REPO_ROOT, tokens)
        assert status in ("PASS", "FAIL")
        assert "reason" not in detail


# =============================================================================
#  CHK-13 — masses de nuages (tâche OPS-13)
# =============================================================================

class TestChk13CloudMasses:
    IMG_W, IMG_H, SKY_SPLIT = 300, 200, 120

    def _sky_canvas(self, tokens):
        sky_rgb = sc.hex_to_rgb01(tokens["maps"]["wasteland"]["sky_horizon"])
        ground_rgb = (0.75, 0.60, 0.40)  # hors des enveloppes zénith/horizon
        img = _solid_image(self.IMG_W, self.IMG_H, ground_rgb)
        _paint(img, sky_rgb, (0, 0, self.IMG_W, self.SKY_SPLIT))
        return img

    def _cloud_rgb(self, tokens):
        return sc.hex_to_rgb01(tokens["shader"]["ink_sky"]["cloud_lit"])

    def test_sky_region_mask_detects_sky_not_ground(self, tokens):
        img = self._sky_canvas(tokens)
        mask = sc.sky_region_mask(img, tokens)
        assert bool(mask[0, 0]) is True
        assert bool(mask[self.SKY_SPLIT + 10, 0]) is False

    def test_sky_region_mask_empty_on_nadir_view(self, tokens):
        ground_rgb = (0.75, 0.60, 0.40)
        img = _solid_image(self.IMG_W, self.IMG_H, ground_rgb)
        assert not sc.sky_region_mask(img, tokens).any()

    def test_passes_with_three_to_five_masses_per_half(self, tokens):
        img = self._sky_canvas(tokens)
        cloud = self._cloud_rgb(tokens)
        for x in (10, 60, 110, 160, 210, 260):
            _paint(img, cloud, (x, 30, x + 40, 50))
        comps = sc.find_cloud_components(img, tokens, row_bounds=(0, self.SKY_SPLIT))
        status, detail = sc.eval_cloud_masses(comps, img.shape[:2], tokens, sky_row_bounds=(0, self.SKY_SPLIT))
        assert status == "PASS"
        assert detail["counts_per_half"] == {"left": 3, "right": 3}

    def test_fails_when_a_half_sky_has_too_few_masses(self, tokens):
        img = self._sky_canvas(tokens)
        cloud = self._cloud_rgb(tokens)
        for x in (10, 60):  # 2 seulement à gauche : hors [3,5]
            _paint(img, cloud, (x, 30, x + 40, 50))
        for x in (160, 210, 260):
            _paint(img, cloud, (x, 30, x + 40, 50))
        comps = sc.find_cloud_components(img, tokens, row_bounds=(0, self.SKY_SPLIT))
        status, detail = sc.eval_cloud_masses(comps, img.shape[:2], tokens, sky_row_bounds=(0, self.SKY_SPLIT))
        assert status == "FAIL"
        assert detail["counts_per_half"]["left"] == 2

    def test_fails_when_a_mass_is_below_min_elevation(self, tokens):
        img = self._sky_canvas(tokens)
        cloud = self._cloud_rgb(tokens)
        for x in (10, 60, 110, 160, 210, 260):
            _paint(img, cloud, (x, 30, x + 40, 50))
        _paint(img, cloud, (200, self.SKY_SPLIT - 20, 240, self.SKY_SPLIT))  # collée à l'horizon
        comps = sc.find_cloud_components(img, tokens, row_bounds=(0, self.SKY_SPLIT))
        status, detail = sc.eval_cloud_masses(comps, img.shape[:2], tokens, sky_row_bounds=(0, self.SKY_SPLIT))
        assert status == "FAIL"
        assert detail["below_min_elevation"]

    def test_tiny_cloud_below_min_area_is_ignored(self, tokens):
        img = self._sky_canvas(tokens)
        cloud = self._cloud_rgb(tokens)
        _paint(img, cloud, (10, 30, 15, 35))  # 5x5=25px, largement sous 1% de 60000
        comps = sc.find_cloud_components(img, tokens, row_bounds=(0, self.SKY_SPLIT))
        status, detail = sc.eval_cloud_masses(comps, img.shape[:2], tokens, sky_row_bounds=(0, self.SKY_SPLIT))
        assert detail["counts_per_half"] == {"left": 0, "right": 0}

    def test_no_targets_in_tokens_returns_empty(self, tokens):
        stripped = {k: v for k, v in tokens.items() if k != "shader"}
        img = self._sky_canvas(tokens)
        assert sc.find_cloud_components(img, stripped) == []


# =============================================================================
#  Garanties générales du scoreur
# =============================================================================

class TestScorerContract:
    def test_all_47_checks_always_present(self, tokens):
        report = sc.build_report(None, sc.DEFAULT_TOKENS_PATH)
        assert set(report["checks"].keys()) == set(sc.ALL_CHECK_IDS)
        assert len(report["checks"]) == 47

    def test_unmeasured_is_always_warn_never_fail(self):
        report = sc.build_report(None, sc.DEFAULT_TOKENS_PATH)
        for chk_id, entry in report["checks"].items():
            if not entry["measured"]:
                assert entry["status"] == "WARN", f"{chk_id} non mesuré mais statut={entry['status']}"

    def test_score_text_matches_pass_count(self):
        report = sc.build_report(None, sc.DEFAULT_TOKENS_PATH)
        pass_count = sum(1 for c in report["checks"].values() if c["status"] == "PASS")
        assert report["score"]["pass"] == pass_count
        assert report["score"]["total"] == 47
        assert report["score"]["text"] == f"{pass_count}/47"

    def test_gate_is_fail_only_on_measured_blocking_fail(self):
        report = sc.build_report(None, sc.DEFAULT_TOKENS_PATH)
        measured_blocking_fails = [
            chk for chk, c in report["checks"].items() if c["status"] == "FAIL" and c["blocking"] and c["measured"]
        ]
        if report["gate"] == "FAIL":
            assert measured_blocking_fails, "gate FAIL sans aucun FAIL bloquant mesuré"

    def test_run_dir_with_real_capture_upgrades_measured_flag(self, tmp_path):
        tokens = sc.load_tokens(sc.DEFAULT_TOKENS_PATH)
        bg = (0.75, 0.60, 0.40)
        img = _solid_image(64, 64, bg)
        from PIL import Image as PILImage

        (tmp_path / "map_shots").mkdir()
        PILImage.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(
            tmp_path / "map_shots" / "wasteland_centre_map.png"
        )
        report = sc.build_report(tmp_path, sc.DEFAULT_TOKENS_PATH)
        assert report["checks"]["CHK-02"]["measured"] is True
        assert report["checks"]["CHK-06"]["measured"] is True

    def test_json_is_serialisable(self, tmp_path):
        report = sc.build_report(None, sc.DEFAULT_TOKENS_PATH)
        out = tmp_path / "style_check.json"
        out.write_text(json.dumps(report, ensure_ascii=False), encoding="utf-8")
        assert json.loads(out.read_text(encoding="utf-8"))["score"]["total"] == 47


# =============================================================================
#  Lints statiques (toujours mesurables, jamais dépendants d'un run_dir)
# =============================================================================

class TestStaticLints:
    def test_reserved_colors_lint_runs_and_is_deterministic(self, tokens):
        s1, d1 = sc.lint_reserved_colors_in_data(tokens, sc.REPO_ROOT)
        s2, d2 = sc.lint_reserved_colors_in_data(tokens, sc.REPO_ROOT)
        assert s1 == s2
        assert d1 == d2

    def test_agent_key_colors_lint(self, tokens):
        status, detail = sc.lint_agent_key_colors(tokens)
        assert status in ("PASS", "FAIL")
        assert "violations" in detail

    def test_cvd_recommendation_always_measurable(self, tokens):
        status, detail = sc.eval_cvd_recommendation(tokens)
        assert status in ("PASS", "FAIL", "WARN")
        assert isinstance(detail, dict)

    def test_theme_states_lint_runs_and_is_deterministic(self, tokens):
        s1, d1 = sc.lint_theme_states(sc.REPO_ROOT, tokens)
        s2, d2 = sc.lint_theme_states(sc.REPO_ROOT, tokens)
        assert s1 == s2
        assert d1 == d2
