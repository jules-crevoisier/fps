#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/blender/tests/test_ai_import_painted.py
Tests de tools/blender/ai_import_painted.py (ART-80).

Deux familles de cas, séparées par leur dépendance à Blender :

1. Manifeste + calculs purs (`parse_manifest`, `resolve_manifest_entry`,
   `scale_factor_for_height`, `resolved_texture_size`, `build_jobs`) —
   AUCUNE de ces fonctions ne touche `bpy` (voir l'en-tête de
   ai_import_painted.py : le module importe `bpy` dans un bloc try/except
   plutôt que sans garde, précisément pour rester importable ici). Ces tests
   importent donc le module DIRECTEMENT, en Python normal, sans lancer
   Blender — rapides, lancés à chaque itération.

2. Pipeline géométrique réel (nettoyage, budget, matériau peint conservé,
   export) — dépend de `bpy`/`bmesh`, donc relance Blender EN SOUS-PROCESS
   (une seule fois, `setUpClass`, coût amorti sur tous les cas), exactement
   comme tools/blender/tests/test_ai_restyle.py : un script de fixtures
   (`_CASES_SCRIPT`, écrit dans un fichier temporaire à l'exécution — ce
   fichier de test reste le SEUL fichier `.py` que ART-80 ajoute à ce
   dossier) construit une mesh synthétique par critère, imprime
   `AI_IMPORT_PAINTED_CASES_RESULT <json>` en dernière ligne de stdout ;
   chaque `test_*` ci-dessous relit ce résultat déjà calculé.

Blender : `BLENDER_BIN` (variable d'environnement, même convention que
`GODOT_BIN` dans tools/test.sh) sinon le chemin connu de CLAUDE.md.

Lancer :
    python -m pytest tools/blender/tests/test_ai_import_painted.py -q
    (ou, sans pytest : python tools/blender/tests/test_ai_import_painted.py)
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_BLENDER_DIR = os.path.dirname(HERE)
REPO_ROOT = os.path.abspath(os.path.join(TOOLS_BLENDER_DIR, "..", ".."))
MANIFEST_PATH = os.path.join(REPO_ROOT, "tools", "ai3d", "manifests", "painted_env.yaml")

sys.path.insert(0, TOOLS_BLENDER_DIR)
import ai_import_painted as aip  # noqa: E402


# ---------------------------------------------------------------------------
# Famille 1 — manifeste + calculs purs (aucun bpy, aucun sous-process Blender)
# ---------------------------------------------------------------------------

class TestParseManifest(unittest.TestCase):
	"""Sous-ensemble YAML restreint de `parse_manifest` (voir sa docstring) —
	sur le manifeste RÉEL du dépôt : garantit que painted_env.yaml reste
	conforme au schéma que ce script attend, pas seulement à une fixture."""

	@classmethod
	def setUpClass(cls):
		with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
			cls.manifest = aip.parse_manifest(f.read())

	def test_top_level_fields_present(self):
		self.assertIn("output_dir", self.manifest)
		self.assertIn("min_island_ratio", self.manifest)
		self.assertIn("merge_ratio", self.manifest)
		self.assertEqual(self.manifest["output_dir"], "assets/models/props/wasteland/tripo")
		self.assertAlmostEqual(self.manifest["min_island_ratio"], 0.01)

	def test_seven_wasteland_landmarks_declared(self):
		# Les 7 repères d'ART-80 restent déclarés ; le manifeste a grandi par blocs
		# documentés (ART-83 bâtiments, ART-89 grappes, ART-93 assets v4).
		ids = sorted(a["id"] for a in self.manifest["assets"])
		self.assertEqual(ids, sorted([
			"wl_water_tower", "wl_oil_derrick", "wl_crane_lattice", "wl_fuel_billboard",
			"wl_canopy_station", "wl_gas_billboard", "wl_tank_horizontal",
			"wl_saloon", "wl_fuel_store", "wl_garage", "wl_shack",
			"wl_car_wreck", "wl_fence_broken", "wl_market_stall", "wl_junk_pile",
			"wl_wagon", "wl_saloon_long", "wl_poste", "wl_diligence", "wl_eolienne",
		]))
		self.assertEqual(len(ids), len(set(ids)), "id en double dans le manifeste")

	def test_every_asset_has_the_six_required_fields(self):
		for entry in self.manifest["assets"]:
			self.assertEqual(
				set(entry.keys()),
				{"id", "source", "height_m", "budget_tris", "texture_size", "notes"},
				entry.get("id"))

	def test_every_source_file_exists_on_disk(self):
		for entry in self.manifest["assets"]:
			path = os.path.join(REPO_ROOT, entry["source"])
			self.assertTrue(os.path.isfile(path), f"{entry['id']}: {path} introuvable")

	def test_every_budget_is_within_the_art80_hard_cap(self):
		# ART-80 : « <= 6 000 tris chacun ».
		for entry in self.manifest["assets"]:
			self.assertLessEqual(entry["budget_tris"], 6000, entry["id"])
			self.assertGreater(entry["budget_tris"], 0, entry["id"])

	def test_every_texture_size_is_an_allowed_value(self):
		for entry in self.manifest["assets"]:
			self.assertIn(entry["texture_size"], aip.ALLOWED_TEXTURE_SIZES, entry["id"])

	def test_explicit_art80_height_ranges_are_respected(self):
		# Les trois cotes EXPLICITEMENT données par le contrat ART-80.
		by_id = {a["id"]: a for a in self.manifest["assets"]}
		self.assertTrue(9.0 <= by_id["wl_water_tower"]["height_m"] <= 11.0)
		self.assertTrue(14.0 <= by_id["wl_oil_derrick"]["height_m"] <= 18.0)
		self.assertTrue(5.0 <= by_id["wl_fuel_billboard"]["height_m"] <= 7.0)
		self.assertTrue(5.0 <= by_id["wl_gas_billboard"]["height_m"] <= 7.0)

	def test_comment_only_and_blank_lines_are_ignored(self):
		text = """
# un commentaire
output_dir: out
min_island_ratio: 0.01
merge_ratio: 0.0005

assets:
# commentaire dans la liste
- id: a
  source: s/a.glb
  height_m: 1.0
  budget_tris: 100
  texture_size: 1024
  notes: 'rien'
"""
		manifest = aip.parse_manifest(text)
		self.assertEqual(len(manifest["assets"]), 1)
		self.assertEqual(manifest["assets"][0]["id"], "a")

	def test_single_quote_escaping_matches_yaml_convention(self):
		text = (
			"output_dir: out\nmin_island_ratio: 0.01\nmerge_ratio: 0.0005\nassets:\n"
			"- id: a\n  source: s/a.glb\n  height_m: 1.0\n  budget_tris: 100\n"
			"  texture_size: 1024\n  notes: 'l''auvent s''ouvre'\n"
		)
		manifest = aip.parse_manifest(text)
		self.assertEqual(manifest["assets"][0]["notes"], "l'auvent s'ouvre")

	def test_invalid_top_level_line_raises_value_error(self):
		with self.assertRaises(ValueError):
			aip.parse_manifest("ceci n'est pas une ligne cle: valeur valide\nmais ceci oui")

	def test_invalid_line_inside_assets_raises_value_error(self):
		text = "output_dir: out\nassets:\n- id: a\nceci ne commence ni par '-' ni par une indentation\n"
		with self.assertRaises(ValueError):
			aip.parse_manifest(text)


