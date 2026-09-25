## tools/blender/weapon_blueprint.py
## FP-11 -- planches de mesure : rend, pour UNE arme donnee (.glb), trois vues
## orthographiques cotees (profil, dessus, face) avec une grille 1 cm calee sur
## l'origine de l'objet et un repere (sphere + etiquette) par Empty present
## dans la scene importee. Ces planches sont l'UNIQUE source de mesure du
## manifeste tools/ai3d/manifests/weapon_rigs.yaml (docs/research/
## 12_viewmodel_v2.md §3.3) : "les valeurs du manifeste se MESURENT sur ces
## plans, jamais devinees" -- un humain (ou un agent avec vision, ici Claude
## via l'outil Read sur l'image produite) lit les coordonnees directement sur
## la grille cotee, comme sur un plan technique papier.
##
##   blender -b --factory-startup --python-exit-code 1 -P tools/blender/weapon_blueprint.py -- \
##       --in assets/models/weapons/_painted_v1/ravage.glb --out reports/checkpoints/2026-09-25_FP-11
##   # planche de DETAIL (une vue, cadre explicite en cm dans les axes de la vue, une cote
##   # par cm) -- le "=" est requis : argparse lirait "-4,..." comme une option :
##   blender ... -P tools/blender/weapon_blueprint.py -- --in <arme.glb> --out <dossier> \
##       --view profile --frame-cm=-4,12,7,18 --tag hammer_cyl --major-every 1
##   # --jpg : ecrit des JPEG (cote max 1600 px) au lieu de PNG -- planches versionnees legeres.
##
## Sur une arme v2 (rig_weapon_parts.py), chaque piece mobile (tout maillage autre que
## "Body") est teintee (magenta, vert acide, orange) : la decoupe se lit sur la planche.
##
## Repere de travail -- IDENTIQUE a fit_weapon_painted.py (voir son en-tete) :
## un .glb deja exporte par ce pipeline (export_yup=True) reimporte ici via
## bpy.ops.import_scene.gltf ressort dans le repere NATIF Z-up de Blender,
## canon +Y, haut +Z, largeur X. Les trois vues (voir `VIEW_AXES`) :
##   - profil : camera cote +X, plan (Y horizontal, canon a droite / Z vertical)
##   - dessus : camera au-dessus (+Z), plan (X horizontal / Y vertical, canon en haut)
##   - face   : camera derriere la crosse (-Y, point de vue du tireur), plan
##              (X horizontal = droite du TIREUR / Z vertical)
## Aucun eclairage : la geometrie et les reperes sont rendus en emission (WYSIWYG
## sans ombre a interpreter), la grille et les etiquettes sont poussees legerement
## devant la silhouette (cote camera) pour rester TOUJOURS visibles, meme a
## travers l'objet -- convention volontaire de plan technique, pas un defaut.
##
## Ce fichier importe bpy/bmesh dans un bloc try/except (meme convention que le
## reste de ce dossier) : les fonctions de projection/grille (section "pures"
## ci-dessous) restent testables par `python -m pytest` sans sous-processus
## Blender -- voir tools/blender/tests/test_rig_weapon_parts.py (suite FP-11
## commune a ce fichier et a rig_weapon_parts.py : mesure/geometrie partagees).
from __future__ import annotations

import argparse
import math
import os
import sys

try:
	import bpy
	import bmesh
	from mathutils import Matrix, Vector
except ImportError:  # pragma: no cover - permet de tester la geometrie hors Blender
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

