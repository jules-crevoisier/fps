## tools/blender/ai_import_painted.py
## Import "peinture conservée" d'un repère Tripo Studio déjà exporté en .glb (voir
## docs/art/WASTELAND_ART_RESET.md, tâche ART-80) — remplace, pour les assets
## d'ENVIRONNEMENT peints, le chemin de tools/blender/ai_restyle.py qui JETTE la
## texture IA (remplacée par une couleur de palette plate) et remesh en voxel :
## deux opérations qui ont mutilé ces mêmes repères à la vague 1 (treillis fondus,
## voir docs/research/09_wasteland_vertical_slice.md §7 : derrick amputé à 0,92 m,
## grue coupée à 3,15 m, château d'eau facetté). Ce script ne modifie JAMAIS le
## fichier source (import en mémoire, comme turntable.py/check_asset.py/ai_restyle.py).
##
##   blender -b --factory-startup --python-exit-code 1 -P tools/blender/ai_import_painted.py -- \
##       --in assets/incoming/tripo/studio/wl_water_tower.glb --height-m 10.0 \
##       --budget-tris 6000 --texture-size 2048 \
##       --out assets/models/props/wasteland/tripo/wl_water_tower.glb
##
##   # ou piloté par le manifeste (tous les repères) :
##   blender -b --factory-startup --python-exit-code 1 -P tools/blender/ai_import_painted.py -- \
##       --manifest tools/ai3d/manifests/painted_env.yaml --all
##
## Pipeline (docs/art/WASTELAND_ART_RESET.md, notes de tâche ART-80) :
##   1. import                 .glb -> un seul objet mesh (fusionne si Tripo Studio a
##                              livré plusieurs sous-objets, comme toonkit.join).
##   2. nettoyage               fusion des sommets quasi confondus (bruit de
##                              triangulation IA, `merge_by_distance`, même mesure
##                              relative que ai_restyle.py) PUIS doublons de face
##                              exacts et éclats non-manifold stricts, VÉRIFIÉS
##                              anti-fracture sur copie (`repair_nonmanifold_edges`/
##                              `_repair_slivers_if_safe` — mêmes deux passes que
##                              ai_restyle.py::repair_nonmanifold_edges, dupliquées ici ;
##                              vérification QA ART-80 : les doublons seuls laissaient
##                              10 à 842 arêtes non-manifold selon le repère) PUIS
##                              retrait des îlots dont la diagonale de bbox est < 1 % de
##                              celle de l'objet entier (`remove_small_islands` — SEUIL
##                              ABSOLU, contrairement au clustering par proximité de
##                              ai_restyle.py::remove_isolated_islands, voir sa
##                              docstring : ce script ne vise que des repères dont les
##                              assemblages légitimes (jambes de derrick, mât de grue)
##                              restent chacun largement au-dessus de 1 %). AUCUN
##                              retrait par simple ÉCART (bbox à bbox) au corps
##                              principal ici : trois tentatives successives (sondage
##                              QA ART-80, corrigé dans CETTE tâche) ont chacune fini
##                              par amputer un repère réel (jambes du derrick, flèche
##                              de la grue, barreaux d'échelle du château d'eau, pieds
##                              du panneau essence) — sur ces exports Tripo Studio, un
##                              membre structurel LÉGITIME est presque aussi souvent un
##                              îlot séparé (jamais vertex-welded) qu'un vrai débris
##                              fantôme, et aucune heuristique géométrique locale ne
##                              les distingue de façon fiable (voir
##                              `detect_floating_islands`, qui ne fait plus que
##                              SIGNALER cet écart, jamais le retirer — même
##                              conclusion, déjà documentée, que ai_restyle.py::
##                              _drop_floating_islands pour ces mêmes repères).
##   3. matériau peint          CHAQUE matériau importé qui porte une image Base Color
##                              est CONSERVÉ (jamais remplacé par une couleur de
##                              palette) : le graphe de nœuds est simplement nettoyé
##                              (Principled BSDF <- Image Texture, rien d'autre — les
##                              cartes normal/occlusion/metallic-roughness qu'un GLB
##                              IA peut aussi porter, jamais lues par ink_toon.gdshader,
##                              sont retirées) et l'image redimensionnée SANS jamais la
##                              quantifier (`keep_painted_materials`/
##                              `resolved_texture_size` — 1024 ou 2048, jamais agrandie
##                              au-delà de sa taille d'origine).
##   4. (aucun remesh)          contrairement à ai_restyle.py : ces repères sortent déjà
##                              d'un Smart Mesh propre (2,4-5,6 k tris, WASTELAND_ART_
##                              RESET.md) — un remesh voxel GLOBAL fondrait le treillis
##                              ajouré (releve concret de tâche, voir l'en-tête de
##                              painted_env.yaml) sans nécessité : le nettoyage de
##                              l'étape 2 suffit à une géométrie déjà propre.
##   5. budget                  Decimate COLLAPSE itératif jusqu'au budget de tris du
##                              manifeste (`decimate_to_budget`, même algorithme que
##                              ai_restyle.py, dupliqué ici à dessein — voir la
##                              docstring de `_apply_modifier` dans ai_restyle.py :
##                              "ce fichier ne doit dépendre que de l'API PUBLIQUE de
##                              toonkit", jamais d'un import croisé entre scripts
##                              frères). No-op si déjà sous le budget (cas courant ici).
##   6. normales/masques         toonkit.weighted_normals + smooth_normal_attrs (coque
##                              de contour) + bake_vertex_ao + curvature_edge_mask —
##                              mêmes couleurs de sommet AO+Curvature que les autres
##                              props peints (docs/3D_PIPELINE.md), PAS le masque
##                              unifié `masks` v3 (celui-ci vise les 4 slots
##                              base/accent/metal/sign d'un générateur bpy maison,
##                              pas un repère Tripo à texture unique).
##   7. échelle/origine          échelle UNIFORME (`scale_obj_uniform_to_height`) vers
##                              la cote du manifeste (axe vertical, Z Blender / Y après
##                              export), puis toonkit.apply_transforms +
##                              toonkit.set_origin_bottom (pivot au sol centré — même
##                              ordre que ai_restyle.py::restyle, étape 7).
##   7bis. réparation finale     `_final_repair_pass` — même rationale A3D-15 que
##                              ai_restyle.py::_repair_nonmanifold_final : ressoudage
##                              par position + triangulation des n-gones (topologie
##                              EXACTEMENT celle que l'export produira), PUIS doublons
##                              + éclats non-manifold non stricts, VÉRIFIÉS anti-
##                              fracture sur copie (même garde que l'étape 2 ci-dessus ;
##                              wl_crane_lattice, dont le treillis brut porte plusieurs
##                              centaines d'arêtes non-manifold, reste une exemption
##                              CONSTATÉE — jamais devinée à l'avance par un plafond —
##                              plutôt que forcée). AUCUN retrait d'îlot ici (contraste
##                              volontaire avec l'étape 2 : les seuls îlots présents à
##                              ce stade sont ceux que ce nettoyage vient lui-même de
##                              produire, jamais des fragments fantômes d'origine).
##   8. export + revue           toonkit.export_glb (rapport JSON tris/attributs) puis
##                              un sidecar propre à CE script (`_augment_sidecar` :
##                              ajoute "painted": true et "source" au même fichier
##                              JSON, sans dupliquer un second fichier) + le turntable
##                              (tools/blender/turntable.py, sous-process Blender dédié,
##                              comme ai_restyle.py::run_turntable).
##
## Ce fichier importe `bpy`/`bmesh` dans un bloc try/except (contrairement à
## ai_restyle.py/turntable.py/check_asset.py, qui les importent sans garde) : la lecture
## du manifeste YAML et les calculs purs (`parse_manifest`, `scale_factor_for_height`,
## `resolved_texture_size`, `resolve_manifest_entry`) ne dépendent d'AUCUN état Blender
## et sont donc testables par un simple `python -m pytest` (rapide, sans sous-process
## Blender) — voir tools/blender/tests/test_ai_import_painted.py, qui ne lance Blender
## qu'UNE fois, pour les cas qui manipulent réellement une mesh. Toute fonction qui
## suit `import bpy` dans ce fichier reste, elle, strictement dépendante de Blender
## (jamais appelée hors de `main()`/des tests en sous-process) — aucune divergence de
## comportement à l'intérieur de Blender, seulement une frontière d'import plus
## permissive qu'ailleurs dans ce dossier.
from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys

