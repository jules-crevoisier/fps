## tools/blender/check_asset.py
## Lint d'un asset exporté (.glb/.gltf/.blend) : réimporte une copie en
## mémoire (jamais de réécriture du fichier source) et vérifie tri count vs
## budget (brut ou par classe d'asset §6.6, voir `--asset-class`), dimensions,
## origine, transforms appliqués, échelle plausible, arêtes non-manifold,
## sommets orphelins, pièces déconnectées flottantes (CHK-16, voir
## `--asset-class`/§6.6), normales potentiellement inversées, présence d'UV,
## matériaux (compte + noms vs les "kinds" connus, voir docs/STYLE_BIBLE.md
## §7.9/§6.4), présence et plausibilité du masque vertex COLOR_0 (§7.9 : R=AO,
## G=convexité, B=hauteur, A=zone — voir toonkit.bake_vertex_masks). Sortie
## texte lisible + JSON ; code de sortie 1 sur ÉCHEC DUR uniquement (le
## reste remonte en avertissement — beaucoup de conventions valides
## divergent d'un asset à l'autre, voir docs/3D_PIPELINE.md).
##
##   blender -b -P tools/blender/check_asset.py -- --in PATH
##       [--budget-tris N] [--asset-class CLASSE] [--json OUT.json]
##
## `--asset-class` (voir toonkit.BEVEL_CLASSES pour la liste) lit le budget de
## triangles LOD0 de docs/STYLE_BIBLE.md §6.6 (toonkit.tri_budget_for_class) :
## `--budget-tris` explicite reste prioritaire s'il est fourni en plus.
##
## Échecs DURS (exit 1) : aucun mesh dans le fichier, mesh vide (0 tri),
## budget de triangles dépassé, sommets orphelins présents, arêtes
## non-manifold "dures" (>= 3 faces sur une même arête — presque toujours
## une erreur de modélisation, contrairement à un bord ouvert normal à 1
## face), pièce d'asset déconnectée à plus de 1 cm du corps principal
## (CHK-16). Tout le reste (origine, transforms, UV, noms de matériaux,
## COLOR_0 absent ou suspect, normales) est un AVERTISSEMENT : ce sont des
## conventions qui varient légitimement entre familles d'assets (une arme n'a
## pas son origine au sol, un prop plat n'a pas forcément d'UV, etc.).
import argparse
import json
import math
import os
import sys

import bpy
import bmesh
import mathutils.kdtree
from mathutils import Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
import toonkit  # noqa: E402

# Vocabulaire de noms de matériaux "connus" (docs/STYLE_BIBLE.md §7.9 : slots
# v3 base/accent/metal/glass/sign ; §6.4/Cartoon._PAINTED : kinds peints
# actuels ; scripts/core/Cartoon.gd character_surface ; slots historiques des
# générateurs armes/gants). Un nom hors de cette liste n'est PAS une erreur
# (un asset peut avoir des slots ad hoc), juste signalé pour relecture.
KNOWN_MATERIAL_KINDS = {
	"base", "accent", "metal", "glass", "sign",
	"painted_metal", "rust", "corrugated_metal", "container_paint", "wood_planks",
	"sand_dirt", "cracked_concrete", "asphalt", "ship_deck", "rubber_tire", "dirty_glass",
	"corrugated", "container", "wood", "sand", "concrete", "rubber", "glass",
	"skin", "cloth", "outfit", "gear",
	"body", "grip", "metal", "glove", "cuff", "flat",
}

MIN_PLAUSIBLE_DIM = 0.01   # 1 cm — en dessous, probablement une échelle oubliée (x0.01 sur un mesh en cm)
MAX_PLAUSIBLE_DIM = 60.0   # 60 m — au-dessus, probablement une échelle oubliée (mesh en cm importé tel quel)
ORIGIN_TOLERANCE_M = 0.05

