#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/blender/tests/test_paint_bake.py
Tests de tools/blender/paint_bake.py (TOOL-01 puis TOOL-01B, « peinture
automatique v2 ») et du correctif qui l'accompagne dans
tools/blender/turntable.py (`_find_albedo_image`).

Trois familles de cas, separees par leur dependance a Blender -- meme
convention que tools/blender/tests/test_ai_restyle.py /
test_ai_import_painted.py :

1. Fonctions PURES (`uv_margin_fraction`, `resolve_kind`, `output_material_
   name`, `island_hue_offset`, `hue01_from_offset_deg`, `reserved_band_
   violation`, `augment_sidecar`, et v2 : `canonical_kind`,
   `resolve_base_texture`, `srgb_luma`, `linear_gain_step`,
   `luma_within_tolerance`, `stroke_frequencies`, `island_value_offset`,
   `guard_reserved_hues`) -- AUCUNE ne touche `bpy` (voir l'en-tete de
   paint_bake.py : import dans un bloc try/except). Import direct du module,
   sans lancer Blender.

2. Pipeline bpy reel v1 (UV/iles/cuisson/materiau final/nettoyage des
   attributs de couleur, + le correctif turntable.py) -- relance Blender EN
   SOUS-PROCESS (une seule fois) : `_paint_bake_cases.py` construit une
   fixture synthetique PAR critere et imprime `PAINT_BAKE_CASES_RESULT
   <json>` en derniere ligne de stdout ; chaque `test_*` relit ce resultat.

3. Pipeline bpy reel v2 (TOOL-01B : base = texture peinte du kind projetee
   en boite, luminance recalee, liseres d'eclat nets et encre fine sur les
   aretes convexes, creux teintes, grain, variation par planche) -- CE
   fichier sert lui-meme de script Blender : `blender -b -P
   test_paint_bake.py -- --paint-bake-v2-cases --out-dir DIR` execute
   `_v2_cases_main()` (bas de fichier) et imprime `PAINT_BAKE_V2_RESULT
   <json>`. Les cas v2 vivent ici plutot que dans `_paint_bake_cases.py`
   parce que ce dernier n'appartient pas au perimetre de TOOL-01B (contrat de
   tache) ; il reste inchange et continue de verifier la v1.

Blender : `BLENDER_BIN` (variable d'environnement, meme convention que
`GODOT_BIN` dans tools/test.sh) sinon le chemin connu de CLAUDE.md.

Lancer :
    python -m pytest tools/blender/tests/test_paint_bake.py -q
    (ou, sans pytest : python tools/blender/tests/test_paint_bake.py)