try:
	import bpy
	import bmesh
	from mathutils import Vector
except ImportError:  # pragma: no cover - permet de tester la logique manifeste hors Blender
	bpy = None
	bmesh = None
	Vector = None

if bpy is not None:
	sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
	import toonkit  # noqa: E402

# ---------------------------------------------------------------------------
# Constantes (mêmes mesures relatives que ai_restyle.py, dupliquées à dessein —
# voir l'en-tête de ce fichier)
# ---------------------------------------------------------------------------

MERGE_DIST_RATIO = 0.0005        # fraction de la diagonale de bbox pour la fusion de sommets
MIN_ISLAND_RATIO = 0.01          # ART-80 : îlot < 1 % de la diagonale totale -> retiré
DECIMATE_MAX_ITERATIONS = 6
DECIMATE_PLANAR_ANGLE_LIMIT = 0.0872665  # ~5 degres (radians)
DECIMATE_STALL_RATIO = 0.99
DEFAULT_BUDGET_TRIS = 6000       # ART-80 : plafond dur, chaque repère <= 6000 tris
DEFAULT_TEXTURE_SIZE = 2048
ALLOWED_TEXTURE_SIZES = (1024, 2048, 4096)  # 4096 : Saloon long v4 (16 m de façade, ART-93)
TURNTABLE_SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "turntable.py")

# Vérification QA ART-80 (check_asset.py réel sur les 7 repères Tripo Studio
# livrés) : 6 des 7 fichiers échouaient CHK-16 (pièce déconnectée de qq
# sommets — 8/12/16/20/24 selon le cas — jusqu'à 6 à 10,9 m du corps principal
# sur wl_oil_derrick, 16 m de haut) et/ou l'arête non-manifold (10 à 842
# arêtes selon l'asset) : du bruit de génération IA (triangles superposés)
# pour l'arête non-manifold, mais PAS du bruit pour CHK-16 — vérifié par
# sondage (rendu `render_textured_preview` avant/après trois tentatives de
# retrait automatique, voir `detect_floating_islands`) : sur ces exports
# Tripo Studio, un membre structurel LÉGITIME (jambe de derrick, flèche de
# grue, barreau d'échelle, pied de panneau) est presque aussi souvent un
# îlot séparé — jamais vertex-welded au corps — qu'un vrai débris fantôme ;
# CHK-16 reste donc un écart RÉEL, documenté (`detect_floating_islands`),
# jamais silencieusement corrigé par un retrait de géométrie. Les constantes
# ci-dessous portent la réparation qui, elle, EST sûre et vérifiée
# (`repair_nonmanifold_edges`, `_final_repair_pass`) — mêmes valeurs que
# check_asset.py/ai_restyle.py, JAMAIS inventées ici (voir la docstring de
# chaque fonction).
FLOATING_GAP_TOLERANCE_M = 0.01  # CHK-16 : EXACTEMENT la tolérance de check_asset.py::check_object
_SLIVER_AREA_RATIO = 0.05        # ai_restyle.py::_remove_nonmanifold_slivers, dupliqué ici
_CHECK_ASSET_WELD_DIST_M = 1e-4  # EXACTEMENT le ressoudage de check_asset.py::check_object (bm_welded)

# Sondage ART-80 (avant cette correction) : un maillage Tripo Studio brut peut
# être SI dégradé (wl_crane_lattice : 842 arêtes non-manifold sur son PROPRE
# treillis) qu'UNE ou PLUSIEURS de ces arêtes en excès ne sont pas un vrai
# doublon local mais l'UNIQUE lien topologique entre deux morceaux du même
# treillis — les retirer (même en mode « strict », voir
# `_remove_nonmanifold_slivers`) FRACTURE alors le maillage en îlots
# supplémentaires (relevé concret : 179 -> 184 îlots en mode strict, corps
# principal 1074 -> 1039 faces ; 179 -> 274 îlots et corps principal
# 1074 -> 716 faces en mode non strict) — exactement la mutilation qu'ART-80
# existe pour éviter (voir l'en-tête de ce fichier). Aucun seuil de COMPTE ou
# de RATIO d'arêtes ne distingue fiablement à l'avance un nettoyage sûr d'un
# nettoyage fracturant (un défaut ponctuel de 3 arêtes peut, par malchance,
# être lui aussi la seule attache d'un îlot) : `_repair_slivers_if_safe`
# VÉRIFIE donc le résultat sur une COPIE du maillage (`bmesh.copy`) avant de
# commiter quoi que ce soit — jamais un plafond deviné.



# ---------------------------------------------------------------------------
# Fonctions pures (aucune dépendance bpy) — manifeste + calculs scalaires.
# ---------------------------------------------------------------------------

_TOP_SCALAR_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$")
_LIST_ITEM_RE = re.compile(r"^-\s+([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$")
_LIST_CONT_RE = re.compile(r"^\s+([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$")
_INT_RE = re.compile(r"^[+-]?\d+$")
_FLOAT_RE = re.compile(r"^[+-]?(\d+\.\d*|\.\d+|\d+)([eE][+-]?\d+)?$")


def _parse_scalar(raw: str):
	"""Convertit une valeur scalaire brute (texte à droite du ':') vers son type
	Python — sous-ensemble volontairement restreint de YAML (voir la docstring
	de `parse_manifest`) : chaîne entre quotes simples (`''` -> `'`, échappement
	YAML standard) ou doubles, `true`/`false`/`null`/`~`, entier, flottant, sinon
	une chaîne brute telle quelle (jamais une erreur — un futur champ texte non
	quoté reste lisible)."""
	s = raw.strip()
	if not s:
		return ""
	if len(s) >= 2 and s[0] == "'" and s[-1] == "'":
		return s[1:-1].replace("''", "'")
	if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
		return s[1:-1].replace('\\"', '"')
	if s in ("true", "True"):
		return True
	if s in ("false", "False"):
		return False
	if s in ("null", "~", "None"):
		return None
	if _INT_RE.match(s):
		return int(s)
	if _FLOAT_RE.match(s):
		return float(s)
	return s


def parse_manifest(text: str) -> dict:
	"""Parseur d'un sous-ensemble STRICT de YAML — suffisant pour le schéma FIXE
	de painted_env.yaml (voir son en-tête) : des scalaires top-level, puis une
	clé `assets:` suivie d'une liste d'items (`- id: ...` puis des lignes
	`  clé: valeur` indentées, une par champ). Aucune autre imbrication n'est
	supportée — délibéré : `ai_import_painted.py` tourne DANS l'interpréteur
	Python embarqué de Blender, qui n'a PAS `pyyaml` installé (contrairement à
	tools/ai3d/restyle_wave.py/run_batch.py, des scripts Python "normaux" — voir
	l'en-tête de ce fichier). Une ligne de commentaire (`#...`) ou vide est
	ignorée partout ; AUCUN commentaire en fin de ligne de données n'est
	supporté (ambigu avec un '#' dans une chaîne non quotée) — painted_env.yaml
	n'en porte jamais. Lève `ValueError` sur toute ligne qui ne correspond à
	aucun des trois patrons attendus, avec la ligne fautive dans le message."""
	top: dict = {}
	assets: list = []
	current: dict | None = None
	in_assets = False
	for raw_line in text.splitlines():
		line = raw_line.rstrip("\n")
		stripped = line.strip()
		if not stripped or stripped.startswith("#"):
			continue
		if not in_assets:
			if stripped == "assets:":
				in_assets = True
				continue
			m = _TOP_SCALAR_RE.match(line)
			if not m:
				raise ValueError(f"painted_env.yaml: ligne top-level invalide: {raw_line!r}")
			top[m.group(1)] = _parse_scalar(m.group(2))
			continue
		m_item = _LIST_ITEM_RE.match(line)
		if m_item:
			if current is not None:
				assets.append(current)
			current = {m_item.group(1): _parse_scalar(m_item.group(2))}
			continue
		m_cont = _LIST_CONT_RE.match(line)
		if m_cont and current is not None:
			current[m_cont.group(1)] = _parse_scalar(m_cont.group(2))
			continue
		raise ValueError(f"painted_env.yaml: ligne inattendue dans 'assets': {raw_line!r}")
	if current is not None:
		assets.append(current)
	top["assets"] = assets
	return top


