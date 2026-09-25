#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/blender/tests/test_repaint_weapon.py
Tests de tools/blender/repaint_weapon.py (FP-12 -- doc 12 §3.4).

Aucun test ne depend de bpy/Blender : `repaint_weapon.py` n'importe jamais
bpy (voir son en-tete), toute la geometrie se lit avec `trimesh`. Deux
familles :

1. Fonctions PURES sur des donnees SYNTHETIQUES (couleur, hue/sat vectorises,
   palette, boites, aretes convexes/concaves sur un cube jetable) -- rapides,
   aucun .glb touche.
2. Integration sur les VRAIES armes (`assets/models/weapons/<id>.glb`,
   LECTURE SEULE) : verifie directement les criteres d'acceptation FP-12
   (teinte bleue <= 2 %, teintes reservees <= 1 %, 6 clusters k-means a
   DeltaE_OK <= 0,10 d'une couleur §5.1 ou son ombre, marge de luminance du
   liisere >= 0,06, hash UV0 inchange, accents §5.2 presents sur Ravage/
   Fracas/Pistolet). Plus lent (~8 s/arme) mais c'est la preuve reelle du
   contrat, pas une approximation sur un cube.

Lancer :
    python -m pytest tools/blender/tests/test_repaint_weapon.py -q
    (ou, sans pytest : python tools/blender/tests/test_repaint_weapon.py)
