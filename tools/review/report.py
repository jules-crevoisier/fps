#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""report.py

Assemble un run de la REVIEW PIPELINE (docs/REVIEW.md) en UN rapport lisible
par une IA ou un humain :
    <run_dir>/index.html    rapport complet, autonome, thème sombre
    <run_dir>/summary.json  état machine (gate global + par étape + régressions)
    <run_dir>/summary.md    résumé court, pensé pour être lu par une IA

Usage :
    python tools/review/report.py <run_dir>

Ne lève jamais d'exception fatale sans écrire quelque chose : même avec des
artefacts partiels ou absents (étapes manquantes, JSON malformé), un rapport
est produit — coloré rouge/orange là où il manque des données, jamais un
crash silencieux.
"""
from __future__ import annotations

import html
import json
import re
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image, ImageStat

# =============================================================================
#  Seuils de gate — LE dictionnaire à modifier pour resserrer/desserrer un
#  critère (voir docs/REVIEW.md « Ce que veut dire chaque gate »).
# =============================================================================
GATES = {
	"gameplay_probe_max_errors": 0,
	"bot_smoke_min_kills": 1,
	"bot_smoke_max_errors": 0,
	# LD-23 (docs/research/09_wasteland_vertical_slice.md §c.4, R17) : nombre
	# de joueurs attendu en 4v4 par défaut (`--team-size` peut légitimement
	# changer ce nombre — voir `eval_bot_smoke_spawns`, seul un AVERTISSEMENT
	# quand il est mesuré plus bas, jamais un FAIL).
	"bot_smoke_min_distinct_t0_spawns": 8,
	"net_smoke_min_rejected_shots": 2,
	"perf_fail_below_avg_fps": 30.0,
	"perf_warn_below_avg_fps": 60.0,
	"perf_regression_pct": 10.0,
	"log_scan_warn_at_non_noise_groups": 1,
	"log_scan_fail_at_non_noise_groups": 10,
	# CHK-29 (STYLE_BIBLE §5.3) pour les poses sprint/ADS — pas de catégorie
	# d'arme là, un seuil fixe unique pour chacune des deux poses.
	"fp_sprint_max_coverage_pct": 20.0,
	"fp_ads_max_coverage_pct": 28.0,
}

STATUS_RANK = {"PASS": 0, "WARN": 1, "MISSING": 1, "SKIP": 0, "FAIL": 2}
STATUS_COLOR = {"PASS": "#4caf6e", "WARN": "#d9a441", "FAIL": "#e0524d", "MISSING": "#6b7280", "SKIP": "#6b7280"}

# =============================================================================
#  CHK-28/29/30 (docs/STYLE_BIBLE.md §5.3, cadrage du viewmodel à la hanche) —
#  seuils par catégorie d'arme (WeaponConfig.Category : SIDEARM=0, SMG=1,
#  RIFLE=2, SHOTGUN=3, SNIPER=4, HEAVY=5, MELEE=6 — index = valeur d'enum
#  GDScript, dupliqué ici comme MASK_RENDER_LAYER l'est dans fp_shots.gd).
# =============================================================================
FP_CATEGORY_LABELS = {
	0: "Poing", 1: "SMG", 2: "Fusil", 3: "Pompe", 4: "Sniper", 5: "Lourde", 6: "Mêlée",
}
# Couverture d'écran (%) à la hanche, min/max, par catégorie — MELEE absent :
# aucune arme de mêlée dans WeaponDatabase.PATHS à ce jour, et le §5.3 ne fixe
# aucun seuil pour cette catégorie.
FP_CATEGORY_COVERAGE_PCT = {
	0: (7.0, 10.0),
	1: (11.0, 15.0),
	2: (13.0, 17.0),
	3: (15.0, 19.0),
	4: (15.0, 19.0),
	5: (18.0, 22.0),
}
FP_MUZZLE_HIP_X_RANGE = (0.58, 0.64)
FP_MUZZLE_HIP_Y_RANGE = (0.56, 0.64)
# Carré central 20 % × 20 %, centré sur l'écran (CHK-28).
FP_CENTER_SQUARE_FRACTION = 0.20
# Seuil "pixel non noir" sur le masque (0-255, niveaux de gris) : le masque
# attendu est binaire (0 ou 255, voir doc de classe de fp_shots.gd) mais un
# PNG peut porter un bruit de compression résiduel — une tolérance basse
# évite de compter ce bruit comme de la silhouette d'arme.
FP_MASK_NONBLACK_THRESHOLD = 8


def worse(a: str, b: str) -> str:
	return a if STATUS_RANK.get(a, 1) >= STATUS_RANK.get(b, 1) else b


def process_status_to_gate(status: str) -> str:
	return {"ok": "PASS", "warn": "WARN", "fail": "FAIL", "error": "FAIL", "missing": "MISSING"}.get(status, "WARN")


# =============================================================================
#  Chargement des artefacts (chacun renvoie None si absent/illisible — jamais
#  d'exception qui remonte).
# =============================================================================

def load_json(path: Path):
	if not path.is_file():
		return None
	try:
		# "utf-8-sig" : PowerShell (Windows PowerShell 5.1) écrit ses JSON
		# (steps.json, */result.json...) en UTF-8 AVEC BOM par défaut
		# (`ConvertTo-Json | Set-Content -Encoding UTF8`) — "utf-8" strict
		# laisserait le caractère BOM en tête et ferait échouer json.loads
		# silencieusement (fichier traité comme absent). Les JSON écrits par
		# Python/GDScript n'ont pas de BOM ; "utf-8-sig" lit les deux.
		return json.loads(path.read_text(encoding="utf-8-sig"))
	except (OSError, json.JSONDecodeError):
		return None


def load_steps(run_dir: Path) -> dict:
	steps = load_json(run_dir / "steps.json") or []
	return {s["name"]: s for s in steps if isinstance(s, dict) and "name" in s}


def parse_junit(path: Path):
	if not path.is_file():
		return None
	try:
		root = ET.parse(path).getroot()
	except ET.ParseError:
		return None
	# Les totaux (tests/failures/skipped) viennent directement de l'élément
	# racine <testsuites> — gdUnit4 les agrège déjà pour toutes les suites,
	# pas besoin de re-sommer par <testsuite> (et donc aucun risque de
	# double-compte à éviter ici).
	total = int(root.get("tests", 0) or 0)
	failures = int(root.get("failures", 0) or 0)
	skipped = int(root.get("skipped", 0) or 0)
	failing = []
	for suite in root.findall("testsuite"):
		for case in suite.findall("testcase"):
			fail_el = case.find("failure")
			err_el = case.find("error")
			if fail_el is not None or err_el is not None:
				node = fail_el if fail_el is not None else err_el
				failing.append({
					"classname": case.get("classname", suite.get("name", "?")),
					"name": case.get("name", "?"),
					"message": (node.get("message") or (node.text or "")).strip()[:500],
				})
	return {"total": total, "failures": failures, "skipped": skipped, "failing_tests": failing}


# =============================================================================
#  Évaluation par étape : combine le statut "process" (l'étape a-t-elle
#  tourné ?) avec un gate sur le CONTENU de l'artefact (le jeu est-il sain ?).
#  Renvoie (status, headline: dict[str,str], details: list[str]).
# =============================================================================

def eval_unit_tests(run_dir: Path, step: dict | None):
	proc_status = process_status_to_gate(step["status"]) if step else "MISSING"
	xml = parse_junit(run_dir / "unit_tests" / "results.xml")
	if xml is None:
		return worse(proc_status, "WARN"), {"tests": "n/a"}, ["results.xml introuvable ou illisible"], None
	status = proc_status
	if xml["failures"] > 0:
		status = worse(status, "FAIL")
	headline = {"tests": str(xml["total"]), "failures": str(xml["failures"]), "skipped": str(xml["skipped"])}
	details = [f"{t['classname']}::{t['name']} — {t['message']}" for t in xml["failing_tests"]]
	return status, headline, details, xml


def eval_gameplay_probe(run_dir: Path, step: dict | None):
	proc_status = process_status_to_gate(step["status"]) if step else "MISSING"
	data = load_json(run_dir / "gameplay_probe" / "gameplay_probe.json")
	if data is None:
		return proc_status, {}, (["gameplay_probe.json introuvable"] if proc_status != "MISSING" else []), None
	checks = data.get("checks", [])
	errors = int(data.get("errors", 0) or 0)
	status = proc_status
	if errors > GATES["gameplay_probe_max_errors"] or any(not c.get("ok", True) for c in checks):
		status = worse(status, "FAIL")
	headline = {"checks": str(len(checks)), "errors": str(errors)}
	details = [f"{c.get('name')} — {c.get('detail', '')}" for c in checks if not c.get("ok", True)]
	return status, headline, details, data


def eval_net_smoke(run_dir: Path, step: dict | None):
	proc_status = process_status_to_gate(step["status"]) if step else "MISSING"
	data = load_json(run_dir / "net_smoke" / "result.json")
	if data is None:
		return proc_status, {}, [], None
	status = proc_status
	if not data.get("ok"):
		status = worse(status, "FAIL")
	if (data.get("rejected_shots") or 0) < GATES["net_smoke_min_rejected_shots"]:
		status = worse(status, "WARN")
	headline = {
		"ok": str(data.get("ok")),
		"damage_taken": str(data.get("damage_taken")),
		"rejected_shots": str(data.get("rejected_shots")),
	}
	return status, headline, [], data


def eval_bot_smoke(run_dir: Path, step: dict | None):
	proc_status = process_status_to_gate(step["status"]) if step else "MISSING"
	data = load_json(run_dir / "bot_smoke" / "result.json")
	if data is None:
		return proc_status, {}, [], None
	status = proc_status
	kills = data.get("kills")
	errors = data.get("errors")
	if kills is None or kills < GATES["bot_smoke_min_kills"]:
		status = worse(status, "FAIL")
	if errors is not None and errors > GATES["bot_smoke_max_errors"]:
		status = worse(status, "FAIL")
	headline = {"kills": str(kills), "errors": str(errors), "rejected_shots": str(data.get("rejected_shots"))}
	return status, headline, [], data


# LD-23 : `spawns_t0_distinct=<n> spawns_t0_total=<n>` (tools/bot_smoke.gd,
# `_count_distinct_t0_spawns`) n'est PAS dans `bot_smoke/result.json` — sa
# capture par `tools/review/run_review.ps1` (hors périmètre de cette tâche)
# ne les extrait pas de la ligne BOT_SMOKE. Lu ici directement dans le log
# brut que `run_review.ps1` écrit déjà à ce chemin fixe pour CHAQUE run.
_BOT_SMOKE_SPAWN_RE = re.compile(r"spawns_t0_distinct=(\d+)\s+spawns_t0_total=(\d+)")


def eval_bot_smoke_spawns(run_dir: Path, step: dict | None):
	"""LD-23 (docs/research/09_wasteland_vertical_slice.md §c.4, R17) :
	anti-empilement des spawns d'UNE MÊME équipe apparue à la même seconde —
	positions de spawn INITIALES (le premier `Telemetry.EVENT_SPAWN` de
	chaque joueur, "à t0") agrégées par `tools/bot_smoke.gd`. `distinct <
	total` : au moins deux joueurs ont partagé LE MÊME point à t0 (régression
	structurelle d'empilement) -> FAIL. `total` sous le plancher attendu
	(8, 4v4 par défaut) reste un simple AVERTISSEMENT : `--team-size` change
	légitimement ce nombre, ce n'est pas en soi un signe d'empilement."""
	proc_status = process_status_to_gate(step["status"]) if step else "MISSING"
	log_path = run_dir / "logs" / "bot_smoke.log"
	if not log_path.is_file():
		return worse(proc_status, "WARN"), {}, ["logs/bot_smoke.log introuvable"], None
	text = log_path.read_text(encoding="utf-8", errors="replace")
	m = _BOT_SMOKE_SPAWN_RE.search(text)
	if not m:
		return (
			worse(proc_status, "WARN"), {},
			["champs spawns_t0_distinct/spawns_t0_total absents du log bot_smoke (build antérieure à LD-23 ?)"],
			None,
		)
	distinct, total = int(m.group(1)), int(m.group(2))
	status = proc_status
	details = []
	if total == 0:
		status = worse(status, "WARN")
		details.append("aucun événement spawn agrégé (télémétrie vide, ou match_id introuvable)")
	elif distinct < total:
		status = worse(status, "FAIL")
		details.append(f"{total - distinct} spawn(s) partagent le même point à t0 (empilement) sur {total} joueurs")
	if 0 < total < GATES["bot_smoke_min_distinct_t0_spawns"]:
		details.append(
			f"seulement {total} joueur(s) mesuré(s) à t0 (attendu {GATES['bot_smoke_min_distinct_t0_spawns']} en 4v4 par défaut)"
		)
	headline = {"distinct": str(distinct), "total": str(total)}
	return status, headline, details, {"distinct": distinct, "total": total}


def eval_generic_shots(run_dir: Path, step: dict | None, artifact_dir: str, json_name: str | None = None):
	"""Étapes de capture d'écran (map_shots/ui_shots/viewmodel_fp/character_shots) :
	le gate est simplement "le process a tourné, et l'artefact JSON dit done=true"."""
	proc_status = process_status_to_gate(step["status"]) if step else "MISSING"
	data = None
	if json_name:
		data = load_json(run_dir / artifact_dir / json_name)
	details = []
	if data is not None:
		# Cherche récursivement un "done"/"ok" false quelque part pour signaler.
		def all_done(d):
			if isinstance(d, dict):
				if "done" in d and not d["done"]:
					return False
				if "ok" in d and not d["ok"]:
					return False
				return all(all_done(v) for v in d.values() if isinstance(v, (dict, list)))
			if isinstance(d, list):
				return all(all_done(v) for v in d)
			return True
		if not all_done(data):
			proc_status = worse(proc_status, "WARN")
			details.append("un ou plusieurs éléments marqués non-ok dans l'artefact JSON")
	return proc_status, {}, details, data


def _load_mask_stats(path: Path) -> dict | None:
	"""Statistiques pixel d'un masque viewmodel (tools/fp_shots.gd, doc de
	classe) : silhouette blanche pleine sur fond noir. `None` si le fichier est
	absent ou illisible — jamais d'exception qui remonte (cf. en-tête du
	module). Le seuil "pixel non noir" (`FP_MASK_NONBLACK_THRESHOLD`) donne un
	masque binaire fiable même pour un matériau d'arme presque noir."""
	if not path.is_file():
		return None
	try:
		img = Image.open(path).convert("L")
	except Exception:
		return None
	w, h = img.size
	if w <= 0 or h <= 0:
		return None
	binary = img.point(lambda v: 255 if v > FP_MASK_NONBLACK_THRESHOLD else 0)
	total_px = w * h
	nonblack_px = int(round(ImageStat.Stat(binary).sum[0] / 255.0))
	half = FP_CENTER_SQUARE_FRACTION / 2.0
	box = (
		int(round((0.5 - half) * w)), int(round((0.5 - half) * h)),
		int(round((0.5 + half) * w)), int(round((0.5 + half) * h)),
	)
	center = binary.crop(box)
	center_nonblack_px = int(round(ImageStat.Stat(center).sum[0] / 255.0))
	return {
		"width": w, "height": h,
		"coverage_pct": 100.0 * nonblack_px / total_px,
		"center_nonblack_px": center_nonblack_px,
	}