def resolve_manifest_entry(manifest: dict, asset_id: str) -> dict:
	"""Entrée de `manifest["assets"]` dont `id` == `asset_id` — lève `KeyError`
	(message listant les ids connus) si absente, jamais un `None` silencieux."""
	for entry in manifest.get("assets", []):
		if entry.get("id") == asset_id:
			return entry
	known = sorted(e.get("id", "?") for e in manifest.get("assets", []))
	raise KeyError(f"ai_import_painted: id \"{asset_id}\" absent du manifeste (connus: {known})")


def scale_factor_for_height(current_height_m: float, target_height_m: float) -> float:
	"""Facteur d'échelle UNIFORME (mêmes trois axes) pour porter une hauteur
	`current_height_m` à `target_height_m` — pure arithmétique, voir
	`scale_obj_uniform_to_height` pour l'application réelle sur un objet bpy."""
	if current_height_m <= 0:
		raise ValueError(f"ai_import_painted: hauteur courante invalide ({current_height_m})")
	if target_height_m <= 0:
		raise ValueError(f"ai_import_painted: hauteur cible invalide ({target_height_m})")
	return target_height_m / current_height_m


def resolved_texture_size(original_size: int, requested_size: int) -> int:
	"""Taille de texture finale : jamais un agrandissement au-delà de l'ORIGINAL
	(un up-scale n'ajoute aucun détail, juste du poids — ART-80 : « redimensionné
	1024 ou 2048, jamais quantifié »), et toujours l'une des deux tailles
	standard `ALLOWED_TEXTURE_SIZES` quand l'original le permet. Si l'original
	est plus petit que la plus petite taille standard (cas dégénéré, jamais
	rencontré sur les exports Tripo Studio 2048² visés ici), renvoie l'original
	tel quel plutôt que de l'agrandir. Lève `ValueError` sur une taille
	demandée hors `ALLOWED_TEXTURE_SIZES` ou une taille d'origine <= 0."""
	if requested_size not in ALLOWED_TEXTURE_SIZES:
		raise ValueError(
			f"ai_import_painted: texture_size {requested_size} hors {ALLOWED_TEXTURE_SIZES}")
	if original_size <= 0:
		raise ValueError(f"ai_import_painted: taille de texture d'origine invalide ({original_size})")
	cap = min(original_size, requested_size)
	candidates = [s for s in ALLOWED_TEXTURE_SIZES if s <= cap]
	if candidates:
		return max(candidates)
	return original_size


def _resolve_path(maybe_relative: str, repo_root: str) -> str:
	if os.path.isabs(maybe_relative):
		return maybe_relative
	return os.path.normpath(os.path.join(repo_root, maybe_relative))


def repo_root() -> str:
	return os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def build_jobs(cli: dict, manifest: dict | None, root: str) -> list:
	"""Résout les jobs à traiter (chacun un dict `{id, in_path, out_path,
	height_m, budget_tris, texture_size, merge_ratio, island_min_ratio}`) à
	partir des arguments CLI déjà parsés (`cli`, un dict simple — voir
	`parse_args`, jamais un `argparse.Namespace` ici : pure fonction, testable
	sans invoquer réellement argparse) et d'un manifeste optionnel déjà parsé
	(`parse_manifest`). Trois modes, mutuellement exclusifs :
	  - `cli["process_all"]` : TOUTES les entrées du manifeste (nécessite
	    `manifest`), sortie dans `manifest["output_dir"]/<id>.glb`.
	  - `cli["asset_id"]` : UNE entrée du manifeste par son id (nécessite
	    `manifest`) ; `cli["out_path"]` la surcharge si fourni.
	  - sinon : un seul job directement depuis `cli["in_path"]`/`cli["out_path"]`/
	    `cli["height_m"]`/`cli["budget_tris"]`/`cli["texture_size"]` (mêmes
	    conventions que ai_restyle.py --in/--out/--budget), sans manifeste.
	Lève `ValueError` (jamais un `sys.exit` — laissé à `main()`) sur toute
	combinaison incomplète (ex. --id sans --manifest, hauteur manquante)."""
	if cli.get("process_all"):
		if manifest is None:
			raise ValueError("ai_import_painted: --all nécessite --manifest")
		output_dir = _resolve_path(manifest["output_dir"], root)
		jobs = []
		for entry in manifest["assets"]:
			jobs.append(_job_from_manifest_entry(entry, manifest, output_dir, root))
		return jobs

	if cli.get("asset_id"):
		if manifest is None:
			raise ValueError("ai_import_painted: --id nécessite --manifest")
		entry = resolve_manifest_entry(manifest, cli["asset_id"])
		output_dir = _resolve_path(manifest["output_dir"], root)
		job = _job_from_manifest_entry(entry, manifest, output_dir, root)
		if cli.get("out_path"):
			job["out_path"] = _resolve_path(cli["out_path"], root)
		return [job]

	if not cli.get("in_path"):
		raise ValueError("ai_import_painted: --in (ou --manifest --all / --manifest --id) requis")
	if not cli.get("out_path"):
		raise ValueError("ai_import_painted: --out requis (hors mode --manifest --all)")
	if cli.get("height_m") is None:
		raise ValueError("ai_import_painted: --height-m requis (hors manifeste)")
	asset_id = os.path.splitext(os.path.basename(cli["in_path"]))[0]
	return [{
		"id": asset_id,
		"in_path": _resolve_path(cli["in_path"], root),
		"out_path": _resolve_path(cli["out_path"], root),
		"height_m": float(cli["height_m"]),
		"budget_tris": int(cli.get("budget_tris") or DEFAULT_BUDGET_TRIS),
		"texture_size": int(cli.get("texture_size") or DEFAULT_TEXTURE_SIZE),
		"merge_ratio": cli.get("merge_ratio") or MERGE_DIST_RATIO,
		"island_min_ratio": cli.get("island_min_ratio") or MIN_ISLAND_RATIO,
	}]


def _job_from_manifest_entry(entry: dict, manifest: dict, output_dir: str, root: str) -> dict:
	asset_id = entry.get("id")
	if not asset_id:
		raise ValueError(f"ai_import_painted: entrée de manifeste sans \"id\": {entry!r}")
	for key in ("source", "height_m", "budget_tris", "texture_size"):
		if entry.get(key) is None:
			raise ValueError(f"ai_import_painted: \"{asset_id}\" n'a pas de champ \"{key}\"")
	return {
		"id": asset_id,
		"in_path": _resolve_path(entry["source"], root),
		"out_path": os.path.join(output_dir, f"{asset_id}.glb"),
		"height_m": float(entry["height_m"]),
		"budget_tris": int(entry["budget_tris"]),
		"texture_size": int(entry["texture_size"]),
		"merge_ratio": float(manifest.get("merge_ratio", MERGE_DIST_RATIO)),
		"island_min_ratio": float(manifest.get("min_island_ratio", MIN_ISLAND_RATIO)),
	}


# ---------------------------------------------------------------------------
# Fonctions dépendantes de bpy — jamais appelées hors de Blender (voir l'en-tête).
# ---------------------------------------------------------------------------

def import_asset(path: str) -> list:
	ext = os.path.splitext(path)[1].lower()
	if ext in (".glb", ".gltf"):
		bpy.ops.import_scene.gltf(filepath=path)
	else:
		raise ValueError(f"ai_import_painted: extension non supportée: {ext!r} (attendu .glb/.gltf)")
	return [o for o in bpy.context.scene.objects if o.type == 'MESH']


def _bbox_diagonal(obj) -> float:
	corners = [Vector(c) for c in obj.bound_box]
	mins = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
	maxs = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
	return (maxs - mins).length


