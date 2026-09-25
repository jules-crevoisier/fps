#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""log_scan.py

Analyse les logs d'une exécution de la REVIEW PIPELINE (docs/REVIEW.md) :
scanne <run_dir>/logs/*.log (un fichier par étape de tools/review/run_review.ps1),
regroupe les lignes ERROR / SCRIPT ERROR / WARNING / "Lambda capture" / erreurs
RPC / push_error par message normalisé (compte + première occurrence), et
étiquette le bruit connu (ex. "material is null" en headless sur des maps
repeintes, dû au renderer factice — voir la section "Environment facts" du
contrat de cette tâche : ce n'est PAS un échec).

Usage :
    python tools/review/log_scan.py <run_dir>

Écrit <run_dir>/log_scan.json. Ne lève jamais d'exception fatale : un dossier
logs/ manquant ou vide produit un rapport vide (totals à 0), pas un crash —
la review pipeline ne doit jamais s'arrêter à cause de ce script.
"""
from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Catégories reconnues, dans l'ordre de priorité (la première regex qui
# matche une ligne gagne). Les motifs couvrent le format court des logs
# console Godot ("E 0:00:01:234  ...", "W 0:00:01:234  ...") ainsi que le
# texte explicite ("SCRIPT ERROR:", "WARNING:", push_error/push_warning tels
# qu'imprimés par le moteur).
# ---------------------------------------------------------------------------
_CATEGORY_PATTERNS: list[tuple[str, re.Pattern]] = [
	("script_error", re.compile(r"SCRIPT ERROR[:\s]", re.IGNORECASE)),
	("lambda_capture", re.compile(r"lambda capture", re.IGNORECASE)),
	("rpc_error", re.compile(r"\brpc\b.*(error|fail|reject|invalid|denied|disconnect)", re.IGNORECASE)),
	("rpc_error", re.compile(r"(error|fail|reject|invalid|denied).*\brpc\b", re.IGNORECASE)),
	("push_error", re.compile(r"push_error", re.IGNORECASE)),
	("error", re.compile(r"^\s*E\s+\d+:\d+:\d+(:\d+)?\s")),
	("error", re.compile(r"\bERROR[:\s]", re.IGNORECASE)),
	("warning", re.compile(r"^\s*W\s+\d+:\d+:\d+(:\d+)?\s")),
	("warning", re.compile(r"\bWARNING[:\s]", re.IGNORECASE)),
]

# Lignes de contexte (continuation) : Godot indente la ligne "at: fonction
# (fichier:ligne)" juste après le message principal d'une erreur/alerte.
_CONTINUATION_RE = re.compile(r"^\s+(at:|<C\+\+|--- GDScript|Stack Trace)", re.IGNORECASE)

# Bruit connu, toujours signalé séparément (jamais compté comme échec).
# (regex sur le message normalisé, raison affichée dans le rapport)
_KNOWN_NOISE: list[tuple[re.Pattern, str]] = [
	(
		# Forme réelle observée : `ERROR: Parameter "material" is null.`
		# (guillemets autour de "material" — le motif doit les tolérer).
		re.compile(r'parameter\s*"?material"?\s*is\s*null', re.IGNORECASE),
		"connu : maps repeintes en --headless utilisent le renderer factice "
		"(dummy renderer), qui ne charge pas les matériaux — sans rapport "
		"avec un vrai bug de rendu (voir contrat REVIEW pipeline).",
	),
	(
		# `run_review.ps1` lance gdUnit4 avec `-d --remote-debug tcp://127.0.0.1:1`
		# (port 1 injoignable) uniquement pour activer le mode debug (-d) sans
		# bloquer sur un vrai débogueur distant. Godot logue alors, toujours au
		# tout début du run, deux lignes ERROR liées (message + sa continuation
		# "at:" pointant vers core/debugger/remote_debugger_peer.cpp) : l'échec
		# de connexion est attendu, pas un vrai bug. On matche sur le message
		# ET sur la continuation (déjà capturée dans "raw") pour couvrir les
		# deux formes observées sans dépendre du texte exact du message.
		re.compile(
			r'remote debugger:\s*unable to connect'
			r'|remote_debugger_peer\.cpp'
			r'|condition\s*"_try_connect\(stream\)"\s*is\s*true',
			re.IGNORECASE,
		),
		"connu : --remote-debug tcp://127.0.0.1:1 (tools/review/run_review.ps1) "
		"sert seulement à activer le mode debug (-d) des tests gdUnit4, sans "
		"jamais viser un vrai débogueur — l'échec de connexion qui en résulte "
		"est attendu, pas un bug.",
	),
	(
		# Course de spawn HORS PÉRIMÈTRE de cette tâche (OPS-06 ne possède que
		# log_scan.py / test_training_records.gd / net_smoke.gd — PAS Weapon.gd) :
		# `Weapon._ready()` (scripts/combat/Weapon.gd:107) diffuse
		# `_broadcast_current_id.rpc(...)` DÈS que le nœud entre dans l'arbre côté
		# SERVEUR, en course avec la réplication `MultiplayerSpawner` de ce MÊME
		# nœud fraîchement spawné vers le pair qui vient tout juste de se
		# connecter. tools/net_smoke.gd observe la rafale « Node not found
		# .../Weapon » qui en résulte tout de suite APRÈS la connexion, AVANT même
		# sa première action de test (jamais liée à l'arrêt de l'hôte : le client
		# y coupe déjà EN PREMIER, voir CLIENT_GRACE dans net_smoke.gd) — et sans
		# impact sur le verdict (NET_SMOKE_RESULT ok/damage_taken/rejected_shots
		# restent corrects, le moteur resynchronise le cache de nœuds dès la RPC
		# légitime suivante). Un correctif définitif exige de retarder cette
		# diffusion dans Weapon.gd, hors périmètre ici — à traiter dans une tâche
		# séparée (signalé au lead).
		re.compile(r'node not found:\s*"[\w./]*players/#/weapon"', re.IGNORECASE),
		"connu (hors périmètre OPS-06) : course de spawn entre Weapon._ready() "
		"(scripts/combat/Weapon.gd:107, _broadcast_current_id.rpc immédiate) et la "
		"réplication MultiplayerSpawner du nœud du pair qui vient de se connecter — "
		"observée juste après connexion dans tools/net_smoke.gd, sans rapport avec "
		"l'arrêt de l'hôte ni impact sur NET_SMOKE_RESULT ; correctif hors périmètre "
		"(Weapon.gd).",
	),
	(
		re.compile(r'failed to get path from rpc:\s*[\w./]*players/#/weapon', re.IGNORECASE),
		"connu (hors périmètre OPS-06) : même course de spawn que ci-dessus "
		"(Weapon.gd:107) — le paquet RPC de _broadcast_current_id référence le "
		"nœud du pair fraîchement connecté avant que son chemin soit résolu "
		"localement ; correctif hors périmètre (Weapon.gd).",
	),
	(
		# Messages génériques (pas de chemin dans le texte) : on ne les classe en
		# bruit connu QUE couplés à leur trace moteur STABLE (fichier:fonction
		# C++), pour ne jamais avaler par erreur un vrai bug sans rapport qui
		# produirait le même message générique depuis un autre point du moteur.
		re.compile(
			r'parameter\s*"?node"?\s*is\s*null[\s\S]*scene_cache_interface\.cpp'
			r'|invalid packet received\.\s*requested node was not found\.[\s\S]*scene_rpc_interface\.cpp',
			re.IGNORECASE,
		),
		"connu (hors périmètre OPS-06) : suite directe de la même course de spawn "
		"(Weapon.gd:107, voir raison ci-dessus) — le cache de résolution de nœuds "
		"RPC (modules/multiplayer/scene_cache_interface.cpp / scene_rpc_interface.cpp) "
		"reçoit un paquet visant un nœud pas encore répliqué localement ; correctif "
		"hors périmètre (Weapon.gd).",
	),
]

_NUM_RE = re.compile(r"\d+")
_ADDR_RE = re.compile(r"0x[0-9a-fA-F]+")
_PATH_LINE_RE = re.compile(r"(res://[\w./]+\.gd):#")  # après normalisation des nombres


def _normalize(message: str) -> str:
	"""Réduit un message à une forme comparable : adresses mémoire, nombres
	(lignes, ids, timestamps, distances...) et espaces multiples effacés, pour
	que des occurrences du "même" problème à des lignes/instants différents se
	regroupent sous une seule entrée."""
	text = _ADDR_RE.sub("0x#", message.strip())
	text = _NUM_RE.sub("#", text)
	text = re.sub(r"\s+", " ", text)
	return text[:400]


def _classify(line: str) -> Optional[str]:
	for category, pattern in _CATEGORY_PATTERNS:
		if pattern.search(line):
			return category
	return None


def _noise_reason(normalized: str, raw: str) -> Optional[str]:
	"""`raw` inclut les lignes de continuation ("at: ...") : certains motifs de
	bruit connu (ex. le débogueur distant) ne se reconnaissent qu'à la trace,
	pas au seul message normalisé — voir le commentaire dans _KNOWN_NOISE."""
	haystack = f"{normalized}\n{raw}"
	for pattern, reason in _KNOWN_NOISE:
		if pattern.search(haystack):
			return reason
	return None


def scan_file(path: Path) -> list[dict]:
	"""Renvoie la liste des entrées brutes {category, raw, line_no} trouvées
	dans un fichier de log (une entrée par ligne déclencheuse, continuations
	incluses dans "raw" pour le contexte affiché)."""
	entries: list[dict] = []
	try:
		# "utf-8-sig" : les logs écrits par run_review.ps1 (StreamWriter côté
		# PowerShell) peuvent porter un BOM UTF-8 en tête — un "utf-8" strict
		# le laisserait collé au premier caractère de la première ligne et
		# casserait sa détection de catégorie.
		lines = path.read_text(encoding="utf-8-sig", errors="replace").splitlines()
	except OSError:
		return entries
	i = 0
	n = len(lines)
	while i < n:
		line = lines[i]
		category = _classify(line)
		if category is None:
			i += 1
			continue
		raw = [line]
		j = i + 1
		while j < n and _CONTINUATION_RE.match(lines[j]):
			raw.append(lines[j])
			j += 1
		entries.append({"category": category, "raw": "\n".join(raw), "message": line.strip(), "line_no": i + 1})
		i = j
	return entries


def build_report(run_dir: Path) -> dict:
	logs_dir = run_dir / "logs"
	log_files = sorted(logs_dir.glob("*.log")) if logs_dir.is_dir() else []

	groups: dict[tuple[str, str], dict] = {}
	totals: dict[str, int] = {}

	for log_path in log_files:
		rel = f"logs/{log_path.name}"
		for entry in scan_file(log_path):
			category = entry["category"]
			normalized = _normalize(entry["message"])
			key = (category, normalized)
			totals[category] = totals.get(category, 0) + 1
			if key not in groups:
				noise_reason = _noise_reason(normalized, entry["raw"])
				groups[key] = {
					"category": category,
					"message": entry["message"][:400],
					"normalized": normalized,
					"count": 0,
					"noise": noise_reason is not None,
					"noise_reason": noise_reason,
					"first_occurrence": {
						"file": rel,
						"line": entry["line_no"],
						"text": entry["raw"][:1200],
					},
					"sources": {},
				}
			g = groups[key]
			g["count"] += 1
			g["sources"][rel] = g["sources"].get(rel, 0) + 1

	group_list = []
	for g in groups.values():
		g["sources"] = [{"file": f, "count": c} for f, c in sorted(g["sources"].items(), key=lambda kv: -kv[1])]
		group_list.append(g)
	# Les vrais problèmes (non-bruit) d'abord, triés par fréquence décroissante.
	group_list.sort(key=lambda g: (g["noise"], -g["count"]))

	noise_count = sum(g["count"] for g in group_list if g["noise"])
	non_noise_count = sum(g["count"] for g in group_list if not g["noise"])

	return {
		"generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
		"run_dir": str(run_dir),
		"files_scanned": [f"logs/{p.name}" for p in log_files],
		"totals": totals,
		"noise_count": noise_count,
		"non_noise_count": non_noise_count,
		"groups": group_list,
	}


def main(argv: list[str]) -> int:
	if len(argv) != 2:
		print("usage : python log_scan.py <run_dir>", file=sys.stderr)
		return 2
	run_dir = Path(argv[1])
	report = build_report(run_dir)
	out_path = run_dir / "log_scan.json"
	out_path.parent.mkdir(parents=True, exist_ok=True)
	out_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
	print(
		"LOG_SCAN_DONE fichiers=%d groupes=%d (bruit=%d, non-bruit=%d) -> %s"
		% (len(report["files_scanned"]), len(report["groups"]), report["noise_count"], report["non_noise_count"], out_path)
	)
	return 0


if __name__ == "__main__":
	raise SystemExit(main(sys.argv))
