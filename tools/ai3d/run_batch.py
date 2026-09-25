#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/ai3d/run_batch.py
Pipeline de production 3D par lot via `tripo-cli` (voir docs/AI_TOOLS.md
§« Production en lot »). Lit un manifeste YAML (liste d'entrées : arme, prop,
gameplay, capacité, décor), estime son coût en crédits, refuse de démarrer si
ce coût dépasse le plafond `--max-credits` OU le solde live (`tripo balance`),
puis pour chaque entrée sélectionnée :
  1. construit la commande tripo adaptée à sa `route` (texte, image amont, ou
     multivue) avec ses paramètres (face_limit, quad, texture, low-poly
     intelligent) ;
  2. l'exécute (en parallèle borné par --parallel), retente une fois en cas
     d'échec, ne régénère jamais un id qui a déjà un .glb (sauf --force) ;
  3. copie le résultat vers assets/incoming/tripo/<category>/<id>.glb et écrit
     sa provenance (<id>.provenance.json) ;
  4. fait vérifier chaque asset (tools/blender/check_asset.py) et le
     photographie en jeu (tools/review/model_preview.gd, fenêtré), puis
     assemble assets/incoming/tripo/review.html — une page unique listant
     toute la vague (aperçu, tris, PASS/FAIL, crédits, prompt) pour une revue
     groupée par le lead.

Usage :
    python tools/ai3d/run_batch.py MANIFEST.yaml [--only id1,id2] [--priority P0]
        [--max-credits N] [--dry-run] [--parallel 4] [--ingest-only] [--force]

`--dry-run` n'appelle JAMAIS l'API : il imprime les commandes exactes et le
coût estimé (pour la route "text", qui passe par `tripo make`, il valide en
plus GRATUITEMENT via le `--dry-run` natif de la CLI — les routes "image" et
"multiview" passent par `tripo generate ...`, qui n'a pas de `--dry-run`
natif : voir `tripo generate --help`, elles ne sont donc que décrites, pas
validées côté serveur).

`--ingest-only` saute entièrement la génération (donc l'estimation de coût et
le contrôle de solde) et ne fait que l'étape 4 ci-dessus sur les .glb déjà
présents — utile pour rejouer la revue, ou pour des fichiers déposés à la
main (voir `resolve_glb_path` : compatible avec d'anciens .glb posés à plat
dans assets/incoming/tripo/, comme verrou_v1.glb / vif_v1.glb).

En `--ingest-only`, MANIFEST peut aussi être un DOSSIER de .glb posés à plat
sans manifeste (ex. `assets/incoming/tripo/studio/`, alimenté par
`tools/ai3d/bridge_autoexport.py` depuis Tripo Studio — voir docs/AI_TOOLS.md
§ Studio → Blender) : chaque .glb y devient une entrée de revue, catégorie
déduite du préfixe de son nom (`weapon_`/`prop_`/`fx_`/..., repli `prop`),
budget de triangles indicatif (`STUDIO_DEFAULT_BUDGET_TRIS`).

Estimation de crédits : barème CONSERVATEUR (jamais sous-évalué — voir les
constantes ci-dessous et docs/AI_TOOLS.md), pas une facturation exacte. Le
coût RÉEL de chaque génération est celui que l'API renvoie
(`credits_consumed`), écrit tel quel dans la provenance de l'asset.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import yaml

ROOT = Path(__file__).resolve().parents[2]
OUT_ROOT = ROOT / "assets" / "incoming" / "tripo"
WORK_ROOT = OUT_ROOT / "_work"