def merge_by_distance(obj, ratio: float = MERGE_DIST_RATIO) -> int:
	"""Fusionne les sommets quasi confondus (bruit de triangulation IA typique)
	— même mesure relative que ai_restyle.py::merge_by_distance, dupliquée ici
	(voir l'en-tête de ce fichier). Renvoie le nombre de sommets retirés."""
	diag = max(_bbox_diagonal(obj), 1e-6)
	dist = max(1e-6, diag * ratio)
	me = obj.data
	before = len(me.vertices)
	bm = bmesh.new()
	bm.from_mesh(me)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=dist)
	bm.to_mesh(me)
	bm.free()
	me.update()
	return before - len(me.vertices)


def _remove_duplicate_faces_bm(bm: "bmesh.types.BMesh") -> int:
	"""Fonction PURE bmesh (opère sur `bm` déjà chargé, ne touche ni import ni
	export) — même logique que ai_restyle.py::_remove_duplicate_faces
	(dupliquée ici, voir l'en-tête de ce fichier) : supprime toute face qui
	partage EXACTEMENT le même ensemble de sommets qu'une face déjà vue.
	Renvoie le nombre de faces retirées."""
	seen = {}
	dupes = []
	for f in bm.faces:
		key = frozenset(v.index for v in f.verts)
		if key in seen:
			dupes.append(f)
		else:
			seen[key] = f
	if dupes:
		bmesh.ops.delete(bm, geom=dupes, context='FACES')
	return len(dupes)


def remove_duplicate_faces(obj) -> int:
	"""Wrapper mesh-level de `_remove_duplicate_faces_bm` — même défaut de
	génération IA que ai_restyle.py::_remove_duplicate_faces (dupliqué ici),
	garde défensive bon marché avant `remove_small_islands`. Renvoie le nombre
	de faces retirées."""
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
	removed = _remove_duplicate_faces_bm(bm)
	bm.to_mesh(me)
	bm.free()
	me.update()
	return removed


def _remove_nonmanifold_slivers(bm: "bmesh.types.BMesh", bad_edges: list, strict: bool = True) -> int:
	"""Même logique que ai_restyle.py::_remove_nonmanifold_slivers (dupliquée
	ici, voir l'en-tête de ce fichier) : sur chaque arête de `bad_edges`
	(>= 3 faces liées, après dé-duplication déjà tentée par
	`_remove_duplicate_faces_bm`), retire les faces les plus PETITES jusqu'à
	n'en garder que 2 (les deux plus grandes, les moins destructrices à
	garder).

	`strict=True` (défaut, nettoyage préventif de `repair_nonmanifold_edges`) :
	ne retire une face que si elle est CLAIREMENT un éclat dégénéré (aire
	>= 20x plus petite que la plus grande face liée, `_SLIVER_AREA_RATIO`) —
	une arête dont les faces en excès restent comparables en aire n'est PAS
	touchée. `strict=False` (dernier recours de `_final_repair_pass`, voir
	`_repair_slivers_if_safe` pour la vérification anti-fracture qui entoure
	CET appel-ci comme celui de `repair_nonmanifold_edges`) : aucun seuil —
	garde TOUJOURS les 2 faces de plus grande aire. Renvoie le nombre de
	faces retirées."""
	to_delete = set()
	for e in bad_edges:
		linked = [f for f in e.link_faces if f not in to_delete]
		while len(linked) > 2:
			areas = [(f.calc_area(), f) for f in linked]
			areas.sort(key=lambda t: t[0])
			smallest_area, smallest_face = areas[0]
			largest_area = areas[-1][0]
			if strict and (largest_area <= 0 or smallest_area > _SLIVER_AREA_RATIO * largest_area):
				break  # ni l'un ni l'autre n'est un éclat clair : arête laissée telle quelle
			to_delete.add(smallest_face)
			linked = [f for f in linked if f is not smallest_face]
	if to_delete:
		bmesh.ops.delete(bm, geom=list(to_delete), context='FACES')
	return len(to_delete)


def _islands_count(bm: "bmesh.types.BMesh") -> int:
	"""Nombre d'îlots (composantes connexes, voir `_face_islands`) — signature
	bon marché pour détecter une FRACTURE de maillage (voir
	`_repair_slivers_if_safe`). Un retrait de face est une opération
	MONOTONE sur la connectivité : il ne peut jamais RÉUNIR deux composantes
	(seule une fusion de sommets le pourrait, jamais faite ici), donc ce
	nombre ne peut que rester égal ou AUGMENTER — jamais baisser — après
	`_remove_nonmanifold_slivers`. Une simple RÉDUCTION du nombre de faces du
	plus gros îlot n'est PAS un signal de fracture (c'est l'effet ATTENDU du
	retrait d'un doublon : le corps principal reste une SEULE composante,
	juste plus légère) — seul un compte d'îlots qui augmente prouve qu'une
	composante s'est scindée en deux."""
	return len(_face_islands(bm))


def _repair_slivers_if_safe(bm: "bmesh.types.BMesh", bad_edges: list, strict: bool) -> tuple:
	"""Enveloppe de sécurité autour de `_remove_nonmanifold_slivers` : essaie
	d'abord l'opération sur une COPIE de `bm` (`bmesh.copy`, jamais `bm`
	directement) et ne la commite sur `bm` QUE si elle n'augmente PAS le
	nombre d'îlots (voir `_islands_count` — la seule vraie preuve de
	fracture ; une réduction du corps principal en NOMBRE DE FACES, elle,
	est l'effet normal et voulu du retrait d'un doublon). Sondage ART-80
	concret : wl_crane_lattice fracture son PROPRE treillis même en mode
	`strict=True` (179 -> 184 îlots) — un défaut du maillage SOURCE
	(certaines arêtes « non-manifold » y relient en réalité deux morceaux
	UNIQUEMENT via la face en excès qu'on s'apprêtait à retirer), jamais un
	compte ou un ratio d'arêtes fixe ne suffit à le prédire sans essayer
	réellement (voir la note de tête de ce module). Renvoie
	`(faces_retirées, aurait_fracturé: bool)` — le second est `True`
	uniquement quand l'opération a été REFUSÉE pour cette raison (jamais
	quand `bad_edges` est vide ou que rien n'était à retirer)."""
	if not bad_edges:
		return 0, False
	n_islands_before = _islands_count(bm)
	trial = bm.copy()
	trial_bad = [e for e in trial.edges if len(e.link_faces) >= 3]
	removed_trial = _remove_nonmanifold_slivers(trial, trial_bad, strict=strict)
	n_islands_trial = _islands_count(trial)
	trial.free()
	if removed_trial == 0:
		return 0, False
	if n_islands_trial > n_islands_before:
		return 0, True
	removed = _remove_nonmanifold_slivers(bm, bad_edges, strict=strict)
	return removed, False


def repair_nonmanifold_edges(obj) -> dict:
	"""Nettoyage best-effort des arêtes non-manifold (>= 3 faces liées) d'un
	maillage BRUT, AVANT le retrait d'îlots/la décimation — même séquence que
	ai_restyle.py::repair_nonmanifold_edges (dupliquée ici, voir l'en-tête de
	ce fichier) : `_remove_duplicate_faces_bm` (déjà appelé séparément par
	`remove_duplicate_faces` avant ART-80 — fusionné ici en une seule passe
	bmesh) PUIS `_remove_nonmanifold_slivers` stricte, VÉRIFIÉE anti-fracture
	(`_repair_slivers_if_safe` — voir sa docstring et la note de tête de ce
	module). Vérification QA ART-80 (check_asset.py réel sur les 7 repères
	Tripo Studio) : `remove_duplicate_faces` SEUL laissait 10 à 842 arêtes
	non-manifold selon l'asset — cette passe supplémentaire (jamais appliquée
	avant cette correction) réduit ce compte sans jamais fracturer un
	maillage déjà connexe (voir `_final_repair_pass` pour le filet de
	sécurité final, non strict, APRÈS décimation/mise à l'échelle). JAMAIS un
	blocage dur ici — check_asset.py reste le juge final en aval. Renvoie
	{"duplicate_faces": int, "sliver_faces": int,
	"remaining_nonmanifold_edges": int, "skipped_would_fragment": bool}."""
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
	dupes = _remove_duplicate_faces_bm(bm)
	bad = [e for e in bm.edges if len(e.link_faces) >= 3]
	slivers, would_fragment = _repair_slivers_if_safe(bm, bad, strict=True)
	if slivers:
		bad = [e for e in bm.edges if len(e.link_faces) >= 3]
	bm.to_mesh(me)
	bm.free()
	me.update()
	return {
		"duplicate_faces": dupes,
		"sliver_faces": slivers,
		"remaining_nonmanifold_edges": len(bad),
		"skipped_would_fragment": would_fragment,
	}