# CHK-16 (docs/STYLE_BIBLE.md §11.2, "bloquant") : "aucune pièce d'asset
# déconnectée à plus de 1 cm de son parent". Le sous-critère "écart entre la
# base d'un prop et le sol ≤ 1 cm" de CHK-16 n'est PAS vérifié ici : il
# suppose une position de placement en niveau (où est "le sol" pour cet
# asset ?) que `check_asset.py` — qui lint un .glb isolé, hors de toute scène
# — n'a aucun moyen de connaître ; c'est la moitié "scan de la scène" de la
# mesure CHK-16 (voir la colonne "Mesure" de la bible), portée par un autre
# outil au niveau carte, pas par ce fichier.
FLOATING_GAP_TOLERANCE_M = 0.01

# Exception §Notes ART-11X (échecs QA ART-11G/ART-11N) : un maillage Tripo
# Smart Mesh comporte des îlots légitimement détachés du corps (bord de
# suroît, verres de lunettes, réservoir dorsal sur Vanne ; collerette,
# basques sur Guet — jusqu'à 0,20 m sondé) qui ne sont PAS une erreur de
# modélisation tant qu'ils sont skinnés RIGIDEMENT (100% de poids sur un seul
# os, voir `rig_tripo_character.py::_rigidify_small_islands`) — un vrai bug
# (poids mélangé qui étire la pièce hors de sa forme en pose) resterait, lui,
# détecté par `_component_rigidly_skinned` ci-dessous. Seule la classe
# `"character"` bénéficie de cette tolérance élargie : les props gardent
# `FLOATING_GAP_TOLERANCE_M` strict (aucune raison légitime pour un prop
# d'avoir une pièce détachée non skinnée).
CHARACTER_FLOATING_GAP_TOLERANCE_M = 0.25

# Poids minimal du groupe dominant, sur CHAQUE sommet d'un îlot, pour le
# considérer "skinné rigidement à un seul os" (voir ci-dessus) — au-delà de
# cette dominance, on tolère l'imprécision numérique résiduelle d'un export/
# réimport glTF (poids quantifiés) sans la confondre avec un vrai mélange de
# deux os (qui, lui, étire la pièce en pose et doit rester un échec dur).
RIGID_SKIN_WEIGHT_THRESHOLD = 0.99

# En dessous de cet écart max-min par canal sur COLOR_0, la couleur de
# sommet est considérée comme une teinte plate (matériau posé à la main sans
# passer par bake_vertex_masks) plutôt qu'un vrai bake — avertissement
# seulement (une teinte plate n'est pas forcément une erreur : un tout petit
# prop provisoire n'a pas toujours besoin du masque complet), voir CHK
# "COLOR_0".
COLOR0_FLAT_SPAN_THRESHOLD = 1e-3


def parse_args():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	p = argparse.ArgumentParser()
	p.add_argument("--in", dest="in_path", required=True)
	p.add_argument("--budget-tris", dest="budget_tris", type=int, default=None)
	p.add_argument("--asset-class", dest="asset_class", default=None,
		help="classe §6.6 (voir toonkit.BEVEL_CLASSES) : fournit le budget de triangles LOD0 "
			"par défaut si --budget-tris est omis")
	p.add_argument("--json", dest="json_path", default=None)
	return p.parse_args(argv)


def import_asset(path: str) -> list:
	ext = os.path.splitext(path)[1].lower()
	if ext in (".glb", ".gltf"):
		bpy.ops.import_scene.gltf(filepath=path)
	elif ext == ".blend":
		bpy.ops.wm.open_mainfile(filepath=path)
	else:
		raise ValueError(f"check_asset: extension non supportée: {ext!r} (attendu .glb/.gltf/.blend)")
	meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
	# §Notes ART-11X : "Icosphere" (+ homonymes numérotés "Icosphere.NNN") est
	# un widget de bone RECRÉÉ PAR L'IMPORTEUR GLTF LUI-MÊME à chaque
	# réimport d'un squelette skinné (sondé : absent du JSON glTF du fichier
	# — vérifié en inspectant directement ses nodes/meshes — donc absent de
	# ce que Godot chargera réellement en jeu ; un artefact PUREMENT propre à
	# CETTE réimportation Blender, jamais du fichier lui-même, cf.
	# `tools/blender/rig_tripo_character.py::_purge_icosphere_widgets`). Sans
	# ce filtre, il polluait tri count/bbox/liste d'objets du rapport pour
	# tout asset avec squelette (ex. dims_m gonflée par la position du widget
	# le long d'un os, sans rapport avec la hauteur réelle du personnage).
	return [o for o in meshes if o.name.split(".")[0] != "Icosphere"]