def eval_fp_shot_weapon(entry: dict, fp_dir: Path) -> dict:
	"""Évalue CHK-28 (zone de visée libre), CHK-29 (couverture par catégorie)
	et CHK-30 (position du canon) — docs/STYLE_BIBLE.md §5.3 — pour UNE arme,
	pose à la hanche, depuis son entrée `fp_shots.json` + son masque PNG.
	CHK-30 est classé "I" (informatif) au §5.3 : il ne descend jamais à FAIL,
	seulement PASS/WARN. Une arme sans modèle livré (`FP_SHOT_SKIP` dans
	fp_shots.gd, `model_found: false`) est classée "MISSING" (« manquante »)."""
	name = entry.get("name", "?")
	category = entry.get("category")
	result: dict = {
		"name": name,
		"weapon_id": entry.get("weapon_id"),
		"weapon_name": entry.get("weapon_name") or name,
		"category": category,
		"category_label": FP_CATEGORY_LABELS.get(category, "?"),
	}
	if not entry.get("model_found", False):
		result["status"] = "MISSING"
		result["chk28"] = "MISSING"
		result["chk29"] = "MISSING"
		result["chk30"] = "MISSING"
		result["note"] = "modèle introuvable (FP_SHOT_SKIP)"
		return result

	notes = []
	mask = _load_mask_stats(fp_dir / f"{name}_mask.png")
	if mask is None:
		result["chk28"] = "WARN"
		result["chk29"] = "WARN"
		notes.append("masque introuvable ou illisible")
	else:
		result["coverage_pct"] = mask["coverage_pct"]
		result["chk28"] = "PASS" if mask["center_nonblack_px"] == 0 else "FAIL"
		lo_hi = FP_CATEGORY_COVERAGE_PCT.get(category)
		if lo_hi is None:
			result["chk29"] = "WARN"
			notes.append("catégorie sans seuil de couverture connu")
		else:
			lo, hi = lo_hi
			result["chk29"] = "PASS" if lo <= mask["coverage_pct"] <= hi else "FAIL"

	muzzle = entry.get("muzzle_screen")
	if not muzzle or len(muzzle) != 2:
		result["chk30"] = "WARN"
		notes.append("position du canon absente de fp_shots.json")
	else:
		mx, my = muzzle
		result["muzzle_x"], result["muzzle_y"] = mx, my
		in_range = (
			FP_MUZZLE_HIP_X_RANGE[0] <= mx <= FP_MUZZLE_HIP_X_RANGE[1]
			and FP_MUZZLE_HIP_Y_RANGE[0] <= my <= FP_MUZZLE_HIP_Y_RANGE[1]
		)
		result["chk30"] = "PASS" if in_range else "WARN"

	if notes:
		result["note"] = " ; ".join(notes)
	result["status"] = worse(worse(result["chk28"], result["chk29"]), result["chk30"])
	return result


