## make_props.py
## Génère la bibliothèque de props stylisés (glTF binaire) pour les décors
## "Borderlands" peints/cel-shadés (wasteland désertique + cargo ship), Godot
## 4.7. Formes chunky, biseautées, silhouettes lisibles avec quelques détails
## hand-authored par prop (pas de simples boîtes). Déterministe (aucun
## random). Slots matériau = les "kinds" peints partagés avec Cartoon.painted
## (scripts/core/Cartoon.gd, en cours d'ajout en parallèle par un autre
## builder) : painted_metal, rust, corrugated, container, wood, sand,
## concrete, asphalt, ship_deck, rubber, glass — plus `accent` (couleur
## teintable) et `sign` (panneaux à lettrage). Origine = base centrée au sol,
## +Y up (repère Godot). Lancer :
##   blender --background --python tools/blender/make_props.py
##
## API bpy 5.2 vérifiée par sondage avant écriture (voir rapport de tâche) :
## - bmesh.ops.{create_cube,create_cone,create_circle,spin,scale,rotate,
##   translate,transform} : opèrent sur les verts qu'on leur passe (jamais sur
##   tout le bmesh partagé) — on isole toujours la géométrie fraîche via les
##   verts RENVOYÉS par l'opérateur de création, ou par un "avant/après" sur
##   bm.faces pour les opérateurs (spin) qui ne renvoient pas la liste
##   complète des faces créées.
## - bmesh.ops.create_circle crée un cercle À PLAT dans le plan XY (normale
##   Z) : pour obtenir un VRAI tore via spin (pas juste un anneau plat), le
##   profil doit d'abord être basculé dans un plan qui CONTIENT l'axe de
##   spin, puis décalé perpendiculairement à cet axe avant de tourner autour
##   de lui (vérifié par sondage : coordonnées Z variables après spin, pas
##   juste le nombre de faces).
## - Texte 3D : bpy.data.curves.new(.., 'FONT') + .body/.size/.extrude,
##   bpy.ops.object.convert(target='MESH') sur l'objet actif/sélectionné (pas
##   besoin de temp_override en mode background), puis fusion manuelle des
##   verts/faces du mesh résultant dans le bmesh partagé (bm.faces.new sur
##   des verts dupliqués) — quelques faces internes de lettres à contour
##   fermé (ex. le "trou" du A) peuvent échouer à la fusion (arête déjà non-
##   manifold) ; on les ignore (try/except), effet cosmétique mineur.
## - Modifier BEVEL appliqué via bpy.ops.object.modifier_apply sous
##   temp_override(object=obj) (identique à make_weapons.py).
## - export_scene.gltf(export_format='GLB', export_apply=True, export_yup=True)
##   Y-up par défaut, identique à Godot ; noms de matériaux Blender =
##   noms de slot glTF (aucun autre objet actif en mémoire au moment de la
##   création grâce à _clear_scene() en tête de build(), donc pas de
##   collision "wood.001" entre deux props qui utilisent le même kind).
import bpy
import bmesh
import json
import math
import os

from mathutils import Matrix, Vector

# ---------------------------------------------------------------------------
# Kinds peints (contrat partagé avec Cartoon.painted). Les noms de slot
# matériau doivent être EXACTEMENT ces chaînes.
# ---------------------------------------------------------------------------
KINDS = [
	"painted_metal", "rust", "corrugated", "container", "wood", "sand",
	"concrete", "asphalt", "ship_deck", "rubber", "glass", "accent", "sign",
]

# Couleurs plates de secours (le vrai rendu peint vient de Cartoon.painted au
# runtime ; ces couleurs ne servent qu'à l'aperçu du .glb brut / import-check).
KIND_COLORS = {
	"painted_metal": (0.36, 0.42, 0.47, 1.0),
	"rust":          (0.42, 0.22, 0.13, 1.0),
	"corrugated":    (0.55, 0.56, 0.58, 1.0),
	"container":     (0.55, 0.30, 0.20, 1.0),
	"wood":          (0.45, 0.32, 0.20, 1.0),
	"sand":          (0.76, 0.65, 0.45, 1.0),
	"concrete":      (0.62, 0.60, 0.56, 1.0),
	"asphalt":       (0.15, 0.15, 0.16, 1.0),
	"ship_deck":     (0.30, 0.34, 0.38, 1.0),
	"rubber":        (0.10, 0.10, 0.11, 1.0),
	"glass":         (0.55, 0.72, 0.78, 0.8),
	"accent":        (0.78, 0.24, 0.14, 1.0),
	"sign":          (0.86, 0.81, 0.66, 1.0),
}
KIND_ROUGHNESS = {
	"painted_metal": 0.5, "rust": 0.75, "corrugated": 0.6, "container": 0.5,
	"wood": 0.8, "sand": 0.9, "concrete": 0.85, "asphalt": 0.9,
	"ship_deck": 0.55, "rubber": 0.9, "glass": 0.1, "accent": 0.4, "sign": 0.75,
}
KIND_METALLIC = {
	"painted_metal": 0.2, "rust": 0.1, "corrugated": 0.2, "container": 0.1,
	"ship_deck": 0.15, "glass": 0.0, "accent": 0.1,
}

SET_WASTELAND = "wasteland"
SET_CARGO = "cargo_ship"

OUT_ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
	"assets", "models", "props")


def _clear_scene() -> None:
	for o in list(bpy.data.objects):
		bpy.data.objects.remove(o, do_unlink=True)
	for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.curves):
		for block in list(coll):
			if block.users == 0:
				coll.remove(block)


# ---------------------------------------------------------------------------
# Primitives géométriques bas niveau. Toutes travaillent sur le bmesh PARTAGÉ
# de la pièce en cours, mais ne manipulent QUE la géométrie qu'elles viennent
# de créer (jamais tout `bm`). Repère d'AUTEUR (avant la correction d'axes
# finale de build()) : X = droite, Y = haut, Z = avant — identique à
# make_weapons.py.
# ---------------------------------------------------------------------------

def add_box(bm: bmesh.types.BMesh, size: tuple, center: tuple, rot=None) -> list:
	before = set(bm.faces)
	verts = list(bmesh.ops.create_cube(bm, size=1.0)["verts"])
	bmesh.ops.scale(bm, vec=Vector(size), verts=verts)
	if rot:
		axis, deg = rot
		bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(deg), 3, axis), verts=verts)
	bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
	return [f for f in bm.faces if f not in before]


def add_cyl(bm: bmesh.types.BMesh, r1: float, r2: float, depth: float, center: tuple,
		segments: int = 12, rot=None) -> list:
	before = set(bm.faces)
	verts = list(bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
		radius1=r1, radius2=r2, depth=depth)["verts"])
	if rot:
		axis, deg = rot
		bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(deg), 3, axis), verts=verts)
	bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
	return [f for f in bm.faces if f not in before]


def add_strut(bm: bmesh.types.BMesh, p0: tuple, p1: tuple, thickness: float) -> list:
	"""Poutre pleine (section carrée `thickness`) entre 2 points — utilisée pour
	les treillis (pylône, grue), rambardes, bras de davier, etc."""
	p0v, p1v = Vector(p0), Vector(p1)
	d = p1v - p0v
	length = d.length
	if length < 1e-6:
		return []
	before = set(bm.faces)
	verts = list(bmesh.ops.create_cube(bm, size=1.0)["verts"])
	bmesh.ops.scale(bm, vec=Vector((thickness, thickness, length)), verts=verts)
	rot_quat = Vector((0.0, 0.0, 1.0)).rotation_difference(d.normalized())
	bmesh.ops.transform(bm, matrix=rot_quat.to_matrix().to_4x4(), verts=verts)
	bmesh.ops.translate(bm, vec=(p0v + p1v) * 0.5, verts=verts)
	return [f for f in bm.faces if f not in before]


# Config du spin pour add_ring : par axe de trou voulu -> (pré-rotation du
# profil, direction de décalage (unitaire), axe de spin). Dérivé par sondage
# (voir en-tête) : le profil (cercle plat XY) doit être basculé pour que son
# plan CONTIENNE l'axe de spin avant d'être décalé perpendiculairement.
_RING_CONF = {
	"Z": (("X", 90.0), Vector((1.0, 0.0, 0.0)), (0.0, 0.0, 1.0)),  # trou face à Z (ex. bouée murale)
	"Y": (("Z", 90.0), Vector((1.0, 0.0, 0.0)), (0.0, 1.0, 0.0)),  # trou face à Y (ex. pneu au sol)
	"X": (None,        Vector((0.0, 0.0, 1.0)), (1.0, 0.0, 0.0)),  # trou face à X
}


def add_ring(bm: bmesh.types.BMesh, ring_r: float, tube_r: float, center: tuple,
		ring_segments: int = 16, tube_segments: int = 8, axis: str = "Y", rot=None) -> list:
	pre, offset_dir, spin_axis = _RING_CONF[axis]
	before = set(bm.faces)
	verts = list(bmesh.ops.create_circle(bm, cap_ends=True, cap_tris=False,
		segments=tube_segments, radius=tube_r)["verts"])
	if pre:
		bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(pre[1]), 3, pre[0]), verts=verts)
	bmesh.ops.translate(bm, vec=offset_dir * ring_r, verts=verts)
	geom_in = set(verts)
	for v in verts:
		geom_in.update(v.link_edges)
		geom_in.update(v.link_faces)
	bmesh.ops.spin(bm, geom=list(geom_in), cent=(0, 0, 0), axis=spin_axis,
		angle=math.radians(360.0), steps=ring_segments, use_duplicate=False)
	new_faces = [f for f in bm.faces if f not in before]
	new_verts = list({v for f in new_faces for v in f.verts})
	if rot:
		axis2, deg = rot
		bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(deg), 3, axis2), verts=new_verts)
	bmesh.ops.translate(bm, vec=Vector(center), verts=new_verts)
	return new_faces


def add_text_merge(bm: bmesh.types.BMesh, text: str, size: float, extrude: float,
		center: tuple, rot=None) -> list:
	"""Texte 3D (panneaux FUEL/GAS/GARAGE...) : courbe FONT -> mesh -> fusion
	manuelle des verts/faces dans le bmesh partagé de la pièce."""
	curve = bpy.data.curves.new("txt", "FONT")
	curve.body = text
	curve.size = size
	curve.extrude = extrude
	curve.resolution_u = 2
	curve.bevel_resolution = 0
	curve.align_x = "CENTER"
	curve.align_y = "CENTER"
	obj = bpy.data.objects.new("txt", curve)
	bpy.context.scene.collection.objects.link(obj)
	bpy.context.view_layer.objects.active = obj
	obj.select_set(True)
	bpy.ops.object.convert(target="MESH")
	bm2 = bmesh.new()
	bm2.from_mesh(obj.data)
	mat = Matrix.Translation(Vector(center))
	if rot:
		axis, deg = rot
		mat = mat @ Matrix.Rotation(math.radians(deg), 4, axis)
	# Une courbe FONT Blender est nativement lisible depuis +Z (convention
	# standard XY-plane/+Z-vers-le-lecteur) — alors que tout le reste de ce
	# fichier tourne la face visible vers -Z (portes, fenêtres, enseignes).
	# Sans cette correction, TOUT texte posé par add_text_merge se lit en
	# miroir depuis le côté -Z d'où on regarde partout ailleurs (confirmé à
	# l'écran sur "SALOON" -> "NOOJAS" avant ce correctif). Demi-tour autour
	# de Y appliqué en dernier (le plus proche de l'espace-objet) pour rester
	# sous le `rot` éventuel de l'appelant.
	mat = mat @ Matrix.Rotation(math.radians(180.0), 4, "Y")
	bmesh.ops.transform(bm2, matrix=mat, verts=bm2.verts)
	vert_map = {}
	for v in bm2.verts:
		vert_map[v] = bm.verts.new(v.co)
	bm.verts.ensure_lookup_table()
	new_faces = []
	for f in bm2.faces:
		try:
			new_faces.append(bm.faces.new([vert_map[v] for v in f.verts]))
		except ValueError:
			pass  # contour interne (ex. "trou" du A) déjà couvert — cosmétique
	bm2.free()
	bpy.data.objects.remove(obj, do_unlink=True)
	bpy.data.curves.remove(curve)
	return new_faces