class TestResolveManifestEntry(unittest.TestCase):
	def setUp(self):
		self.manifest = {"assets": [{"id": "wl_water_tower", "height_m": 10.0}]}

	def test_known_id_returns_its_entry(self):
		entry = aip.resolve_manifest_entry(self.manifest, "wl_water_tower")
		self.assertEqual(entry["height_m"], 10.0)

	def test_unknown_id_raises_key_error_listing_known_ids(self):
		with self.assertRaises(KeyError) as ctx:
			aip.resolve_manifest_entry(self.manifest, "nope")
		self.assertIn("wl_water_tower", str(ctx.exception))


class TestScaleFactorForHeight(unittest.TestCase):
	def test_computes_ratio(self):
		self.assertAlmostEqual(aip.scale_factor_for_height(2.0, 10.0), 5.0)

	def test_identity_when_already_at_target(self):
		self.assertAlmostEqual(aip.scale_factor_for_height(4.0, 4.0), 1.0)

	def test_rejects_non_positive_current_height(self):
		with self.assertRaises(ValueError):
			aip.scale_factor_for_height(0.0, 5.0)

	def test_rejects_non_positive_target_height(self):
		with self.assertRaises(ValueError):
			aip.scale_factor_for_height(2.0, -1.0)


class TestResolvedTextureSize(unittest.TestCase):
	def test_keeps_size_when_original_matches_requested(self):
		self.assertEqual(aip.resolved_texture_size(2048, 2048), 2048)

	def test_never_upscales_beyond_original(self):
		self.assertEqual(aip.resolved_texture_size(1600, 2048), 1024)

	def test_downscales_to_requested_when_original_is_bigger(self):
		self.assertEqual(aip.resolved_texture_size(4096, 1024), 1024)

	def test_keeps_native_size_when_smaller_than_the_smallest_allowed(self):
		self.assertEqual(aip.resolved_texture_size(900, 2048), 900)

	def test_rejects_size_outside_allowed_values(self):
		with self.assertRaises(ValueError):
			aip.resolved_texture_size(2048, 512)

	def test_rejects_non_positive_original_size(self):
		with self.assertRaises(ValueError):
			aip.resolved_texture_size(0, 2048)


