#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/blender/tests/test_rig_weapon_parts.py
Tests de tools/blender/rig_weapon_parts.py ET tools/blender/weapon_blueprint.py (FP-11,
suite commune -- mesure/geometrie partagees par les deux fichiers, voir leurs en-tetes).

AUCUN de ces tests ne touche bpy (voir l'en-tete de rig_weapon_parts.py : import dans un
bloc try/except) -- manifeste, transformation, angles, bout du canon, silhouette/IoU,
ouverture du pontet ("bas de la carcasse"), cote pur de weapon_blueprint.py (axes, grille,
cadrage de detail, teintes). Le pipeline geometrique reel (decoupe bpy,
export des 7 armes) est verifie par une execution reelle de Blender (voir
docs/tasks/README.md) et par tests/combat/test_weapon_models_v2.gd cote Godot -- pas
reproduit ici en sous-processus (contrairement a test_fit_weapon_painted.py) : le budget de
cette tache porte sur la geometrie/le manifeste, la fixture bpy des 7 armes reelles suffit
(voir reports/checkpoints/2026-09-25_FP-11/).

Lancer :
    python -m pytest tools/blender/tests/test_rig_weapon_parts.py -q
"""
from __future__ import annotations

import math
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_BLENDER_DIR = os.path.dirname(HERE)
REPO_ROOT = os.path.abspath(os.path.join(TOOLS_BLENDER_DIR, "..", ".."))
MANIFEST_PATH = os.path.join(REPO_ROOT, "tools", "ai3d", "manifests", "weapon_rigs.yaml")

sys.path.insert(0, TOOLS_BLENDER_DIR)
import rig_weapon_parts as rwp  # noqa: E402
import weapon_blueprint as wbp  # noqa: E402

WEAPON_IDS = ["pistolet", "magnum", "rafale", "marqueur", "ravage", "fracas", "faucheur"]
REQUIRED_WEAPON_FIELDS = {
	"id", "grip_span_m", "grip_local", "foregrip_local", "sight_local",
	"magwell_local", "eject_local", "pieces",
}
EXPECTED_PIECE_NAMES = {
	"pistolet": {"Slide", "Mag"},
	"magnum": {"Cylinder", "Hammer"},
	"rafale": {"Mag"},
	"marqueur": {"Mag"},
	"ravage": {"Mag"},
	"fracas": {"Pump"},
	"faucheur": {"Bolt", "Mag"},
}


# ---------------------------------------------------------------------------
# weapon_rigs.yaml -- manifeste REEL du depot (garantit qu'il reste conforme
# au schema attendu, pas seulement a une fixture -- meme politique que
# test_fit_weapon_painted.py::TestParseManifest).
# ---------------------------------------------------------------------------

class TestRealManifest(unittest.TestCase):
	@classmethod
	def setUpClass(cls):
		with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
			cls.manifest = rwp.parse_manifest(f.read())

	def test_top_level_fields_present(self):
		self.assertEqual(self.manifest["weapons_dir"], "assets/models/weapons")
		self.assertEqual(self.manifest["painted_v1_dir"], "assets/models/weapons/_painted_v1")
		self.assertEqual(self.manifest["output_dir"], "assets/models/weapons/v2")
		self.assertEqual(self.manifest["default_budget_tris"], 8000)
		self.assertAlmostEqual(self.manifest["min_iou"], 0.98)
		self.assertGreaterEqual(self.manifest["target_grip_length_m"], 0.10)
		self.assertLessEqual(self.manifest["target_grip_length_m"], 0.13)

	def test_seven_weapons_declared(self):
		ids = sorted(w["id"] for w in self.manifest["weapons"])
		self.assertEqual(ids, sorted(WEAPON_IDS))

	def test_every_weapon_has_the_required_fields(self):
		for entry in self.manifest["weapons"]:
			self.assertTrue(REQUIRED_WEAPON_FIELDS.issubset(entry.keys()), entry.get("id"))

	def test_every_local_point_is_a_3_tuple_of_floats(self):
		for entry in self.manifest["weapons"]:
			for key in ("grip_local", "foregrip_local", "sight_local", "magwell_local", "eject_local"):
				point = entry[key]
				self.assertEqual(len(point), 3, f"{entry['id']}.{key}")
				for c in point:
					self.assertIsInstance(c, float, f"{entry['id']}.{key}")

	def test_every_weapon_has_the_expected_piece_names(self):
		for entry in self.manifest["weapons"]:
			names = {p["name"] for p in entry["pieces"]}
			self.assertEqual(names, EXPECTED_PIECE_NAMES[entry["id"]], entry["id"])

	def test_every_piece_box_is_non_degenerate(self):
		# `piece_boxes` leve ValueError sur une boite vide ou une paire box2 incomplete.
		for entry in self.manifest["weapons"]:
			for piece in entry["pieces"]:
				boxes = rwp.piece_boxes(piece)
				self.assertGreaterEqual(len(boxes), 1, f"{entry['id']}.{piece['name']}")
				for bmin, bmax in boxes:
					for lo, hi in zip(bmin, bmax):
						self.assertLess(lo, hi, f"{entry['id']}.{piece['name']}")

	def test_every_pivot_is_a_finite_3_tuple(self):
		# Le pivot n'est PAS force a l'interieur de la boite de decoupe : un
		# chargeur, par exemple, a pour pivot le point d'attache (MagWell), utile
		# a la choregraphie de rechargement (FP-13), meme si ce point tombe hors
		# de la petite piece decoupee (le talon visible du chargeur).
		for entry in self.manifest["weapons"]:
			for piece in entry["pieces"]:
				for c in piece["pivot"]:
					self.assertTrue(math.isfinite(c), f"{entry['id']}.{piece['name']}")

	def test_every_grip_sits_on_the_right_flank(self):
		# Regle de pose (en-tete de weapon_rigs.yaml) : la paume droite se pose sur le flanc
		# DROIT de la poignee -- le Grip est a droite du plan median de visee (Sight).
		for entry in self.manifest["weapons"]:
			self.assertGreater(entry["grip_local"][0], entry["sight_local"][0], entry["id"])

	def test_every_eject_is_on_the_right_flank(self):
		for entry in self.manifest["weapons"]:
			self.assertGreater(entry["eject_local"][0], entry["sight_local"][0], entry["id"])

	def test_every_scaled_grip_length_is_in_the_contract_range(self):
		target = self.manifest["target_grip_length_m"]
		lo, hi = rwp.GRIP_LENGTH_RANGE_M
		for entry in self.manifest["weapons"]:
			scale = rwp.scale_factor_for_grip(entry["grip_span_m"], target)
			self.assertGreaterEqual(entry["grip_span_m"] * scale, lo - 1e-9, entry["id"])
			self.assertLessEqual(entry["grip_span_m"] * scale, hi + 1e-9, entry["id"])

	def test_every_grip_span_yields_a_plausible_scale(self):
		# L'echelle finale (target / grip_span, §3.3) doit rester dans un ordre de
		# grandeur raisonnable (0.3x-3x) -- un manifeste avec un grip_span absurde
		# (oubli d'unite, cm au lieu de m) serait detecte ici avant de lancer Blender.
		target = self.manifest["target_grip_length_m"]
		for entry in self.manifest["weapons"]:
			scale = rwp.scale_factor_for_grip(entry["grip_span_m"], target)
			self.assertGreater(scale, 0.3, entry["id"])
			self.assertLess(scale, 3.0, entry["id"])

	def test_comment_only_and_blank_lines_are_ignored(self):
		text = """
