#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/blender/tests/test_fit_weapon_painted.py
Tests de tools/blender/fit_weapon_painted.py (A3D-20).

Deux familles de cas, séparées par leur dépendance à Blender — même convention
que tools/blender/tests/test_ai_import_painted.py :

1. Manifeste + calculs purs (`parse_manifest`, `resolve_manifest_entry`,
   `resolved_texture_size`, `longest_axis_index`, `pick_muzzle_sign`,
   `rotation_for_alignment`, `scale_factor_for_length`, `forward_translation`,
   `lateral_center_translation`, `build_jobs`) — AUCUNE de ces fonctions ne
   touche `bpy` (voir l'en-tête de fit_weapon_painted.py : import dans un bloc
   try/except). Import direct du module, sans lancer Blender.

2. Pipeline géométrique réel (alignement canon/longueur/pivot, matériau peint
   conservé, ancres Muzzle/Foregrip reprises, budget de tris, sauvegarde bpy)
   — dépend de `bpy`/`bmesh`, donc relance Blender EN SOUS-PROCESS (une seule
   fois, `setUpClass`) : un script de fixtures construit une "arme bpy" et une
   "source Tripo" synthétiques (mêmes invariants que les vraies livraisons —
   bbox Tripo centrée sur [-0.5, 0.5] le long de l'axe canon, base au sol),
   imprime `FIT_WEAPON_PAINTED_CASES_RESULT <json>` en dernière ligne de
   stdout ; chaque `test_*` ci-dessous relit ce résultat déjà calculé.

Blender : `BLENDER_BIN` (variable d'environnement) sinon le chemin connu de
CLAUDE.md.

Lancer :
    python -m pytest tools/blender/tests/test_fit_weapon_painted.py -q
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
MANIFEST_PATH = os.path.join(REPO_ROOT, "tools", "ai3d", "manifests", "painted_weapons.yaml")

sys.path.insert(0, TOOLS_BLENDER_DIR)
import fit_weapon_painted as fwp  # noqa: E402


# ---------------------------------------------------------------------------
# Famille 1 — manifeste + calculs purs (aucun bpy, aucun sous-process Blender)
# ---------------------------------------------------------------------------

class TestParseManifest(unittest.TestCase):
	"""Sur le manifeste RÉEL du dépôt — garantit qu'il reste conforme au schéma
	que ce script attend, pas seulement à une fixture."""

	@classmethod
	def setUpClass(cls):
		with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
			cls.manifest = fwp.parse_manifest(f.read())

	def test_top_level_fields_present(self):
		self.assertEqual(self.manifest["weapons_dir"], "assets/models/weapons")
		self.assertEqual(self.manifest["backup_dir"], "assets/models/weapons/_bpy")
		self.assertEqual(self.manifest["default_budget_tris"], 8000)
		self.assertEqual(self.manifest["default_texture_size"], 2048)

	def test_seven_weapons_declared(self):
		ids = sorted(w["id"] for w in self.manifest["weapons"])
		self.assertEqual(ids, sorted([
			"pistolet", "magnum", "rafale", "marqueur", "ravage", "fracas", "faucheur",
		]))

	def test_every_weapon_has_the_eight_required_fields(self):
		for entry in self.manifest["weapons"]:
			self.assertEqual(
				set(entry.keys()),
				{"id", "source", "budget_tris", "texture_size", "flip_muzzle", "z_offset",
					"x_offset", "notes"},
				entry.get("id"))

	def test_every_source_file_exists_on_disk(self):
		for entry in self.manifest["weapons"]:
			path = os.path.join(REPO_ROOT, entry["source"])
			self.assertTrue(os.path.isfile(path), f"{entry['id']}: {path} introuvable")

	def test_every_budget_is_within_the_a3d20_hard_cap(self):
		for entry in self.manifest["weapons"]:
			self.assertLessEqual(entry["budget_tris"], 8000, entry["id"])
			self.assertGreater(entry["budget_tris"], 0, entry["id"])

	def test_every_texture_size_is_an_allowed_value(self):
		for entry in self.manifest["weapons"]:
			self.assertIn(entry["texture_size"], fwp.ALLOWED_TEXTURE_SIZES, entry["id"])

	def test_every_bpy_reference_file_exists_on_disk(self):
		# La forme de référence vient TOUJOURS de la sauvegarde (voir
		# `resolve_bpy_reference_path`) — jamais du fichier courant, qui peut
		# déjà être une version peinte d'un run précédent.
		for entry in self.manifest["weapons"]:
			current = os.path.join(REPO_ROOT, self.manifest["weapons_dir"], f"{entry['id']}.glb")
			self.assertTrue(os.path.isfile(current), entry["id"])

	def test_comment_only_and_blank_lines_are_ignored(self):
		text = """
# un commentaire
weapons_dir: out
backup_dir: out/_bpy
default_budget_tris: 8000
default_texture_size: 2048

weapons:
# commentaire dans la liste
- id: a
  source: s/a.glb
  budget_tris: 8000
  texture_size: 2048
  flip_muzzle: false
  z_offset: 0.0
  x_offset: 0.0
  notes: 'rien'
"""
		manifest = fwp.parse_manifest(text)
		self.assertEqual(len(manifest["weapons"]), 1)
		self.assertEqual(manifest["weapons"][0]["id"], "a")
		self.assertEqual(manifest["weapons"][0]["flip_muzzle"], False)

	def test_invalid_top_level_line_raises_value_error(self):
		with self.assertRaises(ValueError):
			fwp.parse_manifest("ceci n'est pas une ligne cle: valeur valide\nmais ceci oui")

	def test_invalid_line_inside_weapons_raises_value_error(self):
		text = "weapons_dir: out\nweapons:\n- id: a\nceci ne commence ni par '-' ni par une indentation\n"
		with self.assertRaises(ValueError):
			fwp.parse_manifest(text)


class TestResolveManifestEntry(unittest.TestCase):
	def setUp(self):
		self.manifest = {"weapons": [{"id": "pistolet", "budget_tris": 8000}]}

	def test_known_id_returns_its_entry(self):
		entry = fwp.resolve_manifest_entry(self.manifest, "pistolet")
		self.assertEqual(entry["budget_tris"], 8000)

	def test_unknown_id_raises_key_error_listing_known_ids(self):
		with self.assertRaises(KeyError) as ctx:
			fwp.resolve_manifest_entry(self.manifest, "nope")
		self.assertIn("pistolet", str(ctx.exception))


class TestResolvedTextureSize(unittest.TestCase):
	def test_keeps_size_when_original_matches_requested(self):
		self.assertEqual(fwp.resolved_texture_size(2048, 2048), 2048)

	def test_never_upscales_beyond_original(self):
		self.assertEqual(fwp.resolved_texture_size(1600, 2048), 1024)

	def test_rejects_size_outside_allowed_values(self):
		with self.assertRaises(ValueError):
			fwp.resolved_texture_size(2048, 512)

	def test_rejects_non_positive_original_size(self):
		with self.assertRaises(ValueError):
			fwp.resolved_texture_size(0, 2048)


class TestLongestAxisIndex(unittest.TestCase):
	def test_x_is_longest(self):
		self.assertEqual(fwp.longest_axis_index((0.9995, 0.1733, 0.5171)), 0)

	def test_y_is_longest(self):
		self.assertEqual(fwp.longest_axis_index((0.0718, 0.9995, 0.3872)), 1)

	def test_z_is_longest(self):
		self.assertEqual(fwp.longest_axis_index((0.1, 0.2, 0.9)), 2)


class TestPickMuzzleSign(unittest.TestCase):
	"""L'extrémité la plus FINE (rayon le plus petit) est la bouche du canon —
	`+1` si c'est l'extrémité MAX de l'axe, `-1` si c'est l'extrémité MIN."""

	def test_thinner_max_end_is_the_muzzle(self):
		self.assertEqual(fwp.pick_muzzle_sign(radius_min_end=0.09, radius_max_end=0.02), 1)

	def test_thinner_min_end_is_the_muzzle(self):
		self.assertEqual(fwp.pick_muzzle_sign(radius_min_end=0.02, radius_max_end=0.09), -1)

	def test_tie_defaults_to_max_end(self):
		self.assertEqual(fwp.pick_muzzle_sign(radius_min_end=0.05, radius_max_end=0.05), 1)


class TestRotationForAlignment(unittest.TestCase):
	"""Bouche vers +Y (repère Blender après import glTF — voir l'en-tête de
	fit_weapon_painted.py), axe "haut" Z jamais perturbé."""

	def test_length_axis_x_muzzle_at_max_rotates_plus_90_z(self):
		self.assertEqual(fwp.rotation_for_alignment(0, muzzle_sign=1), (0.0, 0.0, 90.0))

	def test_length_axis_x_muzzle_at_min_rotates_minus_90_z(self):
		self.assertEqual(fwp.rotation_for_alignment(0, muzzle_sign=-1), (0.0, 0.0, -90.0))

	def test_length_axis_y_muzzle_at_max_is_identity(self):
		self.assertEqual(fwp.rotation_for_alignment(1, muzzle_sign=1), (0.0, 0.0, 0.0))

	def test_length_axis_y_muzzle_at_min_rotates_180_z(self):
		self.assertEqual(fwp.rotation_for_alignment(1, muzzle_sign=-1), (0.0, 0.0, 180.0))

	def test_length_axis_z_is_rejected(self):
		# Invariant Tripo Studio vérifié par sondage (voir l'en-tête du manifeste) :
		# l'axe "haut" est TOUJOURS Z — un axe canon détecté sur Z signale un
		# repère hors invariant, jamais une réorientation devinée en silence.
		with self.assertRaises(ValueError):
			fwp.rotation_for_alignment(2, muzzle_sign=1)


class TestScaleFactorForLength(unittest.TestCase):
	def test_computes_ratio(self):
		self.assertAlmostEqual(fwp.scale_factor_for_length(0.9995, 0.3325), 0.3325 / 0.9995)

	def test_identity_when_already_at_target(self):
		self.assertAlmostEqual(fwp.scale_factor_for_length(4.0, 4.0), 1.0)

	def test_rejects_non_positive_raw_extent(self):
		with self.assertRaises(ValueError):
			fwp.scale_factor_for_length(0.0, 5.0)

	def test_rejects_non_positive_target_extent(self):
		with self.assertRaises(ValueError):
			fwp.scale_factor_for_length(2.0, -1.0)


class TestForwardTranslation(unittest.TestCase):
	def test_aligns_scaled_min_onto_target_min(self):
		self.assertAlmostEqual(fwp.forward_translation(scaled_min_forward=-0.5, target_min_forward=-0.05), 0.45)

	def test_zero_when_already_aligned(self):
		self.assertAlmostEqual(fwp.forward_translation(-0.05, -0.05), 0.0)


class TestLateralCenterTranslation(unittest.TestCase):
	def test_centers_asymmetric_range_on_zero(self):
		self.assertAlmostEqual(fwp.lateral_center_translation(scaled_min=-0.3, scaled_max=0.1), 0.1)

	def test_already_centered_range_is_a_noop(self):
		self.assertAlmostEqual(fwp.lateral_center_translation(-0.2, 0.2), 0.0)


class TestBuildJobs(unittest.TestCase):
	def setUp(self):
		self.root = os.path.join("C:\\", "repo")
		self.manifest = {
			"weapons_dir": "assets/models/weapons",
			"backup_dir": "assets/models/weapons/_bpy",
			"default_budget_tris": 8000,
			"default_texture_size": 2048,
			"weapons": [
				{"id": "wa", "source": "assets/incoming/tripo/studio/wpn_wa.glb",
					"budget_tris": 7000, "texture_size": 1024, "flip_muzzle": True,
					"z_offset": 0.01, "x_offset": -0.02},
				{"id": "wb", "source": "assets/incoming/tripo/studio/wpn_wb.glb",
					"budget_tris": None, "texture_size": None, "flip_muzzle": None,
					"z_offset": None, "x_offset": None},
			],
		}

	def test_all_mode_builds_one_job_per_manifest_entry(self):
		jobs = fwp.build_jobs({"process_all": True}, self.manifest, self.root)
		self.assertEqual(sorted(j["id"] for j in jobs), ["wa", "wb"])

	def test_all_mode_paths_use_weapons_and_backup_dirs(self):
		jobs = fwp.build_jobs({"process_all": True}, self.manifest, self.root)
		job = next(j for j in jobs if j["id"] == "wa")
		self.assertEqual(os.path.normpath(job["current_path"]),
			os.path.normpath(os.path.join(self.root, "assets/models/weapons/wa.glb")))
		self.assertEqual(os.path.normpath(job["backup_path"]),
			os.path.normpath(os.path.join(self.root, "assets/models/weapons/_bpy/wa.glb")))

	def test_all_mode_keeps_per_entry_overrides(self):
		jobs = fwp.build_jobs({"process_all": True}, self.manifest, self.root)
		job = next(j for j in jobs if j["id"] == "wa")
		self.assertEqual(job["budget_tris"], 7000)
		self.assertEqual(job["texture_size"], 1024)
		self.assertTrue(job["flip_muzzle"])
		self.assertAlmostEqual(job["z_offset"], 0.01)
		self.assertAlmostEqual(job["x_offset"], -0.02)

	def test_all_mode_falls_back_to_manifest_defaults(self):
		jobs = fwp.build_jobs({"process_all": True}, self.manifest, self.root)
		job = next(j for j in jobs if j["id"] == "wb")
		self.assertEqual(job["budget_tris"], 8000)
		self.assertEqual(job["texture_size"], 2048)
		self.assertFalse(job["flip_muzzle"])
		self.assertAlmostEqual(job["z_offset"], 0.0)
		self.assertAlmostEqual(job["x_offset"], 0.0)

	def test_all_mode_without_manifest_raises(self):
		with self.assertRaises(ValueError):
			fwp.build_jobs({"process_all": True}, None, self.root)

	def test_id_mode_resolves_single_entry(self):
		jobs = fwp.build_jobs({"weapon_id": "wa"}, self.manifest, self.root)
		self.assertEqual(len(jobs), 1)
		self.assertEqual(jobs[0]["id"], "wa")

	def test_id_mode_unknown_id_raises_key_error(self):
		with self.assertRaises(KeyError):
			fwp.build_jobs({"weapon_id": "nope"}, self.manifest, self.root)

	def test_neither_all_nor_id_raises(self):
		with self.assertRaises(ValueError):
			fwp.build_jobs({}, self.manifest, self.root)


# ---------------------------------------------------------------------------
# Famille 2 — pipeline géométrique réel (Blender en sous-process)
# ---------------------------------------------------------------------------

def _blender_bin() -> str:
	env = os.environ.get("BLENDER_BIN")
	if env:
		return env
	return r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"


_CASES_SCRIPT_TEMPLATE = r'''#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import annotations

import argparse
import json
import os
import sys
import traceback

import bpy
from mathutils import Vector

REPO = {repo!r}
sys.path.insert(0, os.path.join(REPO, "tools", "blender"))
sys.path.insert(0, os.path.join(REPO, "tools", "blender", "lib"))
import fit_weapon_painted as fwp  # noqa: E402
import toonkit  # noqa: E402


def parse_args():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	p = argparse.ArgumentParser()
	p.add_argument("--out-dir", required=True)
	return p.parse_args(argv)


def _make_rich_image(name, w, h):
	img = bpy.data.images.new(name, width=w, height=h, alpha=False)
	pixels = [0.0] * (w * h * 4)
	for y in range(h):
		for x in range(w):
			i = (y * w + x) * 4
			pixels[i + 0] = ((x * 37 + y * 17) % 256) / 255.0
			pixels[i + 1] = ((x * 53 + y * 91) % 256) / 255.0
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


def _make_bpy_reference_fixture(out_path):
	"""Arme "bpy" synthétique — mêmes conventions que make_weapons.py une fois
	réimportée par Blender (voir l'en-tête de fit_weapon_painted.py) : canon
	vers +Y, origine = poignée, empties Muzzle/Foregrip."""
	toonkit.reset_scene()
	bpy.ops.mesh.primitive_cube_add(size=1.0)
	obj = bpy.context.active_object
	obj.name = "fixture_ref"
	obj.scale = (0.05, 0.20, 0.06)
	obj.location = (0.0, 0.10, 0.0)
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	mat = bpy.data.materials.new("fixture_ref_body")
	obj.data.materials.append(mat)

	muzzle = bpy.data.objects.new("Muzzle", None)
	muzzle.location = (0.0, 0.30, 0.02)
	bpy.context.scene.collection.objects.link(muzzle)
	muzzle.parent = obj

	foregrip = bpy.data.objects.new("Foregrip", None)
	foregrip.location = (0.0, 0.15, 0.01)
	bpy.context.scene.collection.objects.link(foregrip)
	foregrip.parent = obj

	bpy.ops.object.select_all(action='DESELECT')
	obj.select_set(True)
	muzzle.select_set(True)
	foregrip.select_set(True)
	bpy.ops.export_scene.gltf(
		filepath=out_path, export_format='GLB', use_selection=True,
		export_apply=True, export_yup=True, export_materials='EXPORT',
		export_cameras=False, export_lights=False, export_animations=False)
	corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
	length = max(c.y for c in corners) - min(c.y for c in corners)
	return {{"muzzle": list(muzzle.location), "foregrip": list(foregrip.location),
		"length": length}}


def _make_tripo_source_fixture(out_path):
	"""Source "Tripo peinte" synthétique — bbox centrée sur [-0.5, 0.5] le long
	de X (le canon), base au sol sur Z (mêmes DEUX invariants mesurés par
	sondage sur les 10 sources réelles, voir l'en-tête du manifeste), une
	extrémité (+X, la bouche) nettement plus fine que l'autre (-X, la crosse)
	pour que `pick_muzzle_sign` la détecte sans ambiguïté."""
	toonkit.reset_scene()
	bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=0.25, radius2=0.05, depth=1.0)
	obj = bpy.context.active_object
	obj.name = "fixture_tripo"
	# Le cône pointe nativement selon +Z (Blender) ; on le couche sur l'axe X
	# (canon) et on pose sa base au sol (Z >= 0), comme les sources réelles.
	obj.rotation_euler = (0.0, 1.5707963, 0.0)
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	obj.location.z -= min(v.co.z for v in obj.data.vertices)
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	_uv_unwrap(obj)
	img = _make_rich_image("fixture_tex", 256, 256)
	mat = _make_textured_material("tripo_mat_fixture", img)
	obj.data.materials.append(mat)
	bpy.ops.object.select_all(action='DESELECT')
	obj.select_set(True)
	bpy.ops.export_scene.gltf(
		filepath=out_path, export_format='GLB', use_selection=True,
		export_apply=True, export_yup=True, export_materials='EXPORT',
		export_cameras=False, export_lights=False, export_animations=False)


def _find_image_through_mix(mat):
	"""Comme ai_import_painted.py::_material_image_node, mais suit aussi un
	nœud Mix vertex-color x albédo -- Blender reimporte un glTF qui porte
	COLOR_0 en rebranchant la Base Color via un Mix (voir
	test_ai_import_painted.py::_find_image_through_mix, même besoin ici : ce
	pipeline exporte lui aussi l'AO/Curvature en couleur de sommet)."""
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
	ref_path = os.path.join(out_dir, "fixture_ref.glb")
	ref_info = _make_bpy_reference_fixture(ref_path)
	src_path = os.path.join(out_dir, "wpn_fixture.glb")
	_make_tripo_source_fixture(src_path)

	weapons_dir = os.path.join(out_dir, "weapons")
	backup_dir = os.path.join(weapons_dir, "_bpy")
	os.makedirs(weapons_dir, exist_ok=True)
	current_path = os.path.join(weapons_dir, "fixture.glb")
	import shutil
	shutil.copy2(ref_path, current_path)
	backup_path = os.path.join(backup_dir, "fixture.glb")

	report = fwp.process_weapon({{
		"id": "fixture", "source": src_path, "current_path": current_path,
		"backup_path": backup_path, "budget_tris": 2000, "texture_size": 1024,
		"flip_muzzle": False, "z_offset": 0.0, "x_offset": 0.0,
	}})

	backup_existed_before_second_run = os.path.isfile(backup_path)

	toonkit.reset_scene()
	reimported = fwp.import_asset(current_path)
	obj = toonkit.join(reimported) if len(reimported) > 1 else reimported[0]
	mins, maxs = fwp._bbox_world(obj)
	muzzle_obj = next((o for o in bpy.context.scene.objects if o.name == "Muzzle"), None)
	foregrip_obj = next((o for o in bpy.context.scene.objects if o.name == "Foregrip"), None)
	tris = toonkit.tri_count(obj)
	mat = obj.data.materials[0]
	has_painted_suffix = "_painted" in mat.name
	image = _find_image_through_mix(mat)

	# Toutes les valeurs sont capturees en primitives Python PLATES ICI --
	# `toonkit.reset_scene()` (appele par le DEUXIEME `process_weapon` juste
	# en dessous) invaliderait sinon ces references StructRNA avant qu'elles
	# ne soient lues par le dictionnaire de retour.
	length_y = maxs.y - mins.y
	muzzle_local = list(muzzle_obj.location) if muzzle_obj else None
	foregrip_local = list(foregrip_obj.location) if foregrip_obj else None
	material_name = mat.name
	image_size = list(image.size) if image is not None else None
	has_image = image is not None

	# Deuxieme run : idempotence de la sauvegarde (le fichier COURANT est
	# maintenant la version peinte -- la sauvegarde ne doit PAS etre ecrasee
	# par elle).
	report2 = fwp.process_weapon({{
		"id": "fixture", "source": src_path, "current_path": current_path,
		"backup_path": backup_path, "budget_tris": 2000, "texture_size": 1024,
		"flip_muzzle": False, "z_offset": 0.0, "x_offset": 0.0,
	}})

	return {{
		"ok": True,
		"report_tris": report["final_tris"],
		"reimport_tris": tris,
		"length_y": length_y,
		"target_length": ref_info["length"],
		"muzzle_local": muzzle_local,
		"foregrip_local": foregrip_local,
		"expected_muzzle": ref_info["muzzle"],
		"expected_foregrip": ref_info["foregrip"],
		"material_name": material_name,
		"has_painted_suffix": has_painted_suffix,
		"has_image": has_image,
		"image_size": image_size,
		"backup_existed_before_second_run": backup_existed_before_second_run,
		"second_run_ok": report2 is not None,
	}}


CASES = {{
	"full_pipeline": case_full_pipeline,
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
	print("FIT_WEAPON_PAINTED_CASES_RESULT " + json.dumps({{"cases": results}}))


if __name__ == "__main__":
	main()
'''


class _CasesRunner:
	_result = None
	_out_dir = None
	_script_path = None

	@classmethod
	def get(cls) -> dict:
		if cls._result is None:
			cls._out_dir = tempfile.mkdtemp(prefix="fit_weapon_painted_test_")
			script_text = _CASES_SCRIPT_TEMPLATE.format(repo=REPO_ROOT)
			fd, cls._script_path = tempfile.mkstemp(suffix="_fit_weapon_painted_cases.py")
			with os.fdopen(fd, "w", encoding="utf-8") as f:
				f.write(script_text)
			blender_bin = _blender_bin()
			if not os.path.isfile(blender_bin):
				raise unittest.SkipTest(
					f"Blender introuvable ({blender_bin!r}) — définir BLENDER_BIN pour lancer "
					"tools/blender/tests/test_fit_weapon_painted.py")
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
			marker = "FIT_WEAPON_PAINTED_CASES_RESULT "
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


class TestFullPipeline(unittest.TestCase):
	"""Critère d'acceptation A3D-20 bout-en-bout, sur une arme/source
	synthétiques : import -> alignement (axe/longueur/pivot) -> matériau peint
	conservé -> budget de tris -> ancres Muzzle/Foregrip REPRISES de la
	référence bpy -> export, vérifié sur le fichier RÉELLEMENT réécrit."""

	def test_case_passes(self):
		result = _CasesRunner.case("full_pipeline")
		self.assertTrue(result["ok"], result.get("error"))

	def test_length_matches_the_bpy_reference(self):
		result = _CasesRunner.case("full_pipeline")
		self.assertAlmostEqual(result["length_y"], result["target_length"], delta=0.01)

	def test_muzzle_anchor_is_copied_from_the_bpy_reference(self):
		result = _CasesRunner.case("full_pipeline")
		for got, expected in zip(result["muzzle_local"], result["expected_muzzle"]):
			self.assertAlmostEqual(got, expected, delta=1e-4)

	def test_foregrip_anchor_is_copied_from_the_bpy_reference(self):
		result = _CasesRunner.case("full_pipeline")
		for got, expected in zip(result["foregrip_local"], result["expected_foregrip"]):
			self.assertAlmostEqual(got, expected, delta=1e-4)

	def test_material_is_renamed_with_painted_suffix(self):
		result = _CasesRunner.case("full_pipeline")
		self.assertTrue(result["has_painted_suffix"], result["material_name"])

	def test_painted_texture_survives_export(self):
		result = _CasesRunner.case("full_pipeline")
		self.assertTrue(result["has_image"])
		self.assertEqual(result["image_size"], [256, 256])  # 256 < 1024 -> jamais agrandi (resolved_texture_size)

	def test_tris_within_budget(self):
		result = _CasesRunner.case("full_pipeline")
		self.assertLessEqual(result["report_tris"], 2000)
		self.assertLessEqual(result["reimport_tris"], 2000)

	def test_backup_is_never_overwritten_by_a_later_painted_run(self):
		result = _CasesRunner.case("full_pipeline")
		self.assertTrue(result["backup_existed_before_second_run"])
		self.assertTrue(result["second_run_ok"])


if __name__ == "__main__":
	unittest.main()