GRID_STEP_M = 0.01           # grille 1 cm (contrat FP-11)
MAJOR_EVERY = 5              # une etiquette tous les 5 cm (sinon illisible)
GRID_MARGIN_M = 0.04         # marge autour de la bbox, de chaque cote
MIN_HALF_SPAN_M = 0.05       # demi-etendue minimale par axe (objets tres plats)
DEPTH_SAFETY_M = 0.05        # recul supplementaire de la camera derriere la bbox
FRONT_EPSILON_M = 0.002      # grille/reperes pousses de 2 mm devant la silhouette
GRID_LINE_THICKNESS_M = 0.0006
MARKER_RADIUS_M = 0.006
LABEL_SIZE_M = 0.012
TILE_PX = 900
BG_COLOR = (0.035, 0.035, 0.045, 1.0)
SILHOUETTE_FALLBACK = (0.62, 0.63, 0.66, 1.0)
# Lisibilite : l'albedo peint est eclairci vers le blanc de ce facteur (0 = albedo
# brut, 1 = blanc pur). Sans cela, les pieces peintes en acier sombre se confondent
# avec le fond et la silhouette ne se lit plus sur la grille (mesure sur la planche
# v1 du Ravage : carcasse et chargeur illisibles).
ALBEDO_TINT_TO_WHITE = 0.45
# Pieces mobiles (tout maillage autre que "Body", voir rig_weapon_parts.py) :
# teinte d'accent melangee a l'albedo, une par piece, pour que la decoupe se lise
# sur la planche v2 (quelle geometrie part avec le chargeur, la glissiere...).
# Magenta et vert acide d'abord : jamais presents dans la palette peinte des armes (laiton,
# creme, rouge, sarcelle -- bible §5.1), donc jamais confondus avec la texture.
PIECE_TINTS = (
	(0.95, 0.15, 0.75, 1.0),   # magenta
	(0.55, 0.95, 0.10, 1.0),   # vert acide
	(1.00, 0.50, 0.05, 1.0),   # orange
)
PIECE_TINT_FACTOR = 0.7
BODY_OBJECT_NAME = "Body"
GRID_COLOR = (0.30, 0.95, 0.90, 1.0)          # cyan clair -- grille secondaire
ORIGIN_COLOR = (0.98, 0.30, 0.30, 1.0)        # rouge -- lignes d'origine (0,0)
MARKER_COLOR = (1.0, 0.86, 0.20, 1.0)         # jaune -- reperes (empties)
LABEL_COLOR = (0.95, 0.95, 0.92, 1.0)
SHADOW_COLOR = (0.02, 0.02, 0.03, 1.0)       # ombre des etiquettes/reperes (lisibles sur creme)
OVERLAY_STEP_M = 0.0003                       # empilement grille < ombre < etiquette (profondeur)
VIEW_ORDER = ("profile", "top", "front")


# ---------------------------------------------------------------------------
# Fonctions pures -- axes de vue, projection, grille. Aucune dependance bpy :
# testables directement par pytest (voir tools/blender/tests/test_rig_weapon_parts.py).
# ---------------------------------------------------------------------------

def view_axes(view: str) -> dict:
	"""Convention d'axes pour une vue nommee -- voir l'en-tete de ce fichier.
	`u_axis`/`v_axis`/`depth_axis` sont des index (0=X, 1=Y, 2=Z) dans le
	repere de travail Blender natif (X largeur, Y canon, Z hauteur). `u_sign`/
	`v_sign` valent 1 (jamais -1 dans les 3 vues retenues : chaque vue a ete
	choisie pour que l'axe monde positif corresponde deja au sens image
	naturel -- canon a droite en profil, canon en haut en dessus, droite du
	tireur a droite en face). `depth_sign` fixe le cote duquel la camera
	regarde (+1 = camera du cote des valeurs POSITIVES de `depth_axis`, -1 =
	cote negatif) : seule la vue "face" a une camera du cote negatif (derriere
	la crosse, point de vue du tireur, voir l'en-tete)."""
	if view == "profile":
		return {"u_axis": 1, "u_sign": 1.0, "v_axis": 2, "v_sign": 1.0, "depth_axis": 0, "depth_sign": 1.0}
	if view == "top":
		return {"u_axis": 0, "u_sign": 1.0, "v_axis": 1, "v_sign": 1.0, "depth_axis": 2, "depth_sign": 1.0}
	if view == "front":
		return {"u_axis": 0, "u_sign": 1.0, "v_axis": 2, "v_sign": 1.0, "depth_axis": 1, "depth_sign": -1.0}
	raise ValueError(f"weapon_blueprint: vue inconnue {view!r} (attendu profile/top/front)")


def camera_basis_vectors(view: str) -> tuple:
	"""(right, up, back) -- base orthonormee directe (right x up == back) de
	la camera pour `view`, en coordonnees monde (voir `view_axes`). `back` est
	l'oppose de la direction de visee : la camera regarde vers `-back`."""
	axes = view_axes(view)
	right = [0.0, 0.0, 0.0]
	right[axes["u_axis"]] = axes["u_sign"]
	up = [0.0, 0.0, 0.0]
	up[axes["v_axis"]] = axes["v_sign"]
	back = [0.0, 0.0, 0.0]
	back[axes["depth_axis"]] = axes["depth_sign"]
	return tuple(right), tuple(up), tuple(back)