# un commentaire
weapons_dir: out
painted_v1_dir: out/_painted_v1
output_dir: out/v2
default_budget_tris: 8000
target_grip_length_m: 0.115
min_iou: 0.98

weapons:
# commentaire dans la liste
- id: a
  grip_span_m: 0.15
  grip_local: [0.0, 0.0, 0.1]
  foregrip_local: [0.0, 0.1, 0.05]
  sight_local: [0.0, 0.0, 0.2]
  magwell_local: [0.0, 0.1, 0.15]
  eject_local: [0.02, 0.05, 0.15]
  pieces:
  - name: Mag
    box_min: [-0.02, 0.0, 0.0]
    box_max: [0.02, 0.05, 0.05]
    pivot: [0.0, 0.0, 0.05]
"""
		manifest = rwp.parse_manifest(text)
		self.assertEqual(len(manifest["weapons"]), 1)
		self.assertEqual(manifest["weapons"][0]["id"], "a")
		self.assertEqual(len(manifest["weapons"][0]["pieces"]), 1)
		self.assertEqual(manifest["weapons"][0]["pieces"][0]["name"], "Mag")
		self.assertEqual(manifest["weapons"][0]["pieces"][0]["box_max"], (0.02, 0.05, 0.05))


class TestParseManifestErrors(unittest.TestCase):
	def test_bad_top_level_line_raises(self):
		with self.assertRaises(ValueError):
			rwp.parse_manifest("not a key value line\nweapons:\n")

	def test_weapon_entry_must_start_with_id(self):
		with self.assertRaises(ValueError):
			rwp.parse_manifest("weapons:\n- grip_span_m: 0.1\n")

	def test_piece_entry_must_start_with_name(self):
		text = (
			"weapons:\n- id: a\n  grip_span_m: 0.1\n  pieces:\n  - box_min: [0,0,0]\n"
		)
		with self.assertRaises(ValueError):
			rwp.parse_manifest(text)

	def test_field_outside_any_weapon_raises(self):
		with self.assertRaises(ValueError):
			rwp.parse_manifest("weapons:\n  grip_span_m: 0.1\n")

	def test_unexpected_indentation_raises(self):
		with self.assertRaises(ValueError):
			rwp.parse_manifest("weapons:\n- id: a\n        grip_span_m: 0.1\n")


class TestResolveManifestEntry(unittest.TestCase):
	def setUp(self):
		self.manifest = {"weapons": [{"id": "ravage"}, {"id": "fracas"}]}

	def test_found(self):
		self.assertEqual(rwp.resolve_manifest_entry(self.manifest, "fracas")["id"], "fracas")

	def test_missing_lists_known_ids(self):
		with self.assertRaises(KeyError) as ctx:
			rwp.resolve_manifest_entry(self.manifest, "nope")
		self.assertIn("fracas", str(ctx.exception))
		self.assertIn("ravage", str(ctx.exception))


# ---------------------------------------------------------------------------
# Transformation rigide (echelle par la poignee, §3.3)
# ---------------------------------------------------------------------------

class TestRigidTransform(unittest.TestCase):
	def test_scale_factor_basic(self):
		self.assertAlmostEqual(rwp.scale_factor_for_grip(0.10, 0.20), 2.0)

	def test_scale_factor_rejects_non_positive(self):
		with self.assertRaises(ValueError):
			rwp.scale_factor_for_grip(0.0, 0.115)
		with self.assertRaises(ValueError):
			rwp.scale_factor_for_grip(0.1, -1.0)

	def test_translation_puts_grip_at_world_origin(self):
		grip_local = (0.01, 0.22, 0.13)
		scale = 0.75
		translation = rwp.translation_for_grip_at_origin(grip_local, scale)
		transformed = rwp.transform_point(grip_local, scale, translation)
		for c in transformed:
			self.assertAlmostEqual(c, 0.0, places=9)

	def test_transform_point_is_affine(self):
		p = (1.0, 2.0, 3.0)
		out = rwp.transform_point(p, 2.0, (10.0, -5.0, 0.5))
		self.assertEqual(out, (12.0, -1.0, 6.5))

	def test_same_transform_applied_to_a_box_keeps_min_max_order(self):
		# Une echelle positive + une translation ne retourne jamais une boite
		# (composante par composante, min reste < max) -- verifie l'hypothese
		# que process_weapon() exploite pour ne PAS re-trier apres `xf()`.
		scale = 1.6
		translation = (0.02, -0.3, 0.11)
		box_min = (-0.05, 0.1, 0.0)
		box_max = (0.05, 0.2, 0.03)
		tmin = rwp.transform_point(box_min, scale, translation)
		tmax = rwp.transform_point(box_max, scale, translation)
		for lo, hi in zip(tmin, tmax):
			self.assertLess(lo, hi)


# ---------------------------------------------------------------------------
# Angles (axe Sight->Muzzle)
# ---------------------------------------------------------------------------

class TestAngles(unittest.TestCase):
	def test_sight_lateral_angle_zero_when_aligned(self):
		# Meme X (aucun cant), separes uniquement le long de l'axe canon (Y).
		self.assertAlmostEqual(rwp.sight_lateral_angle_deg((0.0, 0.0, 0.20), (0.0, 0.5, 0.06)), 0.0)

	def test_sight_lateral_angle_known_ratio(self):
		# lateral == forward -> 45 degres, independamment de Z (l'elevation n'est
		# pas mesuree par cette fonction, voir sa docstring).
		angle = rwp.sight_lateral_angle_deg((0.0, 0.0, 0.0), (0.02, 0.02, 0.30))
		self.assertAlmostEqual(angle, 45.0, places=6)

	def test_sight_lateral_angle_zero_when_coincident(self):
		self.assertAlmostEqual(rwp.sight_lateral_angle_deg((0.0, 0.1, 0.2), (0.0, 0.1, 0.5)), 0.0)


class TestPieceBoxes(unittest.TestCase):
	def test_single_box(self):
		boxes = rwp.piece_boxes({"name": "Mag", "box_min": (0.0, 0.0, 0.0), "box_max": (1.0, 1.0, 1.0)})
		self.assertEqual(boxes, [((0.0, 0.0, 0.0), (1.0, 1.0, 1.0))])

	def test_second_box_is_a_union(self):
		boxes = rwp.piece_boxes({"name": "Mag", "box_min": (0.0, 0.0, 0.0), "box_max": (1.0, 1.0, 1.0),
			"box2_min": (1.0, 0.0, 0.0), "box2_max": (2.0, 1.0, 0.5)})
		self.assertEqual(len(boxes), 2)
		self.assertTrue(rwp.point_in_boxes((1.5, 0.5, 0.25), boxes))
		self.assertFalse(rwp.point_in_boxes((1.5, 0.5, 0.75), boxes))
		self.assertTrue(rwp.point_in_boxes((0.5, 0.5, 0.75), boxes))

	def test_incomplete_second_box_raises(self):
		with self.assertRaises(ValueError):
			rwp.piece_boxes({"name": "Mag", "box_min": (0.0, 0.0, 0.0), "box_max": (1.0, 1.0, 1.0),
				"box2_min": (1.0, 0.0, 0.0)})

	def test_missing_first_box_raises(self):
		with self.assertRaises(ValueError):
			rwp.piece_boxes({"name": "Mag"})

	def test_empty_box_raises(self):
		with self.assertRaises(ValueError):
			rwp.piece_boxes({"name": "Mag", "box_min": (0.0, 0.0, 0.0), "box_max": (1.0, 0.0, 1.0)})


# ---------------------------------------------------------------------------
# Bout du canon (mesure du Muzzle)
# ---------------------------------------------------------------------------

class TestBoreTipPoint(unittest.TestCase):
	def test_flat_front_face_gives_its_center(self):
		# Face avant carree de 2 cm a Y = 0.30, centree en (X=0.01, Z=0.20).
		face = [(0.0, 0.30, 0.19), (0.02, 0.30, 0.19), (0.02, 0.30, 0.21), (0.0, 0.30, 0.21)]
		tip = rwp.bore_tip_point(face + [(0.0, 0.0, 0.0)])
		self.assertAlmostEqual(tip[0], 0.01)
		self.assertAlmostEqual(tip[1], 0.30)
		self.assertAlmostEqual(tip[2], 0.20)

	def test_flared_ring_gives_the_axis_not_a_rim_vertex(self):
		# Tromblon : anneau de rayon 5 cm au meme Y maximal -- le bout du canon est le
		# CENTRE de l'anneau (axe de l'ame), jamais un sommet de la levre (5 cm a cote).
		ring = [(0.05 * math.cos(a), 0.50, 0.20 + 0.05 * math.sin(a))
			for a in (0.0, math.pi / 2, math.pi, 3 * math.pi / 2)]
		tip = rwp.bore_tip_point(ring + [(0.0, 0.0, 0.0)])
		self.assertAlmostEqual(tip[0], 0.0, places=9)
		self.assertAlmostEqual(tip[2], 0.20, places=9)

	def test_vertices_behind_the_band_are_ignored(self):
		# Un guidon haut situe 1 cm en retrait de la bouche ne tire pas le centre vers le haut.
		verts = [(0.0, 0.30, 0.10), (0.0, 0.30, 0.12), (0.0, 0.29, 0.30)]
		tip = rwp.bore_tip_point(verts)
		self.assertAlmostEqual(tip[2], 0.11)

	def test_rejects_empty_list(self):
		with self.assertRaises(ValueError):
			rwp.bore_tip_point([])

	def test_rejects_negative_band(self):
		with self.assertRaises(ValueError):
			rwp.bore_tip_point([(0.0, 0.0, 0.0)], band=-0.001)


class TestSightElevation(unittest.TestCase):
	def test_elevation_is_the_height_above_the_muzzle(self):
		self.assertAlmostEqual(rwp.sight_elevation_m((0.0, 0.0, 0.25), (0.0, 0.6, 0.21)), 0.04)


# ---------------------------------------------------------------------------
# Silhouette 2D : point dans triangle / silhouette
# ---------------------------------------------------------------------------

class TestPointInSilhouette(unittest.TestCase):
	TRI = ((0.0, 0.0), (1.0, 0.0), (0.0, 1.0))

	def test_inside_point(self):
		self.assertTrue(rwp.point_in_triangle_2d((0.2, 0.2), self.TRI))

	def test_edge_is_inclusive(self):
		self.assertTrue(rwp.point_in_triangle_2d((0.5, 0.0), self.TRI))

	def test_outside_point(self):
		self.assertFalse(rwp.point_in_triangle_2d((0.8, 0.8), self.TRI))

	def test_degenerate_triangle_only_contains_its_segment(self):
		segment = ((0.0, 0.0), (1.0, 1.0), (2.0, 2.0))
		self.assertTrue(rwp.point_in_triangle_2d((0.5, 0.5), segment))
		self.assertFalse(rwp.point_in_triangle_2d((0.5, 0.6), segment))

	def test_silhouette_checks_every_triangle(self):
		far = ((10.0, 10.0), (11.0, 10.0), (10.0, 11.0))
		self.assertTrue(rwp.point_in_silhouette((10.2, 10.2), [self.TRI, far]))
		self.assertFalse(rwp.point_in_silhouette((5.0, 5.0), [self.TRI, far]))


# ---------------------------------------------------------------------------
# Ouverture du pontet (fenetre rasterisee, jours fermes)
# ---------------------------------------------------------------------------

def _rect(u0, v0, u1, v1):
	return [((u0, v0), (u1, v0), (u1, v1)), ((u0, v0), (u1, v1), (u0, v1))]


def _frame(u0, v0, u1, v1, wall):
	"""Cadre rectangulaire (anneau carre) d'epaisseur `wall` -- un jour ferme au centre."""
	return (_rect(u0, v0, u1, v0 + wall) + _rect(u0, v1 - wall, u1, v1)
		+ _rect(u0, v0, u0 + wall, v1) + _rect(u1 - wall, v0, u1, v1))


