## make_gloves.py
## Génère fp_gloves.glb : deux gants cartoon FLOTTANTS (pas d'avant-bras,
## façon Rayman) — remplace fp_arms.glb (rig plein corps + squelette) dans le
## viewmodel FPS. Lead call après 3 échecs avec le rig fp_arms squeletté (voir
## scratchpad shots/fp_final/fp_ravage.png : un bras bleu en travers de
## l'écran, arme illisible) : plus de squelette/pose FP_Hold/solveur
## d'orientation main-cible, juste deux gants dont l'ORIGINE est DÉJÀ le point
## de contact avec l'arme — voir scripts/player/ViewModel.gd `_load_gloves`/
## `_attach_gloves`, qui les rattache tels quels (transform identité) à
## l'origine de l'arme (droit) et près de son empty "Foregrip" (gauche, plus
## un petit ajustement de point d'ancrage — voir `_left_glove_anchor` côté
## ViewModel.gd — car "Foregrip" tombe à l'intérieur de la géométrie de
## chaque arme, pas sur sa surface). Pas de solveur d'orientation générique
## comme l'ancien système : les gants n'ont besoin d'aucune rotation/échelle
## calculée, juste d'être posés au bon endroit.
##
## - "GloveR" : droit, refermé autour d'une poignée VERTICALE (silhouette en
##   C : paume + 4 doigts qui s'enroulent vers l'avant/le bas + pouce sur le
##   côté), origine au sommet de la poignée (là où toutes les armes ont leur
##   origine — tools/blender/make_weapons.py, gabarit du bloc "grip").
## - "GloveL" : gauche, en coupe SOUS un garde-main HORIZONTAL (paume vers le
##   haut, 4 doigts qui passent par-dessus, pouce côté corps), origine au
##   point de contact (= l'empty "Foregrip" de l'arme, déjà positionné SOUS
##   l'axe du canon par make_weapons.py — x0.85 sur la hauteur bouche).
## Chunky/biseauté comme make_weapons.py (4 doigts + pouce lisibles, pas de
## sculpt), slots matériau "glove"/"cuff" (recolorés au runtime par
## ViewModel.gd `_apply_glove_materials` : glove = cuir moyen, cuff = couleur
## d'équipe, toujours alliée depuis la vue locale). ≤ 2k tris/gant.
## Origines à leur point de contact respectif : les DEUX gants sont exportés
## comme enfants d'un empty racine "Gloves" (juste pour un export à racine
## unique), mais leur PROPRE transform local est l'identité par rapport à cet
## empty (aucun décalage caché) — Godot les détache ("GloveR"/"GloveL" trouvés
## par nom) et les rattache directement à l'arme, donc seule la géométrie
## compte, pas la hiérarchie d'export.
##
## Lancer : blender --background --python tools/blender/make_gloves.py
## API bpy 5.2 (mêmes helpers que make_weapons.py, vérifiés par sondage là-bas
## déjà) : bmesh.ops.{create_cube,create_cone,scale,rotate,translate}, bevel
## via bpy.ops.object.modifier_apply sous temp_override, export_scene.gltf
## (GLB, export_apply=True, export_yup=True).
##
## A3D-03 (migration stylekit) : `add_box`/`add_cyl` sont importés depuis
## make_weapons.py (copie canonique, plus de duplication byte-à-byte) ; remise
## à zéro de scène, bevel, lissage "hard-surface", normale de contour
## (`_smooth_normal` — corrige le contour fendu aux arêtes vives, lu par
## assets/shaders/ink_outline.gdshader en CUSTOM0) et AO/courbure viennent de
## `tools/blender/lib/toonkit.py` (A3D-02), comme make_weapons.py.
import bpy
import bmesh
import math
import os
import sys
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
import toonkit  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_weapons import add_box, add_cyl  # noqa: E402 -- copie canonique, pas de duplication

GLOVE, CUFF = 0, 1
SLOT_NAMES = ["glove", "cuff"]

# "glove" = cuir moyen (même valeur que FP_GLOVE_COLOR dans
# tools/blender/make_characters.py — l'ancien gant fp_arms, jamais quasi-noir
# une fois ombré de près) ; ViewModel.gd relit cette couleur BAKÉE et la
# réapplique via Cartoon.character_surface("gear", ...), donc la valeur ici
# EST la couleur finale à l'écran. "cuff" est un placeholder neutre (canevas
# recoloré à l'exécution en couleur d'équipe, cf. le slot "cloth" côté
# make_characters.py — même convention).
SLOT_COLORS = {
	GLOVE: (0.42, 0.29, 0.20, 1.0),
	CUFF: (0.55, 0.52, 0.47, 1.0),
}

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
	"assets", "models", "characters")
OUT_NAME = "fp_gloves"