def world_to_uv(point: tuple, view: str) -> tuple:
	"""Projette `point` (x, y, z) monde sur le plan image de `view` -> (u, v),
	en metres, origine au point (0, 0, 0) monde (l'origine de l'objet)."""
	axes = view_axes(view)
	u = point[axes["u_axis"]] * axes["u_sign"]
	v = point[axes["v_axis"]] * axes["v_sign"]
	return (u, v)


def uv_depth_to_world(u: float, v: float, depth: float, view: str) -> tuple:
	"""Inverse de `world_to_uv`, plus `depth` = coordonnee monde SIGNEE
	(pas une distance) le long de `depth_axis`."""
	axes = view_axes(view)
	p = [0.0, 0.0, 0.0]
	p[axes["u_axis"]] = u * axes["u_sign"]
	p[axes["v_axis"]] = v * axes["v_sign"]
	p[axes["depth_axis"]] = depth
	return tuple(p)


def grid_lines(min_v: float, max_v: float, step: float = GRID_STEP_M) -> list:
	"""Coordonnees (multiples de `step`) couvrant au moins [min_v, max_v] --
	toujours au moins une ligne, jamais de doublon, triees. `step` doit etre
	strictement positif."""
	if step <= 0:
		raise ValueError(f"weapon_blueprint: pas de grille invalide ({step})")
	if min_v > max_v:
		min_v, max_v = max_v, min_v
	first = math.floor(min_v / step)
	last = math.ceil(max_v / step)
	return [round(i * step, 6) for i in range(first, last + 1)]


def is_major_line(value: float, step: float = GRID_STEP_M, major_every: int = MAJOR_EVERY) -> bool:
	"""`True` si `value` (une coordonnee de `grid_lines`) tombe sur une ligne
	"majeure" (etiquetee) -- toutes les `major_every` lignes, y compris 0."""
	idx = round(value / step)
	return idx % major_every == 0


def format_cm_label(value_m: float) -> str:
	"""`value_m` (metres, un multiple de 1 cm attendu) -> etiquette signee en
	centimetres ("+5", "-3", "0")."""
	cm = round(value_m * 100.0)
	if cm == 0:
		return "0"
	return f"{cm:+d}"


def ortho_frame(mins: tuple, maxs: tuple, view: str, margin: float = GRID_MARGIN_M,
		min_half_span: float = MIN_HALF_SPAN_M) -> dict:
	"""Cadrage (u, v) de `view` pour couvrir la bbox monde [`mins`, `maxs`] --
	renvoie {"u_min", "u_max", "v_min", "v_max"}, symetrique autour de
	l'origine (0, 0) de la vue si la bbox est plus petite que
	`min_half_span` de ce cote (evite une grille ridiculement serree sur un
	petit prop)."""
	u0, v0 = world_to_uv(mins, view)
	u1, v1 = world_to_uv(maxs, view)
	u_min, u_max = min(u0, u1), max(u0, u1)
	v_min, v_max = min(v0, v1), max(v0, v1)
	u_min = min(u_min - margin, -min_half_span)
	u_max = max(u_max + margin, min_half_span)
	v_min = min(v_min - margin, -min_half_span)
	v_max = max(v_max + margin, min_half_span)
	return {"u_min": u_min, "u_max": u_max, "v_min": v_min, "v_max": v_max}


def render_resolution(span_u: float, span_v: float, size: int, cap_longest: bool) -> tuple:
	"""Resolution (largeur, hauteur) en pixels d'une vue de `span_u` x `span_v` metres :
	largeur `size`, hauteur au meme rapport. Si `cap_longest`, le plus grand cote est
	ramene a `size` (vue de dessus d'un fusil : 1,3 m de haut pour 20 cm de large -- sans
	plafond, 1600 x 7200 px). Leve `ValueError` sur une etendue ou une taille nulle."""
	if span_u <= 0 or span_v <= 0:
		raise ValueError(f"weapon_blueprint: etendue de vue invalide ({span_u}, {span_v})")
	if size <= 0:
		raise ValueError(f"weapon_blueprint: taille invalide ({size})")
	width, height = size, max(1, round(size * span_v / span_u))
	if cap_longest and height > size:
		width, height = max(1, round(size * span_u / span_v)), size
	return width, height


