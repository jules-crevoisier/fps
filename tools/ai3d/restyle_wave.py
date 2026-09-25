#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/ai3d/restyle_wave.py
Restyle en lot d'une vague Tripo (voir docs/assets/ASSET_PLAN.md §2, chaîne
« manifeste -> ai_raw -> ai_restyle -> check_asset/turntable/model_preview »).
Contrat A3D-13 : lit un manifeste (`tools/ai3d/manifests/waveN.yaml`), et pour
chaque entrée dont le .glb brut existe dans `assets/incoming/tripo/studio/` :

BLOQUANT CONNU (vague 1, 2026-09-24 — voir le rendu de tâche A3D-13, hors de la
liste de fichiers de cette tâche, donc PAS corrigé ici) : sur les 24 assets de
`tools/ai3d/manifests/wave1.yaml`, `tools/blender/ai_restyle.py::ensure_watertight`
échoue DUR (`RuntimeError`, aucune taille de voxel acceptée en 8 tentatives) sur
la majorité des maillages Tripo bruts de cette vague — reproduit en appelant
`ai_restyle.py` SEUL, sans ce script (ex. `wpn_pistolet`, `wpn_magnum`, `gp_bomb`,
7 repères sur 7). Même quand le remesh réussit, `ensure_watertight` ne garde que
le kind de palette DOMINANT quand le maillage porte plusieurs matériaux
(limitation documentée de l'opérateur Remesh Voxel, voir son commentaire) : sur
`wpn_ravage`/`wpn_rafale`/`wpn_semeuse`/`wl_oil_derrick`, 5 à 8 kinds sur 8 sont
jetés, amputant 18 à 95 % de la dimension de référence (voir `verify_scale_m`,
qui échoue alors sur le contrôle bbox = scale_m ± 2 %, et le contrôle
`watertight_fix.dropped_kinds` ci-dessous, qui échoue même quand bbox tient par
chance). `cs_container_20` échoue séparément (budget de triangles dépassé après
6 passes de Decimate — maillage trop dense pour son budget de 2 500 tris).
Aucun de ces trois défauts n'est dans le périmètre de cette tâche (assets/
incoming/tripo/restyled/, tools/ai3d/parts/, ce fichier) : ils vivent dans
`tools/blender/ai_restyle.py`, jamais modifié ici. Ce script les DÉTECTE et les
liste (jamais ne les masque ni ne les contourne par un budget/une classe plus
permissifs) — voir `process_entry`/`verify_scale_m` et le rendu de tâche pour le
détail par asset.

  1. **mise à l'échelle** (ce que `tools/blender/ai_restyle.py` ne fait PAS —
     il ne fait que bake un scale/rotation déjà présent, jamais mettre à
     l'échelle une dimension cible) : les .glb `studio/` sortent de Tripo
     « normalisés à 1 m » (plus grande dimension brute = 1 unité), jamais à la
     bonne échelle réelle. Ce script importe l'asset brut, bake ses transforms,
     mesure sa bbox LOCALE (repère Z-up natif de Blender, le même que tout
     `tools/blender/lib/toonkit.py`), choisit l'axe de référence :
       - armes et objets tenus (`held: true` dans ASSET_META ci-dessous) :
         l'axe le PLUS LONG de la bbox brute — jamais un axe fixe (X ou Y) :
         un sondage sur les 10 armes (voir rapport de tâche) montre que Tripo
         ne canonicalise PAS l'orientation de façon constante (8 armes sur 10
         sortent avec le canon sur X, 2 sur Y) ; comme l'entrée est déjà
         normalisée à 1 m sur sa plus grande dimension, « l'axe le plus long »
         EST par construction l'axe du canon pour un objet plus long que haut
         ou large (vrai pour les 10 armes et gp_bomb, vérifié sur planche
         turntable, voir docs/tasks/ — jamais supposé) ;
       - tout le reste : l'axe Z (hauteur), même convention que
         `toonkit.set_origin_bottom` et que `check_asset.py::dims_m.hauteur_z`.
     … puis met à l'échelle uniformément pour que cet axe vaille exactement
     `scale_m` (manifeste), bake à nouveau, exporte un .glb intermédiaire
     (`<out>.prescaled.glb`, supprimé après coup) — TOUT ceci dans le MÊME
     process Blender que l'étape 2 (voir `_WORKER_SCRIPT`), pour ne payer
     qu'un seul lancement Blender par asset.
  2. **restyle** : appelle `tools/blender/ai_restyle.py::restyle()` (importé
     tel quel, jamais modifié — hors de la liste de fichiers de cette tâche)
     sur le .glb prescaled, avec le budget de triangles et l'axe de biseau de
     `ASSET_META`, et pour les 10 armes le fichier `tools/ai3d/parts/<id>.json`
     (pièces mobiles + marqueurs Muzzle/Foregrip, §3.5) s'il existe.
  3. **vérifications G3** : `tools/blender/check_asset.py` (budget, COLOR_0,
     CHK-16) PUIS un contrôle propre à ce script, absent de check_asset.py :
     bbox = scale_m ± 2 % sur l'axe de référence (voir `verify_scale_m`).
  4. **revue en jeu** : `tools/review/model_preview.gd` (même convention que
     `tools/ai3d/run_batch.py::run_model_preview`, réutilisé tel quel) — la
     « planche PNG par asset » exigée par le contrat.
  5. assemble `assets/incoming/tripo/restyled/index.html` : verdict G3
     (automatique, ci-dessus) et G2 (jugement visuel « forme conforme au
     concept, pas de membrure fondue, pas de socle parasite », ASSET_PLAN §2 —
     lu depuis `assets/incoming/tripo/restyled/g2_verdicts.json`, rempli à la
     main par l'agent qui a réellement regardé chaque planche ; un id absent
     de ce fichier affiche « à revoir », jamais un PASS par défaut).

