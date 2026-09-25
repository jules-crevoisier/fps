#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/blender/tests/test_make_wl_shanty_kit.py
Tests de tools/blender/make_wl_shanty_kit.py (ART-73). Ce générateur importe
`bpy` : indisponible hors du process Blender, donc ce fichier ne l'importe
JAMAIS directement — il relance Blender EN SOUS-PROCESS (une seule fois,
`setUpClass`, coût du lancement amorti sur tous les cas) sur le générateur
lui-même, en mode `--selftest-json` (voir son en-tête) : il construit les 14
modules, exporte chaque .glb réel dans assets/models/props/wasteland/shanty/,
le fait vérifier par `check_asset.py` (importé en process, budget de la
classe "architecture" du contrat, <= 6000 tris), écrit un rapport JSON et
imprime `WL_SHANTY_KIT_SELFTEST_RESULT <json>` en dernière ligne de stdout.
Chaque `test_*` ci-dessous relit ce résultat déjà calculé et fait une
assertion normale dessus (jamais de second lancement Blender par test —
rapide à l'itération, même convention que test_ai_restyle.py).

Blender : `BLENDER_BIN` (variable d'environnement) sinon le chemin connu de
CLAUDE.md.

Lancer :
    python -m pytest tools/blender/tests/test_make_wl_shanty_kit.py -q
    (ou, sans pytest : python tools/blender/tests/test_make_wl_shanty_kit.py)

Un seul module, pendant l'itération (ne passe PAS par ce fichier de test,
mais par le générateur directement, voir son en-tête) :
    blender -b -P tools/blender/make_wl_shanty_kit.py -- --only wall_1_level
"""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
GENERATOR_SCRIPT = os.path.join(HERE, os.pardir, "make_wl_shanty_kit.py")

EXPECTED_MODULES = {
    "wall_1_level", "wall_2_level",
    "pediment_narrow", "pediment_wide",
    "window_shutters_open", "window_shutters_closed",
    "door", "porch", "balcony_railing", "roof_corrugated",
    "corner_outer", "corner_inner", "cornice_band", "exterior_stairs",
}

ALLOWED_KINDS = {"wood_planks", "corrugated_metal", "rust", "painted_metal", "dirty_glass"}


def _blender_bin() -> str:
    env = os.environ.get("BLENDER_BIN")
    if env:
        return env
    # Chemin connu de ce poste (CLAUDE.md du dépôt) — repli seulement si
    # BLENDER_BIN n'est pas défini, jamais supposé sur une autre machine.
    return r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"


class _ReportRunner:
    """Lance le générateur UNE fois pour toute la classe de test et garde le
    résultat JSON en cache — un test qui a besoin du rapport avant qu'il ait
    été calculé (Blender introuvable, plantage avant même d'imprimer le
    marqueur) échoue avec le stdout/stderr complet plutôt qu'un KeyError
    opaque."""
    _result = None
    _raw_output = None

    @classmethod
    def get(cls) -> dict:
        if cls._result is None:
            blender_bin = _blender_bin()
            if not os.path.isfile(blender_bin):
                raise unittest.SkipTest(
                    f"Blender introuvable ({blender_bin!r}) — définir BLENDER_BIN pour lancer "
                    "tools/blender/tests/test_make_wl_shanty_kit.py")
            out_path = os.path.join(tempfile.mkdtemp(prefix="wl_shanty_kit_test_"), "report.json")
            cmd = [
                blender_bin, "-b", "--factory-startup", "--python-exit-code", "1",
                "-P", GENERATOR_SCRIPT, "--", "--selftest-json", out_path,
            ]
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
            cls._raw_output = proc.stdout + "\n--- stderr ---\n" + proc.stderr
            if proc.returncode != 0:
                raise AssertionError(
                    f"make_wl_shanty_kit.py a planté (code {proc.returncode}) avant d'imprimer son "
                    f"résultat :\n{cls._raw_output}")
            marker = "WL_SHANTY_KIT_SELFTEST_RESULT "
            line = next((ln for ln in proc.stdout.splitlines() if ln.startswith(marker)), None)
            if line is None:
                raise AssertionError(f"pas de marqueur {marker!r} dans la sortie :\n{cls._raw_output}")
            cls._result = json.loads(line[len(marker):])
        return cls._result

    @classmethod
    def module(cls, name: str) -> dict:
        report = cls.get()
        by_name = {m["name"]: m for m in report["modules"]}
        if name not in by_name:
            raise AssertionError(f"module {name!r} absent du rapport : {sorted(by_name)}")
        return by_name[name]


class TestModuleCountAndOverallResult(unittest.TestCase):
    """Critère d'acceptation : au moins 14 modules, check_asset PASS partout,
    aucune matière hors des 5 kinds peints du contrat."""

    def test_overall_ok(self):
        report = _ReportRunner.get()
        self.assertTrue(report["ok"], report["failures"])

    def test_at_least_14_modules(self):
        report = _ReportRunner.get()
        self.assertGreaterEqual(report["module_count"], 14)

    def test_expected_module_categories_present(self):
        report = _ReportRunner.get()
        names = {m["name"] for m in report["modules"]}
        missing = EXPECTED_MODULES - names
        self.assertEqual(missing, set(), f"catégories de modules manquantes : {missing}")

    def test_every_module_passes_check_asset_excluding_known_chk16_limitation(self):
        """NOTE : ce test n'affirme PAS le critère d'acceptation littéral
        « check_asset PASS » — il affirme uniquement l'absence d'échec dur
        HORS CHK-16 (mesh vide, budget de triangles, sommets orphelins,
        arêtes non-manifold). Le statut LITTÉRAL (non filtré) est vérifié
        séparément et honnêtement par `TestChk16ExceptionIsTrackedNotHidden`
        ci-dessous — voir make_wl_shanty_kit.py (commentaire
        CHK16_EXCEPTION_APPROVED_BY_LEAD) pour pourquoi cette exclusion
        existe et n'est PAS encore une exception approuvée par le lead."""
        report = _ReportRunner.get()
        failing = [(m["name"], m["check_asset_failures_excl_chk16"])
            for m in report["modules"] if not m["check_asset_ok_excl_chk16_known_limitation"]]
        self.assertEqual(failing, [], f"check_asset ECHEC HORS CHK-16 (vraie régression) sur : {failing}")

    def test_every_module_within_tri_budget(self):
        report = _ReportRunner.get()
        over_budget = [(m["name"], m["tris"]) for m in report["modules"] if m["tris"] > 6000]
        self.assertEqual(over_budget, [], f"budget de 6000 tris dépassé : {over_budget}")

    def test_only_contract_material_kinds_used(self):
        report = _ReportRunner.get()
        for m in report["modules"]:
            with self.subTest(module=m["name"]):
                self.assertTrue(set(m["slots"]).issubset(ALLOWED_KINDS), m["slots"])

    def test_footprints_align_to_half_meter_grid(self):
        report = _ReportRunner.get()
        off_grid = [(m["name"], m["dims_m"][0]) for m in report["modules"] if not m["grid_x_ok"]]
        self.assertEqual(off_grid, [], f"largeur hors grille de 0,5 m : {off_grid}")


class TestPlankWallsAreIndividuallyModeled(unittest.TestCase):
    """« mur de planches 1 et 2 niveaux (planches modélisées une à une) » —
    on vérifie qu'il existe bien PLUSIEURS planches distinctes (jamais un
    seul pavé texturé), et que le niveau 2 en compte le double du niveau 1."""

    def test_wall_1_level_has_multiple_individual_planks(self):
        m = _ReportRunner.module("wall_1_level")
        self.assertGreater(m["plank_count"], 8)

    def test_wall_2_level_has_roughly_twice_the_planks(self):
        w1 = _ReportRunner.module("wall_1_level")
        w2 = _ReportRunner.module("wall_2_level")
        self.assertGreater(w2["plank_count"], w1["plank_count"] * 1.8)

    def test_plank_gap_within_1_to_2_cm(self):
        report = _ReportRunner.get()
        self.assertTrue(report["plank_gap_within_contract"], report["plank_gap_m"])

    def test_plank_offset_within_1_cm(self):
        report = _ReportRunner.get()
        self.assertTrue(report["plank_jitter_within_contract"], report["plank_jitter_m"])


class TestChamfer(unittest.TestCase):
    """« Chanfrein 1-2 cm sur toute arête exposée » (critère d'acceptation)."""

    def test_chamfer_within_1_to_2_cm(self):
        report = _ReportRunner.get()
        self.assertTrue(report["chamfer_within_contract"], report["chamfer_m"])


class TestDoorCotesKit(unittest.TestCase):
    """« ouvertures aux cotes Kit (porte 1,2 x 2,2 m) » — cotes vertes."""

    def test_door_opening_matches_kit_cotes(self):
        m = _ReportRunner.module("door")
        self.assertEqual(m["opening_m"], {"w": 1.2, "h": 2.2})
        self.assertTrue(m["opening_matches_kit_cotes"])

    def test_door_void_is_not_covered_by_wall_planks(self):
        m = _ReportRunner.module("door")
        self.assertTrue(m["opening_void_clear"])


class TestWindowRecess(unittest.TestCase):
    """« fenêtre encadrée en retrait >= 8 cm avec volets » (2 variantes :
    volets ouverts/fermés)."""

    def test_window_variants_present(self):
        report = _ReportRunner.get()
        names = {m["name"] for m in report["modules"]}
        self.assertIn("window_shutters_open", names)
        self.assertIn("window_shutters_closed", names)

    def test_window_recess_at_least_8_cm(self):
        for name in ("window_shutters_open", "window_shutters_closed"):
            with self.subTest(module=name):
                m = _ReportRunner.module(name)
                self.assertGreaterEqual(m["window_recess_m"], 0.08)
                self.assertTrue(m["window_recess_ok"])

    def test_window_void_is_not_covered_by_wall_planks(self):
        for name in ("window_shutters_open", "window_shutters_closed"):
            with self.subTest(module=name):
                m = _ReportRunner.module(name)
                self.assertTrue(m["opening_void_clear"])


class TestModulePivot(unittest.TestCase):
    """« pivots au sol sur une grille de 0,5 m » — chaque module place son
    pivot au repère d'auteur (0,0,0), trivialement un multiple de la grille
    (make_wl_shanty_kit.py::GRID_M) — au sol pour les modules qui reposent au
    rez-de-chaussée, au plan de raccord (haut de mur / coin) pour les modules
    rapportés en hauteur (balcon, corniche, toit) ou asymétriques (angle,
    porche, escalier). check_asset.py ne vérifie qu'une convention générique
    « centre-bas de bbox » (`origin_at_bottom_center`, un AVERTISSEMENT,
    jamais un échec dur — son propre message dit "peut être volontaire") :
    ce test-ci, spécifique au contrat ART-73 et à la géométrie réellement
    construite (`pivot_m` capturé dans Blender avant tout aller-retour
    glTF), est la vérification qui compte pour ce critère, plutôt que
    d'imposer à un kit modulaire à pivots asymétriques la convention
    « bbox centrée » d'un prop isolé — ce qui casserait l'alignement de pose
    attendu par ART-73B (pose sur la carte, hors périmètre de ce fichier)."""

    def test_every_module_pivot_is_on_half_meter_grid(self):
        report = _ReportRunner.get()
        off_grid = [(m["name"], m["pivot_m"]) for m in report["modules"] if not m["pivot_grid_ok"]]
        self.assertEqual(off_grid, [], f"pivot hors grille de 0,5 m : {off_grid}")

    def test_every_module_pivot_is_author_space_origin(self):
        """Convention EFFECTIVEMENT appliquée par ce générateur (voir
        build_module) : le pivot est TOUJOURS le repère d'auteur (0,0,0),
        jamais un recentrage géométrique après coup — un test qui casserait
        si un module oubliait ce point de référence commun au kit."""
        report = _ReportRunner.get()
        wrong_pivot = [(m["name"], m["pivot_m"]) for m in report["modules"] if m["pivot_m"] != [0.0, 0.0, 0.0]]
        self.assertEqual(wrong_pivot, [], f"pivot hors du repère d'auteur (0,0,0) : {wrong_pivot}")


class TestChk16ExceptionIsTrackedNotHidden(unittest.TestCase):
    """Retour vérificateur ART-73 : le test qui affirme « check_asset PASS »
    ne doit JAMAIS confondre le résultat brut du linter (le critère
    d'acceptation littéral) avec l'exclusion CHK-16 documentée dans
    make_wl_shanty_kit.py. Ce test-ci vérifie que le manifeste rend l'état
    RÉEL impossible à manquer, PAS qu'il est déjà résolu : il resterait
    VERT même si demain plus AUCUN module n'était concerné (`affected_
    modules` vide) — il échouerait seulement si l'exception redevenait
    silencieuse (champ absent) ou se déclarait faussement approuvée sans
    qu'un lead ne l'ait explicitement mis à True dans le fichier source."""

    def test_chk16_raw_status_is_journalized_per_module(self):
        report = _ReportRunner.get()
        for m in report["modules"]:
            with self.subTest(module=m["name"]):
                self.assertIn("check_asset_raw_ok", m)
                self.assertIn("check_asset_failures_excl_chk16", m)
                self.assertIn("check_asset_floating_piece_failures", m)
                # Le champ RAW ne doit jamais être plus optimiste que la
                # réalité : s'il dit PASS, aucun échec (même CHK-16) ne doit
                # rester dans check_asset_failures.
                if m["check_asset_raw_ok"]:
                    self.assertEqual(m["check_asset_failures"], [])

    def test_chk16_exception_block_present_and_explicit(self):
        report = _ReportRunner.get()
        self.assertIn("chk16_exception", report)
        exc = report["chk16_exception"]
        self.assertIn("approved_by_lead", exc)
        self.assertIn("affected_modules", exc)
        self.assertIn("decision_needed", exc)
        self.assertGreaterEqual(len(exc["decision_needed"]), 1)
        # Cohérence : la liste des modules affectés doit correspondre
        # EXACTEMENT à ceux qui ont au moins un échec CHK-16 dans leur
        # propre entrée — pas un résumé recalculé différemment ailleurs.
        recomputed = sorted(m["name"] for m in report["modules"] if m["check_asset_floating_piece_failures"])
        self.assertEqual(sorted(exc["affected_modules"]), recomputed)

    def test_chk16_exception_not_silently_marked_approved(self):
        """Si ce test casse un jour, c'est qu'un lead a mis
        CHK16_EXCEPTION_APPROVED_BY_LEAD à True dans make_wl_shanty_kit.py —
        exactement le seul mécanisme d'approbation voulu (voir son
        commentaire) : ce cas est un signal à vérifier manuellement, pas une
        régression à corriger en sens inverse."""
        report = _ReportRunner.get()
        exc = report["chk16_exception"]
        if exc["affected_modules"]:
            self.assertFalse(exc["approved_by_lead"],
                "CHK16_EXCEPTION_APPROVED_BY_LEAD est à True : vérifier que c'est bien une décision "
                "du lead et non un oubli avant de considérer ce test comme un échec")


if __name__ == "__main__":
    unittest.main()