def eval_fp_shot_pose(entry: dict | None, fp_dir: Path, max_coverage_pct: float, label: str) -> dict:
	"""CHK-29 seulement (§5.3) pour une pose sprint/ADS : pas de catégorie
	d'arme, un plafond de couverture fixe par pose, et CHK-28/30 ne s'y
	appliquent pas (contraints uniquement « à la hanche »)."""
	if not entry:
		return {"label": label, "status": "MISSING"}
	name = entry.get("name", label)
	mask = _load_mask_stats(fp_dir / f"{name}_mask.png")
	if mask is None:
		return {"label": label, "name": name, "status": "WARN", "note": "masque introuvable ou illisible"}
	status = "PASS" if mask["coverage_pct"] <= max_coverage_pct else "FAIL"
	return {"label": label, "name": name, "status": status, "coverage_pct": mask["coverage_pct"]}


def eval_fp_shots_checks(run_dir: Path, step: dict | None):
	"""CHK-28/29/30 (docs/STYLE_BIBLE.md §5.3) : lit `fp_shots.json` et les
	masques viewmodel produits par tools/fp_shots.gd (dossier
	`viewmodel_fp/fp/`, voir Step-ViewmodelFpShots dans run_review.ps1) et note
	chaque arme, plus sprint/ADS pour la seule couverture (CHK-29)."""
	proc_status = process_status_to_gate(step["status"]) if step else "MISSING"
	fp_dir = run_dir / "viewmodel_fp" / "fp"
	data = load_json(fp_dir / "fp_shots.json")
	if data is None:
		return proc_status, {}, (["fp_shots.json introuvable (viewmodel_fp/fp)"] if proc_status != "MISSING" else []), None

	weapons = [eval_fp_shot_weapon(w, fp_dir) for w in data.get("weapons", [])]
	sprint = eval_fp_shot_pose(data.get("sprint"), fp_dir, GATES["fp_sprint_max_coverage_pct"], "Sprint")
	ads = eval_fp_shot_pose(data.get("ads"), fp_dir, GATES["fp_ads_max_coverage_pct"], "ADS")

	status = proc_status
	for w in weapons:
		status = worse(status, w["status"])
	status = worse(worse(status, sprint["status"]), ads["status"])

	missing = [w for w in weapons if w["status"] == "MISSING"]
	failing = [w for w in weapons if w["status"] == "FAIL"]
	headline = {"armes": str(len(weapons)), "manquantes": str(len(missing)), "en_echec": str(len(failing))}

	details = []
	for w in weapons:
		if w["status"] == "MISSING":
			details.append(f"{w['weapon_name']} — manquante ({w.get('note', '')})")
		elif w["status"] != "PASS":
			extra = f" — {w['note']}" if w.get("note") else ""
			details.append(
				f"{w['weapon_name']} — CHK-28={w['chk28']} CHK-29={w['chk29']} CHK-30={w['chk30']}{extra}"
			)
	for pose in (sprint, ads):
		if pose["status"] != "PASS":
			cov = f" ({pose['coverage_pct']:.1f}%)" if "coverage_pct" in pose else ""
			extra = f" — {pose['note']}" if pose.get("note") else ""
			details.append(f"{pose['label']} — CHK-29={pose['status']}{cov}{extra}")

	return status, headline, details, {"weapons": weapons, "sprint": sprint, "ads": ads}


