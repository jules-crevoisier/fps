## tools/blender/fit_weapon_painted.py
## Remplace, pour les 7 armes du jeu, le corps bpy en blocs de
## tools/blender/make_weapons.py par la version Tripo Studio « peinture
## conservée » (docs/art/WASTELAND_ART_RESET.md, même politique que
## tools/blender/ai_import_painted.py pour les repères d'environnement —
## JAMAIS ai_restyle.py, qui jette la texture IA). La géométrie bpy n'est
## PAS jetée : elle sert de RÉFÉRENCE DE FORME (axe du canon, longueur,
## pivot poignée, empties "Muzzle"/"Foregrip") à laquelle la source Tripo est
## ALIGNÉE, puis SAUVEGARDÉE sous `backup_dir` avant d'être écrasée par le
## résultat peint — voir tools/ai3d/manifests/painted_weapons.yaml.
##
##   blender -b --factory-startup --python-exit-code 1 -P tools/blender/fit_weapon_painted.py -- \
##       --manifest tools/ai3d/manifests/painted_weapons.yaml --all
##   # ou une seule arme :
##   blender -b --factory-startup --python-exit-code 1 -P tools/blender/fit_weapon_painted.py -- \
##       --manifest tools/ai3d/manifests/painted_weapons.yaml --id pistolet
##
## Repère de travail — IMPORTANT (vérifié par sondage bpy 5.2, sous-process,
## voir l'en-tête du manifeste) : ce script importe DIRECTEMENT les .glb réels
## (référence bpy ET source Tripo) via `bpy.ops.import_scene.gltf`, jamais en
## ré-authorant des coordonnées à la main comme make_weapons.py (qui, lui,
## écrit dans un repère "cible Godot" fictif — X=droite, Y=haut, Z=avant —
## puis applique SA PROPRE rotation +90°/X de correction avant d'exporter).
## Une fois importée par Blender, une arme bpy déjà exportée par
## make_weapons.py (Y-up, canon -Z, comme Godot la lit) ressort, dans le
## repère NATIF Z-up de Blender, avec : canon vers **+Y**, "haut" = **+Z**,
## largeur = **X** (mesuré : Muzzle/Foregrip d'un pistolet réimporté à
## Y > 0, jamais Z ni X) — parce que l'import glTF de Blender applique
## l'inverse EXACT de la conversion Y-up que son propre exporteur
## (`export_yup=True`, voir toonkit.py) appliquera au moment où CE script
## exportera à son tour son résultat. Travailler dans ce même repère du
## début à la fin (alignement ET ancres copiées telles quelles) suffit donc à
## reproduire, après export, EXACTEMENT la convention Godot existante — aucune
## conversion supplémentaire à faire nulle part dans ce fichier.
##
## Pipeline, par arme :
##   1. sauvegarde     l'arme bpy COURANTE est copiée sous `backup_dir` --
##                      SEULEMENT si cette sauvegarde n'existe pas déjà (voir
##                      `backup_bpy_original` : un ré-lancement de ce script NE
##                      DOIT JAMAIS écraser l'original par une version déjà
##                      peinte d'un run précédent).
##   2. référence       la sauvegarde (jamais le fichier courant, voir 1.) est
##                      importée pour lire sa bbox (axe canon = longueur, voir
##                      ci-dessus) et les positions LOCALES de ses empties
##                      "Muzzle"/"Foregrip" (`read_bpy_reference`).
##   3. import peint    la source Tripo est importée (jamais restylée) et
##                      fusionnée en un seul objet (`toonkit.join`) si
##                      plusieurs sous-objets, comme ai_import_painted.py.
##   4. nettoyage léger fusion des sommets quasi confondus + doublons de face
##                      exacts (bruit de triangulation IA typique, même mesure
##                      relative que ai_import_painted.py::merge_by_distance,
##                      dupliquée ici à dessein — voir sa docstring : ce
##                      dossier ne fait jamais dépendre un script d'un autre).
##                      Pas de retrait d'îlot/réparation non-manifold lourde
##                      ici : ces 10 sources sont de petits props "Smart Mesh"
##                      tenus en main, pas des repères architecturaux (le
##                      défaut documenté par ai_import_painted.py concernait
##                      des treillis de plusieurs mètres) — `check_asset.py`
##                      (lu en test, jamais modifié ici) reste le juge final.
##   5. matériau peint  CHAQUE matériau porteur d'une image Base Color est
##                      gardé (jamais remplacé par une couleur de palette),
##                      renommé "<id>_painted"[_i] pour que Cartoon.gd/
##                      ViewModel.gd le distinguent des anciens slots
##                      "_body"/"_grip"/"_metal"/"_accent" du bpy en blocs
##                      (`keep_painted_material`, même nettoyage de graphe de
##                      nœuds que ai_import_painted.py::keep_painted_materials,
##                      dupliqué ici).
##   6. alignement       rotation (axe canon détecté -> +Y, voir
##                      `longest_axis_index`/`pick_muzzle_sign`/
##                      `rotation_for_alignment`) + échelle uniforme (longueur
##                      Tripo -> longueur de la référence bpy le long de +Y,
##                      `scale_factor_for_length`) + translation (pivot poignée
##                      -> celui de la référence, `forward_translation`/
##                      `lateral_center_translation` + nudges manuels
##                      `z_offset`/`x_offset` du manifeste, réglés à l'œil par
##                      rendu si l'origine "sol du tourne-disque" Tripo Studio
##                      ne tombe pas exactement sur la poignée).
##   7. normales/masques toonkit.weighted_normals + smooth_normal_attrs (coque
##                      de contour) + bake_vertex_ao + curvature_edge_mask —
##                      mêmes couleurs de sommet que make_weapons.py, pour que
##                      ink_toon.gdshader affiche un contour/AO identiques à
##                      l'ancienne arme bpy.
##   8. budget           decimate_to_budget (même algorithme itératif que
##                      ai_import_painted.py, dupliqué ici) jusqu'au budget du
##                      manifeste (<= 8000 tris, A3D-20) -- no-op si déjà sous
##                      le budget (cas courant : sources Tripo à 3,9-5,7k tris).
##   9. ancres           "Muzzle"/"Foregrip" REPRIS tels quels de la référence
##                      bpy (positions locales copiées, JAMAIS recalculées) et
##                      reparentés à l'objet peint -- c'est ce qui garde
##                      ViewModel.gd/Weapon.gd et les gants (fp_gloves.glb)
##                      justes sans changement côté Godot au-delà du matériau.
##  10. export + revue   export manuel `bpy.ops.export_scene.gltf` (PAS
##                      toonkit.export_glb, qui suppose que TOUS les objets
##                      passés sont des mesh -- ici "Muzzle"/"Foregrip" sont
##                      des empties, même contrainte que make_weapons.py) puis
##                      sidecar JSON ("painted": true, "source", "fitted_to")
##                      et turntable optionnel (tools/blender/turntable.py, lu
##                      mais hors de la liste de fichiers que cette tâche peut
##                      modifier).
##
## Ce fichier importe `bpy`/`bmesh` dans un bloc try/except (même convention
## que ai_import_painted.py) : le manifeste et les calculs purs restent
## testables par `python -m pytest`, sans sous-process Blender — voir
## tools/blender/tests/test_fit_weapon_painted.py.
from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
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
# Constantes
# ---------------------------------------------------------------------------

