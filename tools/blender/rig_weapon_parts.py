## tools/blender/rig_weapon_parts.py
## FP-11 -- contrat "arme v2" (docs/research/12_viewmodel_v2.md §3.3, cause racine §1.1) :
## les 7 armes peintes (A3D-20, fit_weapon_painted.py) ont leur origine et leurs ancres
## "Muzzle"/"Foregrip" copiees d'une reference bpy JAMAIS recalculees -- la bouche du canon
## se retrouve 15-20 cm sous le vrai canon, l'origine (donc la prise de la main droite) 12 cm
## sous la poignee du Ravage (AABB y min = 0 pour les 7, "sol du tourne-disque" Tripo Studio).
## Ce script repart de zero sur les REPERES et la DECOUPE, sans toucher au v1 :
##   1. copie UNE FOIS assets/models/weapons/<id>.glb vers _painted_v1/<id>.glb (entree
##      figee, rejouable -- meme politique que fit_weapon_painted.py::backup_bpy_original,
##      jamais ecrasee par une sortie v2 d'un run precedent) ;
##   2. importe _painted_v1/<id>.glb et DEPLACE LE MAILLAGE (translation + echelle
##      uniforme, jamais une rotation) pour que le repere "Grip" du manifeste tombe sur
##      l'ORIGINE : l'echelle porte la longueur MESUREE de la poignee (`grip_span_m`) a
##      `target_grip_length_m` (§3.3 : 0,10-0,13 m pour une main x1,15) ;
##   3. decoupe les pieces mobiles nommees (§3.3) par boite (coordonnees du manifeste,
##      transformees par la MEME transformation) -- classification par face (le centroide
##      de chaque face tombe ou non dans la boite, voir `_delete_faces_by_boxes`), PAS un
##      modificateur BOOLEAN : mesure par sondage (rapport de tache FP-11), les solveurs
##      EXACT et FAST perdent silencieusement de la geometrie sur ces sources Tripo Studio
##      (maillage non garanti etanche) -- trous bouches ensuite ;
##   4. pose les 6 reperes orientes (canon -Z, haut +Y apres export) : Grip = l'origine,
##      Foregrip/Sight/MagWell/Eject transformes depuis le manifeste, Muzzle MESURE sur le
##      maillage (centre de la face la plus avancee du canon, `bore_tip_point`) ;
##   5. verifie GEOMETRIQUEMENT chaque critere d'acceptation FP-11 (voir `process_weapon`)
##      et ECHOUE FORT (RuntimeError, jamais un warning silencieux) si un seul est hors
##      tolerance ;
##   6. exporte assets/models/weapons/v2/<id>.glb + un sidecar JSON (rapport complet, dont
##      l'IoU -- tests/combat/test_weapon_models_v2.gd le relit plutot que de reimplementer
##      la rasterisation IoU en GDScript ; tous les autres criteres y sont REMESURES sur le
##      .glb exporte, independamment de ce script).
##
##   blender -b --factory-startup --python-exit-code 1 -P tools/blender/rig_weapon_parts.py -- \
##       --manifest tools/ai3d/manifests/weapon_rigs.yaml --all
##   # ou une seule arme :
##   blender -b --factory-startup --python-exit-code 1 -P tools/blender/rig_weapon_parts.py -- \
##       --manifest tools/ai3d/manifests/weapon_rigs.yaml --id ravage
##
## Repere de travail -- IDENTIQUE a fit_weapon_painted.py (voir son en-tete) : un .glb deja
## exporte par ce pipeline (export_yup=True) reimporte ici via bpy.ops.import_scene.gltf
## ressort dans le repere NATIF Z-up de Blender, canon +Y, haut +Z, largeur X (+X = droite
## du tireur) -- c'est le repere de TOUTES les coordonnees de
## tools/ai3d/manifests/weapon_rigs.yaml. L'export final (export_yup=True) restitue la
## convention Godot "canon -Z, haut +Y, droite +X".
##
## DEFINITIONS MESURABLES (revue du lead du 2026-09-25 : les reperes doivent etre POSES sur
## la bonne piece, chaque critere relu sur le .glb par tests/combat/test_weapon_models_v2.gd) :
##   - Grip : paume droite sur la poignee (creux de la main, haut-arriere de la poignee), a
##     <= 1,0 cm de la surface, a l'interieur du maillage (enferme : un rayon tire dans
##     chacune des 6 directions X/Y/Z touche la matiere) ET de la silhouette de profil, et
##     "a la hauteur du pontet, sous le bas de la carcasse" : entre le bas et le haut de
##     l'ouverture du pontet (`trigger_guard_opening`), le haut de cette ouverture etant la
##     ou la queue de detente sort de la carcasse -- definition commune aux 7 armes, crosses
##     a poignee pistolet comme crosses a poignet ;
##   - Foregrip / Sight / MagWell / Eject : a <= 1,5 cm de la surface du maillage ;
##   - Muzzle : centre de la face la plus avancee du canon (axe de l'ame), dans la bande de
##     2 mm du sommet le plus en avant -- le rayon tire de la bouche vers l'arriere doit
##     toucher le canon a <= 20 cm (le repere est bien DEVANT de la matiere, sur l'axe) ;
##   - Sight : >= 3 cm au-dessus de l'axe du canon (hauteur du Muzzle) ; axe Sight->Muzzle
##     sans cant lateral (<= 1,5°, voir la note de lecture ci-dessous).
##
## NOTE DE LECTURE sur "axe Sight->Muzzle a <= 1,5° de -Z, haut = +Y ± 2°" (critere
## d'acceptation FP-11) : lu comme un angle 3D plein entre le vecteur Sight->Muzzle et
## (0,0,-1) EXPORT, ce critere serait INCOMPATIBLE avec "Sight >= 3 cm au-dessus de l'axe
## du canon" du meme paragraphe (3 cm d'ecart vertical sur un rayon de visee de 15-50 cm
## donne 3,4-11°, jamais <= 1,5°). La tolerance porte donc sur la deviation LATERALE (aucun
## cant gauche-droite), l'elevation etant couverte par le critere "3 cm" ; "haut = +Y ± 2°"
## porte sur l'orientation des reperes (verifiee cote Godot).
##
## Ce fichier importe bpy/bmesh dans un bloc try/except (meme convention que le reste de ce
## dossier) : les fonctions de manifeste/geometrie/rasterisation restent testables par
## `python -m pytest` sans sous-processus Blender -- voir
## tools/blender/tests/test_rig_weapon_parts.py (couvre aussi tools/blender/weapon_blueprint.py,
## mesure/geometrie communes a la tache FP-11).
from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import sys
from collections import deque

try:
	import bpy
	import bmesh
	from mathutils import Matrix, Vector
except ImportError:  # pragma: no cover - permet de tester la logique manifeste/geometrie hors Blender
	bpy = None
	bmesh = None
	Matrix = None
	Vector = None

if bpy is not None:
	sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
	import toonkit  # noqa: E402

# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------