class TestBuildJobs(unittest.TestCase):
	def setUp(self):
		self.root = os.path.join("C:\\", "repo")
		self.manifest = {
			"output_dir": "assets/models/props/wasteland/tripo",
			"min_island_ratio": 0.02,
			"merge_ratio": 0.001,
			"assets": [
				{"id": "wl_a", "source": "assets/incoming/tripo/studio/wl_a.glb",
					"height_m": 5.0, "budget_tris": 4000, "texture_size": 1024},
				{"id": "wl_b", "source": "assets/incoming/tripo/studio/wl_b.glb",
					"height_m": 6.0, "budget_tris": 3000, "texture_size": 2048},
			],
		}

	def test_all_mode_builds_one_job_per_manifest_entry(self):
		jobs = aip.build_jobs({"process_all": True}, self.manifest, self.root)
		self.assertEqual(len(jobs), 2)
		ids = sorted(j["id"] for j in jobs)
		self.assertEqual(ids, ["wl_a", "wl_b"])

	def test_all_mode_output_path_is_output_dir_slash_id(self):
		jobs = aip.build_jobs({"process_all": True}, self.manifest, self.root)
		job = next(j for j in jobs if j["id"] == "wl_a")
		self.assertEqual(
			os.path.normpath(job["out_path"]),
			os.path.normpath(os.path.join(self.root, "assets/models/props/wasteland/tripo", "wl_a.glb")))

	def test_all_mode_inherits_manifest_ratios(self):
		jobs = aip.build_jobs({"process_all": True}, self.manifest, self.root)
		job = next(j for j in jobs if j["id"] == "wl_a")
		self.assertAlmostEqual(job["merge_ratio"], 0.001)
		self.assertAlmostEqual(job["island_min_ratio"], 0.02)

	def test_all_mode_without_manifest_raises(self):
		with self.assertRaises(ValueError):
			aip.build_jobs({"process_all": True}, None, self.root)

	def test_id_mode_resolves_single_entry(self):
		jobs = aip.build_jobs({"asset_id": "wl_b"}, self.manifest, self.root)
		self.assertEqual(len(jobs), 1)
		self.assertEqual(jobs[0]["height_m"], 6.0)
		self.assertEqual(jobs[0]["budget_tris"], 3000)

	def test_id_mode_out_path_override_wins(self):
		jobs = aip.build_jobs(
			{"asset_id": "wl_b", "out_path": "custom/dest.glb"}, self.manifest, self.root)
		self.assertEqual(
			os.path.normpath(jobs[0]["out_path"]),
			os.path.normpath(os.path.join(self.root, "custom/dest.glb")))

	def test_id_mode_without_manifest_raises(self):
		with self.assertRaises(ValueError):
			aip.build_jobs({"asset_id": "wl_b"}, None, self.root)

	def test_id_mode_unknown_id_raises_key_error(self):
		with self.assertRaises(KeyError):
			aip.build_jobs({"asset_id": "nope"}, self.manifest, self.root)

	def test_direct_cli_mode_builds_single_job_from_scalars(self):
		cli = {
			"in_path": "assets/incoming/tripo/studio/wl_c.glb",
			"out_path": "assets/models/props/wasteland/tripo/wl_c.glb",
			"height_m": 7.5, "budget_tris": 5000, "texture_size": 2048,
		}
		jobs = aip.build_jobs(cli, None, self.root)
		self.assertEqual(len(jobs), 1)
		self.assertEqual(jobs[0]["id"], "wl_c")
		self.assertEqual(jobs[0]["height_m"], 7.5)
		self.assertEqual(jobs[0]["budget_tris"], 5000)

	def test_direct_cli_mode_defaults_budget_and_texture_size(self):
		cli = {
			"in_path": "assets/incoming/tripo/studio/wl_c.glb",
			"out_path": "assets/models/props/wasteland/tripo/wl_c.glb",
			"height_m": 7.5,
		}
		jobs = aip.build_jobs(cli, None, self.root)
		self.assertEqual(jobs[0]["budget_tris"], aip.DEFAULT_BUDGET_TRIS)
		self.assertEqual(jobs[0]["texture_size"], aip.DEFAULT_TEXTURE_SIZE)

	def test_direct_cli_mode_without_height_raises(self):
		cli = {"in_path": "x.glb", "out_path": "y.glb"}
		with self.assertRaises(ValueError):
			aip.build_jobs(cli, None, self.root)

	def test_direct_cli_mode_without_in_path_raises(self):
		with self.assertRaises(ValueError):
			aip.build_jobs({}, None, self.root)

	def test_direct_cli_mode_without_out_path_raises(self):
		cli = {"in_path": "x.glb", "height_m": 1.0}
		with self.assertRaises(ValueError):
			aip.build_jobs(cli, None, self.root)


# ---------------------------------------------------------------------------
# Famille 2 — pipeline géométrique réel (Blender en sous-process)
# ---------------------------------------------------------------------------

def _blender_bin() -> str:
	env = os.environ.get("BLENDER_BIN")
	if env:
		return env
	return r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"