MERGE_DIST_RATIO = 0.0005        # même mesure relative que ai_import_painted.py
DECIMATE_MAX_ITERATIONS = 6
DECIMATE_PLANAR_ANGLE_LIMIT = 0.0872665  # ~5 degres (radians)
DECIMATE_STALL_RATIO = 0.99
DEFAULT_BUDGET_TRIS = 8000       # A3D-20 : plafond dur, chaque arme <= 8000 tris
DEFAULT_TEXTURE_SIZE = 2048
ALLOWED_TEXTURE_SIZES = (1024, 2048)
# Fraction de la longueur (axe canon) échantillonnée à chaque extrémité pour
# décider laquelle est la bouche du canon (`pick_muzzle_sign`/`axis_end_radius`) :
# assez large pour lisser le bruit de maillage local, assez étroit pour ne
# jamais déborder sur le corps principal (arme la plus courte du lot,
# pistolet, longueur ~0,33 m -> bande de ~5 cm à chaque bout).
END_BAND_FRACTION = 0.15
# Tolérance sur l'invariant "axe haut = Z, base au sol" des sources Tripo
# Studio (bbox min Z ~ 0, voir l'en-tête du manifeste) -- une valeur hors de
# cette tolérance signale un repère qui ne respecte pas la convention
# attendue, jamais réorienté en silence (voir `assert_up_axis_is_z`).
UP_AXIS_FLOOR_TOLERANCE_M = 0.01
ANCHOR_EMPTY_DISPLAY_SIZE = 0.03
TURNTABLE_SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "turntable.py")


# ---------------------------------------------------------------------------
# Fonctions pures (aucune dépendance bpy) — manifeste + calculs scalaires.
# ---------------------------------------------------------------------------

_TOP_SCALAR_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$")
_LIST_ITEM_RE = re.compile(r"^-\s+([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$")
_LIST_CONT_RE = re.compile(r"^\s+([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$")
_INT_RE = re.compile(r"^[+-]?\d+$")
_FLOAT_RE = re.compile(r"^[+-]?(\d+\.\d*|\.\d+|\d+)([eE][+-]?\d+)?$")