# Chemins des outils externes (mêmes défauts que docs/AI_TOOLS.md et
# tasks/context.md) — surchargeables par variable d'env pour les tests / une
# autre machine.
BLENDER_EXE = os.environ.get("BLENDER_EXE", r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe")
GODOT_EXE = os.environ.get("GODOT_EXE", r"C:\Users\srko\Desktop\Godot_v4.7-stable_win64.exe")
CHECK_ASSET_SCRIPT = ROOT / "tools" / "blender" / "check_asset.py"
MODEL_PREVIEW_SCENE = "res://tools/review/model_preview.gd"

VALID_CATEGORIES = {"weapon", "prop", "gameplay", "ability", "env"}
VALID_ROUTES = {"text", "image", "multiview"}
REQUIRED_KEYS = {
	"id", "category", "route", "prompt", "face_limit", "quad", "texture",
	"smart_lowpoly", "budget_tris", "scale_m", "priority",
}
OPTIONAL_KEYS = {"image_prompt", "notes"}

# ============================================================================
#  Barème de crédits — ESTIMATION conservatrice (docs/AI_TOOLS.md : « image→3D
#  20 crédits, low-poly intelligent +10, quad +5, texture HD +10, auto-rig
#  25 » ; `tripo docs --topic commands/generate` pour le détail des options).
#  Le manifeste ne pilote jamais l'auto-rig (aucune clé dédiée) donc il n'est
#  pas compté ici. Cette fonction ne DOIT jamais sous-estimer : c'est le
#  garde-fou --max-credits qui en dépend, désactiver une option (`texture:
#  false`) ne fait donc jamais BAISSER l'estimation.
# ============================================================================
BASE_GENERATION_CREDITS = 20     # génération text-to-model / image-to-model
CONCEPT_IMAGE_CREDITS = 15       # étape text-to-image (routes image/multiview) — barème t2i non publié dans `tripo docs`, estimation prudente
MULTIVIEW_EXTRA_CREDITS = 10     # image-to-multiview + assemblage 2-4 vues
SMART_LOWPOLY_CREDITS = 10
QUAD_CREDITS = 5
TEXTURE_MARGIN_CREDITS = 10      # marge si la texture bascule en qualité détaillée/extrême côté API

DEFAULT_MAX_CREDITS = 500
DEFAULT_PARALLEL = 4
RETRY_BACKOFF_SEC = 3.0
LICENCE_NOTE = "sorties Tripo — plan payant, usage commercial"


class ManifestError(Exception):
	"""Manifeste invalide — le message liste TOUTES les violations trouvées
	(pas seulement la première), pour corriger le fichier en un seul passage."""


class TripoCommandError(RuntimeError):
	"""Une commande tripo a rendu un code de sortie non nul."""

	def __init__(self, argv: list, proc: "subprocess.CompletedProcess"):
		self.argv = argv
		self.proc = proc
		super().__init__(
			f"commande tripo en échec (code {proc.returncode}) : {' '.join(argv)}\n"
			f"stderr: {proc.stderr.strip()[-2000:]}"
		)


@dataclass(frozen=True)
class ManifestEntry:
	id: str
	category: str
	route: str
	prompt: str
	face_limit: int
	quad: bool
	texture: bool
	smart_lowpoly: bool
	budget_tris: int
	scale_m: float
	priority: str
	image_prompt: Optional[str] = None
	notes: str = ""


# ============================================================================
#  Chemins conventionnels dérivés d'une entrée
# ============================================================================

def category_glb_path(entry: ManifestEntry) -> Path:
	return OUT_ROOT / entry.category / f"{entry.id}.glb"


def flat_glb_path(entry: ManifestEntry) -> Path:
	# Compat : fichiers déposés à plat AVANT ce pipeline (ex. verrou_v1.glb,
	# vif_v1.glb, directement sous assets/incoming/tripo/) — jamais écrit par
	# ce script pour une NOUVELLE génération (toujours <category>/<id>.glb),
	# seulement lu en repli pour l'ingestion d'anciens fichiers.
	return OUT_ROOT / f"{entry.id}.glb"


def resolve_glb_path(entry: ManifestEntry) -> Optional[Path]:
	cat_path = category_glb_path(entry)
	if cat_path.is_file():
		return cat_path
	flat_path = flat_glb_path(entry)
	if flat_path.is_file():
		return flat_path
	return None


def check_json_path(glb_path: Path) -> Path:
	return glb_path.parent / f"{glb_path.stem}.check.json"


def provenance_path(glb_path: Path) -> Path:
	return glb_path.parent / f"{glb_path.stem}.provenance.json"


def preview_dir(glb_path: Path) -> Path:
	# Même convention que le défaut de tools/review/model_preview.gd
	# (`_out_dir = _in_path.get_base_dir().path_join(_model_name + "_preview")`).
	return glb_path.parent / f"{glb_path.stem}_preview"


def preview_sheet_path(glb_path: Path) -> Path:
	return preview_dir(glb_path) / f"{glb_path.stem}_planche.png"


# ============================================================================
#  Chargement + validation du manifeste
# ============================================================================

def _validate_item(item, index: int, seen_ids: set) -> list:
	tag = f"entrée #{index}"
	errors = []
	if not isinstance(item, dict):
		return [f"{tag}: doit être un mapping YAML, reçu {type(item).__name__}"]

	entry_id = item.get("id")
	if isinstance(entry_id, str) and entry_id.strip():
		tag = entry_id
	missing = REQUIRED_KEYS - item.keys()
	if missing:
		errors.append(f"{tag}: clé(s) manquante(s) : {sorted(missing)}")
		return errors  # types non fiables sans les clés de base — inutile de continuer
	unknown = set(item.keys()) - REQUIRED_KEYS - OPTIONAL_KEYS
	if unknown:
		errors.append(f"{tag}: clé(s) inconnue(s) : {sorted(unknown)}")

	if not isinstance(entry_id, str) or not entry_id.strip():
		errors.append(f"{tag}: id doit être une chaîne non vide")
	elif "/" in entry_id or "\\" in entry_id or entry_id != entry_id.strip():
		errors.append(f"{tag}: id invalide {entry_id!r} (aucun séparateur de chemin, pas d'espace de bord)")
	elif entry_id in seen_ids:
		errors.append(f"{tag}: id dupliqué dans le manifeste")
	if isinstance(entry_id, str):
		seen_ids.add(entry_id)

	if item["category"] not in VALID_CATEGORIES:
		errors.append(f"{tag}: category {item['category']!r} inconnue (attendu {sorted(VALID_CATEGORIES)})")
	if item["route"] not in VALID_ROUTES:
		errors.append(f"{tag}: route {item['route']!r} inconnue (attendu {sorted(VALID_ROUTES)})")
	if not isinstance(item["prompt"], str) or not item["prompt"].strip():
		errors.append(f"{tag}: prompt doit être une chaîne non vide")
	if item.get("image_prompt") is not None and not isinstance(item["image_prompt"], str):
		errors.append(f"{tag}: image_prompt doit être une chaîne")
	if item["route"] in ("image", "multiview"):
		if not (item.get("image_prompt") or "").strip() and not (item.get("prompt") or "").strip():
			errors.append(f"{tag}: route {item['route']!r} nécessite prompt ou image_prompt (image de concept)")

	for key in ("face_limit", "budget_tris"):
		if isinstance(item.get(key), bool) or not isinstance(item.get(key), int):
			errors.append(f"{tag}: {key} doit être un entier")
		elif item[key] <= 0:
			errors.append(f"{tag}: {key} doit être positif")
	for key in ("quad", "texture", "smart_lowpoly"):
		if not isinstance(item.get(key), bool):
			errors.append(f"{tag}: {key} doit être un booléen")
	if isinstance(item.get("scale_m"), bool) or not isinstance(item.get("scale_m"), (int, float)):
		errors.append(f"{tag}: scale_m doit être un nombre")
	elif item["scale_m"] <= 0:
		errors.append(f"{tag}: scale_m doit être positif")
	if not isinstance(item.get("priority"), str) or not item["priority"].strip():
		errors.append(f"{tag}: priority doit être une chaîne (ex. 'P0')")
	if item.get("notes") is not None and not isinstance(item["notes"], str):
		errors.append(f"{tag}: notes doit être une chaîne")

	return errors


def _build_entry(item: dict) -> ManifestEntry:
	return ManifestEntry(
		id=item["id"],
		category=item["category"],
		route=item["route"],
		prompt=item["prompt"],
		face_limit=int(item["face_limit"]),
		quad=bool(item["quad"]),
		texture=bool(item["texture"]),
		smart_lowpoly=bool(item["smart_lowpoly"]),
		budget_tris=int(item["budget_tris"]),
		scale_m=float(item["scale_m"]),
		priority=item["priority"],
		image_prompt=item.get("image_prompt"),
		notes=item.get("notes") or "",
	)


def load_manifest(path: Path) -> list:
	path = Path(path)
	raw = yaml.safe_load(path.read_text(encoding="utf-8"))
	if raw is None:
		raw = []
	if not isinstance(raw, list):
		raise ManifestError(f"{path}: le manifeste doit être une liste YAML d'entrées, reçu {type(raw).__name__}")

	errors = []
	seen_ids: set = set()
	for i, item in enumerate(raw):
		errors.extend(_validate_item(item, i, seen_ids))
	if errors:
		raise ManifestError("manifeste invalide (" + str(path) + ") :\n" + "\n".join(f"  - {e}" for e in errors))
	return [_build_entry(item) for item in raw]


def select_entries(entries: list, only: Optional[str], priority: Optional[str]) -> list:
	ids = {s.strip() for s in only.split(",") if s.strip()} if only else None
	out = []
	for e in entries:
		if ids is not None and e.id not in ids:
			continue
		if priority is not None and e.priority != priority:
			continue
		out.append(e)
	return out


# ============================================================================
#  Estimation de crédits + garde-fou
# ============================================================================

def estimate_credits(entry: ManifestEntry) -> int:
	cost = BASE_GENERATION_CREDITS
	if entry.route in ("image", "multiview"):
		cost += CONCEPT_IMAGE_CREDITS
	if entry.route == "multiview":
		cost += MULTIVIEW_EXTRA_CREDITS
	if entry.smart_lowpoly:
		cost += SMART_LOWPOLY_CREDITS
	if entry.quad:
		cost += QUAD_CREDITS
	if entry.texture:
		cost += TEXTURE_MARGIN_CREDITS
	return cost


def plan_batch(entries: list) -> dict:
	per_entry = {e.id: estimate_credits(e) for e in entries}
	return {"per_entry": per_entry, "total": sum(per_entry.values())}


def check_budget(total: int, max_credits: int, balance: Optional[int]) -> list:
	problems = []
	if total > max_credits:
		problems.append(f"coût estimé {total} crédits > plafond --max-credits {max_credits}")
	if balance is not None and total > balance:
		problems.append(f"coût estimé {total} crédits > solde live tripo ({balance})")
	return problems


# ============================================================================
#  Exécution des commandes (point de passage unique — celui que les tests
#  remplacent par un double de test)
# ============================================================================

def _run_command(argv: list, cwd: Optional[Path] = None) -> "subprocess.CompletedProcess":
	# shell=True sur Windows : les CLI npm globales (tripo) sont des shims
	# .cmd — CreateProcess ne les résout pas sans passer par cmd.exe. Une
	# liste d'arguments reste correctement quotée par Python (list2cmdline)
	# même avec shell=True, y compris pour des prompts avec espaces/accents.
	return subprocess.run(
		argv, cwd=str(cwd) if cwd else None, capture_output=True,
		text=True, encoding="utf-8", errors="replace", shell=(os.name == "nt"),
	)


def get_tool_version() -> str:
	try:
		proc = _run_command(["tripo", "--version"])
	except FileNotFoundError:
		return "inconnue (tripo introuvable)"
	if proc.returncode != 0:
		return "inconnue"
	return proc.stdout.strip() or "inconnue"


def get_live_balance() -> Optional[int]:
	try:
		proc = _run_command(["tripo", "balance", "--json"])
	except FileNotFoundError:
		return None
	if proc.returncode != 0:
		return None
	try:
		data = json.loads(proc.stdout.strip().splitlines()[-1])
	except (json.JSONDecodeError, IndexError):
		return None
	return data.get("balance")


# ============================================================================
#  Construction des commandes par route (pure — testable sans subprocess)
# ============================================================================

def _bool_param(v: bool) -> str:
	return "true" if v else "false"


def build_generation_commands(entry: ManifestEntry, work_dir: Path) -> list:
	"""Retourne la chaîne ORDONNÉE de commandes tripo pour produire le .glb de
	`entry`. Chaque étape est {"argv", "produces"} ; les jetons "__PREV_FILE__"
	/ "__PREV_FILES__" dans argv sont substitués À L'EXÉCUTION (voir
	`_materialize_argv`) par le(s) fichier(s) réellement téléchargé(s) par
	l'étape précédente — jamais par une référence de tâche (`@last`/task id) :
	l'acceptation de ces références varie selon l'endpoint (cf.
	`tripo docs --topic commands/generate`, colonne `input`), alors qu'un
	fichier local est TOUJOURS accepté (« the CLI uploads local files for
	you »).

	Aucun `--for`/`--then` : le manifeste donne déjà tous les paramètres de
	génération (face_limit/quad/texture/smart_lowpoly) — un scénario `--for`
	les écraserait silencieusement (ex. `game-pc` force `texture_quality=
	detailed` et une conversion FBX/GLTF non désirée, sondé via
	`tripo make ... --for game-pc --dry-run --json`).

	`--model tripo-v3.1` forcé UNIQUEMENT si quad/smart_lowpoly est demandé :
	sans ça, l'auto-sélection du modèle (P1 pour un petit face_limit) les
	retire silencieusement avec un avertissement (sondé : `tripo make ... -p
	quad=true --dry-run --json` sur un petit face_limit choisit P1 et rend
	"P1 does not support quad (removed)")."""
	force_v31 = entry.quad or entry.smart_lowpoly
	model_flag = ["--model", "tripo-v3.1"] if force_v31 else []
	gen_params = [
		"-p", f"face_limit={entry.face_limit}",
		"-p", f"texture={_bool_param(entry.texture)}",
		"-p", f"quad={_bool_param(entry.quad)}",
		"-p", f"smart_low_poly={_bool_param(entry.smart_lowpoly)}",
	]
	common_tail = ["--json", "--yes", "--no-open"]

	if entry.route == "text":
		argv = ["tripo", "make", entry.prompt, *model_flag, *gen_params, *common_tail,
			"-o", str(work_dir)]
		return [{"argv": argv, "produces": None}]

	concept_prompt = entry.image_prompt or entry.prompt
	step_concept = {
		"argv": ["tripo", "generate", "text-to-image", concept_prompt, *common_tail,
			"-o", str(work_dir / "concept")],
		"produces": "image",
	}

	if entry.route == "image":
		step_model = {
			"argv": ["tripo", "generate", "image-to-model", "__PREV_FILE__", *model_flag, *gen_params,
				*common_tail, "-o", str(work_dir)],
			"produces": None,
		}
		return [step_concept, step_model]

	if entry.route == "multiview":
		step_multiview = {
			"argv": ["tripo", "generate", "image-to-multiview", "__PREV_FILE__", *common_tail,
				"-o", str(work_dir / "multiview")],
			"produces": "images",
		}
		step_model = {
			"argv": ["tripo", "generate", "multiview-to-model", "__PREV_FILES__", *model_flag, *gen_params,
				*common_tail, "-o", str(work_dir)],
			"produces": None,
		}
		return [step_concept, step_multiview, step_model]

	raise ValueError(f"route inconnue : {entry.route!r}")


def _materialize_argv(template: list, prev_files: list) -> list:
	out = []
	for tok in template:
		if tok == "__PREV_FILE__":
			if not prev_files:
				raise RuntimeError("étape précédente : aucun fichier exploitable pour continuer la chaîne")
			out.append(str(prev_files[0]))
		elif tok == "__PREV_FILES__":
			if not prev_files:
				raise RuntimeError("étape précédente : aucun fichier exploitable pour continuer la chaîne")
			out.extend(str(p) for p in prev_files)
		else:
			out.append(tok)
	return out


# ============================================================================
#  Exécution réelle d'une génération
# ============================================================================

IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".webp")
MODEL_EXTS = (".glb",)