# Script de fixtures — voir la docstring de tête de ce fichier : écrit dans un
# fichier temporaire à l'exécution plutôt que commité séparément (ART-80 ne
# possède que CE fichier de test dans tools/blender/tests/). Mêmes conventions
# que tools/blender/tests/_ai_restyle_cases.py (import direct de
# ai_import_painted/toonkit/check_asset, un `case_*` par critère, résultat
# imprimé en JSON sur un marqueur de dernière ligne).
_CASES_SCRIPT_TEMPLATE = r'''#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import annotations

import argparse
import json
import os
import random
import sys
import traceback

import bpy
import bmesh
from mathutils import Vector

REPO = {repo!r}
sys.path.insert(0, os.path.join(REPO, "tools", "blender"))
sys.path.insert(0, os.path.join(REPO, "tools", "blender", "lib"))
import ai_import_painted as aip  # noqa: E402
import toonkit  # noqa: E402
import check_asset  # noqa: E402


def parse_args():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	p = argparse.ArgumentParser()
	p.add_argument("--out-dir", required=True)
	return p.parse_args(argv)


def _make_box(name, size, loc):
	bpy.ops.mesh.primitive_cube_add(size=1.0)
	obj = bpy.context.active_object
	obj.name = name
	obj.scale = size
	obj.location = loc
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	return obj


def _make_rich_image(name, w, h):
	"""Image proceduralement riche en couleurs -- verifie qu'aucune
	quantification ne survient (jamais un aplat de palette)."""
	img = bpy.data.images.new(name, width=w, height=h, alpha=False)
	pixels = [0.0] * (w * h * 4)
	rnd = random.Random(42)
	for y in range(h):
		for x in range(w):
			i = (y * w + x) * 4
			pixels[i + 0] = ((x * 37 + y * 17) % 256) / 255.0
			pixels[i + 1] = ((x * 53 + y * 91 + rnd.randint(0, 9)) % 256) / 255.0
			pixels[i + 2] = ((x * 13 + y * 61) % 256) / 255.0
			pixels[i + 3] = 1.0
	img.pixels = pixels
	img.pack()
	return img


def _make_textured_material(name, image):
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	nt = mat.node_tree
	bsdf = nt.nodes.get("Principled BSDF")
	tex = nt.nodes.new("ShaderNodeTexImage")
	tex.image = image
	nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
	return mat


def _uv_unwrap(obj):
	with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj]):
		bpy.ops.object.mode_set(mode='EDIT')
		bpy.ops.mesh.select_all(action='SELECT')
		bpy.ops.uv.smart_project()
		bpy.ops.object.mode_set(mode='OBJECT')


def _unique_colors(image, sample=2000):
	pixels = list(image.pixels)
	w, h = image.size
	total = w * h
	seen = set()
	step = max(1, total // sample)
	for i in range(0, total, step):
		base = i * 4
		seen.add((round(pixels[base], 3), round(pixels[base + 1], 3), round(pixels[base + 2], 3)))
	return len(seen)


def case_small_island_removed_legit_kept(out_dir):
	"""ART-80 : "retrait des ilots < 1% de la diagonale" -- un debris minuscule
	disparait, un second ilot LEGITIME (assemblage multi-pieces, ex. une jambe
	de derrick) largement au-dessus du seuil survit intact."""
	toonkit.reset_scene()
	main = _make_box("main", (2.0, 2.0, 2.0), (0, 0, 0))
	debris = _make_box("debris", (0.02, 0.02, 0.02), (5.0, 5.0, 5.0))
	legit = _make_box("legit_leg", (0.5, 0.5, 0.5), (3.0, 0.0, 0.0))
	obj = toonkit.join([main, legit, debris])
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	before_islands = [len(comp) for comp in aip._face_islands(bm)]
	bm.free()
	removed = aip.remove_small_islands(obj, min_ratio=aip.MIN_ISLAND_RATIO)
	bm2 = bmesh.new()
	bm2.from_mesh(obj.data)
	after_islands = [len(comp) for comp in aip._face_islands(bm2)]
	bm2.free()
	return {{
		"ok": True,
		"before_islands": sorted(before_islands, reverse=True),
		"after_islands": sorted(after_islands, reverse=True),
		"removed_faces": removed,
	}}


def case_texture_native_size_kept_when_smaller_than_requested(out_dir):
	toonkit.reset_scene()
	obj = _make_box("main", (1, 1, 1), (0, 0, 0))
	_uv_unwrap(obj)
	img = _make_rich_image("small_tex", 300, 300)
	mat = _make_textured_material("small_mat", img)
	obj.data.materials.append(mat)
	before_colors = _unique_colors(img)
	report = aip.keep_painted_materials(obj, 1024)
	after_img = bpy.data.images[report["materials"][0]["image"]]
	after_colors = _unique_colors(after_img)
	return {{
		"ok": True,
		"final_size": list(after_img.size),
		"before_colors": before_colors,
		"after_colors": after_colors,
		"materials_report": report["materials"],
	}}


def case_texture_downscaled_to_requested(out_dir):
	toonkit.reset_scene()
	obj = _make_box("main", (1, 1, 1), (0, 0, 0))
	_uv_unwrap(obj)
	img = _make_rich_image("big_tex", 1200, 1200)
	mat = _make_textured_material("big_mat", img)
	obj.data.materials.append(mat)
	report = aip.keep_painted_materials(obj, 1024)
	after_img = bpy.data.images[report["materials"][0]["image"]]
	after_colors = _unique_colors(after_img, sample=4000)
	return {{"ok": True, "final_size": list(after_img.size), "after_colors": after_colors}}


def _find_image_through_mix(mat):
	"""Comme ai_import_painted._material_image_node, mais suit aussi un noeud
	Mix vertex-color x albedo -- Blender reimporte un glTF qui porte COLOR_0
	en rebranchant la Base Color via un Mix (voir ai_restyle.py::_read_albedo).
	Utilise SEULEMENT pour verifier, apres coup, qu'une image survit dans le
	fichier EXPORTE : jamais rencontre par le pipeline de production lui-meme,
	qui tourne toujours AVANT tout bake vertex color."""
	if mat is None or not mat.use_nodes or mat.node_tree is None:
		return None
	bsdf = mat.node_tree.nodes.get("Principled BSDF")
	if bsdf is None or "Base Color" not in bsdf.inputs:
		return None
	socket = bsdf.inputs["Base Color"]
	if not socket.is_linked:
		return None
	src = socket.links[0].from_node
	if src.type == 'TEX_IMAGE' and src.image is not None:
		return src.image
	if src.type == 'MIX':
		for inp in src.inputs:
			if inp.type == 'RGBA' and inp.is_linked:
				up = inp.links[0].from_node
				if up.type == 'TEX_IMAGE' and up.image is not None:
					return up.image
	return None


def case_full_pipeline(out_dir):
	"""Critere d'acceptation bout-en-bout : import -> nettoyage (debris
	retire) -> budget -> masques -> echelle/origine -> export, puis
	REIMPORT du fichier ecrit sur disque pour verifier l'etat REEL (jamais
	seulement l'etat en memoire) : tri budget tenu, hauteur cible atteinte,
	AO+Curvature+normale lissee presents, texture toujours presente et non
	quantifiee, sidecar augmente (painted/source), check_asset.py PASSE."""
	toonkit.reset_scene()
	main = _make_box("main", (2.0, 2.0, 2.0), (0, 0, 0))
	_uv_unwrap(main)
	img = _make_rich_image("painted_tex", 1200, 1200)
	mat = _make_textured_material("painted_mat", img)
	main.data.materials.append(mat)
	debris = _make_box("debris", (0.02, 0.02, 0.02), (5.0, 5.0, 5.0))
	obj = toonkit.join([main, debris])
	# Transform non triviale (echelle non uniforme + rotation + position hors
	# origine), comme un GLB IA brut -- verifie scale/apply_transforms/
	# set_origin_bottom sur un cas non deja a l'identite.
	obj.location = (10.0, -3.0, 4.0)
	obj.rotation_euler = (0.1, 0.2, 0.3)
	obj.scale = (1.3, 0.8, 1.1)
	fixture_path = os.path.join(out_dir, "fixture_raw.glb")
	toonkit.export_glb(fixture_path, obj, write_report=False)

	out_path = os.path.join(out_dir, "wl_fixture.glb")
	report = aip.process_painted_asset(
		fixture_path, out_path, height_m=10.0, budget_tris=6000, texture_size=1024,
		skip_turntable=True)

	toonkit.reset_scene()
	reimported = aip.import_asset(out_path)
	if len(reimported) != 1:
		return {{"ok": False, "error": f"attendu 1 objet mesh reimporte, obtenu {{len(reimported)}}"}}
	robj = reimported[0]
	me = robj.data
	corners = [robj.matrix_world @ Vector(c) for c in robj.bound_box]
	min_z = min(c.z for c in corners)
	max_z = max(c.z for c in corners)
	height = max_z - min_z
	color_attr_names = sorted(a.name for a in me.color_attributes)
	custom_attr_names = sorted(a.name for a in me.attributes if a.name.startswith("_"))
	image = _find_image_through_mix(me.materials[0])
	has_image = image is not None
	image_size = list(image.size) if image is not None else None
	tris = toonkit.tri_count(robj)  # AVANT check_asset.run() : il reset la scene (invalide robj/image)

	with open(os.path.splitext(out_path)[0] + ".json", "r", encoding="utf-8") as f:
		sidecar = json.load(f)

	check_report = check_asset.run(out_path, budget_tris=6000)

	return {{
		"ok": True,
		"process_report": {{
			"final_tris": report["final_tris"],
			"removed_island_faces": report["removed_island_faces"],
			"scale_factor": report["scale_factor"],
			"floating_islands": report["floating_islands"],
		}},
		"reimport": {{
			"n_objects": len(reimported), "height": height, "tris": tris,
			"color_attrs": color_attr_names, "custom_attrs": custom_attr_names,
			"has_image": has_image, "image_size": image_size,
		}},
		"sidecar": sidecar,
		"check_asset_failures": check_report.get("failures", []),
	}}


def case_decimate_reduces_to_budget(out_dir):
	toonkit.reset_scene()
	bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4, radius=1.0)
	obj = bpy.context.active_object
	before = toonkit.tri_count(obj)
	final = aip.decimate_to_budget(obj, 300)
	return {{"ok": True, "before_tris": before, "final_tris": final}}


def case_decimate_noop_under_budget(out_dir):
	toonkit.reset_scene()
	obj = _make_box("main", (1, 1, 1), (0, 0, 0))
	before = toonkit.tri_count(obj)
	final = aip.decimate_to_budget(obj, 6000)
	return {{"ok": True, "before_tris": before, "final_tris": final, "modifiers": len(obj.modifiers)}}


def case_real_delivered_assets_check_asset(out_dir):
	"""Correction QA ART-80 (verification independante) : contrairement a
	`case_full_pipeline` (une seule mesh synthetique), ce cas fait tourner
	check_asset.py::run sur les 7 REPERES REELLEMENT LIVRES (assets/models/
	props/wasteland/tripo/wl_*.glb), avec le budget de tris DE CHAQUE repere
	(painted_env.yaml) -- jamais un budget generique. Renvoie, par id,
	{{"tris": int, "budget_tris": int, "failures": [str, ...]}} tel quel (les
	assertions de type de defaut restent cote test Python, pas ici)."""
	with open(os.path.join(REPO, "tools", "ai3d", "manifests", "painted_env.yaml"),
			"r", encoding="utf-8") as f:
		manifest = aip.parse_manifest(f.read())
	results = {{}}
	for entry in manifest["assets"]:
		asset_id = entry["id"]
		glb_path = os.path.join(REPO, manifest["output_dir"], f"{{asset_id}}.glb")
		report = check_asset.run(glb_path, budget_tris=entry["budget_tris"])
		results[asset_id] = {{
			"tris": report["tris"],
			"budget_tris": entry["budget_tris"],
			"failures": report["failures"],
		}}
	return {{"ok": True, "assets": results}}


CASES = {{
	"small_island_removed_legit_kept": case_small_island_removed_legit_kept,
	"texture_native_size_kept_when_smaller_than_requested": case_texture_native_size_kept_when_smaller_than_requested,
	"texture_downscaled_to_requested": case_texture_downscaled_to_requested,
	"full_pipeline": case_full_pipeline,
	"decimate_reduces_to_budget": case_decimate_reduces_to_budget,
	"decimate_noop_under_budget": case_decimate_noop_under_budget,
	"real_delivered_assets_check_asset": case_real_delivered_assets_check_asset,
}}


def main():
	args = parse_args()
	out_dir = os.path.abspath(args.out_dir)
	os.makedirs(out_dir, exist_ok=True)
	results = {{}}
	for name, fn in CASES.items():
		case_dir = os.path.join(out_dir, name)
		os.makedirs(case_dir, exist_ok=True)
		try:
			results[name] = fn(case_dir)
		except Exception as exc:  # noqa: BLE001
			results[name] = {{"ok": False, "error": f"{{exc}}\\n{{traceback.format_exc()}}"}}
	print("AI_IMPORT_PAINTED_CASES_RESULT " + json.dumps({{"cases": results}}))


if __name__ == "__main__":
	main()
'''