def parse_frame_cm(text: str) -> dict:
	"""Cadrage explicite "u_min,u_max,v_min,v_max" en CENTIMETRES (les unites lues
	sur la planche cotee) -> meme dictionnaire que `ortho_frame`, en metres. Sert
	aux planches de detail (poignee, bouche, puits de chargeur) rendues a haute
	resolution pour lire une cote au millimetre. Leve `ValueError` si le texte
	n'a pas 4 nombres ou si un intervalle est vide."""
	parts = [p.strip() for p in text.split(",")]
	if len(parts) != 4:
		raise ValueError(f"weapon_blueprint: cadrage attendu \"u_min,u_max,v_min,v_max\" (cm), recu {text!r}")
	try:
		u_min, u_max, v_min, v_max = (float(p) / 100.0 for p in parts)
	except ValueError as exc:
		raise ValueError(f"weapon_blueprint: cadrage non numerique {text!r}") from exc
	if u_min >= u_max or v_min >= v_max:
		raise ValueError(f"weapon_blueprint: cadrage vide {text!r} (min doit etre < max)")
	return {"u_min": u_min, "u_max": u_max, "v_min": v_min, "v_max": v_max}


def lerp_color(color: tuple, target: tuple, factor: float) -> tuple:
	"""Melange lineaire RGBA `color` -> `target` (`factor` borne a [0, 1]) --
	alpha toujours opaque (planche technique, jamais de transparence)."""
	f = max(0.0, min(1.0, factor))
	rgb = tuple(c + (t - c) * f for c, t in zip(color[:3], target[:3]))
	return rgb + (1.0,)


def piece_tint(index: int) -> tuple:
	"""Teinte d'accent de la `index`-ieme piece mobile (cyclique sur `PIECE_TINTS`)."""
	if index < 0:
		raise ValueError(f"weapon_blueprint: index de piece negatif ({index})")
	return PIECE_TINTS[index % len(PIECE_TINTS)]


# ---------------------------------------------------------------------------
# Fonctions dependantes de bpy -- jamais appelees hors de Blender.
# ---------------------------------------------------------------------------

def import_asset(path: str) -> list:
	ext = os.path.splitext(path)[1].lower()
	if ext in (".glb", ".gltf"):
		bpy.ops.import_scene.gltf(filepath=path)
	else:
		raise ValueError(f"weapon_blueprint: extension non supportee: {ext!r} (attendu .glb/.gltf)")
	return [o for o in bpy.context.scene.objects if o.type == 'MESH']


def world_bbox(objs: list) -> tuple:
	corners = []
	for obj in objs:
		corners.extend(obj.matrix_world @ Vector(c) for c in obj.bound_box)
	if not corners:
		raise RuntimeError("weapon_blueprint: aucun sommet pour calculer la bbox monde")
	mins = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
	maxs = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
	return mins, maxs


def _find_albedo_image(mat):
	"""Image liee sur la Base Color de `mat`, ou `None` -- meme logique que
	turntable.py::_find_albedo_image (dupliquee ici a dessein, voir l'en-tete
	de ce fichier) : lien direct (sortie de fit_weapon_painted.py::
	keep_painted_material), OU montage "Mix vertex-color x albedo" -- c'est
	CE SECOND CAS que le reimport glTF d'un .glb ecrit par ce meme pipeline
	produit toujours (l'exporteur re-cable systematiquement COLOR_0 x
	baseColorTexture derriere un noeud Mix, verifie par sondage bpy 5.2)."""
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
	if src.type == 'MIX':
		for inp in src.inputs:
			if inp.type == 'RGBA' and inp.is_linked:
				upstream = inp.links[0].from_node
				if upstream.type == 'TEX_IMAGE' and upstream.image is not None:
					return upstream.image
	return None


