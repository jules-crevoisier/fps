#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/ai3d/tests/test_run_batch.py
Tests de tools/ai3d/run_batch.py : validation de manifeste, estimation de
crédits, construction de commandes par route, logique "ne jamais régénérer un
id déjà présent", écriture de provenance, et ingestion d'un dossier Studio
(hors manifeste). AUCUN appel réseau : tout point de passage vers `tripo` /
Blender / Godot (`run_batch._run_command`) est remplacé par un double de test
(voir `_FakeRun`).

Lancer :
    python -m pytest tools/ai3d/tests/test_run_batch.py -q
    (ou, sans pytest : python tools/ai3d/tests/test_run_batch.py)
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import run_batch  # noqa: E402

FIXTURES = Path(__file__).resolve().parent / "fixtures"
MINI_MANIFEST = FIXTURES / "mini_manifest.yaml"


class _FakeProc:
	"""Imite subprocess.CompletedProcess (juste ce que run_batch lit)."""

	def __init__(self, returncode=0, stdout="", stderr=""):
		self.returncode = returncode
		self.stdout = stdout
		self.stderr = stderr


class _FakeRun:
	"""Remplace run_batch._run_command : rejoue une liste de réponses dans
	l'ordre des appels, et enregistre chaque argv reçu (pour les assertions de
	construction de commande)."""

	def __init__(self, responses):
		self.responses = list(responses)
		self.calls = []

	def __call__(self, argv, cwd=None):
		self.calls.append(list(argv))
		if not self.responses:
			raise AssertionError(f"appel tripo inattendu (plus de réponse simulée) : {argv}")
		resp = self.responses.pop(0)
		if isinstance(resp, Exception):
			raise resp
		return resp


def _tripo_json(stdout_obj: dict) -> _FakeProc:
	return _FakeProc(returncode=0, stdout=json.dumps(stdout_obj))


# ============================================================================
#  Validation du manifeste
# ============================================================================