def add_lattice_tower(bm: bmesh.types.BMesh, base_half: float, top_half: float, height: float,
		levels: list, leg_th: float, brace_th: float, center_xz: tuple = (0.0, 0.0)) -> list:
	"""Pylône treillis générique (derrick, grue portique, grue à conteneurs) :
	4 montants d'angle qui convergent de `base_half` à `top_half`, des
	ceintures horizontales à chaque hauteur de `levels`, et un croisillon en X
	sur chacune des 4 faces entre chaque paire de niveaux consécutifs
	(0, *levels, height). Un seul kind (matériau structure uniforme, réaliste
	pour de l'acier treillis)."""
	cx, cz = center_xz

	def corner(h: float, i: int) -> tuple:
		t = h / height if height else 0.0
		half = base_half + (top_half - base_half) * t
		sx = 1.0 if i in (1, 2) else -1.0
		sz = 1.0 if i in (2, 3) else -1.0
		return (cx + sx * half, h, cz + sz * half)

	faces = []
	for i in range(4):
		faces += add_strut(bm, corner(0.0, i), corner(height, i), leg_th)
	for h in levels:
		pts = [corner(h, i) for i in range(4)]
		for i in range(4):
			faces += add_strut(bm, pts[i], pts[(i + 1) % 4], brace_th)
	all_levels = sorted(set([0.0] + list(levels) + [height]))
	for i in range(len(all_levels) - 1):
		h0, h1 = all_levels[i], all_levels[i + 1]
		p0 = [corner(h0, k) for k in range(4)]
		p1 = [corner(h1, k) for k in range(4)]
		for k in range(4):
			k2 = (k + 1) % 4
			faces += add_strut(bm, p0[k], p1[k2], brace_th)
			faces += add_strut(bm, p0[k2], p1[k], brace_th)
	return faces


# ---------------------------------------------------------------------------
# DSL déclaratif : chaque prop est une fonction -> liste de "parts". build()
# scanne d'abord les kinds utilisés (ordre de première apparition) pour créer
# les slots matériau, puis reconstruit la géométrie et assigne
# face.material_index d'après ce mapping.
# ---------------------------------------------------------------------------

def P_BOX(kind, size, center, rot=None):
	return ("box", kind, size, center, rot)


def P_CYL(kind, r1, depth, center, r2=None, seg=12, rot=None):
	return ("cyl", kind, r1, r2 if r2 is not None else r1, depth, center, seg, rot)


def P_RING(kind, ring_r, tube_r, center, ring_seg=16, tube_seg=8, axis="Y", rot=None):
	return ("ring", kind, ring_r, tube_r, center, ring_seg, tube_seg, axis, rot)


def P_STRUT(kind, p0, p1, thickness):
	return ("strut", kind, p0, p1, thickness)


def P_TEXT(kind, text, size, extrude, center, rot=None):
	return ("text", kind, text, size, extrude, center, rot)


def P_LATTICE(kind, **kwargs):
	return ("lattice", kind, kwargs)


# NOTE convention : chaque boîte de collision du manifeste est
# {"size": [w, d, h], "center": [x, y, z]} — LARGEUR, PROFONDEUR, HAUTEUR
# dans cet ordre (pas w,h,d comme les tuples `size` de P_BOX). Toute
# collision custom écrite à la main dans PROPS doit respecter cet ordre.
def _bbox_collision(w: float, d: float, h: float) -> list:
	return [{"size": [round(w, 3), round(d, 3), round(h, 3)], "center": [0.0, round(h / 2.0, 3), 0.0]}]


# ---------------------------------------------------------------------------
# Helpers de façade (passe détail R2) : fenêtres/portes en "cadre + panneau
# encastré" plutôt qu'un vrai booléen (déterministe, budget tris minime, et
# lisible depuis l'extérieur exactement comme un vrai creux) — le cadre est
# en saillie (plus proche du -Z extérieur) et le panneau sombre légèrement en
# retrait (plus loin en +Z), donnant la lecture "trou encadré" sans jamais
# percer le mur. `wall_face_z` = le Z local de la face EXTÉRIEURE du mur
# (typiquement -profondeur/2) sur laquelle on colle l'ouverture.
# ---------------------------------------------------------------------------

def window_parts(w, h, center_xy, wall_face_z, frame_kind="wood", pane_kind="glass", sill=True, shutters=False):
	x, y = center_xy
	parts = [
		P_BOX(pane_kind, (w - 0.14, h - 0.14, 0.03), (x, y, wall_face_z + 0.03)),
		P_BOX(frame_kind, (w, h, 0.06), (x, y, wall_face_z - 0.03)),
	]
	if sill:
		parts.append(P_BOX(frame_kind, (w + 0.16, 0.06, 0.10), (x, y - h * 0.5 - 0.03, wall_face_z - 0.05)))
	if shutters:
		gap = w * 0.5 + 0.10
		parts.append(P_BOX(frame_kind, (0.16, h * 0.92, 0.03), (x - gap, y, wall_face_z - 0.02)))
		parts.append(P_BOX(frame_kind, (0.16, h * 0.92, 0.03), (x + gap, y, wall_face_z - 0.02)))
	return parts


def door_parts(w, h, center_xy, wall_face_z, door_kind="wood", handle_kind="accent"):
	x, y = center_xy
	return [
		P_BOX(door_kind, (w, h, 0.07), (x, y, wall_face_z - 0.04)),
		P_BOX(handle_kind, (0.04, 0.05, 0.03), (x + w * 0.32, y - h * 0.05, wall_face_z - 0.09)),
	]


def sign_board_parts(text, w, h, center, panel_kind="sign", text_kind="accent", text_size=None):
	# Toujours axe-aligné, face -Z (même convention que le reste du fichier) :
	# une variante tournée demanderait de faire pivoter le texte ET son
	# décalage de front dans le même sens, non vérifié visuellement pour du
	# texte (contrairement aux boîtes, largement éprouvées) — on préfère
	# rester sur la variante dont on a confirmé la lecture à l'écran plutôt
	# que de risquer un texte "miroir" non détecté.
	x, y, z = center
	return [
		P_BOX(panel_kind, (w, h, 0.1), (x, y, z)),
		P_TEXT(text_kind, text, text_size or h * 0.55, 0.03, (x, y, z - 0.08)),
	]


def balcony_rail_parts(kind, x0, x1, y, z, post_h=0.9, n_balusters=6):
	parts = [
		P_STRUT(kind, (x0, y, z), (x1, y, z), 0.04),
		P_STRUT(kind, (x0, y, z), (x0, y + post_h, z), 0.05),
		P_STRUT(kind, (x1, y, z), (x1, y + post_h, z), 0.05),
		P_STRUT(kind, (x0, y + post_h, z), (x1, y + post_h, z), 0.04),
	]
	span = x1 - x0
	for i in range(1, n_balusters + 1):
		bx = x0 + span * i / (n_balusters + 1)
		parts.append(P_STRUT(kind, (bx, y, z), (bx, y + post_h, z), 0.02))
	return parts


def roof_clutter_parts(center, spread=1.0):
	x, y, z = center
	return [
		P_CYL("rust", 0.20, 0.45, (x - spread * 0.4, y + 0.225, z), r2=0.18, rot=("X", -90)),
		P_CYL("painted_metal", 0.035, 0.8, (x + spread * 0.3, y + 0.40, z - spread * 0.15), r2=0.02, rot=("X", -90)),
		P_BOX("rust", (0.32, 0.22, 0.3), (x + spread * 0.1, y + 0.11, z + spread * 0.25)),
	]


# ===========================================================================
# WASTELAND — véhicules
# ===========================================================================

def parts_truck_wreck():
	return [
		P_BOX("painted_metal", (1.9, 1.0, 1.7), (0, 0.85, -1.5)),          # cabine
		P_BOX("painted_metal", (1.8, 0.5, 1.4), (0, 0.55, -2.6)),          # capot
		P_BOX("rust", (1.85, 0.65, 2.6), (0, 0.55, 0.9)),                  # benne rouillée
		P_BOX("accent", (1.0, 0.08, 0.9), (0, 1.72, -1.5)),                # tôle rapiécée sur le toit
		P_BOX("glass", (1.6, 0.05, 0.9), (0, 1.35, -2.05), rot=("X", -25)),  # pare-brise
		P_BOX("painted_metal", (0.06, 0.85, 0.06), (-0.78, 1.35, -2.05)),  # montant A gauche
		P_BOX("painted_metal", (0.06, 0.85, 0.06), (0.78, 1.35, -2.05)),   # montant A droit
		P_BOX("glass", (1.6, 0.05, 0.6), (0, 1.55, -0.95), rot=("X", 20)),   # lunette arrière
		# Passages de roue (ailes évasées) — silhouette moins "boîte plate".
		P_BOX("rust", (0.16, 0.4, 0.55), (-1.02, 0.55, -2.3)),
		P_BOX("rust", (0.16, 0.4, 0.55), (1.02, 0.55, -2.3)),
		P_BOX("rust", (0.16, 0.4, 0.55), (-1.02, 0.55, 1.1)),
		P_BOX("rust", (0.16, 0.4, 0.55), (1.02, 0.55, 1.1)),
		# Roue avant-gauche à plat : jante posée plus bas, légère affaissée.
		P_CYL("rubber", 0.38, 0.26, (-0.95, 0.30, -2.3), r2=0.38, rot=("Y", 90)),
		P_CYL("rubber", 0.40, 0.28, (0.95, 0.42, -2.3), r2=0.40, rot=("Y", 90)),
		P_CYL("rubber", 0.40, 0.28, (-0.95, 0.42, 1.1), r2=0.40, rot=("Y", 90)),
		P_CYL("rubber", 0.40, 0.28, (0.95, 0.42, 1.1), r2=0.40, rot=("Y", 90)),
		P_BOX("rust", (2.0, 0.15, 0.15), (0, 0.35, -3.35)),                # pare-chocs avant
		P_BOX("rust", (1.95, 0.13, 0.13), (0, 0.3, 2.25)),                 # pare-chocs arrière
		P_BOX("rubber", (0.9, 0.32, 0.04), (0, 0.5, -3.3)),                # calandre
		P_BOX("glass", (0.22, 0.18, 0.05), (-0.65, 0.55, -3.28)),          # phare gauche
		P_BOX("accent", (0.22, 0.18, 0.05), (0.65, 0.55, -3.28)),          # phare droit brisé
		P_BOX("rubber", (0.14, 0.16, 0.02), (0.55, 0.35, 0.9), rot=("Z", 15)),   # trou de rouille
		P_BOX("rubber", (0.10, 0.12, 0.02), (-0.3, 0.62, 1.4), rot=("Z", -20)),  # trou de rouille
		P_CYL("painted_metal", 0.04, 0.6, (0.8, 1.3, 1.9), r2=0.04, rot=("X", -80)),  # échappement vertical
	]