class TestRasterizeWindow(unittest.TestCase):
	def test_square_covers_the_expected_cells(self):
		cells, nu, nv = rwp.rasterize_window(_rect(0.0, 0.0, 0.01, 0.01), (0.0, 0.02, 0.0, 0.02), 0.0025)
		self.assertEqual((nu, nv), (8, 8))
		self.assertEqual(len(cells), 16)

	def test_triangles_outside_the_window_are_ignored(self):
		cells, _nu, _nv = rwp.rasterize_window(_rect(1.0, 1.0, 1.1, 1.1), (0.0, 0.02, 0.0, 0.02), 0.0025)
		self.assertEqual(cells, set())

	def test_rejects_bad_cell_or_empty_window(self):
		with self.assertRaises(ValueError):
			rwp.rasterize_window([], (0.0, 1.0, 0.0, 1.0), 0.0)
		with self.assertRaises(ValueError):
			rwp.rasterize_window([], (1.0, 1.0, 0.0, 1.0), 0.01)


class TestEnclosedHoles(unittest.TestCase):
	def test_frame_has_one_hole_of_the_inner_size(self):
		# Cadre de 4 cm, parois de 1 cm : jour de 2 x 2 cm = 8 x 8 cellules de 2,5 mm.
		cells, nu, nv = rwp.rasterize_window(_frame(0.01, 0.01, 0.05, 0.05, 0.01),
			(0.0, 0.06, 0.0, 0.06), 0.0025)
		holes = rwp.enclosed_holes(cells, nu, nv)
		self.assertEqual(len(holes), 1)
		self.assertEqual(len(holes[0]), 64)

	def test_open_u_shape_has_no_hole(self):
		u_shape = (_rect(0.01, 0.01, 0.05, 0.02) + _rect(0.01, 0.01, 0.02, 0.05)
			+ _rect(0.04, 0.01, 0.05, 0.05))
		cells, nu, nv = rwp.rasterize_window(u_shape, (0.0, 0.06, 0.0, 0.06), 0.0025)
		self.assertEqual(rwp.enclosed_holes(cells, nu, nv), [])

	def test_region_touching_the_window_border_is_outside(self):
		# Cadre coupe par la fenetre : son jour touche le bord, ce n'est pas un jour ferme.
		cells, nu, nv = rwp.rasterize_window(_frame(0.01, 0.01, 0.05, 0.05, 0.01),
			(0.0, 0.06, 0.025, 0.06), 0.0025)
		self.assertEqual(rwp.enclosed_holes(cells, nu, nv), [])