def _parse_scalar(raw: str):
	"""Convertit une valeur scalaire brute vers son type Python — même sous-
	ensemble restreint de YAML que ai_import_painted.py::_parse_scalar
	(dupliqué ici, voir l'en-tête de ce fichier : ce dossier ne fait jamais
	dépendre un script d'un autre)."""
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
	"""Parseur d'un sous-ensemble STRICT de YAML — suffisant pour le schéma
	FIXE de painted_weapons.yaml (voir son en-tête) : des scalaires top-level,
	puis une clé `weapons:` suivie d'une liste d'items. Même grammaire que
	ai_import_painted.py::parse_manifest (dupliquée ici à dessein, voir
	l'en-tête de ce fichier), seul le nom de la clé de liste change
	("weapons" au lieu de "assets"). Lève `ValueError` sur toute ligne qui ne
	correspond à aucun des trois patrons attendus."""
	top: dict = {}
	items: list = []
	current: dict | None = None
	in_list = False
	for raw_line in text.splitlines():
		line = raw_line.rstrip("\n")
		stripped = line.strip()
		if not stripped or stripped.startswith("#"):
			continue
		if not in_list:
			if stripped == "weapons:":
				in_list = True
				continue
			m = _TOP_SCALAR_RE.match(line)
			if not m:
				raise ValueError(f"painted_weapons.yaml: ligne top-level invalide: {raw_line!r}")
			top[m.group(1)] = _parse_scalar(m.group(2))
			continue
		m_item = _LIST_ITEM_RE.match(line)
		if m_item:
			if current is not None:
				items.append(current)
			current = {m_item.group(1): _parse_scalar(m_item.group(2))}
			continue
		m_cont = _LIST_CONT_RE.match(line)
		if m_cont and current is not None:
			current[m_cont.group(1)] = _parse_scalar(m_cont.group(2))
			continue
		raise ValueError(f"painted_weapons.yaml: ligne inattendue dans 'weapons': {raw_line!r}")
	if current is not None:
		items.append(current)
	top["weapons"] = items
	return top


def resolve_manifest_entry(manifest: dict, weapon_id: str) -> dict:
	"""Entrée de `manifest["weapons"]` dont `id` == `weapon_id` — lève
	`KeyError` (message listant les ids connus) si absente."""
	for entry in manifest.get("weapons", []):
		if entry.get("id") == weapon_id:
			return entry
	known = sorted(e.get("id", "?") for e in manifest.get("weapons", []))
	raise KeyError(f"fit_weapon_painted: id \"{weapon_id}\" absent du manifeste (connus: {known})")


def resolved_texture_size(original_size: int, requested_size: int) -> int:
	"""Taille de texture finale — identique à
	ai_import_painted.py::resolved_texture_size (dupliquée ici) : jamais un
	agrandissement au-delà de l'original, toujours une taille standard quand
	l'original le permet."""
	if requested_size not in ALLOWED_TEXTURE_SIZES:
		raise ValueError(
			f"fit_weapon_painted: texture_size {requested_size} hors {ALLOWED_TEXTURE_SIZES}")
	if original_size <= 0:
		raise ValueError(f"fit_weapon_painted: taille de texture d'origine invalide ({original_size})")
	cap = min(original_size, requested_size)
	candidates = [s for s in ALLOWED_TEXTURE_SIZES if s <= cap]
	if candidates:
		return max(candidates)
	return original_size


def _resolve_path(maybe_relative: str, root: str) -> str:
	if os.path.isabs(maybe_relative):
		return maybe_relative
	return os.path.normpath(os.path.join(root, maybe_relative))


def repo_root() -> str:
	return os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def longest_axis_index(extent: tuple) -> int:
	"""Index (0=X, 1=Y, 2=Z) de l'axe le plus long d'une bbox — l'axe du canon
	sur les 10 sources Tripo Studio livrées (bbox normalisée sur [-0.5, 0.5]
	le long de cet axe, voir l'en-tête du manifeste ; jamais Z, qui porte
	toujours la hauteur/le sol sur ces mêmes sources)."""
	best = 0
	for i in (1, 2):
		if extent[i] > extent[best]:
			best = i
	return best


def pick_muzzle_sign(radius_min_end: float, radius_max_end: float) -> int:
	"""Laquelle des deux extrémités de l'axe canon est la bouche ? Heuristique
	A3D-20 (même rationale "vérifié, jamais deviné" que le reste de ce
	dossier) : la bouche du canon est TOUJOURS la partie la plus FINE d'une
	arme (le corps/la crosse/la poignée sont plus larges) — l'extrémité dont
	le rayon (distance max à l'axe, voir `axis_end_radius`) est le plus petit
	l'emporte. `+1` si c'est l'extrémité MAXIMALE de l'axe détecté, `-1` si
	c'est la MINIMALE. Égalité stricte (cas dégénéré, jamais rencontré sur les
	10 sources réelles) : `+1` par défaut, jamais une exception — un
	`flip_muzzle` de manifeste reste la voie de correction si ce choix par
	défaut se révèle faux au rendu."""
	return -1 if radius_min_end < radius_max_end else 1


def rotation_for_alignment(length_axis: int, muzzle_sign: int) -> tuple:
	"""Rotation (degrés Euler XYZ) qui amène l'axe canon détecté
	(`length_axis`, voir `longest_axis_index`) sur **+Y** (bouche en avant,
	repère Blender après import glTF — voir l'en-tête de ce fichier), bouche
	du côté indiqué par `muzzle_sign` (voir `pick_muzzle_sign`), SANS jamais
	perturber l'axe "haut" Z (invariant Tripo Studio vérifié par sondage :
	base au sol sur Z, voir l'en-tête du manifeste) : seule une rotation
	AUTOUR de Z peut donc jamais servir ici. `length_axis == 2` (l'axe canon
	détecté serait Z) viole cet invariant -- lève `ValueError` plutôt que de
	deviner une réorientation, jamais rencontré sur les 10 sources réelles
	(voir la note de tête du manifeste)."""
	if length_axis == 0:  # canon sur X -> tourner autour de Z pour l'amener sur Y
		return (0.0, 0.0, 90.0 if muzzle_sign > 0 else -90.0)
	if length_axis == 1:  # canon déjà sur Y -> identité, ou demi-tour si la bouche est côté -Y
		return (0.0, 0.0, 0.0 if muzzle_sign > 0 else 180.0)
	raise ValueError(
		f"fit_weapon_painted: axe canon détecté sur Z (extent index {length_axis}) — "
		"viole l'invariant \"base au sol\" des sources Tripo Studio (voir l'en-tête du "
		"manifeste), jamais réorienté en silence")