def _last_json_line(stdout: str) -> dict:
	lines = [ln for ln in stdout.splitlines() if ln.strip()]
	if not lines:
		raise RuntimeError("sortie tripo vide — une ligne JSON était attendue sur stdout (--json)")
	return json.loads(lines[-1])


def _find_output_files(result: dict, exts: tuple) -> list:
	out_dir = Path(result.get("output_dir") or ".")
	names = result.get("files") or []
	found = [out_dir / n for n in names if Path(n).suffix.lower() in exts]
	model_file = result.get("model_file")
	if model_file and Path(model_file).suffix.lower() in exts:
		p = Path(model_file)
		if p not in found:
			found.insert(0, p)
	return found


def run_generation(entry: ManifestEntry, work_dir: Path) -> dict:
	"""Exécute la chaîne réelle (subprocess) pour `entry`. Retourne
	{"glb_path", "task_ids", "credits_spent"}."""
	steps = build_generation_commands(entry, work_dir)
	task_ids = []
	credits_spent = 0
	prev_files: list = []
	last_result = None
	for step in steps:
		argv = _materialize_argv(step["argv"], prev_files)
		proc = _run_command(argv)
		if proc.returncode != 0:
			raise TripoCommandError(argv, proc)
		result = _last_json_line(proc.stdout)
		last_result = result
		if result.get("task_id"):
			task_ids.append(result["task_id"])
		credits_spent += int(result.get("credits_consumed") or 0)
		if step["produces"] in ("image", "images"):
			prev_files = _find_output_files(result, IMAGE_EXTS)
			if not prev_files:
				raise RuntimeError(f"{entry.id}: étape {argv[2]!r} n'a téléchargé aucune image exploitable")

	glb_candidates = _find_output_files(last_result or {}, MODEL_EXTS)
	if not glb_candidates:
		hint = (
			" (attendu : quad=true force une sortie FBX côté API — un maillage à quads ne "
			"peut pas être stocké en GLB, voir `tripo docs --topic commands/generate` § "
			"paramètres — cette entrée ne peut PAS produire de .glb tel quel, retirer "
			"`quad` ou adapter le pipeline pour accepter du FBX)"
			if entry.quad else ""
		)
		raise RuntimeError(
			f"{entry.id}: aucun .glb dans la sortie tripo — fichiers={((last_result or {}).get('files'))}{hint}"
		)
	return {"glb_path": glb_candidates[0], "task_ids": task_ids, "credits_spent": credits_spent}