def parts_sedan_wreck():
	return [
		P_BOX("painted_metal", (1.75, 0.55, 4.3), (0, 0.35, 0)),           # bas de caisse
		P_BOX("painted_metal", (1.55, 0.55, 2.0), (0, 0.85, -0.3)),        # habitacle
		P_BOX("rust", (1.6, 0.25, 1.3), (0, 0.68, -1.85)),                 # capot
		P_BOX("rust", (1.6, 0.3, 1.0), (0, 0.72, 1.9)),                    # coffre
		P_BOX("glass", (1.45, 0.05, 1.1), (0, 1.05, -1.1), rot=("X", -30)),  # pare-brise
		P_BOX("painted_metal", (0.05, 0.7, 0.05), (-0.72, 1.05, -1.1)),    # montant A gauche
		P_BOX("painted_metal", (0.05, 0.7, 0.05), (0.72, 1.05, -1.1)),     # montant A droit
		P_BOX("glass", (1.45, 0.05, 0.9), (0, 1.15, 0.75), rot=("X", 25)),   # lunette arrière
		P_BOX("rust", (0.14, 0.32, 0.42), (-0.88, 0.42, -1.5)),            # passage de roue AV G
		P_BOX("rust", (0.14, 0.32, 0.42), (0.88, 0.42, -1.5)),             # passage de roue AV D
		P_BOX("rust", (0.14, 0.32, 0.42), (-0.88, 0.42, 1.5)),             # passage de roue AR G
		P_BOX("rust", (0.14, 0.32, 0.42), (0.88, 0.42, 1.5)),              # passage de roue AR D
		# Roue arrière-droite à plat.
		P_CYL("rubber", 0.35, 0.22, (-0.85, 0.35, -1.5), r2=0.35, rot=("Y", 90)),
		P_CYL("rubber", 0.35, 0.22, (0.85, 0.35, -1.5), r2=0.35, rot=("Y", 90)),
		P_CYL("rubber", 0.35, 0.22, (-0.85, 0.35, 1.5), r2=0.35, rot=("Y", 90)),
		P_CYL("rubber", 0.33, 0.20, (0.85, 0.24, 1.5), r2=0.33, rot=("Y", 90)),
		P_BOX("rust", (1.7, 0.10, 0.10), (0, 0.28, -2.05)),                # pare-chocs avant
		P_BOX("rust", (1.7, 0.10, 0.10), (0, 0.30, 2.1)),                  # pare-chocs arrière
		P_BOX("rubber", (0.75, 0.22, 0.04), (0, 0.42, -2.08)),             # calandre
		P_BOX("glass", (0.18, 0.14, 0.04), (-0.55, 0.48, -2.06)),          # phare gauche
		P_BOX("glass", (0.18, 0.14, 0.04), (0.55, 0.48, -2.06)),           # phare droit
		P_BOX("rubber", (0.12, 0.14, 0.02), (-0.6, 0.55, 0.3), rot=("Z", 12)),  # trou de rouille
		P_BOX("accent", (1.6, 0.06, 0.3), (0.7, 0.9, -0.3), rot=("Z", 10)),  # rayure d'impact
	]


# ===========================================================================
# WASTELAND — station-service / signalétique
# ===========================================================================

def parts_fuel_pump():
	return [
		P_BOX("concrete", (0.55, 0.15, 0.55), (0, 0.075, 0)),
		P_BOX("painted_metal", (0.42, 1.1, 0.32), (0, 0.65, 0)),
		P_CYL("painted_metal", 0.24, 0.18, (0, 1.28, 0), r2=0.18, rot=("X", -90)),
		P_BOX("accent", (0.3, 0.25, 0.03), (0, 1.0, 0.18)),                # afficheur
		P_BOX("rust", (0.15, 0.15, 0.15), (0.28, 0.55, 0.15)),             # dévidoir
		P_STRUT("rubber", (0.28, 0.55, 0.2), (0.05, 0.15, 0.35), 0.035),   # tuyau
		P_CYL("painted_metal", 0.03, 0.18, (0.05, 0.12, 0.4), r2=0.03, rot=("X", 60)),  # pistolet
	]


def parts_fuel_billboard():
	return [
		P_BOX("wood", (0.16, 3.0, 0.16), (-1.1, 1.5, 0)),
		P_BOX("wood", (0.16, 3.0, 0.16), (1.1, 1.5, 0)),
		P_STRUT("wood", (-1.1, 2.6, 0), (1.1, 2.6, 0), 0.1),
		P_BOX("sign", (2.4, 0.9, 0.1), (0, 2.7, 0)),
		P_BOX("sign", (2.4, 0.9, 0.1), (0, 1.65, 0)),
		P_TEXT("accent", "FUEL", 0.5, 0.03, (0, 2.7, -0.08)),
		P_TEXT("accent", "FUEL", 0.5, 0.03, (0, 1.65, -0.08)),
	]


def parts_gas_billboard():
	return [
		P_CYL("painted_metal", 0.09, 3.6, (0, 1.8, 0), r2=0.09, seg=8, rot=("X", -90)),
		P_CYL("concrete", 0.3, 0.12, (0, 0.06, 0), r2=0.3, rot=("X", -90)),
		P_BOX("sign", (1.3, 0.9, 0.12), (0, 4.0, 0)),
		P_BOX("accent", (1.4, 0.15, 0.14), (0, 4.42, 0)),
		P_TEXT("accent", "GAS", 0.6, 0.04, (0, 4.0, -0.1)),
		P_STRUT("painted_metal", (-0.09, 3.3, 0), (-0.5, 3.7, 0.0), 0.05),
		P_STRUT("painted_metal", (0.09, 3.3, 0), (0.5, 3.7, 0.0), 0.05),
	]


def parts_shop_sign():
	return [
		P_BOX("wood", (0.14, 1.3, 0.14), (-0.85, 0.65, 0)),
		P_STRUT("painted_metal", (-0.85, 1.2, 0), (-0.1, 1.2, 0.35), 0.06),
		P_STRUT("painted_metal", (-0.55, 1.18, 0.16), (-0.55, 0.95, 0.05), 0.02),
		P_STRUT("painted_metal", (-0.15, 1.2, 0.33), (-0.15, 0.95, 0.28), 0.02),
		P_BOX("wood", (1.5, 0.55, 0.06), (-0.35, 0.85, 0.15)),
		P_TEXT("accent", "SALOON", 0.22, 0.025, (-0.35, 0.85, 0.10)),
	]


# ===========================================================================
# WASTELAND — décor / storage
# ===========================================================================

def parts_oil_drum():
	return [
		P_CYL("rust", 0.29, 0.85, (0, 0.425, 0), r2=0.29, seg=14, rot=("X", -90)),
		P_CYL("painted_metal", 0.30, 0.04, (0, 0.85, 0), r2=0.30, rot=("X", -90)),
		P_CYL("painted_metal", 0.30, 0.04, (0, 0.02, 0), r2=0.30, rot=("X", -90)),
		P_CYL("painted_metal", 0.305, 0.03, (0, 0.28, 0), r2=0.305, rot=("X", -90)),
		P_CYL("painted_metal", 0.305, 0.03, (0, 0.56, 0), r2=0.305, rot=("X", -90)),
		P_BOX("accent", (0.25, 0.2, 0.02), (0, 0.45, 0.29)),
	]


def parts_wooden_crate():
	return [
		P_BOX("wood", (0.78, 0.78, 0.78), (0, 0.39, 0)),
		P_STRUT("wood", (-0.39, 0.02, 0.4), (0.39, 0.76, 0.4), 0.04),
		P_STRUT("wood", (0.39, 0.02, 0.4), (-0.39, 0.76, 0.4), 0.04),
		P_BOX("wood", (0.82, 0.06, 0.82), (0, 0.79, 0)),
		P_BOX("accent", (0.3, 0.3, 0.02), (0, 0.5, 0.4)),
	]


def parts_pallet():
	parts = [P_BOX("wood", (0.12, 0.12, 1.0), (x, 0.06, 0)) for x in (-0.5, 0.0, 0.5)]
	parts += [P_BOX("wood", (1.2, 0.03, 0.18), (0, 0.12, z)) for z in (-0.4, -0.2, 0.0, 0.2, 0.4)]
	parts += [P_BOX("wood", (1.2, 0.03, 0.16), (0, 0.0, z)) for z in (-0.4, 0.0, 0.4)]
	return parts


def parts_tyre_stack():
	return [
		P_RING("rubber", 0.35, 0.13, (0, 0.13, 0), ring_seg=12, tube_seg=6),
		P_RING("rubber", 0.35, 0.13, (0, 0.36, 0), ring_seg=12, tube_seg=6),
		P_RING("rubber", 0.35, 0.13, (0, 0.6, 0), ring_seg=12, tube_seg=6, rot=("Y", 15)),
		P_RING("rubber", 0.35, 0.13, (0, 0.84, 0), ring_seg=12, tube_seg=6, rot=("Y", -10)),
	]


def parts_wooden_shack():
	return [
		P_BOX("wood", (3.8, 2.3, 3.0), (0, 1.15, 0)),
		P_BOX("corrugated", (4.2, 0.12, 1.9), (0, 2.5, -0.75), rot=("X", 18)),
		P_BOX("corrugated", (4.2, 0.12, 1.9), (0, 2.5, 0.75), rot=("X", -18)),
		P_BOX("corrugated", (4.2, 0.15, 0.2), (0, 2.95, 0)),
		P_BOX("wood", (4.0, 0.15, 1.2), (0, 0.08, -1.9)),                  # terrasse
		P_BOX("wood", (0.14, 2.1, 0.14), (-1.8, 1.1, -2.4)),               # poteau porche
		P_BOX("wood", (0.14, 2.1, 0.14), (1.8, 1.1, -2.4)),
		P_BOX("corrugated", (4.2, 0.1, 1.3), (0, 2.15, -2.0), rot=("X", -8)),  # auvent
		P_BOX("wood", (0.85, 1.9, 0.06), (-1.0, 0.95, -1.52)),             # porte
		P_BOX("accent", (0.05, 0.05, 0.05), (-0.65, 0.95, -1.50)),         # poignée
		P_BOX("glass", (0.7, 0.7, 0.05), (0.9, 1.4, -1.52)),               # fenêtre
	]


def parts_corrugated_shed():
	return [
		P_BOX("corrugated", (3.5, 2.3, 2.8), (0, 1.15, 0)),
		P_BOX("corrugated", (3.8, 0.12, 3.2), (0, 2.45, 0), rot=("X", 10)),
		P_BOX("painted_metal", (1.3, 2.0, 0.06), (-0.9, 1.0, -1.41)),      # porte coulissante
		P_BOX("accent", (1.4, 0.08, 0.04), (-0.9, 2.02, -1.4)),            # rail de porte
		P_CYL("painted_metal", 0.15, 0.25, (1.2, 2.55, 0), r2=0.15, rot=("X", -90)),  # cheminée d'aération
		P_BOX("rust", (0.15, 1.2, 0.02), (0.4, 1.0, -1.42)),               # coulure de rouille
	]


# ===========================================================================
# WASTELAND — industriel (tuyaux, poteau, château d'eau, derrick, grue)
# ===========================================================================

def parts_pipe_straight():
	return [
		P_CYL("painted_metal", 0.08, 2.0, (0, 0.08, 0), r2=0.08),
		P_CYL("rust", 0.12, 0.05, (0, 0.08, -1.0), r2=0.12),
		P_CYL("rust", 0.12, 0.05, (0, 0.08, 1.0), r2=0.12),
		P_CYL("accent", 0.13, 0.02, (0, 0.08, -1.0), r2=0.10),
	]