def _world_bbox(objs):
	corners = []
	for obj in objs:
		corners.extend(obj.matrix_world @ Vector(c) for c in obj.bound_box)
	mins = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
	maxs = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
	return mins, maxs


def _signed_volume(bm: "bmesh.types.BMesh") -> float:
	"""Volume signé (somme de tétraèdres face/origine) — négatif si les
	normales d'une mesh FERMÉE sont globalement inversées. N'a de sens que
	sur un maillage manifold fermé (appelant : vérifier `is_closed` avant)."""
	vol = 0.0
	for f in bm.faces:
		if len(f.verts) < 3:
			continue
		v0 = f.verts[0].co
		for i in range(1, len(f.verts) - 1):
			v1, v2 = f.verts[i].co, f.verts[i + 1].co
			vol += v0.dot(v1.cross(v2)) / 6.0
	return vol


def _component_groups(bm: "bmesh.types.BMesh") -> list:
	"""Composantes connexes du graphe maillage (sommets reliés par au moins
	une arête) — approxime les "pièces" d'un objet composite (plusieurs bouts
	de géométrie fusionnés dans le même objet Blender/glTF, ex. un accessoire
	joint à un prop par `toonkit.join`). Renvoie une liste de listes de
	`BMVert`, triée par taille décroissante (composante `[0]` = corps
	principal, la plus grande — CHK-16 compare chaque autre composante à
	celle-ci). L'appelant doit avoir appelé `bm.verts.ensure_lookup_table()`
	et `bm.verts.index_update()` sur CE bmesh avant (des `.index` à jour sont
	nécessaires ici)."""
	visited = [False] * len(bm.verts)
	groups = []
	for start in bm.verts:
		if visited[start.index]:
			continue
		stack = [start]
		visited[start.index] = True
		comp = []
		while stack:
			v = stack.pop()
			comp.append(v)
			for e in v.link_edges:
				other = e.other_vert(v)
				if not visited[other.index]:
					visited[other.index] = True
					stack.append(other)
		groups.append(comp)
	groups.sort(key=len, reverse=True)
	return groups


def _aabb_from_verts(verts, matrix_world):
	pts = [matrix_world @ v.co for v in verts]
	mins = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
	maxs = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
	return mins, maxs


def _skin_kdtree(me: "bpy.types.Mesh") -> "mathutils.kdtree.KDTree":
	"""Arbre KD sur les positions LOCALES des sommets réels de `me` (même
	repère que les `BMVert.co` d'une copie soudée construite via `bm.from_mesh
	(me)`, cf. `_component_groups`) — sert à retrouver, pour un sommet soudé
	d'un îlot, son (ou l'un de ses) sommet(s) réel(s) d'origine et donc ses
	groupes de poids d'os (la fusion par distance de `bm_welded` ne porte que
	sur la topologie, elle ne transfère aucune donnée de skin)."""
	kd = mathutils.kdtree.KDTree(len(me.vertices))
	for i, v in enumerate(me.vertices):
		kd.insert(v.co, i)
	kd.balance()
	return kd