class _CasesRunner:
	"""Lance le script de fixtures UNE fois pour toute la classe de test et
	garde le résultat JSON en cache — même convention que
	test_ai_restyle.py::_CasesRunner."""
	_result = None
	_out_dir = None
	_script_path = None

	@classmethod
	def get(cls) -> dict:
		if cls._result is None:
			cls._out_dir = tempfile.mkdtemp(prefix="ai_import_painted_test_")
			script_text = _CASES_SCRIPT_TEMPLATE.format(repo=REPO_ROOT)
			fd, cls._script_path = tempfile.mkstemp(suffix="_ai_import_painted_cases.py")
			with os.fdopen(fd, "w", encoding="utf-8") as f:
				f.write(script_text)
			blender_bin = _blender_bin()
			if not os.path.isfile(blender_bin):
				raise unittest.SkipTest(
					f"Blender introuvable ({blender_bin!r}) — définir BLENDER_BIN pour lancer "
					"tools/blender/tests/test_ai_import_painted.py")
			cmd = [
				blender_bin, "-b", "--factory-startup", "--python-exit-code", "1",
				"-P", cls._script_path, "--", "--out-dir", cls._out_dir,
			]
			proc = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
			raw_output = proc.stdout + "\n--- stderr ---\n" + proc.stderr
			if proc.returncode != 0:
				raise AssertionError(
					f"le script de fixtures a planté (code {proc.returncode}) avant d'imprimer son "
					f"résultat :\n{raw_output}")
			marker = "AI_IMPORT_PAINTED_CASES_RESULT "
			line = next((ln for ln in proc.stdout.splitlines() if ln.startswith(marker)), None)
			if line is None:
				raise AssertionError(f"pas de marqueur {marker!r} dans la sortie :\n{raw_output}")
			cls._result = json.loads(line[len(marker):])["cases"]
		return cls._result

	@classmethod
	def case(cls, name: str) -> dict:
		results = cls.get()
		if name not in results:
			raise AssertionError(f"cas {name!r} absent du résultat : {sorted(results)}")
		return results[name]