# ---------------------------------------------------------------------------
# Gabarits (mètres, coordonnées GODOT visées — X droite, Y haut, Z avant,
# canon -Z — même convention que make_weapons.py, même correction d'axes
# +90°/X appliquée juste avant export). Origine (0,0,0) = point de contact.
# ---------------------------------------------------------------------------

def _shift(parts: list, offset: tuple) -> list:
	"""Décale chaque `center` de `offset` (garde l'origine (0,0,0) — le point
	d'attache — inchangée ; ne sert qu'à repositionner la géométrie autour
	d'elle)."""
	ox, oy, oz = offset
	out = []
	for kind, size, center, mat_idx, rot in parts:
		cx, cy, cz = center
		out.append((kind, size, (cx + ox, cy + oy, cz + oz), mat_idx, rot))
	return out


## Droit : la poignée verticale des 7 armes (tools/blender/make_weapons.py,
## bloc "grip") fait ~0.075-0.082 de large, ~0.150-0.165 de haut, ~0.070-0.078
## de profond, centrée entre y=-0.070 et y=-0.078. Un gant délibérément un
## peu plus gros que ce gabarit (style "chunky") l'enveloppe entièrement
## quelle que soit l'arme, sans réglage par arme. 4 doigts nettement séparés
## (18 mm d'écart, cran de courbure croissant) + pouce décollé de la paume :
## lisibles même à la distance/résolution du viewmodel (itération render,
## voir tools/fp_shots.gd — la 1ère passe rendait un bloc informe, écarts
## trop fins pour rester visibles une fois ombrés).
##
## Le POINT D'ATTACHE (pas la géométrie ci-dessous, inchangée) est corrigé
## côté ViewModel.gd (`_right_glove_anchor`, tâche FP-02) plutôt qu'ici : le
## repaint Tripo Studio (A3D-20) a changé la convention d'origine des 7 armes
## (mesuré par rendu : l'ancienne hypothèse "origine = sommet de poignée,
## gant pend en Y négatif" ne tient plus partout), mais de façon DIFFÉRENTE
## pour un pistolet (origine proche du bas réel de la poignée) que pour un
## fusil à chargeur externe (origine au bout du chargeur, sous la VRAIE
## poignée) — un simple décalage global ici aurait corrigé l'un en cassant
## l'autre (constaté : un 2e rendu après un décalage +0,12 uniforme ici
## améliorait le Pistolet mais faisait remonter le Ravage dans la zone déjà
## occupée par le gant gauche). Un point d'attache PAR ARME (même
## méthodologie que `weapon_nudge_for`, mesuré au rendu) résout les deux
## sans retoucher cette géométrie.
def parts_glove_r() -> list:
	parts = [
		# Paume : couvre le dos de la poignée (côté +Z, vers le tireur).
		("box", (0.100, 0.150, 0.070), (0.0, -0.078, 0.026), GLOVE, None),
		# 4 doigts enroulés vers l'avant (-Z) et vers le bas, écart croissant
		# de courbure -> silhouette "en escalier" lisible de derrière.
		("box", (0.090, 0.022, 0.060), (0.0, -0.006, -0.052), GLOVE, ("X", -8)),
		("box", (0.090, 0.022, 0.064), (0.0, -0.046, -0.058), GLOVE, ("X", -18)),
		("box", (0.090, 0.022, 0.064), (0.0, -0.086, -0.058), GLOVE, ("X", -28)),
		("box", (0.086, 0.022, 0.058), (0.0, -0.126, -0.050), GLOVE, ("X", -38)),
		# Pouce : côté gauche du gabarit (-X, côté culasse/sûreté), décollé de
		# la paume pour rester lisible comme un doigt à part.
		("box", (0.050, 0.048, 0.098), (-0.070, -0.006, -0.012), GLOVE, ("Z", 18)),
		# Manchette courte, dépasse au-dessus de la poignée (+Y, vers l'avant-
		# bras qui n'existe plus à l'écran) — couleur d'équipe.
		("box", (0.110, 0.085, 0.086), (0.0, 0.048, 0.020), CUFF, None),
	]
	return parts


## Gauche : en coupe sous le garde-main (axe -Z, comme le canon), paume vers
## le haut. L'empty "Foregrip" (make_weapons.py) tombe, sur les 7 armes, à
## l'INTÉRIEUR du bloc "body" (constaté par rendu — le gant gauche
## disparaissait, avalé par la géométrie de l'arme) : ViewModel.gd
## `_attach_gloves` corrige le point d'attache lui-même (interpolation vers
## l'empty "Muzzle", même principe qu'un `lerp` — voir sa doc), donc CE
## fichier n'a plus besoin de décaler sa géométrie pour compenser. Seul un
## petit `_GLOVE_L_SHIFT` vertical reste, pour l'INTENTION du geste ("en
## coupe SOUS le garde-main") plutôt que pour éviter la géométrie de l'arme.
_GLOVE_L_SHIFT = (0.0, -0.020, 0.0)


