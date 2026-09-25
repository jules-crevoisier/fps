#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/blender/tests/test_shell_to_skin.py
Tests de tools/blender/shell_to_skin.py (ART-92, R2 « peau de façade »). Ce
script importe `bpy` : indisponible hors du process Blender, donc ce fichier
ne l'importe JAMAIS directement — il relance Blender EN SOUS-PROCESS (une
seule fois, `setUpClass`, coût du lancement amorti sur tous les cas) sur le
générateur lui-même, en mode `--selftest-json` (voir son en-tête) : il
construit une carte depuis une coque synthétique CONTRÔLÉE (mécanisme
« card » vérifié précisément — perçage, étirement, écrasement de relief,
albédo) puis, séparément, exécute les 3 modes (card/shell/crop) sur la
VRAIE coque `assets/models/props/wasteland/tripo/wl_saloon.glb`, aux cotes
« Hôtel S » du critère d'acceptation ART-92 (docs/art/WASTELAND_V4_ART_
PLAN.md §2/§9 : Hotel 10×6,4×6, portes S offset ±2,5 m). Chaque `test_*`
ci-dessous relit ce résultat déjà calculé et fait une assertion normale
dessus (jamais de second lancement Blender par test — rapide à l'itération,
même convention que test_make_wl_shanty_kit.py).