"""
from __future__ import annotations

import colorsys
import json
import math
import os
import re
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_BLENDER = os.path.dirname(HERE)
REPO_ROOT = os.path.dirname(os.path.dirname(TOOLS_BLENDER))
CASES_SCRIPT = os.path.join(HERE, "_paint_bake_cases.py")
THIS_SCRIPT = os.path.abspath(__file__)
V2_FLAG = "--paint-bake-v2-cases"
V2_MARKER = "PAINT_BAKE_V2_RESULT "

sys.path.insert(0, TOOLS_BLENDER)
import paint_bake as pb  # noqa: E402


def _blender_bin() -> str:
	env = os.environ.get("BLENDER_BIN")
	if env:
		return env
	# Chemin connu de ce poste (CLAUDE.md du depot) -- repli seulement si
	# BLENDER_BIN n'est pas defini, jamais suppose sur une autre machine.
	return r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"


class _CasesRunner:
	"""Lance `_paint_bake_cases.py` UNE fois pour toute la classe de test et
	garde le resultat JSON en cache -- un test qui demande un cas absent du
	resultat (Blender introuvable, plantage avant meme d'imprimer le marqueur)
	echoue avec le stdout/stderr complet plutot qu'un KeyError opaque."""
	_result = None
	_raw_output = None
	_out_dir = None

	@classmethod
	def get(cls) -> dict:
		if cls._result is None:
			cls._out_dir = tempfile.mkdtemp(prefix="paint_bake_test_")
			blender_bin = _blender_bin()
			if not os.path.isfile(blender_bin):
				raise unittest.SkipTest(
					f"Blender introuvable ({blender_bin!r}) -- definir BLENDER_BIN pour lancer "
					"tools/blender/tests/test_paint_bake.py")
			cmd = [
				blender_bin, "-b", "--factory-startup", "--python-exit-code", "1",
				"-P", CASES_SCRIPT, "--", "--out-dir", cls._out_dir,
			]
			proc = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
			cls._raw_output = proc.stdout + "\n--- stderr ---\n" + proc.stderr
			if proc.returncode != 0:
				raise AssertionError(
					f"_paint_bake_cases.py a plante (code {proc.returncode}) avant d'imprimer son "
					f"resultat :\n{cls._raw_output}")
			marker = "PAINT_BAKE_CASES_RESULT "
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


class _V2CasesRunner:
	"""Meme role que `_CasesRunner`, pour les cas v2 (TOOL-01B) : relance CE
	fichier dans Blender (`V2_FLAG`) une seule fois et garde le JSON."""
	_result = None
	_raw_output = None

	@classmethod
	def get(cls) -> dict:
		if cls._result is None:
			out_dir = tempfile.mkdtemp(prefix="paint_bake_v2_test_")
			blender_bin = _blender_bin()
			if not os.path.isfile(blender_bin):
				raise unittest.SkipTest(
					f"Blender introuvable ({blender_bin!r}) -- definir BLENDER_BIN pour lancer "
					"les cas v2 de tools/blender/tests/test_paint_bake.py")
			cmd = [
				blender_bin, "-b", "--factory-startup", "--python-exit-code", "1",
				"-P", THIS_SCRIPT, "--", V2_FLAG, "--out-dir", out_dir,
			]
			proc = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
			cls._raw_output = proc.stdout + "\n--- stderr ---\n" + proc.stderr
			if proc.returncode != 0:
				raise AssertionError(
					f"cas v2 : Blender a plante (code {proc.returncode}) avant d'imprimer son "
					f"resultat :\n{cls._raw_output}")
			line = next((ln for ln in proc.stdout.splitlines() if ln.startswith(V2_MARKER)), None)
			if line is None:
				raise AssertionError(f"pas de marqueur {V2_MARKER!r} dans la sortie :\n{cls._raw_output}")
			cls._result = json.loads(line[len(V2_MARKER):])["cases"]
		return cls._result

	@classmethod
	def detail(cls, name: str) -> dict:
		results = cls.get()
		if name not in results:
			raise AssertionError(f"cas v2 {name!r} absent du resultat : {sorted(results)}")
		result = results[name]
		if not result["ok"]:
			raise AssertionError(f"cas v2 {name!r} en echec : {result.get('error')}\n{result.get('traceback')}")
		return result["detail"]


# ---------------------------------------------------------------------------
# 1. Fonctions pures -- aucun Blender lance.
# ---------------------------------------------------------------------------

class TestUvMarginFraction(unittest.TestCase):
	def test_4px_at_1024(self):
		self.assertAlmostEqual(pb.uv_margin_fraction(4, 1024), 4.0 / 1024.0)

	def test_scales_with_resolution(self):
		self.assertAlmostEqual(pb.uv_margin_fraction(8, 2048), pb.uv_margin_fraction(4, 1024))

	def test_invalid_resolution_raises(self):
		with self.assertRaises(ValueError):
			pb.uv_margin_fraction(4, 0)


class TestResolveKind(unittest.TestCase):
	def test_stored_kind_wins(self):
		self.assertEqual(pb.resolve_kind("anything", "rust", "sand_dirt"), "rust")

	def test_material_name_used_when_no_stored_kind(self):
		self.assertEqual(pb.resolve_kind("wood_planks.002", None, None), "wood_planks")

	def test_default_kind_when_no_material(self):
		self.assertEqual(pb.resolve_kind("__none__", None, "sand_dirt"), "sand_dirt")

	def test_flat_when_nothing_resolves(self):
		self.assertEqual(pb.resolve_kind("__none__", None, None), "flat")


class TestOutputMaterialName(unittest.TestCase):
	def test_single_object_asset(self):
		self.assertEqual(pb.output_material_name("wall_1_level", 0, 1), "wall_1_level_painted")

	def test_multi_object_asset_indexed(self):
		self.assertEqual(pb.output_material_name("door", 0, 3), "door_painted_0")
		self.assertEqual(pb.output_material_name("door", 2, 3), "door_painted_2")

	def test_marker_always_contains_painted(self):
		# scripts/player/ViewModel.gd::_PAINTED_MATERIAL_MARKER /
		# ThirdPersonWeapon.gd cherchent "_painted" (contains, pas endswith).
		for count in (1, 2, 5):
			for i in range(count):
				self.assertIn("_painted", pb.output_material_name("id", i, count))

	def test_stem_already_suffixed_is_not_doubled(self):
		# BUG CONSTATE (rapport de tache TOOL-01, verification independante) :
		# `--out .../wall_1_level_painted.glb` -> stem = "wall_1_level_painted"
		# (deja suffixe par convention) -> le materiau final produit etait
		# "wall_1_level_painted_painted" sur les 4 livrables reels (wall_1_
		# level, door, roof_corrugated, oil_drum), alors que le critere
		# d'acceptation exige exactement "<id>_painted".
		self.assertEqual(pb.output_material_name("wall_1_level_painted", 0, 1), "wall_1_level_painted")
		self.assertEqual(pb.output_material_name("oil_drum_painted", 0, 1), "oil_drum_painted")

	def test_stem_already_suffixed_indexed_is_not_doubled(self):
		self.assertEqual(pb.output_material_name("door_painted", 0, 3), "door_painted_0")
		self.assertEqual(pb.output_material_name("door_painted", 2, 3), "door_painted_2")

	def test_stem_already_suffixed_and_indexed_is_not_doubled(self):
		# Un stem qui porte deja "_painted_N" (relance sur une sortie
		# multi-objets deja peinte) ne doit pas non plus s'accumuler.
		self.assertEqual(pb.output_material_name("door_painted_0", 0, 1), "door_painted")


class TestIslandHueOffset(unittest.TestCase):
	def test_deterministic(self):
		a = pb.island_hue_offset(7, "wall_1_level", 3, max_deg=6.0)
		b = pb.island_hue_offset(7, "wall_1_level", 3, max_deg=6.0)
		self.assertEqual(a, b)

	def test_within_bounds(self):
		for i in range(20):
			v = pb.island_hue_offset(0, "obj", i, max_deg=6.0)
			self.assertGreaterEqual(v, -6.0)
			self.assertLessEqual(v, 6.0)

	def test_differs_across_islands_or_objects(self):
		values = {pb.island_hue_offset(0, "obj", i, max_deg=6.0) for i in range(8)}
		self.assertGreater(len(values), 1)

	def test_hue01_maps_zero_to_half(self):
		self.assertAlmostEqual(pb.hue01_from_offset_deg(0.0), 0.5)

	def test_hue01_clamped(self):
		self.assertEqual(pb.hue01_from_offset_deg(10000.0), 1.0)
		self.assertEqual(pb.hue01_from_offset_deg(-10000.0), 0.0)


class TestReservedBandViolation(unittest.TestCase):
	def test_enemy_magenta_flagged(self):
		self.assertTrue(pb.reserved_band_violation((1.0, 0.0, 0.9)))

	def test_neutral_wood_not_flagged(self):
		self.assertFalse(pb.reserved_band_violation((0.62, 0.47, 0.32)))

	def test_low_chroma_never_flagged_even_in_band(self):
		self.assertFalse(pb.reserved_band_violation((0.51, 0.50, 0.505)))


class TestAugmentSidecar(unittest.TestCase):
	def test_merges_keys_into_existing_json(self):
		with tempfile.TemporaryDirectory() as d:
			glb_path = os.path.join(d, "asset.glb")
			sidecar_path = os.path.join(d, "asset.json")
			with open(sidecar_path, "w", encoding="utf-8") as f:
				json.dump({"tris": 528}, f)
			out_path = pb.augment_sidecar(glb_path, {"painted": True, "res": 1024})
			self.assertEqual(out_path, sidecar_path)
			with open(sidecar_path, encoding="utf-8") as f:
				data = json.load(f)
			self.assertEqual(data["tris"], 528)
			self.assertTrue(data["painted"])
			self.assertEqual(data["res"], 1024)


# -- v2 (TOOL-01B) -------------------------------------------------------------

def _cartoon_kind_aliases() -> dict:
	"""`_KIND_ALIASES` de scripts/core/Cartoon.gd, relu tel quel dans le
	source GDScript (la table de reference cote jeu)."""
	path = os.path.join(REPO_ROOT, "scripts", "core", "Cartoon.gd")
	with open(path, encoding="utf-8") as f:
		text = f.read()
	block = text.split("const _KIND_ALIASES: Dictionary = {", 1)[1].split("}", 1)[0]
	return dict(re.findall(r'&"(\w+)":\s*&"(\w+)"', block))


class TestCanonicalKind(unittest.TestCase):
	def test_aliases_match_cartoon_gd(self):
		# Meme vocabulaire que le jeu : un alias qui diverge ferait cuire une
		# autre texture que celle que Cartoon.painted_for_slot() choisirait.
		self.assertEqual(pb.KIND_ALIASES, _cartoon_kind_aliases())

	def test_short_prop_names_resolve(self):
		self.assertEqual(pb.canonical_kind("wood"), "wood_planks")
		self.assertEqual(pb.canonical_kind("corrugated"), "corrugated_metal")

	def test_unknown_kind_kept_as_is(self):
		self.assertEqual(pb.canonical_kind("rock_strata"), "rock_strata")


class TestResolveBaseTexture(unittest.TestCase):
	def test_kind_uses_its_painted_texture(self):
		base = pb.resolve_base_texture("wood_planks")
		self.assertEqual(base["mode"], "texture")
		self.assertEqual(os.path.basename(base["path"]), "material_wood_planks_albedo.png")
		self.assertTrue(os.path.isfile(base["path"]))

	def test_alias_uses_canonical_texture(self):
		base = pb.resolve_base_texture("corrugated")
		self.assertEqual(os.path.basename(base["path"]), "material_corrugated_metal_albedo.png")

	def test_wasteland_texture_found_with_or_without_prefix(self):
		for kind in ("rock_strata", "wl_rock_strata"):
			base = pb.resolve_base_texture(kind)
			self.assertEqual(base["mode"], "texture", kind)
			self.assertEqual(os.path.basename(base["path"]), "wl_rock_strata_albedo.png", kind)

	def test_accent_recolors_painted_metal_detail(self):
		# Cartoon.painted_for_slot("accent") = painted_metal teinte : meme
		# detail peint, recolore a la couleur d'accent -- jamais un aplat.
		base = pb.resolve_base_texture("accent")
		self.assertEqual(base["mode"], "recolor")
		self.assertEqual(os.path.basename(base["path"]), "material_painted_metal_albedo.png")

	def test_unknown_kind_recolors_a_painted_detail_never_flat(self):
		base = pb.resolve_base_texture("flat")
		self.assertEqual(base["mode"], "recolor")
		self.assertTrue(os.path.isfile(base["path"]))

	def test_missing_library_raises(self):
		with tempfile.TemporaryDirectory() as d:
			with self.assertRaises(RuntimeError):
				pb.resolve_base_texture("wood_planks", painted_dir=d, wasteland_dir=d)


class TestLuma(unittest.TestCase):
	def test_rec709_weights(self):
		self.assertAlmostEqual(pb.srgb_luma((1.0, 1.0, 1.0)), 1.0)
		self.assertAlmostEqual(pb.srgb_luma((0.0, 1.0, 0.0)), 0.7152)

	def test_gain_step_brightens_dark_bake(self):
		self.assertAlmostEqual(pb.linear_gain_step(0.44, 0.40), (0.44 / 0.40) ** 2.2)

	def test_gain_step_darkens_bright_bake(self):
		self.assertLess(pb.linear_gain_step(0.40, 0.50), 1.0)

	def test_gain_step_bounded(self):
		self.assertLessEqual(pb.linear_gain_step(0.9, 0.0), pb.GAIN_MAX)
		self.assertGreaterEqual(pb.linear_gain_step(0.01, 0.99), pb.GAIN_MIN)

	def test_tolerance_is_ten_percent(self):
		self.assertTrue(pb.luma_within_tolerance(0.48, 0.44))
		self.assertTrue(pb.luma_within_tolerance(0.40, 0.44))
		self.assertFalse(pb.luma_within_tolerance(0.36, 0.44))
		self.assertFalse(pb.luma_within_tolerance(0.50, 0.44))


class TestStrokeFrequencies(unittest.TestCase):
	def test_long_axis_gets_the_stretched_stroke(self):
		fx, fy, fz = pb.stroke_frequencies((2.0, 0.05, 0.2))
		self.assertLess(fx, fy)
		self.assertLess(fx, fz)

	def test_vertical_post(self):
		fx, fy, fz = pb.stroke_frequencies((0.1, 0.1, 1.2))
		self.assertLess(fz, fx)
		self.assertLess(fz, fy)

	def test_compact_island_strokes_stay_horizontal(self):
		fx, fy, fz = pb.stroke_frequencies((0.5, 0.45, 0.55))
		self.assertEqual(fz, max(fx, fy, fz))
		self.assertLess(min(fx, fy), fz)


class TestIslandValueOffset(unittest.TestCase):
	def test_deterministic_and_bounded(self):
		values = [pb.island_value_offset(0, "wall", i, max_frac=0.05) for i in range(24)]
		self.assertEqual(values, [pb.island_value_offset(0, "wall", i, max_frac=0.05) for i in range(24)])
		for v in values:
			self.assertGreaterEqual(v, -0.05)
			self.assertLessEqual(v, 0.05)
		self.assertGreater(len(set(values)), 1)

	def test_independent_from_hue_offset(self):
		# Deux tirages differents : une planche plus chaude n'est pas
		# systematiquement plus claire.
		hues = [pb.island_hue_offset(0, "wall", i, max_deg=1.0) for i in range(24)]
		vals = [pb.island_value_offset(0, "wall", i, max_frac=1.0) for i in range(24)]
		self.assertNotEqual(hues, vals)


class TestGuardReservedHues(unittest.TestCase):
	def test_violating_pixels_pushed_out_of_band(self):
		import numpy as np
		rgb = np.array([[1.0, 0.0, 0.9], [0.55, 0.12, 0.30], [0.3, 0.8, 0.3]], dtype=np.float64)
		self.assertTrue(all(pb.reserved_band_violation(tuple(c)) for c in rgb))
		fixed, count = pb.guard_reserved_hues(rgb)
		self.assertEqual(count, 3)
		for c in fixed:
			self.assertFalse(pb.reserved_band_violation(tuple(c)), c)

	def test_value_preserved(self):
		import numpy as np
		rgb = np.array([[0.55, 0.12, 0.30]], dtype=np.float64)
		fixed, _ = pb.guard_reserved_hues(rgb)
		self.assertAlmostEqual(float(fixed[0].max()), 0.55, places=6)

	def test_allowed_pixels_untouched(self):
		import numpy as np
		rgb = np.array([[0.62, 0.47, 0.32], [0.51, 0.50, 0.505], [0.2, 0.3, 0.8]], dtype=np.float64)
		fixed, count = pb.guard_reserved_hues(rgb)
		self.assertEqual(count, 0)
		self.assertTrue((fixed == rgb).all())


# ---------------------------------------------------------------------------
# 2. Pipeline bpy reel -- sous-process Blender (voir _CasesRunner).
# ---------------------------------------------------------------------------

class TestFlatKindBakesUniqueTexture(unittest.TestCase):
	"""Criteres d'acceptation TOOL-01 : UV presentes, texture non uniforme,
	pas de pixel hors palette reservee -- sur un materiau "kind" plat (le cas
	reel des modules du kit shanty, sans texture d'origine)."""

	def test_case_passes(self):
		result = _CasesRunner.case("flat_kind_bakes_unique_texture")
		self.assertTrue(result["ok"], result.get("error"))

	def test_uv_present(self):
		result = _CasesRunner.case("flat_kind_bakes_unique_texture")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertTrue(result["detail"]["uv_present"])

	def test_texture_non_uniform(self):
		result = _CasesRunner.case("flat_kind_bakes_unique_texture")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertGreater(result["detail"]["unique_colors"], 20)

	def test_no_reserved_palette_pixel(self):
		result = _CasesRunner.case("flat_kind_bakes_unique_texture")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertEqual(result["detail"]["reserved_hits"], 0)

	def test_material_name_convention(self):
		result = _CasesRunner.case("flat_kind_bakes_unique_texture")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertTrue(result["detail"]["expects_marker"])

	def test_no_leftover_color_attributes(self):
		# BUG CONSTATE (rapport de tache TOOL-01, oil_drum.glb) : un COLOR_0
		# laisse sur la mesh est multiplie dans le baseColor par tout
		# consommateur glTF conforme (dont Godot) -- jamais souhaite sur une
		# texture DEJA cuite. Voir bake_object_texture, retrait complet.
		result = _CasesRunner.case("flat_kind_bakes_unique_texture")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertEqual(result["detail"]["color_attributes_after"], [])

	def test_check_asset_passes(self):
		result = _CasesRunner.case("flat_kind_bakes_unique_texture")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertTrue(result["detail"]["check_asset_ok"], result["detail"]["check_asset_failures"])

	def test_sidecar_augmented(self):
		result = _CasesRunner.case("flat_kind_bakes_unique_texture")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertTrue(result["detail"]["sidecar_painted_flag"])


class TestPreexistingTilingUvNeverReused(unittest.TestCase):
	"""Regression du bogue reel constate sur wall_1_level.glb : une UV
	preexistante DEGENEREE (plusieurs faces partageant la meme region UV,
	comme une projection boite a l'echelle du monde) ne doit jamais etre
	reutilisee telle quelle pour la cuisson -- sinon une grande partie du
	canevas reste noire (jamais couverte par aucune face)."""

	def test_case_passes(self):
		result = _CasesRunner.case("preexisting_tiling_uv_is_never_reused")
		self.assertTrue(result["ok"], result.get("error"))

	def test_old_uv_layer_removed(self):
		result = _CasesRunner.case("preexisting_tiling_uv_is_never_reused")
		self.assertTrue(result["ok"], result.get("error"))
		# Un seul calque UV survit (le nom "paint_bake_uv" lui-meme ne
		# traverse pas l'aller-retour glTF, voir le commentaire du cas).
		self.assertEqual(result["detail"]["uv_layer_count_after"], 1)

	def test_canvas_mostly_painted(self):
		result = _CasesRunner.case("preexisting_tiling_uv_is_never_reused")
		self.assertTrue(result["ok"], result.get("error"))
		# Avant le correctif : ~49 % du canevas restait noir (aucune face ne
		# le couvrait). Un unwrap frais et unique couvre la quasi-totalite.
		self.assertLess(result["detail"]["frac_near_black"], 0.15)


class TestExistingTextureUsesTriplanar(unittest.TestCase):
	def test_case_passes(self):
		result = _CasesRunner.case("existing_texture_uses_triplanar")
		self.assertTrue(result["ok"], result.get("error"))

	def test_flagged_as_existing_texture(self):
		result = _CasesRunner.case("existing_texture_uses_triplanar")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertTrue(result["detail"]["had_existing_texture"])

	def test_triplanar_output_non_uniform(self):
		result = _CasesRunner.case("existing_texture_uses_triplanar")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertGreater(result["detail"]["unique_colors"], 20)


class TestIslandHueVariesAndIsDeterministic(unittest.TestCase):
	def test_case_passes(self):
		result = _CasesRunner.case("island_hue_varies_and_is_deterministic")
		self.assertTrue(result["ok"], result.get("error"))

	def test_multiple_islands_found(self):
		result = _CasesRunner.case("island_hue_varies_and_is_deterministic")
		self.assertTrue(result["ok"], result.get("error"))
		# Smart UV Project isole CHAQUE face d'un cube en sa propre ile (angle
		# de 90 deg entre faces adjacentes, bien au-dessus de l'angle_limit de
		# 66 deg) : 2 boites de 6 faces -> 12 iles, pas 2 -- ce test ne verifie
		# que "plus d'une ile", la variation par ile etant le vrai critere
		# (voir test_each_island_is_flat_but_islands_differ).
		self.assertGreater(result["detail"]["island_count"], 1)

	def test_each_island_is_flat_but_islands_differ(self):
		result = _CasesRunner.case("island_hue_varies_and_is_deterministic")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertTrue(result["detail"]["each_island_single_flat_value"])
		self.assertFalse(result["detail"]["all_islands_identical"])

	def test_deterministic_across_calls(self):
		result = _CasesRunner.case("island_hue_varies_and_is_deterministic")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertTrue(result["detail"]["deterministic_repeat"])


class TestMultiSlotMergesToSingleMaterial(unittest.TestCase):
	def test_case_passes(self):
		result = _CasesRunner.case("multi_slot_merges_to_single_material")
		self.assertTrue(result["ok"], result.get("error"))

	def test_both_kinds_baked(self):
		result = _CasesRunner.case("multi_slot_merges_to_single_material")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertEqual(result["detail"]["slot_kinds"], ["rust", "wood_planks"])

	def test_single_final_slot(self):
		result = _CasesRunner.case("multi_slot_merges_to_single_material")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertEqual(result["detail"]["final_slot_count"], 1)


class TestTurntableFindsDirectAndMixedImage(unittest.TestCase):
	"""Correctif turntable.py (TOOL-01) : `_find_albedo_image` -- un materiau
	"<id>_painted" affiche desormais sa vraie texture dans l'apercu, au lieu
	de l'aplat bleu-gris constate avant ce correctif."""

	def test_case_passes(self):
		result = _CasesRunner.case("turntable_finds_direct_and_mixed_image")
		self.assertTrue(result["ok"], result.get("error"))

	def test_direct_image_found(self):
		result = _CasesRunner.case("turntable_finds_direct_and_mixed_image")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertTrue(result["detail"]["direct_image_found"])

	def test_flat_material_has_no_image(self):
		result = _CasesRunner.case("turntable_finds_direct_and_mixed_image")
		self.assertTrue(result["ok"], result.get("error"))
		self.assertTrue(result["detail"]["flat_material_image_is_none"])
		self.assertTrue(result["detail"]["flat_albedo_is_4_floats"])


# ---------------------------------------------------------------------------
# 3. Pipeline bpy reel v2 (TOOL-01B) -- sous-process Blender (_V2CasesRunner).
# Seuils : luminance sRGB Rec.709 (`paint_bake.srgb_luma`) mesuree sur la
# texture cuite, aux points 3D donnes (voir `_uv_at_point`).
# ---------------------------------------------------------------------------

EDGE_GAIN_MIN = 1.12        # liseré d'eclat : >= +12 % de luminance vs le centre de la face
CRISP_MAX = 1.05            # a 3,5 cm de l'arete, on est revenu a la face (liseré net)
INK_MAX = 0.85              # trait d'encre : nettement plus sombre que le liseré
CONCAVE_MAX = 1.03          # arete concave : jamais eclaircie
CREVICE_MAX = 0.85          # creux : plus sombre que la face ouverte voisine
FLAT_MIN = 0.92             # face plane ouverte : pas assombrie (vs luminance de la texture source)
GRAIN_STD_MIN = 0.015       # grain / coups de pinceau visibles (texture source : ecart-type ~0,008)


class TestV2ProjectedKindTexture(unittest.TestCase):
	"""Base = texture peinte du kind projetee a l'echelle du monde (jamais la
	couleur unie de la palette), luminance recalee, sur un asset glTF reel
	(sommets eclates aux aretes vives, comme les 4 demos)."""

	def test_base_is_the_kind_texture(self):
		d = _V2CasesRunner.detail("projected_kind_texture")
		self.assertEqual(d["base_mode"], "texture")
		self.assertEqual(os.path.basename(d["base_texture"]), "material_wood_planks_albedo.png")

	def test_luminance_within_ten_percent_of_source(self):
		d = _V2CasesRunner.detail("projected_kind_texture")
		self.assertTrue(pb.luma_within_tolerance(d["reported_baked_luma"], d["source_luma"]), d)
		self.assertTrue(pb.luma_within_tolerance(d["measured_baked_luma"], d["source_luma"]), d)

	def test_not_the_flat_palette_color(self):
		d = _V2CasesRunner.detail("projected_kind_texture")
		self.assertFalse(pb.luma_within_tolerance(d["palette_luma"], d["measured_baked_luma"]), d)

	def test_grain_visible(self):
		d = _V2CasesRunner.detail("projected_kind_texture")
		self.assertGreaterEqual(d["face_luma_std"], GRAIN_STD_MIN)

	def test_chamfer_lightened_after_gltf_roundtrip(self):
		d = _V2CasesRunner.detail("projected_kind_texture")
		self.assertGreaterEqual(d["chamfer_luma"], EDGE_GAIN_MIN * d["face_luma"], d)

	def test_no_reserved_hue_and_single_material(self):
		d = _V2CasesRunner.detail("projected_kind_texture")
		self.assertEqual(d["reserved_hits"], 0)
		self.assertEqual(d["material_count"], 1)
		self.assertEqual(d["color_attributes_after"], [])


class TestV2SharpEdges(unittest.TestCase):
	"""Arete vive convexe : liseré d'eclat net de 1-2 cm + trait d'encre fin ;
	arete concave (deux coques qui se croisent) : jamais eclaircie."""

	def test_convex_edge_band_lightened(self):
		d = _V2CasesRunner.detail("sharp_edges")
		self.assertGreaterEqual(d["band_luma"], EDGE_GAIN_MIN * d["center_luma"], d)

	def test_band_is_crisp(self):
		d = _V2CasesRunner.detail("sharp_edges")
		self.assertLessEqual(d["far_luma"], CRISP_MAX * d["center_luma"], d)

	def test_fine_ink_line_on_the_edge(self):
		d = _V2CasesRunner.detail("sharp_edges")
		self.assertLessEqual(d["ink_luma"], INK_MAX * d["band_luma"], d)

	def test_concave_edge_not_lightened(self):
		d = _V2CasesRunner.detail("sharp_edges")
		self.assertLessEqual(d["concave_luma"], CONCAVE_MAX * d["slab_luma"], d)


class TestV2CreviceTint(unittest.TestCase):
	"""Creux (joint de 1,5 cm entre deux planches) assombri ET teinte vers
	l'ombre de la carte ; faces planes ouvertes pas noircies."""

	def test_crevice_darker(self):
		d = _V2CasesRunner.detail("crevice_tint")
		self.assertLessEqual(d["crevice_luma"], CREVICE_MAX * d["front_luma"], d)

	def test_crevice_tinted_toward_shadow(self):
		d = _V2CasesRunner.detail("crevice_tint")
		self.assertGreater(d["crevice_blue_share"], d["front_blue_share"] + 0.01, d)

	def test_flat_faces_not_darkened(self):
		d = _V2CasesRunner.detail("crevice_tint")
		self.assertGreaterEqual(d["front_luma"], FLAT_MIN * d["source_luma"], d)


class TestV2MultiKindLuminance(unittest.TestCase):
	"""Chaque slot est recale sur SA texture source (+/-10 %) ; un slot sans
	texture propre (accent) recolore un detail peint, jamais un aplat."""

	def test_every_slot_within_tolerance(self):
		d = _V2CasesRunner.detail("multi_kind_luminance")
		for slot in d["slots"]:
			self.assertIsNotNone(slot["luma_ratio"], slot)
			self.assertGreaterEqual(slot["luma_ratio"], 1.0 - pb.LUMA_TOLERANCE, slot)
			self.assertLessEqual(slot["luma_ratio"], 1.0 + pb.LUMA_TOLERANCE, slot)

	def test_accent_recolored_not_flat(self):
		d = _V2CasesRunner.detail("multi_kind_luminance")
		accent = next(s for s in d["slots"] if s["kind"] == "accent")
		self.assertEqual(accent["base_mode"], "recolor")
		self.assertGreaterEqual(d["accent_face_luma_std"], GRAIN_STD_MIN)
		self.assertLess(d["accent_hue_error_deg"], 20.0)


class TestV2PlankVariation(unittest.TestCase):
	def test_one_island_per_plank(self):
		d = _V2CasesRunner.detail("plank_variation")
		self.assertEqual(d["mesh_islands"], 6)

	def test_planks_differ_in_hue(self):
		d = _V2CasesRunner.detail("plank_variation")
		self.assertGreater(d["hue_spread_deg"], 2.0, d)


class TestV2ReservedHueGuard(unittest.TestCase):
	def test_red_metal_crevice_never_reserved(self):
		d = _V2CasesRunner.detail("reserved_hue_guard")
		self.assertEqual(d["reserved_hits"], 0, d)
		self.assertGreater(d["sampled"], 1000)


# ---------------------------------------------------------------------------
# Cote Blender des cas v2 -- execute UNIQUEMENT par `blender -b -P <ce
# fichier> -- --paint-bake-v2-cases --out-dir DIR` (jamais par pytest : bpy
# n'existe pas hors de Blender, d'ou les imports locaux).
# ---------------------------------------------------------------------------

def _bl_box(name: str, size, loc, bevel_m: float = 0.0):
	"""Pave `size` centre en `loc`, position ET echelle appliquees (objet a
	l'origine : coordonnees du maillage = coordonnees monde, celles que
	`_uv_at_point` recoit), chanfreine a `bevel_m` (1 segment, comme les kits
	du projet) si > 0."""
	import bpy
	import bmesh
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
	obj = bpy.context.active_object
	obj.name = name
	obj.scale = size
	with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj]):
		bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
	if bevel_m > 0.0:
		bm = bmesh.new()
		bm.from_mesh(obj.data)
		bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel_m, segments=1, affect='EDGES',
			profile=0.5, clamp_overlap=True)
		bm.to_mesh(obj.data)
		bm.free()
	return obj