def _component_rigidly_skinned(comp, me: "bpy.types.Mesh", kd: "mathutils.kdtree.KDTree") -> bool:
	"""True si CHAQUE sommet de l'îlot `comp` (BMVert d'une copie soudée,
	cf. `_component_groups`) retombe, via `kd`, sur un sommet réel skinné à
	100% (à `RIGID_SKIN_WEIGHT_THRESHOLD` près) sur un SEUL groupe de poids —
	l'attache rigide attendue de `rig_tripo_character.py::
	_rigidify_small_islands`. Un maillage sans aucun groupe de sommets (prop
	non skinné passé par erreur en classe "character") échoue systématiquement
	ici (`groups` vide), ce qui est le comportement voulu : pas d'exception
	sans preuve de skin rigide."""
	for v in comp:
		_co, idx, _dist = kd.find(v.co)
		groups = [g for g in me.vertices[idx].groups if g.weight > 1e-4]
		if len(groups) != 1 or groups[0].weight < RIGID_SKIN_WEIGHT_THRESHOLD:
			return False
	return True


def _aabb_gap(mins_a, maxs_a, mins_b, maxs_b) -> float:
	"""Distance heuristique entre deux boîtes englobantes alignées aux axes
	(monde) — 0 si elles se chevauchent ou se touchent sur les 3 axes, sinon
	la norme du vecteur d'écart par axe. Approxime "l'écart entre une pièce
	et le corps principal" (CHK-16) sans distance surface-à-surface exacte
	(coûteuse et inutile pour un lint) — heuristique documentée, dans le même
	esprit que les autres mesures géométriques de ce module (bbox monde,
	origine, dimensions plausibles)."""
	dx = max(mins_a.x - maxs_b.x, mins_b.x - maxs_a.x, 0.0)
	dy = max(mins_a.y - maxs_b.y, mins_b.y - maxs_a.y, 0.0)
	dz = max(mins_a.z - maxs_b.z, mins_b.z - maxs_a.z, 0.0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)