def parts_pipe_elbow():
	return [
		P_CYL("painted_metal", 0.08, 0.8, (0, 0.08, -0.4), r2=0.08),
		P_CYL("painted_metal", 0.10, 0.18, (0, 0.08, 0), r2=0.10, rot=("X", 45)),
		P_CYL("painted_metal", 0.08, 0.8, (0, 0.48, 0), r2=0.08, rot=("X", -90)),
		P_CYL("rust", 0.12, 0.04, (0, 0.9, 0), r2=0.12, rot=("X", -90)),
	]


def parts_pipe_valve():
	return [
		P_CYL("painted_metal", 0.07, 0.35, (0, 0.08, -0.3), r2=0.07),
		P_CYL("painted_metal", 0.07, 0.35, (0, 0.08, 0.3), r2=0.07),
		P_BOX("rust", (0.22, 0.22, 0.22), (0, 0.08, 0)),
		P_CYL("accent", 0.025, 0.25, (0, 0.315, 0), r2=0.025, rot=("X", -90)),
		P_RING("accent", 0.13, 0.025, (0, 0.46, 0), axis="Z"),
		P_STRUT("accent", (-0.13, 0.46, 0), (0.13, 0.46, 0), 0.02),
		P_STRUT("accent", (0, 0.33, 0), (0, 0.59, 0), 0.02),
	]


def parts_power_pole():
	return [
		P_CYL("wood", 0.11, 7.0, (0, 3.5, 0), r2=0.08, seg=8, rot=("X", -90)),
		P_BOX("wood", (1.6, 0.12, 0.12), (0, 6.6, 0)),
		P_BOX("wood", (0.12, 0.1, 1.0), (0, 6.2, 0)),
		P_CYL("accent", 0.04, 0.12, (-0.7, 6.7, 0), r2=0.03, rot=("X", -90)),
		P_CYL("accent", 0.04, 0.12, (0.7, 6.7, 0), r2=0.03, rot=("X", -90)),
		P_CYL("accent", 0.04, 0.12, (0, 6.2, 0.45), r2=0.03, rot=("X", -90)),
		P_STRUT("wood", (-0.05, 6.4, 0), (-0.55, 6.55, 0), 0.04),
		P_STRUT("wood", (0.05, 6.4, 0), (0.55, 6.55, 0), 0.04),
		P_CYL("rust", 0.15, 0.1, (0, 0.15, 0), r2=0.15, rot=("X", -90)),
	]


def parts_water_tower():
	parts = [
		P_CYL("painted_metal", 1.6, 2.6, (0, 6.8, 0), r2=1.6, seg=16, rot=("X", -90)),
		P_CYL("rust", 1.65, 1.1, (0, 8.65, 0), r2=0.1, seg=16, rot=("X", -90)),
		P_CYL("rust", 1.6, 0.3, (0, 5.35, 0), r2=1.5, seg=16, rot=("X", -90)),
		P_STRUT("painted_metal", (-1.3, 0, -1.3), (-0.5, 5.5, -0.5), 0.14),
		P_STRUT("painted_metal", (1.3, 0, -1.3), (0.5, 5.5, -0.5), 0.14),
		P_STRUT("painted_metal", (-1.3, 0, 1.3), (-0.5, 5.5, 0.5), 0.14),
		P_STRUT("painted_metal", (1.3, 0, 1.3), (0.5, 5.5, 0.5), 0.14),
	]
	for y0, y1, halfw in ((1.8, 3.2, 1.0), (3.2, 4.6, 0.75)):
		t0, t1 = y0 / 5.5, y1 / 5.5
		hw0 = 1.3 + (0.5 - 1.3) * t0
		hw1 = 1.3 + (0.5 - 1.3) * t1
		parts.append(P_STRUT("painted_metal", (-hw0, y0, -hw0), (hw1, y1, -hw1), 0.06))
		parts.append(P_STRUT("painted_metal", (hw0, y0, -hw0), (-hw1, y1, -hw1), 0.06))
		parts.append(P_STRUT("painted_metal", (-hw0, y0, hw0), (hw1, y1, hw1), 0.06))
		parts.append(P_STRUT("painted_metal", (hw0, y0, hw0), (-hw1, y1, hw1), 0.06))
	return parts


def parts_oil_derrick():
	parts = [P_LATTICE("painted_metal", base_half=1.9, top_half=0.35, height=9.5,
		levels=[2.2, 4.6, 7.0, 9.0], leg_th=0.12, brace_th=0.06)]
	parts.append(P_BOX("rust", (0.9, 0.3, 0.9), (0, 9.55, 0)))  # plateforme sommitale
	return parts


def parts_gantry_crane():
	parts = [
		P_LATTICE("painted_metal", base_half=1.0, top_half=0.5, height=5.5,
			levels=[2.0, 4.0], leg_th=0.12, brace_th=0.05, center_xz=(-2.6, 0.0)),
		P_LATTICE("painted_metal", base_half=1.0, top_half=0.5, height=5.5,
			levels=[2.0, 4.0], leg_th=0.12, brace_th=0.05, center_xz=(2.6, 0.0)),
		P_STRUT("painted_metal", (-2.6, 5.6, 0), (2.6, 5.6, 0), 0.15),
		P_STRUT("painted_metal", (-2.6, 6.0, 0), (2.6, 6.0, 0), 0.12),
		P_BOX("rust", (0.6, 0.4, 0.6), (0, 5.3, 0)),                       # chariot
		P_STRUT("accent", (0, 5.3, 0), (0, 3.5, 0), 0.02),                 # câble
	]
	xs = [-2.6, -1.73, -0.87, 0.0, 0.87, 1.73, 2.6]
	for i in range(len(xs) - 1):
		parts.append(P_STRUT("painted_metal", (xs[i], 5.6, 0), (xs[i + 1], 6.0, 0), 0.03))
		parts.append(P_STRUT("painted_metal", (xs[i + 1], 5.6, 0), (xs[i], 6.0, 0), 0.03))
	return parts


# ===========================================================================
# WASTELAND — clôtures / nature
# ===========================================================================

def parts_fence_wood():
	return [
		P_BOX("wood", (0.12, 1.2, 0.12), (-1.0, 0.6, 0)),
		P_BOX("wood", (0.12, 1.2, 0.12), (1.0, 0.6, 0)),
		P_BOX("wood", (2.2, 0.1, 0.06), (0, 1.05, 0)),
		P_BOX("wood", (2.2, 0.1, 0.06), (0, 0.65, 0)),
		P_BOX("wood", (2.2, 0.1, 0.06), (0, 0.25, 0)),
	]


def parts_fence_chainlink():
	return [
		P_CYL("painted_metal", 0.04, 1.5, (-1.0, 0.75, 0), r2=0.04, rot=("X", -90)),
		P_CYL("painted_metal", 0.04, 1.5, (1.0, 0.75, 0), r2=0.04, rot=("X", -90)),
		P_CYL("painted_metal", 0.035, 2.0, (0, 1.48, 0), r2=0.035, rot=("Y", 90)),
		P_BOX("glass", (1.9, 1.35, 0.02), (0, 0.75, 0)),                   # panneau grillagé (alpha)
	]


def parts_sandbags():
	return [
		P_BOX("sand", (0.42, 0.26, 0.30), (-0.42, 0.13, 0.0)),
		P_BOX("sand", (0.42, 0.26, 0.30), (0.0, 0.13, 0.02)),
		P_BOX("sand", (0.42, 0.26, 0.30), (0.42, 0.13, -0.02)),
		P_BOX("sand", (0.40, 0.24, 0.29), (-0.21, 0.37, 0.01)),
		P_BOX("sand", (0.40, 0.24, 0.29), (0.21, 0.37, -0.01)),
	]


def parts_rock_small():
	return [
		P_BOX("concrete", (0.42, 0.30, 0.38), (0, 0.15, 0), rot=("Y", 15)),
		P_BOX("concrete", (0.26, 0.22, 0.24), (0.15, 0.22, 0.1), rot=("Y", -25)),
	]


def parts_rock_medium():
	return [
		P_BOX("concrete", (0.8, 0.55, 0.7), (0, 0.28, 0), rot=("Y", 20)),
		P_BOX("concrete", (0.5, 0.4, 0.45), (0.25, 0.5, 0.15), rot=("Y", -15)),
		P_BOX("concrete", (0.35, 0.3, 0.35), (-0.3, 0.4, -0.1), rot=("Y", 40)),
	]


def parts_rock_large():
	return [
		P_BOX("concrete", (1.4, 1.0, 1.2), (0, 0.5, 0), rot=("Y", 10)),
		P_BOX("concrete", (0.9, 0.7, 0.8), (0.4, 0.9, 0.2), rot=("Y", -20)),
		P_BOX("concrete", (0.7, 0.55, 0.65), (-0.5, 0.75, -0.3), rot=("Y", 35)),
		P_BOX("concrete", (0.5, 0.4, 0.5), (0.1, 1.2, -0.4), rot=("Y", -10)),
	]


def parts_cactus():
	# Tronc + bras "coude horizontal courant -> segment vertical" : une seule
	# rotation cardinale par pièce ne peut pas viser une direction diagonale
	# (X et Y non nuls à la fois) depuis l'axe par défaut (Z) — un bras de
	# saguaro stylisé en 2 segments (coude horizontal + remontée verticale)
	# donne la même silhouette lisible sans avoir besoin d'un axe composé.
	return [
		P_CYL("sand", 0.35, 0.15, (0, 0.07, 0), r2=0.3, rot=("X", -90)),               # butte de sable
		P_CYL("accent", 0.14, 2.0, (0, 1.0, 0), r2=0.11, seg=8, rot=("X", -90)),       # tronc
		P_CYL("accent", 0.07, 0.3, (-0.27, 1.3, 0), r2=0.06, rot=("Y", -90)),          # coude bras gauche
		P_CYL("accent", 0.06, 0.55, (-0.4, 1.6, 0), r2=0.05, rot=("X", -90)),          # remontée bras gauche
		P_CYL("accent", 0.07, 0.3, (0.27, 1.15, 0), r2=0.06, rot=("Y", 90)),           # coude bras droit
		P_CYL("accent", 0.06, 0.5, (0.4, 1.45, 0), r2=0.05, rot=("X", -90)),           # remontée bras droit
		P_CYL("accent", 0.1, 0.15, (0, 2.05, 0), r2=0.02, rot=("X", -90)),             # sommet arrondi
	]


# ===========================================================================
# WASTELAND — devantures (passe détail R2 : la rue lisait "trop boîtes" en
# comparaison à .orchestrator/refs/wasteland_hero.png — ces devantures
# ajoutent fenêtres encadrées, porches, balcons, enseignes 3D et fouillis de
# toiture pour casser la silhouette plate).
# ===========================================================================

def parts_shopfront_1_store():
	parts = [
		P_BOX("wood", (3.8, 2.7, 2.0), (0, 1.35, 0.4)),                    # mur principal
		P_BOX("wood", (4.0, 0.15, 1.4), (0, 0.08, -1.3)),                  # terrasse
		P_BOX("wood", (0.12, 2.2, 0.12), (-1.75, 1.1, -1.95)),             # poteau porche G
		P_BOX("wood", (0.12, 2.2, 0.12), (1.75, 1.1, -1.95)),              # poteau porche D
		P_BOX("wood", (4.3, 0.08, 1.6), (0, 2.55, -1.7), rot=("X", -8)),   # auvent
		P_BOX("corrugated", (4.0, 0.15, 2.2), (0, 2.72, 0.4)),             # toit plat
	]
	parts += window_parts(0.85, 1.1, (-1.15, 1.55), wall_face_z=-0.6, shutters=True)
	parts += window_parts(0.85, 1.1, (1.15, 1.55), wall_face_z=-0.6, shutters=True)
	parts += door_parts(0.9, 1.95, (0, 1.05), wall_face_z=-0.6)
	parts += sign_board_parts("STORE", 2.6, 0.8, (0, 3.25, -0.55))
	parts += roof_clutter_parts((0, 2.8, 0.4), spread=0.9)
	return parts