Usage :
    python tools/ai3d/restyle_wave.py tools/ai3d/manifests/wave1.yaml
        [--only id1,id2] [--force] [--skip-turntable] [--views 8] [--size 512]

Idempotent (reprise) : un asset dont la sortie est déjà plus récente que son
entrée studio, son `tools/ai3d/parts/<id>.json` (si présent) et ce script
lui-même est sauté sans relancer Blender, sauf `--force`. `--only` ne fait
tourner Blender/check_asset/model_preview que sur les ids listés, mais
`assets/incoming/tripo/restyled/index.html` récapitule TOUJOURS le manifeste
entier : le dernier `info` connu de chaque id (y compris ceux non touchés par
ce `--only`) est relu depuis `assets/incoming/tripo/restyled/_wave_state.json`
(écrit après chaque exécution) et fusionné avec les résultats frais avant de
reconstruire la page — un `--only` ne tronque donc jamais la revue.

Ne modifie et ne crée que sous `assets/incoming/tripo/restyled/`,
`tools/ai3d/parts/` et ce fichier — jamais `tools/blender/ai_restyle.py` ni
`tools/ai3d/run_batch.py` (importés, jamais réécrits).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
# Réutilisation délibérée de tools/ai3d/run_batch.py (jamais modifié) : même
# schéma de manifeste (ManifestEntry/load_manifest), mêmes conventions de
# chemin et de reprise pour check_asset/model_preview (run_check_asset,
# run_model_preview, check_json_path, preview_sheet_path), même point de
# passage subprocess (_run_command, gère les .cmd Windows). Réinventer ces
# fonctions ici ferait diverger les deux pipelines sans raison.
import yaml