def eval_perf_bench(run_dir: Path, step: dict | None, prev_summary: dict | None):
	proc_status = process_status_to_gate(step["status"]) if step else "MISSING"
	data = load_json(run_dir / "perf_bench" / "perf.json")
	if data is None:
		return proc_status, {}, [], None
	status = proc_status
	details = []
	maps = data.get("maps", [])
	prev_maps = {}
	if prev_summary and "perf_bench" in prev_summary:
		prev_maps = {m["id"]: m for m in prev_summary["perf_bench"].get("maps", [])}
	for m in maps:
		fps = m.get("avg_fps", 0) or 0
		if fps < GATES["perf_fail_below_avg_fps"]:
			status = worse(status, "FAIL")
			details.append(f"{m['id']} : {fps:.1f} fps (< {GATES['perf_fail_below_avg_fps']} fps plancher)")
		elif fps < GATES["perf_warn_below_avg_fps"]:
			status = worse(status, "WARN")
		prev = prev_maps.get(m["id"])
		if prev and prev.get("avg_fps"):
			drop_pct = 100.0 * (prev["avg_fps"] - fps) / prev["avg_fps"]
			if drop_pct > GATES["perf_regression_pct"]:
				status = worse(status, "WARN")
				details.append(f"{m['id']} : régression fps {prev['avg_fps']:.1f} -> {fps:.1f} (-{drop_pct:.0f}%)")
	if data.get("errors"):
		status = worse(status, "WARN")
		details.extend(f"map {e.get('id')} : {e.get('reason')}" for e in data["errors"])
	headline = {"maps": str(len(maps))}
	return status, headline, details, data


def eval_log_scan(run_dir: Path, step: dict | None):
	proc_status = process_status_to_gate(step["status"]) if step else "MISSING"
	data = load_json(run_dir / "log_scan.json")
	if data is None:
		return proc_status, {}, [], None
	status = proc_status
	non_noise_groups = len([g for g in data.get("groups", []) if not g["noise"]])
	# Seuils exprimés en nombre de groupes DISTINCTS (genres de problèmes), pas
	# en occurrences brutes — un avertissement anodin qui se répète 50 fois
	# (ex. un bake de navmesh par map) ne doit pas, à lui seul, faire FAIL.
	if non_noise_groups >= GATES["log_scan_fail_at_non_noise_groups"]:
		status = worse(status, "FAIL")
	elif non_noise_groups >= GATES["log_scan_warn_at_non_noise_groups"]:
		status = worse(status, "WARN")
	headline = {"groupes_non_bruit": str(non_noise_groups),
		"occurrences_non_bruit": str(data.get("non_noise_count", 0)), "occurrences_bruit": str(data.get("noise_count", 0))}
	return status, headline, [], data


# =============================================================================
#  Comparaison au run précédent
# =============================================================================

def find_previous_run(run_dir: Path):
	review_root = run_dir.parent
	if not review_root.is_dir():
		return None
	siblings = sorted(p.name for p in review_root.iterdir() if p.is_dir() and p.name != run_dir.name)
	older = [s for s in siblings if s < run_dir.name]
	if not older:
		return None
	prev_dir = review_root / older[-1]
	prev_summary = load_json(prev_dir / "summary.json")
	return prev_dir, prev_summary