def parts_shopfront_1_bar():
	parts = [
		P_BOX("wood", (3.4, 2.6, 1.9), (0, 1.3, 0.35)),
		P_BOX("corrugated", (3.8, 0.1, 2.1), (0, 2.68, 0.3), rot=("X", 6)),
		P_STRUT("painted_metal", (-1.9, 2.3, -1.15), (-1.6, 2.55, -1.55), 0.04),
		P_STRUT("painted_metal", (1.9, 2.3, -1.15), (1.6, 2.55, -1.55), 0.04),
	]
	parts += window_parts(0.8, 1.0, (1.0, 1.5), wall_face_z=-0.6, shutters=True)
	parts += door_parts(0.85, 1.9, (-0.75, 1.0), wall_face_z=-0.6)
	parts += sign_board_parts("BAR", 1.8, 0.7, (0, 3.05, -0.5))
	parts.append(P_CYL("rust", 0.28, 0.8, (1.55, 0.4, -1.9), r2=0.28, rot=("X", -90)))  # tonneau devant
	parts += roof_clutter_parts((-0.8, 2.75, 0.3), spread=0.7)
	return parts


def parts_shopfront_2_saloon():
	parts = [
		P_BOX("wood", (4.2, 2.6, 2.0), (0, 1.3, 0.4)),                     # rdc
		P_BOX("wood", (4.2, 2.4, 1.8), (0, 3.9, 0.3)),                     # étage
		P_BOX("wood", (4.4, 0.12, 1.0), (0, 2.65, -0.75)),                 # plancher balcon
		P_BOX("wood", (0.12, 2.7, 0.12), (-1.9, 1.35, -1.5)),              # poteau galerie G
		P_BOX("wood", (0.12, 2.7, 0.12), (1.9, 1.35, -1.5)),               # poteau galerie D
		P_BOX("wood", (4.6, 0.7, 2.0), (0, 5.55, 0.3)),                    # fronton (façade western)
	]
	parts += balcony_rail_parts("wood", -2.1, 2.1, 2.71, -1.25, post_h=0.85, n_balusters=7)
	parts += window_parts(0.8, 1.05, (-1.2, 1.55), wall_face_z=-0.6, shutters=True)
	parts += window_parts(0.8, 1.05, (1.2, 1.55), wall_face_z=-0.6, shutters=True)
	parts += door_parts(0.9, 1.95, (0, 1.05), wall_face_z=-0.6)
	parts += window_parts(0.7, 1.0, (-1.35, 4.05), wall_face_z=-0.6, shutters=True)
	parts += window_parts(0.7, 1.0, (0, 4.05), wall_face_z=-0.6, shutters=True)
	parts += window_parts(0.7, 1.0, (1.35, 4.05), wall_face_z=-0.6, shutters=True)
	parts += sign_board_parts("SALOON", 3.2, 0.85, (0, 6.0, -0.85))  # proud du fronton (face -0.7)
	parts += roof_clutter_parts((1.2, 5.95, 0.3), spread=0.9)
	return parts


def parts_shopfront_2_motel():
	parts = [
		P_BOX("wood", (4.0, 2.5, 1.8), (0, 1.25, 0.3)),
		P_BOX("wood", (4.0, 2.3, 1.6), (0, 3.65, 0.2)),
		P_BOX("wood", (4.2, 0.12, 0.9), (0, 2.55, -0.7)),
		P_BOX("wood", (0.12, 2.6, 0.12), (-1.8, 1.3, -1.4)),
		P_BOX("wood", (0.12, 2.6, 0.12), (1.8, 1.3, -1.4)),
		P_BOX("corrugated", (4.3, 0.12, 1.9), (0, 4.9, 0.2)),
	]
	parts += balcony_rail_parts("wood", -1.95, 1.95, 2.61, -1.15, post_h=0.8, n_balusters=6)
	parts += door_parts(0.85, 1.9, (-0.9, 1.0), wall_face_z=-0.6)
	parts += window_parts(0.75, 1.0, (0.9, 1.5), wall_face_z=-0.6)
	parts += window_parts(0.7, 0.95, (-1.2, 3.85), wall_face_z=-0.6)
	parts += window_parts(0.7, 0.95, (1.2, 3.85), wall_face_z=-0.6)
	# Enseigne "MOTEL" en potence : bras horizontal en saillie (+X) depuis la
	# façade, panneau resté face -Z (axe-aligné, même convention lecture que
	# tout le reste du fichier) monté au bout du bras — lu depuis la rue
	# exactement comme les autres enseignes, juste déporté au-dessus du
	# trottoir (silhouette "potence" classique sans risquer un texte miroir).
	parts.append(P_STRUT("painted_metal", (1.9, 4.1, -0.6), (2.9, 4.3, -0.6), 0.06))
	parts += sign_board_parts("MOTEL", 1.5, 0.65, (2.9, 4.3, -0.95))
	parts += roof_clutter_parts((-1.2, 5.05, 0.2), spread=0.8)
	return parts


def parts_shopfront_corner_garage():
	# Bâtiment d'angle en L (2 façades perpendiculaires) — porte de baie sur
	# la face -Z, entrée piétonne sur la face -X, enseigne à 45° au coin.
	parts = [
		P_BOX("corrugated", (4.4, 2.9, 2.2), (-0.3, 1.45, 0.1)),           # aile -Z
		P_BOX("corrugated", (2.2, 2.9, 3.6), (1.6, 1.45, 1.3)),            # aile -X
		P_BOX("corrugated", (4.7, 0.15, 2.4), (-0.3, 2.95, 0.1)),          # toit aile -Z
		P_BOX("corrugated", (2.4, 0.15, 3.8), (1.6, 2.95, 1.3)),           # toit aile -X
	]
	parts.append(P_BOX("painted_metal", (2.4, 2.2, 0.1), (-1.1, 1.15, -1.0)))  # baie de garage (face -Z)
	for gx in (-1.9, -1.1, -0.3):
		parts.append(P_BOX("accent", (0.04, 2.2, 0.02), (gx, 1.15, -1.05)))
	parts += window_parts(0.7, 0.9, (0.75, 1.5), wall_face_z=-1.0)
	parts.append(P_BOX("wood", (0.07, 1.95, 0.9), (2.66, 1.0, 1.3)))       # porte piétonne (face -X, normale +X)
	parts.append(P_BOX("accent", (0.04, 0.04, 0.05), (2.61, 0.95, 1.42)))  # poignée
	# Enseigne côté baie, proche du coin (axe-aligné face -Z, même convention
	# lecture éprouvée que les autres devantures).
	parts += sign_board_parts("GARAGE", 2.0, 0.7, (-1.0, 3.55, -1.22))  # proud du toit (face -1.1)
	parts += roof_clutter_parts((-0.6, 3.15, 0.1), spread=0.8)
	return parts


def parts_balcony_railing():
	# Module attachable : plateforme + rambarde, à visser sur n'importe quelle
	# façade à l'étage souhaité.
	parts = [P_BOX("wood", (2.4, 0.12, 0.9), (0, 0.06, 0))]
	parts += balcony_rail_parts("wood", -1.15, 1.15, 0.12, 0.4, post_h=0.85, n_balusters=6)
	parts.append(P_STRUT("wood", (-1.1, 0.06, -0.4), (-1.1, -0.55, 0.35), 0.05))
	parts.append(P_STRUT("wood", (1.1, 0.06, -0.4), (1.1, -0.55, 0.35), 0.05))
	return parts


def parts_exterior_stairs():
	parts = [
		P_STRUT("wood", (-0.42, 0, 0), (-0.42, 2.2, -2.6), 0.05),
		P_STRUT("wood", (0.42, 0, 0), (0.42, 2.2, -2.6), 0.05),
		P_STRUT("wood", (-0.42, 0.9, 0), (-0.42, 3.05, -2.6), 0.04),
		P_STRUT("wood", (0.42, 0.9, 0), (0.42, 3.05, -2.6), 0.04),
	]
	for i in range(1, 9):
		t = i / 8.0
		parts.append(P_BOX("wood", (0.9, 0.06, 0.30), (0, 2.2 * t, -2.6 * t)))
	return parts


# ===========================================================================
# WASTELAND — fouillis de rue (casse le sol plat)
# ===========================================================================

def parts_junk_pile():
	return [
		P_BOX("rust", (0.7, 0.35, 0.55), (0, 0.18, 0), rot=("Y", 12)),
		P_BOX("painted_metal", (0.5, 0.25, 0.4), (0.35, 0.42, 0.15), rot=("Y", -20)),
		P_BOX("rust", (0.45, 0.2, 0.5), (-0.3, 0.4, -0.1), rot=("Y", 30)),
		P_CYL("painted_metal", 0.06, 0.5, (0.1, 0.55, 0.25), r2=0.05, rot=("Z", 70)),
		P_CYL("rust", 0.05, 0.4, (-0.25, 0.5, 0.1), r2=0.04, rot=("Z", -60)),
		P_BOX("accent", (0.2, 0.15, 0.02), (0.2, 0.3, 0.3), rot=("Y", -15)),
	]


def parts_scrap_sheets():
	return [
		P_BOX("corrugated", (1.1, 1.4, 0.04), (0, 0.65, 0.05), rot=("X", 24)),
		P_BOX("rust", (0.9, 1.2, 0.04), (0.25, 0.55, 0.25), rot=("X", 20)),
		P_BOX("corrugated", (0.7, 1.0, 0.04), (-0.3, 0.42, 0.3), rot=("X", 28)),
	]


def parts_cable_spool():
	return [
		P_CYL("wood", 0.55, 0.06, (-0.42, 0.55, 0), r2=0.55, rot=("Y", 90)),
		P_CYL("wood", 0.55, 0.06, (0.42, 0.55, 0), r2=0.55, rot=("Y", 90)),
		P_CYL("wood", 0.15, 0.84, (0, 0.55, 0), r2=0.15, rot=("Y", 90)),
		P_RING("accent", 0.15, 0.045, (0, 0.55, 0), ring_seg=14, tube_seg=6, axis="X"),
	]


def parts_crate_stack():
	return [
		P_BOX("wood", (0.75, 0.7, 0.75), (0, 0.35, 0), rot=("Y", 6)),
		P_BOX("wood", (0.65, 0.6, 0.65), (0.08, 1.0, -0.05), rot=("Y", -10)),
		P_BOX("wood", (0.55, 0.5, 0.55), (-0.1, 1.5, 0.1), rot=("Y", 18)),
		P_BOX("accent", (0.25, 0.2, 0.02), (0.1, 0.35, 0.38), rot=("Y", 6)),
	]


def parts_bottle_crates():
	parts = [
		P_BOX("wood", (0.55, 0.28, 0.4), (0, 0.14, 0)),
		P_BOX("wood", (0.5, 0.26, 0.36), (0.05, 0.42, -0.03), rot=("Y", 8)),
	]
	for ix in range(3):
		for iz in range(2):
			x = -0.15 + ix * 0.15
			z = -0.09 + iz * 0.18
			parts.append(P_CYL("glass", 0.03, 0.14, (0.05 + x, 0.62, -0.03 + z), r2=0.02))
	return parts


def parts_tyre_ground():
	return [P_RING("rubber", 0.33, 0.115, (0, 0.115, 0), ring_seg=14, tube_seg=7, axis="Y")]