def _unlit_material(name: str, image, tint: tuple, tint_factor: float):
	"""Materiau Emission : albedo (ou gris neutre) eclairci vers le blanc
	(`ALBEDO_TINT_TO_WHITE`), puis melange a `tint` par `tint_factor` (0 = pas
	de teinte d'accent, cas du corps "Body"). Sans image, la couleur est
	calculee directement (`lerp_color`) ; avec image, le meme melange est cable
	en noeuds Mix (par texel)."""
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	nt = mat.node_tree
	for n in list(nt.nodes):
		nt.nodes.remove(n)
	out = nt.nodes.new("ShaderNodeOutputMaterial")
	em = nt.nodes.new("ShaderNodeEmission")
	nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
	if image is None:
		whitened = lerp_color(SILHOUETTE_FALLBACK, (1.0, 1.0, 1.0, 1.0), ALBEDO_TINT_TO_WHITE)
		em.inputs["Color"].default_value = lerp_color(whitened, tint, tint_factor)
		return mat
	tex = nt.nodes.new("ShaderNodeTexImage")
	tex.image = image
	whiten = nt.nodes.new("ShaderNodeMix")
	whiten.data_type = 'RGBA'
	whiten.inputs["Factor"].default_value = ALBEDO_TINT_TO_WHITE
	whiten.inputs["B"].default_value = (1.0, 1.0, 1.0, 1.0)
	nt.links.new(tex.outputs["Color"], whiten.inputs["A"])
	accent = nt.nodes.new("ShaderNodeMix")
	accent.data_type = 'RGBA'
	accent.inputs["Factor"].default_value = tint_factor
	accent.inputs["B"].default_value = tint
	nt.links.new(whiten.outputs["Result"], accent.inputs["A"])
	nt.links.new(accent.outputs["Result"], em.inputs["Color"])
	return mat


def apply_unlit_preview(mesh_objs: list) -> None:
	"""Remplace chaque materiau par une variante Emission (image d'albedo si
	presente, sinon un gris neutre, eclaircie pour rester lisible sur le fond
	sombre) -- lisible sans eclairage. Chaque piece mobile (tout maillage autre
	que `BODY_OBJECT_NAME`, voir rig_weapon_parts.py) recoit en plus sa propre
	teinte d'accent (`piece_tint`) : la decoupe se lit directement sur la
	planche."""
	cache = {}
	piece_index = 0
	for obj in sorted(mesh_objs, key=lambda o: o.name):
		is_piece = len(mesh_objs) > 1 and obj.name != BODY_OBJECT_NAME
		tint = piece_tint(piece_index) if is_piece else (1.0, 1.0, 1.0, 1.0)
		factor = PIECE_TINT_FACTOR if is_piece else 0.0
		if is_piece:
			piece_index += 1
		for i, slot in enumerate(obj.material_slots):
			original = slot.material
			key = (original.name if original is not None else "__none__", tint, factor)
			if key not in cache:
				cache[key] = _unlit_material(f"{key[0]}_blueprint", _find_albedo_image(original), tint, factor)
			obj.data.materials[i] = cache[key]


def _emission_material(name: str, color: tuple):
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	nt = mat.node_tree
	for n in list(nt.nodes):
		nt.nodes.remove(n)
	out = nt.nodes.new("ShaderNodeOutputMaterial")
	em = nt.nodes.new("ShaderNodeEmission")
	em.inputs["Color"].default_value = color
	nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
	return mat


def _add_flat_quad(name: str, corners: list, mat) -> "bpy.types.Object":
	"""Quad plein (4 coins monde, dans l'ordre) -- utilise pour les lignes de
	grille (rectangles fins) et les etiquettes ne sont PAS ce chemin (police,
	voir `_add_label`)."""
	me = bpy.data.meshes.new(name)
	bm = bmesh.new()
	verts = [bm.verts.new(c) for c in corners]
	bm.faces.new(verts)
	bm.to_mesh(me)
	bm.free()
	obj = bpy.data.objects.new(name, me)
	obj.data.materials.append(mat)
	bpy.context.scene.collection.objects.link(obj)
	return obj


def _add_grid_line(view: str, is_u_line: bool, coord: float, other_min: float, other_max: float,
		depth: float, thickness: float, mat) -> "bpy.types.Object":
	"""Une ligne de grille (rectangle fin) le long de `view`, a `depth` monde
	fixe (voir `uv_depth_to_world`). `is_u_line=True` -> ligne verticale a
	u=`coord` (couvre tout `other_min..other_max` en v) ; sinon ligne
	horizontale a v=`coord`."""
	half = thickness / 2.0
	if is_u_line:
		pts_uv = [(coord - half, other_min), (coord + half, other_min),
			(coord + half, other_max), (coord - half, other_max)]
	else:
		pts_uv = [(other_min, coord - half), (other_max, coord - half),
			(other_max, coord + half), (other_min, coord + half)]
	corners = [uv_depth_to_world(u, v, depth, view) for u, v in pts_uv]
	label = f"grid_{view}_{'u' if is_u_line else 'v'}_{coord:.3f}"
	return _add_flat_quad(label, corners, mat)


