#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/blender/tests/test_make_stylized_rocks.py
Tests de tools/blender/make_stylized_rocks.py (TOOL-02, refonte TOOL-02B).
Ce generateur importe `bpy` : indisponible hors du process Blender, donc ce
fichier ne l'importe JAMAIS directement — il relance Blender EN SOUS-PROCESS
(une seule fois, cout du lancement amorti sur tous les cas) sur le generateur
lui-meme, en mode `--selftest-json` (voir son en-tete) : il construit les 12
pieces, les fait peindre (strates projetees + paint_bake.py), exporte chaque
.glb + sidecar JSON reel dans assets/models/props/wasteland/rocks/, les fait
verifier par `check_asset.py` (importe en process, budget par famille du
contrat TOOL-02), ecrit un manifest.json et imprime
`STYLIZED_ROCKS_SELFTEST_RESULT <json>`. Chaque `test_*` ci-dessous relit ce
resultat deja calcule et fait une assertion normale dessus (jamais de second
lancement Blender par test).

TOOL-02B (contrat du 2026-09-25) remplace la matiere "une couleur par slot
base/accent/cap" et les tours a 8-10 bandes geometriques de la v1 par UNE
texture peinte de strates projetee en boite (1 tuile = 2 m, strates toujours
horizontales, dessus en sable clair) puis cuite par paint_bake.py, et par des
massifs a 3-5 terrasses. Les anciens cas TestStrataLegibility (contraste
base/accent/cap, >= 8 bandes) decrivaient donc un contrat caduc : ils sont
remplaces par TestPaintedStrataMaterial / TestTerracedMassifs, qui verifient
les criteres TOOL-02B. Les cas toujours valides de la v1 (12 pieces,
repartition, check_asset PASS litteral, budgets, tailles, pas de blob,
raccord du canyon, canyon sans biseau) sont conserves tels quels.

Blender : `BLENDER_BIN` (variable d'environnement) sinon le chemin connu de
CLAUDE.md.

Lancer :
    python -m pytest tools/blender/tests/test_make_stylized_rocks.py -q
    (ou, sans pytest : python tools/blender/tests/test_make_stylized_rocks.py)

Une seule piece, pendant l'iteration (ne passe PAS par ce fichier de test,
mais par le generateur directement, voir son en-tete) :
    blender -b -P tools/blender/make_stylized_rocks.py -- --only rock_01 --out-dir DOSSIER