def scale_factor_for_length(raw_extent: float, target_extent: float) -> float:
	"""Facteur d'échelle UNIFORME qui porte la longueur brute (axe canon,
	`raw_extent`) à la longueur cible (celle de la référence bpy le long du
	même axe, `target_extent`) — même calcul que
	ai_import_painted.py::scale_factor_for_height, renommé ici pour refléter
	l'axe réellement mis à l'échelle (longueur, pas hauteur)."""
	if raw_extent <= 0:
		raise ValueError(f"fit_weapon_painted: longueur brute invalide ({raw_extent})")
	if target_extent <= 0:
		raise ValueError(f"fit_weapon_painted: longueur cible invalide ({target_extent})")
	return target_extent / raw_extent


def forward_translation(scaled_min_forward: float, target_min_forward: float) -> float:
	"""Translation (le long de l'axe canon, +Y) qui aligne l'extrémité MINIMALE
	(côté crosse) du maillage Tripo déjà mis à l'échelle sur celle de la
	référence bpy — l'extrémité MAXIMALE (bouche) s'aligne alors d'elle-même,
	les deux longueurs étant déjà égales par construction
	(`scale_factor_for_length`)."""
	return target_min_forward - scaled_min_forward


def lateral_center_translation(scaled_min: float, scaled_max: float) -> float:
	"""Translation qui recentre une plage (largeur X, ou hauteur Z avant
	nudge manuel) sur 0 — les références bpy ont toujours une largeur
	symétrique autour de la poignée (voir tools/blender/make_weapons.py,
	tous les gabarits centrés sur X=0)."""
	return -(scaled_min + scaled_max) / 2.0


def build_jobs(cli: dict, manifest: dict | None, root: str) -> list:
	"""Résout les jobs à traiter (chacun un dict prêt pour `process_weapon` :
	`id`, `source`, `current_path`, `backup_path`, `budget_tris`,
	`texture_size`, `flip_muzzle`, `z_offset`, `x_offset`) à partir des
	arguments CLI déjà parsés (`cli`, un dict simple — voir `parse_args`) et
	du manifeste déjà parsé. Deux modes, mutuellement exclusifs :
	  - `cli["process_all"]` : TOUTES les entrées du manifeste.
	  - `cli["weapon_id"]` : UNE entrée par son id.
	Lève `ValueError` (jamais un `sys.exit`, laissé à `main()`) si ni l'un ni
	l'autre n'est fourni, ou si `manifest` est absent."""
	if manifest is None:
		raise ValueError("fit_weapon_painted: --manifest requis (--all ou --id)")
	if cli.get("process_all"):
		return [_job_from_entry(e, manifest, root) for e in manifest["weapons"]]
	if cli.get("weapon_id"):
		entry = resolve_manifest_entry(manifest, cli["weapon_id"])
		return [_job_from_entry(entry, manifest, root)]
	raise ValueError("fit_weapon_painted: --all ou --id requis")


def _job_from_entry(entry: dict, manifest: dict, root: str) -> dict:
	weapon_id = entry.get("id")
	if not weapon_id:
		raise ValueError(f"fit_weapon_painted: entrée de manifeste sans \"id\": {entry!r}")
	if not entry.get("source"):
		raise ValueError(f"fit_weapon_painted: \"{weapon_id}\" n'a pas de champ \"source\"")
	weapons_dir = _resolve_path(manifest["weapons_dir"], root)
	backup_dir = _resolve_path(manifest["backup_dir"], root)
	return {
		"id": weapon_id,
		"source": _resolve_path(entry["source"], root),
		"current_path": os.path.join(weapons_dir, f"{weapon_id}.glb"),
		"backup_path": os.path.join(backup_dir, f"{weapon_id}.glb"),
		"budget_tris": int(entry["budget_tris"]) if entry.get("budget_tris") is not None
			else int(manifest.get("default_budget_tris", DEFAULT_BUDGET_TRIS)),
		"texture_size": int(entry["texture_size"]) if entry.get("texture_size") is not None
			else int(manifest.get("default_texture_size", DEFAULT_TEXTURE_SIZE)),
		"flip_muzzle": bool(entry["flip_muzzle"]) if entry.get("flip_muzzle") is not None else False,
		"z_offset": float(entry["z_offset"]) if entry.get("z_offset") is not None else 0.0,
		"x_offset": float(entry["x_offset"]) if entry.get("x_offset") is not None else 0.0,
	}


# ---------------------------------------------------------------------------
# Fonctions dépendantes de bpy — jamais appelées hors de Blender.
# ---------------------------------------------------------------------------