def _add_marker(name: str, u: float, v: float, depth: float, view: str, radius: float, mat) -> None:
	bpy.ops.mesh.primitive_ico_sphere_add(radius=radius, subdivisions=2,
		location=uv_depth_to_world(u, v, depth, view))
	obj = bpy.context.active_object
	obj.name = name
	obj.data.materials.append(mat)


def _camera_matrix(view: str, position: tuple) -> "Matrix":
	right, up, back = camera_basis_vectors(view)
	rot = Matrix((Vector(right), Vector(up), Vector(back))).transposed()
	return Matrix.Translation(Vector(position)) @ rot.to_4x4()


def _add_label(text: str, u: float, v: float, depth: float, view: str, size: float, mat,
		align: str = 'CENTER') -> "bpy.types.Object":
	curve = bpy.data.curves.new("blueprint_label", type='FONT')
	curve.body = text
	curve.size = size
	curve.align_x = align
	curve.align_y = 'CENTER'
	curve.extrude = 0.0
	curve.bevel_depth = 0.0
	obj = bpy.data.objects.new("blueprint_label", curve)
	right, up, back = camera_basis_vectors(view)
	rot = Matrix((Vector(right), Vector(up), Vector(back))).transposed()
	obj.matrix_world = Matrix.Translation(Vector(uv_depth_to_world(u, v, depth, view))) @ rot.to_4x4()
	obj.data.materials.append(mat)
	bpy.context.scene.collection.objects.link(obj)
	return obj


