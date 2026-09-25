#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/blender/tests/test_fp_rig.py
Tests de tools/blender/fp_rig.py (FP-10, voir docs/research/12_viewmodel_v2.md
§3.2 et les criteres d'acceptation de la tache).

Deux familles, meme convention que test_fit_weapon_painted.py/test_paint_bake.py :

1. Solveurs + contrat purs (`two_bone_ik_solve`, `shoulder_solve`,
   `auto_grip_finger`/`auto_grip_cylinder`, `delta_e_ok`, listes de noms
   d'os) -- AUCUNE dependance bpy (voir l'en-tete de fp_rig.py : import dans
   un bloc try/except). C'est cette famille qui verifie les criteres
   d'acceptation "test pytest" (epaules + auto-prise) du contrat FP-10.
   Import direct du module, sans lancer Blender.

2. Pipeline bpy reel (determinisme de la liste d'os/nombre de sommets sur
   deux executions, budget de tris, echelle des mains, ΔE_OK du cuir
   fp_glove) -- relance Blender EN SOUS-PROCESS (`blender -b -P
   tools/blender/fp_rig.py -- --out ...`), comme test_fit_weapon_painted.py.
   `--skip-paint` est utilise pour CE test (pas de cuisson Cycles, seul le
   determinisme squelette/maillage est en jeu) ; un test SEPARE, plus lent,
   verifie la peinture (ΔE_OK) avec `RUN_FP_RIG_PAINT_TEST=1` (desactive par
   defaut -- cuisson Cycles, minutes, jamais dans la boucle rapide
   d'iteration, voir CLAUDE.md "tests scopes pendant l'iteration").

Blender : `BLENDER_BIN` (variable d'environnement) sinon le chemin connu de
CLAUDE.md.

Lancer :
    python -m pytest tools/blender/tests/test_fp_rig.py -q
    RUN_FP_RIG_PAINT_TEST=1 python -m pytest tools/blender/tests/test_fp_rig.py -q -k paint
"""
from __future__ import annotations

import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_BLENDER_DIR = os.path.dirname(HERE)
REPO_ROOT = os.path.abspath(os.path.join(TOOLS_BLENDER_DIR, "..", ".."))
SRC_GLB = os.path.join(REPO_ROOT, "assets", "incoming", "quaternius", "ual.glb")

sys.path.insert(0, TOOLS_BLENDER_DIR)
import fp_rig  # noqa: E402
import fp_camera  # noqa: E402

BLENDER_BIN = os.environ.get("BLENDER_BIN", r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe")
BLENDER_AVAILABLE = os.path.isfile(BLENDER_BIN)
SRC_GLB_AVAILABLE = os.path.isfile(SRC_GLB)


# ---------------------------------------------------------------------------
# Famille 1 -- solveurs + contrat purs (aucun bpy, aucun sous-processus Blender)
# ---------------------------------------------------------------------------

class TestBoneContract(unittest.TestCase):
	"""Le contrat de noms d'os du doc 12 §3.2."""

	def test_root_and_weapon_part_bones_present(self):
		for name in ("fp_root", "fp_weapon", "fp_mag", "fp_slide", "fp_bolt",
				"fp_pump", "fp_cylinder", "fp_hammer", "fp_prop"):
			self.assertIn(name, fp_rig.DEFORM_BONE_NAMES)

	def test_arm_bones_present_both_sides(self):
		for side in ("L", "R"):
			for part in ("upper_arm", "forearm", "hand"):
				self.assertIn(f"DEF-{part}.{side}", fp_rig.DEFORM_BONE_NAMES)

	def test_finger_bones_present_both_sides(self):
		for side in ("L", "R"):
			for finger in ("index", "middle", "ring", "pinky"):
				for seg in ("01", "02", "03"):
					self.assertIn(f"DEF-f_{finger}.{seg}.{side}", fp_rig.DEFORM_BONE_NAMES)
			for seg in ("01", "02", "03"):
				self.assertIn(f"DEF-thumb.{seg}.{side}", fp_rig.DEFORM_BONE_NAMES)

	def test_deform_bone_count(self):
		# 9 (fp_root + 8 pieces) + 6 (upper_arm/forearm/hand x2) + 36 (4 doigts x3 seg x2 + pouce x3 seg x2).
		self.assertEqual(len(fp_rig.DEFORM_BONE_NAMES), 9 + 6 + (4 * 3 * 2 + 3 * 2))

	def test_no_overlap_between_deform_and_controller_bones(self):
		self.assertEqual(set(fp_rig.DEFORM_BONE_NAMES) & set(fp_rig.CONTROLLER_BONE_NAMES), set())

	def test_controller_bones_are_ik_hand_and_pole_elbow(self):
		self.assertEqual(fp_rig.CONTROLLER_BONE_NAMES,
			sorted(["ik_hand.L", "ik_hand.R", "pole_elbow.L", "pole_elbow.R"]))

	def test_deform_bone_names_never_contain_controller_prefixes(self):
		for name in fp_rig.DEFORM_BONE_NAMES:
			self.assertFalse(name.startswith("ik_") or name.startswith("pole_"), name)


class TestTwoBoneIK(unittest.TestCase):
	def test_reaches_reachable_target_exactly(self):
		shoulder = (0.0, 0.0, 0.0)
		l1, l2 = 0.3, 0.25
		target = (0.1, -0.2, -0.4)
		pole = (0.0, -1.0, -0.2)
		elbow, hand = fp_rig.two_bone_ik_solve(shoulder, target, pole, l1, l2)
		self.assertAlmostEqual(fp_rig.v_len(fp_rig.v_sub(hand, target)), 0.0, places=9)
		self.assertAlmostEqual(fp_rig.v_len(fp_rig.v_sub(elbow, shoulder)), l1, places=9)
		self.assertAlmostEqual(fp_rig.v_len(fp_rig.v_sub(hand, elbow)), l2, places=9)

	def test_deterministic_same_input_same_output(self):
		args = ((0.0, 0.0, 0.0), (0.15, -0.25, -0.5), (0.0, -1.0, 0.0), 0.3, 0.27)
		r1 = fp_rig.two_bone_ik_solve(*args)
		r2 = fp_rig.two_bone_ik_solve(*args)
		self.assertEqual(r1, r2)

	def test_out_of_reach_clamps_to_full_extension(self):
		shoulder = (0.0, 0.0, 0.0)
		l1, l2 = 0.2, 0.2
		target = (0.0, 0.0, -10.0)  # tres loin -- hors de portee (l1+l2=0.4).
		pole = (0.0, -1.0, 0.0)
		elbow, hand = fp_rig.two_bone_ik_solve(shoulder, target, pole, l1, l2)
		self.assertAlmostEqual(fp_rig.v_len(hand), l1 + l2, places=6)


class TestShoulderSolve(unittest.TestCase):
	"""Critere d'acceptation FP-10 : pour la prise (grip) a
	(0.20, -0.20, -0.42) et le soutien (support) a (0.02, -0.16, -0.70) en
	espace camera Godot, les deux mains atteignent leur cible a <= 2mm, coude
	plie de 25 a 60 deg, coudes projetes hors du cadre 16:9."""

	def _solve(self, side):
		target = fp_rig.TARGET_CAM[side]
		rest = fp_rig.SHOULDER_REST_CAM[side]
		pole = fp_rig.v_add(rest, fp_rig.POLE_OFFSET_CAM[side])
		return fp_rig.shoulder_solve(rest, target, pole)

	def test_grip_hand_reaches_target_within_2mm(self):
		r = self._solve("R")
		self.assertLessEqual(r["err"], 0.002, r)

	def test_support_hand_reaches_target_within_2mm(self):
		r = self._solve("L")
		self.assertLessEqual(r["err"], 0.002, r)

	def test_grip_elbow_bend_in_range(self):
		r = self._solve("R")
		lo, hi = fp_rig.SHOULDER_BEND_RANGE_DEG
		self.assertTrue(lo <= r["bend_deg"] <= hi, r)

	def test_support_elbow_bend_in_range(self):
		r = self._solve("L")
		lo, hi = fp_rig.SHOULDER_BEND_RANGE_DEG
		self.assertTrue(lo <= r["bend_deg"] <= hi, r)

	def test_grip_hand_reach_ratio_in_range(self):
		r = self._solve("R")
		lo, hi = fp_rig.SHOULDER_RATIO_RANGE
		self.assertTrue(lo - 1e-6 <= r["ratio"] <= hi + 1e-6, r)

	def test_support_hand_reach_ratio_in_range(self):
		r = self._solve("L")
		lo, hi = fp_rig.SHOULDER_RATIO_RANGE
		self.assertTrue(lo - 1e-6 <= r["ratio"] <= hi + 1e-6, r)

	def test_grip_translation_stays_bounded(self):
		r = self._solve("R")
		self.assertLessEqual(r["translation_len"], fp_rig.SHOULDER_MAX_TRANSLATION_M + 1e-9)

	def test_support_translation_stays_bounded(self):
		r = self._solve("L")
		self.assertLessEqual(r["translation_len"], fp_rig.SHOULDER_MAX_TRANSLATION_M + 1e-9)

	def test_grip_elbow_outside_16_9_frame(self):
		r = self._solve("R")
		self.assertTrue(fp_rig.is_outside_frame(r["elbow"]), r["elbow"])

	def test_support_elbow_outside_16_9_frame(self):
		r = self._solve("L")
		self.assertTrue(fp_rig.is_outside_frame(r["elbow"]), r["elbow"])

	def test_deterministic(self):
		r1 = self._solve("R")
		r2 = self._solve("R")
		self.assertEqual(r1, r2)

	def test_stretch_never_exceeds_1_12(self):
		for side in ("L", "R"):
			r = self._solve(side)
			self.assertLessEqual(r["stretch"], fp_rig.SHOULDER_MAX_STRETCH + 1e-9)


class TestAutoGripCylinder(unittest.TestCase):
	"""Critere d'acceptation FP-10 : auto-prise sur un cylindre r=1.8cm --
	chaque bout de doigt a 0.4-1.2cm de la surface, aucune articulation
	> 95 deg."""

	@classmethod
	def setUpClass(cls):
		cls.result = fp_rig.auto_grip_cylinder()

	def test_all_five_digits_present(self):
		self.assertEqual(set(self.result.keys()), {"thumb", "index", "middle", "ring", "pinky"})

	def test_each_fingertip_within_contact_window(self):
		for name, r in self.result.items():
			cm = r["tip_distance"] * 100.0
			self.assertTrue(0.4 <= cm <= 1.2, f"{name}: {cm:.3f} cm hors de [0.4, 1.2] -- {r}")

	def test_no_joint_exceeds_95_degrees(self):
		for name, r in self.result.items():
			for angle in r["angles_deg"]:
				self.assertLessEqual(angle, 95.0 + 1e-9, f"{name}: {r['angles_deg']}")

	def test_deterministic(self):
		r1 = fp_rig.auto_grip_cylinder()
		r2 = fp_rig.auto_grip_cylinder()
		self.assertEqual(r1, r2)

	def test_step_is_2_degrees(self):
		# chaque angle doit etre un multiple (a l'epsilon pres) de 2 deg.
		for r in self.result.values():
			for angle in r["angles_deg"]:
				steps = angle / fp_rig.AUTO_GRIP_STEP_DEG
				self.assertAlmostEqual(steps, round(steps), places=6)

	def test_default_radius_matches_contract(self):
		self.assertAlmostEqual(fp_rig.DEFAULT_GRIP_CYLINDER_RADIUS_M, 0.018)


class TestFingerPresets(unittest.TestCase):
	def test_all_presets_within_95_degree_cap(self):
		for preset_name, preset in fp_rig.FINGER_PRESETS.items():
			for finger, angles in preset.items():
				for a in angles:
					self.assertLessEqual(a, fp_rig.FINGER_PRESET_MAX_DEG, (preset_name, finger))
					self.assertGreaterEqual(a, 0.0, (preset_name, finger))

	def test_open_preset_is_fully_extended(self):
		for angles in fp_rig.FINGER_PRESETS["open"].values():
			self.assertEqual(angles, (0.0, 0.0, 0.0))

	def test_every_preset_covers_five_digits(self):
		for preset in fp_rig.FINGER_PRESETS.values():
			self.assertEqual(set(preset.keys()), {"thumb", "index", "middle", "ring", "pinky"})


class TestDeltaEOK(unittest.TestCase):
	def test_identical_colors_have_zero_delta(self):
		rgb = fp_rig.hex_to_srgb01(fp_rig.FP_GLOVE_HEX)
		self.assertAlmostEqual(fp_rig.delta_e_ok(rgb, rgb), 0.0, places=9)

	def test_black_vs_white_is_far(self):
		self.assertGreater(fp_rig.delta_e_ok((0.0, 0.0, 0.0), (1.0, 1.0, 1.0)), 0.5)

	def test_glove_hex_is_the_documented_leather_color(self):
		# docs/style/tokens.json color.character_shared.leather / fp_gear_substitute.to.
		self.assertEqual(fp_rig.FP_GLOVE_HEX, "#6B4A2E")

	def test_small_perturbation_stays_under_threshold(self):
		base = fp_rig.hex_to_srgb01(fp_rig.FP_GLOVE_HEX)
		nudged = tuple(min(1.0, c + 0.01) for c in base)
		self.assertLess(fp_rig.delta_e_ok(base, nudged), fp_rig.FP_GLOVE_DELTA_E_MAX)


class TestHandScale(unittest.TestCase):
	def test_hand_scale_is_1_15(self):
		self.assertAlmostEqual(fp_rig.HAND_SCALE, 1.15)

	def test_hand_scale_tolerance_is_0_02(self):
		self.assertAlmostEqual(fp_rig.HAND_SCALE_TOLERANCE, 0.02)


class TestArmMeasurements(unittest.TestCase):
	"""Constantes mesurees sur ual.glb (voir en-tete de fp_rig.py / rapport
	de tache) -- verrouille contre une regression silencieuse des chiffres
	copies dans le fichier."""

	def test_reach_is_sum_of_upper_and_forearm(self):
		self.assertAlmostEqual(fp_rig.ARM_REACH_M, fp_rig.ARM_UPPER_LEN_M + fp_rig.ARM_FOREARM_LEN_M)

	def test_arm_lengths_are_positive_and_plausible(self):
		for length in (fp_rig.ARM_UPPER_LEN_M, fp_rig.ARM_FOREARM_LEN_M, fp_rig.ARM_HAND_LEN_M):
			self.assertGreater(length, 0.0)
			self.assertLess(length, 1.0)  # un bras humain ne mesure pas 1 m par segment.


# ---------------------------------------------------------------------------
# Famille 2 -- pipeline bpy reel (sous-processus Blender).
# ---------------------------------------------------------------------------

@unittest.skipUnless(BLENDER_AVAILABLE, f"Blender introuvable ({BLENDER_BIN}) -- voir BLENDER_BIN")
@unittest.skipUnless(SRC_GLB_AVAILABLE, f"source UAL absente : {SRC_GLB}")
class TestBlenderPipelineDeterminism(unittest.TestCase):
	"""Critere d'acceptation : deux executions de `blender -b -P fp_rig.py --
	--out ...` donnent la MEME liste d'os et le MEME nombre de sommets.
	`--skip-paint` : seul le squelette/maillage est en jeu ici (pas de
	cuisson Cycles, voir la classe de peinture separee ci-dessous)."""

	@classmethod
	def setUpClass(cls):
		cls.tmp_dir = tempfile.mkdtemp(prefix="fp_rig_test_")
		cls.runs = []
		for i in range(2):
			out_path = os.path.join(cls.tmp_dir, f"fp_arms_{i}.glb")
			proc = subprocess.run([
				BLENDER_BIN, "-b", "--factory-startup", "--python-exit-code", "1",
				"-P", os.path.join(TOOLS_BLENDER_DIR, "fp_rig.py"), "--",
				"--out", out_path, "--skip-paint",
			], capture_output=True, text=True, timeout=300)
			cls.runs.append(proc)

	@classmethod
	def tearDownClass(cls):
		shutil.rmtree(cls.tmp_dir, ignore_errors=True)

	def _bones_and_verts(self, proc):
		self.assertEqual(proc.returncode, 0, proc.stdout + "\n" + proc.stderr)
		bones = None
		verts = None
		for line in proc.stdout.splitlines():
			if line.startswith("FP_RIG_BONES "):
				bones = line[len("FP_RIG_BONES "):].strip()
			elif line.startswith("FP_RIG_VERTS "):
				verts = line[len("FP_RIG_VERTS "):].strip()
		self.assertIsNotNone(bones, proc.stdout)
		self.assertIsNotNone(verts, proc.stdout)
		return bones, verts

	def test_two_runs_produce_the_same_bone_list_and_vertex_count(self):
		bones0, verts0 = self._bones_and_verts(self.runs[0])
		bones1, verts1 = self._bones_and_verts(self.runs[1])
		self.assertEqual(bones0, bones1)
		self.assertEqual(verts0, verts1)

	def test_bone_list_matches_the_contract(self):
		bones0, _ = self._bones_and_verts(self.runs[0])
		self.assertEqual(bones0.split(","), fp_rig.DEFORM_BONE_NAMES)

	def test_no_controller_bone_in_the_exported_list(self):
		bones0, _ = self._bones_and_verts(self.runs[0])
		exported = set(bones0.split(","))
		self.assertEqual(exported & set(fp_rig.CONTROLLER_BONE_NAMES), set())

	def test_tri_budget_respected(self):
		proc = self.runs[0]
		tris = None
		for line in proc.stdout.splitlines():
			if line.startswith("FP_RIG_TRIS "):
				tris = int(line.split()[1])
				break
		self.assertIsNotNone(tris, proc.stdout)
		self.assertLessEqual(tris, fp_rig.TRI_BUDGET_ARMS)


@unittest.skipUnless(BLENDER_AVAILABLE, f"Blender introuvable ({BLENDER_BIN}) -- voir BLENDER_BIN")
@unittest.skipUnless(SRC_GLB_AVAILABLE, f"source UAL absente : {SRC_GLB}")
class TestBlenderPipelineFloatingMode(unittest.TestCase):
	"""Les deux modes --arms-mode s'exportent sans erreur (critere
	d'acceptation : "modes forearm et floating exportes")."""

	def test_floating_mode_exports(self):
		tmp_dir = tempfile.mkdtemp(prefix="fp_rig_floating_")
		try:
			out_path = os.path.join(tmp_dir, "fp_arms_floating.glb")
			proc = subprocess.run([
				BLENDER_BIN, "-b", "--factory-startup", "--python-exit-code", "1",
				"-P", os.path.join(TOOLS_BLENDER_DIR, "fp_rig.py"), "--",
				"--out", out_path, "--arms-mode", "floating", "--skip-paint",
			], capture_output=True, text=True, timeout=300)
			self.assertEqual(proc.returncode, 0, proc.stdout + "\n" + proc.stderr)
			self.assertTrue(os.path.isfile(out_path))
			self.assertIn("FP_RIG_OK", proc.stdout)
		finally:
			shutil.rmtree(tmp_dir, ignore_errors=True)


@unittest.skipUnless(os.environ.get("RUN_FP_RIG_PAINT_TEST") == "1",
	"cuisson Cycles (minutes) -- desactive par defaut, voir RUN_FP_RIG_PAINT_TEST dans l'en-tete")
@unittest.skipUnless(BLENDER_AVAILABLE, f"Blender introuvable ({BLENDER_BIN})")
@unittest.skipUnless(SRC_GLB_AVAILABLE, f"source UAL absente : {SRC_GLB}")
class TestBlenderPipelinePaint(unittest.TestCase):
	"""Critere d'acceptation : cuir fp_glove a DeltaE_OK <= 0.08 de #6B4A2E.
	Lent (cuisson Cycles reelle) -- RUN_FP_RIG_PAINT_TEST=1 pour l'activer."""

	def test_glove_delta_e_within_threshold(self):
		tmp_dir = tempfile.mkdtemp(prefix="fp_rig_paint_")
		try:
			out_path = os.path.join(tmp_dir, "fp_arms.glb")
			proc = subprocess.run([
				BLENDER_BIN, "-b", "--factory-startup", "--python-exit-code", "1",
				"-P", os.path.join(TOOLS_BLENDER_DIR, "fp_rig.py"), "--",
				"--out", out_path,
			], capture_output=True, text=True, timeout=900)
			self.assertEqual(proc.returncode, 0, proc.stdout + "\n" + proc.stderr)
			delta_e = None
			for line in proc.stdout.splitlines():
				if line.startswith("FP_RIG_GLOVE_DELTA_E "):
					delta_e = float(line.split()[1])
			self.assertIsNotNone(delta_e, proc.stdout)
			self.assertLessEqual(delta_e, fp_rig.FP_GLOVE_DELTA_E_MAX, proc.stdout)
		finally:
			shutil.rmtree(tmp_dir, ignore_errors=True)


if __name__ == "__main__":
	unittest.main()