def import_asset(path: str) -> list:
	ext = os.path.splitext(path)[1].lower()
	if ext in (".glb", ".gltf"):
		bpy.ops.import_scene.gltf(filepath=path)
	else:
		raise ValueError(f"fit_weapon_painted: extension non supportée: {ext!r} (attendu .glb/.gltf)")
	return [o for o in bpy.context.scene.objects if o.type == 'MESH']


def _bbox_world(obj):
	"""Bbox monde (min, max — `mathutils.Vector`) de `obj`."""
	corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
	mins = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
	maxs = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
	return mins, maxs


def merge_by_distance(obj, ratio: float = MERGE_DIST_RATIO) -> int:
	"""Fusionne les sommets quasi confondus — même mesure relative que
	ai_import_painted.py::merge_by_distance (dupliquée ici). Renvoie le
	nombre de sommets retirés."""
	mins, maxs = _bbox_world(obj)
	diag = max((maxs - mins).length, 1e-6)
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


def _remove_duplicate_faces(obj) -> int:
	"""Retire toute face qui partage EXACTEMENT le même ensemble de sommets
	qu'une face déjà vue — même défaut de génération IA que
	ai_import_painted.py::_remove_duplicate_faces_bm (dupliqué ici)."""
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
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
	bm.to_mesh(me)
	bm.free()
	me.update()
	return len(dupes)


def assert_up_axis_is_z(obj, tolerance_m: float = UP_AXIS_FLOOR_TOLERANCE_M) -> None:
	"""Vérifie l'invariant Tripo Studio (voir l'en-tête du manifeste) : la
	base du maillage touche le sol sur Z (min Z ~ 0). Lève `ValueError` sinon
	— jamais un alignement deviné sur un repère hors invariant."""
	mins, _ = _bbox_world(obj)
	if abs(mins.z) > tolerance_m:
		raise ValueError(
			f"fit_weapon_painted: \"{obj.name}\" ne repose pas au sol sur Z (min Z = {mins.z:.4f}, "
			f"tolérance {tolerance_m}) — invariant Tripo Studio violé, voir l'en-tête du manifeste")


def axis_end_radius(obj, axis_index: int, take_min_end: bool, frac: float = END_BAND_FRACTION) -> float:
	"""Rayon (distance max au centre local, sur les deux axes autres que
	`axis_index`) des sommets situés dans la bande `frac` la plus proche de
	l'extrémité MIN (`take_min_end=True`) ou MAX de `axis_index` — sert à
	`pick_muzzle_sign` à distinguer la bouche (fine) de la crosse/poignée
	(plus large). `0.0` si la bande est vide (jamais rencontré en pratique)."""
	verts = obj.data.vertices
	other = [i for i in range(3) if i != axis_index]
	axis_vals = [v.co[axis_index] for v in verts]
	lo, hi = min(axis_vals), max(axis_vals)
	band = max((hi - lo) * frac, 1e-6)
	if take_min_end:
		sel = [v.co for v in verts if v.co[axis_index] <= lo + band]
	else:
		sel = [v.co for v in verts if v.co[axis_index] >= hi - band]
	if not sel:
		return 0.0
	a_vals = [c[other[0]] for c in sel]
	b_vals = [c[other[1]] for c in sel]
	ca = sum(a_vals) / len(a_vals)
	cb = sum(b_vals) / len(b_vals)
	return max(math.hypot(a - ca, b - cb) for a, b in zip(a_vals, b_vals))


def read_bpy_reference(path: str) -> dict:
	"""Importe la RÉFÉRENCE bpy (la sauvegarde, voir `backup_bpy_original` —
	jamais le fichier courant) dans une scène vide dédiée et en extrait tout
	ce dont l'alignement/les ancres ont besoin, sous forme de VALEURS SIMPLES
	(tuples/floats — la scène est remise à zéro juste après, voir
	`toonkit.reset_scene`, donc aucun objet bpy de cette référence ne doit
	survivre à cet appel) : longueur le long de +Y (axe canon, voir l'en-tête
	de ce fichier), bornes min/max de cette même longueur, largeur (X)
	min/max, et positions LOCALES des empties "Muzzle"/"Foregrip". Lève
	`RuntimeError` si l'un des deux empties est absent (arme bpy malformée)."""
	toonkit.reset_scene()
	mesh_objs = import_asset(path)
	if not mesh_objs:
		raise RuntimeError(f"fit_weapon_painted: aucun mesh dans la référence {path}")
	obj = toonkit.join(mesh_objs) if len(mesh_objs) > 1 else mesh_objs[0]
	mins, maxs = _bbox_world(obj)
	muzzle = next((o for o in bpy.context.scene.objects if o.name == "Muzzle"), None)
	foregrip = next((o for o in bpy.context.scene.objects if o.name == "Foregrip"), None)
	if muzzle is None or foregrip is None:
		raise RuntimeError(
			f"fit_weapon_painted: \"Muzzle\"/\"Foregrip\" introuvable(s) dans la référence {path}")
	info = {
		"min_forward": mins.y, "max_forward": maxs.y,
		"min_lateral": mins.x, "max_lateral": maxs.x,
		"muzzle_local": tuple(muzzle.location), "foregrip_local": tuple(foregrip.location),
	}
	toonkit.reset_scene()
	return info