class TestManifestValidation(unittest.TestCase):
	def test_fixture_loads_four_entries(self):
		entries = run_batch.load_manifest(MINI_MANIFEST)
		self.assertEqual(len(entries), 4)
		by_id = {e.id: e for e in entries}
		self.assertEqual(by_id["verrou_v1"].route, "image")
		self.assertEqual(by_id["vif_v1"].route, "text")
		self.assertEqual(by_id["crate_ammo_test"].route, "text")
		self.assertTrue(by_id["crate_ammo_test"].quad)
		self.assertTrue(by_id["crate_ammo_test"].smart_lowpoly)
		self.assertEqual(by_id["turret_concept_test"].route, "multiview")

	def test_missing_required_key_raises(self):
		with tempfile.TemporaryDirectory() as td:
			p = Path(td) / "bad.yaml"
			p.write_text(
				"- id: foo\n  category: prop\n  route: text\n  prompt: x\n"
				"  face_limit: 1000\n  quad: false\n  texture: true\n"
				"  # smart_lowpoly manquant, budget_tris manquant, scale_m manquant, priority manquant\n",
				encoding="utf-8",
			)
			with self.assertRaises(run_batch.ManifestError) as ctx:
				run_batch.load_manifest(p)
			msg = str(ctx.exception)
			self.assertIn("foo", msg)
			self.assertIn("smart_lowpoly", msg)

	def test_unknown_category_raises(self):
		with tempfile.TemporaryDirectory() as td:
			p = Path(td) / "bad.yaml"
			p.write_text(
				"- id: foo\n  category: vehicle\n  route: text\n  prompt: x\n"
				"  face_limit: 1000\n  quad: false\n  texture: true\n"
				"  smart_lowpoly: false\n  budget_tris: 500\n  scale_m: 1.0\n  priority: P0\n",
				encoding="utf-8",
			)
			with self.assertRaises(run_batch.ManifestError) as ctx:
				run_batch.load_manifest(p)
			self.assertIn("category", str(ctx.exception))

	def test_unknown_route_raises(self):
		with tempfile.TemporaryDirectory() as td:
			p = Path(td) / "bad.yaml"
			p.write_text(
				"- id: foo\n  category: prop\n  route: photogrammetry\n  prompt: x\n"
				"  face_limit: 1000\n  quad: false\n  texture: true\n"
				"  smart_lowpoly: false\n  budget_tris: 500\n  scale_m: 1.0\n  priority: P0\n",
				encoding="utf-8",
			)
			with self.assertRaises(run_batch.ManifestError) as ctx:
				run_batch.load_manifest(p)
			self.assertIn("route", str(ctx.exception))

	def test_duplicate_id_raises(self):
		with tempfile.TemporaryDirectory() as td:
			p = Path(td) / "bad.yaml"
			entry = (
				"id: dup\n  category: prop\n  route: text\n  prompt: x\n"
				"  face_limit: 1000\n  quad: false\n  texture: true\n"
				"  smart_lowpoly: false\n  budget_tris: 500\n  scale_m: 1.0\n  priority: P0\n"
			)
			p.write_text(f"- {entry}- {entry}", encoding="utf-8")
			with self.assertRaises(run_batch.ManifestError) as ctx:
				run_batch.load_manifest(p)
			self.assertIn("dupliqué", str(ctx.exception))

	def test_wrong_types_raise(self):
		with tempfile.TemporaryDirectory() as td:
			p = Path(td) / "bad.yaml"
			p.write_text(
				"- id: foo\n  category: prop\n  route: text\n  prompt: x\n"
				"  face_limit: \"beaucoup\"\n  quad: \"oui\"\n  texture: true\n"
				"  smart_lowpoly: false\n  budget_tris: 500\n  scale_m: 1.0\n  priority: P0\n",
				encoding="utf-8",
			)
			with self.assertRaises(run_batch.ManifestError) as ctx:
				run_batch.load_manifest(p)
			msg = str(ctx.exception)
			self.assertIn("face_limit", msg)
			self.assertIn("quad", msg)

	def test_not_a_list_raises(self):
		with tempfile.TemporaryDirectory() as td:
			p = Path(td) / "bad.yaml"
			p.write_text("id: foo\ncategory: prop\n", encoding="utf-8")
			with self.assertRaises(run_batch.ManifestError):
				run_batch.load_manifest(p)

	def test_select_entries_only_and_priority(self):
		entries = run_batch.load_manifest(MINI_MANIFEST)
		only = run_batch.select_entries(entries, "verrou_v1,vif_v1", None)
		self.assertEqual({e.id for e in only}, {"verrou_v1", "vif_v1"})
		p0 = run_batch.select_entries(entries, None, "P0")
		self.assertEqual({e.id for e in p0}, {"verrou_v1", "vif_v1"})
		both = run_batch.select_entries(entries, "verrou_v1,crate_ammo_test", "P0")
		self.assertEqual({e.id for e in both}, {"verrou_v1"})


# ============================================================================
#  Estimation de crédits
# ============================================================================