def _face_islands(bm: "bmesh.types.BMesh") -> list:
	"""Composantes connexes par adjacence d'arête (flood fill) — identique à
	ai_restyle.py::_face_islands (dupliqué ici, voir l'en-tête de ce fichier)."""
	bm.faces.ensure_lookup_table()
	seen = set()
	islands = []
	for seed in bm.faces:
		if seed.index in seen:
			continue
		stack = [seed]
		seen.add(seed.index)
		comp = []
		while stack:
			f = stack.pop()
			comp.append(f)
			for e in f.edges:
				for nf in e.link_faces:
					if nf.index not in seen:
						seen.add(nf.index)
						stack.append(nf)
		islands.append(comp)
	return islands


def _island_bbox_diagonal(island_faces: list) -> float:
	verts = {v for f in island_faces for v in f.verts}
	xs = [v.co.x for v in verts]
	ys = [v.co.y for v in verts]
	zs = [v.co.z for v in verts]
	return Vector((max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))).length


def _island_bbox_minmax(island_faces: list):
	"""Coins min/max (espace LOCAL du bmesh courant) de la bbox d'un îlot —
	sert au calcul d'écart de `_aabb_gap` dans `_final_repair_pass` (jamais
	utilisé par `remove_small_islands`, qui ne mesure qu'une diagonale)."""
	verts = {v for f in island_faces for v in f.verts}
	xs = [v.co.x for v in verts]
	ys = [v.co.y for v in verts]
	zs = [v.co.z for v in verts]
	return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


def _aabb_gap(mins_a, maxs_a, mins_b, maxs_b) -> float:
	"""Distance heuristique entre deux boîtes englobantes alignées aux axes —
	EXACTEMENT la même mesure que check_asset.py::_aabb_gap (dupliquée ici,
	voir l'en-tête de ce fichier) : 0 si elles se chevauchent ou se touchent
	sur les 3 axes, sinon la norme du vecteur d'écart par axe."""
	dx = max(mins_a.x - maxs_b.x, mins_b.x - maxs_a.x, 0.0)
	dy = max(mins_a.y - maxs_b.y, mins_b.y - maxs_a.y, 0.0)
	dz = max(mins_a.z - maxs_b.z, mins_b.z - maxs_a.z, 0.0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)


def remove_small_islands(obj, min_ratio: float = MIN_ISLAND_RATIO) -> int:
	"""Retire tout îlot de faces (composante connexe par arête partagée, voir
	`_face_islands`) dont la diagonale de bbox est < `min_ratio` fois la
	diagonale de bbox de L'OBJET ENTIER — mesurée UNE SEULE FOIS, avant toute
	suppression, sur le maillage encore intact (voir la docstring de ce
	module : seuil ABSOLU, contrairement au clustering par proximité de
	ai_restyle.py::remove_isolated_islands/_drop_floating_islands). Ne retire
	JAMAIS le plus gros îlot (le corps), même dans le cas dégénéré où lui
	seul existerait. Renvoie le nombre de faces retirées."""
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
	islands = _face_islands(bm)
	removed = 0
	if len(islands) > 1:
		total_diag = max(_island_bbox_diagonal([f for comp in islands for f in comp]), 1e-6)
		islands.sort(key=len, reverse=True)
		to_delete = []
		for comp in islands[1:]:
			if _island_bbox_diagonal(comp) < min_ratio * total_diag:
				to_delete.extend(comp)
		if to_delete:
			removed = len(to_delete)
			bmesh.ops.delete(bm, geom=to_delete, context='FACES')
			orphan_verts = [v for v in bm.verts if not v.link_faces]
			if orphan_verts:
				bmesh.ops.delete(bm, geom=orphan_verts, context='VERTS')
	bm.to_mesh(me)
	bm.free()
	me.update()
	return removed


def detect_floating_islands(obj, gap_tolerance_m: float) -> list:
	"""Diagnostic NON DESTRUCTIF (ne modifie JAMAIS `obj.data` — contrairement
	à `remove_small_islands`) : liste chaque îlot (voir `_face_islands`) dont
	l'écart AABB (`_aabb_gap`) au plus gros îlot PAR NOMBRE DE FACES dépasse
	`gap_tolerance_m` (CHK-16, même tolérance que check_asset.py::
	check_object). Renvoie une liste de `{"n_faces": int, "gap_m": float}`,
	triée par écart décroissant (vide si un seul îlot ou si aucun ne dépasse
	la tolérance) — appelée sur la topologie déjà à l'échelle FINALE
	(post-`scale_obj_uniform_to_height`/`apply_transforms`), donc `gap_m` est
	déjà en mètres RÉELS/exportés, sans conversion.

	Sondage ART-80 (mésaventure concrète, corrigée dans CETTE tâche) : une
	version antérieure de ce module SUPPRIMAIT ces îlots plutôt que de les
	signaler — trois tentatives successives de garde-fou (comparaison au
	plus gros îlot seul, tout-ou-rien sur le lot entier, retrait cumulatif du
	plus petit au plus grand) ont chacune fini par amputer un repère réel
	(wl_oil_derrick : les 4 jambes du derrick, laissant flotter seule la
	poulie du sommet ; wl_crane_lattice : la flèche et la cabine ;
	wl_water_tower : les barreaux de l'échelle ; wl_gas_billboard : les
	pieds du panneau) — vérifié en rendu (`render_textured_preview`) à
	chaque tentative. Cause commune : sur ces exports Tripo Studio, un
	membre structurel LÉGITIME (jambe, barreau, pied, flèche) est presque
	aussi souvent un îlot séparé — jamais vertex-welded au corps — qu'un vrai
	débris fantôme ; aucune heuristique géométrique locale (taille, écart,
	écart cumulatif, ratio de silhouette survivante) ne les distingue de
	façon fiable, exactement la conclusion déjà tirée par ai_restyle.py::
	_drop_floating_islands pour ces mêmes repères (« défaut CONNU, hors de
	portée d'un ajustement de ce seul filet ») — voir aussi la note de tête
	de ce module. Cette fonction ne retire donc plus RIEN : elle EXPOSE
	l'écart réel (sidecar JSON, `report["floating_islands"]`) pour que le
	rapport de tâche et la revue humaine restent honnêtes (jamais
	« quelques dizaines de cm » quand l'écart réel atteint plusieurs mètres,
	la faute initialement relevée par le QA d'ART-80), laissant
	check_asset.py seul juge en aval, comme pour tout autre défaut de
	maillage brut non corrigé."""
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
	islands = _face_islands(bm)
	floating = []
	if len(islands) > 1:
		islands.sort(key=len, reverse=True)
		main_mins, main_maxs = _island_bbox_minmax(islands[0])
		for comp in islands[1:]:
			comp_mins, comp_maxs = _island_bbox_minmax(comp)
			gap = _aabb_gap(main_mins, main_maxs, comp_mins, comp_maxs)
			if gap > gap_tolerance_m:
				floating.append({"n_faces": len(comp), "gap_m": round(gap, 4)})
	bm.free()
	floating.sort(key=lambda entry: entry["gap_m"], reverse=True)
	return floating