DEFAULT_BUDGET_TRIS = 8000            # plafond dur FP-11 (identique A3D-20)
DEFAULT_TARGET_GRIP_LENGTH_M = 0.115  # milieu de la fourchette §3.3 (0,10-0,13 m)
GRIP_LENGTH_RANGE_M = (0.10, 0.13)    # fourchette §3.3 de la longueur de poignee APRES echelle
DEFAULT_MIN_IOU = 0.98
GRIP_MAX_SURFACE_DIST_M = 0.010       # Grip : <= 1,0 cm de la surface (revue du lead)
ANCHOR_MAX_SURFACE_DIST_M = 0.015     # Foregrip/Sight/MagWell/Eject : <= 1,5 cm de la surface
SIGHT_MIN_ELEVATION_M = 0.03          # Sight : >= 3 cm au-dessus de l'axe du canon
SIGHT_MUZZLE_MAX_LATERAL_DEG = 1.5    # axe Sight->Muzzle : <= 1,5° (voir la note de lecture)
MUZZLE_TIP_BAND_M = 0.002             # bande (le long de l'axe canon) consideree "face avant"
# Rayon bouche -> arriere : de la matiere a <= 20 cm sur l'axe. Pas 0 : une ame modelisee
# (Magnum : 13 cm de vide) ou un tromblon creux (Fracas : 3 cm) laissent du vide devant.
MUZZLE_MAX_BORE_DEPTH_M = 0.20
IOU_GRID_RESOLUTION = 256             # cellules de la grille de rasterisation profil (Y/Z)
# Ouverture du pontet (silhouette de profil, fenetre autour du Grip) : cellule de 2,5 mm,
# fenetre 22 cm vers l'avant, 6 cm vers l'arriere, +-10 cm en hauteur -- le pontet est
# toujours juste devant la poignee (mesure sur les 7 planches v1 : 5-13 cm devant le Grip).
GUARD_CELL_M = 0.0025
GUARD_WINDOW_FRONT_M = 0.22
GUARD_WINDOW_BACK_M = 0.06
GUARD_WINDOW_HALF_HEIGHT_M = 0.10
GUARD_MAX_VERTICAL_GAP_M = 0.06       # l'ouverture doit chevaucher [Grip - 6 cm, Grip + 6 cm]
GUARD_MIN_AREA_M2 = 1.0e-4            # 1 cm2 : en dessous, un jour entre deux pieces, pas un pontet
ANCHOR_EMPTY_DISPLAY_SIZE = 0.03


# ---------------------------------------------------------------------------
# Fonctions pures -- manifeste, transformation, geometrie, rasterisation.
# Aucune dependance bpy : testables directement par pytest.
# ---------------------------------------------------------------------------

_TOP_SCALAR_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$")
_INT_RE = re.compile(r"^[+-]?\d+$")
_FLOAT_RE = re.compile(r"^[+-]?(\d+\.\d*|\.\d+|\d+)([eE][+-]?\d+)?$")
_VEC3_RE = re.compile(
	r"^\[\s*([+-]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?)\s*,\s*"
	r"([+-]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?)\s*,\s*"
	r"([+-]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?)\s*\]$")


def _parse_scalar(raw: str):
	"""Meme sous-ensemble restreint de YAML que fit_weapon_painted.py::_parse_scalar
	(duplique ici a dessein : ce dossier ne fait jamais dependre un script d'un autre),
	plus un vecteur `[x, y, z]` inline (seule extension necessaire au schema de
	weapon_rigs.yaml, voir son en-tete)."""
	s = raw.strip()
	if not s:
		return ""
	m = _VEC3_RE.match(s)
	if m:
		return tuple(float(g) for g in m.groups())
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
	"""Parseur d'un sous-ensemble STRICT de YAML, schema FIXE de weapon_rigs.yaml (voir son
	en-tete) : scalaires top-level, puis `weapons:` -> liste d'armes (indentation 0 sous
	`- id: ...`, champs continuation a l'indentation 2), chaque arme portant `pieces:` ->
	liste de pieces (items ALIGNES sur "pieces:", donc aussi a l'indentation 2, sous
	`- name: ...`, champs continuation de piece a l'indentation 4). DEUX niveaux de
	nesting fixes, jamais plus -- pas un parseur YAML general. Leve `ValueError` (message
	precis) sur toute ligne hors de ce schema."""
	top: dict = {}
	weapons: list = []
	cur_weapon: dict | None = None
	cur_pieces: list | None = None
	cur_piece: dict | None = None
	section = "top"  # "top" -> "weapons" -> (par arme) "pieces"
	for raw_line in text.splitlines():
		line = raw_line.rstrip("\n")
		stripped = line.strip()
		if not stripped or stripped.startswith("#"):
			continue
		indent = len(line) - len(line.lstrip(" "))

		if section == "top":
			if stripped == "weapons:":
				section = "weapons"
				continue
			m = _TOP_SCALAR_RE.match(stripped)
			if not m:
				raise ValueError(f"weapon_rigs.yaml: ligne top-level invalide: {raw_line!r}")
			top[m.group(1)] = _parse_scalar(m.group(2))
			continue

		if indent == 0:
			if not stripped.startswith("- "):
				raise ValueError(f"weapon_rigs.yaml: entree d'arme attendue (\"- id: ...\"): {raw_line!r}")
			if cur_weapon is not None:
				weapons.append(cur_weapon)
			m = _TOP_SCALAR_RE.match(stripped[2:])
			if not m or m.group(1) != "id":
				raise ValueError(f"weapon_rigs.yaml: une entree d'arme doit commencer par \"id\": {raw_line!r}")
			cur_weapon = {"id": _parse_scalar(m.group(2)), "pieces": []}
			cur_pieces = None
			cur_piece = None
			continue

		if indent == 2:
			if cur_weapon is None:
				raise ValueError(f"weapon_rigs.yaml: champ hors de toute arme: {raw_line!r}")
			if stripped.startswith("- "):
				# Item de la liste `pieces:` -- aligne sur sa propre cle (style YAML
				# courant), donc AU MEME niveau d'indentation que "pieces:".
				if cur_pieces is None:
					raise ValueError(f"weapon_rigs.yaml: entree de liste hors de \"pieces:\": {raw_line!r}")
				m = _TOP_SCALAR_RE.match(stripped[2:])
				if not m or m.group(1) != "name":
					raise ValueError(f"weapon_rigs.yaml: une piece doit commencer par \"name\": {raw_line!r}")
				cur_piece = {"name": _parse_scalar(m.group(2))}
				cur_pieces.append(cur_piece)
				continue
			cur_piece = None
			if stripped == "pieces:":
				cur_pieces = cur_weapon["pieces"]
				continue
			cur_pieces = None
			m = _TOP_SCALAR_RE.match(stripped)
			if not m:
				raise ValueError(f"weapon_rigs.yaml: champ d'arme invalide: {raw_line!r}")
			cur_weapon[m.group(1)] = _parse_scalar(m.group(2))
			continue

		if indent == 4:
			if cur_piece is None:
				raise ValueError(f"weapon_rigs.yaml: champ de piece hors de toute piece: {raw_line!r}")
			m = _TOP_SCALAR_RE.match(stripped)
			if not m:
				raise ValueError(f"weapon_rigs.yaml: champ de piece invalide: {raw_line!r}")
			cur_piece[m.group(1)] = _parse_scalar(m.group(2))
			continue

		raise ValueError(f"weapon_rigs.yaml: indentation inattendue ({indent}): {raw_line!r}")

	if cur_weapon is not None:
		weapons.append(cur_weapon)
	top["weapons"] = weapons
	return top