class TestTriggerGuardOpening(unittest.TestCase):
	"""Pistolet synthetique (u = axe canon, + vers la bouche ; v = hauteur) : carcasse
	u -0.03..0.20, v 0.00..0.06 ; poignee u -0.03..0.03, v -0.12..0.00 ; pontet = cadre
	u 0.03..0.09, v -0.05..0.00 (jour v -0.04..-0.01) ; Grip en (0.0, -0.025)."""
	GRIP = (0.0, -0.025)

	@staticmethod
	def _pistol():
		return (_rect(-0.03, 0.0, 0.20, 0.06) + _rect(-0.03, -0.12, 0.03, 0.0)
			+ _frame(0.03, -0.05, 0.09, 0.0, 0.01))

	def test_finds_the_opening_in_front_of_the_grip(self):
		guard = rwp.trigger_guard_opening(self._pistol(), self.GRIP)
		self.assertIsNotNone(guard)
		self.assertAlmostEqual(guard["top"], -0.01, delta=0.0026)
		self.assertAlmostEqual(guard["bottom"], -0.04, delta=0.0026)
		self.assertGreater(guard["back"], self.GRIP[0])

	def test_opening_behind_the_grip_is_ignored(self):
		# Crosse squelette derriere la poignee : jour ferme, mais pas un pontet.
		stock = _frame(-0.06, -0.04, -0.03, 0.0, 0.005)
		tris = _rect(-0.03, 0.0, 0.20, 0.06) + _rect(-0.03, -0.12, 0.03, 0.0) + stock
		self.assertIsNone(rwp.trigger_guard_opening(tris, self.GRIP))

	def test_opening_far_above_the_grip_is_ignored(self):
		# Poignee de transport 9 cm au-dessus du Grip : hors de [Grip - 6 cm, Grip + 6 cm].
		handle = _frame(0.03, 0.065, 0.09, 0.095, 0.005)
		tris = _rect(-0.03, 0.0, 0.20, 0.06) + _rect(-0.03, -0.12, 0.03, 0.0) + handle
		self.assertIsNone(rwp.trigger_guard_opening(tris, self.GRIP))

	def test_grip_height_criterion_reads_top_as_the_frame_bottom(self):
		guard = rwp.trigger_guard_opening(self._pistol(), self.GRIP)
		self.assertTrue(guard["bottom"] <= self.GRIP[1] <= guard["top"])
		# Un Grip dans la carcasse (v = +0.02) serait au-dessus du bas de la carcasse.
		self.assertGreater(0.02, guard["top"])