def parts_fence_broken():
	return [
		P_BOX("wood", (0.12, 1.2, 0.12), (-1.0, 0.6, 0)),
		P_BOX("wood", (0.12, 1.1, 0.12), (1.0, 0.52, 0.05), rot=("Z", -22)),      # poteau penché
		P_BOX("wood", (1.15, 0.1, 0.05), (-0.42, 1.02, 0), rot=("Z", 4)),
		P_BOX("wood", (0.7, 0.1, 0.05), (0.55, 0.55, 0.02), rot=("Z", -35)),      # planche pendante
		P_BOX("wood", (0.9, 0.08, 0.05), (0.15, 0.05, 0.35), rot=("Y", 18)),      # planche au sol
	]


def parts_street_lamp():
	return [
		P_CYL("concrete", 0.18, 0.1, (0, 0.05, 0), r2=0.18, rot=("X", -90)),
		P_CYL("painted_metal", 0.07, 3.8, (0, 2.0, 0), r2=0.05, seg=8, rot=("X", -90)),
		P_STRUT("painted_metal", (0, 3.85, 0), (0.45, 4.05, 0), 0.04),
		P_BOX("glass", (0.28, 0.22, 0.28), (0.55, 3.95, 0)),
		P_BOX("rust", (0.32, 0.05, 0.32), (0.55, 4.08, 0)),
	]


def parts_wires_catenary():
	# Câble affaissé entre 2 points (approximation de chaînette par segments)
	# — kind fin, tris négligeables. Portée fixe ~7.4 m, flèche ~1.1 m. Origine
	# = base centrée au point le plus bas du creux (convention "base centre"),
	# à charge du niveau de placer le prop à la hauteur de montage voulue
	# (ex. juste sous les traverses de 2 power_pole).
	span, sag, seg_n = 7.4, 1.1, 10
	pts = []
	for i in range(seg_n + 1):
		t = i / seg_n
		x = -span * 0.5 + span * t
		y = sag - sag * 4.0 * t * (1.0 - t)  # parabole (chaînette approx.), 0 au creux
		pts.append((x, y, 0.0))
	parts = []
	for i in range(seg_n):
		parts.append(P_STRUT("painted_metal", pts[i], pts[i + 1], 0.018))
	return parts


# ===========================================================================
# CARGO SHIP — conteneurs
# ===========================================================================

def _container_parts(length: float, rib_count: int, offset=(0.0, 0.0, 0.0), open_door=False):
	ox, oy, oz = offset
	half_l = length / 2.0
	parts = [P_BOX("container", (2.44, 2.59, length), (ox, oy + 1.295, oz))]
	step = (length - 0.6) / (rib_count - 1)
	z0 = -half_l + 0.3
	for i in range(rib_count):
		z = z0 + step * i
		parts.append(P_BOX("container", (0.06, 2.5, 0.12), (ox - 1.25, oy + 1.3, oz + z)))
		parts.append(P_BOX("container", (0.06, 2.5, 0.12), (ox + 1.25, oy + 1.3, oz + z)))
	if open_door:
		# Porte gauche fermée, porte droite ouverte à 100° (pivot sur son
		# bord extérieur) + cavité sombre suggérant l'intérieur du conteneur.
		parts.append(P_BOX("container", (1.15, 2.4, 0.08), (ox - 0.61, oy + 1.25, oz - half_l - 0.02)))
		parts.append(P_BOX("container", (2.2, 2.3, 4.6), (ox, oy + 1.25, oz + 2.0)))  # cavité intérieure sombre
		hinge_x, hinge_z = ox + 0.005, oz - half_l - 0.02
		door_center = Vector((ox + 0.615, oy + 1.25, hinge_z))
		hinge = Vector((hinge_x, oy + 1.25, hinge_z))
		rel = door_center - hinge
		rad = math.radians(100.0)
		rel_rot = Vector((rel.x * math.cos(rad) - rel.z * math.sin(rad), rel.y,
			rel.x * math.sin(rad) + rel.z * math.cos(rad)))
		final = hinge + rel_rot
		parts.append(P_BOX("container", (1.15, 2.4, 0.08), (final.x, final.y, final.z), rot=("Y", 100)))
	else:
		parts += [
			P_BOX("container", (1.15, 2.4, 0.08), (ox - 0.61, oy + 1.25, oz - half_l - 0.02)),
			P_BOX("container", (1.15, 2.4, 0.08), (ox + 0.61, oy + 1.25, oz - half_l - 0.02)),
			P_BOX("accent", (2.3, 0.08, 0.05), (ox, oy + 1.7, oz - half_l - 0.07)),
			P_BOX("accent", (2.3, 0.08, 0.05), (ox, oy + 0.8, oz - half_l - 0.07)),
		]
	for x in (-1.2, 1.2):
		for y in (0.1, 2.5):
			for z in (-half_l + 0.05, half_l - 0.05):
				parts.append(P_BOX("accent", (0.18, 0.18, 0.18), (ox + x, oy + y, oz + z)))
	return parts


def parts_container_20ft():
	return _container_parts(6.06, 7)


def parts_container_40ft():
	return _container_parts(12.19, 18)


def parts_container_open20():
	return _container_parts(6.06, 7, open_door=True)


def parts_container_stack2():
	# 2 conteneurs 20 ft empilés avec un léger décalage (X/Z) — silhouette de
	# cour à conteneurs plutôt qu'une tour bien rangée.
	return _container_parts(6.06, 7, offset=(0.0, 0.0, 0.0)) + \
		_container_parts(6.06, 7, offset=(0.35, 2.59, -0.4))


def parts_container_stack3():
	return _container_parts(6.06, 7, offset=(0.0, 0.0, 0.0)) + \
		_container_parts(6.06, 7, offset=(0.3, 2.59, -0.35)) + \
		_container_parts(6.06, 7, offset=(-0.25, 5.18, 0.15))


# ===========================================================================
# CARGO SHIP — coque
# ===========================================================================

def parts_hull_bow():
	return [
		P_BOX("painted_metal", (6.0, 4.0, 5.0), (0, 2.0, 0.7)),
		P_BOX("painted_metal", (3.4, 4.0, 3.4), (-1.5, 2.0, -3.0), rot=("Y", 35)),
		P_BOX("painted_metal", (3.4, 4.0, 3.4), (1.5, 2.0, -3.0), rot=("Y", -35)),
		P_BOX("ship_deck", (6.4, 0.3, 7.6), (0, 4.15, 0.1)),
		P_BOX("rust", (6.3, 0.45, 7.6), (0, 0.35, 0.1)),
		P_CYL("rust", 0.18, 0.5, (-2.6, 3.6, -2.0), r2=0.18, rot=("Y", 90)),
		P_CYL("rust", 0.18, 0.5, (2.6, 3.6, -2.0), r2=0.18, rot=("Y", 90)),
	]


def parts_hull_mid():
	parts = [
		P_BOX("painted_metal", (6.8, 4.2, 8.8), (0, 2.1, 0)),
		P_BOX("ship_deck", (7.0, 0.3, 9.0), (0, 4.35, 0)),
		P_BOX("rust", (7.1, 0.5, 9.1), (0, 0.35, 0)),
		P_STRUT("painted_metal", (-3.5, 4.5, -4.4), (-3.5, 4.5, 4.4), 0.04),
		P_STRUT("painted_metal", (3.5, 4.5, -4.4), (3.5, 4.5, 4.4), 0.04),
	]
	for z in (-3.0, -1.0, 1.0, 3.0):
		parts.append(P_CYL("glass", 0.18, 0.08, (3.44, 2.6, z), r2=0.18, rot=("Y", 90)))
		parts.append(P_CYL("glass", 0.18, 0.08, (-3.44, 2.6, z), r2=0.18, rot=("Y", 90)))
	return parts


def parts_hull_stern():
	return [
		P_BOX("painted_metal", (6.0, 4.0, 5.5), (0, 2.0, -0.3)),
		P_BOX("painted_metal", (6.2, 4.2, 0.6), (0, 2.1, 2.8)),
		P_BOX("ship_deck", (6.4, 0.3, 6.2), (0, 4.15, -0.3)),
		P_BOX("rust", (6.3, 0.45, 6.6), (0, 0.35, -0.1)),
		P_BOX("rust", (0.15, 1.2, 0.9), (0, -0.2, 2.6)),                   # safran
		P_CYL("rust", 0.25, 1.0, (0, 0.1, 2.3), r2=0.15),                  # bossage d'hélice
		P_BOX("painted_metal", (2.0, 1.2, 1.4), (0, 4.9, -1.0)),           # roufle arrière
		P_BOX("glass", (1.8, 0.35, 0.06), (0, 5.1, -1.72)),
	]


def parts_bridge_superstructure():
	return [
		P_BOX("painted_metal", (5.0, 2.0, 4.2), (0, 1.0, 0)),
		P_BOX("painted_metal", (4.2, 1.8, 3.6), (0, 2.9, 0.1)),
		P_BOX("painted_metal", (3.4, 1.6, 3.0), (0, 4.6, 0.2)),
		P_BOX("glass", (4.3, 0.5, 3.7), (0, 3.55, 0.08)),
		P_BOX("glass", (3.5, 0.5, 3.1), (0, 5.25, 0.18)),
		P_BOX("ship_deck", (3.6, 0.2, 3.2), (0, 5.5, 0.2)),
		P_CYL("rust", 0.5, 1.6, (1.2, 6.3, -0.5), r2=0.45, rot=("X", -90)),
		P_CYL("accent", 0.55, 0.1, (1.2, 7.1, -0.5), r2=0.55, rot=("X", -90)),
		P_STRUT("painted_metal", (-1.8, 5.65, -1.6), (1.8, 5.65, -1.6), 0.03),
		P_STRUT("painted_metal", (-1.8, 5.65, 1.6), (1.8, 5.65, 1.6), 0.03),
		P_STRUT("painted_metal", (-1.8, 5.65, -1.6), (-1.8, 5.65, 1.6), 0.03),
		P_STRUT("painted_metal", (1.8, 5.65, -1.6), (1.8, 5.65, 1.6), 0.03),
		P_CYL("painted_metal", 0.06, 1.2, (0, 6.1, 0.2), r2=0.04, rot=("X", -90)),
		P_BOX("ship_deck", (0.7, 2.0, 0.9), (-2.3, 2.0, 1.5), rot=("Z", -8)),
	]


def parts_deck_railing():
	return [
		P_CYL("painted_metal", 0.035, 1.0, (-1.0, 0.5, 0), r2=0.035, rot=("X", -90)),
		P_CYL("painted_metal", 0.035, 1.0, (0.0, 0.5, 0), r2=0.035, rot=("X", -90)),
		P_CYL("painted_metal", 0.035, 1.0, (1.0, 0.5, 0), r2=0.035, rot=("X", -90)),
		P_CYL("painted_metal", 0.03, 2.0, (0, 1.0, 0), r2=0.03, rot=("Y", 90)),
		P_CYL("painted_metal", 0.03, 2.0, (0, 0.55, 0), r2=0.03, rot=("Y", 90)),
		P_BOX("painted_metal", (2.0, 0.08, 0.1), (0, 0.05, 0)),
	]