def resolve_manifest_entry(manifest: dict, weapon_id: str) -> dict:
	"""Entree de `manifest["weapons"]` dont `id` == `weapon_id` -- leve `KeyError`
	(message listant les ids connus) si absente."""
	for entry in manifest.get("weapons", []):
		if entry.get("id") == weapon_id:
			return entry
	known = sorted(e.get("id", "?") for e in manifest.get("weapons", []))
	raise KeyError(f"rig_weapon_parts: id \"{weapon_id}\" absent du manifeste (connus: {known})")


def _resolve_path(maybe_relative: str, root: str) -> str:
	if os.path.isabs(maybe_relative):
		return maybe_relative
	return os.path.normpath(os.path.join(root, maybe_relative))


def repo_root() -> str:
	return os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


# --- Transformation (echelle par la poignee, §3.3) --------------------------

def scale_factor_for_grip(grip_span_m: float, target_grip_length_m: float) -> float:
	"""Facteur d'echelle UNIFORME qui porte `grip_span_m` (longueur MESUREE de la poignee
	dans le maillage source, AVANT echelle) a `target_grip_length_m` (§3.3 : 0,10-0,13 m,
	`DEFAULT_TARGET_GRIP_LENGTH_M` = le milieu de cette fourchette)."""
	if grip_span_m <= 0:
		raise ValueError(f"rig_weapon_parts: grip_span_m invalide ({grip_span_m})")
	if target_grip_length_m <= 0:
		raise ValueError(f"rig_weapon_parts: target_grip_length_m invalide ({target_grip_length_m})")
	return target_grip_length_m / grip_span_m


def translation_for_grip_at_origin(grip_local: tuple, scale: float) -> tuple:
	"""Translation qui, APRES mise a l'echelle uniforme par `scale`, amene `grip_local`
	(coordonnees AVANT echelle) sur l'origine (0, 0, 0) -- c'est la definition meme de
	"Grip = l'origine" (§3.3) : le MAILLAGE se deplace, jamais le repere."""
	return tuple(-scale * c for c in grip_local)


def transform_point(point: tuple, scale: float, translation: tuple) -> tuple:
	"""`scale * point + translation` -- LA MEME transformation est appliquee a CHAQUE
	coordonnee du manifeste (reperes, boites de decoupe, pivots) et au maillage lui-meme
	(voir `process_weapon`) : aucune valeur n'est jamais recopiee "telle quelle" a travers
	un changement de repere (c'est exactement le defaut §1.1 que ce fichier corrige)."""
	return tuple(scale * c + t for c, t in zip(point, translation))


# --- Axe de visee -----------------------------------------------------------

def sight_lateral_angle_deg(sight_local: tuple, muzzle_local: tuple) -> float:
	"""Deviation LATERALE (cant gauche-droite) de l'axe Sight->Muzzle dans le repere de
	travail (X largeur, Y canon, Z hauteur) : angle entre la separation le long de l'axe
	canon (Y) et la separation laterale (X). L'elevation (Z) n'est PAS mesuree ici : elle
	est couverte par `SIGHT_MIN_ELEVATION_M` (voir la note de lecture en tete de fichier)."""
	forward = muzzle_local[1] - sight_local[1]
	lateral = muzzle_local[0] - sight_local[0]
	if forward == 0 and lateral == 0:
		return 0.0
	return math.degrees(math.atan2(abs(lateral), abs(forward)))


def sight_elevation_m(sight: tuple, muzzle: tuple) -> float:
	"""Hauteur (Z) du Sight au-dessus de l'axe du canon, pris a la hauteur du Muzzle."""
	return sight[2] - muzzle[2]


# --- Bouche du canon (remplace l'ancre bpy recopiee §1.1) -------------------

def bore_tip_point(vertices: list, band: float = MUZZLE_TIP_BAND_M) -> tuple:
	"""Bout du canon, sur l'axe de l'ame : centre (X, Z) de la boite englobante des
	sommets situes a `band` du Y maximal (la face la plus avancee), pose a ce Y maximal.
	Le centre de la face -- pas un sommet de son bord : sur une bouche evasee (tromblon du
	Fracas) ou une bague large (Pistolet), le bord est a plusieurs cm de l'axe, et la
	flamme/les traceurs doivent sortir de l'ame, pas de la levre."""
	if not vertices:
		raise ValueError("rig_weapon_parts: aucun sommet pour mesurer le bout du canon")
	if band < 0:
		raise ValueError(f"rig_weapon_parts: bande negative ({band})")
	max_y = max(v[1] for v in vertices)
	tier = [v for v in vertices if v[1] >= max_y - band]
	xs = [v[0] for v in tier]
	zs = [v[2] for v in tier]
	return ((min(xs) + max(xs)) / 2.0, max_y, (min(zs) + max(zs)) / 2.0)


# --- Rasterisation / IoU (silhouette de profil v2 contre v1 transforme) ------

def _edge_function(a: tuple, b: tuple, p: tuple) -> float:
	return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])


def point_in_triangle_2d(p: tuple, tri: tuple) -> bool:
	"""`True` si `p` (u, v) est dans le triangle 2D `tri` (bords inclus). Un triangle
	degenere (vu par la tranche) ne contient que les points de son segment."""
	a, b, c = tri
	d1 = _edge_function(a, b, p)
	d2 = _edge_function(b, c, p)
	d3 = _edge_function(c, a, p)
	has_neg = d1 < 0 or d2 < 0 or d3 < 0
	has_pos = d1 > 0 or d2 > 0 or d3 > 0
	return not (has_neg and has_pos)


def point_in_silhouette(p: tuple, triangles: list) -> bool:
	"""`True` si `p` tombe dans au moins un des triangles 2D (silhouette projetee)."""
	for tri in triangles:
		us = (tri[0][0], tri[1][0], tri[2][0])
		vs = (tri[0][1], tri[1][1], tri[2][1])
		if p[0] < min(us) or p[0] > max(us) or p[1] < min(vs) or p[1] > max(vs):
			continue
		if point_in_triangle_2d(p, tri):
			return True
	return False