def check_object(obj, asset_class: str = None) -> dict:
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
	bm.verts.ensure_lookup_table()
	bm.edges.ensure_lookup_table()

	loose_verts = sum(1 for v in bm.verts if len(v.link_faces) == 0)

	# Topologie "soudée" : un maillage plat (facettes, `use_smooth=False` —
	# le style par défaut de ce projet, voir make_props.py) ressort du
	# réimport glTF avec ses sommets DÉDOUBLÉS à chaque arête dure/frontière
	# de matériau (glTF exige 1 normale par sommet, l'exportateur duplique
	# donc systématiquement) : compter les bords sur la mesh TELLE QUELLE
	# noierait le lint sous de faux positifs sur presque tout asset facetté
	# du projet. On travaille donc sur une COPIE ressoudée (`remove_doubles`)
	# pour ne garder que les vrais trous/non-manifold topologiques.
	bm_welded = bm.copy()
	bmesh.ops.remove_doubles(bm_welded, verts=bm_welded.verts, dist=1e-4)
	bm_welded.edges.ensure_lookup_table()

	boundary_edges = sum(1 for e in bm_welded.edges if len(e.link_faces) == 1)
	bad_nonmanifold = sum(1 for e in bm_welded.edges if len(e.link_faces) >= 3)
	is_closed = boundary_edges == 0 and len(bm_welded.edges) > 0
	flipped_suspect = False
	if is_closed:
		flipped_suspect = _signed_volume(bm_welded) < 0.0

	# CHK-16 ("aucune pièce d'asset déconnectée à plus de 1 cm de son
	# parent") : sur la même mesh SOUDÉE (sans elle, les sommets dédoublés à
	# chaque arête dure feraient croire à des dizaines de "pièces" pour un
	# simple prop facetté, voir le commentaire ci-dessus sur `bm_welded`).
	bm_welded.verts.index_update()
	bm_welded.verts.ensure_lookup_table()
	components = _component_groups(bm_welded)
	floating_pieces = []
	allowed_rigid_islands = 0
	if len(components) > 1:
		main_mins, main_maxs = _aabb_from_verts(components[0], obj.matrix_world)
		# Construit l'arbre KD une seule fois (coûteux sur un maillage dense),
		# uniquement si une exception "character" est même possible.
		skin_kd = _skin_kdtree(me) if asset_class == "character" else None
		for comp in components[1:]:
			comp_mins, comp_maxs = _aabb_from_verts(comp, obj.matrix_world)
			gap = _aabb_gap(main_mins, main_maxs, comp_mins, comp_maxs)
			if gap <= FLOATING_GAP_TOLERANCE_M:
				continue
			if (asset_class == "character" and gap <= CHARACTER_FLOATING_GAP_TOLERANCE_M
					and _component_rigidly_skinned(comp, me, skin_kd)):
				allowed_rigid_islands += 1
				continue
			floating_pieces.append({"vertex_count": len(comp), "gap_m": round(gap, 4)})
	bm_welded.free()

	scale = tuple(round(s, 4) for s in obj.scale)
	rotation = tuple(round(math.degrees(r), 2) for r in obj.rotation_euler)
	transforms_applied = (scale == (1.0, 1.0, 1.0)) and (max(abs(r) for r in rotation) < 0.01)

	mins, maxs = _world_bbox([obj])
	origin_world = obj.matrix_world.translation
	origin_dx = abs(origin_world.x - (mins.x + maxs.x) / 2.0)
	origin_dy = abs(origin_world.y - (mins.y + maxs.y) / 2.0)
	origin_dz = abs(origin_world.z - mins.z)
	origin_at_bottom_center = (origin_dx < ORIGIN_TOLERANCE_M and origin_dy < ORIGIN_TOLERANCE_M
		and origin_dz < ORIGIN_TOLERANCE_M)

	uv_present = len(me.uv_layers) > 0
	color_attrs = [a.name for a in me.color_attributes]
	tris = toonkit.tri_count(obj)

	# COLOR_0 (§7.9 "masks" RGBA — voir toonkit.bake_vertex_masks) : après un
	# aller-retour glTF, Blender renomme systématiquement le PREMIER attribut
	# de couleur "Color" quel que soit son nom à l'export (vérifié par
	# sondage — un export nommé "masks" ou "AO" ressort identiquement
	# "Color") : c'est donc l'attribut d'INDEX 0, pas son nom, qui identifie
	# COLOR_0 ici. Présence seule = un WARN (voir doc de tête de fichier : un
	# ancien asset A3D-02 en "AO"/"Curvature" séparés est toujours légitime) ;
	# en plus de la présence, on détecte une teinte plate suspecte (aucune
	# variation sur aucun canal — matériau posé à la main, jamais passé par
	# bake_vertex_masks) via l'écart max-min par canal.
	color0_present = len(color_attrs) > 0
	color0_flat_suspect = False
	if color0_present:
		c0 = me.color_attributes[0]
		if c0.domain == 'CORNER' and len(c0.data) > 0:
			channels = list(zip(*(tuple(c.color) for c in c0.data)))
			spans = [max(ch) - min(ch) for ch in channels]
			color0_flat_suspect = max(spans) < COLOR0_FLAT_SPAN_THRESHOLD

	mat_names = [slot.material.name if slot.material else "__none__" for slot in obj.material_slots]
	unknown_mats = [n for n in mat_names if n != "__none__"
		and n.rsplit(".", 1)[0] not in KNOWN_MATERIAL_KINDS and n not in KNOWN_MATERIAL_KINDS]

	bm.free()
	return {
		"name": obj.name,
		"tris": tris,
		"loose_verts": loose_verts,
		"boundary_edges": boundary_edges,
		"bad_nonmanifold_edges": bad_nonmanifold,
		"closed": is_closed,
		"flipped_normals_suspect": flipped_suspect,
		"floating_pieces": floating_pieces,
		"allowed_rigid_islands": allowed_rigid_islands,
		"scale": scale,
		"rotation_deg": rotation,
		"transforms_applied": transforms_applied,
		"origin_at_bottom_center": origin_at_bottom_center,
		"uv_present": uv_present,
		"vertex_color_attributes": color_attrs,
		"color0_present": color0_present,
		"color0_flat_suspect": color0_flat_suspect,
		"material_names": mat_names,
		"unknown_material_names": unknown_mats,
	}