def keep_painted_material(obj, weapon_id: str, texture_size: int) -> dict:
	"""Garde CHAQUE matériau importé qui porte une image Base Color — JAMAIS
	remplacé par une couleur de palette (même politique que
	ai_import_painted.py::keep_painted_materials, dupliquée ici) — et le
	RENOMME "<weapon_id>_painted" (ou "<weapon_id>_painted_N" au-delà du
	premier) pour que ViewModel.gd le distingue des anciens slots
	"_body"/"_grip"/"_metal"/"_accent" du bpy en blocs. Un matériau SANS
	image (couleur plate résiduelle, jamais rencontré sur les 10 sources
	réelles) est laissé tel quel, sans renommage. Renvoie
	`{"materials": [...], "images_kept": [...]}`."""
	me = obj.data
	kept_images = []
	report = []
	painted_index = 0
	for mat in list(me.materials):
		if mat is None:
			continue
		image = _material_base_color_image(mat)
		if image is None:
			report.append({"name": mat.name, "has_texture": False})
			continue
		orig_w, orig_h = image.size
		new_w = resolved_texture_size(orig_w, texture_size)
		new_h = resolved_texture_size(orig_h, texture_size)
		if (new_w, new_h) != (orig_w, orig_h):
			image.scale(new_w, new_h)
		new_name = f"{weapon_id}_painted" if painted_index == 0 else f"{weapon_id}_painted_{painted_index}"
		mat.name = new_name
		painted_index += 1
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
		report.append({"name": new_name, "has_texture": True, "image": image.name,
			"texture_size": [new_w, new_h]})
	return {"materials": report, "images_kept": kept_images}


def _material_base_color_image(mat):
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


def _apply_modifier(obj, modifier) -> None:
	name = modifier.name
	index = obj.modifiers.find(name)
	if index < 0:
		raise RuntimeError(f"fit_weapon_painted: modificateur \"{name}\" introuvable sur \"{obj.name}\"")
	if index != 0:
		with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj]):
			move_result = bpy.ops.object.modifier_move_to_index(modifier=name, index=0)
		if 'FINISHED' not in move_result:
			raise RuntimeError(
				f"fit_weapon_painted: impossible de remonter \"{name}\" en tête de pile sur "
				f"\"{obj.name}\" ({move_result!r})")
	with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj]):
		apply_result = bpy.ops.object.modifier_apply(modifier=name)
	if 'FINISHED' not in apply_result:
		raise RuntimeError(
			f"fit_weapon_painted: bpy.ops.object.modifier_apply a échoué ({apply_result!r}) pour "
			f"\"{name}\" sur \"{obj.name}\"")
	if obj.modifiers.find(name) >= 0:
		obj.modifiers.remove(modifier)


def _decimate_planar_pass(obj) -> None:
	mod = obj.modifiers.new("fit_weapon_painted_decimate_planar", type='DECIMATE')
	mod.decimate_type = 'DISSOLVE'
	mod.angle_limit = DECIMATE_PLANAR_ANGLE_LIMIT
	_apply_modifier(obj, mod)
	obj.data.update()


def decimate_to_budget(obj, budget: int, max_iterations: int = DECIMATE_MAX_ITERATIONS) -> int:
	"""Decimate COLLAPSE itératif jusqu'au budget de tris — même algorithme
	que ai_import_painted.py::decimate_to_budget (dupliqué ici). No-op
	immédiat si déjà sous le budget (cas courant : sources Tripo à
	3,9-5,7k tris pour un budget de 8000)."""
	planar_retries = 0
	for _ in range(max_iterations):
		tris = toonkit.tri_count(obj)
		if tris <= budget:
			return tris
		ratio = max(0.02, min(0.95, budget / float(tris)))
		mod = obj.modifiers.new("fit_weapon_painted_decimate", type='DECIMATE')
		mod.decimate_type = 'COLLAPSE'
		mod.ratio = ratio
		_apply_modifier(obj, mod)
		obj.data.update()
		new_tris = toonkit.tri_count(obj)
		if new_tris > budget and new_tris >= tris * DECIMATE_STALL_RATIO and planar_retries < 3:
			planar_retries += 1
			_decimate_planar_pass(obj)
	return toonkit.tri_count(obj)


def add_anchor_empty(obj, name: str, local_pos: tuple):
	"""Ajoute un empty "Muzzle"/"Foregrip" enfant de `obj`, à la position
	LOCALE `local_pos` — même construction que
	tools/blender/make_weapons.py::build (PLAIN_AXES, `ANCHOR_EMPTY_DISPLAY_SIZE`),
	copiée telle quelle depuis la référence bpy (voir `read_bpy_reference`),
	JAMAIS recalculée."""
	empty = bpy.data.objects.new(name, None)
	empty.empty_display_type = 'PLAIN_AXES'
	empty.empty_display_size = ANCHOR_EMPTY_DISPLAY_SIZE
	empty.location = Vector(local_pos)
	bpy.context.scene.collection.objects.link(empty)
	empty.parent = obj
	return empty