class TestCreditEstimation(unittest.TestCase):
	def _entry(self, **overrides):
		base = dict(
			id="x", category="prop", route="text", prompt="p", face_limit=1000,
			quad=False, texture=False, smart_lowpoly=False, budget_tris=500,
			scale_m=1.0, priority="P0",
		)
		base.update(overrides)
		return run_batch.ManifestEntry(**base)

	def test_bare_text_route_is_base_cost(self):
		e = self._entry()
		self.assertEqual(run_batch.estimate_credits(e), run_batch.BASE_GENERATION_CREDITS)

	def test_image_route_adds_concept_image_cost(self):
		e = self._entry(route="image", image_prompt="concept")
		expected = run_batch.BASE_GENERATION_CREDITS + run_batch.CONCEPT_IMAGE_CREDITS
		self.assertEqual(run_batch.estimate_credits(e), expected)

	def test_multiview_route_adds_both_extras(self):
		e = self._entry(route="multiview", image_prompt="concept")
		expected = (
			run_batch.BASE_GENERATION_CREDITS
			+ run_batch.CONCEPT_IMAGE_CREDITS
			+ run_batch.MULTIVIEW_EXTRA_CREDITS
		)
		self.assertEqual(run_batch.estimate_credits(e), expected)

	def test_all_addons_stack(self):
		e = self._entry(quad=True, texture=True, smart_lowpoly=True)
		expected = (
			run_batch.BASE_GENERATION_CREDITS
			+ run_batch.QUAD_CREDITS
			+ run_batch.TEXTURE_MARGIN_CREDITS
			+ run_batch.SMART_LOWPOLY_CREDITS
		)
		self.assertEqual(run_batch.estimate_credits(e), expected)

	def test_disabling_texture_never_lowers_estimate_below_base(self):
		# Estimation majorée par sécurité : texture=false ne doit jamais faire
		# baisser sous le coût de base (voir commentaire dans run_batch.py).
		e = self._entry(texture=False)
		self.assertGreaterEqual(run_batch.estimate_credits(e), run_batch.BASE_GENERATION_CREDITS)

	def test_plan_batch_sums_all_entries(self):
		entries = run_batch.load_manifest(MINI_MANIFEST)
		plan = run_batch.plan_batch(entries)
		self.assertEqual(plan["total"], sum(plan["per_entry"].values()))
		self.assertEqual(len(plan["per_entry"]), 4)

	def test_check_budget_refuses_over_cap(self):
		problems = run_batch.check_budget(total=1000, max_credits=500, balance=None)
		self.assertTrue(problems)
		self.assertIn("500", problems[0])

	def test_check_budget_refuses_over_live_balance(self):
		problems = run_batch.check_budget(total=100, max_credits=500, balance=50)
		self.assertTrue(problems)
		self.assertTrue(any("solde" in p for p in problems))

	def test_check_budget_ok(self):
		problems = run_batch.check_budget(total=50, max_credits=500, balance=200)
		self.assertEqual(problems, [])


# ============================================================================
#  Construction de commandes par route (pure, sans subprocess)
# ============================================================================