def run_generation_with_retry(entry: ManifestEntry, work_dir: Path, retries: int = 1) -> dict:
	# Une tâche tripo en échec est auto-remboursée (docs/AI_TOOLS.md,
	# `tripo docs --llm` § comportement de coût) : retenter la chaîne entière
	# une fois ne double donc pas la dépense en cas d'échec réel côté API.
	last_exc = None
	for attempt in range(retries + 1):
		try:
			return run_generation(entry, work_dir)
		except Exception as exc:  # noqa: BLE001 — on relance nous-mêmes ci-dessous
			last_exc = exc
			if attempt < retries:
				time.sleep(RETRY_BACKOFF_SEC)
	raise last_exc


def write_provenance(entry: ManifestEntry, glb_path: Path, task_ids: list, credits_spent: int, tool_version: str) -> Path:
	data = {
		"id": entry.id,
		"category": entry.category,
		"route": entry.route,
		"tool": "tripo-cli",
		"tool_version": tool_version,
		"task_ids": task_ids,
		"prompt": entry.prompt,
		"image_prompt": entry.image_prompt,
		"params": {
			"face_limit": entry.face_limit,
			"quad": entry.quad,
			"texture": entry.texture,
			"smart_lowpoly": entry.smart_lowpoly,
			"scale_m": entry.scale_m,
		},
		"credits_spent": credits_spent,
		"date": datetime.now(timezone.utc).isoformat(),
		"licence": LICENCE_NOTE,
	}
	path = provenance_path(glb_path)
	path.parent.mkdir(parents=True, exist_ok=True)
	path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
	return path