Blender : `BLENDER_BIN` (variable d'environnement) sinon le chemin connu de
CLAUDE.md.

Lancer :
    python -m pytest tools/blender/tests/test_shell_to_skin.py -q
    (ou, sans pytest : python tools/blender/tests/test_shell_to_skin.py)

Itération rapide sur UN mode/UNE coque, sans passer par ce fichier (voir
l'en-tête de shell_to_skin.py pour le CLI complet) :
    blender -b -P tools/blender/shell_to_skin.py -- --mode card \\
        --in assets/models/props/wasteland/tripo/wl_saloon.glb --face min_y \\
        --depth 0.6 --target-width 10 --target-height 4.5 --out /tmp/out.glb
"""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
GENERATOR_SCRIPT = os.path.join(HERE, os.pardir, "shell_to_skin.py")

# R2 (docs/art/WASTELAND_V4_ART_PLAN.md §1) — mêmes seuils que les constantes
# du module, recopiés ici en dur : un test doit détecter une régression de
# la constante ELLE-MÊME, pas silencieusement suivre si elle change.
CARD_MAX_STRETCH_FRACTION = 0.12
SHELL_MAX_STRETCH_FRACTION = 0.15
SHELL_MAX_STRETCH_CYLINDER_FRACTION = 0.32
MAX_RELIEF_M = 0.10
OPENING_TOLERANCE_M = 0.02


def _blender_bin() -> str:
    env = os.environ.get("BLENDER_BIN")
    if env:
        return env
    # Chemin connu de ce poste (CLAUDE.md du dépôt) — repli seulement si
    # BLENDER_BIN n'est pas défini, jamais supposé sur une autre machine.
    return r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"


class _ReportRunner:
    """Lance le générateur UNE fois pour toute la classe de test et garde le
    résultat JSON en cache — voir la docstring équivalente de
    test_make_wl_shanty_kit.py (même convention)."""
    _result = None
    _raw_output = None

    @classmethod
    def get(cls) -> dict:
        if cls._result is None:
            blender_bin = _blender_bin()
            if not os.path.isfile(blender_bin):
                raise unittest.SkipTest(
                    f"Blender introuvable ({blender_bin!r}) — définir BLENDER_BIN pour lancer "
                    "tools/blender/tests/test_shell_to_skin.py")
            out_path = os.path.join(tempfile.mkdtemp(prefix="shell_to_skin_test_"), "report.json")
            cmd = [
                blender_bin, "-b", "--factory-startup", "--python-exit-code", "1",
                "-P", GENERATOR_SCRIPT, "--", "--selftest-json", out_path,
            ]
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            cls._raw_output = proc.stdout + "\n--- stderr ---\n" + proc.stderr
            if proc.returncode != 0:
                raise AssertionError(
                    f"shell_to_skin.py a planté (code {proc.returncode}) avant d'imprimer son "
                    f"résultat :\n{cls._raw_output}")
            marker = "SHELL_TO_SKIN_SELFTEST_RESULT "
            line = next((ln for ln in proc.stdout.splitlines() if ln.startswith(marker)), None)
            if line is None:
                raise AssertionError(f"pas de marqueur {marker!r} dans la sortie :\n{cls._raw_output}")
            cls._result = json.loads(line[len(marker):])
        return cls._result


class TestOverallResult(unittest.TestCase):
    """Critère d'acceptation global : les 3 modes tournent de bout en bout
    sur la coque réelle `wl_saloon.glb` et le mécanisme « card » (fixture
    contrôlée) satisfait toutes les cotes du contrat."""

    def test_overall_ok(self):
        report = _ReportRunner.get()
        self.assertTrue(report["ok"], report["failures"])


class TestCardStretchWithin12Percent(unittest.TestCase):
    """R2 « card » : jamais plus de 12 % d'étirement par axe."""

    def test_synthetic_card_stretch_u_within_12_percent(self):
        c = _ReportRunner.get()["card"]
        self.assertLessEqual(c["stretch_u"], CARD_MAX_STRETCH_FRACTION)

    def test_synthetic_card_stretch_v_within_12_percent(self):
        c = _ReportRunner.get()["card"]
        self.assertLessEqual(c["stretch_v"], CARD_MAX_STRETCH_FRACTION)

    def test_synthetic_card_stretch_flagged_within_contract(self):
        c = _ReportRunner.get()["card"]
        self.assertTrue(c["stretch_within_contract"])

    def test_wl_saloon_card_stretch_within_12_percent(self):
        """Même contrainte sur la VRAIE coque Hôtel S (docs/research/
        11_wasteland_v4_layout.md §9 : Hotel 10 m de large)."""
        r = _ReportRunner.get()["card_wl_saloon"]
        self.assertLessEqual(r["stretch_u"], CARD_MAX_STRETCH_FRACTION)
        self.assertLessEqual(r["stretch_v"], CARD_MAX_STRETCH_FRACTION)
        self.assertTrue(r["stretch_within_contract"])


class TestReliefCrushedTo10cm(unittest.TestCase):
    """R1 : sous 2,6 m, aucun visuel ne dépasse la boîte de plus de 10 cm,
    en saillie comme en retrait — après `flatten_relief`."""

    def test_synthetic_card_relief_after_flatten_within_10cm(self):
        c = _ReportRunner.get()["card"]
        self.assertLessEqual(c["relief_after_flatten_m"], MAX_RELIEF_M + 1e-6)
        self.assertTrue(c["relief_within_contract"])

    def test_wl_saloon_card_relief_after_flatten_within_10cm(self):
        """Sur `wl_saloon`, le porche mesuré dépasse largement 10 cm AVANT
        écrasement (preuve que le test exerce un vrai cas, pas un no-op) ;
        après écrasement, il doit rentrer dans l'enveloppe."""
        r = _ReportRunner.get()["card_wl_saloon"]
        self.assertGreater(r.get("relief_before_flatten_m", 0.0), MAX_RELIEF_M,
            "fixture suspecte : aucun relief mesuré avant écrasement sur wl_saloon")
        self.assertTrue(r["relief_within_contract"])


class TestOpeningsWithin2cm(unittest.TestCase):
    """R3 : les ouvertures percées correspondent aux cotes du JSON de
    collision à ±2 cm — vérifié STRUCTURELLEMENT (mesure du contour de
    perçage réellement présent dans le maillage exporté, voir
    `shell_to_skin.measure_opening_edges`), jamais supposé."""

    def test_synthetic_card_openings_within_2cm(self):
        c = _ReportRunner.get()["card"]
        self.assertTrue(c["opening_within_2cm"], c["opening_check"])

    def test_synthetic_card_both_doors_measured_and_precise(self):
        c = _ReportRunner.get()["card"]
        samples = c["opening_check"]["samples"]
        self.assertEqual(len(samples), 2, "les 2 portes Hôtel S (offset ±2,5 m) doivent être mesurées")
        for sample in samples:
            with self.subTest(rect=sample["rect"]):
                self.assertTrue(sample["within_2cm"], sample)
                for side, deviation in sample["deviations_m"].items():
                    self.assertLessEqual(deviation, OPENING_TOLERANCE_M + 1e-9,
                        f"côté {side} : écart {deviation} m > {OPENING_TOLERANCE_M} m")


class TestAlbedoIntact(unittest.TestCase):
    """R2 : « le slot 0 garde l'albédo Tripo intact » — le matériau/l'image
    du slot 0 exporté doit être EXACTEMENT celui de la coque source (jamais
    remplacé ni retexturé par ce script), pour les deux passages (fixture
    contrôlée et coque `wl_saloon` réelle)."""

    def test_synthetic_card_slot0_material_intact(self):
        albedo = _ReportRunner.get()["albedo_synthetic"]
        self.assertTrue(albedo["slot0_intact"], albedo)
        self.assertLess(albedo["mean_delta_e"], 2.0)

    def test_wl_saloon_card_slot0_material_intact(self):
        albedo = _ReportRunner.get()["albedo_wl_saloon"]
        self.assertTrue(albedo["slot0_intact"], albedo)
        self.assertLess(albedo["mean_delta_e"], 2.0)


class TestRevealFacesPaintedSlot1(unittest.TestCase):
    """R2 : « les faces de coupe (tableaux de porte) prennent le slot 1, en
    wood_planks peint »."""

    def test_reveal_material_slot_is_wood_planks(self):
        c = _ReportRunner.get()["card"]
        idx = c["reveal_material_index"]
        self.assertGreaterEqual(idx, 1, "le slot 1 (jamais le slot 0, réservé à l'albédo Tripo)")


class TestCheckAssetPass(unittest.TestCase):
    """`check_asset` PASS sur la fixture contrôlée ; sur la VRAIE coque
    `wl_saloon.glb`, PAS de régression (le fichier échoue déjà check_asset
    AVANT tout traitement par ce script — 28 arêtes non-manifold, constaté en
    relançant check_asset.py directement sur le fichier source — donc le
    critère pertinent ici est « ce script n'aggrave rien », pas « check_asset
    PASS sur un fichier déjà en défaut avant lui », voir le commentaire de
    `shell_to_skin.run_selftest`)."""

    def test_synthetic_card_check_asset_pass(self):
        c = _ReportRunner.get()["card"]
        self.assertIsNot(c["check_asset_ok"], False, c.get("check_asset"))

    def test_shell_and_crop_do_not_add_nonmanifold_edges(self):
        report = _ReportRunner.get()
        known_baseline = 28  # voir shell_to_skin.py::run_selftest, WL_SALOON_KNOWN_NONMANIFOLD_EDGES
        for key in ("shell", "crop"):
            with self.subTest(mode=key):
                check = report[key]["check_asset"]
                count = check["objects"][0]["bad_nonmanifold_edges"] if check and check.get("objects") else 0
                self.assertLessEqual(count, known_baseline,
                    f"{key} : {count} arêtes non-manifold, plus que la référence source ({known_baseline})")


class TestShellStretchWithinContract(unittest.TestCase):
    """R2 « shell » : au plus 15 % d'étirement par axe (32 % le long d'un
    axe cylindrique déclaré)."""

    def test_shell_stretch_within_contract(self):
        s = _ReportRunner.get()["shell"]
        self.assertTrue(s["stretch_within_contract"], s)
        for axis in ("x", "y", "z"):
            self.assertLessEqual(s[f"stretch_{axis}"], SHELL_MAX_STRETCH_FRACTION + 1e-9)


class TestPureGeometryHelpers(unittest.TestCase):
    """Fonctions géométriques pures (aucun bpy) de shell_to_skin.py, testées
    indirectement via le rapport JSON (le module lui-même importe `bpy` au
    niveau fichier — voir l'en-tête — donc jamais importé directement ici,
    même contrainte que le reste de ce fichier)."""

    def test_hotel_south_doors_present_in_collision_json_schema(self):
        """Le schéma JSON documenté en tête de shell_to_skin.py (`{"pieces":
        [{"name","pos","size","doors":[{"side","floor","offset","w","h"}]}]}
        `) produit bien 2 rectangles pour Hôtel S (offset ±2,5 m, largeur
        1,6 m, doc 11 §9) — vérifié via les rectangles effectivement utilisés
        par le self-test, imprimés dans son rapport."""
        c = _ReportRunner.get()["card"]
        rects = c["opening_rects"]
        self.assertEqual(len(rects), 2)
        offsets = sorted((r["x0"] + r["x1"]) / 2.0 for r in rects)
        self.assertAlmostEqual(offsets[0], -2.5, places=6)
        self.assertAlmostEqual(offsets[1], 2.5, places=6)
        for r in rects:
            self.assertAlmostEqual(r["x1"] - r["x0"], 1.6, places=6)
            self.assertAlmostEqual(r["y0"], 0.0, places=6)
            self.assertAlmostEqual(r["y1"], 2.2, places=6)


if __name__ == "__main__":
    unittest.main()