def rasterize_triangles(triangles: list, bounds: tuple, resolution: int = IOU_GRID_RESOLUTION) -> set:
	"""Rasterise une liste de triangles 2D (`[(u0,v0),(u1,v1),(u2,v2)], ...`) sur une
	grille `resolution` x `resolution` couvrant `bounds` = (u_min, u_max, v_min, v_max) --
	renvoie l'ensemble des cellules (i, j) dont le CENTRE tombe dans au moins un triangle
	(bords inclus : deux triangles adjacents couvrent leur arete commune sans trou d'un
	pixel). Chaque triangle n'est teste que sur sa propre boite englobante en cellules."""
	u_min, u_max, v_min, v_max = bounds
	if resolution <= 0:
		raise ValueError(f"rig_weapon_parts: resolution de grille invalide ({resolution})")
	span_u = max(u_max - u_min, 1e-9)
	span_v = max(v_max - v_min, 1e-9)
	cell_u = span_u / resolution
	cell_v = span_v / resolution
	covered = set()
	for tri in triangles:
		a, b, c = tri
		i0 = max(0, int((min(a[0], b[0], c[0]) - u_min) / cell_u))
		i1 = min(resolution - 1, int((max(a[0], b[0], c[0]) - u_min) / cell_u))
		j0 = max(0, int((min(a[1], b[1], c[1]) - v_min) / cell_v))
		j1 = min(resolution - 1, int((max(a[1], b[1], c[1]) - v_min) / cell_v))
		for i in range(i0, i1 + 1):
			pu = u_min + (i + 0.5) * cell_u
			for j in range(j0, j1 + 1):
				if (i, j) in covered:
					continue
				if point_in_triangle_2d((pu, v_min + (j + 0.5) * cell_v), tri):
					covered.add((i, j))
	return covered


def iou_from_cells(cells_a: set, cells_b: set) -> float:
	"""Intersection-sur-union de deux ensembles de cellules -- 1.0 si les deux sont vides
	(silhouettes egales, meme vide), 0.0 si une seule l'est."""
	union = cells_a | cells_b
	if not union:
		return 1.0
	return len(cells_a & cells_b) / len(union)


def silhouette_iou(triangles_a: list, triangles_b: list, resolution: int = IOU_GRID_RESOLUTION) -> float:
	"""IoU de silhouette entre deux jeux de triangles 2D (voir `rasterize_triangles`) --
	bbox commune (union des deux jeux, + marge de 2 %) pour que les deux rasterisations
	partagent exactement la meme grille."""
	all_pts = [p for tri in (triangles_a + triangles_b) for p in tri]
	if not all_pts:
		return 1.0
	u_min = min(p[0] for p in all_pts)
	u_max = max(p[0] for p in all_pts)
	v_min = min(p[1] for p in all_pts)
	v_max = max(p[1] for p in all_pts)
	pad_u = max((u_max - u_min) * 0.02, 1e-4)
	pad_v = max((v_max - v_min) * 0.02, 1e-4)
	bounds = (u_min - pad_u, u_max + pad_u, v_min - pad_v, v_max + pad_v)
	return iou_from_cells(rasterize_triangles(triangles_a, bounds, resolution),
		rasterize_triangles(triangles_b, bounds, resolution))


# --- Ouverture du pontet ("bas de la carcasse") -----------------------------

def rasterize_window(triangles: list, window: tuple, cell: float) -> tuple:
	"""Rasterise les triangles 2D sur une grille de cellules CARREES de cote `cell`
	couvrant `window` = (u_min, u_max, v_min, v_max). Renvoie (cellules couvertes, nu, nv).
	Les triangles hors fenetre sont ignores (seule la region du pontet est analysee)."""
	u_min, u_max, v_min, v_max = window
	if cell <= 0:
		raise ValueError(f"rig_weapon_parts: cellule invalide ({cell})")
	if u_max <= u_min or v_max <= v_min:
		raise ValueError(f"rig_weapon_parts: fenetre vide {window}")
	nu = int(math.ceil((u_max - u_min) / cell))
	nv = int(math.ceil((v_max - v_min) / cell))
	covered = set()
	for tri in triangles:
		a, b, c = tri
		tu0, tu1 = min(a[0], b[0], c[0]), max(a[0], b[0], c[0])
		tv0, tv1 = min(a[1], b[1], c[1]), max(a[1], b[1], c[1])
		if tu1 < u_min or tu0 > u_max or tv1 < v_min or tv0 > v_max:
			continue
		i0 = max(0, int(math.floor((tu0 - u_min) / cell)))
		i1 = min(nu - 1, int(math.floor((tu1 - u_min) / cell)))
		j0 = max(0, int(math.floor((tv0 - v_min) / cell)))
		j1 = min(nv - 1, int(math.floor((tv1 - v_min) / cell)))
		for i in range(i0, i1 + 1):
			pu = u_min + (i + 0.5) * cell
			for j in range(j0, j1 + 1):
				if (i, j) in covered:
					continue
				if point_in_triangle_2d((pu, v_min + (j + 0.5) * cell), tri):
					covered.add((i, j))
	return covered, nu, nv


def enclosed_holes(cells: set, nu: int, nv: int) -> list:
	"""Composantes (4-connexes) de cellules VIDES qui ne touchent pas le bord de la grille
	-- les jours fermes de la silhouette (pontet, poignee de transport, crosse squelette).
	Une region vide reliee au bord est "dehors", meme si elle ressort de la fenetre et y
	revient : seules les ouvertures entierement cernees de matiere comptent."""
	outside = set()
	queue = deque()
	for i in range(nu):
		for j in (0, nv - 1):
			if (i, j) not in cells and (i, j) not in outside:
				outside.add((i, j))
				queue.append((i, j))
	for j in range(nv):
		for i in (0, nu - 1):
			if (i, j) not in cells and (i, j) not in outside:
				outside.add((i, j))
				queue.append((i, j))
	while queue:
		i, j = queue.popleft()
		for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			n = (i + di, j + dj)
			if 0 <= n[0] < nu and 0 <= n[1] < nv and n not in cells and n not in outside:
				outside.add(n)
				queue.append(n)
	seen = set()
	holes = []
	for i in range(nu):
		for j in range(nv):
			start = (i, j)
			if start in cells or start in outside or start in seen:
				continue
			comp = {start}
			seen.add(start)
			queue.append(start)
			while queue:
				ci, cj = queue.popleft()
				for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
					n = (ci + di, cj + dj)
					if 0 <= n[0] < nu and 0 <= n[1] < nv and n not in cells and n not in outside and n not in seen:
						seen.add(n)
						comp.add(n)
						queue.append(n)
			holes.append(comp)
	return holes


def trigger_guard_opening(triangles: list, grip_uv: tuple, cell: float = GUARD_CELL_M) -> dict | None:
	"""Ouverture du pontet dans la silhouette de profil (u = axe canon, + vers la bouche ;
	v = hauteur) : le jour ferme le plus proche du Grip, DEVANT lui (centroide en avant
	du Grip), d'au moins `GUARD_MIN_AREA_M2`, et dont la hauteur chevauche
	[Grip - 6 cm, Grip + 6 cm]. Renvoie {"top", "bottom", "back", "front", "area_m2"} en
	coordonnees de la vue, ou `None` si aucun jour ne convient. Son "top" est le bas de la
	carcasse (la ou la queue de detente en sort) : le critere "Grip a la hauteur du pontet,
	sous le bas de la carcasse" s'ecrit `bottom <= Grip.v <= top`."""
	gu, gv = grip_uv
	window = (gu - GUARD_WINDOW_BACK_M, gu + GUARD_WINDOW_FRONT_M,
		gv - GUARD_WINDOW_HALF_HEIGHT_M, gv + GUARD_WINDOW_HALF_HEIGHT_M)
	cells, nu, nv = rasterize_window(triangles, window, cell)
	best = None
	best_dist = math.inf
	for comp in enclosed_holes(cells, nu, nv):
		area = len(comp) * cell * cell
		if area < GUARD_MIN_AREA_M2:
			continue
		i_vals = [c[0] for c in comp]
		j_vals = [c[1] for c in comp]
		back = window[0] + min(i_vals) * cell
		front = window[0] + (max(i_vals) + 1) * cell
		bottom = window[2] + min(j_vals) * cell
		top = window[2] + (max(j_vals) + 1) * cell
		cu = window[0] + (sum(i_vals) / len(comp) + 0.5) * cell
		cv = window[2] + (sum(j_vals) / len(comp) + 0.5) * cell
		if cu <= gu:
			continue
		if top < gv - GUARD_MAX_VERTICAL_GAP_M or bottom > gv + GUARD_MAX_VERTICAL_GAP_M:
			continue
		dist = math.hypot(cu - gu, cv - gv)
		if dist < best_dist:
			best_dist = dist
			best = {"top": top, "bottom": bottom, "back": back, "front": front, "area_m2": area}
	return best