def _bl_material(kind: str):
	import toonkit
	return toonkit.toon_material(kind, toonkit.palette(kind), kind=kind)


def _bl_part(name: str, size, loc, kind: str, bevel_m: float = 0.0):
	obj = _bl_box(name, size, loc, bevel_m)
	obj.data.materials.append(_bl_material(kind))
	return obj


def _bl_pixels(image):
	"""Pixels RGB (sRGB encode, 0..1) de `image`, tableau (h, w, 3)."""
	import numpy as np
	w, h = image.size
	flat = np.empty(w * h * image.channels, dtype=np.float32)
	image.pixels.foreach_get(flat)
	return flat.reshape(h, w, image.channels)[:, :, :3].astype(np.float64)


def _uv_at_point(obj, point):
	"""UV de la texture cuite au point 3D `point` (coordonnees objet) :
	triangle du maillage qui contient ce point (tolerance 0,1 mm au plan,
	bords et diagonales de quad inclus), interpolation barycentrique des UV.
	`None` si aucun triangle ne le contient."""
	from mathutils import Vector
	me = obj.data
	me.calc_loop_triangles()
	uv_data = me.uv_layers.active.data
	p = Vector(point)
	for tri in me.loop_triangles:
		a, b, c = (me.vertices[i].co for i in tri.vertices)
		if abs((p - a).dot(tri.normal)) > 1e-4:
			continue
		v0, v1, v2 = b - a, c - a, p - a
		d00, d01, d11 = v0.dot(v0), v0.dot(v1), v1.dot(v1)
		d20, d21 = v2.dot(v0), v2.dot(v1)
		denom = d00 * d11 - d01 * d01
		if abs(denom) < 1e-14:
			continue
		wb = (d11 * d20 - d01 * d21) / denom
		wc = (d00 * d21 - d01 * d20) / denom
		wa = 1.0 - wb - wc
		if min(wa, wb, wc) < -1e-6:
			continue
		uvs = [uv_data[li].uv for li in tri.loops]
		return (wa * uvs[0][0] + wb * uvs[1][0] + wc * uvs[2][0], wa * uvs[0][1] + wb * uvs[1][1] + wc * uvs[2][1])
	return None