def parts_glove_l() -> list:
	parts = [
		# Paume : coupe sous le point de contact.
		("box", (0.078, 0.060, 0.120), (0.0, -0.046, 0.0), GLOVE, None),
		# 4 doigts qui passent par-dessus (+Y) et retombent côté loin (+X),
		# espacés le long du garde-main (18 mm d'écart entre boîtes).
		("box", (0.028, 0.088, 0.024), (0.048, 0.012, -0.060), GLOVE, ("Z", -28)),
		("box", (0.028, 0.090, 0.024), (0.050, 0.014, -0.020), GLOVE, ("Z", -30)),
		("box", (0.028, 0.090, 0.024), (0.050, 0.014, 0.020), GLOVE, ("Z", -30)),
		("box", (0.028, 0.086, 0.024), (0.048, 0.010, 0.060), GLOVE, ("Z", -28)),
		# Pouce : côté proche (-X, côté corps du tireur), décollé de la paume.
		("box", (0.056, 0.068, 0.050), (-0.058, 0.002, -0.020), GLOVE, ("Z", 18)),
		# Manchette courte vers l'arrière/le haut (+Z, +Y — vers l'épaule).
		("box", (0.088, 0.088, 0.082), (0.0, 0.020, 0.080), CUFF, None),
	]
	return _shift(parts, _GLOVE_L_SHIFT)


GLOVES = {
	"GloveR": (parts_glove_r, 0.0035),
	"GloveL": (parts_glove_l, 0.0035),
}


def build_glove(name: str, parts_fn, bevel_width: float) -> object:
	bm = bmesh.new()
	for kind, size, center, mat_idx, rot in parts_fn():
		if kind == "box":
			add_box(bm, size, center, mat_idx, rot=rot)
		else:  # "cyl" -> size = (radius, depth, radius2)
			radius, depth, radius2 = size
			add_cyl(bm, radius, depth, center, mat_idx, rot=rot, radius2=radius2)

	# Même correction d'axes que make_weapons.py (voir son commentaire) :
	# +90°/X sur tout le maillage avant l'export Y-up de Blender restitue le
	# repère Godot voulu (authored ci-dessus en X=droite/Y=haut/Z=avant).
	bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, 'X'), verts=list(bm.verts))

	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	obj = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(obj)

	for slot in SLOT_NAMES:
		mat = bpy.data.materials.new(f"{name}_{slot}")
		mat.diffuse_color = SLOT_COLORS[SLOT_NAMES.index(slot)]
		if mat.node_tree:
			bsdf = mat.node_tree.nodes.get("Principled BSDF")
			if bsdf:
				bsdf.inputs["Base Color"].default_value = SLOT_COLORS[SLOT_NAMES.index(slot)]
				bsdf.inputs["Roughness"].default_value = 0.8
		obj.data.materials.append(mat)

	# Bevel appliqué, puis lissage "hard-surface" stylekit (remplace l'ancien
	# `p.use_smooth = False` uniforme) + normale de contour + AO/courbure —
	# voir le commentaire d'en-tête de fichier (A3D-03), identique à
	# make_weapons.py.
	toonkit.add_bevel(obj, width=bevel_width, segments=2, angle_limit_deg=35.0)
	toonkit.weighted_normals(obj)
	toonkit.smooth_normal_attrs(obj)
	toonkit.bake_vertex_ao(obj)
	toonkit.curvature_edge_mask(obj)

	tris = toonkit.tri_count(obj)
	print(f"GLOVE_MODEL_OK {name} tris={tris}")
	return obj


def main() -> None:
	toonkit.reset_scene()
	root = bpy.data.objects.new("Gloves", None)
	root.empty_display_type = 'PLAIN_AXES'
	bpy.context.scene.collection.objects.link(root)

	objs = [root]
	for name, (parts_fn, bevel_width) in GLOVES.items():
		obj = build_glove(name, parts_fn, bevel_width)
		obj.parent = root
		objs.append(obj)
		tris = toonkit.tri_count(obj)
		if tris > 2000:
			raise RuntimeError(f"{name} dépasse le budget de 2000 tris ({tris})")

	os.makedirs(OUT_DIR, exist_ok=True)
	out_path = os.path.join(OUT_DIR, f"{OUT_NAME}.glb")
	bpy.ops.object.select_all(action='DESELECT')
	for o in objs:
		o.select_set(True)
	bpy.ops.export_scene.gltf(
		filepath=out_path,
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
	print(f"GLOVES_MODEL_OK -> {out_path}")


if __name__ == "__main__":
	main()