"""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
GENERATOR_SCRIPT = os.path.join(HERE, os.pardir, "make_stylized_rocks.py")

EXPECTED_CATEGORY_COUNTS = {"rock": 6, "cliff": 3, "mesa": 2, "canyon_edge": 1}
BUDGET_TRIS = {"rock": 800, "cliff": 3000, "mesa": 2000, "canyon_edge": 3000}
# Plage de taille par famille (m), critere d'acceptation TOOL-02 : verifiee
# sur la plus grande dimension de la bbox (le contrat ne precise pas l'axe).
SIZE_RANGE_M = {
    "rock": (0.3, 2.0),
    "cliff": (4.0, 10.0),
    "mesa": (30.0, 60.0),
}
# Matiere TOOL-02B : texture de strates imposee, projetee a 1 tuile = 2 m.
STRATA_TEXTURE = "assets/textures/wasteland/wl_rock_strata_albedo.png"
STRATA_TILE_M = 2.0
# Rochers TOOL-02B : "6-10 coupes planes", "biseau 1 segment de 2-4 cm".
ROCK_MAIN_CUTS_RANGE = (6, 10)
ROCK_BEVEL_RANGE_M = (0.02, 0.04)
# "aucune silhouette ovoide" : les grandes facettes planes (>= 3 % de l'aire
# chacune) couvrent au moins 60 % de la surface d'un rocher. Une icosphere
# subdiv 2 etiree (un oeuf) n'a que des faces de ~1,25 % : 0 %.
ROCK_MIN_LARGE_FACET_AREA_RATIO = 0.6
# "jamais de symetrie radiale visible" : empreinte au sol allongee.
ROCK_MIN_FOOTPRINT_ASPECT = 1.15
# Falaises/mesas TOOL-02B : "contour 2D irregulier (12-24 sommets ...) pas un
# cercle", "3-5 terrasses".
OUTLINE_VERTEX_RANGE = (12, 24)
TERRACE_RANGE = (3, 5)
MASSIF_MIN_OUTLINE_ASPECT = 1.2
# "planche de controle avec la texture VISIBLE" : la texture cuite n'est pas
# un aplat, reste dans les teintes chaudes de la roche et du sable, sans
# pixel dans les bandes reservees (surbrillance ennemie/alliee), et sa
# luminance moyenne reste proche de celle de la texture source (ni boue
# sombre, ni delavee).
MIN_ALBEDO_LUMA_STD = 0.05
WARM_HUE_RANGE_DEG = (10.0, 50.0)
MAX_RESERVED_HUE_FRACTION = 0.001
ALBEDO_TO_SOURCE_LUMA_RANGE = (0.75, 1.35)
# « aucune silhouette [...] cylindrique empilee », applique aux contreforts de
# la paroi de canyon (retour du verificateur TOOL-02B : colonnes quasi
# cylindriques sur canyon_edge_01, _captures/canyon_edge_01/view_04.png). La
# section horizontale de chaque volume de contrefort, mesuree a plusieurs
# hauteurs par le generateur (sommets quasi alignes fusionnes = une facette) :
#   - au moins 60 % de son virage total est porte par des aretes FRANCHES :
#     virage >= 46 deg, le seuil d'encrage des plis de la planche de controle
#     (turntable.py, Freestyle crease_angle 134 deg). Un polygone quasi
#     regulier de 10-14 sommets (virages de 26-36 deg partout, aucun pli
#     encre) - un cylindre - en a 0 % ;
#   - sa plus grande facette cote canyon (devant la paroi) couvre au moins
#     1/5 du pourtour visible : quelques grandes coupes planes, pas une
#     demi-couronne de 6-7 petites faces (1/6-1/7 chacune).
BUTTRESS_MIN_SHARP_TURN_SHARE = 0.6
BUTTRESS_MIN_FRONT_FACE_SHARE = 0.2
BUTTRESS_MIN_SECTIONS_PER_VOLUME = 2


def _blender_bin() -> str:
    env = os.environ.get("BLENDER_BIN")
    if env:
        return env
    # Chemin connu de ce poste (CLAUDE.md du depot) — repli seulement si
    # BLENDER_BIN n'est pas defini, jamais suppose sur une autre machine.
    return r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"


def _code_lines() -> str:
    """Source du generateur sans les lignes de commentaire (l'en-tete nomme
    expressement ce qui n'est PAS utilise)."""
    with open(GENERATOR_SCRIPT, "r", encoding="utf-8") as f:
        return "".join(ln for ln in f if not ln.lstrip().startswith("#"))


class _ReportRunner:
    """Lance le generateur UNE fois pour toute la session de test et garde le
    resultat JSON en cache — un test qui a besoin du rapport avant qu'il ait
    ete calcule (Blender introuvable, plantage avant meme d'imprimer le
    marqueur) echoue avec le stdout/stderr complet plutot qu'un KeyError
    opaque."""
    _result = None
    _raw_output = None

    @classmethod
    def get(cls) -> dict:
        if cls._result is None:
            blender_bin = _blender_bin()
            if not os.path.isfile(blender_bin):
                raise unittest.SkipTest(
                    f"Blender introuvable ({blender_bin!r}) — definir BLENDER_BIN pour lancer "
                    "tools/blender/tests/test_make_stylized_rocks.py")
            out_path = os.path.join(tempfile.mkdtemp(prefix="stylized_rocks_test_"), "report.json")
            cmd = [
                blender_bin, "-b", "--factory-startup", "--python-exit-code", "1",
                "-P", GENERATOR_SCRIPT, "--", "--selftest-json", out_path,
            ]
            # 12 pieces x (geometrie + paint_bake.py en sous-process + cuisson
            # de composition) : plusieurs minutes, d'ou la marge.
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=2400)
            cls._raw_output = proc.stdout + "\n--- stderr ---\n" + proc.stderr
            if proc.returncode != 0:
                raise AssertionError(
                    f"make_stylized_rocks.py a plante (code {proc.returncode}) avant d'imprimer son "
                    f"resultat :\n{cls._raw_output[-6000:]}")
            marker = "STYLIZED_ROCKS_SELFTEST_RESULT "
            line = next((ln for ln in proc.stdout.splitlines() if ln.startswith(marker)), None)
            if line is None:
                raise AssertionError(f"pas de marqueur {marker!r} dans la sortie :\n{cls._raw_output[-6000:]}")
            cls._result = json.loads(line[len(marker):])
        return cls._result

    @classmethod
    def piece(cls, name: str) -> dict:
        report = cls.get()
        by_name = {p["name"]: p for p in report["pieces"]}
        if name not in by_name:
            raise AssertionError(f"piece {name!r} absente du rapport : {sorted(by_name)}")
        return by_name[name]

    @classmethod
    def pieces_of(cls, category: str) -> list:
        report = cls.get()
        return [p for p in report["pieces"] if p["category"] == category]

    @classmethod
    def massifs(cls) -> list:
        return cls.pieces_of("cliff") + cls.pieces_of("mesa")