# --- Boites de decoupe d'une piece ------------------------------------------

def piece_boxes(piece_entry: dict) -> list:
	"""Boites de decoupe d'une piece du manifeste : `box_min`/`box_max` (obligatoire),
	plus `box2_min`/`box2_max` (optionnelle, toujours par paire) quand une seule boite ne
	peut pas separer la piece de ses voisines -- chargeur courbe du Ravage, dont le bas
	avance sous la levre du garde-main. Une face part avec la piece si son centroide tombe
	dans l'UNE des boites. Leve `ValueError` sur une paire incomplete ou une boite vide."""
	name = piece_entry.get("name", "?")
	boxes = []
	for prefix in ("box", "box2"):
		lo = piece_entry.get(f"{prefix}_min")
		hi = piece_entry.get(f"{prefix}_max")
		if lo is None and hi is None and prefix != "box":
			continue
		if lo is None or hi is None:
			raise ValueError(f"rig_weapon_parts: piece \"{name}\" : {prefix}_min/{prefix}_max incomplets")
		if any(a >= b for a, b in zip(lo, hi)):
			raise ValueError(f"rig_weapon_parts: piece \"{name}\" : {prefix} vide ({lo} -> {hi})")
		boxes.append((tuple(lo), tuple(hi)))
	return boxes


def point_in_boxes(point: tuple, boxes: list) -> bool:
	"""`True` si `point` tombe (bords inclus) dans au moins une des boites (min, max)."""
	return any(all(lo[i] <= point[i] <= hi[i] for i in range(3)) for lo, hi in boxes)


# ---------------------------------------------------------------------------
# Fonctions dependantes de bpy -- jamais appelees hors de Blender.
# ---------------------------------------------------------------------------

def import_asset(path: str) -> list:
	ext = os.path.splitext(path)[1].lower()
	if ext in (".glb", ".gltf"):
		bpy.ops.import_scene.gltf(filepath=path)
	else:
		raise ValueError(f"rig_weapon_parts: extension non supportee: {ext!r} (attendu .glb/.gltf)")
	return [o for o in bpy.context.scene.objects if o.type == 'MESH']


def _provenance_path(glb_path: str) -> str:
	"""Meme convention que tools/ai3d/licence_check.py::provenance_path_for :
	`<id>.provenance.json`, a cote du .glb."""
	stem = os.path.splitext(glb_path)[0]
	return f"{stem}.provenance.json"


def backup_painted_v1(current_path: str, backup_path: str) -> bool:
	"""Copie UNE FOIS `current_path` (assets/models/weapons/<id>.glb, v1 peint A3D-20) vers
	`backup_path` (_painted_v1/<id>.glb) -- jamais si `backup_path` existe deja (un
	re-lancement de ce script ne doit jamais l'ecraser). Copie aussi le sidecar de
	metadonnees (`<id>.json`) et la provenance de licence (`<id>.provenance.json`, note du
	lead 2026-09-25T19:27:35 -- tools/ai3d/licence_check.py exige ce fichier a cote de
	CHAQUE .glb, y compris une copie)."""
	if os.path.isfile(backup_path):
		return False
	os.makedirs(os.path.dirname(backup_path), exist_ok=True)
	if not os.path.isfile(current_path):
		raise RuntimeError(f"rig_weapon_parts: v1 introuvable a sauvegarder: {current_path}")
	shutil.copy2(current_path, backup_path)
	sidecar = os.path.splitext(current_path)[0] + ".json"
	if os.path.isfile(sidecar):
		shutil.copy2(sidecar, os.path.splitext(backup_path)[0] + ".json")
	provenance = _provenance_path(current_path)
	if os.path.isfile(provenance):
		shutil.copy2(provenance, _provenance_path(backup_path))
	return True


def _world_vertices(obj) -> list:
	mat = obj.matrix_world
	return [tuple(mat @ Vector(v.co)) for v in obj.data.vertices]


def bake_transform(obj, matrix) -> None:
	"""Cuit `matrix @ obj.matrix_world` dans le maillage et remet l'objet a l'identite :
	son origine EST ensuite l'origine monde (= Grip, voir `translation_for_grip_at_origin`)."""
	obj.data.transform(matrix @ obj.matrix_world)
	obj.matrix_world = Matrix.Identity(4)
	obj.data.update()


def rigid_matrix(scale: float, translation: tuple):
	"""Matrice `translation @ echelle uniforme` -- `transform_point` en forme bpy."""
	return Matrix.Translation(Vector(translation)) @ Matrix.Diagonal((scale, scale, scale, 1.0))


def _duplicate(obj, name: str):
	new_obj = bpy.data.objects.new(name, obj.data.copy())
	new_obj.matrix_world = obj.matrix_world.copy()
	bpy.context.scene.collection.objects.link(new_obj)
	return new_obj


def _face_centroid(face) -> tuple:
	n = len(face.verts)
	return (sum(v.co.x for v in face.verts) / n, sum(v.co.y for v in face.verts) / n,
		sum(v.co.z for v in face.verts) / n)


def _delete_faces_by_boxes(obj, boxes: list, keep_inside: bool) -> int:
	"""Supprime, sur le maillage de `obj` (objet a transform identite, coordonnees
	monde), toute face dont le CENTROIDE tombe dans l'une des `boxes` (`keep_inside=False`,
	utilise sur "Body") ou hors de toutes (`keep_inside=True`, utilise sur une piece) --
	classification par face, PAS un booleen geometrique (voir l'en-tete : un modificateur
	BOOLEAN perd de la geometrie sur ces sources non etanches). Renvoie le nombre de faces
	supprimees. La frontiere de coupe suit les aretes existantes ; `fill_holes` la
	reboucle ensuite."""
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
	to_delete = [f for f in bm.faces if point_in_boxes(_face_centroid(f), boxes) != keep_inside]
	if to_delete:
		bmesh.ops.delete(bm, geom=to_delete, context='FACES')
	bm.to_mesh(me)
	bm.free()
	me.update()
	return len(to_delete)