from run_batch import (  # noqa: E402
	BLENDER_EXE,
	GODOT_EXE,
	ManifestEntry,
	ManifestError,
	_build_entry,
	_run_command,
	_validate_item,
	check_json_path,
	preview_sheet_path,
	run_check_asset,
	run_model_preview,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
STUDIO_DIR = REPO_ROOT / "assets" / "incoming" / "tripo" / "studio"
OUT_DIR = REPO_ROOT / "assets" / "incoming" / "tripo" / "restyled"
PARTS_DIR = REPO_ROOT / "tools" / "ai3d" / "parts"
AI_RESTYLE_SCRIPT = REPO_ROOT / "tools" / "blender" / "ai_restyle.py"
TOONKIT_LIB = REPO_ROOT / "tools" / "blender" / "lib" / "toonkit.py"
THIS_SCRIPT = Path(__file__).resolve()
G2_VERDICTS_PATH = OUT_DIR / "g2_verdicts.json"

SCALE_TOLERANCE_RATIO = 0.02  # ± 2 % (contrat A3D-13)

# ============================================================================
#  Métadonnées par asset — pas dans le manifeste (schéma verrouillé à 13 clés,
#  voir tools/ai3d/manifests/wave1.yaml en-tête) : `bevel_class` (classe
#  toonkit.BEVEL_CLASSES, docs/STYLE_BIBLE.md §6.6) et `held` (True = axe de
#  référence = le plus long de la bbox brute, longueur canon/objet tenu ;
#  False = axe Z, hauteur — voir le commentaire de module ci-dessus).
#
#  `bevel_class` : docs/assets/ASSET_PLAN.md §4 donne des classes de biseau
#  (Arme FP 3 mm, Repère 6-8 cm, Skin>=3m 6 cm/2 seg, Prop moyen 4 cm
#  conteneur/2,5 cm caisse, Objet de jeu 5 mm) qui ne correspondent pas
#  TOUTES à une entrée de toonkit.BEVEL_CLASSES (vocabulaire fermé §6.6) : ce
#  plan note lui-même (§4, note *) que « objet de jeu » n'a pas d'entrée
#  dédiée dans la bible. gp_bomb/gp_borne (5 mm visé) reçoivent donc la classe
#  EXISTANTE la plus proche, weapon_fp (3 mm) — écart connu, à trancher par le
#  lead (voir le rendu de cette tâche), jamais une classe inventée ici.
ASSET_META = {
	# armes (10) — classe weapon_fp (§6.6), axe = le plus long (canon)
	"wpn_pistolet": {"bevel_class": "weapon_fp", "held": True},
	"wpn_magnum": {"bevel_class": "weapon_fp", "held": True},
	"wpn_rafale": {"bevel_class": "weapon_fp", "held": True},
	"wpn_marqueur": {"bevel_class": "weapon_fp", "held": True},
	"wpn_ravage": {"bevel_class": "weapon_fp", "held": True},
	"wpn_fracas": {"bevel_class": "weapon_fp", "held": True},
	"wpn_faucheur": {"bevel_class": "weapon_fp", "held": True},
	"wpn_eclair": {"bevel_class": "weapon_fp", "held": True},
	"wpn_semeuse": {"bevel_class": "weapon_fp", "held": True},
	"wpn_percuteur": {"bevel_class": "weapon_fp", "held": True},
	# repères Wasteland/Cargo (classe landmark, §4 "Repère" 6-8 cm) — axe Z
	"wl_fuel_billboard": {"bevel_class": "landmark", "held": False},
	"wl_canopy_station": {"bevel_class": "landmark", "held": False},
	"wl_water_tower": {"bevel_class": "landmark", "held": False},
	"wl_oil_derrick": {"bevel_class": "landmark", "held": False},
	"wl_crane_lattice": {"bevel_class": "landmark", "held": False},
	"wl_gas_billboard": {"bevel_class": "landmark", "held": False},
	"cs_ship_mast": {"bevel_class": "landmark", "held": False},
	"cs_deck_crane": {"bevel_class": "landmark", "held": False},
	# "Skin >= 3 m" (§4) -> architecture (6 cm, 2 segments, table identique)
	"wl_tank_horizontal": {"bevel_class": "architecture", "held": False},
	# "Prop moyen 1-3 m" (§4) : conteneur -> prop_container (4 cm),
	# canots/davits -> prop_crate (2,5 cm, pas un conteneur)
	"cs_container_40": {"bevel_class": "prop_container", "held": False},
	"cs_container_20": {"bevel_class": "prop_container", "held": False},
	"cs_lifeboat_davits": {"bevel_class": "prop_crate", "held": False},
	# objets de jeu — gp_bomb porté (longueur), gp_borne planté (hauteur du mât)
	"gp_bomb": {"bevel_class": "weapon_fp", "held": True},
	"gp_borne": {"bevel_class": "weapon_fp", "held": False},
}


# ============================================================================
#  Chemins conventionnels
# ============================================================================

def studio_glb_path(asset_id: str) -> Path:
	return STUDIO_DIR / f"{asset_id}.glb"


def restyled_glb_path(asset_id: str) -> Path:
	return OUT_DIR / f"{asset_id}.glb"


def restyle_report_path(glb_path: Path) -> Path:
	return glb_path.parent / f"{glb_path.stem}.ai_restyle.json"


def parts_json_path(asset_id: str) -> Optional[Path]:
	path = PARTS_DIR / f"{asset_id}.json"
	return path if path.is_file() else None


def load_wave_manifest(path: Path) -> list:
	"""Charge un manifeste `waveN.yaml` (tools/ai3d/manifests/) — format
	RÉEL de ces fichiers : un mapping YAML avec des clés de vague
	(`wave`/`credit_cap`/`credit_estimate`/`negative_prompt`/...) et la liste
	des assets sous `assets:` (voir l'en-tête de wave1.yaml, "SCHÉMA — chaque
	entrée de `assets` a EXACTEMENT ces 13 clés"). PAS directement le format
	que `tools/ai3d/run_batch.py::load_manifest` attend (une liste YAML nue
	en racine) : les deux scripts partagent le même schéma PAR ENTRÉE, donc
	on réutilise `run_batch._validate_item`/`_build_entry` (mêmes
	REQUIRED_KEYS/OPTIONAL_KEYS, jamais réimplémentés ici) sur `raw["assets"]`
	plutôt que sur `raw` directement."""
	path = Path(path)
	raw = yaml.safe_load(path.read_text(encoding="utf-8"))
	if not isinstance(raw, dict) or not isinstance(raw.get("assets"), list):
		raise ManifestError(
			f"{path}: attendu un mapping YAML avec une clé 'assets' (liste) — "
			f"reçu {type(raw).__name__}")
	items = raw["assets"]
	errors = []
	seen_ids: set = set()
	for i, item in enumerate(items):
		errors.extend(_validate_item(item, i, seen_ids))
	if errors:
		raise ManifestError("manifeste invalide (" + str(path) + ") :\n" + "\n".join(f"  - {e}" for e in errors))
	return [_build_entry(item) for item in items]


# ============================================================================
#  Worker Blender — un seul lancement par asset (prescale + ai_restyle.restyle)
#  Contenu FIXE (pas de gabarit à substituer : tous les paramètres passent en
#  argv, comme tools/blender/ai_restyle.py lui-même) — écrit dans un fichier
#  temporaire à chaque exécution, jamais versionné (voir `_write_worker_script`).
# ============================================================================

_WORKER_SCRIPT = r'''
## Worker Blender genere par tools/ai3d/restyle_wave.py (A3D-13) — PAS un
## fichier du depot : ecrit dans un dossier temporaire a chaque lancement.
## Etape 1 (prescale, absente de ai_restyle.py) : bake les transforms de
## l'asset BRUT, choisit l'axe de reference (--held : le plus long de la
## bbox ; sinon Z), met a l'echelle pour que cet axe vaille --scale-m, bake,
## exporte un .glb intermediaire. Etape 2 : appelle telle quelle
## tools/blender/ai_restyle.py::restyle() sur ce .glb intermediaire (jamais
## modifiee), qui fait tout le reste (palette, etancheite, decimation,
## pieces mobiles, biseau/COLOR_0, export, turntable).
import argparse
import os
import sys

import bpy
from mathutils import Vector

REPO_ROOT = r"__REPO_ROOT__"
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "blender", "lib"))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "blender"))
import toonkit  # noqa: E402
import ai_restyle  # noqa: E402


def parse_args():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	p = argparse.ArgumentParser()
	p.add_argument("--in", dest="in_path", required=True)
	p.add_argument("--out", dest="out_path", required=True)
	p.add_argument("--family", required=True)
	p.add_argument("--budget", type=int, required=True)
	p.add_argument("--bevel-class", dest="bevel_class", required=True)
	p.add_argument("--scale-m", dest="scale_m", type=float, required=True)
	p.add_argument("--held", action="store_true")
	p.add_argument("--parts", dest="parts_path", default=None)
	p.add_argument("--views", type=int, default=8)
	p.add_argument("--size", type=int, default=512)
	p.add_argument("--skip-turntable", action="store_true")
	return p.parse_args(argv)


def main():
	args = parse_args()
	toonkit.reset_scene()
	mesh_objs = ai_restyle.import_asset(args.in_path)
	if not mesh_objs:
		print("WORKER_FAIL aucun mesh dans " + args.in_path)
		sys.exit(1)
	obj = toonkit.join(mesh_objs) if len(mesh_objs) > 1 else mesh_objs[0]
	toonkit.apply_transforms(obj)

	corners = [Vector(c) for c in obj.bound_box]
	mins = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
	maxs = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
	extents = maxs - mins
	if args.held:
		vals = {"x": extents.x, "y": extents.y, "z": extents.z}
		axis = max(vals, key=vals.get)
		axis_extent = vals[axis]
	else:
		axis = "z"
		axis_extent = extents.z
	if axis_extent <= 1e-6:
		print("WORKER_FAIL extent nul sur l'axe " + axis + " pour " + args.in_path)
		sys.exit(1)
	scale_factor = args.scale_m / axis_extent
	obj.scale = (scale_factor, scale_factor, scale_factor)
	toonkit.apply_transforms(obj)
	print("WORKER_PRESCALE axis=%s scale_factor=%.6f extents_raw=(%.4f,%.4f,%.4f)" % (
		axis, scale_factor, extents.x, extents.y, extents.z))

	prescaled_path = args.out_path + ".prescaled.glb"
	toonkit.export_glb(prescaled_path, obj, write_report=False)

	parts_spec = ai_restyle.load_parts_spec(args.parts_path) if args.parts_path else None
	try:
		ai_restyle.restyle(
			prescaled_path, args.out_path, args.budget, args.family,
			turntable_views=args.views, turntable_size=args.size,
			skip_turntable=args.skip_turntable,
			bevel_class=args.bevel_class, parts_spec=parts_spec,
		)
	finally:
		if os.path.isfile(prescaled_path):
			os.remove(prescaled_path)

	print("WORKER_OK")


if __name__ == "__main__":
	main()
'''


def _write_worker_script() -> Path:
	content = _WORKER_SCRIPT.replace("__REPO_ROOT__", str(REPO_ROOT))
	fd, path = tempfile.mkstemp(prefix="restyle_wave_worker_", suffix=".py")
	with os.fdopen(fd, "w", encoding="utf-8") as f:
		f.write(content)
	return Path(path)


# ============================================================================
#  Exécution d'un asset
# ============================================================================

def _newer_than_all(output: Path, inputs: list) -> bool:
	if not output.is_file():
		return False
	out_mtime = output.stat().st_mtime
	return all(p.stat().st_mtime <= out_mtime for p in inputs if p.is_file())


# ----------------------------------------------------------------------------
#  Cause précise d'un échec worker — corrige le retour QA de A3D-13 (« les
#  échecs sont listés avec leur cause » : un `ai_restyle (code 1) — voir le
#  journal` générique ne satisfait pas ce critère). `_run_command` fait
#  tourner `blender -b --python-exit-code 1 -P <worker>` : toute exception
#  Python non interceptée dans le worker (y compris celles, non catchées ici
#  à dessein, de `ai_restyle.restyle()` — jamais modifié, hors périmètre
#  A3D-13) termine Blender avec ce code et un traceback standard sur
#  stdout/stderr. On relit ce traceback DÉJÀ écrit par Blender (on ne modifie
#  ni ne réexécute rien côté ai_restyle.py) pour en extraire la dernière
#  exception non interceptée et, quand la frame juste au-dessus vient d'un
#  fichier de tools/blender/, la fonction d'origine — ex.
#  « RuntimeError: ai_restyle: le remesh voxel n'a pas reussi a rendre le
#  maillage etanche (ai_restyle.py:1024 in ensure_watertight) » plutôt que
#  « code 1 ».
_PY_TRACE_FRAME_RE = re.compile(r'^\s*File "([^"]+)", line (\d+), in (\S+)\s*$')
_PY_EXC_LINE_RE = re.compile(r'^([A-Za-z_][A-Za-z0-9_.]*(?:Error|Exception|Warning)):\s*(.+)$')

# Signatures des deux défauts connus de tools/blender/ai_restyle.py identifiés
# pendant A3D-13 (voir docstring de module) — hors périmètre de cette tâche
# (relèvent de A3D-12/A3D-07, tasks/backlog.yaml). Rattache la cause précise
# au défaut connu quand elle correspond, jamais une classification inventée :
# tout message qui ne matche ni l'une ni l'autre reste affiché tel quel, sans
# note ajoutée.
_KNOWN_AI_RESTYLE_BUGS = (
	("le remesh voxel n'a pas reussi a rendre le maillage etanche",
		"défaut connu hors périmètre A3D-13 : tools/blender/ai_restyle.py::"
		"ensure_watertight, relève de A3D-12/A3D-07 (jamais corrigé ici)"),
	("budget depasse apres decimation",
		"défaut connu hors périmètre A3D-13 : tools/blender/ai_restyle.py::"
		"restyle (décimation insuffisante pour ce budget), relève de "
		"A3D-12/A3D-07 (jamais corrigé ici)"),
)


def _known_bug_note(message: str) -> Optional[str]:
	for needle, note in _KNOWN_AI_RESTYLE_BUGS:
		if needle in message:
			return note
	return None


def _extract_python_error(log: str) -> Optional[str]:
	"""Retrouve la dernière exception Python non interceptée dans `log`
	(stdout+stderr concaténés du worker Blender) et l'attribue à la frame de
	traceback qui la précède immédiatement quand celle-ci vient d'un fichier
	`tools/blender/*.py`. Renvoie None si aucun traceback standard n'est
	trouvé (crash Blender sans exception Python, ex. segfault — le code de
	sortie générique reste alors le seul signal disponible)."""
	last_frame = None
	last_error = None
	for raw in (log or "").splitlines():
		frame_m = _PY_TRACE_FRAME_RE.match(raw)
		if frame_m:
			last_frame = frame_m
			continue
		exc_m = _PY_EXC_LINE_RE.match(raw.strip())
		if exc_m:
			exc_type, message = exc_m.groups()
			origin = ""
			if last_frame is not None and "tools" in last_frame.group(1).replace("\\", "/").split("/"):
				origin = f" ({Path(last_frame.group(1)).name}:{last_frame.group(2)} in {last_frame.group(3)})"
			last_error = f"{exc_type}: {message}{origin}"
	return last_error


def run_worker(entry: ManifestEntry, meta: dict, in_path: Path, out_path: Path,
		views: int, size: int, skip_turntable: bool, force: bool) -> dict:
	parts_path = parts_json_path(entry.id)
	report_path = restyle_report_path(out_path)
	inputs = [in_path, THIS_SCRIPT, AI_RESTYLE_SCRIPT, TOONKIT_LIB]
	if parts_path is not None:
		inputs.append(parts_path)
	if not force and _newer_than_all(out_path, inputs) and report_path.is_file():
		try:
			return {"ok": True, "skipped": True, "report": json.loads(report_path.read_text(encoding="utf-8")),
				"log": "(sauté — sortie déjà à jour, --force pour relancer)"}
		except json.JSONDecodeError:
			pass  # rapport corrompu : on relance pour de vrai

	worker_script = _write_worker_script()
	argv = [
		BLENDER_EXE, "-b", "--factory-startup", "--python-exit-code", "1",
		"-P", str(worker_script), "--",
		"--in", str(in_path), "--out", str(out_path),
		"--family", ("weapons" if meta["held"] and entry.id.startswith("wpn_") else "props"),
		"--budget", str(entry.budget_tris), "--bevel-class", meta["bevel_class"],
		"--scale-m", str(entry.scale_m), "--views", str(views), "--size", str(size),
	]
	if meta["held"]:
		argv.append("--held")
	if parts_path is not None:
		argv += ["--parts", str(parts_path)]
	if skip_turntable:
		argv.append("--skip-turntable")

	try:
		proc = _run_command(argv)
	finally:
		try:
			worker_script.unlink()
		except OSError:
			pass

	log = (proc.stdout or "") + "\n" + (proc.stderr or "")
	ok = proc.returncode == 0 and "WORKER_OK" in (proc.stdout or "")
	result = {"ok": ok, "skipped": False, "log": log[-6000:], "report": None}
	if ok and report_path.is_file():
		try:
			result["report"] = json.loads(report_path.read_text(encoding="utf-8"))
		except json.JSONDecodeError:
			pass
	if not ok:
		py_error = _extract_python_error(log)
		if py_error is not None:
			known = _known_bug_note(py_error)
			result["error"] = f"ai_restyle : {py_error}" + (f" — {known}" if known else "")
		else:
			result["error"] = f"ai_restyle (code {proc.returncode}) — voir le journal (aucun traceback Python reconnu)"
	return result


# ============================================================================
#  Vérification bbox = scale_m ± 2 % — absente de check_asset.py (voir
#  docstring de module). Relit les dims_m du check_asset (mêmes axes que le
#  worker : Z toujours "hauteur", X/Y les deux autres) plutôt que de
#  réimporter le .glb une troisième fois.
# ============================================================================

def verify_scale_m(entry: ManifestEntry, meta: dict, check_report: dict, worker_report: dict) -> Optional[str]:
	dims = (check_report or {}).get("dims_m")
	if not dims:
		return "bbox scale_m : aucune dimension mesurée (check_asset.py en échec)"
	if meta["held"]:
		axis = (worker_report or {}).get("_prescale_axis") or "x"  # repli : voir _prescale_axis
		measured = {"x": dims["largeur_x"], "y": dims["profondeur_y"], "z": dims["hauteur_z"]}.get(axis)
	else:
		axis = "z"
		measured = dims["hauteur_z"]
	if measured is None:
		return f"bbox scale_m : axe {axis!r} introuvable dans dims_m"
	tolerance = entry.scale_m * SCALE_TOLERANCE_RATIO
	if abs(measured - entry.scale_m) > tolerance:
		return (f"bbox = {measured:.4f} m sur l'axe {axis} (attendu {entry.scale_m:.4f} m "
			f"± {tolerance:.4f} m, {SCALE_TOLERANCE_RATIO*100:.0f} %)")
	return None


def _extract_prescale_axis(log: str) -> Optional[str]:
	for line in (log or "").splitlines():
		line = line.strip()
		if line.startswith("WORKER_PRESCALE axis="):
			return line.split("axis=", 1)[1].split(" ", 1)[0]
	return None


# ============================================================================
#  Un asset, bout en bout
# ============================================================================

def process_entry(entry: ManifestEntry, force: bool, skip_turntable: bool, views: int, size: int) -> dict:
	meta = ASSET_META.get(entry.id)
	info = {
		"id": entry.id, "category": entry.category, "priority": entry.priority,
		"scale_m": entry.scale_m, "budget_tris": entry.budget_tris, "notes": entry.notes,
		"failures": [], "warnings": [], "worker": None, "check": None, "preview_sheet": None,
		"turntable_sheet": None, "glb": None, "meta": meta,
	}
	if meta is None:
		info["failures"].append(
			f"aucune entrée ASSET_META pour {entry.id!r} dans tools/ai3d/restyle_wave.py "
			"(bevel_class/held inconnus) — asset sauté")
		return info

	in_path = studio_glb_path(entry.id)
	if not in_path.is_file():
		info["failures"].append(f".glb brut introuvable : {in_path}")
		return info

	out_path = restyled_glb_path(entry.id)
	worker = run_worker(entry, meta, in_path, out_path, views, size, skip_turntable, force)
	info["worker"] = worker
	if not worker["ok"]:
		info["failures"].append(worker.get("error", "ai_restyle : échec inconnu"))
		return info

	info["glb"] = out_path
	axis = _extract_prescale_axis(worker.get("log", "")) or ("x" if meta["held"] else "z")
	worker["_prescale_axis"] = axis

	report = worker.get("report") or {}
	turntable = report.get("turntable_contact_sheet")
	info["turntable_sheet"] = Path(turntable) if turntable else None
	if report.get("parts") is not None:
		info["parts_separated"] = report["parts"]
	if report.get("markers") is not None:
		info["markers"] = report["markers"]

	check = run_check_asset(out_path, entry.budget_tris, force)
	info["check"] = check
	if not check.get("ok", False):
		info["failures"].extend(check.get("failures", []))
	info["warnings"].extend(check.get("warnings", []))

	scale_issue = verify_scale_m(entry, meta, check, worker)
	if scale_issue:
		info["failures"].append(scale_issue)

	# ai_restyle.py::ensure_watertight, quand un remesh Voxel est nécessaire
	# ET que le maillage porte plusieurs kinds de palette, ne garde QUE le
	# kind dominant (limitation DOCUMENTÉE de l'opérateur Remesh Voxel,
	# tools/blender/ai_restyle.py autour de la ligne 710) — un compromis tracé
	# dans le rapport, jamais une perte silencieuse côté ai_restyle.py, mais
	# qui peut amputer une part importante de la silhouette (ex. wpn_ravage
	# vague 1 : 7 kinds sur 8 jetés, ~34 % des faces classifiées). check_asset.py
	# ne le détecte PAS (aucun bord ouvert ni pièce flottante APRÈS coup) : ce
	# script le traite donc comme un échec G3 à lui, jamais un simple avertissement.
	watertight_fix = report.get("watertight_fix") or {}
	if watertight_fix.get("dropped_kinds"):
		info["failures"].append(
			f"ai_restyle a jeté {len(watertight_fix['dropped_kinds'])} kind(s) de palette lors du remesh "
			f"étanche ({', '.join(watertight_fix['dropped_kinds'])}) — collapsed_to={watertight_fix.get('collapsed_to')!r}, "
			"silhouette probablement amputée (à confirmer en revue G2)")
	elif watertight_fix.get("remeshed"):
		info["warnings"].append("ai_restyle a dû reremesher l'étanchéité (un seul kind sur le maillage — rien jeté)")

	try:
		info["preview_sheet"] = run_model_preview(out_path, force)
	except Exception as exc:  # noqa: BLE001 — un aperçu manquant ne doit jamais arrêter la revue
		info["warnings"].append(f"model_preview.gd : {exc}")

	if meta["held"] and entry.id.startswith("wpn_"):
		parts = info.get("parts_separated") or []
		markers = info.get("markers") or []
		if not parts:
			info["failures"].append("aucune pièce mobile séparée (tools/ai3d/parts/<id>.json manquant ou vide)")
		if "Muzzle" not in markers:
			info["failures"].append("marqueur Muzzle absent")

	return info


# ============================================================================
#  index.html — cartes par asset, verdict G3 automatique + G2 (voir
#  g2_verdicts.json, rempli par l'agent qui a regardé chaque planche).
# ============================================================================

def _load_g2_verdicts() -> dict:
	if not G2_VERDICTS_PATH.is_file():
		return {}
	try:
		return json.loads(G2_VERDICTS_PATH.read_text(encoding="utf-8"))
	except json.JSONDecodeError:
		return {}


_STATUS_COLOR = {"PASS": "#4caf6e", "FAIL": "#e0524d", "PENDING": "#c9a227", "MISSING": "#6b7280"}

_CSS = """
:root { color-scheme: dark; }
body { background:#12151a; color:#e6e8eb; font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;
	margin:0; padding:24px 16px 64px; line-height:1.5; }
h1 { font-size:1.5rem; margin-bottom:4px; }
.meta { color:#9aa2af; font-size:0.85rem; margin-bottom:20px; }
.stats { display:flex; flex-wrap:wrap; gap:10px; margin-bottom:24px; }
.pill { display:inline-flex; align-items:center; gap:6px; padding:6px 12px; border-radius:999px;
	font-size:0.82rem; font-weight:600; background:#1c2028; border:1px solid #2a2f3a; }
.dot { width:9px; height:9px; border-radius:50%; display:inline-block; }
.grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(320px,1fr)); gap:16px; }
.card { background:#171a20; border:1px solid #262b34; border-radius:10px; padding:14px 16px; }
.card h2 { font-size:1rem; margin:0 0 6px; display:flex; align-items:center; gap:8px; flex-wrap:wrap; }
.badge { font-size:0.68rem; padding:1px 7px; border-radius:5px; background:#2a2f3a; color:#c7cbd3; }
.verdicts { display:flex; gap:6px; margin:4px 0 8px; }
.verdict { font-size:0.72rem; padding:2px 8px; border-radius:5px; font-weight:600; }
.thumb { width:100%; border-radius:6px; border:1px solid #2a2f3a; cursor:zoom-in; display:block; margin:8px 0; }
.thumb-missing { width:100%; aspect-ratio:16/9; border-radius:6px; border:1px dashed #3a4150;
	display:flex; align-items:center; justify-content:center; color:#6b7280; font-size:0.8rem; margin:8px 0; }
.row { font-size:0.82rem; color:#c7cbd3; margin:2px 0; }
.row b { color:#fff; }
ul.issues { margin:6px 0 0; padding-left:18px; font-size:0.78rem; }
.issues.fail { color:#f3a9a6; }
.issues.warn { color:#e8c988; }
.notes { font-size:0.78rem; color:#8a919d; font-style:italic; margin-top:6px; }
.lightbox { display:none; position:fixed; inset:0; background:rgba(5,6,8,0.92); z-index:50;
	align-items:center; justify-content:center; cursor:zoom-out; }
.lightbox.open { display:flex; }
.lightbox img { max-width:92vw; max-height:92vh; border-radius:8px; }
@media (max-width:700px) { .grid { grid-template-columns:1fr; } }
"""

_JS = """
function openLightbox(src) {
	var lb = document.getElementById('lightbox');
	document.getElementById('lightbox-img').src = src;
	lb.classList.add('open');
}
document.addEventListener('DOMContentLoaded', function () {
	document.getElementById('lightbox').addEventListener('click', function () { this.classList.remove('open'); });
});
"""


def _esc(v) -> str:
	import html as _html
	return _html.escape(str(v), quote=True)


def _rel(path: Path, base: Path) -> str:
	return os.path.relpath(path, base).replace("\\", "/")


def _g3_status(info: dict) -> str:
	if info["glb"] is None:
		return "MISSING"
	return "FAIL" if info["failures"] else "PASS"


def _g2_status(info: dict, verdicts: dict) -> tuple:
	v = verdicts.get(info["id"])
	if not v:
		return "PENDING", ""
	status = str(v.get("g2", "PENDING")).upper()
	if status not in _STATUS_COLOR:
		status = "PENDING"
	return status, v.get("note", "")


def _render_card(info: dict, out_dir: Path, verdicts: dict) -> str:
	g3 = _g3_status(info)
	g2, g2_note = _g2_status(info, verdicts)

	if info["preview_sheet"] is not None and Path(info["preview_sheet"]).is_file():
		src = _rel(Path(info["preview_sheet"]), out_dir)
		thumb_html = f'<img class="thumb" src="{_esc(src)}" loading="lazy" onclick="openLightbox(\'{_esc(src)}\')">'
	elif info["turntable_sheet"] is not None and Path(info["turntable_sheet"]).is_file():
		src = _rel(Path(info["turntable_sheet"]), out_dir)
		thumb_html = (f'<img class="thumb" src="{_esc(src)}" loading="lazy" onclick="openLightbox(\'{_esc(src)}\')">'
			'<div class="notes">planche turntable (model_preview indisponible)</div>')
	else:
		thumb_html = '<div class="thumb-missing">aucune planche</div>'

	check = info.get("check") or {}
	tris = check.get("tris")
	tris_txt = f"{tris} / {info['budget_tris']}" if tris is not None else "n/a"

	issues_html = ""
	if info["failures"]:
		issues_html += '<ul class="issues fail">' + "".join(f"<li>{_esc(f)}</li>" for f in info["failures"][:12]) + "</ul>"
	if info["warnings"]:
		issues_html += '<ul class="issues warn">' + "".join(f"<li>{_esc(w)}</li>" for w in info["warnings"][:8]) + "</ul>"

	parts = info.get("parts_separated") or []
	markers = info.get("markers") or []
	parts_row = ""
	if parts or markers:
		parts_row = f'<div class="row"><b>Pièces</b> {_esc(", ".join(parts) or "aucune")} — <b>Marqueurs</b> {_esc(", ".join(markers) or "aucun")}</div>'

	notes_html = f'<div class="notes">{_esc(info["notes"])}</div>' if info.get("notes") else ""
	g2_note_html = f'<div class="notes">G2 : {_esc(g2_note)}</div>' if g2_note else ""

	return f"""
	<div class="card">
		<h2>{_esc(info['id'])}
			<span class="badge">{_esc(info['category'])}</span>
			<span class="badge">{_esc(info['priority'])}</span>
		</h2>
		<div class="verdicts">
			<span class="verdict" style="background:{_STATUS_COLOR[g2]}22;color:{_STATUS_COLOR[g2]}">G2 {g2}</span>
			<span class="verdict" style="background:{_STATUS_COLOR[g3]}22;color:{_STATUS_COLOR[g3]}">G3 {g3}</span>
		</div>
		{thumb_html}
		<div class="row"><b>Triangles</b> {_esc(tris_txt)} — <b>scale_m cible</b> {_esc(info['scale_m'])} m</div>
		{parts_row}
		{issues_html}
		{notes_html}
		{g2_note_html}
	</div>"""


def build_index_html(infos: list, out_path: Path) -> None:
	out_path.parent.mkdir(parents=True, exist_ok=True)
	verdicts = _load_g2_verdicts()
	total = len(infos)
	n_g3_pass = sum(1 for i in infos if _g3_status(i) == "PASS")
	n_g3_fail = total - n_g3_pass
	g2_counts = {"PASS": 0, "FAIL": 0, "PENDING": 0}
	for i in infos:
		status, _ = _g2_status(i, verdicts)
		g2_counts[status] = g2_counts.get(status, 0) + 1

	stats_html = "".join(
		f'<span class="pill"><span class="dot" style="background:{c}"></span>{label}</span>'
		for label, c in (
			(f"{total} assets", "#6b7280"),
			(f"{n_g3_pass} G3 PASS", _STATUS_COLOR["PASS"]),
			(f"{n_g3_fail} G3 FAIL", _STATUS_COLOR["FAIL"]),
			(f"{g2_counts['PASS']} G2 PASS", _STATUS_COLOR["PASS"]),
			(f"{g2_counts['FAIL']} G2 FAIL", _STATUS_COLOR["FAIL"]),
			(f"{g2_counts['PENDING']} G2 à revoir", _STATUS_COLOR["PENDING"]),
		)
	)
	cards_html = "".join(_render_card(info, out_path.parent, verdicts) for info in infos)
	generated_at = datetime.now(timezone.utc).isoformat()

	html_doc = f"""<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Revue restyle — vague 1 Tripo (A3D-13)</title>
<style>{_CSS}</style>
</head>
<body>
	<h1>Revue restyle — vague 1 Tripo (A3D-13)</h1>
	<div class="meta">Généré le {_esc(generated_at)} — G2 : jugement visuel (voir g2_verdicts.json) · G3 : check_asset.py + bbox scale_m ± 2 % (automatique)</div>
	<div class="stats">{stats_html}</div>
	<div class="grid">{cards_html}</div>
	<div class="lightbox" id="lightbox"><img id="lightbox-img" src=""></div>
	<script>{_JS}</script>
</body>
</html>"""
	out_path.write_text(html_doc, encoding="utf-8")


# ============================================================================
#  État persistant par asset — corrige un second défaut du retour QA A3D-13 :
#  `main()` ne construisait `index.html` qu'à partir des entrées de CETTE
#  exécution, donc un `--only id1,id2` tronquait la page récapitulative à ces
#  seuls ids (repro : lancer `--only wpn_pistolet,cs_container_20` faisait
#  tomber "24 assets" à "2 assets" dans l'en-tête). `assets/incoming/tripo/
#  restyled/_wave_state.json` (sous mon périmètre, comme le reste de ce
#  dossier) garde le dernier `info` connu de CHAQUE id déjà traité au moins
#  une fois ; `main()` le fusionne avec les résultats frais de cette exécution
#  avant de construire l'index, qui couvre donc TOUJOURS le manifeste entier.
# ============================================================================

STATE_PATH = OUT_DIR / "_wave_state.json"
_PATH_FIELDS = ("glb", "turntable_sheet", "preview_sheet")


def _info_to_state(info: dict) -> dict:
	d = dict(info)
	for k in _PATH_FIELDS:
		if d.get(k) is not None:
			d[k] = str(d[k])
	return d


def _state_to_info(d: dict) -> dict:
	info = dict(d)
	for k in _PATH_FIELDS:
		if info.get(k) is not None:
			info[k] = Path(info[k])
	return info


def _load_wave_state() -> dict:
	if not STATE_PATH.is_file():
		return {}
	try:
		raw = json.loads(STATE_PATH.read_text(encoding="utf-8"))
	except json.JSONDecodeError:
		return {}
	if not isinstance(raw, dict):
		return {}
	return {aid: _state_to_info(d) for aid, d in raw.items() if isinstance(d, dict)}


def _save_wave_state(infos_by_id: dict) -> None:
	OUT_DIR.mkdir(parents=True, exist_ok=True)
	payload = {aid: _info_to_state(info) for aid, info in infos_by_id.items()}
	STATE_PATH.write_text(
		json.dumps(payload, ensure_ascii=False, indent="\t", sort_keys=True), encoding="utf-8")


def _untried_info(entry: ManifestEntry) -> dict:
	"""Fiche d'un id du manifeste jamais traité par aucune exécution passée
	(absent de `_wave_state.json`) — ne doit jamais arriver en usage normal
	(le premier lancement traite tout le manifeste), seulement après un
	`--only` portant sur un sous-ensemble avant tout premier passage complet."""
	return {
		"id": entry.id, "category": entry.category, "priority": entry.priority,
		"scale_m": entry.scale_m, "budget_tris": entry.budget_tris, "notes": entry.notes,
		"failures": ["jamais traité par tools/ai3d/restyle_wave.py (aucun --only précédent ne le couvrait)"],
		"warnings": [], "worker": None, "check": None, "preview_sheet": None,
		"turntable_sheet": None, "glb": None, "meta": ASSET_META.get(entry.id),
	}


def parse_args(argv=None) -> argparse.Namespace:
	p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
	p.add_argument("manifest", type=Path)
	p.add_argument("--only", default=None, help="ids séparés par des virgules")
	p.add_argument("--force", action="store_true")
	p.add_argument("--skip-turntable", action="store_true", dest="skip_turntable")
	p.add_argument("--views", type=int, default=8)
	p.add_argument("--size", type=int, default=512)
	return p.parse_args(argv)


def main(argv=None) -> int:
	args = parse_args(argv)
	all_entries = load_wave_manifest(args.manifest)
	if args.only:
		ids = {s.strip() for s in args.only.split(",") if s.strip()}
		entries = [e for e in all_entries if e.id in ids]
	else:
		entries = all_entries
	if not entries:
		print("RESTYLE_WAVE_EMPTY aucune entrée sélectionnée", file=sys.stderr)
		return 2

	infos_by_id = _load_wave_state()
	for entry in entries:
		print(f"RESTYLE_WAVE_START {entry.id}", flush=True)
		info = process_entry(entry, args.force, args.skip_turntable, args.views, args.size)
		status = "OK" if not info["failures"] else "ECHEC"
		print(f"RESTYLE_WAVE_{status} {entry.id} — {len(info['failures'])} échec(s), {len(info['warnings'])} avertissement(s)", flush=True)
		for f in info["failures"]:
			print(f"    - {f}", flush=True)
		infos_by_id[entry.id] = info
	_save_wave_state(infos_by_id)

	# L'index couvre TOUJOURS le manifeste entier (voir commentaire au-dessus
	# de _load_wave_state) : un `--only` ne rend que ce sous-ensemble mais ne
	# tronque jamais la page récapitulative aux ids qu'il a traités.
	full_infos = [infos_by_id.get(entry.id) or _untried_info(entry) for entry in all_entries]

	out_path = OUT_DIR / "index.html"
	build_index_html(full_infos, out_path)
	n_bad_run = sum(1 for e in entries if (infos_by_id.get(e.id) or {}).get("failures"))
	n_bad_total = sum(1 for i in full_infos if i["failures"])
	print(f"RESTYLE_WAVE_DONE {out_path} ({len(full_infos)} entrée(s) au total, "
		f"{n_bad_total} en échec dont {n_bad_run} sur les {len(entries)} traitée(s) cette exécution)")
	return 0 if n_bad_run == 0 else 1


if __name__ == "__main__":
	sys.exit(main())