class TestPieceCountAndOverallResult(unittest.TestCase):
    """Critere d'acceptation : 12 .glb + sidecars, check_asset PASS partout."""

    def test_overall_ok(self):
        report = _ReportRunner.get()
        self.assertTrue(report["ok"], report["failures"])

    def test_exactly_12_pieces(self):
        report = _ReportRunner.get()
        self.assertEqual(report["piece_count"], 12)
        self.assertEqual(len(report["pieces"]), 12)

    def test_category_counts_match_contract(self):
        report = _ReportRunner.get()
        self.assertEqual(report["category_counts"], EXPECTED_CATEGORY_COUNTS)

    def test_every_piece_glb_and_sidecar_exist_on_disk(self):
        report = _ReportRunner.get()
        for p in report["pieces"]:
            with self.subTest(piece=p["name"]):
                self.assertTrue(os.path.isfile(p["path"]), p["path"])
                sidecar = os.path.splitext(p["path"])[0] + ".json"
                self.assertTrue(os.path.isfile(sidecar), sidecar)

    def test_every_piece_passes_check_asset_literally(self):
        """Aucune exception CHK-16 a suivre ici : `check_asset_ok` doit etre
        un PASS litteral et non filtre pour toutes les pieces."""
        report = _ReportRunner.get()
        failing = [(p["name"], p["check_asset_failures"]) for p in report["pieces"] if not p["check_asset_ok"]]
        self.assertEqual(failing, [], f"check_asset ECHEC sur : {failing}")

    def test_every_piece_within_its_category_budget(self):
        report = _ReportRunner.get()
        over_budget = [(p["name"], p["tris"], p["budget_tris"])
            for p in report["pieces"] if p["tris"] > p["budget_tris"]]
        self.assertEqual(over_budget, [], f"budget de triangles depasse : {over_budget}")

    def test_budgets_match_contract_notes(self):
        report = _ReportRunner.get()
        self.assertEqual(report["budgets_tris"], BUDGET_TRIS)


