## make_backdrops.py
## Génère les maillages "landmark" des coulisses d'horizon (STYLE_BIBLE.md
## SS6.3 "Coulisses (nouveau, obligatoire)", tâche ART-06,
## scripts/levels/Backdrop.gd) : UN glTF binaire par thème de carte --
## désert (derrick), port_cargo (grue portique), city (toit + cheminée),
## mountain (crête à 3 pointes) -- exporté vers
## assets/models/backdrops/<thème>/landmark.glb. Silhouettes SEULEMENT :
## vues à 150-600 m et rendues `unshaded` par Backdrop.gd (jamais peintes en
## triplanaire/toon, jamais vues de près), donc pas de bake AO/courbure ici
## (inutile pour un rendu plat -- ce script ne fabrique que la forme).
##
## Contrat d'échelle avec Backdrop.gd (scripts/levels/Backdrop.gd,
## `landmark_mesh_for_theme`/`landmark_transforms`) : le maillage exporté est
## RÉUTILISÉ TEL QUEL par un seul MultiMesh par carte, une transformation par
## instance qui monte SEULEMENT l'axe Y à l'échelle réelle (mètres) et l'X/Z
## d'une légère gigue de gabarit (0,8 à 1,3) -- donc CE fichier doit livrer
## une géométrie dont :
##   - X/Z sont DÉJÀ à l'échelle finale en mètres (les largeurs/profondeurs
##     de `_LANDMARK_SHAPE` côté Backdrop.gd, reprises ci-dessous dans
##     `THEMES[...]['footprint']`) ;
##   - Y va de 0 (base au sol, SS7.9 "origine = base centrée au sol") à
##     EXACTEMENT 1,0 m -- Backdrop.gd multiplie ensuite cet axe par la
##     hauteur de clôture d'horizon réelle à la position de l'instance
##     (`wall_height_for_radius(rayon) * h_mul`), jamais l'inverse.
## Une forme "amincie" en hauteur ici (1 m de haut sur 6-34 m de large) est
## donc VOULUE et normale à l'aperçu Blender/éditeur brut : elle ne prend sa
## proportion réelle qu'une fois redimensionnée en jeu par Backdrop.gd.
##
## Lancer : blender --background --python tools/blender/make_backdrops.py
##
## Repose sur les mêmes helpers bmesh que le reste du pipeline (voir
## tools/blender/make_weapons.py, tête de fichier, pour le détail de l'API
## bpy 5.2 vérifiée) : `add_box`/`add_cyl` importés de make_weapons.py (même
## convention que make_gloves.py, "copie canonique, pas de duplication"),
## rotation +90°/X finale (Blender Z-up -> export Y-up Godot), bevel léger +
## normales pondérées (toonkit) pour un aperçu propre, export glTF binaire
## par objet/thème (un thème = un fichier, contrairement à make_gloves.py qui
## exporte plusieurs objets sous un empty commun -- ici chaque thème est
## consommé indépendamment par Backdrop.gd, un fichier par thème est donc
## plus simple côté chargement res://).
import bpy
import math
import os
import sys
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
import toonkit  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_weapons import add_box, add_cyl  # noqa: E402 -- copie canonique, pas de duplication

import bmesh  # noqa: E402 -- après les imports de chemin, comme les autres make_*.py

BASE = 0
SLOT_NAMES = ["base"]
# Couleur d'aperçu brute seulement (jamais lue en jeu : Backdrop.gd ignore le
# matériau importé et pose toujours son propre `material_override` unshaded
# teinté par carte -- voir `landmark_mesh_for_theme`/`_load_glb_mesh`, qui
# n'extrait QUE le Mesh, jamais son matériau). Un gris neutre suffit donc à
# l'aperçu Blender/éditeur.
SLOT_COLOR = (0.55, 0.55, 0.55, 1.0)

OUT_ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
	"assets", "models", "backdrops")

# `footprint` (largeur, profondeur, en mètres FINAUX -- doit rester égal à
# `_LANDMARK_SHAPE[thème]["w"/"d"]` côté scripts/levels/Backdrop.gd, sinon la
# gigue de gabarit (0,8-1,3) part d'une base différente de celle documentée
# là-bas) ; `bevel` en mètres, réduit avec la taille de l'objet.
THEMES = {
	"desert": {"footprint": (6.0, 6.0), "bevel": 0.05},
	"port_cargo": {"footprint": (5.0, 20.0), "bevel": 0.05},
	"city": {"footprint": (15.0, 15.0), "bevel": 0.08},
	"mountain": {"footprint": (34.0, 34.0), "bevel": 0.1},
}


## Derrick désertique : tour tronconique (4 pans, base large -> sommet
## étroit, silhouette de derrick pétrolier) + une traverse basse (croisillon
## lisible en silhouette).
def parts_desert(w: float, d: float) -> list:
	r1 = min(w, d) * 0.5
	r2 = r1 * 0.25
	return [
		# `add_cyl` crée son cône le long de son axe LOCAL Z (voir sa
		# docstring dans make_weapons.py) : `rot=("X", -90)` le redresse à la
		# verticale (axe Y, base au sol) AVANT la correction d'axes globale
		# de `build_landmark` -- vérifié par sondage (probe_axis.py, base
		# y=0, sommet y=1.0). Les boîtes n'ont pas besoin de cette rotation
		# (leurs 3 axes sont symétriques avant `scale`, voir `add_box`).
		("cyl", (r1, 1.0, r2), (0.0, 0.5, 0.0), BASE, ("X", -90)),
		("box", (w * 0.8, 0.05, d * 0.1), (0.0, 0.62, 0.0), BASE, None),
	]