class TestCommandBuilding(unittest.TestCase):
	def _entry(self, **overrides):
		base = dict(
			id="padlock", category="prop", route="text", prompt="a rusty padlock",
			face_limit=6000, quad=False, texture=True, smart_lowpoly=False,
			budget_tris=800, scale_m=0.2, priority="P0", image_prompt=None,
		)
		base.update(overrides)
		return run_batch.ManifestEntry(**base)

	def test_text_route_single_step_uses_make(self):
		e = self._entry()
		steps = run_batch.build_generation_commands(e, Path("/tmp/work"))
		self.assertEqual(len(steps), 1)
		argv = steps[0]["argv"]
		self.assertEqual(argv[0], "tripo")
		self.assertEqual(argv[1], "make")
		self.assertIn(e.prompt, argv)
		self.assertIn("face_limit=6000", argv)
		self.assertIn("texture=true", argv)
		self.assertIn("quad=false", argv)
		self.assertIn("smart_low_poly=false", argv)
		self.assertNotIn("--for", argv)  # jamais de scénario : le manifeste pilote déjà tout
		self.assertNotIn("--then", argv)

	def test_quad_or_smart_lowpoly_forces_v31_model(self):
		e = self._entry(quad=True)
		argv = run_batch.build_generation_commands(e, Path("/tmp/work"))[0]["argv"]
		self.assertIn("--model", argv)
		self.assertIn("tripo-v3.1", argv)

	def test_no_special_option_leaves_model_auto(self):
		e = self._entry()
		argv = run_batch.build_generation_commands(e, Path("/tmp/work"))[0]["argv"]
		self.assertNotIn("--model", argv)

	def test_image_route_two_steps(self):
		e = self._entry(route="image", image_prompt="concept art of a padlock")
		steps = run_batch.build_generation_commands(e, Path("/tmp/work"))
		self.assertEqual(len(steps), 2)
		self.assertEqual(steps[0]["argv"][:3], ["tripo", "generate", "text-to-image"])
		self.assertIn("concept art of a padlock", steps[0]["argv"])
		self.assertEqual(steps[1]["argv"][:3], ["tripo", "generate", "image-to-model"])
		self.assertIn("__PREV_FILE__", steps[1]["argv"])
		self.assertIn("face_limit=6000", steps[1]["argv"])

	def test_image_route_falls_back_to_prompt_without_image_prompt(self):
		e = self._entry(route="image", image_prompt=None)
		steps = run_batch.build_generation_commands(e, Path("/tmp/work"))
		self.assertIn(e.prompt, steps[0]["argv"])

	def test_multiview_route_three_steps(self):
		e = self._entry(route="multiview", image_prompt="turret concept")
		steps = run_batch.build_generation_commands(e, Path("/tmp/work"))
		self.assertEqual(len(steps), 3)
		self.assertEqual(steps[0]["argv"][:3], ["tripo", "generate", "text-to-image"])
		self.assertEqual(steps[1]["argv"][:3], ["tripo", "generate", "image-to-multiview"])
		self.assertIn("__PREV_FILE__", steps[1]["argv"])
		self.assertEqual(steps[2]["argv"][:3], ["tripo", "generate", "multiview-to-model"])
		self.assertIn("__PREV_FILES__", steps[2]["argv"])

	def test_unknown_route_raises(self):
		e = self._entry(route="text")
		object.__setattr__(e, "route", "bogus")  # dataclass frozen — bidouille test uniquement
		with self.assertRaises(ValueError):
			run_batch.build_generation_commands(e, Path("/tmp/work"))

	def test_materialize_argv_substitutes_single_and_multi(self):
		argv = run_batch._materialize_argv(
			["tripo", "generate", "image-to-model", "__PREV_FILE__"], [Path("/a/b.png")]
		)
		self.assertEqual(argv[-1], str(Path("/a/b.png")))

		argv2 = run_batch._materialize_argv(
			["tripo", "generate", "multiview-to-model", "__PREV_FILES__"],
			[Path("/a/front.png"), Path("/a/back.png")],
		)
		self.assertEqual(argv2[3:], [str(Path("/a/front.png")), str(Path("/a/back.png"))])

	def test_materialize_argv_raises_without_prev_files(self):
		with self.assertRaises(RuntimeError):
			run_batch._materialize_argv(["x", "__PREV_FILE__"], [])


# ============================================================================
#  Exécution réelle (mockée) : skip-existant, retry, provenance
# ============================================================================