def _sample(obj, pixels, points) -> list:
	"""Couleurs RGB (sRGB) de la texture cuite aux points 3D `points`."""
	h, w, _ = pixels.shape
	out = []
	for p in points:
		uv = _uv_at_point(obj, p)
		if uv is None:
			raise AssertionError(f"point {p} hors de toute face de {obj.name}")
		x = min(w - 1, max(0, int(uv[0] * w)))
		y = min(h - 1, max(0, int(uv[1] * h)))
		out.append(tuple(float(c) for c in pixels[y, x]))
	return out


def _mean_luma(colors) -> float:
	return sum(pb.srgb_luma(c) for c in colors) / len(colors)


def _luma_std(colors) -> float:
	values = [pb.srgb_luma(c) for c in colors]
	mean = sum(values) / len(values)
	return math.sqrt(sum((v - mean) ** 2 for v in values) / len(values))


def _mean_color(colors) -> tuple:
	return tuple(sum(c[i] for c in colors) / len(colors) for i in range(3))


def _blue_share(colors) -> float:
	r, g, b = _mean_color(colors)
	return b / max(r + g + b, 1e-6)


def _hue_deg(rgb) -> float:
	return colorsys.rgb_to_hsv(*rgb)[0] * 360.0


def _hue_distance(a: float, b: float) -> float:
	d = abs(a - b) % 360.0
	return min(d, 360.0 - d)