## Grue portique / silhouette de coque : deux jambes verticales reliées par
## une longue flèche horizontale -- une forme en portique lisible contre le
## ciel, distincte des masses pleines des autres thèmes.
def parts_port_cargo(w: float, d: float) -> list:
	leg_w = w * 0.5
	leg_d = d * 0.10
	return [
		("box", (leg_w, 0.85, leg_d), (0.0, 0.425, -d * 0.5 + leg_d * 0.5), BASE, None),
		("box", (leg_w, 0.85, leg_d), (0.0, 0.425, d * 0.5 - leg_d * 0.5), BASE, None),
		("box", (leg_w, 0.16, d), (0.0, 0.92, 0.0), BASE, None),
	]


## Bloc de toit + cheminée décentrée -- silhouette urbaine trapue.
def parts_city(w: float, d: float) -> list:
	return [
		("box", (w, 0.6, d), (0.0, 0.3, 0.0), BASE, None),
		("box", (w * 0.14, 0.4, w * 0.14), (w * 0.28, 0.8, d * 0.28), BASE, None),
	]


## Crête à 3 pointes -- silhouette de montagne moins régulière qu'un pic
## unique, plus proche d'une ligne de crête vue de loin.
def parts_mountain(w: float, d: float) -> list:
	# Même redressement d'axe que `parts_desert` (voir son commentaire) ;
	# `radius2=0.0` fait une VRAIE pointe (cône complet), pas un cylindre.
	return [
		("cyl", (w * 0.32, 0.72, 0.0), (-w * 0.28, 0.36, 0.0), BASE, ("X", -90)),
		("cyl", (w * 0.36, 1.0, 0.0), (0.0, 0.5, 0.0), BASE, ("X", -90)),
		("cyl", (w * 0.30, 0.78, 0.0), (w * 0.30, 0.39, 0.0), BASE, ("X", -90)),
	]


PARTS_BY_THEME = {
	"desert": parts_desert,
	"port_cargo": parts_port_cargo,
	"city": parts_city,
	"mountain": parts_mountain,
}


def build_landmark(theme: str, footprint: tuple, bevel_width: float) -> object:
	w, d = footprint
	bm = bmesh.new()
	for kind, size, center, mat_idx, rot in PARTS_BY_THEME[theme](w, d):
		if kind == "box":
			add_box(bm, size, center, mat_idx, rot=rot)
		else:  # "cyl" -> size = (radius, depth, radius2) ; segments=4 : pans plats, silhouette "tour"
			# radius2=0.0 est une VRAIE pointe (cône complet, ex. les crêtes de
			# montagne) -- distinct de radius2=None (add_cyl le retomberait sur
			# `radius`, un cylindre droit), donc jamais interchangés ici.
			radius, depth, radius2 = size
			add_cyl(bm, radius, depth, center, mat_idx, segments=4, rot=rot, radius2=radius2)

	# Même correction d'axes que make_weapons.py/make_gloves.py : le maillage
	# est authoré ci-dessus en repère Godot (Y = haut), +90°/X avant l'export
	# Y-up restitue ce repère depuis le Z-up natif de Blender.
	bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, 'X'), verts=list(bm.verts))

	name = f"landmark_{theme}"
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	obj = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(obj)

	mat = bpy.data.materials.new(f"{name}_{SLOT_NAMES[BASE]}")
	mat.diffuse_color = SLOT_COLOR
	if mat.node_tree:
		bsdf = mat.node_tree.nodes.get("Principled BSDF")
		if bsdf:
			bsdf.inputs["Base Color"].default_value = SLOT_COLOR
			bsdf.inputs["Roughness"].default_value = 0.8
	obj.data.materials.append(mat)

	toonkit.add_bevel(obj, width=bevel_width, segments=2, angle_limit_deg=35.0)
	toonkit.weighted_normals(obj)

	tris = toonkit.tri_count(obj)
	print(f"BACKDROP_LANDMARK_OK {theme} tris={tris}")
	return obj


def export_theme(theme: str, obj: object) -> str:
	out_dir = os.path.join(OUT_ROOT, theme)
	os.makedirs(out_dir, exist_ok=True)
	out_path = os.path.join(out_dir, "landmark.glb")
	bpy.ops.object.select_all(action='DESELECT')
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.export_scene.gltf(
		filepath=out_path,
		export_format='GLB',
		use_selection=True,
		export_apply=True,
		export_yup=True,
		export_materials='EXPORT',
		export_cameras=False,
		export_lights=False,
		export_animations=False,
	)
	return out_path


def main() -> None:
	for theme, cfg in THEMES.items():
		toonkit.reset_scene()
		obj = build_landmark(theme, cfg["footprint"], cfg["bevel"])
		out_path = export_theme(theme, obj)
		print(f"BACKDROP_MODEL_OK {theme} -> {out_path}")
	print("BACKDROPS_ALL_OK")


if __name__ == "__main__":
	main()