def _apply_modifier(obj, modifier) -> None:
	"""Applique `modifier` et le retire de la pile — même garde-fou que
	ai_restyle.py::_apply_modifier (déplace en tête de pile avant d'appliquer,
	vérifie que l'opérateur n'a pas été annulé), dupliqué ici (voir l'en-tête
	de ce fichier). Post-condition : `modifier` n'est jamais dans
	`obj.modifiers` au retour normal."""
	name = modifier.name
	index = obj.modifiers.find(name)
	if index < 0:
		raise RuntimeError(f"ai_import_painted: modificateur \"{name}\" introuvable sur \"{obj.name}\"")
	if index != 0:
		with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj]):
			move_result = bpy.ops.object.modifier_move_to_index(modifier=name, index=0)
		if 'FINISHED' not in move_result:
			raise RuntimeError(
				f"ai_import_painted: impossible de remonter \"{name}\" en tête de pile sur "
				f"\"{obj.name}\" ({move_result!r})")
	with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj]):
		apply_result = bpy.ops.object.modifier_apply(modifier=name)
	if 'FINISHED' not in apply_result:
		raise RuntimeError(
			f"ai_import_painted: bpy.ops.object.modifier_apply a échoué ({apply_result!r}) pour "
			f"\"{name}\" sur \"{obj.name}\"")
	if obj.modifiers.find(name) >= 0:
		obj.modifiers.remove(modifier)


def _decimate_planar_pass(obj) -> None:
	mod = obj.modifiers.new("ai_import_painted_decimate_planar", type='DECIMATE')
	mod.decimate_type = 'DISSOLVE'
	mod.angle_limit = DECIMATE_PLANAR_ANGLE_LIMIT
	_apply_modifier(obj, mod)
	obj.data.update()


def decimate_to_budget(obj, budget: int, max_iterations: int = DECIMATE_MAX_ITERATIONS) -> int:
	"""Decimate COLLAPSE itératif jusqu'au budget de tris — même algorithme que
	ai_restyle.py::decimate_to_budget (dupliqué ici, voir l'en-tête de ce
	fichier). No-op immédiat (renvoie le compte courant) si déjà sous le
	budget — le cas courant pour ces repères déjà bas-poly."""
	planar_retries = 0
	for _ in range(max_iterations):
		tris = toonkit.tri_count(obj)
		if tris <= budget:
			return tris
		ratio = max(0.02, min(0.95, budget / float(tris)))
		mod = obj.modifiers.new("ai_import_painted_decimate", type='DECIMATE')
		mod.decimate_type = 'COLLAPSE'
		mod.ratio = ratio
		_apply_modifier(obj, mod)
		obj.data.update()
		new_tris = toonkit.tri_count(obj)
		if new_tris > budget and new_tris >= tris * DECIMATE_STALL_RATIO and planar_retries < 3:
			planar_retries += 1
			_decimate_planar_pass(obj)
	return toonkit.tri_count(obj)


def _bbox_height_m(obj) -> float:
	"""Hauteur monde courante de `obj` (axe Z Blender, avant rotation d'export
	Y-up) — utilisée par `scale_obj_uniform_to_height` juste avant l'échelle
	finale."""
	corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
	return max(c.z for c in corners) - min(c.z for c in corners)


def scale_obj_uniform_to_height(obj, target_height_m: float) -> float:
	"""Échelle UNIFORME (mêmes trois axes) qui porte la hauteur monde courante
	de `obj` à `target_height_m` — voir `scale_factor_for_height` pour le
	calcul pur. Ne bake rien : le facteur est posé sur `obj.scale`, à
	appliquer ensuite via `toonkit.apply_transforms` (même ordre que
	ai_restyle.py::restyle, étape 7)."""
	factor = scale_factor_for_height(_bbox_height_m(obj), target_height_m)
	obj.scale = tuple(s * factor for s in obj.scale)
	return factor


def _material_image_node(mat):
	"""Image branchée sur Base Color de `mat` (même logique que
	ai_restyle.py::_material_image_node, dupliquée ici), ou `None` si `mat` n'a
	pas de texture (couleur plate, résiduel rare sur ces repères)."""
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
	return None


