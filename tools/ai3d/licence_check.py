#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/ai3d/licence_check.py
Garde-fou de licence pour les assets 3D (voir docs/research/06_ai_3d_pipeline.md
§10 et §A6). Deux règles, indépendantes l'une de l'autre :

1. Tout fichier de modèle 3D sous `assets/models/**` doit être traçable : soit
   il a une ligne dans `THIRD_PARTY_LICENSES.md` (colonne « Chemin », lue comme
   un motif glob — ex. `assets/models/characters/*.glb` couvre tout le
   dossier), soit il a une provenance à côté de lui,
   `<nom_du_fichier>.provenance.json` (même convention que
   `tools/ai3d/run_batch.py::provenance_path`). Sans l'un des deux, le fichier
   sort du contrôle de licence : on ne sait plus dire d'où il vient.
2. Si une provenance existe, son contenu ne doit citer AUCUN outil de la liste
   noire : **Hunyuan3D** (toutes versions — licence qui exclut l'UE/le
   Royaume-Uni/la Corée du Sud, voir docs/research/06_ai_3d_pipeline.md §A1),
   **FLUX.1 dev** (licence non commerciale, à ne pas confondre avec FLUX.1
   schnell qui est autorisé), **Qwen-Image-2.1** (licence de recherche, à ne
   pas confondre avec Qwen-Image-2512 qui est autorisé). La recherche se fait
   sur tout le JSON (n'importe quel champ), insensible à la casse ET à la
   ponctuation (« black-forest-labs/FLUX.1-dev », « flux.1-dev », « flux1-dev »
   sont tous reconnus comme le même modèle interdit — voir `_normalize`).

Un fichier peut violer la règle 1, la règle 2, ou les deux ; chaque violation
trouvée est rapportée (jamais seulement la première), pour corriger en un
seul passage.

Usage :
    python tools/ai3d/licence_check.py
    python tools/ai3d/licence_check.py --root D:/autre_checkout
    python tools/ai3d/licence_check.py --models-dir tests/fixtures/models --licences tests/fixtures/THIRD_PARTY_LICENSES.md
    python tools/ai3d/licence_check.py --selftest   # fixtures internes de la liste noire, aucun asset réel touché

Code de sortie : 0 si aucune violation, 1 sinon (rien n'est jamais modifié :
c'est un contrôle, pas un correcteur).
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# Formats de modèle 3D concernés par la traçabilité. Les fichiers annexes
# (`.import` généré par Godot, `.provenance.json` lui-même, rapports de build
# `.json` des scripts Blender, images de référence `.jpg`/`.png`) ne sont pas
# des assets 3D et ne sont pas scannés ici.
MODEL_EXTENSIONS = {".glb", ".gltf", ".fbx", ".obj"}

# Liste noire (docs/research/06_ai_3d_pipeline.md §10 et §A1/§A3) : recherche
# en sous-chaîne, insensible à la casse ET à la ponctuation, sur tout le JSON de
# provenance (voir `_normalize` / `_find_banned_term` ci-dessous). Les vrais
# identifiants rencontrés en pratique varient dans leur ponctuation sans que le
# modèle change : « black-forest-labs/FLUX.1-dev », « flux.1-dev », « flux1-dev »
# doivent tous être reconnus comme le même FLUX.1 [dev] interdit ; « Hunyuan3D-2.1 »,
# « hunyuan_3d_2.0 » doivent tous matcher « hunyuan » quelle que soit la version.
BANNED_PROVENANCE_TERMS = ("hunyuan", "flux.1-dev", "qwen-image-2.1")

_SEPARATOR_CELL_RE = re.compile(r":?-+:?")
_BACKTICK_RE = re.compile(r"`([^`]+)`")
_NON_ALNUM_RE = re.compile(r"[^a-z0-9]+")


def _normalize(text: str) -> str:
	"""Réduit une chaîne à ses seuls caractères alphanumériques en minuscules,
	pour comparer deux identifiants malgré des séparateurs différents (`.`, `-`,
	`_`, `/`, espace) : « FLUX.1-dev », « flux1-dev » et
	« black-forest-labs/FLUX.1-dev » deviennent tous "...flux1dev"."""
	return _NON_ALNUM_RE.sub("", text.lower())


_BANNED_NORMALIZED = tuple((term, _normalize(term)) for term in BANNED_PROVENANCE_TERMS)


@dataclass
class Violation:
	"""Une violation trouvée sur un fichier : chemin du modèle et raison lisible."""

	model_path: Path
	reason: str


def provenance_path_for(model_path: Path) -> Path:
	"""Même convention que `run_batch.py::provenance_path` : la provenance
	d'un modèle est son nom de fichier suivi de `.provenance.json`, à côté de lui."""
	return model_path.parent / f"{model_path.stem}.provenance.json"


def iter_model_files(models_dir: Path):
	"""Tous les fichiers de modèle 3D sous `models_dir`, triés pour un rapport stable."""
	if not models_dir.is_dir():
		return
	for path in sorted(models_dir.rglob("*")):
		if path.is_file() and path.suffix.lower() in MODEL_EXTENSIONS:
			yield path


def _is_separator_row(cells: list) -> bool:
	return bool(cells) and all(_SEPARATOR_CELL_RE.fullmatch(c) for c in cells)


def _extract_path(cell: str) -> str:
	"""Lit le contenu d'une cellule « Chemin » : le texte entre backticks s'il y en
	a, sinon la cellule telle quelle. Rejette ce qui ne ressemble pas à un chemin
	(ex. `(runtime)`) : un tel texte ne peut de toute façon couvrir aucun fichier."""
	match = _BACKTICK_RE.search(cell)
	text = (match.group(1) if match else cell).strip()
	if not text or "/" not in text or " " in text:
		return ""
	return text.replace("\\", "/")


def parse_licence_paths(licences_path: Path) -> list:
	"""Extrait les motifs de chemin (glob) de la colonne « Chemin » de chaque
	tableau Markdown de THIRD_PARTY_LICENSES.md (il peut y en avoir plusieurs,
	ex. « Livré avec le jeu » et « Outils de développement »)."""
	if not licences_path.is_file():
		return []
	patterns = []
	chemin_index = None
	for raw_line in licences_path.read_text(encoding="utf-8").splitlines():
		line = raw_line.strip()
		if not line.startswith("|"):
			chemin_index = None
			continue
		cells = [c.strip() for c in line.strip("|").split("|")]
		if _is_separator_row(cells):
			continue
		if chemin_index is None:
			lowered = [c.lower() for c in cells]
			if "chemin" in lowered:
				chemin_index = lowered.index("chemin")
			continue
		if chemin_index >= len(cells):
			continue
		path = _extract_path(cells[chemin_index])
		if path:
			patterns.append(path)
	return patterns


def _matches_any(rel_path: str, patterns: list) -> bool:
	return any(fnmatch.fnmatchcase(rel_path, pattern) for pattern in patterns)


def _find_banned_term(provenance_data) -> str:
	"""Cherche un terme de la liste noire n'importe où dans le JSON de
	provenance (tous les champs, valeurs imbriquées comprises), en ignorant la
	casse et la ponctuation (voir `_normalize`) pour reconnaître les variantes
	réelles d'un même identifiant (« flux.1-dev », « flux1-dev », « FLUX.1-dev »
	dans un chemin type « black-forest-labs/FLUX.1-dev »). Retourne le terme de
	`BANNED_PROVENANCE_TERMS` trouvé (forme lisible, pour le message d'erreur),
	ou une chaîne vide si aucun ne matche."""
	blob = _normalize(json.dumps(provenance_data, ensure_ascii=False))
	for term, normalized in _BANNED_NORMALIZED:
		if normalized in blob:
			return term
	return ""


def check_assets(models_dir: Path, root: Path, licence_patterns: list) -> list:
	"""Applique les deux règles à chaque modèle 3D sous `models_dir`.
	Retourne la liste des violations (vide si tout est en règle)."""
	violations = []
	for model_path in iter_model_files(models_dir):
		try:
			rel_path = model_path.relative_to(root).as_posix()
		except ValueError:
			rel_path = model_path.as_posix()

		prov_path = provenance_path_for(model_path)
		if not prov_path.is_file():
			if not _matches_any(rel_path, licence_patterns):
				violations.append(Violation(
					model_path,
					f"aucune ligne dans THIRD_PARTY_LICENSES.md ni provenance ({prov_path.name})",
				))
			continue

		try:
			provenance_data = json.loads(prov_path.read_text(encoding="utf-8"))
		except (OSError, json.JSONDecodeError) as exc:
			violations.append(Violation(
				model_path,
				f"provenance illisible ({prov_path.name}) : {exc}",
			))
			continue

		banned_term = _find_banned_term(provenance_data)
		if banned_term:
			violations.append(Violation(
				model_path,
				f"provenance cite un outil interdit ({banned_term}) dans {prov_path.name}",
			))
	return violations


# Fixtures de la liste noire : une entrée par forme réelle rencontrée dans les
# provenances (voir docs/research/06_ai_3d_pipeline.md §A1/§A3 et la revue QA de
# A3D-09). Chaque forme interdite doit être détectée malgré sa ponctuation ;
# chaque forme AUTORISÉE voisine (le modèle « frère » réellement permis, à ne
# pas confondre avec l'interdit) ne doit PAS déclencher de faux positif.
# `--selftest` exécute ces fixtures sans toucher aux vrais assets du dépôt.
_SELFTEST_FIXTURES = (
	# (nom de fixture, JSON de provenance, terme banni attendu ou "" si autorisé)
	("hunyuan_2_1", {"tool": "Hunyuan3D-2.1", "date": "2026-01-01"}, "hunyuan"),
	("hunyuan_underscored", {"tool": "hunyuan_3d_2.0", "date": "2026-01-01"}, "hunyuan"),
	("flux_dot_form", {"tool": "flux.1-dev", "date": "2026-01-01"}, "flux.1-dev"),
	("flux_no_sep_form", {"tool": "flux1-dev", "date": "2026-01-01"}, "flux.1-dev"),
	(
		"flux_full_repo_id",
		{"image_prompt": "black-forest-labs/FLUX.1-dev", "date": "2026-01-01"},
		"flux.1-dev",
	),
	("qwen_image_2_1", {"tool": "qwen-image-2.1", "date": "2026-01-01"}, "qwen-image-2.1"),
	(
		"qwen_image_2_1_spaced",
		{"tool": "Qwen Image 2.1", "date": "2026-01-01"},
		"qwen-image-2.1",
	),
	# Autorisés : ne doivent déclencher AUCUN terme banni malgré la ressemblance.
	("flux_schnell_allowed", {"tool": "flux1-schnell", "date": "2026-01-01"}, ""),
	("qwen_image_2512_allowed", {"tool": "qwen-image-2512", "date": "2026-01-01"}, ""),
	("sdxl_allowed", {"tool": "sdxl-base", "date": "2026-01-01"}, ""),
)


def run_selftest() -> bool:
	"""Vérifie la détection de la liste noire sur une fixture par forme
	d'identifiant (voir `_SELFTEST_FIXTURES`), dans un dossier temporaire — les
	vrais assets du dépôt ne sont jamais touchés. Affiche un rapport et
	retourne True si toutes les fixtures se comportent comme attendu."""
	import tempfile

	ok = True
	with tempfile.TemporaryDirectory(prefix="licence_check_selftest_") as tmp:
		tmp_root = Path(tmp)
		models_dir = tmp_root / "assets" / "models"
		models_dir.mkdir(parents=True)
		licences_path = tmp_root / "THIRD_PARTY_LICENSES.md"
		licences_path.write_text("# vide : les fixtures passent toutes par provenance.json\n", encoding="utf-8")

		for name, provenance, _expected in _SELFTEST_FIXTURES:
			model_path = models_dir / f"{name}.glb"
			model_path.write_bytes(b"")
			prov_path = provenance_path_for(model_path)
			prov_path.write_text(json.dumps(provenance, ensure_ascii=False), encoding="utf-8")

		violations_by_name = {}
		for violation in check_assets(models_dir, tmp_root, []):
			violations_by_name[violation.model_path.stem] = violation.reason

		for name, _provenance, expected_term in _SELFTEST_FIXTURES:
			reason = violations_by_name.get(name)
			if expected_term:
				if reason is None or expected_term not in reason:
					ok = False
					print(
						f"SELFTEST_FAIL {name}: attendu un rejet citant « {expected_term} », obtenu : {reason!r}",
						file=sys.stderr,
					)
				else:
					print(f"SELFTEST_OK {name}: rejeté ({expected_term})")
			else:
				if reason is not None:
					ok = False
					print(
						f"SELFTEST_FAIL {name}: attendu autorisé, obtenu un rejet : {reason!r}",
						file=sys.stderr,
					)
				else:
					print(f"SELFTEST_OK {name}: autorisé")

	if ok:
		print(f"SELFTEST_SUMMARY {len(_SELFTEST_FIXTURES)} fixture(s), 0 échec")
	else:
		print("SELFTEST_SUMMARY échec — voir SELFTEST_FAIL ci-dessus", file=sys.stderr)
	return ok


def parse_args(argv=None) -> argparse.Namespace:
	p = argparse.ArgumentParser(description="Garde-fou de licence des assets 3D — voir docs/research/06_ai_3d_pipeline.md")
	p.add_argument("--root", type=Path, default=ROOT, help="racine du dépôt (défaut : dépôt courant)")
	p.add_argument("--models-dir", type=Path, default=None, help="dossier des modèles 3D (défaut : <root>/assets/models)")
	p.add_argument("--licences", type=Path, default=None, help="fichier THIRD_PARTY_LICENSES.md (défaut : <root>/THIRD_PARTY_LICENSES.md)")
	p.add_argument(
		"--selftest",
		action="store_true",
		help="vérifie la liste noire sur des fixtures internes (une par forme d'identifiant) au lieu de scanner les vrais assets",
	)
	return p.parse_args(argv)


def main(argv=None) -> int:
	args = parse_args(argv)
	if args.selftest:
		return 0 if run_selftest() else 1
	root = args.root.resolve()
	models_dir = (args.models_dir if args.models_dir is not None else root / "assets" / "models").resolve()
	licences_path = (args.licences if args.licences is not None else root / "THIRD_PARTY_LICENSES.md").resolve()

	licence_patterns = parse_licence_paths(licences_path)
	violations = check_assets(models_dir, root, licence_patterns)
	scanned = sum(1 for _ in iter_model_files(models_dir))

	if violations:
		for violation in violations:
			try:
				rel = violation.model_path.relative_to(root).as_posix()
			except ValueError:
				rel = violation.model_path.as_posix()
			print(f"LICENCE_CHECK_FAIL {rel}: {violation.reason}", file=sys.stderr)
		print(
			f"LICENCE_CHECK_SUMMARY {len(violations)} violation(s) sur {scanned} fichier(s) scanné(s)",
			file=sys.stderr,
		)
		return 1

	print(f"LICENCE_CHECK_OK {scanned} fichier(s) scanné(s), 0 violation")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