def compute_regressions(current: dict, prev_summary: dict | None) -> list[str]:
	if not prev_summary:
		return []
	regressions = []
	cur_ut = current.get("unit_tests", {})
	prev_ut = prev_summary.get("unit_tests", {})
	cur_failing = {f"{t['classname']}::{t['name']}" for t in cur_ut.get("failing_tests", [])}
	prev_failing = {f"{t['classname']}::{t['name']}" for t in prev_ut.get("failing_tests", [])}
	for name in sorted(cur_failing - prev_failing):
		regressions.append(f"test nouvellement en échec : {name}")

	cur_ls = current.get("log_scan", {})
	prev_ls = prev_summary.get("log_scan", {})
	if cur_ls.get("non_noise_count", 0) > prev_ls.get("non_noise_count", 0):
		regressions.append(f"erreurs de log en hausse : {prev_ls.get('non_noise_count', 0)} -> {cur_ls.get('non_noise_count', 0)}")

	cur_bs = current.get("bot_smoke", {})
	prev_bs = prev_summary.get("bot_smoke", {})
	if cur_bs.get("kills") is not None and prev_bs.get("kills") is not None and cur_bs["kills"] < prev_bs["kills"]:
		regressions.append(f"bot_smoke kills en baisse : {prev_bs['kills']} -> {cur_bs['kills']}")

	# LD-23 : un nombre de positions DISTINCTES à t0 en baisse, à `total`
	# (nombre de joueurs) égal ou plus grand, signale un empilement nouveau.
	cur_sp = current.get("bot_smoke_spawns", {})
	prev_sp = prev_summary.get("bot_smoke_spawns", {})
	if (
		cur_sp.get("distinct") is not None and prev_sp.get("distinct") is not None
		and cur_sp["distinct"] < prev_sp["distinct"]
		and (cur_sp.get("total") or 0) >= (prev_sp.get("total") or 0)
	):
		regressions.append(
			f"spawns distincts à t0 en baisse : {prev_sp['distinct']} -> {cur_sp['distinct']} (sur {cur_sp.get('total')} joueurs)"
		)

	cur_perf = {m["id"]: m for m in current.get("perf_bench", {}).get("maps", [])}
	prev_perf = {m["id"]: m for m in prev_summary.get("perf_bench", {}).get("maps", [])}
	for map_id, cm in cur_perf.items():
		pm = prev_perf.get(map_id)
		if pm and pm.get("avg_fps") and cm.get("avg_fps") is not None:
			drop_pct = 100.0 * (pm["avg_fps"] - cm["avg_fps"]) / pm["avg_fps"]
			if drop_pct > GATES["perf_regression_pct"]:
				regressions.append(f"fps en baisse sur {map_id} : {pm['avg_fps']:.1f} -> {cm['avg_fps']:.1f} (-{drop_pct:.0f}%)")
	return regressions


# =============================================================================
#  Feuilles de contact d'images
# =============================================================================

def collect_images(run_dir: Path) -> dict[str, list[str]]:
	groups: dict[str, list[str]] = {}
	for png in sorted(run_dir.rglob("*.png")):
		rel = png.relative_to(run_dir)
		group = str(rel.parent).replace("\\", "/") if rel.parent != Path(".") else "(racine)"
		groups.setdefault(group, []).append(str(rel).replace("\\", "/"))
	return groups


# =============================================================================
#  Assemblage
# =============================================================================

# "report" est délibérément absent : ce script écrit lui-même ce fichier, il
# ne peut donc jamais connaître SON PROPRE statut au moment de l'évaluer —
# l'afficher donnerait toujours "MISSING", ce qui serait trompeur (le
# rapport qu'on est en train de lire prouve déjà que cette étape a réussi).
STEP_ORDER = ["import", "unit_tests", "gameplay_probe", "net_smoke", "bot_smoke", "map_shots", "ui_shots",
	"viewmodel_fp_shots", "character_shots", "perf_bench", "log_scan"]

STEP_TITLES = {
	"import": "Import du projet",
	"unit_tests": "Tests unitaires (gdUnit4)",
	"gameplay_probe": "Sonde de gameplay",
	"net_smoke": "Fumée réseau (2 process)",
	"bot_smoke": "Fumée de bots (match TDM)",
	"map_shots": "Captures des maps",
	"ui_shots": "Captures de l'UI",
	"viewmodel_fp_shots": "Captures ViewModel / première personne",
	"character_shots": "Captures des personnages",
	"perf_bench": "Benchmark de performance",
	"log_scan": "Analyse des logs",
	"report": "Génération du rapport",
	# Pas une étape process à part entière (dérivé de l'artefact de
	# viewmodel_fp_shots) — même traitement que "report" : hors STEP_ORDER,
	# rendu à part (voir render_fp_shots_checks_table).
	"fp_shots_checks": "Cadrage du viewmodel (CHK-28/29/30)",
	# Même traitement : dérivé du log brut de l'étape "bot_smoke", pas un
	# process à part (voir eval_bot_smoke_spawns), hors STEP_ORDER.
	"bot_smoke_spawns": "Spawns de bots — anti-empilement (LD-23)",
}


def build_summary(run_dir: Path) -> dict:
	steps = load_steps(run_dir)
	prev = find_previous_run(run_dir)
	prev_dir, prev_summary = prev if prev else (None, None)

	current: dict = {"generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"), "run_dir": str(run_dir)}
	sections = {}

	ut_status, ut_head, ut_details, ut_raw = eval_unit_tests(run_dir, steps.get("unit_tests"))
	sections["unit_tests"] = {"status": ut_status, "headline": ut_head, "details": ut_details}
	current["unit_tests"] = {"failing_tests": (ut_raw or {}).get("failing_tests", []), "total": (ut_raw or {}).get("total")}

	gp_status, gp_head, gp_details, gp_raw = eval_gameplay_probe(run_dir, steps.get("gameplay_probe"))
	sections["gameplay_probe"] = {"status": gp_status, "headline": gp_head, "details": gp_details}

	ns_status, ns_head, ns_details, ns_raw = eval_net_smoke(run_dir, steps.get("net_smoke"))
	sections["net_smoke"] = {"status": ns_status, "headline": ns_head, "details": ns_details}

	bs_status, bs_head, bs_details, bs_raw = eval_bot_smoke(run_dir, steps.get("bot_smoke"))
	sections["bot_smoke"] = {"status": bs_status, "headline": bs_head, "details": bs_details}
	current["bot_smoke"] = {"kills": (bs_raw or {}).get("kills")}

	sp_status, sp_head, sp_details, sp_raw = eval_bot_smoke_spawns(run_dir, steps.get("bot_smoke"))
	sections["bot_smoke_spawns"] = {"status": sp_status, "headline": sp_head, "details": sp_details}
	current["bot_smoke_spawns"] = {"distinct": (sp_raw or {}).get("distinct"), "total": (sp_raw or {}).get("total")}

	ms_status, ms_head, ms_details, _ = eval_generic_shots(run_dir, steps.get("map_shots"), "map_shots", "result.json")
	sections["map_shots"] = {"status": ms_status, "headline": ms_head, "details": ms_details}

	ui_status, ui_head, ui_details, _ = eval_generic_shots(run_dir, steps.get("ui_shots"), "ui_shots", "ui_shots.json")
	sections["ui_shots"] = {"status": ui_status, "headline": ui_head, "details": ui_details}

	vm_status, vm_head, vm_details, _ = eval_generic_shots(run_dir, steps.get("viewmodel_fp_shots"), "viewmodel_fp", "result.json")
	sections["viewmodel_fp_shots"] = {"status": vm_status, "headline": vm_head, "details": vm_details}

	fp_status, fp_head, fp_details, _ = eval_fp_shots_checks(run_dir, steps.get("viewmodel_fp_shots"))
	sections["fp_shots_checks"] = {"status": fp_status, "headline": fp_head, "details": fp_details}

	ch_status, ch_head, ch_details, _ = eval_generic_shots(run_dir, steps.get("character_shots"), "character_shots", "result.json")
	sections["character_shots"] = {"status": ch_status, "headline": ch_head, "details": ch_details}

	pf_status, pf_head, pf_details, pf_raw = eval_perf_bench(run_dir, steps.get("perf_bench"), prev_summary)
	sections["perf_bench"] = {"status": pf_status, "headline": pf_head, "details": pf_details}
	current["perf_bench"] = {"maps": (pf_raw or {}).get("maps", [])}

	ls_status, ls_head, ls_details, ls_raw = eval_log_scan(run_dir, steps.get("log_scan"))
	sections["log_scan"] = {"status": ls_status, "headline": ls_head, "details": ls_details}
	current["log_scan"] = {"non_noise_count": (ls_raw or {}).get("non_noise_count", 0)}

	rp_step = steps.get("report")
	sections["report"] = {"status": process_status_to_gate(rp_step["status"]) if rp_step else "MISSING", "headline": {}, "details": []}

	im_step = steps.get("import")
	sections["import"] = {"status": process_status_to_gate(im_step["status"]) if im_step else "MISSING", "headline": {}, "details": []}

	overall = "PASS"
	for name, s in sections.items():
		if name == "report":
			continue  # le statut de report ne peut pas se connaître lui-même avant d'exister
		overall = worse(overall, s["status"])

	regressions = compute_regressions(current, prev_summary)

	summary = {
		"generated_at": current["generated_at"],
		"run_dir": str(run_dir),
		"previous_run_dir": str(prev_dir) if prev_dir else None,
		"overall_status": overall,
		"sections": sections,
		"regressions": regressions,
		**current,
	}
	return summary