def keep_painted_materials(obj, texture_size: int) -> dict:
	"""Garde CHAQUE matériau importé qui porte une image Base Color — JAMAIS
	remplacé par une couleur de palette (contrairement à
	ai_restyle.py::restyle_materials) : le graphe de nœuds est reconstruit au
	minimum (Principled BSDF <- Image Texture -> Output, rien d'autre — une
	carte normal/occlusion/metallic-roughness qu'un GLB Tripo peut aussi
	porter n'est JAMAIS lue par ink_toon.gdshader, donc retirée) et l'image est
	redimensionnée SANS jamais être quantifiée (`resolved_texture_size` : ni
	agrandie au-delà de sa taille d'origine, ni tramée/réduite en palette —
	seul un redimensionnement bilinéaire, `Image.scale`). Un matériau SANS
	image (couleur plate résiduelle) est laissé tel quel : ce script ne
	fabrique jamais lui-même de matériau ink_toon (c'est
	Cartoon.painted_texture_prop(), côté Godot, qui construit le
	ShaderMaterial final — voir scripts/core/Cartoon.gd). Toute image devenue
	orpheline (carte retirée du graphe) est purgée de bpy.data. Renvoie
	`{"materials": [...], "images_kept": [...], "images_purged": [...]}`."""
	me = obj.data
	kept_images = []
	report_mats = []
	for mat in list(me.materials):
		if mat is None:
			continue
		image = _material_image_node(mat)
		if image is None:
			report_mats.append({"name": mat.name, "has_texture": False})
			continue
		orig_w, orig_h = image.size
		new_w = resolved_texture_size(orig_w, texture_size)
		new_h = resolved_texture_size(orig_h, texture_size)
		if (new_w, new_h) != (orig_w, orig_h):
			image.scale(new_w, new_h)
		mat.use_nodes = True
		nt = mat.node_tree
		for n in list(nt.nodes):
			if n.type not in ('OUTPUT_MATERIAL', 'BSDF_PRINCIPLED', 'TEX_IMAGE'):
				nt.nodes.remove(n)
		out = next((n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL'), None)
		if out is None:
			out = nt.nodes.new("ShaderNodeOutputMaterial")
		bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
		if bsdf is None:
			bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
		tex_nodes = [n for n in nt.nodes if n.type == 'TEX_IMAGE']
		for extra in tex_nodes[1:]:
			nt.nodes.remove(extra)
		tex = tex_nodes[0] if tex_nodes else nt.nodes.new("ShaderNodeTexImage")
		tex.image = image
		for link in list(nt.links):
			nt.links.remove(link)
		nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
		nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
		bsdf.inputs["Roughness"].default_value = 1.0
		kept_images.append(image.name)
		report_mats.append({
			"name": mat.name, "has_texture": True, "image": image.name,
			"texture_size": [new_w, new_h],
		})
	purged = []
	for img in list(bpy.data.images):
		if img.name not in kept_images and img.users == 0:
			purged.append(img.name)
			bpy.data.images.remove(img)
	return {"materials": report_mats, "images_kept": kept_images, "images_purged": purged}


def _augment_sidecar(glb_path: str, source: str, extra: dict | None = None) -> str:
	"""Ajoute `"painted": true` et `"source": source` au rapport JSON déjà
	écrit par `toonkit.export_glb` à côté de `glb_path` (ART-80 : « sidecar
	JSON (+ "painted": true, "source") ») — augmente CE fichier plutôt que
	d'en écrire un second (contrairement à ai_restyle.py, qui écrit son propre
	`.ai_restyle.json` séparé : ce script n'a pas de rapport de restyle
	distinct à documenter, le rapport de toonkit suffit une fois augmenté).
	`extra`, si fourni, ajoute ses clés en plus (correction QA ART-80,
	honnêteté du rapport : `floating_islands`/`final_repair`, voir
	`detect_floating_islands`/`_final_repair_pass` — pour que l'écart réel
	restant, s'il y en a un, soit visible DANS le fichier livré lui-même,
	jamais seulement dans le retour Python transitoire de cette tâche)."""
	sidecar_path = os.path.splitext(glb_path)[0] + ".json"
	with open(sidecar_path, "r", encoding="utf-8") as f:
		data = json.load(f)
	data["painted"] = True
	data["source"] = source
	if extra:
		data.update(extra)
	with open(sidecar_path, "w", encoding="utf-8") as f:
		json.dump(data, f, indent=2, ensure_ascii=False)
	return sidecar_path


PREVIEW_AZIMUTHS_DEG = (30.0, 150.0, 270.0)  # 3 vues suffisent a prouver "texture visible, pas de face manquante"
PREVIEW_ELEVATION_DEG = 22.0
PREVIEW_FRAME_MARGIN = 2.4


def render_textured_preview(glb_path: str, out_dir: str, size: int = 640) -> list:
	"""Rendu EEVEE minimal avec le MATÉRIAU RÉELLEMENT EXPORTÉ (texture peinte
	conservée, jamais un aperçu 2 tons reconstruit) — turntable.py (lu, mais
	hors de la liste de fichiers que cette tâche peut modifier) reconstruit
	un matériau d'aperçu à partir d'une seule COULEUR PLATE
	(`_read_albedo` : lit `default_value` d'un socket non lié, ou l'entrée
	non liée d'un nœud Mix) — il ne sait lire NI une image directement liée
	NI le nœud Mix "image x vertex-color" que ce même pipeline bake ensuite
	(AO/Curvature) : son rendu masquerait donc la texture conservée derrière
	un aplat gris (vérifié par sondage sur wl_water_tower — voir le rapport
	de tâche ART-80). Cette fonction importe le .glb FINAL tel quel (aucun
	remplacement de matériau) sous un éclairage neutre à deux soleils, la
	SEULE façon, dans les fichiers que cette tâche peut modifier, de prouver
	à l'œil le critère d'acceptation « texture peinte visible, aucune face
	manquante » — turntable.py reste utilisé EN PLUS (silhouette/échelle
	humaine/calibration), jamais remplacé. Renvoie la liste des chemins PNG
	écrits."""
	toonkit.reset_scene()
	mesh_objs = import_asset(glb_path)
	if not mesh_objs:
		raise RuntimeError(f"ai_import_painted: aucun mesh à prévisualiser dans {glb_path}")
	obj = toonkit.join(mesh_objs)
	corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
	mins = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
	maxs = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
	center = (mins + maxs) / 2.0
	radius = max((maxs - mins).length / 2.0, 0.05)

	scene = bpy.context.scene
	scene.render.engine = 'BLENDER_EEVEE'
	scene.render.resolution_x = size
	scene.render.resolution_y = size
	scene.render.film_transparent = False
	scene.render.image_settings.file_format = 'PNG'
	scene.view_settings.view_transform = 'Standard'

	world = bpy.data.worlds.new("PreviewWorld")
	world.use_nodes = True
	bg = world.node_tree.nodes.get("Background")
	if bg is not None:
		bg.inputs[0].default_value = (0.5, 0.5, 0.52, 1.0)
		bg.inputs[1].default_value = 1.0
	scene.world = world

	key = bpy.data.objects.new("PreviewKeySun", bpy.data.lights.new("PreviewKeySun", type='SUN'))
	key.data.energy = 3.0
	key.rotation_euler = (math.radians(55.0), 0.0, math.radians(-35.0))
	scene.collection.objects.link(key)
	fill = bpy.data.objects.new("PreviewFillSun", bpy.data.lights.new("PreviewFillSun", type='SUN'))
	fill.data.energy = 1.2
	fill.rotation_euler = (math.radians(-35.0), 0.0, math.radians(150.0))
	scene.collection.objects.link(fill)

	cam_data = bpy.data.cameras.new("PreviewCam")
	cam_data.lens_unit = 'FOV'
	cam_data.angle = math.radians(45.0)
	cam = bpy.data.objects.new("PreviewCam", cam_data)
	scene.collection.objects.link(cam)
	scene.camera = cam
	distance = radius * PREVIEW_FRAME_MARGIN / math.sin(math.radians(45.0) / 2.0)

	os.makedirs(out_dir, exist_ok=True)
	paths = []
	for i, az in enumerate(PREVIEW_AZIMUTHS_DEG):
		el = math.radians(PREVIEW_ELEVATION_DEG)
		azr = math.radians(az)
		horiz = distance * math.cos(el)
		cam.location = center + Vector((horiz * math.sin(azr), horiz * math.cos(azr), distance * math.sin(el)))
		direction = center - cam.location
		cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
		path = os.path.join(out_dir, f"painted_preview_{i:02d}.png")
		scene.render.filepath = path
		bpy.ops.render.render(write_still=True)
		paths.append(path)
	print(f"AI_IMPORT_PAINTED_PREVIEW_OK {len(paths)} vue(s) -> {out_dir}")
	return paths


def run_turntable(glb_path: str, views: int = 8, size: int = 512, timeout_s: int = 600) -> str:
	"""Turntable dans un sous-process Blender dédié — identique à
	ai_restyle.py::run_turntable (dupliqué ici, voir l'en-tête de ce
	fichier)."""
	import subprocess
	cmd = [
		bpy.app.binary_path, "-b", "--factory-startup", "--python-exit-code", "1",
		"-P", TURNTABLE_SCRIPT, "--",
		"--in", glb_path, "--views", str(views), "--size", str(size),
	]
	proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
	if proc.returncode != 0:
		raise RuntimeError(
			f"ai_import_painted: le turntable a échoué (code {proc.returncode}) pour {glb_path}\n"
			f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}")
	lines = proc.stdout.splitlines()
	for i, line in enumerate(lines):
		if line.strip().startswith("TURNTABLE_OK") and i + 1 < len(lines):
			path = lines[i + 1].strip()
			if path:
				return path
	raise RuntimeError(
		f"ai_import_painted: pas de marqueur TURNTABLE_OK dans la sortie du turntable pour {glb_path}\n"
		f"--- stdout ---\n{proc.stdout}")


def _final_repair_pass(obj) -> dict:
	"""Repasse de nettoyage FINALE, juste avant l'export — APRÈS décimation et
	mise à l'échelle/origine, donc dans les unités RÉELLEMENT exportées
	(mêmes unités que celles que check_asset.py mesurera sur le .glb
	réimporté). Même rationale A3D-15 que ai_restyle.py::
	_repair_nonmanifold_final : un poste ULTÉRIEUR du pipeline (décimation)
	peut re-salir une topologie déjà nettoyée en étape 2 (nouvelle arête
	non-manifold), donc revérifiée ICI sur l'état RÉEL, jamais seulement
	l'état en mémoire au milieu du pipeline. Deux nettoyages, dans l'ordre :
	  1. ressoudage par position (`_CHECK_ASSET_WELD_DIST_M` — EXACTEMENT la
	     même tolérance que check_asset.py::check_object sur sa copie
	     ressoudée, jamais une valeur inventée ici) puis triangulation des
	     n-gones restants (`ngon_method='EAR_CLIP'`, même choix que
	     ai_restyle.py) : la topologie vérifiée ici doit être EXACTEMENT celle
	     que l'export glTF produira (qui triangule lui-même tout n-gone),
	     jamais une approximation optimiste sur une géométrie qui sera
	     re-triangulée différemment à l'export.
	  2. doublons de face exacts (`_remove_duplicate_faces_bm`) PUIS éclats
	     non-manifold NON STRICTS, VÉRIFIÉS anti-fracture
	     (`_repair_slivers_if_safe(strict=False)` — voir sa docstring et la
	     note de tête de ce module : un compte/ratio d'arêtes fixe ne suffit
	     PAS à prédire une fracture, seul un essai sur copie le fait).
	JAMAIS de retrait d'îlot ici : aucune fonction de ce module ne retire
	plus d'îlot par écart (voir `detect_floating_islands`, purement
	diagnostique — trois tentatives de retrait automatique, essayées puis
	abandonnées dans cette même tâche, ont chacune fini par amputer un
	repère réel, voir la note de tête de ce module). JAMAIS un blocage dur
	ici (best-effort) : check_asset.py reste le juge final en aval, comme
	pour tout autre défaut de maillage brut non corrigé. Renvoie
	{"duplicate_faces": int, "sliver_faces": int,
	"remaining_nonmanifold_edges": int, "skipped_would_fragment": bool}."""
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)

	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=_CHECK_ASSET_WELD_DIST_M)
	ngons = [f for f in bm.faces if len(f.verts) > 3]
	if ngons:
		bmesh.ops.triangulate(bm, faces=ngons, ngon_method='EAR_CLIP')

	dupes = _remove_duplicate_faces_bm(bm)
	bad = [e for e in bm.edges if len(e.link_faces) >= 3]
	slivers, would_fragment = _repair_slivers_if_safe(bm, bad, strict=False)
	if slivers:
		bad = [e for e in bm.edges if len(e.link_faces) >= 3]

	bm.to_mesh(me)
	bm.free()
	me.update()
	return {
		"duplicate_faces": dupes,
		"sliver_faces": slivers,
		"remaining_nonmanifold_edges": len(bad),
		"skipped_would_fragment": would_fragment,
	}