def generate_one(entry: ManifestEntry, tool_version: str) -> dict:
	work_dir = WORK_ROOT / entry.id
	work_dir.mkdir(parents=True, exist_ok=True)
	gen = run_generation_with_retry(entry, work_dir)
	dest = category_glb_path(entry)
	dest.parent.mkdir(parents=True, exist_ok=True)
	shutil.copy2(gen["glb_path"], dest)
	write_provenance(entry, dest, gen["task_ids"], gen["credits_spent"], tool_version)
	return {"glb_path": dest, "task_ids": gen["task_ids"], "credits_spent": gen["credits_spent"]}


# ============================================================================
#  Ingestion (check_asset + aperçu en jeu) — TOUJOURS séquentielle : Godot
#  ouvre une vraie fenêtre pour rendre model_preview.gd (voir sa docstring),
#  en lancer plusieurs en parallèle sur la même machine est fragile (focus/
#  swapchain exclusifs) — --parallel ne s'applique qu'à la génération.
# ============================================================================

def run_check_asset(glb_path: Path, budget_tris: int, force: bool) -> dict:
	out_json = check_json_path(glb_path)
	if not force and out_json.is_file() and out_json.stat().st_mtime >= glb_path.stat().st_mtime:
		return json.loads(out_json.read_text(encoding="utf-8"))
	argv = [
		BLENDER_EXE, "-b", "-P", str(CHECK_ASSET_SCRIPT), "--",
		"--in", str(glb_path), "--budget-tris", str(budget_tris), "--json", str(out_json),
	]
	_run_command(argv)
	if not out_json.is_file():
		return {"ok": False, "failures": ["check_asset.py n'a produit aucun rapport JSON"], "warnings": [],
			"tris": None, "dims_m": None}
	return json.loads(out_json.read_text(encoding="utf-8"))


def run_model_preview(glb_path: Path, force: bool) -> Optional[Path]:
	sheet = preview_sheet_path(glb_path)
	if not force and sheet.is_file() and sheet.stat().st_mtime >= glb_path.stat().st_mtime:
		return sheet
	argv = [GODOT_EXE, "--path", str(ROOT), "-s", MODEL_PREVIEW_SCENE, "--", f"--in={glb_path}"]
	_run_command(argv)
	return sheet if sheet.is_file() else None


STUDIO_DIR = OUT_ROOT / "studio"
# Pas de manifeste pour ces .glb (reçus via tools/ai3d/bridge_autoexport.py —
# Tripo Studio › Exporter › Envoyer à Blender, voir docs/AI_TOOLS.md § Studio
# → Blender) : aucun budget de triangles connu par asset, on applique un
# plafond indicatif large (la vraie vérification par classe se fait à la
# promotion, une fois l'asset copié avec un vrai manifeste --asset-class).
STUDIO_DEFAULT_BUDGET_TRIS = 100_000
STUDIO_CATEGORY_PREFIXES = {"weapon", "prop", "fx", "gameplay", "ability", "env"}