def parts_mast_antennas():
	return [
		P_CYL("painted_metal", 0.09, 6.0, (0, 3.0, 0), r2=0.05, seg=8, rot=("X", -90)),
		P_STRUT("painted_metal", (-0.9, 4.6, 0), (0.9, 4.6, 0), 0.06),
		P_CYL("accent", 0.015, 1.2, (0.3, 6.2, 0), r2=0.015, rot=("X", -90)),
		P_CYL("accent", 0.015, 0.9, (-0.3, 6.0, 0), r2=0.015, rot=("X", -90)),
		P_STRUT("painted_metal", (0, 5.6, 0), (0.5, 5.6, 0.3), 0.03),
		P_RING("accent", 0.22, 0.03, (0.5, 5.6, 0.3), axis="Z"),
		P_CYL("painted_metal", 0.02, 0.3, (0, 6.55, 0), r2=0.005, rot=("X", -90)),
	]


def parts_cargo_crane():
	parts = [
		P_LATTICE("painted_metal", base_half=1.1, top_half=0.6, height=8.5,
			levels=[2.5, 5.0, 7.0], leg_th=0.12, brace_th=0.05, center_xz=(0.0, -3.0)),
		P_STRUT("painted_metal", (0, 8.6, -3.0), (0, 8.6, 4.0), 0.12),
		P_STRUT("painted_metal", (0, 9.0, -3.0), (0, 9.0, 3.6), 0.09),
		P_BOX("rust", (1.6, 1.0, 1.2), (0, 8.2, -3.8)),
		P_BOX("glass", (1.0, 1.0, 1.0), (0, 8.0, -2.2)),
		P_STRUT("accent", (0, 8.6, 3.2), (0, 3.0, 3.2), 0.025),
		P_BOX("accent", (0.15, 0.2, 0.15), (0, 2.9, 3.2)),
	]
	zs = [-3.0, -1.15, 0.7, 2.5, 4.0]
	for i in range(len(zs) - 1):
		parts.append(P_STRUT("painted_metal", (0, 8.6, zs[i]), (0, 9.0, zs[i + 1]), 0.03))
		parts.append(P_STRUT("painted_metal", (0, 9.0, zs[i]), (0, 8.6, zs[i + 1]), 0.03))
	return parts


def parts_lifeboat_davits():
	return [
		P_BOX("accent", (0.9, 0.5, 2.0), (0, 1.3, 0)),
		P_BOX("accent", (0.7, 0.45, 0.7), (0, 1.32, 1.35)),
		P_BOX("accent", (0.7, 0.45, 0.7), (0, 1.32, -1.35)),
		P_BOX("painted_metal", (0.8, 0.35, 1.6), (0, 1.65, 0)),
		P_STRUT("painted_metal", (-1.5, 0, -1.4), (-1.5, 2.0, -1.4), 0.05),
		P_STRUT("painted_metal", (-1.5, 2.0, -1.4), (-0.5, 2.2, 0.3), 0.05),
		P_STRUT("painted_metal", (1.5, 0, -1.4), (1.5, 2.0, -1.4), 0.05),
		P_STRUT("painted_metal", (1.5, 2.0, -1.4), (0.5, 2.2, 0.3), 0.05),
	]


def parts_bollard():
	return [
		P_CYL("concrete", 0.16, 0.08, (0, 0.04, 0), r2=0.16, rot=("X", -90)),
		P_CYL("painted_metal", 0.13, 0.42, (0, 0.29, 0), r2=0.10, rot=("X", -90)),
		P_CYL("painted_metal", 0.15, 0.12, (0, 0.56, 0), r2=0.02, rot=("X", -90)),
		P_RING("accent", 0.06, 0.015, (0, 0.4, 0.11), axis="Z"),
	]


def parts_hatch_cover():
	parts = [P_BOX("ship_deck", (2.5, 0.15, 2.5), (0, 0.08, 0))]
	parts += [P_BOX("ship_deck", (2.5, 0.08, 0.15), (0, 0.19, z)) for z in (-0.9, -0.3, 0.3, 0.9)]
	for x in (-1.15, 1.15):
		for z in (-1.15, 1.15):
			parts.append(P_BOX("accent", (0.18, 0.18, 0.18), (x, 0.17, z)))
	return parts


def parts_stairs_ladder():
	parts = [
		P_STRUT("painted_metal", (-0.4, 0, 0), (-0.4, 2.0, -2.4), 0.04),
		P_STRUT("painted_metal", (0.4, 0, 0), (0.4, 2.0, -2.4), 0.04),
		P_STRUT("painted_metal", (-0.4, 0.9, 0), (-0.4, 2.9, -2.4), 0.025),
		P_STRUT("painted_metal", (0.4, 0.9, 0), (0.4, 2.9, -2.4), 0.025),
	]
	for i in range(1, 9):
		t = i / 8.0
		parts.append(P_BOX("painted_metal", (0.9, 0.05, 0.28), (0, 2.0 * t, -2.4 * t)))
	return parts


def parts_life_ring():
	return [
		P_RING("accent", 0.32, 0.06, (0, 0.4, 0), axis="Z"),
		P_STRUT("sign", (-0.23, 0.63, 0), (0.23, 0.17, 0), 0.025),
		P_STRUT("sign", (-0.23, 0.17, 0), (0.23, 0.63, 0), 0.025),
		P_BOX("painted_metal", (0.1, 0.15, 0.05), (0, 0.75, 0.05)),
	]


def parts_gangway():
	return [
		P_BOX("ship_deck", (1.3, 0.08, 4.0), (0, 1.0, 0), rot=("X", 28)),
		P_STRUT("painted_metal", (-0.6, 0.9, -2.0), (-0.6, 2.7, 2.0), 0.03),
		P_STRUT("painted_metal", (0.6, 0.9, -2.0), (0.6, 2.7, 2.0), 0.03),
		P_STRUT("painted_metal", (-0.62, 0.05, -2.0), (-0.62, 1.9, 2.0), 0.04),
		P_STRUT("painted_metal", (0.62, 0.05, -2.0), (0.62, 1.9, 2.0), 0.04),
	]


# ===========================================================================
# CARGO SHIP — fouillis de pont (passe détail R2)
# ===========================================================================

def parts_deck_hatch():
	# Variante "sécurité" de hatch_cover : liséré jaune (kind `accent`, teinté
	# jaune par défaut dans l'aperçu — voir PROP_TINT_OVERRIDE de prop_shots.gd)
	# le long des 4 bords, convention chantier naval.
	parts = [P_BOX("ship_deck", (2.5, 0.15, 2.5), (0, 0.08, 0))]
	parts += [P_BOX("ship_deck", (2.5, 0.08, 0.15), (0, 0.19, z)) for z in (-0.9, -0.3, 0.3, 0.9)]
	for x in (-1.15, 1.15):
		for z in (-1.15, 1.15):
			parts.append(P_BOX("accent", (0.18, 0.18, 0.18), (x, 0.17, z)))
	edge = 0.08
	parts.append(P_BOX("accent", (2.5, 0.02, edge), (0, 0.235, -1.25 + edge * 0.5)))
	parts.append(P_BOX("accent", (2.5, 0.02, edge), (0, 0.235, 1.25 - edge * 0.5)))
	parts.append(P_BOX("accent", (edge, 0.02, 2.5), (-1.25 + edge * 0.5, 0.235, 0)))
	parts.append(P_BOX("accent", (edge, 0.02, 2.5), (1.25 - edge * 0.5, 0.235, 0)))
	return parts


def parts_lashing_bar():
	return [
		P_STRUT("painted_metal", (-0.42, 0.06, 0), (0.42, 0.32, 0), 0.03),
		P_CYL("rust", 0.05, 0.08, (-0.44, 0.06, 0), r2=0.05, rot=("X", -90)),
		P_CYL("rust", 0.05, 0.08, (0.44, 0.32, 0), r2=0.05, rot=("X", -90)),
		P_CYL("accent", 0.035, 0.1, (0, 0.19, 0), r2=0.035, rot=("X", -90)),  # tendeur
	]


def parts_pipe_manifold():
	parts = [
		P_STRUT("painted_metal", (-0.55, 0.2, 0), (0.55, 0.2, 0), 0.05),   # console murale
		P_STRUT("painted_metal", (-0.55, 0.7, 0), (0.55, 0.7, 0), 0.05),
	]
	for i, y in enumerate((0.32, 0.48, 0.64)):
		parts.append(P_CYL("painted_metal", 0.05, 1.5, (0, y, 0), r2=0.05, seg=8))
		parts.append(P_CYL("rust", 0.075, 0.04, (0, y, -0.75), r2=0.075, seg=8))
		parts.append(P_CYL("rust", 0.075, 0.04, (0, y, 0.75), r2=0.075, seg=8))
	parts.append(P_RING("accent", 0.11, 0.02, (0, 0.32, 0.75), ring_seg=10, tube_seg=5, axis="Z"))
	parts.append(P_RING("accent", 0.11, 0.02, (0, 0.64, -0.75), ring_seg=10, tube_seg=5, axis="Z"))
	return parts


# ===========================================================================
# Registre — nom -> (parts_fn, bevel_width, set, footprint(w,d,h), collision)
# ===========================================================================