def backup_bpy_original(current_path: str, backup_path: str) -> bool:
	"""Copie l'arme bpy COURANTE (`current_path`) sous `backup_path` — mais
	SEULEMENT si cette sauvegarde n'existe pas déjà : un ré-lancement de ce
	script (arme déjà peinte par un run précédent) ne doit JAMAIS écraser
	l'original par sa propre sortie peinte. Renvoie `True` si une copie a
	réellement eu lieu."""
	if os.path.isfile(backup_path):
		return False
	os.makedirs(os.path.dirname(backup_path), exist_ok=True)
	if not os.path.isfile(current_path):
		raise RuntimeError(f"fit_weapon_painted: arme bpy introuvable à sauvegarder: {current_path}")
	shutil.copy2(current_path, backup_path)
	sidecar = os.path.splitext(current_path)[0] + ".json"
	if os.path.isfile(sidecar):
		shutil.copy2(sidecar, os.path.splitext(backup_path)[0] + ".json")
	return True


def _augment_sidecar(glb_path: str, source: str, fitted_to: str) -> str:
	"""Écrit/augmente le sidecar JSON à côté de `glb_path` avec
	`"painted": true`, `"source"` et `"fitted_to"` (chemin de la référence
	bpy utilisée pour l'alignement) — même politique que
	ai_import_painted.py::_augment_sidecar (dupliquée ici) : le sidecar
	précédent (arme bpy en blocs, s'il existe déjà à cet emplacement) est
	remplacé, jamais fusionné (le rapport d'une géométrie bpy n'a plus de
	sens une fois celle-ci remplacée par la version peinte)."""
	sidecar_path = os.path.splitext(glb_path)[0] + ".json"
	data = {}
	if os.path.isfile(sidecar_path):
		with open(sidecar_path, "r", encoding="utf-8") as f:
			try:
				data = json.load(f)
			except ValueError:
				data = {}
	data["painted"] = True
	data["source"] = source
	data["fitted_to"] = fitted_to
	with open(sidecar_path, "w", encoding="utf-8") as f:
		json.dump(data, f, indent=2, ensure_ascii=False)
	return sidecar_path


def process_weapon(job: dict) -> dict:
	"""Orchestration complète (voir la numérotation de l'en-tête de ce
	fichier) pour UNE arme. `job` : voir `build_jobs`/`_job_from_entry` (ou,
	en test, un dict construit à la main avec les mêmes clés). Renvoie le
	rapport complet (dict, aussi utile aux tests)."""
	weapon_id = job["id"]
	backed_up = backup_bpy_original(job["current_path"], job["backup_path"])
	reference = read_bpy_reference(job["backup_path"])

	toonkit.reset_scene()
	mesh_objs = import_asset(job["source"])
	if not mesh_objs:
		raise RuntimeError(f"fit_weapon_painted: aucun mesh dans la source {job['source']}")
	obj = toonkit.join(mesh_objs) if len(mesh_objs) > 1 else mesh_objs[0]

	assert_up_axis_is_z(obj)
	merged_vertices = merge_by_distance(obj)
	duplicate_faces = _remove_duplicate_faces(obj)

	material_report = keep_painted_material(obj, weapon_id, job["texture_size"])

	raw_mins, raw_maxs = _bbox_world(obj)
	extent = (raw_maxs.x - raw_mins.x, raw_maxs.y - raw_mins.y, raw_maxs.z - raw_mins.z)
	length_axis = longest_axis_index(extent)
	radius_min_end = axis_end_radius(obj, length_axis, take_min_end=True)
	radius_max_end = axis_end_radius(obj, length_axis, take_min_end=False)
	muzzle_sign = pick_muzzle_sign(radius_min_end, radius_max_end)
	if job.get("flip_muzzle"):
		muzzle_sign = -muzzle_sign
	rot_deg = rotation_for_alignment(length_axis, muzzle_sign)

	target_length = reference["max_forward"] - reference["min_forward"]
	scale = scale_factor_for_length(extent[length_axis], target_length)

	# `obj.rotation_mode` peut être 'QUATERNION' à la sortie de l'import glTF
	# (courant sur un asset susceptible de porter une animation) : `obj.
	# rotation_euler` est alors ignoré par la transform RÉELLE (seul
	# `obj.rotation_quaternion` compterait) — repasser explicitement en 'XYZ'
	# AVANT de poser `rotation_euler` est donc nécessaire, jamais un simple
	# oubli sans effet visible (vérifié par sondage : sans cette ligne,
	# l'objet ressort mis à l'échelle mais PAS tourné).
	obj.rotation_mode = 'XYZ'
	obj.rotation_euler = (math.radians(rot_deg[0]), math.radians(rot_deg[1]), math.radians(rot_deg[2]))
	obj.scale = (scale, scale, scale)
	toonkit.apply_transforms(obj)

	scaled_mins, scaled_maxs = _bbox_world(obj)
	ty = forward_translation(scaled_mins.y, reference["min_forward"])
	tx = lateral_center_translation(scaled_mins.x, scaled_maxs.x) + job.get("x_offset", 0.0)
	tz = job.get("z_offset", 0.0)
	obj.location = (tx, ty, tz)
	toonkit.apply_transforms(obj)

	decimate_to_budget(obj, job["budget_tris"])

	toonkit.weighted_normals(obj)
	toonkit.smooth_normal_attrs(obj)
	toonkit.bake_vertex_ao(obj)
	toonkit.curvature_edge_mask(obj)

	if obj.modifiers:
		raise RuntimeError(
			f"fit_weapon_painted: {len(obj.modifiers)} modificateur(s) encore empilé(s) sur "
			f"\"{obj.name}\" avant l'export ({[m.name for m in obj.modifiers]})")

	muzzle = add_anchor_empty(obj, "Muzzle", reference["muzzle_local"])
	foregrip = add_anchor_empty(obj, "Foregrip", reference["foregrip_local"])

	final_tris = toonkit.tri_count(obj)
	if final_tris > job["budget_tris"]:
		raise RuntimeError(
			f"fit_weapon_painted: budget dépassé après décimation : {final_tris} > "
			f"{job['budget_tris']} tris")

	bpy.ops.object.select_all(action='DESELECT')
	obj.select_set(True)
	muzzle.select_set(True)
	foregrip.select_set(True)
	os.makedirs(os.path.dirname(os.path.abspath(job["current_path"])), exist_ok=True)
	bpy.ops.export_scene.gltf(
		filepath=job["current_path"],
		export_format='GLB',
		use_selection=True,
		export_apply=True,
		export_yup=True,
		export_materials='EXPORT',
		export_vertex_color='ACTIVE',
		export_all_vertex_colors=True,
		export_attributes=True,
		export_cameras=False,
		export_lights=False,
		export_animations=False,
	)
	sidecar_path = _augment_sidecar(job["current_path"], source=job["source"], fitted_to=job["backup_path"])

	report = {
		"id": weapon_id,
		"output": os.path.abspath(job["current_path"]),
		"backup": os.path.abspath(job["backup_path"]),
		"backed_up_this_run": backed_up,
		"final_tris": final_tris,
		"scale_factor": scale,
		"length_axis": length_axis,
		"muzzle_sign": muzzle_sign,
		"merged_vertices": merged_vertices,
		"duplicate_faces_removed": duplicate_faces,
		"materials": material_report,
		"sidecar": sidecar_path,
	}
	print(f"FIT_WEAPON_PAINTED_OK {weapon_id} tris={final_tris} -> {job['current_path']}")
	return report