class TestPieceSizesWithinContractRanges(unittest.TestCase):
    """« 6 rochers (0,3-2 m), 3 blocs de falaise (4-10 m), 2 mesas lointaines
    (30-60 m) » — verifie sur la plus grande dimension de la bbox exportee."""

    def _assert_category_sizes(self, category: str):
        lo, hi = SIZE_RANGE_M[category]
        for p in _ReportRunner.pieces_of(category):
            with self.subTest(piece=p["name"]):
                max_dim = max(p["dims_m"])
                self.assertGreaterEqual(max_dim, lo, f"{p['name']}: {max_dim} m < {lo} m")
                self.assertLessEqual(max_dim, hi, f"{p['name']}: {max_dim} m > {hi} m")

    def test_rocks_within_0_3_to_2_m(self):
        self._assert_category_sizes("rock")

    def test_cliffs_within_4_to_10_m(self):
        self._assert_category_sizes("cliff")

    def test_mesas_within_30_to_60_m(self):
        self._assert_category_sizes("mesa")

    def test_rock_sizes_are_spread_across_the_range_not_clustered(self):
        """« 6 rochers » doit lire comme une VARIETE de tailles, pas 6 copies
        proches du meme gabarit."""
        maxes = sorted(max(p["dims_m"]) for p in _ReportRunner.pieces_of("rock"))
        self.assertGreater(maxes[-1] - maxes[0], 1.0, maxes)


class TestNoOrganicSoftNoise(unittest.TestCase):
    """« formes facettees "taillees a la serpe" (pas de bruit organique
    mou) » : jamais toonkit.blob() (icosphere + SUBSURF + DISPLACE CLOUDS),
    jamais de subdivision lissante."""

    def test_generator_source_never_calls_toonkit_blob(self):
        code = _code_lines()
        self.assertNotIn("toonkit.blob(", code)
        self.assertNotIn(".blob(", code)

    def test_generator_source_never_adds_a_subsurf_modifier(self):
        self.assertNotIn("SUBSURF", _code_lines())