# =============================================================================
#  Rendu HTML
# =============================================================================

_CSS = """
:root { color-scheme: dark; }
body { background:#12151a; color:#e6e8eb; font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif; margin:0; padding:24px 32px 64px; line-height:1.5; }
h1 { font-size:1.6rem; margin-bottom:4px; }
h2 { font-size:1.15rem; border-bottom:1px solid #2a2f3a; padding-bottom:6px; margin-top:36px; }
.meta { color:#9aa2af; font-size:0.85rem; margin-bottom:20px; }
.gate-row { display:flex; flex-wrap:wrap; gap:10px; margin:18px 0 28px; }
.pill { display:inline-flex; align-items:center; gap:6px; padding:6px 12px; border-radius:999px; font-size:0.82rem; font-weight:600; background:#1c2028; border:1px solid #2a2f3a; }
.dot { width:9px; height:9px; border-radius:50%; display:inline-block; }
.overall { font-size:1.3rem; font-weight:700; padding:10px 18px; border-radius:8px; display:inline-block; margin-bottom:10px; }
.section { background:#171a20; border:1px solid #262b34; border-radius:10px; padding:16px 20px; margin-bottom:16px; }
.headline { display:flex; gap:18px; flex-wrap:wrap; margin:8px 0; font-size:0.9rem; color:#c7cbd3; }
.headline b { color:#fff; }
ul.details { margin:8px 0 0; padding-left:20px; font-size:0.85rem; color:#d3d7de; }
table { border-collapse:collapse; width:100%; margin-top:10px; font-size:0.85rem; }
th, td { text-align:left; padding:5px 8px; border-bottom:1px solid #262b34; }
th { color:#9aa2af; font-weight:600; }
.regressions { background:#241618; border:1px solid #5a2b2b; border-radius:10px; padding:14px 20px; margin-bottom:20px; }
.regressions li { color:#f3a9a6; }
.noregress { color:#7fb894; }
.contact-sheet { display:flex; flex-wrap:wrap; gap:10px; margin-top:10px; }
.thumb { width:150px; }
.thumb img { width:100%; border-radius:6px; border:1px solid #2a2f3a; cursor:zoom-in; display:block; }
.thumb span { display:block; font-size:0.7rem; color:#8a919d; margin-top:3px; word-break:break-all; }
.lightbox { display:none; position:fixed; inset:0; background:rgba(5,6,8,0.92); z-index:50; align-items:center; justify-content:center; cursor:zoom-out; }
.lightbox.open { display:flex; }
.lightbox img { max-width:92vw; max-height:92vh; border-radius:8px; }
.log-group { border-left:3px solid #3a4150; padding:6px 12px; margin-bottom:8px; font-size:0.82rem; }
.log-group.noise { border-left-color:#4a4f58; opacity:0.65; }
.log-group.err { border-left-color:#e0524d; }
.log-group pre { white-space:pre-wrap; background:#0e1014; padding:8px; border-radius:6px; margin:6px 0 0; font-size:0.78rem; color:#c7cbd3; }
.badge { font-size:0.7rem; padding:1px 7px; border-radius:5px; background:#2a2f3a; color:#c7cbd3; margin-left:6px; }
code { background:#0e1014; padding:1px 5px; border-radius:4px; }
a { color:#7db8f2; }
"""

_JS = """
function openLightbox(src) {
  var lb = document.getElementById('lightbox');
  document.getElementById('lightbox-img').src = src;
  lb.classList.add('open');
}
document.addEventListener('DOMContentLoaded', function() {
  document.getElementById('lightbox').addEventListener('click', function() { this.classList.remove('open'); });
});
"""


def esc(v) -> str:
	return html.escape(str(v), quote=True)


def render_pill(label: str, status: str) -> str:
	return f'<span class="pill"><span class="dot" style="background:{STATUS_COLOR[status]}"></span>{esc(label)} — {status}</span>'


def render_section(step_name: str, section: dict) -> str:
	status = section["status"]
	head = section.get("headline", {})
	details = section.get("details", [])
	headline_html = "".join(f"<div><b>{esc(v)}</b> {esc(k)}</div>" for k, v in head.items())
	details_html = ""
	if details:
		items = "".join(f"<li>{esc(d)}</li>" for d in details[:50])
		more = f"<li><i>… {len(details) - 50} de plus</i></li>" if len(details) > 50 else ""
		details_html = f'<ul class="details">{items}{more}</ul>'
	return f"""
	<div class="section">
		<h2>{render_pill(STEP_TITLES.get(step_name, step_name), status)}</h2>
		<div class="headline">{headline_html}</div>
		{details_html}
	</div>"""