# ---------------------------------------------------------------------------
# Rasterisation / IoU de silhouette
# ---------------------------------------------------------------------------

class TestSilhouetteIoU(unittest.TestCase):
	@staticmethod
	def _square(u0, v0, u1, v1):
		return [((u0, v0), (u1, v0), (u1, v1)), ((u0, v0), (u1, v1), (u0, v1))]

	def test_identical_squares_have_iou_one(self):
		sq = self._square(0.0, 0.0, 1.0, 1.0)
		self.assertAlmostEqual(rwp.silhouette_iou(sq, list(sq), resolution=64), 1.0, places=3)

	def test_disjoint_squares_have_iou_zero(self):
		a = self._square(0.0, 0.0, 1.0, 1.0)
		b = self._square(10.0, 10.0, 11.0, 11.0)
		self.assertAlmostEqual(rwp.silhouette_iou(a, b, resolution=128), 0.0, places=2)

	def test_half_overlap_squares_match_known_ratio(self):
		# [0,1]x[0,1] et [0.5,1.5]x[0,1] -> intersection 0.5x1, union 1.5x1 -> IoU = 1/3.
		a = self._square(0.0, 0.0, 1.0, 1.0)
		b = self._square(0.5, 0.0, 1.5, 1.0)
		iou = rwp.silhouette_iou(a, b, resolution=300)
		self.assertAlmostEqual(iou, 1.0 / 3.0, delta=0.02)

	def test_both_empty_is_iou_one(self):
		self.assertEqual(rwp.silhouette_iou([], []), 1.0)

	def test_iou_from_cells_matches_expected_set_ratio(self):
		a = {(0, 0), (1, 0), (2, 0)}
		b = {(1, 0), (2, 0), (3, 0)}
		self.assertAlmostEqual(rwp.iou_from_cells(a, b), 2 / 4)

	def test_rasterize_rejects_non_positive_resolution(self):
		with self.assertRaises(ValueError):
			rwp.rasterize_triangles([], (0, 1, 0, 1), resolution=0)