class TestGenerationExecution(unittest.TestCase):
	def setUp(self):
		self._tmp = tempfile.TemporaryDirectory()
		self.addCleanup(self._tmp.cleanup)
		self.root = Path(self._tmp.name)
		self._patchers = [
			mock.patch.object(run_batch, "ROOT", self.root),
			mock.patch.object(run_batch, "OUT_ROOT", self.root / "assets" / "incoming" / "tripo"),
			mock.patch.object(run_batch, "WORK_ROOT", self.root / "assets" / "incoming" / "tripo" / "_work"),
		]
		for p in self._patchers:
			p.start()
			self.addCleanup(p.stop)

	def _entry(self, **overrides):
		base = dict(
			id="padlock", category="prop", route="text", prompt="a rusty padlock",
			face_limit=6000, quad=False, texture=True, smart_lowpoly=False,
			budget_tris=800, scale_m=0.2, priority="P0", image_prompt=None,
		)
		base.update(overrides)
		return run_batch.ManifestEntry(**base)

	def test_text_route_generation_end_to_end_mocked(self):
		e = self._entry()
		work_dir = run_batch.WORK_ROOT / e.id
		fake = _FakeRun([
			_tripo_json({
				"task_id": "task_abc", "credits_consumed": 27,
				"output_dir": str(work_dir), "files": ["model.glb", "preview.png", "task.json"],
				"model_file": str(work_dir / "model.glb"),
			}),
		])
		(work_dir).mkdir(parents=True, exist_ok=True)
		(work_dir / "model.glb").write_bytes(b"glTF-fake")
		with mock.patch.object(run_batch, "_run_command", fake):
			result = run_batch.run_generation(e, work_dir)
		self.assertEqual(result["task_ids"], ["task_abc"])
		self.assertEqual(result["credits_spent"], 27)
		self.assertEqual(result["glb_path"], work_dir / "model.glb")

	def test_run_generation_raises_when_no_glb_in_output(self):
		e = self._entry()
		work_dir = run_batch.WORK_ROOT / e.id
		fake = _FakeRun([
			_tripo_json({
				"task_id": "task_abc", "credits_consumed": 27,
				"output_dir": str(work_dir), "files": ["model.fbx", "preview.png"],
			}),
		])
		with mock.patch.object(run_batch, "_run_command", fake):
			with self.assertRaises(RuntimeError):
				run_batch.run_generation(e, work_dir)

	def test_run_generation_retries_once_then_succeeds(self):
		e = self._entry()
		work_dir = run_batch.WORK_ROOT / e.id
		work_dir.mkdir(parents=True, exist_ok=True)
		(work_dir / "model.glb").write_bytes(b"glTF-fake")
		fake = _FakeRun([
			_FakeProc(returncode=7, stdout="", stderr="network error"),
			_tripo_json({
				"task_id": "task_retry", "credits_consumed": 20,
				"output_dir": str(work_dir), "files": ["model.glb"],
			}),
		])
		with mock.patch.object(run_batch, "_run_command", fake), \
			mock.patch.object(run_batch.time, "sleep", lambda *_: None):
			result = run_batch.run_generation_with_retry(e, work_dir, retries=1)
		self.assertEqual(result["task_ids"], ["task_retry"])
		self.assertEqual(len(fake.calls), 2)

	def test_run_generation_gives_up_after_retries_exhausted(self):
		e = self._entry()
		work_dir = run_batch.WORK_ROOT / e.id
		fake = _FakeRun([
			_FakeProc(returncode=7, stdout="", stderr="network error"),
			_FakeProc(returncode=7, stdout="", stderr="network error again"),
		])
		with mock.patch.object(run_batch, "_run_command", fake), \
			mock.patch.object(run_batch.time, "sleep", lambda *_: None):
			with self.assertRaises(run_batch.TripoCommandError):
				run_batch.run_generation_with_retry(e, work_dir, retries=1)
		self.assertEqual(len(fake.calls), 2)

	def test_resolve_glb_path_finds_category_file(self):
		e = self._entry()
		dest = run_batch.category_glb_path(e)
		dest.parent.mkdir(parents=True, exist_ok=True)
		dest.write_bytes(b"already-here")
		self.assertEqual(run_batch.resolve_glb_path(e), dest)

	def test_write_provenance_contents(self):
		e = self._entry()
		dest = run_batch.category_glb_path(e)
		dest.parent.mkdir(parents=True, exist_ok=True)
		dest.write_bytes(b"fake-glb")
		path = run_batch.write_provenance(e, dest, ["task_1", "task_2"], 42, "0.5.1")
		self.assertTrue(path.is_file())
		data = json.loads(path.read_text(encoding="utf-8"))
		self.assertEqual(data["id"], "padlock")
		self.assertEqual(data["tool"], "tripo-cli")
		self.assertEqual(data["tool_version"], "0.5.1")
		self.assertEqual(data["task_ids"], ["task_1", "task_2"])
		self.assertEqual(data["credits_spent"], 42)
		self.assertEqual(data["params"]["face_limit"], 6000)
		self.assertEqual(data["licence"], run_batch.LICENCE_NOTE)
		self.assertIn("date", data)


# ============================================================================
#  Skip-existant bout en bout (manifeste dédié, GLB pré-existant)
# ============================================================================