def render_log_scan_groups(run_dir: Path) -> str:
	data = load_json(run_dir / "log_scan.json")
	if not data:
		return "<p><i>log_scan.json indisponible.</i></p>"
	groups = data.get("groups", [])
	if not groups:
		return "<p class='noregress'>Aucune ligne ERROR/WARNING/SCRIPT ERROR/RPC/Lambda détectée dans les logs.</p>"
	out = []
	for g in groups[:80]:
		cls = "log-group noise" if g["noise"] else ("log-group err" if g["category"] in ("error", "script_error") else "log-group")
		badge = f'<span class="badge">bruit connu</span>' if g["noise"] else ""
		first = g["first_occurrence"]
		out.append(f"""
		<div class="{cls}">
			<b>[{esc(g['category'])}]</b> ×{g['count']} {badge}<br>
			{esc(g['message'])}
			<div style="font-size:0.75rem;color:#8a919d;margin-top:4px;">
				première occurrence : {esc(first['file'])}:{first['line']}
				{' — ' + esc(g['noise_reason']) if g.get('noise_reason') else ''}
			</div>
		</div>""")
	if len(groups) > 80:
		out.append(f"<p><i>… {len(groups) - 80} groupes de plus (voir log_scan.json).</i></p>")
	return "".join(out)


def render_contact_sheets(run_dir: Path) -> str:
	groups = collect_images(run_dir)
	if not groups:
		return "<p><i>Aucune capture d'écran trouvée sous ce run (probablement -Quick, ou étapes fenêtrées manquantes/échouées).</i></p>"
	out = []
	for group, files in sorted(groups.items()):
		thumbs = "".join(
			f'<div class="thumb"><img src="{esc(f)}" loading="lazy" onclick="openLightbox(\'{esc(f)}\')">'
			f'<span>{esc(Path(f).name)}</span></div>'
			for f in files
		)
		out.append(f"<h3 style='margin-top:18px;font-size:0.95rem;color:#c7cbd3;'>{esc(group)} ({len(files)})</h3><div class='contact-sheet'>{thumbs}</div>")
	return "".join(out)


def render_fp_shots_checks_table(run_dir: Path) -> str:
	"""Tableau détaillé CHK-28 (zone de visée libre) / CHK-29 (couverture) /
	CHK-30 (position du canon), une ligne par arme (docs/STYLE_BIBLE.md §5.3),
	plus sprint/ADS (CHK-29 seulement). Une arme sans modèle livré (voir
	`eval_fp_shot_weapon`) occupe une ligne « manquante » à part."""
	fp_dir = run_dir / "viewmodel_fp" / "fp"
	data = load_json(fp_dir / "fp_shots.json")
	if data is None:
		return "<p><i>fp_shots.json indisponible (viewmodel_fp/fp) — étape non exécutée, ou fenêtre indisponible.</i></p>"

	rows = []
	for w in [eval_fp_shot_weapon(w, fp_dir) for w in data.get("weapons", [])]:
		if w["status"] == "MISSING":
			rows.append(
				f"<tr><td>{esc(w['weapon_name'])}</td><td>{esc(w['category_label'])}</td>"
				f"<td colspan='3' style='color:{STATUS_COLOR['MISSING']}'>manquante — {esc(w.get('note', ''))}</td></tr>"
			)
			continue
		cov = w.get("coverage_pct")
		cov_txt = f"{cov:.1f} %" if cov is not None else "n/a"
		mx, my = w.get("muzzle_x"), w.get("muzzle_y")
		muzzle_txt = f"x={mx:.2f} y={my:.2f}" if mx is not None and my is not None else "n/a"
		rows.append(
			f"<tr><td>{esc(w['weapon_name'])}</td><td>{esc(w['category_label'])}</td>"
			f"<td style='color:{STATUS_COLOR[w['chk28']]}'>{esc(w['chk28'])}</td>"
			f"<td style='color:{STATUS_COLOR[w['chk29']]}'>{esc(w['chk29'])} ({esc(cov_txt)})</td>"
			f"<td style='color:{STATUS_COLOR[w['chk30']]}'>{esc(w['chk30'])} ({esc(muzzle_txt)})</td></tr>"
		)

	sprint = eval_fp_shot_pose(data.get("sprint"), fp_dir, GATES["fp_sprint_max_coverage_pct"], "Sprint")
	ads = eval_fp_shot_pose(data.get("ads"), fp_dir, GATES["fp_ads_max_coverage_pct"], "ADS")
	for pose in (sprint, ads):
		if pose["status"] == "MISSING":
			rows.append(f"<tr><td>{esc(pose['label'])}</td><td>—</td><td colspan='3' style='color:{STATUS_COLOR['MISSING']}'>manquante</td></tr>")
			continue
		cov = pose.get("coverage_pct")
		cov_txt = f"{cov:.1f} %" if cov is not None else (pose.get("note") or "n/a")
		rows.append(
			f"<tr><td>{esc(pose['label'])}</td><td>—</td><td>—</td>"
			f"<td style='color:{STATUS_COLOR[pose['status']]}'>{esc(pose['status'])} ({esc(cov_txt)})</td><td>—</td></tr>"
		)

	return f"""
	<table>
		<tr><th>Arme / pose</th><th>Catégorie</th><th>CHK-28 (zone libre)</th><th>CHK-29 (couverture)</th><th>CHK-30 (canon)</th></tr>
		{''.join(rows)}
	</table>"""


def _video_mem_cell(m: dict) -> str:
	video_mb = m.get("video_mem_mb", -1)
	return "n/a" if video_mb is None or video_mb < 0 else f"{video_mb:.0f}"


def render_perf_table(run_dir: Path) -> str:
	data = load_json(run_dir / "perf_bench" / "perf.json")
	if not data or not data.get("maps"):
		return ""
	rows = "".join(
		f"<tr><td>{esc(m['id'])}</td><td>{m.get('avg_fps', 0):.1f}</td><td>{m.get('low_1pct_fps', 0):.1f}</td>"
		f"<td>{m.get('p99_frame_ms', 0):.2f}</td><td>{m.get('draw_calls_avg', 0):.0f}</td>"
		f"<td>{m.get('primitives_avg', 0):.0f}</td>"
		f"<td>{_video_mem_cell(m)}</td></tr>"
		for m in data["maps"]
	)
	return f"""
	<table>
		<tr><th>Map</th><th>FPS moyen</th><th>1% low</th><th>p99 frame (ms)</th><th>Draw calls</th><th>Primitives</th><th>Vid. mem (Mo)</th></tr>
		{rows}
	</table>"""