def run_turntable(glb_path: str, views: int = 8, size: int = 512, timeout_s: int = 600) -> str:
	"""Turntable dans un sous-process Blender dédié — identique à
	ai_import_painted.py::run_turntable (dupliqué ici)."""
	import subprocess
	cmd = [
		bpy.app.binary_path, "-b", "--factory-startup", "--python-exit-code", "1",
		"-P", TURNTABLE_SCRIPT, "--",
		"--in", glb_path, "--views", str(views), "--size", str(size),
	]
	proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
	if proc.returncode != 0:
		raise RuntimeError(
			f"fit_weapon_painted: le turntable a échoué (code {proc.returncode}) pour {glb_path}\n"
			f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}")
	lines = proc.stdout.splitlines()
	for i, line in enumerate(lines):
		if line.strip().startswith("TURNTABLE_OK") and i + 1 < len(lines):
			path = lines[i + 1].strip()
			if path:
				return path
	raise RuntimeError(
		f"fit_weapon_painted: pas de marqueur TURNTABLE_OK dans la sortie du turntable pour {glb_path}\n"
		f"--- stdout ---\n{proc.stdout}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> dict:
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	p = argparse.ArgumentParser()
	p.add_argument("--manifest", dest="manifest_path", required=True)
	p.add_argument("--id", dest="weapon_id", default=None)
	p.add_argument("--all", dest="process_all", action="store_true")
	p.add_argument("--skip-turntable", dest="skip_turntable", action="store_true")
	p.add_argument("--views", dest="views", type=int, default=8)
	p.add_argument("--size", dest="size", type=int, default=512)
	ns = p.parse_args(argv)
	return vars(ns)


def main() -> None:
	cli = parse_args()
	root = repo_root()
	manifest_path = _resolve_path(cli["manifest_path"], root)
	if not os.path.isfile(manifest_path):
		print(f"FIT_WEAPON_PAINTED_FAIL manifeste introuvable: {manifest_path}")
		sys.exit(1)
	with open(manifest_path, "r", encoding="utf-8") as f:
		manifest = parse_manifest(f.read())
	try:
		jobs = build_jobs(cli, manifest, root)
	except ValueError as exc:
		print(f"FIT_WEAPON_PAINTED_FAIL {exc}")
		sys.exit(1)

	failures = []
	for job in jobs:
		if not os.path.isfile(job["source"]):
			failures.append((job["id"], f"source introuvable: {job['source']}"))
			print(f"FIT_WEAPON_PAINTED_FAIL {job['id']}: source introuvable: {job['source']}")
			continue
		print(f"FIT_WEAPON_PAINTED_START {job['id']} <- {job['source']}")
		try:
			process_weapon(job)
			if not cli["skip_turntable"]:
				run_turntable(job["current_path"], views=cli["views"], size=cli["size"])
		except Exception as exc:  # noqa: BLE001 - rapporte chaque échec, continue les autres jobs
			failures.append((job["id"], str(exc)))
			print(f"FIT_WEAPON_PAINTED_FAIL {job['id']}: {exc}")
	if failures:
		sys.exit(1)


if __name__ == "__main__":
	main()