# ---------------------------------------------------------------------------
# weapon_blueprint.py -- axes de vue / grille / cadrage (aucun bpy)
# ---------------------------------------------------------------------------

class TestBlueprintViewAxes(unittest.TestCase):
	def test_unknown_view_raises(self):
		with self.assertRaises(ValueError):
			wbp.view_axes("side")

	def test_camera_basis_is_right_handed_for_every_view(self):
		for view in wbp.VIEW_ORDER:
			right, up, back = wbp.camera_basis_vectors(view)

			def cross(a, b):
				return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
			computed_back = cross(right, up)
			for c, b in zip(computed_back, back):
				self.assertAlmostEqual(c, b, msg=view)

	def test_profile_view_maps_bore_axis_to_horizontal(self):
		axes = wbp.view_axes("profile")
		self.assertEqual(axes["u_axis"], 1)  # Y (canon)
		self.assertEqual(axes["v_axis"], 2)  # Z (hauteur)

	def test_front_view_camera_is_behind_the_stock(self):
		axes = wbp.view_axes("front")
		self.assertEqual(axes["depth_axis"], 1)
		self.assertEqual(axes["depth_sign"], -1.0)


class TestBlueprintProjection(unittest.TestCase):
	def test_world_to_uv_round_trip(self):
		point = (0.02, 0.35, 0.11)
		for view in wbp.VIEW_ORDER:
			u, v = wbp.world_to_uv(point, view)
			axes = wbp.view_axes(view)
			depth = point[axes["depth_axis"]]
			back = wbp.uv_depth_to_world(u, v, depth, view)
			for a, b in zip(point, back):
				self.assertAlmostEqual(a, b, msg=view)

	def test_grid_lines_cover_range_without_duplicates(self):
		lines = wbp.grid_lines(-0.023, 0.041, step=0.01)
		self.assertEqual(lines, sorted(set(lines)))
		self.assertLessEqual(lines[0], -0.023)
		self.assertGreaterEqual(lines[-1], 0.041)

	def test_grid_lines_rejects_non_positive_step(self):
		with self.assertRaises(ValueError):
			wbp.grid_lines(0.0, 1.0, step=0.0)

	def test_is_major_line_every_five_including_zero(self):
		self.assertTrue(wbp.is_major_line(0.0, step=0.01, major_every=5))
		self.assertTrue(wbp.is_major_line(0.05, step=0.01, major_every=5))
		self.assertFalse(wbp.is_major_line(0.02, step=0.01, major_every=5))

	def test_format_cm_label(self):
		self.assertEqual(wbp.format_cm_label(0.0), "0")
		self.assertEqual(wbp.format_cm_label(0.05), "+5")
		self.assertEqual(wbp.format_cm_label(-0.03), "-3")

	def test_ortho_frame_applies_margin_and_min_span(self):
		frame = wbp.ortho_frame((-0.01, -0.02, -0.01), (0.01, 0.02, 0.01), "top", margin=0.01,
			min_half_span=0.05)
		# bbox top: u=X in[-0.01,0.01], v=Y in[-0.02,0.02] -- plus petit que
		# min_half_span des deux cotes -> le cadrage doit rester symetrique a +-0.05.
		self.assertAlmostEqual(frame["u_min"], -0.05)
		self.assertAlmostEqual(frame["u_max"], 0.05)
		self.assertAlmostEqual(frame["v_min"], -0.05)
		self.assertAlmostEqual(frame["v_max"], 0.05)