class TestSmallIslandRemovedLegitKept(unittest.TestCase):
	"""ART-80 : "retrait des îlots < 1 % de la diagonale" — un débris minuscule
	disparaît, un assemblage légitime largement au-dessus du seuil survit."""

	def test_case_passes(self):
		result = _CasesRunner.case("small_island_removed_legit_kept")
		self.assertTrue(result["ok"], result.get("error"))

	def test_three_islands_before_two_after(self):
		result = _CasesRunner.case("small_island_removed_legit_kept")
		self.assertEqual(result["before_islands"], [6, 6, 6])
		self.assertEqual(result["after_islands"], [6, 6])

	def test_only_the_debris_faces_are_removed(self):
		result = _CasesRunner.case("small_island_removed_legit_kept")
		self.assertEqual(result["removed_faces"], 6)


class TestKeepPaintedMaterials(unittest.TestCase):
	"""ART-80 : « albédo conservé (redimensionné 1024 ou 2048, jamais
	quantifié) » — jamais remplacé par une couleur de palette."""

	def test_smaller_than_requested_case_passes(self):
		result = _CasesRunner.case("texture_native_size_kept_when_smaller_than_requested")
		self.assertTrue(result["ok"], result.get("error"))

	def test_smaller_original_is_never_upscaled(self):
		result = _CasesRunner.case("texture_native_size_kept_when_smaller_than_requested")
		self.assertEqual(result["final_size"], [300, 300])

	def test_smaller_original_keeps_its_material_flagged_as_textured(self):
		result = _CasesRunner.case("texture_native_size_kept_when_smaller_than_requested")
		self.assertTrue(result["materials_report"][0]["has_texture"])

	def test_color_richness_is_not_reduced_by_processing(self):
		result = _CasesRunner.case("texture_native_size_kept_when_smaller_than_requested")
		self.assertGreater(result["after_colors"], result["before_colors"] * 0.9)

	def test_downscale_case_passes(self):
		result = _CasesRunner.case("texture_downscaled_to_requested")
		self.assertTrue(result["ok"], result.get("error"))

	def test_bigger_original_is_downscaled_to_requested_allowed_size(self):
		result = _CasesRunner.case("texture_downscaled_to_requested")
		self.assertEqual(result["final_size"], [1024, 1024])

	def test_downscaled_texture_still_carries_many_distinct_colors(self):
		# Preuve qu'aucune quantification en palette n'a eu lieu (un
		# redimensionnement bilinéaire garde une image riche, jamais aplatie).
		result = _CasesRunner.case("texture_downscaled_to_requested")
		self.assertGreater(result["after_colors"], 1000)