def infer_studio_category(stem: str) -> str:
	"""Catégorie déduite du préfixe du nom de fichier avant le premier '_'
	(ex. weapon_shotgun.glb -> "weapon", fx_muzzle.glb -> "fx") — simple
	étiquette d'affichage pour la revue, PAS une des VALID_CATEGORIES du
	manifeste (ces .glb n'en ont pas). Repli 'prop' si le préfixe n'est pas
	reconnu ou qu'il n'y a pas de '_'."""
	prefix = stem.split("_", 1)[0].lower()
	return prefix if prefix in STUDIO_CATEGORY_PREFIXES else "prop"


def ingest_studio_glb(glb: Path, force: bool) -> dict:
	"""Même vérification (check_asset + aperçu en jeu) qu'`ingest_entry`, mais
	pour un .glb posé à plat par le Bridge Blender — pas de ManifestEntry
	(pas d'id/prompt/route/priority connus au sens du manifeste)."""
	info = {
		"id": glb.stem, "category": infer_studio_category(glb.stem), "route": "studio",
		"priority": "n/a", "prompt": "(reçu depuis Tripo Studio via le DCC Bridge — pas de manifeste)",
		"notes": "", "glb": glb, "check": None, "preview_sheet": None, "provenance": None, "error": None,
	}
	try:
		info["check"] = run_check_asset(glb, STUDIO_DEFAULT_BUDGET_TRIS, force)
	except Exception as exc:  # noqa: BLE001 — un échec de vérification ne doit jamais arrêter la revue
		info["check"] = {"ok": False, "failures": [f"check_asset.py : {exc}"], "warnings": []}
	try:
		info["preview_sheet"] = run_model_preview(glb, force)
	except Exception as exc:  # noqa: BLE001 — idem : la revue reste utile sans aperçu
		info["error"] = f"aperçu échoué : {exc}"
	return info


def scan_studio_dir(dir_path: Path, force: bool, only: Optional[str] = None) -> list:
	ids = {s.strip() for s in only.split(",") if s.strip()} if only else None
	glbs = sorted(p for p in dir_path.glob("*.glb"))
	if ids is not None:
		glbs = [p for p in glbs if p.stem in ids]
	return [ingest_studio_glb(glb, force) for glb in glbs]


def ingest_entry(entry: ManifestEntry, force: bool) -> dict:
	glb = resolve_glb_path(entry)
	info = {
		"id": entry.id, "category": entry.category, "route": entry.route, "priority": entry.priority,
		"prompt": entry.prompt, "notes": entry.notes, "glb": glb,
		"check": None, "preview_sheet": None, "provenance": None, "error": None,
	}
	if glb is None:
		info["error"] = (
			f"GLB introuvable (ni {category_glb_path(entry)} ni {flat_glb_path(entry)}) "
			"— générer d'abord, ou vérifier l'id/la catégorie"
		)
		return info

	prov_path = provenance_path(glb)
	if prov_path.is_file():
		try:
			info["provenance"] = json.loads(prov_path.read_text(encoding="utf-8"))
		except json.JSONDecodeError:
			info["provenance"] = None

	try:
		info["check"] = run_check_asset(glb, entry.budget_tris, force)
	except Exception as exc:  # noqa: BLE001 — un échec de vérification ne doit jamais arrêter la revue
		info["check"] = {"ok": False, "failures": [f"check_asset.py : {exc}"], "warnings": []}

	try:
		info["preview_sheet"] = run_model_preview(glb, force)
	except Exception as exc:  # noqa: BLE001 — idem : la revue reste utile sans aperçu
		info["error"] = (info["error"] or "") + f" | aperçu échoué : {exc}"

	return info


# ============================================================================
#  Page de revue (assets/incoming/tripo/review.html) — mêmes codes couleurs
#  que tools/review/report.py (STATUS_COLOR), images référencées en CHEMIN
#  RELATIF (pas d'encodage base64 : convention déjà utilisée par
#  tools/review/report.py, plus léger pour une vague de plusieurs dizaines
#  d'assets — la page reste "autonome" au sens de ce dépôt : un seul fichier
#  html, ouvrable localement, ses images à côté).
# ============================================================================