class TestBlueprintDetailFrame(unittest.TestCase):
	def test_parse_frame_cm_converts_to_meters(self):
		frame = wbp.parse_frame_cm("-4,12,7,18")
		self.assertAlmostEqual(frame["u_min"], -0.04)
		self.assertAlmostEqual(frame["u_max"], 0.12)
		self.assertAlmostEqual(frame["v_min"], 0.07)
		self.assertAlmostEqual(frame["v_max"], 0.18)

	def test_parse_frame_cm_rejects_malformed_text(self):
		for bad in ("1,2,3", "a,b,c,d", "5,1,0,1", "0,1,3,3"):
			with self.assertRaises(ValueError, msg=bad):
				wbp.parse_frame_cm(bad)


class TestBlueprintResolution(unittest.TestCase):
	def test_width_is_size_and_height_follows_the_aspect(self):
		self.assertEqual(wbp.render_resolution(0.40, 0.20, 1600, cap_longest=False), (1600, 800))

	def test_tall_view_is_capped_on_its_longest_side(self):
		# Vue de dessus d'un fusil : 0,2 m de large pour 1,4 m de long.
		self.assertEqual(wbp.render_resolution(0.20, 1.40, 1600, cap_longest=True), (229, 1600))
		self.assertEqual(wbp.render_resolution(0.20, 1.40, 1600, cap_longest=False), (1600, 11200))

	def test_rejects_zero_span_or_size(self):
		with self.assertRaises(ValueError):
			wbp.render_resolution(0.0, 1.0, 1600, cap_longest=True)
		with self.assertRaises(ValueError):
			wbp.render_resolution(1.0, 1.0, 0, cap_longest=True)


class TestBlueprintTints(unittest.TestCase):
	def test_lerp_color_endpoints_and_clamp(self):
		self.assertEqual(wbp.lerp_color((0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0), 0.0), (0.0, 0.0, 0.0, 1.0))
		self.assertEqual(wbp.lerp_color((0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0), 2.0), (1.0, 1.0, 1.0, 1.0))
		mid = wbp.lerp_color((0.0, 0.2, 0.4, 0.5), (1.0, 0.2, 0.0, 1.0), 0.5)
		for got, want in zip(mid, (0.5, 0.2, 0.2, 1.0)):
			self.assertAlmostEqual(got, want)

	def test_piece_tints_are_distinct_and_cycle(self):
		tints = [wbp.piece_tint(i) for i in range(len(wbp.PIECE_TINTS))]
		self.assertEqual(len(set(tints)), len(tints))
		self.assertEqual(wbp.piece_tint(len(wbp.PIECE_TINTS)), wbp.piece_tint(0))

	def test_piece_tint_rejects_negative_index(self):
		with self.assertRaises(ValueError):
			wbp.piece_tint(-1)


if __name__ == "__main__":
	unittest.main()