class TestDecimateToBudget(unittest.TestCase):
	def test_reduces_case_passes(self):
		result = _CasesRunner.case("decimate_reduces_to_budget")
		self.assertTrue(result["ok"], result.get("error"))

	def test_dense_mesh_is_reduced_under_budget(self):
		result = _CasesRunner.case("decimate_reduces_to_budget")
		self.assertGreater(result["before_tris"], 300)
		self.assertLessEqual(result["final_tris"], 300)

	def test_noop_case_passes(self):
		result = _CasesRunner.case("decimate_noop_under_budget")
		self.assertTrue(result["ok"], result.get("error"))

	def test_mesh_already_under_budget_is_left_untouched(self):
		result = _CasesRunner.case("decimate_noop_under_budget")
		self.assertEqual(result["final_tris"], result["before_tris"])
		self.assertEqual(result["modifiers"], 0)


class TestFullPipeline(unittest.TestCase):
	"""Critère d'acceptation bout-en-bout ART-80 : import -> nettoyage ->
	budget -> masques -> échelle/origine -> export, vérifié sur le fichier
	RÉELLEMENT écrit sur disque (jamais seulement l'état en mémoire)."""

	def test_case_passes(self):
		result = _CasesRunner.case("full_pipeline")
		self.assertTrue(result["ok"], result.get("error"))

	def test_debris_island_is_removed_before_export(self):
		result = _CasesRunner.case("full_pipeline")
		self.assertEqual(result["reimport"]["n_objects"], 1)
		self.assertEqual(result["process_report"]["removed_island_faces"], 12)
		self.assertEqual(result["reimport"]["tris"], 12)

	def test_debris_gap_is_reported_not_silently_fixed(self):
		# ART-80 (correction QA) : `remove_small_islands` (taille) retire déjà ce
		# débris avant que `detect_floating_islands` (diagnostic pur, jamais un
		# retrait — voir sa docstring) ne le voie ; sur ce fixture précis, aucun
		# îlot flottant ne devrait donc rester à signaler.
		result = _CasesRunner.case("full_pipeline")
		self.assertEqual(result["process_report"]["floating_islands"], [])

	def test_exported_asset_reaches_the_manifest_height(self):
		result = _CasesRunner.case("full_pipeline")
		self.assertAlmostEqual(result["reimport"]["height"], 10.0, delta=0.01)

	def test_ao_and_curvature_vertex_colors_are_present(self):
		result = _CasesRunner.case("full_pipeline")
		self.assertIn("AO", result["sidecar"]["color_attributes"])
		self.assertIn("Curvature", result["sidecar"]["color_attributes"])
		self.assertTrue(result["sidecar"]["ao"])
		self.assertTrue(result["sidecar"]["curvature"])

	def test_smooth_normal_attribute_is_present(self):
		result = _CasesRunner.case("full_pipeline")
		self.assertTrue(result["sidecar"]["smooth_normal"])
		self.assertIn("_SMOOTH_NORMAL", result["reimport"]["custom_attrs"])

	def test_albedo_texture_survives_export_resized_to_requested_size(self):
		result = _CasesRunner.case("full_pipeline")
		self.assertTrue(result["reimport"]["has_image"])
		self.assertEqual(result["reimport"]["image_size"], [1024, 1024])

	def test_sidecar_is_augmented_with_painted_and_source(self):
		result = _CasesRunner.case("full_pipeline")
		self.assertTrue(result["sidecar"]["painted"])
		self.assertTrue(result["sidecar"]["source"].endswith("fixture_raw.glb"))

	def test_final_tris_within_budget(self):
		result = _CasesRunner.case("full_pipeline")
		self.assertLessEqual(result["process_report"]["final_tris"], 6000)

	def test_check_asset_reports_no_hard_failure(self):
		result = _CasesRunner.case("full_pipeline")
		self.assertEqual(result["check_asset_failures"], [])