class TestSkipExistingEndToEnd(unittest.TestCase):
	def setUp(self):
		self._tmp = tempfile.TemporaryDirectory()
		self.addCleanup(self._tmp.cleanup)
		self.root = Path(self._tmp.name)
		self.out_root = self.root / "assets" / "incoming" / "tripo"
		self._patchers = [
			mock.patch.object(run_batch, "ROOT", self.root),
			mock.patch.object(run_batch, "OUT_ROOT", self.out_root),
			mock.patch.object(run_batch, "WORK_ROOT", self.out_root / "_work"),
		]
		for p in self._patchers:
			p.start()
			self.addCleanup(p.stop)

		self.manifest_path = self.root / "one.yaml"
		self.manifest_path.write_text(
			"- id: existing_prop\n  category: prop\n  route: text\n"
			"  prompt: une caisse\n  face_limit: 2000\n  quad: false\n"
			"  texture: true\n  smart_lowpoly: false\n  budget_tris: 800\n"
			"  scale_m: 0.8\n  priority: P1\n",
			encoding="utf-8",
		)
		dest = self.out_root / "prop" / "existing_prop.glb"
		dest.parent.mkdir(parents=True, exist_ok=True)
		dest.write_bytes(b"deja-la")
		self.dest = dest

	def test_generation_skipped_and_no_tripo_call_made(self):
		fake = _FakeRun([_tripo_json({"balance": 1000, "frozen": 0})])  # seul appel attendu : tripo balance
		with mock.patch.object(run_batch, "_run_command", fake), \
			mock.patch.object(run_batch, "run_check_asset", return_value={"ok": True, "failures": [], "warnings": []}), \
			mock.patch.object(run_batch, "run_model_preview", return_value=None):
			exit_code = run_batch.main([str(self.manifest_path)])
		self.assertEqual(exit_code, 0)
		# Un seul appel tripo (balance) — jamais `tripo make` : la génération a
		# été sautée car existing_prop.glb existait déjà.
		make_calls = [c for c in fake.calls if len(c) > 1 and c[1] == "make"]
		self.assertEqual(make_calls, [])
		self.assertTrue((self.out_root / "review.html").is_file())

	def test_force_regenerates(self):
		work_dir = run_batch.WORK_ROOT / "existing_prop"
		work_dir.mkdir(parents=True, exist_ok=True)
		(work_dir / "model.glb").write_bytes(b"nouveau-glb")
		fake = _FakeRun([
			_tripo_json({"balance": 1000, "frozen": 0}),
			_FakeProc(returncode=0, stdout="0.5.1"),
			_tripo_json({"task_id": "t1", "credits_consumed": 20,
				"output_dir": str(work_dir), "files": ["model.glb"]}),
		])
		with mock.patch.object(run_batch, "_run_command", fake), \
			mock.patch.object(run_batch, "run_check_asset", return_value={"ok": True, "failures": [], "warnings": []}), \
			mock.patch.object(run_batch, "run_model_preview", return_value=None):
			exit_code = run_batch.main([str(self.manifest_path), "--force"])
		self.assertEqual(exit_code, 0)
		make_calls = [c for c in fake.calls if len(c) > 1 and c[1] == "make"]
		self.assertEqual(len(make_calls), 1)
		self.assertEqual(self.dest.read_bytes(), b"nouveau-glb")
		self.assertTrue(run_batch.provenance_path(self.dest).is_file())

	def test_max_credits_gate_refuses_before_any_tripo_call(self):
		fake = _FakeRun([_tripo_json({"balance": 100000, "frozen": 0})])
		with mock.patch.object(run_batch, "_run_command", fake):
			exit_code = run_batch.main([str(self.manifest_path), "--force", "--max-credits", "1"])
		self.assertEqual(exit_code, 4)
		make_calls = [c for c in fake.calls if len(c) > 1 and c[1] == "make"]
		self.assertEqual(make_calls, [])


# ============================================================================
#  Ingestion d'un dossier Studio (hors manifeste)
# ============================================================================