_STATUS_COLOR = {"PASS": "#4caf6e", "FAIL": "#e0524d", "MISSING": "#6b7280"}

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
.grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(300px,1fr)); gap:16px; }
.card { background:#171a20; border:1px solid #262b34; border-radius:10px; padding:14px 16px; }
.card h2 { font-size:1rem; margin:0 0 6px; display:flex; align-items:center; gap:8px; flex-wrap:wrap; }
.badge { font-size:0.68rem; padding:1px 7px; border-radius:5px; background:#2a2f3a; color:#c7cbd3; }
.thumb { width:100%; border-radius:6px; border:1px solid #2a2f3a; cursor:zoom-in; display:block; margin:8px 0; }
.thumb-missing { width:100%; aspect-ratio:16/5; border-radius:6px; border:1px dashed #3a4150;
	display:flex; align-items:center; justify-content:center; color:#6b7280; font-size:0.8rem; margin:8px 0; }
.row { font-size:0.82rem; color:#c7cbd3; margin:2px 0; }
.row b { color:#fff; }
ul.issues { margin:6px 0 0; padding-left:18px; font-size:0.78rem; }
.issues.fail { color:#f3a9a6; }
.issues.warn { color:#e8c988; }
.error-banner { background:#241618; border:1px solid #5a2b2b; border-radius:8px; padding:8px 10px;
	font-size:0.8rem; color:#f3a9a6; margin:8px 0; }
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


def _entry_status(info: dict) -> str:
	if info["error"] or info["glb"] is None:
		return "MISSING"
	check = info.get("check") or {}
	return "PASS" if check.get("ok") else "FAIL"


def _render_card(info: dict, out_dir: Path) -> str:
	status = _entry_status(info)
	color = _STATUS_COLOR[status]
	check = info.get("check") or {}
	prov = info.get("provenance")

	if info["error"]:
		error_html = f'<div class="error-banner">{_esc(info["error"])}</div>'
	else:
		error_html = ""

	if info["preview_sheet"] is not None:
		src = _rel(info["preview_sheet"], out_dir)
		thumb_html = f'<img class="thumb" src="{_esc(src)}" loading="lazy" onclick="openLightbox(\'{_esc(src)}\')">'
	else:
		thumb_html = '<div class="thumb-missing">aperçu manquant</div>'

	tris = check.get("tris")
	dims = check.get("dims_m") or {}
	dims_txt = (
		f"{dims.get('largeur_x', '?')} × {dims.get('profondeur_y', '?')} × {dims.get('hauteur_z', '?')} m"
		if dims else "n/a"
	)
	budget = check.get("budget_tris")
	tris_txt = f"{tris} / {budget}" if tris is not None else "n/a"

	issues_html = ""
	failures = check.get("failures") or []
	warnings = check.get("warnings") or []
	if failures:
		issues_html += '<ul class="issues fail">' + "".join(f"<li>{_esc(f)}</li>" for f in failures[:10]) + "</ul>"
	if warnings:
		issues_html += '<ul class="issues warn">' + "".join(f"<li>{_esc(w)}</li>" for w in warnings[:10]) + "</ul>"

	if prov:
		credits_txt = f"{prov.get('credits_spent', 'n/a')} crédits · {_esc(prov.get('date', ''))}"
	else:
		credits_txt = "n/a (ingestion seule, pas de provenance)"

	notes_html = f'<div class="notes">{_esc(info["notes"])}</div>' if info.get("notes") else ""

	return f"""
	<div class="card">
		<h2><span class="dot" style="background:{color}"></span>{_esc(info['id'])}
			<span class="badge">{_esc(info['category'])}</span>
			<span class="badge">{_esc(info['route'])}</span>
			<span class="badge">{_esc(info['priority'])}</span>
			<span class="badge" style="color:{color}">{status}</span>
		</h2>
		{error_html}
		{thumb_html}
		<div class="row"><b>Triangles</b> {_esc(tris_txt)} — <b>Dimensions</b> {_esc(dims_txt)}</div>
		<div class="row"><b>Crédits</b> {credits_txt}</div>
		<div class="row"><b>Prompt</b> {_esc(info['prompt'])}</div>
		{issues_html}
		{notes_html}
	</div>"""


def build_review_html(infos: list, out_path: Path) -> None:
	out_path.parent.mkdir(parents=True, exist_ok=True)
	total = len(infos)
	n_pass = sum(1 for i in infos if _entry_status(i) == "PASS")
	n_fail = sum(1 for i in infos if _entry_status(i) == "FAIL")
	n_missing = total - n_pass - n_fail
	total_credits = sum((i.get("provenance") or {}).get("credits_spent", 0) for i in infos)

	stats_html = "".join(
		f'<span class="pill"><span class="dot" style="background:{c}"></span>{label}</span>'
		for label, c in (
			(f"{total} assets", "#6b7280"),
			(f"{n_pass} PASS", _STATUS_COLOR["PASS"]),
			(f"{n_fail} FAIL", _STATUS_COLOR["FAIL"]),
			(f"{n_missing} manquant(s)", _STATUS_COLOR["MISSING"]),
			(f"{total_credits} crédits dépensés (générés dans cette page)", "#6b7280"),
		)
	)
	cards_html = "".join(_render_card(info, out_path.parent) for info in infos)
	generated_at = datetime.now(timezone.utc).isoformat()

	html_doc = f"""<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Revue de production — Tripo</title>
<style>{_CSS}</style>
</head>
<body>
	<h1>Revue de production 3D — Tripo</h1>
	<div class="meta">Généré le {_esc(generated_at)}</div>
	<div class="stats">{stats_html}</div>
	<div class="grid">{cards_html}</div>
	<div class="lightbox" id="lightbox"><img id="lightbox-img" src=""></div>
	<script>{_JS}</script>
</body>
</html>"""
	out_path.write_text(html_doc, encoding="utf-8")


# ============================================================================
#  Orchestration (main)
# ============================================================================

def parse_args(argv=None) -> argparse.Namespace:
	p = argparse.ArgumentParser(description="Pipeline de production 3D par lot (Tripo) — voir docs/AI_TOOLS.md")
	p.add_argument("manifest", type=Path, help="chemin du manifeste YAML")
	p.add_argument("--only", default=None, help="ids séparés par des virgules")
	p.add_argument("--priority", default=None, help="filtre exact sur priority (ex. P0)")
	p.add_argument("--max-credits", type=int, default=DEFAULT_MAX_CREDITS, dest="max_credits")
	p.add_argument("--dry-run", action="store_true", dest="dry_run")
	p.add_argument("--parallel", type=int, default=DEFAULT_PARALLEL)
	p.add_argument("--ingest-only", action="store_true", dest="ingest_only")
	p.add_argument("--force", action="store_true")
	return p.parse_args(argv)


def _do_review(selected: list, force: bool) -> int:
	infos = [ingest_entry(e, force) for e in selected]
	out_path = OUT_ROOT / "review.html"
	build_review_html(infos, out_path)
	n_bad = sum(1 for i in infos if _entry_status(i) != "PASS")
	print(f"RUN_BATCH_REVIEW {out_path} ({len(infos)} entrée(s), {n_bad} en échec ou manquante(s))")
	return 0


def main(argv=None) -> int:
	args = parse_args(argv)

	if args.manifest.is_dir():
		# Dossier de .glb posés à plat (ex. assets/incoming/tripo/studio/,
		# alimenté par tools/ai3d/bridge_autoexport.py depuis Tripo Studio) —
		# uniquement valide en --ingest-only : pas de manifeste YAML, donc pas
		# de face_limit/prompt/priority à planifier ni de génération possible.
		if not args.ingest_only:
			print(
				f"RUN_BATCH_USAGE {args.manifest} est un dossier — seul --ingest-only "
				"accepte un dossier de .glb (ex. assets/incoming/tripo/studio/) en entrée, "
				"pas de plan de génération sans manifeste YAML",
				file=sys.stderr,
			)
			return 2
		infos = scan_studio_dir(args.manifest, args.force, args.only)
		if not infos:
			print(f"RUN_BATCH_EMPTY aucun .glb trouvé dans {args.manifest}", file=sys.stderr)
			return 2
		out_path = OUT_ROOT / "review.html"
		build_review_html(infos, out_path)
		n_bad = sum(1 for i in infos if _entry_status(i) != "PASS")
		print(f"RUN_BATCH_REVIEW {out_path} ({len(infos)} entrée(s), {n_bad} en échec ou manquante(s))")
		return 0

	try:
		entries = load_manifest(args.manifest)
	except ManifestError as exc:
		print(f"MANIFEST_INVALID\n{exc}", file=sys.stderr)
		return 2

	selected = select_entries(entries, args.only, args.priority)
	if not selected:
		print("RUN_BATCH_EMPTY aucune entrée sélectionnée (vérifier --only/--priority)", file=sys.stderr)
		return 2

	if args.ingest_only:
		return _do_review(selected, args.force)

	plan = plan_batch(selected)
	balance = get_live_balance()
	print(f"RUN_BATCH_PLAN total_estime={plan['total']} plafond={args.max_credits} solde_live={balance}")
	for e in selected:
		print(f"  - {e.id} ({e.category}/{e.route}): ~{plan['per_entry'][e.id]} crédits")

	problems = check_budget(plan["total"], args.max_credits, balance)
	if problems and not args.dry_run:
		# Le garde-fou ne bloque QUE la dépense réelle : --dry-run existe
		# précisément pour visualiser le plan/coût estimé sans appeler l'API,
		# y compris à solde 0 (c'est le seul mode utilisable tant que le
		# compte n'est pas rechargé — voir docs/AI_TOOLS.md).
		for pb in problems:
			print(f"RUN_BATCH_REFUS {pb}", file=sys.stderr)
		return 4
	if problems and args.dry_run:
		for pb in problems:
			print(f"RUN_BATCH_DRYRUN_WARN {pb} (un run réel serait refusé)")

	to_generate = []
	for e in selected:
		existing = resolve_glb_path(e)
		if existing is not None and not args.force:
			print(f"RUN_BATCH_SKIP {e.id}: GLB déjà présent ({existing}), --force pour régénérer")
			continue
		to_generate.append(e)

	if args.dry_run:
		for e in to_generate:
			steps = build_generation_commands(e, WORK_ROOT / e.id)
			print(f"RUN_BATCH_DRYRUN {e.id} ({e.route}):")
			for step in steps:
				print("    " + " ".join(step["argv"]))
			if e.route == "text":
				# La route "text" passe par `tripo make` : on peut la valider
				# GRATUITEMENT via son propre --dry-run (voir docstring de
				# build_generation_commands — "generate" n'a pas cette option).
				probe = [a for a in steps[0]["argv"] if a != "--no-open"] + ["--dry-run"]
				proc = _run_command(probe)
				out = proc.stdout.strip().splitlines()
				print("    validation tripo --dry-run:", out[-1] if out else proc.stderr.strip())
		print(f"RUN_BATCH_DRYRUN_OK total_estime={plan['total']} entrees_a_generer={len(to_generate)}")
		return 0

	if to_generate:
		# `tripo --version` n'est interrogé que s'il reste vraiment quelque
		# chose à générer (sinon un lot entièrement déjà présent — cas
		# fréquent en relance — ferait un appel tripo pour rien).
		tool_version = get_tool_version()
		with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.parallel)) as pool:
			futures = {pool.submit(generate_one, e, tool_version): e for e in to_generate}
			for fut in concurrent.futures.as_completed(futures):
				e = futures[fut]
				try:
					result = fut.result()
					print(f"RUN_BATCH_OK {e.id}: {result['glb_path']} ({result['credits_spent']} crédits)")
				except Exception as exc:  # noqa: BLE001 — une entrée en échec ne doit pas arrêter les autres
					print(f"RUN_BATCH_FAIL {e.id}: {exc}", file=sys.stderr)

	return _do_review(selected, args.force)


if __name__ == "__main__":
	sys.exit(main())