def render_view(view: str, mins: Vector, maxs: Vector, out_path: str, size: int = TILE_PX,
		frame: dict | None = None, major_every: int = MAJOR_EVERY, jpeg: bool = False) -> str:
	"""Rend une seule vue orthographique cotee (grille + reperes) de la scene
	COURANTE (mesh deja importe + materiau unlit deja applique, voir
	`apply_unlit_preview`) vers `out_path`. Les empties presents dans la
	scene (Muzzle/Foregrip v1, ou les 6 reperes v2) sont marques. `frame`
	(voir `parse_frame_cm`) remplace le cadrage automatique sur la bbox : planche
	de detail, une etiquette toutes les `major_every` lignes de 1 cm."""
	names_before = {o.name for o in bpy.context.scene.objects}
	if frame is None:
		frame = ortho_frame(tuple(mins), tuple(maxs), view)
	# Taille des etiquettes proportionnelle au cadre (une planche de detail de
	# 10 cm ne doit pas porter des chiffres de 1,2 cm de haut qui masquent la
	# piece mesuree).
	label_size = min(LABEL_SIZE_M, (frame["u_max"] - frame["u_min"]) / 45.0)
	marker_radius = min(MARKER_RADIUS_M, (frame["u_max"] - frame["u_min"]) / 110.0)
	axes = view_axes(view)
	depth_extent = maxs[axes["depth_axis"]] - mins[axes["depth_axis"]]
	center_depth = (maxs[axes["depth_axis"]] + mins[axes["depth_axis"]]) / 2.0
	cam_depth = center_depth + axes["depth_sign"] * (depth_extent / 2.0 + DEPTH_SAFETY_M + 0.4)
	# Depth de premier plan (grille/reperes) : juste devant la face de la bbox
	# la plus proche de la camera, pour rester visible par-dessus la silhouette.
	front_depth = (center_depth + axes["depth_sign"] * (depth_extent / 2.0)) + axes["depth_sign"] * FRONT_EPSILON_M

	u_center = (frame["u_min"] + frame["u_max"]) / 2.0
	v_center = (frame["v_min"] + frame["v_max"]) / 2.0
	cam_pos = uv_depth_to_world(u_center, v_center, cam_depth, view)
	cam_data = bpy.data.cameras.new(f"BlueprintCam_{view}")
	cam_data.type = 'ORTHO'
	span_u = frame["u_max"] - frame["u_min"]
	span_v = frame["v_max"] - frame["v_min"]
	cam_data.sensor_fit = 'HORIZONTAL'
	cam_data.ortho_scale = span_u
	cam_obj = bpy.data.objects.new(f"BlueprintCam_{view}", cam_data)
	cam_obj.matrix_world = _camera_matrix(view, cam_pos)
	bpy.context.scene.collection.objects.link(cam_obj)
	bpy.context.scene.camera = cam_obj

	grid_mat = _emission_material(f"grid_{view}", GRID_COLOR)
	origin_mat = _emission_material(f"origin_{view}", ORIGIN_COLOR)
	label_mat = _emission_material(f"label_{view}", LABEL_COLOR)
	marker_mat = _emission_material(f"marker_{view}", MARKER_COLOR)

	# Etiquettes poussees a l'INTERIEUR du cadre (jamais hors du frustum de la
	# camera ortho, qui s'arrete pile a frame["u/v_min/max"] -- une etiquette
	# posee hors cadre serait simplement invisible sur le rendu).
	for u in grid_lines(frame["u_min"], frame["u_max"]):
		mat = origin_mat if round(u / GRID_STEP_M) == 0 else grid_mat
		_add_grid_line(view, True, u, frame["v_min"], frame["v_max"], front_depth,
			GRID_LINE_THICKNESS_M, mat)
		if is_major_line(u, major_every=major_every):
			_add_label(format_cm_label(u), u, frame["v_min"] + label_size * 1.2, front_depth, view, label_size,
				label_mat)
	for v in grid_lines(frame["v_min"], frame["v_max"]):
		mat = origin_mat if round(v / GRID_STEP_M) == 0 else grid_mat
		_add_grid_line(view, False, v, frame["u_min"], frame["u_max"], front_depth,
			GRID_LINE_THICKNESS_M, mat)
		if is_major_line(v, major_every=major_every):
			_add_label(format_cm_label(v), frame["u_min"] + label_size * 0.3, v, front_depth, view, label_size,
				label_mat, align='LEFT')

	# Reperes : pastille jaune cernee de noir + etiquette doublee d'une ombre decalee, posees
	# DEVANT la grille (sinon illisibles sur les pieces creme ou laiton).
	shadow_mat = _emission_material(f"shadow_{view}", SHADOW_COLOR)
	sign = axes["depth_sign"]
	shadow_depth = front_depth + sign * OVERLAY_STEP_M
	label_depth = front_depth + 2.0 * sign * OVERLAY_STEP_M
	# Taille des reperes proportionnelle au cadre (et non plafonnee comme les cotes) : une
	# planche de fusil d'1,3 m reste lisible une fois reduite dans la planche contact.
	span = frame["u_max"] - frame["u_min"]
	anchor_label = max(label_size, span / 45.0)
	anchor_radius = max(marker_radius, span / 260.0)
	offset = anchor_label * 0.08
	for empty in [o for o in bpy.context.scene.objects if o.type == 'EMPTY']:
		u, v = world_to_uv(tuple(empty.matrix_world.translation), view)
		_add_marker(f"marker_shadow_{view}_{empty.name}", u, v, front_depth - sign * anchor_radius, view,
			anchor_radius * 1.45, shadow_mat)
		_add_marker(f"marker_{view}_{empty.name}", u, v, front_depth, view, anchor_radius, marker_mat)
		_add_label(empty.name, u + offset, v + anchor_label - offset, shadow_depth, view, anchor_label, shadow_mat)
		_add_label(empty.name, u, v + anchor_label, label_depth, view, anchor_label, label_mat)

	scene = bpy.context.scene
	scene.render.engine = 'BLENDER_EEVEE'
	scene.render.resolution_x, scene.render.resolution_y = render_resolution(span_u, span_v, size, jpeg)
	scene.render.film_transparent = False
	if jpeg:
		scene.render.image_settings.file_format = 'JPEG'
		scene.render.image_settings.quality = 88
	else:
		scene.render.image_settings.file_format = 'PNG'
	scene.view_settings.view_transform = 'Standard'
	scene.view_settings.exposure = 0.0
	scene.view_settings.gamma = 1.0
	world = bpy.data.worlds.new(f"BlueprintWorld_{view}")
	world.use_nodes = True
	bg = world.node_tree.nodes.get("Background")
	if bg is not None:
		bg.inputs[0].default_value = BG_COLOR
	scene.world = world
	scene.render.filepath = out_path
	bpy.ops.render.render(write_still=True)
	# Grille/etiquettes/reperes de CETTE vue retires : sinon la vue suivante les
	# verrait par la tranche (plans perpendiculaires a son axe de visee).
	for obj in [o for o in bpy.context.scene.objects if o.name not in names_before]:
		bpy.data.objects.remove(obj, do_unlink=True)
	return out_path