def process_painted_asset(in_path: str, out_path: str, height_m: float, budget_tris: int,
		texture_size: int, merge_ratio: float = MERGE_DIST_RATIO,
		island_min_ratio: float = MIN_ISLAND_RATIO, skip_turntable: bool = True,
		turntable_views: int = 8, turntable_size: int = 512,
		textured_preview: bool = False, preview_size: int = 640) -> dict:
	"""Orchestration complète (voir la numérotation de l'en-tête de ce
	fichier) : import -> nettoyage -> matériau peint conservé -> budget de
	tris -> normales/masques -> échelle/origine -> export + sidecar ->
	turntable optionnel. Renvoie le rapport complet (dict, aussi utile aux
	tests)."""
	toonkit.reset_scene()
	mesh_objs = import_asset(in_path)
	if not mesh_objs:
		raise RuntimeError(f"ai_import_painted: aucun mesh dans {in_path}")
	obj = toonkit.join(mesh_objs)

	merged_vertices = merge_by_distance(obj, ratio=merge_ratio)
	nonmanifold_cleanup = repair_nonmanifold_edges(obj)
	removed_island_faces = remove_small_islands(obj, min_ratio=island_min_ratio)

	material_report = keep_painted_materials(obj, texture_size)

	decimate_to_budget(obj, budget_tris)

	toonkit.weighted_normals(obj)
	toonkit.smooth_normal_attrs(obj)
	toonkit.bake_vertex_ao(obj)
	toonkit.curvature_edge_mask(obj)

	scale_factor = scale_obj_uniform_to_height(obj, height_m)
	toonkit.apply_transforms(obj)
	toonkit.set_origin_bottom(obj)

	if obj.modifiers:
		raise RuntimeError(
			f"ai_import_painted: {len(obj.modifiers)} modificateur(s) encore empilé(s) sur "
			f"\"{obj.name}\" avant l'export ({[m.name for m in obj.modifiers]})")

	final_repair = _final_repair_pass(obj)

	# Diagnostic NON DESTRUCTIF (voir sa docstring : jamais un retrait —
	# trois tentatives de retrait automatique ont chacune fini par amputer
	# un repère réel) — tourne ICI, à l'échelle FINALE, pour que `gap_m`
	# soit directement en mètres réels/exportés, sans conversion.
	floating_islands = detect_floating_islands(obj, FLOATING_GAP_TOLERANCE_M)

	final_tris = toonkit.tri_count(obj)
	if final_tris > budget_tris:
		raise RuntimeError(
			f"ai_import_painted: budget dépassé après décimation : {final_tris} > {budget_tris} tris")

	toonkit.export_glb(out_path, obj)
	sidecar_path = _augment_sidecar(out_path, source=in_path, extra={
		"floating_islands": floating_islands,
		"nonmanifold_edges_remaining": final_repair["remaining_nonmanifold_edges"],
	})

	report = {
		"input": os.path.abspath(in_path),
		"output": os.path.abspath(out_path),
		"height_m": height_m,
		"budget_tris": budget_tris,
		"final_tris": final_tris,
		"scale_factor": scale_factor,
		"merged_vertices": merged_vertices,
		"floating_islands": floating_islands,
		"duplicate_faces_removed": nonmanifold_cleanup["duplicate_faces"],
		"sliver_faces_removed": nonmanifold_cleanup["sliver_faces"],
		"nonmanifold_edges_after_initial_cleanup": nonmanifold_cleanup["remaining_nonmanifold_edges"],
		"removed_island_faces": removed_island_faces,
		"materials": material_report,
		"sidecar": sidecar_path,
		"final_repair": final_repair,
	}

	turntable_path = None
	if not skip_turntable:
		turntable_path = run_turntable(out_path, views=turntable_views, size=turntable_size)
	report["turntable_contact_sheet"] = turntable_path

	preview_paths = None
	if textured_preview:
		preview_dir = os.path.join(os.path.dirname(out_path),
			f"{os.path.splitext(os.path.basename(out_path))[0]}_preview")
		preview_paths = render_textured_preview(out_path, preview_dir, size=preview_size)
	report["textured_preview"] = preview_paths

	print(f"AI_IMPORT_PAINTED_OK {os.path.basename(out_path)} tris={final_tris}")
	return report


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> dict:
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	p = argparse.ArgumentParser()
	p.add_argument("--in", dest="in_path", default=None)
	p.add_argument("--out", dest="out_path", default=None)
	p.add_argument("--manifest", dest="manifest_path", default=None)
	p.add_argument("--id", dest="asset_id", default=None)
	p.add_argument("--all", dest="process_all", action="store_true")
	p.add_argument("--height-m", dest="height_m", type=float, default=None)
	p.add_argument("--budget-tris", dest="budget_tris", type=int, default=None)
	p.add_argument("--texture-size", dest="texture_size", type=int, default=None)
	p.add_argument("--merge-ratio", dest="merge_ratio", type=float, default=None)
	p.add_argument("--island-min-ratio", dest="island_min_ratio", type=float, default=None)
	p.add_argument("--views", dest="views", type=int, default=8)
	p.add_argument("--size", dest="size", type=int, default=512)
	p.add_argument("--skip-turntable", dest="skip_turntable", action="store_true")
	p.add_argument("--textured-preview", dest="textured_preview", action="store_true",
		help="rendu(s) supplémentaire(s) avec le matériau réellement exporté (texture peinte "
			"visible) — turntable.py ne sait pas encore prévisualiser une image, voir "
			"render_textured_preview()")
	p.add_argument("--preview-size", dest="preview_size", type=int, default=640)
	ns = p.parse_args(argv)
	return vars(ns)


def main() -> None:
	cli = parse_args()
	root = repo_root()
	manifest = None
	if cli.get("manifest_path"):
		manifest_path = _resolve_path(cli["manifest_path"], root)
		if not os.path.isfile(manifest_path):
			print(f"AI_IMPORT_PAINTED_FAIL manifeste introuvable: {manifest_path}")
			sys.exit(1)
		with open(manifest_path, "r", encoding="utf-8") as f:
			manifest = parse_manifest(f.read())
	try:
		jobs = build_jobs(cli, manifest, root)
	except ValueError as exc:
		print(f"AI_IMPORT_PAINTED_FAIL {exc}")
		sys.exit(1)

	failures = []
	for job in jobs:
		if not os.path.isfile(job["in_path"]):
			failures.append((job["id"], f"fichier introuvable: {job['in_path']}"))
			print(f"AI_IMPORT_PAINTED_FAIL {job['id']}: fichier introuvable: {job['in_path']}")
			continue
		print(f"AI_IMPORT_PAINTED_START {job['id']} <- {job['in_path']}")
		try:
			process_painted_asset(
				job["in_path"], job["out_path"], job["height_m"], job["budget_tris"],
				job["texture_size"], merge_ratio=job["merge_ratio"],
				island_min_ratio=job["island_min_ratio"], skip_turntable=cli["skip_turntable"],
				turntable_views=cli["views"], turntable_size=cli["size"],
				textured_preview=cli["textured_preview"], preview_size=cli["preview_size"],
			)
		except Exception as exc:  # noqa: BLE001 - rapporte chaque échec, continue les autres jobs
			failures.append((job["id"], str(exc)))
			print(f"AI_IMPORT_PAINTED_FAIL {job['id']}: {exc}")
	if failures:
		sys.exit(1)


if __name__ == "__main__":
	main()