def render_steps_table(run_dir: Path, steps: dict) -> str:
	rows = []
	for name in STEP_ORDER:
		s = steps.get(name)
		if not s:
			rows.append(f"<tr><td>{esc(name)}</td><td colspan='4'><i>non exécutée</i></td></tr>")
			continue
		rows.append(
			f"<tr><td>{esc(name)}</td><td>{esc(s['status'])}</td><td>{esc(s.get('exit_code'))}</td>"
			f"<td>{esc(s.get('duration_sec'))}s</td><td>{esc(s.get('note') or '')}</td></tr>"
		)
	return f"""
	<table>
		<tr><th>Étape</th><th>Statut process</th><th>Code retour</th><th>Durée</th><th>Note</th></tr>
		{''.join(rows)}
	</table>"""


def render_html(run_dir: Path, summary: dict, steps: dict) -> str:
	overall = summary["overall_status"]
	pills = "".join(render_pill(STEP_TITLES.get(name, name), s["status"]) for name, s in summary["sections"].items())
	regressions = summary["regressions"]
	if regressions:
		regressions_html = f"""<div class="regressions"><b>Régressions vs run précédent</b> ({esc(summary.get('previous_run_dir') or '?')})
			<ul>{''.join(f'<li>{esc(r)}</li>' for r in regressions)}</ul></div>"""
	else:
		prev_note = "aucun run précédent trouvé" if not summary.get("previous_run_dir") else "aucune régression détectée"
		regressions_html = f'<p class="noregress">✓ {esc(prev_note)}.</p>'

	sections_html = "".join(render_section(name, summary["sections"][name]) for name in STEP_ORDER if name in summary["sections"])
	bot_smoke_spawns_section = summary["sections"].get("bot_smoke_spawns")
	bot_smoke_spawns_html = render_section("bot_smoke_spawns", bot_smoke_spawns_section) if bot_smoke_spawns_section else ""

	return f"""<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>Review — {esc(run_dir.name)}</title>
<style>{_CSS}</style>
</head>
<body>
	<h1>Rapport de review — {esc(run_dir.name)}</h1>
	<div class="meta">Généré le {esc(summary['generated_at'])} · dossier : <code>{esc(str(run_dir))}</code></div>

	<div class="overall" style="background:{STATUS_COLOR[overall]}22;color:{STATUS_COLOR[overall]};border:1px solid {STATUS_COLOR[overall]};">
		État global : {overall}
	</div>
	<div class="gate-row">{pills}</div>

	{regressions_html}

	<h2>Étapes (durée / code retour)</h2>
	{render_steps_table(run_dir, steps)}

	{sections_html}

	{bot_smoke_spawns_html}

	<h2>Cadrage du viewmodel — CHK-28/29/30 (STYLE_BIBLE §5.3)</h2>
	{render_fp_shots_checks_table(run_dir)}

	<h2>Benchmark de performance — détail par map</h2>
	{render_perf_table(run_dir)}

	<h2>Logs — groupes d'erreurs / avertissements</h2>
	{render_log_scan_groups(run_dir)}

	<h2>Captures d'écran</h2>
	{render_contact_sheets(run_dir)}

	<div id="lightbox" class="lightbox"><img id="lightbox-img" src=""></div>
	<script>{_JS}</script>
</body>
</html>"""


def render_summary_md(summary: dict) -> str:
	lines = [f"# Review — {Path(summary['run_dir']).name}", "", f"État global : **{summary['overall_status']}**", ""]
	for name in STEP_ORDER:
		s = summary["sections"].get(name)
		if not s:
			continue
		head = ", ".join(f"{k}={v}" for k, v in s.get("headline", {}).items())
		lines.append(f"- **{STEP_TITLES.get(name, name)}** : {s['status']}" + (f" ({head})" if head else ""))
	fp_section = summary["sections"].get("fp_shots_checks")
	if fp_section:
		head = ", ".join(f"{k}={v}" for k, v in fp_section.get("headline", {}).items())
		lines.append(f"- **{STEP_TITLES['fp_shots_checks']}** : {fp_section['status']}" + (f" ({head})" if head else ""))
		lines.extend(f"  - {d}" for d in fp_section.get("details", [])[:50])
	bot_smoke_spawns_section = summary["sections"].get("bot_smoke_spawns")
	if bot_smoke_spawns_section:
		head = ", ".join(f"{k}={v}" for k, v in bot_smoke_spawns_section.get("headline", {}).items())
		lines.append(
			f"- **{STEP_TITLES['bot_smoke_spawns']}** : {bot_smoke_spawns_section['status']}"
			+ (f" ({head})" if head else "")
		)
		lines.extend(f"  - {d}" for d in bot_smoke_spawns_section.get("details", [])[:50])
	lines.append("")
	if summary["regressions"]:
		lines.append("## Régressions")
		lines.extend(f"- {r}" for r in summary["regressions"])
	else:
		lines.append("Aucune régression détectée par rapport au run précédent.")
	return "\n".join(lines) + "\n"


# =============================================================================
#  Entrée
# =============================================================================

def main(argv: list[str]) -> int:
	if len(argv) != 2:
		print("usage : python report.py <run_dir>", file=sys.stderr)
		return 2
	run_dir = Path(argv[1])
	run_dir.mkdir(parents=True, exist_ok=True)
	try:
		steps = load_steps(run_dir)
		summary = build_summary(run_dir)
		html_out = render_html(run_dir, summary, steps)
		(run_dir / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
		(run_dir / "summary.md").write_text(render_summary_md(summary), encoding="utf-8")
		(run_dir / "index.html").write_text(html_out, encoding="utf-8")
		print(f"REPORT_DONE overall={summary['overall_status']} -> {run_dir / 'index.html'}")
		return 0
	except Exception as exc:  # noqa: BLE001 — dernier filet : un rapport doit toujours exister.
		fallback = (
			f"<!DOCTYPE html><html><body style='background:#12151a;color:#e0524d;font-family:monospace;padding:32px'>"
			f"<h1>report.py a échoué</h1><pre>{html.escape(repr(exc))}</pre></body></html>"
		)
		(run_dir / "index.html").write_text(fallback, encoding="utf-8")
		print(f"REPORT_FAIL {exc!r}", file=sys.stderr)
		return 1


if __name__ == "__main__":
	raise SystemExit(main(sys.argv))