"""
from __future__ import annotations

import os
import sys
import unittest

import numpy as np
import trimesh

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_BLENDER = os.path.dirname(HERE)
REPO_ROOT = os.path.dirname(os.path.dirname(TOOLS_BLENDER))
WEAPONS_DIR = os.path.join(REPO_ROOT, "assets", "models", "weapons")

sys.path.insert(0, TOOLS_BLENDER)
import repaint_weapon as rw  # noqa: E402

try:
	from scipy.cluster.vq import kmeans2
	HAVE_SCIPY_KMEANS = True
except ImportError:  # pragma: no cover
	HAVE_SCIPY_KMEANS = False

REQUIRED_WEAPONS = ["pistolet", "magnum", "rafale", "marqueur", "ravage", "fracas", "faucheur"]
WEAPONS_PRESENT = [w for w in REQUIRED_WEAPONS if os.path.isfile(os.path.join(WEAPONS_DIR, f"{w}.glb"))]


# ---------------------------------------------------------------------------
# 1. Fonctions pures -- donnees synthetiques.
# ---------------------------------------------------------------------------

class TestOklabReferenceValues(unittest.TestCase):
	"""Verifie la conversion sRGB<->OKLab contre la table de reference
	publiee par Ottosson (https://bottosson.github.io/posts/oklab/) --
	quelques valeurs a 3 decimales pres."""

	REFERENCE = {
		"white": ((1, 1, 1), (1.000, 0.000, 0.000)),
		"black": ((0, 0, 0), (0.000, 0.000, 0.000)),
		"red": ((1, 0, 0), (0.628, 0.225, 0.126)),
		"green": ((0, 1, 0), (0.866, -0.234, 0.179)),
		"blue": ((0, 0, 1), (0.452, -0.032, -0.312)),
	}

	def test_matches_published_table(self):
		for name, (rgb, expected) in self.REFERENCE.items():
			lab = rw.srgb_to_oklab(np.array(rgb, dtype=np.float64))
			for got, want in zip(lab, expected):
				self.assertAlmostEqual(got, want, places=3, msg=name)

	def test_round_trip(self):
		for name, (rgb, _) in self.REFERENCE.items():
			lab = rw.srgb_to_oklab(np.array(rgb, dtype=np.float64))
			back = rw.oklab_to_srgb(lab)
			for got, want in zip(back, rgb):
				self.assertAlmostEqual(got, want, places=5, msg=name)

	def test_vectorized_over_image_shape(self):
		img = np.random.default_rng(0).random((4, 5, 3))
		lab = rw.srgb_to_oklab(img)
		self.assertEqual(lab.shape, (4, 5, 3))
		back = rw.oklab_to_srgb(lab)
		np.testing.assert_allclose(back, img, atol=1e-6)


class TestHueSat(unittest.TestCase):
	def test_matches_colorsys(self):
		import colorsys
		rng = np.random.default_rng(1)
		samples = rng.random((200, 3))
		hue, sat = rw.rgb_to_hue_sat(samples)
		for (r, g, b), h, s in zip(samples, hue, sat):
			h_ref, s_ref, _ = colorsys.rgb_to_hsv(r, g, b)
			self.assertAlmostEqual(float(h) / 360.0, h_ref, places=4)
			self.assertAlmostEqual(float(s), s_ref, places=4)

	def test_grey_has_zero_saturation(self):
		hue, sat = rw.rgb_to_hue_sat(np.array([0.5, 0.5, 0.5]))
		self.assertAlmostEqual(float(sat), 0.0)

	def test_pure_blue_hue_is_240(self):
		hue, sat = rw.rgb_to_hue_sat(np.array([0.0, 0.0, 1.0]))
		self.assertAlmostEqual(float(hue), 240.0, places=3)
		self.assertAlmostEqual(float(sat), 1.0, places=6)


class TestPaletteLoading(unittest.TestCase):
	def test_loads_the_nine_colours_from_tokens_json(self):
		palette = rw.load_palette()
		self.assertEqual(set(palette["materials"]), set(rw.BASE_MATERIAL_KEYS))
		self.assertEqual(set(palette["accents"]), set(rw.ACCENT_KEYS))
		self.assertEqual(palette["materials"]["enamel_steel"], "#4A505C")
		self.assertEqual(palette["accents"]["red"], "#C8322B")

	def test_resolve_target_hex(self):
		palette = rw.load_palette()
		self.assertEqual(rw.resolve_target_hex(palette, "material:brass"), "#D9A21B")
		self.assertEqual(rw.resolve_target_hex(palette, "accent:teal"), "#2E8C86")

	def test_resolve_target_hex_rejects_unknown(self):
		palette = rw.load_palette()
		with self.assertRaises(ValueError):
			rw.resolve_target_hex(palette, "accent:magenta")
		with self.assertRaises(ValueError):
			rw.resolve_target_hex(palette, "nope:red")

	def test_no_base_colour_is_in_a_reserved_or_blue_band(self):
		# Sondage direct : la palette §5.1 elle-meme ne doit jamais declencher
		# ses propres gardes (sinon guard_reserved_hues abimerait les couleurs
		# CIBLES, pas seulement les texels a corriger).
		palette = rw.load_palette()
		for table in (palette["materials"], palette["accents"]):
			for name, hexv in table.items():
				rgb = np.array(rw.hex_to_rgb01(hexv))
				hue, sat = rw.rgb_to_hue_sat(rgb)
				is_blue = rw.hue_in_band(hue, rw.BLUE_HUE_RANGE_DEG) and sat > rw.BLUE_SATURATION_MIN
				self.assertFalse(is_blue, f"{name} ({hexv}) tombe dans la bande bleue")
				for band in rw.RESERVED_HUE_BANDS_DEG:
					in_reserved = rw.hue_in_band(hue, band) and sat > rw.RESERVED_SATURATION_MIN
					self.assertFalse(in_reserved, f"{name} ({hexv}) tombe dans la bande reservee {band}")


class TestPaletteCandidates(unittest.TestCase):
	def test_eighteen_candidates_with_shadow_variants(self):
		palette = rw.load_palette()
		labels, lab = rw.palette_candidates_lab(palette)
		self.assertEqual(len(labels), 18)
		self.assertEqual(lab.shape, (18, 3))
		self.assertIn("enamel_steel", labels)
		self.assertIn("enamel_steel_shadow", labels)

	def test_shadow_scales_lightness_only(self):
		palette = rw.load_palette()
		labels, lab = rw.palette_candidates_lab(palette, shadow_factor=0.6)
		base = lab[labels.index("brass")]
		shadow = lab[labels.index("brass_shadow")]
		self.assertAlmostEqual(shadow[0], base[0] * 0.6, places=6)
		self.assertAlmostEqual(shadow[1], base[1], places=6)
		self.assertAlmostEqual(shadow[2], base[2], places=6)


class TestNearestCandidate(unittest.TestCase):
	def test_picks_the_closest(self):
		cand = np.array([[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]])
		pixels = np.array([[0.9, 0.1, 0.0], [0.1, 0.0, 0.0]])
		idx, dist = rw.nearest_candidate(pixels, cand)
		self.assertEqual(list(idx), [1, 0])
		np.testing.assert_allclose(dist, [np.linalg.norm([0.1, 0.1, 0.0]), np.linalg.norm([0.1, 0.0, 0.0])])


class TestGuardBlueSaturation(unittest.TestCase):
	"""Etape 4bis (revue du lead 2026-09-25 20:57) : filet de securite final,
	distinct de `guard_reserved_hues` -- desature au lieu de repousser hors
	bande (on veut un acier/sarcelle credible, pas une teinte au hasard)."""

	def test_violations_desaturated_hue_and_value_kept(self):
		# Bleu sature (comme le defaut mesure sur rafale.glb) au-dessus du
		# seuil de declenchement -- doit finir DESATURE sous la cible, teinte
		# et valeur (HSV) conservees.
		rgb = np.array([[[0.15, 0.25, 0.55]]], dtype=np.float64)
		fixed, count = rw.guard_blue_saturation(rgb, saturation_max=0.12, target_saturation=0.16)
		self.assertEqual(count, 1)
		hue_before, _ = rw.rgb_to_hue_sat(rgb[0, 0])
		hue_after, sat_after = rw.rgb_to_hue_sat(fixed[0, 0])
		self.assertLessEqual(float(sat_after), 0.16 + 1e-9)
		self.assertAlmostEqual(float(hue_after), float(hue_before), places=3)
		self.assertAlmostEqual(float(np.max(fixed[0, 0])), float(np.max(rgb[0, 0])), places=6)

	def test_allowed_pixels_untouched(self):
		# Cream (hors bande bleue) + un gris bleute mais TRES peu chromatique
		# (S=0,0625, sous le seuil de declenchement 0,12) -- aucun des deux
		# n'est un "bleu" au sens de ce garde.
		rgb = np.array([[[0.62, 0.47, 0.32], [0.30, 0.31, 0.32]]], dtype=np.float64)
		fixed, count = rw.guard_blue_saturation(rgb, saturation_max=0.12, target_saturation=0.16)
		self.assertEqual(count, 0)
		np.testing.assert_allclose(fixed, rgb)

	def test_default_trigger_is_below_native_steel_saturation(self):
		# Propriete cle du choix de seuil (voir la constante
		# BLUE_GUARD_SATURATION_TRIGGER) : l'acier emaille #4A505C lui-meme
		# (S=0,1957) doit declencher le garde par defaut, pour absorber la
		# derive de quantification PNG 8 bits mesuree sur les vraies armes.
		steel_hue, steel_sat = rw.rgb_to_hue_sat(np.array(rw.hex_to_rgb01("#4A505C")))
		self.assertTrue(bool(rw.hue_in_band(steel_hue, rw.BLUE_HUE_RANGE_DEG)))
		self.assertGreater(float(steel_sat), rw.BLUE_GUARD_SATURATION_TRIGGER)


class TestApplyBrushNoise(unittest.TestCase):
	"""Corrige un defaut mesure sur les vraies armes (revue du lead
	2026-09-25 20:57) : un jitter ADDITIF remonte la saturation HSV d'une
	couleur peu chromatique (l'acier emaille, S=0,196) des qu'il assombrit.
	Le jitter est desormais MULTIPLICATIF, qui preserve S exactement quel
	que soit le facteur -- voir `apply_brush_noise`."""

	@staticmethod
	def _single_face_buffer(shape):
		# Une seule face couvrant toute l'image (memes conventions que
		# `build_face_id_buffer` : id de face + 1, 0 = hors triangle) --
		# meme jitter partout, donc equivalent a un simple facteur d'echelle.
		return np.ones(shape, dtype=np.int64)

	def test_multiplicative_jitter_preserves_saturation(self):
		steel = np.array(rw.hex_to_rgb01("#4A505C"))
		img = np.tile(steel, (4, 4, 1))
		vertices = np.array([[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]])
		faces = np.array([[0, 1, 2]])
		face_id_buffer = self._single_face_buffer((4, 4))
		out = rw.apply_brush_noise(img, face_id_buffer, vertices, faces, amplitude=0.035, seed="test-seed")
		_, sat_before = rw.rgb_to_hue_sat(steel)
		hue_after, sat_after = rw.rgb_to_hue_sat(out[0, 0])
		self.assertAlmostEqual(float(sat_after), float(sat_before), places=9)
		# le jitter a quand meme bouge la couleur (sinon le test ne prouve rien)
		self.assertGreater(float(np.linalg.norm(out[0, 0] - steel)), 1e-4)

	def test_zero_amplitude_is_identity(self):
		img = np.tile(np.array([0.3, 0.4, 0.5]), (2, 2, 1))
		vertices = np.array([[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]])
		faces = np.array([[0, 1, 2]])
		face_id_buffer = self._single_face_buffer((2, 2))
		out = rw.apply_brush_noise(img, face_id_buffer, vertices, faces, amplitude=0.0, seed="x")
		np.testing.assert_allclose(out, img)


class TestGuardReservedHues(unittest.TestCase):
	def test_violations_pushed_out_of_band(self):
		rgb = np.array([[[1.0, 0.0, 0.9]], [[0.55, 0.12, 0.30]], [[0.3, 0.8, 0.3]]], dtype=np.float64)
		fixed, count = rw.guard_reserved_hues(rgb)
		self.assertEqual(count, 3)
		flat = fixed.reshape(-1, 3)
		hue, sat = rw.rgb_to_hue_sat(flat)
		for h, s in zip(hue, sat):
			for band in rw.RESERVED_HUE_BANDS_DEG:
				self.assertFalse(rw.hue_in_band(np.array([h]), band)[0] and s > rw.RESERVED_SATURATION_MIN)

	def test_allowed_pixels_untouched(self):
		rgb = np.array([[[0.62, 0.47, 0.32], [0.29, 0.31, 0.36]]], dtype=np.float64)
		fixed, count = rw.guard_reserved_hues(rgb)
		self.assertEqual(count, 0)
		np.testing.assert_allclose(fixed, rgb)


class TestApplyGlobalPull(unittest.TestCase):
	def test_saturated_blue_is_removed(self):
		# Damier synthetique tout bleu sature (hue ~220, S eleve) -- reproduit
		# le defaut mesure sur rafale.glb (90 % de texels a teinte bleue).
		img = np.tile(np.array([0.15, 0.25, 0.55]), (16, 16, 1))
		palette = rw.load_palette()
		out, report = rw.apply_global_pull(img, palette)
		hue, sat = rw.rgb_to_hue_sat(out.reshape(-1, 3))
		blue = rw.hue_in_band(hue, rw.BLUE_HUE_RANGE_DEG) & (sat > rw.BLUE_SATURATION_MIN)
		self.assertEqual(int(blue.sum()), 0)
		self.assertGreater(report["blue_remapped_texels"], 0)

	def test_non_blue_pull_uses_general_force_not_full_remap(self):
		# Un rouge legerement decale (pas bleu) doit etre TIRE (force 0,6),
		# jamais entierement remplace comme un bleu.
		img = np.tile(np.array([0.9, 0.2, 0.1]), (4, 4, 1))
		palette = rw.load_palette()
		out, _ = rw.apply_global_pull(img, palette, force=0.6)
		lab_before = rw.srgb_to_oklab(np.array([0.9, 0.2, 0.1]))
		lab_after = rw.srgb_to_oklab(out[0, 0])
		# a 0,6 le pixel ne doit ni rester sur place ni sauter pile sur la cible.
		self.assertGreater(np.linalg.norm(lab_after - lab_before), 1e-4)
		red_target = rw.srgb_to_oklab(np.array(rw.hex_to_rgb01(palette["accents"]["red"])))
		self.assertGreater(np.linalg.norm(lab_after - red_target), 1e-4)

	def test_shape_preserved(self):
		img = np.random.default_rng(0).random((8, 6, 3))
		palette = rw.load_palette()
		out, _ = rw.apply_global_pull(img, palette)
		self.assertEqual(out.shape, img.shape)
		self.assertTrue(np.all(out >= 0.0) and np.all(out <= 1.0))


class TestFacesInBox(unittest.TestCase):
	def test_selects_only_centroids_inside(self):
		vertices = np.array([
			[0, 0, 0], [1, 0, 0], [0, 1, 0],   # face 0 -- centroide (0.33,0.33,0)
			[5, 5, 5], [6, 5, 5], [5, 6, 5],   # face 1 -- loin
		], dtype=np.float64)
		faces = np.array([[0, 1, 2], [3, 4, 5]])
		mask = rw.faces_in_box(vertices, faces, [-1, -1, -1], [1, 1, 1])
		self.assertEqual(list(mask), [True, False])


class TestApplyColorForce(unittest.TestCase):
	def test_masked_pixels_move_toward_target_unmasked_untouched(self):
		img = np.tile(np.array([0.3, 0.3, 0.3]), (4, 4, 1))
		mask = np.zeros((4, 4), dtype=bool)
		mask[0, 0] = True
		out = rw.apply_color_force(img, mask, "#C8322B", force=1.0)
		np.testing.assert_allclose(out[0, 0], rw.hex_to_rgb01("#C8322B"), atol=1e-3)
		np.testing.assert_allclose(out[1, 1], img[1, 1])


class _WeldedCube:
	"""Cube unite jetable (`trimesh.creation.box` -- normales exterieures et
	sens de rotation garantis corrects, jamais ecrits a la main : un mauvais
	sens donnerait un `face_adjacency_convex` invalide, comme mesure lors de
	l'ecriture de ce test) avec une UV triviale par sommet -- sert a verifier
	la detection d'aretes convexes SANS toucher a un .glb reel. Toutes les
	aretes d'un cube convexe sont convexes par construction (angle diedre
	90 deg)."""

	def __init__(self):
		box = trimesh.creation.box(extents=(1.0, 1.0, 1.0))
		v = np.asarray(box.vertices, dtype=np.float64)
		uv = np.zeros((v.shape[0], 2), dtype=np.float64)
		uv[:, 0] = (v[:, 0] + v[:, 2] * 0.3 + 2.0) / 4.0
		uv[:, 1] = (v[:, 1] + v[:, 2] * 0.3 + 2.0) / 4.0
		self.vertices = v
		self.faces = np.asarray(box.faces, dtype=np.int64)
		self.uv = uv


class TestEdgeSegments(unittest.TestCase):
	def test_cube_edges_are_all_convex(self):
		cube = _WeldedCube()
		convex_segs, concave_segs = rw.find_edge_segments(cube.vertices, cube.faces, cube.uv,
			min_angle_deg=1.0, max_angle_deg=179.0)
		self.assertGreater(len(convex_segs), 0)
		self.assertEqual(len(concave_segs), 0)

	def test_flat_neighbouring_triangles_are_not_an_edge(self):
		# Deux triangles coplanaires (meme normale -- une face du cube coupee
		# en deux triangles, `trimesh.creation.box` : faces 0 et 2) partagent
		# une arete a 0 deg -- exclue par min_angle_deg par defaut.
		cube = _WeldedCube()
		coplanar = cube.faces[[0, 2]]
		convex_segs, concave_segs = rw.find_edge_segments(cube.vertices, coplanar, cube.uv)
		self.assertEqual(convex_segs, [])
		self.assertEqual(concave_segs, [])


class TestLightenDarken(unittest.TestCase):
	def test_lighten_moves_toward_white_never_exceeds_one(self):
		img = np.tile(np.array([0.2, 0.3, 0.4]), (3, 3, 1))
		mask = np.zeros((3, 3), dtype=bool)
		mask[1, 1] = True
		out = rw.lighten_toward_white(img, mask, amount=0.9)
		self.assertTrue(np.all(out[1, 1] > img[1, 1]))
		self.assertTrue(np.all(out <= 1.0))
		np.testing.assert_allclose(out[0, 0], img[0, 0])

	def test_darken_toward_moves_toward_target(self):
		img = np.tile(np.array([0.8, 0.8, 0.8]), (3, 3, 1))
		mask = np.ones((3, 3), dtype=bool)
		out = rw.darken_toward(img, mask, (0.0, 0.0, 0.0), amount=0.5)
		np.testing.assert_allclose(out, np.full((3, 3, 3), 0.4))


class TestSrgbLuma(unittest.TestCase):
	def test_rec709_weights(self):
		self.assertAlmostEqual(float(rw.srgb_luma(np.array([1.0, 1.0, 1.0]))), 1.0)
		self.assertAlmostEqual(float(rw.srgb_luma(np.array([0.0, 1.0, 0.0]))), 0.7152)


class TestManifest(unittest.TestCase):
	def test_manifest_lists_the_seven_weapons_with_measured_boxes(self):
		manifest = rw.load_manifest()
		ids = [w["id"] for w in manifest["weapons"]]
		self.assertEqual(sorted(ids), sorted(REQUIRED_WEAPONS))
		for entry in manifest["weapons"]:
			self.assertTrue(entry["boxes"], f"{entry['id']} n'a aucune boite d'accent")
			for box in entry["boxes"]:
				self.assertIn("box_min", box)
				self.assertIn("box_max", box)
				lo = box["box_min"]
				hi = box["box_max"]
				for a, b in zip(lo, hi):
					self.assertLessEqual(a, b, f"{entry['id']}/{box['part']}: box_min > box_max")

	def test_every_box_target_resolves(self):
		palette = rw.load_palette()
		manifest = rw.load_manifest()
		for entry in manifest["weapons"]:
			for box in entry["boxes"]:
				rw.resolve_target_hex(palette, box["target"])  # leve si invalide


# ---------------------------------------------------------------------------
# 2. Integration -- vraies armes (assets/models/weapons/*.glb, LECTURE SEULE).
# ---------------------------------------------------------------------------

@unittest.skipUnless(WEAPONS_PRESENT, "assets/models/weapons/*.glb absents de ce checkout")
class TestRepaintRealWeapons(unittest.TestCase):
	"""Un test par arme (`subTest`) -- verifie DIRECTEMENT les criteres
	d'acceptation FP-12 sur la sortie reelle du pipeline, pas une
	approximation synthetique. ~8 s/arme (chargement .glb + rappel OKLab sur
	2048x2048 + relief + garde de teinte)."""

	@classmethod
	def setUpClass(cls):
		cls.palette = rw.load_palette()
		cls.manifest = rw.load_manifest()
		cls.results = {}
		for entry in cls.manifest["weapons"]:
			wid = entry["id"]
			if wid not in WEAPONS_PRESENT:
				continue
			glb_path = os.path.join(WEAPONS_DIR, f"{wid}.glb")
			cls.results[wid] = rw.repaint_weapon(wid, glb_path, entry["boxes"], cls.palette)

	def test_output_is_2048_rgb(self):
		for wid, result in self.results.items():
			with self.subTest(weapon=wid):
				img = result["image"]
				self.assertEqual(img.size, (2048, 2048))
				self.assertEqual(img.mode, "RGB")

	def test_uv0_hash_matches_source(self):
		for wid, result in self.results.items():
			with self.subTest(weapon=wid):
				mesh = rw.load_weapon_mesh(os.path.join(WEAPONS_DIR, f"{wid}.glb"))
				self.assertEqual(result["uv0_hash"], rw.uv0_hash(mesh["uv"]))

	def test_blue_fraction_at_most_two_percent(self):
		for wid, result in self.results.items():
			with self.subTest(weapon=wid):
				rgb01 = np.asarray(result["image"], dtype=np.float64) / 255.0
				hue, sat = rw.rgb_to_hue_sat(rgb01.reshape(-1, 3))
				blue = rw.hue_in_band(hue, rw.BLUE_HUE_RANGE_DEG) & (sat > rw.BLUE_SATURATION_MIN)
				self.assertLessEqual(float(blue.mean()), 0.02, f"{wid}: {blue.mean()*100:.2f}% bleu")

	def test_reserved_hue_fraction_at_most_one_percent(self):
		for wid, result in self.results.items():
			with self.subTest(weapon=wid):
				rgb01 = np.asarray(result["image"], dtype=np.float64) / 255.0
				flat = rgb01.reshape(-1, 3)
				hue, sat = rw.rgb_to_hue_sat(flat)
				reserved = np.zeros(flat.shape[0], dtype=bool)
				for band in rw.RESERVED_HUE_BANDS_DEG:
					reserved |= rw.hue_in_band(hue, band) & (sat > rw.RESERVED_SATURATION_MIN)
				self.assertLessEqual(float(reserved.mean()), 0.01, f"{wid}: {reserved.mean()*100:.2f}% reserve")

	def test_lisere_luma_margin_at_least_six_hundredths(self):
		for wid, result in self.results.items():
			with self.subTest(weapon=wid):
				margin = result["report"]["relief"]["lisere_margin"]
				self.assertFalse(np.isnan(margin), f"{wid}: pas assez de texels de liisere/voisins pour mesurer")
				self.assertGreaterEqual(margin, 0.06, f"{wid}: marge {margin:.4f}")

	@unittest.skipUnless(HAVE_SCIPY_KMEANS, "scipy.cluster.vq indisponible")
	def test_six_kmeans_clusters_near_palette_or_shadow(self):
		labels, cand_lab = rw.palette_candidates_lab(self.palette)
		for wid, result in self.results.items():
			with self.subTest(weapon=wid):
				rgb01 = np.asarray(result["image"], dtype=np.float64) / 255.0
				lab = rw.srgb_to_oklab(rgb01.reshape(-1, 3))
				rng = np.random.default_rng(0)
				sample = lab[rng.choice(lab.shape[0], size=min(150000, lab.shape[0]), replace=False)]
				centroids, _ = kmeans2(sample, 6, seed=0, minit="++")
				_, dists = rw.nearest_candidate(centroids, cand_lab)
				for d in dists:
					self.assertLessEqual(float(d), 0.10, f"{wid}: cluster a DeltaE_OK={d:.4f}")


@unittest.skipUnless(all(w in WEAPONS_PRESENT for w in ("ravage", "fracas", "pistolet")),
	"ravage/fracas/pistolet absents de ce checkout")
class TestAcceptanceAccentsPresent(unittest.TestCase):
	"""Critere d'acceptation FP-12 explicite : "accents du §5.2 presents
	(garde-main rouge Ravage, tromblon laiton Fracas, carcasse creme
	Pistolet)" -- verifie que la couleur MOYENNE de chaque boite d'accent
	dans la texture PRODUITE est proche (DeltaE_OK <= 0,10, meme tolerance
	que le critere k-means) de sa cible."""

	CASES = [
		("ravage", "garde_main", "#C8322B"),
		("fracas", "tromblon", "#D9A21B"),
		("pistolet", "carcasse", "#E6E1D6"),
	]

	def test_accent_present_at_measured_location(self):
		palette = rw.load_palette()
		manifest = rw.load_manifest()
		for wid, part, target_hex in self.CASES:
			with self.subTest(weapon=wid, part=part):
				entry = next(e for e in manifest["weapons"] if e["id"] == wid)
				box = next(b for b in entry["boxes"] if b["part"] == part)
				glb_path = os.path.join(WEAPONS_DIR, f"{wid}.glb")
				mesh = rw.load_weapon_mesh(glb_path)
				result = rw.repaint_weapon(wid, glb_path, entry["boxes"], palette)
				rgb01 = np.asarray(result["image"], dtype=np.float64) / 255.0
				width, height = result["image"].size
				face_id_buffer = rw.build_face_id_buffer(mesh["uv"], mesh["faces"], width, height)
				fmask = rw.faces_in_box(mesh["vertices"], mesh["faces"], box["box_min"], box["box_max"])
				valid = face_id_buffer > 0
				face_idx = np.where(valid, face_id_buffer - 1, 0)
				texel_mask = valid & fmask[face_idx]
				self.assertGreater(int(texel_mask.sum()), 0, f"{wid}/{part}: boite vide sur ce maillage")
				mean_rgb = rgb01[texel_mask].mean(axis=0)
				mean_lab = rw.srgb_to_oklab(mean_rgb)
				target_lab = rw.srgb_to_oklab(np.array(rw.hex_to_rgb01(target_hex)))
				self.assertLessEqual(rw.delta_e_ok(mean_lab, target_lab), 0.10)


if __name__ == "__main__":
	unittest.main()