class TestPaintedStrataMaterial(unittest.TestCase):
    """MATIERE TOOL-02B : la texture peinte de strates projetee en boite a
    l'echelle du monde (1 tuile = 2 m), strates TOUJOURS horizontales et
    continues d'une facette a l'autre, dessus en sable clair, puis
    paint_bake.py par-dessus ; planche avec la texture VISIBLE."""

    def test_report_declares_the_imposed_strata_texture_and_scale(self):
        report = _ReportRunner.get()
        self.assertEqual(report["strata_texture"], STRATA_TEXTURE)
        self.assertEqual(report["strata_tile_m"], STRATA_TILE_M)

    def test_painter_projects_at_one_tile_per_2_m(self):
        """Echelle de la projection en boite de paint_bake.py, lue dans le
        module par le generateur au moment de la cuisson."""
        report = _ReportRunner.get()
        self.assertAlmostEqual(report["painter_world_uv_scale"], 1.0 / STRATA_TILE_M, places=9)

    def test_painter_baked_the_strata_texture_on_every_piece(self):
        """Le slot des strates a ete cuit par paint_bake.py avec la texture
        imposee comme base (et non une couleur ou une autre texture)."""
        report = _ReportRunner.get()
        for p in report["pieces"]:
            with self.subTest(piece=p["name"]):
                strata = [s for s in p["painter_slots"] if s["original_material"] == report["strata_slot"]]
                self.assertEqual(len(strata), 1, p["painter_slots"])
                self.assertEqual(strata[0]["base_mode"], "texture")
                self.assertEqual(strata[0]["base_texture"], STRATA_TEXTURE)

    def test_every_piece_has_one_painted_material_and_uvs(self):
        """Materiau unique "<id>_painted" (texture cuite, reconnu cote jeu
        par Cartoon.painted_texture_prop) relu dans le .glb par check_asset."""
        for p in _ReportRunner.get()["pieces"]:
            with self.subTest(piece=p["name"]):
                self.assertEqual(p["materials"], [f"{p['name']}_painted"])
                self.assertTrue(p["uv_present"])

    def test_every_sidecar_declares_the_painted_strata_texture(self):
        for p in _ReportRunner.get()["pieces"]:
            with self.subTest(piece=p["name"]):
                sidecar = os.path.splitext(p["path"])[0] + ".json"
                with open(sidecar, "r", encoding="utf-8") as f:
                    data = json.load(f)
                self.assertTrue(data.get("painted"))
                self.assertEqual(data.get("strata_texture"), STRATA_TEXTURE)
                self.assertEqual(data.get("strata_tile_m"), STRATA_TILE_M)
                self.assertEqual(data.get("material"), f"{p['name']}_painted")

    def test_strata_are_horizontal_and_continuous_on_every_facet(self):
        """En projection en boite, une face projetee par un cote lit
        v = z / 2 m : une rangee de strates = une hauteur, identique sur deux
        facettes voisines. TOUTE face de strates (hors dessous de surplomb,
        ou l'horizontale n'a pas de sens) doit donc etre projetee par un
        cote - aucune par le haut, ou les strates tourneraient."""
        for p in _ReportRunner.get()["pieces"]:
            with self.subTest(piece=p["name"]):
                self.assertEqual(p["strata_side_projected_ratio"], 1.0)

    def test_terraced_pieces_have_sand_tops(self):
        for p in _ReportRunner.massifs() + _ReportRunner.pieces_of("canyon_edge"):
            with self.subTest(piece=p["name"]):
                self.assertGreater(p["sand_top_area_m2"], 0.0)

    def test_baked_texture_is_visible_not_a_flat_fill(self):
        for p in _ReportRunner.get()["pieces"]:
            with self.subTest(piece=p["name"]):
                self.assertGreaterEqual(p["albedo_luma_std"], MIN_ALBEDO_LUMA_STD, p["albedo_luma_std"])

    def test_baked_texture_keeps_warm_rock_hues(self):
        lo, hi = WARM_HUE_RANGE_DEG
        for p in _ReportRunner.get()["pieces"]:
            with self.subTest(piece=p["name"]):
                self.assertGreaterEqual(p["albedo_median_hue_deg"], lo)
                self.assertLessEqual(p["albedo_median_hue_deg"], hi)

    def test_baked_texture_has_no_reserved_hue_pixels(self):
        for p in _ReportRunner.get()["pieces"]:
            with self.subTest(piece=p["name"]):
                self.assertLessEqual(p["albedo_reserved_hue_fraction"], MAX_RESERVED_HUE_FRACTION)

    def test_baked_texture_luminance_stays_close_to_the_source_texture(self):
        lo, hi = ALBEDO_TO_SOURCE_LUMA_RANGE
        for p in _ReportRunner.get()["pieces"]:
            with self.subTest(piece=p["name"]):
                ratio = p["albedo_mean_luma"] / p["strata_source_mean_luma"]
                self.assertGreaterEqual(ratio, lo, f"{p['name']}: {ratio:.3f}")
                self.assertLessEqual(ratio, hi, f"{p['name']}: {ratio:.3f}")


class TestRocksCutWithPlanes(unittest.TestCase):
    """ROCHERS TOOL-02B : icosphere subdiv 2 etiree, 6-10 coupes planes, 2e
    passe de petites coupes, biseau 1 segment de 2-4 cm ; aucune silhouette
    ovoide, jamais de symetrie radiale visible."""

    def test_rocks_start_from_an_icosphere_subdiv_2(self):
        for p in _ReportRunner.pieces_of("rock"):
            with self.subTest(piece=p["name"]):
                self.assertEqual(p["icosphere_subdivisions"], 2)

    def test_generator_cuts_with_plane_bisection(self):
        code = _code_lines()
        self.assertIn("create_icosphere(", code)
        self.assertIn("bisect_plane(", code)
        self.assertIn("clear_outer=True", code)

    def test_main_plane_cuts_between_6_and_10(self):
        lo, hi = ROCK_MAIN_CUTS_RANGE
        for p in _ReportRunner.pieces_of("rock"):
            with self.subTest(piece=p["name"]):
                self.assertGreaterEqual(p["main_plane_cuts"], lo)
                self.assertLessEqual(p["main_plane_cuts"], hi)

    def test_second_pass_of_small_cuts(self):
        for p in _ReportRunner.pieces_of("rock"):
            with self.subTest(piece=p["name"]):
                self.assertGreaterEqual(p["detail_plane_cuts"], 2)

    def test_bevel_is_2_to_4_cm(self):
        lo, hi = ROCK_BEVEL_RANGE_M
        for p in _ReportRunner.pieces_of("rock"):
            with self.subTest(piece=p["name"]):
                self.assertGreaterEqual(p["bevel_width_m"], lo)
                self.assertLessEqual(p["bevel_width_m"], hi)

    def test_large_planar_facets_not_an_egg(self):
        for p in _ReportRunner.pieces_of("rock"):
            with self.subTest(piece=p["name"]):
                self.assertGreaterEqual(p["large_facet_area_ratio"], ROCK_MIN_LARGE_FACET_AREA_RATIO,
                    p["large_facet_area_ratio"])

    def test_footprint_not_radially_symmetric(self):
        for p in _ReportRunner.pieces_of("rock"):
            with self.subTest(piece=p["name"]):
                self.assertGreaterEqual(p["footprint_aspect"], ROCK_MIN_FOOTPRINT_ASPECT, p["footprint_aspect"])