def _orient_caps_to_neighbors(bm, new_faces: list) -> int:
	"""Oriente chaque face de bouchage comme ses voisines d'origine : deux faces
	adjacentes coherentes parcourent leur arete commune en sens OPPOSES. Seuls les
	nouveaux caps sont retournes -- jamais une face d'origine : un recalcul global des
	normales (`recalc_face_normals` sur tout le corps) retourne des coques entieres de ces
	maillages Tripo a coques superposees (plaquettes de poignee sur la carcasse, mesure par
	sondage FP-11), ce qui les ferait disparaitre au rendu (faces arriere eliminees).
	Renvoie le nombre de caps retournes."""
	new_set = set(new_faces)
	flipped = []
	for face in new_faces:
		for loop in face.loops:
			neighbours = [lf for lf in loop.edge.link_faces if lf is not face and lf not in new_set]
			if not neighbours:
				continue
			other_loop = next(lp for lp in neighbours[0].loops if lp.edge == loop.edge)
			if other_loop.vert == loop.vert:
				flipped.append(face)
			break
	if flipped:
		bmesh.ops.reverse_faces(bm, faces=flipped)
	return len(flipped)


def fill_holes(obj) -> int:
	"""Bouche les trous ouverts par une decoupe boite (bords non-manifold, §3.3 "trous
	bouches") et oriente les caps comme leurs voisines (`_orient_caps_to_neighbors`) --
	les faces d'origine gardent leur enroulement exact. Renvoie le nombre de faces
	ajoutees."""
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
	boundary = [e for e in bm.edges if e.is_boundary]
	added = 0
	if boundary:
		res = bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
		new_faces = [f for f in res.get("faces", []) if f.is_valid]
		added = len(new_faces)
		_orient_caps_to_neighbors(bm, new_faces)
	bm.normal_update()
	bm.to_mesh(me)
	bm.free()
	me.update()
	return added


def cut_piece(source_obj, name: str, boxes: list, pivot: tuple):
	"""Duplique `source_obj`, ne garde que les faces dont le centroide tombe dans la boite,
	bouche les trous, pose l'origine sur `pivot` (§3.3 : "origine au pivot"). Leve
	`RuntimeError` si la boite ne capture aucune face (boite mal mesuree)."""
	piece = _duplicate(source_obj, name)
	_delete_faces_by_boxes(piece, boxes, keep_inside=True)
	if len(piece.data.polygons) == 0:
		raise RuntimeError(f"rig_weapon_parts: la boite de \"{name}\" ne capture aucune face")
	fill_holes(piece)
	offset = Matrix.Translation(-Vector(pivot))
	piece.data.transform(offset)
	piece.matrix_world = Matrix.Translation(Vector(pivot))
	piece.data.update()
	return piece


def remove_piece_from_body(body_obj, boxes: list) -> None:
	"""Retire du corps toute face dont le centroide tombe dans la boite (evite que "Body"
	duplique une piece decoupee par `cut_piece`), puis bouche les trous."""
	_delete_faces_by_boxes(body_obj, boxes, keep_inside=False)
	fill_holes(body_obj)


def _forward_up_rotation():
	"""Rotation IDENTITE dans le repere Blender : l'exporteur glTF (export_yup=True)
	convertit les axes d'un noeud comme ceux du monde, donc un empty sans rotation ressort
	en Godot avec -Z local = avant (canon) et +Y local = haut -- verifie cote Godot par
	test_every_v2_anchor_is_oriented_bore_forward_and_up."""
	return Matrix.Identity(4)


def add_anchor_empty(name: str, world_pos: tuple):
	empty = bpy.data.objects.new(name, None)
	empty.empty_display_type = 'ARROWS'
	empty.empty_display_size = ANCHOR_EMPTY_DISPLAY_SIZE
	empty.matrix_world = Matrix.Translation(Vector(world_pos)) @ _forward_up_rotation()
	bpy.context.scene.collection.objects.link(empty)
	return empty


def _closest_surface_point(obj, point_world: tuple):
	inv = obj.matrix_world.inverted()
	ok, loc, _normal, _index = obj.closest_point_on_mesh(inv @ Vector(point_world))
	if not ok:
		raise RuntimeError(f"rig_weapon_parts: closest_point_on_mesh a echoue sur \"{obj.name}\"")
	return obj.matrix_world @ loc


def distance_to_surface(objs: list, point_world: tuple) -> float:
	"""Distance du point a la surface la plus proche parmi `objs` (corps + pieces)."""
	return min((Vector(point_world) - _closest_surface_point(o, point_world)).length for o in objs)


AXIS_DIRECTIONS = ((1.0, 0.0, 0.0), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, -1.0, 0.0),
	(0.0, 0.0, 1.0), (0.0, 0.0, -1.0))


def _ray_hits(objs: list, origin: tuple, direction: tuple) -> bool:
	for obj in objs:
		inv = obj.matrix_world.inverted()
		ok, _loc, _n, _i = obj.ray_cast(inv @ Vector(origin), (inv.to_3x3() @ Vector(direction)).normalized())
		if ok:
			return True
	return False


def point_is_enclosed(objs: list, point_world: tuple) -> bool:
	"""`True` si un rayon tire du point dans CHACUNE des 6 directions X/Y/Z touche la
	matiere : le point est cerne par le maillage. Mesure robuste sur ces "smart mesh"
	Tripo non etanches et a coques superposees (plaquettes de poignee posees sur la
	carcasse), ou ni la parite de rayons ni la normale de la surface la plus proche ne
	disent le vrai (sondage FP-11 : normale d'une coque interne a 1,5 mm du Grip du
	Pistolet). Un point qui flotte a cote d'une piece a toujours une direction libre."""
	return all(_ray_hits(objs, point_world, d) for d in AXIS_DIRECTIONS)


def bore_depth(objs: list, muzzle_world: tuple) -> float:
	"""Distance parcourue par un rayon tire du Muzzle vers l'ARRIERE (-Y) avant de toucher
	la matiere (face avant pleine : ~0 ; tromblon creux : profondeur du cone). `inf` si
	le rayon ne touche rien -- repere a cote du canon, pas sur son axe."""
	best = math.inf
	origin = Vector(muzzle_world) + Vector((0.0, 0.001, 0.0))
	for obj in objs:
		inv = obj.matrix_world.inverted()
		ok, loc, _n, _i = obj.ray_cast(inv @ origin, (inv.to_3x3() @ Vector((0.0, -1.0, 0.0))).normalized())
		if ok:
			best = min(best, ((obj.matrix_world @ loc) - Vector(muzzle_world)).length)
	return best


def _triangles_2d(objs: list, axes: tuple = (1, 2)) -> list:
	"""Triangles (coordonnees monde, projetes sur `axes` -- (1,2) = (Y, Z), le plan de
	profil) de tous les maillages de `objs`, apres triangulation."""
	tris = []
	for obj in objs:
		bm = bmesh.new()
		bm.from_mesh(obj.data)
		bmesh.ops.triangulate(bm, faces=bm.faces)
		mat = obj.matrix_world
		for f in bm.faces:
			pts = [mat @ v.co for v in f.verts]
			tris.append(tuple((p[axes[0]], p[axes[1]]) for p in pts))
		bm.free()
	return tris