PROPS = {
	# --- wasteland ---
	"truck_wreck":            (parts_truck_wreck, 0.02, SET_WASTELAND, (2.0, 5.0, 1.8),
		[{"size": [2.0, 3.2, 1.8], "center": [0.0, 0.9, -1.5]}, {"size": [1.9, 2.8, 1.3], "center": [0.0, 0.65, 0.9]}]),
	"sedan_wreck":             (parts_sedan_wreck, 0.015, SET_WASTELAND, (2.45, 4.9, 1.4), None),
	"fuel_pump":               (parts_fuel_pump, 0.008, SET_WASTELAND, (0.6, 0.6, 1.7), None),
	"fuel_billboard":          (parts_fuel_billboard, 0.012, SET_WASTELAND, (2.6, 0.5, 3.4), None),
	"gas_billboard":           (parts_gas_billboard, 0.012, SET_WASTELAND, (1.4, 1.0, 4.6), None),
	"shop_sign":               (parts_shop_sign, 0.008, SET_WASTELAND, (1.9, 0.5, 1.3), None),
	"oil_drum":                (parts_oil_drum, 0.01, SET_WASTELAND, (0.6, 0.6, 0.9), None),
	"wooden_crate":            (parts_wooden_crate, 0.012, SET_WASTELAND, (0.8, 0.8, 0.8), None),
	"pallet":                  (parts_pallet, 0.008, SET_WASTELAND, (1.2, 1.0, 0.15), None),
	"tyre_stack":              (parts_tyre_stack, 0.01, SET_WASTELAND, (0.9, 0.9, 1.2), None),
	"wooden_shack":            (parts_wooden_shack, 0.02, SET_WASTELAND, (4.2, 4.35, 3.05), None),
	"corrugated_shed":         (parts_corrugated_shed, 0.018, SET_WASTELAND, (3.8, 3.2, 2.7), None),
	"pipe_straight":           (parts_pipe_straight, 0.008, SET_WASTELAND, (0.26, 2.0, 0.26), None),
	"pipe_elbow":              (parts_pipe_elbow, 0.008, SET_WASTELAND, (0.4, 1.0, 0.98), None),
	"pipe_valve":              (parts_pipe_valve, 0.006, SET_WASTELAND, (0.4, 0.94, 0.61), None),
	"power_pole":              (parts_power_pole, 0.012, SET_WASTELAND, (1.6, 1.0, 7.2), None),
	"water_tower":             (parts_water_tower, 0.03, SET_WASTELAND, (3.3, 3.3, 9.3),
		[{"size": [3.0, 3.0, 5.5], "center": [0.0, 2.75, 0.0]}, {"size": [3.4, 3.4, 3.9], "center": [0.0, 7.05, 0.0]}]),
	"oil_derrick":             (parts_oil_derrick, 0.02, SET_WASTELAND, (4.4, 4.4, 10.0), None),
	"gantry_crane":            (parts_gantry_crane, 0.02, SET_WASTELAND, (6.5, 3.2, 6.5), None),
	"fence_wood":              (parts_fence_wood, 0.006, SET_WASTELAND, (2.2, 0.15, 1.3), None),
	"fence_chainlink":         (parts_fence_chainlink, 0.006, SET_WASTELAND, (2.2, 0.1, 1.6), None),
	"sandbags":                (parts_sandbags, 0.015, SET_WASTELAND, (1.3, 0.55, 0.55), None),
	"rock_small":              (parts_rock_small, 0.03, SET_WASTELAND, (0.5, 0.4, 0.35), None),
	"rock_medium":             (parts_rock_medium, 0.05, SET_WASTELAND, (0.9, 0.75, 0.7), None),
	"rock_large":              (parts_rock_large, 0.07, SET_WASTELAND, (1.6, 1.3, 1.3), None),
	"cactus":                  (parts_cactus, 0.008, SET_WASTELAND, (0.8, 0.6, 2.4), None),
	# --- wasteland: devantures (R2) ---
	"shopfront_1_store":      (parts_shopfront_1_store, 0.02, SET_WASTELAND, (4.3, 4.0, 3.65), None),
	"shopfront_1_bar":        (parts_shopfront_1_bar, 0.018, SET_WASTELAND, (3.8, 3.4, 3.3), None),
	"shopfront_2_saloon":     (parts_shopfront_2_saloon, 0.02, SET_WASTELAND, (4.6, 3.0, 6.75), None),
	"shopfront_2_motel":      (parts_shopfront_2_motel, 0.02, SET_WASTELAND, (5.8, 2.7, 5.85),
		[{"size": [4.3, 3.35, 5.85], "center": [0.0, 2.93, 0.0]}]),
	"shopfront_corner_garage": (parts_shopfront_corner_garage, 0.02, SET_WASTELAND, (5.45, 4.41, 3.95),
		[{"size": [4.4, 2.2, 2.9], "center": [-0.3, 1.45, 0.1]}, {"size": [2.2, 3.6, 2.9], "center": [1.6, 1.45, 1.3]}]),
	"balcony_railing":        (parts_balcony_railing, 0.006, SET_WASTELAND, (2.4, 0.9, 1.56), None),
	"exterior_stairs":        (parts_exterior_stairs, 0.008, SET_WASTELAND, (0.9, 2.7, 3.1), None),
	# --- wasteland: fouillis de rue (R2) ---
	"junk_pile":              (parts_junk_pile, 0.012, SET_WASTELAND, (1.27, 0.93, 0.6), None),
	"scrap_sheets":           (parts_scrap_sheets, 0.008, SET_WASTELAND, (1.35, 0.8, 1.4), None),
	"cable_spool":            (parts_cable_spool, 0.012, SET_WASTELAND, (0.9, 1.1, 1.1), None),
	"crate_stack":            (parts_crate_stack, 0.012, SET_WASTELAND, (1.0, 1.0, 1.85), None),
	"bottle_crates":          (parts_bottle_crates, 0.008, SET_WASTELAND, (0.6, 0.5, 0.7), None),
	"tyre_ground":            (parts_tyre_ground, 0.006, SET_WASTELAND, (0.9, 0.9, 0.23), None),
	"fence_broken":           (parts_fence_broken, 0.006, SET_WASTELAND, (2.32, 0.58, 1.21), None),
	"street_lamp":            (parts_street_lamp, 0.008, SET_WASTELAND, (0.9, 0.4, 4.15), None),
	"wires_catenary":         (parts_wires_catenary, 0.004, SET_WASTELAND, (7.4, 0.2, 1.1), None),
	# --- cargo ship ---
	"container_20ft":          (parts_container_20ft, 0.01, SET_CARGO, (2.44, 6.06, 2.59), None),
	"container_40ft":          (parts_container_40ft, 0.01, SET_CARGO, (2.44, 12.19, 2.59), None),
	"hull_bow":                (parts_hull_bow, 0.03, SET_CARGO, (7.8, 9.3, 4.4), None),
	"hull_mid":                (parts_hull_mid, 0.03, SET_CARGO, (7.0, 9.0, 5.0), None),
	"hull_stern":              (parts_hull_stern, 0.03, SET_CARGO, (6.4, 6.6, 6.4), None),
	"bridge_superstructure":   (parts_bridge_superstructure, 0.025, SET_CARGO, (5.2, 4.5, 7.2), None),
	"deck_railing":            (parts_deck_railing, 0.006, SET_CARGO, (2.0, 0.12, 1.1), None),
	"mast_antennas":           (parts_mast_antennas, 0.01, SET_CARGO, (1.8, 0.45, 6.8), None),
	"cargo_crane":             (parts_cargo_crane, 0.02, SET_CARGO, (3.2, 8.5, 10.0),
		[{"size": [2.4, 1.4, 8.6], "center": [0.0, 4.3, -3.0]}, {"size": [1.4, 8.0, 1.6], "center": [0.0, 8.6, 0.3]}]),
	"lifeboat_davits":         (parts_lifeboat_davits, 0.015, SET_CARGO, (3.6, 1.6, 2.4), None),
	"bollard":                 (parts_bollard, 0.006, SET_CARGO, (0.35, 0.35, 0.55), None),
	"hatch_cover":             (parts_hatch_cover, 0.012, SET_CARGO, (2.6, 2.6, 0.35), None),
	"stairs_ladder":           (parts_stairs_ladder, 0.01, SET_CARGO, (0.9, 2.6, 3.0), None),
	"life_ring":               (parts_life_ring, 0.006, SET_CARGO, (0.75, 0.12, 0.75), None),
	"gangway":                 (parts_gangway, 0.01, SET_CARGO, (1.4, 4.1, 2.7), None),
	# --- cargo ship: fouillis de pont (R2) ---
	"container_open20":       (parts_container_open20, 0.01, SET_CARGO, (2.6, 7.4, 2.7), None),
	"container_stack2":       (parts_container_stack2, 0.01, SET_CARGO, (2.9, 6.5, 5.3), None),
	"container_stack3":       (parts_container_stack3, 0.01, SET_CARGO, (3.15, 6.7, 7.9), None),
	"deck_hatch":             (parts_deck_hatch, 0.012, SET_CARGO, (2.6, 2.6, 0.35), None),
	"lashing_bar":            (parts_lashing_bar, 0.004, SET_CARGO, (0.98, 0.15, 0.35), None),
	"pipe_manifold":          (parts_pipe_manifold, 0.006, SET_CARGO, (1.7, 1.6, 0.75), None),
}


# ---------------------------------------------------------------------------
# Construction / export
# ---------------------------------------------------------------------------

def _new_material(name: str) -> bpy.types.Material:
	mat = bpy.data.materials.new(name)
	color = KIND_COLORS.get(name, (0.6, 0.6, 0.6, 1.0))
	mat.diffuse_color = color
	if mat.node_tree:
		bsdf = mat.node_tree.nodes.get("Principled BSDF")
		if bsdf:
			bsdf.inputs["Base Color"].default_value = color
			bsdf.inputs["Roughness"].default_value = KIND_ROUGHNESS.get(name, 0.7)
			if "Metallic" in bsdf.inputs:
				bsdf.inputs["Metallic"].default_value = KIND_METALLIC.get(name, 0.0)
			if "Alpha" in bsdf.inputs:
				bsdf.inputs["Alpha"].default_value = color[3] if len(color) > 3 else 1.0
	return mat


def build(name: str, parts_fn, bevel_width: float, set_name: str) -> dict:
	_clear_scene()
	bm = bmesh.new()
	parts = parts_fn()

	kinds_used = []
	for p in parts:
		k = p[1]
		assert k in KINDS, f"{name}: unknown kind {k!r}"
		if k not in kinds_used:
			kinds_used.append(k)
	kind_index = {k: i for i, k in enumerate(kinds_used)}

	for p in parts:
		ptype, kind = p[0], p[1]
		if ptype == "box":
			_, _, size, center, rot = p
			faces = add_box(bm, size, center, rot)
		elif ptype == "cyl":
			_, _, r1, r2, depth, center, seg, rot = p
			faces = add_cyl(bm, r1, r2, depth, center, segments=seg, rot=rot)
		elif ptype == "ring":
			_, _, ring_r, tube_r, center, ring_seg, tube_seg, axis, rot = p
			faces = add_ring(bm, ring_r, tube_r, center, ring_segments=ring_seg, tube_segments=tube_seg, axis=axis, rot=rot)
		elif ptype == "strut":
			_, _, p0, p1, thickness = p
			faces = add_strut(bm, p0, p1, thickness)
		elif ptype == "text":
			_, _, text, size, extrude, center, rot = p
			faces = add_text_merge(bm, text, size, extrude, center, rot)
		elif ptype == "lattice":
			_, _, kwargs = p
			faces = add_lattice_tower(bm, **kwargs)
		else:
			raise ValueError(f"unknown part type {ptype!r}")
		for f in faces:
			f.material_index = kind_index[kind]

	# Repère d'auteur (Y-up) -> repère interne Blender (Z-up), corrigé par
	# export_yup=True à l'export (identique à make_weapons.py).
	bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"), verts=list(bm.verts))

	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	obj = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(obj)

	for kind in kinds_used:
		obj.data.materials.append(_new_material(kind))

	if bevel_width > 0:
		mod = obj.modifiers.new("bevel", type="BEVEL")
		mod.width = bevel_width
		mod.segments = 2
		mod.limit_method = "ANGLE"
		mod.angle_limit = math.radians(35)
		bpy.context.view_layer.objects.active = obj
		with bpy.context.temp_override(object=obj):
			bpy.ops.object.modifier_apply(modifier=mod.name)
	obj.data.update()
	for poly in obj.data.polygons:
		poly.use_smooth = False

	out_dir = os.path.join(OUT_ROOT, set_name)
	os.makedirs(out_dir, exist_ok=True)
	out_path = os.path.join(out_dir, f"{name}.glb")
	bpy.ops.object.select_all(action="DESELECT")
	obj.select_set(True)
	bpy.ops.export_scene.gltf(
		filepath=out_path,
		export_format="GLB",
		use_selection=True,
		export_apply=True,
		export_yup=True,
		export_materials="EXPORT",
		export_cameras=False,
		export_lights=False,
		export_animations=False,
	)

	tris = sum(max(0, len(poly.vertices) - 2) for poly in obj.data.polygons)
	dims = tuple(round(v, 3) for v in obj.dimensions)
	print(f"PROP_MODEL_OK {name} tris={tris} dims={dims} slots={kinds_used} -> {out_path}")
	return {"tris": tris, "dims": dims, "slots": kinds_used, "path": out_path}


def main() -> None:
	manifest = []
	for name, (parts_fn, bevel_width, set_name, footprint, collision) in PROPS.items():
		info = build(name, parts_fn, bevel_width, set_name)
		w, d, h = footprint
		manifest.append({
			"name": name,
			"set": set_name,
			"path": f"res://assets/models/props/{set_name}/{name}.glb",
			"footprint": {"w": w, "d": d, "h": h},
			"collision": collision if collision is not None else _bbox_collision(w, d, h),
			"slots": info["slots"],
			"tris": info["tris"],
		})

	manifest_path = os.path.join(OUT_ROOT, "manifest.json")
	os.makedirs(OUT_ROOT, exist_ok=True)
	with open(manifest_path, "w", encoding="utf-8") as f:
		json.dump({"props": manifest}, f, indent=2)
	print(f"PROP_MANIFEST_OK {len(manifest)} props -> {manifest_path}")


if __name__ == "__main__":
	main()