class TestTerracedMassifs(unittest.TestCase):
    """FALAISES / MESAS TOOL-02B : contour 2D irregulier (12-24 sommets, pas
    un cercle) extrude en 3-5 terrasses avec retraits/avancees differents par
    terrasse, rainures verticales, blocs eboules au pied, dessus plat avec
    levre."""

    def test_three_to_five_terraces(self):
        lo, hi = TERRACE_RANGE
        for p in _ReportRunner.massifs():
            with self.subTest(piece=p["name"]):
                self.assertGreaterEqual(p["terrace_count"], lo)
                self.assertLessEqual(p["terrace_count"], hi)

    def test_every_outline_has_12_to_24_vertices(self):
        lo, hi = OUTLINE_VERTEX_RANGE
        for p in _ReportRunner.massifs():
            with self.subTest(piece=p["name"]):
                for count in p["outline_vertex_counts"]:
                    self.assertGreaterEqual(count, lo, p["outline_vertex_counts"])
                    self.assertLessEqual(count, hi, p["outline_vertex_counts"])

    def test_outline_is_not_a_circle(self):
        for p in _ReportRunner.massifs():
            with self.subTest(piece=p["name"]):
                self.assertGreaterEqual(p["outline_aspect"], MASSIF_MIN_OUTLINE_ASPECT, p["outline_aspect"])

    def test_terraces_retreat_and_advance_by_different_amounts(self):
        """Pas une pile de crepes : les decalages de terrasse a terrasse
        different (ecart >= 2 % de la plus grande dimension) et comprennent au
        moins un retrait (corniche) et une avancee (surplomb/levre)."""
        for p in _ReportRunner.massifs():
            with self.subTest(piece=p["name"]):
                offsets = p["terrace_offsets_m"]
                self.assertGreaterEqual(max(offsets) - min(offsets), 0.02 * max(p["dims_m"]), offsets)
                self.assertTrue(any(o > 0.0 for o in offsets), offsets)
                self.assertTrue(any(o < 0.0 for o in offsets), offsets)

    def test_vertical_grooves_and_fallen_blocks(self):
        for p in _ReportRunner.massifs():
            with self.subTest(piece=p["name"]):
                self.assertGreaterEqual(p["groove_count"], 2)
                self.assertGreaterEqual(p["fallen_block_count"], 3)

    def test_flat_top_with_a_lip(self):
        for p in _ReportRunner.massifs():
            with self.subTest(piece=p["name"]):
                self.assertGreater(p["flat_top_area_m2"], 0.0)
                self.assertGreater(p["top_lip_overhang_m"], 0.0)