def maybe_replace_albedo(mat, weapon_id: str, root: str) -> str | None:
	"""Si `assets/textures/weapons/<id>_albedo.png` existe (FP-12, repeinture -- §3.3 : "il
	remplace la Base Color, UV identiques"), remplace l'image de CHAQUE noeud Image
	Texture du materiau. Renvoie le chemin utilise, `None` si le fichier n'existe pas."""
	albedo_path = os.path.join(root, "assets", "textures", "weapons", f"{weapon_id}_albedo.png")
	if not os.path.isfile(albedo_path):
		return None
	if mat is None or not mat.use_nodes or mat.node_tree is None:
		return None
	replaced = False
	for node in mat.node_tree.nodes:
		if node.type == 'TEX_IMAGE':
			node.image = bpy.data.images.load(albedo_path, check_existing=True)
			replaced = True
	return albedo_path if replaced else None


# --- Orchestration d'une arme -----------------------------------------------------------

def process_weapon(job: dict, root: str) -> dict:
	"""Pipeline complet (voir la numerotation de l'en-tete) pour UNE arme. Leve
	`RuntimeError` (message listant TOUTES les violations, pour iterer sur le manifeste)
	si un seul critere FP-11 echoue. Renvoie le rapport (aussi ecrit en sidecar JSON)."""
	entry = job["entry"]
	weapon_id = entry["id"]
	backed_up = backup_painted_v1(job["current_path"], job["backup_path"])

	toonkit.reset_scene()
	mesh_objs = import_asset(job["backup_path"])
	if not mesh_objs:
		raise RuntimeError(f"rig_weapon_parts: aucun mesh dans {job['backup_path']}")
	# `_painted_v1/<id>.glb` porte encore les ancres "Muzzle"/"Foregrip" recopiees de bpy
	# (§1.1) : les retirer AVANT de poser les 6 nouvelles, sinon Blender renomme les
	# nouvelles "Muzzle.001" et l'ancienne, fausse, est celle que Godot trouve par nom.
	for stale in [o for o in bpy.context.scene.objects if o.type == 'EMPTY']:
		bpy.data.objects.remove(stale, do_unlink=True)
	body = toonkit.join(mesh_objs) if len(mesh_objs) > 1 else mesh_objs[0]
	body.name = "Body"
	body.parent = None

	scale = scale_factor_for_grip(float(entry["grip_span_m"]), job["target_grip_length_m"])
	translation = translation_for_grip_at_origin(entry["grip_local"], scale)
	grip_length_m = float(entry["grip_span_m"]) * scale

	# Copie PRE-decoupe du corps transforme -- reference "v1 transforme" de l'IoU (la
	# decoupe et le bouchage ne doivent PAS changer le contour exterieur).
	bake_transform(body, rigid_matrix(scale, translation))
	reference = _duplicate(body, "IoU_Reference")

	def xf(point):
		return transform_point(point, scale, translation)

	grip_world = xf(entry["grip_local"])          # (0, 0, 0) par construction
	foregrip_world = xf(entry["foregrip_local"])
	sight_world = xf(entry["sight_local"])
	magwell_world = xf(entry["magwell_local"])
	eject_world = xf(entry["eject_local"])

	pieces = []
	for piece_entry in entry["pieces"]:
		boxes = [(xf(lo), xf(hi)) for lo, hi in piece_boxes(piece_entry)]
		pieces.append(cut_piece(body, piece_entry["name"], boxes, xf(piece_entry["pivot"])))
		remove_piece_from_body(body, boxes)

	all_objs = [body] + pieces
	vertices_world = []
	for obj in all_objs:
		vertices_world.extend(_world_vertices(obj))
	muzzle_world = bore_tip_point(vertices_world)

	albedo_used = maybe_replace_albedo(body.data.materials[0] if body.data.materials else None, weapon_id, root)

	# --- Verification geometrique (echec fort, toutes les violations rassemblees) -------
	violations = []
	profile_tris = _triangles_2d(all_objs)

	grip_inside = point_is_enclosed(all_objs, grip_world)
	grip_dist = distance_to_surface(all_objs, grip_world)
	grip_in_profile = point_in_silhouette((grip_world[1], grip_world[2]), profile_tris)
	if not (grip_inside and grip_in_profile and grip_dist <= GRIP_MAX_SURFACE_DIST_M):
		violations.append(
			f"Grip: interieur={grip_inside}, dans la silhouette de profil={grip_in_profile}, "
			f"distance a la surface={grip_dist * 100:.2f} cm (attendu interieur et <= "
			f"{GRIP_MAX_SURFACE_DIST_M * 100:.1f} cm)")
	guard = trigger_guard_opening(profile_tris, (grip_world[1], grip_world[2]))
	if guard is None:
		violations.append("Grip: aucune ouverture de pontet trouvee devant la poignee")
	elif not (guard["bottom"] <= grip_world[2] <= guard["top"]):
		violations.append(
			f"Grip: hauteur {grip_world[2] * 100:.2f} cm hors du pontet [{guard['bottom'] * 100:.2f}, "
			f"{guard['top'] * 100:.2f}] cm (attendu a la hauteur du pontet, sous le bas de la carcasse)")
	if not (GRIP_LENGTH_RANGE_M[0] <= grip_length_m <= GRIP_LENGTH_RANGE_M[1]):
		violations.append(f"Grip: longueur de poignee {grip_length_m * 100:.1f} cm hors de [10, 13] cm")

	anchor_dists = {}
	for anchor_name, point in (("Foregrip", foregrip_world), ("Sight", sight_world),
			("MagWell", magwell_world), ("Eject", eject_world)):
		dist = distance_to_surface(all_objs, point)
		anchor_dists[anchor_name] = dist
		if dist > ANCHOR_MAX_SURFACE_DIST_M:
			violations.append(
				f"{anchor_name}: distance a la surface={dist * 100:.2f} cm "
				f"(attendu <= {ANCHOR_MAX_SURFACE_DIST_M * 100:.1f} cm)")

	muzzle_depth = bore_depth(all_objs, muzzle_world)
	if muzzle_depth > MUZZLE_MAX_BORE_DEPTH_M:
		violations.append(
			f"Muzzle: aucune matiere a <= {MUZZLE_MAX_BORE_DEPTH_M * 100:.0f} cm derriere la bouche "
			f"({muzzle_depth * 100:.2f} cm) -- repere hors de l'axe du canon")

	elevation = sight_elevation_m(sight_world, muzzle_world)
	if elevation < SIGHT_MIN_ELEVATION_M:
		violations.append(
			f"Sight: elevation au-dessus de l'axe du canon={elevation * 100:.2f} cm "
			f"(attendu >= {SIGHT_MIN_ELEVATION_M * 100:.1f} cm)")

	lateral_angle = sight_lateral_angle_deg(sight_world, muzzle_world)
	if lateral_angle > SIGHT_MUZZLE_MAX_LATERAL_DEG:
		violations.append(
			f"axe Sight->Muzzle: deviation laterale={lateral_angle:.2f}° "
			f"(attendu <= {SIGHT_MUZZLE_MAX_LATERAL_DEG}°)")

	total_tris = sum(toonkit.tri_count(o) for o in all_objs)
	if total_tris > job["budget_tris"]:
		violations.append(f"budget: {total_tris} tris (attendu <= {job['budget_tris']})")

	iou = silhouette_iou(_triangles_2d([reference]), profile_tris)
	if iou < job["min_iou"]:
		violations.append(f"IoU silhouette de profil: {iou:.4f} (attendu >= {job['min_iou']})")

	if violations:
		raise RuntimeError(
			f"rig_weapon_parts: \"{weapon_id}\" hors contrat FP-11 --\n  - " + "\n  - ".join(violations))

	# --- Reperes (tous valides -- poses apres coup) ---------------------------------------
	for anchor_name, point in (("Grip", grip_world), ("Foregrip", foregrip_world),
			("Muzzle", muzzle_world), ("Sight", sight_world), ("MagWell", magwell_world),
			("Eject", eject_world)):
		add_anchor_empty(anchor_name, point).parent = body

	bpy.data.objects.remove(reference, do_unlink=True)

	# --- Export ---------------------------------------------------------------------------
	bpy.ops.object.select_all(action='DESELECT')
	export_objs = all_objs + [o for o in bpy.context.scene.objects if o.type == 'EMPTY']
	for o in export_objs:
		o.select_set(True)
	os.makedirs(os.path.dirname(os.path.abspath(job["output_path"])), exist_ok=True)
	bpy.ops.export_scene.gltf(
		filepath=job["output_path"],
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

	def cm(point):
		return [round(c * 100.0, 3) for c in point]

	report = {
		"id": weapon_id,
		"output": os.path.relpath(os.path.abspath(job["output_path"]), root).replace("\\", "/"),
		"backup": os.path.relpath(os.path.abspath(job["backup_path"]), root).replace("\\", "/"),
		"backed_up_this_run": backed_up,
		"albedo": None if albedo_used is None else os.path.relpath(albedo_used, root).replace("\\", "/"),
		"scale_factor": scale,
		"grip_length_cm": round(grip_length_m * 100.0, 2),
		"final_tris": total_tris,
		"iou_profile": iou,
		"pieces": [p.name for p in pieces],
		"anchors_blender_cm": {
			"Grip": cm(grip_world), "Foregrip": cm(foregrip_world), "Muzzle": cm(muzzle_world),
			"Sight": cm(sight_world), "MagWell": cm(magwell_world), "Eject": cm(eject_world),
		},
		"trigger_guard_cm": {k: round(v * 100.0, 2) for k, v in guard.items() if k != "area_m2"},
		"checks": {
			"grip_inside": grip_inside, "grip_in_profile": grip_in_profile,
			"grip_surface_dist_cm": round(grip_dist * 100, 3),
			"foregrip_surface_dist_cm": round(anchor_dists["Foregrip"] * 100, 3),
			"sight_surface_dist_cm": round(anchor_dists["Sight"] * 100, 3),
			"magwell_surface_dist_cm": round(anchor_dists["MagWell"] * 100, 3),
			"eject_surface_dist_cm": round(anchor_dists["Eject"] * 100, 3),
			"muzzle_bore_depth_cm": round(muzzle_depth * 100, 3),
			"sight_elevation_cm": round(elevation * 100, 3),
			"sight_muzzle_lateral_deg": round(lateral_angle, 4),
		},
	}
	sidecar_path = os.path.splitext(job["output_path"])[0] + ".json"
	with open(sidecar_path, "w", encoding="utf-8") as f:
		json.dump(report, f, indent=2, ensure_ascii=False)
		f.write("\n")
	report["sidecar"] = sidecar_path
	# Provenance de licence a cote du .glb v2 aussi (licence_check.py scanne CHAQUE .glb).
	source_provenance = _provenance_path(job["backup_path"])
	if not os.path.isfile(source_provenance):
		source_provenance = _provenance_path(job["current_path"])
	if os.path.isfile(source_provenance):
		shutil.copy2(source_provenance, _provenance_path(job["output_path"]))
	print(f"RIG_WEAPON_PARTS_OK {weapon_id} tris={total_tris} iou={iou:.4f} scale={scale:.4f} "
		f"-> {job['output_path']}")
	return report


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_jobs(cli: dict, manifest: dict, root: str) -> list:
	weapons_dir = _resolve_path(manifest["weapons_dir"], root)
	backup_dir = _resolve_path(manifest["painted_v1_dir"], root)
	output_dir = _resolve_path(manifest["output_dir"], root)
	target_grip_length_m = float(manifest.get("target_grip_length_m", DEFAULT_TARGET_GRIP_LENGTH_M))
	budget_tris = int(manifest.get("default_budget_tris", DEFAULT_BUDGET_TRIS))
	min_iou = float(manifest.get("min_iou", DEFAULT_MIN_IOU))

	if cli.get("process_all"):
		entries = manifest["weapons"]
	elif cli.get("weapon_id"):
		entries = [resolve_manifest_entry(manifest, cli["weapon_id"])]
	else:
		raise ValueError("rig_weapon_parts: --all ou --id requis")

	jobs = []
	for entry in entries:
		weapon_id = entry["id"]
		jobs.append({
			"entry": entry,
			"current_path": os.path.join(weapons_dir, f"{weapon_id}.glb"),
			"backup_path": os.path.join(backup_dir, f"{weapon_id}.glb"),
			"output_path": os.path.join(output_dir, f"{weapon_id}.glb"),
			"target_grip_length_m": target_grip_length_m,
			"budget_tris": budget_tris,
			"min_iou": min_iou,
		})
	return jobs


def parse_args() -> dict:
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	p = argparse.ArgumentParser()
	p.add_argument("--manifest", dest="manifest_path", required=True)
	p.add_argument("--id", dest="weapon_id", default=None)
	p.add_argument("--all", dest="process_all", action="store_true")
	ns = p.parse_args(argv)
	return vars(ns)


def main() -> None:
	cli = parse_args()
	root = repo_root()
	manifest_path = _resolve_path(cli["manifest_path"], root)
	if not os.path.isfile(manifest_path):
		print(f"RIG_WEAPON_PARTS_FAIL manifeste introuvable: {manifest_path}")
		sys.exit(1)
	with open(manifest_path, "r", encoding="utf-8") as f:
		manifest = parse_manifest(f.read())
	try:
		jobs = build_jobs(cli, manifest, root)
	except (ValueError, KeyError) as exc:
		print(f"RIG_WEAPON_PARTS_FAIL {exc}")
		sys.exit(1)

	failures = []
	for job in jobs:
		weapon_id = job["entry"]["id"]
		if not os.path.isfile(job["current_path"]) and not os.path.isfile(job["backup_path"]):
			failures.append((weapon_id, "v1 introuvable"))
			print(f"RIG_WEAPON_PARTS_FAIL {weapon_id}: v1 introuvable ({job['current_path']})")
			continue
		try:
			process_weapon(job, root)
		except Exception as exc:  # noqa: BLE001 - rapporte chaque echec, continue les autres jobs
			failures.append((weapon_id, str(exc)))
			print(f"RIG_WEAPON_PARTS_FAIL {weapon_id}: {exc}")
	if failures:
		sys.exit(1)


if __name__ == "__main__":
	main()