# Non-manifold : `wl_crane_lattice` est la SEULE exception connue et VÉRIFIÉE
# (voir `_repair_slivers_if_safe`/la note de tête de ai_import_painted.py) —
# son treillis brut Tripo Studio porte plusieurs centaines d'arêtes
# non-manifold qu'AUCUNE réparation locale ne peut retirer sans fracturer le
# maillage (essayé, refusé automatiquement par le pipeline lui-même). Jamais
# une valeur devinée : documentée ici pour que ce test échoue fort si un
# AUTRE repère se met un jour à échouer sur ce même critère (régression) ou
# si `wl_crane_lattice` se met, lui, à PASSER (le pipeline serait alors plus
# sûr que prévu — à documenter, jamais un échec de test à corriger en
# élargissant la liste en silence).
# Sorties Smart Mesh d'ART-83 (saloon 28, fuel_store 158, garage 111, shack 73 arêtes) et
# d'ART-89 (car_wreck 22, junk_pile 10) : arêtes à >= 3 faces sur galeries, auvents et
# tôles fines — maillages VISUELS seuls (collisions = boîtes de la scène), sans effet au
# rendu ; les assets HD d'ART-93 en ont 0. Exemption levée asset par asset si corrigé.
KNOWN_NONMANIFOLD_EXEMPTIONS = frozenset({
	"wl_crane_lattice", "wl_saloon", "wl_fuel_store", "wl_garage", "wl_shack",
	"wl_car_wreck", "wl_junk_pile",
})


class TestRealDeliveredAssetsCheckAsset(unittest.TestCase):
	"""Correction QA ART-80 : le retour du vérificateur notait que
	`test_check_asset_reports_no_hard_failure` (ci-dessus) ne prouve que
	l'absence d'échec dur sur une mesh SYNTHÉTIQUE, jamais sur les 7 fichiers
	.glb RÉELLEMENT livrés — ces tests-ci font tourner check_asset.py::run
	sur CES fichiers, avec le budget de tris DE CHAQUE repère
	(painted_env.yaml), et vérifient honnêtement ce qui est RÉELLEMENT
	garanti (aucune mesh vide/sommet orphelin/dépassement de budget ; arête
	non-manifold réparée partout sauf l'exemption documentée ci-dessus) SANS
	prétendre que les 7 repères passent check_asset.py au complet : CHK-16
	(pièce déconnectée) reste un écart RÉEL sur plusieurs de ces repères
	(barreaux d'échelle, jambes, pieds — jamais des assemblages illégitimes,
	voir `detect_floating_islands`), documenté et signalé, jamais
	silencieusement supprimé par une heuristique qui a, par le passé
	(vérifié en rendu pendant cette même tâche), amputé le repère entier."""

	def test_no_asset_has_an_empty_mesh_or_orphan_vertices(self):
		result = _CasesRunner.case("real_delivered_assets_check_asset")
		self.assertTrue(result["ok"], result.get("error"))
		for asset_id, info in result["assets"].items():
			for failure in info["failures"]:
				self.assertNotIn("mesh vide", failure, asset_id)
				self.assertNotIn("sommet(s) orphelin(s)", failure, asset_id)

	def test_every_asset_stays_within_its_manifest_budget(self):
		result = _CasesRunner.case("real_delivered_assets_check_asset")
		for asset_id, info in result["assets"].items():
			self.assertLessEqual(info["tris"], info["budget_tris"], asset_id)

	def test_nonmanifold_edges_are_fixed_except_the_documented_exemption(self):
		result = _CasesRunner.case("real_delivered_assets_check_asset")
		for asset_id, info in result["assets"].items():
			nonmanifold_failures = [f for f in info["failures"] if "non-manifold" in f]
			if asset_id in KNOWN_NONMANIFOLD_EXEMPTIONS:
				self.assertTrue(nonmanifold_failures, (
					f"{asset_id}: exemption documentée mais aucune arête non-manifold "
					"trouvée — retirer de KNOWN_NONMANIFOLD_EXEMPTIONS si corrigé"))
			else:
				self.assertEqual(nonmanifold_failures, [], asset_id)

	def test_only_known_failure_categories_survive(self):
		# Honnêteté du rapport (retour QA ART-80) : toute défaillance HORS des
		# deux catégories connues (non-manifold sur l'exemption documentée,
		# pièce déconnectée CHK-16) ferait échouer ce test — jamais une
		# régression silencieuse sur un défaut encore différent.
		result = _CasesRunner.case("real_delivered_assets_check_asset")
		for asset_id, info in result["assets"].items():
			for failure in info["failures"]:
				allowed = "pièce déconnectée" in failure or (
					"non-manifold" in failure and asset_id in KNOWN_NONMANIFOLD_EXEMPTIONS)
				self.assertTrue(allowed, f"{asset_id}: échec inattendu — {failure!r}")


if __name__ == "__main__":
	unittest.main()