class TestCanyonEdgeIsConnectable(unittest.TestCase):
    """« PAROI DE CANYON = mur long extrude dont la face est taillee par
    coupes planes et terrasses, raccordable aux deux bouts » — le raccord est
    verifie geometriquement sur la geometrie finale exportee (voir
    make_stylized_rocks.py::canyon_seam_delta), pas seulement suppose par
    construction."""

    def test_exactly_one_canyon_edge_module(self):
        pieces = _ReportRunner.pieces_of("canyon_edge")
        self.assertEqual(len(pieces), 1, pieces)

    def test_seam_matches_within_submillimeter_tolerance(self):
        p = _ReportRunner.piece("canyon_edge_01")
        self.assertIn("seam_max_delta_m", p)
        self.assertLess(p["seam_max_delta_m"], 1e-4, p["seam_max_delta_m"])

    def test_module_width_matches_its_own_length_field(self):
        """La largeur (axe de raccord, X) de la bbox exportee doit
        correspondre EXACTEMENT a `length_m` — sinon deux exemplaires poses
        cote a cote a `length_m` d'intervalle ne se toucheraient pas."""
        p = _ReportRunner.piece("canyon_edge_01")
        self.assertIn("length_m", p)
        # dims_m est (largeur X, profondeur Y, hauteur Z) en axes Blender
        # (Z-haut) : la largeur (axe de raccord X) est dims_m[0].
        self.assertAlmostEqual(p["dims_m"][0], p["length_m"], places=3)

    def test_canyon_edge_has_no_bevel_by_design(self):
        """Decision documentee (en-tete de make_stylized_rocks.py) : la paroi
        de canyon n'a jamais de biseau, pour ne jamais risquer d'introduire
        une asymetrie entre ses deux bouts. Le module importe bpy au niveau
        fichier (indisponible hors Blender) — on lit donc la constante
        directement dans le SOURCE."""
        with open(GENERATOR_SCRIPT, "r", encoding="utf-8") as f:
            src = f.read()
        self.assertIn('"canyon_edge": 0.0', src)

    def test_face_is_terraced_and_cut_by_planes(self):
        p = _ReportRunner.piece("canyon_edge_01")
        self.assertGreaterEqual(p["terrace_count"], 2)
        self.assertGreaterEqual(p["face_plane_cuts"], 3)


class TestCanyonButtressesAreFacetedNotColumns(unittest.TestCase):
    """« aucune silhouette ovoide ni cylindrique empilee » sur les contreforts
    de la paroi de canyon : chaque volume de contrefort est mesure en coupe
    horizontale a plusieurs hauteurs (`buttress_sections` du rapport) - aretes
    franches et grandes facettes cote canyon, jamais une colonne ronde."""

    def _sections(self) -> list:
        p = _ReportRunner.piece("canyon_edge_01")
        self.assertIn("buttress_sections", p)
        self.assertTrue(p["buttress_sections"], "aucune section de contrefort mesuree")
        return p["buttress_sections"]

    def test_every_buttress_volume_is_measured_at_several_heights(self):
        p = _ReportRunner.piece("canyon_edge_01")
        self.assertGreaterEqual(p["buttress_volume_count"], p["buttress_count"])
        per_volume = {}
        for s in self._sections():
            key = (s["buttress"], s["volume"])
            per_volume[key] = per_volume.get(key, 0) + 1
        self.assertEqual(len(per_volume), p["buttress_volume_count"], per_volume)
        for key, count in per_volume.items():
            with self.subTest(volume=key):
                self.assertGreaterEqual(count, BUTTRESS_MIN_SECTIONS_PER_VOLUME)

    def test_section_turning_is_carried_by_sharp_facet_edges(self):
        for s in self._sections():
            with self.subTest(buttress=s["buttress"], volume=s["volume"], z=s["z"]):
                self.assertGreaterEqual(s["sharp_turn_share"], BUTTRESS_MIN_SHARP_TURN_SHARE, s)

    def test_canyon_side_shows_large_cut_facets(self):
        for s in self._sections():
            with self.subTest(buttress=s["buttress"], volume=s["volume"], z=s["z"]):
                self.assertGreaterEqual(s["front_largest_face_share"], BUTTRESS_MIN_FRONT_FACE_SHARE, s)


if __name__ == "__main__":
    unittest.main()