def run(in_path: str, budget_tris, asset_class: str = None) -> dict:
	toonkit.reset_scene()
	mesh_objs = import_asset(in_path)

	# Budget par classe (§6.6, via toonkit.tri_budget_for_class) : ne sert que
	# de VALEUR PAR DÉFAUT — un `--budget-tris` explicite reste prioritaire,
	# pour un appelant qui a une raison ponctuelle de dévier de la classe.
	# Classe inconnue : `tri_budget_for_class` lève `ValueError`, l'appelant
	# de `run()` (voir `main()`) le convertit en échec propre plutôt que de
	# laisser remonter une trace Python brute.
	class_budget = toonkit.tri_budget_for_class(asset_class) if asset_class else None
	effective_budget_tris = budget_tris if budget_tris is not None else (
		class_budget.get("max") if class_budget else None)

	report = {
		"file": in_path,
		"object_count": len(mesh_objs),
		"asset_class": asset_class,
		"class_budget": class_budget,
		"budget_tris": effective_budget_tris,
		"objects": [],
		"warnings": [],
		"failures": [],
	}

	if not mesh_objs:
		report["failures"].append("aucun objet mesh trouvé dans le fichier")
		report["ok"] = False
		return report

	mins, maxs = _world_bbox(mesh_objs)
	dims = maxs - mins
	report["dims_m"] = {"largeur_x": round(dims.x, 4), "hauteur_z": round(dims.z, 4), "profondeur_y": round(dims.y, 4)}
	total_tris = 0

	for obj in mesh_objs:
		info = check_object(obj, asset_class=asset_class)
		report["objects"].append(info)
		total_tris += info["tris"]

		if info["tris"] == 0:
			report["failures"].append(f"{obj.name}: mesh vide (0 triangle)")
		if info["loose_verts"] > 0:
			report["failures"].append(f"{obj.name}: {info['loose_verts']} sommet(s) orphelin(s)")
		if info["bad_nonmanifold_edges"] > 0:
			report["failures"].append(
				f"{obj.name}: {info['bad_nonmanifold_edges']} arête(s) non-manifold (>= 3 faces partagées)")
		for piece in info["floating_pieces"]:
			report["failures"].append(
				f"{obj.name}: pièce déconnectée de {piece['vertex_count']} sommet(s) à "
				f"{piece['gap_m']} m du corps principal (CHK-16 : > {FLOATING_GAP_TOLERANCE_M} m)")
		if info["allowed_rigid_islands"] > 0:
			report["warnings"].append(
				f"{obj.name}: {info['allowed_rigid_islands']} îlot(s) skinné(s) rigidement autorisé(s) "
				f"(classe 'character', <= {CHARACTER_FLOATING_GAP_TOLERANCE_M} m, 100% de poids sur un seul os)")

		if info["boundary_edges"] > 0:
			report["warnings"].append(f"{obj.name}: {info['boundary_edges']} arête(s) de bord ouvert (normal si non-fermé)")
		if info["flipped_normals_suspect"]:
			report["warnings"].append(f"{obj.name}: volume signé négatif — normales potentiellement inversées")
		if not info["transforms_applied"]:
			report["warnings"].append(
				f"{obj.name}: transform non appliqué (scale={info['scale']}, rot={info['rotation_deg']}°)")
		if not info["origin_at_bottom_center"]:
			report["warnings"].append(f"{obj.name}: origine hors du centre-bas de la bbox (peut être volontaire — arme/gant)")
		if not info["uv_present"]:
			report["warnings"].append(f"{obj.name}: aucune UV map")
		if not info["color0_present"]:
			report["warnings"].append(
				f"{obj.name}: aucun COLOR_0 (vertex color) — masque §7.9 (AO/convexité/hauteur/zone) "
				"absent, voir toonkit.bake_vertex_masks")
		elif info["color0_flat_suspect"]:
			report["warnings"].append(
				f"{obj.name}: COLOR_0 présent mais uniforme sur tous ses canaux — "
				"probablement une teinte posée à la main, pas un bake_vertex_masks réel")
		if info["unknown_material_names"]:
			report["warnings"].append(
				f"{obj.name}: nom(s) de matériau hors vocabulaire connu: {info['unknown_material_names']} "
				"(voir docs/STYLE_BIBLE.md §7.9 / docs/3D_PIPELINE.md)")

	report["tris"] = total_tris
	if effective_budget_tris is not None and total_tris > effective_budget_tris:
		report["failures"].append(f"budget de triangles dépassé: {total_tris} > {effective_budget_tris}")
	if class_budget and "min" in class_budget and total_tris < class_budget["min"]:
		report["warnings"].append(
			f"sous le budget minimum de la classe {asset_class!r} (§6.6) : "
			f"{total_tris} < {class_budget['min']} — silhouette peut-être trop simple pour cette famille")

	max_dim = max(dims.x, dims.y, dims.z)
	if max_dim > MAX_PLAUSIBLE_DIM or (0.0 < max_dim < MIN_PLAUSIBLE_DIM):
		report["warnings"].append(
			f"dimension max {max_dim:.3f} m hors de la plage plausible "
			f"[{MIN_PLAUSIBLE_DIM}, {MAX_PLAUSIBLE_DIM}] — échelle (1 unité = 1 m) à vérifier")

	report["ok"] = len(report["failures"]) == 0
	return report