def _grid(center, axis_u, axis_v, half_u: float, half_v: float, n: int = 7) -> list:
	"""Grille n x n de points sur une face (centre + deux axes unitaires)."""
	pts = []
	for i in range(n):
		for j in range(n):
			fu = -half_u + 2.0 * half_u * i / (n - 1)
			fv = -half_v + 2.0 * half_v * j / (n - 1)
			pts.append(tuple(center[k] + axis_u[k] * fu + axis_v[k] * fv for k in range(3)))
	return pts


def _v2_case_projected_kind_texture(out_dir: str) -> dict:
	"""Planche chanfreinee (1,5 cm) wood_planks sans texture d'origine,
	exportee en .glb (sommets eclates aux aretes vives, comme les vrais kits)
	puis passee par `paint_bake()` complet ; mesures sur la sortie reimportee."""
	import toonkit
	toonkit.reset_scene()
	obj = _bl_part("plank", (1.6, 0.06, 0.24), (0.0, 0.0, 0.12), "wood_planks", bevel_m=0.015)
	src = os.path.join(out_dir, "v2_plank_src.glb")
	toonkit.export_glb(src, obj, write_report=False)
	out = os.path.join(out_dir, "v2_plank_painted.glb")
	report = pb.paint_bake(src, out, res=1024, samples=12, skip_turntable=True)
	slot = report["objects"][0]["slots"][0]

	toonkit.reset_scene()
	baked = pb.import_asset(out)[0]
	image = pb._material_image_node(baked.data.materials[0])
	pixels = _bl_pixels(image)
	# Face avant (normale -Y, y = -0,03), interieur a 4 cm des bords.
	face_pts = _grid((0.0, -0.03, 0.12), (1, 0, 0), (0, 0, 1), 0.70, 0.07)
	face = _sample(baked, pixels, face_pts)
	# Milieu du chanfrein entre la face avant et le dessus (arete y=-0,03 /
	# z=0,24, chanfrein de 1,5 cm).
	chamfer_pts = [(x, -0.03 + 0.0075, 0.24 - 0.0075) for x in (-0.6, -0.3, 0.0, 0.3, 0.6)]
	chamfer = _sample(baked, pixels, chamfer_pts)
	covered = pixels.reshape(-1, 3)
	covered = covered[covered.max(axis=1) > 0.02]
	step = max(1, len(covered) // 20000)
	sampled = covered[::step]
	return {
		"base_mode": slot["base_mode"],
		"base_texture": slot["base_texture"],
		"source_luma": slot["target_luma"],
		"reported_baked_luma": slot["baked_luma"],
		"measured_baked_luma": float(sum(pb.srgb_luma(c) for c in sampled) / len(sampled)),
		"palette_luma": pb.srgb_luma(toonkit.palette("wood_planks")),
		"face_luma": _mean_luma(face),
		"face_luma_std": _luma_std(face),
		"chamfer_luma": _mean_luma(chamfer),
		"reserved_hits": sum(1 for c in sampled if pb.reserved_band_violation(tuple(c))),
		"material_count": len(baked.data.materials),
		"color_attributes_after": [a.name for a in baked.data.color_attributes],
	}


def _bake_in_place(obj, res: int = 1024, seed: str = "0:v2", palette_kind=None) -> dict:
	report = pb.bake_object_texture(
		obj, res=res, bake_margin_px=4, samples=12, seed=seed, hue_max_deg=pb.DEFAULT_HUE_MAX_DEG,
		palette_kind=palette_kind, image_name=f"{obj.name}_albedo")
	report["pixels"] = _bl_pixels(pb._material_image_node(obj.data.materials[0]))
	return report


def _v2_case_sharp_edges(out_dir: str) -> dict:
	import toonkit
	toonkit.reset_scene()
	cube = _bl_part("sharp_cube", (0.5, 0.5, 0.5), (0.0, 0.0, 0.25), "wood_planks")
	rep = _bake_in_place(cube)
	px = rep["pixels"]
	ys = (-0.15, -0.075, 0.0, 0.075, 0.15)

	def edge_points(d):
		# 4 aretes du dessus (z = 0,5), a la distance d de chacune.
		pts = []
		for t in ys:
			pts += [(0.25 - d, t, 0.5), (-0.25 + d, t, 0.5), (t, 0.25 - d, 0.5), (t, -0.25 + d, 0.5)]
		return pts

	center = _sample(cube, px, _grid((0.0, 0.0, 0.5), (1, 0, 0), (0, 1, 0), 0.1, 0.1, n=5))
	band = _sample(cube, px, edge_points(0.007))
	ink = _sample(cube, px, edge_points(0.001))
	far = _sample(cube, px, edge_points(0.035))

	toonkit.reset_scene()
	slab = _bl_box("slab", (0.8, 0.8, 0.1), (0.0, 0.0, 0.05))
	post = _bl_box("post", (0.1, 0.1, 0.6), (0.0, 0.0, 0.3))
	joined = toonkit.join([slab, post])
	joined.data.materials.append(_bl_material("wood_planks"))
	rep2 = _bake_in_place(joined, seed="0:v2c")
	px2 = rep2["pixels"]
	concave = _sample(joined, px2, [(0.05 + 0.007, t, 0.1) for t in (-0.03, 0.0, 0.03)]
		+ [(-0.05 - 0.007, t, 0.1) for t in (-0.03, 0.0, 0.03)])
	slab_ref = _sample(joined, px2, [(0.2, t, 0.1) for t in (-0.2, -0.1, 0.1, 0.2)]
		+ [(-0.2, t, 0.1) for t in (-0.2, -0.1, 0.1, 0.2)])
	return {
		"center_luma": _mean_luma(center),
		"band_luma": _mean_luma(band),
		"ink_luma": _mean_luma(ink),
		"far_luma": _mean_luma(far),
		"concave_luma": _mean_luma(concave),
		"slab_luma": _mean_luma(slab_ref),
	}


def _v2_case_crevice_tint(out_dir: str) -> dict:
	import toonkit
	toonkit.reset_scene()
	low = _bl_box("plank_low", (1.2, 0.05, 0.2), (0.0, 0.0, 0.1))
	high = _bl_box("plank_high", (1.2, 0.05, 0.2), (0.0, 0.0, 0.315))
	obj = toonkit.join([low, high])
	obj.data.materials.append(_bl_material("wood_planks"))
	rep = _bake_in_place(obj, seed="0:crevice")
	px = rep["pixels"]
	crevice = _sample(obj, px, [(x, t, 0.2) for x in (-0.4, -0.2, 0.0, 0.2, 0.4) for t in (-0.01, 0.0, 0.01)])
	front = _sample(obj, px, _grid((0.0, -0.025, 0.1), (1, 0, 0), (0, 0, 1), 0.45, 0.05, n=5)
		+ _grid((0.0, -0.025, 0.315), (1, 0, 0), (0, 0, 1), 0.45, 0.05, n=5))
	return {
		"crevice_luma": _mean_luma(crevice),
		"front_luma": _mean_luma(front),
		"crevice_blue_share": _blue_share(crevice),
		"front_blue_share": _blue_share(front),
		"source_luma": rep["slots"][0]["target_luma"],
	}


def _v2_case_multi_kind_luminance(out_dir: str) -> dict:
	import toonkit
	toonkit.reset_scene()
	parts = [
		_bl_part("wood_box", (0.5, 0.5, 0.5), (0.0, 0.0, 0.25), "wood_planks"),
		_bl_part("rust_box", (0.5, 0.5, 0.5), (1.0, 0.0, 0.25), "rust"),
		_bl_part("accent_box", (0.5, 0.5, 0.5), (2.0, 0.0, 0.25), "accent"),
	]
	obj = toonkit.join(parts)
	rep = _bake_in_place(obj, seed="0:multi")
	px = rep["pixels"]
	accent = _sample(obj, px, _grid((2.0, -0.25, 0.25), (1, 0, 0), (0, 0, 1), 0.18, 0.18))
	accent_hue = _hue_deg(_mean_color(accent))
	palette_hue = _hue_deg(toonkit.palette("accent")[:3])
	return {
		"slots": [{k: s[k] for k in ("kind", "base_mode", "luma_ratio")} for s in rep["slots"]],
		"accent_face_luma_std": _luma_std(accent),
		"accent_hue_error_deg": _hue_distance(accent_hue, palette_hue),
	}


def _v2_case_plank_variation(out_dir: str) -> dict:
	import toonkit
	toonkit.reset_scene()
	planks = [_bl_box(f"p{i}", (1.0, 0.05, 0.18), (0.0, 0.0, 0.09 + i * 0.2)) for i in range(6)]
	obj = toonkit.join(planks)
	obj.data.materials.append(_bl_material("wood_planks"))
	rep = _bake_in_place(obj, seed="0:planks")
	px = rep["pixels"]
	hues = []
	for i in range(6):
		pts = _grid((0.0, -0.025, 0.09 + i * 0.2), (1, 0, 0), (0, 0, 1), 0.35, 0.04, n=5)
		hues.append(_hue_deg(_mean_color(_sample(obj, px, pts))))
	spread = max(_hue_distance(a, b) for a in hues for b in hues)
	return {"mesh_islands": rep["mesh_islands"], "hues": hues, "hue_spread_deg": spread}


def _v2_case_reserved_hue_guard(out_dir: str) -> dict:
	import toonkit
	toonkit.reset_scene()
	a = _bl_box("red_a", (0.6, 0.3, 0.6), (0.0, 0.0, 0.3))
	b = _bl_box("red_b", (0.6, 0.3, 0.6), (0.0, 0.31, 0.3))
	obj = toonkit.join([a, b])
	obj.data.materials.append(_bl_material("painted_metal"))
	rep = _bake_in_place(obj, seed="0:red")
	flat = rep["pixels"].reshape(-1, 3)
	covered = flat[flat.max(axis=1) > 0.02]
	step = max(1, len(covered) // 30000)
	sampled = covered[::step]
	return {
		"reserved_hits": sum(1 for c in sampled if pb.reserved_band_violation(tuple(c))),
		"sampled": int(len(sampled)),
		"guarded_texels": rep["reserved_hue_guarded"],
	}


_V2_CASES = {
	"projected_kind_texture": _v2_case_projected_kind_texture,
	"sharp_edges": _v2_case_sharp_edges,
	"crevice_tint": _v2_case_crevice_tint,
	"multi_kind_luminance": _v2_case_multi_kind_luminance,
	"plank_variation": _v2_case_plank_variation,
	"reserved_hue_guard": _v2_case_reserved_hue_guard,
}


def _v2_cases_main() -> None:
	import traceback
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	out_dir = argv[argv.index("--out-dir") + 1]
	only = argv[argv.index("--only") + 1].split(",") if "--only" in argv else None
	os.makedirs(out_dir, exist_ok=True)
	results = {}
	for name, fn in _V2_CASES.items():
		if only and name not in only:
			continue
		try:
			results[name] = {"ok": True, "error": None, "detail": fn(out_dir)}
		except Exception as exc:  # noqa: BLE001 -- un cas qui plante est un echec de test, pas un crash du harnais
			results[name] = {"ok": False, "error": f"{type(exc).__name__}: {exc}", "detail": None,
				"traceback": traceback.format_exc()}
	print(V2_MARKER + json.dumps({"cases": results}, ensure_ascii=False))


if __name__ == "__main__":
	if V2_FLAG in sys.argv:
		_v2_cases_main()
	else:
		unittest.main()