class TestStudioDirIngestion(unittest.TestCase):
	def setUp(self):
		self._tmp = tempfile.TemporaryDirectory()
		self.addCleanup(self._tmp.cleanup)
		self.root = Path(self._tmp.name)
		self.out_root = self.root / "assets" / "incoming" / "tripo"
		self.studio_dir = self.out_root / "studio"
		self.studio_dir.mkdir(parents=True, exist_ok=True)
		self._patchers = [
			mock.patch.object(run_batch, "ROOT", self.root),
			mock.patch.object(run_batch, "OUT_ROOT", self.out_root),
			mock.patch.object(run_batch, "WORK_ROOT", self.out_root / "_work"),
		]
		for p in self._patchers:
			p.start()
			self.addCleanup(p.stop)

	def test_category_inferred_from_prefix(self):
		self.assertEqual(run_batch.infer_studio_category("weapon_shotgun"), "weapon")
		self.assertEqual(run_batch.infer_studio_category("prop_barrel"), "prop")
		self.assertEqual(run_batch.infer_studio_category("fx_muzzle_flash"), "fx")
		self.assertEqual(run_batch.infer_studio_category("random_thing"), "prop")
		self.assertEqual(run_batch.infer_studio_category("noprefixatall"), "prop")

	def test_scan_studio_dir_builds_one_info_per_glb(self):
		(self.studio_dir / "weapon_shotgun.glb").write_bytes(b"glb1")
		(self.studio_dir / "prop_barrel.glb").write_bytes(b"glb2")
		(self.studio_dir / "_bridge_log.txt").write_text("log", encoding="utf-8")
		with mock.patch.object(run_batch, "run_check_asset", return_value={"ok": True, "failures": [], "warnings": []}), \
			mock.patch.object(run_batch, "run_model_preview", return_value=None):
			infos = run_batch.scan_studio_dir(self.studio_dir, force=False)
		self.assertEqual(len(infos), 2)
		ids = {i["id"] for i in infos}
		self.assertEqual(ids, {"weapon_shotgun", "prop_barrel"})
		cats = {i["id"]: i["category"] for i in infos}
		self.assertEqual(cats["weapon_shotgun"], "weapon")
		self.assertEqual(cats["prop_barrel"], "prop")

	def test_main_ingest_only_on_directory(self):
		(self.studio_dir / "fx_spark.glb").write_bytes(b"glb")
		with mock.patch.object(run_batch, "run_check_asset", return_value={"ok": False, "failures": ["x"], "warnings": []}), \
			mock.patch.object(run_batch, "run_model_preview", return_value=None):
			exit_code = run_batch.main([str(self.studio_dir), "--ingest-only"])
		self.assertEqual(exit_code, 0)
		self.assertTrue((self.out_root / "review.html").is_file())

	def test_main_refuses_directory_without_ingest_only(self):
		exit_code = run_batch.main([str(self.studio_dir)])
		self.assertEqual(exit_code, 2)

	def test_main_empty_studio_dir_is_an_error(self):
		exit_code = run_batch.main([str(self.studio_dir), "--ingest-only"])
		self.assertEqual(exit_code, 2)


# ============================================================================
#  Page de revue (structure minimale)
# ============================================================================

class TestReviewHtml(unittest.TestCase):
	def test_build_review_html_writes_a_file_with_expected_markers(self):
		with tempfile.TemporaryDirectory() as td:
			out_path = Path(td) / "review.html"
			infos = [
				{
					"id": "padlock", "category": "prop", "route": "text", "priority": "P0",
					"prompt": "a rusty padlock", "notes": "", "glb": Path(td) / "padlock.glb",
					"check": {"ok": True, "tris": 3000, "budget_tris": 4000, "dims_m": {"largeur_x": 0.2, "profondeur_y": 0.1, "hauteur_z": 0.3}, "failures": [], "warnings": []},
					"preview_sheet": None, "provenance": {"credits_spent": 20, "date": "2026-09-24"}, "error": None,
				},
				{
					"id": "broken", "category": "weapon", "route": "text", "priority": "P0",
					"prompt": "x", "notes": "", "glb": None,
					"check": None, "preview_sheet": None, "provenance": None,
					"error": "GLB introuvable",
				},
			]
			run_batch.build_review_html(infos, out_path)
			self.assertTrue(out_path.is_file())
			html_text = out_path.read_text(encoding="utf-8")
			self.assertIn("padlock", html_text)
			self.assertIn("broken", html_text)
			self.assertIn("GLB introuvable", html_text)
			self.assertIn("PASS", html_text)
			self.assertIn("MISSING", html_text)


if __name__ == "__main__":
	unittest.main()