def print_text(report: dict) -> None:
	print(f"CHECK_ASSET {report['file']}")
	classe = f" classe={report['asset_class']!r}" if report.get("asset_class") else ""
	print(f"  objets={report['object_count']} tris={report.get('tris', 0)} budget={report['budget_tris']}{classe}")
	if "dims_m" in report:
		d = report["dims_m"]
		print(f"  dims (m) largeur={d['largeur_x']} hauteur={d['hauteur_z']} profondeur={d['profondeur_y']}")
	for obj in report.get("objects", []):
		print(f"  - {obj['name']}: tris={obj['tris']} uv={obj['uv_present']} "
			f"vcolors={obj['vertex_color_attributes'] or 'aucun'} materiaux={obj['material_names']}")
	if report["warnings"]:
		print("  AVERTISSEMENTS:")
		for w in report["warnings"]:
			print(f"    - {w}")
	if report["failures"]:
		print("  ECHECS:")
		for f in report["failures"]:
			print(f"    - {f}")
	print(f"  RESULTAT: {'OK' if report['ok'] else 'ECHEC'}")


def main() -> None:
	args = parse_args()
	in_path = os.path.abspath(args.in_path)
	if not os.path.isfile(in_path):
		print(f"CHECK_ASSET_FAIL fichier introuvable: {in_path}")
		sys.exit(1)

	try:
		report = run(in_path, args.budget_tris, asset_class=args.asset_class)
	except ValueError as exc:
		# Classe d'asset inconnue (`toonkit.tri_budget_for_class`, voir sa
		# docstring) : erreur d'usage, pas un défaut de l'asset — même
		# traitement que "fichier introuvable" ci-dessus.
		print(f"CHECK_ASSET_FAIL {exc}")
		sys.exit(1)
	print_text(report)

	payload = json.dumps(report, indent=2, ensure_ascii=False)
	if args.json_path:
		out_path = os.path.abspath(args.json_path)
		os.makedirs(os.path.dirname(out_path), exist_ok=True)
		with open(out_path, "w", encoding="utf-8") as f:
			f.write(payload)
		print(f"CHECK_ASSET_JSON_WRITTEN {out_path}")
	else:
		print("CHECK_ASSET_JSON " + payload)

	sys.exit(0 if report["ok"] else 1)


if __name__ == "__main__":
	main()
