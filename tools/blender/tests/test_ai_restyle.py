#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/blender/tests/test_ai_restyle.py
Tests de tools/blender/ai_restyle.py (v2, A3D-12). `ai_restyle.py` importe
`bpy` : indisponible hors du process Blender, donc ce fichier n'importe
JAMAIS `ai_restyle` lui-meme — il relance Blender EN SOUS-PROCESS (une seule
fois, `setUpClass`, cout du lancement Blender amorti sur tous les cas) sur
`_ai_restyle_cases.py`, qui construit une fixture synthetique par critere
d'acceptation A3D-12 et imprime `AI_RESTYLE_CASES_RESULT <json>` en derniere
ligne de stdout ; chaque `test_*` ci-dessous relit ce resultat deja calcule et
fait une assertion normale dessus (jamais de nouveau lancement Blender par
test — rapide a l'iteration).

Blender : `BLENDER_BIN` (variable d'environnement, meme convention que
`GODOT_BIN` dans tools/test.sh) sinon le chemin connu de CLAUDE.md.

Lancer :
    python -m pytest tools/blender/tests/test_ai_restyle.py -q
    (ou, sans pytest : python tools/blender/tests/test_ai_restyle.py)
"""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
CASES_SCRIPT = os.path.join(HERE, "_ai_restyle_cases.py")


def _blender_bin() -> str:
	env = os.environ.get("BLENDER_BIN")
	if env:
		return env
	# Chemin connu de ce poste (CLAUDE.md du depot) — repli seulement si
	# BLENDER_BIN n'est pas defini, jamais suppose sur une autre machine.
	return r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"


class _CasesRunner:
	"""Lance `_ai_restyle_cases.py` UNE fois pour toute la classe de test et
	garde le resultat JSON en cache — un test qui demande un cas absent du
	resultat (Blender introuvable, plantage avant meme d'imprimer le marqueur)
	echoue avec le stdout/stderr complet plutot qu'un KeyError opaque."""
	_result = None
	_raw_output = None
	_out_dir = None

	@classmethod
	def get(cls) -> dict:
		if cls._result is None:
			cls._out_dir = tempfile.mkdtemp(prefix="ai_restyle_test_")
			blender_bin = _blender_bin()
			if not os.path.isfile(blender_bin):
				raise unittest.SkipTest(
					f"Blender introuvable ({blender_bin!r}) — definir BLENDER_BIN pour lancer "
					"tools/blender/tests/test_ai_restyle.py")
			cmd = [
				blender_bin, "-b", "--factory-startup", "--python-exit-code", "1",
				"-P", CASES_SCRIPT, "--", "--out-dir", cls._out_dir,
			]
			proc = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
			cls._raw_output = proc.stdout + "\n--- stderr ---\n" + proc.stderr
			if proc.returncode != 0:
				raise AssertionError(
					f"_ai_restyle_cases.py a plante (code {proc.returncode}) avant d'imprimer son "
					f"resultat :\n{cls._raw_output}")
			marker = "AI_RESTYLE_CASES_RESULT "
			line = next((ln for ln in proc.stdout.splitlines() if ln.startswith(marker)), None)
			if line is None:
				raise AssertionError(f"pas de marqueur {marker!r} dans la sortie :\n{cls._raw_output}")
			cls._result = json.loads(line[len(marker):])["cases"]
		return cls._result

	@classmethod
	def case(cls, name: str) -> dict:
		results = cls.get()
		if name not in results:
			raise AssertionError(f"cas {name!r} absent du resultat : {sorted(results)}")
		return results[name]


class TestFaceQuantizationPerFace(unittest.TestCase):
	"""Quantification Lab PAR FACE (A3D-12) : un SEUL materiau texture Tripo
	d'entree, plusieurs couleurs de piece -> plusieurs kinds de sortie —
	jamais un seul kind moyen pour tout l'objet (comportement A3D-07)."""

	def test_case_passes(self):
		result = _CasesRunner.case("face_quantization_unit")
		self.assertTrue(result["ok"], result.get("error"))

	def test_four_distinct_kinds_from_one_material(self):
		result = _CasesRunner.case("face_quantization_unit")
		self.assertTrue(result["ok"], result.get("error"))
		out_kinds = result["detail"]["out_kinds"]
		self.assertEqual(out_kinds, sorted(["wood_planks", "rust", "painted_metal", "dirty_glass"]))

	def test_face_counts_per_kind_match_fixture(self):
		result = _CasesRunner.case("face_quantization_unit")
		self.assertTrue(result["ok"], result.get("error"))
		counts = {s["assigned_kind"]: s["face_count"] for s in result["detail"]["report_slots"]}
		self.assertEqual(counts, {"wood_planks": 2, "rust": 2, "painted_metal": 1, "dirty_glass": 1})


class TestFullPipelineNoImagesColor0CheckAsset(unittest.TestCase):
	"""Critere d'acceptation #1 : sur un GLB Tripo texture (simule), chaque
	face recoit un slot connu de Cartoon, aucune image ne survit, COLOR_0 est
	present, et check_asset.py PASSE (budget de la famille)."""

	def test_case_passes(self):
		result = _CasesRunner.case("full_pipeline_no_images_color0_check_asset")
		self.assertTrue(result["ok"], result.get("error"))

	def test_assigned_kinds_are_known_and_outside_reserved_bands(self):
		result = _CasesRunner.case("full_pipeline_no_images_color0_check_asset")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertEqual(
			sorted(result["detail"]["assigned_kinds"]),
			sorted(["wood_planks", "rust", "painted_metal", "dirty_glass"]))

	def test_color0_present(self):
		result = _CasesRunner.case("full_pipeline_no_images_color0_check_asset")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertTrue(result["detail"]["color0_present"])

	def test_check_asset_passes(self):
		result = _CasesRunner.case("full_pipeline_no_images_color0_check_asset")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertTrue(result["detail"]["check_asset_ok"], result["detail"]["check_asset_failures"])


class TestWeaponPartsAndMarkers(unittest.TestCase):
	"""Critere d'acceptation #2 : sur une arme de test, les pieces declarees
	(ici « magazine ») sortent en noeuds separes sans trou visible, et le
	noeud Muzzle existe (meme convention que ViewModel.gd/make_weapons.py)."""

	def test_case_passes(self):
		result = _CasesRunner.case("weapon_parts_and_markers")
		self.assertTrue(result["ok"], result.get("error"))

	def test_magazine_is_a_separate_mesh_node(self):
		result = _CasesRunner.case("weapon_parts_and_markers")
		self.assertTrue(result["ok"], result.get("error"))
		mesh_nodes = result["detail"]["nodes_by_type"].get("MESH", [])
		self.assertIn("magazine", mesh_nodes)
		self.assertEqual(len(mesh_nodes), 2, mesh_nodes)  # corps + chargeur, jamais fondus

	def test_muzzle_and_foregrip_markers_exist(self):
		result = _CasesRunner.case("weapon_parts_and_markers")
		self.assertTrue(result["ok"], result.get("error"))
		empties = result["detail"]["nodes_by_type"].get("EMPTY", [])
		self.assertIn("Muzzle", empties)
		self.assertIn("Foregrip", empties)

	def test_no_visible_hole_after_separation(self):
		result = _CasesRunner.case("weapon_parts_and_markers")
		self.assertTrue(result["ok"], result.get("error"))
		boundary_edges = result["detail"]["boundary_edges"]
		self.assertTrue(boundary_edges, "aucun objet mesh mesure")
		for name, n_boundary in boundary_edges.items():
			self.assertEqual(n_boundary, 0, f"{name} a {n_boundary} arete(s) de bord ouvert (trou visible)")

	def test_check_asset_passes_on_separated_weapon(self):
		result = _CasesRunner.case("weapon_parts_and_markers")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertTrue(result["detail"]["check_asset_ok"])


class TestCurvedPartSeparationStaysManifold(unittest.TestCase):
	"""Critere d'acceptation A3D-15 : separer une piece decoupee dans une
	surface COURBE (contour de coupe non planaire, plusieurs boucles de bord
	a la fois — releve concret vague 1 : wpn_magnum barillet/chien,
	wpn_marqueur capuchon, wpn_pistolet chargeur/culasse) ne doit laisser NI
	trou NI arete non-manifold apres reboucher+trianguler."""

	def test_case_passes(self):
		result = _CasesRunner.case("curved_part_separation_stays_manifold")
		self.assertTrue(result["ok"], result.get("error"))

	def test_no_holes_after_separation(self):
		result = _CasesRunner.case("curved_part_separation_stays_manifold")
		self.assertTrue(result["ok"], result.get("error"))
		boundary = result["detail"]["boundary_edges"]
		self.assertTrue(boundary, "aucun objet mesh mesure")
		for name, n in boundary.items():
			self.assertEqual(n, 0, f"{name} a {n} arete(s) de bord ouvert (trou visible)")

	def test_no_nonmanifold_edges_after_separation(self):
		result = _CasesRunner.case("curved_part_separation_stays_manifold")
		self.assertTrue(result["ok"], result.get("error"))
		nonmanifold = result["detail"]["nonmanifold_edges"]
		self.assertTrue(nonmanifold, "aucun objet mesh mesure")
		for name, n in nonmanifold.items():
			self.assertEqual(n, 0, f"{name} a {n} arete(s) non-manifold apres reboucher+trianguler")

	def test_check_asset_passes(self):
		result = _CasesRunner.case("curved_part_separation_stays_manifold")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertTrue(result["detail"]["check_asset_ok"])


class TestVolumeLossGuard(unittest.TestCase):
	"""Critere d'acceptation #3 : le garde-fou explicite sur le VOLUME clos
	(A3D-12) rejette toute tentative qui perd plus de 10 % du volume, et
	accepte celles qui restent en dessous — teste isolement (fonction pure)
	ET bout en bout (caisse trouee reelle, voir TestHollowCrateEndToEnd)."""

	def test_case_passes(self):
		result = _CasesRunner.case("volume_guard_unit")
		self.assertTrue(result["ok"], result.get("error"))

	def test_more_than_ten_percent_loss_is_rejected(self):
		result = _CasesRunner.case("volume_guard_unit")
		self.assertTrue(result["ok"], result.get("error"))
		detail = result["detail"]
		self.assertGreater(detail["loss_reject"], 0.10)
		self.assertFalse(detail["rejected"])

	def test_under_ten_percent_loss_is_accepted(self):
		result = _CasesRunner.case("volume_guard_unit")
		self.assertTrue(result["ok"], result.get("error"))
		detail = result["detail"]
		self.assertLess(detail["loss_accept"], 0.10)
		self.assertTrue(detail["accepted"])


class TestHollowCrateWatertightWarning(unittest.TestCase):
	"""Critere d'acceptation A3D-15 : une caisse trouee reelle (grand trou +
	debris deja etanche distant, le mode de defaillance documente de
	`_voxel_remesh`) ne doit PLUS faire lever `ensure_watertight` — le
	watertight est un AVERTISSEMENT (`remesh_failed=True`), le maillage
	D'ORIGINE (toujours troue) reste conserve tel quel, jamais un blocage dur
	sur un maillage par ailleurs propre/bas-poly (releve A3D-13)."""

	def test_case_passes(self):
		result = _CasesRunner.case("hollow_crate_watertight_warning")
		self.assertTrue(result["ok"], result.get("error"))

	def test_ensure_watertight_does_not_raise_and_flags_remesh_failed(self):
		result = _CasesRunner.case("hollow_crate_watertight_warning")
		self.assertTrue(result["ok"], result.get("error"))
		fix = result["detail"]["watertight_fix"]
		self.assertTrue(fix["remesh_failed"])
		self.assertFalse(fix["remeshed"])
		self.assertIsNone(fix["collapsed_to"])
		self.assertEqual(fix["dropped_kinds"], [])

	def test_original_crate_geometry_preserved_only_distant_debris_dropped(self):
		result = _CasesRunner.case("hollow_crate_watertight_warning")
		self.assertTrue(result["ok"], result.get("error"))
		detail = result["detail"]
		dropped = detail["watertight_fix"]["dropped_disconnected_faces"]
		self.assertGreater(dropped, 0)
		self.assertEqual(detail["faces_after"], detail["faces_before"] - dropped)
		self.assertGreater(detail["volume_after"], detail["volume_before"] * 0.99)


class TestBudgetEnforcedAfterBevel(unittest.TestCase):
	"""Critere d'acceptation A3D-15 : le biseau (toonkit.apply_stylekit_shading)
	ajoute des triangles APRES la premiere passe de decimation — un maillage
	deja sous son budget avant le biseau (donc jamais decime a cette premiere
	passe) ne doit jamais ressortir au-dessus de ce budget une fois biseaute."""

	def test_case_passes(self):
		result = _CasesRunner.case("budget_enforced_after_bevel")
		self.assertTrue(result["ok"], result.get("error"))

	def test_final_tris_within_budget(self):
		result = _CasesRunner.case("budget_enforced_after_bevel")
		self.assertTrue(result["ok"], result.get("error"))
		detail = result["detail"]
		self.assertLessEqual(detail["final_tris"], detail["budget"])

	def test_check_asset_passes(self):
		result = _CasesRunner.case("budget_enforced_after_bevel")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertTrue(result["detail"]["check_asset_ok"])


class TestMultiPartChainSurvivesIslandCleanup(unittest.TestCase):
	"""Critere d'acceptation A3D-15 : un assemblage a plusieurs ilots
	topologiquement disjoints en CHAINE (jamais ressoudes par
	merge_by_distance, comme un mat/une cabine/une fleche de grue IA generes
	en pieces separees — releve concret vague 1 : wl_oil_derrick,
	wl_crane_lattice, cs_deck_crane, cs_ship_mast) doit survivre ENTIER a
	`remove_isolated_islands` (regroupement TRANSITIF par proximite, pas une
	simple comparaison au plus gros ilot) ; seul un vrai fragment distant
	doit etre retire."""

	def test_case_passes(self):
		result = _CasesRunner.case("multi_part_chain_survives_island_cleanup")
		self.assertTrue(result["ok"], result.get("error"))

	def test_only_distant_debris_removed(self):
		result = _CasesRunner.case("multi_part_chain_survives_island_cleanup")
		self.assertTrue(result["ok"], result.get("error"))
		detail = result["detail"]
		self.assertEqual(detail["removed"], 6)
		self.assertEqual(detail["faces_after"], detail["faces_before"] - detail["removed"])

	def test_chain_extremities_preserved(self):
		result = _CasesRunner.case("multi_part_chain_survives_island_cleanup")
		self.assertTrue(result["ok"], result.get("error"))
		detail = result["detail"]
		self.assertLess(detail["z_min"], 0.01, "l'ilot A (base de la chaine) a disparu a tort")
		self.assertGreater(detail["z_max"], 3.0, "l'ilot C (sommet de la chaine) a disparu a tort")
		self.assertFalse(detail["debris_survives"])


class TestTwoKindRemeshPreservesMaterials(unittest.TestCase):
	"""Critere d'acceptation A3D-15 : un remesh ACCEPTE sur un objet a
	PLUSIEURS kinds (limitation documentee du Remesh Voxel : reinitialise
	material_index a 0 sur toutes ses faces) ne doit plus collapser tout
	l'objet vers un seul kind dominant — chaque region doit garder son kind
	d'origine par reaffectation au plus proche voisin (releve concret vague 1 :
	cs_container_20/40, cs_lifeboat_davits, gp_bomb, gp_borne, wl_water_tower,
	wpn_eclair/fracas/rafale/ravage/semeuse, tous amputes a un seul kind par
	l'ancien collapse)."""

	def test_case_passes(self):
		result = _CasesRunner.case("two_kind_remesh_preserves_materials")
		self.assertTrue(result["ok"], result.get("error"))

	def test_remesh_accepted_nothing_collapsed_or_dropped(self):
		result = _CasesRunner.case("two_kind_remesh_preserves_materials")
		self.assertTrue(result["ok"], result.get("error"))
		fix = result["detail"]["watertight_fix"]
		self.assertTrue(fix["remeshed"])
		self.assertFalse(fix["remesh_failed"])
		self.assertIsNone(fix["collapsed_to"])
		self.assertEqual(fix["dropped_kinds"], [])

	def test_both_kinds_survive_in_their_own_region(self):
		result = _CasesRunner.case("two_kind_remesh_preserves_materials")
		self.assertTrue(result["ok"], result.get("error"))
		detail = result["detail"]
		self.assertEqual(detail["out_kinds"], ["painted_metal", "wood_planks"])
		self.assertEqual(detail["left_kinds"], ["painted_metal"])
		self.assertEqual(detail["right_kinds"], ["wood_planks"])


class TestFinalNonmanifoldRepairUnit(unittest.TestCase):
	"""Critere d'acceptation A3D-15 : `_repair_nonmanifold_final` repare un
	PETIT nombre d'aretes non-manifold introduites APRES `_fill_holes` (biseau/
	seconde decimation — releve concret : wpn_fracas "pompe", wpn_percuteur
	"chien", wpn_pistolet "culasse"), mais laisse INTACT un objet qui en porte
	TROP (au-dela du plafond, ex. wl_crane_lattice) plutot que de mutiler sa
	silhouette."""

	def test_case_passes(self):
		result = _CasesRunner.case("final_nonmanifold_repair_unit")
		self.assertTrue(result["ok"], result.get("error"))

	def test_small_count_is_fully_repaired(self):
		result = _CasesRunner.case("final_nonmanifold_repair_unit")
		self.assertTrue(result["ok"], result.get("error"))
		detail = result["detail"]
		self.assertEqual(detail["bad_before_small"], 3)
		self.assertEqual(detail["bad_after_small"], 0)

	def test_over_cap_count_is_left_untouched(self):
		result = _CasesRunner.case("final_nonmanifold_repair_unit")
		self.assertTrue(result["ok"], result.get("error"))
		detail = result["detail"]
		self.assertEqual(detail["bad_after_big"], detail["bad_before_big"])
		self.assertIn("BigBad", detail["skipped_max_edges"])
		self.assertNotIn("SmallBad", detail["skipped_max_edges"])


if __name__ == "__main__":
	unittest.main()