def render_blueprint(in_path: str, out_dir: str, size: int = TILE_PX, views: tuple = VIEW_ORDER,
		frame: dict | None = None, tag: str = "", major_every: int = MAJOR_EVERY, jpeg: bool = False) -> dict:
	"""Rend les vues `views` (par defaut profil/dessus/face) de `in_path` vers
	`out_dir` -- `<stem>_profile.png`, `<stem>_top.png`, `<stem>_front.png`
	(`<stem>_<vue>_<tag>.png` si `tag`, planche de detail cadree par `frame`).
	Renvoie {"paths": {...}, "bbox_min": [...], "bbox_max": [...], "empties": {...}}."""
	stem = os.path.splitext(os.path.basename(in_path))[0]
	os.makedirs(out_dir, exist_ok=True)
	toonkit.reset_scene()
	mesh_objs = import_asset(in_path)
	if not mesh_objs:
		raise RuntimeError(f"weapon_blueprint: aucun mesh dans {in_path}")
	apply_unlit_preview(mesh_objs)
	mins, maxs = world_bbox(mesh_objs)
	empties = {o.name: [round(v, 4) for v in o.matrix_world.translation]
		for o in bpy.context.scene.objects if o.type == 'EMPTY'}

	paths = {}
	for view in views:
		suffix = f"_{tag}" if tag else ""
		path = os.path.join(out_dir, f"{stem}_{view}{suffix}{'.jpg' if jpeg else '.png'}")
		render_view(view, mins, maxs, path, size=size, frame=frame, major_every=major_every, jpeg=jpeg)
		paths[view] = path
	return {
		"paths": paths,
		"bbox_min": [round(v, 4) for v in mins],
		"bbox_max": [round(v, 4) for v in maxs],
		"empties": empties,
	}


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> dict:
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	p = argparse.ArgumentParser()
	p.add_argument("--in", dest="in_path", required=True)
	p.add_argument("--out", dest="out_dir", required=True)
	p.add_argument("--size", dest="size", type=int, default=TILE_PX)
	p.add_argument("--view", dest="views", action="append", choices=VIEW_ORDER, default=None,
		help="vue a rendre (repetable) ; toutes par defaut")
	p.add_argument("--frame-cm", dest="frame_cm", default=None,
		help="planche de detail : \"u_min,u_max,v_min,v_max\" en cm, dans les axes de la vue")
	p.add_argument("--tag", dest="tag", default="", help="suffixe du nom de fichier (planche de detail)")
	p.add_argument("--major-every", dest="major_every", type=int, default=MAJOR_EVERY,
		help="une etiquette toutes les N lignes de 1 cm")
	p.add_argument("--jpg", dest="jpeg", action="store_true",
		help="JPEG (plus grand cote plafonne a --size) au lieu de PNG")
	ns = p.parse_args(argv)
	return vars(ns)


def main() -> None:
	cli = parse_args()
	in_path = os.path.abspath(cli["in_path"])
	if not os.path.isfile(in_path):
		print(f"WEAPON_BLUEPRINT_FAIL fichier introuvable: {in_path}")
		sys.exit(1)
	views = tuple(cli["views"]) if cli["views"] else VIEW_ORDER
	try:
		frame = parse_frame_cm(cli["frame_cm"]) if cli["frame_cm"] else None
		if cli["major_every"] <= 0:
			raise ValueError(f"--major-every doit etre > 0 (recu {cli['major_every']})")
		report = render_blueprint(in_path, os.path.abspath(cli["out_dir"]), size=cli["size"], views=views,
			frame=frame, tag=cli["tag"], major_every=cli["major_every"], jpeg=cli["jpeg"])
	except Exception as exc:  # noqa: BLE001 - message clair, code de sortie 1
		print(f"WEAPON_BLUEPRINT_FAIL {exc}")
		sys.exit(1)
	print(f"WEAPON_BLUEPRINT_OK {os.path.basename(in_path)}")
	for view in views:
		print(report["paths"][view])


if __name__ == "__main__":
	main()
